# Core gap analysis

This document compares the C++ `libs/xtb_core` capability set with the D
`xtb.core` implementation. It is an inventory, not a compatibility promise:
the D project keeps idiomatic BetterC designs and deliberately rejects several
C++ APIs whose ownership, global-state, or macro semantics are undesirable.

## Major missing subsystems

### Stack traces

The stack-trace subsystem has not been implemented:

- stack-frame collection;
- explicit executable/debug-information initialization;
- filename, function, line-number, and program-counter capture;
- symbol demangling where the platform supports it;
- missing-debug-information frame handling;
- formatted stack-frame output through an explicit `Writer`;
- signature tokenization and classification;
- optional colored signature formatting and color configuration;
- `printStackTrace(skipFrames)` and full-stack convenience operations.

The C++ implementation is tied to libbacktrace and C++ demangling. The D API
should put a portable frame/sink interface above per-platform backends and must
not require stack-trace initialization for programs that do not use it.

### Fatal process signals

There is no equivalent of the Linux fatal-signal support:

- handlers for `SIGABRT`, `SIGFPE`, `SIGILL`, `SIGINT`, `SIGSEGV`, and
  `SIGTERM`;
- reentrant-handler protection;
- signal-specific exit codes and descriptions;
- stack-trace emission after a fatal signal;
- explicit handler installation and restoration;
- subprocess tests for signal behavior.

This must be opt-in and platform-specific. It must not be installed by a module
constructor or a monolithic library initializer. Only async-signal-safe work is
allowed in a signal handler; the C++ implementation's logging, allocation, and
rich formatting must not be copied into that context.

## Strings

The following `String` capabilities remain missing:

- a checked C-boundary helper for borrowing or copying a NUL-terminated string;
- `front`, `back`, and a project-level `empty` predicate;
- escaping control characters and quotes;
- predicate-based splitting;
- predicate-based token splitting that discards empty tokens;
- splitting by `String`, character, ASCII whitespace, and lines;
- an owning collection of borrowed split results, preferably `Array!String`;
- allocator-backed formatting that directly produces an allocator-owned view;
- explicitly fallible allocation-based string operations;
- embedded-NUL validation for C APIs that would truncate the input.

`StringBuf` still lacks:

- `appendAssumeCapacity` with a checked precondition;
- `tryPrepend`;
- fallible construction/copy operations;
- insertion at an arbitrary offset;
- in-place replacement;
- escaping and formatting directly into an existing builder;
- a release/reset operation that frees retained capacity;
- an explicit, safe ownership-transfer operation, if allocator semantics make
  one useful.

The C++ invalid-string sentinel remains intentionally rejected: an empty
`String` is valid and expected failures use status values. C++ `inspect()` is
also intentionally omitted because a string value should not hide an output
side effect. The C++ `StringBuf::detach()` implementation appears to return
storage after `clear()` frees it; it must not be reproduced. Any D transfer API
must leave the source empty without releasing the transferred allocation.

## Arrays and generic slices

`Array!T` still lacks:

- `fromSlice` copying construction;
- `withLength` construction;
- fallible factories such as `tryWithCapacity`;
- `appendAssumeCapacity`;
- fallible removal;
- insertion and range removal;
- `shrinkToFit`;
- `resetAndRelease`;
- explicit ownership transfer/release;
- an owning variant for elements requiring destruction.

The current `Array!T` deliberately accepts only POD elements. Its `clear()`
retains capacity, unlike the C++ operation that frees it; retaining capacity is
the desired container convention, but `resetAndRelease()` is needed for the
other behavior.

Native D slices intentionally replace the C++ `Slice!T` representation, but
generic allocation-free UFCS algorithms are missing:

- `subslice`/range validation;
- `drop`, `take`, `dropLast`, and `takeLast`;
- checked `front` and `back` access;
- optional index-aware iteration helpers only where native `foreach
  (index, value; slice)` is insufficient.

C++ iterators, initializer lists, and raw `data()` access do not need direct D
ports. Native slices already provide the borrowed representation and normal
iteration.

## Intrusive collections

The D doubly linked list still lacks:

- insertion before or after an arbitrary node;
- `popBack`;
- concatenation;
- forward and reverse range iteration.

The singly linked structures from the C++ macro collection are absent:

- a doubly headed queue with push-back, push-front, and pop;
- a singly headed stack with push and pop.

Custom sentinel/nil-node support should be added only if a real consumer needs
it. The implementation should use typed templates and checked UFCS operations,
not macro-equivalent token substitution.

## Allocators

The essential intrusive allocator ABI and malloc allocator exist. Missing
conveniences and diagnostics are:

- typed element-count `tryReallocate!T` and `reallocate!T`;
- `tryAllocateZeroed!T` and `allocateZeroed!T`;
- byte-specific helpers where they improve call-site clarity;
- a public instrumented allocator for counts, outstanding bytes, alignment,
  and invalid frees;
- a deterministic failing allocator for failure-path tests;
- allocator statistics suitable for diagnostics.

The C++ global heap/static allocator registry, getters, setters, and allocator
initialization remain intentionally omitted. Allocator selection in D is
explicit and must not depend on mutable process-wide defaults.

## Arenas and scratch

The allocator-backed arena, aligned allocation, retained chunk reuse, manual
`TempArena` push/pop, TLS thread context, conflict selection, and RAII
`ScratchScope` are implemented. Missing capabilities are:

- current used-byte and reserved-byte statistics;
- peak/high-water tracking;
- human-readable usage formatting through the print layer;
- explicit trimming of retained chunks;
- a configurable retention/high-water policy;
- optional poisoning of rewound storage;
- generation/checkpoint diagnostics for stale use and invalid pop;
- thread-identity checks for cross-thread scope use;
- a fallible low-level arena allocation operation.

Heap-owning pointer construction, exact bootstrap sizing, and storing the arena
and first chunk in one allocation are C++ representation choices rather than
required public capabilities. They should be introduced only if profiling
justifies them.

## Panic and contracts

Missing panic/contract behavior includes:

- formatted panic messages without allocation;
- source-location-aware contract diagnostics;
- a dedicated `unreachable` helper;
- recursion protection if panic handling itself fails;
- configurable termination/exit policy where testing or embedding requires it;
- explicit output flushing policy;
- optional integration with an explicit `Logger`;
- subprocess death tests for all panic contracts.

D `assert` and `static assert` replace most C++ contract macros. The project
still needs a documented distinction between removable internal assertions and
always-enforced public/runtime preconditions.

## Logging and printing

The explicit D `Logger`, `Writer`, sinks, compile-time formatting, fixed-buffer
output, file output, and custom `formatTo` extension are implemented. Missing
logger capabilities are:

- a callback adapter receiving one complete logical message and severity;
- a default stderr logger factory;
- optional ANSI severity styling;
- reporting of short writes/sink failure from `log`;
- explicit flush support.

The current byte sink may be called more than once for one log operation, so it
is not semantically equivalent to the C++ complete-message callback. Mutable
global logger state, logging macros, C variadics, arbitrary struct reflection,
and large fixed formatting buffers remain intentionally omitted.

## Core utilities and metadata

Still missing:

- semantic version constants and a version string;
- checked byte-unit helpers for KiB, MiB, GiB, and TiB;
- generic `max` and `clamp` utilities;
- a reusable checked geometric-growth calculation;
- flag/mask aliases only if they add meaning at real call sites;
- a small public platform/architecture trait surface if consumers require it.

A monolithic `xtb.init(argc, argv)` remains intentionally omitted. Stack
tracing, signals, logging, and thread contexts have different costs and
lifetimes and should be initialized explicitly. C++ memory, array-length,
unused-value, branch-hint, and defer macros should be expressed with D language
features or narrow functions rather than ported.

## Testing and build gaps

- panic and contract death tests;
- scratch acquisition-failure, non-LIFO, double-pop, and missing-context tests;
- cross-thread context/scratch tests;
- injected allocator-failure and partial-cleanup tests;
- reusable allocator leak/alignment/double-free tests;
- logger short-write and failing-sink tests;
- C ABI smoke tests for exported ABI-facing declarations;
- stack-trace and signal subprocess integration tests;
- UndefinedBehaviorSanitizer in addition to AddressSanitizer;
- actual build validation for every system advertised by the flake.

## Proposed next implementation milestone

The next milestone should be deliberately broad and should complete the
portable foundational layer before platform diagnostics are allowed to shape
it.

### 1. Complete allocator and container failure semantics

- Add typed reallocations and zeroed allocations.
- Add reusable instrumented and deterministic failing allocators.
- Add `Array.fromSlice`, `withLength`, fallible factories,
  `appendAssumeCapacity`, insert/range removal, `shrinkToFit`, and
  `resetAndRelease`.
- Specify strong failure guarantees and test every operation under allocation
  failure.

### 2. Complete borrowed-slice and string manipulation

- Add generic slice UFCS algorithms.
- Add `String` front/back/empty, escaping, all split forms, and C-boundary
  validation.
- Represent split results as allocator-owned `Array!String` whose elements
  borrow the original bytes; document both lifetimes explicitly.
- Add fallible and builder-writing variants for every allocating string
  transformation.
- Add `StringBuf` insertion, replacement, assume-capacity operations,
  `tryPrepend`, and `resetAndRelease`.

### 3. Finish intrusive collections

- Add arbitrary DLL insertion, `popBack`, concatenation, and typed iteration.
- Add typed intrusive queue and stack templates.
- Test membership, empty transitions, concatenation, and misuse contracts.

### 4. Add arena observability and retention control

- Track used, reserved, and peak bytes.
- Add non-allocating usage formatting.
- Add explicit trim and configurable retention policy.
- Add optional debug poisoning and checkpoint-generation validation without
  changing release-build API behavior.

### 5. Harden panic, contracts, logging, and tests

- Add source-location contracts, `unreachable`, and panic recursion handling.
- Add a complete-message logger callback adapter, stderr factory, flush, and
  visible sink-failure result.
- Build a BetterC subprocess death-test harness and cover scratch and panic
  contract violations.
- Add UBSan and C ABI smoke-test targets to `just check`/flake checks where
  supported.

### 6. Add the portable stack-trace abstraction and one production backend

- Define allocation and lifetime semantics for captured frames.
- Define an explicit stack-trace context rather than mutable hidden global
  initialization.
- Implement and test the Linux backend first, including symbolization and
  graceful operation without debug information.
- Print through `Writer`; keep ANSI styling optional and policy-driven.

Fatal signal handling should follow this milestone, after the stack-trace
backend exists. It is intentionally not bundled into the first implementation
because async-signal safety requires a much narrower path than ordinary stack
capture and formatted output.

## Deferred or rejected C++ compatibility

Do not implement these merely for parity:

- global heap/static allocator selection;
- a mutable process-global logger;
- an invalid-string sentinel;
- `String::inspect()` output side effects;
- the unsafe C++ `StringBuf::detach()` behavior;
- automatic process-wide initialization;
- macro ports for slices, lists, memory operations, defer, or logging;
- automatic fatal-signal handler installation;
- C variadic formatting as the ordinary D interface.

Revisit a deferred item only when a concrete consumer demonstrates a need that
cannot be met cleanly by the existing BetterC architecture.
