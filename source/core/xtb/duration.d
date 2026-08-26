module xtb.duration;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.types : u64;

enum u64 nanosecondsPerMicrosecond = 1_000;
enum u64 nanosecondsPerMillisecond = 1_000_000;
enum u64 nanosecondsPerSecond = 1_000_000_000;
enum u64 nanosecondsPerMinute = 60 * nanosecondsPerSecond;
enum u64 nanosecondsPerHour = 60 * nanosecondsPerMinute;
enum u64 nanosecondsPerDay = 24 * nanosecondsPerHour;

private enum bool isDurationCount(T) =
    is(T == byte) || is(T == short) || is(T == int) || is(T == long) ||
    is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong);

private enum bool isSignedDurationCount(T) =
    is(T == byte) || is(T == short) || is(T == int) || is(T == long);

/// A finite, nonnegative span of time with nanosecond resolution.
struct Duration
{
nothrow @nogc:

    private u64 nanoseconds_;

    /// The largest duration representable by this type.
    enum Duration max = Duration(u64.max);

    bool isZero() const pure @safe
    {
        return nanoseconds_ == 0;
    }

    u64 totalNanoseconds() const pure @safe
    {
        return nanoseconds_;
    }

    u64 wholeMicroseconds() const pure @safe
    {
        return nanoseconds_ / nanosecondsPerMicrosecond;
    }

    u64 wholeMilliseconds() const pure @safe
    {
        return nanoseconds_ / nanosecondsPerMillisecond;
    }

    u64 wholeSeconds() const pure @safe
    {
        return nanoseconds_ / nanosecondsPerSecond;
    }

    u64 wholeMinutes() const pure @safe
    {
        return nanoseconds_ / nanosecondsPerMinute;
    }

    u64 wholeHours() const pure @safe
    {
        return nanoseconds_ / nanosecondsPerHour;
    }

    u64 wholeDays() const pure @safe
    {
        return nanoseconds_ / nanosecondsPerDay;
    }

    int opCmp(Duration other) const pure @safe
    {
        return nanoseconds_ < other.nanoseconds_ ? -1 : nanoseconds_ > other.nanoseconds_ ? 1 : 0;
    }

    Duration opBinary(string operation)(Duration other) const @safe
            if (operation == "+" || operation == "-")
    {
        static if (operation == "+")
        {
            version (XTB_Checked)
                require(
                    other.nanoseconds_ <= u64.max - nanoseconds_,
                    "Duration addition overflow",
                );
            return Duration(nanoseconds_ + other.nanoseconds_);
        }
        else
        {
            version (XTB_Checked)
                require(
                    other.nanoseconds_ <= nanoseconds_,
                    "Duration subtraction underflow",
                );
            return Duration(nanoseconds_ - other.nanoseconds_);
        }
    }

    Duration opBinary(string operation, T)(T value) const @safe
            if ((operation == "*" || operation == "/") && isDurationCount!T)
    {
        static if (isSignedDurationCount!T)
            version (XTB_Checked)
                require(value >= 0, "Duration scale cannot be negative");

        const scale = cast(u64) value;
        static if (operation == "*")
        {
            version (XTB_Checked)
                require(
                    nanoseconds_ == 0 || scale <= u64.max / nanoseconds_,
                    "Duration multiplication overflow",
                );
            return Duration(nanoseconds_ * scale);
        }
        else
        {
            version (XTB_Checked)
                require(scale != 0, "Duration division by zero");
            return Duration(nanoseconds_ / scale);
        }
    }

    Duration opBinaryRight(string operation, T)(T value) const @safe
            if (operation == "*" && isDurationCount!T)
    {
        return this * value;
    }
}

private Duration scaledDuration(T)(T count, u64 scale) @safe if (isDurationCount!T)
{
    static if (isSignedDurationCount!T)
        version (XTB_Checked)
            require(count >= 0, "Duration cannot be negative");

    const value = cast(u64) count;
    version (XTB_Checked)
        require(
            value == 0 || scale <= u64.max / value,
            "Duration unit conversion overflow",
        );
    return Duration(value * scale);
}

Duration nanoseconds(T)(T count) @safe if (isDurationCount!T)
{
    return scaledDuration(count, 1);
}

Duration microseconds(T)(T count) @safe if (isDurationCount!T)
{
    return scaledDuration(count, nanosecondsPerMicrosecond);
}

Duration milliseconds(T)(T count) @safe if (isDurationCount!T)
{
    return scaledDuration(count, nanosecondsPerMillisecond);
}

Duration seconds(T)(T count) @safe if (isDurationCount!T)
{
    return scaledDuration(count, nanosecondsPerSecond);
}

Duration minutes(T)(T count) @safe if (isDurationCount!T)
{
    return scaledDuration(count, nanosecondsPerMinute);
}

Duration hours(T)(T count) @safe if (isDurationCount!T)
{
    return scaledDuration(count, nanosecondsPerHour);
}

Duration days(T)(T count) @safe if (isDurationCount!T)
{
    return scaledDuration(count, nanosecondsPerDay);
}

static assert(Duration.sizeof == u64.sizeof);
static assert(__traits(isPOD, Duration));
static assert(!__traits(compiles, milliseconds(1.5)));
static assert(!__traits(compiles, milliseconds(1) * 1.5));

unittest
{
    assert(Duration.init.isZero);
    assert(Duration.max.totalNanoseconds == u64.max);

    assert(nanoseconds(7).totalNanoseconds == 7);
    assert(microseconds(2).totalNanoseconds == 2_000);
    assert(milliseconds(3).totalNanoseconds == 3_000_000);
    assert(seconds(4).totalNanoseconds == 4_000_000_000);
    assert(minutes(2).wholeSeconds == 120);
    assert(hours(2).wholeMinutes == 120);
    assert(days(2).wholeHours == 48);

    const duration = milliseconds(2_500);
    assert(duration.wholeMicroseconds == 2_500_000);
    assert(duration.wholeMilliseconds == 2_500);
    assert(duration.wholeSeconds == 2);
    assert(duration.wholeMinutes == 0);

    assert(milliseconds(500) < seconds(1));
    assert(seconds(1) == milliseconds(1_000));
    assert(seconds(2) + milliseconds(500) == milliseconds(2_500));
    assert(seconds(2) - milliseconds(500) == milliseconds(1_500));
    assert(milliseconds(250) * 4 == seconds(1));
    assert(4 * milliseconds(250) == seconds(1));
    assert(seconds(1) / 4 == milliseconds(250));

    int signedCount = 5;
    uint unsignedCount = 6;
    assert(milliseconds(signedCount) == milliseconds(5));
    assert(milliseconds(unsignedCount) == milliseconds(6));
    assert(seconds(1) * signedCount == seconds(5));
    assert(unsignedCount * seconds(1) == seconds(6));
}
