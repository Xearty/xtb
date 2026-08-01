module xtb.core.print;

import core.stdc.stdio : FILE, fflush, fwrite, snprintf, stderr, stdout;
import core.stdc.string : memcpy;
import xtb.core.string : String, StringBuf, append, clear, equal, tryAppend;
import xtb.core.memory : Allocator;
import xtb.core.panic : panic, require;

alias Sink = size_t function(void* context, scope String bytes) nothrow @nogc;

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
    enum bufferSize = 512;

    private Sink sink_;
    private void* context_;
    private char[bufferSize] buffer_;
    private size_t buffered_;
    private size_t written_;
    private bool failed_;

    static Writer fromSink(Sink sink, void* context) nothrow @nogc
    {
        Writer result;
        result.sink_ = sink;
        result.context_ = context;
        result.failed_ = sink is null;
        return result;
    }

    static Writer fromFile(FILE* file) nothrow @nogc
    {
        return fromSink(&fileSink, cast(void*) file);
    }

    bool ok() const pure nothrow @safe @nogc
    {
        return !failed_;
    }

    size_t written() const pure nothrow @safe @nogc
    {
        return written_;
    }

    void put(char value) nothrow @nogc
    {
        if (failed_)
            return;
        if (buffered_ == buffer_.length)
            flush();
        if (!failed_)
            buffer_[buffered_++] = value;
    }

    void put(scope String bytes) nothrow @nogc
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
            const amount = available < remaining ? available : remaining;
            memcpy(buffer_.ptr + buffered_, bytes.ptr + offset, amount);
            buffered_ += amount;
            offset += amount;
            if (buffered_ == buffer_.length)
                flush();
        }
    }

    void repeat(char value, size_t count) nothrow @nogc
    {
        foreach (_; 0 .. count)
            put(value);
    }

    void flush() nothrow @nogc
    {
        if (failed_ || buffered_ == 0)
            return;
        emit(buffer_[0 .. buffered_]);
        buffered_ = 0;
    }

    WriteResult finish() nothrow @nogc
    {
        flush();
        return WriteResult(!failed_, written_);
    }

    void value(T)(auto ref T value) nothrow @nogc
    {
        writeValue(this, value);
    }

    private void emit(scope String bytes) nothrow @nogc
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

private size_t fileSink(void* context, scope String bytes) nothrow @nogc
{
    FILE* file = cast(FILE*) context;
    if (file is null)
        return 0;
    return fwrite(bytes.ptr, 1, bytes.length, file);
}

private size_t stringBufSink(void* context, scope String bytes) nothrow @nogc
{
    StringBuf* buffer = cast(StringBuf*) context;
    if (buffer is null)
        return 0;
    (*buffer).append(bytes);
    return bytes.length;
}

private size_t fallibleStringBufSink(
    void* context,
    scope String bytes,
) nothrow @nogc
{
    StringBuf* buffer = cast(StringBuf*) context;
    return buffer !is null && (*buffer).tryAppend(bytes) ? bytes.length : 0;
}

private struct FixedBufferState
{
    char[] destination;
    size_t written;
    size_t required;
    bool overflow;
}

private size_t fixedBufferSink(void* context, scope String bytes) nothrow @nogc
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

WriteResult write(Args...)(auto ref Args args) nothrow @nogc
{
    return writeFile(cast(FILE*) stdout, args);
}

WriteResult writeln(Args...)(auto ref Args args) nothrow @nogc
{
    return writelnFile(cast(FILE*) stdout, args);
}

WriteResult ewrite(Args...)(auto ref Args args) nothrow @nogc
{
    return writeFile(cast(FILE*) stderr, args);
}

WriteResult ewriteln(Args...)(auto ref Args args) nothrow @nogc
{
    return writelnFile(cast(FILE*) stderr, args);
}

WriteResult writeFile(Args...)(FILE* file, auto ref Args args)
nothrow @nogc
{
    Writer writer = Writer.fromFile(file);
    static foreach (i; 0 .. Args.length)
        writeValue(writer, args[i]);
    return writer.finish();
}

WriteResult writelnFile(Args...)(FILE* file, auto ref Args args)
nothrow @nogc
{
    Writer writer = Writer.fromFile(file);
    static foreach (i; 0 .. Args.length)
        writeValue(writer, args[i]);
    writer.put('\n');
    return writer.finish();
}

WriteResult writeTo(Args...)(ref StringBuf buffer, auto ref Args args)
nothrow @nogc
{
    Writer writer = Writer.fromSink(&stringBufSink, &buffer);
    static foreach (i; 0 .. Args.length)
        writeValue(writer, args[i]);
    return writer.finish();
}

BufferWriteResult writeBuffer(Args...)(char[] destination, auto ref Args args)
nothrow @nogc
{
    FixedBufferState state;
    state.destination = destination;
    if (destination.length != 0)
        destination[0] = '\0';

    Writer writer = Writer.fromSink(&fixedBufferSink, &state);
    static foreach (i; 0 .. Args.length)
        writeValue(writer, args[i]);
    const result = writer.finish();
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
) nothrow @nogc
{
    FixedBufferState state;
    state.destination = destination;
    if (destination.length != 0)
        destination[0] = '\0';

    Writer writer = Writer.fromSink(&fixedBufferSink, &state);
    writeFormat!(pattern, 0, 0)(writer, args);
    const result = writer.finish();
    return BufferWriteResult(
        result.ok && !state.overflow,
        state.overflow || state.required > state.written,
        state.written,
        state.required,
    );
}

bool tryFormatString(string pattern, Args...)(
    Allocator* allocator,
    StringBuf* output,
    auto ref Args args,
) nothrow @nogc
{
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

StringBuf formatString(string pattern, Args...)(
    Allocator* allocator,
    auto ref Args args,
) nothrow @nogc
{
    StringBuf result;
    if (!tryFormatString!pattern(allocator, &result, args))
        panic("String formatting failed");
    return result;
}

bool flushStdout() nothrow @nogc
{
    return fflush(cast(FILE*) stdout) == 0;
}

bool flushStderr() nothrow @nogc
{
    return fflush(cast(FILE*) stderr) == 0;
}

private template Unqualified(T)
{
    alias Unqualified = typeof(cast() T.init);
}

private void writeValue(T)(ref Writer writer, auto ref T value)
nothrow @nogc
{
    alias U = Unqualified!T;
    static if (__traits(compiles, value.formatTo(writer)))
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
) nothrow @nogc
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
nothrow @nogc
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
nothrow @nogc
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

private void writeCodePoint(ref Writer writer, dchar codePoint) nothrow @nogc
{
    if (codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF))
        codePoint = 0xFFFD;
    char[4] bytes;
    size_t count;
    if (codePoint <= 0x7F)
    {
        bytes[0] = cast(char) codePoint;
        count = 1;
    }
    else if (codePoint <= 0x7FF)
    {
        bytes[0] = cast(char)(0xC0 | (codePoint >> 6));
        bytes[1] = cast(char)(0x80 | (codePoint & 0x3F));
        count = 2;
    }
    else if (codePoint <= 0xFFFF)
    {
        bytes[0] = cast(char)(0xE0 | (codePoint >> 12));
        bytes[1] = cast(char)(0x80 | ((codePoint >> 6) & 0x3F));
        bytes[2] = cast(char)(0x80 | (codePoint & 0x3F));
        count = 3;
    }
    else
    {
        bytes[0] = cast(char)(0xF0 | (codePoint >> 18));
        bytes[1] = cast(char)(0x80 | ((codePoint >> 12) & 0x3F));
        bytes[2] = cast(char)(0x80 | ((codePoint >> 6) & 0x3F));
        bytes[3] = cast(char)(0x80 | (codePoint & 0x3F));
        count = 4;
    }
    writer.put(bytes[0 .. count]);
}

struct IntegerFormat(T)
{
    T value;
    ubyte radix = 10;
    bool prefix;
    bool uppercase;
    ushort minimumDigits = 1;

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writeInteger(writer, value, radix, prefix, uppercase, minimumDigits);
    }

    IntegerFormat digits(ushort count) const nothrow @nogc
    {
        IntegerFormat result = this;
        result.minimumDigits = count;
        return result;
    }

    IntegerFormat upper() const nothrow @nogc
    {
        IntegerFormat result = this;
        result.uppercase = true;
        return result;
    }
}

IntegerFormat!T radix(T)(T value, ubyte base) nothrow @nogc
{
    static assert(__traits(isIntegral, T) && T.sizeof <= ulong.sizeof);
    IntegerFormat!T result;
    result.value = value;
    result.radix = base;
    return result;
}

IntegerFormat!T binary(T)(T value) nothrow @nogc
{
    IntegerFormat!T result = radix(value, 2);
    result.prefix = true;
    return result;
}

IntegerFormat!T hexadecimal(T)(T value) nothrow @nogc
{
    IntegerFormat!T result = radix(value, 16);
    result.prefix = true;
    return result;
}

struct FloatFormat(T)
{
    T value;
    char mode;
    int precision;

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writeFloat(writer, value, mode, precision);
    }
}

FloatFormat!T fixed(T)(T value, int precision = 6) nothrow @nogc
{
    return FloatFormat!T(value, 'f', precision);
}

FloatFormat!T scientific(T)(T value, int precision = 6) nothrow @nogc
{
    return FloatFormat!T(value, 'e', precision);
}

WriteResult format(string pattern, Args...)(auto ref Args args)
nothrow @nogc
{
    Writer writer = Writer.fromFile(cast(FILE*) stdout);
    writeFormat!(pattern, 0, 0)(writer, args);
    return writer.finish();
}

WriteResult formatln(string pattern, Args...)(auto ref Args args)
nothrow @nogc
{
    Writer writer = Writer.fromFile(cast(FILE*) stdout);
    writeFormat!(pattern, 0, 0)(writer, args);
    writer.put('\n');
    return writer.finish();
}

WriteResult formatTo(string pattern, Args...)(
    ref StringBuf buffer,
    auto ref Args args,
) nothrow @nogc
{
    Writer writer = Writer.fromSink(&stringBufSink, &buffer);
    writeFormat!(pattern, 0, 0)(writer, args);
    return writer.finish();
}

private void writeFormat(
    string pattern,
    size_t position,
    size_t argument,
    Args...,
)(ref Writer writer, auto ref Args args) nothrow @nogc
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
pure nothrow @safe @nogc
{
    size_t result = start;
    while (result < pattern.length && pattern[result] != '{' && pattern[result] != '}')
        ++result;
    return result;
}

nothrow @nogc unittest
{
    import xtb.core.memory : mallocAllocator;

    StringBuf buffer = StringBuf.create(mallocAllocator());
    buffer.writeTo("answer=", 42, ", hex=", hexadecimal(255));
    assert(buffer.view.equal("answer=42, hex=0xff"));
    buffer.clear();
    buffer.formatTo!"{} + {} = {}"(2, 3, 5);
    assert(buffer.view.equal("2 + 3 = 5"));

    char[8] fixedBuffer;
    const result = fixedBuffer[].writeBuffer("abcdefghi");
    assert(result.ok);
    assert(result.truncated);
    assert(result.written == 7);
    assert(result.required == 9);
    assert(fixedBuffer[7] == '\0');

    StringBuf allocated = formatString!"{}:{}"(mallocAllocator(), "item", 9);
    assert(allocated.view.equal("item:9"));

    struct StatefulValue
    {
        size_t* calls;

        void formatTo(ref Writer writer) nothrow @nogc
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
    assert(stateful.view.equal("stateful"));
    assert(calls == 1);
}
