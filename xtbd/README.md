# xtbd

`xtbd` is a small foundational D library designed for `-betterC`: explicit
allocators, arenas and thread-local scratch scopes, owning arrays and string
builders, read-only `String` views, intrusive lists, panic/logging facilities,
allocation-free formatted output, structured logging, panic contracts, and
explicit caller-storage-backed stack traces.

Stack traces include bounded D demangling, allocation-free signature coloring,
configurable ANSI themes, and explicitly installed panic/fatal-signal handlers.
See `examples/stacktrace_demo.d` and the diagnostics section of
`docs/architecture.md` for the safety tradeoff between strict and best-effort
signal unwinding.

Signatures default to an overload-oriented view: outer return types and
function attributes are hidden, while member qualifiers and complete nested
function/delegate parameter types remain visible. Set
`StackTraceStyle.signatureDetail` to `SignatureDetail.full` for every encoded
return type and attribute.

The project is independent from the adjacent C++ sources. Public modules live
under `source/xtb/core`, focused unit tests are colocated with those modules,
and `tests/core_tests.d` is the explicit BetterC test runner.

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

The remaining C++ core capability audit and proposed implementation milestone
are maintained in `docs/core-gap-analysis.md`.
