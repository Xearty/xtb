# xtb

`xtb` is a small foundational D library designed for `-betterC`: explicit
allocators, arenas and thread-local scratch scopes, owning arrays, mutable
string builders, exact immutable `OwnedString` values, borrowed-key
`StringViewHashMap` maps, owning `StringHashMap` maps, borrowed
`StringViewHashSet` sets, owning `StringHashSet` sets, intrusive lists,
strongly typed bit flags, finite checked `Duration` values, panic/logging
facilities, allocation-free formatted output, structured logging, and panic
contracts.
Optional stack traces and crash observation live in `xtb.diagnostics`.

## Start an application

Create a ready-to-run project from the flake template without cloning xtb:

```sh
nix flake new -t github:Xearty/xtb#app ./my-app
cd my-app
direnv allow
just run
```

The generated flake pins xtb and consumes its installed modules and static
libraries directly from the Nix store. It does not make a writable source copy.
Run `nix flake update xtb` in the application when you want to update the
library revision.

The `xtb.math` package adds allocation-free scalar, vector, matrix, transform,
camera, and projection operations, plus a stable deterministic random generator
and allocator-owned periodic value noise.

The `xtb.os` package provides borrowed validated paths, RAII files and memory
maps, binary-safe complete I/O, metadata, streaming directory traversal,
explicit errors, environment/path queries, monotonic/wall clocks, RAII pipes,
and direct child-process creation. The process API keeps argv values separate,
supports explicit standard-stream routing and environments, and provides
nonblocking, timed, and blocking waits. Fixed-buffer communication pumps all
three standard streams without deadlock, and allocator-owned linear pipelines
borrow command/stage descriptions only during creation. Linux has the locally
tested backend; other targets retain buildable APIs reporting unsupported
operations.

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

The archived C++ implementation remains under `archive/cpp` for historical
reference only. The D project at the repository root is independent from it;
public modules live under `source/xtb`, and focused unit tests are colocated
there. `tests/core_tests.d`, `tests/utf8_tests.d`, `tests/math_tests.d`,
`tests/os_tests.d`, `tests/serde_tests.d`, and `tests/parser_tests.d` are the
explicit BetterC test runners.

## Build and test

```sh
direnv allow
just check
```

Alternatively, run `nix develop` from the repository root and then use the same
`just` commands. The project-local `.envrc` selects the root `xtb` flake.

`just check` verifies formatting, lints, builds all static targets in all
three supported modes, runs debug, optimized, release-safe, and
AddressSanitizer tests, then runs the examples. The primary command interface
is target-oriented:

```sh
just build                              # static xtb debug
just build static core release-safe
just build static xtb release-fast
just build example serde release-safe
just run example serde release-safe
```

Use `just targets` to list static libraries, examples, and modes. The shorter
`just debug`, `just release-safe`, and `just release-fast` aliases build the
monolithic library and every component library in the selected mode. See
`docs/build-modes.md` for exact check semantics. Other commands include
`just test [mode]`, `just test-sanitize`, `just format-check`, `just lint`, and
`just clean`. A reproducible package and test derivation are also available
through `nix build` and `nix flake check`.

DUB owns the build manifests and Just only coordinates workflows. Component
libraries are independent subpackages colocated under `source/xtb`;
`examples/dub.sdl` owns `*-demo` configurations and `tests/dub.sdl` owns
`test-*` and `test-helper-*`. Just discovers all three groups automatically, so
adding one never requires editing the Justfile.

DUB keeps compilation intermediates in its external cache, while final
libraries, examples, and mode-specific test runners are isolated below `build`
by default. No object files are written into the source tree, and the layout is
safe for a read-only Nix-store source and parallel `just` execution.

## Using the library

Import the stable core surface with `import xtb.core;`, or import a focused
module such as `xtb.core.arena`. All consuming targets must also compile with
`-betterC`. Managed containers expose handwritten member APIs colocated with
their unmanaged storage, plus a mutable allocator member; no generated adapter
code or UFCS forwarding layer is involved. See `docs/managed-containers.md`. See
`examples/core_demo.d`, `examples/hash_demo.d`, and `examples/print_demo.d` for
complete runnable programs, and `docs/architecture.md` for ownership and
scratch-space contracts.

Logging may remain explicit through `logger.log(...)`, or an application can
install a caller-owned logger with `ThreadLoggerScope` and use
`log(level, ...)` throughout that thread. Installation requires an active
`ThreadContextScope`, is nestable, and restores the previous logger on scope
exit. Level-specific calls avoid repeating `LogLevel`: use `trace`/`tracef`,
`debug_`/`debugf`, `info`/`infof`, `warning`/`warningf`, `error`/`errorf`, and
`critical`/`criticalf`, either as explicit logger UFCS calls or against the
current thread logger. `examples/logging_demo.d` demonstrates the complete
setup, filtering behavior, custom values, nested installation, runtime levels,
automatic terminal detection, and palette customization.

Terminal styling is allocation-free and shared by logging and stack traces.
Build styles from named, indexed, or RGB `AnsiColor` values and combine text
attributes through `AnsiStyle`. Logger colors are configurable with
`LogPalette`; the core logger remains explicit and defaults to plain output.
Applications importing `xtb.os` can select `LogStyle.ansi` when
`shouldUseAnsi(stderr)` succeeds. Automatic policy uses the destination,
`TERM`, and `NO_COLOR`; there is deliberately no separate terminal logger or
hidden environment lookup in `xtb.core.logger`.

`FlagSet!E` treats enum values as bit positions and chooses the smallest
fitting unsigned storage type by default. Specify its storage type explicitly
for ABI or serialized layouts. In checked builds, invalid cast-created enum values panic instead of shifting
by an unchecked position; release-fast treats validity as a caller precondition.
Raw masks can be decoded strictly or with undeclared bits deliberately
truncated.
Use `enable`, `disable`, and `toggle` to mutate a set, or `enabled`, `disabled`,
and `toggled` to derive a changed value without changing the original.
`foreach (flag; flags)` visits enabled values in enum declaration order.
Use `flags.enabledCount` for the number currently enabled and
`Flags.declaredCount` for the number of atomic enum members.

Use `milliseconds(250)`, `seconds(2)`, and the other explicit unit helpers to
construct `Duration` values. Arithmetic is checked when `XTB_Checked` is
enabled; release-fast assumes valid, non-overflowing operands. Floating-point
counts are intentionally rejected. `Duration` represents only finite nonnegative
spans; timeout policies add infinity or immediacy as separate tagged states.

Validate external bytes with `asString` before treating them as text. Audited
code whose protocol already guarantees UTF-8 may use `asStringUnchecked`, or
copy the same proven text into `StringBuf.fromBytesUnchecked`. Malformed data
violates those unchecked APIs' preconditions; arbitrary binary ownership uses
`Array!u8`.

Import `xtb.diagnostics` only in targets that need demangling, stack traces, or
crash observation. On Linux those targets link libbacktrace; core-only, math,
and OS targets do not.

`just build` defaults to the monolithic checked-debug `libxtb.a`. Select a
component library or mode explicitly when needed:

```sh
just build static xtb debug
just build static core release-safe
just build static diagnostics release-fast
just build static all release-safe
```

`all` builds `libxtb.a` plus the independent component libraries
`libxtb_core.a`, `libxtb_diagnostics.a`, `libxtb_math.a`, `libxtb_os.a`,
`libxtb_parser.a`, and `libxtb_serde.a`. Additional component subpackages under `source/xtb` are
discovered automatically.

Examples use the same mode names and accept short names with or without the
`-demo` suffix:

```sh
just build example logging
just run example logging release-safe
just run example all debug
```

Static libraries are written below `build/debug`, `build/release-safe`, or
`build/release-fast`. Pass another base destination through the environment
when a different layout is needed:

```sh
XTB_LIBRARY_OUTPUT_DIR=path/to/lib just build
XTB_LIBRARY_OUTPUT_DIR=path/to/lib just build static core release-safe
XTB_LIBRARY_OUTPUT_DIR=path/to/lib just build static all release-fast
```

Relative destinations are resolved from the directory where Just was invoked,
not from the library source, and the selected mode name is appended. This
matters when the Justfile and DUB manifest come from a read-only flake input in
`/nix/store`: compiler output still lands directly in the consuming project.

Import `xtb.math` for the stable math surface. Matrices are column-major and
multiply column vectors; transformations compose right-to-left. See
`examples/math_demo.d` for transforms and deterministic periodic noise.

Import `xtb.os` for platform services. Threads making path-based OS calls must
install `ThreadContextScope`, which supplies temporary C-string storage.
Directory traversal streams entries rather than allocating a linked list. See
`examples/os_demo.d`. Direct process creation requires the same thread context
for temporary argv/environment construction; see `examples/process_demo.d`.
That exhaustive example also covers binary communication, bounded capture,
resumable and terminating timeouts, borrowed pipeline slices, per-stage stderr,
status reporting, and success policies.

Import `xtb.parser` for arena-backed parser combinators. Grammars own their
parser graph in an `Arena`; `Parser!T` handles remain small and reusable, while
parse execution allocates only when `.collect()` or a semantic action explicitly
uses `ParseContext.outputArena`. The package includes `attempt()`/`cut()`
backtracking control, structural operator-precedence levels, an RFC 8259 JSON
AST parser, and an algebraic arithmetic parser used to validate precedence and
associativity. See `design_spec/parser.md`.

Import `xtb.serde` for attribute-driven JSON and TOML mapping. Use
`Deserialized!T` with `String`, slices, and `StringViewHashMap!V` (the readable
alias for `HashMap!(String, V)`) for one document-owned graph. Direct owning
decodes may use `StringBuf`, `OwnedString`, `Array!T`, and
`StringHashMap!V`. JSON accepts every supported value at the document root.
TOML roots remain tables represented by a serde struct, tagged union, borrowed
string-view map, or owning string map; nested maps use inline tables. Borrowed
map keys live under `Deserialized!T`, while `StringHashMap` stores exact owned
key allocations and is valid only when its values are recursively owning. Use
`Option!T` for nullable fields; JSON maps absence to
`null`, while TOML omits absent struct fields. See `examples/serde_demo.d`. The
dedicated `examples/option_demo.d` covers every `Option!T` state transition,
copy and move behavior, destruction, nesting, pointer access, and
backend-specific serialization rules.

The remaining C++ core capability audit and proposed implementation milestone
are maintained in `docs/core-gap-analysis.md`.
