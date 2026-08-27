# time

`time` provides wall-clock timestamps and monotonic instants for elapsed-time
measurement.

```d
Timestamp timestamp;
if (Timestamp.now(&timestamp).failed)
    return 1;

Instant started;
if (Instant.now(&started).failed)
    return 1;
```

`Timestamp` is wall-clock time relative to the Unix epoch and can move when the
system clock changes. `Instant` uses the system monotonic clock and is intended
for measuring elapsed time.
