# Logging sink fan-out and ANSI presentation design specification

> **Protocol note (2026-08-22):** The repeated whole-graph `LogSinkEvent`
> dispatch described here has been superseded by the record-resolution model in
> `design_spec/logging_record_resolution.md`. This document remains useful as
> historical rationale for the fan-out/prefix behavior it introduced.


## Status and maintenance

**Status: historical. The original Steps 1–4 were implemented and verified,
then the whole-graph delivery protocol was superseded by record resolution.**

This document records the rationale and contracts established by the original
sink-fanout work. It is no longer the authoritative description of the current
delivery protocol; use `design_spec/logging_record_resolution.md` and
`docs/architecture.md` for that. Sections below intentionally retain the old
protocol vocabulary so the design history remains reviewable.

The design evolved the earlier record-at-once sink proposal. Its key decisions
at that stage were:

- there is no `TeeLogger` containing multiple `Logger` values;
- fan-out remains a sink/output-composition concern;
- sinks never invent the log-level label or future timestamp/date text;
- the logger owns textual log framing and supplies presentation styles as
  out-of-band sink operations;
- formatted message bytes are forwarded verbatim from formatter storage;
- message styling uses embedded ANSI SGR bytes rather than style-span metadata;
- logger-generated label/metadata styling remains out-of-band and therefore can
  disappear completely in a plain destination;
- an optional per-level base message style may be applied by an ANSI sink;
- no formatter metadata such as `hasAnsi`, style spans, or ANSI flags is added;
- supported well-formed SGR sequences must not be divided at sink chunk
  boundaries;
- chunk-boundary normalization is a logger/plumbing invariant and should use a
  bounded suffix check rather than parsing every message byte; and
- sinks use explicit record/message lifecycle events and never infer "first
  chunk" from delivery history.

## Baseline before Step 1

The B0 logger was simpler than the target protocol. It exposed:

```d
alias LogSink = bool function(void* context, scope const LogRecord* record);
alias LogFlush = bool function(void* context);
```

with:

```d
struct LogRecord
{
    LogLevel level;
    String message;
    AnsiStyle style;
}
```

`Logger` at B0:

1. filtered by `minimumLevel` before formatting;
2. formatted one accepted call into one caller-provided `char[]` buffer;
3. truncated when that buffer was too small;
4. constructed one borrowed `LogRecord`;
5. invoked one sink callback; and
6. used one recursion guard around delivery.

The B0 plain and ANSI file sinks constructed `[level] ` themselves. The ANSI
file sink applied the level style to the entire rendered line.

Step 1 replaced that boundary with the explicit event protocol described below.
The logger now owns the level label, spaces, message boundary, newline, and
record boundary. `LogPalette` now carries `LogLevelStyle { label, message }`,
and `LogSinkRef` is the copyable borrowed sink descriptor. Step 2 adds the
plain/ANSI presentation behavior, embedded-SGR handling, and bounded safe
truncation described below. The formatter itself still produces one bounded
message-buffer result per log call; true streaming formatter delivery remains a
future extension of the already chunk-capable sink protocol.

As a post-plan API convenience, `LogPalettePreset` provides three built-in
palettes without changing the sink protocol: `basic` uses only 16-color ANSI
labels and no base message color, `extended` uses 256-color labels plus a gray
message-brightness ramp, and `trueColor` uses RGB colors. The two enhanced
presets target dark terminal backgrounds. `LogPalette.preset(...)` returns an
ordinary value for further customization, while `logger.setPalette(preset)`
selects one directly.

## Motivation

The primary use case is one logical log call producing rich terminal output and
clean file output:

```text
logger.warning(...)
        |
        | format once
        | construct logger-owned prefix/metadata once
        v
    TeeLogSink
      /     \
     /       \
 ANSI sink   plain sink
    |           |
 colored       no ANSI
 terminal      logfile
```

The terminal branch should be able to show all of the following independently:

- a level label style, such as yellow `[warning]`;
- future timestamp/date styles, such as dim gray metadata;
- an optional base message color chosen by level; and
- arbitrary supported ANSI SGR sequences embedded by the formatted message.

The file branch should receive the same textual content but no ANSI styling,
including no level/timestamp styling and no embedded message SGR sequences.

The message must still be formatted only once. The logger must not copy or
rewrite the formatted message merely to support fan-out.

## Design goals

The target design should:

- remain `-betterC`, `nothrow`, `@nogc`, allocation-free on the logging path;
- preserve filter-before-format behavior;
- format message arguments once regardless of destination count;
- forward normal message spans directly from formatter-owned storage;
- avoid style-span arrays and formatter-to-logger ANSI metadata;
- support ANSI terminal plus plain logfile through one logger;
- keep textual framing under logger control;
- support future logger-generated metadata without teaching sinks about
  timestamps, dates, thread IDs, or severity-name spelling;
- make sink composition explicit and general enough for teeing, buffering,
  capture, filtering, and future adapters;
- avoid first-chunk heuristics in stateful sinks;
- preserve terminal state at logical record boundaries;
- keep the ordinary no-ANSI/no-message-color path extremely cheap; and
- establish ANSI integrity once in the producer plumbing rather than requiring
  every sink to repair arbitrary chunking.

## Non-goals

The first implementation should not introduce:

- style-span metadata or a parallel rich-text representation;
- a `hasAnsi` bit or similar formatter-produced metadata;
- a `TeeLogger` that calls multiple complete loggers;
- dynamic allocation for sink graphs;
- background/asynchronous logging;
- a full terminal emulator or parser for every ANSI control family;
- rewriting user message bytes inside `Logger`;
- sink-specific log-level spelling or timestamp generation; or
- hidden sink ownership/automatic file cleanup.

The supported embedded-control contract is intentionally centered on ANSI SGR
styling. Arbitrary cursor movement, screen clearing, OSC, DCS, terminal titles,
and similar terminal control protocols are outside this logging design unless a
future proposal explicitly broadens it.

## Responsibility split

The design has four distinct layers.

```text
Formatter
    |
    | message bytes only
    v
Logger
    |
    | record lifecycle
    | logger-generated text
    | presentation style instructions
    | verbatim message chunks
    | safe SGR chunk boundaries
    v
LogSink / adapters
    |
    +--> TeeLogSink
    |      +--> AnsiLogSink --> byte destination
    |      +--> PlainLogSink --> byte destination
    |
    +--> other future adapters
```

### Formatter

The formatter knows nothing about logging colors or destinations. It produces
bytes. If the user formats XTB ANSI values or supplies a string containing
supported ANSI SGR sequences, those bytes are part of the formatted message.

The formatter does **not** return:

- style spans;
- `hasAnsi`;
- active-color state;
- reset locations; or
- sink-specific formatting metadata.

### Logger

The logger owns logical log structure:

- filtering;
- the level selected for the call;
- textual level-name spelling;
- future timestamp/date/metadata text;
- palette selection for logger-generated presentation;
- message formatting orchestration;
- record and message boundaries;
- chunk safety for supported well-formed SGR; and
- recursion detection.

The logger does not insert ANSI bytes into the formatted message buffer and does
not rewrite the message. It forwards message slices from formatter storage
verbatim.

### Log sink protocol

A log sink consumes semantic **output events**, not a complete high-level logger
policy object. It may render or ignore presentation styles, but it does not know
that a styled text segment happens to be a level label or timestamp.

### Byte destination

Raw byte output remains a lower-level concern. File/stdout/stderr writing,
locking, and flushing should be reusable below the log presentation sinks where
practical.

## Explicit sink event protocol

A sink must never infer record state from "the first chunk." Record and message
boundaries are explicit because stateful sinks need to lock once per record,
maintain optional message presentation state across chunks, and finalize even
when a write fails.

The conceptual event set is:

```d
enum LogSinkEventKind : ubyte
{
    beginRecord,
    text,
    beginMessage,
    messageChunk,
    endMessage,
    endRecord,
}

struct LogSinkEvent
{
    LogSinkEventKind kind;
    String bytes;
    AnsiStyle style;
}
```

Step 1 adopts this tagged-event representation. Later steps may extend event
payload conventions only if they preserve the lifecycle semantics and the
copyable `LogSinkRef` boundary.

### `beginRecord`

Begins one logical record. A file-backed sink may acquire its destination lock
here and retain it until `endRecord` so chunks from another thread cannot
interleave inside one record.

No textual prefix is implied. The sink does not generate a timestamp or level
label.

### `text`

Writes logger-generated text with an optional presentation style.

Examples include:

```text
"2026-08-20 19:02:31"
" "
"[warning]"
" "
```

The logger chooses both the bytes and the style. An ANSI sink renders the style;
a plain sink ignores the style and writes the bytes.

`AnsiStyle.init`/an empty generated ANSI sequence means no style.

### `beginMessage`

Begins the user-formatted message and carries the optional base message style
selected for the level.

An empty style means **no custom base message style**. This distinction enables
an important ANSI fast path described below.

### `messageChunk`

Carries one borrowed formatter-buffer slice. The bytes are the formatter output
verbatim. No sink may retain the slice after the callback returns.

The event repeats the optional base message style selected at `beginMessage`.
Repeating this logger-owned presentation value keeps built-in file presentation
sinks stateless: their callback context can remain only the borrowed `FILE*`.
This is not formatter metadata; formatting still produces bytes only and does
not report ANSI presence or style spans back to the logger.

The logger/plumbing guarantees that, for supported well-formed SGR input, a
`messageChunk` boundary does not divide an SGR sequence.

### `endMessage`

Ends the logical message. ANSI presentation sinks restore the terminal to the
normal/default state here. Plain sinks need no presentation action.

This event exists separately from `endRecord` so the logger can emit unstyled
record terminators such as `"\n"` after message presentation has ended.

### `endRecord`

Ends the logical record. A file-backed sink releases its per-record destination
lock here.

A sink that successfully accepted `beginRecord` must be prepared to receive
record-finalization events even after a later payload operation reports failure.
This is required so locks and presentation state are not abandoned.

## Proposed sink descriptor

Retain the useful borrowed descriptor idea, but its callback receives the event
protocol rather than one complete `LogRecord`:

```d
alias LogSink = bool function(
    void* context,
    scope const LogSinkEvent* event,
);

alias LogFlush = bool function(void* context);

struct LogSinkRef
{
    static LogSinkRef create(
        LogSink sink,
        void* context,
        LogFlush flush = null,
    );

    bool valid() const pure @safe;
    bool submit(scope const LogSinkEvent* event);
    bool flush();
}
```

`LogSinkRef` is non-owning and copyable. Its context must outlive every copied
reference that may invoke it.

Using one event callback keeps the descriptor small and makes adapters such as
`TeeLogSink` mechanically forwardable. The implementation may instead choose a
small fixed callback table if measurement shows a meaningful advantage, but
that alternative must preserve the same explicit lifecycle.

## Logger-owned presentation model

The current palette has one `AnsiStyle` per level. The target model separates
label presentation from optional base-message presentation:

```d
struct LogLevelStyle
{
    AnsiStyle label;
    AnsiStyle message;
}

struct LogPalette
{
    LogLevelStyle trace;
    LogLevelStyle debug_;
    LogLevelStyle info;
    LogLevelStyle warning;
    LogLevelStyle error;
    LogLevelStyle critical;
}
```

The initial default label styles should preserve today's visible severity
palette. Initial default message styles should remain empty unless a separate
presentation decision intentionally chooses a gray/brightness ramp.

Example customization:

```d
LogPalette palette = LogPalette.defaults();
palette.warning.label = AnsiStyle.foreground(AnsiColor.yellow);
palette.warning.message = AnsiStyle.foreground(AnsiColor.brightBlack);
```

The important semantic distinction is:

- `label` styles logger-generated severity text;
- `message` is an optional base style for the whole user-formatted message.

Future metadata styles should be passed with their own `text` events rather
than added as semantic fields to sinks.

## Logger emission example

A warning record may conceptually produce:

```d
sink.submit(beginRecord());

sink.submit(text(timestampBytes, timestampStyle));
sink.submit(text(" "));
sink.submit(text("[warning]", palette.warning.label));
sink.submit(text(" "));

sink.submit(beginMessage(palette.warning.message));
foreach (chunk; formattedMessageChunks)
    sink.submit(messageChunk(chunk));
sink.submit(endMessage());

sink.submit(text("\n"));
sink.submit(endRecord());
```

The logger owns `[warning]` and the timestamp bytes. The sink does not generate
or reinterpret either piece.

## ANSI message semantics

Formatted messages may contain supported ANSI SGR bytes directly.

For example:

```text
"loaded " + <green> + "config.toml" + <reset> + " successfully"
```

The canonical message bytes are the ANSI-containing formatter output. There is
no parallel styled-message representation and no style-span buffer.

### No base message style: fast path

If `beginMessage` carries no custom message style, the ANSI sink does not need
to inspect message chunks for resets. It can write every safe `messageChunk`
directly:

```d
if (baseMessageStyle.empty)
    writeDirect(chunk);
```

Embedded SGR behaves exactly as normal terminal SGR behaves. `ESC[0m` returns to
the terminal default because there is no logger-selected base message color to
restore.

At `endMessage`, the ANSI sink emits a final full reset so even a message that
ends while an embedded style is active cannot leak presentation into the next
record.

### Base message style enabled

If a level has a non-empty message style, the ANSI sink emits that style at
`beginMessage` and treats it as the message's base presentation.

Example intended rendering:

```text
<gray>
ordinary
<green>
special
<reset><gray>
ordinary again
<final reset>
```

The sink therefore needs to recognize full SGR resets inside message chunks.
For each supported full reset, it emits the reset and immediately reapplies the
base message style.

The message bytes themselves are not modified in formatter storage. The extra
base-style sequence is destination output generated by the ANSI presentation
sink.

Only **full SGR reset** semantics are required initially. Partial resets such as
foreground-default `39m` remain ordinary embedded SGR and may intentionally
override the base style. A future richer SGR-state model requires a separate
design decision.

### ANSI-sink fast scanning

When a base message style exists, the ANSI sink can still use a cheap common
path:

```d
if (memchr(chunk.ptr, ESC, chunk.length) is null)
{
    writeDirect(chunk);
    return true;
}
```

Only chunks containing an escape byte need reset recognition. Because the
logger guarantees safe supported-SGR chunk boundaries, this parser does not
need cross-chunk partial-sequence state.

## Plain message semantics

A plain sink ignores styles attached to logger-generated `text` events and
writes the text bytes directly.

For message chunks:

- no `ESC` byte: write the entire chunk directly;
- supported SGR present: write the plain spans and skip the SGR sequences.

The common path is therefore one fast escape search plus one direct write.

The plain sink does not need a cross-chunk partial-SGR buffer because the logger
owns that integrity invariant.

The design promises clean output for supported well-formed SGR. It does not
claim to sanitize every arbitrary/malformed terminal protocol.

## ANSI chunk-boundary integrity

### Required invariant

For supported well-formed SGR input:

> A `messageChunk` passed to a sink never ends in the middle of an SGR sequence,
> and the next `messageChunk` never begins with the continuation of that
> sequence.

This lets ANSI sinks trust chunk boundaries and lets plain sinks strip SGR with
stateless per-chunk parsing.

### Why only the suffix matters

A well-formed incomplete SGR sequence can only threaten the **end** of a
candidate formatter chunk. Complete sequences earlier in the chunk are already
safe.

Therefore the logger/plumbing should not parse the whole message merely to find
safe boundaries.

Let `maxSupportedSgrLength` be a small compile-time bound consistent with XTB's
supported/generated ANSI sequence capacity. For each candidate chunk:

1. inspect only the final `maxSupportedSgrLength` bytes (or the entire chunk if
   shorter);
2. search backward for the last `ESC` in that bounded suffix;
3. if there is no candidate `ESC`, the whole chunk is safe;
4. if the suffix beginning at that `ESC` contains a complete supported SGR, the
   whole chunk is safe;
5. if it is a valid prefix of a supported SGR but has no final byte yet, the
   safe boundary is immediately before that `ESC`; and
6. malformed/unsupported terminal input is outside the strong integrity
   guarantee and must not force a full-message validator into the hot path.

A CSI SGR sequence becomes unambiguously complete when its CSI final byte `m`
is present. There is no need to delay a complete `...m` sequence waiting to see
whether a later chunk could extend it.

### Current single-buffer truncation

With today's bounded `writeBuffer`/`formatBuffer` model there is no later
formatter chunk after truncation. If the truncated buffer ends in a valid
partial SGR prefix, delivery simply shortens the borrowed message slice to the
last safe boundary. The partial sequence is not emitted.

The message storage is neither rewritten nor copied:

```text
formatter buffer:
| safe message bytes............ | ESC [ 38 ; 2 ; 255 ;
^                                 ^
message.ptr                       delivered end
```

The ANSI sink then finishes `endMessage` with its own full reset, so the terminal
returns to a known default state.

`LogResult.written` describes the safely selected formatter-message prefix after
safe-boundary trimming; `required` continues to describe formatter demand. Sink
callbacks report only success/failure rather than a partial byte count, so
`written` is not a destination-I/O counter when a sink fails.

### Future multi-chunk formatting

The protocol is deliberately chunk-capable, but strict zero-copy continuation
across an incomplete SGR suffix constrains the future formatter-buffer plumbing.
The target rule is:

> Normal emitted message spans remain borrowed slices of formatter-owned
> storage. The logger does not concatenate or rewrite the message to normalize
> ANSI.

If future formatting can split one SGR sequence across candidate chunks, the
implementation must retain the incomplete suffix in source storage until the
sequence completes, or otherwise arrange candidate chunk boundaries so the
sequence remains contiguous before sink delivery.

A tiny copied carry buffer is **not** part of the approved design at this time.
If implementation constraints make such a buffer desirable, revisit the
zero-copy decision explicitly rather than adding it silently.

Possible zero-copy plumbing techniques include retained source-buffer suffixes,
a chunk producer with commit/consume boundaries, or reserved tail capacity.
The exact mechanism is deferred until chunked formatting itself is implemented
and can be measured against the real formatter API.

## Tee composition

### Why a tee must not infer first chunk

A first-chunk flag would make composition fragile:

- a buffering adapter may rechunk writes;
- a tee may nest another tee;
- a filter/capture adapter may consume some events but not others;
- a sink may need to acquire a lock even before any message bytes exist; and
- future logger-generated metadata may precede the message by several writes.

Explicit lifecycle events avoid all of those ambiguities.

### `TeeLogSink`

The tee is an allocation-free adapter over two borrowed `LogSinkRef` values:

```d
struct TeeLogSink
{
    @disable this(this);

    static TeeLogSink create(LogSinkRef first, LogSinkRef second);
    bool valid() const pure @safe;
    LogSinkRef sinkRef();
}
```

It owns neither branch. `sinkRef()` borrows the tee object as callback context,
so the tee must remain alive at a stable address for as long as the returned
reference may be used.

The tee has no knowledge of:

- log-level names;
- timestamps;
- ANSI colors;
- base message styles;
- formatter arguments; or
- byte-destination details.

It forwards the event protocol.

### Per-record branch state and failures

Streaming fan-out needs slightly richer failure behavior than the older
record-at-once tee proposal.

A branch that fails partway through a record must not prevent a still-healthy
branch from receiving the remainder. At the same time, a branch that accepted
`beginRecord` must still be finalized so it can release locks/state.

The tee should therefore track, for the active record:

- whether each branch accepted `beginRecord`;
- whether `beginMessage` was delivered and therefore needs matching cleanup;
- whether each branch remains healthy for normal payload delivery; and
- whether any failure occurred.

Normative behavior:

1. `beginRecord` is attempted on both branches.
2. Normal events are delivered to every currently healthy branch.
3. A payload failure marks that branch unhealthy but does not stop the other
   branch.
4. `endMessage` is attempted once `beginMessage` has been delivered, even if
   that call itself reports failure; `endRecord` is attempted for every branch
   that accepted `beginRecord`. This mirrors direct logger cleanup semantics.
5. The tee remembers any branch failure and reports overall failure for the
   logical record after finalization.
6. Flush attempts both branches regardless of the first result.

This makes nested tees composable: an inner tee can continue a surviving child
for the remainder of the record while eventually reporting that its composite
record had a partial failure.

The implemented callback-return timing is part of the contract:

- child `beginRecord` is attempted first branch, then second branch;
- a child that rejects `beginRecord` is not considered begun and receives no
  later events for that record;
- the tee itself accepts `beginRecord` even if one or both children reject it,
  so any surviving child can still receive the complete logical record;
- after a child that successfully began reports a payload failure, ordinary
  payload is suppressed only for that child;
- once `beginMessage` has been delivered to a child, `endMessage` is attempted
  even when `beginMessage` itself reports failure; a child that accepted
  `beginRecord` still receives `endRecord`; and
- the remembered aggregate result is returned by the tee's `endRecord`, which
  makes the enclosing `Logger` return `LogStatus.sinkFailed` only after required
  finalization has been attempted.

This delayed failure report is what lets a healthy branch continue while still
preserving one record-level result for the composite sink.

## Built-in presentation sinks

### ANSI file/terminal sink

The ANSI presentation sink wraps a byte/file destination and implements:

- `beginRecord`: acquire per-record destination serialization where needed;
- `text`: optionally emit opening style, exact text bytes, then full reset;
- `beginMessage`: emit the optional base message style when present;
- `messageChunk` with no base style: direct write, no ANSI scan;
- `messageChunk` with a base style: fast-search for `ESC`; recognize full reset
  sequences and reapply the base style; otherwise preserve supported embedded
  SGR verbatim;
- `endMessage`: emit one final full reset;
- `endRecord`: release per-record serialization; and
- `flush`: flush the underlying destination.

The sink does **not** emit `[warning]`, a timestamp, a date, or any other logger
text from its context.

### Plain file sink

The plain sink implements:

- `beginRecord`: acquire per-record destination serialization where needed;
- `text`: ignore the style and write exact text bytes;
- `beginMessage`: no presentation output;
- `messageChunk`: direct-write when no `ESC` exists, otherwise strip supported
  SGR and write the plain spans;
- `endMessage`: no presentation output;
- `endRecord`: release per-record serialization; and
- `flush`: flush the underlying destination.

This is what makes one tee logger produce colored terminal output and a clean
log file from exactly the same logical log operations.

## Example output

Given a future logger configuration roughly equivalent to:

```d
LogPalette palette = LogPalette.defaults();
palette.warning.label = AnsiStyle.foreground(AnsiColor.yellow);
palette.warning.message = AnsiStyle.foreground(AnsiColor.brightBlack);
```

and a message containing an embedded green section:

```text
loaded <green>config.toml<reset> successfully
```

one logical warning may be emitted as events equivalent to:

```text
beginRecord
text("2026-08-20 19:02:31", dim-gray)
text(" ")
text("[warning]", yellow)
text(" ")
beginMessage(gray)
messageChunk("loaded <green>config.toml<reset> successfully")
endMessage
text("\n")
endRecord
```

The ANSI terminal may render:

```text
<dim-gray>2026-08-20 19:02:31</reset>
<yellow>[warning]</reset>
<gray>loaded <green>config.toml</reset><gray> successfully</reset>
```

on one line with the spaces shown above, while the plain file receives:

```text
2026-08-20 19:02:31 [warning] loaded config.toml successfully
```

The timestamp is only an example of future logger-generated metadata; it is not
part of the first implementation requirement unless added separately.

## No-message-color fast path

The common configuration may leave every `LogLevelStyle.message` empty. In that
case the ANSI sink has no base style to restore and therefore does not need to
parse message chunks at all:

```text
beginMessage(empty)
messageChunk -> write direct
messageChunk -> write direct
...
endMessage   -> final reset
```

This is the preferred hot path.

When a base message color is configured, only chunks containing `ESC` require
reset recognition. That cost is paid only for the optional feature that needs
it.

The plain sink necessarily needs to detect embedded ANSI because removing it is
its defining transformation, but it should use the same `memchr`-style no-ESC
fast path.

## Ownership and lifetime

All composition remains borrowed:

```text
Logger
  borrows formatter/message storage
  borrows LogSinkRef context

TeeLogSink
  borrows child LogSinkRef contexts

presentation sink
  borrows byte/file destination context
```

No sink closes a file or frees a context unless a separately designed owning
wrapper explicitly says so.

A typical declaration order is:

```d
FILE* logFile = fopen("application.log", "w");
if (logFile is null)
    return 1;
scope (exit) fclose(logFile);

LogSinkRef terminal = ansiFileLogSink(stderr);
LogSinkRef file = plainFileLogSink(logFile);
TeeLogSink output = TeeLogSink.create(terminal, file);

char[1024] storage;
Logger logger = Logger.create(output.sinkRef(), storage[], LogLevel.info);
```

The concrete names may change, but the borrowed lifetime direction must remain
obvious.

## Threading and record atomicity

`Logger` itself remains thread-confined unless documented otherwise. Each thread
normally has its own logger and formatter buffer.

`TeeLogSink` is also stateful and thread-confined. Its per-record branch-health
state assumes one active protocol record at a time. Multiple threads may still
use distinct tee/logger values whose child sinks share a synchronized destination.

A file/terminal presentation sink may be shared when its destination can be
serialized. Because records may consist of several protocol events/chunks,
serialization must cover the logical record rather than one individual byte
write:

```text
beginRecord -> lock
...
endRecord   -> unlock
```

This is another reason first-chunk inference is not acceptable.

A tee guarantees branch invocation order for one logger operation, not identical
cross-destination ordering between unrelated logging threads.

## Filtering

`Logger.minimumLevel` remains the outer filter and is checked before formatting
or any sink event.

A filtered call:

- formats nothing;
- emits no `beginRecord`;
- touches no tee branch; and
- returns `LogStatus.filtered`.

Per-destination thresholds remain deferred. If needed later, they should be a
separate composable adapter with a carefully designed aggregate pre-format
threshold so filtering does not accidentally force unnecessary formatting.

## Result accounting

The existing `LogResult` shape can remain initially:

```d
struct LogResult
{
    LogStatus status;
    size_t written;
    size_t required;
}
```

Important target semantics:

- `required` counts formatter message bytes required for the complete message;
- `written` counts message bytes actually exposed to sinks after any safe ANSI
  suffix trim caused by final truncation;
- logger-generated prefixes, timestamps, spaces, newlines, ANSI sequences, and
  sink-inserted base-style restorations do not count toward either field; and
- any sink/fan-out branch failure produces `sinkFailed` after required record
  finalization has been attempted.

A richer partial-delivery result remains deferred.

## Rejected alternatives

### Styled spans

Do not represent message styling as text plus `LogStyleSpan[]` metadata.

That would require additional caller-provided storage, span-capacity semantics,
formatter integration, truncation coordination, and a parallel rich-text model.
The selected design keeps ANSI styling in the formatted message byte stream.

### Formatter ANSI metadata

Do not add `hasAnsi`, active-style state, or similar side-channel data from the
formatter to the logger.

The logger's chunk safety uses only the produced bytes, and optional base-message
restoration belongs to the ANSI presentation sink.

### `TeeLogger(Logger*, Logger*)`

Do not fan out by calling multiple complete loggers. That would duplicate
formatting buffers, filtering, truncation, recursion state, and message
formatting work.

### Sink-generated level label

Do not make ANSI/plain sinks emit `[warning]` from `LogLevel` stored in their
context or infer that the first message chunk needs a prefix.

The logger owns textual structure. Sinks render generic styled text and message
operations. This is what lets future timestamps/date metadata compose without
adding timestamp-specific sink APIs.

### First-chunk state

Do not use `isFirstChunk` as the record lifecycle. Rechunking adapters and nested
composition make that state ambiguous. Use explicit `beginRecord` and
`beginMessage` events.

### Full-message ANSI validation

Do not parse every formatted byte in the logger merely to protect chunk
integrity. Under the supported-well-formed-input contract, inspect only a bounded
suffix for an incomplete SGR sequence.

### Byte-level tee after ANSI rendering

Do not make the primary logging tee duplicate already-rendered terminal bytes.
A byte tee after ANSI rendering would force the logfile branch to receive the
same logger-generated ANSI prefix styles. Fan-out must happen before ANSI/plain
presentation policy diverges.

## Proposed public API direction

The exact names should be reviewed immediately before implementation, but the
intended surface is approximately:

```d
struct LogLevelStyle
{
    AnsiStyle label;
    AnsiStyle message;
}

struct LogPalette
{
    LogLevelStyle trace;
    LogLevelStyle debug_;
    LogLevelStyle info;
    LogLevelStyle warning;
    LogLevelStyle error;
    LogLevelStyle critical;
}

enum LogSinkEventKind : ubyte
{
    beginRecord,
    text,
    beginMessage,
    messageChunk,
    endMessage,
    endRecord,
}

struct LogSinkEvent
{
    LogSinkEventKind kind;
    String bytes;
    AnsiStyle style;
}

alias LogSink = bool function(
    void* context,
    scope const LogSinkEvent* event,
);

alias LogFlush = bool function(void* context);

struct LogSinkRef
{
    static LogSinkRef create(LogSink sink, void* context, LogFlush flush = null);
    bool valid() const pure @safe;
    bool submit(scope const LogSinkEvent* event);
    bool flush();
}

struct TeeLogSink
{
    @disable this(this);

    static TeeLogSink create(LogSinkRef first, LogSinkRef second);
    bool valid() const pure @safe;
    LogSinkRef sinkRef();
}
```

Step 2 exposes the file presentation paths directly as borrowed sink
descriptors. This keeps the future composition shape small:

```d
LogSinkRef terminal = ansiFileLogSink(stderr);
LogSinkRef file = plainFileLogSink(logFile);
TeeLogSink tee = TeeLogSink.create(terminal, file);

char[1024] storage;
Logger logger = Logger.create(
    tee.sinkRef(),
    storage[],
    LogLevel.debug_,
    palette,
);
```

`LogSinkEventKind`, `LogSinkEvent`, `LogSink`, `LogFlush`, `LogSinkRef`,
`plainFileLogSink`, and `ansiFileLogSink` are implemented public names.
`TeeLogSink` is the implemented Step 3 public spelling. `valid()` reports
whether both borrowed child sink references are valid. `sinkRef()` itself remains
usable when one child is invalid so the valid branch can still receive the
record; that record then reports aggregate sink failure.

## Compatibility and migration

B0 used a record-at-once public sink callback and built-in sinks generated the
level prefix. Step 1 intentionally makes the event protocol the public sink
boundary, so this migration is source-breaking for application-defined sink
callbacks.

Migration should preserve ordinary convenience construction where practical:

```d
char[512] storage;
Logger logger = stderrLogger(storage[], LogLevel.info, LogStyle.ansi);
logger.info("started");
```

may continue to work even if its internals become:

```text
Logger -> ANSI file presentation sink -> stderr
```

Application-defined callbacks using the old `LogRecord*` signature are source
incompatible with Step 1. The compatibility decision is deliberately simple:

- `LogSink` now names the lifecycle-event callback;
- `LogRecord` and the record-at-once callback boundary are removed;
- `Logger.create(LogSink, void*, ...)` and `setSink(LogSink, void*, ...)` remain
  convenience overloads, but their callback uses `LogSinkEvent*`; and
- no legacy record adapter is provided, because reconstructing a complete record
  would work against the chunked/composable direction of this design.

Ordinary `fileLogger`, `stderrLogger`, `stdoutLogger`, `log`, `logf`, and
level-specific call sites remain source-compatible apart from the intentional
`LogPalette` field split (`palette.warning.label`, with optional
`palette.warning.message`).

## Implementation stages

Implementation is executed according to
`design_spec/logging_sink_fanout_implementation_plan.md`. That plan deliberately
compresses the work into four reviewable, test-complete steps and defines the
required step-only and cumulative diff workflow.

| Step | Status | Scope |
| --- | --- | --- |
| 1 | complete | Composable sink lifecycle protocol, `LogSinkRef`, logger-owned framing, palette split, compatibility migration. |
| 2 | complete | ANSI/plain presentation, optional message base style, embedded SGR behavior, bounded suffix normalization, chunk-capable presentation semantics. |
| 3 | complete | `TeeLogSink`, branch failure/finalization semantics, nesting, formatting-once proof, record atomicity. |
| 4 | complete | Public API stabilization, examples/docs/exports, final stress/regression coverage and repository gates. |

Do not mark a step complete until every test required by the implementation plan
and the relevant repository checks pass together.

### Step 1 implementation notes

Step 1 uses the single tagged `LogSinkEvent` callback described in this document.
A successful non-empty record is delivered as:

```text
beginRecord
text("[level]", labelStyle)
text(" ")
beginMessage(messageStyle)
messageChunk(verbatim formatter slice, messageStyle)
endMessage
text("\n")
endRecord
```

An empty message omits `messageChunk` but retains the explicit message lifecycle.
If a payload event fails after `beginRecord` succeeds, the logger stops ordinary
payload delivery but still sends any required `endMessage` and `endRecord`
finalization. A rejected `beginRecord` ends delivery immediately. The recursion
guard covers the entire lifecycle. The logger snapshots the `LogSinkRef` and the
selected `LogLevelStyle` before `beginRecord`; `setSink` or `setPalette` invoked
from a callback therefore affects later records rather than redirecting or
restyling an in-flight lifecycle.

### Step 2 implementation notes

The built-in presentation callbacks are exposed through
`plainFileLogSink(FILE*)` and `ansiFileLogSink(FILE*)`. They remain stateless:
their callback context is the borrowed `FILE*`, and `messageChunk.style` repeats
the base message style selected for the logical message.

The plain path ignores logger-generated styles and removes complete supported
SGR from message chunks. It searches for `ESC` first and writes the whole chunk
directly when none exists. Unsupported/malformed terminal material is outside
the stripping guarantee and does not trigger an unbounded parser.

The ANSI path renders logger-generated styles, applies the optional base message
style at `beginMessage`, and preserves message SGR. With no base message style,
`messageChunk` is a direct write with no ANSI scan. With a base style, the sink
first searches for `ESC`; complete full resets are preserved and followed by
the base style, while partial resets such as `39m` are left untouched.
`endMessage` emits one full reset.

The current logger still receives one bounded `writeBuffer`/`formatBuffer`
result. When that result is truncated, it inspects at most the final
`AnsiSequence.capacity` bytes, searches backward for a candidate `ESC`, and
shortens only the delivered borrowed slice if the suffix is a valid incomplete
supported SGR prefix. The formatter buffer is not rewritten or copied.
`LogResult.written` reports the shortened safe prefix and `required` retains the
formatter demand. UTF-8 repair continues to happen inside the formatter before
this SGR suffix check.

The sink protocol itself is exercised with multiple complete `messageChunk`
events so base-style restoration and embedded colors are not tied to a first
chunk. True formatter streaming that can split one SGR across candidate chunks
remains deferred under the zero-copy rules in **Future multi-chunk formatting**.

### Step 3 implementation notes

Step 3 implements `TeeLogSink` as a non-copyable, allocation-free two-way fan-out
value over borrowed `LogSinkRef` children. `sinkRef()` borrows the tee itself as
callback context, so the tee must remain alive at a stable address while that
reference is in use.

The tee is deliberately presentation-agnostic. It does not inspect level labels,
styles, message bytes, ANSI, or formatter state. For each protocol event it calls
the first child before the second child. Branch failures are deferred and
aggregated at `endRecord`: a failed branch stops receiving ordinary payload, but
any lifecycle it successfully began is finalized, while healthy peers continue.
Nested tees inherit the same behavior mechanically.

Flush always attempts both child flush callbacks. File presentation sinks retain
the Step 2 record-level `flockfile`/`funlockfile` serialization, and Step 3 tests
exercise concurrent thread-confined loggers sharing one file destination as well
as a failing tee branch to prove required finalization releases that lock.

Formatting still happens once in `Logger` before any sink event. A tee only fans
out already-constructed logger events and borrowed formatter bytes, so fan-out
depth does not multiply custom-value formatting work.

### Step 4 stabilization notes

The public names proven in Steps 1–3 are retained: `LogSinkEventKind`,
`LogSinkEvent`, `LogSink`, `LogFlush`, `LogSinkRef`, `TeeLogSink`,
`plainFileLogSink`, and `ansiFileLogSink`. The callback/context convenience
overloads on `Logger.create` and `setSink` are also retained deliberately; they
construct `LogSinkRef` directly and do not recreate the removed record-at-once
compatibility layer.

The stabilization review fixed one lifecycle-composition discrepancy. Direct
`Logger` delivery attempts `endMessage` after any delivered `beginMessage`, even
when `beginMessage` reports failure, because presentation work may already have
partially occurred. `TeeLogSink` now preserves that same contract for each child
instead of treating a rejected `beginMessage` as if it had never been delivered.
The regression suite compares every tee child failure position with direct sink
delivery and separately verifies ANSI base-style cleanup for this case.

The final logging example uses the public `xtb.core` package surface and shows a
plain logger, conditional ANSI terminal presentation, custom label/message
styles, embedded message SGR, a tee to a plain file, thread-local installation,
and explicit flush/lifetime ordering. A dedicated public-package integration
test exercises nested tees, long output, one-pass formatting, ANSI/plain output,
and the final copyability constraints under BetterC.

## Required tests

### Logger framing

- logger, not sink context, determines level-label spelling;
- level label is emitted as a styled `text` event;
- unstyled spaces/newlines are explicit logger text;
- future metadata-style events can precede the level without affecting message
  state;
- filtering emits no lifecycle events; and
- recursion still rejects nested use of the same logger safely.

### Optional message style

- empty message style takes the ANSI direct-write path;
- non-empty message style is applied once at `beginMessage`;
- complete embedded `ESC[0m` with a base style causes base style restoration;
- complete embedded reset with no base style is passed through without
  restoration;
- `endMessage` always restores terminal default state; and
- partial resets such as `39m` are not silently rewritten as full resets.

### Plain sink

- logger-generated styled text appears without ANSI;
- message with no ESC takes the direct path;
- supported embedded SGR is removed while text is preserved;
- multiple SGR sequences in one chunk are stripped correctly; and
- safe chunk boundaries require no cross-chunk parser state.

### ANSI boundary normalization

- ordinary chunks require only the bounded suffix check;
- complete SGR ending at the chunk end is retained;
- incomplete SGR suffix is withheld/trimmed;
- no complete message bytes before the incomplete suffix are changed;
- truncation in an incomplete SGR never emits the partial sequence;
- UTF-8 and ANSI safe-boundary rules compose correctly;
- `written` reflects the safely delivered message length; and
- malformed input does not cause unbounded scanning or out-of-bounds reads.

### Tee

- begin/payload/end events reach both healthy children in order;
- a first-branch payload failure does not stop the healthy second branch from
  receiving later message chunks;
- a second-branch failure likewise does not stop the first;
- a failed-but-begun branch still receives required finalization events;
- overall record result reports failure when either branch failed;
- flush attempts both branches;
- nested tees preserve the same semantics;
- terminal branch keeps logger-generated and embedded colors;
- plain branch contains no logger-generated or embedded SGR; and
- formatter work occurs once, not once per tee branch.

### Threading / atomicity

- a shared file presentation sink locks from `beginRecord` through `endRecord`;
- message chunks from concurrent per-thread loggers cannot interleave within one
  destination record; and
- a branch failure does not leave a destination lock held.

## Performance expectations

The intended common costs are:

### Ordinary ANSI terminal, no message base color

```text
logger chunk normalization: none unless formatter truncates;
                            then bounded suffix inspection
ANSI sink message path:     direct write
end message:                one final reset
```

No full-message ANSI parse is required.

### ANSI terminal with message base color

```text
logger chunk normalization: none unless formatter truncates;
                            then bounded suffix inspection
ANSI sink message path:     memchr(ESC)
                             direct write if absent
                             reset recognition only when present
```

### Plain file

```text
logger chunk normalization: bounded suffix inspection
plain sink message path:    memchr(ESC)
                             direct write if absent
                             strip supported SGR only when present
```

No formatter metadata is consulted in any case.

Performance-sensitive helper code should be benchmarked before replacing
`memchr`/bounded scans with more complicated machinery.

## Deferred questions

The following remain intentionally unresolved until implementation pressure
makes them concrete:

- whether `LogSinkEvent` should remain one tagged callback or become a small
  fixed callback table after measurement;
- whether default message styles should remain empty or adopt a standard gray
  brightness ramp;
- exact zero-copy mechanism for retaining an incomplete SGR suffix when true
  multi-chunk formatting is introduced;
- per-destination level filtering;
- arbitrary-N fan-out versus nested tees;
- richer partial-delivery diagnostics; and
- broader ANSI control support beyond well-formed supported SGR.

## Decision log

### 2026-08-20 — sink fan-out direction

Fan-out belongs below one `Logger`; do not create a `TeeLogger` that owns or
calls multiple loggers.

### 2026-08-20 — ANSI in message bytes

Reject style spans. Formatted message bytes may contain ANSI SGR directly. A
plain presentation sink strips supported SGR; an ANSI presentation sink
preserves it.

### 2026-08-20 — no formatter metadata

Do not add `hasAnsi` or equivalent style metadata from formatter to logger.

### 2026-08-20 — separate label and optional message styles

The level label keeps its per-level color. A level may additionally select an
optional base message style. No base style means the ANSI message path can
forward chunks directly without reset scanning.

### 2026-08-20 — logger owns textual framing

Sinks do not generate `[level]`, timestamps, dates, spaces, or newlines from
semantic logger state. The logger emits the text. Sinks only render generic
presentation operations and message bytes.

### 2026-08-20 — explicit lifecycle for composability

Reject first-chunk inference. Use explicit record and message boundaries so tee,
buffering, locking, capture, and future adapters compose predictably.

### 2026-08-20 — zero-copy message delivery

Normal message chunks are verbatim borrowed slices of formatter storage. The
logger does not concatenate, rewrite, or duplicate the message for fan-out.

### 2026-08-20 — suffix-only ANSI boundary normalization

Under the supported well-formed-SGR contract, the logger checks only a bounded
chunk suffix to avoid splitting an SGR sequence. A final truncated partial
sequence is omitted rather than emitted. True multi-chunk continuation must
preserve the suffix without silently introducing a copied carry buffer.

## Summary

The target architecture is:

```text
Formatter
    |
    | verbatim message bytes
    v
Logger
    |
    | explicit record lifecycle
    | logger-owned timestamp/level text
    | generic presentation styles
    | optional per-level base message style
    | bounded suffix ANSI chunk normalization
    v
TeeLogSink
   /      \
  /        \
ANSI       plain
presentation presentation
  |           |
  |           +-- ignores logger styles
  |           +-- strips embedded SGR
  |
  +-- renders logger styles
  +-- preserves embedded SGR
  +-- with base message style only:
      full reset -> reset + reapply base style
```

The central composability rule is that **record/message boundaries are explicit
and sinks never infer them from chunk position**. The central performance rule
is that **ordinary message bytes remain zero-copy and the logger performs only a
bounded suffix check for ANSI chunk integrity**. The central presentation rule
is that **logger-generated styles are out-of-band while user-formatted message
ANSI remains verbatim bytes**, allowing one tee to produce rich terminal output
and a clean plain logfile from one formatting pass.
