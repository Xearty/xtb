module xtb.math.vector;

nothrow @nogc @safe:

import core.stdc.math;

import xtb.math.scalar;
import xtb.panic;
import xtb.types;

struct Vector2
{
    nothrow @nogc @safe:

    f32 x = 0;
    f32 y = 0;

    Vector2 opUnary(string op : "-")() const pure
    {
        return Vector2(-this.x, -this.y);
    }

    Vector2 opBinary(string op : "+")(Vector2 b) const pure
    {
        return Vector2(this.x + b.x, this.y + b.y);
    }

    Vector2 opBinary(string op : "-")(Vector2 b) const pure
    {
        return Vector2(this.x - b.x, this.y - b.y);
    }

    Vector2 opBinary(string op : "*")(Vector2 b) const pure
    {
        return Vector2(this.x * b.x, this.y * b.y);
    }

    Vector2 opBinary(string op : "/")(Vector2 b) const pure
    {
        return Vector2(this.x / b.x, this.y / b.y);
    }

    Vector2 opBinary(string op : "*")(f32 scalar) const pure
    {
        return Vector2(this.x * scalar, this.y * scalar);
    }

    Vector2 opBinary(string op : "/")(f32 scalar) const pure
    {
        return Vector2(this.x / scalar, this.y / scalar);
    }

    Vector2 opBinary(string op : "+")(f32 scalar) const pure
    {
        return Vector2(this.x + scalar, this.y + scalar);
    }

    Vector2 opBinary(string op : "-")(f32 scalar) const pure
    {
        return Vector2(this.x - scalar, this.y - scalar);
    }

    Vector2 opBinaryRight(string op : "*")(f32 scalar) const pure
    {
        return this * scalar;
    }

    Vector3 with_z(f32 z) const pure
    {
        return Vector3(this.x, this.y, z);
    }

    f32 length_squared() const pure
    {
        return this.x * this.x + this.y * this.y;
    }

    bool is_finite() const pure
    {
        return xtb.math.scalar.is_finite(this.x) && xtb.math.scalar.is_finite(this.y);
    }

    f32 length() const
    {
        if (this.x != this.x || this.y != this.y) return f32.nan;

        const absolute_x = fabsf(this.x);
        const absolute_y = fabsf(this.y);
        const scale = xtb.math.scalar.max(absolute_x, absolute_y);
        if (scale == 0) return 0;
        if (scale == f32.infinity) return f32.infinity;

        const scaled_x = absolute_x / scale;
        const scaled_y = absolute_y / scale;
        return scale * sqrtf(scaled_x * scaled_x + scaled_y * scaled_y);
    }

    Vector2 normalized() const
    {
        if (!this.is_finite) return Vector2(f32.nan, f32.nan);

        const scale = xtb.math.scalar.max(fabsf(this.x), fabsf(this.y));
        if (scale == 0) return Vector2.init;

        const scaled = this / scale;
        return scaled / sqrtf(dot(scaled, scaled));
    }

    f32 projection_length(Vector2 onto) const
    {
        const unit = onto.normalized;
        return unit == Vector2.init ? 0 : dot(this, unit);
    }

    Vector2 projected_onto(Vector2 onto) const
    {
        const unit = onto.normalized;
        return unit == Vector2.init ? Vector2.init : unit * dot(this, unit);
    }

    Vector2 rejected_from(Vector2 onto) const
    {
        return this - this.projected_onto(onto);
    }

    Vector2 reflected(Vector2 unit_normal) const pure
    {
        return this - unit_normal * (2 * dot(this, unit_normal));
    }
}

struct Vector3
{
    nothrow @nogc @safe:

    f32 x = 0;
    f32 y = 0;
    f32 z = 0;

    Vector3 opUnary(string op : "-")() const pure
    {
        return Vector3(-this.x, -this.y, -this.z);
    }

    Vector3 opBinary(string op : "+")(Vector3 b) const pure
    {
        return Vector3(this.x + b.x, this.y + b.y, this.z + b.z);
    }

    Vector3 opBinary(string op : "-")(Vector3 b) const pure
    {
        return Vector3(this.x - b.x, this.y - b.y, this.z - b.z);
    }

    Vector3 opBinary(string op : "*")(Vector3 b) const pure
    {
        return Vector3(this.x * b.x, this.y * b.y, this.z * b.z);
    }

    Vector3 opBinary(string op : "/")(Vector3 b) const pure
    {
        return Vector3(this.x / b.x, this.y / b.y, this.z / b.z);
    }

    Vector3 opBinary(string op : "*")(f32 scalar) const pure
    {
        return Vector3(this.x * scalar, this.y * scalar, this.z * scalar);
    }

    Vector3 opBinary(string op : "/")(f32 scalar) const pure
    {
        return Vector3(this.x / scalar, this.y / scalar, this.z / scalar);
    }

    Vector3 opBinary(string op : "+")(f32 scalar) const pure
    {
        return Vector3(this.x + scalar, this.y + scalar, this.z + scalar);
    }

    Vector3 opBinary(string op : "-")(f32 scalar) const pure
    {
        return Vector3(this.x - scalar, this.y - scalar, this.z - scalar);
    }

    Vector3 opBinaryRight(string op : "*")(f32 scalar) const pure
    {
        return this * scalar;
    }

    Vector2 xy() const pure
    {
        return Vector2(this.x, this.y);
    }

    Vector4 with_w(f32 w) const pure
    {
        return Vector4(this.x, this.y, this.z, w);
    }

    f32 length_squared() const pure
    {
        return this.x * this.x + this.y * this.y + this.z * this.z;
    }

    bool is_finite() const pure
    {
        return xtb.math.scalar.is_finite(this.x)
            && xtb.math.scalar.is_finite(this.y)
            && xtb.math.scalar.is_finite(this.z);
    }

    f32 length() const
    {
        if (this.x != this.x || this.y != this.y || this.z != this.z) return f32.nan;

        const absolute_x = fabsf(this.x);
        const absolute_y = fabsf(this.y);
        const absolute_z = fabsf(this.z);
        const scale = xtb.math.scalar.max(
            absolute_x,
            xtb.math.scalar.max(absolute_y, absolute_z),
        );
        if (scale == 0) return 0;
        if (scale == f32.infinity) return f32.infinity;

        const scaled_x = absolute_x / scale;
        const scaled_y = absolute_y / scale;
        const scaled_z = absolute_z / scale;
        return scale * sqrtf(
            scaled_x * scaled_x + scaled_y * scaled_y + scaled_z * scaled_z,
        );
    }

    Vector3 normalized() const
    {
        if (!this.is_finite) return Vector3(f32.nan, f32.nan, f32.nan);

        const scale = xtb.math.scalar.max(
            fabsf(this.x),
            xtb.math.scalar.max(fabsf(this.y), fabsf(this.z)),
        );
        if (scale == 0) return Vector3.init;

        const scaled = this / scale;
        return scaled / sqrtf(dot(scaled, scaled));
    }

    f32 projection_length(Vector3 onto) const
    {
        const unit = onto.normalized;
        return unit == Vector3.init ? 0 : dot(this, unit);
    }

    Vector3 projected_onto(Vector3 onto) const
    {
        const unit = onto.normalized;
        return unit == Vector3.init ? Vector3.init : unit * dot(this, unit);
    }

    Vector3 rejected_from(Vector3 onto) const
    {
        return this - this.projected_onto(onto);
    }

    Vector3 reflected(Vector3 unit_normal) const pure
    {
        return this - unit_normal * (2 * dot(this, unit_normal));
    }
}

struct Vector4
{
    nothrow @nogc @safe:

    f32 x = 0;
    f32 y = 0;
    f32 z = 0;
    f32 w = 0;

    Vector4 opUnary(string op : "-")() const pure
    {
        return Vector4(-this.x, -this.y, -this.z, -this.w);
    }

    Vector4 opBinary(string op : "+")(Vector4 b) const pure
    {
        return Vector4(this.x + b.x, this.y + b.y, this.z + b.z, this.w + b.w);
    }

    Vector4 opBinary(string op : "-")(Vector4 b) const pure
    {
        return Vector4(this.x - b.x, this.y - b.y, this.z - b.z, this.w - b.w);
    }

    Vector4 opBinary(string op : "*")(Vector4 b) const pure
    {
        return Vector4(this.x * b.x, this.y * b.y, this.z * b.z, this.w * b.w);
    }

    Vector4 opBinary(string op : "/")(Vector4 b) const pure
    {
        return Vector4(this.x / b.x, this.y / b.y, this.z / b.z, this.w / b.w);
    }

    Vector4 opBinary(string op : "*")(f32 scalar) const pure
    {
        return Vector4(this.x * scalar, this.y * scalar, this.z * scalar, this.w * scalar);
    }

    Vector4 opBinary(string op : "/")(f32 scalar) const pure
    {
        return Vector4(this.x / scalar, this.y / scalar, this.z / scalar, this.w / scalar);
    }

    Vector4 opBinary(string op : "+")(f32 scalar) const pure
    {
        return Vector4(this.x + scalar, this.y + scalar, this.z + scalar, this.w + scalar);
    }

    Vector4 opBinary(string op : "-")(f32 scalar) const pure
    {
        return Vector4(this.x - scalar, this.y - scalar, this.z - scalar, this.w - scalar);
    }

    Vector4 opBinaryRight(string op : "*")(f32 scalar) const pure
    {
        return this * scalar;
    }

    Vector2 xy() const pure
    {
        return Vector2(this.x, this.y);
    }

    Vector3 xyz() const pure
    {
        return Vector3(this.x, this.y, this.z);
    }

    f32 length_squared() const pure
    {
        return this.x * this.x + this.y * this.y + this.z * this.z + this.w * this.w;
    }

    bool is_finite() const pure
    {
        return xtb.math.scalar.is_finite(this.x)
            && xtb.math.scalar.is_finite(this.y)
            && xtb.math.scalar.is_finite(this.z)
            && xtb.math.scalar.is_finite(this.w);
    }

    f32 length() const
    {
        if (this.x != this.x || this.y != this.y || this.z != this.z || this.w != this.w)
            return f32.nan;

        const absolute_x = fabsf(this.x);
        const absolute_y = fabsf(this.y);
        const absolute_z = fabsf(this.z);
        const absolute_w = fabsf(this.w);
        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(absolute_x, absolute_y),
            xtb.math.scalar.max(absolute_z, absolute_w),
        );
        if (scale == 0) return 0;
        if (scale == f32.infinity) return f32.infinity;

        const scaled_x = absolute_x / scale;
        const scaled_y = absolute_y / scale;
        const scaled_z = absolute_z / scale;
        const scaled_w = absolute_w / scale;
        return scale * sqrtf(
            scaled_x * scaled_x + scaled_y * scaled_y + scaled_z * scaled_z + scaled_w * scaled_w,
        );
    }

    Vector4 normalized() const
    {
        if (!this.is_finite) return Vector4(f32.nan, f32.nan, f32.nan, f32.nan);

        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(fabsf(this.x), fabsf(this.y)),
            xtb.math.scalar.max(fabsf(this.z), fabsf(this.w)),
        );
        if (scale == 0) return Vector4.init;

        const scaled = this / scale;
        return scaled / sqrtf(dot(scaled, scaled));
    }
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
