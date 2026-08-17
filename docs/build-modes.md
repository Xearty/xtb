# Build modes

XTB has three supported compilation modes. Use the target-oriented Just
commands rather than assembling compiler flags manually:

```sh
just build                              # static xtb debug
just build static core release-safe
just build static xtb release-fast
just build example serde release-safe
just run example serde release-safe
```

The `build` recipe defaults to `static xtb debug`. `xtb` is one monolithic
static library; component names build independent libraries. `all` builds both
the monolithic library and every discovered component library. The legacy
`just debug`, `just release-safe`, and `just release-fast` aliases remain and
build `static all` in the selected mode.

## Debug

`just debug` uses DUB's `debug` build, defines `XTB_Checked`, and forces array
bounds checks on. It keeps native D assertions and contracts enabled and emits
debug information. Final libraries are written below `build/debug` by default.

Use this mode for ordinary development and debugging.

## Release-safe

`just release-safe` uses XTB's optimized `release-safe` DUB build type, defines
`XTB_Checked`, and forces array bounds checks on. It enables optimization and
inlining but deliberately does not pass `-release`, so native D assertions and
contracts remain enabled. Final libraries are written below
`build/release-safe`.

Use this mode when testing optimized code while retaining programmer-contract
and language-runtime diagnostics.

`ListHook` and `ForwardListHook` carry their per-hook `linked_` diagnostic state
under `XTB_Checked`, just like the contracts that consume it. Release-safe
therefore detects same-hook double insertion while release-fast compiles both
the state and its `linked` diagnostic accessor out completely. See
`docs/intrusive-collections.md`.

## Release-fast

`just release-fast` uses DUB's `release-nobounds` build, does not define
`XTB_Checked`, and forces bounds checks off. DUB passes `-release`, so native D
assertions and contracts are removed as well. Final libraries are written
below `build/release-fast`.

Every XTB `require` call is guarded at its call site. Use a scoped version
block when a location has multiple contract checks:

```d
version (XTB_Checked)
{
    require(index < length, "index out of bounds");
    require(storage !is null, "storage pointer is null");
}
```

A single check may remain in compact form:

```d
version (XTB_Checked)
    require(index < length, "index out of bounds");
```

The guard is outside the function call. Consequently neither the condition nor
the diagnostic message is evaluated in release-fast. `require` itself is also
only declared and imported under `XTB_Checked`, making an unguarded use a
release-fast compilation error.

Release-fast therefore treats documented programming contracts as caller
preconditions. Violating one may cause invalid results, memory corruption, or
another form of undefined behavior. Do not use release-fast with untrusted
callers or while diagnosing correctness problems.

## Documentation convention

API documentation states checked-only contracts as requirements or
preconditions without repeating the build-mode behavior at every call. Unless
explicitly qualified, “panics” means the implementation has an explicit fatal
path that remains in every supported build. A `require` diagnostic is not such
a release-fast guarantee; it enforces a precondition only when `XTB_Checked`
is present.

## What remains in release-fast

The mode removes runtime programmer checks; it does not remove necessary
program behavior:

- `static assert` and other compile-time validation still run;
- fallible APIs still validate external data and return their documented
  status or error values;
- explicit `panic` and `unreachableCode` calls still terminate;
- allocation failures in non-fallible APIs still follow their documented panic
  paths;
- hardware faults and operating-system errors remain possible.

`XTB_Checked` is a public build contract. Code extending XTB should put every
`require` import and call behind the same version identifier. Do not put the
version test inside `require`; doing so would still evaluate function
arguments in release-fast.

A `require` condition must only inspect already-computed state. Do not perform
necessary work, mutate state, or initialize an output inside the condition:

```d
// Wrong: release-fast removes the call to tryCompute entirely.
version (XTB_Checked)
    require(tryCompute(input, &output), "computation failed");

// Correct: computation is part of the operation; only validation is optional.
const computed = tryCompute(input, &output);
version (XTB_Checked)
    require(computed, "computation failed");
```

This rule also makes checked builds easier to reason about: adding or removing
contract enforcement must not change successful program behavior.

## Custom output directory

`XTB_LIBRARY_OUTPUT_DIR` changes the base directory. The mode name is appended
to keep incompatible artifacts separate:

```sh
XTB_LIBRARY_OUTPUT_DIR=path/to/lib just build static all release-safe
# Writes to path/to/lib/release-safe
```
