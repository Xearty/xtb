# Formatting and writers

XTB formatting is built around `Writer`, a synchronous non-owning output
interface. Ordinary values, formatting helpers, strings, fixed buffers, loggers,
and custom sinks all use the same formatting path.

For stdout/stderr, use `write`/`writeln` for sequential values and
`format`/`formatln` for compile-time `{}` formatting or D interpolation:

```d
writeln("count=", 3);
formatln!"id={}, hex={}"(7, hexadecimal(255));
formatln(i"name=$(name), count=$(count)");
```

Custom types participate by implementing `formatTo`:

```d
struct Point
{
    int x;
    int y;

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writer.format!"({}, {})"(x, y);
    }
}
```

`formatted!"..."(...)` creates a lazy allocation-free printable value, which is
useful when formatted text must be nested inside another write.

## Choosing a destination

| Destination | API |
|---|---|
| stdout/stderr | `write`, `writeln`, `format`, `formatln` |
| existing `Writer` | `writer.write`, `writer.format` |
| owned string | `formatString` / `tryFormatString` |
| caller buffer | `writeBuffer` / `formatBuffer` |
| buffered sink | `BufferedWriter` |

`formatString` returns an owning `StringBuf` and therefore requires `deinit`.
Fixed-buffer formatting does not allocate; its result reports `written`,
`required`, and whether output was truncated.

`Writer` itself owns no resources and has no flush obligation. `BufferedWriter`
is different: it borrows the destination and caller-provided staging storage,
and pending bytes must be delivered explicitly with `flush()`.

See [`print_demo.d`](../../../examples/print_demo.d) for the formatting paths in
one place.
