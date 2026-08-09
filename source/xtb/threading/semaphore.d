module xtb.threading.semaphore;

nothrow @nogc:

import xtb.core.intrusive_list : ForwardListHook, IntrusiveQueue;
import xtb.core.panic : panic;
import xtb.threading.atomic : Atomic, MemoryOrder;
import xtb.threading.mutex : Mutex;

version (XTB_Checked) import xtb.core.panic : require;

private enum uint waiterQueued = 0;
private enum uint waiterParking = 1;
private enum uint waiterSignaled = 2;

private struct SemaphoreWaiter
{
    Atomic!uint state;
    ForwardListHook!SemaphoreWaiter queueHook;
}

/// Allocation-free counting semaphore.
///
/// `Semaphore.init` contains zero permits. `Semaphore(initialPermits)` creates a
/// semaphore with the requested initial permit count. A successful acquire
/// consumes exactly one permit; `release(count)` contributes `count` permits.
///
/// Blocking waiters use one stack-backed wait word each. The semaphore never
/// reuses a shared finite-width wait generation, so its blocking protocol has no
/// wake-counter wrap/ABA case. The type is non-copyable and must remain at a
/// stable address once another thread may access or wait on it.
struct Semaphore
{
nothrow @nogc:
    @disable this(this);

    // Available, unreserved permits. A queued waiter has no permit represented
    // here: release hands a permit directly to that waiter instead.
    private Atomic!size_t permits_;

    static if (Atomic!uint.waitSupported)
    {
        // Serializes slow-path registration with release so the transition from
        // observing zero permits to parking cannot lose a release.
        private Mutex stateMutex_;
        private IntrusiveQueue!(SemaphoreWaiter, "queueHook") waiters_;

        version (XTB_Checked) private size_t activeWaiters_;
    }

    /// Constructs a semaphore with `initialPermits` immediately available.
    this(size_t initialPermits) @safe
    {
        permits_.store(initialPermits, MemoryOrder.relaxed);
    }

    /// Adds `count` permits.
    ///
    /// `release(0)` is a no-op. Permits are handed directly to already queued
    /// waiters before any remainder is added to the fast-path permit counter.
    /// Overflowing the `size_t` permit counter is a programming error.
    void release(size_t count = 1) @safe
    {
        if (count == 0)
            return;

        static if (!Atomic!uint.waitSupported)
        {
            addPermits(count);
        }
        else
        {
            stateMutex_.lock();

            // Queue membership and the permit counter obey this invariant:
            // whenever a waiter is queued, there are no unreserved permits.
            // Therefore a release can reserve its first permits directly for
            // queued waiters without exposing them to fast-path barging.
            while (count != 0 && !waiters_.empty)
            {
                SemaphoreWaiter* waiter = waiters_.popFront();
                signalWaiter(waiter);
                --count;
            }

            if (count != 0)
                addPermits(count);

            stateMutex_.unlock();
        }
    }

    /// Acquires exactly one permit, blocking when none is immediately available.
    void acquire() @safe
    {
        if (tryTakePermit())
            return;

        static if (!Atomic!uint.waitSupported)
        {
            unsupportedAcquire();
        }
        else
        {
            SemaphoreWaiter waiter;

            stateMutex_.lock();

            // A release may have published a permit after the fast-path miss but
            // before slow-path registration. Recheck while registration is
            // serialized and consume that permit instead of sleeping.
            if (tryTakePermit())
            {
                stateMutex_.unlock();
                return;
            }

            registerWaiter(waiter);
            stateMutex_.unlock();

            // The private one-shot wait word closes signal-before-park without a
            // shared wrapping epoch. The signaled-state release update is the
            // publication edge for a directly handed-off permit.
            waitForSignal(waiter);

            // release() holds stateMutex_ through its final access to the waiter
            // node, including notifyOne(). Crossing the mutex here proves that
            // no releaser can still touch this stack node before acquire returns.
            stateMutex_.lock();
            finishWait();
            stateMutex_.unlock();
        }
    }

    /// Attempts to acquire one permit without blocking.
    ///
    /// This path never takes the semaphore's internal mutex and never parks. A
    /// permit reserved for an already queued waiter is not visible here.
    bool tryAcquire() @safe
    {
        return tryTakePermit();
    }

    version (XTB_Checked)
    {
        ~this() @safe
        {
            static if (Atomic!uint.waitSupported)
                require(
                    activeWaiters_ == 0,
                    "cannot destroy a Semaphore while an acquire is active",
                );
        }
    }

private:
    bool tryTakePermit() @safe
    {
        size_t observed = permits_.load(MemoryOrder.relaxed);
        while (observed != 0)
        {
            if (permits_.compareExchangeWeak(
                    observed,
                    observed - 1,
                    MemoryOrder.acquire,
                    MemoryOrder.relaxed,
                ))
                return true;
        }
        return false;
    }

    void addPermits(size_t count) @safe
    {
        size_t observed = permits_.load(MemoryOrder.relaxed);
        while (true)
        {
            if (count > size_t.max - observed)
                semaphoreOverflow();

            if (permits_.compareExchangeWeak(
                    observed,
                    observed + count,
                    MemoryOrder.release,
                    MemoryOrder.relaxed,
                ))
                return;
        }
    }

    static if (Atomic!uint.waitSupported)
    {
        void registerWaiter(ref SemaphoreWaiter waiter) @trusted
        {
            version (XTB_Checked)
                require(
                    permits_.load(MemoryOrder.relaxed) == 0,
                    "Semaphore queued a waiter while a permit was available",
                );

            waiters_.pushBack(&waiter);
            version (XTB_Checked)
                ++activeWaiters_;
        }

        void waitForSignal(ref SemaphoreWaiter waiter) @trusted
        {
            uint expected = waiterQueued;
            if (waiter.state.compareExchangeStrong(
                    expected,
                    waiterParking,
                    MemoryOrder.acquire,
                    MemoryOrder.acquire,
                ))
            {
                waiter.state.wait(waiterParking, MemoryOrder.acquire);
                version (XTB_Checked)
                    require(
                        waiter.state.load(MemoryOrder.relaxed) == waiterSignaled,
                        "Semaphore waiter resumed without a handoff",
                    );
                return;
            }

            version (XTB_Checked)
                require(
                    expected == waiterSignaled,
                    "Semaphore waiter entered an invalid state",
                );
        }

        void signalWaiter(SemaphoreWaiter* waiter) @trusted
        {
            // If the waiter has not yet committed to parking, changing its
            // one-shot state is enough: its CAS will observe the handoff and it
            // will never enter the kernel. Once parking is intended, wake the
            // address after publishing the signaled state.
            const previous = waiter.state.exchange(
                waiterSignaled,
                MemoryOrder.release,
            );
            version (XTB_Checked)
                require(
                    previous == waiterQueued || previous == waiterParking,
                    "Semaphore waiter was signaled more than once",
                );
            if (previous == waiterParking)
                waiter.state.notifyOne();
        }

        void finishWait() @trusted
        {
            version (XTB_Checked)
            {
                require(activeWaiters_ != 0, "Semaphore waiter accounting underflow");
                --activeWaiters_;
            }
        }
    }
}

private noreturn semaphoreOverflow() @trusted
{
    panic("Semaphore permit count overflow");
}

private noreturn unsupportedAcquire() @trusted
{
    panic("Semaphore.acquire requires a supported thread parking backend when no permit is available");
}

static assert(!__traits(isCopyable, Semaphore));

unittest
{
    Semaphore semaphore;
    assert(!semaphore.tryAcquire());

    semaphore.release(0);
    assert(!semaphore.tryAcquire());

    semaphore.release(2);
    assert(semaphore.tryAcquire());
    assert(semaphore.tryAcquire());
    assert(!semaphore.tryAcquire());

    Semaphore initialized = Semaphore(3);
    assert(initialized.tryAcquire());
    assert(initialized.tryAcquire());
    assert(initialized.tryAcquire());
    assert(!initialized.tryAcquire());
}

version (unittest)
{
    static if (Atomic!uint.waitSupported)
    {
        import xtb.threading.thread : Thread, yieldThread;

        private struct WaiterLifetimeContext
        {
            Semaphore* semaphore;
            SemaphoreWaiter* waiter;
            Atomic!uint signalStored;
            Atomic!uint allowWake;
            Atomic!uint barrierPassed;
        }

        private int delayedSemaphoreSignal(WaiterLifetimeContext* context)
        nothrow @nogc
        {
            context.semaphore.stateMutex_.lock();
            if (context.semaphore.waiters_.empty)
            {
                context.semaphore.stateMutex_.unlock();
                return 1;
            }
            SemaphoreWaiter* waiter = context.semaphore.waiters_.popFront();
            if (waiter !is context.waiter)
            {
                context.semaphore.stateMutex_.unlock();
                return 2;
            }

            const previous = waiter.state.exchange(
                waiterSignaled,
                MemoryOrder.release,
            );
            if (previous != waiterParking)
            {
                context.semaphore.stateMutex_.unlock();
                return 3;
            }
            context.signalStored.store(1, MemoryOrder.release);
            context.allowWake.wait(0, MemoryOrder.acquire);
            waiter.state.notifyOne();
            context.semaphore.stateMutex_.unlock();
            return 0;
        }

        private int crossSemaphoreLifetimeBarrier(WaiterLifetimeContext* context)
        nothrow @nogc
        {
            context.semaphore.waitForSignal(*context.waiter);
            context.semaphore.stateMutex_.lock();
            context.semaphore.stateMutex_.unlock();
            context.barrierPassed.store(1, MemoryOrder.release);
            return 0;
        }

        private bool waitForSemaphoreTestFlag(Atomic!uint* value) nothrow @nogc
        {
            foreach (_; 0 .. 100_000)
            {
                if (value.load(MemoryOrder.acquire) != 0)
                    return true;
                yieldThread();
            }
            return false;
        }

        private bool waitForQueuedSemaphoreWaiter(Semaphore* semaphore)
        nothrow @nogc
        {
            foreach (_; 0 .. 100_000)
            {
                semaphore.stateMutex_.lock();
                const queued = !semaphore.waiters_.empty;
                semaphore.stateMutex_.unlock();
                if (queued)
                    return true;
                yieldThread();
            }
            return false;
        }

        private struct StoredPermitPublicationContext
        {
            Semaphore* semaphore;
            Atomic!uint entered;
            Atomic!uint gate;
            int payload;
            int observed;
        }

        private int storedPermitPublicationWorker(
            StoredPermitPublicationContext* context,
        ) nothrow @nogc
        {
            context.entered.store(1, MemoryOrder.release);
            while (context.gate.load(MemoryOrder.relaxed) == 0)
                yieldThread();
            context.semaphore.acquire();
            context.observed = context.payload;
            return 0;
        }

        private struct DirectHandoffPublicationContext
        {
            Semaphore* semaphore;
            int payload;
            int observed;
        }

        private int directHandoffPublicationWorker(
            DirectHandoffPublicationContext* context,
        ) nothrow @nogc
        {
            context.semaphore.acquire();
            context.observed = context.payload;
            return 0;
        }

        unittest
        {
            // Force release to create an unreserved stored permit before the
            // worker is allowed to call acquire. The relaxed gate intentionally
            // contributes no publication edge; the semaphore must publish the
            // payload through permits_.
            Semaphore semaphore;
            StoredPermitPublicationContext context;
            context.semaphore = &semaphore;

            auto started = Thread.start!storedPermitPublicationWorker(&context);
            assert(started.isOk);
            Thread worker = started.unwrap();
            assert(waitForSemaphoreTestFlag(&context.entered));

            context.payload = 0x51ab_29c4;
            semaphore.release();
            context.gate.store(1, MemoryOrder.relaxed);

            assert(worker.join() == 0);
            assert(context.observed == context.payload);
        }

        unittest
        {
            // Force the worker into the intrusive queue before release, so this
            // publication can only travel through the private waiter handoff.
            Semaphore semaphore;
            DirectHandoffPublicationContext context;
            context.semaphore = &semaphore;

            auto started = Thread.start!directHandoffPublicationWorker(&context);
            assert(started.isOk);
            Thread worker = started.unwrap();
            assert(waitForQueuedSemaphoreWaiter(&semaphore));

            context.payload = 0x6c11_8ae3;
            semaphore.release();

            assert(worker.join() == 0);
            assert(context.observed == context.payload);
        }

        unittest
        {
            // tryAcquire must remain a true non-blocking fast path even while a
            // slow-path operation owns the internal mutex.
            Semaphore semaphore = Semaphore(1);
            semaphore.stateMutex_.lock();
            assert(semaphore.tryAcquire());
            assert(!semaphore.tryAcquire());
            semaphore.stateMutex_.unlock();
        }

        unittest
        {
            // Deterministically exercise a release after slow-path registration
            // but before the waiter executes Atomic.wait. The private signal word
            // retains the handoff, so the wake cannot be lost.
            Semaphore semaphore;
            SemaphoreWaiter waiter;

            semaphore.stateMutex_.lock();
            semaphore.registerWaiter(waiter);
            semaphore.stateMutex_.unlock();

            semaphore.release();
            assert(waiter.state.load(MemoryOrder.acquire) == waiterSignaled);
            semaphore.waitForSignal(waiter);

            semaphore.stateMutex_.lock();
            semaphore.finishWait();
            semaphore.stateMutex_.unlock();
            assert(!semaphore.tryAcquire());
        }

        unittest
        {
            // A waiter may observe its release-store before the releaser has
            // executed notifyOne. It still cannot end the stack node lifetime
            // until the releaser's final pointer access is complete.
            Semaphore semaphore;
            SemaphoreWaiter waiter;
            semaphore.stateMutex_.lock();
            semaphore.registerWaiter(waiter);
            semaphore.stateMutex_.unlock();
            waiter.state.store(waiterParking, MemoryOrder.relaxed);

            WaiterLifetimeContext context;
            context.semaphore = &semaphore;
            context.waiter = &waiter;

            auto releaserStarted = Thread.start!delayedSemaphoreSignal(&context);
            assert(releaserStarted.isOk);
            Thread releaser = releaserStarted.unwrap();
            assert(waitForSemaphoreTestFlag(&context.signalStored));

            auto barrierStarted = Thread.start!crossSemaphoreLifetimeBarrier(&context);
            assert(barrierStarted.isOk);
            Thread barrier = barrierStarted.unwrap();

            foreach (_; 0 .. 32)
                yieldThread();
            assert(context.barrierPassed.load(MemoryOrder.acquire) == 0);

            context.allowWake.store(1, MemoryOrder.release);
            context.allowWake.notifyOne();

            assert(releaser.join() == 0);
            assert(barrier.join() == 0);
            assert(context.barrierPassed.load(MemoryOrder.acquire) == 1);

            semaphore.stateMutex_.lock();
            semaphore.finishWait();
            semaphore.stateMutex_.unlock();
        }
    }
    else version (XTB_TestUnsupportedThreadBackend)
    {
        version (Posix)
        {
            import core.stdc.signal : SIGABRT;
            import core.sys.posix.sys.wait : waitpid;
            import core.sys.posix.unistd : _exit, fork;

            private bool unsupportedSemaphoreBlockingAcquireAborts() @system
            {
                const process = fork();
                if (process < 0)
                    return false;
                if (process == 0)
                {
                    Semaphore semaphore;
                    semaphore.acquire();
                    _exit(0);
                }

                int status;
                return waitpid(process, &status, 0) == process &&
                    (status & 0x7f) == SIGABRT;
            }

            unittest
            {
                // Non-blocking functionality remains useful without a parking
                // backend; only an acquire that actually needs to block fails.
                Semaphore semaphore;
                semaphore.release(2);
                assert(semaphore.tryAcquire());
                semaphore.acquire();
                assert(!semaphore.tryAcquire());
                assert(unsupportedSemaphoreBlockingAcquireAborts());
            }
        }
    }
}
