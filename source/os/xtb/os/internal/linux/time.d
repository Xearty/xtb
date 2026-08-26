module xtb.os.internal.linux.time;

nothrow @nogc:

import core.stdc.errno : EINTR, errno;
import core.sys.posix.time : CLOCK_MONOTONIC, CLOCK_REALTIME, clock_gettime, nanosleep, timespec;
import xtb.types : i64, u64;
import xtb.os.error : OsError, OsErrorKind, lastError;

package(xtb.os) OsError monotonicNanosecondsImpl(u64* output) @system
{
    timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
        return lastError();
    *output = cast(u64) value.tv_sec * 1_000_000_000UL + value.tv_nsec;
    return OsError.init;
}

package(xtb.os) OsError wallClockNanosecondsImpl(i64* output) @system
{
    timespec value;
    if (clock_gettime(CLOCK_REALTIME, &value) != 0)
        return lastError();
    const seconds = cast(i64) value.tv_sec;
    enum i64 nanosecondsPerSecond = 1_000_000_000L;
    if (seconds < i64.min / nanosecondsPerSecond ||
        seconds > i64.max / nanosecondsPerSecond)
        return OsError(OsErrorKind.invalidArgument, 0);
    *output = seconds * nanosecondsPerSecond + cast(i64) value.tv_nsec;
    return OsError.init;
}

package(xtb.os) OsError sleepNanosecondsImpl(u64 duration) @system
{
    timespec remaining;
    remaining.tv_sec = cast(typeof(remaining.tv_sec))(duration / 1_000_000_000UL);
    remaining.tv_nsec = cast(typeof(remaining.tv_nsec))(duration % 1_000_000_000UL);
    for (;;)
    {
        timespec next;
        if (nanosleep(&remaining, &next) == 0)
            return OsError.init;
        if (errno != EINTR)
            return lastError();
        remaining = next;
    }
}
