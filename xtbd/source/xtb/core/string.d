module xtb.core.string;

public import xtb.core.types : String;

import core.stdc.string : memcmp, memmove;
import xtb.core.array : Array;
import xtb.core.array : appendArray = append;
import xtb.core.array : clearArray = clear;
import xtb.core.array : reserveArray = reserve;
import xtb.core.array : resizeArray = resize;
import xtb.core.array : tryAppendArray = tryAppend;
import xtb.core.array : tryReserveArray = tryReserve;
import xtb.core.memory : Allocator, allocate;
import xtb.core.panic : panic, require;

enum notFound = size_t.max;

bool equal(String left, String right) pure nothrow @system @nogc
{
    if (left.length != right.length)
        return false;
    return left.length == 0 || memcmp(left.ptr, right.ptr, left.length) == 0;
}

int compare(String left, String right) pure nothrow @system @nogc
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
    pure nothrow @safe @nogc
{
    assert(begin <= end && end <= value.length);
    return value[begin .. end];
}

String head(String value, size_t count) pure nothrow @safe @nogc
{
    return value.slice(0, count < value.length ? count : value.length);
}

String tail(String value, size_t count) pure nothrow @safe @nogc
{
    const amount = count < value.length ? count : value.length;
    return value.slice(value.length - amount, value.length);
}

String truncateLeft(String value, size_t count) pure nothrow @safe @nogc
{
    const amount = count < value.length ? count : value.length;
    return value[amount .. $];
}

String truncateRight(String value, size_t count) pure nothrow @safe @nogc
{
    const amount = count < value.length ? count : value.length;
    return value[0 .. value.length - amount];
}

size_t find(String value, String needle) pure nothrow @system @nogc
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

size_t find(String value, char needle) pure nothrow @safe @nogc
{
    foreach (i, character; value)
    {
        if (character == needle)
            return i;
    }
    return notFound;
}

size_t findLast(String value, String needle) pure nothrow @system @nogc
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

size_t findLast(String value, char needle) pure nothrow @safe @nogc
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

String baseName(String value) pure nothrow @safe @nogc
{
    const slash = value.findLast('/');
    const backslash = value.findLast('\\');
    const separator = slash == notFound ? backslash :
        backslash == notFound ? slash : slash > backslash ? slash : backslash;
    return separator == notFound ? value : value[separator + 1 .. $];
}

String stripExtension(String value) pure nothrow @safe @nogc
{
    const extension = value.findLast('.');
    const baseOffset = value.length - value.baseName.length;
    return extension == notFound || extension < baseOffset ? value : value[0 .. extension];
}

bool contains(String value, String needle) pure nothrow @system @nogc
{
    return value.find(needle) != notFound;
}

bool startsWith(String value, String prefix) pure nothrow @system @nogc
{
    return prefix.length <= value.length && value[0 .. prefix.length].equal(prefix);
}

bool endsWith(String value, String suffix) pure nothrow @system @nogc
{
    return suffix.length <= value.length &&
        value[value.length - suffix.length .. $].equal(suffix);
}

private bool isAsciiWhitespace(char value) pure nothrow @safe @nogc
{
    return value == ' ' || value == '\t' || value == '\n' ||
        value == '\r' || value == '\f' || value == '\v';
}

String trimLeft(String value) pure nothrow @safe @nogc
{
    size_t begin;
    while (begin < value.length && isAsciiWhitespace(value[begin]))
        ++begin;
    return value[begin .. $];
}

String trimRight(String value) pure nothrow @safe @nogc
{
    size_t end = value.length;
    while (end != 0 && isAsciiWhitespace(value[end - 1]))
        --end;
    return value[0 .. end];
}

String trim(String value) pure nothrow @safe @nogc
{
    return value.trimLeft().trimRight();
}

String copy(String value, Allocator* allocator) nothrow @nogc
{
    if (value.length == size_t.max)
        panic("String size overflow");
    char* destination = allocator.allocate!char(value.length + 1);
    if (value.length != 0)
        memmove(destination, value.ptr, value.length);
    destination[value.length] = '\0';
    return destination[0 .. value.length];
}

String concat(String left, String right, Allocator* allocator) nothrow @nogc
{
    if (right.length > size_t.max - left.length)
        panic("String size overflow");
    const length = left.length + right.length;
    if (length == size_t.max)
        panic("String size overflow");
    char* destination = allocator.allocate!char(length + 1);
    if (left.length != 0)
        memmove(destination, left.ptr, left.length);
    if (right.length != 0)
        memmove(destination + left.length, right.ptr, right.length);
    destination[length] = '\0';
    return destination[0 .. length];
}

String replace(String value, String from, String to, Allocator* allocator)
    nothrow @nogc
{
    if (from.length == 0)
        return value.copy(allocator);

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
            panic("String size overflow");
        length += count * growth;
    }
    else
        length -= count * (from.length - to.length);

    if (length == size_t.max)
        panic("String size overflow");
    char* destination = allocator.allocate!char(length + 1);
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
    return destination[0 .. length];
}

String join(scope const(String)[] values, String separator, Allocator* allocator)
    nothrow @nogc
{
    size_t length;
    foreach (value; values)
    {
        if (value.length > size_t.max - length)
            panic("String size overflow");
        length += value.length;
    }
    if (values.length > 1)
    {
        const count = values.length - 1;
        if (separator.length != 0 && count > (size_t.max - length) / separator.length)
            panic("String size overflow");
        length += count * separator.length;
    }
    if (length == size_t.max)
        panic("String size overflow");

    char* destination = allocator.allocate!char(length + 1);
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
    return destination[0 .. length];
}

struct StringBuf
{
    private Array!char bytes_;

    @disable this(this);

    static StringBuf create(Allocator* allocator) nothrow @nogc
    {
        StringBuf result;
        result.bytes_ = Array!char.create(allocator);
        return result;
    }

    static StringBuf withCapacity(Allocator* allocator, size_t capacity)
        nothrow @nogc
    {
        StringBuf result;
        result.bytes_ = Array!char.withCapacity(allocator, capacity);
        return result;
    }

    static StringBuf fromString(Allocator* allocator, String value)
        nothrow @nogc
    {
        StringBuf result = withCapacity(allocator, value.length);
        result.append(value);
        return result;
    }

    void deinit() nothrow @nogc
    {
        bytes_.deinit();
    }

    size_t length() const pure nothrow @safe @nogc
    {
        return bytes_.length;
    }

    size_t capacity() const pure nothrow @safe @nogc
    {
        return bytes_.capacity;
    }

    bool empty() const pure nothrow @safe @nogc
    {
        return bytes_.empty;
    }

    Allocator* allocator() return nothrow @nogc
    {
        return bytes_.allocator;
    }

    String view() const return nothrow @system @nogc
    {
        return bytes_.slice;
    }
}

void reserve(ref StringBuf buffer, size_t capacity) nothrow @nogc
{
    buffer.bytes_.reserveArray(capacity);
}

bool tryReserve(ref StringBuf buffer, size_t capacity) nothrow @nogc
{
    return buffer.bytes_.tryReserveArray(capacity);
}

void append(ref StringBuf buffer, String value) nothrow @nogc
{
    buffer.bytes_.appendArray(value);
}

bool tryAppend(ref StringBuf buffer, String value) nothrow @nogc
{
    return buffer.bytes_.tryAppendArray(value);
}

void append(ref StringBuf buffer, char value) nothrow @nogc
{
    buffer.bytes_.appendArray(value);
}

bool tryAppend(ref StringBuf buffer, char value) nothrow @nogc
{
    return buffer.bytes_.tryAppendArray(value);
}

void appendByte(ref StringBuf buffer, char value) nothrow @nogc
{
    buffer.append(value);
}

void prepend(ref StringBuf buffer, String value) nothrow @nogc
{
    if (value.length == 0)
        return;
    if (value.length > size_t.max - buffer.length)
        panic("StringBuf size overflow");

    const oldLength = buffer.length;
    buffer.bytes_.resizeArray(oldLength + value.length);
    memmove(
        buffer.bytes_.slice.ptr + value.length,
        buffer.bytes_.slice.ptr,
        oldLength,
    );
    memmove(buffer.bytes_.slice.ptr, value.ptr, value.length);
}

void clear(ref StringBuf buffer) nothrow @nogc
{
    buffer.bytes_.clearArray();
}

const(char)* cString(ref StringBuf buffer) nothrow @system @nogc
{
    const oldLength = buffer.length;
    buffer.bytes_.resizeArray(oldLength + 1);
    buffer.bytes_[oldLength] = '\0';
    char* pointer = buffer.bytes_.slice.ptr;
    buffer.bytes_.resizeArray(oldLength);
    return pointer;
}

nothrow @nogc unittest
{
    import xtb.core.memory : deallocate, mallocAllocator;

    String text = "  hello world  ";
    assert(text.trim().equal("hello world"));
    assert(text.find("world") == 8);
    assert(text.startsWith("  he"));
    assert(text.endsWith("  "));
    assert("a/b/file.tar".baseName.equal("file.tar"));
    assert("a/b/file.tar".stripExtension.equal("a/b/file"));
    assert("one two one".findLast("one") == 8);

    String replaced = "one two one".replace("one", "1", mallocAllocator());
    assert(replaced.equal("1 two 1"));
    mallocAllocator().deallocate(cast(void*) replaced.ptr, replaced.length + 1);

    String[3] parts = ["a", "b", "c"];
    String joined = parts[].join("/", mallocAllocator());
    assert(joined.equal("a/b/c"));
    mallocAllocator().deallocate(cast(void*) joined.ptr, joined.length + 1);

    StringBuf buffer = StringBuf.fromString(mallocAllocator(), "hello");
    buffer.append(',');
    buffer.append(" world");
    buffer.prepend("say: ");
    assert(buffer.view.equal("say: hello, world"));
    assert(buffer.cString()[buffer.length] == '\0');
}
