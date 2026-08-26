module xtb.sync.latch;

nothrow @nogc:

import xtb.sync.internal.countdown : CountdownState;

/// Allocation-free one-shot countdown synchronization primitive.
///
/// `Latch.init` is completed. `Latch(count)` starts with `count` outstanding
/// arrivals. Once another thread can access or wait on a latch, its address
/// must remain stable until all such access has ended.
struct Latch
{
nothrow @nogc:
    @disable this(this);

    private CountdownState state_;

    /// Constructs a latch with the requested outstanding count.
    this(size_t count) @safe
    {
        state_.initialize(count);
    }

    /// Completes `count` arrivals. Completing more than remain is a fatal
    /// programming error. `countDown(0)` is a no-op.
    void countDown(size_t count = 1) @safe
    {
        state_.countDown(count);
    }

    /// Blocks until the outstanding count reaches zero.
    void wait() const @safe
    {
        state_.wait();
    }

    /// Reports whether the latch has completed without blocking.
    bool tryWait() const @safe
    {
        return state_.tryWait();
    }
}

static assert(!__traits(isCopyable, Latch));

unittest
{
    Latch completed;
    assert(completed.tryWait());
    completed.wait();
    completed.countDown(0);

    Latch latch = Latch(3);
    assert(!latch.tryWait());
    latch.countDown(0);
    latch.countDown(2);
    assert(!latch.tryWait());
    latch.countDown();
    assert(latch.tryWait());
    latch.wait();
}

version (unittest)
{
    import xtb.sync.atomic : Atomic, MemoryOrder;

    private enum bool countdownWaitSupported = Atomic!uint.waitSupported;

    static if (countdownWaitSupported)
    {
        import xtb.thread.thread : Thread;

        private struct LatchWaitContext
        {
            Latch* latch;
            Atomic!uint* entered;
            Atomic!uint* completed;
            int* payload;
            int* observed;
        }

        private int waitOnLatch(LatchWaitContext* context) nothrow @nogc
        {
            context.entered.fetchAdd(1, MemoryOrder.release);
            context.entered.notifyAll();
            context.latch.wait();
            *context.observed = *context.payload;
            context.completed.fetchAdd(1, MemoryOrder.release);
            return 0;
        }

        private struct LatchCountdownContext
        {
            Latch* latch;
            int* output;
            int value;
        }

        private int countDownLatch(LatchCountdownContext* context) nothrow @nogc
        {
            *context.output = context.value;
            context.latch.countDown();
            return 0;
        }

        unittest
        {
            enum waiterCount = 4;
            Latch latch = Latch(2);
            Atomic!uint entered;
            Atomic!uint completed;
            int payload;
            int[waiterCount] observed;
            LatchWaitContext[waiterCount] contexts;
            Thread[waiterCount] waiters;

            foreach (index, ref waiter; waiters)
            {
                contexts[index] = LatchWaitContext(
                    &latch,
                    &entered,
                    &completed,
                    &payload,
                    &observed[index],
                );
                auto started = Thread.start!waitOnLatch(&contexts[index]);
                assert(started.isOk);
                waiter = started.unwrap();
            }

            uint enteredSnapshot = entered.load(MemoryOrder.acquire);
            while (enteredSnapshot != waiterCount)
            {
                entered.wait(enteredSnapshot, MemoryOrder.acquire);
                enteredSnapshot = entered.load(MemoryOrder.acquire);
            }

            latch.countDown();
            assert(!latch.tryWait());
            assert(completed.load(MemoryOrder.acquire) == 0);

            payload = 0x1234_5678;
            latch.countDown();
            foreach (ref waiter; waiters)
                assert(waiter.join() == 0);

            assert(completed.load(MemoryOrder.acquire) == waiterCount);
            foreach (value; observed)
                assert(value == payload);
        }

        unittest
        {
            enum workerCount = 8;
            Latch latch = Latch(workerCount);
            int[workerCount] output;
            LatchCountdownContext[workerCount] contexts;
            Thread[workerCount] workers;

            foreach (index, ref worker; workers)
            {
                contexts[index] = LatchCountdownContext(
                    &latch,
                    &output[index],
                    cast(int) index + 1,
                );
                auto started = Thread.start!countDownLatch(&contexts[index]);
                assert(started.isOk);
                worker = started.unwrap();
            }

            latch.wait();
            foreach (ref worker; workers)
                assert(worker.join() == 0);
            foreach (index, value; output)
                assert(value == index + 1);
        }
    }
}
