# time

`time` provides wall-clock timestamps and monotonic instants for elapsed-time
measurement.

```d
const timestamp = Timestamp.now();
const started = Instant.now();
// ... work ...
const elapsed = Instant.now().since(started);
```

`Timestamp` is wall-clock time relative to the Unix epoch and can move when the
system clock changes. `Instant` uses the system monotonic clock and is intended
for measuring elapsed time. Clock sampling is infallible at this API level; an
unexpected platform clock failure panics.
