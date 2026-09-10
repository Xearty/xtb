module xtb.fmt.format;

nothrow @nogc:

import core.interpolation;
import core_lifetime = core.lifetime;
import core.stdc.stdio;

import xtb.fmt.print;
import xtb.fmt.writer;
import xtb.lifetime;
import xtb.memory;
import xtb.panic;
import xtb.string;

/// A lazy, allocation-free compile-time formatting expression.
///
/// Arguments are captured by value. Formatting is deferred until this value is
/// written through the ordinary XTB printable-value path.
struct Formatted(string pattern, Args...)
{
    Args arguments;

    void format_to(ref Writer writer) nothrow @nogc
    {
        writer.format!pattern(this.arguments);
    }

    void format_to(ref Writer writer) const nothrow @nogc
    {
        writer.format!pattern(this.arguments);
    }
}

/// Captures `arguments` as one lazily formatted printable value.
auto formatted(string pattern, Args...)(auto ref Args arguments)
{
    return Formatted!(pattern, Args)(core_lifetime.forward!arguments);
}

/// Writes one ordinary printable value to `writer`.
void format_to(T)(ref Writer writer, auto ref T value)
{
    writer.value(value);
}

/// Applies compile-time `{}` formatting to `writer`.
void format_to(string pattern, Args...)(ref Writer writer, auto ref Args args)
{
    writer.format!pattern(args);
}

/// Writes a D interpolated-string sequence to `writer`.
void format_to(Sequence...)(
    ref Writer writer,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    writer.format(header, sequence, footer);
}

bool try_format_string(string pattern, Args...)(
    Allocator* allocator,
    StringBuf* output,
    auto ref Args args,
)
{
    require(output !is null, "StringBuf output pointer is null");
    output.deinit();

    StringBuf fresh = StringBuf.create(allocator);
    if (!fresh.try_format!pattern(args))
    {
        fresh.deinit();
        return false;
    }

    move_emplace(fresh, *output);
    return true;
}

bool try_format_string(Sequence...)(
    Allocator* allocator,
    StringBuf* output,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    require(output !is null, "StringBuf output pointer is null");
    output.deinit();

    StringBuf fresh = StringBuf.create(allocator);
    if (!fresh.try_format(header, sequence, footer))
    {
        fresh.deinit();
        return false;
    }

    move_emplace(fresh, *output);
    return true;
}

StringBuf format_string(string pattern, Args...)(
    Allocator* allocator,
    auto ref Args args,
)
{
    StringBuf result;
    if (!try_format_string!pattern(allocator, &result, args))
        panic("string formatting failed");

    return move(result);
}

StringBuf format_string(Sequence...)(
    Allocator* allocator,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    StringBuf result;
    if (!try_format_string(allocator, &result, header, sequence, footer))
        panic("string formatting failed");

    return move(result);
}

WriteResult format(string pattern, Args...)(auto ref Args args)
{
    Writer writer = file_writer(cast(FILE*) stdout);
    writer.format!pattern(args);
    return writer.result;
}

WriteResult format(Sequence...)(
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    Writer writer = file_writer(cast(FILE*) stdout);
    writer.format(header, sequence, footer);
    return writer.result;
}

WriteResult formatln(string pattern, Args...)(auto ref Args args)
{
    Writer writer = file_writer(cast(FILE*) stdout);
    writer.formatln!pattern(args);
    return writer.result;
}

WriteResult formatln(Sequence...)(
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    Writer writer = file_writer(cast(FILE*) stdout);
    writer.formatln(header, sequence, footer);
    return writer.result;
}

version (unittest)
{
    import xtb.fmt.fixed_buffer;
    import xtb.types;
}

unittest
{
    char[128] storage;

    u32 captured = 7;
    const id = formatted!"#{}:{}"(captured, 3u);
    captured = 9;
    const result = write_buffer(storage[], "id=", id);
    assert(result.ok);
    assert(!result.truncated);
    assert(storage[0 .. result.written].equal("id=#7:3"));

    const nested = formatted!"{} / {}"(fixed(1.25, 2), hexadecimal(16));
    const nested_result = write_buffer(storage[], nested);
    assert(nested_result.ok);
    assert(storage[0 .. nested_result.written].equal("1.25 / 0x10"));

    struct MoveOnly
    {
        i32 value;

        @disable this(this);

        void format_to(ref Writer writer) const nothrow @nogc
        {
            writer.value(this.value);
        }
    }

    auto moved = formatted!"<{}>"(MoveOnly(11));
    const moved_result = write_buffer(storage[], moved);
    assert(moved_result.ok);
    assert(storage[0 .. moved_result.written].equal("<11>"));
}
