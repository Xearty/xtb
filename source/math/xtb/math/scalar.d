module xtb.math.scalar;

nothrow @nogc @safe:

import core.stdc.math;

import xtb.panic;
import xtb.types;

enum f32 pi = 3.14159265358979323846f;
enum f32 tau = 2.0f * pi;
enum f32 golden_ratio = 1.61803398874989484820f;

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

f32 fract(f32 value)
{
    return value - floorf(value);
}

f32 step(f32 edge, f32 value) pure
{
    return value < edge ? 0 : 1;
}

f32 sign(f32 value) pure
{
    return value < 0 ? -1 : value > 0 ? 1 : 0;
}

f32 radians(f32 angle_degrees) pure
{
    return angle_degrees * (pi / 180);
}

f32 degrees(f32 angle_radians) pure
{
    return angle_radians * (180 / pi);
}

bool is_finite(f32 value) pure
{
    return value == value && value >= -f32.max && value <= f32.max;
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
    return value - floorf(value / period) * period;
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
    assert(fract(2.25f) == 0.25f);
    assert(repeat(-1, 4) == 3);
    assert(repeat(-0.25f, 1) == 0.75f);
    assert(ping_pong(1.25f, 1) == 0.75f);
    assert(smoothstep(0, 1, 0.5f) == 0.5f);
    assert(smootherstep(0, 1, 0.5f) == 0.5f);
}
