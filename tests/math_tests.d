module tests.math_tests;

import xtb.math;
import xtb.types;

version (Posix)
{
    import core.stdc.signal;
    import core.sys.posix.fcntl;
    import core.sys.posix.sys.wait;
    import core.sys.posix.unistd;
}

version (Posix)
{
    private bool invalid_random_bound_panics() nothrow @nogc @system
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
        return waitpid(process, &status, 0) == process
            && (status & 0x7f) == SIGABRT;
    }
}

private bool overload_sets_resolve() nothrow @nogc @safe
{
    const vector_clamped = clamp(
        Vector2(3, -2),
        Vector2(0, 0),
        Vector2(2, 2),
    );

    return min(3.0f, 7.0f) == 3.0f
        && min(Vector2(3, -2), Vector2(1, 4)) == Vector2(1, -2)
        && max(3.0f, 7.0f) == 7.0f
        && max(Vector2(3, -2), Vector2(1, 4)) == Vector2(3, 4)
        && clamp(1.5f, 0.0f, 1.0f) == 1.0f
        && vector_clamped == Vector2(2, 0)
        && lerp(0.0f, 2.0f, 0.5f) == 1.0f
        && lerp(Vector2(0, 2), Vector2(2, 4), 0.5f) == Vector2(1, 3)
        && is_finite(1.0f)
        && Vector2(1, 2).is_finite;
}

extern (C) int main()
{
    if (!overload_sets_resolve()) return 1;

    version (Posix)
    {
        if (!invalid_random_bound_panics()) return 1;
    }

    return 0;
}
