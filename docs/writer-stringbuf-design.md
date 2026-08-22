# Writer and StringBuf Design

## Status

Implemented design for XTB's formatted text output layer.

## Goals

- Make `StringBuf` extraordinarily convenient for formatted text construction.
- Let code that accepts `ref Writer` render directly into a `StringBuf` without an intermediate allocation or explicit finalization step.
- Keep one formatting implementation for files, fixed buffers, `StringBuf`, logging, pretty printing, diagnostics, CLI help, and serde.
- Preserve BetterC, `@nogc`, exception-free operation, explicit allocation failure, and caller-owned lifetimes.
- Remove redundant destination-specific formatting APIs and unnecessary buffering/finalization machinery.

## Core decision: Writer is an immediate borrowed destination

`Writer` is a small non-owning view consisting of a sink callback, sink context,
accepted-byte count, and sticky failure state. It does not own staging storage.
Every `put` reaches the destination synchronously before the call returns.

This replaces the previous design where every `Writer` carried a 512-byte
internal buffer and therefore required `flush()` / `finish()` to make the final
bytes visible.

Immediate delivery has several advantages:

- `StringBuf.writer()` is safe to use without a cleanup/finalization obligation.
- `LogMessageWriter` remains the only layer responsible for logging-specific
  staging and SGR-safe chunk boundaries; generic formatting is no longer
  double-buffered.
- `StringBuf` already owns growth capacity and libc `FILE*` already has its own
  buffering, so a generic 512-byte buffer duplicated destination behavior.
- Generic renderers can accept only `ref Writer` and do not need templates over
  every possible output type.

`Writer` is non-copyable because copies would share a destination while
silently diverging in failure and byte-count state.

## Module boundaries

The output stack is split into three layers:

```text
xtb.core.writer
    Writer, WriterSink, WriteResult
    generic value formatting
    pattern/interpolation formatting
    numeric format wrappers

       /                    \
      /                      \
xtb.core.string          xtb.core.print
    StringBuf                FILE* adapter
    StringBuf.writer()       stdout/stderr helpers
    StringBuf.write()        fixed-buffer helpers
    StringBuf.format()       owned formatted-string helpers
```

`xtb.core.writer` must not import `xtb.core.string`. This makes it possible for
`StringBuf` to depend on the generic writer without a module cycle.

`xtb.core.print` publicly re-exports `xtb.core.writer`, preserving the natural
place where applications discover printing symbols while keeping the generic
writer implementation independent from `StringBuf` and `FILE*` policy.

## Writer API

The common text-output interface is:

```d
Writer writer = Writer.fromSink(sink, context);

writer.put('[');
writer.put("hello");
writer.put(cast(dchar) 'λ');
writer.repeat(' ', 4);

writer.value(value);
writer.write("name=", name, ", count=", count);
writer.writeln("status=", status);
writer.writeln();

writer.format!"{} + {} = {}"(2, 3, 5);
writer.formatln!"result = {}"(result);
writer.write(i"name=$(name)");

if (!writer.ok) { ... }
WriteResult result = writer.result;
```

There is no `flush()` or `finish()`. `result` is only a snapshot of current
sticky status and accepted bytes; it performs no work.

A sink may short-write. `Writer` retries the remaining bytes synchronously.
Sink fragments remain raw byte fragments and are not independently guaranteed
to be UTF-8 code-point aligned after a short write.

## Optional BufferedWriter decorator

`Writer` stays immediate by default. Destinations that benefit from coalescing
small fragments may opt into `BufferedWriter`, which borrows an existing
`Writer*` plus caller-owned staging storage:

```d
Writer destination = fileWriter(file);
char[1024] staging;
BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
Writer output = buffered.writer();
render(output);
if (!buffered.flush()) { ... }
```

The decorator owns no allocation and never flushes implicitly. `flush()` is
therefore a real buffering-policy operation rather than a generic Writer
operation. The destination writer and staging slice must outlive the decorator,
and callers must not write directly through the destination while bytes are
pending because that would reorder output.

Small fragments accumulate until a later write needs the space or the caller
flushes. Once earlier pending bytes are drained, a fragment at least as large as
the staging capacity bypasses staging and is forwarded directly. A zero-length
staging slice is a direct pass-through. This keeps large borrowed slices
zero-copy through the decorator.

The `Writer` returned by `BufferedWriter.writer()` reports bytes accepted by the
buffering layer. A later explicit flush can still expose downstream failure, so
`BufferedWriter.flush()` / `BufferedWriter.ok` are authoritative for final
delivery of pending bytes. If the destination accepts only a prefix before
failing, that delivered prefix is removed from staging and the undelivered suffix
remains observable through `pending()`. Failure is sticky.

`BufferedWriter` is not automatically inserted in front of `StringBuf`,
`LogMessageWriter`, fixed buffers, or `FILE*`. `StringBuf` and fixed buffers
already own storage, `LogMessageWriter` already performs transport-specific
staging, and libc `FILE*` already has buffering. The decorator exists for
callers and future destinations where callback coalescing is measurably useful.

## StringBuf as a writer destination

A managed `StringBuf` exposes:

```d
Writer writer() return;
```

The returned writer borrows the buffer. It never owns or retains copied buffer
state. Its sink uses `StringBuf.tryAppend`, so allocator failure becomes
`Writer.ok == false` instead of an exception or hidden panic.

This enables ordinary generic renderers:

```d
void writeHeader(ref Writer writer, String name)
{
    writer.write("[", name, "] ");
}

StringBuf buffer = StringBuf.create(allocator);
Writer writer = buffer.writer();
writeHeader(writer, "HTTP");
writer.writeln("status=", 200);
```

No `withWriter` callback is necessary because immediate `Writer` has no pending
bytes to finalize.

The conversion is deliberately explicit: callers write `buffer.writer()` rather
than relying on an implicit cast. The returned Writer contains a borrowed pointer
to the buffer, so making the conversion visible at the call site keeps the
lifetime boundary obvious and avoids surprising overload resolution.

## StringBuf convenience surface

`StringBuf` keeps its existing raw builder operations (`append`, `insert`,
`replaceInPlace`, etc.) and adds writer-style convenience operations:

```d
bool tryWrite(...);
void write(...);

bool tryWriteln(...);
void writeln(...);

bool tryFormat!pattern(...);
void format!pattern(...);
bool tryFormatln!pattern(...);
void formatln!pattern(...);

bool tryFormat(interpolated string);
void format(interpolated string);
bool tryFormatln(interpolated string);
void formatln(interpolated string);
```

`write` uses the exact same printable-value semantics as `Writer.write`, so any
value supported by `formatRepresentation()` or `formatTo(ref Writer)` works.
This intentionally fixes the dangerous old UFCS behavior where
`buffer.write(value)` could resolve to the process-wide stdout `write` free
function.

The `try*` operations are logically transactional. They remember the original
byte length and truncate back to that code-point boundary if the writer fails.
Capacity growth and user formatter side effects are not rolled back, but the
visible StringBuf contents are unchanged on failure.

The non-`try` counterparts panic if their corresponding fallible operation
fails, matching existing `StringBuf` mutation conventions.

## Raw append versus formatted write

The distinction is intentional:

- `append(x)` is a raw string/code-point builder operation.
- `writer.put(x)` is low-level text emission through a generic destination.
- `write(values...)` renders ordinary XTB printable values sequentially.
- `format!pattern(values...)` applies compile-time placeholder formatting.

This keeps low-level string mutation cheap while making general output
construction convenient and predictable.

## LogMessageWriter integration

`LogMessageWriter` keeps its logging-specific raw `write(String)`, `flush()`,
and package-private message finalization because those operations manage its
caller-owned staging buffer and incomplete SGR carry state.

It additionally exposes:

```d
Writer writer() return;
```

The generic `Writer` feeds bytes immediately into `LogMessageWriter.write`.
This removes the old `LogMessageWriter.format` helper and eliminates the extra
512-byte generic Writer staging layer:

```text
before:
formatter -> Writer[512] -> LogMessageWriter[logger buffer] -> sink

after:
formatter -> Writer -> LogMessageWriter[logger buffer] -> sink
```

SGR boundary guarantees remain owned exclusively by `LogMessageWriter`.

## FILE and fixed-buffer adapters

`xtb.core.print.fileWriter(FILE*)` adapts libc output to `Writer`. libc retains
its normal `FILE*` buffering; XTB does not add a second generic staging buffer.

Integer formatting emits bounded digit slices rather than one sink callback per
digit. Repetition emits bounded blocks. This prevents immediate Writer from
turning common formatting operations into pathological callback counts.

Fixed-buffer writers continue to count the full required byte length while
storing only the available prefix, and the existing post-pass backs truncated
output up to a complete UTF-8 scalar.

## Breaking migration

The refactor intentionally prefers one coherent output abstraction over
compatibility aliases:

```text
old                                  new
Writer.fromFile(file)                fileWriter(file)
writer.finish() / writer.flush()     writer.result / no finalization
buffer.writeTo(values...)            buffer.write(values...)
buffer.formatTo!pattern(values...)   buffer.format!pattern(values...)
message.format(value)                message.writer().write(value)
```

Custom formatting hooks remain `formatTo(ref Writer)`; those are value
extension points, not destination-specific free functions, and therefore are
not part of the removed `StringBuf formatTo` API.

## Removed API and machinery

The refactor deliberately removes:

- `Writer`'s 512-byte buffer and `buffered_` state;
- `Writer.flush()` and `Writer.finish()`;
- `AnsiWriter.flush()` and `AnsiWriter.finish()` forwarding;
- `writeTo(ref StringBuf, ...)`;
- `formatTo(ref StringBuf, ...)`;
- StringBuf sink adapters from `xtb.core.print`;
- `LogMessageWriter.format(...)`;
- serde/diagnostic flushes that existed only to drain generic Writer staging.

Callers use `writer.result` to inspect an immediate writer and real
`StringBuf` members for StringBuf output.

## Failure and lifetime rules

- `Writer` never owns its destination or context.
- A writer returned by `StringBuf.writer()` must not outlive that buffer and
  must not be used after the buffer is destroyed or moved.
- A writer returned by `LogMessageWriter.writer()` is valid only for the
  surrounding synchronous logger producer.
- Sink rejection is sticky. Later writes are no-ops.
- `written` counts bytes accepted by the destination before failure.
- `StringBuf.try*` convenience methods restore their original logical length on
  writer failure.

## Testing requirements

The implementation must cover:

- direct StringBuf `write`, `writeln`, `format`, and `formatln`, including interpolation;
- arbitrary printable/custom `formatTo` values;
- converting StringBuf to Writer and passing it through `ref Writer` renderers;
- no finalization call required for Writer visibility;
- sticky sink failure and short-write accounting;
- BufferedWriter coalescing, explicit flush, large-slice direct forwarding,
  zero-length staging, downstream short writes, partial failure, and no implicit flush;
- transactional StringBuf rollback under injected allocator failure;
- fixed-buffer UTF-8 truncation and exact required-byte accounting;
- LogMessageWriter value/pretty formatting through its Writer view;
- existing ANSI, pretty-print, CLI, serde, diagnostics, logging, and examples.
