# Testing

## Strategy

Use D's built-in `unittest` blocks for focused tests and keep them in the
module they exercise. This gives private-symbol access, keeps behavior close to
its implementation, and lets tests move with a module. Use `tests/` only when a
test spans public modules, needs fixtures, checks an ABI, or reproduces a bug
more clearly as an external consumer.

All tests run with `-betterC`. A test suite that runs only with the full D
runtime can hide forbidden dependencies and is not an acceptable substitute.
BetterC does not emit `ModuleInfo`, so test discovery must be compile-time.
DUB's generated BetterC runner statically imports the modules owned by a
component and invokes their tests through `__traits(getUnitTests, module_)`.

The pinned D-Scanner 0.15 parser does not understand interpolated expression
sequence literals yet. `just lint` therefore uses DUB/LDC semantic builds for
the complete library and every example, then sends every supported file
through D-Scanner. Keep the D-Scanner exception list narrow and remove it when
D-Scanner can parse `i"..."`.


## Build-mode coverage

Run contract-sensitive tests with `XTB_Checked` enabled. The Just test recipes
define it for debug, optimized, release-safe, and AddressSanitizer runs.
`just build static all release-fast` compiles the unchecked production
libraries, and `just test release-fast` compiles every test runner without
executing assertions that `-release` removes. Together they ensure guarded
`require` imports and calls disappear cleanly. See `docs/build-modes.md`.

## Colocated unit tests

Put tests immediately after the declaration or small group of declarations
they cover. Keep production imports at module scope and test-only imports local
to the `unittest` block where possible.

```d
module xtb.math.scalar;

@safe nothrow @nogc:

version (XTB_Checked)
    import xtb.core.panic : require;

int clamp(int value, int low, int high)
{
    version (XTB_Checked)
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

## BetterC test runners

Run colocated module tests once per component with `dub test :component`. Each
component's positively listed `sourceFiles` are the authoritative module
inventory; DUB generates a BetterC-compatible compile-time runner from that
inventory. Adding a production module to a component therefore also adds its
colocated tests without a second handwritten list. Component unit-test build
types preserve the debug, optimized, release-safe, release-fast, and
AddressSanitizer policies used by `just test`.

Release-fast remains a compile-only check for unittest bodies. The test recipe
passes `tests/support/compile_unittests.d` as DUB's custom main, which compiles
the component with unittests and release checks stripped but deliberately does
not execute those bodies.

Executables in `tests/` cover integration, regression, death-test, exhaustive,
and alternate-backend behavior. They depend on the ordinary component static
libraries and must not invoke colocated module tests again. The unsupported
threading-backend runner is the deliberate exception: it compiles threading
sources with a mutually exclusive test version and explicitly invokes those
backend-versioned module tests.

The UTF-8 runner expands the exhaustive 1.1-million-scalar test body exported
by `xtb.core.utf8`. The OS runner creates a process-unique directory below
`/tmp`, touches only paths inside it, and removes every created file and
directory before returning. Platform runtime assertions are backend-versioned;
the same runner remains a compile check where no native backend exists.

Process integration tests compile `tests/support/process_helper.d` as a
dedicated BetterC executable. Use its length-unambiguous argv/environment
output and binary stream modes instead of depending on shell parsing or the
host behavior of `echo`, `cat`, and `sleep`.
Every build mode places the helper beside its OS test executable. The test
resolves that sibling from its own executable path, not from the repository
working directory, so debug, optimized, release, and sanitizer suites can run
in parallel without replacing one another's helper.
Its flood mode deliberately exceeds stdin, stdout, and stderr pipe capacities
at the same time, proving that communication makes progress in every direction.
Pipeline tests cover both borrowed `Command[]` and `PipelineStage[]`, failure
rollback, allocator failure, per-stage status/success policy, explicit lifecycle resolution, and reaping.

The generated DUB main is an implementation detail, not a permanent test API.
A future custom BetterC runner may replace it with a compile-time registry that
stores package, module, and stable test-name literals beside homogeneous test
function pointers. That runner must support listing and command-line filtering
without runtime reflection or allocation. Keep test ownership independent of
DUB's main so adopting that runner does not require moving tests or restoring
manual module lists. Running subsequent tests after an assertion aborts will
require subprocess isolation or a separate nonfatal assertion protocol.

## Test layers

1. **Compile-time checks** use `static assert`, `__traits(compiles, ...)`, and
   type/size/alignment checks next to the relevant API. They are ideal for ABI,
   template, and attribute guarantees.
2. **Unit tests** are colocated `unittest` blocks for pure algorithms, parsers,
   containers, ownership transitions, and validation.
3. **Integration tests** in `tests/` call public APIs across module boundaries.
   They may create files only inside a runner-provided temporary directory.
4. **Examples** compile in CI as consumer checks. They are documentation, not a
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
- managed-container member calls work from values and non-null struct pointers,
  including const queries, allocation failure, release, and cleanup; checked
  builds reject a null receiver through the managed invariant;
- the component aggregate import re-exports every public container module;
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

- `String` exposes only a const pointer/slice and its algorithms do not alter
  the source bytes;
- copying and slicing a `String` allocate nothing and preserve the correct
  borrowed range;
- operations that create immutable bytes return `OwnedString` for `Allocator*`
  contexts or a borrowed arena-backed `String` for explicit `Arena*` contexts;
  mutable construction returns/writes `StringBuf`, and a `String` view itself
  never owns storage;
- `StringBuf` growth preserves content, honors alignment, checks overflow, and
  leaves valid state after injected allocation failure;
- `view()` reflects current bytes and tests never use it after a mutation that
  invalidates the view;
- copying into another `StringBuf` creates independent ownership and allocator
  lifetime;
- zero-length strings, embedded NUL, malformed external UTF-8, and valid
  multibyte UTF-8 are covered according to each API's byte/Unicode contract;
- strict decoding covers every leading-byte class, truncation and continuation
  position, overlong form, surrogate encoding, and out-of-range scalar with an
  exact error kind and byte offset;
- every legal Unicode scalar round-trips through the shared encoder/decoder;
- forward, reverse, offset-producing, copied, and early-break code-point ranges
  work both manually and with language-level `foreach`;
- byte slicing, insertion, and truncation accept scalar boundaries and reject
  split sequences in checked builds;
- `StringBuf` equality with literals, mutable and immutable `String` slices,
  and other buffers is tested in both operand orders, including inequality and
  null-string/empty-buffer equivalence;
- C conversion adds exactly one terminator outside logical length, rejects
  embedded NUL when required, and respects scratch lifetime;
- compile-time checks reject copying an owning `StringBuf` and reject mutation
  through `String`;
- mutating managed-container operations are real members
  (`buffer.append(value)`) so definition navigation does not depend on UFCS
  overload reconstruction.

Printer sinks consume `const(u8)[]` stream fragments because flushes and short
writes may split a scalar; a sink callback must not treat each fragment as an
independently valid `String`. Printer tests cover interpolated expression sequences through direct output,
`StringBuf`, fixed-buffer, and allocator-owned sinks. Include empty and nested
sequences, expressions with side effects, custom `formatRepresentation` and
`formatTo` values, numeric format wrappers, mixed ordinary/interpolated
arguments, exact fixed-buffer accounting, truncation, and injected allocation
failure. Assert that every expression and raw custom formatter runs exactly
once and that expression-source metadata is never emitted or evaluated by the
printer. Pretty-print tests additionally cover semantic `prettyDescribe`
delegation for scalar wrappers, constructors, managed/unmanaged sequences,
maps, sets, string-specialized hash containers, and flags; rendering and width
measurement must agree on those descriptions. Fixed-buffer tests also
prove that truncation backs up to a complete scalar while `required` retains
the exact untruncated byte count.

Logging tests cover explicit and thread-context calls, filtering before
formatting, truncation, sink and flush failure, recursion rejection, nested
thread-logger restoration, and the no-context/no-installed-logger behavior.
ANSI tests cover named, indexed, and RGB encoding, combined foreground,
background, and `FlagSet`-backed attributes, reset behavior, plain file output,
custom logger palettes, and coloring of the complete log record. OS tests
exercise forced and disabled ANSI policy, conservative redirected-file
detection, `TERM=dumb`/`NO_COLOR` policy logic, and environment-name
validation. Core ANSI tests never depend on a terminal or process environment.
Every level-specific plain and compile-time-pattern wrapper is exercised for
both explicit and current-thread dispatch, including the `debug_` keyword
workaround and overload resolution through the `xtb.core` aggregate import.
Death tests cover null or invalid installation, installation without a thread
context, destruction before the installed logger scope, and non-LIFO nested
scope destruction. Logger tests use caller-owned buffers and callback/context
pairs; they must not rely on process-global output capture.

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
- checked death tests diagnose double pop/destruction, non-LIFO
  pop/destruction, a second thread context, and cross-thread use.

Serde tests additionally verify:

- every supported scalar, enum, nested struct, pointer, fixed array, and
  dynamic-slice shape round-trips through each applicable backend;
- `Option!T` covers trivial, borrowed, and move-only owning values; JSON null
  and missing fields remain absent, TOML omits absent values, nested optional
  tables decode correctly, and `@serdeRequired` checks key presence independently
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
- explicitly deinitializing or resetting a successful `Deserialized!T` releases
  the root, copied strings, slices, and nullable pointer values exactly once;
- owning decodes populate `StringBuf`, shallow `Array!T` for trivial elements,
  `OwnedArray!T` for cleanup-bearing elements, nested owning structs, and fixed
  arrays without an ownership wrapper; failure/replacement paths explicitly
  deinitialize every nested allocation;
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
`justfile` expose these stable commands:

```sh
nix develop
just targets                              # list modes and target names
just build                                # monolithic static xtb, debug
just build static core release-safe
just build static all release-fast
just build example core release-safe
just run example core release-safe
just test                                 # debug test suite
just test release-safe
just test release-fast                    # compile only; checks are stripped
just test-sanitize                        # AddressSanitizer suite
just lint                                 # compiler and D-Scanner policy checks
just format                               # format all D source files
just format-check                         # verify formatting only
just check                                # complete local matrix
```

The short `justfile` is the public command interface, while DUB owns static
libraries, examples, test executables, build modes, output names, and source
selection. Just discovers component subpackages under `source/xtb` and the
configurations in `examples/dub.sdl` and `tests/dub.sdl` by naming convention.
The important default outputs are:

```text
build/{debug,release-safe,release-fast}/  static libraries
build/test/{debug,optimized,...}/         test runners and helpers
build/examples/                           example executables
```

Static libraries may be redirected through `XTB_LIBRARY_OUTPUT_DIR`; the mode
name is always appended. `just build` means `just build static xtb debug`.
Use `all` to build the monolithic archive and every component archive:

```sh
just build
just build static core release-safe
just build static all release-fast
XTB_LIBRARY_OUTPUT_DIR=path/to/lib just build static serde debug
```

Examples accept short names, source names, or configuration names. `all`
builds or runs every example:

```sh
just build example logging
just run example logging release-safe
just run example core-demo
just run example all debug
just run example cli -- --help
just run-example cli release-safe -- build -r
```

For a single example, arguments after `--` are forwarded verbatim to the
executable. The optional build mode remains before `--` and defaults to `debug`.
Program arguments are intentionally rejected with `all`, since there is no
single executable to receive them.

The older `build-example`, `run-example`, `build-examples`, and `run-examples`
recipes remain as convenience aliases.

Unit-test runners still compile their production modules from source because
D's `unittest` blocks only exist when those modules are compiled with
`-unittest`. Each runner is a `test-*` DUB configuration; supporting programs
use `test-helper-*`. The custom DUB test build types preserve the debug,
optimized, release-safe, and AddressSanitizer modes without relying on normal
Druntime test discovery.

D-Scanner 0.15.2's static-analysis visitor does not terminate on the
allocation-free signature styling module, although its lexer and parser accept
the module immediately. Until that upstream defect is fixed, `dscanner.ini`
records the narrow set of files that D-Scanner cannot process. LDC still checks
every ignored file with the same BetterC warnings and deprecation policy
through the generic DUB library and example builds.

Keep formatting consistent with the surrounding modules and use DScanner for
syntax and style enforcement. Do not mix a repository-wide formatting rewrite
into a functional change. Treat compiler warnings and
deprecations as errors in CI. Use sanitizers supported by LDC for native debug
test builds. AddressSanitizer is mandatory on the pinned toolchain. Retain a
normal debug run because sanitizers change execution.

Coverage is a trend and gap-finding tool, not a substitute for boundary cases.
If BetterC coverage support is unavailable on a target, collect it in a
separate compatible job without weakening the canonical BetterC build/test
gate.

## Definition of done for tests

- The regression test fails before a bug fix when practical.
- Focused and complete BetterC test runners pass.
- New production modules are included in a runner.
- Failure paths and ownership cleanup are exercised.
- Affected examples compile.
- Lint checks pass with the pinned Nix toolchain.
- The checked-in `dscanner.ini` is used; disabled checks are those that conflict
  with deliberate BetterC RAII idioms or are enforced during API review.
