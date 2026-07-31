# xtbd

`xtbd` is a small foundational D library designed for `-betterC`: explicit
allocators, arenas and thread-local scratch scopes, owning arrays and string
builders, read-only `String` views, intrusive lists, panic/logging facilities,
allocation-free formatted output, structured logging, panic contracts, and
explicit caller-storage-backed stack traces.

The `xtb.math` package adds allocation-free scalar, vector, matrix, transform,
camera, and projection operations, plus a stable deterministic random generator
and allocator-owned periodic value noise.

The `xtb.os` package provides borrowed validated paths, RAII files and memory
maps, binary-safe complete I/O, metadata, streaming directory traversal,
explicit errors, environment/path queries, and monotonic/wall clocks. Linux
has the locally tested backend; other targets retain buildable APIs reporting
unsupported operations.

Stack traces include bounded D demangling, allocation-free signature coloring,
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
`tests/core_tests.d`, `tests/math_tests.d`, and `tests/os_tests.d` are the
explicit BetterC test runners.

## Build and test

```sh
direnv allow
just check
```

Alternatively, run `nix develop` from `xtbd` and then use the same `just`
commands. The project-local `.envrc` deliberately selects the independent
`xtbd` flake instead of inheriting the adjacent C++ project's environment.

`just check` lints, builds the static library, runs every unit test, and builds
and runs the examples. Individual commands are `just build`, `just test`,
`just lint`, and `just examples`. A reproducible package and test derivation are
also available through `nix build` and `nix flake check`.

## Using the library

Import the stable core surface with `import xtb.core;`, or import a focused
module such as `xtb.core.arena`. All consuming targets must also compile with
`-betterC`. See `examples/core_demo.d` and `examples/print_demo.d` for complete
runnable programs, and `docs/architecture.md` for ownership and scratch-space
contracts.

Import `xtb.math` for the stable math surface. Matrices are column-major and
multiply column vectors; transformations compose right-to-left. See
`examples/math_demo.d` for transforms and deterministic periodic noise.

Import `xtb.os` for platform services. Threads making path-based OS calls must
install `ThreadContextScope`, which supplies temporary C-string storage.
Directory traversal streams entries rather than allocating a linked list. See
`examples/os_demo.d`.

The remaining C++ core capability audit and proposed implementation milestone
are maintained in `docs/core-gap-analysis.md`.
