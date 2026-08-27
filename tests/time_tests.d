module tests.time_tests;

import xtb.time;

extern (C) int main()
{
    Timestamp timestamp;
    if (Timestamp.now(&timestamp).failed ||
        timestamp.nanosecondsSinceUnixEpoch == 0)
        return 1;

    Instant before;
    Instant after;
    if (Instant.now(&before).failed ||
        Instant.now(&after).failed ||
        after < before)
        return 1;

    return after.since(before).totalNanoseconds <= after.nanoseconds ? 0 : 1;
}
