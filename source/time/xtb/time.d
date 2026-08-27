module xtb.time;

nothrow @nogc:

import xtb.panic : panic;
version (XTB_Checked) import xtb.panic : require;
import xtb.duration : Duration, durationNanoseconds = nanoseconds;
import xtb.os.time : monotonicNanoseconds, wallClockNanoseconds;
import xtb.types : i64, u64;

/// A wall-clock timestamp represented as nanoseconds since the Unix epoch.
///
/// Wall-clock time can move forwards or backwards when the system clock is
/// adjusted. Use `Instant` for measuring elapsed time.
struct Timestamp
{
nothrow @nogc:

    private i64 nanoseconds_;

    /// Samples the system wall clock.
    ///
    /// Panics if the platform clock unexpectedly cannot be read.
    static Timestamp now() @trusted
    {
        i64 value;
        if (wallClockNanoseconds(&value).failed)
            panic("failed to read wall clock");
        return Timestamp(value);
    }

    i64 nanosecondsSinceUnixEpoch() const pure @safe
    {
        return nanoseconds_;
    }

    int opCmp(Timestamp other) const pure @safe
    {
        return nanoseconds_ < other.nanoseconds_
            ? -1 : nanoseconds_ > other.nanoseconds_ ? 1 : 0;
    }
}

/// A sample from the system monotonic clock.
///
/// The value has no wall-clock meaning. Compare instants from the same running
/// system and use `since` to measure elapsed time.
struct Instant
{
nothrow @nogc:

    private u64 nanoseconds_;

    /// Samples the system monotonic clock.
    ///
    /// Panics if the platform clock unexpectedly cannot be read.
    static Instant now() @trusted
    {
        u64 value;
        if (monotonicNanoseconds(&value).failed)
            panic("failed to read monotonic clock");
        return Instant(value);
    }

    u64 nanoseconds() const pure @safe
    {
        return nanoseconds_;
    }

    Duration since(Instant earlier) const @safe
    {
        version (XTB_Checked)
            require(earlier.nanoseconds_ <= nanoseconds_, "Instant order is reversed");
        return durationNanoseconds(nanoseconds_ - earlier.nanoseconds_);
    }

    int opCmp(Instant other) const pure @safe
    {
        return nanoseconds_ < other.nanoseconds_
            ? -1 : nanoseconds_ > other.nanoseconds_ ? 1 : 0;
    }
}

static assert(Timestamp.sizeof == i64.sizeof);
static assert(Instant.sizeof == u64.sizeof);
static assert(__traits(isPOD, Timestamp));
static assert(__traits(isPOD, Instant));

unittest
{
    import xtb.os.time : sleepNanoseconds;

    const timestamp = Timestamp.now();
    assert(timestamp.nanosecondsSinceUnixEpoch != 0);

    const before = Instant.now();
    assert(sleepNanoseconds(1_000_000).succeeded);
    const after = Instant.now();
    assert(after >= before);
    assert(after.since(before).totalNanoseconds <= after.nanoseconds);
}
