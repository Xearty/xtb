module xtb.math.vector;

nothrow @nogc @safe:

import core.stdc.math;

import xtb.math.scalar;
import xtb.panic;
import xtb.types;

struct Vector2
{
pure nothrow @nogc @safe:

    f32 x = 0;
    f32 y = 0;

    Vector2 opUnary(string op : "-")() const
    {
        return Vector2(-this.x, -this.y);
    }

    Vector2 opBinary(string op : "+")(Vector2 b) const
    {
        return Vector2(this.x + b.x, this.y + b.y);
    }

    Vector2 opBinary(string op : "-")(Vector2 b) const
    {
        return Vector2(this.x - b.x, this.y - b.y);
    }

    Vector2 opBinary(string op : "*")(Vector2 b) const
    {
        return Vector2(this.x * b.x, this.y * b.y);
    }

    Vector2 opBinary(string op : "/")(Vector2 b) const
    {
        return Vector2(this.x / b.x, this.y / b.y);
    }

    Vector2 opBinary(string op : "*")(f32 scalar) const
    {
        return Vector2(this.x * scalar, this.y * scalar);
    }

    Vector2 opBinary(string op : "/")(f32 scalar) const
    {
        return Vector2(this.x / scalar, this.y / scalar);
    }

    Vector2 opBinary(string op : "+")(f32 scalar) const
    {
        return Vector2(this.x + scalar, this.y + scalar);
    }

    Vector2 opBinary(string op : "-")(f32 scalar) const
    {
        return Vector2(this.x - scalar, this.y - scalar);
    }

    Vector2 opBinaryRight(string op : "*")(f32 scalar) const
    {
        return this * scalar;
    }
}

struct Vector3
{
pure nothrow @nogc @safe:

    f32 x = 0;
    f32 y = 0;
    f32 z = 0;

    Vector3 opUnary(string op : "-")() const
    {
        return Vector3(-this.x, -this.y, -this.z);
    }

    Vector3 opBinary(string op : "+")(Vector3 b) const
    {
        return Vector3(this.x + b.x, this.y + b.y, this.z + b.z);
    }

    Vector3 opBinary(string op : "-")(Vector3 b) const
    {
        return Vector3(this.x - b.x, this.y - b.y, this.z - b.z);
    }

    Vector3 opBinary(string op : "*")(Vector3 b) const
    {
        return Vector3(this.x * b.x, this.y * b.y, this.z * b.z);
    }

    Vector3 opBinary(string op : "/")(Vector3 b) const
    {
        return Vector3(this.x / b.x, this.y / b.y, this.z / b.z);
    }

    Vector3 opBinary(string op : "*")(f32 scalar) const
    {
        return Vector3(this.x * scalar, this.y * scalar, this.z * scalar);
    }

    Vector3 opBinary(string op : "/")(f32 scalar) const
    {
        return Vector3(this.x / scalar, this.y / scalar, this.z / scalar);
    }

    Vector3 opBinary(string op : "+")(f32 scalar) const
    {
        return Vector3(this.x + scalar, this.y + scalar, this.z + scalar);
    }

    Vector3 opBinary(string op : "-")(f32 scalar) const
    {
        return Vector3(this.x - scalar, this.y - scalar, this.z - scalar);
    }

    Vector3 opBinaryRight(string op : "*")(f32 scalar) const
    {
        return this * scalar;
    }
}

struct Vector4
{
pure nothrow @nogc @safe:

    f32 x = 0;
    f32 y = 0;
    f32 z = 0;
    f32 w = 0;

    Vector4 opUnary(string op : "-")() const
    {
        return Vector4(-this.x, -this.y, -this.z, -this.w);
    }

    Vector4 opBinary(string op : "+")(Vector4 b) const
    {
        return Vector4(this.x + b.x, this.y + b.y, this.z + b.z, this.w + b.w);
    }

    Vector4 opBinary(string op : "-")(Vector4 b) const
    {
        return Vector4(this.x - b.x, this.y - b.y, this.z - b.z, this.w - b.w);
    }

    Vector4 opBinary(string op : "*")(Vector4 b) const
    {
        return Vector4(this.x * b.x, this.y * b.y, this.z * b.z, this.w * b.w);
    }

    Vector4 opBinary(string op : "/")(Vector4 b) const
    {
        return Vector4(this.x / b.x, this.y / b.y, this.z / b.z, this.w / b.w);
    }

    Vector4 opBinary(string op : "*")(f32 scalar) const
    {
        return Vector4(this.x * scalar, this.y * scalar, this.z * scalar, this.w * scalar);
    }

    Vector4 opBinary(string op : "/")(f32 scalar) const
    {
        return Vector4(this.x / scalar, this.y / scalar, this.z / scalar, this.w / scalar);
    }

    Vector4 opBinary(string op : "+")(f32 scalar) const
    {
        return Vector4(this.x + scalar, this.y + scalar, this.z + scalar, this.w + scalar);
    }

    Vector4 opBinary(string op : "-")(f32 scalar) const
    {
        return Vector4(this.x - scalar, this.y - scalar, this.z - scalar, this.w - scalar);
    }

    Vector4 opBinaryRight(string op : "*")(f32 scalar) const
    {
        return this * scalar;
    }
}

Vector2 xy(Vector3 v) pure
{
    return Vector2(v.x, v.y);
}

Vector2 xy(Vector4 v) pure
{
    return Vector2(v.x, v.y);
}

Vector3 xyz(Vector4 v) pure
{
    return Vector3(v.x, v.y, v.z);
}

Vector3 with_z(Vector2 v, f32 z) pure
{
    return Vector3(v.x, v.y, z);
}

Vector4 with_w(Vector3 v, f32 w) pure
{
    return Vector4(v.x, v.y, v.z, w);
}

f32 dot(Vector2 a, Vector2 b) pure
{
    return a.x * b.x + a.y * b.y;
}

f32 dot(Vector3 a, Vector3 b) pure
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

f32 dot(Vector4 a, Vector4 b) pure
{
    return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}

Vector3 cross(Vector3 a, Vector3 b) pure
{
    return Vector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    );
}

f32 length_squared(Vector2 v) pure
{
    return dot(v, v);
}

f32 length_squared(Vector3 v) pure
{
    return dot(v, v);
}

f32 length_squared(Vector4 v) pure
{
    return dot(v, v);
}

private bool finite_component(f32 value) pure
{
    return value == value && value >= -f32.max && value <= f32.max;
}

bool is_finite(Vector2 v) pure
{
    return finite_component(v.x) && finite_component(v.y);
}

bool is_finite(Vector3 v) pure
{
    return finite_component(v.x) && finite_component(v.y) && finite_component(v.z);
}

bool is_finite(Vector4 v) pure
{
    return finite_component(v.x)
        && finite_component(v.y)
        && finite_component(v.z)
        && finite_component(v.w);
}

f32 length(Vector2 v)
{
    if (v.x != v.x || v.y != v.y) return f32.nan;

    const ax = fabsf(v.x);
    const ay = fabsf(v.y);
    const scale = xtb.math.scalar.max(ax, ay);
    if (scale == 0) return 0;
    if (scale == f32.infinity) return f32.infinity;

    const x = ax / scale;
    const y = ay / scale;
    return scale * sqrtf(x * x + y * y);
}

f32 length(Vector3 v)
{
    if (v.x != v.x || v.y != v.y || v.z != v.z) return f32.nan;

    const ax = fabsf(v.x);
    const ay = fabsf(v.y);
    const az = fabsf(v.z);
    const scale = xtb.math.scalar.max(ax, xtb.math.scalar.max(ay, az));
    if (scale == 0) return 0;
    if (scale == f32.infinity) return f32.infinity;

    const x = ax / scale;
    const y = ay / scale;
    const z = az / scale;
    return scale * sqrtf(x * x + y * y + z * z);
}

f32 length(Vector4 v)
{
    if (v.x != v.x || v.y != v.y || v.z != v.z || v.w != v.w) return f32.nan;

    const ax = fabsf(v.x);
    const ay = fabsf(v.y);
    const az = fabsf(v.z);
    const aw = fabsf(v.w);
    const scale = xtb.math.scalar.max(
        xtb.math.scalar.max(ax, ay),
        xtb.math.scalar.max(az, aw),
    );
    if (scale == 0) return 0;
    if (scale == f32.infinity) return f32.infinity;

    const x = ax / scale;
    const y = ay / scale;
    const z = az / scale;
    const w = aw / scale;
    return scale * sqrtf(x * x + y * y + z * z + w * w);
}

Vector2 normalized(Vector2 v)
{
    if (!v.is_finite) return Vector2(f32.nan, f32.nan);

    const scale = xtb.math.scalar.max(fabsf(v.x), fabsf(v.y));
    if (scale == 0) return Vector2.init;

    const scaled = v / scale;
    return scaled / sqrtf(dot(scaled, scaled));
}

Vector3 normalized(Vector3 v)
{
    if (!v.is_finite) return Vector3(f32.nan, f32.nan, f32.nan);

    const scale = xtb.math.scalar.max(
        fabsf(v.x),
        xtb.math.scalar.max(fabsf(v.y), fabsf(v.z)),
    );
    if (scale == 0) return Vector3.init;

    const scaled = v / scale;
    return scaled / sqrtf(dot(scaled, scaled));
}

Vector4 normalized(Vector4 v)
{
    if (!v.is_finite) return Vector4(f32.nan, f32.nan, f32.nan, f32.nan);

    const scale = xtb.math.scalar.max(
        xtb.math.scalar.max(fabsf(v.x), fabsf(v.y)),
        xtb.math.scalar.max(fabsf(v.z), fabsf(v.w)),
    );
    if (scale == 0) return Vector4.init;

    const scaled = v / scale;
    return scaled / sqrtf(dot(scaled, scaled));
}

f32 distance_squared(Vector2 a, Vector2 b) pure
{
    return (a - b).length_squared;
}

f32 distance_squared(Vector3 a, Vector3 b) pure
{
    return (a - b).length_squared;
}

f32 distance_squared(Vector4 a, Vector4 b) pure
{
    return (a - b).length_squared;
}

f32 distance(Vector2 a, Vector2 b)
{
    return (a - b).length;
}

f32 distance(Vector3 a, Vector3 b)
{
    return (a - b).length;
}

f32 distance(Vector4 a, Vector4 b)
{
    return (a - b).length;
}

f32 angle(Vector2 a, Vector2 b)
{
    const unit_a = a.normalized;
    const unit_b = b.normalized;
    return unit_a == Vector2.init || unit_b == Vector2.init
        ? 0
        : acosf(xtb.math.scalar.clamp(dot(unit_a, unit_b), -1, 1));
}

f32 angle(Vector3 a, Vector3 b)
{
    const unit_a = a.normalized;
    const unit_b = b.normalized;
    return unit_a == Vector3.init || unit_b == Vector3.init
        ? 0
        : acosf(xtb.math.scalar.clamp(dot(unit_a, unit_b), -1, 1));
}

f32 projection_length(Vector2 a, Vector2 onto)
{
    const unit = onto.normalized;
    return unit == Vector2.init ? 0 : dot(a, unit);
}

f32 projection_length(Vector3 a, Vector3 onto)
{
    const unit = onto.normalized;
    return unit == Vector3.init ? 0 : dot(a, unit);
}

Vector2 projected_onto(Vector2 a, Vector2 onto)
{
    const unit = onto.normalized;
    return unit == Vector2.init ? Vector2.init : unit * dot(a, unit);
}

Vector3 projected_onto(Vector3 a, Vector3 onto)
{
    const unit = onto.normalized;
    return unit == Vector3.init ? Vector3.init : unit * dot(a, unit);
}

Vector2 rejected_from(Vector2 a, Vector2 onto)
{
    return a - a.projected_onto(onto);
}

Vector3 rejected_from(Vector3 a, Vector3 onto)
{
    return a - a.projected_onto(onto);
}

Vector2 reflected(Vector2 v, Vector2 unit_normal) pure
{
    return v - unit_normal * (2 * dot(v, unit_normal));
}

Vector3 reflected(Vector3 v, Vector3 unit_normal) pure
{
    return v - unit_normal * (2 * dot(v, unit_normal));
}

Vector2 lerp(Vector2 a, Vector2 b, f32 t) pure
{
    return Vector2(
        xtb.math.scalar.lerp(a.x, b.x, t),
        xtb.math.scalar.lerp(a.y, b.y, t),
    );
}

Vector3 lerp(Vector3 a, Vector3 b, f32 t) pure
{
    return Vector3(
        xtb.math.scalar.lerp(a.x, b.x, t),
        xtb.math.scalar.lerp(a.y, b.y, t),
        xtb.math.scalar.lerp(a.z, b.z, t),
    );
}

Vector4 lerp(Vector4 a, Vector4 b, f32 t) pure
{
    return Vector4(
        xtb.math.scalar.lerp(a.x, b.x, t),
        xtb.math.scalar.lerp(a.y, b.y, t),
        xtb.math.scalar.lerp(a.z, b.z, t),
        xtb.math.scalar.lerp(a.w, b.w, t),
    );
}

Vector2 min(Vector2 a, Vector2 b) pure
{
    return Vector2(
        xtb.math.scalar.min(a.x, b.x),
        xtb.math.scalar.min(a.y, b.y),
    );
}

Vector3 min(Vector3 a, Vector3 b) pure
{
    return Vector3(
        xtb.math.scalar.min(a.x, b.x),
        xtb.math.scalar.min(a.y, b.y),
        xtb.math.scalar.min(a.z, b.z),
    );
}

Vector4 min(Vector4 a, Vector4 b) pure
{
    return Vector4(
        xtb.math.scalar.min(a.x, b.x),
        xtb.math.scalar.min(a.y, b.y),
        xtb.math.scalar.min(a.z, b.z),
        xtb.math.scalar.min(a.w, b.w),
    );
}

Vector2 max(Vector2 a, Vector2 b) pure
{
    return Vector2(
        xtb.math.scalar.max(a.x, b.x),
        xtb.math.scalar.max(a.y, b.y),
    );
}

Vector3 max(Vector3 a, Vector3 b) pure
{
    return Vector3(
        xtb.math.scalar.max(a.x, b.x),
        xtb.math.scalar.max(a.y, b.y),
        xtb.math.scalar.max(a.z, b.z),
    );
}

Vector4 max(Vector4 a, Vector4 b) pure
{
    return Vector4(
        xtb.math.scalar.max(a.x, b.x),
        xtb.math.scalar.max(a.y, b.y),
        xtb.math.scalar.max(a.z, b.z),
        xtb.math.scalar.max(a.w, b.w),
    );
}

Vector2 clamp(Vector2 v, Vector2 lower, Vector2 upper) pure
{
    return max(lower, min(v, upper));
}

Vector3 clamp(Vector3 v, Vector3 lower, Vector3 upper) pure
{
    return max(lower, min(v, upper));
}

Vector4 clamp(Vector4 v, Vector4 lower, Vector4 upper) pure
{
    return max(lower, min(v, upper));
}

Vector3 direction_from_degrees(f32 yaw, f32 pitch)
{
    require(
        xtb.math.scalar.is_finite(yaw) && xtb.math.scalar.is_finite(pitch),
        "direction angles must be finite",
    );
    const yaw_radians = radians(yaw);
    const pitch_radians = radians(pitch);
    return Vector3(
        sinf(yaw_radians) * cosf(pitch_radians),
        sinf(pitch_radians),
        -cosf(yaw_radians) * cosf(pitch_radians),
    );
}

static assert(Vector2.sizeof == 2 * f32.sizeof);
static assert(Vector3.sizeof == 3 * f32.sizeof);
static assert(Vector4.sizeof == 4 * f32.sizeof);

unittest
{
    const a = Vector3(1, 2, 3);
    const b = Vector3(4, 5, 6);
    assert(a + b == Vector3(5, 7, 9));
    assert(dot(a, b) == 32);
    assert(cross(Vector3(1, 0, 0), Vector3(0, 1, 0)) == Vector3(0, 0, 1));
    assert(Vector3.init.normalized == Vector3.init);
    assert(Vector3(3, 0, 0).projected_onto(Vector3(0, 2, 0)) == Vector3.init);

    const huge = f32.max;
    const huge_unit = Vector3(huge, huge, 0).normalized;
    assert(huge_unit.length > 0.9999f && huge_unit.length < 1.0001f);

    const tiny_unit = Vector3(1e-30f, -1e-30f, 0).normalized;
    assert(tiny_unit.length > 0.9999f && tiny_unit.length < 1.0001f);

    const projected = Vector3(4, 3, 2).projected_onto(Vector3(huge, 0, 0));
    assert(projected.x == 4 && projected.y == 0 && projected.z == 0);
}
