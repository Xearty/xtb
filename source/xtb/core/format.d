module xtb.core.format;

nothrow @nogc:

import core.lifetime : forward;
import xtb.core.writer : Writer;

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

unittest
{
    import xtb.core.print : writeBuffer;
    import xtb.core.string : equal;
    import xtb.core.writer : fixed, hexadecimal;

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
