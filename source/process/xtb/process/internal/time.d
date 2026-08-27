module xtb.process.internal.time;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.types : u64;

version (Posix)
{
    import xtb.os.posix.time : posixMonotonicNanoseconds = monotonicNanoseconds,
        posixSleepNanoseconds = sleepNanoseconds;

    package(xtb.process) OsError monotonicNanoseconds(u64* output) @system
    {
        return posixMonotonicNanoseconds(output);
    }

    package(xtb.process) OsError sleepNanoseconds(u64 duration) @system
    {
        return posixSleepNanoseconds(duration);
    }
}
else
{
    package(xtb.process) OsError monotonicNanoseconds(u64* output) @system
    {
        if (output !is null)
            *output = 0;
        return unsupported();
    }

    package(xtb.process) OsError sleepNanoseconds(u64) pure @safe
    {
        return unsupported();
    }
}
