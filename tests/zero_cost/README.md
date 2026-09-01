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

Keep each probe deterministic and focused on an artifact property. Do not use
timing thresholds here; performance measurements belong in benchmarks.
