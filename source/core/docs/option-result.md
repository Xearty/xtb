# Option and Result

XTB uses explicit values instead of exceptions for absence and recoverable
errors.

## Option

`Option!T` is either `some(T)` or `none`. Its zero state is `none`.

```d
Option!i32 index = find_index();
if (index) use(index.value);
```

Use `value` when presence is already established, or `pointer` when a nullable
pointer is convenient. `take` transfers the stored value out and leaves the
option empty. `unwrap` and `expect` also transfer the value, but panic when it
is absent.

```d
Option!OwnedString name = load_name();
if (name.is_some)
{
    OwnedString owned = name.take();
    scope (exit) owned.deinit();
    use(owned);
}
```

An option owns its active payload. If `T` needs cleanup, replacing, resetting,
or deinitializing the option cleans the active value. `take` transfers that
cleanup obligation to the caller.

## Result

`Result!(T, E)` is exactly either `Ok(T)` or `Err(E)`; it has no empty state.
Construct it with `ok` or `err`. `mixin ResultReturns` introduces short aliases
for the enclosing function's result type.

```d
Result!(i64, ParseError) load_value()
{
    mixin ResultReturns;

    auto parsed = parse_value();
    if (!parsed)
        return err(parsed); // transfers the same error type

    return ok(cast(i64) parsed.take());
}
```

Test `is_ok` / `is_err`, or use the boolean conversion. `value` and `error` borrow
the active payload. `take` and `take_error` transfer it. `unwrap`, `expect`,
`unwrap_error`, and `expect_error` panic when the result is in the wrong branch;
they are not error-propagation operators.

Like `Option`, `Result` owns its active payload and cleans it when necessary.
After `take` or `take_error`, responsibility for the transferred value belongs to
the caller.

`map`, `map_error`, `and_then`, and `or_else` are convenient for cleanup-free
payloads. For owning values, prefer an explicit branch and `take` so ownership
transfer stays visible.
