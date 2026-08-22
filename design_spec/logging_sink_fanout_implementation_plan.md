# Logging sink fan-out implementation plan

> **Protocol note (2026-08-22):** The repeated whole-graph `LogSinkEvent`
> dispatch described here has been superseded by the record-resolution model in
> `design_spec/logging_record_resolution.md`. This document remains useful as
> historical rationale for the fan-out/prefix behavior it introduced.


## Status

**Status: historical. Steps 1–4 were completed before record resolution superseded the whole-graph protocol.**

This is the execution plan for `design_spec/logging_sink_fanout.md`. The design
specification remains authoritative for semantics; this document defines the
order in which those semantics are implemented, tested, reviewed, and delivered.

Implementation is intentionally split into only four steps. Do not begin a later
step until the previous step has been reviewed and the user explicitly asks to
continue.

## Baseline and diff discipline

The implementation baseline, **B0**, is the XTB source tree that contains this
plan before Step 1 changes are made. If the user supplies a newer source tree
before Step 1 begins, that newer tree becomes B0 and this plan/design document
must be reconciled with it before implementation.

Every completed implementation step produces **two git-style unified diffs**:

1. **Step diff** — only the changes introduced by the current step, relative to
   the immediately preceding completed step.
2. **Cumulative diff** — every implementation change from B0 through the current
   step.

Use names of this form:

```text
logging-sink-fanout-step-01.patch
logging-sink-fanout-through-step-01.patch

logging-sink-fanout-step-02.patch
logging-sink-fanout-through-step-02.patch
```

The same pattern continues for later steps. The cumulative patch is regenerated
from B0 after every step; it is not constructed by concatenating step patches.
The step patch must remain independently reviewable and contain no changes from
later work.

Documentation changes required by a step belong in both its step diff and its
cumulative diff. Temporary build artifacts, generated binaries, local toolchain
state, and `.git` metadata never belong in either diff.

## Test discipline

Every step is test-complete before it is presented as finished.

For each step:

- add all focused unit, compile-time, integration, failure-path, and regression
  tests needed to establish that step's complete contract;
- run the focused tests for the changed logging/printing code;
- run the relevant BetterC configurations and repository checks available in the
  supplied toolchain;
- verify the tests in both the step-only state and the cumulative state are the
  same source result;
- update the design specification and this plan when implementation discoveries
  change an invariant, public API, or deferred decision; and
- do not leave known behavior intentionally untested for a later step when that
  behavior is already introduced by the current step.

Tests for later functionality are not required early, but every public or
internal behavior introduced in the current step must be covered before moving
on.

---

## Step 1 — Establish the composable sink protocol and logger-owned framing

**Status: complete.**

### Goal

Replace the record-at-once sink boundary with the small explicit lifecycle
protocol while keeping ordinary logger construction and logging usage coherent.
Move ownership of textual framing out of built-in destinations and into
`Logger`.

### Implementation

- Finalize the public/internal names for the event protocol and `LogSinkRef`.
- Introduce explicit record/message lifecycle delivery; sinks must never infer a
  first chunk.
- Change `Logger` to emit the level label text itself, with the selected
  presentation style carried separately from the bytes.
- Change `LogPalette` to distinguish level-label style from the optional base
  message style.
- Migrate `Logger.create`, `setSink`, flush handling, recursion protection, and
  the built-in logger factories to the new sink reference/protocol.
- Preserve the normal `stderrLogger`, `stdoutLogger`, `fileLogger`, `log`, `logf`,
  and level-specific convenience APIs where the design allows it.
- Choose and implement the compatibility strategy for old record callbacks; do
  not retain record-at-once buffering merely to preserve the old callback shape.
- Keep message bytes verbatim. Do not add style spans, ANSI metadata, or message
  rewriting.

### Complete tests for this step

At minimum, test:

- exact lifecycle/event ordering for an accepted record;
- logger-generated spelling and placement of all six level labels;
- label style selection and optional message-style selection from the palette;
- no events at all for filtered calls;
- invalid logger behavior;
- recursion rejection without corrupting the outer lifecycle;
- sink rejection and flush failure propagation;
- empty and non-empty messages;
- `log`, `logf`, and every level-specific convenience wrapper;
- `setMinimumLevel`, `setPalette`, and sink replacement;
- compile-time/public API construction and non-copying constraints; and
- regression coverage showing ordinary plain/ANSI convenience loggers still
  produce the expected logical line structure.

### Step 1 completion gate

The protocol is usable directly by tests/custom sinks, logger framing no longer
comes from file-sink context, and no destination has to infer record position.
Produce the Step 1 diff and the B0-through-Step-1 cumulative diff.

---

## Step 2 — Implement ANSI/plain presentation and safe chunk plumbing

**Status: complete.**

### Goal

Make the new protocol correctly support rich terminal output and plain output
from the same verbatim formatted message stream, including optional base message
color and ANSI-safe chunk boundaries.

### Implementation

- Implement/refactor the ANSI presentation sink and the plain presentation sink
  on top of the lifecycle protocol.
- ANSI sink:
  - render logger-provided styles;
  - preserve supported embedded SGR bytes in message chunks;
  - use the direct-write fast path when no base message color is configured;
  - when a base message color is configured, recognize complete full resets and
    restore that base style for following message bytes;
  - fully reset terminal presentation at logical record/message completion.
- Plain sink:
  - ignore logger-generated presentation styles;
  - preserve all ordinary text;
  - use a fast no-ESC direct path;
  - strip supported complete embedded SGR sequences when present.
- Implement the logger/plumbing invariant that a sink message chunk never ends
  inside a supported well-formed SGR sequence.
- Make chunk normalization a bounded suffix operation rather than a full-message
  ANSI scan.
- Keep formatter output slices verbatim and zero-copy; safe delivery is achieved
  by selecting safe slice boundaries, not by rewriting the message.
- Keep the current logger formatter path as one bounded caller-provided buffer;
  do not invent a new streaming formatter merely for this step. The sink
  protocol must nevertheless behave correctly for multiple already-safe
  `messageChunk` events. True formatter-chunk continuation of a split SGR
  remains deferred under the zero-copy rule in the design specification.
- Define final truncation semantics: an incomplete terminal SGR suffix is not
  emitted, and record finalization still restores a known terminal state.
- Preserve UTF-8-safe boundary behavior and make it compose with SGR-safe
  boundaries.
- Keep `LogResult` accounting well-defined for safely delivered/truncated
  message bytes.

### Complete tests for this step

At minimum, test:

- plain and ANSI output with no message base color;
- every level with an independently configurable label style;
- optional message base color across multiple message chunks;
- embedded foreground/background/attribute SGR sequences;
- embedded `ESC[0m` with and without a base message style;
- partial resets such as `39m` not being treated as a full reset;
- final terminal reset on normal completion, sink failure paths where possible,
  and truncation;
- plain stripping of one and many SGR sequences;
- no-ESC fast paths for both presentation modes;
- complete SGR ending exactly at a chunk boundary;
- incomplete SGR beginning near every relevant suffix position;
- base-style and embedded-SGR behavior across multiple already-safe protocol
  chunks;
- final truncation inside an SGR emits none of the partial sequence;
- ordinary bytes before a withheld suffix remain byte-for-byte unchanged;
- UTF-8 scalar boundaries adjacent to ANSI sequences;
- bounded handling of malformed input without out-of-bounds/unbounded scanning;
- large messages that span the printer's internal buffering while remaining one
  current logger message chunk; and
- exact `LogResult.written` / `required` semantics after safe boundary handling.

### Step 2 completion gate

A single logger can feed either ANSI or plain presentation correctly; formatter
message bytes are never semantically rewritten; the current bounded formatter
output cannot expose a partial supported SGR on truncation; multiple safe
protocol chunks preserve presentation state; and the common no-message-color
path does not require embedded-reset parsing. Produce the Step 2 diff and the
B0-through-Step-2 cumulative diff.

---

## Step 3 — Add `TeeLogSink` and prove composability/record atomicity

**Status: complete.**

### Goal

Add fan-out as a general sink-protocol combinator and prove that rich terminal
presentation and plain-file presentation can coexist without duplicate
formatting or fragile first-chunk state.

### Implementation

- Add `TeeLogSink` over two borrowed `LogSinkRef` children.
- Forward lifecycle and payload events in deterministic order.
- Attempt both branches even when one branch fails.
- Track only the minimal per-record branch health required for correct failure
  aggregation/finalization; do not add logging/presentation knowledge to the
  tee.
- Ensure a branch that began a record receives required finalization events even
  after a payload failure, so terminal state and destination locks cannot be
  stranded.
- Flush both children and aggregate the result.
- Support nested tees with the same semantics.
- Ensure file-backed presentation sinks hold their destination lock across the
  whole logical record rather than independently around arbitrary chunks.
- Preserve one formatting pass per logger call regardless of fan-out depth.

### Complete tests for this step

At minimum, test:

- both healthy branches receive every event in order;
- first-branch failure does not prevent second-branch progress;
- second-branch failure does not prevent first-branch progress;
- simultaneous failures aggregate correctly;
- failed-but-begun branches still receive required finalization;
- flush always attempts both branches;
- nested tee ordering and failures;
- colored terminal + plain file from the same log call, including level label,
  optional message base color, and embedded SGR;
- plain branch contains no logger-generated or embedded SGR;
- formatter/custom-value formatting executes once, not once per branch;
- filtering prevents all tee activity;
- recursion semantics remain logger-local rather than tee-local; and
- concurrent per-thread loggers sharing a file destination cannot interleave
  chunks inside one record and cannot strand the file lock on failure.

### Step 3 completion gate

The tee is presentation-agnostic, nestable, failure-resilient, and demonstrates
the primary use case: one formatting pass producing colored terminal output and
plain file output. Produce the Step 3 diff and the B0-through-Step-3 cumulative
diff.

---

## Step 4 — Stabilize the public surface, examples, documentation, and full gates

**Status: complete.**

### Goal

Turn the proven implementation into the finished XTB feature without carrying
transitional API/documentation debt.

### Implementation

- Review the names and visibility of the new sink/event/presentation types after
  real use in Steps 1–3; make only justified API cleanup changes.
- Remove temporary compatibility adapters that are not intended to remain, or
  document the ones deliberately retained.
- Update `examples/logging_demo.d` to show:
  - ordinary plain logging;
  - ANSI terminal logging;
  - custom per-level label/message styles;
  - embedded message ANSI;
  - ANSI terminal + plain file tee; and
  - flush/lifetime requirements.
- Reconcile `docs/architecture.md`, package exports, this implementation plan,
  and `design_spec/logging_sink_fanout.md` with the actual final API.
- Add/finish any end-to-end regression, stress, death, or compile-negative tests
  exposed by the complete implementation.
- Run the broad repository validation available under the supplied toolchain,
  including formatting/static-analysis/build matrices relevant to changed code.
- Do a focused code review for ownership, callback lifetimes, BetterC
  compatibility, error/finalization paths, accidental allocations, unnecessary
  copies, and performance regressions.

### Complete tests for this step

This step does not defer correctness to documentation. In addition to retaining
all earlier tests, add whatever final coverage is needed for:

- public package imports and examples compiling under BetterC;
- final compatibility behavior;
- representative long/multi-chunk tee output;
- nested composition through public APIs;
- final failure and flush behavior;
- final threaded file atomicity/stress coverage; and
- compile-time rejection of invalid sink/lifetime constructions that the final
  API promises to reject.

Run the full relevant test/build/check matrix and ensure no earlier logging tests
were weakened or deleted merely to accommodate the new implementation.

### Step 4 completion gate

The code, tests, examples, architecture documentation, design specification, and
public exports all describe the same stable implementation, and the relevant
repository gates pass. Produce the Step 4 diff and the final B0-through-Step-4
cumulative diff.

---

## Per-step delivery checklist

For every step delivered to the user:

- summarize what changed and any design decision that had to be refined;
- state exactly which focused and broad checks were run and their results;
- call out any limitation that remains intentionally for a later step;
- provide the **step-only patch**;
- provide the **B0-through-current-step cumulative patch**;
- provide updated source files/project archive when useful for applying or
  inspecting the work; and
- provide a normal final commit message for the completed step.

Do not start the next step until requested.
