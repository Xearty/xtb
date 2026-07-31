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

## Colocated unit tests

Put tests immediately after the declaration or small group of declarations
they cover. Keep production imports at module scope and test-only imports local
to the `unittest` block where possible.

```d
module xtb.math.scalar;

pure nothrow @safe @nogc
int clamp(int value, int low, int high)
{
    assert(low <= high);
    return value < low ? low : value > high ? high : value;
}

@safe nothrow @nogc unittest
{
    assert(clamp(-1, 0, 10) == 0);
    assert(clamp(4, 0, 10) == 4);
    assert(clamp(11, 0, 10) == 10);
}
```

Attributes on a unittest are useful compile-time checks. Match the strongest
contract promised by the code under test. Avoid heap-backed literals,
concatenation, exceptions, and test helpers that accidentally require
Druntime. Fixed-size stack arrays, slices, caller-provided buffers, and libc
facilities are appropriate.

## BetterC test runner

Maintain one small runner per coherent package or test shard. It imports the
modules in that shard and lists them explicitly. Explicit enumeration is
intentional: it replaces unavailable `ModuleInfo` discovery and makes omissions
visible in review.

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
- malformed, truncated, and adversarial BMP/JSON input;
- short reads/writes and operating-system error mapping;
- repeated `create`/`deinit`, zero-state cleanup, and allocator failure;
- foreign enum/range validation and callback user-context preservation.

Allocator-aware code should be tested with a small instrumented allocator that
can count allocations, detect leaks/double frees, enforce alignment, and fail
on the Nth allocation. Keep it BetterC-compatible and share it from
`tests/support/` only when several modules need it.

String tests enforce the type boundary as well as textual behavior:

- `String` exposes no mutable pointer/slice and its algorithms do not alter the
  source bytes;
- copying and slicing a `String` allocate nothing and preserve the correct
  borrowed range;
- operations that create bytes either return an explicitly allocator-backed
  `String` or return/write `StringBuf`; the view itself never owns storage;
- `StringBuf` growth preserves content, honors alignment, checks overflow, and
  leaves valid state after injected allocation failure;
- `view()` reflects current bytes and tests never use it after a mutation that
  invalidates the view;
- copying into another `StringBuf` creates independent ownership and allocator
  lifetime;
- zero-length strings, embedded NUL, invalid UTF-8, and multibyte UTF-8 are
  covered according to each API's byte/Unicode contract;
- C conversion adds exactly one terminator outside logical length, rejects
  embedded NUL when required, and respects scratch lifetime;
- compile-time checks reject copying an owning `StringBuf` and reject mutation
  through `String`;
- mutating operations compile with direct UFCS (`buffer.append(value)`) using
  only the allowed first-parameter `ref` receiver.

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
`dscanner`, `just`, and native debugging tools. `dub.sdl` and the
`justfile` should expose these stable commands once source code is introduced:

```sh
nix develop
just lint            # dscanner plus project policy checks
just test            # every BetterC runner
just build           # production static library with -betterC
just test-sanitize   # BetterC runner under AddressSanitizer
just examples        # compile and run public consumer examples
just check           # lint, build, test, and examples
```

D-Scanner 0.15.2's static-analysis visitor does not terminate on the
allocation-free signature styling module, although its lexer and parser accept
the module immediately. Until that upstream defect is fixed, `just lint` runs
D-Scanner's syntax checker on `stacktrace_style.d` and all configured static
analysis checks on every other D file. LDC still compiles the style module with
the same BetterC warnings/deprecations policy in every build and test command.

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
