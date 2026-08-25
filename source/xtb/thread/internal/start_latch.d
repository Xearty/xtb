module xtb.thread.internal.start_latch;

nothrow @nogc:

import xtb.core.panic : panic;
import xtb.sync.atomic : Atomic, MemoryOrder;

/// Whether the active backend can provide the allocation-free blocking path
/// required by `StartLatch`.
package(xtb.thread) enum bool startLatchSupported = Atomic!uint.waitSupported;

private noreturn unsupportedStartLatch() @trusted
{
    panic("thread start latch is unsupported on this platform");
}

/// Package-private one-shot rendezvous used by thread-start ownership handoffs.
///
/// The zero-initialized state is pending. Exactly one signaling thread publishes
/// completion with release ordering and wakes the single waiting starter. The
/// waiter uses acquire ordering, so all accesses sequenced before `signal` are
/// visible after `wait` returns.
///
/// This primitive has no reset operation, owns no allocation/native handle, and
/// must remain at a stable address while another thread can be waiting on it.
/// It is intentionally narrower than a public latch or event: one signal, one
/// waiter, one lifetime.
package(xtb.thread) struct StartLatch
{
nothrow @nogc:
    @disable this(this);

    private Atomic!uint state_;

    /// Blocks until the latch has been signaled.
    void wait() @safe
    {
        static if (startLatchSupported)
        {
            state_.wait(0, MemoryOrder.acquire);
        }
        else
        {
            unsupportedStartLatch();
        }
    }

    /// Permanently signals the latch and wakes its waiter, if already parked.
    void signal() @safe
    {
        static if (startLatchSupported)
        {
            state_.store(1, MemoryOrder.release);
            state_.notifyOne();
        }
        else
        {
            unsupportedStartLatch();
        }
    }
}

static assert(StartLatch.sizeof == Atomic!uint.sizeof);
static assert(StartLatch.alignof == Atomic!uint.alignof);
static assert(!__traits(compiles, () { StartLatch first; StartLatch second = first; }));

version (unittest)
{
    version (Posix)
    {
        import core.stdc.signal : SIGABRT;
        import core.sys.posix.pthread : pthread_create, pthread_join, pthread_t;
        import core.sys.posix.sched : sched_yield;
        import core.sys.posix.sys.wait : waitpid;
        import core.sys.posix.unistd : _exit, fork;

        private struct PublicationContext
        {
            StartLatch* latch;
            Atomic!uint* entered;
            int* payload;
        }

        private extern (C) void* publicationWorker(void* opaque) @system
        {
            PublicationContext* context = cast(PublicationContext*) opaque;
            context.entered.store(1, MemoryOrder.release);
            *context.payload = 0x4c61_7463;
            context.latch.signal();
            return null;
        }

        private bool waitForEntered(Atomic!uint* entered)
        {
            foreach (_; 0 .. 1_000_000)
            {
                if (entered.load(MemoryOrder.acquire) != 0)
                    return true;
                sched_yield();
            }
            return false;
        }

        private bool releaseAcquirePublication() @system
        {
            StartLatch latch;
            Atomic!uint entered;
            int payload;
            PublicationContext context = PublicationContext(
                &latch,
                &entered,
                &payload,
            );

            pthread_t worker;
            if (pthread_create(&worker, null, &publicationWorker, &context) != 0)
                return false;

            if (!waitForEntered(&entered))
            {
                // The worker was created, so always join it before the
                // stack-backed context can go out of scope.
                cast(void) pthread_join(worker, null);
                return false;
            }

            latch.wait();
            const published = payload == 0x4c61_7463;
            return pthread_join(worker, null) == 0 && published;
        }

        private struct WaitingContext
        {
            StartLatch* latch;
            Atomic!uint* entered;
            Atomic!uint* completed;
        }

        private extern (C) void* waitingWorker(void* opaque) @system
        {
            WaitingContext* context = cast(WaitingContext*) opaque;
            context.entered.store(1, MemoryOrder.release);
            context.latch.wait();
            context.completed.store(1, MemoryOrder.release);
            return null;
        }

        private bool waitThenSignal() @system
        {
            StartLatch latch;
            Atomic!uint entered;
            Atomic!uint completed;
            WaitingContext context = WaitingContext(
                &latch,
                &entered,
                &completed,
            );

            pthread_t worker;
            if (pthread_create(&worker, null, &waitingWorker, &context) != 0)
                return false;

            if (!waitForEntered(&entered))
            {
                latch.signal();
                cast(void) pthread_join(worker, null);
                return false;
            }

            // Before the one-shot state is published, the waiter must not be
            // able to complete. Yielding here also gives it repeated chances
            // to enter the blocking path before the signal is sent.
            foreach (_; 0 .. 1_024)
            {
                if (completed.load(MemoryOrder.acquire) != 0)
                {
                    cast(void) pthread_join(worker, null);
                    return false;
                }
                sched_yield();
            }

            latch.signal();
            if (pthread_join(worker, null) != 0)
                return false;
            return completed.load(MemoryOrder.acquire) == 1;
        }

        private struct StressContext
        {
            StartLatch* latches;
            uint* payloads;
            uint rounds;
        }

        private extern (C) void* signalAheadWorker(void* opaque) @system
        {
            StressContext* context = cast(StressContext*) opaque;
            foreach (round; 0 .. context.rounds)
            {
                context.payloads[round] = round + 1;
                context.latches[round].signal();
            }
            return null;
        }

        private bool signalBeforeWaitStress() @system
        {
            enum rounds = 1_024;
            StartLatch[rounds] latches;
            uint[rounds] payloads;
            StressContext context = StressContext(
                latches.ptr,
                payloads.ptr,
                rounds,
            );

            pthread_t worker;
            if (pthread_create(&worker, null, &signalAheadWorker, &context) != 0)
                return false;

            bool succeeded = true;
            foreach (round; 0 .. rounds)
            {
                latches[round].wait();
                if (payloads[round] != round + 1)
                {
                    succeeded = false;
                    break;
                }
            }

            return pthread_join(worker, null) == 0 && succeeded;
        }
    }

    version (XTB_TestUnsupportedThreadBackend)
    {
        version (Posix)
        {
            private enum UnsupportedStartLatchCase : ubyte
            {
                wait,
                signal,
            }

            private void runUnsupportedStartLatchCase(
                UnsupportedStartLatchCase latchCase,
            )
            {
                StartLatch latch;
                final switch (latchCase)
                {
                    case UnsupportedStartLatchCase.wait:
                        latch.wait();
                        return;
                    case UnsupportedStartLatchCase.signal:
                        latch.signal();
                        return;
                }
            }

            private bool unsupportedStartLatchAborts(
                UnsupportedStartLatchCase latchCase,
            )
            {
                const process = fork();
                if (process < 0)
                    return false;
                if (process == 0)
                {
                    runUnsupportedStartLatchCase(latchCase);
                    _exit(0);
                }

                int status;
                return waitpid(process, &status, 0) == process &&
                    (status & 0x7f) == SIGABRT;
            }
        }
    }
}

unittest
{
    static assert(startLatchSupported == Atomic!uint.waitSupported);

    version (XTB_TestUnsupportedThreadBackend)
    {
        static assert(!startLatchSupported);
        version (Posix)
        {
            assert(unsupportedStartLatchAborts(UnsupportedStartLatchCase.wait));
            assert(unsupportedStartLatchAborts(UnsupportedStartLatchCase.signal));
        }
    }
    else version (linux)
    {
        static if (startLatchSupported)
        {
            StartLatch alreadySignaled;
            alreadySignaled.signal();
            alreadySignaled.wait();

            assert(releaseAcquirePublication());
            assert(waitThenSignal());
            assert(signalBeforeWaitStress());
        }
    }
}
