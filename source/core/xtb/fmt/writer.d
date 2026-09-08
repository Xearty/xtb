module xtb.fmt.writer;

nothrow @nogc:

import core.attribute;
import core.interpolation;
import core.stdc.stdio;

import xtb.lifetime;
import xtb.panic;
import xtb.types;
import xtb.utf8;

/// Synchronously accepts raw output bytes and returns the accepted prefix size.
alias WriterSink = usize function(void* context, scope const(u8)[] bytes) nothrow @nogc;

/// Snapshot of an immediate writer's sticky status and accepted byte count.
struct WriteResult
{
    bool ok;
    usize written;
}

/// A synchronous, non-owning view over a formatted-text destination.
///
/// `Writer` owns no buffering. Every successful `put`, `write`, or `format`
/// operation reaches the sink before the call returns, so there is no flush or
/// finalization obligation. The sink and context must remain valid for the
/// writer's lifetime. The four fields form one coupled writer state: `sink`
/// and `context` identify the destination, while `written` and `failed` track
/// its sticky delivery status.
struct Writer
{
nothrow @nogc:

    WriterSink sink;
    void* context;
    usize written;
    bool failed;

    @disable this(this);

    /// Rebinds this writer from an rvalue writer. Copying another live writer
    /// remains rejected because the copy constructor is disabled.
    ref Writer opAssign(Writer source) return
    {
        this.sink = source.sink;
        this.context = source.context;
        this.written = source.written;
        this.failed = source.failed;
        source.sink = null;
        source.context = null;
        source.written = 0;
        source.failed = true;
        return this;
    }

    /// Creates a writer for `sink` and its opaque `context`.
    ///
    /// The caller must ensure that `sink` can safely interpret `context` and
    /// keep `context` valid until the writer is no longer used. A null sink
    /// creates an already-failed writer.
    static Writer from_sink(WriterSink sink, void* context) @system
    {
        Writer result;
        result.sink = sink;
        result.context = context;
        result.failed = sink is null;
        return result;
    }

    bool ok() const pure @safe
    {
        return !this.failed;
    }

    WriteResult result() const pure @safe
    {
        return WriteResult(!this.failed, this.written);
    }

    /// Writes one complete ASCII code unit.
    void put(char value)
    {
        require(
            cast(u8) value <= 0x7F,
            "non-ASCII char written as a complete code point; use dchar",
        );
        if (this.failed) return;

        char[1] bytes = [value];
        this.emit(bytes[]);
    }

    /// Writes one complete Unicode scalar encoded as UTF-8.
    void put(dchar value)
    {
        if (this.failed) return;

        const encoded = encode_utf8(value);
        const code_units = encoded.bytes;
        this.emit(code_units[0 .. encoded.byte_length]);
    }

    /// Writes borrowed UTF-8 text synchronously.
    void put(scope String text)
    {
        if (this.failed || text.length == 0) return;

        this.emit(text);
    }

    /// Repeats one ASCII code unit without issuing one sink callback per byte.
    void repeat(char value, usize count)
    {
        require(
            cast(u8) value <= 0x7F,
            "non-ASCII char written as a complete code point; use dchar",
        );
        if (this.failed || count == 0) return;

        char[64] block;
        block[] = value;
        while (count >= block.length && !this.failed)
        {
            this.emit(block[]);
            count -= block.length;
        }
        if (count != 0 && !this.failed) this.emit(block[0 .. count]);
    }

    /// Repeats one Unicode scalar.
    void repeat(dchar value, usize count)
    {
        if (this.failed || count == 0) return;

        const encoded = encode_utf8(value);
        const code_units = encoded.bytes;
        const text = cast(String) code_units[0 .. encoded.byte_length];
        while (count-- != 0 && !this.failed) this.emit(text);
    }

    /// Repeats borrowed UTF-8 text.
    void repeat(scope String value, usize count)
    {
        if (this.failed || value.length == 0 || count == 0) return;

        while (count-- != 0 && !this.failed) this.emit(value);
    }

    /// Writes one ordinary XTB printable value.
    void value(T)(auto ref T value)
    {
        write_value(this, value);
    }

    /// Writes ordinary XTB printable values sequentially.
    void write(Args...)(auto ref Args args)
    {
        write_arguments(this, args);
    }

    /// Writes ordinary values followed by one newline.
    void writeln(Args...)(auto ref Args args)
    {
        write_arguments(this, args);
        this.put('\n');
    }

    /// Applies compile-time `{}` placeholder formatting.
    void format(String pattern, Args...)(auto ref Args args)
    {
        write_format!(pattern, 0, 0)(this, args);
    }

    /// Writes a D interpolated-string sequence.
    void format(Sequence...)(InterpolationHeader, auto ref Sequence sequence, InterpolationFooter)
    {
        write_arguments(this, sequence);
    }

    /// Applies compile-time formatting and appends one newline.
    void formatln(String pattern, Args...)(auto ref Args args)
    {
        write_format!(pattern, 0, 0)(this, args);
        this.put('\n');
    }

    /// Writes an interpolated-string sequence followed by one newline.
    void formatln(Sequence...)(InterpolationHeader, auto ref Sequence sequence, InterpolationFooter)
    {
        write_arguments(this, sequence);
        this.put('\n');
    }

    private void emit(scope String text)
    {
        // char and u8 have the same size, and the scoped input is consumed
        // synchronously without widening its access or lifetime.
        cast(void) this.emit_bytes(cast(const(u8)[]) text);
    }

    package(xtb.fmt) usize emit_bytes(scope const(u8)[] bytes)
    {
        usize offset;
        while (offset < bytes.length && !this.failed)
        {
            const accepted = this.sink(this.context, bytes[offset .. $]);
            if (accepted == 0 || accepted > bytes.length - offset)
            {
                this.failed = true;
                return offset;
            }

            // The sink has already accepted this prefix. Advance the physical
            // delivery count before checking whether the public cumulative
            // counter can still represent it.
            offset += accepted;
            if (accepted > usize.max - this.written)
            {
                this.failed = true;
                return offset;
            }
            this.written += accepted;
        }
        return offset;
    }
}

private template Unqualified(T)
{
    alias Unqualified = typeof(cast() T.init);
}

private enum has_format_representation(T) =
    __traits(hasMember, Unqualified!T, "format_representation");

private enum has_format_to_member(T) =
    __traits(hasMember, Unqualified!T, "format_to");

private bool has_function_attribute(alias candidate, String expected)()
{
    static foreach (attribute; __traits(getFunctionAttributes, candidate))
    {
        if (attribute == expected) return true;
    }

    return false;
}

private void write_arguments(Args...)(ref Writer writer, auto ref Args args)
{
    static foreach (index; 0 .. Args.length)
    {
        if (writer.ok) write_value(writer, args[index]);
    }
}

private void write_value(T)(ref Writer writer, auto ref T value)
{
    alias U = Unqualified!T;
    static if (is(U == InterpolationHeader) || is(U == InterpolationFooter))
    {
        // Interpolation boundary markers carry no output.
    }
    else static if (is(U == InterpolatedLiteral!text, String text))
    {
        writer.put(text);
    }
    else static if (is(U == InterpolatedExpression!expression, String expression))
    {
        // Source text is metadata only. The compiler passes its evaluated
        // value or values as the following sequence elements.
    }
    else static if (has_format_representation!U)
    {
        static assert(
            !has_format_to_member!U,
            U.stringof ~ " defines both format_representation and format_to",
        );
        alias Representation = typeof(value.format_representation());
        static assert(
            !is(Unqualified!Representation == U),
            U.stringof ~ ".format_representation() must not return the same type",
        );
        enum representation_is_borrowed =
            has_function_attribute!(value.format_representation, "ref")();
        static assert(
            representation_is_borrowed || !needs_finalization!Representation,
            U.stringof ~ ".format_representation() must return a borrowed reference "
                ~ "or a cleanup-free value",
        );
        write_value(writer, value.format_representation());
    }
    else static if (__traits(compiles, value.format_to(writer)))
    {
        alias FormatReturn = typeof(value.format_to(writer));
        static assert(
            is(FormatReturn == void),
            U.stringof ~ ".format_to(ref Writer) must return void",
        );
        value.format_to(writer);
    }
    else static if (is(U == typeof(null)))
    {
        writer.put("null");
    }
    else static if (is(U == bool))
    {
        writer.put(value ? "true" : "false");
    }
    else static if (is(U == char))
    {
        writer.put(value);
    }
    else static if (is(U == wchar) || is(U == dchar))
    {
        writer.put(cast(dchar) value);
    }
    else static if (is(U == enum))
    {
        write_integer(writer, value, 10, false, false, 1);
    }
    else static if (__traits(isIntegral, U))
    {
        write_integer(writer, value, 10, false, false, 1);
    }
    else static if (__traits(isFloating, U))
    {
        write_float(writer, value, 'g', 6);
    }
    else static if (
        is(U == char[])
        || is(U == const(char)[])
        || is(U == immutable(char)[])
    )
    {
        writer.put(cast(String) value);
    }
    else static if (is(U == char[array_length], usize array_length))
    {
        writer.put(cast(String) value[]);
    }
    else static if (is(U == Pointee*, Pointee))
    {
        write_pointer(writer, cast(const(void)*) value);
    }
    else
    {
        static assert(
            false,
            "unsupported printable type: " ~ U.stringof
                ~ "; define `format_representation()` or "
                ~ "`void format_to(ref Writer) nothrow @nogc`",
        );
    }
}

private void write_integer(T)(
    ref Writer writer,
    T value,
    u8 radix,
    bool prefix,
    bool uppercase,
    u16 minimum_digits,
)
{
    static assert(__traits(isIntegral, T) && T.sizeof <= u64.sizeof);
    if (radix < 2 || radix > 36) radix = 10;

    bool negative;
    u64 magnitude;
    static if (__traits(isUnsigned, T))
    {
        magnitude = cast(u64) value;
    }
    else
    {
        const signed_value = cast(i64) value;
        negative = signed_value < 0;
        const bits = cast(u64) signed_value;
        magnitude = negative ? cast(u64) 0 - bits : bits;
    }

    char[65] digits_buffer;
    usize start = digits_buffer.length;
    const digits = uppercase
        ? "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        : "0123456789abcdefghijklmnopqrstuvwxyz";
    do
    {
        digits_buffer[--start] = digits[cast(usize)(magnitude % radix)];
        magnitude /= radix;
    }
    while (magnitude != 0);

    const count = digits_buffer.length - start;
    if (negative) writer.put('-');
    if (prefix)
    {
        if (radix == 2)
        {
            writer.put(uppercase ? "0B" : "0b");
        }
        else if (radix == 8)
        {
            writer.put(uppercase ? "0O" : "0o");
        }
        else if (radix == 16)
        {
            writer.put(uppercase ? "0X" : "0x");
        }
    }

    if (minimum_digits > count) writer.repeat('0', minimum_digits - count);
    writer.put(digits_buffer[start .. $]);
}

private void write_float(T)(ref Writer writer, T value, char mode, i32 precision)
{
    static assert(__traits(isFloating, T));
    if (precision < 0) precision = 0;
    if (precision > 64) precision = 64;

    char[128] buffer;
    i32 count;
    static if (is(Unqualified!T == real))
    {
        if (mode == 'f')
        {
            count = snprintf(
                buffer.ptr,
                buffer.length,
                "%.*Lf".ptr,
                precision,
                cast(real) value,
            );
        }
        else if (mode == 'e')
        {
            count = snprintf(
                buffer.ptr,
                buffer.length,
                "%.*Le".ptr,
                precision,
                cast(real) value,
            );
        }
        else
        {
            count = snprintf(
                buffer.ptr,
                buffer.length,
                "%.*Lg".ptr,
                precision,
                cast(real) value,
            );
        }
    }
    else
    {
        if (mode == 'f')
        {
            count = snprintf(
                buffer.ptr,
                buffer.length,
                "%.*f".ptr,
                precision,
                cast(f64) value,
            );
        }
        else if (mode == 'e')
        {
            count = snprintf(
                buffer.ptr,
                buffer.length,
                "%.*e".ptr,
                precision,
                cast(f64) value,
            );
        }
        else
        {
            count = snprintf(
                buffer.ptr,
                buffer.length,
                "%.*g".ptr,
                precision,
                cast(f64) value,
            );
        }
    }

    if (count < 0)
    {
        writer.put("<float-format-error>");
    }
    else if (cast(usize) count >= buffer.length)
    {
        writer.put("<float-format-error>");
    }
    else
    {
        writer.put(buffer[0 .. cast(usize) count]);
    }
}

private void write_pointer(ref Writer writer, const(void)* pointer)
{
    if (pointer is null)
    {
        writer.put("null");
        return;
    }

    write_integer(
        writer,
        cast(usize) pointer,
        16,
        true,
        false,
        cast(u16)(usize.sizeof * 2),
    );
}

struct IntegerFormat(T)
{
nothrow @nogc:

    T value;
    u8 radix = 10;
    bool prefix;
    bool uppercase;
    u16 minimum_digits = 1;

    void format_to(ref Writer writer) const
    {
        write_integer(
            writer,
            this.value,
            this.radix,
            this.prefix,
            this.uppercase,
            this.minimum_digits,
        );
    }

    IntegerFormat digits(u16 count) const
    {
        IntegerFormat result = this;
        result.minimum_digits = count;
        return result;
    }

    IntegerFormat upper() const
    {
        IntegerFormat result = this;
        result.uppercase = true;
        return result;
    }
}

private template UnqualifiedValue(T)
{
    alias UnqualifiedValue = typeof(cast() T.init);
}

IntegerFormat!(UnqualifiedValue!T) radix(T)(T value, u8 base)
{
    static assert(__traits(isIntegral, T) && T.sizeof <= u64.sizeof);
    IntegerFormat!(UnqualifiedValue!T) result;
    result.value = value;
    result.radix = base;
    return result;
}

IntegerFormat!(UnqualifiedValue!T) binary(T)(T value)
{
    IntegerFormat!(UnqualifiedValue!T) result = radix(value, 2);
    result.prefix = true;
    return result;
}

IntegerFormat!(UnqualifiedValue!T) hexadecimal(T)(T value)
{
    IntegerFormat!(UnqualifiedValue!T) result = radix(value, 16);
    result.prefix = true;
    return result;
}

struct FloatFormat(T)
{
nothrow @nogc:

    T value;
    char mode;
    i32 precision;

    void format_to(ref Writer writer) const
    {
        write_float(writer, this.value, this.mode, this.precision);
    }
}

FloatFormat!(UnqualifiedValue!T) fixed(T)(T value, i32 precision = 6)
{
    return FloatFormat!(UnqualifiedValue!T)(value, 'f', precision);
}

FloatFormat!(UnqualifiedValue!T) scientific(T)(T value, i32 precision = 6)
{
    return FloatFormat!(UnqualifiedValue!T)(value, 'e', precision);
}

private void write_format(
    String pattern,
    usize position,
    usize argument,
    Args...,
)(ref Writer writer, auto ref Args args)
{
    static if (position == pattern.length)
    {
        static assert(argument == Args.length, "too many format arguments");
    }
    else static if (pattern[position] == '{')
    {
        static if (position + 1 < pattern.length && pattern[position + 1] == '{')
        {
            writer.put('{');
            write_format!(pattern, position + 2, argument)(writer, args);
        }
        else static if (position + 1 < pattern.length && pattern[position + 1] == '}')
        {
            static assert(argument < Args.length, "not enough format arguments");
            write_value(writer, args[argument]);
            write_format!(pattern, position + 2, argument + 1)(writer, args);
        }
        else
        {
            static assert(false, "format placeholders must be {} or {{");
        }
    }
    else static if (pattern[position] == '}')
    {
        static if (position + 1 < pattern.length && pattern[position + 1] == '}')
        {
            writer.put('}');
            write_format!(pattern, position + 2, argument)(writer, args);
        }
        else
        {
            static assert(false, "unmatched } in format string");
        }
    }
    else
    {
        enum next = next_special(pattern, position);
        writer.put(pattern[position .. next]);
        write_format!(pattern, next, argument)(writer, args);
    }
}

private usize next_special(String pattern, usize start) pure @safe
{
    usize result = start;
    while (result < pattern.length && pattern[result] != '{' && pattern[result] != '}') ++result;

    return result;
}

version (unittest)
{
    import core.stdc.string;

    private struct WriterTestSinkState
    {
        char[256] storage;
        usize length;
        usize max_per_call = usize.max;
        usize successful_call_limit = usize.max;
        usize calls;
        const(u8)* first_pointer;
        usize first_length;
        bool reject;
    }

    private usize writer_test_sink(void* context, scope const(u8)[] bytes) @system
    {
        // Tests pass a live WriterTestSinkState as the opaque sink context.
        auto state = cast(WriterTestSinkState*) context;
        if (
            state is null
            || state.reject
            || bytes.length == 0
            || state.calls >= state.successful_call_limit
        )
        {
            return 0;
        }

        if (state.calls == 0)
        {
            state.first_pointer = bytes.ptr;
            state.first_length = bytes.length;
        }

        auto amount = bytes.length < state.max_per_call
            ? bytes.length
            : state.max_per_call;
        const available = state.storage.length - state.length;
        if (amount > available) amount = available;
        if (amount == 0) return 0;

        cast(void) memcpy(state.storage.ptr + state.length, bytes.ptr, amount);
        state.length += amount;
        ++state.calls;
        return amount;
    }
}

unittest
{
    static assert(!__traits(compiles, () @system
    {
        WriterTestSinkState state;
        auto first = Writer.from_sink(&writer_test_sink, &state);
        auto second = first;
    }));

    static assert(!__traits(compiles, () @system
    {
        WriterTestSinkState state;
        auto first = Writer.from_sink(&writer_test_sink, &state);
        auto second = Writer.from_sink(&writer_test_sink, &state);
        second = first;
    }));
}

unittest
{
    WriterTestSinkState state;
    state.max_per_call = 2;
    auto writer = Writer.from_sink(&writer_test_sink, &state);

    writer.write("x=", 42, ", ", cast(dchar) 'λ');
    assert(writer.ok);
    assert(writer.written == 8);
    assert(state.length == 8);
    assert(state.storage[0 .. state.length] == "x=42, λ");
    assert(state.calls > 1);

    writer.writeln();
    assert(state.storage[state.length - 1] == '\n');
    assert(writer.result.written == state.length);
}

unittest
{
    WriterTestSinkState state;
    auto writer = Writer.from_sink(&writer_test_sink, &state);
    writer.put("accepted");
    assert(writer.ok);
    const before = writer.written;

    state.reject = true;
    writer.put("rejected");
    assert(!writer.ok);
    assert(writer.written == before);

    writer.put("ignored");
    assert(writer.written == before);
}
