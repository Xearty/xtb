module xtb.time;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.duration : Duration, durationNanoseconds = nanoseconds;
import xtb.os.error : OsError;
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

    static OsError now(Timestamp* output) @system
    {
        version (XTB_Checked)
            require(output !is null, "timestamp output pointer is null");

        *output = Timestamp.init;
        i64 value;
        const error = wallClockNanoseconds(&value);
        if (error.failed)
            return error;

        output.nanoseconds_ = value;
        return OsError.init;
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

    static OsError now(Instant* output) @system
    {
        version (XTB_Checked)
            require(output !is null, "instant output pointer is null");

        *output = Instant.init;
        u64 value;
        const error = monotonicNanoseconds(&value);
        if (error.failed)
            return error;

        output.nanoseconds_ = value;
        return OsError.init;
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

    Timestamp timestamp;
    assert(Timestamp.now(&timestamp).succeeded);
    assert(timestamp.nanosecondsSinceUnixEpoch != 0);

    Instant before;
    Instant after;
    assert(Instant.now(&before).succeeded);
    assert(sleepNanoseconds(1_000_000).succeeded);
    assert(Instant.now(&after).succeeded);
    assert(after >= before);
    assert(after.since(before).totalNanoseconds <= after.nanoseconds);
}
