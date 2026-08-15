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
  caller-owned values use explicit pointers. Owning structs expose their
  ordinary receiver-owned operations as member methods, so mutation remains
  discoverable without synthetic UFCS adapters. Document and validate pointer
  nullability at actual pointer boundaries.
- Use `scope const` for borrowed input that must not escape or mutate. Use
  `return scope` deliberately; do not use `in` as a blanket substitute. Do not
  use `ref` for ordinary mutable parameters; reserve it for language-required
  hooks, tightly scoped internals, or genuine free algorithms whose receiver is
  not an owning type.
- Put `@safe`, `pure`, `nothrow`, and `@nogc` on public APIs when their actual
  contracts permit it. Keep unavoidable `@system` code in small boundary
  modules and document its invariants.
- Model fallible operations with explicit result/status values. Do not encode
  expected failures as assertions.
- Give every owning struct explicit `create`/`deinit` behavior, make zero state
  valid when practical, and document whether copying is allowed. When an
  explicit-lifetime local is intentionally kept until the end of the current
  lexical scope, put its `scope (exit)` cleanup immediately after the
  declaration/acquisition it protects. Keep a one-statement cleanup on the same
  line, for example `scope (exit) value.deinit();`. Do not add such a guard when
  ownership is moved/released or otherwise ended earlier, and do not duplicate
  cleanup already owned by a genuine RAII guard.
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
- Use short operation names (`append`, `reserve`, `clear`) rather than
  type-prefixed names. Put receiver-owned operations on owning structs as real
  members for compiler/LSP discoverability. Keep free functions for algorithms
  over borrowed/native representations (such as `String`) and for operations
  that genuinely combine unrelated types.
- Handwrite managed-container APIs in the same module as their unmanaged
  storage; do not generate forwarding declarations with mixins or reflection.
  Managed structs contain ownership fields, static factories, ordinary member
  operations, a mutable-only `Allocator* allocator()` member, and D-required
  hooks. D automatically permits member calls through a non-null struct
  pointer; checked builds use a struct invariant to reject a null receiver.
  Guard every
  `require` import and call with `version (XTB_Checked)` so release-fast does
  not evaluate contract expressions. When several `require` calls are
  adjacent, put them in one scoped `version (XTB_Checked) { ... }` block.
  Conditions passed to `require` must only inspect already-computed state:
  never put necessary computation, mutation,
  or output initialization inside a removable contract. See
  `docs/managed-containers.md` and `docs/build-modes.md`.
- Re-export stable public modules from the component `package.d` so consumers
  can use short imports. Keep implementation imports focused and do not put
  implementation code in `package.d`.
- Preserve the existing public API unless the task explicitly requires a change.
- Keep allocator vocabulary explicit: `allocate!T()` is raw storage for one
  object, `allocateArray!T(n)` returns raw array storage as a slice,
  `allocateInit*` establishes `T.init`, and `create!T(args)` allocates and
  constructs. General allocators pair raw `deallocate`/`deallocateArray` with
  lifetime-aware `dispose`/`disposeArray`. Arena mirrors allocation and
  construction helpers but never pretends to individually free or destroy
  arena allocations; `clear`/`deinit` do not run element destructors. Stateful
  allocator adapters expose their `Allocator*` consistently as `.allocator`.
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
