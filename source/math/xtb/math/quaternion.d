module xtb.math.quaternion;

nothrow @nogc @safe:

import xtb.math.coordinate_system;
import xtb.math.scalar;
import xtb.math.vector;
import xtb.panic;
import xtb.types;

struct Quaternion
{
    nothrow @nogc @safe:

    f32 x = 0.0f;
    f32 y = 0.0f;
    f32 z = 0.0f;
    f32 w = 1.0f;

    static Quaternion identity() pure
    {
        return Quaternion.init;
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
        const sine = sin(half_angle);
        const cosine = cos(half_angle);
        return Quaternion(axis.x * sine, axis.y * sine, axis.z * sine, cosine);
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

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const absolute_w = abs(this.w);
        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(absolute_x, absolute_y),
            xtb.math.scalar.max(absolute_z, absolute_w),
        );

        if (scale == 0) return 0;

        const scaled = this / scale;
        return scale * sqrt(scaled.length_squared);
    }

    Quaternion normalized() const
    {
        if (!this.is_finite)
            return Quaternion(f32.nan, f32.nan, f32.nan, f32.nan);

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const absolute_w = abs(this.w);
        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(absolute_x, absolute_y),
            xtb.math.scalar.max(absolute_z, absolute_w),
        );

        if (scale == 0) return Quaternion(0.0f, 0.0f, 0.0f, 0.0f);

        const scaled = this / scale;
        return scaled / sqrt(scaled.length_squared);
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

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const absolute_w = abs(this.w);
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
        const sine_half_angle = sqrt(
            xtb.math.scalar.max(0, 1 - canonical.w * canonical.w),
        );

        if (sine_half_angle <= rotation_epsilon) return Vector3(1, 0, 0);

        return Vector3(canonical.x, canonical.y, canonical.z) / sine_half_angle;
    }

    /// Returns the canonical rotation angle in radians in the range `[0, pi]`.
    f32 angle() const
    {
        require(this.is_unit, "rotation quaternion must be unit length");
        return 2 * acos(
            xtb.math.scalar.clamp(abs(this.w), 0, 1),
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

private struct YawPitchRollAxes
{
    Vector3 yaw_axis;
    Vector3 pitch_axis;
    Vector3 roll_axis;
}

/// Creates an intrinsic yaw-pitch-roll rotation for `coordinates`.
///
/// Yaw turns around world up, pitch around local right after yaw, and roll around local forward
/// after yaw and pitch. Positive yaw turns forward toward right, positive pitch turns forward
/// toward up, and positive roll turns right toward up.
/// `coordinates` must be valid, and all angles must be finite.
Quaternion quaternion_from_yaw_pitch_roll(
    CoordinateSystem coordinates,
    f32 yaw,
    f32 pitch,
    f32 roll,
)
{
    require(
        yaw.is_finite && pitch.is_finite && roll.is_finite,
        "yaw, pitch, and roll must be finite",
    );

    const axes = derive_yaw_pitch_roll_axes(coordinates);
    return quaternion_from_yaw_pitch_roll_axes(axes, yaw, pitch, roll);
}

/// Creates an intrinsic yaw-pitch-roll rotation for a compile-time coordinate convention.
/// All angles must be finite.
package(xtb.math) Quaternion quaternion_from_yaw_pitch_roll(CoordinateSystem coordinates)(
    f32 yaw,
    f32 pitch,
    f32 roll,
)
{
    enum axes = derive_yaw_pitch_roll_axes(coordinates);
    return quaternion_from_yaw_pitch_roll_axes(axes, yaw, pitch, roll);
}

private YawPitchRollAxes derive_yaw_pitch_roll_axes(CoordinateSystem coordinates)
{
    const forward_axis = get_world_forward(coordinates);
    const right_axis = get_world_right(coordinates);
    const up_axis = get_world_up(coordinates);

    if (coordinates.handedness == Handedness.right)
    {
        return YawPitchRollAxes(
            yaw_axis: -up_axis,
            pitch_axis: right_axis,
            roll_axis: -forward_axis,
        );
    }
    else
    {
        return YawPitchRollAxes(
            yaw_axis: up_axis,
            pitch_axis: -right_axis,
            roll_axis: forward_axis,
        );
    }
}

private Quaternion quaternion_from_yaw_pitch_roll_axes(
    YawPitchRollAxes axes,
    f32 yaw,
    f32 pitch,
    f32 roll,
)
{
    require(
        yaw.is_finite && pitch.is_finite && roll.is_finite,
        "yaw, pitch, and roll must be finite",
    );

    const yaw_rotation = Quaternion.from_axis_angle(axes.yaw_axis, yaw);
    const pitch_rotation = Quaternion.from_axis_angle(axes.pitch_axis, pitch);
    const roll_rotation = Quaternion.from_axis_angle(axes.roll_axis, roll);
    return yaw_rotation * pitch_rotation * roll_rotation;
}

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

    const angle = acos(cosine);
    const sine = sin(angle);
    const a_weight = sin((1 - t) * angle) / sine;
    const b_weight = sin(t * angle) / sine;
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
    assert(Quaternion.init == identity);
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
    const quarter_turn = pi / 2;
    const rh_yaw = quaternion_from_yaw_pitch_roll(rh_z_up_y_forward, quarter_turn, 0, 0);
    const rh_pitch = quaternion_from_yaw_pitch_roll(rh_z_up_y_forward, 0, quarter_turn, 0);
    const rh_roll = quaternion_from_yaw_pitch_roll(rh_z_up_y_forward, 0, 0, quarter_turn);
    assert(xtb.math.vector.approximately_equal(
        rh_yaw.rotated(get_world_forward(rh_z_up_y_forward)),
        get_world_right(rh_z_up_y_forward),
        1e-5f,
        1e-5f,
    ));
    assert(xtb.math.vector.approximately_equal(
        rh_pitch.rotated(get_world_forward(rh_z_up_y_forward)),
        get_world_up(rh_z_up_y_forward),
        1e-5f,
        1e-5f,
    ));
    assert(xtb.math.vector.approximately_equal(
        rh_roll.rotated(get_world_right(rh_z_up_y_forward)),
        get_world_up(rh_z_up_y_forward),
        1e-5f,
        1e-5f,
    ));

    const lh_yaw = quaternion_from_yaw_pitch_roll(lh_y_up_z_forward, quarter_turn, 0, 0);
    assert(xtb.math.vector.approximately_equal(
        lh_yaw.rotated(get_world_forward(lh_y_up_z_forward)),
        get_world_right(lh_y_up_z_forward),
        1e-5f,
        1e-5f,
    ));
}

unittest
{
    const yaw = radians(35.0f);
    const pitch = radians(-20.0f);
    const combined = quaternion_from_yaw_pitch_roll(rh_z_up_y_forward, yaw, pitch, 0);
    const expected = Quaternion.from_axis_angle(-get_world_up(rh_z_up_y_forward), yaw).rotated(
        Quaternion.from_axis_angle(get_world_right(rh_z_up_y_forward), pitch).rotated(
            get_world_forward(rh_z_up_y_forward),
        ),
    );
    assert(xtb.math.vector.approximately_equal(
        combined.rotated(get_world_forward(rh_z_up_y_forward)),
        expected,
        1e-5f,
        1e-5f,
    ));
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
    assert(!Quaternion(0.0f, 0.0f, 0.0f, 0.0f).try_inverse(&unchanged));
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
        Vector3(sqrt(0.5f), sqrt(0.5f), 0),
        1e-5f,
        1e-5f,
    ));

    const same_rotation = nlerp(identity, -identity, 0.25f);
    assert(same_rotation == identity);
}

unittest
{
    const yaw = pi / 2;
    const yaw_rotation = quaternion_from_yaw_pitch_roll(
        rh_y_up_negative_z_forward,
        yaw,
        0,
        0,
    );
    assert(xtb.math.vector.approximately_equal(
        yaw_rotation.rotated(Vector3(0, 0, -1)),
        direction_from_yaw_pitch(rh_y_up_negative_z_forward, yaw, 0),
        1e-5f,
        1e-5f,
    ));

    const pitch = pi / 2;
    const pitch_rotation = quaternion_from_yaw_pitch_roll(
        rh_y_up_negative_z_forward,
        0,
        pitch,
        0,
    );
    assert(xtb.math.vector.approximately_equal(
        pitch_rotation.rotated(Vector3(0, 0, -1)),
        direction_from_yaw_pitch(rh_y_up_negative_z_forward, 0, pitch),
        1e-5f,
        1e-5f,
    ));

    const roll = pi / 7;
    const combined = quaternion_from_yaw_pitch_roll(
        rh_y_up_negative_z_forward,
        yaw,
        pitch,
        roll,
    );
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
