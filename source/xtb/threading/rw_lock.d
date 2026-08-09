module xtb.threading.rw_lock;

nothrow @nogc:

import xtb.core.panic : panic;
import xtb.threading.atomic : Atomic, MemoryOrder;
import xtb.threading.thread : currentThreadId, threadIdBits;

version (XTB_Checked) import xtb.core.panic : require;

private enum uint rwLockWriterActive = 1u << 31;
private enum uint rwLockWriterPending = 1u << 30;
private enum uint rwLockReaderMask = rwLockWriterPending - 1;
private enum uint rwLockReaderGate = rwLockWriterActive | rwLockWriterPending;

/// Allocation-free writer-preferring reader/writer lock.
///
/// `RwLock.init` is unlocked. Readers may coexist, while writers exclude every
/// reader and writer. Once a writer queues, later readers wait until queued
/// writers have made progress. The lock is non-recursive in both modes and has
/// no upgrade or downgrade operation.
///
/// Once another thread can access or wait on the lock, its address must remain
/// stable until all such access has ended.
struct RwLock
{
nothrow @nogc:
    @disable this(this);

    // The low bits count readers. The high bits close the reader gate when a
    // writer owns or is waiting for the lock. This is also the parking word.
    private Atomic!uint state_;
    private Atomic!size_t waitingWriters_;

    version (XTB_Checked) private Atomic!ulong writerOwner_;

    /// Acquires shared read ownership, blocking while a writer owns or is
    /// waiting for the lock.
    void lockRead() @safe
    {
        rejectReadWhileOwningWrite();

        uint observed = state_.load(MemoryOrder.relaxed);
        while (true)
        {
            if ((observed & rwLockReaderGate) != 0)
            {
                waitForStateChange(observed);
                observed = state_.load(MemoryOrder.relaxed);
                continue;
            }

            if ((observed & rwLockReaderMask) == rwLockReaderMask)
                rwLockReaderOverflow();

            if (state_.compareExchangeWeak(
                    observed,
                    observed + 1,
                    MemoryOrder.acquire,
                    MemoryOrder.relaxed,
                ))
                return;
        }
    }

    /// Attempts shared read acquisition without parking.
    bool tryLockRead() @safe
    {
        uint observed = state_.load(MemoryOrder.relaxed);
        if ((observed & rwLockReaderGate) != 0)
            return false;
        if ((observed & rwLockReaderMask) == rwLockReaderMask)
            rwLockReaderOverflow();

        return state_.compareExchangeStrong(
            observed,
            observed + 1,
            MemoryOrder.acquire,
            MemoryOrder.relaxed,
        );
    }

    /// Releases one read ownership. An unmatched read unlock is fatal in every
    /// build. Per-reader thread identity is not tracked.
    void unlockRead() @safe
    {
        uint observed = state_.load(MemoryOrder.relaxed);
        while (true)
        {
            const readers = observed & rwLockReaderMask;
            if (readers == 0)
                rwLockReadUnderflow();

            if (state_.compareExchangeWeak(
                    observed,
                    observed - 1,
                    MemoryOrder.acquireRelease,
                    MemoryOrder.relaxed,
                ))
            {
                static if (Atomic!uint.waitSupported)
                    if (readers == 1 &&
                        (observed & rwLockWriterPending) != 0)
                        state_.notifyAll();
                return;
            }
        }
    }

    /// Acquires exclusive write ownership. Publishing writer intent closes the
    /// reader gate before waiting for existing owners to drain.
    void lockWrite() @safe
    {
        rejectWriteWhileOwningWrite();
        registerWaitingWriter();
        cast(void) state_.fetchOr(rwLockWriterPending, MemoryOrder.release);

        uint observed = state_.load(MemoryOrder.relaxed);
        while (true)
        {
            if ((observed & (rwLockWriterActive | rwLockReaderMask)) == 0)
            {
                if (state_.compareExchangeWeak(
                        observed,
                        observed | rwLockWriterActive,
                        MemoryOrder.acquire,
                        MemoryOrder.relaxed,
                    ))
                {
                    const waiting = unregisterWaitingWriter();
                    if (waiting == 0)
                        clearPendingWriterBit();
                    recordWriterOwner();
                    return;
                }
                continue;
            }

            waitForStateChange(observed);
            observed = state_.load(MemoryOrder.relaxed);
        }
    }

    /// Attempts exclusive write acquisition without parking.
    bool tryLockWrite() @safe
    {
        uint expected = 0;
        if (!state_.compareExchangeStrong(
                expected,
                rwLockWriterActive,
                MemoryOrder.acquire,
                MemoryOrder.relaxed,
            ))
            return false;

        recordWriterOwner();
        return true;
    }

    /// Releases exclusive write ownership. Unlocking when no writer is active
    /// is fatal in every build; wrong-thread ownership is checked when enabled.
    void unlockWrite() @safe
    {
        uint observed = state_.load(MemoryOrder.relaxed);
        if ((observed & rwLockWriterActive) == 0)
            rwLockWriteUnderflow();

        version (XTB_Checked)
        {
            require(
                writerOwner_.load(MemoryOrder.relaxed) == currentOwnerBits(),
                "RwLock.unlockWrite requires ownership by the calling thread",
            );
            writerOwner_.store(0, MemoryOrder.relaxed);
        }

        while (true)
        {
            const desired = observed & rwLockWriterPending;
            if (state_.compareExchangeWeak(
                    observed,
                    desired,
                    MemoryOrder.release,
                    MemoryOrder.relaxed,
                ))
            {
                static if (Atomic!uint.waitSupported)
                    state_.notifyAll();
                return;
            }

            if ((observed & rwLockWriterActive) == 0)
                rwLockWriteUnderflow();
        }
    }

    version (XTB_Checked)
    {
        ~this() @safe
        {
            const state = state_.load(MemoryOrder.relaxed);
            const waiting = waitingWriters_.load(MemoryOrder.relaxed);
            require(
                state == 0 && waiting == 0,
                "cannot destroy an owned or contended RwLock",
            );
        }
    }

private:
    void waitForStateChange(uint observed) @safe
    {
        static if (!Atomic!uint.waitSupported)
            unsupportedRwLockContention();
        else
            state_.wait(observed, MemoryOrder.acquire);
    }

    void registerWaitingWriter() @safe
    {
        size_t observed = waitingWriters_.load(MemoryOrder.relaxed);
        while (true)
        {
            if (observed == size_t.max)
                rwLockWriterWaiterOverflow();
            if (waitingWriters_.compareExchangeWeak(
                    observed,
                    observed + 1,
                    MemoryOrder.release,
                    MemoryOrder.relaxed,
                ))
                return;
        }
    }

    size_t unregisterWaitingWriter() @safe
    {
        size_t observed = waitingWriters_.load(MemoryOrder.relaxed);
        while (true)
        {
            if (observed == 0)
                rwLockWriterWaiterUnderflow();
            if (waitingWriters_.compareExchangeWeak(
                    observed,
                    observed - 1,
                    MemoryOrder.relaxed,
                    MemoryOrder.relaxed,
                ))
                return observed - 1;
        }
    }

    void clearPendingWriterBit() @safe
    {
        // Acquire pairs with a racing writer's release fetchOr, which is
        // sequenced after that writer increments waitingWriters_.
        cast(void) state_.fetchAnd(
            ~rwLockWriterPending,
            MemoryOrder.acquireRelease,
        );

        // A new writer may register immediately before or during the clear.
        // Its own fetchOr restores the gate if it registered after this load;
        // otherwise this check restores a bit that the clear raced with.
        if (waitingWriters_.load(MemoryOrder.acquire) != 0)
            cast(void) state_.fetchOr(
                rwLockWriterPending,
                MemoryOrder.release,
            );
    }

    version (XTB_Checked)
    {
        ulong currentOwnerBits() @safe
        {
            return threadIdBits(currentThreadId());
        }

        void rejectReadWhileOwningWrite() @safe
        {
            const owner = writerOwner_.load(MemoryOrder.relaxed);
            require(
                owner == 0 || owner != currentOwnerBits(),
                "RwLock writer cannot recursively acquire a read lock",
            );
        }

        void rejectWriteWhileOwningWrite() @safe
        {
            const owner = writerOwner_.load(MemoryOrder.relaxed);
            require(
                owner == 0 || owner != currentOwnerBits(),
                "recursive RwLock.lockWrite is not allowed",
            );
        }

        void recordWriterOwner() @safe
        {
            writerOwner_.store(currentOwnerBits(), MemoryOrder.relaxed);
        }
    }
    else
    {
        void rejectReadWhileOwningWrite() pure @safe
        {
        }

        void rejectWriteWhileOwningWrite() pure @safe
        {
        }

        void recordWriterOwner() pure @safe
        {
        }
    }
}

private noreturn unsupportedRwLockContention() @trusted
{
    panic("RwLock contention requires a supported thread parking backend");
}

private noreturn rwLockReaderOverflow() @trusted
{
    panic("RwLock active reader count overflow");
}

private noreturn rwLockReadUnderflow() @trusted
{
    panic("RwLock.unlockRead requires active read ownership");
}

private noreturn rwLockWriteUnderflow() @trusted
{
    panic("RwLock.unlockWrite requires active write ownership");
}

private noreturn rwLockWriterWaiterOverflow() @trusted
{
    panic("RwLock waiting writer count overflow");
}

private noreturn rwLockWriterWaiterUnderflow() @trusted
{
    panic("RwLock waiting writer count underflow");
}

static assert(!__traits(isCopyable, RwLock));

unittest
{
    RwLock lock;

    assert(lock.tryLockRead());
    lock.unlockRead();

    lock.lockRead();
    lock.unlockRead();

    assert(lock.tryLockWrite());
    assert(!lock.tryLockRead());
    assert(!lock.tryLockWrite());
    lock.unlockWrite();

    lock.lockWrite();
    lock.unlockWrite();
}

version (unittest)
{
    private enum bool rwLockBlockingSupported = Atomic!uint.waitSupported;

    version (Posix)
    {
        import core.stdc.signal : SIGABRT;
        import core.sys.posix.sys.wait : waitpid;
        import core.sys.posix.unistd : _exit, fork;

        private enum RwLockInternalDeathCase : ubyte
        {
            readerOverflow,
            writerWaiterOverflow,
        }

        private bool rwLockInternalDeathAborts(
            RwLockInternalDeathCase deathCase,
        ) @system
        {
            const process = fork();
            if (process < 0)
                return false;
            if (process == 0)
            {
                final switch (deathCase)
                {
                    case RwLockInternalDeathCase.readerOverflow:
                        RwLock lock;
                        lock.state_.store(
                            rwLockReaderMask,
                            MemoryOrder.relaxed,
                        );
                        lock.lockRead();
                        break;
                    case RwLockInternalDeathCase.writerWaiterOverflow:
                        RwLock lock;
                        lock.waitingWriters_.store(
                            size_t.max,
                            MemoryOrder.relaxed,
                        );
                        lock.lockWrite();
                        break;
                }
                _exit(0);
            }

            int status;
            return waitpid(process, &status, 0) == process &&
                (status & 0x7f) == SIGABRT;
        }

        unittest
        {
            assert(rwLockInternalDeathAborts(
                    RwLockInternalDeathCase.readerOverflow,
            ));
            assert(rwLockInternalDeathAborts(
                    RwLockInternalDeathCase.writerWaiterOverflow,
            ));
        }
    }

    static if (rwLockBlockingSupported)
    {
        import xtb.threading.thread : Thread, yieldThread;

        private struct RwLockReaderContext
        {
            RwLock* lock;
            Atomic!uint* entered;
            Atomic!uint* releaseReaders;
            int* output;
            int value;
        }

        private int holdRwLockRead(RwLockReaderContext* context)
        nothrow @nogc
        {
            context.lock.lockRead();
            *context.output = context.value;
            context.entered.fetchAdd(1, MemoryOrder.release);
            context.entered.notifyAll();
            waitForRwLockValue(context.releaseReaders, 1);
            context.lock.unlockRead();
            return 0;
        }

        private struct RwLockWriterContext
        {
            RwLock* lock;
            Atomic!uint* entered;
            Atomic!uint* releaseWriter;
            int* readerOutputs;
            size_t readerCount;
            Atomic!uint* failed;
            int* payload;
        }

        private int holdRwLockWrite(RwLockWriterContext* context)
        nothrow @nogc
        {
            context.lock.lockWrite();
            foreach (index; 0 .. context.readerCount)
                if (context.readerOutputs[index] != cast(int)(index + 1))
                    context.failed.store(1, MemoryOrder.relaxed);

            context.entered.store(1, MemoryOrder.release);
            context.entered.notifyAll();
            waitForRwLockValue(context.releaseWriter, 1);
            *context.payload = 0x1357_2468;
            context.lock.unlockWrite();
            return 0;
        }

        private struct RwLockLateReaderContext
        {
            RwLock* lock;
            Atomic!uint* entered;
            int* payload;
            int* observed;
        }

        private int enterRwLockReadLate(RwLockLateReaderContext* context)
        nothrow @nogc
        {
            context.lock.lockRead();
            *context.observed = *context.payload;
            context.entered.store(1, MemoryOrder.release);
            context.entered.notifyAll();
            context.lock.unlockRead();
            return 0;
        }

        private struct RwLockStressContext
        {
            RwLock* lock;
            Atomic!uint* activeReaders;
            Atomic!uint* activeWriter;
            Atomic!uint* failed;
            uint rounds;
            int* value;
        }

        private int stressRwLockRead(RwLockStressContext* context)
        nothrow @nogc
        {
            foreach (_; 0 .. context.rounds)
            {
                context.lock.lockRead();
                context.activeReaders.fetchAdd(1, MemoryOrder.relaxed);
                if (context.activeWriter.load(MemoryOrder.acquire) != 0)
                    context.failed.store(1, MemoryOrder.relaxed);
                context.activeReaders.fetchSub(1, MemoryOrder.relaxed);
                context.lock.unlockRead();
            }
            return 0;
        }

        private int stressRwLockWrite(RwLockStressContext* context)
        nothrow @nogc
        {
            foreach (_; 0 .. context.rounds)
            {
                context.lock.lockWrite();
                if (context.activeWriter.exchange(1, MemoryOrder.acquire) != 0)
                    context.failed.store(1, MemoryOrder.relaxed);
                if (context.activeReaders.load(MemoryOrder.relaxed) != 0)
                    context.failed.store(1, MemoryOrder.relaxed);
                ++*context.value;
                if (context.activeReaders.load(MemoryOrder.relaxed) != 0)
                    context.failed.store(1, MemoryOrder.relaxed);
                context.activeWriter.store(0, MemoryOrder.release);
                context.lock.unlockWrite();
            }
            return 0;
        }

        private void waitForRwLockValue(Atomic!uint* value, uint target)
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
            enum readerCount = 6;
            RwLock lock;
            lock.lockRead();

            Atomic!uint readersEntered;
            Atomic!uint releaseReaders;
            int[readerCount] outputs;
            RwLockReaderContext[readerCount] readerContexts;
            Thread[readerCount] readers;
            foreach (index, ref reader; readers)
            {
                readerContexts[index] = RwLockReaderContext(
                    &lock,
                    &readersEntered,
                    &releaseReaders,
                    &outputs[index],
                    cast(int)(index + 1),
                );
                auto started = Thread.start!holdRwLockRead(&readerContexts[index]);
                assert(started.isOk);
                reader = started.unwrap();
            }
            waitForRwLockValue(&readersEntered, readerCount);

            Atomic!uint writerEntered;
            Atomic!uint releaseWriter;
            Atomic!uint failed;
            int payload;
            RwLockWriterContext writerContext = RwLockWriterContext(
                &lock,
                &writerEntered,
                &releaseWriter,
                outputs.ptr,
                readerCount,
                &failed,
                &payload,
            );
            auto writerStarted = Thread.start!holdRwLockWrite(&writerContext);
            assert(writerStarted.isOk);
            Thread writer = writerStarted.unwrap();
            while ((lock.state_.load(MemoryOrder.acquire) &
                    rwLockWriterPending) == 0)
                yieldThread();

            Atomic!uint lateReaderEntered;
            int lateReaderObserved;
            RwLockLateReaderContext lateReaderContext = RwLockLateReaderContext(
                &lock,
                &lateReaderEntered,
                &payload,
                &lateReaderObserved,
            );
            auto lateReaderStarted = Thread.start!enterRwLockReadLate(
                &lateReaderContext,
            );
            assert(lateReaderStarted.isOk);
            Thread lateReader = lateReaderStarted.unwrap();

            foreach (_; 0 .. 64)
                yieldThread();
            assert(lateReaderEntered.load(MemoryOrder.acquire) == 0);

            releaseReaders.store(1, MemoryOrder.release);
            releaseReaders.notifyAll();
            foreach (ref reader; readers)
                assert(reader.join() == 0);
            assert(writerEntered.load(MemoryOrder.acquire) == 0);

            lock.unlockRead();
            waitForRwLockValue(&writerEntered, 1);
            assert(lateReaderEntered.load(MemoryOrder.acquire) == 0);
            releaseWriter.store(1, MemoryOrder.release);
            releaseWriter.notifyOne();

            assert(writer.join() == 0);
            assert(lateReader.join() == 0);
            assert(failed.load(MemoryOrder.relaxed) == 0);
            assert(lateReaderObserved == payload);
        }

        unittest
        {
            enum readerThreadCount = 4;
            enum writerThreadCount = 2;
            enum rounds = 1_024;
            RwLock lock;
            Atomic!uint activeReaders;
            Atomic!uint activeWriter;
            Atomic!uint failed;
            int value;
            RwLockStressContext context = RwLockStressContext(
                &lock,
                &activeReaders,
                &activeWriter,
                &failed,
                rounds,
                &value,
            );

            Thread[readerThreadCount] readers;
            foreach (ref reader; readers)
            {
                auto started = Thread.start!stressRwLockRead(&context);
                assert(started.isOk);
                reader = started.unwrap();
            }

            Thread[writerThreadCount] writers;
            foreach (ref writer; writers)
            {
                auto started = Thread.start!stressRwLockWrite(&context);
                assert(started.isOk);
                writer = started.unwrap();
            }

            foreach (ref reader; readers)
                assert(reader.join() == 0);
            foreach (ref writer; writers)
                assert(writer.join() == 0);
            assert(failed.load(MemoryOrder.relaxed) == 0);
            assert(value == writerThreadCount * rounds);
        }
    }
    else version (XTB_TestUnsupportedThreadBackend)
    {
        version (Posix)
        {
            private bool unsupportedRwLockWaitAborts() @system
            {
                const process = fork();
                if (process < 0)
                    return false;
                if (process == 0)
                {
                    RwLock lock;
                    lock.state_.store(rwLockWriterActive, MemoryOrder.relaxed);
                    lock.lockRead();
                    _exit(0);
                }

                int status;
                return waitpid(process, &status, 0) == process &&
                    (status & 0x7f) == SIGABRT;
            }

            unittest
            {
                RwLock lock;
                assert(lock.tryLockRead());
                lock.unlockRead();
                assert(lock.tryLockWrite());
                assert(!lock.tryLockRead());
                lock.unlockWrite();
                assert(unsupportedRwLockWaitAborts());
            }
        }
    }
}
