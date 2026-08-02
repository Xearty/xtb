# xtbd

`xtbd` is a small foundational D library designed for `-betterC`: explicit
allocators, arenas and thread-local scratch scopes, owning arrays and string
builders, hash maps and sets, read-only `String` views, intrusive lists,
strongly typed bit flags, finite checked `Duration` values, panic/logging
facilities, allocation-free formatted output, structured logging, and panic
contracts.
Optional stack traces and crash observation live in `xtb.diagnostics`.

The `xtb.math` package adds allocation-free scalar, vector, matrix, transform,
camera, and projection operations, plus a stable deterministic random generator
and allocator-owned periodic value noise.

The `xtb.os` package provides borrowed validated paths, RAII files and memory
maps, binary-safe complete I/O, metadata, streaming directory traversal,
explicit errors, environment/path queries, and monotonic/wall clocks. Linux
has the locally tested backend; other targets retain buildable APIs reporting
unsupported operations.

The `xtb.serde` package provides compile-time, attribute-driven mapping of
BetterC structs to structured formats. It has no runtime registry or DOM;
JSON and TOML backends traverse typed values directly, and decoded object
graphs are held by explicit non-copyable `Deserialized!T` owners. `Option!T`
provides nullable values in both document-owned and self-owning schemas.

Stack traces include caller-storage-bounded D demangling, allocation-free
signature coloring,
configurable ANSI themes, and explicitly installed panic/fatal-signal handlers.
See `examples/stacktrace_demo.d` and the diagnostics section of
`docs/architecture.md` for the safety tradeoff between fault-address-only and
attempted stack unwinding.

Signatures default to an overload-oriented view: outer return types and
function attributes are hidden, while member qualifiers and complete nested
function/delegate parameter types remain visible. Set
`StackTraceStyle.signatureDetail` to `SignatureDetail.full` for every encoded
return type and attribute.

Long signatures use source-style multiline parameter lists beyond 100 columns
by default. Set `StackTraceStyle.signatureColumns` to another limit, or select
`SignatureLayout.singleLine` through `StackTraceStyle.signatureLayout`.

The project is independent from the adjacent C++ sources. Public modules live
under `source/xtb`, focused unit tests are colocated with those modules, and
`tests/core_tests.d`, `tests/math_tests.d`, `tests/os_tests.d`, and
`tests/serde_tests.d` are the explicit BetterC test runners.

## Build and test

```sh
direnv allow
just check
```

Alternatively, run `nix develop` from `xtbd` and then use the same `just`
commands. The project-local `.envrc` deliberately selects the independent
`xtbd` flake instead of inheriting the adjacent C++ project's environment.

`just check` lints, builds the package archives, runs debug, optimized, release,
ABI, sanitizer, cross-build, and fuzz checks, then builds and runs the examples.
Individual commands include `just build`, `just test`, `just test-sanitize`,
`just fuzz-smoke`, `just lint`, and `just examples`. A reproducible package and
test derivation are also available through `nix build` and `nix flake check`.

## Using the library

Import the stable core surface with `import xtb.core;`, or import a focused
module such as `xtb.core.arena`. All consuming targets must also compile with
`-betterC`. See `examples/core_demo.d`, `examples/hash_demo.d`, and
`examples/print_demo.d` for complete runnable programs, and
`docs/architecture.md` for ownership and scratch-space contracts.

`FlagSet!E` treats enum values as bit positions and chooses the smallest
fitting unsigned storage type by default. Specify its storage type explicitly
for ABI or serialized layouts. Invalid cast-created enum values panic instead
of shifting by an unchecked position; raw masks can be decoded strictly or
with undeclared bits deliberately truncated.
Use `enable`, `disable`, and `toggle` to mutate a set, or `enabled`, `disabled`,
and `toggled` to derive a changed value without changing the original.
`foreach (flag; flags)` visits enabled values in enum declaration order.
Use `flags.enabledCount` for the number currently enabled and
`Flags.declaredCount` for the number of atomic enum members.

Use `milliseconds(250)`, `seconds(2)`, and the other explicit unit helpers to
construct `Duration` values. Arithmetic is checked and floating-point counts
are intentionally rejected. `Duration` represents only finite nonnegative
spans; timeout policies add infinity or immediacy as separate tagged states.

Import `xtb.diagnostics` only in targets that need demangling, stack traces, or
crash observation. On Linux those targets link libbacktrace; core-only, math,
and OS targets do not. `just build` produces independent `libxtbd_core`,
`libxtbd_diagnostics`, `libxtbd_math`, `libxtbd_os`, and `libxtbd_serde`
archives.

Import `xtb.math` for the stable math surface. Matrices are column-major and
multiply column vectors; transformations compose right-to-left. See
`examples/math_demo.d` for transforms and deterministic periodic noise.

Import `xtb.os` for platform services. Threads making path-based OS calls must
install `ThreadContextScope`, which supplies temporary C-string storage.
Directory traversal streams entries rather than allocating a linked list. See
`examples/os_demo.d`.

Import `xtb.serde` for attribute-driven JSON and TOML mapping. Use
`Deserialized!T` with `String` and slices for one document-owned graph, or
decode directly into an ordinary RAII struct containing `StringBuf` and
`Array!T` for independently owned, freely mutable data. Use `Option!T` for
nullable fields; JSON maps absence to `null`, while TOML omits absent fields. See
`examples/serde_demo.d`. The dedicated `examples/option_demo.d` covers every
`Option!T` state transition, copy and move behavior, destruction, nesting,
pointer access, and backend-specific serialization rules.

The remaining C++ core capability audit and proposed implementation milestone
are maintained in `docs/core-gap-analysis.md`.
