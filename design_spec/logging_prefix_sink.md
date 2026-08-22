# Logging record-prefix sink and OS timestamp design specification

> **Protocol note (2026-08-22):** Prefix delivery now uses the record-resolution
> model in `design_spec/logging_record_resolution.md`. This document retains the
> prefix/timestamp rationale and is updated here where the current semantics
> differ from the original whole-graph event implementation.


## Status

**Status: implemented.**

This is a companion to `design_spec/logging_sink_fanout.md`. It defines a generic record-prefix decorator in `xtb.core` and an initial date/time prefix provider in `xtb.os`.

Maintain this document with the implementation whenever the public API, lifecycle rules, timestamp format, style defaults, failure semantics, or composition behavior changes.

## Decision summary

- Add a generic `PrefixLogSink` in `xtb.core.logging`.
- Prefix insertion is driven by explicit `beginRecord`; there is no first-chunk inference.
- A prefix provider writes styled setup text through a restricted `LogPrefixWriter` and the already-resolved child record.
- Prefix providers may use stack storage because delivery is synchronous; the prefix sink does not allocate or own prefix text.
- `LogPrefixWriter.write` accepts ANSI-free bytes plus out-of-band `AnsiStyle`; `writeAnsi` explicitly accepts bytes that may contain supported embedded SGR.
- ANSI sinks render/preserve prefix styling; plain sinks ignore semantic style and strip supported embedded SGR.
- The first provider is a wall-clock timestamp implementation in `xtb.os.logging`.
- Timestamp color/style is configurable. The default is subdued gray; `AnsiStyle.init` disables styling.
- Prefix placement determines scope: wrapping one tee branch affects only that destination; wrapping the tee affects all branches.
- Prefix failure after the child has begun a record is deferred until `endRecord`, so the actual log record can still be delivered and finalized.

## Motivation

The immediate use case is a timestamp in a logfile without showing it in the interactive terminal:

```text
                         +--> ANSI terminal sink
                         |      [info] server started
Logger --> TeeLogSink ---+
                         |
                         +--> PrefixLogSink(timestamp)
                                  |
                                  +--> plain file sink
                                       2026-08-21 02:17:03 [info] server started
```

The logger must not generate this timestamp because logger-generated text is upstream of `TeeLogSink` and would therefore appear in every destination.

A destination-specific prefix is a sink-composition concern.

The generic abstraction should also be reusable later for thread IDs, process IDs, subsystem names, request IDs, elapsed time, or combined metadata prefixes.

## Goals

The design should:

- remain `-betterC`, `nothrow`, `@nogc`, and allocation-free;
- preserve the existing explicit sink lifecycle;
- keep OS wall-clock access out of `xtb.core`;
- allow dynamic prefixes without persistent string ownership;
- preserve logger-owned level labels and message framing;
- keep prefix presentation independent of text generation;
- allow the same prefix provider to feed ANSI and plain destinations;
- compose with `TeeLogSink` without modifying tee semantics;
- keep a file sink's record lock around both the prefix and the record body;
- preserve record cleanup after prefix failure; and
- impose zero overhead on loggers that do not use a prefix decorator.

## Non-goals

The initial design does not add:

- timestamps or timestamp flags to `Logger`;
- timestamp knowledge to `TeeLogSink`;
- timestamp generation to plain/ANSI file sinks;
- a structured metadata dictionary;
- dynamically allocated prefix strings;
- arbitrary `strftime`-style format strings;
- asynchronous prefix formatting; or
- timestamp-specific embedded ANSI generation (the generic prefix writer permits embedded supported SGR).

## Current logging contract

`LogSinkRef.beginRecord(info)` resolves the sink graph once into a short-lived
`LogRecordRef`. `PrefixLogSink` resolves its child, emits its prefix through that
resolved record, then returns the child record unchanged. It therefore performs
no work on later message chunks.

`LogRecordRef.writeText(bytes, style)` is the ANSI-free fast path used by normal
framing and semantic-style-only prefixes. `writeAnsiText` explicitly marks setup
bytes as potentially containing supported embedded SGR. Plain presentation strips
that SGR; ANSI presentation preserves it and restores the supplied semantic style
after complete resets.

## Core design

### `LogPrefixWriter`

A provider receives a deliberately restricted writer:

```d
struct LogPrefixWriter
{
    bool write(
        return scope String bytes,
        AnsiStyle style = AnsiStyle.init,
    );

    bool writeAnsi(
        return scope String bytes,
        AnsiStyle style = AnsiStyle.init,
    );
}
```

`write` synchronously submits ANSI-free setup text to a child record that has already accepted `beginRecord`; its color/style is carried out-of-band. `writeAnsi` is the explicit variant for bytes that may contain supported embedded SGR. Each ANSI span is terminated with a full reset by ANSI presentation so style cannot leak into later prefix/logger framing. One supported SGR sequence must not be split across two `writeAnsi` calls.

The writer exposes no record/message lifecycle operations. A prefix callback therefore cannot accidentally begin a second record, open a message, or finalize the child.

Because submission is synchronous, stack-backed prefix text is valid:

```d
bool timestampPrefix(void* context, LogPrefixWriter* output)
{
    char[64] storage;
    // Format timestamp into storage.
    return output.write(storage[0 .. used], style);
}
```

The child must consume the borrowed bytes before `write` returns, matching the existing synchronous sink contract.

### Prefix callback and reference

```d
alias LogPrefix = bool function(
    void* context,
    LogPrefixWriter* output,
) nothrow @nogc;

struct LogPrefixRef
{
    static LogPrefixRef create(LogPrefix prefix, void* context);

    bool valid() const;
    bool write(LogPrefixWriter* output);
}
```

`LogPrefixRef` is copyable and non-owning, analogous to `LogSinkRef`.

A provider may emit zero, one, or several text spans. Multiple spans allow one logical prefix to contain differently styled fields in the future.

### `PrefixLogSink`

```d
struct PrefixLogSink
{
    @disable this(this);

    static PrefixLogSink create(
        LogSinkRef child,
        LogPrefixRef prefix,
    );

    bool valid() const;
    LogSinkRef sinkRef() return;
}
```

`PrefixLogSink` is non-copyable because `sinkRef()` borrows its stable address. It does not remain in the active message path: deferred prefix failure is attached to the resolved child record before that record is returned.

It borrows both the child sink and prefix provider. After `sinkRef()` is taken, the wrapper must remain at a stable address and outlive all derived sink references.

## Lifecycle semantics

For a normal logger record:

```text
beginRecord
text("[info]", infoStyle)
text(" ")
beginMessage(...)
messageChunk("started")
endMessage
text("\n")
endRecord
```

`PrefixLogSink` delivers:

```text
beginRecord
text(prefix...)
text("[info]", infoStyle)
text(" ")
beginMessage(...)
messageChunk("started")
endMessage
text("\n")
endRecord
```

All logger events after the injected prefix are forwarded unchanged.

### Child rejects `beginRecord`

If the child rejects `beginRecord`:

- no child record exists;
- the prefix provider is not invoked;
- `PrefixLogSink` reports the rejection immediately; and
- it does not invent cleanup events.

### Prefix generation/delivery fails

If the child accepted `beginRecord` but the prefix callback or one of its writes fails:

1. mark the current record failed;
2. continue forwarding later logger events while the child record remains active;
3. preserve matching message/record finalization; and
4. return failure when `endRecord` completes.

This mirrors the tee's deferred-failure philosophy: metadata failure should not strand the record or unnecessarily hide the actual log message.

A provider should format indivisible values such as a timestamp completely before its first `write`, because already-emitted prefix bytes cannot be rolled back.

Failure state is record-local and must reset after `endRecord`.

## Timestamp provider in `xtb.os`

Wall-clock acquisition belongs outside core. The initial logging-specific provider should live in:

```text
xtb.os.logging
```

It may use `xtb.os.time.wallClockNanoseconds` and platform calendar conversion internally.

The OS package should use reentrant conversion functions such as `localtime_r`/`gmtime_r` on POSIX; process-global `localtime`/`gmtime` buffers are not acceptable for concurrent logging.

### Proposed API

```d
enum LogTimestampZone : ubyte
{
    local,
    utc,
}

struct LogTimestampOptions
{
    LogTimestampZone zone;
    bool milliseconds;
    AnsiStyle style;
    String separator;

    static LogTimestampOptions defaults();
}

struct TimestampLogPrefix
{
    @disable this(this);

    static TimestampLogPrefix create(
        LogTimestampOptions options = LogTimestampOptions.defaults(),
    );

    LogPrefixRef prefixRef() return;
}
```

The provider formats into fixed stack storage for each record and synchronously passes the resulting slice to `LogPrefixWriter`. No heap storage is required.

The fixed buffer size should be compile-time sufficient for every supported built-in timestamp format.

### Timestamp format

The first implementation should use stable, sortable fixed formats rather than locale-dependent or arbitrary format strings.

Default local form:

```text
YYYY-MM-DD HH:MM:SS
```

UTC form:

```text
YYYY-MM-DDTHH:MM:SSZ
```

With `milliseconds = true`:

```text
YYYY-MM-DD HH:MM:SS.mmm
YYYY-MM-DDTHH:MM:SS.mmmZ
```

`zone` should initially default to `local` for human-oriented application logs. Applications requiring canonical cross-machine logs can select `utc`.

Arbitrary formatting can be proposed later if a real use case justifies the extra parsing and buffer-policy complexity.

## Configurable timestamp color

Timestamp style is presentation configuration, not part of timestamp text.

`LogTimestampOptions.style` determines the `AnsiStyle` attached to the timestamp `text` event.

The default should be a subdued gray metadata style, initially:

```d
AnsiStyle.foreground(AnsiColor.brightBlack).dim
```

The exact default may be tuned against the logging palette presets during implementation, but it should remain visually subordinate to the level label and message.

The caller may choose any existing `AnsiStyle`, for example a plain 4-bit gray:

```d
LogTimestampOptions options = LogTimestampOptions.defaults();
options.style = AnsiStyle.foreground(AnsiColor.brightBlack);
```

or true color:

```d
options.style = AnsiStyle
    .foreground(AnsiColor.rgb(128, 128, 128))
    .dim;
```

or no style at all:

```d
options.style = AnsiStyle.init;
```

The timestamp provider itself uses semantic `AnsiStyle` rather than generating SGR bytes, although generic prefix providers may emit supported embedded SGR when useful.

### ANSI destination

An ANSI sink receives semantic text plus style:

```text
text("2026-08-21 02:17:03", timestampStyle)
```

and renders the style using the existing styled-text path.

### Plain destination

A plain sink receives the same prefix bytes but ignores semantic style and strips supported embedded SGR:

```text
2026-08-21 02:17:03
```

Changing timestamp color can therefore never change logfile bytes.

## Separator

The timestamp provider stores a borrowed separator view. A custom separator must outlive the `TimestampLogPrefix` and every use of its `LogPrefixRef`. `LogTimestampOptions.separator` defaults to one ASCII space:

```d
options.separator = " ";
```

The recommended rendering is:

```text
<timestamp style>2026-08-21 02:17:03</reset> [info] message
```

so the separator is emitted as a separate unstyled span rather than extending the timestamp style into the level label.

## Composition

### Timestamp only the logfile

This is the current intended configuration:

```d
char[1024] logStorage;

TimestampLogPrefix timestamp = TimestampLogPrefix.create();

PrefixLogSink timestampedFile = PrefixLogSink.create(
    plainFileLogSink(logFile),
    timestamp.prefixRef(),
);

TeeLogSink output = TeeLogSink.create(
    ansiFileLogSink(stderr),
    timestampedFile.sinkRef(),
);

Logger logger = Logger.create(
    output.sinkRef(),
    logStorage[],
    LogLevel.debug_,
);
```

Result:

```text
terminal:
[info] server started

logfile:
2026-08-21 02:17:03 [info] server started
```

The timestamp's configured style is intentionally ignored by the plain branch.

### Timestamp both destinations

Move the prefix wrapper outside the tee:

```text
Logger
  |
PrefixLogSink(timestamp)
  |
TeeLogSink
  +--> ANSI sink
  +--> plain sink
```

Result:

```text
ANSI terminal:
<configured timestamp style>2026-08-21 02:17:03</reset> [info] server started

plain file:
2026-08-21 02:17:03 [info] server started
```

This is why timestamp styling belongs to the semantic prefix event instead of an ANSI-specific timestamp implementation.

### Timestamp only the terminal

The same `PrefixLogSink` can decorate only the ANSI branch. No new provider type is necessary.

### Multiple prefix fields

One `LogPrefix` callback may emit multiple spans, which is the preferred way to guarantee ordering for a composite prefix:

```text
<timestamp> <thread-id> <subsystem> [level] message
```

Nested `PrefixLogSink` wrappers are valid, but their observable order follows lifecycle nesting: an inner prefix is emitted while the outer wrapper is forwarding `beginRecord`, before the outer prefix callback runs. When field order matters, prefer one provider that emits the complete ordered prefix.

## Interaction with `TeeLogSink`

`TeeLogSink` needs no special handling.

A prefix wrapper is simply another child sink. Existing tee failure isolation therefore applies:

- timestamp failure on the file branch must not prevent terminal delivery;
- an already-begun file record must still be finalized; and
- aggregate branch failure is reported using the tee's existing `endRecord` semantics.

This is an important composability property: destination-specific metadata requires no changes to `Logger` or tee.

## Threading and file atomicity

`PrefixLogSink` keeps no per-record state after resolution. Its address must still remain stable because `sinkRef()` borrows it; provider and child thread-safety requirements continue to apply.

Separate thread-confined prefix/tee/logger objects may still share a synchronized file destination.

The prefix is emitted after the child accepts `beginRecord`. A file presentation sink that acquires its file lock in `beginRecord` therefore keeps the complete record under one lock:

```text
lock
  timestamp
  level label
  message
  newline
unlock
```

A timestamp from one thread cannot be separated from its record body by another thread's output.

## Error policy

The initial policy should make prefix failures observable while preserving the record:

- wall-clock failure -> provider returns `false`;
- calendar conversion/format failure -> provider returns `false`;
- prefix-text rejection -> wrapper records failure;
- remaining record content is still forwarded when the child record exists;
- `endRecord` is still attempted; and
- failure is reported at record completion.

The implementation must not fabricate a timestamp such as `????-??-??`.

If a future user wants best-effort silent omission, that should be an explicit provider policy rather than the core default.

## Performance

Without a prefix wrapper there is no new work.

A timestamped record adds only:

- one prefix callback;
- one OS wall-clock read;
- one calendar conversion;
- fixed-size stack formatting;
- one styled timestamp `text` event;
- one separator `text` event; and
- the corresponding output bytes.

There is no heap allocation, message copy, or message reformatting.

Timestamp color itself adds no ANSI scan: the timestamp provider uses the
ANSI-free `write(..., style)` path. ANSI sinks render the semantic style and
plain sinks ignore it directly. Only a provider that explicitly calls
`writeAnsi` pays the supported-SGR scan required for preservation/stripping.

## Required tests

### Core prefix decorator

Cover:

- exact successful event ordering;
- zero-, one-, and multi-span prefixes;
- styled and unstyled spans;
- child `beginRecord` rejection;
- provider failure before output;
- provider failure after partial output;
- child rejection of each prefix span;
- later child failure after a successful prefix;
- matching message/record cleanup;
- failure isolation to one record;
- direct `LogSinkRef` use;
- flush forwarding;
- nesting with tee in both directions;
- prefix only on one tee branch;
- prefix upstream of the tee; and
- compile-time non-copyability/lifetime constraints.

### Timestamp provider

Use an injectable fixed clock internally for deterministic tests. Cover:

- local and UTC forms;
- seconds and milliseconds;
- date boundaries and leap days;
- configured separator;
- default subdued-gray style;
- custom 4-bit style;
- custom RGB style;
- `AnsiStyle.init`;
- clock failure;
- conversion failure where injectable; and
- buffer bounds.

### End-to-end graphs

Verify:

```text
Logger -> Tee(
    ANSI terminal,
    Prefix(timestamp) -> plain file
)
```

with:

- no timestamp in terminal;
- timestamp in file;
- no ANSI bytes in file; and
- unchanged level/message styling in terminal.

Also verify:

```text
Logger -> Prefix(timestamp) -> Tee(ANSI terminal, plain file)
```

with:

- identical timestamp text in both destinations;
- configured timestamp style visible only in ANSI output;
- no timestamp ANSI bytes in the plain file; and
- record-level atomicity under concurrent writers.

## Suggested implementation order

The implementation was completed in two independently test-complete stages.

### Step 1 — core prefix composition — complete

Implemented and tested:

- `LogPrefixWriter`;
- `LogPrefix` and `LogPrefixRef`;
- `PrefixLogSink`;
- deferred prefix-failure semantics;
- tee composition; and
- core exports/docs.

No OS dependency belongs in this step.

### Step 2 — OS timestamp provider — complete

Implemented and tested:

- `xtb.os.logging`;
- wall-clock/calendar conversion;
- local/UTC fixed timestamp forms;
- configurable timestamp `AnsiStyle`;
- default subdued-gray style;
- examples for file-only and shared timestamp placement; and
- OS exports/docs.

## Rejected alternatives

### Timestamp option on `Logger`

Rejected because it makes destination-specific metadata global to every branch after fan-out.

### Timestamp logic in `TeeLogSink`

Rejected because tee is intentionally metadata- and presentation-agnostic.

### Timestamp logic in the file sink

Rejected because file presentation should remain generic and timestamping should compose with arbitrary destinations.

### ANSI bytes embedded in timestamp text

Rejected because the timestamp already has an out-of-band `AnsiStyle`; embedding SGR would force plain sinks to remove presentation bytes that never needed to exist.

### Hard-coded timestamp color in `PrefixLogSink`

Rejected because prefix styling is provider configuration. The timestamp helper supplies a default, not a core policy.

### Prefix insertion on the first chunk

Rejected because explicit `beginRecord` exists specifically to avoid first-chunk heuristics and remains correct under chunking and composition.
