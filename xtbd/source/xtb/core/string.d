module xtb.core.string;

nothrow @nogc:

public import xtb.core.types : String;
public import xtb.core.utf8 : Utf8Error, Utf8ErrorKind, Utf8StringResult,
    asString;

import core.stdc.string : memcmp, memmove, strlen;
import xtb.core.types : u8;
import xtb.core.array : Array;
import xtb.core.array : appendArray = append;
import xtb.core.array : appendAssumeCapacityArray = appendAssumeCapacity;
import xtb.core.array : clearArray = clear;
import xtb.core.array : insertArray = insert;
import xtb.core.array : resetAndReleaseArray = resetAndRelease;
import xtb.core.array : reserveArray = reserve;
import xtb.core.array : resizeArray = resize;
import xtb.core.array : tryAppendArray = tryAppend;
import xtb.core.array : tryInsertArray = tryInsert;
import xtb.core.array : tryReserveArray = tryReserve;
import xtb.core.memory : Allocator, allocate, tryAllocate;
import xtb.core.hash : hashValue;
import xtb.core.panic : panic, require;
import xtb.core.utf8 : encodeUtf8, isCodePointBoundary, validateUtf8;

enum notFound = size_t.max;

alias SplitPredicate = size_t function(String rest, void* context);

/// Borrows bytes already proven to be valid UTF-8.
String asStringUnchecked(return scope const(u8)[] bytes)
pure @system
{
    return cast(String) bytes;
}

Utf8StringResult fromCString(const(char)* value) @system
{
    require(value !is null, "null C string");
    const candidate = value[0 .. strlen(value)];
    const error = validateUtf8(candidate);
    return error.failed
        ? Utf8StringResult(String.init, error) : Utf8StringResult(candidate, Utf8Error.init);
}

String fromCStringUnchecked(const(char)* value) @system
{
    require(value !is null, "null C string");
    return value[0 .. strlen(value)];
}

size_t byteLength(String value) pure @safe
{
    return value.length;
}

const(u8)[] bytes(return scope String value) pure @trusted
{
    return cast(const(u8)[]) value;
}

bool empty(String value) pure @safe
{
    return value.length == 0;
}

char frontCodeUnit(String value) @safe
{
    require(value.length != 0, "frontCodeUnit of empty String");
    return value[0];
}

char backCodeUnit(String value) @safe
{
    require(value.length != 0, "backCodeUnit of empty String");
    return value[value.length - 1];
}

bool equal(String left, String right) pure @trusted
{
    if (left.length != right.length)
        return false;
    return left.length == 0 || memcmp(left.ptr, right.ptr, left.length) == 0;
}

int compare(String left, String right) pure @trusted
{
    const common = left.length < right.length ? left.length : right.length;
    if (common != 0)
    {
        const comparison = memcmp(left.ptr, right.ptr, common);
        if (comparison < 0)
            return -1;
        if (comparison > 0)
            return 1;
    }
    return left.length < right.length ? -1 : left.length > right.length ? 1 : 0;
}

String sliceBytes(
    return scope String value,
    size_t beginByteOffset,
    size_t endByteOffset,
)
@safe
{
    require(beginByteOffset <= endByteOffset,
        "String byte slice begin exceeds end");
    require(endByteOffset <= value.length,
        "String byte slice end out of bounds");
    require(value.isCodePointBoundary(beginByteOffset),
        "String byte slice begins inside UTF-8 code point");
    require(value.isCodePointBoundary(endByteOffset),
        "String byte slice ends inside UTF-8 code point");
    return value[beginByteOffset .. endByteOffset];
}

String prefixBytes(return scope String value, size_t endByteOffset)
@safe
{
    return value.sliceBytes(0, endByteOffset);
}

String suffixBytes(return scope String value, size_t beginByteOffset)
@safe
{
    return value.sliceBytes(beginByteOffset, value.length);
}

size_t find(String value, String needle) pure @trusted
{
    if (needle.length == 0)
        return 0;
    if (needle.length > value.length)
        return notFound;

    foreach (i; 0 .. value.length - needle.length + 1)
    {
        if (value[i .. i + needle.length].equal(needle))
            return i;
    }
    return notFound;
}

size_t findCodeUnit(String value, char codeUnit) pure @safe
{
    foreach (byteOffset, candidate; value)
    {
        if (candidate == codeUnit)
            return byteOffset;
    }
    return notFound;
}

size_t findLast(String value, String needle) pure @trusted
{
    if (needle.length == 0)
        return value.length;
    if (needle.length > value.length)
        return notFound;

    size_t index = value.length - needle.length + 1;
    while (index != 0)
    {
        --index;
        if (value[index .. index + needle.length].equal(needle))
            return index;
    }
    return notFound;
}

size_t findLastCodeUnit(String value, char codeUnit) pure @safe
{
    size_t byteOffset = value.length;
    while (byteOffset != 0)
    {
        --byteOffset;
        if (value[byteOffset] == codeUnit)
            return byteOffset;
    }
    return notFound;
}

size_t findCodePoint(String value, dchar codePoint) @safe
{
    const encoded = encodeUtf8(codePoint);
    const codeUnits = encoded.codeUnits;
    return value.find(codeUnits[0 .. encoded.byteLength]);
}

size_t findLastCodePoint(String value, dchar codePoint) @safe
{
    const encoded = encodeUtf8(codePoint);
    const codeUnits = encoded.codeUnits;
    return value.findLast(codeUnits[0 .. encoded.byteLength]);
}

String baseName(String value) pure @safe
{
    const slash = value.findLastCodeUnit('/');
    const backslash = value.findLastCodeUnit('\\');
    size_t separator = slash;
    if (separator == notFound ||
        (backslash != notFound && backslash > separator))
        separator = backslash;
    return separator == notFound ? value : value[separator + 1 .. $];
}

String stripExtension(String value) pure @safe
{
    const extension = value.findLastCodeUnit('.');
    const baseOffset = value.length - value.baseName.length;
    return extension == notFound || extension <= baseOffset
        ? value : value[0 .. extension];
}

bool contains(String value, String needle) pure @safe
{
    return value.find(needle) != notFound;
}

bool containsCodeUnit(String value, char codeUnit) pure @safe
{
    return value.findCodeUnit(codeUnit) != notFound;
}

bool containsCodePoint(String value, dchar codePoint) @safe
{
    return value.findCodePoint(codePoint) != notFound;
}

bool containsNul(String value) pure @safe
{
    return value.containsCodeUnit('\0');
}

bool startsWith(String value, String prefix) pure @trusted
{
    return prefix.length <= value.length && value[0 .. prefix.length].equal(prefix);
}

bool endsWith(String value, String suffix) pure @trusted
{
    return suffix.length <= value.length &&
        value[value.length - suffix.length .. $].equal(suffix);
}

private bool isAsciiWhitespace(char value) pure @safe
{
    return value == ' ' || value == '\t' || value == '\n' ||
        value == '\r' || value == '\f' || value == '\v';
}

String trimAsciiStart(return scope String value) pure @safe
{
    size_t begin;
    while (begin < value.length && isAsciiWhitespace(value[begin]))
        ++begin;
    return value[begin .. $];
}

String trimAsciiEnd(return scope String value) pure @safe
{
    size_t end = value.length;
    while (end != 0 && isAsciiWhitespace(value[end - 1]))
        --end;
    return value[0 .. end];
}

String trimAscii(return scope String value) pure @safe
{
    return value.trimAsciiStart().trimAsciiEnd();
}

bool tryCopy(String value, Allocator* allocator, String* output)
{
    require(output !is null, "String output pointer is null");
    if (value.length == size_t.max)
        return false;
    char* destination = allocator.tryAllocate!char(value.length + 1);
    if (destination is null)
        return false;
    if (value.length != 0)
        memmove(destination, value.ptr, value.length);
    destination[value.length] = '\0';
    *output = destination[0 .. value.length];
    return true;
}

String copy(String value, Allocator* allocator)
{
    String result;
    if (!value.tryCopy(allocator, &result))
        panic("String allocation failed");
    return result;
}

bool tryConcat(
    String left,
    String right,
    Allocator* allocator,
    String* output,
)
{
    require(output !is null, "String output pointer is null");
    if (right.length > size_t.max - left.length)
        return false;
    const length = left.length + right.length;
    if (length == size_t.max)
        return false;
    char* destination = allocator.tryAllocate!char(length + 1);
    if (destination is null)
        return false;
    if (left.length != 0)
        memmove(destination, left.ptr, left.length);
    if (right.length != 0)
        memmove(destination + left.length, right.ptr, right.length);
    destination[length] = '\0';
    *output = destination[0 .. length];
    return true;
}

String concat(String left, String right, Allocator* allocator)
{
    String result;
    if (!left.tryConcat(right, allocator, &result))
        panic("String allocation failed");
    return result;
}

bool tryReplace(
    String value,
    String from,
    String to,
    Allocator* allocator,
    String* output,
)
{
    require(output !is null, "String output pointer is null");
    if (from.length == 0)
        return value.tryCopy(allocator, output);

    size_t count;
    size_t position;
    while (position <= value.length)
    {
        const found = value[position .. $].find(from);
        if (found == notFound)
            break;
        ++count;
        position += found + from.length;
    }

    size_t length = value.length;
    if (to.length >= from.length)
    {
        const growth = to.length - from.length;
        if (growth != 0 && count > (size_t.max - length) / growth)
            return false;
        length += count * growth;
    }
    else
        length -= count * (from.length - to.length);

    if (length == size_t.max)
        return false;
    char* destination = allocator.tryAllocate!char(length + 1);
    if (destination is null)
        return false;
    size_t sourceOffset;
    size_t destinationOffset;
    while (sourceOffset < value.length)
    {
        const found = value[sourceOffset .. $].find(from);
        if (found == notFound)
        {
            const remainder = value.length - sourceOffset;
            if (remainder != 0)
                memmove(destination + destinationOffset, value.ptr + sourceOffset, remainder);
            destinationOffset += remainder;
            break;
        }
        if (found != 0)
            memmove(destination + destinationOffset, value.ptr + sourceOffset, found);
        destinationOffset += found;
        if (to.length != 0)
            memmove(destination + destinationOffset, to.ptr, to.length);
        destinationOffset += to.length;
        sourceOffset += found + from.length;
    }
    destination[length] = '\0';
    *output = destination[0 .. length];
    return true;
}

String replace(String value, String from, String to, Allocator* allocator)
{
    String result;
    if (!value.tryReplace(from, to, allocator, &result))
        panic("String allocation failed");
    return result;
}

bool tryJoin(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
    String* output,
)
{
    require(output !is null, "String output pointer is null");
    size_t length;
    foreach (value; values)
    {
        if (value.length > size_t.max - length)
            return false;
        length += value.length;
    }
    if (values.length > 1)
    {
        const count = values.length - 1;
        if (separator.length != 0 && count > (size_t.max - length) / separator.length)
            return false;
        length += count * separator.length;
    }
    if (length == size_t.max)
        return false;

    char* destination = allocator.tryAllocate!char(length + 1);
    if (destination is null)
        return false;
    size_t offset;
    foreach (index, value; values)
    {
        if (index != 0 && separator.length != 0)
        {
            memmove(destination + offset, separator.ptr, separator.length);
            offset += separator.length;
        }
        if (value.length != 0)
        {
            memmove(destination + offset, value.ptr, value.length);
            offset += value.length;
        }
    }
    destination[length] = '\0';
    *output = destination[0 .. length];
    return true;
}

String join(scope const(String)[] values, String separator, Allocator* allocator)
{
    String result;
    if (!tryJoin(values, separator, allocator, &result))
        panic("String allocation failed");
    return result;
}

private char escapedCharacter(char value) pure @safe
{
    switch (value)
    {
        case '\a':
            return 'a';
        case '\b':
            return 'b';
        case '\x1b':
            return 'e';
        case '\f':
            return 'f';
        case '\n':
            return 'n';
        case '\r':
            return 'r';
        case '\t':
            return 't';
        case '\v':
            return 'v';
        case '\\':
            return '\\';
        case '\'':
            return '\'';
        case '"':
            return '"';
        case '?':
            return '?';
        default:
            return '\0';
    }
}

bool tryEscape(String value, Allocator* allocator, String* output)
{
    require(output !is null, "String output pointer is null");
    size_t escapedCount;
    foreach (character; value)
        if (escapedCharacter(character) != '\0')
            ++escapedCount;
    if (escapedCount > size_t.max - value.length)
        return false;
    const length = value.length + escapedCount;
    if (length == size_t.max)
        return false;
    char* destination = allocator.tryAllocate!char(length + 1);
    if (destination is null)
        return false;
    size_t offset;
    foreach (character; value)
    {
        const escaped = escapedCharacter(character);
        if (escaped != '\0')
        {
            destination[offset++] = '\\';
            destination[offset++] = escaped;
        }
        else
            destination[offset++] = character;
    }
    destination[length] = '\0';
    *output = destination[0 .. length];
    return true;
}

String escape(String value, Allocator* allocator)
{
    String result;
    if (!value.tryEscape(allocator, &result))
        panic("String allocation failed");
    return result;
}

bool trySplitWhen(
    String value,
    SplitPredicate predicate,
    void* context,
    bool discardEmpty,
    Allocator* allocator,
    Array!String* output,
)
{
    require(predicate !is null, "split predicate is null");
    require(output !is null, "split output is null");
    *output = Array!String.create(allocator);

    size_t tokenBegin;
    size_t index;
    while (index < value.length)
    {
        const skip = predicate(value[index .. $], context);
        require(skip <= value.length - index, "split predicate skipped past input");
        if (skip == 0)
        {
            ++index;
            continue;
        }

        String token = value[tokenBegin .. index];
        if ((!discardEmpty || token.length != 0) &&
            !tryAppendArray(*output, token))
        {
            (*output).deinit();
            return false;
        }
        index += skip;
        tokenBegin = index;
    }

    String token = value[tokenBegin .. $];
    if ((!discardEmpty || token.length != 0) &&
        !tryAppendArray(*output, token))
    {
        (*output).deinit();
        return false;
    }
    return true;
}

Array!String splitWhen(
    String value,
    SplitPredicate predicate,
    void* context,
    bool discardEmpty,
    Allocator* allocator,
)
{
    Array!String result;
    if (!value.trySplitWhen(predicate, context, discardEmpty, allocator, &result))
        panic("String split allocation failed");
    return result;
}

private size_t stringSeparator(String rest, void* context)
{
    String separator = *cast(String*) context;
    return rest.startsWith(separator) ? separator.length : 0;
}

private size_t characterSeparator(String rest, void* context)
{
    return rest.length != 0 && rest[0] == *cast(char*) context ? 1 : 0;
}

private bool isAsciiWhitespacePublic(char value) pure @safe
{
    return isAsciiWhitespace(value);
}

private size_t whitespaceSeparator(String rest, void*)
{
    size_t count;
    while (count < rest.length && isAsciiWhitespacePublic(rest[count]))
        ++count;
    return count;
}

Array!String split(String value, String separator, Allocator* allocator)
{
    require(separator.length != 0, "String separator must not be empty");
    return value.splitWhen(&stringSeparator, &separator, false, allocator);
}

Array!String split(String value, char separator, Allocator* allocator)
{
    return value.splitWhen(&characterSeparator, &separator, false, allocator);
}

Array!String splitWhitespace(String value, Allocator* allocator)
{
    return value.splitWhen(&whitespaceSeparator, null, true, allocator);
}

Array!String splitLines(String value, Allocator* allocator)
{
    return value.split('\n', allocator);
}

struct StringBuf
{
nothrow @nogc:

    private Array!char bytes_;

    @disable this(this);

    static StringBuf create(Allocator* allocator)
    {
        StringBuf result;
        result.bytes_ = Array!char.create(allocator);
        return result;
    }

    static StringBuf withCapacity(Allocator* allocator, size_t byteCapacity)

    {
        StringBuf result;
        result.bytes_ = Array!char.withCapacity(allocator, byteCapacity);
        return result;
    }

    static StringBuf fromString(Allocator* allocator, String value)

    {
        StringBuf result = withCapacity(allocator, value.length);
        result.append(value);
        return result;
    }

    static bool tryFromString(
        Allocator* allocator,
        String value,
        StringBuf* output,
    )
    {
        require(output !is null, "StringBuf output pointer is null");
        *output = create(allocator);
        return (*output).tryAppend(value);
    }

    /// Copies arbitrary bytes without validating UTF-8.
    static StringBuf fromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    )
    @system
    {
        StringBuf result;
        if (!tryFromBytesUnchecked(allocator, bytes, &result))
            panic("StringBuf allocation failed");
        return result;
    }

    /// Fallible counterpart to `fromBytesUnchecked`.
    static bool tryFromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        StringBuf* output,
    )
    @system
    {
        require(output !is null, "StringBuf output pointer is null");
        *output = create(allocator);
        return (*output).bytes_.tryAppendArray(bytes.asStringUnchecked);
    }

    package(xtb) static StringBuf adopt(
        Allocator* allocator,
        char* data,
        size_t length,
        size_t capacity,
    )
    {
        StringBuf result;
        result.bytes_ = Array!char.adopt(allocator, data, length, capacity);
        return result;
    }

    void deinit()
    {
        bytes_.deinit();
    }

    size_t byteLength() const pure @safe
    {
        return bytes_.length;
    }

    size_t byteCapacity() const pure @safe
    {
        return bytes_.capacity;
    }

    bool empty() const pure @safe
    {
        return bytes_.empty;
    }

    Allocator* allocator() return
    {
        return bytes_.allocator;
    }

    String view() const return pure @trusted
    {
        return bytes_.slice;
    }

    bool opEquals(scope String other) const pure @trusted
    {
        return view.equal(other);
    }

    bool opEquals(scope ref const StringBuf other) const pure @trusted
    {
        return view.equal(other.view);
    }

    size_t toHash() const pure @trusted
    {
        return hashValue(view);
    }
}

void reserve(ref StringBuf buffer, size_t byteCapacity)
{
    buffer.bytes_.reserveArray(byteCapacity);
}

bool tryReserve(ref StringBuf buffer, size_t byteCapacity)
{
    return buffer.bytes_.tryReserveArray(byteCapacity);
}

void append(ref StringBuf buffer, String value)
{
    buffer.bytes_.appendArray(value);
}

bool tryAppend(ref StringBuf buffer, String value)
{
    return buffer.bytes_.tryAppendArray(value);
}

void append(ref StringBuf buffer, char value)
{
    require(cast(u8) value <= 0x7f,
        "non-ASCII char appended to StringBuf; use dchar");
    buffer.bytes_.appendArray(value);
}

bool tryAppend(ref StringBuf buffer, char value)
{
    require(cast(u8) value <= 0x7f,
        "non-ASCII char appended to StringBuf; use dchar");
    return buffer.bytes_.tryAppendArray(value);
}

void append(ref StringBuf buffer, dchar value)
{
    if (!buffer.tryAppend(value))
        panic("StringBuf allocation failed");
}

bool tryAppend(ref StringBuf buffer, dchar value)
{
    const encoded = encodeUtf8(value);
    const codeUnits = encoded.codeUnits;
    return buffer.bytes_.tryAppendArray(codeUnits[0 .. encoded.byteLength]);
}

void appendAssumeCapacity(ref StringBuf buffer, String value)
{
    buffer.bytes_.appendAssumeCapacityArray(value);
}

void appendAssumeCapacity(ref StringBuf buffer, char value)
{
    require(cast(u8) value <= 0x7f,
        "non-ASCII char appended to StringBuf; use dchar");
    buffer.bytes_.appendAssumeCapacityArray(value);
}

void appendAssumeCapacity(ref StringBuf buffer, dchar value)
{
    const encoded = encodeUtf8(value);
    const codeUnits = encoded.codeUnits;
    buffer.bytes_.appendAssumeCapacityArray(codeUnits[0 .. encoded.byteLength]);
}

/// Appends a raw fragment belonging to a transaction that must finish as UTF-8.
package(xtb) bool tryAppendUtf8Fragment(
    ref StringBuf buffer,
    scope const(u8)[] bytes,
)
@system
{
    return buffer.bytes_.tryAppendArray(bytes.asStringUnchecked);
}

/// Panicking counterpart to `tryAppendUtf8Fragment`.
package(xtb) void appendUtf8Fragment(
    ref StringBuf buffer,
    scope const(u8)[] bytes,
)
@system
{
    if (!buffer.tryAppendUtf8Fragment(bytes))
        panic("StringBuf allocation failed");
}

bool tryInsert(ref StringBuf buffer, size_t byteOffset, String value)
{
    require(byteOffset <= buffer.byteLength,
        "StringBuf insertion byte offset out of bounds");
    require(buffer.view.isCodePointBoundary(byteOffset),
        "StringBuf insertion byte offset is inside UTF-8 code point");
    return buffer.bytes_.tryInsertArray(byteOffset, value);
}

void insert(ref StringBuf buffer, size_t byteOffset, String value)
{
    if (!buffer.tryInsert(byteOffset, value))
        panic("StringBuf allocation failed");
}

bool tryPrepend(ref StringBuf buffer, String value)
{
    return buffer.tryInsert(0, value);
}

void prepend(ref StringBuf buffer, String value)
{
    buffer.insert(0, value);
}

void truncateBytes(ref StringBuf buffer, size_t newByteLength)
{
    require(newByteLength <= buffer.byteLength,
        "StringBuf truncation byte length out of bounds");
    require(buffer.view.isCodePointBoundary(newByteLength),
        "StringBuf truncation splits UTF-8 code point");
    buffer.bytes_.resizeArray(newByteLength);
}

void clear(ref StringBuf buffer)
{
    buffer.bytes_.clearArray();
}

void resetAndRelease(ref StringBuf buffer)
{
    buffer.bytes_.resetAndReleaseArray();
}

bool tryEscape(ref StringBuf buffer, String value)
{
    bool aliasesBuffer;
    size_t sourceOffset;
    if (value.length != 0 && buffer.byteLength != 0)
    {
        const sourceAddress = cast(size_t) value.ptr;
        const beginAddress = cast(size_t) buffer.view.ptr;
        const byteOffset = sourceAddress - beginAddress;
        aliasesBuffer = sourceAddress >= beginAddress && byteOffset < buffer.byteLength;
        if (aliasesBuffer)
        {
            if (value.length > buffer.byteLength - byteOffset)
                return false;
            sourceOffset = byteOffset;
        }
    }

    size_t escapedCount;
    foreach (character; value)
        if (escapedCharacter(character) != '\0')
            ++escapedCount;
    if (escapedCount > size_t.max - value.length ||
        value.length + escapedCount > size_t.max - buffer.byteLength)
        return false;
    const required = buffer.byteLength + value.length + escapedCount;
    if (!buffer.tryReserve(required))
        return false;
    if (aliasesBuffer)
        value = buffer.view[sourceOffset .. sourceOffset + value.length];
    foreach (character; value)
    {
        const escaped = escapedCharacter(character);
        if (escaped != '\0')
        {
            buffer.appendAssumeCapacity('\\');
            buffer.appendAssumeCapacity(escaped);
        }
        else
            buffer.appendAssumeCapacity(character);
    }
    return true;
}

void appendEscaped(ref StringBuf buffer, String value)
{
    if (!buffer.tryEscape(value))
        panic("StringBuf allocation failed");
}

bool tryReplace(ref StringBuf buffer, String from, String to)
{
    require(from.length != 0, "replacement source must not be empty");
    String original = buffer.view;
    if (original.length != 0)
    {
        const begin = cast(size_t) original.ptr;
        const end = begin + original.length;
        const fromAddress = cast(size_t) from.ptr;
        const toAddress = cast(size_t) to.ptr;
        require(from.length == 0 || fromAddress < begin || fromAddress >= end,
            "replacement source aliases StringBuf");
        require(to.length == 0 || toAddress < begin || toAddress >= end,
            "replacement value aliases StringBuf");
    }
    size_t count;
    size_t position;
    while (position <= original.length)
    {
        const found = original[position .. $].find(from);
        if (found == notFound)
            break;
        ++count;
        position += found + from.length;
    }
    if (count == 0)
        return true;

    size_t newLength = original.length;
    if (to.length >= from.length)
    {
        const growth = to.length - from.length;
        if (growth != 0 && count > (size_t.max - newLength) / growth)
            return false;
        newLength += count * growth;
    }
    else
        newLength -= count * (from.length - to.length);
    if (!buffer.tryReserve(newLength))
        return false;

    const oldLength = original.length;
    if (newLength <= oldLength)
    {
        size_t readOffset;
        size_t writeOffset;
        while (readOffset < oldLength)
        {
            const found = buffer.view[readOffset .. oldLength].find(from);
            if (found == notFound)
            {
                const remaining = oldLength - readOffset;
                if (remaining != 0)
                    memmove(buffer.bytes_.slice.ptr + writeOffset,
                        buffer.bytes_.slice.ptr + readOffset, remaining);
                writeOffset += remaining;
                break;
            }
            if (found != 0)
                memmove(buffer.bytes_.slice.ptr + writeOffset,
                    buffer.bytes_.slice.ptr + readOffset, found);
            writeOffset += found;
            if (to.length != 0)
                memmove(buffer.bytes_.slice.ptr + writeOffset, to.ptr, to.length);
            writeOffset += to.length;
            readOffset += found + from.length;
        }
        buffer.bytes_.resizeArray(newLength);
        return true;
    }

    buffer.bytes_.resizeArray(newLength);
    size_t readEnd = oldLength;
    size_t writeEnd = newLength;
    while (readEnd != 0)
    {
        const found = buffer.view[0 .. readEnd].findLast(from);
        if (found == notFound)
        {
            if (readEnd != 0)
                memmove(buffer.bytes_.slice.ptr + writeEnd - readEnd,
                    buffer.bytes_.slice.ptr, readEnd);
            break;
        }
        const tailBegin = found + from.length;
        const tailLength = readEnd - tailBegin;
        writeEnd -= tailLength;
        if (tailLength != 0)
            memmove(buffer.bytes_.slice.ptr + writeEnd,
                buffer.bytes_.slice.ptr + tailBegin, tailLength);
        writeEnd -= to.length;
        if (to.length != 0)
            memmove(buffer.bytes_.slice.ptr + writeEnd, to.ptr, to.length);
        readEnd = found;
    }
    return true;
}

void replaceInPlace(ref StringBuf buffer, String from, String to)
{
    if (!buffer.tryReplace(from, to))
        panic("StringBuf allocation failed");
}

const(char)* cString(ref StringBuf buffer) @system
{
    const oldLength = buffer.byteLength;
    buffer.bytes_.resizeArray(oldLength + 1);
    buffer.bytes_[oldLength] = '\0';
    char* pointer = buffer.bytes_.slice.ptr;
    buffer.bytes_.resizeArray(oldLength);
    return pointer;
}

const(char)* checkedCString(ref StringBuf buffer) @system
{
    require(!buffer.view.containsNul, "String contains embedded NUL");
    return buffer.cString();
}

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        deallocate, mallocAllocator;

    String text = "  hello world  ";
    assert(text.trimAscii().equal("hello world"));
    assert(text.find("world") == 8);
    assert(text.startsWith("  he"));
    assert(text.endsWith("  "));
    assert("a/b/file.tar".baseName.equal("file.tar"));
    assert("a/b/file.tar".stripExtension.equal("a/b/file"));
    assert("a/b/.gitignore".stripExtension.equal("a/b/.gitignore"));
    assert("a/b/.config.json".stripExtension.equal("a/b/.config"));
    assert("one two one".findLast("one") == 8);
    assert("hello".frontCodeUnit == 'h' && "hello".backCodeUnit == 'o');
    assert("".empty);

    const cResult = fromCString("native".ptr);
    assert(cResult.succeeded && cResult.value.equal("native"));

    u8[5] encoded = ['a', 0xc3, 0xa9, 0, 'z'];
    String unchecked = encoded[].asStringUnchecked;
    assert(unchecked.ptr is cast(const(char)*) encoded.ptr);
    assert(unchecked.byteLength == encoded.length);
    assert(unchecked.findCodePoint(0xe9) == 1 && unchecked[3] == '\0');

    StringBuf copiedBytes = StringBuf.fromBytesUnchecked(
        mallocAllocator(),
        encoded[],
    );
    encoded[0] = 'b';
    assert(unchecked[0] == 'b');
    assert(copiedBytes.view[0] == 'a');
    assert(copiedBytes.view.findCodePoint(0xe9) == 1);
    assert(copiedBytes.view[3] == '\0');

    StringBuf emptyBytes = StringBuf.fromBytesUnchecked(
        mallocAllocator(),
        null,
    );
    assert(emptyBytes.empty);

    String escaped = "a\n\t\\b".escape(mallocAllocator());
    assert(escaped.equal("a\\n\\t\\\\b"));
    mallocAllocator().deallocate(cast(void*) escaped.ptr, escaped.length + 1);

    String replaced = "one two one".replace("one", "1", mallocAllocator());
    assert(replaced.equal("1 two 1"));
    mallocAllocator().deallocate(cast(void*) replaced.ptr, replaced.length + 1);

    String[3] parts = ["a", "b", "c"];
    String joined = parts[].join("/", mallocAllocator());
    assert(joined.equal("a/b/c"));
    mallocAllocator().deallocate(cast(void*) joined.ptr, joined.length + 1);

    Array!String tokens = "a::b::".split("::", mallocAllocator());
    assert(tokens.length == 3);
    assert(tokens[0].equal("a") && tokens[1].equal("b") && tokens[2].empty);
    Array!String words = "  alpha\t beta  ".splitWhitespace(mallocAllocator());
    assert(words.length == 2);
    assert(words[0].equal("alpha") && words[1].equal("beta"));

    StringBuf buffer = StringBuf.fromString(mallocAllocator(), "hello");
    assert(buffer == "hello");
    assert("hello" == buffer);
    assert(buffer != "other");

    char[5] mutableText = "hello";
    assert(buffer == mutableText[]);
    assert(mutableText[] == buffer);

    StringBuf same = StringBuf.fromString(mallocAllocator(), "hello");
    StringBuf different = StringBuf.fromString(mallocAllocator(), "Hello");
    assert(buffer == same && same == buffer);
    assert(buffer != different && different != buffer);
    assert(buffer.toHash == same.toHash);

    StringBuf emptyBuffer = StringBuf.create(mallocAllocator());
    String emptyString;
    assert(emptyBuffer == emptyString);
    assert(emptyString == emptyBuffer);

    buffer.append(',');
    buffer.append(" world");
    buffer.append(cast(dchar) 0x1f642);
    assert(buffer.view.endsWith("🙂"));
    buffer.truncateBytes(buffer.byteLength - "🙂".length);
    buffer.prepend("say: ");
    assert(buffer == "say: hello, world");
    buffer.replaceInPlace("world", "BetterC library");
    assert(buffer == "say: hello, BetterC library");
    buffer.replaceInPlace("BetterC library", "D");
    assert(buffer == "say: hello, D");
    buffer.appendEscaped("\n");
    assert(buffer.view.endsWith("\\n"));
    assert(buffer.cString()[buffer.byteLength] == '\0');

    StringBuf unicode = StringBuf.fromString(mallocAllocator(), "Aé🙂");
    assert(unicode.byteLength == 7);
    assert(unicode.byteCapacity >= unicode.byteLength);
    unicode.insert(3, "界");
    assert(unicode == "Aé界🙂");
    unicode.truncateBytes(6);
    assert(unicode == "Aé界");

    StringBuf selfPrepend = StringBuf.fromString(
        mallocAllocator(),
        "abcdefgh",
    );
    selfPrepend.prepend(selfPrepend.view);
    assert(selfPrepend == "abcdefghabcdefgh");

    StringBuf selfEscape = StringBuf.fromString(
        mallocAllocator(),
        "a\nbcdefg",
    );
    selfEscape.appendEscaped(selfEscape.view);
    assert(selfEscape == "a\nbcdefga\\nbcdefg");

    AllocationRecord[4] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(), records[],
    );
    failing.failAfter(0);
    String failedOutput = "unchanged";
    assert(!"copy".tryCopy(failing.handle, &failedOutput));
    assert(failedOutput.equal("unchanged"));

    StringBuf failedBytes;
    assert(!StringBuf.tryFromBytesUnchecked(
            failing.handle,
            encoded[],
            &failedBytes,
    ));
    assert(failedBytes.empty);
}
