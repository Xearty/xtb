module xtb.threading.spawn;

nothrow @nogc:

import core.attribute : mustuse;
import core.internal.traits : Parameters, ReturnType, Unqual;
import core.lifetime : emplace, forward, move, moveEmplace;
import xtb.core.memory : Allocator, deallocate, tryAllocate;
import xtb.core.panic : panic;
import xtb.core.result : Result, ResultReturns;
import xtb.threading.thread : Thread,
    ThreadStartError,
    ThreadStartOptions,
    startStableThread;
import backend = xtb.threading.internal.thread_backend;

/// Portable category for failures that occur before a spawned computation is
/// running.
enum SpawnErrorKind : ubyte
{
    allocationFailed,
    threadStartFailed,
}

/// Recoverable failure to allocate spawn state or create its native thread.
///
/// `threadStartError` is meaningful only when `kind == threadStartFailed`.
struct SpawnError
{
    SpawnErrorKind kind;
    ThreadStartError threadStartError;
}

private union SpawnResultSlot(T)
{
    T value;
}

private struct SpawnStateBase(T)
{
    backend.NativeStableStartPacket native;
    Allocator* allocator;
    void* allocation;
    size_t allocationSize;
    size_t allocationAlignment;
    static if (!is(T == void))
    {
        SpawnResultSlot!T result;
        bool resultLive;
    }
}

// Capture slots begin their manual lifetime only after state allocation. On
// native-start failure the spawning thread destroys every slot. On success the
// child moves every slot to its stack and destroys the moved-from values before
// user code runs, leaving only the common base and eventual result live.
private union SpawnCaptureSlot(T)
{
    T value;
}

private struct SpawnCaptures(alias function_)
{
    alias WorkerParameters = Parameters!function_;

    static foreach (index; 0 .. WorkerParameters.length)
        mixin(
            "SpawnCaptureSlot!(Unqual!(WorkerParameters[" ~ index.stringof
                ~ "])) capture" ~ index.stringof ~ ";",
        );
}

private struct SpawnState(alias function_)
{
    alias WorkerReturn = ReturnType!function_;

    SpawnStateBase!WorkerReturn base;
    SpawnCaptures!function_ captures;
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

private void validateSpawnWorker(alias function_)()
{
    static assert(
        __traits(isStaticFunction, function_),
        "spawn requires a module-level or static function symbol",
    );
    static assert(
        hasFunctionAttribute!(function_, "nothrow"),
        "spawn worker must be nothrow",
    );
    static assert(
        hasFunctionAttribute!(function_, "@nogc"),
        "spawn worker must be @nogc",
    );
    static assert(
        !hasFunctionAttribute!(function_, "ref"),
        "spawn worker must return an owned value, not ref",
    );

    static foreach (index; 0 .. Parameters!function_.length)
    {
        static assert(
            !parameterHasStorageClass!(function_, index, "ref"),
            "spawn does not accept ref worker parameters",
        );
        static assert(
            !parameterHasStorageClass!(function_, index, "out"),
            "spawn does not accept out worker parameters",
        );
        static assert(
            !parameterHasStorageClass!(function_, index, "lazy"),
            "spawn does not accept lazy worker parameters",
        );
        static assert(
            !parameterHasStorageClass!(function_, index, "in"),
            "spawn deliberately rejects in parameters because their "
                ~ "reference/value semantics depend on the compiler preview mode",
        );
        static assert(
            !is(Parameters!function_[index] == shared SharedBase, SharedBase),
            "spawn does not yet accept top-level shared parameters",
        );
        static assert(
            !is(Parameters!function_[index] == inout InoutBase, InoutBase),
            "spawn does not yet accept top-level inout parameters",
        );
    }
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
        enum movedWorkerArgumentList = "move(argument0)";
    else
        enum movedWorkerArgumentList = movedWorkerArgumentList!(count - 1)
            ~ ", move(argument" ~ decimalIndex!(count - 1) ~ ")";
}

private void destroySpawnCaptures(alias function_)(
    ref SpawnCaptures!function_ captures,
) @system
{
    static foreach_reverse (index; 0 .. Parameters!function_.length)
        destroy(captures.tupleof[index].value);
}

private int spawnTrampoline(alias function_)(void* opaque) @system
{
    validateSpawnWorker!function_();
    alias WorkerParameters = Parameters!function_;
    alias WorkerReturn = ReturnType!function_;
    alias State = SpawnState!function_;

    State* state = cast(State*) opaque;

    static foreach (index; 0 .. WorkerParameters.length)
        mixin(
            "Unqual!(WorkerParameters[" ~ decimalIndex!index ~ "]) argument"
                ~ decimalIndex!index ~ " = move(state.captures.tupleof["
                ~ decimalIndex!index ~ "].value);",
        );

    destroySpawnCaptures!function_(state.captures);

    static if (is(WorkerReturn == void))
    {
        mixin("function_(" ~ movedWorkerArgumentList!(WorkerParameters.length) ~ ");");
    }
    else
    {
        mixin(
            "WorkerReturn result = function_("
                ~ movedWorkerArgumentList!(WorkerParameters.length) ~ ");",
        );
        moveEmplace(result, state.base.result.value);
        state.base.resultLive = true;
    }
    return 0;
}

private SpawnError allocationFailure() pure @safe
{
    return SpawnError(
        SpawnErrorKind.allocationFailed,
        ThreadStartError.init,
    );
}

private SpawnError threadStartFailure(ThreadStartError error) pure @safe
{
    return SpawnError(SpawnErrorKind.threadStartFailed, error);
}

private void releaseSpawnState(T)(SpawnStateBase!T* state) @system
{
    Allocator* allocator = state.allocator;
    void* allocation = state.allocation;
    const allocationSize = state.allocationSize;
    const allocationAlignment = state.allocationAlignment;

    destroy(*state);
    allocator.deallocate(allocation, allocationSize, allocationAlignment);
}

/// Unique owner of a spawned computation and its stable result storage.
///
/// A default, moved-from, or joined handle is empty. A live handle must be
/// joined explicitly; it cannot be detached.
@mustuse struct JoinHandle(T)
{
nothrow @nogc:
    @disable this(this);

    private Thread thread_;
    private SpawnStateBase!T* state_;

    private this(Thread thread, SpawnStateBase!T* state) @trusted
    {
        thread_ = move(thread);
        state_ = state;
    }

    ~this() @trusted
    {
        if (state_ !is null)
            panic("destroyed a joinable JoinHandle without join");
    }

    /// Move-assigns a computation obligation into an empty destination.
    ref JoinHandle opAssign(JoinHandle source) return @trusted
    {
        if (state_ !is null)
            panic("cannot move-assign over a joinable JoinHandle");

        thread_ = move(source.thread_);
        state_ = source.state_;
        source.state_ = null;
        return this;
    }

    /// Whether this handle still owns a join and result obligation.
    bool joinable() const pure @safe
    {
        return state_ !is null;
    }

    static if (is(T == void))
    {
        /// Waits for completion, consumes the handle, and releases its state.
        void join() @trusted
        {
            if (state_ is null)
                panic("cannot join an empty JoinHandle");

            const status = thread_.join();
            if (status != 0)
                panic("spawn trampoline returned a nonzero status");

            SpawnStateBase!T* state = state_;
            state_ = null;
            releaseSpawnState(state);
        }
    }
    else
    {
        /// Waits for completion, consumes the handle, and returns its result.
        T join() @trusted
        {
            if (state_ is null)
                panic("cannot join an empty JoinHandle");

            const status = thread_.join();
            if (status != 0)
                panic("spawn trampoline returned a nonzero status");
            if (!state_.resultLive)
                panic("spawn worker completed without publishing a result");

            T result = void;
            moveEmplace(state_.result.value, result);
            destroy(state_.result.value);
            state_.resultLive = false;

            SpawnStateBase!T* state = state_;
            state_ = null;
            releaseSpawnState(state);
            return result;
        }
    }
}

/// Starts a typed concurrent computation with default native-thread options.
///
/// Arguments are captured by value in the worker's declared parameter types.
/// The returned handle owns the single state allocation until `join`. The
/// allocator object must therefore remain valid through `join` and must permit
/// deallocation on any thread to which the handle is moved. Pointer, slice, and
/// other reference-bearing argument/result values remain shallow and do not
/// extend the lifetime of referenced storage.
Result!(JoinHandle!(ReturnType!function_), SpawnError) spawn(
    alias function_,
    Args...,
)(
    Allocator* allocator,
    Args arguments,
) @system
{
    mixin ResultReturns;
    return spawnWith!function_(
        ThreadStartOptions.init,
        allocator,
        forward!arguments,
    );
}

/// Starts a typed concurrent computation with explicit native-thread options.
///
/// This has the same ownership and allocator requirements as `spawn` and
/// applies `options` to the created native thread.
Result!(JoinHandle!(ReturnType!function_), SpawnError) spawnWith(
    alias function_,
    Args...,
)(
    ThreadStartOptions options,
    Allocator* allocator,
    Args arguments,
) @system
{
    mixin ResultReturns;
    validateSpawnWorker!function_();
    alias WorkerParameters = Parameters!function_;
    alias WorkerReturn = ReturnType!function_;
    alias State = SpawnState!function_;

    static assert(
        Args.length == WorkerParameters.length,
        "spawn argument count must match worker parameter count",
    );
    static assert(State.base.offsetof == 0,
        "SpawnStateBase must begin at the allocation address");

    if (allocator is null || *allocator is null)
        panic("spawn requires a valid allocator");

    State* state = allocator.tryAllocate!State();
    if (state is null)
        return err(allocationFailure());

    state.base.allocator = allocator;
    state.base.allocation = state;
    state.base.allocationSize = State.sizeof;
    state.base.allocationAlignment = State.alignof;
    state.base.native = backend.NativeStableStartPacket(
        &spawnTrampoline!function_,
        state,
    );
    static if (!is(WorkerReturn == void))
        state.base.resultLive = false;

    static foreach (index; 0 .. WorkerParameters.length)
        emplace(
            &state.captures.tupleof[index].value,
            move(arguments[index]),
        );

    auto started = startStableThread(options, &state.base.native);
    if (started.isErr)
    {
        destroySpawnCaptures!function_(state.captures);
        const error = started.unwrapError();
        allocator.deallocate(state);
        return err(threadStartFailure(error));
    }

    Thread thread = started.unwrap();
    JoinHandle!WorkerReturn handle = JoinHandle!WorkerReturn(
        move(thread),
        &state.base,
    );
    return ok(move(handle));
}

static assert(!__traits(isCopyable, JoinHandle!int));
static assert(!__traits(isCopyable, JoinHandle!void));

version (unittest)
{
    private int addSpawnedValues(int left, int right) nothrow @nogc
    {
        return left + right;
    }

    private void publishSpawnedVoid(int* value) nothrow @nogc
    {
        *value = 42;
    }

    private struct SpawnedPair
    {
        int left;
        int right;
    }

    private SpawnedPair makeSpawnedPair(int value) nothrow @nogc
    {
        return SpawnedPair(value, value + 1);
    }
}

unittest
{
    version (linux)
    {
        version (XTB_TestUnsupportedThreadBackend)
        {
        }
        else
        {
            import xtb.core.allocators.malloc : mallocAllocator;

            auto scalarStarted = spawn!addSpawnedValues(
                mallocAllocator(),
                19,
                23,
            );
            assert(scalarStarted.isOk);
            JoinHandle!int scalar = scalarStarted.unwrap();
            assert(scalar.joinable());
            assert(scalar.join() == 42);
            assert(!scalar.joinable());

            int published;
            auto voidStarted = spawn!publishSpawnedVoid(
                mallocAllocator(),
                &published,
            );
            assert(voidStarted.isOk);
            JoinHandle!void voidHandle = voidStarted.unwrap();
            voidHandle.join();
            assert(published == 42);

            auto aggregateStarted = spawn!makeSpawnedPair(
                mallocAllocator(),
                7,
            );
            assert(aggregateStarted.isOk);
            JoinHandle!SpawnedPair aggregate = aggregateStarted.unwrap();
            const pair = aggregate.join();
            assert(pair == SpawnedPair(7, 8));
        }
    }
}
