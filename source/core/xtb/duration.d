module xtb.duration;

nothrow @nogc:

import xtb.panic;
import xtb.types;

enum u64 nanoseconds_per_microsecond = 1_000;
enum u64 nanoseconds_per_millisecond = 1_000_000;
enum u64 nanoseconds_per_second = 1_000_000_000;
enum u64 nanoseconds_per_minute = 60 * nanoseconds_per_second;
enum u64 nanoseconds_per_hour = 60 * nanoseconds_per_minute;
enum u64 nanoseconds_per_day = 24 * nanoseconds_per_hour;

private enum bool is_duration_count(T) = is(T == i8)
    || is(T == i16)
    || is(T == i32)
    || is(T == i64)
    || is(T == u8)
    || is(T == u16)
    || is(T == u32)
    || is(T == u64);

private enum bool is_signed_duration_count(T) = is(T == i8)
    || is(T == i16)
    || is(T == i32)
    || is(T == i64);

/// A finite, nonnegative span of time with nanosecond resolution.
///
/// Arithmetic operands and unit counts must produce a representable duration.
/// Signed counts must be nonnegative, and divisors must be nonzero.
struct Duration
{
nothrow @nogc:

    u64 nanoseconds;

    /// The largest duration representable by this type.
    enum Duration max = Duration(u64.max);

    bool is_zero() const pure @safe
    {
        return this.nanoseconds == 0;
    }

    u64 total_nanoseconds() const pure @safe
    {
        return this.nanoseconds;
    }

    u64 whole_microseconds() const pure @safe
    {
        return this.nanoseconds / nanoseconds_per_microsecond;
    }

    u64 whole_milliseconds() const pure @safe
    {
        return this.nanoseconds / nanoseconds_per_millisecond;
    }

    u64 whole_seconds() const pure @safe
    {
        return this.nanoseconds / nanoseconds_per_second;
    }

    u64 whole_minutes() const pure @safe
    {
        return this.nanoseconds / nanoseconds_per_minute;
    }

    u64 whole_hours() const pure @safe
    {
        return this.nanoseconds / nanoseconds_per_hour;
    }

    u64 whole_days() const pure @safe
    {
        return this.nanoseconds / nanoseconds_per_day;
    }

    i32 opCmp(Duration other) const pure @safe
    {
        if (this.nanoseconds < other.nanoseconds) return -1;
        if (this.nanoseconds > other.nanoseconds) return 1;

        return 0;
    }

    Duration opBinary(string operation)(Duration other) const @safe
    if (operation == "+" || operation == "-")
    {
        static if (operation == "+")
        {
            require(
                other.nanoseconds <= u64.max - this.nanoseconds,
                "duration addition overflow",
            );

            return Duration(this.nanoseconds + other.nanoseconds);
        }
        else
        {
            require(
                other.nanoseconds <= this.nanoseconds,
                "duration subtraction underflow",
            );

            return Duration(this.nanoseconds - other.nanoseconds);
        }
    }

    Duration opBinary(string operation, T)(T value) const @safe
    if ((operation == "*" || operation == "/") && is_duration_count!T)
    {
        static if (is_signed_duration_count!T)
            require(value >= 0, "duration scale cannot be negative");

        const scale = cast(u64) value;

        static if (operation == "*")
        {
            require(
                this.nanoseconds == 0 || scale <= u64.max / this.nanoseconds,
                "duration multiplication overflow",
            );

            return Duration(this.nanoseconds * scale);
        }
        else
        {
            require(scale != 0, "duration division by zero");

            return Duration(this.nanoseconds / scale);
        }
    }

    Duration opBinaryRight(string operation, T)(T value) const @safe
    if (operation == "*" && is_duration_count!T)
    {
        return this * value;
    }
}

private Duration scaled_duration(T)(T count, u64 scale) @safe
if (is_duration_count!T)
{
    static if (is_signed_duration_count!T)
        require(count >= 0, "duration cannot be negative");

    const value = cast(u64) count;

    require(
        value == 0 || scale <= u64.max / value,
        "duration unit conversion overflow",
    );

    return Duration(value * scale);
}

Duration nanoseconds(T)(T count) @safe
if (is_duration_count!T)
{
    return scaled_duration(count, 1);
}

Duration microseconds(T)(T count) @safe
if (is_duration_count!T)
{
    return scaled_duration(count, nanoseconds_per_microsecond);
}

Duration milliseconds(T)(T count) @safe
if (is_duration_count!T)
{
    return scaled_duration(count, nanoseconds_per_millisecond);
}

Duration seconds(T)(T count) @safe
if (is_duration_count!T)
{
    return scaled_duration(count, nanoseconds_per_second);
}

Duration minutes(T)(T count) @safe
if (is_duration_count!T)
{
    return scaled_duration(count, nanoseconds_per_minute);
}

Duration hours(T)(T count) @safe
if (is_duration_count!T)
{
    return scaled_duration(count, nanoseconds_per_hour);
}

Duration days(T)(T count) @safe
if (is_duration_count!T)
{
    return scaled_duration(count, nanoseconds_per_day);
}

static assert(Duration.sizeof == u64.sizeof);
static assert(__traits(isPOD, Duration));
static assert(!__traits(compiles, milliseconds(1.5)));
static assert(!__traits(compiles, milliseconds(1) * 1.5));

unittest
{
    assert(Duration.init.is_zero);
    assert(Duration.max.total_nanoseconds == u64.max);

    assert(nanoseconds(7).total_nanoseconds == 7);
    assert(microseconds(2).total_nanoseconds == 2_000);
    assert(milliseconds(3).total_nanoseconds == 3_000_000);
    assert(seconds(4).total_nanoseconds == 4_000_000_000);
    assert(minutes(2).whole_seconds == 120);
    assert(hours(2).whole_minutes == 120);
    assert(days(2).whole_hours == 48);

    const duration = milliseconds(2_500);
    assert(duration.whole_microseconds == 2_500_000);
    assert(duration.whole_milliseconds == 2_500);
    assert(duration.whole_seconds == 2);
    assert(duration.whole_minutes == 0);

    assert(milliseconds(500) < seconds(1));
    assert(seconds(1) == milliseconds(1_000));
    assert(seconds(2) + milliseconds(500) == milliseconds(2_500));
    assert(seconds(2) - milliseconds(500) == milliseconds(1_500));
    assert(milliseconds(250) * 4 == seconds(1));
    assert(4 * milliseconds(250) == seconds(1));
    assert(seconds(1) / 4 == milliseconds(250));

    const i32 signed_count = 5;
    const u32 unsigned_count = 6;
    assert(milliseconds(signed_count) == milliseconds(5));
    assert(milliseconds(unsigned_count) == milliseconds(6));
    assert(seconds(1) * signed_count == seconds(5));
    assert(unsigned_count * seconds(1) == seconds(6));
}
