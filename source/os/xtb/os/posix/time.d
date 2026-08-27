module xtb.os.posix.time;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import core.stdc.errno : EINTR, errno;
import core.sys.posix.time : CLOCK_MONOTONIC, CLOCK_REALTIME, clock_gettime,
    nanosleep, timespec;
import xtb.os.error : OsError, OsErrorKind;
import xtb.os.posix.error : lastError;
import xtb.types : i64, u64;

OsError monotonicNanoseconds(u64* output) @system
{
    version (XTB_Checked)
        require(output !is null, "monotonic clock output pointer is null");
    *output = 0;

    timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
        return lastError();
    *output = cast(u64) value.tv_sec * 1_000_000_000UL + value.tv_nsec;
    return OsError.init;
}

OsError wallClockNanoseconds(i64* output) @system
{
    version (XTB_Checked)
        require(output !is null, "wall clock output pointer is null");
    *output = 0;

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

OsError sleepNanoseconds(u64 duration) @system
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
