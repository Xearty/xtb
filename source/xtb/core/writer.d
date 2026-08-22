module xtb.core.writer;

nothrow @nogc:

import core.interpolation : InterpolatedExpression, InterpolatedLiteral,
    InterpolationFooter, InterpolationHeader;
import core.stdc.stdio : snprintf;
import xtb.core.lifetime : needsFinalization;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.types : String, u8;
import xtb.core.utf8 : encodeUtf8;

/// Synchronously accepts raw output bytes and returns the accepted prefix size.
alias WriterSink = size_t function(void* context, scope const(u8)[] bytes);

/// Snapshot of an immediate writer's sticky status and accepted byte count.
struct WriteResult
{
    bool ok;
    size_t written;
}

/// A synchronous, non-owning view over a formatted-text destination.
///
/// `Writer` owns no buffering. Every successful `put`, `write`, or `format`
/// operation reaches the sink before the call returns, so there is no flush or
/// finalization obligation. The sink and context must remain valid for the
/// writer's lifetime.
struct Writer
{
nothrow @nogc:

    private WriterSink sink_;
    private void* context_;
    private size_t written_;
    private bool failed_;

    @disable this(this);

    /// Rebinds this writer from an rvalue writer. Copying another live writer
    /// remains rejected because the copy constructor is disabled.
    ref Writer opAssign(Writer source) return
    {
        sink_ = source.sink_;
        context_ = source.context_;
        written_ = source.written_;
        failed_ = source.failed_;
        source.sink_ = null;
        source.context_ = null;
        source.written_ = 0;
        source.failed_ = true;
        return this;
    }

    static Writer fromSink(WriterSink sink, void* context)
    {
        Writer result;
        result.sink_ = sink;
        result.context_ = context;
        result.failed_ = sink is null;
        return result;
    }

    bool ok() const pure @safe
    {
        return !failed_;
    }

    size_t written() const pure @safe
    {
        return written_;
    }

    WriteResult result() const pure @safe
    {
        return WriteResult(!failed_, written_);
    }

    /// Writes one complete ASCII code unit.
    void put(char value)
    {
        version (XTB_Checked)
            require(cast(u8) value <= 0x7f,
                "non-ASCII char written as a complete code point; use dchar");
        if (failed_)
            return;

        char[1] bytes = [value];
        emit(bytes[]);
    }

    /// Writes one complete Unicode scalar encoded as UTF-8.
    void put(dchar value)
    {
        if (failed_)
            return;
        const encoded = encodeUtf8(value);
        const codeUnits = encoded.codeUnits;
        emit(codeUnits[0 .. encoded.byteLength]);
    }

    /// Writes borrowed UTF-8 text synchronously.
    void put(scope String text)
    {
        if (failed_ || text.length == 0)
            return;
        emit(text);
    }

    /// Repeats one ASCII code unit without issuing one sink callback per byte.
    void repeat(char value, size_t count)
    {
        version (XTB_Checked)
            require(cast(u8) value <= 0x7f,
                "non-ASCII char written as a complete code point; use dchar");
        if (failed_ || count == 0)
            return;

        char[64] block;
        block[] = value;
        while (count >= block.length && !failed_)
        {
            emit(block[]);
            count -= block.length;
        }
        if (count != 0 && !failed_)
            emit(block[0 .. count]);
    }

    /// Repeats one Unicode scalar.
    void repeat(dchar value, size_t count)
    {
        if (failed_ || count == 0)
            return;
        const encoded = encodeUtf8(value);
        const codeUnits = encoded.codeUnits;
        const text = cast(String) codeUnits[0 .. encoded.byteLength];
        while (count-- != 0 && !failed_)
            emit(text);
    }

    /// Repeats borrowed UTF-8 text.
    void repeat(scope String value, size_t count)
    {
        if (failed_ || value.length == 0 || count == 0)
            return;
        while (count-- != 0 && !failed_)
            emit(value);
    }

    /// Writes one ordinary XTB printable value.
    void value(T)(auto ref T value)
    {
        writeValue(this, value);
    }

    /// Writes ordinary XTB printable values sequentially.
    void write(Args...)(auto ref Args args)
    {
        writeArguments(this, args);
    }

    /// Writes ordinary values followed by one newline.
    void writeln(Args...)(auto ref Args args)
    {
        writeArguments(this, args);
        put('\n');
    }

    /// Applies compile-time `{}` placeholder formatting.
    void format(string pattern, Args...)(auto ref Args args)
    {
        writeFormat!(pattern, 0, 0)(this, args);
    }

    /// Writes a D interpolated-string sequence.
    void format(Sequence...)(
        InterpolationHeader,
        auto ref Sequence sequence,
        InterpolationFooter,
    )
    {
        writeArguments(this, sequence);
    }

    /// Applies compile-time formatting and appends one newline.
    void formatln(string pattern, Args...)(auto ref Args args)
    {
        writeFormat!(pattern, 0, 0)(this, args);
        put('\n');
    }

    /// Writes an interpolated-string sequence followed by one newline.
    void formatln(Sequence...)(
        InterpolationHeader,
        auto ref Sequence sequence,
        InterpolationFooter,
    )
    {
        writeArguments(this, sequence);
        put('\n');
    }

    private void emit(scope String text)
    @trusted
    {
        emitBytes(cast(const(u8)[]) text);
    }

    private size_t emitBytes(scope const(u8)[] bytes)
    {
        size_t offset;
        while (offset < bytes.length && !failed_)
        {
            const accepted = sink_(context_, bytes[offset .. $]);
            if (accepted == 0 || accepted > bytes.length - offset)
            {
                failed_ = true;
                return offset;
            }

            // The sink has already accepted this prefix. Advance the physical
            // delivery count before checking whether the public cumulative
            // counter can still represent it.
            offset += accepted;
            if (accepted > size_t.max - written_)
            {
                failed_ = true;
                return offset;
            }
            written_ += accepted;
        }
        return offset;
    }
}

/// Explicit caller-buffered decorator over an immediate `Writer`.
///
/// Small fragments are copied into caller-owned staging storage and emitted to
/// the destination when that storage must be drained or `flush` is called. Once
/// pending bytes are drained, a fragment at least as large as the staging capacity
/// bypasses staging and is forwarded directly without an intermediate copy.
/// Zero-length staging therefore acts as a direct pass-through.
///
/// The decorator borrows both the destination writer and staging storage. Neither
/// may be moved, destroyed, or reused while this object or a writer returned by
/// `writer()` remains live. Do not write directly through the destination while
/// bytes are pending here, because doing so would reorder output.
///
/// A writer returned by `writer()` reports bytes accepted by this buffering layer.
/// Final delivery of staged bytes is checked explicitly through `flush()` / `ok`.
/// `BufferedWriter` never flushes implicitly when it goes out of scope.
struct BufferedWriter
{
nothrow @nogc:

    private Writer* destination_;
    private char[] staging_;
    private size_t staged_;
    private bool failed_;

    @disable this(this);
    @disable ref BufferedWriter opAssign(BufferedWriter source) return;

    /// Creates a buffering decorator over `destination` using caller-owned storage.
    ///
    /// `destination` must be non-null and outlive the returned decorator.
    static BufferedWriter create(
        return scope Writer* destination,
        return scope char[] staging,
    ) @safe
    {
        version (XTB_Checked)
            require(destination !is null, "BufferedWriter destination is null");

        BufferedWriter result;
        result.destination_ = destination;
        result.staging_ = staging;
        result.failed_ = destination is null || !destination.ok;
        return result;
    }

    /// Returns whether this decorator and its destination remain writable.
    bool ok() const pure @safe
    {
        return !failed_ && destination_ !is null && destination_.ok;
    }

    /// Number of accepted bytes still staged locally.
    size_t pending() const pure @safe
    {
        return staged_;
    }

    /// Returns an immediate generic Writer view over this buffering decorator.
    ///
    /// The returned writer borrows this object and must not outlive or move past it.
    Writer writer() return @trusted
    {
        return Writer.fromSink(&bufferedWriterSink, &this);
    }

    /// Delivers all staged bytes to the underlying writer.
    ///
    /// On a partial downstream failure the accepted prefix is removed from the
    /// staging buffer and the undelivered suffix remains observable via `pending`.
    /// Failure is sticky and later writes are rejected.
    bool flush()
    {
        return flushPending();
    }

    private size_t accept(scope const(u8)[] bytes)
    {
        if (bytes.length == 0 || !ok)
            return 0;

        if (staging_.length == 0)
            return forward(bytes);

        const remaining = staging_.length - staged_;
        if (staged_ != 0 && bytes.length > remaining)
        {
            if (!flushPending())
                return 0;
        }

        // Once earlier bytes are drained, avoid copying a fragment that is at
        // least as large as the whole staging area.
        if (staged_ == 0 && bytes.length >= staging_.length)
            return forward(bytes);

        import core.stdc.string : memcpy;

        memcpy(staging_.ptr + staged_, bytes.ptr, bytes.length);
        staged_ += bytes.length;
        return bytes.length;
    }

    private size_t forward(scope const(u8)[] bytes)
    {
        if (!ok || bytes.length == 0)
            return 0;

        const accepted = destination_.emitBytes(bytes);
        if (!destination_.ok)
            failed_ = true;
        return accepted;
    }

    private bool flushPending()
    {
        if (!ok)
        {
            failed_ = true;
            return false;
        }
        if (staged_ == 0)
            return true;

        const delivered = destination_.emitBytes(
            cast(const(u8)[]) staging_[0 .. staged_],
        );

        if (delivered != 0)
        {
            if (delivered < staged_)
            {
                import core.stdc.string : memmove;

                memmove(staging_.ptr, staging_.ptr + delivered, staged_ - delivered);
            }
            staged_ -= delivered;
        }

        if (!destination_.ok || staged_ != 0)
            failed_ = true;
        return !failed_;
    }
}

private size_t bufferedWriterSink(
    void* context,
    scope const(u8)[] bytes,
)
@trusted
{
    BufferedWriter* buffered = cast(BufferedWriter*) context;
    if (buffered is null)
        return 0;
    return buffered.accept(bytes);
}

private template Unqualified(T)
{
    alias Unqualified = typeof(cast() T.init);
}

private enum hasFormatRepresentation(T) =
    __traits(hasMember, Unqualified!T, "formatRepresentation");

private enum hasFormatToMember(T) =
    __traits(hasMember, Unqualified!T, "formatTo");

private bool hasFunctionAttribute(alias function_, string expected)()
{
    static foreach (attribute; __traits(getFunctionAttributes, function_))
        if (attribute == expected)
            return true;
    return false;
}

private void writeArguments(Args...)(ref Writer writer, auto ref Args args)
{
    static foreach (index; 0 .. Args.length)
        if (writer.ok)
            writeValue(writer, args[index]);
}

private void writeValue(T)(ref Writer writer, auto ref T value)
{
    alias U = Unqualified!T;
    static if (is(U == InterpolationHeader) || is(U == InterpolationFooter))
    {
    }
    else static if (is(U == InterpolatedLiteral!text, string text))
    {
        writer.put(text);
    }
    else static if (is(U == InterpolatedExpression!expression, string expression))
    {
        // Source text is metadata only. The compiler passes its evaluated
        // value or values as the following sequence elements.
    }
    else static if (hasFormatRepresentation!U)
    {
        static assert(!hasFormatToMember!U, U.stringof ~
                " defines both formatRepresentation and formatTo");
        alias Representation = typeof(value.formatRepresentation());
        static assert(!is(Unqualified!Representation == U), U.stringof ~
                ".formatRepresentation() must not return the same type");
        enum representationIsBorrowed =
            hasFunctionAttribute!(value.formatRepresentation, "ref")();
        static assert(representationIsBorrowed ||
                !needsFinalization!Representation, U.stringof ~
                ".formatRepresentation() must return a borrowed reference " ~
                "or a cleanup-free value");
        writeValue(writer, value.formatRepresentation());
    }
    else static if (__traits(compiles, value.formatTo(writer)))
    {
        alias FormatReturn = typeof(value.formatTo(writer));
        static assert(is(FormatReturn == void), U.stringof ~
                ".formatTo(ref Writer) must return void");
        value.formatTo(writer);
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
        writeInteger(writer, value, 10, false, false, 1);
    }
    else static if (__traits(isIntegral, U))
    {
        writeInteger(writer, value, 10, false, false, 1);
    }
    else static if (__traits(isFloating, U))
    {
        writeFloat(writer, value, 'g', 6);
    }
    else static if (is(U == char[]) || is(U == const(char)[]) ||
        is(U == immutable(char)[]))
    {
        writer.put(cast(String) value);
    }
    else static if (is(U == char[N], size_t N))
    {
        writer.put(cast(String) value[]);
    }
    else static if (is(U == Pointee*, Pointee))
    {
        writePointer(writer, cast(const(void)*) value);
    }
    else
    {
        static assert(false, "unsupported printable type: " ~ U.stringof ~
                "; define `formatRepresentation()` or " ~
                "`void formatTo(ref Writer) nothrow @nogc`");
    }
}

private void writeInteger(T)(
    ref Writer writer,
    T value,
    ubyte radix,
    bool prefix,
    bool uppercase,
    ushort minimumDigits,
)
{
    static assert(__traits(isIntegral, T) && T.sizeof <= ulong.sizeof);
    if (radix < 2 || radix > 36)
        radix = 10;

    bool negative;
    ulong magnitude;
    static if (__traits(isUnsigned, T))
        magnitude = cast(ulong) value;
    else
    {
        const signedValue = cast(long) value;
        negative = signedValue < 0;
        const bits = cast(ulong) signedValue;
        magnitude = negative ? 0UL - bits : bits;
    }

    char[65] digitsBuffer;
    size_t start = digitsBuffer.length;
    String digits = uppercase
        ? "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" : "0123456789abcdefghijklmnopqrstuvwxyz";
    do
    {
        digitsBuffer[--start] = digits[cast(size_t)(magnitude % radix)];
        magnitude /= radix;
    }
    while (magnitude != 0);

    const count = digitsBuffer.length - start;
    if (negative)
        writer.put('-');
    if (prefix)
    {
        if (radix == 2)
            writer.put(uppercase ? "0B" : "0b");
        else if (radix == 8)
            writer.put(uppercase ? "0O" : "0o");
        else if (radix == 16)
            writer.put(uppercase ? "0X" : "0x");
    }

    if (minimumDigits > count)
        writer.repeat('0', minimumDigits - count);
    writer.put(digitsBuffer[start .. $]);
}

private void writeFloat(T)(ref Writer writer, T value, char mode, int precision)
{
    static assert(__traits(isFloating, T));
    if (precision < 0)
        precision = 0;
    if (precision > 64)
        precision = 64;

    char[128] buffer;
    int count;
    static if (is(Unqualified!T == real))
    {
        if (mode == 'f')
            count = snprintf(buffer.ptr, buffer.length, "%.*Lf".ptr, precision, cast(real) value);
        else if (mode == 'e')
            count = snprintf(buffer.ptr, buffer.length, "%.*Le".ptr, precision, cast(real) value);
        else
            count = snprintf(buffer.ptr, buffer.length, "%.*Lg".ptr, precision, cast(real) value);
    }
    else
    {
        if (mode == 'f')
            count = snprintf(buffer.ptr, buffer.length, "%.*f".ptr, precision, cast(double) value);
        else if (mode == 'e')
            count = snprintf(buffer.ptr, buffer.length, "%.*e".ptr, precision, cast(double) value);
        else
            count = snprintf(buffer.ptr, buffer.length, "%.*g".ptr, precision, cast(double) value);
    }

    if (count < 0 || cast(size_t) count >= buffer.length)
        writer.put("<float-format-error>");
    else
        writer.put(buffer[0 .. cast(size_t) count]);
}

private void writePointer(ref Writer writer, const(void)* pointer)
{
    if (pointer is null)
    {
        writer.put("null");
        return;
    }
    writeInteger(
        writer,
        cast(size_t) pointer,
        16,
        true,
        false,
        cast(ushort)(size_t.sizeof * 2),
    );
}

struct IntegerFormat(T)
{
nothrow @nogc:

    T value;
    ubyte radix = 10;
    bool prefix;
    bool uppercase;
    ushort minimumDigits = 1;

    void formatTo(ref Writer writer) const
    {
        writeInteger(writer, value, radix, prefix, uppercase, minimumDigits);
    }

    IntegerFormat digits(ushort count) const
    {
        IntegerFormat result = this;
        result.minimumDigits = count;
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

IntegerFormat!(UnqualifiedValue!T) radix(T)(T value, ubyte base)
{
    static assert(__traits(isIntegral, T) && T.sizeof <= ulong.sizeof);
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
    int precision;

    void formatTo(ref Writer writer) const
    {
        writeFloat(writer, value, mode, precision);
    }
}

FloatFormat!(UnqualifiedValue!T) fixed(T)(T value, int precision = 6)
{
    return FloatFormat!(UnqualifiedValue!T)(value, 'f', precision);
}

FloatFormat!(UnqualifiedValue!T) scientific(T)(T value, int precision = 6)
{
    return FloatFormat!(UnqualifiedValue!T)(value, 'e', precision);
}

private void writeFormat(
    string pattern,
    size_t position,
    size_t argument,
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
            writeFormat!(pattern, position + 2, argument)(writer, args);
        }
        else static if (position + 1 < pattern.length && pattern[position + 1] == '}')
        {
            static assert(argument < Args.length, "not enough format arguments");
            writeValue(writer, args[argument]);
            writeFormat!(pattern, position + 2, argument + 1)(writer, args);
        }
        else
            static assert(false, "format placeholders must be {} or {{");
    }
    else static if (pattern[position] == '}')
    {
        static if (position + 1 < pattern.length && pattern[position + 1] == '}')
        {
            writer.put('}');
            writeFormat!(pattern, position + 2, argument)(writer, args);
        }
        else
            static assert(false, "unmatched } in format string");
    }
    else
    {
        enum next = nextSpecial(pattern, position);
        writer.put(pattern[position .. next]);
        writeFormat!(pattern, next, argument)(writer, args);
    }
}

private size_t nextSpecial(string pattern, size_t start)
pure @safe
{
    size_t result = start;
    while (result < pattern.length && pattern[result] != '{' && pattern[result] != '}')
        ++result;
    return result;
}

version (unittest) private struct WriterTestSinkState
{
    char[256] storage;
    size_t length;
    size_t maxPerCall = size_t.max;
    size_t successfulCallLimit = size_t.max;
    size_t calls;
    const(u8)* firstPointer;
    size_t firstLength;
    bool reject;
}

version (unittest) private size_t writerTestSink(
    void* context,
    scope const(u8)[] bytes,
)
@trusted
{
    import core.stdc.string : memcpy;

    WriterTestSinkState* state = cast(WriterTestSinkState*) context;
    if (state is null || state.reject || bytes.length == 0 ||
        state.calls >= state.successfulCallLimit)
        return 0;

    if (state.calls == 0)
    {
        state.firstPointer = bytes.ptr;
        state.firstLength = bytes.length;
    }

    size_t amount = bytes.length < state.maxPerCall
        ? bytes.length : state.maxPerCall;
    const available = state.storage.length - state.length;
    if (amount > available)
        amount = available;
    if (amount == 0)
        return 0;

    memcpy(state.storage.ptr + state.length, bytes.ptr, amount);
    state.length += amount;
    ++state.calls;
    return amount;
}

unittest
{
    static assert(!__traits(compiles, {
            WriterTestSinkState state;
            Writer first = Writer.fromSink(&writerTestSink, &state);
            Writer second = first;
        }));

    static assert(!__traits(compiles, {
            WriterTestSinkState state;
            Writer first = Writer.fromSink(&writerTestSink, &state);
            Writer second = Writer.fromSink(&writerTestSink, &state);
            second = first;
        }));

    WriterTestSinkState state;
    state.maxPerCall = 2;
    Writer writer = Writer.fromSink(&writerTestSink, &state);
    writer.write("x=", 42, ", ", cast(dchar) 'λ');
    assert(writer.ok);
    assert(writer.written == 8);
    assert(state.length == 8);
    assert(state.storage[0 .. state.length] == "x=42, λ");
    assert(state.calls > 1);

    writer.writeln();
    assert(state.storage[state.length - 1] == '\n');
    assert(writer.result.written == state.length);

    state.reject = true;
    const before = writer.written;
    writer.put("rejected");
    assert(!writer.ok);
    assert(writer.written == before);
    writer.put("ignored");
    assert(writer.written == before);
}

unittest
{
    static assert(!__traits(compiles, {
            WriterTestSinkState state;
            Writer destination = Writer.fromSink(&writerTestSink, &state);
            char[8] storage;
            BufferedWriter first = BufferedWriter.create(&destination, storage[]);
            BufferedWriter second = first;
        }));

    static assert(!__traits(compiles, {
            WriterTestSinkState state;
            Writer destination = Writer.fromSink(&writerTestSink, &state);
            char[8] firstStorage;
            char[8] secondStorage;
            BufferedWriter first = BufferedWriter.create(&destination, firstStorage[]);
            BufferedWriter second = BufferedWriter.create(&destination, secondStorage[]);
            second = first;
        }));

    WriterTestSinkState state;
    Writer destination = Writer.fromSink(&writerTestSink, &state);
    char[8] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.write("ab", "cd", "ef");
    assert(output.ok);
    assert(output.written == 6);
    assert(buffered.ok);
    assert(buffered.pending == 6);
    assert(destination.written == 0);
    assert(state.calls == 0);

    assert(buffered.flush());
    assert(buffered.pending == 0);
    assert(destination.written == 6);
    assert(state.calls == 1);
    assert(state.storage[0 .. state.length] == "abcdef");
}

unittest
{
    WriterTestSinkState state;
    Writer destination = Writer.fromSink(&writerTestSink, &state);
    char[4] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.write("ab", "cd", "ef");
    assert(output.ok);
    assert(state.calls == 1);
    assert(state.storage[0 .. state.length] == "abcd");
    assert(buffered.pending == 2);

    assert(buffered.flush());
    assert(state.calls == 2);
    assert(state.storage[0 .. state.length] == "abcdef");
}

unittest
{
    WriterTestSinkState state;
    Writer destination = Writer.fromSink(&writerTestSink, &state);
    char[4] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();
    String large = "0123456789";

    output.put(large);
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(destination.written == large.length);
    assert(state.calls == 1);
    assert(state.firstPointer == cast(const(u8)*) large.ptr);
    assert(state.firstLength == large.length);
    assert(state.storage[0 .. state.length] == large);
}

unittest
{
    WriterTestSinkState state;
    Writer destination = Writer.fromSink(&writerTestSink, &state);
    char[4] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();
    String exactCapacity = "abcd";

    output.put(exactCapacity);
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(destination.written == exactCapacity.length);
    assert(state.calls == 1);
    assert(state.firstPointer == cast(const(u8)*) exactCapacity.ptr);
    assert(state.firstLength == exactCapacity.length);
    assert(state.storage[0 .. state.length] == exactCapacity);
}

unittest
{
    WriterTestSinkState state;
    Writer destination = Writer.fromSink(&writerTestSink, &state);
    char[4] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.put("ab");
    output.put("0123456789");
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(state.calls == 2);
    assert(state.storage[0 .. state.length] == "ab0123456789");
}

unittest
{
    WriterTestSinkState state;
    state.maxPerCall = 2;
    Writer destination = Writer.fromSink(&writerTestSink, &state);
    char[8] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.put("abcdef");
    assert(state.calls == 0);
    assert(buffered.flush());
    assert(state.calls == 3);
    assert(destination.written == 6);
    assert(state.storage[0 .. state.length] == "abcdef");
}

unittest
{
    WriterTestSinkState state;
    state.maxPerCall = 2;
    state.successfulCallLimit = 1;
    Writer destination = Writer.fromSink(&writerTestSink, &state);
    char[8] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.put("abcd");
    assert(output.ok);
    assert(buffered.pending == 4);

    assert(!buffered.flush());
    assert(!buffered.ok);
    assert(destination.written == 2);
    assert(buffered.pending == 2);
    assert(staging[0 .. 2] == "cd");
    assert(state.storage[0 .. state.length] == "ab");

    const acceptedBefore = output.written;
    output.put("ignored");
    assert(!output.ok);
    assert(output.written == acceptedBefore);
    assert(buffered.pending == 2);
}

unittest
{
    WriterTestSinkState state;
    Writer destination = Writer.fromSink(&writerTestSink, &state);
    char[] noStaging;
    BufferedWriter buffered = BufferedWriter.create(&destination, noStaging);
    Writer output = buffered.writer();

    output.put("direct");
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(state.calls == 1);
    assert(state.storage[0 .. state.length] == "direct");
    assert(buffered.flush());
}

unittest
{
    WriterTestSinkState state;
    Writer destination = Writer.fromSink(&writerTestSink, &state);
    char[8] staging;

    {
        BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
        Writer output = buffered.writer();
        output.put("pending");
        assert(buffered.pending == 7);
    }

    // BufferedWriter has no destructor-side flush. Buffering policy remains
    // explicit and cannot unexpectedly perform output during scope teardown.
    assert(state.calls == 0);
    assert(destination.written == 0);
}
