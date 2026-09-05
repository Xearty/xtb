module xtb.allocators.internal.virtual_memory_unsupported;

nothrow @nogc:

package(xtb.allocators.internal) enum bool virtualMemorySupported = false;

package(xtb.allocators.internal) alias virtual_memory_supported =
    virtualMemorySupported;

package(xtb.allocators.internal) size_t virtualMemoryPageSizeBackend() pure @safe
{
    return 0;
}

package(xtb.allocators.internal) alias virtual_memory_page_size_backend =
    virtualMemoryPageSizeBackend;

package(xtb.allocators.internal) void* tryReserveVirtualMemoryBackend(size_t) @system
{
    return null;
}

package(xtb.allocators.internal) alias try_reserve_virtual_memory_backend =
    tryReserveVirtualMemoryBackend;

package(xtb.allocators.internal) bool tryCommitVirtualMemoryBackend(void*, size_t) @system
{
    return false;
}

package(xtb.allocators.internal) alias try_commit_virtual_memory_backend =
    tryCommitVirtualMemoryBackend;

package(xtb.allocators.internal) bool tryDecommitVirtualMemoryBackend(void*, size_t) @system
{
    return false;
}

package(xtb.allocators.internal) alias try_decommit_virtual_memory_backend =
    tryDecommitVirtualMemoryBackend;

package(xtb.allocators.internal) bool releaseVirtualMemoryBackend(void*, size_t) @system
{
    return false;
}

package(xtb.allocators.internal) alias release_virtual_memory_backend =
    releaseVirtualMemoryBackend;

unittest
{
    assert(!virtualMemorySupported);
    assert(virtualMemoryPageSizeBackend() == 0);
    assert(tryReserveVirtualMemoryBackend(4096) is null);
    assert(!tryCommitVirtualMemoryBackend(null, 4096));
    assert(!tryDecommitVirtualMemoryBackend(null, 4096));
    assert(!releaseVirtualMemoryBackend(null, 4096));
}
