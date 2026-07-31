module xtb.math.scalar;

@safe nothrow @nogc:

import core.stdc.math : floorf;
import xtb.core.types : i32;

enum float pi = 3.14159265358979323846f;
enum float tau = 2.0f * pi;
enum float goldenRatio = 1.61803398874989484820f;

pure float min(float a, float b) { return a < b ? a : b; }
pure float max(float a, float b) { return a > b ? a : b; }

pure
float clamp(float value, float lower, float upper)
{
    assert(lower <= upper, "invalid clamp range");
    return value < lower ? lower : value > upper ? upper : value;
}

pure float saturate(float value) { return clamp(value, 0, 1); }
pure float lerp(float a, float b, float t) { return a + (b - a) * t; }

pure
float inverseLerp(float a, float b, float value)
{
    return a == b ? 0 : (value - a) / (b - a);
}

float fract(float value) { return value - floorf(value); }
pure float step(float edge, float value) { return value < edge ? 0 : 1; }
pure float sign(float value) { return value < 0 ? -1 : value > 0 ? 1 : 0; }
pure float radians(float degrees) { return degrees * (pi / 180); }
pure float degrees(float radians_) { return radians_ * (180 / pi); }

pure
float smoothstep(float edge0, float edge1, float value)
{
    const t = saturate(inverseLerp(edge0, edge1, value));
    return t * t * (3 - 2 * t);
}

pure
float smootherstep(float edge0, float edge1, float value)
{
    const t = saturate(inverseLerp(edge0, edge1, value));
    return t * t * t * (t * (t * 6 - 15) + 10);
}


float repeat(float value, float period)
{
    assert(period > 0, "repeat period must be positive");
    return value - floorf(value / period) * period;
}

pure
i32 repeat(i32 value, i32 period)
{
    assert(period > 0, "repeat period must be positive");
    const remainder = value % period;
    return remainder < 0 ? remainder + period : remainder;
}


float pingPong(float value, float length)
{
    assert(length > 0, "ping-pong length must be positive");
    const folded = repeat(value, 2 * length);
    return length - (folded > length ? folded - length : length - folded);
}

unittest
{
    assert(fract(2.25f) == 0.25f);
    assert(repeat(-1, 4) == 3);
    assert(repeat(-0.25f, 1) == 0.75f);
    assert(pingPong(1.25f, 1) == 0.75f);
    assert(smoothstep(0, 1, 0.5f) == 0.5f);
    assert(smootherstep(0, 1, 0.5f) == 0.5f);
}
