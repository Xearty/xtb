module xtb.core.print;

nothrow @nogc:

import core.stdc.stdio : FILE, fflush, fwrite, snprintf, stderr, stdout;
import core.stdc.string : memcpy;
import core.interpolation : InterpolatedExpression, InterpolatedLiteral,
    InterpolationFooter, InterpolationHeader;
import xtb.core.string;
import xtb.core.memory : Allocator;
import xtb.core.panic : panic;
version (XTB_Checked)
    import xtb.core.panic : require;
import xtb.core.types : u8;
import xtb.core.utf8 : encodeUtf8, floorCodePointBoundary, isValidUtf8;

alias Sink = size_t function(void* context, scope const(u8)[] bytes);

version (unittest) private template InterpolationTestSequence(Values...)
{
    alias InterpolationTestSequence = Values;
}

struct WriteResult
{
    bool ok;
    size_t written;
}

struct BufferWriteResult
{
    bool ok;
    bool truncated;
    size_t written;
    size_t required;
}

struct Writer
{
nothrow @nogc:

    enum bufferSize = 512;

    private Sink sink_;
    private void* context_;
    private char[bufferSize] buffer_;
    private size_t buffered_;
    private size_t written_;
    private bool failed_;

    static Writer fromSink(Sink sink, void* context)
    {
        Writer result;
        result.sink_ = sink;
        result.context_ = context;
        result.failed_ = sink is null;
        return result;
    }

    static Writer fromFile(FILE* file)
    {
        return fromSink(&fileSink, cast(void*) file);
    }

    bool ok() const pure @safe
    {
        return !failed_;
    }

    size_t written() const pure @safe
    {
        return written_;
    }

    void put(char value)
    {
        version (XTB_Checked)
            require(cast(u8) value <= 0x7f,
                "non-ASCII char written as a complete code point; use dchar");
        if (failed_)
            return;
        if (buffered_ == buffer_.length)
            flush();
        if (!failed_)
            buffer_[buffered_++] = value;
    }

    void put(scope String bytes)
    {
        if (failed_ || bytes.length == 0)
            return;

        size_t offset;
        while (offset < bytes.length && !failed_)
        {
            if (buffered_ == 0 && bytes.length - offset >= buffer_.length)
            {
                emit(bytes[offset .. $]);
                return;
            }

            const available = buffer_.length - buffered_;
            const remaining = bytes.length - offset;
            size_t amount = available < remaining ? available : remaining;

            if (amount < remaining)
            {
                const boundary = bytes.floorCodePointBoundary(offset + amount);
                amount = boundary - offset;
                if (amount == 0)
                {
                    flush();
                    continue;
                }
            }

            memcpy(buffer_.ptr + buffered_, bytes.ptr + offset, amount);
            buffered_ += amount;
            offset += amount;
            if (buffered_ == buffer_.length)
                flush();
        }
    }

    void repeat(char value, size_t count)
    {
        foreach (_; 0 .. count)
            put(value);
    }

    void flush()
    {
        if (failed_ || buffered_ == 0)
            return;
        emit(buffer_[0 .. buffered_]);
        buffered_ = 0;
    }

    WriteResult finish()
    {
        flush();
        return WriteResult(!failed_, written_);
    }

    void value(T)(auto ref T value)
    {
        writeValue(this, value);
    }

    private void emit(scope String text)
    @trusted
    {
        emitBytes(cast(const(u8)[]) text);
    }

    private void emitBytes(scope const(u8)[] bytes)
    {
        size_t offset;
        while (offset < bytes.length)
        {
            const accepted = sink_(context_, bytes[offset .. $]);
            if (accepted == 0 || accepted > bytes.length - offset)
            {
                failed_ = true;
                return;
            }
            if (accepted > size_t.max - written_)
            {
                failed_ = true;
                return;
            }
            offset += accepted;
            written_ += accepted;
        }
    }
}

private size_t fileSink(void* context, scope const(u8)[] bytes)
{
    FILE* file = cast(FILE*) context;
    if (file is null)
        return 0;
    return fwrite(bytes.ptr, 1, bytes.length, file);
}

private size_t stringBufSink(void* context, scope const(u8)[] bytes)
{
    StringBuf* buffer = cast(StringBuf*) context;
    if (buffer is null)
        return 0;
    (*buffer).append(bytes.asStringUnchecked);
    return bytes.length;
}

private size_t fallibleStringBufSink(
    void* context,
    scope const(u8)[] bytes,
)
{
    StringBuf* buffer = cast(StringBuf*) context;
    return buffer !is null && (*buffer).tryAppend(bytes.asStringUnchecked)
        ? bytes.length : 0;
}

version (unittest) private struct Utf8ValidatingSinkState
{
    StringBuf* buffer;
    bool allFragmentsValid = true;
    size_t calls;
}

version (unittest) private size_t utf8ValidatingStringBufSink(
    void* context,
    scope const(u8)[] bytes,
)
{
    Utf8ValidatingSinkState* state = cast(Utf8ValidatingSinkState*) context;
    if (state is null || state.buffer is null)
        return 0;

    ++state.calls;
    if (!isValidUtf8(bytes))
    {
        state.allFragmentsValid = false;
        return 0;
    }

    (*state.buffer).append(bytes.asStringUnchecked);
    return bytes.length;
}

private struct FixedBufferState
{
    char[] destination;
    size_t written;
    size_t required;
    bool overflow;
}

private size_t fixedBufferSink(void* context, scope const(u8)[] bytes)
{
    FixedBufferState* state = cast(FixedBufferState*) context;
    if (state is null)
        return 0;

    if (bytes.length > size_t.max - state.required)
        state.overflow = true;
    else
        state.required += bytes.length;

    const capacity = state.destination.length == 0
        ? 0 : state.destination.length - 1;
    if (state.written < capacity)
    {
        const available = capacity - state.written;
        const amount = bytes.length < available ? bytes.length : available;
        if (amount != 0)
            memcpy(state.destination.ptr + state.written, bytes.ptr, amount);
        state.written += amount;
    }
    if (state.destination.length != 0)
        state.destination[state.written] = '\0';

    return bytes.length;
}

private void finishFixedBuffer(FixedBufferState* state)
@trusted
{
    version (XTB_Checked)
        require(state !is null, "fixed buffer state is null");
    while (state.written != 0 &&
        !isValidUtf8(cast(String) state.destination[0 .. state.written]))
        --state.written;
    if (state.destination.length != 0)
        state.destination[state.written] = '\0';
}

WriteResult write(Args...)(auto ref Args args)
{
    return writeFile(cast(FILE*) stdout, args);
}

WriteResult writeln(Args...)(auto ref Args args)
{
    return writelnFile(cast(FILE*) stdout, args);
}

WriteResult ewrite(Args...)(auto ref Args args)
{
    return writeFile(cast(FILE*) stderr, args);
}

WriteResult ewriteln(Args...)(auto ref Args args)
{
    return writelnFile(cast(FILE*) stderr, args);
}

WriteResult writeFile(Args...)(FILE* file, auto ref Args args)
{
    Writer writer = Writer.fromFile(file);
    writeArguments(writer, args);
    return writer.finish();
}

WriteResult writelnFile(Args...)(FILE* file, auto ref Args args)
{
    Writer writer = Writer.fromFile(file);
    writeArguments(writer, args);
    writer.put('\n');
    return writer.finish();
}

WriteResult writeTo(Args...)(ref StringBuf buffer, auto ref Args args)
{
    Writer writer = Writer.fromSink(&stringBufSink, &buffer);
    writeArguments(writer, args);
    return writer.finish();
}

BufferWriteResult writeBuffer(Args...)(char[] destination, auto ref Args args)
{
    FixedBufferState state;
    state.destination = destination;
    if (destination.length != 0)
        destination[0] = '\0';

    Writer writer = Writer.fromSink(&fixedBufferSink, &state);
    writeArguments(writer, args);
    const result = writer.finish();
    finishFixedBuffer(&state);
    return BufferWriteResult(
        result.ok && !state.overflow,
        state.overflow || state.required > state.written,
        state.written,
        state.required,
    );
}

BufferWriteResult formatBuffer(string pattern, Args...)(
    char[] destination,
    auto ref Args args,
)
{
    FixedBufferState state;
    state.destination = destination;
    if (destination.length != 0)
        destination[0] = '\0';

    Writer writer = Writer.fromSink(&fixedBufferSink, &state);
    writeFormat!(pattern, 0, 0)(writer, args);
    const result = writer.finish();
    finishFixedBuffer(&state);
    return BufferWriteResult(
        result.ok && !state.overflow,
        state.overflow || state.required > state.written,
        state.written,
        state.required,
    );
}

BufferWriteResult formatBuffer(Sequence...)(
    char[] destination,
    InterpolationHeader,
    auto ref Sequence sequence,
    InterpolationFooter,
)
{
    return destination.writeBuffer(sequence);
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
    *output = StringBuf.create(allocator);
    Writer writer = Writer.fromSink(&fallibleStringBufSink, output);
    writeFormat!(pattern, 0, 0)(writer, args);
    if (!writer.finish().ok)
    {
        output.deinit();
        return false;
    }
    return true;
}

bool tryFormatString(Sequence...)(
    Allocator* allocator,
    StringBuf* output,
    InterpolationHeader,
    auto ref Sequence sequence,
    InterpolationFooter,
)
{
    version (XTB_Checked)
        require(output !is null, "StringBuf output pointer is null");
    output.deinit();
    *output = StringBuf.create(allocator);
    Writer writer = Writer.fromSink(&fallibleStringBufSink, output);
    writeArguments(writer, sequence);
    if (!writer.finish().ok)
    {
        output.deinit();
        return false;
    }
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
    return result;
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
    return result;
}

bool flushStdout()
{
    return fflush(cast(FILE*) stdout) == 0;
}

bool flushStderr()
{
    return fflush(cast(FILE*) stderr) == 0;
}

private template Unqualified(T)
{
    alias Unqualified = typeof(cast() T.init);
}

private void writeArguments(Args...)(ref Writer writer, auto ref Args args)
{
    static foreach (i; 0 .. Args.length)
        writeValue(writer, args[i]);
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
    else static if (is(U == StringBuf))
    {
        writer.put(value.view);
    }
    else static if (__traits(compiles, value.formatTo(writer)))
    {
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
        writeCodePoint(writer, cast(dchar) value);
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
                "; define `void formatTo(ref Writer) nothrow @nogc`");
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

    char[65] reversed;
    size_t count;
    String digits = uppercase
        ? "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" : "0123456789abcdefghijklmnopqrstuvwxyz";
    do
    {
        reversed[count++] = digits[cast(size_t)(magnitude % radix)];
        magnitude /= radix;
    }
    while (magnitude != 0);

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

    const total = count < minimumDigits ? minimumDigits : count;
    foreach (i; 0 .. total)
    {
        const fromRight = total - i;
        writer.put(fromRight > count ? '0' : reversed[fromRight - 1]);
    }
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

private void writeCodePoint(ref Writer writer, dchar codePoint)
{
    const encoded = encodeUtf8(codePoint);
    const codeUnits = encoded.codeUnits;
    writer.put(codeUnits[0 .. encoded.byteLength]);
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

IntegerFormat!(Unqualified!T) radix(T)(T value, ubyte base)
{
    static assert(__traits(isIntegral, T) && T.sizeof <= ulong.sizeof);
    IntegerFormat!(Unqualified!T) result;
    result.value = value;
    result.radix = base;
    return result;
}

IntegerFormat!(Unqualified!T) binary(T)(T value)
{
    IntegerFormat!(Unqualified!T) result = radix(value, 2);
    result.prefix = true;
    return result;
}

IntegerFormat!(Unqualified!T) hexadecimal(T)(T value)
{
    IntegerFormat!(Unqualified!T) result = radix(value, 16);
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

FloatFormat!(Unqualified!T) fixed(T)(T value, int precision = 6)
{
    return FloatFormat!(Unqualified!T)(value, 'f', precision);
}

FloatFormat!(Unqualified!T) scientific(T)(T value, int precision = 6)
{
    return FloatFormat!(Unqualified!T)(value, 'e', precision);
}

WriteResult format(string pattern, Args...)(auto ref Args args)
{
    Writer writer = Writer.fromFile(cast(FILE*) stdout);
    writeFormat!(pattern, 0, 0)(writer, args);
    return writer.finish();
}

WriteResult format(Sequence...)(
    InterpolationHeader,
    auto ref Sequence sequence,
    InterpolationFooter,
)
{
    Writer writer = Writer.fromFile(cast(FILE*) stdout);
    writeArguments(writer, sequence);
    return writer.finish();
}

WriteResult formatln(string pattern, Args...)(auto ref Args args)
{
    Writer writer = Writer.fromFile(cast(FILE*) stdout);
    writeFormat!(pattern, 0, 0)(writer, args);
    writer.put('\n');
    return writer.finish();
}

WriteResult formatln(Sequence...)(
    InterpolationHeader,
    auto ref Sequence sequence,
    InterpolationFooter,
)
{
    Writer writer = Writer.fromFile(cast(FILE*) stdout);
    writeArguments(writer, sequence);
    writer.put('\n');
    return writer.finish();
}

WriteResult formatTo(string pattern, Args...)(
    ref StringBuf buffer,
    auto ref Args args,
)
{
    Writer writer = Writer.fromSink(&stringBufSink, &buffer);
    writeFormat!(pattern, 0, 0)(writer, args);
    return writer.finish();
}

WriteResult formatTo(Sequence...)(
    ref StringBuf buffer,
    InterpolationHeader,
    auto ref Sequence sequence,
    InterpolationFooter,
)
{
    Writer writer = Writer.fromSink(&stringBufSink, &buffer);
    writeArguments(writer, sequence);
    return writer.finish();
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

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        mallocAllocator;

    StringBuf buffer = StringBuf.create(mallocAllocator());
    buffer.writeTo("answer=", 42, ", hex=", hexadecimal(255));
    assert(buffer == "answer=42, hex=0xff");
    const uint constantInteger = 255;
    const double constantFloat = 1.25;
    buffer.clear();
    buffer.writeTo(
        hexadecimal(constantInteger).upper,
        ", ",
        fixed(constantFloat, 2),
    );
    assert(buffer == "0XFF, 1.25");
    buffer.clear();
    buffer.formatTo!"{} + {} = {}"(2, 3, 5);
    assert(buffer == "2 + 3 = 5");

    // Put a four-byte scalar across the staging-buffer boundary. Writer must
    // flush before the scalar so every StringBuf append receives valid UTF-8.
    char[511] splitScalarPrefix;
    splitScalarPrefix[] = 'a';
    const String splitScalarPrefixString = splitScalarPrefix[];

    buffer.clear();
    Utf8ValidatingSinkState validatingState =
        Utf8ValidatingSinkState(&buffer);
    Writer validatingWriter = Writer.fromSink(
        &utf8ValidatingStringBufSink,
        &validatingState,
    );
    validatingWriter.put(splitScalarPrefixString);
    validatingWriter.put("🙂");
    assert(validatingWriter.finish().ok);
    assert(validatingState.allFragmentsValid);
    assert(validatingState.calls == 2);
    assert(buffer.byteLength == 515);
    assert(buffer.view[0 .. 511] == splitScalarPrefixString);
    assert(buffer.view[511 .. $] == "🙂");

    StringBuf fallibleSplitScalar;
    assert(tryFormatString!"{}{}"(
        mallocAllocator(),
        &fallibleSplitScalar,
        splitScalarPrefixString,
        "🙂",
    ));
    assert(fallibleSplitScalar.byteLength == 515);
    assert(fallibleSplitScalar.view[511 .. $] == "🙂");

    char[8] fixedBuffer;
    const result = fixedBuffer[].writeBuffer("abcdefghi");
    assert(result.ok);
    assert(result.truncated);
    assert(result.written == 7);
    assert(result.required == 9);
    assert(fixedBuffer[7] == '\0');

    char[4] truncatedScalar;
    const scalarResult = truncatedScalar[].writeBuffer("A🙂");
    assert(scalarResult.ok);
    assert(scalarResult.truncated);
    assert(scalarResult.written == 1);
    assert(scalarResult.required == 5);
    assert(truncatedScalar[0 .. 1] == "A");
    assert(truncatedScalar[1] == '\0');

    char[6] exactScalar;
    const exactScalarResult = exactScalar[].writeBuffer("A🙂");
    assert(exactScalarResult.ok);
    assert(!exactScalarResult.truncated);
    assert(exactScalarResult.written == 5);
    assert(exactScalarResult.required == 5);
    assert(exactScalar[0 .. 5] == "A🙂");

    StringBuf allocated = formatString!"{}:{}"(mallocAllocator(), "item", 9);
    assert(allocated == "item:9");
    buffer.clear();
    buffer.writeTo("owned=", allocated);
    assert(buffer == "owned=item:9");

    struct StatefulValue
    {
    nothrow @nogc:

        size_t* calls;

        void formatTo(ref Writer writer)
        {
            ++*calls;
            writer.put("stateful");
        }
    }

    size_t calls;
    StatefulValue value = StatefulValue(&calls);
    StringBuf stateful = formatString!"{}"(
        mallocAllocator(),
        value,
    );
    assert(stateful == "stateful");
    assert(calls == 1);

    int answer = 42;
    buffer.clear();
    buffer.writeTo(i"answer=$(answer), hex=$(hexadecimal(answer))");
    assert(buffer == "answer=42, hex=0x2a");

    struct CountedExpression
    {
    nothrow @nogc:

        size_t* evaluations;

        int evaluate()
        {
            ++*evaluations;
            return 7;
        }
    }

    size_t evaluations;
    CountedExpression counted = CountedExpression(&evaluations);
    buffer.clear();
    buffer.formatTo(i"once=$(counted.evaluate()), custom=$(value)");
    assert(buffer == "once=7, custom=stateful");
    assert(evaluations == 1);
    assert(calls == 2);

    buffer.clear();
    buffer.writeTo(i"outer [$(i"inner=$(answer)")] done");
    assert(buffer == "outer [inner=42] done");

    buffer.clear();
    buffer.writeTo("prefix ", i"$(answer)", " suffix");
    assert(buffer == "prefix 42 suffix");

    buffer.clear();
    buffer.writeTo(
        i"expanded=$(InterpolationTestSequence!(answer, answer))",
    );
    assert(buffer == "expanded=4242");

    buffer.clear();
    buffer.writeTo(i"");
    assert(buffer.empty);

    char[12] interpolatedFixed;
    const interpolatedFixedResult = interpolatedFixed[].formatBuffer(
        i"value=$(answer)",
    );
    assert(interpolatedFixedResult.ok);
    assert(!interpolatedFixedResult.truncated);
    assert(interpolatedFixedResult.written == 8);
    assert(interpolatedFixedResult.required == 8);
    assert(interpolatedFixed[0 .. 8] == "value=42");
    assert(interpolatedFixed[8] == '\0');

    char[8] truncatedInterpolation;
    const truncatedInterpolationResult = truncatedInterpolation[].formatBuffer(
        i"value=$(answer)",
    );
    assert(truncatedInterpolationResult.ok);
    assert(truncatedInterpolationResult.truncated);
    assert(truncatedInterpolationResult.written == 7);
    assert(truncatedInterpolationResult.required == 8);
    assert(truncatedInterpolation[0 .. 7] == "value=4");
    assert(truncatedInterpolation[7] == '\0');

    StringBuf interpolated = formatString(
        mallocAllocator(),
        i"owned: $(answer), $(fixed(1.25, 2))",
    );
    assert(interpolated == "owned: 42, 1.25");

    StringBuf fallibleInterpolated;
    assert(tryFormatString(
            mallocAllocator(),
            &fallibleInterpolated,
            i"try: $(binary(5))",
    ));
    assert(fallibleInterpolated == "try: 0b101");

    AllocationRecord[4] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    failing.failAfter(0);
    StringBuf failedInterpolated;
    assert(!tryFormatString(
            failing.allocator,
            &failedInterpolated,
            i"allocation required: $(answer)",
    ));
    assert(failedInterpolated.empty);
    assert(failing.clean);
}
