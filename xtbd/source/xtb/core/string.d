module xtb.core.string;

nothrow @nogc:

public import xtb.core.types : String;

import core.stdc.string : memcmp, memmove, strlen;
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
import xtb.core.panic : panic, require;

enum notFound = size_t.max;

alias SplitPredicate = size_t function(String rest, void* context);

String fromCString(const(char)* value) @system
{
    require(value !is null, "null C string");
    return value[0 .. strlen(value)];
}

bool tryFromCString(const(char)* value, String* output)
@system
{
    require(output !is null, "String output pointer is null");
    if (value is null)
    {
        *output = null;
        return false;
    }
    *output = value[0 .. strlen(value)];
    return true;
}

bool empty(String value) pure @safe
{
    return value.length == 0;
}

char front(String value) @system
{
    require(value.length != 0, "front of empty String");
    return value[0];
}

char back(String value) @system
{
    require(value.length != 0, "back of empty String");
    return value[value.length - 1];
}

bool equal(String left, String right) pure @system
{
    if (left.length != right.length)
        return false;
    return left.length == 0 || memcmp(left.ptr, right.ptr, left.length) == 0;
}

int compare(String left, String right) pure @system
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

String slice(String value, size_t begin, size_t end)
@safe
{
    require(begin <= end, "String slice begin exceeds end");
    require(end <= value.length, "String slice end out of bounds");
    return value[begin .. end];
}

String head(String value, size_t count) pure @safe
{
    const amount = count < value.length ? count : value.length;
    return value[0 .. amount];
}

String tail(String value, size_t count) pure @safe
{
    const amount = count < value.length ? count : value.length;
    return value[value.length - amount .. value.length];
}

String truncateLeft(String value, size_t count) pure @safe
{
    const amount = count < value.length ? count : value.length;
    return value[amount .. $];
}

String truncateRight(String value, size_t count) pure @safe
{
    const amount = count < value.length ? count : value.length;
    return value[0 .. value.length - amount];
}

size_t find(String value, String needle) pure @system
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

size_t find(String value, char needle) pure @safe
{
    foreach (i, character; value)
    {
        if (character == needle)
            return i;
    }
    return notFound;
}

size_t findLast(String value, String needle) pure @system
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

size_t findLast(String value, char needle) pure @safe
{
    size_t index = value.length;
    while (index != 0)
    {
        --index;
        if (value[index] == needle)
            return index;
    }
    return notFound;
}

String baseName(String value) pure @safe
{
    const slash = value.findLast('/');
    const backslash = value.findLast('\\');
    size_t separator = slash;
    if (separator == notFound ||
        (backslash != notFound && backslash > separator))
        separator = backslash;
    return separator == notFound ? value : value[separator + 1 .. $];
}

String stripExtension(String value) pure @safe
{
    const extension = value.findLast('.');
    const baseOffset = value.length - value.baseName.length;
    return extension == notFound || extension <= baseOffset
        ? value : value[0 .. extension];
}

bool contains(String value, String needle) pure @system
{
    return value.find(needle) != notFound;
}

bool contains(String value, char needle) pure @safe
{
    return value.find(needle) != notFound;
}

bool containsNul(String value) pure @safe
{
    return value.contains('\0');
}

bool startsWith(String value, String prefix) pure @system
{
    return prefix.length <= value.length && value[0 .. prefix.length].equal(prefix);
}

bool endsWith(String value, String suffix) pure @system
{
    return suffix.length <= value.length &&
        value[value.length - suffix.length .. $].equal(suffix);
}

private bool isAsciiWhitespace(char value) pure @safe
{
    return value == ' ' || value == '\t' || value == '\n' ||
        value == '\r' || value == '\f' || value == '\v';
}

String trimLeft(String value) pure @safe
{
    size_t begin;
    while (begin < value.length && isAsciiWhitespace(value[begin]))
        ++begin;
    return value[begin .. $];
}

String trimRight(String value) pure @safe
{
    size_t end = value.length;
    while (end != 0 && isAsciiWhitespace(value[end - 1]))
        --end;
    return value[0 .. end];
}

String trim(String value) pure @safe
{
    return value.trimLeft().trimRight();
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

    static StringBuf withCapacity(Allocator* allocator, size_t capacity)

    {
        StringBuf result;
        result.bytes_ = Array!char.withCapacity(allocator, capacity);
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

    size_t length() const pure @safe
    {
        return bytes_.length;
    }

    size_t capacity() const pure @safe
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

    String view() const return @system
    {
        return bytes_.slice;
    }
}

void reserve(ref StringBuf buffer, size_t capacity)
{
    buffer.bytes_.reserveArray(capacity);
}

bool tryReserve(ref StringBuf buffer, size_t capacity)
{
    return buffer.bytes_.tryReserveArray(capacity);
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
    buffer.bytes_.appendArray(value);
}

bool tryAppend(ref StringBuf buffer, char value)
{
    return buffer.bytes_.tryAppendArray(value);
}

void appendByte(ref StringBuf buffer, char value)
{
    buffer.append(value);
}

void appendAssumeCapacity(ref StringBuf buffer, String value)
{
    buffer.bytes_.appendAssumeCapacityArray(value);
}

void appendAssumeCapacity(ref StringBuf buffer, char value)
{
    buffer.bytes_.appendAssumeCapacityArray(value);
}

bool tryInsert(ref StringBuf buffer, size_t index, String value)
{
    return buffer.bytes_.tryInsertArray(index, value);
}

void insert(ref StringBuf buffer, size_t index, String value)
{
    buffer.bytes_.insertArray(index, value);
}

bool tryPrepend(ref StringBuf buffer, String value)
{
    return buffer.tryInsert(0, value);
}

void prepend(ref StringBuf buffer, String value)
{
    buffer.insert(0, value);
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
    if (value.length != 0 && buffer.length != 0)
    {
        const sourceAddress = cast(size_t) value.ptr;
        const beginAddress = cast(size_t) buffer.view.ptr;
        const byteOffset = sourceAddress - beginAddress;
        aliasesBuffer = sourceAddress >= beginAddress && byteOffset < buffer.length;
        if (aliasesBuffer)
        {
            if (value.length > buffer.length - byteOffset)
                return false;
            sourceOffset = byteOffset;
        }
    }

    size_t escapedCount;
    foreach (character; value)
        if (escapedCharacter(character) != '\0')
            ++escapedCount;
    if (escapedCount > size_t.max - value.length ||
        value.length + escapedCount > size_t.max - buffer.length)
        return false;
    const required = buffer.length + value.length + escapedCount;
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
    const oldLength = buffer.length;
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
    assert(text.trim().equal("hello world"));
    assert(text.find("world") == 8);
    assert(text.startsWith("  he"));
    assert(text.endsWith("  "));
    assert("a/b/file.tar".baseName.equal("file.tar"));
    assert("a/b/file.tar".stripExtension.equal("a/b/file"));
    assert("a/b/.gitignore".stripExtension.equal("a/b/.gitignore"));
    assert("a/b/.config.json".stripExtension.equal("a/b/.config"));
    assert("one two one".findLast("one") == 8);
    assert("hello".front == 'h' && "hello".back == 'o');
    assert("".empty);

    String cView = fromCString("native".ptr);
    assert(cView.equal("native"));

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
    buffer.append(',');
    buffer.append(" world");
    buffer.prepend("say: ");
    assert(buffer.view.equal("say: hello, world"));
    buffer.replaceInPlace("world", "BetterC library");
    assert(buffer.view.equal("say: hello, BetterC library"));
    buffer.replaceInPlace("BetterC library", "D");
    assert(buffer.view.equal("say: hello, D"));
    buffer.appendEscaped("\n");
    assert(buffer.view.endsWith("\\n"));
    assert(buffer.cString()[buffer.length] == '\0');

    StringBuf selfPrepend = StringBuf.fromString(
        mallocAllocator(),
        "abcdefgh",
    );
    selfPrepend.prepend(selfPrepend.view);
    assert(selfPrepend.view.equal("abcdefghabcdefgh"));

    StringBuf selfEscape = StringBuf.fromString(
        mallocAllocator(),
        "a\nbcdefg",
    );
    selfEscape.appendEscaped(selfEscape.view);
    assert(selfEscape.view.equal("a\nbcdefga\\nbcdefg"));

    AllocationRecord[4] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(), records[],
    );
    failing.failAfter(0);
    String failedOutput = "unchanged";
    assert(!"copy".tryCopy(failing.handle, &failedOutput));
    assert(failedOutput.equal("unchanged"));
}
