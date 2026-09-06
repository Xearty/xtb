module xtb.allocators.malloc;

nothrow @nogc:

import core.stdc.stdlib;
import core.stdc.string;

import xtb.memory;
import xtb.types;

private __gshared Allocator malloc_allocator_slot = &malloc_allocator_procedure;

/// Returns XTB's process-wide libc-backed allocator.
Allocator* malloc_allocator() @trusted
{
    return &malloc_allocator_slot;
}

private bool is_power_of_two(usize value) pure @safe
{
    return value != 0 && (value & (value - 1)) == 0;
}

private usize normalized_alignment(usize alignment) pure @safe
{
    const minimum = (void*).alignof;
    return alignment < minimum ? minimum : alignment;
}

private bool add_overflows(usize left, usize right) pure @safe
{
    return left > usize.max - right;
}

private void* allocate_aligned(usize size, usize alignment) @system
{
    // Allocate enough room to align the returned address and retain the base
    // allocation immediately before it. This uses only ISO C malloc/free, so
    // importing the malloc allocator remains portable across XTB targets.
    const header_size = (void*).sizeof;
    const extra = alignment - 1;
    if (add_overflows(size, extra) || add_overflows(size + extra, header_size))
        return null;

    void* base = malloc(size + extra + header_size);
    if (base is null) return null;

    const raw = cast(usize) base + header_size;
    const aligned = (raw + extra) & ~extra;
    void* result = cast(void*) aligned;
    (cast(void**) result)[-1] = base;
    return result;
}

private void free_aligned(void* pointer) @system
{
    if (pointer !is null) free((cast(void**) pointer)[-1]);
}

private extern (C) void* malloc_allocator_procedure(
    void*,
    usize new_size,
    void* old_pointer,
    usize old_size,
    usize alignment,
) @system
{
    alignment = normalized_alignment(alignment);
    if (!is_power_of_two(alignment)) return null;

    if (new_size == 0)
    {
        if (alignment <= (void*).alignof)
        {
            free(old_pointer);
        }
        else
        {
            free_aligned(old_pointer);
        }

        return null;
    }

    if (alignment <= (void*).alignof)
        return realloc(old_pointer, new_size);

    void* replacement = allocate_aligned(new_size, alignment);
    if (replacement is null) return null;

    if (old_pointer !is null)
    {
        const copy_size = old_size < new_size ? old_size : new_size;
        if (copy_size != 0) memcpy(replacement, old_pointer, copy_size);

        free_aligned(old_pointer);
    }

    return replacement;
}

unittest
{
    Allocator* allocator = malloc_allocator();
    assert(allocator !is null && *allocator !is null);

    void* ordinary = allocator.allocate(32, (void*).alignof);
    assert(ordinary !is null);
    allocator.deallocate(ordinary, 32, (void*).alignof);

    enum usize alignment = 64;
    u8* aligned = cast(u8*) allocator.allocate(17, alignment);
    assert(aligned !is null);
    assert((cast(usize) aligned & (alignment - 1)) == 0);
    foreach (index; 0 .. 17)
        aligned[index] = cast(u8)(index + 1);

    aligned = cast(u8*) allocator.reallocate(97, aligned, 17, alignment);
    assert((cast(usize) aligned & (alignment - 1)) == 0);
    foreach (index; 0 .. 17)
        assert(aligned[index] == cast(u8)(index + 1));

    allocator.deallocate(aligned, 97, alignment);
}
