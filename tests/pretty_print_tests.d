module tests.pretty_print_tests;

import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.owned_string : OwnedString, OwnedStringUnmanaged;
import xtb.core.pretty_print;
import xtb.core.print : Writer, writeBuffer;
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

static assert(!__traits(compiles,
        (ref ConflictingFormatTestValue value) { char[16] storage; writeBuffer(storage[], value); }));
static assert(!__traits(compiles,
        (ref RecursiveFormatTestValue value) { char[16] storage; writeBuffer(storage[], value); }));

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
    static foreach (testFunction; __traits(getUnitTests, xtb.core.pretty_print))
        testFunction();
    return 0;
}
