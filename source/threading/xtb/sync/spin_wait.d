module xtb.sync.spin_wait;

nothrow @nogc:

import core.atomic;
import xtb.thread.thread : yieldThread;

/// Gives the processor a short spin-wait hint without yielding to the scheduler.
///
/// This is not an atomic operation or memory fence. Callers must perform any
/// synchronized condition access separately.
void cpuRelax() pure @safe
{
    core.atomic.pause();
}

/// Adaptive polling helper for conditions without a parking/wakeup protocol.
///
/// Early calls actively spin with exponentially increasing `cpuRelax()` batches.
/// Once the bounded spinning phase is exhausted, every later call yields to the
/// scheduler until `reset()` is called. `SpinWait` never parks and provides no
/// memory ordering of its own.
struct SpinWait
{
nothrow @nogc:

    /// Performs one backoff round.
    void spin() @safe
    {
        spinRound!(cpuRelax, yieldThread)(round_);
    }

    /// Restores the initial round-zero state.
    void reset() pure @safe
    {
        round_ = 0;
    }

private:
    ubyte round_;
}

private enum activeSpinRounds = 7;

private void spinRound(alias relax_, alias yield_)(ref ubyte round)
{
    if (round < activeSpinRounds)
    {
        const pauseCount = 1u << round;
        foreach (_; 0 .. pauseCount)
            relax_();
        ++round;
        return;
    }

    yield_();
    round = activeSpinRounds;
}

unittest
{
    cpuRelax();

    SpinWait spinWait;
    assert(spinWait.round_ == 0);
    spinWait.spin();
    assert(spinWait.round_ == 1);
    spinWait.reset();
    assert(spinWait.round_ == 0);
}

version (unittest)
{
    private uint testRelaxCount;
    private uint testYieldCount;

    private void countRelax() @safe
    {
        ++testRelaxCount;
    }

    private void countYield() @safe
    {
        ++testYieldCount;
    }

    unittest
    {
        testRelaxCount = 0;
        testYieldCount = 0;

        ubyte round;
        static foreach (expectedRelaxCount; [1u, 3u, 7u, 15u, 31u, 63u, 127u])
        {
            spinRound!(countRelax, countYield)(round);
            assert(testRelaxCount == expectedRelaxCount);
            assert(testYieldCount == 0);
        }

        assert(round == activeSpinRounds);

        foreach (_; 0 .. 3)
            spinRound!(countRelax, countYield)(round);

        assert(testRelaxCount == 127);
        assert(testYieldCount == 3);
        assert(round == activeSpinRounds);
    }
}
