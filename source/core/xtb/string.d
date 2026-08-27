module xtb.string;

nothrow @nogc:

public import xtb.types : String;
public import xtb.utf8 : Utf8Error, Utf8ErrorKind, Utf8StringResult,
    asString;

import core.interpolation : InterpolationFooter, InterpolationHeader;
import xtb.lifetime : move, moveEmplace;
import core.stdc.string : memcmp, memmove, strlen;
import xtb.types : u8;
import xtb.containers.array;
import xtb.allocators.arena : Arena;
import xtb.memory : Allocator, deallocateArray, tryAllocateArray;
import xtb.hash : hashValue;
import xtb.panic : panic;
import xtb.fmt.writer : Writer;

version (XTB_Checked) import xtb.panic : require;
import xtb.containers.released_storage : ReleasedStorage;
import xtb.utf8 : ceilCodePointBoundary, encodeUtf8,
    isCodePointBoundary, validateUtf8;

enum notFound = size_t.max;

alias SplitPredicate = size_t function(String rest, void* context);

private template UnqualifiedStringInput(T)
{
    alias UnqualifiedStringInput = typeof(cast() T.init);
}

private enum isOwnedStringInput(T) =
    is(UnqualifiedStringInput!T == OwnedString);

private enum isStringBufInput(T) = is(T : String) || isOwnedStringInput!T;

private enum isStringBufArgument(alias value) =
    isStringBufInput!(typeof(value)) &&
    (!isOwnedStringInput!(typeof(value)) || __traits(isRef, value));

private String stringBufInput(T)(return scope auto ref T value) pure @trusted if (isStringBufInput!T)
{
    static if (isOwnedStringInput!T)
    {
        static assert(__traits(isRef, value),
            "temporary OwnedString input would lose its cleanup obligation");
        return value.view;
    }
    else
        return value;
}

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

    static bool tryFromString(Value)(
        Allocator* allocator,
        scope auto ref Value value,
        scope StringBufUnmanaged* output,
    ) if (isStringBufArgument!value)
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

    static StringBufUnmanaged fromString(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    ) if (isStringBufArgument!value)
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

private:
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

package(xtb):
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

    bool opEquals(Other)(scope auto ref Other other) const pure @trusted if (isStringBufArgument!other)
    {
        return view.equal(stringBufInput(other));
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

    void append(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    ) if (isStringBufArgument!value)
    {
        bytes_.append(allocator, stringBufInput(value));
    }

    bool tryAppend(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    ) if (isStringBufArgument!value)
    {
        return bytes_.tryAppend(allocator, stringBufInput(value));
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

    void appendAssumeCapacity(Value)(scope auto ref Value value) if (isStringBufArgument!value)
    {
        bytes_.appendAssumeCapacity(stringBufInput(value));
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

    bool tryInsert(Value)(
        Allocator* allocator,
        size_t byteOffset,
        scope auto ref Value value,
    ) if (isStringBufArgument!value)
    {
        version (XTB_Checked)
        {
            require(byteOffset <= byteLength,
                "StringBuf insertion byte offset out of bounds");
            require(view.isCodePointBoundary(byteOffset),
                "StringBuf insertion byte offset is inside UTF-8 code point");
        }
        return bytes_.tryInsert(
            allocator,
            byteOffset,
            stringBufInput(value),
        );
    }

    void insert(Value)(
        Allocator* allocator,
        size_t byteOffset,
        scope auto ref Value value,
    ) if (isStringBufArgument!value)
    {
        if (!tryInsert(allocator, byteOffset, value))
            panic("StringBuf allocation failed");
    }

    bool tryPrepend(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    ) if (isStringBufArgument!value)
    {
        return tryInsert(allocator, 0, value);
    }

    void prepend(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    ) if (isStringBufArgument!value)
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

    bool tryAppendEscaped(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    ) if (isStringBufArgument!value)
    {
        String input = stringBufInput(value);
        bool aliasesBuffer;
        size_t sourceOffset;
        if (input.length != 0 && byteLength != 0)
        {
            const sourceAddress = cast(size_t) input.ptr;
            const beginAddress = cast(size_t) view.ptr;
            const byteOffset = sourceAddress - beginAddress;
            aliasesBuffer = sourceAddress >= beginAddress &&
                byteOffset < byteLength;
            if (aliasesBuffer)
            {
                if (input.length > byteLength - byteOffset)
                    return false;
                sourceOffset = byteOffset;
            }
        }

        size_t escapedCount;
        foreach (character; input)
            if (escapedCharacter(character) != '\0')
                ++escapedCount;
        if (escapedCount > size_t.max - input.length ||
            input.length + escapedCount > size_t.max - byteLength)
            return false;
        const required = byteLength + input.length + escapedCount;
        if (!tryReserve(allocator, required))
            return false;
        if (aliasesBuffer)
            input = view[sourceOffset .. sourceOffset + input.length];
        foreach (character; input)
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

    void appendEscaped(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    ) if (isStringBufArgument!value)
    {
        if (!tryAppendEscaped(allocator, value))
            panic("StringBuf allocation failed");
    }

    /// Replaces every non-overlapping match in this buffer.
    ///
    /// Aliased `from` and `to` views are snapshotted before any mutation. On
    /// allocation failure the buffer remains unchanged.
    bool tryReplaceInPlace(From, To)(
        Allocator* allocator,
        scope auto ref From fromValue,
        scope auto ref To toValue,
    ) if (isStringBufArgument!fromValue &&
        isStringBufArgument!toValue)
    {
        String from = stringBufInput(fromValue);
        String to = stringBufInput(toValue);
        if (from.length == 0)
            return true;

        StringBufUnmanaged fromSnapshot;
        scope (exit)
            fromSnapshot.deinit(allocator);
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
        scope (exit)
            toSnapshot.deinit(allocator);
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

    void replaceInPlace(From, To)(
        Allocator* allocator,
        scope auto ref From from,
        scope auto ref To to,
    ) if (isStringBufArgument!from && isStringBufArgument!to)
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

    static bool tryFromString(Value)(
        Allocator* allocator,
        scope auto ref Value value,
        scope Self* output,
    ) @trusted if (isStringBufArgument!value)
    {
        version (XTB_Checked)
        {
            require(output !is null, "StringBuf output pointer is null");
            require(output.allocator_ is null,
                "StringBuf output is already initialized");
        }
        Storage storage;
        if (!Storage.tryFromString(
                allocator,
                stringBufInput(value),
                &storage,
            ))
            return false;
        output.allocator_ = allocator;
        moveEmplace(storage, output.storage_);
        return true;
    }

    static Self fromString(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    ) @trusted if (isStringBufArgument!value)
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

    bool equal(Other)(scope auto ref Other other) const pure @trusted if (isStringBufArgument!other)
    {
        return storage_ == stringBufInput(other);
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

    void append(Value)(scope auto ref Value value) @trusted if (isStringBufArgument!value)
    {
        storage_.append(allocator_, stringBufInput(value));
    }

    bool tryAppend(Value)(scope auto ref Value value) @trusted if (isStringBufArgument!value)
    {
        return storage_.tryAppend(allocator_, stringBufInput(value));
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

    /// Returns an immediate fallible `Writer` view over this buffer.
    ///
    /// The writer borrows this buffer and must not outlive it or be used after
    /// the buffer is moved or destroyed. Allocation failure becomes sticky
    /// writer failure; no explicit flush or finalization is required.
    Writer writer() return @trusted
    {
        return Writer.fromSink(&stringBufWriterSink, &this);
    }

    /// Writes ordinary XTB printable values transactionally.
    ///
    /// On failure the visible contents are restored to their original length.
    /// Capacity growth and formatter side effects are not rolled back.
    bool tryWrite(Args...)(auto ref Args args) @trusted
    {
        const checkpoint = byteLength;
        Writer output = writer();
        output.write(args);
        if (output.ok)
            return true;
        truncateBytes(checkpoint);
        return false;
    }

    /// Panicking counterpart to `tryWrite`.
    void write(Args...)(auto ref Args args) @trusted
    {
        if (!tryWrite(args))
            panic("StringBuf write failed");
    }

    /// Writes ordinary values followed by one newline transactionally.
    bool tryWriteln(Args...)(auto ref Args args) @trusted
    {
        const checkpoint = byteLength;
        Writer output = writer();
        output.writeln(args);
        if (output.ok)
            return true;
        truncateBytes(checkpoint);
        return false;
    }

    /// Panicking counterpart to `tryWriteln`.
    void writeln(Args...)(auto ref Args args) @trusted
    {
        if (!tryWriteln(args))
            panic("StringBuf write failed");
    }

    /// Applies compile-time `{}` formatting transactionally.
    bool tryFormat(string pattern, Args...)(auto ref Args args) @trusted
    {
        const checkpoint = byteLength;
        Writer output = writer();
        output.format!pattern(args);
        if (output.ok)
            return true;
        truncateBytes(checkpoint);
        return false;
    }

    /// Panicking counterpart to `tryFormat`.
    void format(string pattern, Args...)(auto ref Args args) @trusted
    {
        if (!tryFormat!pattern(args))
            panic("StringBuf formatting failed");
    }

    /// Applies compile-time `{}` formatting and appends one newline transactionally.
    bool tryFormatln(string pattern, Args...)(auto ref Args args) @trusted
    {
        const checkpoint = byteLength;
        Writer output = writer();
        output.formatln!pattern(args);
        if (output.ok)
            return true;
        truncateBytes(checkpoint);
        return false;
    }

    /// Panicking counterpart to `tryFormatln`.
    void formatln(string pattern, Args...)(auto ref Args args) @trusted
    {
        if (!tryFormatln!pattern(args))
            panic("StringBuf formatting failed");
    }

    /// Writes a D interpolated string transactionally.
    bool tryFormat(Sequence...)(
        InterpolationHeader header,
        auto ref Sequence sequence,
        InterpolationFooter footer,
    ) @trusted
    {
        const checkpoint = byteLength;
        Writer output = writer();
        output.format(header, sequence, footer);
        if (output.ok)
            return true;
        truncateBytes(checkpoint);
        return false;
    }

    /// Panicking counterpart for interpolated-string formatting.
    void format(Sequence...)(
        InterpolationHeader header,
        auto ref Sequence sequence,
        InterpolationFooter footer,
    ) @trusted
    {
        if (!tryFormat(header, sequence, footer))
            panic("StringBuf formatting failed");
    }

    /// Writes a D interpolated string followed by one newline transactionally.
    bool tryFormatln(Sequence...)(
        InterpolationHeader header,
        auto ref Sequence sequence,
        InterpolationFooter footer,
    ) @trusted
    {
        const checkpoint = byteLength;
        Writer output = writer();
        output.formatln(header, sequence, footer);
        if (output.ok)
            return true;
        truncateBytes(checkpoint);
        return false;
    }

    /// Panicking counterpart for interpolated-string formatting with a newline.
    void formatln(Sequence...)(
        InterpolationHeader header,
        auto ref Sequence sequence,
        InterpolationFooter footer,
    ) @trusted
    {
        if (!tryFormatln(header, sequence, footer))
            panic("StringBuf formatting failed");
    }

    void appendAssumeCapacity(Value)(scope auto ref Value value) @trusted if (isStringBufArgument!value)
    {
        storage_.appendAssumeCapacity(stringBufInput(value));
    }

    void appendAssumeCapacity(char value) @trusted
    {
        storage_.appendAssumeCapacity(value);
    }

    void appendAssumeCapacity(dchar value) @trusted
    {
        storage_.appendAssumeCapacity(value);
    }

    bool tryInsert(Value)(
        size_t byteOffset,
        scope auto ref Value value,
    ) @trusted if (isStringBufArgument!value)
    {
        return storage_.tryInsert(
            allocator_,
            byteOffset,
            stringBufInput(value),
        );
    }

    void insert(Value)(
        size_t byteOffset,
        scope auto ref Value value,
    ) @trusted if (isStringBufArgument!value)
    {
        storage_.insert(allocator_, byteOffset, stringBufInput(value));
    }

    bool tryPrepend(Value)(scope auto ref Value value) @trusted if (isStringBufArgument!value)
    {
        return storage_.tryPrepend(allocator_, stringBufInput(value));
    }

    void prepend(Value)(scope auto ref Value value) @trusted if (isStringBufArgument!value)
    {
        storage_.prepend(allocator_, stringBufInput(value));
    }

    void truncateBytes(size_t newByteLength) @trusted
    {
        storage_.truncateBytes(newByteLength);
    }

    void clear() @trusted
    {
        storage_.clear();
    }

    bool tryAppendEscaped(Value)(scope auto ref Value value) @trusted if (isStringBufArgument!value)
    {
        return storage_.tryAppendEscaped(
            allocator_,
            stringBufInput(value),
        );
    }

    void appendEscaped(Value)(scope auto ref Value value) @trusted if (isStringBufArgument!value)
    {
        storage_.appendEscaped(allocator_, stringBufInput(value));
    }

    /// Copies this buffer into a new exact-sized owner allocated by `allocator`.
    bool tryCopy(
        Allocator* allocator,
        scope OwnedString* output,
    ) const @trusted
    {
        return storage_.view.tryCopy(allocator, output);
    }

    /// Copies this buffer into arena-owned storage.
    bool tryCopy(Arena* arena, scope String* output) const @trusted
    {
        return storage_.view.tryCopy(arena, output);
    }

    /// Panicking independently owned counterpart to `tryCopy`.
    OwnedString copy(Allocator* allocator) const @trusted
    {
        return storage_.view.copy(allocator);
    }

    /// Panicking arena-owned counterpart to `tryCopy`.
    String copy(Arena* arena) const @trusted
    {
        return storage_.view.copy(arena);
    }

    bool tryReplaceInPlace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
    ) @trusted if (isStringBufArgument!from && isStringBufArgument!to)
    {
        return storage_.tryReplaceInPlace(
            allocator_,
            stringBufInput(from),
            stringBufInput(to),
        );
    }

    void replaceInPlace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
    ) @trusted if (isStringBufArgument!from && isStringBufArgument!to)
    {
        storage_.replaceInPlace(
            allocator_,
            stringBufInput(from),
            stringBufInput(to),
        );
    }

    /// Replaces every non-overlapping `from` occurrence in a new exact-sized
    /// owner allocated by `allocator`.
    bool tryReplace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
        Allocator* allocator,
        scope OwnedString* output,
    ) const @trusted if (isStringBufArgument!from && isStringBufArgument!to)
    {
        return storage_.view.tryReplace(
            stringBufInput(from),
            stringBufInput(to),
            allocator,
            output,
        );
    }

    /// Replaces every non-overlapping `from` occurrence in arena-owned output.
    bool tryReplace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
        Arena* arena,
        scope String* output,
    ) const @trusted if (isStringBufArgument!from && isStringBufArgument!to)
    {
        return storage_.view.tryReplace(
            stringBufInput(from),
            stringBufInput(to),
            arena,
            output,
        );
    }

    /// Panicking independently owned counterpart to `tryReplace`.
    OwnedString replace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
        Allocator* allocator,
    ) const @trusted if (isStringBufArgument!from && isStringBufArgument!to)
    {
        return storage_.view.replace(
            stringBufInput(from),
            stringBufInput(to),
            allocator,
        );
    }

    /// Panicking arena-owned counterpart to `tryReplace`.
    String replace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
        Arena* arena,
    ) const @trusted if (isStringBufArgument!from && isStringBufArgument!to)
    {
        return storage_.view.replace(
            stringBufInput(from),
            stringBufInput(to),
            arena,
        );
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
        return storage_.view.frontCodeUnit();
    }

    /// Returns the last UTF-8 code unit. The buffer must not be empty.
    char backCodeUnit() const @trusted
    {
        return storage_.view.backCodeUnit();
    }

    int compare(Other)(scope auto ref Other other) const pure @trusted if (isStringBufArgument!other)
    {
        return storage_.view.compare(stringBufInput(other));
    }

    String sliceBytes(size_t beginByteOffset, size_t endByteOffset) const return @trusted
    {
        return storage_.view.sliceBytes(beginByteOffset, endByteOffset);
    }

    String prefixBytes(size_t endByteOffset) const return @trusted
    {
        return storage_.view.prefixBytes(endByteOffset);
    }

    String suffixBytes(size_t beginByteOffset) const return @trusted
    {
        return storage_.view.suffixBytes(beginByteOffset);
    }

    size_t find(Needle)(scope auto ref Needle needle) const pure @trusted
            if (isStringBufArgument!needle)
    {
        return storage_.view.find(stringBufInput(needle));
    }

    size_t findLast(Needle)(scope auto ref Needle needle) const pure @trusted
            if (isStringBufArgument!needle)
    {
        return storage_.view.findLast(stringBufInput(needle));
    }

    size_t findCodeUnit(char codeUnit) const pure @trusted
    {
        return storage_.view.findCodeUnit(codeUnit);
    }

    size_t findLastCodeUnit(char codeUnit) const pure @trusted
    {
        return storage_.view.findLastCodeUnit(codeUnit);
    }

    size_t findCodePoint(dchar codePoint) const @trusted
    {
        return storage_.view.findCodePoint(codePoint);
    }

    size_t findLastCodePoint(dchar codePoint) const @trusted
    {
        return storage_.view.findLastCodePoint(codePoint);
    }

    bool contains(Needle)(scope auto ref Needle needle) const pure @trusted
            if (isStringBufArgument!needle)
    {
        return storage_.view.contains(stringBufInput(needle));
    }

    bool containsCodeUnit(char codeUnit) const pure @trusted
    {
        return storage_.view.containsCodeUnit(codeUnit);
    }

    bool containsCodePoint(dchar codePoint) const @trusted
    {
        return storage_.view.containsCodePoint(codePoint);
    }

    bool containsNul() const pure @trusted
    {
        return storage_.view.containsNul();
    }

    bool startsWith(Prefix)(scope auto ref Prefix prefix) const pure @trusted
            if (isStringBufArgument!prefix)
    {
        return storage_.view.startsWith(stringBufInput(prefix));
    }

    bool endsWith(Suffix)(scope auto ref Suffix suffix) const pure @trusted
            if (isStringBufArgument!suffix)
    {
        return storage_.view.endsWith(stringBufInput(suffix));
    }

    String baseName() const return pure @trusted
    {
        return storage_.view.baseName();
    }

    String stripExtension() const return pure @trusted
    {
        return storage_.view.stripExtension();
    }

    String trimAsciiStart() const return pure @trusted
    {
        return storage_.view.trimAsciiStart();
    }

    String trimAsciiEnd() const return pure @trusted
    {
        return storage_.view.trimAsciiEnd();
    }

    String trimAscii() const return pure @trusted
    {
        return storage_.view.trimAscii();
    }

    /// Replaces the complete contents while retaining reusable capacity.
    ///
    /// `value` may be a view into this buffer; self-assignment and subview
    /// assignment are handled without allocation.
    bool tryAssign(Value)(scope auto ref Value value) @trusted if (isStringBufArgument!value)
    {
        const input = stringBufInput(value);
        const current = storage_.view;
        bool aliases;
        size_t sourceOffset;
        if (input.length != 0 && current.length != 0)
        {
            const sourceAddress = cast(size_t) input.ptr;
            const beginAddress = cast(size_t) current.ptr;
            if (sourceAddress >= beginAddress)
            {
                sourceOffset = sourceAddress - beginAddress;
                aliases = sourceOffset <= current.length &&
                    input.length <= current.length - sourceOffset;
            }
        }

        if (aliases)
        {
            if (input.length != 0 && sourceOffset != 0)
                memmove(storage_.bytes_.slice.ptr, input.ptr, input.length);
            if (input.length < current.length)
                storage_.bytes_.removeRange(
                    input.length,
                    current.length - input.length,
                );
            return true;
        }

        if (!storage_.tryReserve(allocator_, input.length))
            return false;
        storage_.clear();
        storage_.appendAssumeCapacity(input);
        return true;
    }

    void assign(Value)(scope auto ref Value value) @trusted if (isStringBufArgument!value)
    {
        if (!tryAssign(value))
            panic("StringBuf allocation failed");
    }

    /// Removes `prefix` when present and reports whether the buffer changed.
    bool removePrefix(Prefix)(scope auto ref Prefix prefix) @trusted if (isStringBufArgument!prefix)
    {
        const input = stringBufInput(prefix);
        if (!storage_.view.startsWith(input))
            return false;
        if (input.length != 0)
            storage_.bytes_.removeRange(0, input.length);
        return true;
    }

    /// Removes `suffix` when present and reports whether the buffer changed.
    bool removeSuffix(Suffix)(scope auto ref Suffix suffix) @trusted if (isStringBufArgument!suffix)
    {
        const input = stringBufInput(suffix);
        if (!storage_.view.endsWith(input))
            return false;
        if (input.length != 0)
            storage_.truncateBytes(storage_.byteLength - input.length);
        return true;
    }

    /// Removes leading ASCII whitespace in place.
    void trimAsciiStartInPlace() @trusted
    {
        const trimmed = storage_.view.trimAsciiStart();
        const removed = storage_.byteLength - trimmed.length;
        if (removed != 0)
            storage_.bytes_.removeRange(0, removed);
    }

    /// Removes trailing ASCII whitespace in place.
    void trimAsciiEndInPlace() @trusted
    {
        const trimmed = storage_.view.trimAsciiEnd();
        storage_.truncateBytes(trimmed.length);
    }

    /// Removes leading and trailing ASCII whitespace in place.
    void trimAsciiInPlace() @trusted
    {
        const original = storage_.view;
        const trimmed = original.trimAscii();
        const begin = trimmed.length == 0
            ? original.length : cast(size_t) trimmed.ptr - cast(size_t) original.ptr;
        if (begin != 0)
            storage_.bytes_.removeRange(0, begin);
        storage_.truncateBytes(trimmed.length);
    }

    Array!String split(Separator)(
        scope auto ref Separator separator,
        Allocator* allocator,
    ) const @trusted if (isStringBufArgument!separator)
    {
        return storage_.view.split(stringBufInput(separator), allocator);
    }

    Array!String split(char separator, Allocator* allocator) const @trusted
    {
        return storage_.view.split(separator, allocator);
    }

    Array!String splitWhitespace(Allocator* allocator) const @trusted
    {
        return storage_.view.splitWhitespace(allocator);
    }

    Array!String splitLines(Allocator* allocator) const @trusted
    {
        return storage_.view.splitLines(allocator);
    }

    bool opEquals(Other)(scope auto ref Other other) const pure @trusted if (isStringBufArgument!other)
    {
        return storage_ == stringBufInput(other);
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

private size_t stringBufWriterSink(
    void* context,
    scope const(u8)[] bytes,
)
@trusted
{
    StringBuf* buffer = cast(StringBuf*) context;
    if (buffer is null || buffer.allocator_ is null)
        return 0;
    return buffer.tryAppend(cast(String) bytes) ? bytes.length : 0;
}

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : mallocAllocator;

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
    import xtb.memory : Allocator;
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : mallocAllocator;
    import xtb.lifetime : deinit, needsDeinit;

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
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : mallocAllocator;

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
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : mallocAllocator;

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
///
/// The zero state is valid. Nonempty values must be explicitly deinitialized
/// with the allocator that created or adopted their storage. Copying is
/// disabled because a shallow copy would duplicate ownership.
struct OwnedStringUnmanaged
{
nothrow @nogc:

private:
    String value_;

public:
    @disable this(this);
    @disable ref OwnedStringUnmanaged opAssign(OwnedStringUnmanaged source) return;

    static bool tryFromString(
        Allocator* allocator,
        scope String value,
        scope OwnedStringUnmanaged* output,
    ) @trusted
    {
        requireValidOwnedStringAllocator(allocator);
        version (XTB_Checked)
        {
            require(output !is null,
                "OwnedStringUnmanaged output pointer is null");
            require(output.value_.ptr is null && output.value_.length == 0,
                "OwnedStringUnmanaged output is not empty");
        }

        if (value.length == 0)
            return true;

        char* bytes = allocator.tryAllocateArray!char(value.length).ptr;
        if (bytes is null)
            return false;
        memmove(bytes, value.ptr, value.length);
        output.value_ = bytes[0 .. value.length];
        return true;
    }

    static OwnedStringUnmanaged fromString(
        Allocator* allocator,
        scope String value,
    ) @trusted
    {
        OwnedStringUnmanaged result;
        if (!tryFromString(allocator, value, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    /// Copies bytes whose UTF-8 validity the caller has already proved.
    static bool tryFromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        scope OwnedStringUnmanaged* output,
    ) @system
    {
        return tryFromString(allocator, bytes.asStringUnchecked, output);
    }

    /// Panicking counterpart to `tryFromBytesUnchecked`.
    static OwnedStringUnmanaged fromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    ) @system
    {
        OwnedStringUnmanaged result;
        if (!tryFromBytesUnchecked(allocator, bytes, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    void deinit(Allocator* allocator) @trusted
    {
        if (value_.length != 0)
        {
            requireValidOwnedStringAllocator(allocator);
            allocator.deallocateArray(value_.ptr[0 .. value_.length]);
        }
        value_ = String.init;
    }

    void resetAndRelease(Allocator* allocator) @trusted
    {
        deinit(allocator);
    }

    String view() const return pure @safe
    {
        return value_;
    }

    String formatRepresentation() const return pure @safe
    {
        return view;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.value(view);
    }

    size_t byteLength() const pure @safe
    {
        return value_.length;
    }

    bool empty() const pure @safe
    {
        return value_.length == 0;
    }

    bool opEquals(scope String other) const pure @safe
    {
        import xtb.string : equal;

        return value_.equal(other);
    }

    bool opEquals(scope ref const OwnedStringUnmanaged other) const
    pure @safe
    {
        import xtb.string : equal;

        return value_.equal(other.value_);
    }

    size_t toHash() const pure @safe
    {
        return hashValue(value_);
    }

package(xtb):
    static OwnedStringUnmanaged adoptExact(
        scope RawArrayStorage!char* storage,
    ) @system
    {
        version (XTB_Checked)
        {
            require(storage !is null,
                "raw OwnedString storage pointer is null");
            require(storage.length == storage.capacity,
                "adopted OwnedString storage is not exact-sized");
            require((storage.length == 0) == (storage.data is null),
                "adopted OwnedString storage is not canonical");
        }
        OwnedStringUnmanaged result;
        result.value_ = storage.data[0 .. storage.length];
        storage.data = null;
        storage.length = 0;
        storage.capacity = 0;
        return move(result);
    }

    const(String)* viewPointer() const return @safe
    {
        return &value_;
    }
}

/// Standalone explicit-lifetime wrapper around `OwnedStringUnmanaged`.
struct OwnedString
{
nothrow @nogc:

    alias Self = OwnedString;
    alias Storage = OwnedStringUnmanaged;
    alias Released = ReleasedStorage!Storage;

private:
    Allocator* allocator_;
    Storage storage_;

    version (XTB_Checked)
    {
        invariant
        {
            require(&this !is null, "OwnedString pointer is null");
        }
    }

public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(Allocator* allocator) @trusted
    {
        requireValidOwnedStringAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    static bool tryFromString(
        Allocator* allocator,
        scope String value,
        scope Self* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "OwnedString output pointer is null");
            require(output.allocator_ is null && output.storage_.empty,
                "OwnedString output is not empty");
        }
        Storage storage;
        if (!Storage.tryFromString(allocator, value, &storage))
            return false;
        output.allocator_ = allocator;
        moveEmplace(storage, output.storage_);
        return true;
    }

    static Self fromString(Allocator* allocator, scope String value) @trusted
    {
        Self result;
        if (!tryFromString(allocator, value, &result))
            panic("OwnedString allocation failed");
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
            require(output !is null, "OwnedString output pointer is null");
            require(output.allocator_ is null && output.storage_.empty,
                "OwnedString output is not empty");
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
            panic("OwnedString allocation failed");
        return move(result);
    }

    static Self adopt(scope Released* released) @trusted
    {
        version (XTB_Checked)
            require(released !is null,
                "released OwnedString storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator_ = allocator;
        moveEmplace(storage, result.storage_);
        return move(result);
    }

    void deinit() @trusted
    {
        if (allocator_ is null)
            return;
        storage_.deinit(allocator_);
        allocator_ = null;
    }

    void resetAndRelease() @trusted
    {
        storage_.resetAndRelease(allocator_);
    }

    Released release() @trusted
    {
        auto result = Released.fromOwnedParts(allocator_, &storage_);
        allocator_ = null;
        return move(result);
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

    size_t byteLength() const pure @trusted
    {
        return storage_.byteLength;
    }

    bool empty() const pure @trusted
    {
        return storage_.empty;
    }

    bool equal(scope String other) const pure @trusted
    {
        return storage_ == other;
    }

    bool equal(scope ref const Self other) const pure @trusted
    {
        return storage_ == other.storage_;
    }

    /// Copies this value into storage owned by `arena`.
    bool tryCopy(Arena* arena, scope String* output) const @trusted
    {
        return storage_.view.tryCopy(arena, output);
    }

    /// Panicking arena-owned counterpart to `tryCopy`.
    String copy(Arena* arena) const @trusted
    {
        return storage_.view.copy(arena);
    }

    /// Clones this value with an explicit allocator.
    bool tryClone(
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return Self.tryFromString(allocator, storage_.view, output);
    }

    /// Panicking clone using an explicit allocator.
    Self clone(Allocator* allocator) const @trusted
    {
        return Self.fromString(allocator, storage_.view);
    }

    /// Concatenates into a new owner using an explicit allocator.
    bool tryConcat(
        String right,
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return storage_.view.tryConcat(right, allocator, output);
    }

    /// Concatenates into storage owned by `arena`.
    bool tryConcat(
        String right,
        Arena* arena,
        scope String* output,
    ) const @trusted
    {
        return storage_.view.tryConcat(right, arena, output);
    }

    /// Panicking concatenation using an explicit allocator.
    Self concat(String right, Allocator* allocator) const @trusted
    {
        return storage_.view.concat(right, allocator);
    }

    /// Panicking concatenation into storage owned by `arena`.
    String concat(String right, Arena* arena) const @trusted
    {
        return storage_.view.concat(right, arena);
    }

    /// Replaces matches into a new owner using an explicit allocator.
    bool tryReplace(
        String from,
        String to,
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return storage_.view.tryReplace(from, to, allocator, output);
    }

    /// Replaces matches into storage owned by `arena`.
    bool tryReplace(
        String from,
        String to,
        Arena* arena,
        scope String* output,
    ) const @trusted
    {
        return storage_.view.tryReplace(from, to, arena, output);
    }

    /// Panicking replacement using an explicit allocator.
    Self replace(
        String from,
        String to,
        Allocator* allocator,
    ) const @trusted
    {
        return storage_.view.replace(from, to, allocator);
    }

    /// Panicking replacement into storage owned by `arena`.
    String replace(String from, String to, Arena* arena) const @trusted
    {
        return storage_.view.replace(from, to, arena);
    }

    /// Escapes into a new owner using an explicit allocator.
    bool tryEscape(
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return storage_.view.tryEscape(allocator, output);
    }

    /// Escapes into storage owned by `arena`.
    bool tryEscape(Arena* arena, scope String* output) const @trusted
    {
        return storage_.view.tryEscape(arena, output);
    }

    /// Panicking escape using an explicit allocator.
    Self escape(Allocator* allocator) const @trusted
    {
        return storage_.view.escape(allocator);
    }

    /// Panicking escape into storage owned by `arena`.
    String escape(Arena* arena) const @trusted
    {
        return storage_.view.escape(arena);
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
        requireValidOwnedStringAllocator(allocator);
        version (XTB_Checked)
            require(storage !is null,
                "OwnedStringUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        moveEmplace(*storage, result.storage_);
        return move(result);
    }
}

/// Copies borrowed text into exact-sized independently owned storage.
bool tryCopy(
    String value,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryCopyImpl(value, allocator, output);
}

/// Copies borrowed text into storage owned by `arena`.
bool tryCopy(
    String value,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryCopyImpl(value, arena, output);
}

/// Panicking independently owned counterpart to `tryCopy`.
OwnedString copy(String value, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!value.tryCopy(allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `tryCopy`.
String copy(String value, Arena* arena) @trusted
{
    String result;
    if (!value.tryCopy(arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Concatenates into exact-sized independently owned storage.
bool tryConcat(
    String left,
    String right,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryConcatImpl(left, right, allocator, output);
}

/// Concatenates into storage owned by `arena`.
bool tryConcat(
    String left,
    String right,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryConcatImpl(left, right, arena, output);
}

/// Panicking independently owned counterpart to `tryConcat`.
OwnedString concat(String left, String right, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!left.tryConcat(right, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `tryConcat`.
String concat(String left, String right, Arena* arena) @trusted
{
    String result;
    if (!left.tryConcat(right, arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Replaces every non-overlapping `from` occurrence in independently owned output.
bool tryReplace(
    String value,
    String from,
    String to,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryReplaceImpl(value, from, to, allocator, output);
}

/// Replaces every non-overlapping `from` occurrence in arena-owned output.
bool tryReplace(
    String value,
    String from,
    String to,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryReplaceImpl(value, from, to, arena, output);
}

/// Panicking independently owned counterpart to `tryReplace`.
OwnedString replace(
    String value,
    String from,
    String to,
    Allocator* allocator,
) @trusted
{
    OwnedString result;
    if (!value.tryReplace(from, to, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `tryReplace`.
String replace(
    String value,
    String from,
    String to,
    Arena* arena,
) @trusted
{
    String result;
    if (!value.tryReplace(from, to, arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Joins borrowed strings into exact-sized independently owned storage.
bool tryJoin(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryJoinImpl(values, separator, allocator, output);
}

/// Joins borrowed strings into storage owned by `arena`.
bool tryJoin(
    scope const(String)[] values,
    String separator,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryJoinImpl(values, separator, arena, output);
}

/// Panicking independently owned counterpart to `tryJoin`.
OwnedString join(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
) @trusted
{
    OwnedString result;
    if (!tryJoin(values, separator, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `tryJoin`.
String join(
    scope const(String)[] values,
    String separator,
    Arena* arena,
) @trusted
{
    String result;
    if (!tryJoin(values, separator, arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Escapes conventional C-style special characters into independently owned text.
bool tryEscape(
    String value,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryEscapeImpl(value, allocator, output);
}

/// Escapes conventional C-style special characters into arena-owned text.
bool tryEscape(
    String value,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryEscapeImpl(value, arena, output);
}

/// Panicking independently owned counterpart to `tryEscape`.
OwnedString escape(String value, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!value.tryEscape(allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `tryEscape`.
String escape(String value, Arena* arena) @trusted
{
    String result;
    if (!value.tryEscape(arena, &result))
        panic("arena string allocation failed");
    return result;
}

private bool tryCopyImpl(Context, Output)(
    String value,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
    char[] allocation;
    if (!tryPrepareStringTransform(context, value.length, &allocation))
        return false;
    if (value.length != 0)
        memmove(allocation.ptr, value.ptr, value.length);
    commitStringTransform(context, allocation, output);
    return true;
}

private bool tryConcatImpl(Context, Output)(
    String left,
    String right,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
    if (right.length > size_t.max - left.length)
        return false;
    const length = left.length + right.length;

    char[] allocation;
    if (!tryPrepareStringTransform(context, length, &allocation))
        return false;
    if (left.length != 0)
        memmove(allocation.ptr, left.ptr, left.length);
    if (right.length != 0)
        memmove(allocation.ptr + left.length, right.ptr, right.length);
    commitStringTransform(context, allocation, output);
    return true;
}

private bool tryReplaceImpl(Context, Output)(
    String value,
    String from,
    String to,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
    if (from.length == 0)
        return tryCopyImpl(value, context, output);

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

    char[] allocation;
    if (!tryPrepareStringTransform(context, length, &allocation))
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
                memmove(
                    allocation.ptr + destinationOffset,
                    value.ptr + sourceOffset,
                    remainder,
                );
            destinationOffset += remainder;
            break;
        }
        if (found != 0)
            memmove(
                allocation.ptr + destinationOffset,
                value.ptr + sourceOffset,
                found,
            );
        destinationOffset += found;
        if (to.length != 0)
            memmove(
                allocation.ptr + destinationOffset,
                to.ptr,
                to.length,
            );
        destinationOffset += to.length;
        sourceOffset += found + from.length;
    }
    commitStringTransform(context, allocation, output);
    return true;
}

private bool tryJoinImpl(Context, Output)(
    scope const(String)[] values,
    String separator,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
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
        if (separator.length != 0 &&
            count > (size_t.max - length) / separator.length)
            return false;
        length += count * separator.length;
    }

    char[] allocation;
    if (!tryPrepareStringTransform(context, length, &allocation))
        return false;
    size_t offset;
    foreach (index, value; values)
    {
        if (index != 0 && separator.length != 0)
        {
            memmove(allocation.ptr + offset, separator.ptr, separator.length);
            offset += separator.length;
        }
        if (value.length != 0)
        {
            memmove(allocation.ptr + offset, value.ptr, value.length);
            offset += value.length;
        }
    }
    commitStringTransform(context, allocation, output);
    return true;
}

private bool tryEscapeImpl(Context, Output)(
    String value,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
    size_t escapedCount;
    foreach (character; value)
        if (escapedCharacter(character) != '\0')
            ++escapedCount;
    if (escapedCount > size_t.max - value.length)
        return false;
    const length = value.length + escapedCount;

    char[] allocation;
    if (!tryPrepareStringTransform(context, length, &allocation))
        return false;
    size_t offset;
    foreach (character; value)
    {
        const escaped = escapedCharacter(character);
        if (escaped != '\0')
        {
            allocation[offset++] = '\\';
            allocation[offset++] = escaped;
        }
        else
            allocation[offset++] = character;
    }
    commitStringTransform(context, allocation, output);
    return true;
}

private void requireStringTransformOutput(
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    requireEmptyOwnedStringOutput(allocator, output);
}

private void requireStringTransformOutput(
    Arena* arena,
    scope String* output,
) @trusted
{
    version (XTB_Checked)
    {
        require(arena !is null, "string transform requires a valid arena");
        require(output !is null, "String output pointer is null");
    }
}

private bool tryPrepareStringTransform(
    Allocator* allocator,
    size_t length,
    scope char[]* allocation,
) @trusted
{
    if (length == 0)
        return true;
    *allocation = allocator.tryAllocateArray!char(length);
    return allocation.ptr !is null;
}

private bool tryPrepareStringTransform(
    Arena* arena,
    size_t length,
    scope char[]* allocation,
) @trusted
{
    if (length == 0)
        return true;
    *allocation = arena.tryAllocateArray!char(length);
    return allocation.ptr !is null;
}

private void commitStringTransform(
    Allocator* allocator,
    char[] allocation,
    scope OwnedString* output,
) @system
{
    if (allocation.length == 0)
    {
        OwnedString result = OwnedString.create(allocator);
        moveEmplace(result, *output);
        return;
    }
    adoptExactOwnedString(allocator, allocation, output);
}

private void commitStringTransform(
    Arena*,
    char[] allocation,
    scope String* output,
) @trusted
{
    *output = allocation;
}

private void requireEmptyOwnedStringOutput(
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    requireValidOwnedStringAllocator(allocator);
    version (XTB_Checked)
    {
        require(output !is null, "OwnedString output pointer is null");
        require(output.allocator_ is null && output.storage_.empty,
            "OwnedString output is not empty");
    }
}

private void adoptExactOwnedString(
    Allocator* allocator,
    char[] allocation,
    scope OwnedString* output,
) @system
{
    RawArrayStorage!char raw = RawArrayStorage!char.adopt(
        allocation.ptr,
        allocation.length,
        allocation.length,
    );
    OwnedStringUnmanaged storage = OwnedStringUnmanaged.adoptExact(&raw);
    OwnedString result = OwnedString.adoptUnmanaged(allocator, &storage);
    moveEmplace(result, *output);
}

private void requireValidOwnedStringAllocator(Allocator* allocator) @trusted
{
    version (XTB_Checked)
        require(allocator !is null && *allocator !is null,
            "OwnedString requires a valid allocator");
}

static assert(OwnedStringUnmanaged.sizeof == String.sizeof);
static assert(OwnedString.sizeof == (Allocator*).sizeof + String.sizeof);
static assert(__traits(compiles, (scope OwnedString* value) @safe {
        Allocator* allocator = value.allocator;
    }));
static assert(!__traits(compiles, (scope const OwnedString* value) @safe {
        Allocator* allocator = value.allocator;
    }));

unittest
{
    import core.internal.traits : hasElaborateDestructor;
    import xtb.lifetime : needsDeinit;
    import xtb.allocators.instrumented : InstrumentedAllocator;
    import xtb.allocators.malloc : mallocAllocator;

    OwnedString empty = OwnedString.fromString(mallocAllocator(), "");
    assert(empty.empty);
    assert(empty.allocator is mallocAllocator());

    OwnedString text = OwnedString.fromString(mallocAllocator(), "hello");
    assert(text.view == "hello");
    assert(text.equal("hello"));
    assert(text.byteLength == 5);
    assert(text.toHash == hashValue("hello"));
    static assert(!__traits(isCopyable, OwnedString));
    static assert(!__traits(isCopyable, OwnedStringUnmanaged));
    static assert(!hasElaborateDestructor!OwnedString);
    static assert(!hasElaborateDestructor!OwnedStringUnmanaged);
    static assert(needsDeinit!OwnedString);
    static assert(!__traits(compiles, (ref OwnedString left,
            ref OwnedString right) { left = move(right); }));
    static assert(!__traits(compiles, (ref OwnedStringUnmanaged left,
            ref OwnedStringUnmanaged right) { left = move(right); }));
    static assert(!__traits(compiles,
            OwnedStringUnmanaged.adoptExact(cast(String) "borrowed")));

    OwnedString copy = text.clone(mallocAllocator());
    assert(copy == text);
    assert(copy.equal(text));
    assert(copy.view.ptr !is text.view.ptr);

    StringBuf exact = StringBuf.fromString(mallocAllocator(), "exact");
    const(char)* exactPointer;
    {
        exact.shrinkToFit();
        exactPointer = exact.view.ptr;
    }
    OwnedString bufferCopy = exact.copy(mallocAllocator());
    assert(bufferCopy.view == exact.view);
    assert(bufferCopy.view.ptr !is exactPointer);
    assert(exact.view.ptr is exactPointer);

    StringBufUnmanaged unmanaged = StringBufUnmanaged.fromString(
        mallocAllocator(),
        "unmanaged exact",
    );
    unmanaged.shrinkToFit(mallocAllocator());
    RawArrayStorage!char raw = unmanaged.releaseExactStorage();
    OwnedStringUnmanaged exactUnmanaged =
        OwnedStringUnmanaged.adoptExact(&raw);
    assert(raw.data is null && raw.length == 0 && raw.capacity == 0);
    assert(exactUnmanaged.view == "unmanaged exact");
    exactUnmanaged.deinit(mallocAllocator());

    import xtb.allocators.instrumented : AllocationRecord;

    AllocationRecord[8] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    StringBuf source = StringBuf.fromString(mallocAllocator(), "retained");
    failing.failAfter(0);
    OwnedString failed;
    assert(!source.tryCopy(failing.allocator, &failed));
    {
        assert(source.view == "retained");
        source.deinit();
    }
    assert(failed.allocator is null && failed.empty);
    assert(failing.clean);

    failed.deinit();
    bufferCopy.deinit();
    exact.deinit();
    copy.deinit();
    text.deinit();
    empty.deinit();
}

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : mallocAllocator;

    AllocationRecord[16] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    OwnedStringUnmanaged exact;
    assert(OwnedStringUnmanaged.tryFromString(
            allocator.allocator,
            "sixteen bytes!!!",
            &exact,
    ));
    assert(exact.byteLength == 16);
    assert(allocator.stats.outstandingAllocations == 1);
    assert(allocator.stats.outstandingBytes == 16);
    exact.deinit(allocator.allocator);
    assert(allocator.clean);

    const allocationCalls = allocator.stats.allocationCalls;
    OwnedString empty = OwnedString.fromString(allocator.allocator, "");
    assert(empty.empty);
    assert(empty.allocator is allocator.allocator);
    assert(allocator.stats.allocationCalls == allocationCalls);

    StringBuf spare = StringBuf.withCapacity(allocator.allocator, 64);
    {
        spare.append("small");
    }
    OwnedString compact = spare.copy(allocator.allocator);
    assert(compact.view == "small");
    assert(compact.byteLength == 5);
    assert(compact.view.ptr !is spare.view.ptr);
    assert(spare.view == "small");

    AllocationRecord[8] foreignRecords;
    InstrumentedAllocator foreign = InstrumentedAllocator.create(
        mallocAllocator(),
        foreignRecords[],
    );
    StringBuf foreignBuffer = StringBuf.fromString(
        foreign.allocator,
        "foreign",
    );
    const(char)* foreignPointer;
    {
        foreignPointer = foreignBuffer.view.ptr;
    }
    OwnedString normalized = foreignBuffer.copy(allocator.allocator);
    assert(normalized.view == "foreign");
    assert(normalized.view.ptr !is foreignPointer);
    assert(foreignBuffer.view == "foreign");
    foreignBuffer.deinit();
    assert(foreign.clean);

    normalized.deinit();
    compact.deinit();
    spare.deinit();
    empty.deinit();
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
    assert(foreign.stats.invalidCalls == 0);
}

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : mallocAllocator;

    static assert(is(typeof("copy".copy(mallocAllocator())) == OwnedString));
    static assert(is(typeof("a".concat("b", mallocAllocator())) == OwnedString));
    static assert(is(typeof("a".replace("a", "b", mallocAllocator())) == OwnedString));
    static assert(is(typeof("a".escape(mallocAllocator())) == OwnedString));
    static assert(!is(typeof("copy".tryCopy(
            mallocAllocator(),
            cast(String*) null,
            ))));

    AllocationRecord[32] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    OwnedString copied = "copy".copy(allocator.allocator);
    assert(copied == "copy");
    assert(allocator.stats.outstandingBytes == copied.byteLength);
    copied.deinit();
    assert(allocator.clean);

    OwnedString concatenated = "left".concat("right", allocator.allocator);
    assert(concatenated == "leftright");
    assert(allocator.stats.outstandingBytes == concatenated.byteLength);
    concatenated.deinit();
    assert(allocator.clean);

    OwnedString replaced = "one two one".replace(
        "one",
        "1",
        allocator.allocator,
    );
    assert(replaced == "1 two 1");
    assert(allocator.stats.outstandingBytes == replaced.byteLength);
    replaced.deinit();
    assert(allocator.clean);

    String[3] parts = ["a", "b", "c"];
    OwnedString joined = parts[].join("/", allocator.allocator);
    assert(joined == "a/b/c");
    assert(allocator.stats.outstandingBytes == joined.byteLength);
    joined.deinit();
    assert(allocator.clean);

    OwnedString escaped = "a\n\t\\b".escape(allocator.allocator);
    assert(escaped == "a\\n\\t\\\\b");
    assert(allocator.stats.outstandingBytes == escaped.byteLength);
    escaped.deinit();
    assert(allocator.clean);

    const allocationCalls = allocator.stats.allocationCalls;
    OwnedString empty = "".concat("", allocator.allocator);
    assert(empty.empty && empty.allocator is allocator.allocator);
    assert(allocator.stats.allocationCalls == allocationCalls);
    empty.deinit();

    allocator.failAfter(0);
    OwnedString failedCopy;
    OwnedString failedConcat;
    OwnedString failedReplace;
    OwnedString failedJoin;
    OwnedString failedEscape;
    assert(!"copy".tryCopy(allocator.allocator, &failedCopy));
    assert(!"a".tryConcat("b", allocator.allocator, &failedConcat));
    assert(!"a".tryReplace("a", "b", allocator.allocator, &failedReplace));
    assert(!parts[].tryJoin("/", allocator.allocator, &failedJoin));
    assert(!"\n".tryEscape(allocator.allocator, &failedEscape));
    assert(failedCopy.allocator is null && failedCopy.empty);
    assert(failedConcat.allocator is null && failedConcat.empty);
    assert(failedReplace.allocator is null && failedReplace.empty);
    assert(failedJoin.allocator is null && failedJoin.empty);
    assert(failedEscape.allocator is null && failedEscape.empty);
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
}
