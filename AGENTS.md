# Project guidelines

## Project overview

This is a D library targeting BetterC. All production code must compile
with `-betterC`.

Important directories:

- `source/xtb/`: library implementation and its colocated unit tests
- `tests/`: cross-module, integration, and regression test runners/fixtures
- `examples/`: minimal usage examples
- `archive/cpp/`: historical C++ implementation, retained for reference only

Do not modify, import, generate from, or build `archive/cpp` as part of the D
project. The root BetterC project must remain independent from the archive.

Before changing public APIs, inspect their existing call sites.

## Implementation constraints

- Do not introduce dependencies on the garbage collector.
- Do not use exceptions, `TypeInfo`, classes, or runtime reflection.
- Prefer slices for borrowed contiguous data. Function parameters that mutate
  caller-owned values use explicit pointers, except that the first parameter
  of a mutating UFCS operation may use `ref` so callers can write
  `value.operation()`. Document and validate pointer nullability.
- Use `scope const` for borrowed input that must not escape or mutate. Use
  `return scope` deliberately; do not use `in` as a blanket substitute. Do not
  use `ref` for other mutable parameters; reserve it for the mutating UFCS
  receiver exception, language-required hooks, or tightly scoped internals.
- Put `@safe`, `pure`, `nothrow`, and `@nogc` on public APIs when their actual
  contracts permit it. Keep unavoidable `@system` code in small boundary
  modules and document its invariants.
- Model fallible operations with explicit result/status values. Do not encode
  expected failures as assertions.
- Give every owning struct explicit `create`/`deinit` behavior, make zero state
  valid when practical, and document whether copying is allowed.
- Do not declare a member named `init`; preserve D's built-in `Type.init`
  property. Use `create`, `withCapacity`, `fromX`, or `acquire` according to
  whether the operation constructs, preallocates, converts, or acquires a
  scoped resource.
- Use `snake_case` for modules and filenames, `PascalCase` for types, and
  `camelCase` for functions and variables. Follow D's standard naming for
  compile-time values and enum members unless a foreign ABI dictates names.
- Avoid module constructors, mutable process-wide state, and hidden persistent
  allocator selection. Scratch and the optional current logger use the TLS
  thread context that the thread explicitly installs through
  `ThreadContextScope`; logger installation is additionally scoped.
- Use scratch space for temporary allocation and pass every allocator that may
  back live input/output in the conflict list. Never let scratch-backed memory
  escape its scope or store a scratch allocator in longer-lived state.
- Prefer the non-copyable RAII `ScratchScope`; its destructor owns rewind and
  needs no `scope(exit)`. Lower-level code may manually `push`/`pop` a
  `TempArena` when RAII is unsuitable, but must balance it on every path.
  Failure to obtain a non-conflicting arena is a panic, not a recoverable API
  result.
- Keep strings split by role: `String` (`const(char)[]`) is a read-only
  non-owning view and `StringBuf` is the non-copyable owning mutable
  buffer/builder. Never expose mutable bytes through `String`;
  transformations that create bytes use an explicit allocator or write
  to/return `StringBuf`, and every returned view documents its lifetime.
- Use `String` everywhere string bytes are not intentionally mutated. Do not
  substitute raw `const(char)[]`, D `string`, or C pointers in ordinary APIs.
- Design free functions for UFCS and use short verbs (`append`, `reserve`,
  `clear`), not type-prefixed names. Use `ref` only for the first parameter of
  mutating UFCS functions such as those operating on `StringBuf` and `Array`.
- Preserve the existing public API unless the task explicitly requires a change.
- Avoid allocations in formatting and low-level utility code.
- Follow the formatting and naming conventions of nearby code.

## Testing workflow

For every bug fix:

1. Reproduce the failure with a regression test.
2. Confirm the test fails before the fix when practical.
3. Implement the smallest coherent fix.
4. Run the focused test.
5. Run the complete test suite.
6. Add boundary and failure-path tests.

Do not declare the task complete while tests are failing.

## Definition of done

A change is complete only when:

- It compiles with `-betterC`.
- New behavior has tests.
- Existing tests pass.
- Examples affected by the change still compile.
- No unrelated files were reformatted or changed.
- The final response summarizes modifications and commands executed.

## Important documentation

- Read `docs/architecture.md` before changing module boundaries.
- Read `docs/testing.md` before adding a new test executable.
