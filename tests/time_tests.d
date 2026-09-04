module tests.time_tests;

import xtb.time;

extern (C) int main()
{
    import xtb.duration : milliseconds;

    if (!Timeout.init.isInfinite || !Timeout.after(milliseconds(1)).isFinite)
        return 1;
    const timestamp = Timestamp.now();
    if (timestamp.nanosecondsSinceUnixEpoch == 0)
        return 1;

    const before = Instant.now();
    sleep(milliseconds(1));
    const after = Instant.now();
    if (after < before)
        return 1;

    return after.since(before).total_nanoseconds <= after.nanoseconds ? 0 : 1;
}
