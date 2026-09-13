module xtb.math.scalar;

nothrow @nogc @safe:

import core.stdc.math;

import xtb.panic;
import xtb.types;

enum f32 pi = 3.14159265358979323846f;
enum f32 tau = 2.0f * pi;
enum f32 golden_ratio = 1.61803398874989484820f;

/// Returns the sine of `angle`, in radians.
f32 sin(f32 angle) pure
{
    return sinf(angle);
}

/// Returns the cosine of `angle`, in radians.
f32 cos(f32 angle) pure
{
    return cosf(angle);
}

/// Returns the tangent of `angle`, in radians.
f32 tan(f32 angle) pure
{
    return tanf(angle);
}

/// Returns the inverse sine of `value`, in radians.
f32 asin(f32 value)
{
    return asinf(value);
}

/// Returns the inverse cosine of `value`, in radians.
f32 acos(f32 value)
{
    return acosf(value);
}

/// Returns the inverse tangent of `value`, in radians.
f32 atan(f32 value) pure
{
    return atanf(value);
}

/// Returns the angle of `(x, y)`, in radians.
f32 atan2(f32 y, f32 x)
{
    return atan2f(y, x);
}

f32 sqrt(f32 value)
{
    return sqrtf(value);
}

f32 abs(f32 value) pure
{
    return fabsf(value);
}

f32 floor(f32 value) pure
{
    return floorf(value);
}

f32 ceil(f32 value) pure
{
    return ceilf(value);
}

f32 round(f32 value) pure
{
    return roundf(value);
}

f32 trunc(f32 value) pure
{
    return truncf(value);
}

f32 min(f32 a, f32 b) pure
{
    return a < b ? a : b;
}

f32 max(f32 a, f32 b) pure
{
    return a > b ? a : b;
}

f32 clamp(f32 value, f32 lower, f32 upper)
{
    require(lower <= upper, "invalid clamp range");
    return value < lower ? lower : value > upper ? upper : value;
}

f32 saturate(f32 value)
{
    return clamp(value, 0, 1);
}

f32 lerp(f32 a, f32 b, f32 t) pure
{
    return a + (b - a) * t;
}

f32 inverse_lerp(f32 a, f32 b, f32 value) pure
{
    return a == b ? 0 : (value - a) / (b - a);
}

f32 remap(f32 value, f32 input_lower, f32 input_upper, f32 output_lower, f32 output_upper) pure
{
    return lerp(output_lower, output_upper, inverse_lerp(input_lower, input_upper, value));
}

f32 fract(f32 value) pure
{
    return value - floor(value);
}

f32 step(f32 edge, f32 value) pure
{
    return value < edge ? 0 : 1;
}

f32 sign(f32 value) pure
{
    return value < 0 ? -1 : value > 0 ? 1 : 0;
}

f32 move_towards(f32 current, f32 target, f32 max_delta)
{
    require(max_delta >= 0 && max_delta.is_finite, "maximum delta must be nonnegative and finite");

    const delta = target - current;
    if (abs(delta) <= max_delta) return target;

    return current + sign(delta) * max_delta;
}

f32 radians(f32 angle_degrees) pure
{
    return angle_degrees * (pi / 180);
}

f32 degrees(f32 angle_radians) pure
{
    return angle_radians * (180 / pi);
}

/// Wraps a radian angle to the half-open range `[-pi, pi)`.
f32 wrap_angle(f32 angle)
{
    return repeat(angle + pi, tau) - pi;
}

/// Returns the shortest signed radian angle from `from` to `to`.
f32 angle_difference(f32 from, f32 to)
{
    return wrap_angle(to - from);
}

/// Interpolates along the shortest radian arc from `a` to `b`.
f32 lerp_angle(f32 a, f32 b, f32 t)
{
    return a + angle_difference(a, b) * t;
}

bool is_nan(f32 value) pure
{
    return value != value;
}

bool is_finite(f32 value) pure
{
    return value == value && value >= -f32.max && value <= f32.max;
}

bool is_infinite(f32 value) pure
{
    return !value.is_nan && !value.is_finite;
}

bool approximately_equal(f32 a, f32 b, f32 absolute_tolerance, f32 relative_tolerance)
{
    require(
        absolute_tolerance >= 0 && absolute_tolerance.is_finite,
        "absolute tolerance must be nonnegative and finite",
    );
    require(
        relative_tolerance >= 0 && relative_tolerance.is_finite,
        "relative tolerance must be nonnegative and finite",
    );

    if (a == b) return true;
    if (!a.is_finite || !b.is_finite) return false;

    const difference = abs(a - b);
    const scale = max(abs(a), abs(b));
    return difference <= max(absolute_tolerance, relative_tolerance * scale);
}

f32 smoothstep(f32 edge_0, f32 edge_1, f32 value)
{
    const t = saturate(inverse_lerp(edge_0, edge_1, value));
    return t * t * (3 - 2 * t);
}

f32 smootherstep(f32 edge_0, f32 edge_1, f32 value)
{
    const t = saturate(inverse_lerp(edge_0, edge_1, value));
    return t * t * t * (t * (t * 6 - 15) + 10);
}

f32 repeat(f32 value, f32 period)
{
    require(period > 0 && period.is_finite, "repeat period must be positive and finite");
    return value - floor(value / period) * period;
}

i32 repeat(i32 value, i32 period)
{
    require(period > 0, "repeat period must be positive");
    const remainder = value % period;
    return remainder < 0 ? remainder + period : remainder;
}

f32 ping_pong(f32 value, f32 length)
{
    require(length > 0 && length.is_finite, "ping-pong length must be positive and finite");
    const folded = repeat(value, 2 * length);
    return length - (folded > length ? folded - length : length - folded);
}

unittest
{
    assert(approximately_equal(sin(pi / 2), 1, 1e-6f, 1e-6f));
    assert(approximately_equal(cos(pi), -1, 1e-6f, 1e-6f));
    assert(approximately_equal(tan(pi / 4), 1, 1e-6f, 1e-6f));
    assert(approximately_equal(asin(1), pi / 2, 1e-6f, 1e-6f));
    assert(approximately_equal(acos(0), pi / 2, 1e-6f, 1e-6f));
    assert(approximately_equal(atan(1), pi / 4, 1e-6f, 1e-6f));
    assert(approximately_equal(atan2(1, 0), pi / 2, 1e-6f, 1e-6f));
}

unittest
{
    assert(sqrt(9) == 3);
    assert(abs(-3) == 3);
    assert(floor(-1.25f) == -2);
    assert(ceil(-1.25f) == -1);
    assert(round(1.5f) == 2);
    assert(round(-1.5f) == -2);
    assert(trunc(-1.75f) == -1);
}

unittest
{
    assert(f32.nan.is_nan);
    assert(!1.0f.is_nan);
    assert(f32.infinity.is_infinite);
    assert((-f32.infinity).is_infinite);
    assert(!f32.nan.is_infinite);
    assert(1.0f.is_finite);
    assert(!f32.infinity.is_finite);
}

unittest
{
    assert(approximately_equal(1, 1, 0, 0));
    assert(approximately_equal(1.0f, 1.000_001f, 1e-5f, 0));
    assert(approximately_equal(1_000_000.0f, 1_000_001.0f, 0, 1e-5f));
    assert(!approximately_equal(1, 1.1f, 1e-5f, 1e-5f));
    assert(!approximately_equal(f32.nan, f32.nan, 1e-5f, 1e-5f));
    assert(approximately_equal(f32.infinity, f32.infinity, 0, 0));
}

unittest
{
    assert(remap(0.5f, 0, 1, 10, 20) == 15);
    assert(move_towards(0, 10, 3) == 3);
    assert(move_towards(9, 10, 3) == 10);
}

unittest
{
    assert(wrap_angle(pi) == -pi);
    assert(wrap_angle(-pi) == -pi);
    assert(approximately_equal(angle_difference(3 * pi / 4, -3 * pi / 4), pi / 2, 1e-6f, 1e-6f));
    assert(approximately_equal(lerp_angle(3 * pi / 4, -3 * pi / 4, 0.5f), pi, 1e-6f, 1e-6f));
}

unittest
{
    assert(fract(2.25f) == 0.25f);
    assert(repeat(-1, 4) == 3);
    assert(repeat(-0.25f, 1) == 0.75f);
    assert(ping_pong(1.25f, 1) == 0.75f);
    assert(smoothstep(0, 1, 0.5f) == 0.5f);
    assert(smootherstep(0, 1, 0.5f) == 0.5f);
}
