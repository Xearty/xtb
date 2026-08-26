module xtb.thread.thread;

nothrow @nogc:

import core.attribute : mustuse;
import core.internal.traits : Parameters, ReturnType, Unqual;
import core.lifetime : emplace, forward, move;
import xtb.lifetime : finalize, hasDDestructor,
    lifetimeDeinit = deinit, lifetimeMove = move, needsDeinit,
    needsFinalization;
import xtb.memory : Allocator, deallocate, tryAllocate;
import xtb.panic : panic;
import xtb.result : Result, ResultReturns;
import xtb.types : String;
import xtb.thread.internal.start_latch : StartLatch, startLatchSupported;
import backend = xtb.thread.internal.thread_backend;

/// Portable raw worker callback used by the lowest-level thread API.
alias RawThreadFn = int function(void* context) nothrow @nogc;

/// Portable category for native thread-creation failures.
enum ThreadStartErrorKind : ubyte
{
    unsupported,
    resourceExhausted,
    permissionDenied,
    invalidConfiguration,
    system,
}

/// Recoverable failure to create a native thread.
struct ThreadStartError
{
    ThreadStartErrorKind kind;
    int nativeCode;
}

/// Portable category for allocator-backed thread-start failures.
enum ThreadStartAllocErrorKind : ubyte
{
    allocationFailed,
    threadStartFailed,
}

/// Recoverable failure from an allocator-backed thread start.
///
/// `threadStartError` is meaningful only when `kind == threadStartFailed`.
struct ThreadStartAllocError
{
    ThreadStartAllocErrorKind kind;
    ThreadStartError threadStartError;
}

/// Portable native-thread options shared by all thread creation surfaces.
struct ThreadStartOptions
{
    /// Requested minimum native stack reservation in bytes; zero uses the
    /// platform default.
    size_t stackSize;
}

/// Opaque diagnostic identity for a thread.
///
/// IDs do not own or extend a thread lifetime. `.init` is the invalid sentinel;
/// equality and inequality are the only portable semantic operations.
struct ThreadId
{
    private ulong value_;
}

/// Package-private access to the opaque identity bits for synchronization
/// diagnostics. These bits remain non-portable and must not escape the
/// threading package.
package(xtb) ulong threadIdBits(ThreadId id) pure @safe
{
    return id.value_;
}

/// Portable category for thread-name failures.
enum ThreadNameErrorKind : ubyte
{
    unsupported,
    invalidName,
    tooLong,
    threadUnavailable,
    system,
}

/// Recoverable failure to set a diagnostic native thread name.
struct ThreadNameError
{
    ThreadNameErrorKind kind;
    int nativeCode;
}

private ThreadStartError mapStartError(
    backend.NativeThreadStartErrorKind kind,
    int nativeCode,
) pure @safe
{
    final switch (kind)
    {
        case backend.NativeThreadStartErrorKind.unsupported:
            return ThreadStartError(
                ThreadStartErrorKind.unsupported,
                nativeCode,
            );
        case backend.NativeThreadStartErrorKind.resourceExhausted:
            return ThreadStartError(
                ThreadStartErrorKind.resourceExhausted,
                nativeCode,
            );
        case backend.NativeThreadStartErrorKind.permissionDenied:
            return ThreadStartError(
                ThreadStartErrorKind.permissionDenied,
                nativeCode,
            );
        case backend.NativeThreadStartErrorKind.invalidConfiguration:
            return ThreadStartError(
                ThreadStartErrorKind.invalidConfiguration,
                nativeCode,
            );
        case backend.NativeThreadStartErrorKind.system:
            return ThreadStartError(ThreadStartErrorKind.system, nativeCode);
    }
}

private ThreadNameError mapNameError(
    backend.NativeThreadNameErrorKind kind,
    int nativeCode,
) pure @safe
{
    final switch (kind)
    {
        case backend.NativeThreadNameErrorKind.unsupported:
            return ThreadNameError(ThreadNameErrorKind.unsupported, nativeCode);
        case backend.NativeThreadNameErrorKind.invalidName:
            return ThreadNameError(ThreadNameErrorKind.invalidName, nativeCode);
        case backend.NativeThreadNameErrorKind.tooLong:
            return ThreadNameError(ThreadNameErrorKind.tooLong, nativeCode);
        case backend.NativeThreadNameErrorKind.threadUnavailable:
            return ThreadNameError(
                ThreadNameErrorKind.threadUnavailable,
                nativeCode,
            );
        case backend.NativeThreadNameErrorKind.system:
            return ThreadNameError(ThreadNameErrorKind.system, nativeCode);
    }
}

private bool hasFunctionAttribute(alias function_, string expected)()
{
    static foreach (attribute; __traits(getFunctionAttributes, function_))
        static if (attribute == expected)
            return true;
    return false;
}

private bool parameterHasStorageClass(
    alias function_,
    size_t index,
    string expected,
)()
{
    static foreach (storageClass; __traits(getParameterStorageClasses, function_, index))
        static if (storageClass == expected)
            return true;
    return false;
}

private void validateTypedWorker(alias function_)()
{
    static assert(
        __traits(isStaticFunction, function_),
        "typed Thread start requires a module-level or static function symbol",
    );
    static assert(
        hasFunctionAttribute!(function_, "nothrow"),
        "typed Thread worker must be nothrow",
    );
    static assert(
        hasFunctionAttribute!(function_, "@nogc"),
        "typed Thread worker must be @nogc",
    );

    alias WorkerReturn = ReturnType!function_;
    static assert(
        !hasFunctionAttribute!(function_, "ref"),
        "typed Thread worker must return int or void by value; ref returns are not supported",
    );
    static assert(
        is(WorkerReturn == void) || is(WorkerReturn == int),
        "typed Thread worker must return void or int; use spawn for other result types",
    );

    static foreach (index; 0 .. Parameters!function_.length)
    {
        static assert(
            !parameterHasStorageClass!(function_, index, "ref"),
            "typed Thread start does not accept ref worker parameters",
        );
        static assert(
            !parameterHasStorageClass!(function_, index, "out"),
            "typed Thread start does not accept out worker parameters",
        );
        static assert(
            !parameterHasStorageClass!(function_, index, "lazy"),
            "typed Thread start does not accept lazy worker parameters",
        );
        static assert(
            !parameterHasStorageClass!(function_, index, "in"),
            "typed Thread start deliberately rejects in parameters because their "
                ~ "reference/value semantics depend on the compiler preview mode",
        );
        static assert(
            !is(Parameters!function_[index] == shared SharedBase, SharedBase),
            "typed Thread start does not yet accept top-level shared parameters",
        );
        static assert(
            !is(Parameters!function_[index] == inout InoutBase, InoutBase),
            "typed Thread start does not yet accept top-level inout parameters",
        );
        static if (needsDeinit!(Parameters!function_[index]))
            static assert(
                is(Parameters!function_[index] ==
                    Unqual!(Parameters!function_[index])),
                "explicit-lifetime Thread worker value parameters must be mutable",
            );
    }
}

// The union suppresses automatic destruction of `T`; exactly one capture member
// is manually constructed in explicit start storage and manually finalized on
// either the native-start failure path or the child-consumption path.
private union CaptureSlot(T)
{
    T value;
}

private struct TypedCaptures(alias function_)
{
    alias WorkerParameters = Parameters!function_;

    static foreach (index; 0 .. WorkerParameters.length)
        mixin(
            "CaptureSlot!(Unqual!(WorkerParameters[" ~ index.stringof
                ~ "])) capture" ~ index.stringof ~ ";",
        );
}

private void finalizeTypedValue(T)(ref T value) @system
{
    static if (needsFinalization!T)
        finalize(value);
}

private void finalizeTypedCaptures(alias function_)(
    ref TypedCaptures!function_ captures,
) @system
{
    static foreach_reverse (index; 0 .. Parameters!function_.length)
        finalizeTypedValue(captures.tupleof[index].value);
}

private struct AllocatedTypedStartState(alias function_)
{
    backend.NativeStableStartPacket native;
    Allocator* allocator;
    TypedCaptures!function_ captures;
}

private struct StackTypedStartState(alias function_)
{
    StartLatch captured;
    TypedCaptures!function_ captures;
}

private template decimalIndex(size_t value)
{
    static if (value < 10)
        enum decimalIndex = "0123456789"[value .. value + 1];
    else
        enum decimalIndex = decimalIndex!(value / 10) ~ decimalIndex!(value % 10);
}

private template movedWorkerArgumentList(size_t count)
{
    static if (count == 0)
        enum movedWorkerArgumentList = "";
    else static if (count == 1)
        enum movedWorkerArgumentList = "lifetimeMove(argument0)";
    else
        enum movedWorkerArgumentList = movedWorkerArgumentList!(count - 1)
            ~ ", lifetimeMove(argument" ~ decimalIndex!(count - 1) ~ ")";
}

private int typedAllocatedStartTrampoline(alias function_)(void* opaque) @system
{
    validateTypedWorker!function_();
    alias WorkerParameters = Parameters!function_;
    alias State = AllocatedTypedStartState!function_;

    State* state = cast(State*) opaque;
    Allocator* allocator = state.allocator;

    static foreach (index; 0 .. WorkerParameters.length)
        mixin(
            "Unqual!(WorkerParameters[" ~ decimalIndex!index ~ "]) argument"
                ~ decimalIndex!index ~ " = lifetimeMove(state.captures.tupleof["
                ~ decimalIndex!index ~ "].value);",
        );

    finalizeTypedCaptures!function_(state.captures);

    // Every typed capture now lives in child-local storage. Release the source
    // allocation before entering potentially long-running user code.
    destroy(*state);
    allocator.deallocate(state);

    static if (is(ReturnType!function_ == void))
    {
        mixin("function_(" ~ movedWorkerArgumentList!(WorkerParameters.length) ~ ");");
        return 0;
    }
    else
    {
        mixin("return function_(" ~ movedWorkerArgumentList!(WorkerParameters.length) ~ ");");
    }
}

private int typedStackStartTrampoline(alias function_)(void* opaque) @system
{
    validateTypedWorker!function_();
    alias WorkerParameters = Parameters!function_;
    alias State = StackTypedStartState!function_;

    State* state = cast(State*) opaque;

    static foreach (index; 0 .. WorkerParameters.length)
        mixin(
            "Unqual!(WorkerParameters[" ~ decimalIndex!index ~ "]) argument"
                ~ decimalIndex!index ~ " = lifetimeMove(state.captures.tupleof["
                ~ decimalIndex!index ~ "].value);",
        );

    finalizeTypedCaptures!function_(state.captures);

    // This is the final access to the parent-stack packet. The caller may let
    // that storage disappear as soon as the signal is observed.
    state.captured.signal();

    static if (is(ReturnType!function_ == void))
    {
        mixin("function_(" ~ movedWorkerArgumentList!(WorkerParameters.length) ~ ");");
        return 0;
    }
    else
    {
        mixin("return function_(" ~ movedWorkerArgumentList!(WorkerParameters.length) ~ ");");
    }
}

private struct RawAllocatedStartState
{
    backend.NativeStableStartPacket native;
    Allocator* allocator;
    RawThreadFn function_;
    void* context;
}

private int rawAllocatedStartTrampoline(void* opaque) @system
{
    RawAllocatedStartState* state = cast(RawAllocatedStartState*) opaque;
    Allocator* allocator = state.allocator;
    const function_ = state.function_;
    void* context = state.context;

    destroy(*state);
    allocator.deallocate(state);
    return function_(context);
}

private ThreadStartAllocError allocationStartFailure() pure @safe
{
    return ThreadStartAllocError(
        ThreadStartAllocErrorKind.allocationFailed,
        ThreadStartError.init,
    );
}

private ThreadStartAllocError nativeStartFailure(ThreadStartError error) pure @safe
{
    return ThreadStartAllocError(
        ThreadStartAllocErrorKind.threadStartFailed,
        error,
    );
}

/// Unique owner of a native thread's outstanding join/detach obligation.
///
/// A default, moved-from, joined, or detached `Thread` is empty. Destruction of
/// a still-joinable thread is always a programming error: callers must choose
/// `join` or `detach` explicitly.
@mustuse struct Thread
{
nothrow @nogc:
    @disable this(this);

    private backend.NativeThreadHandle handle_;
    private ThreadId id_;
    private bool joinable_;

    private this(
        backend.NativeThreadHandle handle,
        ThreadId id,
    )
    {
        handle_ = handle;
        id_ = id;
        joinable_ = true;
    }

    ~this() @trusted
    {
        if (joinable_)
            panic("destroyed a joinable Thread without join or detach");
    }

    /// Clears the source after a language/druntime move so the join
    /// obligation has exactly one owner.
    void opPostMove(ref Thread source) pure @safe
    {
        source.clear();
    }

    /// Move-assigns a thread obligation into an empty destination.
    ref Thread opAssign(Thread source) return @trusted
    {
        if (joinable_)
            panic("cannot move-assign over a joinable Thread");

        handle_ = source.handle_;
        id_ = source.id_;
        joinable_ = source.joinable_;
        source.clear();
        return this;
    }

    /// Starts a raw worker with platform-default thread options.
    ///
    /// This allocation-free path may wait after successful native creation only
    /// until the child has consumed the temporary ABI adapter. It never waits
    /// for user worker completion.
    static Result!(Thread, ThreadStartError) startRaw(
        RawThreadFn function_,
        void* context = null,
    ) @system
    {
        mixin ResultReturns;
        return startRawWith(ThreadStartOptions.init, function_, context);
    }

    /// Starts a raw worker with explicit native thread options.
    ///
    /// Like `startRaw`, successful creation may include the short adapter
    /// handoff required to keep the zero-allocation start packet stack-backed.
    static Result!(Thread, ThreadStartError) startRawWith(
        ThreadStartOptions options,
        RawThreadFn function_,
        void* context = null,
    ) @system
    {
        mixin ResultReturns;
        if (function_ is null)
            panic("Thread.startRaw requires a non-null worker function");

        const started = backend.startRaw(
            options.stackSize,
            function_,
            context,
        );
        if (!started.succeeded)
            return err(
                mapStartError(started.kind, started.nativeCode),
            );

        Thread thread = fromNativeStart(started);
        return Result!(Thread, ThreadStartError).okMove(thread);
    }

    /// Starts a typed worker without allocating startup storage.
    ///
    /// Arguments are captured synchronously in the starting thread using the
    /// worker's declared parameter types. Explicit-lifetime owner arguments are
    /// consumed by the call, require an exact parameter type, and become the
    /// worker's cleanup responsibility after successful start. After native
    /// creation, this call waits
    /// only until the child has moved those captures to child-local storage; it
    /// does not wait for user worker completion.
    static Result!(Thread, ThreadStartError) start(
        alias function_,
        Args...,
    )(
        Args arguments,
    ) @system
    {
        mixin ResultReturns;
        return startWith!function_(
            ThreadStartOptions.init,
            forward!arguments,
        );
    }

    /// Starts a typed zero-allocation worker with explicit native options.
    static Result!(Thread, ThreadStartError) startWith(
        alias function_,
        Args...,
    )(
        ThreadStartOptions options,
        Args arguments,
    ) @system
    {
        mixin ResultReturns;
        validateTypedWorker!function_();
        alias WorkerParameters = Parameters!function_;
        alias State = StackTypedStartState!function_;

        static assert(
            Args.length == WorkerParameters.length,
            "typed Thread start argument count must match worker parameter count",
        );

        static foreach (index; 0 .. WorkerParameters.length)
            static if (needsDeinit!(Unqual!(Args[index])) ||
                needsDeinit!(Unqual!(WorkerParameters[index])))
                static assert(
                    is(Unqual!(Args[index]) == Unqual!(WorkerParameters[index])),
                    "explicit-lifetime Thread arguments require an exact worker parameter type",
                );

        State state;
        static foreach (index; 0 .. WorkerParameters.length)
            emplace(
                &state.captures.tupleof[index].value,
                lifetimeMove(arguments[index]),
            );

        static if (!startLatchSupported)
        {
            finalizeTypedCaptures!function_(state.captures);
            return err(
                ThreadStartError(ThreadStartErrorKind.unsupported, 0),
            );
        }
        else
        {
            auto started = startRawWith(
                options,
                &typedStackStartTrampoline!function_,
                &state,
            );
            if (started.isErr)
            {
                finalizeTypedCaptures!function_(state.captures);
                return err(started.unwrapError());
            }

            state.captured.wait();
            return lifetimeMove(started);
        }
    }

    private static Thread fromNativeStart(
        backend.NativeThreadStartResult started,
    ) @trusted
    {
        const rawId = backend.threadIdValue(started.handle);
        if (rawId == 0)
            panic("native backend returned an invalid ThreadId");
        return Thread(started.handle, ThreadId(rawId));
    }

    /// Starts a raw worker using allocator-backed stable startup state.
    ///
    /// Unlike `startRaw`, this returns as soon as native creation succeeds; it
    /// does not wait for the child to consume an adapter packet. The supplied
    /// allocator must remain valid until the child releases that packet and
    /// must permit deallocation from the created thread.
    static Result!(Thread, ThreadStartAllocError) startRawAlloc(
        Allocator* allocator,
        RawThreadFn function_,
        void* context = null,
    ) @system
    {
        mixin ResultReturns;
        return startRawAllocWith(
            ThreadStartOptions.init,
            allocator,
            function_,
            context,
        );
    }

    /// Starts a raw allocator-backed worker with explicit native options.
    static Result!(Thread, ThreadStartAllocError) startRawAllocWith(
        ThreadStartOptions options,
        Allocator* allocator,
        RawThreadFn function_,
        void* context = null,
    ) @system
    {
        mixin ResultReturns;
        if (allocator is null || *allocator is null)
            panic("Thread.startRawAlloc requires a valid allocator");
        if (function_ is null)
            panic("Thread.startRawAlloc requires a non-null worker function");

        RawAllocatedStartState* state = allocator.tryAllocate!RawAllocatedStartState();
        if (state is null)
            return err(allocationStartFailure());

        emplace(state);
        state.allocator = allocator;
        state.function_ = function_;
        state.context = context;
        state.native = backend.NativeStableStartPacket(
            &rawAllocatedStartTrampoline,
            state,
        );

        const started = backend.startStable(options.stackSize, &state.native);
        if (!started.succeeded)
        {
            const error = mapStartError(started.kind, started.nativeCode);
            destroy(*state);
            allocator.deallocate(state);
            return err(nativeStartFailure(error));
        }

        Thread thread = fromNativeStart(started);
        return Result!(Thread, ThreadStartAllocError).okMove(thread);
    }

    /// Starts a typed worker from allocator-backed stable capture storage.
    ///
    /// Argument values are captured in the worker's declared parameter types.
    /// Explicit-lifetime owner arguments are consumed by the call, require an
    /// exact parameter type, and become the worker's cleanup responsibility
    /// after successful start. The child moves them to its own stack, finalizes
    /// the source captures, and
    /// releases the allocation before invoking the worker. The allocator must
    /// remain valid until that child-side release and must support deallocation
    /// from the created thread.
    static Result!(Thread, ThreadStartAllocError) startAlloc(
        alias function_,
        Args...,
    )(
        Allocator* allocator,
        Args arguments,
    ) @system
    {
        mixin ResultReturns;
        return startAllocWith!function_(
            ThreadStartOptions.init,
            allocator,
            forward!arguments,
        );
    }

    /// Starts a typed allocator-backed worker with explicit native options.
    static Result!(Thread, ThreadStartAllocError) startAllocWith(
        alias function_,
        Args...,
    )(
        ThreadStartOptions options,
        Allocator* allocator,
        Args arguments,
    ) @system
    {
        mixin ResultReturns;
        validateTypedWorker!function_();
        alias WorkerParameters = Parameters!function_;
        alias State = AllocatedTypedStartState!function_;

        static assert(
            Args.length == WorkerParameters.length,
            "typed Thread start argument count must match worker parameter count",
        );

        static foreach (index; 0 .. WorkerParameters.length)
            static if (needsDeinit!(Unqual!(Args[index])) ||
                needsDeinit!(Unqual!(WorkerParameters[index])))
                static assert(
                    is(Unqual!(Args[index]) == Unqual!(WorkerParameters[index])),
                    "explicit-lifetime Thread arguments require an exact worker parameter type",
                );

        if (allocator is null || *allocator is null)
            panic("Thread.startAlloc requires a valid allocator");

        State* state = allocator.tryAllocate!State();
        if (state is null)
        {
            static foreach_reverse (index; 0 .. Args.length)
                static if (needsDeinit!(Unqual!(Args[index])))
                    lifetimeDeinit(arguments[index]);
            return err(allocationStartFailure());
        }

        emplace(state);
        state.allocator = allocator;
        state.native = backend.NativeStableStartPacket(
            &typedAllocatedStartTrampoline!function_,
            state,
        );

        static foreach (index; 0 .. WorkerParameters.length)
            emplace(
                &state.captures.tupleof[index].value,
                lifetimeMove(arguments[index]),
            );

        const started = backend.startStable(options.stackSize, &state.native);
        if (!started.succeeded)
        {
            finalizeTypedCaptures!function_(state.captures);
            const error = mapStartError(started.kind, started.nativeCode);
            destroy(*state);
            allocator.deallocate(state);
            return err(nativeStartFailure(error));
        }

        Thread thread = fromNativeStart(started);
        return Result!(Thread, ThreadStartAllocError).okMove(thread);
    }

    /// Whether this handle still owns a join/detach obligation.
    bool joinable() const pure @safe
    {
        return joinable_;
    }

    /// Returns the represented thread identity while this handle is joinable.
    ThreadId id() const @trusted
    {
        if (!joinable_)
            panic("empty Thread has no id");
        return id_;
    }

    /// Sets the represented live thread's diagnostic name.
    Result!(void, ThreadNameError) setName(String name) @trusted
    {
        mixin ResultReturns;
        if (!joinable_)
            panic("cannot name an empty Thread");

        const named = backend.setThreadNameBackend(handle_, name);
        if (!named.succeeded)
            return err(
                mapNameError(named.kind, named.nativeCode),
            );
        return ok();
    }

    /// Waits for completion, consumes the join obligation, and returns status.
    int join() @trusted
    {
        if (!joinable_)
            panic("cannot join an empty Thread");
        if (backend.isCurrentThread(handle_))
            panic("a Thread cannot join itself");

        const joined = backend.joinThread(handle_);
        if (!joined.succeeded)
            panic("native thread join failed");

        const status = joined.status;
        clear();
        return status;
    }

    /// Consumes the join obligation while allowing the worker to continue.
    void detach() @trusted
    {
        if (!joinable_)
            panic("cannot detach an empty Thread");

        const code = backend.detachThread(handle_);
        if (code != 0)
            panic("native thread detach failed");
        clear();
    }

    private void clear() pure @safe
    {
        handle_ = backend.NativeThreadHandle.init;
        id_ = ThreadId.init;
        joinable_ = false;
    }
}

/// Starts a native thread from caller-owned stable packet storage.
///
/// The packet must remain valid until the callback begins. This package-only
/// boundary exists for higher-level threading owners whose own stable state
/// already provides that lifetime.
package(xtb.thread) Result!(Thread, ThreadStartError) startStableThread(
    ThreadStartOptions options,
    backend.NativeStableStartPacket* packet,
) @system
{
    mixin ResultReturns;
    if (packet is null || packet.function_ is null)
        panic("stable thread start requires a valid packet and worker");

    const started = backend.startStable(options.stackSize, packet);
    if (!started.succeeded)
        return err(
            mapStartError(started.kind, started.nativeCode),
        );

    Thread thread = Thread.fromNativeStart(started);
    return Result!(Thread, ThreadStartError).okMove(thread);
}

/// Returns the calling thread's opaque identity, or `.init` on an unsupported
/// backend that cannot provide one.
ThreadId currentThreadId() @trusted
{
    const value = backend.currentThreadIdValue();
    return ThreadId(value);
}

/// Requests a best-effort scheduler yield. This is not a memory fence.
void yieldThread() @trusted
{
    backend.yieldThreadBackend();
}

/// Returns the best available logical-processor concurrency hint, or zero when
/// unavailable.
uint hardwareConcurrency() @trusted
{
    return backend.hardwareConcurrencyBackend();
}

/// Sets the calling native thread's diagnostic name.
Result!(void, ThreadNameError) setCurrentThreadName(String name) @trusted
{
    mixin ResultReturns;
    const named = backend.setCurrentThreadNameBackend(name);
    if (!named.succeeded)
        return err(
            mapNameError(named.kind, named.nativeCode),
        );
    return ok();
}

static assert(!__traits(isCopyable, Thread));
static assert(__traits(isCopyable, ThreadId));
