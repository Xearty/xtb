module xtb.allocators.internal.virtual_memory_unsupported;

import xtb.types;

nothrow @nogc:

package(xtb.allocators.internal) enum bool virtual_memory_supported = false;

package(xtb.allocators.internal) usize virtual_memory_page_size_backend() pure @safe
{
    return 0;
}

package(xtb.allocators.internal) void* try_reserve_virtual_memory_backend(usize) pure @safe
{
    return null;
}

package(xtb.allocators.internal) bool try_commit_virtual_memory_backend(void*, usize) pure @safe
{
    return false;
}

package(xtb.allocators.internal) bool try_decommit_virtual_memory_backend(void*, usize) pure @safe
{
    return false;
}

package(xtb.allocators.internal) bool release_virtual_memory_backend(void*, usize) pure @safe
{
    return false;
}

unittest
{
    assert(!virtual_memory_supported);
    assert(virtual_memory_page_size_backend() == 0);
    assert(try_reserve_virtual_memory_backend(4096) is null);
    assert(!try_commit_virtual_memory_backend(null, 4096));
    assert(!try_decommit_virtual_memory_backend(null, 4096));
    assert(!release_virtual_memory_backend(null, 4096));
}
