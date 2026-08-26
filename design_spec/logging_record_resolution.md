# Logging record resolution, prefixes, and source context

## Status

**Status: complete. Steps 1-6 are implemented and verified.**

The record-resolution protocol is now implemented. `docs/architecture.md`
describes the current behavior. The older sink-fanout and prefix design
documents remain historical rationale for the behavior they introduced, but
their repeated whole-graph `LogSinkEvent` mechanics are superseded by this
document and the current architecture.

Maintain this document with every implementation step. If implementation work
finds a materially simpler, safer, or faster representation, update this file in
the same step rather than preserving incidental details from the original plan.

## Goals

The refactor has four related goals:

1. Compose logging behavior through sinks without forcing every decorator into
   every formatter write.
2. Keep prefixes before the level label and allow prefix providers to produce
   styled or embedded-ANSI output without knowing whether the destination is
   ANSI or plain.
3. Add optional allocation-free trailing source context rendered as
   `  (function:line)`, with logger-wide capture control and per-branch
   suppression. ANSI presentation makes it neutral and dim so it remains
   secondary to the level/message pair.
4. Preserve the existing BetterC, failure/finalization, record-atomicity,
   formatting, and result-accounting guarantees.

The target presentation is:

```text
prefix [error] message  (xtb.config.parse:87)
```

With no prefix:

```text
[error] message  (xtb.config.parse:87)
```

With callsite capture disabled, or removed from one sink branch:

```text
[error] message
```

## Core model

### Long-lived sink graph

`LogSinkRef` remains a copyable, non-owning description of a logging destination
or composition node. It is configured once and can prepare many records.

Instead of receiving every record fragment through the original sink graph, the
sink is asked once to prepare a specific record:

```text
LogSinkRef
    |
    | beginRecord(info)
    v
resolved record output
```

The implemented API keeps direct sinks deliberately simple.
`LogSinkRef.create(LogSink, context, flush)` still accepts the existing direct
`LogSinkEvent` callback. `LogSinkRef.beginRecord(info, callsite)` sends that
direct sink one `beginRecord` event and returns a `LogRecordRef` backed directly
by the same callback/context. `callsite` is an optional borrowed pointer and may
be null. Composite nodes use the overload taking a `LogRecordResolver`, resolve
their child graph once, and return the minimal active record path.

### `LogRecordInfo`

The implemented framing information is:

```d
struct LogRecordInfo
{
    LogLevel level;
    String levelLabel;
    AnsiStyle labelStyle;
    AnsiStyle messageStyle;
}
```

The resolved record borrows the setup value for the synchronous lifetime of
the record. Optional `LogSourceLocation` is passed separately to `beginRecord`
as one nullable borrowed pointer. Keeping the effective callsite outside the
larger framing structure lets a setup decorator suppress it by forwarding
`null`, without copying `LogRecordInfo` into decorator-owned storage and without
introducing a lifetime hazard. A direct record retains that pointer alongside
the borrowed framing info and emits `levelLabel` plus its separator when the
message begins. After the message style ends, a direct record appends the
effective callsite as dim-only trailing context. Composite records propagate the
same effective callsite to their children unless they intentionally transform
it.

Step 4 added optional `LogSourceLocation`, carried separately from the framing
structure during resolution. The implemented source representation is:

```d
struct LogSourceLocation
{
    String functionName;
    size_t line;
}
```

No filename is planned initially.

### Resolved per-record output

Record setup returns a small value handle representing the already-resolved
output path for that record. It is not a heap object and must not require
per-record allocation.

For a direct file sink it should be close in spirit to:

```text
FILE* + direct record callbacks/state
```

The resolved path owns the operations that genuinely need to happen after
resolution, for example:

```text
setup/framing write
begin message
message write
end message
end record
```

The implemented name is `LogRecordRef`. It is a small value handle containing
the resolved callback/context, a borrowed pointer to `LogRecordInfo`, the
branch-effective borrowed callsite pointer, message lifecycle state, and one
deferred setup-failure bit. It
allocates nothing. A
direct sink needs no concrete per-record object; a tee stores its two child
`LogRecordRef` values in the existing stable `TeeLogSink` object for the active
record.

### Resolution rule

A node remains in the resolved path only if it must perform work for repeated
record output.

Setup-only nodes disappear:

```text
WithoutCallsite
Prefix
level filter or similar one-shot metadata decorator
```

Nodes that genuinely transform or route bytes remain:

```text
Tee
ANSI/plain byte presentation when it must inspect bytes
other future per-byte transforms
```

The architectural rule is:

> Do record metadata and one-time decoration during setup. Keep a sink layer in
> the resolved output path only when it genuinely must process repeated output.

## Prefix semantics

A prefix means bytes emitted before the level label. Its intended use includes
wall-clock date/time, but it remains a generic provider.

Order is fixed:

```text
prefix -> level -> message -> optional trailing callsite
```

A prefix may use semantic `AnsiStyle` and may contain embedded supported SGR
bytes. Prefix providers do not inspect destination capability and never decide
whether ANSI should be retained.

Prefix bytes must pass through the resolved destination byte path:

```text
prefix provider
      |
      v
resolved ANSI/plain path
      |
      +--> ANSI destination: preserve/render styling
      |
      +--> plain destination: strip supported SGR
```

This means `PrefixLogSink` is setup-only from the perspective of repeated
message delivery, but its one-time bytes are still written through the resolved
child path.

The current `LogPrefixRef` / `LogPrefixWriter` provider model should be retained
if it maps cleanly to the new writer. `TimestampLogPrefix` must continue to be
allocation-free and destination-agnostic.

Prefix failure must not strand an already-begun child record. The current useful
contract is to defer the failure while allowing the actual record and required
finalization to continue. The resolved record representation should preserve
that behavior without keeping `PrefixLogSink` in every message write merely to
remember a boolean.

## Callsite semantics

### Logger-wide capture

The logger decides whether source information exists at all. Callsite capture is
disabled by default so existing output remains unchanged.

Implemented API:

```d
logger.setCallsitesEnabled(true);
logger.setCallsitesEnabled(false);
assert(logger.callsitesEnabled);
```

With capture enabled, normal sinks receive callsite metadata by default. Capture
must require no additional argument at an ordinary log call:

```d
logger.error("failed");
error("failed");
```

The public variadic wrappers use a trailing default
`LogSourceLocation(__FUNCTION__, __LINE__)`. Wrapper layers forward that value
through internal `logAt` / `logfAt` helpers whose callsite parameter precedes the
variadic message pack. The fixed position is required for the empty-Args case:
forcing an empty D template tuple does not otherwise prevent a forwarded
`LogSourceLocation` from being re-deduced as printable message data. Tests cover
all explicit and TLS level wrappers so the reported function never becomes a
logging wrapper.

Capture uses compile-time/static source data and an integer line number. It must
perform no allocation, stack walk, symbol lookup, or runtime reflection.

### Per-branch suppression

`WithoutCallsiteLogSink` is a setup-only decorator. Its resolver ignores the
incoming effective callsite and delegates with `null`:

```text
                         Tee
                        /   \
                       /     \
        WithoutCallsite       plain file
               |
         ANSI terminal
```

With logger capture enabled:

```text
terminal: [error] message
file:     [error] message  (application.foo:42)
```

The decorator returns the child's resolved record path directly. It must add no
indirection to repeated message writes.

Presence is the presentation contract: a resolved presentation record appends a
callsite after the message when its effective callsite pointer is non-null. ANSI
presentation uses dim-only terminal-default styling so the source is visually
secondary and severity-independent. There is no separate
per-presentation-sink `showCallsite` flag. The effective pointer is propagated
separately from `LogRecordInfo`, so suppression requires no metadata copy and
returns the child's resolved record unchanged.

## Sink behavior

### Plain file sink

Setup locks the `FILE*` for the complete record and returns a direct file-backed
record path. It requires no allocated per-record object.

Logger/setup styles are ignored. Supported embedded SGR sequences are stripped
from all arbitrary output bytes that are allowed to contain them, including
prefix output and message output.

### ANSI file sink

Setup locks the `FILE*` for the complete record and returns a direct ANSI-aware
record path.

Semantic styles are rendered, supported embedded SGR is preserved, and the
existing base-message-style restoration after complete full resets remains
correct. Message reset/finalization behavior must stay deterministic.

### Prefix sink

The prefix node resolves its child, emits the prefix once through the resolved
child byte path before level framing, records any deferred provider/write
failure in the active record state, then disappears from repeated message
writes.

### Tee sink

Tee resolves both children once and creates the record-local fan-out path:

```text
Tee record
├── first resolved record
└── second resolved record
```

Each repeated write therefore reaches the two already-resolved children rather
than traversing the original child sink graphs again.

Existing semantics remain requirements:

- deterministic first-then-second order;
- a failing branch does not prevent a healthy branch from completing;
- a branch that successfully began record/message lifecycle receives required
  finalization;
- a branch that rejects record setup receives no later record operations;
- the complete record reports failure when any required branch operation fails;
- flush attempts both children.

## Record phase ordering

The intended logical phases are:

```text
1. prepare/resolve record from LogRecordInfo
2. emit setup-only prefix bytes through resolved output
3. emit level framing
4. begin message presentation
5. write message chunks through the resolved hot path
6. end message presentation
7. emit optional dim trailing callsite framing
8. emit newline/final framing
9. end record and release destination state
```

The exact split between operations 2--4 may change if a smaller interface can
preserve the same ordering and ANSI semantics. What matters is that prefix bytes
are before the level and setup-only decorators are gone before repeated message
writes.

## Result accounting

`LogResult.written` and `required` continue to count message bytes only. They do
not include:

- prefixes;
- level labels;
- callsite framing;
- final newline;
- sink-generated ANSI escapes.

Bounded and streaming behavior otherwise remains unchanged unless a later step
documents a deliberate correction.

## Failure and recursion requirements

The refactor must preserve the current logger-local recursion guard and sink
snapshot semantics.

A setup or payload failure must not leave a successfully acquired file lock,
message presentation state, or child record unfinalized. Healthy tee branches
continue even after a peer fails. Prefix failure remains deferred when enough of
the child record exists to continue safely.

If implementation reveals a simpler failure representation than the current
per-decorator booleans, use it, but preserve the externally observable cleanup
contract.

## Step plan

### Step 1 — Freeze behavior and performance baseline

**Status: complete.**

- Inspect current sink, prefix, tee, file, streaming, TLS, OS timestamp, and
  failure-path contracts.
- Run focused core logging unit tests and the logging integration executable.
- Run the logging example.
- Run formatting and lint checks.
- Extend the opt-in microbenchmark with `PrefixLogSink -> TeeLogSink` so later
  steps can measure whether setup-only prefix indirection left the repeated
  path.
- Record machine-specific baseline timings and, more importantly, event/chunk
  counts.
- Add this implementation specification without changing public logging
  behavior.

### Step 2 — Introduce record setup/resolution and migrate the existing graph

**Status: complete.**

Implement the central protocol migration as one coherent step:

- `LogRecordInfo`;
- resolved per-record output handle;
- new `LogSinkRef` setup callback;
- direct sink record paths, including the existing plain and ANSI file sinks;
- logger bounded delivery and streaming over the resolved record;
- resolved `TeeLogSink`;
- resolved `PrefixLogSink`;
- custom/test sink migration;
- removal of the old repeated `LogSinkEvent` chain once no caller requires it.

Step 2 preserves visible logging output. Direct/custom sinks keep the simple
`LogSink` callback API, while `PrefixLogSink` now resolves its child, writes its
once-per-record prefix through the returned record, attaches provider failure
to that record, and disappears from repeated message writes. `TeeLogSink`
resolves both children once and remains only for genuine fan-out.

One intentional protocol-order refinement accompanies resolution: tee setup is
depth-first first-child then second-child, and a child's standard message
framing may complete before the next child enters its message lifecycle. Actual
fan-out writes remain deterministic first-child then second-child. This avoids
forcing branch-specific setup back through a global event chain.

### Step 3 — Finalize prefix-before-level and arbitrary ANSI prefix bytes

**Status: complete.**

- Prefix is always before the level label.
- Prefix writes use the resolved byte path and disappear before repeated message
  writes.
- Prefix providers may combine semantic `AnsiStyle` with supported embedded SGR.
- ANSI destinations preserve embedded SGR and restore the active semantic prefix
  style after complete resets.
- Plain destinations strip supported embedded SGR from prefix output as well as
  message output.
- `LogPrefixWriter.write` and `LogRecordRef.writeText` are the fast ANSI-free
  semantic-style path. `writeAnsi` / `writeAnsiText` explicitly opt bytes into
  supported-SGR processing, recorded by `LogSinkEvent.mayContainAnsi`. This keeps
  `[level]`, separators, newline, and the ordinary timestamp prefix off the SGR
  scanner.
- `TimestampLogPrefix` uses the same path and remains allocation-free.
- Prefix failure/finalization behavior remains unchanged.

### Step 3 implementation note

The first implementation that treated every `text` event as potentially ANSI
worked functionally but made ordinary level/separator/newline framing pay the
SGR scanner too. The final API makes the expensive capability explicit instead:
`LogRecordRef.writeText` and `LogPrefixWriter.write` require ANSI-free bytes and
keep the direct presentation path, while `writeAnsiText` / `writeAnsi` opt into
supported embedded-SGR processing. The event carries `mayContainAnsi` only so
the already-resolved destination can choose preservation versus stripping.

This is also faster for the timestamp use case: its color is an out-of-band
`AnsiStyle`, so its ordinary `write` does not need to scan the timestamp bytes.
Each `writeAnsi` call is one presentation span: ANSI output ends it with a full
reset so embedded style cannot leak into a later prefix span or the level label.
A provider must not split one supported SGR sequence across two calls.

## Step 3 prefix/ANSI validation

Step 3 kept the prefix on the resolved setup path and split prefix output into
two explicit cases: `write(..., style)` for ANSI-free bytes with semantic style,
and `writeAnsi(..., style)` for bytes that may contain supported embedded SGR.
This avoids making ordinary framing and timestamp bytes pay the SGR scanner.

Three release-fast benchmark runs at 300,000 small-record iterations gave these
medians after the final Step 3 API:

| Case | Step 2 | Step 3 |
| --- | ---: | ---: |
| resolved direct protocol | 18.62 ns/record | 15.68 ns/record |
| null sink, normal small | 46.77 ns/record | 44.93 ns/record |
| plain `/dev/null`, normal small | 96.32 ns/record | 96.11 ns/record |
| ANSI `/dev/null`, normal small | 142.43 ns/record | 143.26 ns/record |
| tee null+null, normal small | 90.38 ns/record | 96.95 ns/record |
| prefix -> tee null+null, normal small | 103.11 ns/record | 108.05 ns/record |
| prefix -> tee null+null, stream 64 KiB | 119.27 ns/record | 119.68 ns/record |

The tee small-record medians moved a few nanoseconds while file presentation and
the streamed prefix/tee case remained effectively at the Step 2 level. More
importantly, a discarded prototype that sent every `text` event through SGR
processing measured roughly 103 ns for plain small records and 157 ns for ANSI
small records in one run. That structural regression is why the final API makes
embedded-ANSI processing explicit instead of scanning all framing. Final
performance judgment remains Step 6's job.

### Step 4 — Add optional logger callsite capture

**Status: complete.**

- Added `LogSourceLocation` plus logger `setCallsitesEnabled` /
  `callsitesEnabled`; source metadata is a separate borrowed setup pointer.
- Capture remains disabled by default and can be toggled at runtime without
  reconstructing the logger or sink graph.
- Bounded `log`, formatted `logf`, streaming, every explicit level wrapper, and
  every TLS level wrapper preserve the original application function/line.
- Internal fixed-position `logAt` / `logfAt` forwarding avoids the empty variadic
  tuple ambiguity discovered during implementation.
- Direct presentation renders exactly `[level] message  (function:line)`; prefix
  setup remains before the level and ANSI callsites use neutral dim-only styling.
- Callsite framing remains outside message `written` / `required` accounting.
- Capture allocates nothing and performs no stack walk, symbol lookup, or runtime
  reflection.

The original Step 4 release-fast sanity benchmark kept the disabled null-sink
topology at eight events per record and raised the then-leading-callsite
topology to ten. The later trailing-callsite presentation keeps the ordinary
level separator and adds three post-message framing writes, so the final enabled
direct topology is eleven events per record. Clean Step 4 runs placed the
small null-sink path around 48 ns/record disabled and roughly 57--62 ns/record
enabled on this sandbox. The nullable source pointer avoids copying the 24-byte
source descriptor through sink branches. Final
performance comparison remains Step 6's responsibility because the shared host
showed substantial I/O benchmark noise.

### Step 5 — Add per-branch callsite suppression

**Status: complete.**

- Added `WithoutCallsiteLogSink` as a setup-only decorator.
- Split the effective callsite pointer from `LogRecordInfo` during resolution so
  suppression forwards `null` without temporary metadata storage or copying.
- Verified suppression inside a tee affects only that branch, while suppression
  around a tee affects every descendant.
- Verified composition with setup-only prefixes and with logger capture already
  disabled.
- Verified a failing suppressed tee branch still finalizes its begun lifecycle
  while the healthy located branch completes the full record.
- The decorator returns its child's `LogRecordRef` unchanged, so it is absent
  from repeated message writes.

### Step 6 — Performance review, cleanup, and final validation

**Status: complete.**

- Re-ran the benchmark matrix and added the missing callsite-suppression topology
  case.
- Compared topology as well as timings against a Step 1 worktree built with the
  same supplied toolchain and run alternately on the same shared host.
- Kept the resolved-record representation unchanged after review: the remaining
  one-time setup cost is the deliberate price of removing setup-only decorators
  from repeated writes, and the controlled runs show the targeted composed paths
  benefiting without a material regression in ordinary bounded/file logging.
- Ran the complete debug, optimized, release-safe, release-fast compile-only, and
  AddressSanitizer test matrices in chunks where the monolithic Just recipe
  exceeded the sandbox command window.
- Built all static libraries in debug/release-safe/release-fast, ran all debug
  examples, and re-ran formatting/lint checks.
- Audited current logging documentation and marked the older whole-graph fan-out
  documents explicitly historical.
- Reviewed record lifetimes, one-shot invalidation, setup failure cleanup, tee
  branch finalization, BetterC constraints, allocations, and callback ownership.

## Step 1 baseline

### Toolchain

- LDC 1.42.0 / DMD frontend 2.112.1 / LLVM 21.1.8
- DUB 1.41.0
- dfmt 0.15.2
- D-Scanner 0.15.2
- Linux x86-64 sandbox host

### Behavioral checks

The following passed before protocol changes:

```text
core logging package unit tests
logging integration executable
logging example
format-check
lint
```

Existing unit coverage already exercises the important invariants needed by the
refactor, including prefix ordering and failure deferral, arbitrary safe chunk
forwarding, tee ordering/failure aggregation, recursive logging rejection,
ANSI/plain fan-out, SGR-safe streaming, concurrent file record atomicity, and
file-lock release after branch failure. No redundant semantic tests were added
in Step 1.

### Microbenchmark baseline

Three release-fast runs were made at 300,000 small-record iterations after
adding the prefix+tee benchmark case. The table records the median. Timings are
machine-specific diagnostics, not API guarantees.

| Case | Median |
| --- | ---: |
| current protocol, 8 null events | 14.17 ns/record |
| hypothetical 6 null events | 10.55 ns/record |
| null sink, normal small | 47.70 ns/record |
| null sink, stream small | 48.50 ns/record |
| null sink, normal 64 KiB borrowed | 57,820.25 ns/record |
| null sink, stream 64 KiB borrowed | 78.58 ns/record |
| null sink, ~64 KiB fragmented stream | 37,821.51 ns/record |
| plain `/dev/null`, normal small | 96.98 ns/record |
| plain `/dev/null`, stream 64 KiB | 924.26 ns/record |
| ANSI `/dev/null`, normal small | 139.40 ns/record |
| ANSI `/dev/null`, stream 64 KiB | 377.31 ns/record |
| tee null+null, normal small | 90.37 ns/record |
| tee null+null, stream 64 KiB | 121.74 ns/record |
| prefix -> tee null+null, normal small | 112.15 ns/record |
| prefix -> tee null+null, stream 64 KiB | 148.71 ns/record |

The topology counts are the more durable baseline:

```text
normal null record:                 8 events, 1 message chunk
normal tee branch:                 8 events, 1 message chunk
prefix -> tee branch:              9 events, 1 message chunk
streamed 64 KiB null record:       8 events, 1 direct borrowed chunk
prefix -> tee streamed 64 KiB:     9 events, 1 direct borrowed chunk
```

The prefix benchmark confirms the original cost that motivated resolution: the
prefix wrapper participated in the sink chain for every logger event even though
it only contributed one prefix write per record. Step 2 removes that wrapper
from repeated message delivery while preserving one-time prefix work.

### Step 2 resolution benchmark

After the final Step 2 API/lifetime refinement, the same release-fast benchmark
was run three times at 300,000 small-record iterations. The table records the
median and compares it with the Step 1 median where the cases are directly
comparable.

| Case | Step 1 | Step 2 |
| --- | ---: | ---: |
| null sink, normal small | 47.70 ns/record | 46.77 ns/record |
| null sink, stream small | 48.50 ns/record | 55.13 ns/record |
| plain `/dev/null`, normal small | 96.98 ns/record | 96.32 ns/record |
| ANSI `/dev/null`, normal small | 139.40 ns/record | 142.43 ns/record |
| tee null+null, normal small | 90.37 ns/record | 90.38 ns/record |
| tee null+null, stream 64 KiB | 121.74 ns/record | 102.81 ns/record |
| prefix -> tee null+null, normal small | 112.15 ns/record | 103.11 ns/record |
| prefix -> tee null+null, stream 64 KiB | 148.71 ns/record | 119.27 ns/record |

The isolated direct-record protocol itself measures 18.62 ns/record in Step 2,
versus 14.17 ns/record for the old eight-event protocol baseline. That extra
one-time setup cost is expected: `beginRecord` now constructs and validates the
resolved handle. The end-to-end normal null, file, and tee cases remain roughly
flat, while the composition targeted by the refactor improves because
`PrefixLogSink` no longer dispatches every later event. One of the three tee and
prefix-stream runs was an obvious timing outlier; medians are retained for the
same reason Step 1 used three runs.

The child event counts remain eight ordinary events plus one prefix `text` event
when a prefix exists. That is intentional: resolution removes wrapper dispatch,
not semantic output. The topology improvement is that the prefix provider runs
once during resolution and the returned child `LogRecordRef` is used directly
thereafter.

## Step 6 final performance review

The final benchmark was run three times at 300,000 small-record iterations. A
second controlled A/B used a detached Step 1 worktree and the final tree, built
with the same toolchain and run alternately on the same shared host. Timing on
this host remains noisy, so topology is the stronger invariant and the A/B
medians are diagnostic rather than contractual.

Selected controlled A/B medians:

| Case | Step 1 A/B | Final A/B | Change |
| --- | ---: | ---: | ---: |
| null sink, normal small | 61.08 ns | 52.62 ns | -13.9% |
| null sink, one-chunk stream small | 51.87 ns | 69.87 ns | +34.7% |
| plain `/dev/null`, normal small | 93.14 ns | 95.92 ns | +3.0% |
| plain `/dev/null`, stream 64 KiB | 1291.58 ns | 1280.26 ns | -0.9% |
| ANSI `/dev/null`, normal small | 144.31 ns | 146.74 ns | +1.7% |
| ANSI `/dev/null`, stream 64 KiB | 343.09 ns | 336.22 ns | -2.0% |
| tee null+null, normal small | 94.88 ns | 99.18 ns | +4.5% |
| prefix -> tee, normal small | 123.82 ns | 105.43 ns | -14.9% |
| prefix -> tee, stream 64 KiB | 145.95 ns | 123.24 ns | -15.6% |

The one-chunk null streaming microcase exposes the deliberate resolution setup
cost most clearly because it performs almost no useful formatting or I/O after
setup. That cost does not multiply with message chunks. The fragmented ~64 KiB
stream, where repeated delivery dominates, was slightly faster in the same A/B
set (43.05 us -> 41.26 us median), while the setup-only prefix composition
improved by roughly 15%. Ordinary bounded and file-backed small records stayed
within a few percent in the controlled comparison. No additional hot-path layer
was added to recover the one-chunk microcase because that would defeat the
composition model this refactor is intended to establish.

Final topology is deterministic:

```text
callsite disabled, direct branch:       8 events/record
callsite enabled, direct branch:        11 events/record
prefix -> tee child branch:              9 events/record
callsite tee suppressed child:           8 events/record
callsite tee unsuppressed child:         11 events/record
```

The prefix branch still receives one semantic prefix `text` event; the
improvement is that `PrefixLogSink` itself no longer receives or forwards the
later level/message/finalization events. Likewise `WithoutCallsiteLogSink` is
absent after setup. `TeeLogSink` remains because actual fan-out is inherently
per-write work.

A presentation follow-up moved callsites behind the message so the level remains
visually attached to its payload. The trailing callsite uses dim-only semantic
styling after `endMessage`; this adds one event versus the earlier leading
presentation because the ordinary `[level] ` separator remains. Three 300k
release-fast smoke runs measured the enabled direct null-sink case at
56.18--58.83 ns/record, still within the range observed during the original
callsite work despite the clearer presentation.

In the final-only controlled runs, enabling callsites on the direct null sink
added roughly a few nanoseconds per small record in the median. Capture remains
allocation-free: the source strings are compiler-emitted static data and the
line is an integer. The branch-suppression benchmark additionally asserts that
the suppressed branch receives eight events while its unsuppressed sibling
receives eleven after trailing-callsite presentation.

## Incremental delivery policy

All steps accumulate in one working tree. Do not reset to the archive between
steps.

After each completed step report:

- behavioral/API changes;
- checks run;
- any specification correction and why;
- cumulative diff summary;
- completed step count;
- remaining steps and approximate remaining work.

Documentation changes are part of the same step as the code they describe.

The final deliverable is produced from the complete accumulated diff with the
user's requested Git author identity.
