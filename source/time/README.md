# time

`time` owns wall-clock timestamps, monotonic instants, timeout value semantics,
and sleeping. Platform clock and sleep mechanisms are supplied by `xtb.os`.

```d
const timestamp = Timestamp.now();
const started = Instant.now();
sleep(milliseconds(5));
const elapsed = Instant.now().since(started);
const timeout = Timeout.after(milliseconds(250));
```

`Timestamp` is wall-clock time relative to the Unix epoch and can move when the
system clock changes. `Instant` uses the system monotonic clock and is intended
for measuring elapsed time. Clock sampling and sleeping are infallible at this
API level; an unexpected platform failure panics.
