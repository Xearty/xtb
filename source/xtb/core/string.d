module xtb.core.string;

nothrow @nogc:

public import xtb.core.types : String;
public import xtb.core.utf8 : Utf8Error, Utf8ErrorKind, Utf8StringResult,
    asString;

import xtb.core.lifetime : move, moveEmplace;
import core.stdc.string : memcmp, memmove, strlen;
import xtb.core.types : u8;
import xtb.core.array;
import xtb.core.memory : Allocator;
import xtb.core.hash : hashValue;
import xtb.core.panic : panic;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.released_storage : ReleasedStorage;
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
    version (XTB_Checked)
        require(value !is null, "null C string");
    const candidate = value[0 .. strlen(value)];
    const error = validateUtf8(candidate);
    return error.failed
        ? Utf8StringResult(String.init, error) : Utf8StringResult(candidate, Utf8Error.init);
}

String fromCStringUnchecked(const(char)* value) @system
{
    version (XTB_Checked)
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
    version (XTB_Checked)
        require(value.length != 0, "frontCodeUnit of empty String");
    return value[0];
}

char backCodeUnit(String value) @safe
{
    version (XTB_Checked)
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
    version (XTB_Checked)
    {
        require(beginByteOffset <= endByteOffset,
            "String byte slice begin exceeds end");
        require(endByteOffset <= value.length,
            "String byte slice end out of bounds");
        require(value.isCodePointBoundary(beginByteOffset),
            "String byte slice begins inside UTF-8 code point");
        require(value.isCodePointBoundary(endByteOffset),
            "String byte slice ends inside UTF-8 code point");
    }
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

package(xtb) char escapedCharacter(char value) pure @safe
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

bool trySplitWhen(
    String value,
    SplitPredicate predicate,
    void* context,
    bool discardEmpty,
    Allocator* allocator,
    Array!String* output,
)
{
    version (XTB_Checked)
    {
        require(predicate !is null, "split predicate is null");
        require(output !is null, "split output is null");
    }
    Array!String created = Array!String.create(allocator);
    moveEmplace(created, *output);

    size_t tokenBegin;
    size_t index;
    while (index < value.length)
    {
        const skip = predicate(value[index .. $], context);
        version (XTB_Checked)
            require(skip <= value.length - index, "split predicate skipped past input");
        if (skip == 0)
        {
            index = value.ceilCodePointBoundary(index + 1);
            continue;
        }
        version (XTB_Checked)
            require(value.isCodePointBoundary(index + skip),
                "split predicate ended inside UTF-8 code point");

        String token = value[tokenBegin .. index];
        if ((!discardEmpty || token.length != 0) &&
            !output.tryAppend(&token))
        {
            output.deinit();
            return false;
        }
        index += skip;
        tokenBegin = index;
    }

    String token = value[tokenBegin .. $];
    if ((!discardEmpty || token.length != 0) &&
        !output.tryAppend(&token))
    {
        output.deinit();
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
    version (XTB_Checked)
        require(separator.length != 0, "String separator must not be empty");
    return value.splitWhen(&stringSeparator, &separator, false, allocator);
}

Array!String split(String value, char separator, Allocator* allocator)
{
    version (XTB_Checked)
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

private bool stringsOverlap(scope String left, scope String right) pure @trusted
{
    if (left.length == 0 || right.length == 0)
        return false;

    const leftBegin = cast(size_t) left.ptr;
    const leftEnd = leftBegin + left.length;
    const rightBegin = cast(size_t) right.ptr;
    const rightEnd = rightBegin + right.length;
    return leftBegin < rightEnd && rightBegin < leftEnd;
}

/// Growable UTF-8 backing storage without embedded allocator context.
///
/// The value owns its allocation but every allocating or releasing operation
/// requires the originating allocator explicitly. Copying and generated
/// assignment are disabled.
struct StringBufUnmanaged
{
nothrow @nogc:

private:
    ArrayUnmanaged!char bytes_;

public:
    @disable this(this);
    @disable ref StringBufUnmanaged opAssign(StringBufUnmanaged source) return;

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t byteCapacity,
        scope StringBufUnmanaged* output,
    )
    {
        version (XTB_Checked)
        {
            require(output !is null,
                "StringBufUnmanaged output pointer is null");
            require(output.bytes_.capacity == 0,
                "StringBufUnmanaged output is not empty");
        }
        StringBufUnmanaged temporary;
        if (!temporary.bytes_.tryReserve(allocator, byteCapacity))
            return false;
        moveEmplace(temporary, *output);
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
        version (XTB_Checked)
        {
            require(output !is null,
                "StringBufUnmanaged output pointer is null");
            require(output.bytes_.capacity == 0,
                "StringBufUnmanaged output is not empty");
        }
        StringBufUnmanaged temporary;
        if (!temporary.tryAppend(allocator, value))
            return false;
        moveEmplace(temporary, *output);
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
        version (XTB_Checked)
        {
            require(output !is null,
                "StringBufUnmanaged output pointer is null");
            require(output.bytes_.capacity == 0,
                "StringBufUnmanaged output is not empty");
        }
        StringBufUnmanaged temporary;
        if (!temporary.bytes_.tryAppend(
                allocator,
                bytes.asStringUnchecked,
            ))
            return false;
        moveEmplace(temporary, *output);
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
        auto bytes = ArrayUnmanaged!char.adopt(data, length, capacity);
        moveEmplace(bytes, result.bytes_);
        return result;
    }

    /// Detaches storage whose allocation size is exactly the logical length.
    /// The returned token owns the allocation but carries no allocator.
    RawArrayStorage!char releaseExactStorage() @system
    {
        version (XTB_Checked)
            require(byteCapacity == byteLength,
                "StringBuf storage is not exact-sized");
        return bytes_.releaseRaw();
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

    String formatRepresentation() const return pure @trusted
    {
        return view;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.value(view);
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
        version (XTB_Checked)
            require(cast(u8) value <= 0x7f,
                "non-ASCII char appended to StringBuf; use dchar");
        bytes_.append(allocator, value);
    }

    bool tryAppend(Allocator* allocator, char value)
    {
        version (XTB_Checked)
            require(cast(u8) value <= 0x7f,
                "non-ASCII char appended to StringBuf; use dchar");
        return bytes_.tryAppend(allocator, &value);
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
        version (XTB_Checked)
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
        version (XTB_Checked)
        {
            require(byteOffset <= byteLength,
                "StringBuf insertion byte offset out of bounds");
            require(view.isCodePointBoundary(byteOffset),
                "StringBuf insertion byte offset is inside UTF-8 code point");
        }
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
        version (XTB_Checked)
        {
            require(newByteLength <= byteLength,
                "StringBuf truncation byte length out of bounds");
            require(view.isCodePointBoundary(newByteLength),
                "StringBuf truncation splits UTF-8 code point");
        }
        bytes_.removeRange(newByteLength, byteLength - newByteLength);
    }

    void clear()
    {
        bytes_.clear();
    }

    bool tryAppendEscaped(Allocator* allocator, String value)
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
        if (!tryAppendEscaped(allocator, value))
            panic("StringBuf allocation failed");
    }

    /// Replaces every non-overlapping match in this buffer.
    ///
    /// Aliased `from` and `to` views are snapshotted before any mutation. On
    /// allocation failure the buffer remains unchanged.
    bool tryReplaceInPlace(
        Allocator* allocator,
        String from,
        String to,
    )
    {
        if (from.length == 0)
            return true;

        StringBufUnmanaged fromSnapshot;
        scope (exit) fromSnapshot.deinit(allocator);
        if (stringsOverlap(view, from))
        {
            if (!StringBufUnmanaged.tryFromString(
                    allocator,
                    from,
                    &fromSnapshot,
                ))
                return false;
            from = fromSnapshot.view;
        }

        StringBufUnmanaged toSnapshot;
        scope (exit) toSnapshot.deinit(allocator);
        if (stringsOverlap(view, to))
        {
            if (!StringBufUnmanaged.tryFromString(
                    allocator,
                    to,
                    &toSnapshot,
                ))
                return false;
            to = toSnapshot.view;
        }

        String original = view;
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
        if (!tryReplaceInPlace(allocator, from, to))
            panic("StringBuf allocation failed");
    }

    /// Escapes this buffer in place.
    ///
    /// The operation reserves all required capacity before changing the
    /// logical contents, so allocation failure leaves the buffer unchanged.
    bool tryEscapeInPlace(Allocator* allocator)
    {
        const oldLength = byteLength;
        size_t escapedCount;
        foreach (character; view)
            if (escapedCharacter(character) != '\0')
                ++escapedCount;
        if (escapedCount == 0)
            return true;
        if (escapedCount > size_t.max - oldLength)
            return false;
        const newLength = oldLength + escapedCount;
        if (!tryReserve(allocator, newLength))
            return false;

        bytes_.resize(allocator, newLength);
        size_t readOffset = oldLength;
        size_t writeOffset = newLength;
        while (readOffset != 0)
        {
            const character = bytes_[--readOffset];
            const escaped = escapedCharacter(character);
            if (escaped != '\0')
            {
                bytes_[--writeOffset] = escaped;
                bytes_[--writeOffset] = '\\';
            }
            else
                bytes_[--writeOffset] = character;
        }
        return true;
    }

    void escapeInPlace(Allocator* allocator)
    {
        if (!tryEscapeInPlace(allocator))
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
        version (XTB_Checked)
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
        version (XTB_Checked)
            require(!view.containsNul, "String contains embedded NUL");
        return cString(allocator);
    }
}

struct StringBuf
{
nothrow @nogc:

    alias Self = StringBuf;
    alias Storage = StringBufUnmanaged;
    alias Released = ReleasedStorage!Storage;

private:
    Allocator* allocator_;
    Storage storage_;

    version (XTB_Checked)
    {
        invariant
        {
            require(&this !is null, "StringBuf pointer is null");
        }
    }

public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(Allocator* allocator) @trusted
    {
        requireValidStringBufAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t byteCapacity,
        scope Self* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "StringBuf output pointer is null");
            require(output.allocator_ is null,
                "StringBuf output is already initialized");
        }
        Storage storage;
        if (!Storage.tryWithCapacity(allocator, byteCapacity, &storage))
            return false;
        output.allocator_ = allocator;
        moveEmplace(storage, output.storage_);
        return true;
    }

    static Self withCapacity(
        Allocator* allocator,
        size_t byteCapacity,
    ) @trusted
    {
        Self result;
        if (!tryWithCapacity(allocator, byteCapacity, &result))
            panic("StringBuf allocation failed");
        return move(result);
    }

    static bool tryFromString(
        Allocator* allocator,
        String value,
        scope Self* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "StringBuf output pointer is null");
            require(output.allocator_ is null,
                "StringBuf output is already initialized");
        }
        Storage storage;
        if (!Storage.tryFromString(allocator, value, &storage))
            return false;
        output.allocator_ = allocator;
        moveEmplace(storage, output.storage_);
        return true;
    }

    static Self fromString(Allocator* allocator, String value) @trusted
    {
        Self result;
        if (!tryFromString(allocator, value, &result))
            panic("StringBuf allocation failed");
        return move(result);
    }

    static bool tryFromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        scope Self* output,
    ) @system
    {
        version (XTB_Checked)
        {
            require(output !is null, "StringBuf output pointer is null");
            require(output.allocator_ is null,
                "StringBuf output is already initialized");
        }
        Storage storage;
        if (!Storage.tryFromBytesUnchecked(allocator, bytes, &storage))
            return false;
        output.allocator_ = allocator;
        moveEmplace(storage, output.storage_);
        return true;
    }

    static Self fromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    ) @system
    {
        Self result;
        if (!tryFromBytesUnchecked(allocator, bytes, &result))
            panic("StringBuf allocation failed");
        return move(result);
    }

    static Self adopt(scope Released* released) @trusted
    {
        version (XTB_Checked)
            require(released !is null,
                "released StringBuf storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator_ = allocator;
        moveEmplace(storage, result.storage_);
        return move(result);
    }

    /// Releases all storage and unbinds the allocator. The zero state is valid.
    void deinit() @trusted
    {
        if (allocator_ is null)
            return;
        storage_.deinit(allocator_);
        allocator_ = null;
    }

    /// Releases allocated storage but keeps the allocator binding.
    void resetAndRelease() @trusted
    {
        storage_.resetAndRelease(allocator_);
    }

    /// Transfers allocator-bound storage out and leaves this buffer empty.
    Released release() @trusted
    {
        auto result = Released.fromOwnedParts(allocator_, &storage_);
        allocator_ = null;
        return move(result);
    }

    size_t byteLength() const pure @trusted
    {
        return storage_.byteLength;
    }

    size_t byteCapacity() const pure @trusted
    {
        return storage_.byteCapacity;
    }

    bool empty() const pure @trusted
    {
        return storage_.empty;
    }

    String view() const return pure @trusted
    {
        return storage_.view;
    }

    String formatRepresentation() const return pure @trusted
    {
        return view;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.value(view);
    }

    bool equal(scope String other) const pure @trusted
    {
        return storage_ == other;
    }

    bool equal(scope ref const Self other) const pure @trusted
    {
        return storage_ == other.storage_;
    }

    void reserve(size_t byteCapacity) @trusted
    {
        storage_.reserve(allocator_, byteCapacity);
    }

    bool tryReserve(size_t byteCapacity) @trusted
    {
        return storage_.tryReserve(allocator_, byteCapacity);
    }

    bool tryShrinkToFit() @trusted
    {
        return storage_.tryShrinkToFit(allocator_);
    }

    void shrinkToFit() @trusted
    {
        storage_.shrinkToFit(allocator_);
    }

    void append(String value) @trusted
    {
        storage_.append(allocator_, value);
    }

    bool tryAppend(String value) @trusted
    {
        return storage_.tryAppend(allocator_, value);
    }

    void append(char value) @trusted
    {
        storage_.append(allocator_, value);
    }

    bool tryAppend(char value) @trusted
    {
        return storage_.tryAppend(allocator_, value);
    }

    void append(dchar value) @trusted
    {
        storage_.append(allocator_, value);
    }

    bool tryAppend(dchar value) @trusted
    {
        return storage_.tryAppend(allocator_, value);
    }

    void appendAssumeCapacity(String value) @trusted
    {
        storage_.appendAssumeCapacity(value);
    }

    void appendAssumeCapacity(char value) @trusted
    {
        storage_.appendAssumeCapacity(value);
    }

    void appendAssumeCapacity(dchar value) @trusted
    {
        storage_.appendAssumeCapacity(value);
    }

    bool tryInsert(size_t byteOffset, String value) @trusted
    {
        return storage_.tryInsert(allocator_, byteOffset, value);
    }

    void insert(size_t byteOffset, String value) @trusted
    {
        storage_.insert(allocator_, byteOffset, value);
    }

    bool tryPrepend(String value) @trusted
    {
        return storage_.tryPrepend(allocator_, value);
    }

    void prepend(String value) @trusted
    {
        storage_.prepend(allocator_, value);
    }

    void truncateBytes(size_t newByteLength) @trusted
    {
        storage_.truncateBytes(newByteLength);
    }

    void clear() @trusted
    {
        storage_.clear();
    }

    bool tryAppendEscaped(String value) @trusted
    {
        return storage_.tryAppendEscaped(allocator_, value);
    }

    void appendEscaped(String value) @trusted
    {
        storage_.appendEscaped(allocator_, value);
    }

    bool tryReplaceInPlace(String from, String to) @trusted
    {
        return storage_.tryReplaceInPlace(allocator_, from, to);
    }

    void replaceInPlace(String from, String to) @trusted
    {
        storage_.replaceInPlace(allocator_, from, to);
    }

    bool tryEscapeInPlace() @trusted
    {
        return storage_.tryEscapeInPlace(allocator_);
    }

    void escapeInPlace() @trusted
    {
        storage_.escapeInPlace(allocator_);
    }

    bool tryCString(scope const(char)** output) @system
    {
        return storage_.tryCString(allocator_, output);
    }

    const(char)* cString() return @system
    {
        return storage_.cString(allocator_);
    }

    const(char)* checkedCString() return @system
    {
        return storage_.checkedCString(allocator_);
    }

    /// Returns the first UTF-8 code unit. The buffer must not be empty.
    char frontCodeUnit() const @trusted
    {
        return xtb.core.string.frontCodeUnit(storage_.view);
    }

    /// Returns the last UTF-8 code unit. The buffer must not be empty.
    char backCodeUnit() const @trusted
    {
        return xtb.core.string.backCodeUnit(storage_.view);
    }

    int compare(scope String other) const pure @trusted
    {
        return xtb.core.string.compare(storage_.view, other);
    }

    String sliceBytes(size_t beginByteOffset, size_t endByteOffset) const return @trusted
    {
        return xtb.core.string.sliceBytes(storage_.view, beginByteOffset, endByteOffset);
    }

    String prefixBytes(size_t endByteOffset) const return @trusted
    {
        return xtb.core.string.prefixBytes(storage_.view, endByteOffset);
    }

    String suffixBytes(size_t beginByteOffset) const return @trusted
    {
        return xtb.core.string.suffixBytes(storage_.view, beginByteOffset);
    }

    size_t find(scope String needle) const pure @trusted
    {
        return xtb.core.string.find(storage_.view, needle);
    }

    size_t findLast(scope String needle) const pure @trusted
    {
        return xtb.core.string.findLast(storage_.view, needle);
    }

    size_t findCodeUnit(char codeUnit) const pure @trusted
    {
        return xtb.core.string.findCodeUnit(storage_.view, codeUnit);
    }

    size_t findLastCodeUnit(char codeUnit) const pure @trusted
    {
        return xtb.core.string.findLastCodeUnit(storage_.view, codeUnit);
    }

    size_t findCodePoint(dchar codePoint) const @trusted
    {
        return xtb.core.string.findCodePoint(storage_.view, codePoint);
    }

    size_t findLastCodePoint(dchar codePoint) const @trusted
    {
        return xtb.core.string.findLastCodePoint(storage_.view, codePoint);
    }

    bool contains(scope String needle) const pure @trusted
    {
        return xtb.core.string.contains(storage_.view, needle);
    }

    bool containsCodeUnit(char codeUnit) const pure @trusted
    {
        return xtb.core.string.containsCodeUnit(storage_.view, codeUnit);
    }

    bool containsCodePoint(dchar codePoint) const @trusted
    {
        return xtb.core.string.containsCodePoint(storage_.view, codePoint);
    }

    bool containsNul() const pure @trusted
    {
        return xtb.core.string.containsNul(storage_.view);
    }

    bool startsWith(scope String prefix) const pure @trusted
    {
        return xtb.core.string.startsWith(storage_.view, prefix);
    }

    bool endsWith(scope String suffix) const pure @trusted
    {
        return xtb.core.string.endsWith(storage_.view, suffix);
    }

    String baseName() const return pure @trusted
    {
        return xtb.core.string.baseName(storage_.view);
    }

    String stripExtension() const return pure @trusted
    {
        return xtb.core.string.stripExtension(storage_.view);
    }

    String trimAsciiStart() const return pure @trusted
    {
        return xtb.core.string.trimAsciiStart(storage_.view);
    }

    String trimAsciiEnd() const return pure @trusted
    {
        return xtb.core.string.trimAsciiEnd(storage_.view);
    }

    String trimAscii() const return pure @trusted
    {
        return xtb.core.string.trimAscii(storage_.view);
    }

    /// Replaces the complete contents while retaining reusable capacity.
    ///
    /// `value` may be a view into this buffer; self-assignment and subview
    /// assignment are handled without allocation.
    bool tryAssign(scope String value) @trusted
    {
        const current = storage_.view;
        bool aliases;
        size_t sourceOffset;
        if (value.length != 0 && current.length != 0)
        {
            const sourceAddress = cast(size_t) value.ptr;
            const beginAddress = cast(size_t) current.ptr;
            if (sourceAddress >= beginAddress)
            {
                sourceOffset = sourceAddress - beginAddress;
                aliases = sourceOffset <= current.length &&
                    value.length <= current.length - sourceOffset;
            }
        }

        if (aliases)
        {
            if (value.length != 0 && sourceOffset != 0)
                memmove(storage_.bytes_.slice.ptr, value.ptr, value.length);
            if (value.length < current.length)
                storage_.bytes_.removeRange(
                    value.length,
                    current.length - value.length,
                );
            return true;
        }

        if (!storage_.tryReserve(allocator_, value.length))
            return false;
        storage_.clear();
        storage_.appendAssumeCapacity(value);
        return true;
    }

    void assign(scope String value) @trusted
    {
        if (!tryAssign(value))
            panic("StringBuf allocation failed");
    }

    /// Removes `prefix` when present and reports whether the buffer changed.
    bool removePrefix(scope String prefix) @trusted
    {
        if (!xtb.core.string.startsWith(storage_.view, prefix))
            return false;
        if (prefix.length != 0)
            storage_.bytes_.removeRange(0, prefix.length);
        return true;
    }

    /// Removes `suffix` when present and reports whether the buffer changed.
    bool removeSuffix(scope String suffix) @trusted
    {
        if (!xtb.core.string.endsWith(storage_.view, suffix))
            return false;
        if (suffix.length != 0)
            storage_.truncateBytes(storage_.byteLength - suffix.length);
        return true;
    }

    /// Removes leading ASCII whitespace in place.
    void trimAsciiStartInPlace() @trusted
    {
        const trimmed = xtb.core.string.trimAsciiStart(storage_.view);
        const removed = storage_.byteLength - trimmed.length;
        if (removed != 0)
            storage_.bytes_.removeRange(0, removed);
    }

    /// Removes trailing ASCII whitespace in place.
    void trimAsciiEndInPlace() @trusted
    {
        const trimmed = xtb.core.string.trimAsciiEnd(storage_.view);
        storage_.truncateBytes(trimmed.length);
    }

    /// Removes leading and trailing ASCII whitespace in place.
    void trimAsciiInPlace() @trusted
    {
        const original = storage_.view;
        const trimmed = xtb.core.string.trimAscii(original);
        const begin = trimmed.length == 0
            ? original.length : cast(size_t) trimmed.ptr - cast(size_t) original.ptr;
        if (begin != 0)
            storage_.bytes_.removeRange(0, begin);
        storage_.truncateBytes(trimmed.length);
    }

    Array!String split(scope String separator, Allocator* allocator) const @trusted
    {
        return xtb.core.string.split(storage_.view, separator, allocator);
    }

    Array!String split(char separator, Allocator* allocator) const @trusted
    {
        return xtb.core.string.split(storage_.view, separator, allocator);
    }

    Array!String splitWhitespace(Allocator* allocator) const @trusted
    {
        return xtb.core.string.splitWhitespace(storage_.view, allocator);
    }

    Array!String splitLines(Allocator* allocator) const @trusted
    {
        return xtb.core.string.splitLines(storage_.view, allocator);
    }

    bool opEquals(scope String other) const pure @trusted
    {
        return storage_ == other;
    }

    bool opEquals(scope ref const Self other) const pure @trusted
    {
        return storage_ == other.storage_;
    }

    size_t toHash() const pure @trusted
    {
        return storage_.toHash();
    }

    Allocator* allocator() return pure @safe
    {
        return allocator_;
    }

package(xtb):
    static Self adoptUnmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        requireValidStringBufAllocator(allocator);
        version (XTB_Checked)
            require(storage !is null,
                "StringBufUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        moveEmplace(*storage, result.storage_);
        return move(result);
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

private void requireValidStringBufAllocator(Allocator* allocator) @trusted
{
    version (XTB_Checked)
        require(allocator !is null && *allocator !is null,
            "StringBuf requires a valid allocator");
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

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

    Array!String tokens = "a::b::".split("::", mallocAllocator());
    assert(tokens.length == 3);
    assert(tokens[0].equal("a") && tokens[1].equal("b") && tokens[2].empty);
    Array!String words = "  alpha\t beta  ".splitWhitespace(mallocAllocator());
    assert(words.length == 2);
    assert(words[0].equal("alpha") && words[1].equal("beta"));
    words.deinit();
    tokens.deinit();

    StringBuf buffer = StringBuf.fromString(mallocAllocator(), "hello");
    assert(buffer == "hello");
    assert(buffer.equal("hello"));
    assert("hello" == buffer);
    assert(buffer != "other");

    char[5] mutableText = "hello";
    assert(buffer == mutableText[]);
    assert(mutableText[] == buffer);

    StringBuf same = StringBuf.fromString(mallocAllocator(), "hello");
    StringBuf different = StringBuf.fromString(mallocAllocator(), "Hello");
    assert(buffer == same && same == buffer);
    assert(buffer.equal(same));
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
    StringBuf failedBytes;
    assert(!StringBuf.tryFromBytesUnchecked(
            failing.allocator,
            encoded[],
            &failedBytes,
    ));
    assert(failedBytes.empty);

    StringBuf failedScalar = StringBuf.create(failing.allocator);
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

    emptyCString.deinit();
    failedScalar.deinit();
    failedBytes.deinit();
    selfEscape.deinit();
    selfPrepend.deinit();
    scalarWidths.deinit();
    unicode.deinit();
    emptyBuffer.deinit();
    different.deinit();
    same.deinit();
    buffer.deinit();
    emptyBytes.deinit();
    copiedBytes.deinit();
}

unittest
{
    import core.internal.traits : hasElaborateDestructor;
    import xtb.core.memory : Allocator;
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;
    import xtb.core.lifetime : deinit, needsDeinit;

    static assert(StringBufUnmanaged.sizeof == ArrayUnmanaged!char.sizeof);
    static assert(StringBuf.sizeof ==
            StringBufUnmanaged.sizeof + (Allocator*).sizeof);
    static assert(!__traits(isCopyable, StringBufUnmanaged));
    static assert(!__traits(isCopyable, StringBuf));
    static assert(!__traits(isCopyable, StringBuf.Released));
    static assert(!hasElaborateDestructor!StringBufUnmanaged);
    static assert(!hasElaborateDestructor!StringBuf);
    static assert(needsDeinit!StringBuf);
    static assert(!__traits(compiles, (ref StringBufUnmanaged left,
            ref StringBufUnmanaged right) { left = move(right); }));
    static assert(!__traits(compiles, (ref StringBuf left,
            ref StringBuf right) { left = move(right); }));
    static assert(__traits(compiles, (scope StringBuf* value) @safe {
            Allocator* allocator = value.allocator;
        }));
    static assert(!__traits(compiles, (scope const StringBuf* value) @safe {
            Allocator* allocator = value.allocator;
        }));
    static assert(!__traits(compiles, () @safe {
            StringBuf.Released released;
            ref StringBufUnmanaged storage = released.storage;
        }));
    static assert(!__traits(compiles, (scope StringBuf* value) { value.tryReplace("a", "b"); }));
    static assert(!__traits(compiles, (scope StringBufUnmanaged* value,
            Allocator* allocator) { value.tryReplace(allocator, "a", "b"); }));
    static assert(!__traits(compiles, (scope StringBuf* value) { value.tryEscape("x"); }));
    static assert(!__traits(compiles, (scope StringBufUnmanaged* value,
            Allocator* allocator) { value.tryEscape(allocator, "x"); }));

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
        StringBuf buffer = StringBuf.fromString(tracked.allocator, "alpha");
        StringBuf.Released released = buffer.release();
        assert(buffer.allocator is null && buffer.empty);
        assert(released.allocator is tracked.allocator);
        assert(released.storage.view == "alpha");

        released.storage.append(released.allocator, " beta");
        assert(released.storage.view == "alpha beta");
        deinit(released);
    }
    assert(tracked.clean);

    {
        StringBuf source = StringBuf.fromString(tracked.allocator, "adopted");
        StringBuf.Released released = source.release();
        StringBuf adopted = StringBuf.adopt(&released);

        assert(source.allocator is null && source.empty);
        assert(released.allocator is null && released.storage.empty);
        assert(adopted.allocator is tracked.allocator);
        assert(adopted.view == "adopted");
        adopted.deinit();
    }
    assert(tracked.clean);

    {
        StringBuf source = StringBuf.fromString(tracked.allocator, "raw");
        StringBuf.Released released = source.release();
        Allocator* allocator;
        StringBufUnmanaged storage = released.extract(&allocator);

        assert(allocator is tracked.allocator);
        assert(released.allocator is null && released.storage.empty);
        storage.append(allocator, " storage");
        assert(storage.view == "raw storage");
        storage.deinit(allocator);
    }
    assert(tracked.clean);
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

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

    StringBuf managed = StringBuf.create(managedAllocator.allocator);
    StringBufUnmanaged unmanaged;

    assert(managed.tryAppend("alpha"));
    assert(unmanaged.tryAppend(unmanagedAllocator.allocator, "alpha"));
    assert(managed.tryAppend(cast(dchar) 0x1f642));
    assert(unmanaged.tryAppend(
            unmanagedAllocator.allocator,
            cast(dchar) 0x1f642,
    ));
    assert(managed.tryInsert(5, " beta"));
    assert(unmanaged.tryInsert(
            unmanagedAllocator.allocator,
            5,
            " beta",
    ));
    assert(managed.tryReplaceInPlace("alpha", "A"));
    assert(unmanaged.tryReplaceInPlace(
            unmanagedAllocator.allocator,
            "alpha",
            "A",
    ));
    assert(managed.tryReserve(128));
    assert(unmanaged.tryReserve(unmanagedAllocator.allocator, 128));

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
    unmanaged.deinit(unmanagedAllocator.allocator);
    assert(managedAllocator.stats == unmanagedAllocator.stats);
    assert(managedAllocator.clean && unmanagedAllocator.clean);
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

    StringBuf text = StringBuf.fromString(
        mallocAllocator(),
        "  alpha/beta/🙂  ",
    );
    StringBuf* pointer = &text;

    assert(pointer.startsWith("  alpha"));
    assert(pointer.endsWith("🙂  "));
    assert(pointer.contains("beta"));
    assert(pointer.containsCodePoint(cast(dchar) 0x1f642));
    assert(pointer.find("alpha") == 2);
    assert(pointer.findLastCodeUnit('/') == 12);
    assert(pointer.sliceBytes(2, 7) == "alpha");
    assert(pointer.baseName == "🙂  ");
    assert(pointer.stripExtension == pointer.view);
    assert(pointer.trimAsciiStart == "alpha/beta/🙂  ");
    assert(pointer.trimAsciiEnd == "  alpha/beta/🙂");
    assert(pointer.trimAscii == "alpha/beta/🙂");

    pointer.trimAsciiInPlace();
    assert(text == "alpha/beta/🙂");
    assert(pointer.removePrefix("alpha/"));
    assert(pointer.removeSuffix("/🙂"));
    assert(text == "beta");
    assert(!pointer.removePrefix("missing"));

    pointer.assign("prefix-value-suffix");
    String middle = pointer.sliceBytes(7, 12);
    pointer.assign(middle);
    assert(text == "value");
    pointer.assign(pointer.view);
    assert(text == "value");

    pointer.assign("a,b,c");
    Array!String parts = pointer.split(',', mallocAllocator());
    assert(parts.length == 3);
    assert(parts[0] == "a" && parts[1] == "b" && parts[2] == "c");
    parts.deinit();

    pointer.assign("\t  words  \n");
    pointer.trimAsciiStartInPlace();
    assert(text == "words  \n");
    pointer.trimAsciiEndInPlace();
    assert(text == "words");

    AllocationRecord[8] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    StringBuf retained = StringBuf.fromString(failing.allocator, "small");
    failing.failAfter(0);
    assert(!retained.tryAssign(
            "this replacement is intentionally larger than the current capacity",
    ));
    assert(retained == "small");
    retained.deinit();
    assert(failing.clean);
    text.deinit();
}
