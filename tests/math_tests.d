module tests.math_tests;

import xtb.math;
import xtb.types;

import lh_math = tests.support.math_lh_y_up;
import lh_math_consumer = tests.support.math_lh_y_up_consumer;
import rh_math = tests.support.math_rh_z_up;
import rh_math_consumer = tests.support.math_rh_z_up_consumer;

static assert(!__traits(compiles, Quaternion.from_yaw_pitch_roll(0, 0, 0)));
static assert(!__traits(compiles, rotation_yaw_pitch_roll(0, 0, 0)));
static assert(!__traits(compiles, look_at(Vector3.init, Vector3.unit_z, Vector3.unit_y)));
static assert(!__traits(compiles, direction_from_yaw_pitch(0.0f, 0.0f)));
static assert(!__traits(compiles, ConfiguredMath!rh_z_up_y_forward));
static assert(!__traits(compiles, world_forward(rh_z_up_y_forward)));
static assert(!__traits(compiles, rh_math.world_forward()));

version (Posix)
{
    import core.stdc.signal;
    import core.sys.posix.fcntl;
    import core.sys.posix.sys.wait;
    import core.sys.posix.unistd;
}

version (Posix)
{
    private bool invalid_random_bound_panics() nothrow @nogc
    {
        const process = fork();
        if (process < 0) return false;

        if (process == 0)
        {
            const sink = open("/dev/null".ptr, O_WRONLY);
            if (sink >= 0)
            {
                cast(void) dup2(sink, STDERR_FILENO);
                close(sink);
            }

            auto random = Random.seeded(1);
            random.below(0);
            _exit(0);
        }

        i32 status;
        return waitpid(process, &status, 0) == process && (status & 0x7f) == SIGABRT;
    }
}

private bool overload_sets_resolve() nothrow @nogc @safe
{
    const vector_clamped = clamp(Vector2(3, -2), Vector2(0, 0), Vector2(2, 2));
    const quarter_turn = Quaternion.from_axis_angle(Vector3(0, 0, 1), pi / 2);
    const transform = trs(Vector3(1, 2, 3), quarter_turn, Vector3(2, 2, 2));

    return min(3.0f, 7.0f) == 3.0f
        && min(Vector2(3, -2), Vector2(1, 4)) == Vector2(1, -2)
        && max(3.0f, 7.0f) == 7.0f
        && max(Vector2(3, -2), Vector2(1, 4)) == Vector2(3, 4)
        && clamp(1.5f, 0.0f, 1.0f) == 1.0f
        && vector_clamped == Vector2(2, 0)
        && lerp(0.0f, 2.0f, 0.5f) == 1.0f
        && lerp(Vector2(0, 2), Vector2(2, 4), 0.5f) == Vector2(1, 3)
        && approximately_equal(1.0f, 1.000_001f, 1e-5f, 0)
        && approximately_equal(Vector2(1, 2), Vector2(1.000_001f, 2), 1e-5f, 0)
        && approximately_equal(quarter_turn, quarter_turn, 0, 0)
        && dot(Vector2(1, 2), Vector2(3, 4)) == 11
        && dot(Quaternion.identity, Quaternion.identity) == 1
        && approximately_equal(
            transform.transform_point(Vector3(1, 0, 0)),
            Vector3(1, 4, 3),
            1e-5f,
            1e-5f,
        )
        && is_finite(1.0f)
        && Vector2(1, 2).is_finite;
}

private bool configured_coordinate_systems_resolve() nothrow @nogc @safe
{
    const quarter_turn = pi / 2;
    const rh_forward = rh_math_consumer.configured_world_forward();
    const lh_forward = lh_math_consumer.configured_world_forward();
    const rh_yaw = rh_math_consumer.configured_yaw(quarter_turn);
    const lh_yaw = lh_math_consumer.configured_yaw(quarter_turn);
    const rh_direction = rh_math_consumer.configured_direction(quarter_turn, 0);
    const lh_direction = lh_math_consumer.configured_direction(quarter_turn, 0);
    const explicit_lh_yaw = rh_math.quaternion_from_yaw_pitch_roll(
        lh_y_up_z_forward,
        quarter_turn,
        0,
        0,
    );
    const rh_yaw_matrix = rh_math_consumer.configured_yaw_matrix(quarter_turn);
    const explicit_lh_yaw_matrix = rh_math.rotation_matrix_from_yaw_pitch_roll(
        lh_y_up_z_forward,
        quarter_turn,
        0,
        0,
    );
    const rh_view = rh_math_consumer.configured_view(Vector3.init, rh_forward);
    const lh_view = lh_math_consumer.configured_view(
        Vector3.init,
        lh_forward,
        lh_math_consumer.configured_world_up(),
    );

    return rh_math_consumer.configured_world_right() == Vector3.unit_x
        && rh_forward == Vector3.unit_y
        && rh_math_consumer.configured_world_up() == Vector3.unit_z
        && lh_math_consumer.configured_world_right() == Vector3.unit_x
        && lh_forward == Vector3.unit_z
        && lh_math_consumer.configured_world_up() == Vector3.unit_y
        && approximately_equal(
            rh_direction,
            rh_math_consumer.configured_world_right(),
            1e-5f,
            1e-5f,
        )
        && approximately_equal(
            lh_direction,
            lh_math_consumer.configured_world_right(),
            1e-5f,
            1e-5f,
        )
        && approximately_equal(
            rh_yaw.rotated(rh_forward),
            rh_math_consumer.configured_world_right(),
            1e-5f,
            1e-5f,
        )
        && approximately_equal(
            lh_yaw.rotated(lh_forward),
            lh_math_consumer.configured_world_right(),
            1e-5f,
            1e-5f,
        )
        && approximately_equal(
            explicit_lh_yaw.rotated(lh_forward),
            lh_math_consumer.configured_world_right(),
            1e-5f,
            1e-5f,
        )
        && approximately_equal(
            rh_yaw_matrix.transform_direction(rh_forward),
            rh_math_consumer.configured_world_right(),
            1e-5f,
            1e-5f,
        )
        && approximately_equal(
            explicit_lh_yaw_matrix.transform_direction(lh_forward),
            lh_math_consumer.configured_world_right(),
            1e-5f,
            1e-5f,
        )
        && approximately_equal(
            rh_view.transform_direction(rh_forward),
            Vector3(0, 0, -1),
            1e-5f,
            1e-5f,
        )
        && approximately_equal(
            lh_view.transform_direction(lh_forward),
            Vector3(0, 0, 1),
            1e-5f,
            1e-5f,
        );
}

extern (C) int main()
{
    if (!overload_sets_resolve()) return 1;
    if (!configured_coordinate_systems_resolve()) return 1;

    version (Posix)
    {
        if (!invalid_random_bound_panics()) return 1;
    }

    return 0;
}
