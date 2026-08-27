# Logging

`Logger` writes levelled records through a `LogSinkRef`. The logger borrows its
sink and message buffer; sinks can be wrapped or combined without changing log
calls.

A basic logger needs only a destination, a buffer, and a minimum level:

```d
char[512] storage;
Logger logger = stderrLogger(storage[], LogLevel.info);

logger.info("server started on port ", 8080);
logger.warningf!"retry {}/{}"(2, 3);
logger.error(i"request $(requestId) failed");
logger.flush(); // Optional: flushes underlying stdio buffers.
```

Filtering happens before message formatting. Use `enabled(level)` when producing
the arguments themselves would be expensive.

Ordinary `info`/`warning`/`logf` calls are bounded by the logger's message
buffer. `LogResult` reports delivery, truncation, filtering, or sink failure.
Use `stream` only for deliberately unbounded diagnostics; there the same buffer
is reused as staging storage.

## Sinks and presentation

| API | Purpose |
|---|---|
| `plainFileLogSink` | file output with ANSI removed |
| `ansiFileLogSink` | ANSI-preserving terminal/file output |
| `PrefixLogSink` | prepend a custom prefix provider |
| `TimestampLogPrefix` | wall-clock prefix provider backed by the `time` subpackage |
| `TeeLogSink` | send each record to two sinks |
| `WithoutCallsiteLogSink` | omit callsites from one sink branch |

`TimestampLogPrefix` reads wall-clock time through `xtb.time`; `log` therefore
depends on `time`, while `time` delegates system clock access to `os`.

A sink graph can give different destinations different presentation and
metadata. This sends ANSI-styled output to the terminal without timestamps or
callsites, while `app.log` receives plain text with both a timestamp and the
callsite:

```d
import core.stdc.stdio : FILE, fclose, fopen, stderr;
import xtb.log;

FILE* terminal = cast(FILE*) stderr;
FILE* logFile = fopen("app.log".ptr, "a".ptr);
if (logFile is null)
    return 1;
scope (exit) fclose(logFile);

// Terminal: ANSI presentation, no timestamp, no callsite.
WithoutCallsiteLogSink terminalSink = WithoutCallsiteLogSink.create(
    ansiFileLogSink(terminal),
);

// File: plain presentation, timestamp prefix, callsite retained.
TimestampLogPrefix timestamp = TimestampLogPrefix.create();
PrefixLogSink fileSink = PrefixLogSink.create(
    plainFileLogSink(logFile),
    timestamp.prefixRef(),
);

TeeLogSink sinks = TeeLogSink.create(
    terminalSink.sinkRef(),
    fileSink.sinkRef(),
);

char[512] storage;
Logger logger = Logger.create(sinks.sinkRef(), storage[], LogLevel.info);
logger.setCallsitesEnabled(true);

logger.info("server started");
logger.flush(); // Optional: flushes underlying stdio buffers.
```

Callsite capture is enabled once on the logger, then removed only from the
terminal branch by `WithoutCallsiteLogSink`. Likewise, the timestamp decorates
only the file branch. The plain file sink strips ANSI styling while the terminal
sink renders it.

`setMinimumLevel`, `setPalette`, `setLevelLabels`,
`setMessageAlignmentEnabled`, and `setCallsitesEnabled` change logger policy
without rebuilding the sink graph.

Sink decorators borrow their children. Stateful decorators such as
`PrefixLogSink` and `TeeLogSink` must remain at a stable address and outlive any
`sinkRef()` taken from them.

See [`logging_demo.d`](../../../examples/logging_demo.d) for timestamp prefixes,
tee fan-out, streaming, callsites, palettes, and the optional thread-local
logger.
