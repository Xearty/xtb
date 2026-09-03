# Project guidelines

## Project overview

This is a D library targeting BetterC. All production code must compile
with `-betterC`.

Important directories:

- `source/<subpackage>/README.md`: subpackage overview and documentation entry point
- `source/<subpackage>/xtb/`: library implementation and its colocated unit tests
- `source/<subpackage>/docs/`: detailed documentation owned by that subpackage
- `tests/`: cross-module, integration, and regression test runners/fixtures
- `examples/`: minimal usage examples
- `archive/cpp/`: historical C++ implementation, retained for reference only

Do not modify, import, generate from, or build `archive/cpp` as part of the D
project. The root BetterC project must remain independent from the archive.

Keep user documentation short and with its owner. Every source subpackage has a
concise `source/<subpackage>/README.md` that explains what it provides and links
to relevant examples or guides. Put subpackage-specific user guides in
`source/<subpackage>/docs/` and cross-subpackage user documentation in `docs/`.
Do not use user documentation for design plans, implementation logs, or project
history.

Before modifying handwritten D code, read `docs/style-guide.md` in full and
follow it. It is the single source of truth for naming, formatting, declaration
layout, and API-expression conventions. When nearby legacy code conflicts with
the guide, follow the guide without reformatting or renaming unrelated code.

Before changing public APIs, inspect their existing call sites.

## Implementation constraints

- Do not introduce dependencies on the garbage collector.
- Do not use exceptions, `TypeInfo`, classes, or runtime reflection.
- Put `@safe`, `pure`, `nothrow`, and `@nogc` on public APIs when their actual
  contracts permit it. Keep unavoidable `@system` code in small boundary
  modules and document its invariants.
- Model fallible operations with explicit result/status values. Do not encode
  expected failures as assertions.
- Document caller obligations as requirements or preconditions. Say that an
  API panics only for an explicit panic path that remains in every supported
  build; do not describe `XTB_Checked` contract enforcement as an unconditional
  panic guarantee or repeat the build-mode mechanics on every API.
- Give every owning struct explicit construction and deinitialization behavior,
  make zero state valid when practical, document whether copying is allowed,
  and balance every explicit lifetime. Do not duplicate cleanup already owned
  by a genuine RAII guard.
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
- Handwrite managed-container APIs in the same module as their unmanaged
  storage; do not generate forwarding declarations with mixins or reflection.
  Managed structs contain ownership fields, static factories, ordinary member
  operations, a mutable-only `Allocator* allocator()` member, and D-required
  hooks. D automatically permits member calls through a non-null struct
  pointer; checked builds use a struct invariant to reject a null receiver.
  Use `require` for caller obligations and `ensure` for implementation
  guarantees. Their operands are not evaluated in release-fast, even without
  an explicit `version (XTB_Checked)` guard; existing guarded call sites may be
  migrated separately. Contract operands must only inspect already-computed
  state: never put necessary computation, mutation, or output initialization
  inside a removable contract. Do not use D's runtime `assert` outside unit
  tests or test programs; `static assert` remains valid. See
  `docs/build-modes.md`.
- Re-export stable public modules from the corresponding public `package.d` so
  consumers can use short imports. Keep implementation imports focused and do
  not put implementation code in `package.d`.
- For non-field declarations, use the narrowest D protection boundary that
  fits an internal API. Prefer `private` for same-module implementation details
  and `package(xtb.<domain>)` for helpers shared only within one namespace.
  Reserve `package(xtb)` for intentional XTB-internal bridges that must cross
  sibling namespaces; do not use it as a default friend mechanism.
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

## Repository structure

- Treat each `source/<subpackage>` directory as an independently declared DUB subpackage.
- Keep user-facing documentation short and colocated with the subpackage it describes.
- Do not add design plans, implementation logs, or roadmaps to the user documentation.
