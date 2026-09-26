# Zero-cost abstraction checks

These checks verify properties of optimized compiler output. They are separate
from correctness tests, which exercise program behavior, and benchmarks, which
measure runtime performance.

Run the suite with:

```sh
just check-zero-cost
```

The contract probe uses observable side effects to verify that `require` and
`ensure` operands are not evaluated in `release-fast`. Its verifier then
inspects the final linked executable to confirm that unique diagnostic strings
and contract function symbols were removed.

The vector probe compares constant and runtime indexed reads and writes for
`Vector2`, `Vector3`, and `Vector4` against raw static-array access in an importing
module. Its x86-64 instruction comparison requires `objdump` and checks the final
executable; bounds checks are disabled for this release-fast comparison.

Keep each probe deterministic and focused on an artifact property. Do not use
timing thresholds here; performance measurements belong in benchmarks.
