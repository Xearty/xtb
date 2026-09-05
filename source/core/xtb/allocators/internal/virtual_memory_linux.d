module xtb.allocators.internal.virtual_memory_linux;

version (linux)
{
    nothrow @nogc:

    import core.sys.posix.sys.mman;
    import core.sys.posix.unistd;

    import xtb.types;

    package(xtb.allocators.internal) enum bool virtual_memory_supported = true;

    package(xtb.allocators.internal) usize virtual_memory_page_size_backend() @trusted
    {
        // sysconf writes no memory and its signed result is validated before
        // conversion to the address-sized type exposed by this backend.
        const value = sysconf(_SC_PAGESIZE);
        if (value <= 0 || cast(u64) value > usize.max) return 0;

        return cast(usize) value;
    }

    /// Reserves an inaccessible native mapping that the caller must release.
    package(xtb.allocators.internal) void* try_reserve_virtual_memory_backend(
        usize bytes,
    ) @system
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

    /// Makes a range within an owned reservation accessible.
    /// `address` and `bytes` must describe a complete page-aligned subrange.
    package(xtb.allocators.internal) bool try_commit_virtual_memory_backend(
        void* address,
        usize bytes,
    ) @system
    {
        return mprotect(address, bytes, PROT_READ | PROT_WRITE) == 0;
    }

    /// Replaces a range within an owned reservation with fresh pages.
    /// `address` and `bytes` must describe a complete page-aligned subrange.
    package(xtb.allocators.internal) bool try_decommit_virtual_memory_backend(
        void* address,
        usize bytes,
    ) @system
    {
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
        if (replacement == MAP_FAILED) return false;

        if (replacement != address)
        {
            cast(void) munmap(replacement, bytes);
            return false;
        }
        return true;
    }

    /// Releases a complete native reservation owned by the caller.
    /// `address` and `bytes` must exactly match that reservation.
    package(xtb.allocators.internal) bool release_virtual_memory_backend(
        void* address,
        usize bytes,
    ) @system
    {
        return munmap(address, bytes) == 0;
    }
}
