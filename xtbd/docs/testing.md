# Testing

## Strategy

Use D's built-in `unittest` blocks for focused tests and keep them in the
module they exercise. This gives private-symbol access, keeps behavior close to
its implementation, and lets tests move with a module. Use `tests/` only when a
test spans public modules, needs fixtures, checks an ABI, or reproduces a bug
more clearly as an external consumer.

All tests run with `-betterC`. A test suite that runs only with the full D
runtime can hide forbidden dependencies and is not an acceptable substitute.
BetterC does not emit `ModuleInfo`, so the ordinary runtime test discovery used
by `dub test` must not be assumed. Test executables explicitly enumerate their
modules and invoke unit tests with `__traits(getUnitTests, module_)`.

The pinned D-Scanner 0.15 parser does not understand interpolated expression
sequence literals yet. `just lint` therefore sends only the interpolation-
bearing printer module and example through LDC's warning-as-error semantic
check and sends every other supported file through D-Scanner. Keep that
exception list narrow and remove it when D-Scanner can parse `i"..."`; all
printer unit tests and build variants still compile those files with LDC.

## Colocated unit tests

Put tests immediately after the declaration or small group of declarations
they cover. Keep production imports at module scope and test-only imports local
to the `unittest` block where possible.

```d
module xtb.math.scalar;

@safe nothrow @nogc:

import xtb.core.panic : require;

int clamp(int value, int low, int high)
{
    require(low <= high, "invalid clamp range");
    return value < low ? low : value > high ? high : value;
}

unittest
{
    assert(clamp(-1, 0, 10) == 0);
    assert(clamp(4, 0, 10) == 4);
    assert(clamp(11, 0, 10) == 10);
}
```

Module and aggregate attribute blocks establish the common BetterC contract;
do not repeat `nothrow @nogc` on every function or unittest. Add a narrower
attribute locally only when it documents a real boundary. Avoid heap-backed
literals, concatenation, exceptions, and test helpers that accidentally
require Druntime. Fixed-size stack arrays, slices, caller-provided buffers, and
libc facilities are appropriate.

## BetterC test runner

Maintain one small runner per coherent package or test shard. It imports the
modules in that shard and lists them explicitly. Explicit enumeration is
intentional: it replaces unavailable `ModuleInfo` discovery and makes omissions
visible in review.

The explicit runners are `core_tests.d`, `math_tests.d`, `os_tests.d`, and
`serde_tests.d`.
The OS runner creates a process-unique directory below `/tmp`, touches only
paths inside it, and removes every created file and directory before returning.
Platform runtime assertions are backend-versioned; the same runner remains a
compile check where no native backend exists.

Process integration tests compile `tests/support/process_helper.d` as a
dedicated BetterC executable. Use its length-unambiguous argv/environment
output and binary stream modes instead of depending on shell parsing or the
host behavior of `echo`, `cat`, and `sleep`.
Its flood mode deliberately exceeds stdin, stdout, and stderr pipe capacities
at the same time, proving that communication makes progress in every direction.
Pipeline tests cover both borrowed `Command[]` and `PipelineStage[]`, failure
rollback, allocator failure, per-stage status/success policy, and RAII reaping.

```d
module tests.core_runner;

import xtb.core.memory;
import xtb.core.result;

alias testedModules = AliasSeq!(xtb.core.memory, xtb.core.result);

template AliasSeq(T...)
{
    alias AliasSeq = T;
}

extern(C) int main()
{
    static foreach (testedModule; testedModules)
        static foreach (testFunction;
            __traits(getUnitTests, testedModule))
            testFunction();
    return 0;
}
```

If compiler parsing makes module aliases awkward, keep the same mechanism in a
tiny generated runner. Generation must be deterministic, inspectable, and
based only on `source/xtb/**/*.d`; check the generator into `tools/`, not its
build output. Whenever a production module is added, verify that a runner
imports it. The standard command should build each runner with both
`-unittest` and `-betterC` and then execute it.

## Test layers

1. **Compile-time checks** use `static assert`, `__traits(compiles, ...)`, and
   type/size/alignment checks next to the relevant API. They are ideal for ABI,
   template, and attribute guarantees.
2. **Unit tests** are colocated `unittest` blocks for pure algorithms, parsers,
   containers, ownership transitions, and validation.
3. **Integration tests** in `tests/` call public APIs across module boundaries.
   They may create files only inside a runner-provided temporary directory.
4. **ABI smoke tests** compile and link a minimal C caller against exported
   `extern(C)` functions. Test both symbol/link compatibility and layouts.
5. **Examples** compile in CI as consumer checks. They are documentation, not a
   replacement for assertions.
6. **Fuzz targets** expose libFuzzer's `LLVMFuzzerTestOneInput` C ABI and are
   built with AddressSanitizer plus inline-counter/PC-table coverage. A short
   run belongs in the standard gate; longer corpus-backed runs belong in
   dedicated jobs.

Window and graphics tests are split into deterministic state-machine tests and
thin backend smoke tests. Backend smoke tests must skip explicitly when their
documented display/GPU prerequisite is absent; they must not silently pass.

## What to test

For each API, cover the normal case, boundary values, invalid input, and cleanup
after partial failure. In this project pay particular attention to:

- zero-length and one-element slices;
- null pointer plus zero length versus invalid null plus nonzero length;
- required mutable pointers reject null, and pointer-based mutation is visible
  and limited to the documented fields;
- integer overflow in byte/element size calculations;
- exact-capacity and one-past-capacity allocator/container operations;
- malformed, truncated, and adversarial serialized input;
- short reads/writes and operating-system error mapping;
- repeated `create`/`deinit`, zero-state cleanup, and allocator failure;
- owning-container destruction order, removal and shrinking of elaborate
  elements, relocation without double destruction, move-only elements, and
  copy-constrained slice operations;
- hash-container growth, replacement, duplicate insertion, tombstone reuse,
  removal, shrinking, cursor and ref/pointer `foreach` coverage, immutable
  keys, explicit value-pointer/ref mutation, deterministic/custom hashing, and
  seeded hashing;
- constant-hash collision chains and allocation failure during each table
  allocation, with the previous table and every live value preserved;
- hash-map value destruction on replacement, removal, clear, release, and
  scope exit without double destruction;
- byte-zeroed allocation produces all-zero POD storage and rejects elaborate
  element types at compile time;
- foreign enum/range validation and callback user-context preservation;
- bit-flag sparse positions, inferred and explicit storage widths, raw-mask
  validation, truncation, set algebra, and release-mode rejection of
  cast-created undeclared enum values before any shift;
- flag-set iteration order, empty/full traversal, `break`, and snapshot
  behavior when the source set changes inside the loop.

Allocator-aware code should be tested with a small instrumented allocator that
can count allocations, detect leaks/double frees, enforce alignment, and fail
on the Nth allocation. Keep it BetterC-compatible and share it from
`tests/support/` only when several modules need it.

String tests enforce the type boundary as well as textual behavior:

- `String` exposes no mutable pointer/slice, `alias this`, `opIndex`, or
  `opSlice`, and its algorithms do not alter the source bytes;
- copying and `sliceBytes` allocate nothing and preserve the correct borrowed
  range while rejecting offsets inside a UTF-8 sequence;
- `byteLength`, code-unit access, code-point count, and code-point traversal are
  tested as distinct units on the same multibyte text;
- checked construction rejects malformed raw `char` and `u8` slices with exact
  error offsets, while ordinary construction and `StringBuf.view` always
  produce valid UTF-8;
- operations that create bytes either return an explicitly allocator-backed
  `String` or return/write `StringBuf`; the view itself never owns storage;
- `StringBuf` growth preserves content, honors alignment, checks overflow, and
  leaves valid state after injected allocation failure;
- `view()` reflects current bytes and tests never use it after a mutation that
  invalidates the view;
- copying into another `StringBuf` creates independent ownership and allocator
  lifetime;
- zero-length strings, embedded NUL, malformed external UTF-8, and multibyte
  UTF-8 are covered according to each API's byte/scalar contract;
- `String` and `StringBuf` equality with literals, raw code-unit slices, and
  other strings/buffers is tested in both operand orders, including inequality
  and `String.init`/empty-buffer equivalence;
- C conversion adds exactly one terminator outside logical length, rejects
  embedded NUL when required, and respects scratch lifetime;
- compile-time checks reject copying an owning `StringBuf`, reject mutation
  through `String`, and reject implicit conversion from `String` to an array;
- mutating operations compile with direct UFCS (`buffer.append(value)`) using
  only the allowed first-parameter `ref` receiver.

Printer tests cover interpolated expression sequences through direct output,
`StringBuf`, fixed-buffer, and allocator-owned sinks. Include empty and nested
sequences, expressions with side effects, custom `formatTo` values, numeric
format wrappers, mixed ordinary/interpolated arguments, exact fixed-buffer
accounting, truncation, and injected allocation failure. Assert that every
expression and custom formatter runs exactly once and that expression-source
metadata is never emitted or evaluated by the printer.

Scratch-space tests additionally verify:

- ending a scope restores the exact chunk and offset checkpoint;
- manual `push`/`pop` restores the same checkpoint as `ScratchScope`;
- manual scopes are balanced across every tested control-flow path;
- nested scopes on one arena rewind in LIFO order;
- allocator conflicts select a different arena by handle identity;
- acquisition panics when every thread-context arena conflicts or no thread
  context is installed; test this with the project's death-test/subprocess
  mechanism;
- an output allocated from a conflicting persistent allocator survives rewind;
- scratch-backed pointers become invalid after rewind; when optional generation
  checks or poisoning are enabled, verify that they expose stale use;
- alignment and arena growth remain correct across chunk boundaries;
- repeated scopes reuse retained chunks rather than allocating every time;
- early return invokes the RAII destructor and restores the checkpoint;
- copying a `ScratchScope` fails at compile time;
- copying a `TempArena` fails at compile time;
- double pop/destruction, non-LIFO pop/destruction, a second thread context,
  and cross-thread use panic in tests that deliberately violate those
  contracts.

Serde tests additionally verify:

- every supported scalar, enum, nested struct, pointer, fixed array, and
  dynamic-slice shape round-trips through each applicable backend;
- `Option!T` covers trivial, borrowed, and move-only owning values; JSON null
  and missing fields remain absent, TOML omits absent values, nested optional
  tables decode correctly, and `@required` checks key presence independently
  of JSON nullness;
- rename, legacy alias, ignore, required, explicit-default, omit-default,
  omission-predicate, adapter, and flatten attributes compose correctly, with
  invalid or conflicting schemas rejected at compile time;
- preserve, camel, Pascal, snake, screaming-snake, and kebab key policies
  handle acronym and existing-separator boundaries, with struct defaults,
  document overrides, exact renames, and exact aliases tested separately;
- unknown-field policy, duplicate keys, missing required fields, type
  mismatches, integer overflow, non-finite floats, maximum depth, and maximum
  collection length report the exact error category and useful source
  position;
- external, internal, and adjacent tagged unions round-trip at roots and in
  nested values, accept tag-after-payload ordering, preserve enum aliases and
  casing, and reject missing, duplicate, unmapped, or unknown discriminants;
- raw owning union cases, incomplete case maps, duplicate discriminant values,
  internal non-struct cases, name collisions, and malformed adapters fail at
  compile time;
- JSON escaping, UTF-8, Unicode surrogate pairs, whitespace, and strict
  rejection of comments/trailing commas are covered independently;
- TOML comments, dotted/table paths, quoted keys, basic and literal strings,
  scalar arrays, inline nested tables, and arrays of inline tables are covered
  within the supported schema data model; explicitly unsupported TOML value
  kinds are rejected deterministically;
- allocation failure at every allocation point leaves `Deserialized!T` empty
  and the instrumented allocator balanced;
- destroying or resetting a successful `Deserialized!T` recursively releases
  the root, copied strings, slices, and nullable pointer values exactly once;
- owning decodes populate `StringBuf`, `Array!T`, nested owning structs, and
  fixed arrays, including those nested in `Option!T`, without an ownership
  wrapper; the result remains freely mutable and normal RAII destruction
  releases every nested allocation;
- absent owning fields retain the decode allocator and can grow immediately,
  while omit-default compares empty owning containers without allocating;
- any owning decode failure destroys the temporary partial graph, balances the
  caller's allocator, and leaves a previously populated output unchanged;
- replacing a successful owning output releases its former graph exactly once,
  including arrays of move-only strings and nested owning records;
- serializers allocate nothing, propagate sink failure, produce deterministic
  field order, and never emit a partial token after detecting an unsupported
  value; and
- the shared backend-contract harness runs the same casing, alias, required,
  default, omission, option, nested-value, unknown-field, and round-trip cases
  against JSON and TOML, while backend-specific grammar tests remain separate;
- JSON and TOML fuzz targets accept arbitrary byte slices under AddressSanitizer
  with bounded depth and collection limits.

Stack-trace tests use synthetic signatures to cover valid D linkage names,
truncated length fields, unsupported encodings, empty output buffers, and ANSI
versus plain rendering. Run crash handlers only in death-test subprocesses.
The fault-address-only signal mode is the deterministic test target: assert
nonzero signal termination and capture stderr when exact diagnostics matter.
Attempted stack unwinding is an integration smoke test rather than a
deterministic assertion because unwinder behavior varies with architecture,
optimization, unwind
tables, and the instruction at which the signal arrived.

## Regression tests and fixtures

A bug fix starts with the smallest test that fails for the reported reason.
Keep it colocated if it exercises one module; otherwise name an external test
after the behavior, not an issue number alone. Add a short comment linking the
issue only when the scenario is non-obvious.

Store small textual fixtures as source literals. Put binary or large fixtures
under `tests/fixtures/<area>/`, record their origin/license, and assert their
expected size or digest so accidental changes are visible. Never read fixtures
relative to the process working directory without resolving the repository or
runner fixture root explicitly.

## Tooling and commands

The Nix development shell is the canonical toolchain and provides LDC, DUB,
`dscanner`, `dfmt`, `just`, and native debugging tools. `dub.sdl` and the
`justfile` should expose these stable commands once source code is introduced:

```sh
nix develop
just lint            # dscanner plus project policy checks
just format          # format all D sources, runners, fuzzers, and examples
just test            # every BetterC runner
just build           # production static library with -betterC
just test-sanitize   # BetterC runner under AddressSanitizer
just fuzz-smoke      # short ASan/libFuzzer parser and container runs
just examples        # compile and run public consumer examples
just check           # complete local verification matrix
```

D-Scanner 0.15.2's static-analysis visitor does not terminate on the
allocation-free signature styling module, although its lexer and parser accept
the module immediately. Until that upstream defect is fixed, `just lint` runs
D-Scanner's syntax checker on `stacktrace_style.d` and all configured static
analysis checks on every other D file. LDC still compiles the style module with
the same BetterC warnings/deprecations policy in every build and test command.

Fuzz harnesses receive syntax checking but are excluded from D-Scanner's naming
style pass because `LLVMFuzzerTestOneInput` is a required foreign symbol, not a
D naming choice.

Keep formatting consistent with the surrounding modules and use DScanner for
syntax and style enforcement. Do not mix a repository-wide formatting rewrite
into a functional change. Treat compiler warnings and
deprecations as errors in CI. Use sanitizers supported by LDC/Clang for native
debug test builds. AddressSanitizer is mandatory on the pinned toolchain;
UndefinedBehaviorSanitizer is run when the compiler accepts it and otherwise
reports an explicit capability skip. Retain a normal debug run because
sanitizers change execution.

Coverage is a trend and gap-finding tool, not a substitute for boundary cases.
If BetterC coverage support is unavailable on a target, collect it in a
separate compatible job without weakening the canonical BetterC build/test
gate.

## Definition of done for tests

- The regression test fails before a bug fix when practical.
- Focused and complete BetterC test runners pass.
- New production modules are included in a runner.
- Failure paths and ownership cleanup are exercised.
- Affected examples and ABI smoke tests compile.
- Lint checks pass with the pinned Nix toolchain.
- The checked-in `dscanner.ini` is used; disabled checks are those that conflict
  with deliberate BetterC RAII idioms or are enforced during API review.
