module xtb.threading.wait_group;

nothrow @nogc:

import xtb.core.panic : panic;
import xtb.threading.atomic : Atomic, MemoryOrder;
import xtb.threading.internal.generation_wait : GenerationWaitState;
import xtb.threading.mutex : Mutex;

version (XTB_Checked) import xtb.core.panic : require;

/// Allocation-free dynamic work countdown reusable across generations.
///
/// `WaitGroup.init` has no outstanding work. Positive `add` calls while work
/// remains join the current generation. After a generation completes, every
/// waiter must return before a positive `add` opens the next generation. Once
/// published to another thread, the wait group must remain at a stable address.
struct WaitGroup
{
nothrow @nogc:
    @disable this(this);

    private Mutex stateMutex_;
    private Atomic!size_t count_;
    private GenerationWaitState generation_;

    version (XTB_Checked)
    {
        ~this() @safe
        {
            require(
                count_.load(MemoryOrder.relaxed) == 0,
                "cannot destroy a WaitGroup with outstanding work",
            );
        }
    }

    /// Registers `count` work items. A positive add from zero opens a new
    /// generation and must occur only after previous waiters have returned.
    void add(size_t count = 1) @safe
    {
        if (count == 0)
            return;

        stateMutex_.lock();
        const current = count_.load(MemoryOrder.relaxed);
        if (count > size_t.max - current)
            waitGroupOverflow();

        version (XTB_Checked)
            if (current == 0 && generation_.hasWaiters())
                waitGroupReusedBeforeWaitReturned();

        count_.store(current + count, MemoryOrder.relaxed);
        stateMutex_.unlock();
    }

    /// Marks `count` work items complete. Completing more work than was
    /// registered is a fatal programming error. `done(0)` is a no-op.
    void done(size_t count = 1) @safe
    {
        if (count == 0)
            return;

        stateMutex_.lock();
        const current = count_.load(MemoryOrder.relaxed);
        if (count > current)
            waitGroupUnderflow();

        const remaining = current - count;
        count_.store(remaining, MemoryOrder.release);
        if (remaining == 0)
            generation_.advance();
        stateMutex_.unlock();
    }

    /// Blocks until the generation current at entry completes.
    void wait() @safe
    {
        stateMutex_.lock();
        if (count_.load(MemoryOrder.acquire) == 0)
        {
            stateMutex_.unlock();
            return;
        }

        const generation = generation_.currentGeneration();
        version (XTB_Checked)
            generation_.registerWaiter();
        stateMutex_.unlock();

        version (XTB_Checked)
        {
            generation_.waitForChangeRegistered(generation);

            stateMutex_.lock();
            if (count_.load(MemoryOrder.acquire) != 0)
                waitGroupReusedBeforeWaitReturned();
            generation_.unregisterWaiter();
            stateMutex_.unlock();
        }
        else
        {
            generation_.waitForChange(generation);
        }
    }

    /// Reports whether there is currently no outstanding work without
    /// blocking. A true result observes completed work with acquire ordering.
    bool tryWait() const @safe
    {
        return count_.load(MemoryOrder.acquire) == 0;
    }
}

private noreturn waitGroupOverflow() @trusted
{
    panic("WaitGroup outstanding count overflow");
}

private noreturn waitGroupUnderflow() @trusted
{
    panic("WaitGroup done count exceeds outstanding work");
}

version (XTB_Checked) private noreturn waitGroupReusedBeforeWaitReturned()
@trusted
{
    panic("WaitGroup reused before previous wait returned");
}

static assert(!__traits(isCopyable, WaitGroup));

unittest
{
    WaitGroup group;
    assert(group.tryWait());
    group.wait();
    group.add(0);
    group.done(0);

    group.add(3);
    assert(!group.tryWait());
    group.done(2);
    assert(!group.tryWait());
    group.add(2);
    group.done(3);
    assert(group.tryWait());
    group.wait();

    group.add();
    group.done();
    group.wait();

    group.add(size_t.max);
    group.done(size_t.max);
    assert(group.tryWait());
}

version (unittest)
{
    private enum bool waitGroupBlockingSupported = Atomic!uint.waitSupported;

    version (Posix)
    {
        import core.stdc.signal : SIGABRT;
        import core.sys.posix.sys.wait : waitpid;
        import core.sys.posix.unistd : _exit, fork;
    }

    version (XTB_Checked) version (Posix)
    {
        private bool waitGroupPrematureReuseAborts() @system
        {
            const process = fork();
            if (process < 0)
                return false;
            if (process == 0)
            {
                WaitGroup group;
                group.generation_.registerWaiter();
                group.add();
                _exit(0);
            }

            int status;
            return waitpid(process, &status, 0) == process &&
                (status & 0x7f) == SIGABRT;
        }

        unittest
        {
            assert(waitGroupPrematureReuseAborts());
        }
    }

    static if (waitGroupBlockingSupported)
    {
        import xtb.threading.thread : Thread;

        private struct WaitGroupWorkerContext
        {
            WaitGroup* group;
            int* output;
            int value;
        }

        private int completeWaitGroupWork(WaitGroupWorkerContext* context)
        nothrow @nogc
        {
            *context.output = context.value;
            context.group.done();
            return 0;
        }

        private struct WaitGroupWaiterContext
        {
            WaitGroup* group;
            Atomic!uint* entered;
            int* payload;
            int* observed;
        }

        private int waitOnWaitGroup(WaitGroupWaiterContext* context)
        nothrow @nogc
        {
            context.entered.fetchAdd(1, MemoryOrder.release);
            context.entered.notifyAll();
            context.group.wait();
            *context.observed = *context.payload;
            return 0;
        }

        private struct WaitGroupReuseContext
        {
            WaitGroup* group;
            Atomic!uint* requestedRound;
            Atomic!uint* completedRound;
            int* payload;
            uint rounds;
        }

        private struct WaitGroupDynamicAddContext
        {
            WaitGroup* group;
            Atomic!uint* registered;
            Atomic!uint* releaseWork;
            int* output;
        }

        private int dynamicallyAddWaitGroupWork(
            WaitGroupDynamicAddContext* context,
        ) nothrow @nogc
        {
            context.group.add(2);
            context.registered.store(1, MemoryOrder.release);
            context.registered.notifyOne();

            uint released = context.releaseWork.load(MemoryOrder.acquire);
            while (released == 0)
            {
                context.releaseWork.wait(released, MemoryOrder.acquire);
                released = context.releaseWork.load(MemoryOrder.acquire);
            }

            *context.output = 73;
            context.group.done(3);
            return 0;
        }

        private int reuseWaitGroupWorker(WaitGroupReuseContext* context)
        nothrow @nogc
        {
            foreach (round; 0 .. context.rounds)
            {
                uint requested = context.requestedRound.load(MemoryOrder.acquire);
                while (requested < round + 1)
                {
                    context.requestedRound.wait(requested, MemoryOrder.acquire);
                    requested = context.requestedRound.load(MemoryOrder.acquire);
                }

                *context.payload = cast(int)(round + 1);
                context.group.done();
                context.completedRound.store(round + 1, MemoryOrder.release);
                context.completedRound.notifyAll();
            }
            return 0;
        }

        private void waitForRound(Atomic!uint* value, uint target)
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
            enum workerCount = 8;
            enum waiterCount = 4;
            WaitGroup group;
            group.add(workerCount);
            Atomic!uint entered;
            int payload = 0x1357_2468;
            int[waiterCount] observed;
            WaitGroupWaiterContext[waiterCount] waiterContexts;
            Thread[waiterCount] waiters;

            foreach (index, ref waiter; waiters)
            {
                waiterContexts[index] = WaitGroupWaiterContext(
                    &group,
                    &entered,
                    &payload,
                    &observed[index],
                );
                auto started = Thread.start!waitOnWaitGroup(&waiterContexts[index]);
                assert(started.isOk);
                waiter = started.unwrap();
            }
            waitForRound(&entered, waiterCount);

            int[workerCount] output;
            WaitGroupWorkerContext[workerCount] workerContexts;
            Thread[workerCount] workers;
            foreach (index, ref worker; workers)
            {
                workerContexts[index] = WaitGroupWorkerContext(
                    &group,
                    &output[index],
                    cast(int)(index + 1),
                );
                auto started = Thread.start!completeWaitGroupWork(
                    &workerContexts[index],
                );
                assert(started.isOk);
                worker = started.unwrap();
            }

            foreach (ref worker; workers)
                assert(worker.join() == 0);
            foreach (ref waiter; waiters)
                assert(waiter.join() == 0);
            foreach (index, value; output)
                assert(value == index + 1);
            foreach (value; observed)
                assert(value == payload);
        }

        unittest
        {
            enum rounds = 512;
            WaitGroup group;
            Atomic!uint requestedRound;
            Atomic!uint completedRound;
            int payload;
            WaitGroupReuseContext context = WaitGroupReuseContext(
                &group,
                &requestedRound,
                &completedRound,
                &payload,
                rounds,
            );

            auto started = Thread.start!reuseWaitGroupWorker(&context);
            assert(started.isOk);
            Thread worker = started.unwrap();

            foreach (round; 0 .. rounds)
            {
                group.add();
                requestedRound.store(round + 1, MemoryOrder.release);
                requestedRound.notifyOne();
                group.wait();
                assert(payload == round + 1);
                waitForRound(&completedRound, round + 1);
            }

            assert(worker.join() == 0);
            assert(group.tryWait());
        }

        unittest
        {
            WaitGroup group;
            group.add();
            Atomic!uint registered;
            Atomic!uint releaseWork;
            int output;
            WaitGroupDynamicAddContext context = WaitGroupDynamicAddContext(
                &group,
                &registered,
                &releaseWork,
                &output,
            );

            auto started = Thread.start!dynamicallyAddWaitGroupWork(&context);
            assert(started.isOk);
            Thread worker = started.unwrap();
            waitForRound(&registered, 1);
            assert(!group.tryWait());

            releaseWork.store(1, MemoryOrder.release);
            releaseWork.notifyOne();
            group.wait();

            assert(output == 73);
            assert(worker.join() == 0);
        }
    }
    else version (XTB_TestUnsupportedThreadBackend)
    {
        version (Posix)
        {
            private bool unsupportedWaitGroupWaitAborts() @system
            {
                const process = fork();
                if (process < 0)
                    return false;
                if (process == 0)
                {
                    WaitGroup group;
                    group.add();
                    group.wait();
                    _exit(0);
                }

                int status;
                return waitpid(process, &status, 0) == process &&
                    (status & 0x7f) == SIGABRT;
            }

            unittest
            {
                WaitGroup group;
                group.add(2);
                assert(!group.tryWait());
                group.done(2);
                assert(group.tryWait());
                group.wait();
                assert(unsupportedWaitGroupWaitAborts());
            }
        }
    }
}
