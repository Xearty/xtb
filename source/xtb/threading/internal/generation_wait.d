module xtb.threading.internal.generation_wait;

nothrow @nogc:

import xtb.core.panic : panic;
import xtb.threading.atomic : Atomic, MemoryOrder;

version (XTB_Checked) import xtb.core.panic : require;

/// Package-private reusable phase-change wait state.
///
/// The full-width logical generation distinguishes semantic phases. The
/// separate 32-bit epoch is only the address parked on by the current backend;
/// callers must always decide completion from `generation_`.
package(xtb.threading) struct GenerationWaitState
{
nothrow @nogc:
    @disable this(this);

    private Atomic!size_t generation_;
    private Atomic!uint wakeEpoch_;
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

    /// Returns the current logical generation with acquire ordering.
    package(xtb.threading) size_t currentGeneration() const @safe
    {
        return generation_.load(MemoryOrder.acquire);
    }

    /// Reports whether `expected` has completed with acquire ordering.
    package(xtb.threading) bool hasChanged(size_t expected) const @safe
    {
        return currentGeneration() != expected;
    }

    /// Publishes completion of the current phase and wakes all phase waiters.
    package(xtb.threading) void advance() @safe
    {
        cast(void) generation_.fetchAdd(1, MemoryOrder.release);
        static if (Atomic!uint.waitSupported)
        {
            cast(void) wakeEpoch_.fetchAdd(1, MemoryOrder.release);
            wakeEpoch_.notifyAll();
        }
    }

    /// Blocks until the logical generation differs from `expected`.
    ///
    /// The waitable epoch is sampled before a second logical-generation check,
    /// closing the transition-before-park lost-wakeup race. Epoch wrap cannot
    /// create semantic ambiguity because every return decision rechecks the
    /// full logical generation.
    package(xtb.threading) void waitForChange(size_t expected) @safe
    {
        version (XTB_Checked)
            registerWaiter();

        while (!hasChanged(expected))
        {
            static if (!Atomic!uint.waitSupported)
            {
                unsupportedGenerationWait();
            }
            else
            {
                const epoch = wakeEpoch_.load(MemoryOrder.relaxed);
                if (!hasChanged(expected))
                    wakeEpoch_.wait(epoch, MemoryOrder.acquire);
            }
        }

        version (XTB_Checked)
            unregisterWaiter();
    }

    version (XTB_Checked)
    {
        /// Whether a caller is currently inside `waitForChange`.
        package(xtb.threading) bool hasWaiters() const @safe
        {
            return waiters_.load(MemoryOrder.acquire) != 0;
        }

        private void registerWaiter() @safe
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

        private void unregisterWaiter() @safe
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
            state.wakeEpoch_.store(uint.max, MemoryOrder.relaxed);
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
            assert(state.wakeEpoch_.load(MemoryOrder.relaxed) == 0);
        }
    }
}
