module tests.time_tests;

import xtb.time;

extern (C) int main()
{
    const timestamp = Timestamp.now();
    if (timestamp.nanosecondsSinceUnixEpoch == 0)
        return 1;

    const before = Instant.now();
    const after = Instant.now();
    if (after < before)
        return 1;

    return after.since(before).totalNanoseconds <= after.nanoseconds ? 0 : 1;
}
