module xtb.math.configured;

nothrow @nogc @safe:

import xtb.math.coordinate_system;

/// Generates convention-sensitive defaults for an application-owned math facade.
mixin template ConfiguredMath(CoordinateSystem coordinates)
{
    private import xtb.math.coordinate_system;
    private import xtb.math.matrix;
    private import xtb.math.quaternion;
    private import xtb.math.vector;
    private import xtb.types;

    Vector3 get_world_forward() pure nothrow @nogc @safe
    {
        enum axis = xtb.math.coordinate_system.get_world_forward(coordinates);
        return axis;
    }

    Vector3 get_world_backward() pure nothrow @nogc @safe
    {
        enum axis = xtb.math.coordinate_system.get_world_backward(coordinates);
        return axis;
    }

    Vector3 get_world_up() pure nothrow @nogc @safe
    {
        enum axis = xtb.math.coordinate_system.get_world_up(coordinates);
        return axis;
    }

    Vector3 get_world_down() pure nothrow @nogc @safe
    {
        enum axis = xtb.math.coordinate_system.get_world_down(coordinates);
        return axis;
    }

    Vector3 get_world_right() pure nothrow @nogc @safe
    {
        enum axis = xtb.math.coordinate_system.get_world_right(coordinates);
        return axis;
    }

    Vector3 get_world_left() pure nothrow @nogc @safe
    {
        enum axis = xtb.math.coordinate_system.get_world_left(coordinates);
        return axis;
    }

    Vector3 direction_from_yaw_pitch(
        f32 yaw,
        f32 pitch,
    ) nothrow @nogc @safe
    {
        return xtb.math.coordinate_system.direction_from_yaw_pitch!coordinates(yaw, pitch);
    }

    Quaternion quaternion_from_yaw_pitch_roll(
        f32 yaw,
        f32 pitch,
        f32 roll,
    ) nothrow @nogc @safe
    {
        return xtb.math.quaternion.quaternion_from_yaw_pitch_roll!coordinates(
            yaw,
            pitch,
            roll,
        );
    }

    Matrix4 rotation_matrix_from_yaw_pitch_roll(
        f32 yaw,
        f32 pitch,
        f32 roll,
    ) nothrow @nogc @safe
    {
        return Matrix4.from_quaternion(
            quaternion_from_yaw_pitch_roll(yaw, pitch, roll),
        );
    }

    bool try_look_at(
        Vector3 eye,
        Vector3 target,
        Vector3 up,
        Matrix4* output,
    ) nothrow @nogc @system
    {
        static if (coordinates.handedness == Handedness.right)
            return xtb.math.matrix.try_look_at_rh(eye, target, up, output);
        else
            return xtb.math.matrix.try_look_at_lh(eye, target, up, output);
    }

    Matrix4 look_at(
        Vector3 eye,
        Vector3 target,
        Vector3 up,
    ) nothrow @nogc @safe
    {
        static if (coordinates.handedness == Handedness.right)
            return xtb.math.matrix.look_at_rh(eye, target, up);
        else
            return xtb.math.matrix.look_at_lh(eye, target, up);
    }

    Matrix4 look_at(
        Vector3 eye,
        Vector3 target,
    ) nothrow @nogc @safe
    {
        enum up = xtb.math.coordinate_system.get_world_up(coordinates);
        return look_at(eye, target, up);
    }
}
