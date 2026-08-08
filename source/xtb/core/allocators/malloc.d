module xtb.core.allocators.malloc;

nothrow @nogc:

import core.stdc.stdlib : free, malloc, realloc;
import core.stdc.string : memcpy;
import xtb.core.memory : Allocator;

private __gshared Allocator mallocAllocatorSlot = &mallocAllocatorProcedure;

/// Returns XTB's process-wide libc-backed allocator.
Allocator* mallocAllocator() @trusted
{
    return &mallocAllocatorSlot;
}

private bool isPowerOfTwo(size_t value) pure @safe
{
    return value != 0 && (value & (value - 1)) == 0;
}

private size_t normalizedAlignment(size_t alignment) pure @safe
{
    const minimum = (void*).alignof;
    return alignment < minimum ? minimum : alignment;
}

private bool addOverflows(size_t left, size_t right) pure @safe
{
    return left > size_t.max - right;
}

private void* allocateAligned(size_t size, size_t alignment) @system
{
    // Allocate enough room to align the returned address and retain the base
    // allocation immediately before it. This uses only ISO C malloc/free, so
    // importing the malloc allocator remains portable across XTB targets.
    const headerSize = (void*).sizeof;
    const extra = alignment - 1;
    if (addOverflows(size, extra) || addOverflows(size + extra, headerSize))
        return null;

    void* base = malloc(size + extra + headerSize);
    if (base is null)
        return null;

    const raw = cast(size_t) base + headerSize;
    const aligned = (raw + extra) & ~extra;
    void* result = cast(void*) aligned;
    (cast(void**) result)[-1] = base;
    return result;
}

private void freeAligned(void* pointer) @system
{
    if (pointer !is null)
        free((cast(void**) pointer)[-1]);
}

private extern (C) void* mallocAllocatorProcedure(
    void*,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) @system
{
    alignment = normalizedAlignment(alignment);
    if (!isPowerOfTwo(alignment))
        return null;

    if (newSize == 0)
    {
        if (alignment <= (void*).alignof)
            free(oldPointer);
        else
            freeAligned(oldPointer);
        return null;
    }

    if (alignment <= (void*).alignof)
        return realloc(oldPointer, newSize);

    void* replacement = allocateAligned(newSize, alignment);
    if (replacement is null)
        return null;

    if (oldPointer !is null)
    {
        const copySize = oldSize < newSize ? oldSize : newSize;
        if (copySize != 0)
            memcpy(replacement, oldPointer, copySize);
        freeAligned(oldPointer);
    }
    return replacement;
}

unittest
{
    import xtb.core.memory : allocate, deallocate, reallocate;

    Allocator* allocator = mallocAllocator();
    assert(allocator !is null && *allocator !is null);

    void* ordinary = allocator.allocate(32, (void*).alignof);
    assert(ordinary !is null);
    allocator.deallocate(ordinary, 32, (void*).alignof);

    enum size_t alignment = 64;
    ubyte* aligned = cast(ubyte*) allocator.allocate(17, alignment);
    assert(aligned !is null);
    assert((cast(size_t) aligned & (alignment - 1)) == 0);
    foreach (index; 0 .. 17)
        aligned[index] = cast(ubyte)(index + 1);

    aligned = cast(ubyte*) allocator.reallocate(97, aligned, 17, alignment);
    assert((cast(size_t) aligned & (alignment - 1)) == 0);
    foreach (index; 0 .. 17)
        assert(aligned[index] == cast(ubyte)(index + 1));
    allocator.deallocate(aligned, 97, alignment);
}
