module xtb.threading.internal.countdown;

nothrow @nogc:

import xtb.core.panic : panic;
import xtb.threading.atomic : Atomic, MemoryOrder;

/// Package-private one-shot countdown state with a full-width logical count.
///
/// The separate 32-bit wake epoch lets public countdown primitives retain the
/// full `size_t` range even when the parking backend only waits on 32-bit words.
package(xtb.threading) struct CountdownState
{
nothrow @nogc:
    @disable this(this);

    private Atomic!size_t count_;
    private Atomic!uint wakeEpoch_;

    package(xtb.threading) void initialize(size_t count) @safe
    {
        count_.store(count, MemoryOrder.relaxed);
    }

    package(xtb.threading) void countDown(size_t count) @safe
    {
        if (count == 0)
            return;

        size_t observed = count_.load(MemoryOrder.relaxed);
        while (true)
        {
            if (count > observed)
                countdownUnderflow();

            const desired = observed - count;
            if (count_.compareExchangeWeak(
                    observed,
                    desired,
                    MemoryOrder.release,
                    MemoryOrder.relaxed,
                ))
            {
                if (desired == 0)
                {
                    static if (Atomic!uint.waitSupported)
                    {
                        cast(void) wakeEpoch_.fetchAdd(1, MemoryOrder.release);
                        wakeEpoch_.notifyAll();
                    }
                }
                return;
            }
        }
    }

    package(xtb.threading) bool tryWait() const @safe
    {
        return count_.load(MemoryOrder.acquire) == 0;
    }

    package(xtb.threading) void wait() const @safe
    {
        while (!tryWait())
        {
            static if (!Atomic!uint.waitSupported)
            {
                unsupportedCountdownWait();
            }
            else
            {
                const epoch = wakeEpoch_.load(MemoryOrder.relaxed);
                if (!tryWait())
                    wakeEpoch_.wait(epoch, MemoryOrder.acquire);
            }
        }
    }
}

private noreturn countdownUnderflow() @trusted
{
    panic("countdown would decrement below zero");
}

private noreturn unsupportedCountdownWait() @trusted
{
    panic("countdown wait requires a supported thread parking backend");
}

static assert(!__traits(isCopyable, CountdownState));
