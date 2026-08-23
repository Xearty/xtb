module xtb.core.allocators.internal.virtual_memory_linux;

// dfmt off
version (linux):
// dfmt on
nothrow @nogc:

import core.sys.posix.sys.mman : MAP_ANON,
    MAP_FAILED,
    MAP_FIXED,
    MAP_PRIVATE,
    PROT_NONE,
    PROT_READ,
    PROT_WRITE,
    mmap,
    mprotect,
    munmap;
import core.sys.posix.unistd : _SC_PAGESIZE, sysconf;

package(xtb.core.allocators.internal) enum bool virtualMemorySupported = true;

package(xtb.core.allocators.internal) size_t virtualMemoryPageSizeBackend() @system
{
    const value = sysconf(_SC_PAGESIZE);
    if (value <= 0 || cast(ulong) value > size_t.max)
        return 0;
    return cast(size_t) value;
}

package(xtb.core.allocators.internal) void* tryReserveVirtualMemoryBackend(size_t bytes) @system
{
    void* result = mmap(
        null,
        bytes,
        PROT_NONE,
        MAP_PRIVATE | MAP_ANON,
        -1,
        0,
    );
    return result == MAP_FAILED ? null : result;
}

package(xtb.core.allocators.internal) bool tryCommitVirtualMemoryBackend(void* address, size_t bytes) @system
{
    return mprotect(address, bytes, PROT_READ | PROT_WRITE) == 0;
}

package(xtb.core.allocators.internal) bool tryDecommitVirtualMemoryBackend(
    void* address,
    size_t bytes,
) @system
{
    // Replace the committed subrange with fresh inaccessible anonymous pages.
    // MAP_FIXED is safe here because the validated caller range lies entirely
    // inside a reservation owned by this subsystem. Replacement both discards
    // the old physical backing and guarantees zero-filled contents after a
    // later commit.
    void* replacement = mmap(
        address,
        bytes,
        PROT_NONE,
        MAP_PRIVATE | MAP_ANON | MAP_FIXED,
        -1,
        0,
    );
    if (replacement == MAP_FAILED)
        return false;
    if (replacement != address)
    {
        cast(void) munmap(replacement, bytes);
        return false;
    }
    return true;
}

package(xtb.core.allocators.internal) bool releaseVirtualMemoryBackend(void* address, size_t bytes) @system
{
    return munmap(address, bytes) == 0;
}
