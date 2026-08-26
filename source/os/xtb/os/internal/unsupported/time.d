module xtb.os.internal.unsupported.time;

nothrow @nogc:

import xtb.types : i64, u64;
import xtb.os.error : OsError, unsupported;

package(xtb.os) OsError monotonicNanosecondsImpl(u64*) @system
{
    return unsupported();
}

package(xtb.os) OsError wallClockNanosecondsImpl(i64*) @system
{
    return unsupported();
}

package(xtb.os) OsError sleepNanosecondsImpl(u64) @system
{
    return unsupported();
}
