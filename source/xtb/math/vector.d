module xtb.math.vector;

@safe nothrow @nogc:

import core.stdc.math : acosf, cosf, fabsf, sinf, sqrtf;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.math.scalar : clamp, degrees, isFinite, lerp, max, min, radians;

struct Vector2
{
pure nothrow @safe @nogc:

    float x = 0;
    float y = 0;

    pure Vector2 opUnary(string op : "-")() const
    {
        return Vector2(-x, -y);
    }

    pure Vector2 opBinary(string op : "+")(Vector2 b) const
    {
        return Vector2(x + b.x, y + b.y);
    }

    pure Vector2 opBinary(string op : "-")(Vector2 b) const
    {
        return Vector2(x - b.x, y - b.y);
    }

    pure Vector2 opBinary(string op : "*")(Vector2 b) const
    {
        return Vector2(x * b.x, y * b.y);
    }

    pure Vector2 opBinary(string op : "/")(Vector2 b) const
    {
        return Vector2(x / b.x, y / b.y);
    }

    pure Vector2 opBinary(string op : "*")(float s) const
    {
        return Vector2(x * s, y * s);
    }

    pure Vector2 opBinary(string op : "/")(float s) const
    {
        return Vector2(x / s, y / s);
    }

    pure Vector2 opBinary(string op : "+")(float s) const
    {
        return Vector2(x + s, y + s);
    }

    pure Vector2 opBinary(string op : "-")(float s) const
    {
        return Vector2(x - s, y - s);
    }

    pure Vector2 opBinaryRight(string op : "*")(float s) const
    {
        return this * s;
    }
}

struct Vector3
{
pure nothrow @safe @nogc:

    float x = 0;
    float y = 0;
    float z = 0;

    pure Vector3 opUnary(string op : "-")() const
    {
        return Vector3(-x, -y, -z);
    }

    pure Vector3 opBinary(string op : "+")(Vector3 b) const
    {
        return Vector3(x + b.x, y + b.y, z + b.z);
    }

    pure Vector3 opBinary(string op : "-")(Vector3 b) const
    {
        return Vector3(x - b.x, y - b.y, z - b.z);
    }

    pure Vector3 opBinary(string op : "*")(Vector3 b) const
    {
        return Vector3(x * b.x, y * b.y, z * b.z);
    }

    pure Vector3 opBinary(string op : "/")(Vector3 b) const
    {
        return Vector3(x / b.x, y / b.y, z / b.z);
    }

    pure Vector3 opBinary(string op : "*")(float s) const
    {
        return Vector3(x * s, y * s, z * s);
    }

    pure Vector3 opBinary(string op : "/")(float s) const
    {
        return Vector3(x / s, y / s, z / s);
    }

    pure Vector3 opBinary(string op : "+")(float s) const
    {
        return Vector3(x + s, y + s, z + s);
    }

    pure Vector3 opBinary(string op : "-")(float s) const
    {
        return Vector3(x - s, y - s, z - s);
    }

    pure Vector3 opBinaryRight(string op : "*")(float s) const
    {
        return this * s;
    }
}

struct Vector4
{
pure nothrow @safe @nogc:

    float x = 0;
    float y = 0;
    float z = 0;
    float w = 0;

    pure Vector4 opUnary(string op : "-")() const
    {
        return Vector4(-x, -y, -z, -w);
    }

    pure Vector4 opBinary(string op : "+")(Vector4 b) const
    {
        return Vector4(x + b.x, y + b.y, z + b.z, w + b.w);
    }

    pure Vector4 opBinary(string op : "-")(Vector4 b) const
    {
        return Vector4(x - b.x, y - b.y, z - b.z, w - b.w);
    }

    pure Vector4 opBinary(string op : "*")(Vector4 b) const
    {
        return Vector4(x * b.x, y * b.y, z * b.z, w * b.w);
    }

    pure Vector4 opBinary(string op : "/")(Vector4 b) const
    {
        return Vector4(x / b.x, y / b.y, z / b.z, w / b.w);
    }

    pure Vector4 opBinary(string op : "*")(float s) const
    {
        return Vector4(x * s, y * s, z * s, w * s);
    }

    pure Vector4 opBinary(string op : "/")(float s) const
    {
        return Vector4(x / s, y / s, z / s, w / s);
    }

    pure Vector4 opBinary(string op : "+")(float s) const
    {
        return Vector4(x + s, y + s, z + s, w + s);
    }

    pure Vector4 opBinary(string op : "-")(float s) const
    {
        return Vector4(x - s, y - s, z - s, w - s);
    }

    pure Vector4 opBinaryRight(string op : "*")(float s) const
    {
        return this * s;
    }
}

pure Vector2 xy(Vector3 v)
{
    return Vector2(v.x, v.y);
}

pure Vector2 xy(Vector4 v)
{
    return Vector2(v.x, v.y);
}

pure Vector3 xyz(Vector4 v)
{
    return Vector3(v.x, v.y, v.z);
}

pure Vector3 withZ(Vector2 v, float z)
{
    return Vector3(v.x, v.y, z);
}

pure Vector4 withW(Vector3 v, float w)
{
    return Vector4(v.x, v.y, v.z, w);
}

pure float dot(Vector2 a, Vector2 b)
{
    return a.x * b.x + a.y * b.y;
}

pure float dot(Vector3 a, Vector3 b)
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

pure float dot(Vector4 a, Vector4 b)
{
    return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}

pure Vector3 cross(Vector3 a, Vector3 b)
{
    return Vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

pure float lengthSquared(Vector2 v)
{
    return dot(v, v);
}

pure float lengthSquared(Vector3 v)
{
    return dot(v, v);
}

pure float lengthSquared(Vector4 v)
{
    return dot(v, v);
}

private pure bool finiteComponent(float value)
{
    return value == value && value >= -float.max && value <= float.max;
}

pure bool isFinite(Vector2 v)
{
    return finiteComponent(v.x) && finiteComponent(v.y);
}

pure bool isFinite(Vector3 v)
{
    return finiteComponent(v.x) && finiteComponent(v.y) && finiteComponent(v.z);
}

pure bool isFinite(Vector4 v)
{
    return finiteComponent(v.x) && finiteComponent(v.y) &&
        finiteComponent(v.z) && finiteComponent(v.w);
}

float length(Vector2 v)
{
    if (v.x != v.x || v.y != v.y)
        return float.nan;
    const ax = fabsf(v.x), ay = fabsf(v.y);
    const scale = max(ax, ay);
    if (scale == 0)
        return 0;
    if (scale == float.infinity)
        return float.infinity;
    const x = ax / scale, y = ay / scale;
    return scale * sqrtf(x * x + y * y);
}

float length(Vector3 v)
{
    if (v.x != v.x || v.y != v.y || v.z != v.z)
        return float.nan;
    const ax = fabsf(v.x), ay = fabsf(v.y), az = fabsf(v.z);
    const scale = max(ax, max(ay, az));
    if (scale == 0)
        return 0;
    if (scale == float.infinity)
        return float.infinity;
    const x = ax / scale, y = ay / scale, z = az / scale;
    return scale * sqrtf(x * x + y * y + z * z);
}

float length(Vector4 v)
{
    if (v.x != v.x || v.y != v.y || v.z != v.z || v.w != v.w)
        return float.nan;
    const ax = fabsf(v.x), ay = fabsf(v.y), az = fabsf(v.z), aw = fabsf(v.w);
    const scale = max(max(ax, ay), max(az, aw));
    if (scale == 0)
        return 0;
    if (scale == float.infinity)
        return float.infinity;
    const x = ax / scale, y = ay / scale, z = az / scale, w = aw / scale;
    return scale * sqrtf(x * x + y * y + z * z + w * w);
}

Vector2 normalized(Vector2 v)
{
    if (!v.isFinite)
        return Vector2(float.nan, float.nan);
    const scale = max(fabsf(v.x), fabsf(v.y));
    if (scale == 0)
        return Vector2.init;
    const scaled = v / scale;
    return scaled / sqrtf(dot(scaled, scaled));
}

Vector3 normalized(Vector3 v)
{
    if (!v.isFinite)
        return Vector3(float.nan, float.nan, float.nan);
    const scale = max(fabsf(v.x), max(fabsf(v.y), fabsf(v.z)));
    if (scale == 0)
        return Vector3.init;
    const scaled = v / scale;
    return scaled / sqrtf(dot(scaled, scaled));
}

Vector4 normalized(Vector4 v)
{
    if (!v.isFinite)
        return Vector4(float.nan, float.nan, float.nan, float.nan);
    const scale = max(max(fabsf(v.x), fabsf(v.y)),
        max(fabsf(v.z), fabsf(v.w)));
    if (scale == 0)
        return Vector4.init;
    const scaled = v / scale;
    return scaled / sqrtf(dot(scaled, scaled));
}

pure float distanceSquared(Vector2 a, Vector2 b)
{
    return (a - b).lengthSquared;
}

pure float distanceSquared(Vector3 a, Vector3 b)
{
    return (a - b).lengthSquared;
}

pure float distanceSquared(Vector4 a, Vector4 b)
{
    return (a - b).lengthSquared;
}

float distance(Vector2 a, Vector2 b)
{
    return (a - b).length;
}

float distance(Vector3 a, Vector3 b)
{
    return (a - b).length;
}

float distance(Vector4 a, Vector4 b)
{
    return (a - b).length;
}

float angle(Vector2 a, Vector2 b)
{
    const unitA = a.normalized, unitB = b.normalized;
    return unitA == Vector2.init || unitB == Vector2.init
        ? 0 : acosf(clamp(dot(unitA, unitB), -1, 1));
}

float angle(Vector3 a, Vector3 b)
{
    const unitA = a.normalized, unitB = b.normalized;
    return unitA == Vector3.init || unitB == Vector3.init
        ? 0 : acosf(clamp(dot(unitA, unitB), -1, 1));
}

float projectionLength(Vector2 a, Vector2 onto)
{
    const unit = onto.normalized;
    return unit == Vector2.init ? 0 : dot(a, unit);
}

float projectionLength(Vector3 a, Vector3 onto)
{
    const unit = onto.normalized;
    return unit == Vector3.init ? 0 : dot(a, unit);
}

Vector2 projectedOnto(Vector2 a, Vector2 onto)
{
    const unit = onto.normalized;
    return unit == Vector2.init ? Vector2.init : unit * dot(a, unit);
}

Vector3 projectedOnto(Vector3 a, Vector3 onto)
{
    const unit = onto.normalized;
    return unit == Vector3.init ? Vector3.init : unit * dot(a, unit);
}

Vector2 rejectedFrom(Vector2 a, Vector2 onto)
{
    return a - a.projectedOnto(onto);
}

Vector3 rejectedFrom(Vector3 a, Vector3 onto)
{
    return a - a.projectedOnto(onto);
}

pure Vector2 reflected(Vector2 v, Vector2 unitNormal)
{
    return v - unitNormal * (2 * dot(v, unitNormal));
}

pure Vector3 reflected(Vector3 v, Vector3 unitNormal)
{
    return v - unitNormal * (2 * dot(v, unitNormal));
}

pure Vector2 lerp(Vector2 a, Vector2 b, float t)
{
    return Vector2(lerp(a.x, b.x, t), lerp(a.y, b.y, t));
}

pure Vector3 lerp(Vector3 a, Vector3 b, float t)
{
    return Vector3(lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t));
}

pure Vector4 lerp(Vector4 a, Vector4 b, float t)
{
    return Vector4(lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t), lerp(a.w, b.w, t));
}

pure Vector2 min(Vector2 a, Vector2 b)
{
    return Vector2(min(a.x, b.x), min(a.y, b.y));
}

pure Vector3 min(Vector3 a, Vector3 b)
{
    return Vector3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z));
}

pure Vector4 min(Vector4 a, Vector4 b)
{
    return Vector4(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z), min(a.w, b.w));
}

pure Vector2 max(Vector2 a, Vector2 b)
{
    return Vector2(max(a.x, b.x), max(a.y, b.y));
}

pure Vector3 max(Vector3 a, Vector3 b)
{
    return Vector3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z));
}

pure Vector4 max(Vector4 a, Vector4 b)
{
    return Vector4(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z), max(a.w, b.w));
}

pure Vector2 clamp(Vector2 v, Vector2 lo, Vector2 hi)
{
    return max(lo, min(v, hi));
}

pure Vector3 clamp(Vector3 v, Vector3 lo, Vector3 hi)
{
    return max(lo, min(v, hi));
}

pure Vector4 clamp(Vector4 v, Vector4 lo, Vector4 hi)
{
    return max(lo, min(v, hi));
}

Vector3 directionFromDegrees(float yaw, float pitch)
{
    version (XTB_Checked)
        require(yaw.isFinite && pitch.isFinite,
            "direction angles must be finite");
    const y = radians(yaw), p = radians(pitch);
    return Vector3(sinf(y) * cosf(p), sinf(p), -cosf(y) * cosf(p));
}

static assert(Vector2.sizeof == 2 * float.sizeof);
static assert(Vector3.sizeof == 3 * float.sizeof);
static assert(Vector4.sizeof == 4 * float.sizeof);

unittest
{
    const a = Vector3(1, 2, 3), b = Vector3(4, 5, 6);
    assert(a + b == Vector3(5, 7, 9));
    assert(dot(a, b) == 32);
    assert(cross(Vector3(1, 0, 0), Vector3(0, 1, 0)) == Vector3(0, 0, 1));
    assert(Vector3.init.normalized == Vector3.init);
    assert(Vector3(3, 0, 0).projectedOnto(Vector3(0, 2, 0)) == Vector3.init);
    const huge = float.max;
    const hugeUnit = Vector3(huge, huge, 0).normalized;
    assert(hugeUnit.length > 0.9999f && hugeUnit.length < 1.0001f);
    const tinyUnit = Vector3(1e-30f, -1e-30f, 0).normalized;
    assert(tinyUnit.length > 0.9999f && tinyUnit.length < 1.0001f);
    const projected = Vector3(4, 3, 2).projectedOnto(
        Vector3(huge, 0, 0),
    );
    assert(projected.x == 4 && projected.y == 0 && projected.z == 0);
}
