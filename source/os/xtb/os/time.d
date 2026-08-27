module xtb.os.time;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.types : i64, u64;
import xtb.os.error : OsError;

version (linux)
    private import backend = xtb.os.internal.linux.time;
else
    private import backend = xtb.os.internal.unsupported.time;

OsError monotonicNanoseconds(u64* output) @system
{
    version (XTB_Checked)
        require(output !is null, "monotonic clock output pointer is null");
    *output = 0;
    return backend.monotonicNanosecondsImpl(output);
}

OsError wallClockNanoseconds(i64* output) @system
{
    version (XTB_Checked)
        require(output !is null, "wall clock output pointer is null");
    *output = 0;
    return backend.wallClockNanosecondsImpl(output);
}

OsError sleepNanoseconds(u64 duration) @system
{
    return backend.sleepNanosecondsImpl(duration);
}
