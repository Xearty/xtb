# Contracts

Import `require` and `ensure` from `xtb.panic`, or through the public `xtb`
module.

- `require` checks an obligation imposed on the caller, such as a valid index,
  non-null pointer, or permitted state transition.
- `ensure` checks an obligation imposed on the implementation, such as a
  postcondition or representation invariant.

Both functions invoke the installed XTB panic handler when their condition is
false in a checked build. In `release-fast`, neither argument is evaluated and
the contract code and message are removed from the executable. An explicit
`version (XTB_Checked)` guard is not required, although existing guarded call
sites may be migrated separately.

```d
require(index < this.length, "index is outside the array");

T value = this.items[index];
ensure(this.length <= this.capacity, "array length exceeds capacity");
```

Contract operands may inspect only already-computed state. Never put required
computation, mutation, output initialization, or another necessary side effect
inside one.

Do not use D's runtime `assert` in library code because BetterC does not
reliably route it through XTB's panic handler. Runtime assertions remain useful
in tests, and `static assert` remains available for compile-time constraints.
Use `Result`, `Option`, or another explicit status for expected failure. If a
condition must remain enforced in every build, use an explicit branch with
`panic` or return a failure value.
