module xtb.math.quaternion;

nothrow @nogc @safe:

import xtb.math.scalar;
import xtb.math.vector;
import xtb.panic;
import xtb.types;

struct Quaternion
{
    nothrow @nogc @safe:

    f32 x = 0;
    f32 y = 0;
    f32 z = 0;
    f32 w = 0;

    static Quaternion identity() pure
    {
        return Quaternion(0, 0, 0, 1);
    }

    /// Creates a rotation of `angle` radians around `axis`.
    ///
    /// `axis` is normalized internally. A zero axis produces the identity rotation.
    static Quaternion from_axis_angle(Vector3 axis, f32 angle)
    {
        require(axis.is_finite && angle.is_finite, "rotation axis and angle must be finite");

        axis = axis.normalized;
        if (axis == Vector3.init) return identity();

        const half_angle = angle / 2;
        const sine = xtb.math.scalar.sin(half_angle);
        const cosine = xtb.math.scalar.cos(half_angle);
        return Quaternion(axis.x * sine, axis.y * sine, axis.z * sine, cosine);
    }

    /// Creates a yaw-pitch-roll rotation from radian angles.
    ///
    /// Yaw rotates around negative Y, pitch around positive X, and roll around positive Z.
    /// The result is `yaw_rotation * pitch_rotation * roll_rotation`, so roll acts first
    /// when the quaternion is applied to a vector.
    static Quaternion from_yaw_pitch_roll(f32 yaw, f32 pitch, f32 roll)
    {
        require(
            yaw.is_finite && pitch.is_finite && roll.is_finite,
            "yaw, pitch, and roll must be finite",
        );

        const yaw_rotation = from_axis_angle(Vector3(0, -1, 0), yaw);
        const pitch_rotation = from_axis_angle(Vector3(1, 0, 0), pitch);
        const roll_rotation = from_axis_angle(Vector3(0, 0, 1), roll);
        return yaw_rotation * pitch_rotation * roll_rotation;
    }

    Quaternion opUnary(string op : "-")() const pure
    {
        return Quaternion(-this.x, -this.y, -this.z, -this.w);
    }

    Quaternion opBinary(string op : "+")(Quaternion other) const pure
    {
        return Quaternion(
            this.x + other.x,
            this.y + other.y,
            this.z + other.z,
            this.w + other.w,
        );
    }

    Quaternion opBinary(string op : "-")(Quaternion other) const pure
    {
        return Quaternion(
            this.x - other.x,
            this.y - other.y,
            this.z - other.z,
            this.w - other.w,
        );
    }

    Quaternion opBinary(string op : "*")(Quaternion other) const pure
    {
        return Quaternion(
            this.w * other.x + this.x * other.w + this.y * other.z - this.z * other.y,
            this.w * other.y - this.x * other.z + this.y * other.w + this.z * other.x,
            this.w * other.z + this.x * other.y - this.y * other.x + this.z * other.w,
            this.w * other.w - this.x * other.x - this.y * other.y - this.z * other.z,
        );
    }

    Quaternion opBinary(string op : "*")(f32 scalar) const pure
    {
        return Quaternion(
            this.x * scalar,
            this.y * scalar,
            this.z * scalar,
            this.w * scalar,
        );
    }

    Quaternion opBinary(string op : "/")(f32 scalar) const pure
    {
        return Quaternion(
            this.x / scalar,
            this.y / scalar,
            this.z / scalar,
            this.w / scalar,
        );
    }

    Quaternion opBinaryRight(string op : "*")(f32 scalar) const pure
    {
        return this * scalar;
    }

    f32 length_squared() const pure
    {
        return this.x * this.x + this.y * this.y + this.z * this.z + this.w * this.w;
    }

    bool is_finite() const pure
    {
        return this.x.is_finite
            && this.y.is_finite
            && this.z.is_finite
            && this.w.is_finite;
    }

    f32 length() const
    {
        if (!this.is_finite)
        {
            return this.x.is_nan || this.y.is_nan || this.z.is_nan || this.w.is_nan
                ? f32.nan
                : f32.infinity;
        }

        const absolute_x = xtb.math.scalar.abs(this.x);
        const absolute_y = xtb.math.scalar.abs(this.y);
        const absolute_z = xtb.math.scalar.abs(this.z);
        const absolute_w = xtb.math.scalar.abs(this.w);
        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(absolute_x, absolute_y),
            xtb.math.scalar.max(absolute_z, absolute_w),
        );
        if (scale == 0) return 0;

        const scaled = this / scale;
        return scale * xtb.math.scalar.sqrt(scaled.length_squared);
    }

    Quaternion normalized() const
    {
        if (!this.is_finite)
            return Quaternion(f32.nan, f32.nan, f32.nan, f32.nan);

        const absolute_x = xtb.math.scalar.abs(this.x);
        const absolute_y = xtb.math.scalar.abs(this.y);
        const absolute_z = xtb.math.scalar.abs(this.z);
        const absolute_w = xtb.math.scalar.abs(this.w);
        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(absolute_x, absolute_y),
            xtb.math.scalar.max(absolute_z, absolute_w),
        );
        if (scale == 0) return Quaternion.init;

        const scaled = this / scale;
        return scaled / xtb.math.scalar.sqrt(scaled.length_squared);
    }

    Quaternion conjugated() const pure
    {
        return Quaternion(-this.x, -this.y, -this.z, this.w);
    }

    /// `output` must not be null.
    ///
    /// On failure, `output` remains unchanged.
    bool try_inverse(Quaternion* output) const @system
    {
        require(output !is null, "quaternion inverse output pointer is null");
        if (!this.is_finite) return false;

        const absolute_x = xtb.math.scalar.abs(this.x);
        const absolute_y = xtb.math.scalar.abs(this.y);
        const absolute_z = xtb.math.scalar.abs(this.z);
        const absolute_w = xtb.math.scalar.abs(this.w);
        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(absolute_x, absolute_y),
            xtb.math.scalar.max(absolute_z, absolute_w),
        );
        if (scale == 0) return false;

        const scaled = this / scale;
        const scaled_length_squared = scaled.length_squared;
        const result = (scaled.conjugated / scaled_length_squared) / scale;
        if (!result.is_finite) return false;

        *output = result;
        return true;
    }

    /// Rotates `vector` by this unit quaternion.
    Vector3 rotated(Vector3 vector) const
    {
        require(this.is_unit, "rotation quaternion must be unit length");

        const imaginary = Vector3(this.x, this.y, this.z);
        const twice_cross = 2 * cross(imaginary, vector);
        return vector + this.w * twice_cross + cross(imaginary, twice_cross);
    }

    /// Returns a canonical rotation axis for this unit quaternion.
    ///
    /// The identity rotation uses positive X because its rotation axis is otherwise undefined.
    Vector3 axis() const
    {
        require(this.is_unit, "rotation quaternion must be unit length");

        const canonical = this.w < 0 ? -this : this;
        const sine_half_angle = xtb.math.scalar.sqrt(
            xtb.math.scalar.max(0, 1 - canonical.w * canonical.w),
        );
        if (sine_half_angle <= rotation_epsilon) return Vector3(1, 0, 0);

        return Vector3(canonical.x, canonical.y, canonical.z) / sine_half_angle;
    }

    /// Returns the canonical rotation angle in radians in the range `[0, pi]`.
    f32 angle() const
    {
        require(this.is_unit, "rotation quaternion must be unit length");
        return 2 * xtb.math.scalar.acos(
            xtb.math.scalar.clamp(xtb.math.scalar.abs(this.w), 0, 1),
        );
    }

    /// Returns whether this quaternion has unit length within the rotation tolerance.
    bool is_unit() const
    {
        return xtb.math.scalar.approximately_equal(
            this.length_squared,
            1,
            unit_absolute_tolerance,
            unit_relative_tolerance,
        );
    }
}

static assert(Quaternion.sizeof == 4 * f32.sizeof);

private enum f32 unit_absolute_tolerance = 1e-5f;
private enum f32 unit_relative_tolerance = 1e-5f;
private enum f32 rotation_epsilon = 1e-6f;

f32 dot(Quaternion a, Quaternion b) pure
{
    return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}

Quaternion nlerp(Quaternion a, Quaternion b, f32 t)
{
    require(a.is_unit && b.is_unit, "interpolated quaternions must be unit length");

    if (dot(a, b) < 0) b = -b;
    return (a + (b - a) * t).normalized;
}

Quaternion slerp(Quaternion a, Quaternion b, f32 t)
{
    require(a.is_unit && b.is_unit, "interpolated quaternions must be unit length");

    f32 cosine = dot(a, b);
    if (cosine < 0)
    {
        b = -b;
        cosine = -cosine;
    }

    cosine = xtb.math.scalar.clamp(cosine, -1, 1);
    if (cosine > 0.9995f) return nlerp(a, b, t);

    const angle = xtb.math.scalar.acos(cosine);
    const sine = xtb.math.scalar.sin(angle);
    const a_weight = xtb.math.scalar.sin((1 - t) * angle) / sine;
    const b_weight = xtb.math.scalar.sin(t * angle) / sine;
    return a * a_weight + b * b_weight;
}

/// Compares quaternion components. Opposite-sign quaternions remain distinct values.
bool approximately_equal(
    Quaternion a,
    Quaternion b,
    f32 absolute_tolerance,
    f32 relative_tolerance,
)
{
    return xtb.math.scalar.approximately_equal(
            a.x,
            b.x,
            absolute_tolerance,
            relative_tolerance,
        )
        && xtb.math.scalar.approximately_equal(
            a.y,
            b.y,
            absolute_tolerance,
            relative_tolerance,
        )
        && xtb.math.scalar.approximately_equal(
            a.z,
            b.z,
            absolute_tolerance,
            relative_tolerance,
        )
        && xtb.math.scalar.approximately_equal(
            a.w,
            b.w,
            absolute_tolerance,
            relative_tolerance,
        );
}

unittest
{
    const identity = Quaternion.identity;
    assert(identity == Quaternion(0, 0, 0, 1));
    assert(identity.length_squared == 1);
    assert(identity.is_finite);
    assert(identity.is_unit);
    assert(identity.normalized == identity);
    assert(identity.conjugated == identity);
    assert(identity.axis == Vector3(1, 0, 0));
    assert(identity.angle == 0);
}

unittest
{
    const quarter_turn = Quaternion.from_axis_angle(Vector3(0, 0, 2), pi / 2);
    assert(xtb.math.scalar.approximately_equal(quarter_turn.length, 1, 1e-5f, 1e-5f));
    const rotated = quarter_turn.rotated(Vector3(1, 0, 0));
    assert(xtb.math.vector.approximately_equal(rotated, Vector3(0, 1, 0), 1e-5f, 1e-5f));
    assert(xtb.math.vector.approximately_equal(quarter_turn.axis, Vector3(0, 0, 1), 1e-5f, 1e-5f));
    assert(xtb.math.scalar.approximately_equal(quarter_turn.angle, pi / 2, 1e-5f, 1e-5f));

    const same_rotation = -quarter_turn;
    assert(xtb.math.vector.approximately_equal(
        same_rotation.axis,
        quarter_turn.axis,
        1e-5f,
        1e-5f,
    ));
    assert(xtb.math.scalar.approximately_equal(
        same_rotation.angle,
        quarter_turn.angle,
        1e-5f,
        1e-5f,
    ));
    assert(!approximately_equal(quarter_turn, same_rotation, 1e-5f, 1e-5f));
    assert(Quaternion.from_axis_angle(Vector3.init, pi / 2) == Quaternion.identity);
}

@system unittest
{
    const rotation = Quaternion.from_axis_angle(Vector3(0, 1, 0), pi / 3);
    Quaternion inverse = Quaternion.identity;
    assert(rotation.try_inverse(&inverse));
    assert(approximately_equal(rotation * inverse, Quaternion.identity, 1e-5f, 1e-5f));

    Quaternion unchanged = Quaternion.identity;
    assert(!Quaternion.init.try_inverse(&unchanged));
    assert(unchanged == Quaternion.identity);

    const tiny = Quaternion(1e-20f, 0, 0, 0);
    Quaternion tiny_inverse;
    assert(tiny.try_inverse(&tiny_inverse));
    assert(xtb.math.scalar.approximately_equal(tiny_inverse.x, -1e20f, 0, 1e-5f));

    const huge = Quaternion(1e20f, 0, 0, 0);
    Quaternion huge_inverse;
    assert(huge.try_inverse(&huge_inverse));
    assert(xtb.math.scalar.approximately_equal(huge_inverse.x, -1e-20f, 0, 1e-5f));
}

unittest
{
    const identity = Quaternion.identity;
    const quarter_turn = Quaternion.from_axis_angle(Vector3(0, 0, 1), pi / 2);
    const halfway = slerp(identity, quarter_turn, 0.5f);
    assert(xtb.math.vector.approximately_equal(
        halfway.rotated(Vector3(1, 0, 0)),
        Vector3(xtb.math.scalar.sqrt(0.5f), xtb.math.scalar.sqrt(0.5f), 0),
        1e-5f,
        1e-5f,
    ));

    const same_rotation = nlerp(identity, -identity, 0.25f);
    assert(same_rotation == identity);
}

unittest
{
    const yaw = pi / 2;
    const yaw_rotation = Quaternion.from_yaw_pitch_roll(yaw, 0, 0);
    assert(xtb.math.vector.approximately_equal(
        yaw_rotation.rotated(Vector3(0, 0, -1)),
        direction_from_yaw_pitch(yaw, 0),
        1e-5f,
        1e-5f,
    ));

    const pitch = pi / 2;
    const pitch_rotation = Quaternion.from_yaw_pitch_roll(0, pitch, 0);
    assert(xtb.math.vector.approximately_equal(
        pitch_rotation.rotated(Vector3(0, 0, -1)),
        direction_from_yaw_pitch(0, pitch),
        1e-5f,
        1e-5f,
    ));

    const roll = pi / 7;
    const combined = Quaternion.from_yaw_pitch_roll(yaw, pitch, roll);
    const vector = Vector3(0.25f, -0.5f, 1);
    const sequential = Quaternion.from_axis_angle(Vector3(0, -1, 0), yaw).rotated(
        Quaternion.from_axis_angle(Vector3(1, 0, 0), pitch).rotated(
            Quaternion.from_axis_angle(Vector3(0, 0, 1), roll).rotated(vector),
        ),
    );
    assert(xtb.math.vector.approximately_equal(
        combined.rotated(vector),
        sequential,
        1e-5f,
        1e-5f,
    ));
}
