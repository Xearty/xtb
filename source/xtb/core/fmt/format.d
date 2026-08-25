module xtb.core.fmt.format;

nothrow @nogc:

import core.interpolation : InterpolationFooter, InterpolationHeader;
import core.lifetime : forward;
import core.stdc.stdio : FILE, stdout;
import xtb.core.fmt.print : fileWriter;
import xtb.core.fmt.writer : WriteResult, Writer;
import xtb.core.lifetime : move, moveEmplace;
import xtb.core.memory : Allocator;
import xtb.core.panic : panic;
import xtb.core.string : StringBuf;

version (XTB_Checked) import xtb.core.panic : require;

/// A lazy, allocation-free compile-time formatting expression.
///
/// Arguments are captured by value. Formatting is deferred until this value is
/// written through the ordinary XTB printable-value path.
struct Formatted(string pattern, Args...)
{
    Args arguments;

    void formatTo(ref Writer writer)
    {
        writer.format!pattern(arguments);
    }

    void formatTo(ref Writer writer) const
    {
        writer.format!pattern(arguments);
    }
}

/// Captures `arguments` as one lazily formatted printable value.
auto formatted(string pattern, Args...)(auto ref Args arguments)
{
    return Formatted!(pattern, Args)(forward!arguments);
}

/// Writes one ordinary printable value to `writer`.
void formatTo(T)(ref Writer writer, auto ref T value)
{
    writer.value(value);
}

/// Applies compile-time `{}` formatting to `writer`.
void formatTo(string pattern, Args...)(ref Writer writer, auto ref Args args)
{
    writer.format!pattern(args);
}

/// Writes a D interpolated-string sequence to `writer`.
void formatTo(Sequence...)(
    ref Writer writer,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    writer.format(header, sequence, footer);
}

bool tryFormatString(string pattern, Args...)(
    Allocator* allocator,
    StringBuf* output,
    auto ref Args args,
)
{
    version (XTB_Checked)
        require(output !is null, "StringBuf output pointer is null");
    output.deinit();

    StringBuf fresh = StringBuf.create(allocator);
    if (!fresh.tryFormat!pattern(args))
    {
        fresh.deinit();
        return false;
    }
    moveEmplace(fresh, *output);
    return true;
}

bool tryFormatString(Sequence...)(
    Allocator* allocator,
    StringBuf* output,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    version (XTB_Checked)
        require(output !is null, "StringBuf output pointer is null");
    output.deinit();

    StringBuf fresh = StringBuf.create(allocator);
    if (!fresh.tryFormat(header, sequence, footer))
    {
        fresh.deinit();
        return false;
    }
    moveEmplace(fresh, *output);
    return true;
}

StringBuf formatString(string pattern, Args...)(
    Allocator* allocator,
    auto ref Args args,
)
{
    StringBuf result;
    if (!tryFormatString!pattern(allocator, &result, args))
        panic("String formatting failed");
    return move(result);
}

StringBuf formatString(Sequence...)(
    Allocator* allocator,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    StringBuf result;
    if (!tryFormatString(allocator, &result, header, sequence, footer))
        panic("String formatting failed");
    return move(result);
}

WriteResult format(string pattern, Args...)(auto ref Args args)
{
    Writer writer = fileWriter(cast(FILE*) stdout);
    writer.format!pattern(args);
    return writer.result;
}

WriteResult format(Sequence...)(
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    Writer writer = fileWriter(cast(FILE*) stdout);
    writer.format(header, sequence, footer);
    return writer.result;
}

WriteResult formatln(string pattern, Args...)(auto ref Args args)
{
    Writer writer = fileWriter(cast(FILE*) stdout);
    writer.formatln!pattern(args);
    return writer.result;
}

WriteResult formatln(Sequence...)(
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    Writer writer = fileWriter(cast(FILE*) stdout);
    writer.formatln(header, sequence, footer);
    return writer.result;
}

unittest
{
    import xtb.core.fmt.fixed_buffer : writeBuffer;
    import xtb.core.string : equal;
    import xtb.core.fmt.writer : fixed, hexadecimal;

    char[128] storage;

    uint captured = 7;
    const id = formatted!"#{}:{}"(captured, 3u);
    captured = 9;
    const result = writeBuffer(storage[], "id=", id);
    assert(result.ok);
    assert(!result.truncated);
    assert(storage[0 .. result.written].equal("id=#7:3"));

    const nested = formatted!"{} / {}"(fixed(1.25, 2), hexadecimal(16));
    const nestedResult = writeBuffer(storage[], nested);
    assert(nestedResult.ok);
    assert(storage[0 .. nestedResult.written].equal("1.25 / 0x10"));

    struct MoveOnly
    {
    nothrow @nogc:

        @disable this(this);
        int value;

        void formatTo(ref Writer writer) const
        {
            writer.value(value);
        }
    }

    auto moved = formatted!"<{}>"(MoveOnly(11));
    const movedResult = writeBuffer(storage[], moved);
    assert(movedResult.ok);
    assert(storage[0 .. movedResult.written].equal("<11>"));
}
