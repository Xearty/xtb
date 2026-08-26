module xtb.thread.thread_scope;

nothrow @nogc:

import core.internal.traits : Parameters, ReturnType, Unqual;
import core.lifetime : emplace, forward, move;
import xtb.containers.intrusive_list : ForwardListHook, IntrusiveForwardList;
import xtb.lifetime : finalize, hasDDestructor,
    lifetimeDeinit = deinit, lifetimeMove = move, needsDeinit,
    needsFinalization;
import xtb.memory : Allocator, deallocate, tryAllocate;
import xtb.panic : panic;
import xtb.result : Result, ResultReturns;
import xtb.thread.spawn : SpawnError, SpawnErrorKind;
import xtb.thread.thread : Thread,
    ThreadId,
    ThreadStartError,
    ThreadStartOptions,
    currentThreadId,
    startStableThread;
import backend = xtb.thread.internal.thread_backend;

private struct ScopedChildHeader
{
    backend.NativeStableStartPacket native;
    Thread thread;
    ForwardListHook!ScopedChildHeader forwardListHook;
    void* allocation;
    size_t allocationSize;
    size_t allocationAlignment;
}

private union ScopedOwnedSlot(T)
{
    T value;
}

private struct ScopedCapture(T, bool byReference)
{
    static if (byReference)
        T* reference;
    else
        ScopedOwnedSlot!(Unqual!T) owned;
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

private template parameterIsRef(alias function_, size_t index)
{
    enum parameterIsRef = parameterHasStorageClass!(function_, index, "ref");
}

private struct ScopedCaptures(alias function_)
{
    alias WorkerParameters = Parameters!function_;

    static foreach (index; 0 .. WorkerParameters.length)
        mixin(
            "ScopedCapture!(WorkerParameters[" ~ index.stringof
                ~ "], parameterIsRef!(function_, " ~ index.stringof
                ~ ")) capture" ~ index.stringof ~ ";",
        );
}

private struct ScopedChildNode(alias function_)
{
    ScopedChildHeader header;
    ScopedCaptures!function_ captures;
}

private void validateScopedWorker(alias function_)()
{
    static assert(
        __traits(isStaticFunction, function_),
        "ThreadScope.spawn requires a module-level or static function symbol",
    );
    static assert(
        hasFunctionAttribute!(function_, "nothrow"),
        "ThreadScope worker must be nothrow",
    );
    static assert(
        hasFunctionAttribute!(function_, "@nogc"),
        "ThreadScope worker must be @nogc",
    );
    static assert(
        is(ReturnType!function_ == void),
        "ThreadScope worker must return void; use top-level spawn for results",
    );

    static foreach (index; 0 .. Parameters!function_.length)
    {
        static assert(
            !parameterHasStorageClass!(function_, index, "out"),
            "ThreadScope worker does not accept out parameters",
        );
        static assert(
            !parameterHasStorageClass!(function_, index, "lazy"),
            "ThreadScope worker does not accept lazy parameters",
        );
        static assert(
            !parameterHasStorageClass!(function_, index, "in"),
            "ThreadScope worker deliberately rejects preview-sensitive in parameters",
        );
        static if (!parameterIsRef!(function_, index))
        {
            static assert(
                !is(Parameters!function_[index] == shared SharedBase, SharedBase),
                "ThreadScope worker does not yet accept top-level shared value parameters",
            );
            static assert(
                !is(Parameters!function_[index] == inout InoutBase, InoutBase),
                "ThreadScope worker does not yet accept top-level inout value parameters",
            );
            static if (needsDeinit!(Parameters!function_[index]))
                static assert(
                    is(Parameters!function_[index] ==
                        Unqual!(Parameters!function_[index])),
                    "explicit-lifetime ThreadScope value parameters must be mutable",
                );
        }
    }
}

private template decimalIndex(size_t value)
{
    static if (value < 10)
        enum decimalIndex = "0123456789"[value .. value + 1];
    else
        enum decimalIndex = decimalIndex!(value / 10) ~ decimalIndex!(value % 10);
}

private template scopedWorkerArgument(alias function_, size_t index)
{
    static if (parameterIsRef!(function_, index))
        enum scopedWorkerArgument = "*argument" ~ decimalIndex!index;
    else
        enum scopedWorkerArgument = "lifetimeMove(argument" ~ decimalIndex!index ~ ")";
}

private template scopedWorkerArgumentList(alias function_, size_t count)
{
    static if (count == 0)
        enum scopedWorkerArgumentList = "";
    else static if (count == 1)
        enum scopedWorkerArgumentList = scopedWorkerArgument!(function_, 0);
    else
        enum scopedWorkerArgumentList = scopedWorkerArgumentList!(
                function_,
                count - 1,
            ) ~ ", " ~ scopedWorkerArgument!(function_, count - 1);
}

private void finalizeScopedValue(T)(ref T value) @system
{
    static if (needsFinalization!T)
        finalize(value);
}

private void finalizeOwnedScopedCaptures(alias function_)(
    ref ScopedCaptures!function_ captures,
) @system
{
    static foreach_reverse (index; 0 .. Parameters!function_.length)
        static if (!parameterIsRef!(function_, index))
            finalizeScopedValue(captures.tupleof[index].owned.value);
}

private int scopedChildTrampoline(alias function_)(void* opaque) @system
{
    validateScopedWorker!function_();
    alias WorkerParameters = Parameters!function_;
    alias Node = ScopedChildNode!function_;

    Node* node = cast(Node*) opaque;

    static foreach (index; 0 .. WorkerParameters.length)
    {
        static if (parameterIsRef!(function_, index))
            mixin(
                "WorkerParameters[" ~ decimalIndex!index ~ "]* argument"
                    ~ decimalIndex!index ~ " = node.captures.tupleof["
                    ~ decimalIndex!index ~ "].reference;",
            );
        else
            mixin(
                "Unqual!(WorkerParameters[" ~ decimalIndex!index
                    ~ "]) argument" ~ decimalIndex!index
                    ~ " = lifetimeMove(node.captures.tupleof[" ~ decimalIndex!index
                    ~ "].owned.value);",
            );
    }

    finalizeOwnedScopedCaptures!function_(node.captures);
    mixin(
        "function_(" ~ scopedWorkerArgumentList!(
            function_,
            WorkerParameters.length,
    ) ~ ");",
    );
    return 0;
}

private SpawnError scopeAllocationFailure() pure @safe
{
    return SpawnError(
        SpawnErrorKind.allocationFailed,
        ThreadStartError.init,
    );
}

private SpawnError scopeThreadStartFailure(ThreadStartError error) pure @safe
{
    return SpawnError(SpawnErrorKind.threadStartFailed, error);
}

/// Lexically bounded owner of scoped child threads.
///
/// Meaningful instances are created only by `threadScope`. `ThreadScope.init`
/// is inert, and spawning through it is a programming error. The capability is
/// non-copyable and may be used only by the thread executing the scope body.
struct ThreadScope
{
nothrow @nogc:
    @disable this(this);

    private Allocator* allocator_;
    private ThreadId owner_;
    private IntrusiveForwardList!ScopedChildHeader children_;

    private this(Allocator* allocator) @trusted
    {
        allocator_ = allocator;
        owner_ = currentThreadId();
    }

    ~this() @trusted
    {
        if (allocator_ !is null)
            panic("ThreadScope escaped its structured boundary");
    }

    /// Starts a scoped `void` worker with default native-thread options.
    ///
    /// `ref` worker arguments borrow addressable caller-owned values whose
    /// lifetimes must enclose the complete outer `threadScope` call. Other
    /// arguments are captured by value in the allocated child node. Explicit-
    /// lifetime owner values must be moved into the scope, require an exact
    /// worker parameter type, and become the worker's cleanup responsibility.
    Result!(void, SpawnError) spawn(alias function_, Args...)(
        auto ref Args arguments,
    ) @system
    {
        mixin ResultReturns;
        return spawnWith!function_(
            ThreadStartOptions.init,
            forward!arguments,
        );
    }

    /// Starts a scoped `void` worker with explicit native-thread options.
    Result!(void, SpawnError) spawnWith(alias function_, Args...)(
        ThreadStartOptions options,
        auto ref Args arguments,
    ) @system
    {
        mixin ResultReturns;
        validateScopedWorker!function_();
        alias WorkerParameters = Parameters!function_;
        alias Node = ScopedChildNode!function_;

        static assert(
            Args.length == WorkerParameters.length,
            "ThreadScope.spawn argument count must match worker parameter count",
        );

        static foreach (index; 0 .. WorkerParameters.length)
            static if (!parameterIsRef!(function_, index) &&
                (needsDeinit!(Unqual!(Args[index])) ||
                    needsDeinit!(Unqual!(WorkerParameters[index]))))
                {
                static assert(
                    is(Unqual!(Args[index]) == Unqual!(WorkerParameters[index])),
                    "explicit-lifetime ThreadScope arguments require an exact worker parameter type",
                );
                static assert(
                    !__traits(isRef, arguments[index]),
                    "explicit-lifetime ThreadScope value arguments must be moved into the scope",
                );
            }
        static assert(Node.header.offsetof == 0,
            "ScopedChildHeader must begin at the allocation address");

        if (allocator_ is null || *allocator_ is null)
            panic("cannot spawn through an inert ThreadScope");
        if (currentThreadId() != owner_)
            panic("ThreadScope may only be used by its owning thread");

        Node* node = allocator_.tryAllocate!Node();
        if (node is null)
        {
            static foreach_reverse (index; 0 .. Args.length)
                static if (!parameterIsRef!(function_, index) &&
                    !__traits(isRef, arguments[index]) &&
                    needsDeinit!(Unqual!(Args[index])))
                    lifetimeDeinit(arguments[index]);
            return err(scopeAllocationFailure());
        }

        emplace(node);
        node.header.allocation = node;
        node.header.allocationSize = Node.sizeof;
        node.header.allocationAlignment = Node.alignof;
        node.header.native = backend.NativeStableStartPacket(
            &scopedChildTrampoline!function_,
            node,
        );

        static foreach (index; 0 .. WorkerParameters.length)
        {
            static if (parameterIsRef!(function_, index))
            {
                static assert(
                    __traits(isRef, arguments[index]),
                    "ThreadScope ref worker arguments require addressable lvalues",
                );
                node.captures.tupleof[index].reference = &arguments[index];
            }
            else static if (needsDeinit!(Unqual!(WorkerParameters[index])))
                emplace(
                    &node.captures.tupleof[index].owned.value,
                    lifetimeMove(arguments[index]),
                );
            else
                emplace(
                    &node.captures.tupleof[index].owned.value,
                    forward!(arguments[index]),
                );
        }

        auto started = startStableThread(options, &node.header.native);
        if (started.isErr)
        {
            finalizeOwnedScopedCaptures!function_(node.captures);
            const error = started.unwrapError();
            destroy(*node);
            allocator_.deallocate(node);
            return err(scopeThreadStartFailure(error));
        }

        node.header.thread = started.unwrap();
        children_.pushFront(&node.header);
        return ok();
    }

    private void finish() @trusted
    {
        while (!children_.empty)
        {
            ScopedChildHeader* child = children_.popFront();
            const status = child.thread.join();
            if (status != 0)
                panic("scoped child trampoline returned a nonzero status");

            void* allocation = child.allocation;
            const allocationSize = child.allocationSize;
            const allocationAlignment = child.allocationAlignment;
            destroy(*child);
            allocator_.deallocate(
                allocation,
                allocationSize,
                allocationAlignment,
            );
        }

        allocator_ = null;
        owner_ = ThreadId.init;
    }
}

private void validateScopeBody(alias body, Context, bool hasContext)()
{
    static assert(
        __traits(isStaticFunction, body),
        "threadScope body must be a module-level or static function",
    );
    static assert(
        hasFunctionAttribute!(body, "nothrow"),
        "threadScope body must be nothrow",
    );
    static assert(
        hasFunctionAttribute!(body, "@nogc"),
        "threadScope body must be @nogc",
    );
    static assert(
        is(ReturnType!body == void),
        "threadScope body must return void",
    );
    enum expectedParameters = hasContext ? 2 : 1;
    static assert(
        Parameters!body.length == expectedParameters,
        "threadScope body has the wrong parameter count",
    );
    static if (Parameters!body.length >= 1)
    {
        static assert(
            is(Parameters!body[0] == ThreadScope),
            "threadScope body first parameter must be ThreadScope",
        );
        static assert(
            parameterHasStorageClass!(body, 0, "ref") &&
                parameterHasStorageClass!(body, 0, "scope"),
            "threadScope body first parameter must be scope ref ThreadScope",
        );
    }
    static if (hasContext && Parameters!body.length >= 2)
    {
        static assert(
            is(Parameters!body[1] == Context*),
            "threadScope body context parameter must match the supplied pointer",
        );
        static assert(
            parameterHasStorageClass!(body, 1, "scope"),
            "threadScope body context pointer must be scope",
        );
    }
}

/// Runs a context-free structured scope and joins every successful child.
///
/// The static body signature is `void body(scope ref ThreadScope)`.
void threadScope(alias body)(Allocator* allocator) @system
{
    validateScopeBody!(body, void, false)();
    if (allocator is null || *allocator is null)
        panic("threadScope requires a valid allocator");

    ThreadScope scope_ = ThreadScope(allocator);
    body(scope_);
    scope_.finish();
}

/// Runs a structured scope over an explicit caller-owned context.
///
/// The static body signature is
/// `void body(scope ref ThreadScope, scope Context*)`. The context must remain
/// alive for the complete call and is the intended source of scoped borrows.
void threadScope(alias body, Context)(
    Allocator* allocator,
    scope Context* context,
) @system
{
    validateScopeBody!(body, Context, true)();
    if (allocator is null || *allocator is null)
        panic("threadScope requires a valid allocator");
    if (context is null)
        panic("threadScope requires a non-null context pointer");

    ThreadScope scope_ = ThreadScope(allocator);
    body(scope_, context);
    scope_.finish();
}

static assert(!__traits(isCopyable, ThreadScope));

/// Scoped callback accepted by the inline structured-concurrency overload.
///
/// The delegate context is borrowed only for the duration of `threadScope` and
/// is never retained by a child node. Values borrowed by scoped workers must
/// have lifetimes enclosing the complete `threadScope` call; callback-local
/// variables do not satisfy that requirement because join-all follows callback
/// return.
alias ThreadScopeBody = void delegate(scope ref ThreadScope) nothrow @nogc;

/// Runs an inline structured scope and joins every successful child.
///
/// The callback itself is stack-borrowed and may capture enclosing caller
/// values without allocation. Scoped workers may borrow those enclosing values,
/// but must not borrow variables created inside the callback body.
void threadScope(
    Allocator* allocator,
    scope ThreadScopeBody body,
) @system
{
    if (allocator is null || *allocator is null)
        panic("threadScope requires a valid allocator");
    if (body is null)
        panic("threadScope requires a non-null body");

    ThreadScope scope_ = ThreadScope(allocator);
    body(scope_);
    scope_.finish();
}

version (unittest)
{
    private struct BasicScopeContext
    {
        int value;
        int left;
        int right;
    }

    private void incrementScopedValue(ref int value) nothrow @nogc
    {
        ++value;
    }

    private void addScopedValue(int value, int* sum) nothrow @nogc
    {
        *sum += value;
    }

    private void basicScopeBody(
        scope ref ThreadScope scope_,
        scope BasicScopeContext* context,
    ) nothrow @nogc
    {
        scope_.spawn!incrementScopedValue(context.value).unwrap();
        scope_.spawn!addScopedValue(20, &context.left).unwrap();
        scope_.spawn!addScopedValue(22, &context.right).unwrap();
    }

    private void emptyScopeBody(scope ref ThreadScope) nothrow @nogc
    {
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
            import xtb.allocators.malloc : mallocAllocator;

            threadScope!emptyScopeBody(mallocAllocator());

            BasicScopeContext context = BasicScopeContext(41, 0, 0);
            threadScope!basicScopeBody(mallocAllocator(), &context);
            assert(context.value == 42);
            assert(context.left + context.right == 42);

            int inlineValue = 41;
            threadScope(
                mallocAllocator(),
                (scope ref ThreadScope scope_) nothrow @nogc {
                scope_.spawn!incrementScopedValue(inlineValue).unwrap();
            },
            );
            assert(inlineValue == 42);
        }
    }
}
