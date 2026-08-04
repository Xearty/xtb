module tests.math_tests;

import xtb.math.matrix;
import xtb.math.random;
import xtb.math.noise;
import xtb.math.scalar;
import xtb.math.vector;

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

extern (C) int main()
{
    static foreach (testFunction; __traits(getUnitTests, xtb.math.scalar))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.math.vector))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.math.matrix))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.math.random))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.math.noise))
        testFunction();
    version (Posix)
        if (!invalidRandomBoundPanics())
            return 1;
    return 0;
}
