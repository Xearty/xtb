module tests.support.math_rh_z_up_consumer;

nothrow @nogc @safe:

import tests.support.math_rh_z_up;
import xtb.types;

static assert(__traits(compiles, get_world_forward()));
static assert(__traits(compiles, get_world_forward(rh_z_up_y_forward)));
static assert(__traits(compiles, direction_from_yaw_pitch(0.0f, 0.0f)));
static assert(__traits(compiles, direction_from_yaw_pitch(
    rh_z_up_y_forward,
    0.0f,
    0.0f,
)));
static assert(__traits(compiles, quaternion_from_yaw_pitch_roll(0.0f, 0.0f, 0.0f)));
static assert(__traits(compiles, quaternion_from_yaw_pitch_roll(
    rh_z_up_y_forward,
    0.0f,
    0.0f,
    0.0f,
)));

Vector3 configured_world_forward()
{
    return get_world_forward();
}

Vector3 configured_world_right()
{
    return get_world_right();
}

Vector3 configured_world_up()
{
    return get_world_up();
}

Vector3 configured_direction(f32 yaw, f32 pitch)
{
    return direction_from_yaw_pitch(yaw, pitch);
}

Quaternion configured_yaw(f32 yaw)
{
    return quaternion_from_yaw_pitch_roll(yaw, 0, 0);
}

Matrix4 configured_yaw_matrix(f32 yaw)
{
    return rotation_matrix_from_yaw_pitch_roll(yaw, 0, 0);
}

Matrix4 configured_view(Vector3 eye, Vector3 target, Vector3 up)
{
    return look_at(eye, target, up);
}

Matrix4 configured_view(Vector3 eye, Vector3 target)
{
    return look_at(eye, target);
}
