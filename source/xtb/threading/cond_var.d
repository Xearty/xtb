module xtb.threading.cond_var;

nothrow @nogc:

import xtb.core.intrusive_list : ForwardListHook, IntrusiveQueue;
import xtb.core.panic : panic;
import xtb.threading.atomic : Atomic, MemoryOrder;
import xtb.threading.mutex : Mutex;

version (XTB_Checked) import xtb.core.panic : require;

private struct Waiter
{
    Atomic!uint signaled;
    ForwardListHook!Waiter queueHook;
}

/// Allocation-free condition variable.
///
/// `CondVar.init` is ready for use. Waiters must always test their predicate in
/// a loop because the API permits spurious wakeups. All concurrent waiters on a
/// CondVar must use the same predicate mutex in v1.
///
/// The type is non-copyable. Once another thread may access or wait on it, its
/// address must remain stable until all such access has finished.
struct CondVar
{
nothrow @nogc:
    @disable this(this);

    static if (Atomic!uint.waitSupported)
    {
        // Serializes waiter registration/removal and closes the
        // register-before-unlock lost-wakeup window.
        private Mutex stateMutex_;
        private IntrusiveQueue!(Waiter, "queueHook") waiters_;

        version (XTB_Checked)
        {
            private size_t associatedMutexAddress_;
            private size_t activeWaiters_;
        }
    }

    /// Releases `mutex`, waits for notification, then reacquires `mutex` before
    /// returning. The calling thread must own `mutex`.
    ///
    /// Always use this operation in a predicate loop. V1 requires every
    /// concurrent waiter on one CondVar to use the same mutex.
    void wait(ref Mutex mutex) @safe
    {
        static if (!Atomic!uint.waitSupported)
        {
            unsupportedWait();
        }
        else
        {
            Waiter waiter;

            stateMutex_.lock();
            registerWaiter(waiter, mutex);

            // Registration is visible while the predicate mutex is still held.
            // Keeping stateMutex_ locked across this unlock is the commit point:
            // a notifier orders either before registration or after the release.
            mutex.unlock();
            stateMutex_.unlock();

            // Atomic.wait closes the ordinary signal-before-park race. Each wait
            // call owns a unique stack-backed wait word, so there is no shared
            // generation counter or finite-width reuse ABA to account for.
            waiter.signaled.wait(0, MemoryOrder.relaxed);

            mutex.lock();

            // A notifier keeps stateMutex_ locked through its final access to a
            // waiter node, including the wake call. Taking the lock here after
            // waking therefore proves no notifier can still touch this stack
            // node before wait() returns and its lifetime ends.
            stateMutex_.lock();
            finishWait(mutex);
            stateMutex_.unlock();
        }
    }

    /// Makes one registered waiter able to complete its wait.
    ///
    /// V1 chooses the oldest registered waiter, but FIFO scheduling is not part
    /// of the public contract: the awakened thread must still reacquire the
    /// predicate mutex before `wait` returns.
    void notifyOne() @safe
    {
        static if (!Atomic!uint.waitSupported)
        {
            // No supported waiter can exist, so notification is a harmless no-op.
            return;
        }
        else
        {
            stateMutex_.lock();
            Waiter* waiter = popWaiter();
            if (waiter !is null)
                signalWaiter(waiter);
            stateMutex_.unlock();
        }
    }

    /// Makes every waiter registered before this notification's serialized
    /// snapshot able to complete. Later waiters are not affected.
    void notifyAll() @safe
    {
        static if (!Atomic!uint.waitSupported)
        {
            return;
        }
        else
        {
            stateMutex_.lock();

            signalAllWaiters();
            stateMutex_.unlock();
        }
    }

private:
    static if (Atomic!uint.waitSupported)
    {
        void registerWaiter(ref Waiter waiter, ref Mutex mutex) @trusted
        {
            waiters_.pushBack(&waiter);

            version (XTB_Checked)
            {
                const address = mutexAddress(mutex);
                if (activeWaiters_ == 0)
                    associatedMutexAddress_ = address;
                else
                    require(
                        associatedMutexAddress_ == address,
                        "all concurrent CondVar waiters must use the same Mutex",
                    );
                ++activeWaiters_;
            }
        }

        Waiter* popWaiter() @trusted
        {
            if (waiters_.empty)
                return null;
            return waiters_.popFront();
        }

        void signalWaiter(Waiter* waiter) @trusted
        {
            // stateMutex_ remains held through notifyOne(). A waiter that
            // observes this store can make progress immediately, but it cannot
            // leave wait() and destroy its stack node until it later acquires
            // stateMutex_, which can happen only after this final pointer use.
            waiter.signaled.store(1, MemoryOrder.relaxed);
            waiter.signaled.notifyOne();
        }

        void signalAllWaiters() @trusted
        {
            // Registration is serialized by stateMutex_, so draining the current
            // queue selects exactly the waiter population present at this broadcast.
            // Later waiters can only enqueue after stateMutex_ is released.
            while (!waiters_.empty)
                signalWaiter(waiters_.popFront());
        }

        void finishWait(ref Mutex mutex) @trusted
        {
            version (XTB_Checked)
            {
                require(activeWaiters_ != 0, "CondVar waiter accounting underflow");
                require(
                    associatedMutexAddress_ == mutexAddress(mutex),
                    "CondVar waiter mutex association changed unexpectedly",
                );
                --activeWaiters_;
                if (activeWaiters_ == 0)
                    associatedMutexAddress_ = 0;
            }
        }

        version (XTB_Checked)
        {
            size_t mutexAddress(ref Mutex mutex) @trusted
            {
                return cast(size_t)&mutex;
            }
        }
    }
}

private noreturn unsupportedWait() @trusted
{
    panic("CondVar.wait requires a supported thread parking backend");
}

static assert(!__traits(isCopyable, CondVar));

unittest
{
    CondVar condition;
    condition.notifyOne();
    condition.notifyAll();
}

version (unittest)
{
    static if (Atomic!uint.waitSupported)
    {
        import xtb.threading.thread : Thread, yieldThread;

        private struct WaiterLifetimeContext
        {
            CondVar* condition;
            Waiter* waiter;
            Atomic!uint signalStored;
            Atomic!uint allowWake;
            Atomic!uint barrierPassed;
        }

        private int delayedWaiterSignal(WaiterLifetimeContext* context) nothrow @nogc
        {
            context.condition.stateMutex_.lock();
            Waiter* waiter = context.condition.popWaiter();
            if (waiter !is context.waiter)
                return 1;

            waiter.signaled.store(1, MemoryOrder.relaxed);
            context.signalStored.store(1, MemoryOrder.release);
            context.allowWake.wait(0, MemoryOrder.acquire);
            waiter.signaled.notifyOne();
            context.condition.stateMutex_.unlock();
            return 0;
        }

        private int crossWaiterLifetimeBarrier(
            WaiterLifetimeContext* context,
        ) nothrow @nogc
        {
            context.waiter.signaled.wait(0, MemoryOrder.relaxed);
            context.condition.stateMutex_.lock();
            context.condition.stateMutex_.unlock();
            context.barrierPassed.store(1, MemoryOrder.release);
            return 0;
        }

        private bool waitForTestFlag(Atomic!uint* value) nothrow @nogc
        {
            foreach (_; 0 .. 100_000)
            {
                if (value.load(MemoryOrder.acquire) != 0)
                    return true;
                yieldThread();
            }
            return false;
        }

        unittest
        {
            // Deterministically exercise notification after registration but
            // before the waiter enters Atomic.wait. The signal is retained in
            // this wait call's private word and cannot be lost.
            CondVar condition;
            Mutex mutex;
            Waiter waiter;

            mutex.lock();
            condition.stateMutex_.lock();
            condition.registerWaiter(waiter, mutex);
            mutex.unlock();
            condition.stateMutex_.unlock();

            condition.notifyOne();
            assert(waiter.signaled.load(MemoryOrder.relaxed) == 1);
            waiter.signaled.wait(0, MemoryOrder.relaxed);

            mutex.lock();
            condition.stateMutex_.lock();
            condition.finishWait(mutex);
            condition.stateMutex_.unlock();
            mutex.unlock();
        }

        unittest
        {
            // A waiter may observe its signal before the notifier has executed
            // the wake syscall. It must not be allowed to end the stack node's
            // lifetime until the notifier has completed its final node access.
            CondVar condition;
            Waiter waiter;
            condition.stateMutex_.lock();
            condition.waiters_.pushBack(&waiter);
            condition.stateMutex_.unlock();

            WaiterLifetimeContext context;
            context.condition = &condition;
            context.waiter = &waiter;

            auto notifierStarted = Thread.start!delayedWaiterSignal(&context);
            assert(notifierStarted.isOk);
            Thread notifier = notifierStarted.unwrap();
            assert(waitForTestFlag(&context.signalStored));

            auto barrierStarted = Thread.start!crossWaiterLifetimeBarrier(&context);
            assert(barrierStarted.isOk);
            Thread barrier = barrierStarted.unwrap();

            foreach (_; 0 .. 32)
                yieldThread();
            assert(context.barrierPassed.load(MemoryOrder.acquire) == 0);

            context.allowWake.store(1, MemoryOrder.release);
            context.allowWake.notifyOne();

            assert(notifier.join() == 0);
            assert(barrier.join() == 0);
            assert(context.barrierPassed.load(MemoryOrder.acquire) == 1);
        }
    }
    else version (XTB_TestUnsupportedThreadBackend)
    {
        version (Posix)
        {
            import core.stdc.signal : SIGABRT;
            import core.sys.posix.sys.wait : waitpid;
            import core.sys.posix.unistd : _exit, fork;

            private bool unsupportedCondVarWaitAborts() @system
            {
                const process = fork();
                if (process < 0)
                    return false;
                if (process == 0)
                {
                    CondVar condition;
                    Mutex mutex;
                    condition.wait(mutex);
                    _exit(0);
                }

                int status;
                return waitpid(process, &status, 0) == process &&
                    (status & 0x7f) == SIGABRT;
            }

            unittest
            {
                assert(unsupportedCondVarWaitAborts());
            }
        }
    }
}
