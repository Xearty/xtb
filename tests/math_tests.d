module tests.math_tests;

import xtb;
import xtb.math;

version (Posix)
{
    import core.stdc.signal : SIGABRT;
    import core.sys.posix.fcntl : O_WRONLY, open;
    import core.sys.posix.sys.wait : waitpid;
    import core.sys.posix.unistd : STDERR_FILENO, _exit, close, dup2, fork;
}

version (Posix) private bool invalidRandomBoundPanics() nothrow @system @nogc
{
    const process = fork();
    if (process < 0)
        return false;
    if (process == 0)
    {
        const sink = open("/dev/null".ptr, O_WRONLY);
        if (sink >= 0)
        {
            cast(void) dup2(sink, STDERR_FILENO);
            close(sink);
        }
        Random random = Random.seeded(1);
        random.below(0);
        _exit(0);
    }

    int status;
    return waitpid(process, &status, 0) == process &&
        (status & 0x7f) == SIGABRT;
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
        && isFinite(1.0f)
        && isFinite(Vector2(1, 2));
}

extern (C) int main()
{
    if (!overload_sets_resolve())
        return 1;
    version (Posix)
        if (!invalidRandomBoundPanics())
            return 1;
    return 0;
}
