module xtb.core.string;

nothrow @nogc:

public import xtb.core.types : String;
public import xtb.core.utf8 : Utf8Error, Utf8ErrorKind, Utf8StringResult,
    asString;

import core.lifetime : move;
import core.stdc.string : memcmp, memmove, strlen;
import xtb.core.types : u8;
import xtb.core.array : Array, ArrayUnmanaged, RawArrayStorage;
import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator, allocate, tryAllocate;
import xtb.core.hash : hashValue;
import xtb.core.panic : panic, require;
import xtb.core.utf8 : ceilCodePointBoundary, encodeUtf8,
    isCodePointBoundary, validateUtf8;

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
        if (memcmp(value.ptr + i, needle.ptr, needle.length) == 0)
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
        if (memcmp(value.ptr + index, needle.ptr, needle.length) == 0)
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
            index = value.ceilCodePointBoundary(index + 1);
            continue;
        }
        require(value.isCodePointBoundary(index + skip),
            "split predicate ended inside UTF-8 code point");

        String token = value[tokenBegin .. index];
        if ((!discardEmpty || token.length != 0) &&
            !(*output).tryAppend(token))
        {
            (*output).deinit();
            return false;
        }
        index += skip;
        tokenBegin = index;
    }

    String token = value[tokenBegin .. $];
    if ((!discardEmpty || token.length != 0) &&
        !(*output).tryAppend(token))
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
    require(cast(u8) separator <= 0x7f,
        "non-ASCII split separator; use String");
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

struct StringBufUnmanaged
{
nothrow @nogc:

private:
    ArrayUnmanaged!char bytes_;

public:
    @disable this(this);

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t byteCapacity,
        scope StringBufUnmanaged* output,
    )
    {
        require(output !is null,
            "StringBufUnmanaged output pointer is null");
        require(output.bytes_.capacity == 0,
            "StringBufUnmanaged output is not empty");
        StringBufUnmanaged temporary;
        if (!temporary.bytes_.tryReserve(allocator, byteCapacity))
            return false;
        *output = move(temporary);
        return true;
    }

    static StringBufUnmanaged withCapacity(
        Allocator* allocator,
        size_t byteCapacity,
    )
    {
        StringBufUnmanaged result;
        if (!tryWithCapacity(allocator, byteCapacity, &result))
            panic("StringBuf allocation failed");
        return result;
    }

    static bool tryFromString(
        Allocator* allocator,
        String value,
        scope StringBufUnmanaged* output,
    )
    {
        require(output !is null,
            "StringBufUnmanaged output pointer is null");
        require(output.bytes_.capacity == 0,
            "StringBufUnmanaged output is not empty");
        StringBufUnmanaged temporary;
        if (!temporary.tryAppend(allocator, value))
            return false;
        *output = move(temporary);
        return true;
    }

    static StringBufUnmanaged fromString(
        Allocator* allocator,
        String value,
    )
    {
        StringBufUnmanaged result;
        if (!tryFromString(allocator, value, &result))
            panic("StringBuf allocation failed");
        return result;
    }

    /// Copies bytes whose UTF-8 validity the caller has already proved.
    static StringBufUnmanaged fromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    ) @system
    {
        StringBufUnmanaged result;
        if (!tryFromBytesUnchecked(allocator, bytes, &result))
            panic("StringBuf allocation failed");
        return result;
    }

    /// Fallible counterpart to `fromBytesUnchecked`.
    static bool tryFromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        scope StringBufUnmanaged* output,
    ) @system
    {
        require(output !is null,
            "StringBufUnmanaged output pointer is null");
        require(output.bytes_.capacity == 0,
            "StringBufUnmanaged output is not empty");
        StringBufUnmanaged temporary;
        if (!temporary.bytes_.tryAppend(
                allocator,
                bytes.asStringUnchecked,
            ))
            return false;
        *output = move(temporary);
        return true;
    }

package(xtb):
    static StringBufUnmanaged adopt(
        char* data,
        size_t length,
        size_t capacity,
    ) @system
    {
        StringBufUnmanaged result;
        result.bytes_ = ArrayUnmanaged!char.adopt(data, length, capacity);
        return result;
    }

    /// Detaches storage whose allocation size is exactly the logical length.
    /// The returned descriptor owns its bytes but carries no allocator.
    String releaseExactStorage() @system
    {
        require(byteCapacity == byteLength,
            "StringBuf storage is not exact-sized");
        RawArrayStorage!char raw = bytes_.releaseRaw();
        return raw.data[0 .. raw.length];
    }

public:
    void deinit(Allocator* allocator)
    {
        bytes_.deinit(allocator);
    }

    void resetAndRelease(Allocator* allocator)
    {
        bytes_.resetAndRelease(allocator);
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

    String view() const return pure @trusted
    {
        return bytes_.slice;
    }

    bool opEquals(scope String other) const pure @trusted
    {
        return view.equal(other);
    }

    bool opEquals(scope ref const StringBufUnmanaged other) const pure @trusted
    {
        return view.equal(other.view);
    }

    size_t toHash() const pure @trusted
    {
        return hashValue(view);
    }

    void reserve(Allocator* allocator, size_t byteCapacity)
    {
        bytes_.reserve(allocator, byteCapacity);
    }

    bool tryReserve(Allocator* allocator, size_t byteCapacity)
    {
        return bytes_.tryReserve(allocator, byteCapacity);
    }

    bool tryShrinkToFit(Allocator* allocator)
    {
        return bytes_.tryShrinkToFit(allocator);
    }

    void shrinkToFit(Allocator* allocator)
    {
        bytes_.shrinkToFit(allocator);
    }

    void append(Allocator* allocator, String value)
    {
        bytes_.append(allocator, value);
    }

    bool tryAppend(Allocator* allocator, String value)
    {
        return bytes_.tryAppend(allocator, value);
    }

    void append(Allocator* allocator, char value)
    {
        require(cast(u8) value <= 0x7f,
            "non-ASCII char appended to StringBuf; use dchar");
        bytes_.append(allocator, value);
    }

    bool tryAppend(Allocator* allocator, char value)
    {
        require(cast(u8) value <= 0x7f,
            "non-ASCII char appended to StringBuf; use dchar");
        return bytes_.tryAppend(allocator, value);
    }

    void append(Allocator* allocator, dchar value)
    {
        if (!tryAppend(allocator, value))
            panic("StringBuf allocation failed");
    }

    bool tryAppend(Allocator* allocator, dchar value)
    {
        const encoded = encodeUtf8(value);
        const codeUnits = encoded.codeUnits;
        return bytes_.tryAppend(
            allocator,
            codeUnits[0 .. encoded.byteLength],
        );
    }

    void appendAssumeCapacity(String value)
    {
        bytes_.appendAssumeCapacity(value);
    }

    void appendAssumeCapacity(char value)
    {
        require(cast(u8) value <= 0x7f,
            "non-ASCII char appended to StringBuf; use dchar");
        bytes_.appendAssumeCapacity(value);
    }

    void appendAssumeCapacity(dchar value)
    {
        const encoded = encodeUtf8(value);
        const codeUnits = encoded.codeUnits;
        bytes_.appendAssumeCapacity(codeUnits[0 .. encoded.byteLength]);
    }

    bool tryInsert(
        Allocator* allocator,
        size_t byteOffset,
        String value,
    )
    {
        require(byteOffset <= byteLength,
            "StringBuf insertion byte offset out of bounds");
        require(view.isCodePointBoundary(byteOffset),
            "StringBuf insertion byte offset is inside UTF-8 code point");
        return bytes_.tryInsert(allocator, byteOffset, value);
    }

    void insert(
        Allocator* allocator,
        size_t byteOffset,
        String value,
    )
    {
        if (!tryInsert(allocator, byteOffset, value))
            panic("StringBuf allocation failed");
    }

    bool tryPrepend(Allocator* allocator, String value)
    {
        return tryInsert(allocator, 0, value);
    }

    void prepend(Allocator* allocator, String value)
    {
        insert(allocator, 0, value);
    }

    void truncateBytes(size_t newByteLength)
    {
        require(newByteLength <= byteLength,
            "StringBuf truncation byte length out of bounds");
        require(view.isCodePointBoundary(newByteLength),
            "StringBuf truncation splits UTF-8 code point");
        bytes_.removeRange(newByteLength, byteLength - newByteLength);
    }

    void clear()
    {
        bytes_.clear();
    }

    bool tryEscape(Allocator* allocator, String value)
    {
        bool aliasesBuffer;
        size_t sourceOffset;
        if (value.length != 0 && byteLength != 0)
        {
            const sourceAddress = cast(size_t) value.ptr;
            const beginAddress = cast(size_t) view.ptr;
            const byteOffset = sourceAddress - beginAddress;
            aliasesBuffer = sourceAddress >= beginAddress &&
                byteOffset < byteLength;
            if (aliasesBuffer)
            {
                if (value.length > byteLength - byteOffset)
                    return false;
                sourceOffset = byteOffset;
            }
        }

        size_t escapedCount;
        foreach (character; value)
            if (escapedCharacter(character) != '\0')
                ++escapedCount;
        if (escapedCount > size_t.max - value.length ||
            value.length + escapedCount > size_t.max - byteLength)
            return false;
        const required = byteLength + value.length + escapedCount;
        if (!tryReserve(allocator, required))
            return false;
        if (aliasesBuffer)
            value = view[sourceOffset .. sourceOffset + value.length];
        foreach (character; value)
        {
            const escaped = escapedCharacter(character);
            if (escaped != '\0')
            {
                appendAssumeCapacity('\\');
                appendAssumeCapacity(escaped);
            }
            else
                bytes_.appendAssumeCapacity(character);
        }
        return true;
    }

    void appendEscaped(Allocator* allocator, String value)
    {
        if (!tryEscape(allocator, value))
            panic("StringBuf allocation failed");
    }

    bool tryReplace(
        Allocator* allocator,
        String from,
        String to,
    )
    {
        require(from.length != 0,
            "replacement source must not be empty");
        String original = view;
        if (original.length != 0)
        {
            const begin = cast(size_t) original.ptr;
            const end = begin + original.length;
            const fromAddress = cast(size_t) from.ptr;
            const toAddress = cast(size_t) to.ptr;
            require(from.length == 0 || fromAddress < begin ||
                    fromAddress >= end,
                "replacement source aliases StringBuf");
            require(to.length == 0 || toAddress < begin ||
                    toAddress >= end,
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
        if (!tryReserve(allocator, newLength))
            return false;

        const oldLength = original.length;
        if (newLength <= oldLength)
        {
            size_t readOffset;
            size_t writeOffset;
            while (readOffset < oldLength)
            {
                const found = view[readOffset .. oldLength].find(from);
                if (found == notFound)
                {
                    const remaining = oldLength - readOffset;
                    if (remaining != 0)
                        memmove(bytes_.slice.ptr + writeOffset,
                            bytes_.slice.ptr + readOffset, remaining);
                    writeOffset += remaining;
                    break;
                }
                if (found != 0)
                    memmove(bytes_.slice.ptr + writeOffset,
                        bytes_.slice.ptr + readOffset, found);
                writeOffset += found;
                if (to.length != 0)
                    memmove(bytes_.slice.ptr + writeOffset,
                        to.ptr, to.length);
                writeOffset += to.length;
                readOffset += found + from.length;
            }
            bytes_.removeRange(newLength, oldLength - newLength);
            return true;
        }

        bytes_.resize(allocator, newLength);
        size_t readEnd = oldLength;
        size_t writeEnd = newLength;
        while (readEnd != 0)
        {
            const found = view[0 .. readEnd].findLast(from);
            if (found == notFound)
            {
                if (readEnd != 0)
                    memmove(bytes_.slice.ptr + writeEnd - readEnd,
                        bytes_.slice.ptr, readEnd);
                break;
            }
            const tailBegin = found + from.length;
            const tailLength = readEnd - tailBegin;
            writeEnd -= tailLength;
            if (tailLength != 0)
                memmove(bytes_.slice.ptr + writeEnd,
                    bytes_.slice.ptr + tailBegin, tailLength);
            writeEnd -= to.length;
            if (to.length != 0)
                memmove(bytes_.slice.ptr + writeEnd, to.ptr, to.length);
            readEnd = found;
        }
        return true;
    }

    void replaceInPlace(
        Allocator* allocator,
        String from,
        String to,
    )
    {
        if (!tryReplace(allocator, from, to))
            panic("StringBuf allocation failed");
    }

    /// Ensures a trailing NUL exists outside the logical string contents.
    ///
    /// The returned pointer remains valid only until this buffer is mutated or
    /// destroyed. Embedded NUL bytes are permitted; use `checkedCString` when
    /// the target C API must receive the complete logical string.
    bool tryCString(
        Allocator* allocator,
        scope const(char)** output,
    ) @system
    {
        require(output !is null, "C string output pointer is null");
        const oldLength = byteLength;
        if (oldLength == size_t.max ||
            !bytes_.tryResize(allocator, oldLength + 1))
            return false;

        bytes_[oldLength] = '\0';
        const(char)* result = bytes_.slice.ptr;
        bytes_.removeRange(oldLength, 1);
        *output = result;
        return true;
    }

    /// Panicking counterpart to `tryCString`.
    const(char)* cString(Allocator* allocator) return @system
    {
        const(char)* result;
        if (!tryCString(allocator, &result))
            panic("StringBuf allocation failed");
        return result;
    }

    /// Returns a C string after rejecting embedded NUL bytes.
    const(char)* checkedCString(Allocator* allocator) return @system
    {
        require(!view.containsNul, "String contains embedded NUL");
        return cString(allocator);
    }
}

struct StringBuf
{
nothrow @nogc:

    alias Self = StringBuf;
    alias Storage = StringBufUnmanaged;

private:
    Allocator* allocator_;
    Storage storage_;

public:
    mixin ManagedContainerAdapter!(Self, Storage);

package(xtb):
    static Self adoptUnmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        require(allocator !is null && *allocator !is null,
            "StringBuf allocator is null");
        require(storage !is null,
            "StringBufUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(*storage);
        return result;
    }

    static Self adoptRaw(
        Allocator* allocator,
        char* data,
        size_t length,
        size_t capacity,
    ) @system
    {
        Storage storage = Storage.adopt(data, length, capacity);
        return adoptUnmanaged(allocator, &storage);
    }

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
    buffer.appendEscaped(" café🙂");
    assert(buffer.view.endsWith(" café🙂"));
    const originalLength = buffer.byteLength;
    const(char)* terminated;
    assert(buffer.tryCString(&terminated));
    assert(buffer.byteLength == originalLength);
    assert(buffer.view == "say: hello, D\\n café🙂");
    assert(terminated[buffer.byteLength] == '\0');
    assert(buffer.checkedCString[buffer.byteLength] == '\0');

    buffer.append('!');
    terminated = buffer.cString;
    assert(buffer.view.endsWith("!"));
    assert(terminated[buffer.byteLength] == '\0');

    StringBuf unicode = StringBuf.fromString(mallocAllocator(), "Aé🙂");
    assert(unicode.byteLength == 7);
    assert(unicode.byteCapacity >= unicode.byteLength);
    unicode.insert(3, "界");
    assert(unicode == "Aé界🙂");
    unicode.truncateBytes(6);
    assert(unicode == "Aé界");

    StringBuf scalarWidths = StringBuf.withCapacity(mallocAllocator(), 1);
    scalarWidths.append(cast(dchar) 0x7f);
    scalarWidths.append(cast(dchar) 0x80);
    scalarWidths.append(cast(dchar) 0x800);
    scalarWidths.append(cast(dchar) 0x10000);
    assert(scalarWidths.view == "\x7f\u0080\u0800\U00010000");

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

    StringBuf failedScalar = StringBuf.create(failing.handle);
    assert(!failedScalar.tryAppend(cast(dchar) 0x1f642));
    assert(failedScalar.empty && failing.clean);

    const(char)* sentinel = cast(const(char)*) 1;
    const(char)* unchanged = sentinel;
    assert(!failedScalar.tryCString(&unchanged));
    assert(unchanged is sentinel);
    assert(failedScalar.empty && failing.clean);

    StringBuf emptyCString = StringBuf.create(mallocAllocator());
    const(char)* emptyPointer;
    assert(emptyCString.tryCString(&emptyPointer));
    assert(emptyPointer !is null && emptyPointer[0] == '\0');
    assert(emptyCString.empty);
}

unittest
{
    import xtb.core.memory : AllocationRecord, Allocator,
        InstrumentedAllocator, mallocAllocator;

    static assert(StringBufUnmanaged.sizeof == ArrayUnmanaged!char.sizeof);
    static assert(StringBuf.sizeof ==
        StringBufUnmanaged.sizeof + (Allocator*).sizeof);
    static assert(!__traits(isCopyable, StringBufUnmanaged));
    static assert(!__traits(isCopyable, StringBuf));
    static assert(!__traits(isCopyable, StringBuf.Released));
    static assert(!__traits(compiles, () @safe {
        StringBuf.Released released;
        ref StringBufUnmanaged storage = released.storage;
    }));

    StringBufUnmanaged zero;
    zero.deinit(null);
    zero.resetAndRelease(null);
    assert(zero.empty && zero.byteCapacity == 0);

    AllocationRecord[16] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    {
        StringBuf buffer = StringBuf.fromString(tracked.handle, "alpha");
        StringBuf.Released released = buffer.release();
        assert(buffer.allocator is null && buffer.empty);
        assert(released.allocator is tracked.handle);
        assert(released.storage.view == "alpha");

        released.storage.append(released.allocator, " beta");
        assert(released.storage.view == "alpha beta");
    }
    assert(tracked.clean);

    {
        StringBuf source = StringBuf.fromString(tracked.handle, "adopted");
        StringBuf.Released released = source.release();
        StringBuf adopted = StringBuf.adopt(&released);

        assert(source.allocator is null && source.empty);
        assert(released.allocator is null && released.storage.empty);
        assert(adopted.allocator is tracked.handle);
        assert(adopted.view == "adopted");
    }
    assert(tracked.clean);

    {
        StringBuf source = StringBuf.fromString(tracked.handle, "raw");
        StringBuf.Released released = source.release();
        Allocator* allocator;
        StringBufUnmanaged storage = released.extract(&allocator);

        assert(allocator is tracked.handle);
        assert(released.allocator is null && released.storage.empty);
        storage.append(allocator, " storage");
        assert(storage.view == "raw storage");
        storage.deinit(allocator);
    }
    assert(tracked.clean);
}

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        mallocAllocator;

    AllocationRecord[32] managedRecords;
    AllocationRecord[32] unmanagedRecords;
    InstrumentedAllocator managedAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        managedRecords[],
    );
    InstrumentedAllocator unmanagedAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        unmanagedRecords[],
    );

    StringBuf managed = StringBuf.create(managedAllocator.handle);
    StringBufUnmanaged unmanaged;

    assert(managed.tryAppend("alpha"));
    assert(unmanaged.tryAppend(unmanagedAllocator.handle, "alpha"));
    assert(managed.tryAppend(cast(dchar) 0x1f642));
    assert(unmanaged.tryAppend(
        unmanagedAllocator.handle,
        cast(dchar) 0x1f642,
    ));
    assert(managed.tryInsert(5, " beta"));
    assert(unmanaged.tryInsert(
        unmanagedAllocator.handle,
        5,
        " beta",
    ));
    assert(managed.tryReplace("alpha", "A"));
    assert(unmanaged.tryReplace(
        unmanagedAllocator.handle,
        "alpha",
        "A",
    ));
    assert(managed.tryReserve(128));
    assert(unmanaged.tryReserve(unmanagedAllocator.handle, 128));

    assert(managed.view == unmanaged.view);
    assert(managed.byteLength == unmanaged.byteLength);
    assert(managed.byteCapacity == unmanaged.byteCapacity);
    assert(managedAllocator.stats == unmanagedAllocator.stats);

    const managedStatsBeforeClear = managedAllocator.stats;
    const unmanagedStatsBeforeClear = unmanagedAllocator.stats;
    managed.clear();
    unmanaged.clear();
    assert(managedAllocator.stats == managedStatsBeforeClear);
    assert(unmanagedAllocator.stats == unmanagedStatsBeforeClear);

    managed.deinit();
    unmanaged.deinit(unmanagedAllocator.handle);
    assert(managedAllocator.stats == unmanagedAllocator.stats);
    assert(managedAllocator.clean && unmanagedAllocator.clean);
}
