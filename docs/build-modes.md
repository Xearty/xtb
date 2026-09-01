# Build modes

XTB supports three build modes:

| Mode | Optimization | `XTB_Checked` | Bounds/assertions/contracts |
|---|---:|---:|---|
| `debug` | no | yes | enabled |
| `release-safe` | yes | yes | enabled |
| `release-fast` | yes | no | removed where permitted by D/XTB |

Build the full library with:

```sh
just build
just release-safe
just release-fast
```

Examples accept the mode before `--`:

```sh
just run example cli release-safe -- --help
```

## Checked behavior

`XTB_Checked` enables diagnostics for programmer errors and violated API
preconditions: invalid indices, foreign pointers, invalid ownership/state
transitions, and similar misuse. These checks normally panic when violated.

Use `require` for caller preconditions and `ensure` for implementation
postconditions and invariants. They invoke XTB's panic handler when they fail in
a checked build. In `release-fast`, their operands are lazy and are not
evaluated; the optimizer and linker remove their checking code and diagnostic
strings. Contract operands must therefore only inspect already-computed state
and must never perform work required by the program.

The contract functions own their build-mode behavior, so they may be imported
and called without a `version (XTB_Checked)` guard. Existing guarded call sites
may be migrated independently.

`release-fast` removes checked-only diagnostics, so callers must satisfy the
documented preconditions. It does **not** turn ordinary failures into unchecked
behavior. Fallible APIs still report allocation, parsing, CLI, and operating
system errors, and semantic guarantees such as generational-pool stale-handle
rejection remain enabled.

Use `release-safe` when you want optimization while retaining those diagnostics.
Use `release-fast` only for code whose preconditions have already been validated.

`just check` verifies the project across the public build modes in addition to
formatting, linting, tests, sanitizers, and examples.

## Library output

The full development build produces one `libxtb.a`. For distribution, `just
compose` can build one archive from a selected subpackage closure:

```sh
just compose log math
just compose release-fast threading
```

Build outputs are separated by mode under `build/` by default. Set
`XTB_LIBRARY_OUTPUT_DIR` to change the base output directory.
