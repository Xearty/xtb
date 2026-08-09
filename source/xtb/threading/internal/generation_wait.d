module xtb.threading.internal.generation_wait;

nothrow @nogc:

import xtb.core.panic : panic;
import xtb.threading.atomic : Atomic, MemoryOrder;

version (XTB_Checked) import xtb.core.panic : require;

/// Package-private reusable phase-change wait state.
///
/// The 32-bit generation is both the semantic phase token and the address
/// parked on by the current backend. `WaitGroup` reuse rules and `Barrier`
/// participation guarantee that a valid waiter cannot span enough completed
/// phases for generation wrap to become ambiguous.
package(xtb.threading) struct GenerationWaitState
{
nothrow @nogc:
    @disable this(this);

    private Atomic!uint generation_;
    version (XTB_Checked) private Atomic!size_t waiters_;

    version (XTB_Checked)
    {
        ~this() @safe
        {
            require(
                waiters_.load(MemoryOrder.relaxed) == 0,
                "cannot destroy generation state with active waiters",
            );
        }
    }

    /// Returns the current generation with acquire ordering.
    package(xtb.threading) uint currentGeneration() const @safe
    {
        return generation_.load(MemoryOrder.acquire);
    }

    /// Reports whether `expected` has completed with acquire ordering.
    package(xtb.threading) bool hasChanged(uint expected) const @safe
    {
        return currentGeneration() != expected;
    }

    /// Publishes completion of the current phase and wakes all phase waiters.
    package(xtb.threading) void advance() @safe
    {
        cast(void) generation_.fetchAdd(1, MemoryOrder.release);
        static if (Atomic!uint.waitSupported)
            generation_.notifyAll();
    }

    /// Blocks until the generation differs from `expected`.
    ///
    /// Atomic compare-and-sleep prevents a completion between the caller's
    /// observation and parking from becoming a lost wakeup.
    package(xtb.threading) void waitForChange(uint expected) @safe
    {
        version (XTB_Checked)
            registerWaiter();

        waitForChangeRegistered(expected);

        version (XTB_Checked)
            unregisterWaiter();
    }

    /// Waits after a caller has performed any required external registration.
    package(xtb.threading) void waitForChangeRegistered(uint expected) @safe
    {
        while (!hasChanged(expected))
        {
            static if (!Atomic!uint.waitSupported)
            {
                unsupportedGenerationWait();
            }
            else
            {
                generation_.wait(expected, MemoryOrder.acquire);
            }
        }
    }

    version (XTB_Checked)
    {
        /// Whether a caller is currently inside `waitForChange`.
        package(xtb.threading) bool hasWaiters() const @safe
        {
            return waiters_.load(MemoryOrder.acquire) != 0;
        }

        package(xtb.threading) void registerWaiter() @safe
        {
            size_t observed = waiters_.load(MemoryOrder.relaxed);
            while (true)
            {
                if (observed == size_t.max)
                    generationWaiterOverflow();
                if (waiters_.compareExchangeWeak(
                        observed,
                        observed + 1,
                        MemoryOrder.release,
                        MemoryOrder.relaxed,
                    ))
                    return;
            }
        }

        package(xtb.threading) void unregisterWaiter() @safe
        {
            size_t observed = waiters_.load(MemoryOrder.relaxed);
            while (true)
            {
                if (observed == 0)
                    generationWaiterUnderflow();
                if (waiters_.compareExchangeWeak(
                        observed,
                        observed - 1,
                        MemoryOrder.release,
                        MemoryOrder.relaxed,
                    ))
                    return;
            }
        }
    }
}

private noreturn unsupportedGenerationWait() @trusted
{
    panic("generation wait requires a supported thread parking backend");
}

version (XTB_Checked)
{
    private noreturn generationWaiterOverflow() @trusted
    {
        panic("generation waiter count overflow");
    }

    private noreturn generationWaiterUnderflow() @trusted
    {
        panic("generation waiter count underflow");
    }
}

static assert(!__traits(isCopyable, GenerationWaitState));
version (XTB_Checked)
    static assert(GenerationWaitState.sizeof >=
            Atomic!uint.sizeof + Atomic!size_t.sizeof);
else
    static assert(GenerationWaitState.sizeof == Atomic!uint.sizeof);

unittest
{
    GenerationWaitState state;
    assert(state.currentGeneration() == 0);
    assert(!state.hasChanged(0));
    version (XTB_Checked)
        assert(!state.hasWaiters());

    state.advance();
    assert(state.currentGeneration() == 1);
    assert(state.hasChanged(0));
    state.waitForChange(0);
    version (XTB_Checked)
        assert(!state.hasWaiters());
}

version (unittest)
{
    static if (Atomic!uint.waitSupported)
    {
        import xtb.threading.thread : Thread, yieldThread;

        private struct GenerationWaitContext
        {
            GenerationWaitState* state;
            Atomic!uint* entered;
            Atomic!uint* completed;
            int* payload;
            int* observed;
        }

        private int waitForGeneration(GenerationWaitContext* context)
        nothrow @nogc
        {
            const generation = context.state.currentGeneration();
            context.entered.fetchAdd(1, MemoryOrder.release);
            context.entered.notifyAll();
            context.state.waitForChange(generation);
            *context.observed = *context.payload;
            context.completed.fetchAdd(1, MemoryOrder.release);
            context.completed.notifyAll();
            return 0;
        }

        private struct GenerationStressContext
        {
            GenerationWaitState* state;
            Atomic!uint* enteredRound;
            Atomic!uint* completedRound;
            Atomic!uint* failed;
            int* payload;
            uint rounds;
        }

        private int stressGenerationWait(GenerationStressContext* context)
        nothrow @nogc
        {
            foreach (round; 0 .. context.rounds)
            {
                const generation = context.state.currentGeneration();
                context.enteredRound.store(round + 1, MemoryOrder.release);
                context.enteredRound.notifyAll();
                context.state.waitForChange(generation);
                if (*context.payload != cast(int)(round + 1))
                    context.failed.store(1, MemoryOrder.relaxed);
                context.completedRound.store(round + 1, MemoryOrder.release);
                context.completedRound.notifyAll();
            }
            return 0;
        }

        private void waitUntilAtLeast(Atomic!uint* value, uint target)
        nothrow @nogc
        {
            uint observed = value.load(MemoryOrder.acquire);
            while (observed < target)
            {
                value.wait(observed, MemoryOrder.acquire);
                observed = value.load(MemoryOrder.acquire);
            }
        }

        unittest
        {
            enum waiterCount = 8;
            GenerationWaitState state;
            Atomic!uint entered;
            Atomic!uint completed;
            int payload;
            int[waiterCount] observed;
            GenerationWaitContext[waiterCount] contexts;
            Thread[waiterCount] waiters;

            foreach (index, ref waiter; waiters)
            {
                contexts[index] = GenerationWaitContext(
                    &state,
                    &entered,
                    &completed,
                    &payload,
                    &observed[index],
                );
                auto started = Thread.start!waitForGeneration(&contexts[index]);
                assert(started.isOk);
                waiter = started.unwrap();
            }

            waitUntilAtLeast(&entered, waiterCount);
            version (XTB_Checked)
                while (state.waiters_.load(MemoryOrder.acquire) != waiterCount)
                    yieldThread();
            payload = 0x2468_1357;
            state.advance();

            foreach (ref waiter; waiters)
                assert(waiter.join() == 0);
            assert(completed.load(MemoryOrder.acquire) == waiterCount);
            foreach (value; observed)
                assert(value == payload);
            version (XTB_Checked)
                assert(!state.hasWaiters());
        }

        unittest
        {
            enum rounds = 2_048;
            GenerationWaitState state;
            Atomic!uint enteredRound;
            Atomic!uint completedRound;
            Atomic!uint failed;
            int payload;
            GenerationStressContext context = GenerationStressContext(
                &state,
                &enteredRound,
                &completedRound,
                &failed,
                &payload,
                rounds,
            );

            auto started = Thread.start!stressGenerationWait(&context);
            assert(started.isOk);
            Thread waiter = started.unwrap();

            foreach (round; 0 .. rounds)
            {
                waitUntilAtLeast(&enteredRound, round + 1);
                payload = cast(int)(round + 1);
                state.advance();
                waitUntilAtLeast(&completedRound, round + 1);
            }

            assert(waiter.join() == 0);
            assert(failed.load(MemoryOrder.relaxed) == 0);
            assert(state.currentGeneration() == rounds);
        }

        unittest
        {
            GenerationWaitState state;
            state.generation_.store(uint.max, MemoryOrder.relaxed);
            Atomic!uint entered;
            Atomic!uint completed;
            int payload = 91;
            int observed;
            GenerationWaitContext context = GenerationWaitContext(
                &state,
                &entered,
                &completed,
                &payload,
                &observed,
            );

            auto started = Thread.start!waitForGeneration(&context);
            assert(started.isOk);
            Thread waiter = started.unwrap();
            waitUntilAtLeast(&entered, 1);
            state.advance();

            assert(waiter.join() == 0);
            assert(observed == payload);
            assert(state.currentGeneration() == 0);
        }
    }
}
