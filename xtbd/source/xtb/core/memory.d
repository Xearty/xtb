module xtb.core.memory;

import core.stdc.stdlib : aligned_alloc, free, malloc, realloc;
import core.stdc.string : memcpy;
import xtb.core.panic : panic, require;
import xtb.core.types : multiplyOverflows;

alias Allocator = void* function(
    void* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) nothrow @nogc;

private Allocator mallocAllocatorSlot = &mallocAllocatorProcedure;

Allocator* mallocAllocator() nothrow @nogc
{
    return &mallocAllocatorSlot;
}

private bool isPowerOfTwo(size_t value) pure nothrow @safe @nogc
{
    return value != 0 && (value & (value - 1)) == 0;
}

private size_t normalizedAlignment(size_t alignment) pure nothrow @safe @nogc
{
    const minimum = (void*).alignof;
    return alignment < minimum ? minimum : alignment;
}

private bool roundUp(size_t value, size_t alignment, size_t* result)
    pure nothrow @safe @nogc
{
    const remainder = value & (alignment - 1);
    if (remainder == 0)
    {
        *result = value;
        return true;
    }

    const addition = alignment - remainder;
    if (addition > size_t.max - value)
        return false;
    *result = value + addition;
    return true;
}

private void* mallocAllocatorProcedure(
    void*,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) nothrow @nogc
{
    alignment = normalizedAlignment(alignment);
    if (!isPowerOfTwo(alignment))
        return null;

    if (newSize == 0)
    {
        free(oldPointer);
        return null;
    }

    if (alignment <= (void*).alignof)
        return realloc(oldPointer, newSize);

    size_t allocationSize;
    if (!roundUp(newSize, alignment, &allocationSize))
        return null;

    void* replacement = aligned_alloc(alignment, allocationSize);
    if (replacement is null)
        return null;

    if (oldPointer !is null)
    {
        const copySize = oldSize < newSize ? oldSize : newSize;
        if (copySize != 0)
            memcpy(replacement, oldPointer, copySize);
        free(oldPointer);
    }
    return replacement;
}

void* tryReallocate(
    Allocator* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) nothrow @nogc
{
    if (allocator is null || *allocator is null || !isPowerOfTwo(alignment) ||
        (oldPointer is null && oldSize != 0))
        return null;
    return (*allocator)(allocator, newSize, oldPointer, oldSize, alignment);
}

void* reallocate(
    Allocator* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) nothrow @nogc
{
    void* result = tryReallocate(
        allocator,
        newSize,
        oldPointer,
        oldSize,
        alignment,
    );
    if (newSize != 0 && result is null)
        panic("allocation failed");
    return result;
}

void* tryAllocate(
    Allocator* allocator,
    size_t size,
    size_t alignment,
) nothrow @nogc
{
    return tryReallocate(allocator, size, null, 0, alignment);
}

void* allocate(
    Allocator* allocator,
    size_t size,
    size_t alignment,
) nothrow @nogc
{
    return reallocate(allocator, size, null, 0, alignment);
}

T* tryAllocate(T)(Allocator* allocator, size_t count = 1) nothrow @nogc
{
    if (multiplyOverflows(T.sizeof, count))
        return null;
    return cast(T*) tryAllocate(allocator, T.sizeof * count, T.alignof);
}

T* allocate(T)(Allocator* allocator, size_t count = 1) nothrow @nogc
{
    if (multiplyOverflows(T.sizeof, count))
        panic("allocation size overflow");
    return cast(T*) allocate(allocator, T.sizeof * count, T.alignof);
}

void deallocate(
    Allocator* allocator,
    void* pointer,
    size_t oldSize,
    size_t alignment,
) nothrow @nogc
{
    if (pointer is null)
        return;
    require(allocator !is null && *allocator !is null, "invalid allocator");
    (*allocator)(allocator, 0, pointer, oldSize, alignment);
}

void deallocate(T)(Allocator* allocator, T* pointer, size_t count = 1)
    nothrow @nogc
{
    if (multiplyOverflows(T.sizeof, count))
        panic("deallocation size overflow");
    deallocate(allocator, pointer, T.sizeof * count, T.alignof);
}

nothrow @nogc unittest
{
    Allocator* allocator = mallocAllocator();
    int* values = allocator.allocate!int(4);
    assert(values !is null);
    foreach (i; 0 .. 4)
        values[i] = cast(int) i;

    values = cast(int*) allocator.reallocate(
        8 * int.sizeof,
        values,
        4 * int.sizeof,
        int.alignof,
    );
    foreach (i; 0 .. 4)
        assert(values[i] == cast(int) i);
    allocator.deallocate(values, 8);
}
