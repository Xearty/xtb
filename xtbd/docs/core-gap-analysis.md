# Core capability audit

This document records the comparison between C++ `libs/xtb_core` and the D
`xtb.core` package. It is a completion ledger, not a compatibility contract.
The D implementation preserves useful capabilities while rejecting unsafe
ownership, hidden global state, and macro-oriented interfaces.

## Implemented portable core

### Metadata and scalar utilities

- semantic version constants and version string;
- operating-system and architecture traits;
- fixed-width integer and floating-point aliases;
- `min`, `max`, `clamp`, checked geometric growth, and overflow helpers;
- checked KiB, MiB, GiB, and TiB scaling.

### Allocators

- intrusive `Allocator` function-pointer ABI with state stored at the allocator
  address;
- malloc-backed allocation, reallocation, and deallocation;
- typed and byte-count allocation APIs;
- typed element-count reallocation;
- byte-zeroed allocation constrained to POD element types;
- fallible and panicking variants;
- overflow, alignment, and old-allocation validation;
- caller-storage-backed `InstrumentedAllocator` with deterministic failure
  injection, active-allocation records, call counts, invalid-call counts,
  outstanding bytes, and peak bytes;
- C-to-D ABI smoke coverage for the allocator callback and handle layout.

### Arrays and borrowed slices

- non-copyable allocator-owning `Array!T` for POD, copyable, and move-only
  BetterC value types;
- `create`, `withCapacity`, `tryWithCapacity`, `withLength`, and `fromSlice`;
- fallible/panicking reserve, resize, append, and insertion;
- assume-capacity append;
- alias-safe append across reallocation;
- pop, indexed removal, range removal, clear-with-capacity-retention,
  `shrinkToFit`, and `resetAndRelease`;
- lifetime-aware construction, move relocation, reverse-order destruction,
  and POD-only bytewise fast paths;
- strong-state tests under injected allocation failure;
- native D slices as the borrowed representation;
- generic `subslice`, `drop`, `take`, `dropLast`, `takeLast`, `front`, and
  `back` UFCS algorithms.

### Strings

- mandatory read-only `String = const(char)[]` values;
- comparison, equality, search/last-search, containment, prefix/suffix,
  head/tail/truncation, ASCII trimming, basename, and extension removal;
- checked C-string borrowing and embedded-NUL detection;
- allocator-owned copy, concatenation, replacement, escaping, joining, and
  compile-time formatting;
- fallible variants of allocator-owned transformations;
- predicate splitting, token splitting, string/character splitting,
  whitespace splitting, and line splitting into allocator-owned
  `Array!String` results whose elements borrow the source;
- non-copyable `StringBuf` with creation/copy factories, fallible reserve and
  append, assume-capacity append, insertion, prepend, in-place replacement,
  escaping, capacity release, views, and checked C conversion;
- short UFCS verbs and the documented first-receiver `ref` exception.

### Arenas and scratch space

- explicit backing allocator and correctly aligned chunk allocation;
- fallible and panicking allocation, including zeroed variants;
- retained chunk reuse, clear, destruction, explicit trimming, and configurable
  retention limit;
- used, reserved, peak, and chunk-count statistics with `Writer` formatting;
- intrusive arena allocator handle compatible with the allocator ABI;
- non-copyable manual `TempArena` push/pop with strict LIFO validation;
- optional rewind poisoning, checkpoint generations, and cross-thread pop
  detection;
- explicitly installed TLS `ThreadContextScope` with configurable arena count;
- zero-, one-, and many-conflict scratch acquisition;
- panic on missing context or exhausted non-conflicting arenas;
- non-copyable RAII `ScratchScope` using the same manual pop implementation.

### Intrusive collections

- typed doubly linked `List` with explicit reusable membership hooks,
  front/back insertion, insertion before/after a node, removal, front/back pop,
  concatenation, and forward/reverse cursors;
- typed intrusive queue and stack with independent forward-link hooks;
- exact singleton membership and transition validation without C++ macro
  expansion.

### Printing and logging

- allocation-free buffered `Writer` over explicit byte sinks;
- stdout, stderr, file, `StringBuf`, and fixed-buffer destinations;
- checked short-write handling and required/truncated counts;
- integers, arbitrary radix, binary/hex wrappers, floating-point modes,
  pointers, strings, and opt-in custom `formatTo` values;
- compile-time checked `{}` formatting and allocator-owned formatted strings;
- one complete structured `LogRecord` per sink invocation;
- severity kept separate from message text;
- explicit caller-provided message storage;
- filtered, delivered, truncated, failed, recursive, and invalid logger status;
- complete-message callbacks, stdout/stderr/file factories, plain/ANSI styles,
  threshold mutation, sink replacement, and flush;
- no mutable process-global logger.

### Panic and contracts

- process-wide panic hook with a thread-local recursion guard;
- allocation-free formatted panic messages;
- source-location-bearing runtime preconditions;
- dedicated unreachable-code panic;
- recursive-panic termination guard;
- raw stderr fallback, stream flushing, and abort termination;
- subprocess death coverage for panic, missing scratch context, conflict
  exhaustion, double pop, non-LIFO pop, and cross-thread pop.

### Stack traces

- explicit `StackTraceContext`; no module constructor or mandatory global
  initialization;
- caller-provided frame and text storage;
- program counter, function, file, and line capture through libbacktrace on
  Linux;
- execinfo/dladdr fallback when debug information is unavailable;
- truncation and backend-error reporting;
- bounded D demangling with overload-oriented, return-type, and full detail;
- optional module qualifiers and source-style multiline signatures;
- non-allocating token-colored `Writer` rendering;
- the complete embedded theme catalog plus a plain theme;
- explicitly scoped panic tracing and Linux fatal-signal diagnostics;
- fault-address-only and attempted-unwind signal modes;
- runnable debug-info example.

### Build and verification

- BetterC compilation for library, tests, and examples;
- colocated unit tests with an explicit BetterC test runner;
- AddressSanitizer execution;
- UBSan capability detection with an explicit skip on the pinned LDC, which
  does not support `-fsanitize=undefined`;
- C ABI allocator smoke test;
- DScanner policy;
- DUB library and example configurations;
- Nix package and test derivations;
- optimized no-debug-info test execution;
- local AArch64 Darwin cross-compilation of the portable library;
- runnable core, print, and stack-trace examples.

## Deliberately deferred or rejected compatibility

The following C++ behavior is not part of the completed D core milestone.
These items were judged unsafe, overly global, representation-specific, or
insufficiently justified. They should not be implemented without a concrete
consumer and a new design review.

### Hidden global policy

- global heap/static allocator registry and allocator replacement;
- mutable process-global logger;
- monolithic `xtb.init(argc, argv)`;
- automatic stack-trace or signal initialization;
- module constructors that install runtime policy.

### Questionable ownership and sentinels

- invalid-string sentinel distinct from an empty string;
- C++ `StringBuf::detach()` behavior, which appears to expose freed storage;
- implicit ownership transfer from containers;

### Macro and C++ representation compatibility

- memory, array length, defer, branch-hint, logging, and linked-list macros;
- custom `Slice!T` storage instead of native D slices;
- C++ iterator and initializer-list machinery;
- sentinel/nil-node list variants;
- bootstrap arenas that co-locate the arena object and first chunk;
- exact-total-allocation-size arena constructors;
- raw `String::inspect()` output side effects;
- C variadic formatting;
- arbitrary automatic struct reflection in the printer.

### Termination and logging policy in panic

- configurable continuation after panic;
- hidden logger lookup from panic;
- attempting rich logger recursion during panic handling.

Panic always terminates. Applications may observe the panic hook, while the
core retains a minimal raw stderr path that does not depend on logger health.

## Known environmental limitation

This development host executes only x86-64 Linux binaries. The complete
portable library is cross-compiled locally for AArch64 Darwin, but builders or
CI on AArch64 Linux and Darwin are still required before claiming those targets
have been executed. Fatal-signal installation and rich stack capture are Linux
backends; elsewhere `CrashHandlerScope` still traces panics through the portable
hook and stack capture reports `backendError`.
