module xtb.math.coordinate_system;

nothrow @nogc @safe:

import xtb.math.scalar;
import xtb.math.vector;
import xtb.panic;
import xtb.types;

enum Handedness
{
    right,
    left,
}

enum SignedAxis
{
    positive_x,
    negative_x,
    positive_y,
    negative_y,
    positive_z,
    negative_z,
}

/// Describes an orthogonal world-coordinate convention.
///
/// Construction derives and caches the right axis from handedness, forward, and up.
/// `forward` and `up` must identify perpendicular axes.
/// The four fields must remain mutually consistent; construct a new value instead of
/// mutating an individual field.
struct CoordinateSystem
{
    nothrow @nogc @safe:

    Handedness handedness = Handedness.right;
    SignedAxis forward = SignedAxis.positive_y;
    SignedAxis right = SignedAxis.positive_x;
    SignedAxis up = SignedAxis.positive_z;

    this(Handedness handedness, SignedAxis forward, SignedAxis up)
    {
        require(
            axis_dimension(forward) != axis_dimension(up),
            "coordinate system forward and up axes must be perpendicular",
        );

        this.handedness = handedness;
        this.forward = forward;
        this.right = derive_right_axis(handedness, forward, up);
        this.up = up;
    }
}

enum rh_z_up_y_forward = CoordinateSystem(
    handedness: Handedness.right,
    forward: SignedAxis.positive_y,
    up: SignedAxis.positive_z,
);

enum rh_y_up_negative_z_forward = CoordinateSystem(
    handedness: Handedness.right,
    forward: SignedAxis.negative_z,
    up: SignedAxis.positive_y,
);

enum lh_y_up_z_forward = CoordinateSystem(
    handedness: Handedness.left,
    forward: SignedAxis.positive_z,
    up: SignedAxis.positive_y,
);

Vector3 vector_from_signed_axis(SignedAxis axis) pure
{
    final switch (axis)
    {
        case SignedAxis.positive_x:
            return Vector3(1, 0, 0);
        case SignedAxis.negative_x:
            return Vector3(-1, 0, 0);
        case SignedAxis.positive_y:
            return Vector3(0, 1, 0);
        case SignedAxis.negative_y:
            return Vector3(0, -1, 0);
        case SignedAxis.positive_z:
            return Vector3(0, 0, 1);
        case SignedAxis.negative_z:
            return Vector3(0, 0, -1);
    }
}

Vector3 get_world_forward(CoordinateSystem coordinates) pure
{
    return vector_from_signed_axis(coordinates.forward);
}

Vector3 get_world_backward(CoordinateSystem coordinates) pure
{
    return -get_world_forward(coordinates);
}

Vector3 get_world_up(CoordinateSystem coordinates) pure
{
    return vector_from_signed_axis(coordinates.up);
}

Vector3 get_world_down(CoordinateSystem coordinates) pure
{
    return -get_world_up(coordinates);
}

Vector3 get_world_right(CoordinateSystem coordinates) pure
{
    return vector_from_signed_axis(coordinates.right);
}

Vector3 get_world_left(CoordinateSystem coordinates) pure
{
    return -get_world_right(coordinates);
}

/// Returns the forward direction for `yaw` and `pitch`, in radians, under `coordinates`.
/// Both angles must be finite.
Vector3 direction_from_yaw_pitch(
    CoordinateSystem coordinates,
    f32 yaw,
    f32 pitch,
)
{
    const forward_axis = get_world_forward(coordinates);
    const right_axis = get_world_right(coordinates);
    const up_axis = get_world_up(coordinates);
    return direction_from_yaw_pitch_axes(
        forward_axis,
        right_axis,
        up_axis,
        yaw,
        pitch,
    );
}

/// Returns the forward direction for a compile-time coordinate convention.
/// Both angles must be finite.
package(xtb.math) Vector3 direction_from_yaw_pitch(CoordinateSystem coordinates)(
    f32 yaw,
    f32 pitch,
)
{
    enum Vector3 forward_axis = get_world_forward(coordinates);
    enum Vector3 right_axis = get_world_right(coordinates);
    enum Vector3 up_axis = get_world_up(coordinates);
    return direction_from_yaw_pitch_axes(
        forward_axis,
        right_axis,
        up_axis,
        yaw,
        pitch,
    );
}

private SignedAxis derive_right_axis(
    Handedness handedness,
    SignedAxis forward,
    SignedAxis up,
) pure
{
    const forward_axis = vector_from_signed_axis(forward);
    const up_axis = vector_from_signed_axis(up);
    const right_axis = handedness == Handedness.right
        ? cross(forward_axis, up_axis) : cross(up_axis, forward_axis);

    if (right_axis.x > 0)
        return SignedAxis.positive_x;
    if (right_axis.x < 0)
        return SignedAxis.negative_x;
    if (right_axis.y > 0)
        return SignedAxis.positive_y;
    if (right_axis.y < 0)
        return SignedAxis.negative_y;
    if (right_axis.z > 0)
        return SignedAxis.positive_z;
    return SignedAxis.negative_z;
}

private i32 axis_dimension(SignedAxis axis) pure
{
    final switch (axis)
    {
        case SignedAxis.positive_x:
        case SignedAxis.negative_x:
            return 0;
        case SignedAxis.positive_y:
        case SignedAxis.negative_y:
            return 1;
        case SignedAxis.positive_z:
        case SignedAxis.negative_z:
            return 2;
    }
}

private Vector3 direction_from_yaw_pitch_axes(
    Vector3 forward_axis,
    Vector3 right_axis,
    Vector3 up_axis,
    f32 yaw,
    f32 pitch,
)
{
    require(yaw.is_finite && pitch.is_finite, "direction angles must be finite");

    const yaw_sine = sin(yaw);
    const yaw_cosine = cos(yaw);
    const pitch_sine = sin(pitch);
    const pitch_cosine = cos(pitch);
    return forward_axis * (yaw_cosine * pitch_cosine)
        + right_axis * (yaw_sine * pitch_cosine)
        + up_axis * pitch_sine;
}

unittest
{
    assert(get_world_right(rh_z_up_y_forward) == Vector3.unit_x);
    assert(get_world_forward(rh_z_up_y_forward) == Vector3.unit_y);
    assert(get_world_up(rh_z_up_y_forward) == Vector3.unit_z);
    assert(get_world_left(rh_z_up_y_forward) == -Vector3.unit_x);
    assert(get_world_backward(rh_z_up_y_forward) == -Vector3.unit_y);
    assert(get_world_down(rh_z_up_y_forward) == -Vector3.unit_z);
    assert(cross(get_world_right(rh_z_up_y_forward), get_world_forward(rh_z_up_y_forward))
        == get_world_up(rh_z_up_y_forward));

    assert(get_world_right(rh_y_up_negative_z_forward) == Vector3.unit_x);
    assert(get_world_forward(rh_y_up_negative_z_forward) == -Vector3.unit_z);
    assert(get_world_up(rh_y_up_negative_z_forward) == Vector3.unit_y);

    const negative_right = CoordinateSystem(
        handedness: Handedness.right,
        forward: SignedAxis.positive_x,
        up: SignedAxis.positive_z,
    );
    assert(get_world_right(negative_right) == -Vector3.unit_y);
}

unittest
{
    assert(get_world_right(lh_y_up_z_forward) == Vector3.unit_x);
    assert(get_world_forward(lh_y_up_z_forward) == Vector3.unit_z);
    assert(get_world_up(lh_y_up_z_forward) == Vector3.unit_y);
    assert(cross(get_world_right(lh_y_up_z_forward), get_world_forward(lh_y_up_z_forward))
        == -get_world_up(lh_y_up_z_forward));
}

unittest
{
    const quarter_turn = pi / 2;
    assert(xtb.math.vector.approximately_equal(
        direction_from_yaw_pitch(rh_z_up_y_forward, 0, 0),
        get_world_forward(rh_z_up_y_forward),
        1e-6f,
        1e-6f,
    ));
    assert(xtb.math.vector.approximately_equal(
        direction_from_yaw_pitch(rh_z_up_y_forward, quarter_turn, 0),
        get_world_right(rh_z_up_y_forward),
        1e-6f,
        1e-6f,
    ));
    assert(xtb.math.vector.approximately_equal(
        direction_from_yaw_pitch(rh_z_up_y_forward, 0, quarter_turn),
        get_world_up(rh_z_up_y_forward),
        1e-6f,
        1e-6f,
    ));
    assert(xtb.math.vector.approximately_equal(
        direction_from_yaw_pitch(lh_y_up_z_forward, quarter_turn, 0),
        get_world_right(lh_y_up_z_forward),
        1e-6f,
        1e-6f,
    ));
    assert(xtb.math.vector.approximately_equal(
        direction_from_yaw_pitch(rh_y_up_negative_z_forward, 0, 0),
        -Vector3.unit_z,
        1e-6f,
        1e-6f,
    ));
}
