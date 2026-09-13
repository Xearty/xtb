module xtb.math.vector;

nothrow @nogc @safe:

import xtb.math.scalar;
import xtb.panic;
import xtb.types;

private bool is_valid_swizzle(string swizzle, string components) pure
{
    if (swizzle.length < 2 || swizzle.length > 4) return false;

    foreach (component; swizzle)
    {
        bool found = false;
        foreach (available; components)
        {
            if (component != available) continue;

            found = true;
            break;
        }
        if (!found) return false;
    }

    return true;
}

private mixin template VectorSwizzles(string components)
{
    auto opDispatch(string swizzle)() const pure
    if (is_valid_swizzle(swizzle, components))
    {
        static if (swizzle.length == 2)
        {
            return Vector2(
                mixin("this." ~ swizzle[0 .. 1]),
                mixin("this." ~ swizzle[1 .. 2]),
            );
        }
        else static if (swizzle.length == 3)
        {
            return Vector3(
                mixin("this." ~ swizzle[0 .. 1]),
                mixin("this." ~ swizzle[1 .. 2]),
                mixin("this." ~ swizzle[2 .. 3]),
            );
        }
        else
        {
            return Vector4(
                mixin("this." ~ swizzle[0 .. 1]),
                mixin("this." ~ swizzle[1 .. 2]),
                mixin("this." ~ swizzle[2 .. 3]),
                mixin("this." ~ swizzle[3 .. 4]),
            );
        }
    }
}

struct Vector2
{
    nothrow @nogc @safe:

    f32 x = 0;
    f32 y = 0;

    mixin VectorSwizzles!"xy";

    static Vector2 zero() pure
    {
        return Vector2.init;
    }

    static Vector2 splat(f32 value) pure
    {
        return Vector2(value, value);
    }

    static Vector2 unit_x() pure
    {
        return Vector2(1.0f, 0.0f);
    }

    static Vector2 unit_y() pure
    {
        return Vector2(0.0f, 1.0f);
    }

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

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const scale = xtb.math.scalar.max(absolute_x, absolute_y);
        if (scale == 0) return 0;
        if (scale == f32.infinity) return f32.infinity;

        const scaled_x = absolute_x / scale;
        const scaled_y = absolute_y / scale;
        return scale * sqrt(scaled_x * scaled_x + scaled_y * scaled_y);
    }

    Vector2 normalized() const
    {
        if (!this.is_finite) return Vector2(f32.nan, f32.nan);

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const scale = xtb.math.scalar.max(absolute_x, absolute_y);
        if (scale == 0) return Vector2.init;

        const scaled = this / scale;
        return scaled / sqrt(dot(scaled, scaled));
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

    /// Returns this vector rotated counterclockwise by `angle` radians.
    Vector2 rotated(f32 angle) const pure
    {
        const cosine = cos(angle);
        const sine = sin(angle);
        return Vector2(
            this.x * cosine - this.y * sine,
            this.x * sine + this.y * cosine,
        );
    }
}

struct Vector3
{
    nothrow @nogc @safe:

    f32 x = 0;
    f32 y = 0;
    f32 z = 0;

    mixin VectorSwizzles!"xyz";

    static Vector3 zero() pure
    {
        return Vector3.init;
    }

    static Vector3 splat(f32 value) pure
    {
        return Vector3(value, value, value);
    }

    static Vector3 unit_x() pure
    {
        return Vector3(1.0f, 0.0f, 0.0f);
    }

    static Vector3 unit_y() pure
    {
        return Vector3(0.0f, 1.0f, 0.0f);
    }

    static Vector3 unit_z() pure
    {
        return Vector3(0.0f, 0.0f, 1.0f);
    }

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

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const scale = xtb.math.scalar.max(
            absolute_x,
            xtb.math.scalar.max(absolute_y, absolute_z),
        );
        if (scale == 0) return 0;
        if (scale == f32.infinity) return f32.infinity;

        const scaled_x = absolute_x / scale;
        const scaled_y = absolute_y / scale;
        const scaled_z = absolute_z / scale;
        return scale * sqrt(
            scaled_x * scaled_x + scaled_y * scaled_y + scaled_z * scaled_z,
        );
    }

    Vector3 normalized() const
    {
        if (!this.is_finite) return Vector3(f32.nan, f32.nan, f32.nan);

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const scale = xtb.math.scalar.max(absolute_x, xtb.math.scalar.max(absolute_y, absolute_z));
        if (scale == 0) return Vector3.init;

        const scaled = this / scale;
        return scaled / sqrt(dot(scaled, scaled));
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

    mixin VectorSwizzles!"xyzw";

    static Vector4 zero() pure
    {
        return Vector4.init;
    }

    static Vector4 splat(f32 value) pure
    {
        return Vector4(value, value, value, value);
    }

    static Vector4 unit_x() pure
    {
        return Vector4(1.0f, 0.0f, 0.0f, 0.0f);
    }

    static Vector4 unit_y() pure
    {
        return Vector4(0.0f, 1.0f, 0.0f, 0.0f);
    }

    static Vector4 unit_z() pure
    {
        return Vector4(0.0f, 0.0f, 1.0f, 0.0f);
    }

    static Vector4 unit_w() pure
    {
        return Vector4(0.0f, 0.0f, 0.0f, 1.0f);
    }

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

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const absolute_w = abs(this.w);
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
        return scale * sqrt(
            scaled_x * scaled_x + scaled_y * scaled_y + scaled_z * scaled_z + scaled_w * scaled_w,
        );
    }

    Vector4 normalized() const
    {
        if (!this.is_finite) return Vector4(f32.nan, f32.nan, f32.nan, f32.nan);

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const absolute_w = abs(this.w);
        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(absolute_x, absolute_y),
            xtb.math.scalar.max(absolute_z, absolute_w),
        );
        if (scale == 0) return Vector4.init;

        const scaled = this / scale;
        return scaled / sqrt(dot(scaled, scaled));
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
        : acos(xtb.math.scalar.clamp(dot(unit_a, unit_b), -1, 1));
}

f32 angle(Vector3 a, Vector3 b)
{
    const unit_a = a.normalized;
    const unit_b = b.normalized;
    return unit_a == Vector3.init || unit_b == Vector3.init
        ? 0
        : acos(xtb.math.scalar.clamp(dot(unit_a, unit_b), -1, 1));
}

/// Returns the signed counterclockwise angle from `from` to `to`, in radians.
f32 signed_angle(Vector2 from, Vector2 to)
{
    const unit_from = from.normalized;
    const unit_to = to.normalized;
    if (unit_from == Vector2.init || unit_to == Vector2.init) return 0;

    const sine = unit_from.x * unit_to.y - unit_from.y * unit_to.x;
    const cosine = xtb.math.scalar.clamp(dot(unit_from, unit_to), -1, 1);
    return atan2(sine, cosine);
}

/// Returns the signed angle from `from` to `to` around `axis`, in radians.
///
/// The input vectors are projected onto the plane perpendicular to `axis`.
f32 signed_angle(Vector3 from, Vector3 to, Vector3 axis)
{
    const unit_axis = axis.normalized;
    if (unit_axis == Vector3.init) return 0;

    const unit_from = from.rejected_from(unit_axis).normalized;
    const unit_to = to.rejected_from(unit_axis).normalized;
    if (unit_from == Vector3.init || unit_to == Vector3.init) return 0;

    const sine = dot(unit_axis, cross(unit_from, unit_to));
    const cosine = xtb.math.scalar.clamp(dot(unit_from, unit_to), -1, 1);
    return atan2(sine, cosine);
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

bool approximately_equal(
    Vector2 a,
    Vector2 b,
    f32 absolute_tolerance,
    f32 relative_tolerance,
)
{
    const x_equal = xtb.math.scalar.approximately_equal(
        a.x,
        b.x,
        absolute_tolerance,
        relative_tolerance,
    );
    const y_equal = xtb.math.scalar.approximately_equal(
        a.y,
        b.y,
        absolute_tolerance,
        relative_tolerance,
    );
    return x_equal && y_equal;
}

bool approximately_equal(
    Vector3 a,
    Vector3 b,
    f32 absolute_tolerance,
    f32 relative_tolerance,
)
{
    const x_equal = xtb.math.scalar.approximately_equal(
        a.x,
        b.x,
        absolute_tolerance,
        relative_tolerance,
    );
    const y_equal = xtb.math.scalar.approximately_equal(
        a.y,
        b.y,
        absolute_tolerance,
        relative_tolerance,
    );
    const z_equal = xtb.math.scalar.approximately_equal(
        a.z,
        b.z,
        absolute_tolerance,
        relative_tolerance,
    );
    return x_equal && y_equal && z_equal;
}

bool approximately_equal(
    Vector4 a,
    Vector4 b,
    f32 absolute_tolerance,
    f32 relative_tolerance,
)
{
    const x_equal = xtb.math.scalar.approximately_equal(
        a.x,
        b.x,
        absolute_tolerance,
        relative_tolerance,
    );
    const y_equal = xtb.math.scalar.approximately_equal(
        a.y,
        b.y,
        absolute_tolerance,
        relative_tolerance,
    );
    const z_equal = xtb.math.scalar.approximately_equal(
        a.z,
        b.z,
        absolute_tolerance,
        relative_tolerance,
    );
    const w_equal = xtb.math.scalar.approximately_equal(
        a.w,
        b.w,
        absolute_tolerance,
        relative_tolerance,
    );
    return x_equal && y_equal && z_equal && w_equal;
}

/// Returns the forward direction for `yaw` and `pitch`, in radians.
Vector3 direction_from_yaw_pitch(f32 yaw, f32 pitch)
{
    require(
        xtb.math.scalar.is_finite(yaw) && xtb.math.scalar.is_finite(pitch),
        "direction angles must be finite",
    );

    const yaw_sine = sin(yaw);
    const yaw_cosine = cos(yaw);
    const pitch_sine = sin(pitch);
    const pitch_cosine = cos(pitch);
    return Vector3(
        yaw_sine * pitch_cosine,
        pitch_sine,
        -yaw_cosine * pitch_cosine,
    );
}

unittest
{
    const right = Vector2(1, 0);
    const up = Vector2(0, 1);
    assert(approximately_equal(right.rotated(pi / 2), up, 1e-6f, 1e-6f));
    assert(xtb.math.scalar.approximately_equal(signed_angle(right, up), pi / 2, 1e-6f, 1e-6f));
    assert(xtb.math.scalar.approximately_equal(signed_angle(up, right), -pi / 2, 1e-6f, 1e-6f));
}

unittest
{
    const right = Vector3(1, 0, 0);
    const up = Vector3(0, 1, 0);
    const forward = Vector3(0, 0, -1);
    assert(xtb.math.scalar.approximately_equal(
        signed_angle(forward, right, up),
        -pi / 2,
        1e-6f,
        1e-6f,
    ));
    assert(signed_angle(up, right, up) == 0);
}

unittest
{
    assert(approximately_equal(
        direction_from_yaw_pitch(pi / 2, 0),
        Vector3(1, 0, 0),
        1e-6f,
        1e-6f,
    ));
    assert(approximately_equal(
        direction_from_yaw_pitch(0, pi / 2),
        Vector3(0, 1, 0),
        1e-6f,
        1e-6f,
    ));
}

unittest
{
    assert(Vector2.zero() == Vector2.init);
    assert(Vector2.splat(3.0f) == Vector2(3.0f, 3.0f));
    assert(Vector2.unit_x() == Vector2(1.0f, 0.0f));
    assert(Vector2.unit_y() == Vector2(0.0f, 1.0f));

    assert(Vector3.zero() == Vector3.init);
    assert(Vector3.splat(3.0f) == Vector3(3.0f, 3.0f, 3.0f));
    assert(Vector3.unit_x() == Vector3(1.0f, 0.0f, 0.0f));
    assert(Vector3.unit_y() == Vector3(0.0f, 1.0f, 0.0f));
    assert(Vector3.unit_z() == Vector3(0.0f, 0.0f, 1.0f));

    assert(Vector4.zero() == Vector4.init);
    assert(Vector4.splat(3.0f) == Vector4(3.0f, 3.0f, 3.0f, 3.0f));
    assert(Vector4.unit_x() == Vector4(1.0f, 0.0f, 0.0f, 0.0f));
    assert(Vector4.unit_y() == Vector4(0.0f, 1.0f, 0.0f, 0.0f));
    assert(Vector4.unit_z() == Vector4(0.0f, 0.0f, 1.0f, 0.0f));
    assert(Vector4.unit_w() == Vector4(0.0f, 0.0f, 0.0f, 1.0f));
}

unittest
{
    const vector2 = Vector2(1.0f, 2.0f);
    assert(vector2.yx == Vector2(2.0f, 1.0f));
    assert(vector2.xyy == Vector3(1.0f, 2.0f, 2.0f));
    assert(vector2.yxxy == Vector4(2.0f, 1.0f, 1.0f, 2.0f));

    const vector3 = Vector3(1.0f, 2.0f, 3.0f);
    assert(vector3.xy == Vector2(1.0f, 2.0f));
    assert(vector3.zyx == Vector3(3.0f, 2.0f, 1.0f));
    assert(vector3.xzyz == Vector4(1.0f, 3.0f, 2.0f, 3.0f));

    const vector4 = Vector4(1.0f, 2.0f, 3.0f, 4.0f);
    assert(vector4.wx == Vector2(4.0f, 1.0f));
    assert(vector4.yzw == Vector3(2.0f, 3.0f, 4.0f));
    assert(vector4.wzyx == Vector4(4.0f, 3.0f, 2.0f, 1.0f));
    assert(vector4.xxxx == Vector4(1.0f, 1.0f, 1.0f, 1.0f));
}

static assert(!__traits(compiles, Vector2.init.xz));
static assert(!__traits(compiles, Vector3.init.xw));
static assert(!__traits(compiles, Vector4.init.xyzwx));
static assert(!__traits(compiles, Vector4.init.xq));
static assert(!__traits(compiles, ()
{
    Vector3 vector;
    vector.xy = Vector2(1.0f, 2.0f);
}));

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
