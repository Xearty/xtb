module xtb.os.time;

nothrow @nogc:

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.duration : Duration;
import xtb.core.types : i64, u64;
import xtb.os.error : OsError, OsErrorKind, lastError, unsupported;

enum TimeoutKind : ubyte
{
    infinite,
    immediate,
    finite,
}

struct Timeout
{
nothrow @nogc:

    private TimeoutKind kind_;
    private Duration duration_;

    static Timeout infinite() pure @safe
    {
        return Timeout.init;
    }

    static Timeout immediate() pure @safe
    {
        return Timeout(TimeoutKind.immediate, Duration.init);
    }

    static Timeout after(Duration duration) pure @safe
    {
        return duration.isZero
            ? immediate() : Timeout(TimeoutKind.finite, duration);
    }

    TimeoutKind kind() const pure @safe
    {
        return kind_;
    }

    bool isInfinite() const pure @safe
    {
        return kind_ == TimeoutKind.infinite;
    }

    bool isImmediate() const pure @safe
    {
        return kind_ == TimeoutKind.immediate;
    }

    bool isFinite() const pure @safe
    {
        return kind_ == TimeoutKind.finite;
    }

    Duration duration() const @safe
    {
        version (XTB_Checked)
            require(isFinite, "non-finite Timeout has no duration");
        return duration_;
    }
}

OsError monotonicNanoseconds(u64* output) @system
{
    version (XTB_Checked)
        require(output !is null, "monotonic clock output pointer is null");
    *output = 0;
    version (linux)
    {
        import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;

        timespec value;
        if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
            return lastError();
        *output = cast(u64) value.tv_sec * 1_000_000_000UL + value.tv_nsec;
        return OsError.init;
    }
    else
        return unsupported();
}

OsError wallClockNanoseconds(i64* output) @system
{
    version (XTB_Checked)
        require(output !is null, "wall clock output pointer is null");
    *output = 0;
    version (linux)
    {
        import core.sys.posix.time : CLOCK_REALTIME, clock_gettime, timespec;

        timespec value;
        if (clock_gettime(CLOCK_REALTIME, &value) != 0)
            return lastError();
        const seconds = cast(i64) value.tv_sec;
        enum i64 nanosecondsPerSecond = 1_000_000_000L;
        if (seconds < i64.min / nanosecondsPerSecond ||
            seconds > i64.max / nanosecondsPerSecond)
            return OsError(OsErrorKind.invalidArgument, 0);
        *output = seconds * nanosecondsPerSecond + cast(i64) value.tv_nsec;
        return OsError.init;
    }
    else
        return unsupported();
}

OsError sleepNanoseconds(u64 duration) @system
{
    version (linux)
    {
        import core.stdc.errno : EINTR, errno;
        import core.sys.posix.time : nanosleep, timespec;

        timespec remaining;
        remaining.tv_sec = cast(typeof(remaining.tv_sec))(duration / 1_000_000_000UL);
        remaining.tv_nsec = cast(typeof(remaining.tv_nsec))(duration % 1_000_000_000UL);
        for (;;)
        {
            timespec next;
            if (nanosleep(&remaining, &next) == 0)
                return OsError.init;
            if (errno != EINTR)
                return lastError();
            remaining = next;
        }
    }
    else
        return unsupported();
}

unittest
{
    import xtb.core.duration : milliseconds;

    assert(Timeout.init.isInfinite);
    assert(Timeout.infinite.isInfinite);
    assert(Timeout.immediate.isImmediate);
    assert(Timeout.after(Duration.init).isImmediate);
    const finite = Timeout.after(milliseconds(250));
    assert(finite.isFinite && finite.duration == milliseconds(250));
}
