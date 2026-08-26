module xtb.sync.once;

nothrow @nogc:

import core.internal.traits : Parameters, ReturnType;
import core.lifetime : forward;
import xtb.panic : panic;
import xtb.sync.atomic : Atomic, MemoryOrder;

version (XTB_Checked) import xtb.thread.thread : currentThreadId, threadIdBits;

private enum uint onceUninitialized = 0;
private enum uint onceInitializing = 1;
private enum uint onceInitialized = 2;

/// Allocation-free state for one-time initialization.
///
/// `Once.init` is uninitialized. Use `callOnce` with a module-level or static
/// `nothrow @nogc` initializer. Once published, this object must remain at a
/// stable address until no thread can access it.
struct Once
{
nothrow @nogc:
    @disable this(this);

    private Atomic!uint state_;
    version (XTB_Checked) private Atomic!ulong initializingOwner_;

    package(xtb.sync) bool completed() const @trusted
    {
        return state_.load(MemoryOrder.acquire) == onceInitialized;
    }

    version (XTB_Checked) package(xtb.sync) bool initializing() const @trusted
    {
        return state_.load(MemoryOrder.relaxed) == onceInitializing;
    }
}

/// Runs exactly one context-free initializer for `once`.
///
/// Arguments are ordinary by-value function arguments and are therefore
/// evaluated and captured before this function determines whether the caller
/// wins initialization. Only the winning caller invokes `initializer`.
void callOnce(alias initializer, Args...)(ref Once once, Args arguments)
{
    validateInitializer!initializer();

    uint observed = once.state_.load(MemoryOrder.acquire);
    while (observed != onceInitialized)
    {
        if (observed == onceUninitialized)
        {
            uint expected = onceUninitialized;
            if (once.state_.compareExchangeStrong(
                    expected,
                    onceInitializing,
                    MemoryOrder.acquire,
                    MemoryOrder.acquire,
                ))
            {
                version (XTB_Checked)
                    once.initializingOwner_.store(
                        currentOwnerBits(),
                        MemoryOrder.relaxed,
                    );

                initializer(forward!arguments);

                version (XTB_Checked)
                    once.initializingOwner_.store(0, MemoryOrder.relaxed);
                once.state_.store(onceInitialized, MemoryOrder.release);
                static if (Atomic!uint.waitSupported)
                    once.state_.notifyAll();
                return;
            }
            observed = expected;
            continue;
        }

        if (observed != onceInitializing)
            invalidOnceState();

        version (XTB_Checked)
            if (once.initializingOwner_.load(MemoryOrder.relaxed) ==
                currentOwnerBits())
                recursiveOnce();

        static if (!Atomic!uint.waitSupported)
        {
            unsupportedOnceWait();
        }
        else
        {
            once.state_.wait(onceInitializing, MemoryOrder.acquire);
            observed = once.state_.load(MemoryOrder.acquire);
        }
    }
}

private void validateInitializer(alias initializer)()
{
    static assert(
        __traits(isStaticFunction, initializer),
        "callOnce initializer must be a module-level or static function",
    );
    static assert(
        hasFunctionAttribute!(initializer, "nothrow"),
        "callOnce initializer must be nothrow",
    );
    static assert(
        hasFunctionAttribute!(initializer, "@nogc"),
        "callOnce initializer must be @nogc",
    );
    static assert(is(ReturnType!initializer == void),
        "callOnce initializer must return void");
    static foreach (index; 0 .. Parameters!initializer.length)
    {
        static assert(
            !parameterHasStorageClass!(initializer, index, "ref") &&
                !parameterHasStorageClass!(initializer, index, "out") &&
                !parameterHasStorageClass!(initializer, index, "lazy") &&
                !parameterHasStorageClass!(initializer, index, "in"),
            "callOnce initializer parameters must use by-value transport",
        );
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

version (XTB_Checked) private ulong currentOwnerBits() @safe
{
    return threadIdBits(currentThreadId());
}

private noreturn recursiveOnce() @trusted
{
    panic("recursive callOnce on the same Once is not allowed");
}

private noreturn invalidOnceState() @trusted
{
    panic("Once contains an invalid state");
}

private noreturn unsupportedOnceWait() @trusted
{
    panic("contended callOnce requires a supported thread parking backend");
}

static assert(!__traits(isCopyable, Once));
version (XTB_Checked)
    static assert(Once.sizeof >= Atomic!uint.sizeof + Atomic!ulong.sizeof);
else
    static assert(Once.sizeof == Atomic!uint.sizeof);

version (unittest)
{
    private void incrementOnce(int* value) nothrow @nogc
    {
        ++*value;
    }

    private int wrongOnceReturn() nothrow @nogc
    {
        return 1;
    }

    private void refOnceInitializer(ref int value) nothrow @nogc
    {
        ++value;
    }

    private int* evaluateOnceArgument(int* evaluations, int* value)
    nothrow @nogc
    {
        ++*evaluations;
        return value;
    }

    unittest
    {
        Once once;
        int calls;
        callOnce!incrementOnce(once, &calls);
        callOnce!incrementOnce(once, &calls);
        assert(calls == 1);

        Once evaluatedOnce;
        int evaluations;
        int initializedValue;
        callOnce!incrementOnce(
            evaluatedOnce,
            evaluateOnceArgument(&evaluations, &initializedValue),
        );
        callOnce!incrementOnce(
            evaluatedOnce,
            evaluateOnceArgument(&evaluations, &initializedValue),
        );
        assert(evaluations == 2);
        assert(initializedValue == 1);

        static assert(!__traits(compiles, callOnce!wrongOnceReturn(once)));
        static assert(!__traits(compiles, callOnce!refOnceInitializer(once, calls)));

        void nested() nothrow @nogc
        {
        }

        static assert(!__traits(compiles, callOnce!nested(once)));
    }

    static if (Atomic!uint.waitSupported)
    {
        import xtb.thread.thread : Thread;

        private struct OnceContentionContext
        {
            Once* once;
            Atomic!uint* entered;
            Atomic!uint* releaseInitializer;
            Atomic!uint* calls;
            int* payload;
        }

        private void contendedInitializer(OnceContentionContext* context)
        nothrow @nogc
        {
            context.calls.fetchAdd(1, MemoryOrder.relaxed);
            context.entered.store(1, MemoryOrder.release);
            context.entered.notifyAll();
            context.releaseInitializer.wait(0, MemoryOrder.acquire);
            *context.payload = 0x2468_1357;
        }

        private int invokeContendedOnce(OnceContentionContext* context)
        nothrow @nogc
        {
            callOnce!contendedInitializer(*context.once, context);
            return *context.payload == 0x2468_1357 ? 0 : 1;
        }

        unittest
        {
            enum callerCount = 8;
            Once once;
            Atomic!uint entered;
            Atomic!uint releaseInitializer;
            Atomic!uint calls;
            int payload;
            OnceContentionContext context = OnceContentionContext(
                &once,
                &entered,
                &releaseInitializer,
                &calls,
                &payload,
            );
            Thread[callerCount] callers;

            auto firstStarted = Thread.start!invokeContendedOnce(&context);
            assert(firstStarted.isOk);
            callers[0] = firstStarted.unwrap();

            entered.wait(0, MemoryOrder.acquire);
            foreach (ref caller; callers[1 .. $])
            {
                auto started = Thread.start!invokeContendedOnce(&context);
                assert(started.isOk);
                caller = started.unwrap();
            }

            releaseInitializer.store(1, MemoryOrder.release);
            releaseInitializer.notifyAll();

            foreach (ref caller; callers)
                assert(caller.join() == 0);
            assert(calls.load(MemoryOrder.relaxed) == 1);
        }
    }
}
