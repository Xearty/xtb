module xtb.sync.mutex;

nothrow @nogc:

import xtb.sync.atomic : Atomic, MemoryOrder;
import xtb.sync.spin_wait : cpuRelax;
import xtb.thread.thread : currentThreadId, hardwareConcurrency, threadIdBits;

version (XTB_Checked) import xtb.panic : require;

private enum uint mutexUnlocked = 0;
private enum uint mutexLocked = 1;
private enum uint mutexContended = 2;
private enum uint mutexActiveSpinRounds = 7;

/// Allocation-free non-recursive mutex.
///
/// `Mutex.init` is unlocked. Once a mutex may be accessed or waited on by
/// another thread, its address must remain stable until all such access has
/// finished. The type is therefore non-copyable; moving a published mutex is a
/// programming error even though D cannot diagnose every relocation.
///
/// Acquisition uses acquire ordering and `unlock()` uses release ordering.
/// Under contention the implementation performs a bounded exponential
/// `cpuRelax()` backoff before parking on the internal 32-bit state word. It
/// never scheduler-yields between the active spin phase and parking.
struct Mutex
{
nothrow @nogc:
    @disable this(this);

    private Atomic!uint state_;

    version (XTB_Checked) private Atomic!ulong owner_;

    /// Blocks until the calling thread owns the mutex.
    void lock() @safe
    {
        uint expected = mutexUnlocked;
        if (state_.compareExchangeStrong(
                expected,
                mutexLocked,
                MemoryOrder.acquire,
                MemoryOrder.relaxed,
            ))
        {
            recordOwner();
            return;
        }

        version (XTB_Checked)
            require(
                owner_.load(MemoryOrder.relaxed) != currentOwnerBits(),
                "recursive Mutex.lock is not allowed",
            );

        lockSlow(expected);
        recordOwner();
    }

    /// Attempts to acquire the mutex without blocking.
    ///
    /// Returns `false` when the mutex is already locked, including when the
    /// current thread already owns this non-recursive mutex.
    bool tryLock() @safe
    {
        uint expected = mutexUnlocked;
        if (!state_.compareExchangeStrong(
                expected,
                mutexLocked,
                MemoryOrder.acquire,
                MemoryOrder.relaxed,
            ))
            return false;

        recordOwner();
        return true;
    }

    /// Releases a mutex owned by the calling thread.
    /// Unlocking an already-unlocked mutex is fatal in every build.
    void unlock() @safe
    {
        version (XTB_Checked)
        {
            require(
                state_.load(MemoryOrder.relaxed) != mutexUnlocked,
                "cannot unlock an unlocked Mutex",
            );
            require(
                owner_.load(MemoryOrder.relaxed) == currentOwnerBits(),
                "Mutex.unlock requires ownership by the calling thread",
            );
            owner_.store(0, MemoryOrder.relaxed);
        }

        const previous = state_.exchange(mutexUnlocked, MemoryOrder.release);
        if (previous == mutexUnlocked)
            unlockUnlockedMutex();

        static if (Atomic!uint.waitSupported)
            if (previous == mutexContended)
                state_.notifyOne();
    }

private:
    void lockSlow(uint observed) @safe
    {
        static if (!Atomic!uint.waitSupported)
        {
            unsupportedContention();
        }
        else
        {
            bool contendedObserved = observed == mutexContended;

            const processorCount = hardwareConcurrency();
            if (shouldActivelySpin(processorCount))
            {
                foreach (round; 0 .. mutexActiveSpinRounds)
                {
                    relaxRound!cpuRelax(round);

                    const state = state_.load(MemoryOrder.relaxed);
                    if (state == mutexContended)
                        contendedObserved = true;

                    if (state == mutexUnlocked)
                    {
                        uint expected = mutexUnlocked;
                        uint desired = mutexLocked;
                        if (contendedObserved)
                            desired = mutexContended;
                        if (state_.compareExchangeStrong(
                                expected,
                                desired,
                                MemoryOrder.acquire,
                                MemoryOrder.relaxed,
                            ))
                            return;

                        if (expected == mutexContended)
                            contendedObserved = true;
                    }
                }
            }

            while (true)
            {
                const previous = state_.exchange(
                    mutexContended,
                    MemoryOrder.acquire,
                );
                if (previous == mutexUnlocked)
                    return;

                state_.wait(mutexContended, MemoryOrder.relaxed);
            }
        }
    }

    version (XTB_Checked)
    {
        ulong currentOwnerBits() @safe
        {
            return threadIdBits(currentThreadId());
        }

        void recordOwner() @safe
        {
            owner_.store(currentOwnerBits(), MemoryOrder.relaxed);
        }
    }
    else
    {
        void recordOwner() pure @safe
        {
        }
    }
}

private bool shouldActivelySpin(uint processorCount) pure @safe
{
    return processorCount > 1;
}

private void relaxRound(alias relax_)(uint round)
{
    const pauseCount = 1u << round;
    foreach (_; 0 .. pauseCount)
        relax_();
}

private noreturn unsupportedContention() @trusted
{
    import xtb.panic : panic;

    panic("Mutex contention requires a supported thread parking backend");
}

private noreturn unlockUnlockedMutex() @trusted
{
    import xtb.panic : panic;

    panic("cannot unlock an unlocked Mutex");
}

static assert(!__traits(isCopyable, Mutex));
version (XTB_Checked)
    static assert(Mutex.sizeof >= Atomic!uint.sizeof + Atomic!ulong.sizeof);
else
    static assert(Mutex.sizeof == Atomic!uint.sizeof);

unittest
{
    Mutex mutex;

    assert(mutex.tryLock());
    assert(!mutex.tryLock());
    mutex.unlock();

    mutex.lock();
    mutex.unlock();
}

version (unittest)
{
    private uint testRelaxCount;

    private void countRelax() @safe
    {
        ++testRelaxCount;
    }

    unittest
    {
        assert(!shouldActivelySpin(0));
        assert(!shouldActivelySpin(1));
        assert(shouldActivelySpin(2));

        testRelaxCount = 0;
        foreach (round; 0 .. mutexActiveSpinRounds)
            relaxRound!countRelax(round);
        assert(testRelaxCount == 127);
    }
}
