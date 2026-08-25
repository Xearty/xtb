module tests.pretty_print_tests;

import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.memory : Allocator;
import xtb.core.string : OwnedString, OwnedStringUnmanaged;
import xtb.core.fmt.pretty_print;
import xtb.core.fmt.writer : Writer;
import xtb.core.fmt.fixed_buffer : writeBuffer;
import xtb.core.string : StringBuf, StringBufUnmanaged;

private struct FormatRepresentationTestValue
{
    int value;

    int formatRepresentation() const pure nothrow @nogc @safe
    {
        return value;
    }
}

private struct ConflictingFormatTestValue
{
    int formatRepresentation() const pure nothrow @nogc @safe
    {
        return 1;
    }

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writer.put("conflict");
    }
}

private struct RecursiveFormatTestValue
{
    RecursiveFormatTestValue formatRepresentation() const pure nothrow @nogc @safe
    {
        return this;
    }
}

private struct NonVoidFormatToTestValue
{
    int formatTo(ref Writer writer) const nothrow @nogc
    {
        writer.put("invalid");
        return 1;
    }
}

private struct OwningFormatRepresentationTestValue
{
    Allocator* allocator;

    OwnedString formatRepresentation() nothrow @nogc
    {
        return OwnedString.fromString(allocator, "owned representation");
    }
}

private struct BorrowedOwningFormatRepresentationTestValue
{
    OwnedString* representation;

    ref const(OwnedString) formatRepresentation() const return pure nothrow @nogc @trusted
    {
        return *representation;
    }
}

static assert(!__traits(compiles,
        (ref ConflictingFormatTestValue value) { char[16] storage; writeBuffer(storage[], value); }));
static assert(!__traits(compiles,
        (ref RecursiveFormatTestValue value) { char[16] storage; writeBuffer(storage[], value); }));
static assert(!__traits(compiles,
        (ref NonVoidFormatToTestValue value) { char[16] storage; writeBuffer(storage[], value); }));
static assert(!__traits(compiles,
        (ref OwningFormatRepresentationTestValue value) {
        char[32] storage;
        writeBuffer(storage[], value);
    }));
static assert(__traits(compiles,
        (ref BorrowedOwningFormatRepresentationTestValue value) {
        char[32] storage;
        writeBuffer(storage[], value);
    }));

private void testFormatRepresentation()
{
    char[32] storage;
    FormatRepresentationTestValue value = FormatRepresentationTestValue(42);
    auto result = writeBuffer(storage[], value);
    assert(result.ok && !result.truncated);
    assert(storage[0 .. result.written] == "42");

    auto allocator = mallocAllocator();

    OwnedStringUnmanaged unmanagedOwned =
        OwnedStringUnmanaged.fromString(allocator, "owned-unmanaged");
    result = writeBuffer(storage[], unmanagedOwned);
    assert(result.ok && !result.truncated);
    assert(storage[0 .. result.written] == "owned-unmanaged");
    unmanagedOwned.deinit(allocator);

    OwnedString owned = OwnedString.fromString(allocator, "owned");
    result = writeBuffer(storage[], owned);
    assert(result.ok && !result.truncated);
    assert(storage[0 .. result.written] == "owned");

    auto borrowedRepresentation = BorrowedOwningFormatRepresentationTestValue(&owned);
    result = writeBuffer(storage[], borrowedRepresentation);
    assert(result.ok && !result.truncated);
    assert(storage[0 .. result.written] == "owned");

    owned.deinit();

    StringBufUnmanaged unmanagedBuffer =
        StringBufUnmanaged.fromString(allocator, "buffer-unmanaged");
    result = writeBuffer(storage[], unmanagedBuffer);
    assert(result.ok && !result.truncated);
    assert(storage[0 .. result.written] == "buffer-unmanaged");
    unmanagedBuffer.deinit(allocator);

    StringBuf buffer = StringBuf.fromString(allocator, "buffer");
    result = writeBuffer(storage[], buffer);
    assert(result.ok && !result.truncated);
    assert(storage[0 .. result.written] == "buffer");
    buffer.deinit();
}

extern (C) int main()
{
    testFormatRepresentation();
    return 0;
}
