module xtb.sync.barrier;

nothrow @nogc:

import xtb.panic : panic;
import xtb.sync.atomic : Atomic;
import xtb.sync.internal.generation_wait : GenerationWaitState;
import xtb.sync.mutex : Mutex;

/// Allocation-free reusable phase barrier with a fixed initial participant
/// count.
///
/// `Barrier.init` is inert and permanently complete; arrival operations on it
/// are invalid. `Barrier(participants)` requires a positive participant count.
/// Each logical participant must arrive exactly once per generation and must
/// not arrive again after dropping; participant identity is not stored.
/// Writes before arrival are visible after that generation completes.
/// Once another thread can access the barrier, its address must remain stable
/// until all such access has ended.
struct Barrier
{
nothrow @nogc:
    @disable this(this);

    private Mutex stateMutex_;
    private size_t remaining_;
    private size_t nextExpected_;
    private GenerationWaitState generation_;

    /// Constructs a barrier for `participants` logical participants.
    this(size_t participants) @safe
    {
        if (participants == 0)
            barrierRequiresParticipants();

        remaining_ = participants;
        nextExpected_ = participants;
    }

    /// Arrives in the current generation and blocks until every current
    /// participant has arrived.
    void arriveAndWait() @safe
    {
        stateMutex_.lock();
        requireActiveBarrier();

        const generation = generation_.currentGeneration();
        --remaining_;
        if (remaining_ == 0)
        {
            remaining_ = nextExpected_;
            generation_.advance();
            stateMutex_.unlock();
            return;
        }

        version (XTB_Checked)
            generation_.registerWaiter();
        stateMutex_.unlock();

        version (XTB_Checked)
        {
            generation_.waitForChangeRegistered(generation);
            generation_.unregisterWaiter();
        }
        else
        {
            generation_.waitForChange(generation);
        }
    }

    /// Arrives in the current generation, permanently removes one participant
    /// from later generations, and returns without waiting for this phase.
    void arriveAndDrop() @safe
    {
        stateMutex_.lock();
        requireActiveBarrier();

        --remaining_;
        --nextExpected_;
        if (remaining_ == 0)
        {
            remaining_ = nextExpected_;
            generation_.advance();
        }
        stateMutex_.unlock();
    }

private:
    void requireActiveBarrier() @safe
    {
        if (nextExpected_ == 0)
            barrierIsPermanentlyComplete();
    }
}

private noreturn barrierRequiresParticipants() @trusted
{
    panic("Barrier participant count must be greater than zero");
}

private noreturn barrierIsPermanentlyComplete() @trusted
{
    panic("cannot arrive at an inert or permanently complete Barrier");
}

static assert(!__traits(isCopyable, Barrier));

unittest
{
    Barrier inert;

    Barrier single = Barrier(1);
    foreach (_; 0 .. 8)
        single.arriveAndWait();

    Barrier maximum = Barrier(size_t.max);
    maximum.arriveAndDrop();
}

version (unittest)
{
    private enum bool barrierBlockingSupported = Atomic!uint.waitSupported;

    version (Posix)
    {
        import core.stdc.signal : SIGABRT;
        import core.sys.posix.sys.wait : waitpid;
        import core.sys.posix.unistd : _exit, fork;
    }

    static if (barrierBlockingSupported)
    {
        import xtb.sync.atomic : MemoryOrder;
        import xtb.thread.thread : Thread, yieldThread;

        private struct BarrierPhaseContext
        {
            Barrier* barrier;
            int* values;
            size_t participant;
            size_t participantCount;
            uint rounds;
            Atomic!uint* failed;
        }

        private int crossBarrierPhases(BarrierPhaseContext* context)
        nothrow @nogc
        {
            foreach (round; 0 .. context.rounds)
            {
                context.values[context.participant] = cast(int)(round + 1);
                context.barrier.arriveAndWait();

                foreach (participant; 0 .. context.participantCount)
                    if (context.values[participant] != cast(int)(round + 1))
                        context.failed.store(1, MemoryOrder.relaxed);

                context.barrier.arriveAndWait();
            }
            return 0;
        }

        private struct BarrierDropContext
        {
            Barrier* barrier;
            uint dropAfterPhase;
            Atomic!uint* completed;
        }

        private struct BarrierFinalDropContext
        {
            Barrier* barrier;
            Atomic!uint* entered;
            int* payload;
            int* observed;
        }

        private int waitForBarrierFinalDrop(BarrierFinalDropContext* context)
        nothrow @nogc
        {
            context.entered.store(1, MemoryOrder.release);
            context.entered.notifyOne();
            context.barrier.arriveAndWait();
            *context.observed = *context.payload;
            context.barrier.arriveAndDrop();
            return 0;
        }

        private int crossBarrierUntilDrop(BarrierDropContext* context)
        nothrow @nogc
        {
            foreach (_; 0 .. context.dropAfterPhase)
                context.barrier.arriveAndWait();

            context.barrier.arriveAndDrop();
            context.completed.fetchAdd(1, MemoryOrder.release);
            context.completed.notifyAll();
            return 0;
        }

        private void waitForBarrierValue(Atomic!uint* value, uint target)
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
            enum participantCount = 8;
            enum rounds = 256;
            Barrier barrier = Barrier(participantCount);
            int[participantCount] values;
            Atomic!uint failed;
            BarrierPhaseContext[participantCount] contexts;
            Thread[participantCount] participants;

            foreach (participant, ref thread; participants)
            {
                contexts[participant] = BarrierPhaseContext(
                    &barrier,
                    values.ptr,
                    participant,
                    participantCount,
                    rounds,
                    &failed,
                );
                auto started = Thread.start!crossBarrierPhases(
                    &contexts[participant],
                );
                assert(started.isOk);
                thread = started.unwrap();
            }

            foreach (ref thread; participants)
                assert(thread.join() == 0);
            assert(failed.load(MemoryOrder.relaxed) == 0);
            assert(barrier.remaining_ == participantCount);
            assert(barrier.nextExpected_ == participantCount);
        }

        unittest
        {
            enum participantCount = 4;
            Barrier barrier = Barrier(participantCount);
            Atomic!uint completed;
            BarrierDropContext[participantCount] contexts;
            Thread[participantCount] participants;

            foreach (participant; 0 .. participantCount)
                contexts[participant] = BarrierDropContext(
                    &barrier,
                    cast(uint) participant,
                    &completed,
                );

            auto firstStarted = Thread.start!crossBarrierUntilDrop(&contexts[0]);
            assert(firstStarted.isOk);
            participants[0] = firstStarted.unwrap();
            assert(participants[0].join() == 0);
            assert(completed.load(MemoryOrder.acquire) == 1);

            foreach (participant; 1 .. participantCount)
            {
                auto started = Thread.start!crossBarrierUntilDrop(
                    &contexts[participant],
                );
                assert(started.isOk);
                participants[participant] = started.unwrap();
            }

            waitForBarrierValue(&completed, participantCount);
            foreach (participant; 1 .. participantCount)
                assert(participants[participant].join() == 0);
            assert(barrier.remaining_ == 0);
            assert(barrier.nextExpected_ == 0);
        }

        unittest
        {
            Barrier barrier = Barrier(2);
            Atomic!uint entered;
            int payload;
            int observed;
            BarrierFinalDropContext context = BarrierFinalDropContext(
                &barrier,
                &entered,
                &payload,
                &observed,
            );

            auto started = Thread.start!waitForBarrierFinalDrop(&context);
            assert(started.isOk);
            Thread waiter = started.unwrap();
            waitForBarrierValue(&entered, 1);
            version (XTB_Checked)
                while (!barrier.generation_.hasWaiters())
                    yieldThread();

            payload = 0x2468_1357;
            barrier.arriveAndDrop();

            assert(waiter.join() == 0);
            assert(observed == payload);
            assert(barrier.remaining_ == 0);
            assert(barrier.nextExpected_ == 0);
        }
    }
    else version (XTB_TestUnsupportedThreadBackend)
    {
        version (Posix)
        {
            private bool unsupportedBarrierWaitAborts() @system
            {
                const process = fork();
                if (process < 0)
                    return false;
                if (process == 0)
                {
                    Barrier barrier = Barrier(2);
                    barrier.arriveAndWait();
                    _exit(0);
                }

                int status;
                return waitpid(process, &status, 0) == process &&
                    (status & 0x7f) == SIGABRT;
            }

            unittest
            {
                Barrier single = Barrier(1);
                single.arriveAndWait();

                Barrier dropping = Barrier(2);
                dropping.arriveAndDrop();
                dropping.arriveAndDrop();
                assert(unsupportedBarrierWaitAborts());
            }
        }
    }
}
