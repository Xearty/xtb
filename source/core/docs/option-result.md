# Option and Result

XTB uses explicit values instead of exceptions for absence and recoverable
errors.

## Option

`Option!T` is either `some(T)` or `none`. Its zero state is `none`.

```d
Option!int index = findIndex();
if (index)
    use(index.value);
```

Use `value` when presence is already established, or `pointer` when a nullable
pointer is convenient. `take` transfers the stored value out and leaves the
option empty. `unwrap` and `expect` also transfer the value, but panic when it
is absent.

```d
Option!OwnedString name = loadName();
if (name.isSome)
{
    OwnedString owned = name.take();
    scope(exit) owned.deinit();
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
Result!(long, ParseError) loadValue()
{
    mixin ResultReturns;

    auto parsed = parseValue();
    if (!parsed)
        return err(parsed); // transfers the same error type

    return ok(cast(long) parsed.take());
}
```

Test `isOk` / `isErr`, or use the boolean conversion. `value` and `error` borrow
the active payload. `take` and `takeError` transfer it. `unwrap`, `expect`,
`unwrapError`, and `expectError` panic when the result is in the wrong branch;
they are not error-propagation operators.

Like `Option`, `Result` owns its active payload and cleans it when necessary.
After `take` or `takeError`, responsibility for the transferred value belongs to
the caller.

`map`, `mapError`, `andThen`, and `orElse` are convenient for cleanup-free
payloads. For owning values, prefer an explicit branch and `take` so ownership
transfer stays visible.
