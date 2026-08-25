module xtb.os.time;

nothrow @nogc:

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.duration : Duration;
import xtb.core.types : i64, u64;
import xtb.os.error : OsError;

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

version (linux)
    private import backend = xtb.os.internal.linux.time;
else
    private import backend = xtb.os.internal.unsupported.time;

OsError monotonicNanoseconds(u64* output) @system
{
    version (XTB_Checked)
        require(output !is null, "monotonic clock output pointer is null");
    *output = 0;
    return backend.monotonicNanosecondsImpl(output);
}

OsError wallClockNanoseconds(i64* output) @system
{
    version (XTB_Checked)
        require(output !is null, "wall clock output pointer is null");
    *output = 0;
    return backend.wallClockNanosecondsImpl(output);
}

OsError sleepNanoseconds(u64 duration) @system
{
    return backend.sleepNanosecondsImpl(duration);
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
