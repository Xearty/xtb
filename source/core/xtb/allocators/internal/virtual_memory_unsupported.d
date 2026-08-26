module xtb.allocators.internal.virtual_memory_unsupported;

nothrow @nogc:

package(xtb.allocators.internal) enum bool virtualMemorySupported = false;

package(xtb.allocators.internal) size_t virtualMemoryPageSizeBackend() pure @safe
{
    return 0;
}

package(xtb.allocators.internal) void* tryReserveVirtualMemoryBackend(size_t) @system
{
    return null;
}

package(xtb.allocators.internal) bool tryCommitVirtualMemoryBackend(void*, size_t) @system
{
    return false;
}

package(xtb.allocators.internal) bool tryDecommitVirtualMemoryBackend(void*, size_t) @system
{
    return false;
}

package(xtb.allocators.internal) bool releaseVirtualMemoryBackend(void*, size_t) @system
{
    return false;
}

unittest
{
    assert(!virtualMemorySupported);
    assert(virtualMemoryPageSizeBackend() == 0);
    assert(tryReserveVirtualMemoryBackend(4096) is null);
    assert(!tryCommitVirtualMemoryBackend(null, 4096));
    assert(!tryDecommitVirtualMemoryBackend(null, 4096));
    assert(!releaseVirtualMemoryBackend(null, 4096));
}
