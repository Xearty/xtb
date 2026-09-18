module tests.support.math_lh_y_up_consumer;

nothrow @nogc @safe:

import tests.support.math_lh_y_up;
import xtb.types;

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

Matrix4 configured_view(Vector3 eye, Vector3 target, Vector3 up)
{
    return look_at(eye, target, up);
}
