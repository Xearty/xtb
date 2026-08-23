module xtb.core.allocators.internal.virtual_memory;

nothrow @nogc:

version (linux)
{
    private import backend = xtb.core.allocators.internal.virtual_memory_linux;
}
else
{
    private import backend = xtb.core.allocators.internal.virtual_memory_unsupported;
}

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.panic : panic;

/// Whether this target has XTB's native virtual-memory backend.
package(xtb) enum bool virtualMemorySupported =
    backend.virtualMemorySupported;

/// One reserved contiguous virtual-address range.
///
/// The reservation owns only address space until pages are committed. It is an
/// explicit non-copyable owner; call `deinit` when the reservation is no longer
/// needed. The reservation does not track committed subranges; its internal
/// consumer owns that policy and bookkeeping.
package(xtb) struct VirtualMemoryReservation
{
nothrow @nogc:

private:
    void* base_;
    size_t reservedBytes_;

public:
    @disable this(this);
    @disable ref VirtualMemoryReservation opAssign(VirtualMemoryReservation source) return;

    /// First address in the reserved range, or null for the inert state.
    void* base() @system
    {
        return base_;
    }

    /// Page-rounded size of the reserved address range.
    size_t reservedBytes() const pure @safe
    {
        return reservedBytes_;
    }

    bool active() const pure @safe
    {
        return base_ !is null;
    }

    /// Makes a page-aligned subrange readable and writable.
    ///
    /// Returns false for an inactive reservation, an invalid/non-page-aligned
    /// range, an unsupported backend, or a native commit failure. A zero-length
    /// range is always a successful no-op.
    bool tryCommit(size_t offset, size_t bytes) @system
    {
        if (bytes == 0)
            return true;
        if (!validPageRange(base_, reservedBytes_, offset, bytes))
            return false;

        return backend.tryCommitVirtualMemoryBackend(
            byteAddress(base_, offset),
            bytes,
        );
    }

    /// Returns a page-aligned subrange to its inaccessible, uncommitted state.
    ///
    /// Successful decommit discards the previous anonymous-page contents; a
    /// later successful commit observes zero-filled pages. Returns false under
    /// the same conditions as `tryCommit`, plus native decommit failure. A
    /// zero-length range is always a successful no-op.
    bool tryDecommit(size_t offset, size_t bytes) @system
    {
        if (bytes == 0)
            return true;
        if (!validPageRange(base_, reservedBytes_, offset, bytes))
            return false;

        return backend.tryDecommitVirtualMemoryBackend(
            byteAddress(base_, offset),
            bytes,
        );
    }

    /// Releases the complete reservation. The inert state is accepted.
    void deinit() @system
    {
        if (base_ is null)
        {
            reservedBytes_ = 0;
            return;
        }

        void* base = base_;
        const reservedBytes = reservedBytes_;
        base_ = null;
        reservedBytes_ = 0;

        if (!backend.releaseVirtualMemoryBackend(base, reservedBytes))
            panic("virtual-memory release failed");
    }
}

/// Returns the native VM page size, or zero when virtual memory is unsupported.
package(xtb) size_t virtualMemoryPageSize() @system
{
    return backend.virtualMemoryPageSizeBackend();
}

/// Attempts to reserve at least `bytes` of contiguous virtual address space.
///
/// `output` must point to an inert reservation. The actual reservation is
/// rounded up to a whole number of native pages and starts inaccessible. A
/// zero-byte request succeeds and leaves `output` inert. Unsupported targets,
/// size overflow, page-size failure, and native reservation failure return
/// false and leave `output` inert.
package(xtb) bool tryReserveVirtualMemory(
    size_t bytes,
    scope VirtualMemoryReservation* output,
) @system
{
    version (XTB_Checked)
    {
        require(output !is null, "VirtualMemoryReservation output is null");
        require(!output.active, "VirtualMemoryReservation output is active");
    }

    if (bytes == 0)
        return true;
    if (!virtualMemorySupported)
        return false;

    const pageSize = virtualMemoryPageSize();
    size_t reservedBytes;
    if (pageSize == 0 || !roundUpToMultiple(bytes, pageSize, &reservedBytes))
        return false;

    void* base = backend.tryReserveVirtualMemoryBackend(reservedBytes);
    if (base is null)
        return false;

    output.base_ = base;
    output.reservedBytes_ = reservedBytes;
    return true;
}

private bool validPageRange(
    void* base,
    size_t reservedBytes,
    size_t offset,
    size_t bytes,
) @system
{
    if (!virtualMemorySupported || base is null)
        return false;
    if (offset > reservedBytes || bytes > reservedBytes - offset)
        return false;

    const pageSize = virtualMemoryPageSize();
    return pageSize != 0 &&
        offset % pageSize == 0 &&
        bytes % pageSize == 0;
}

private bool roundUpToMultiple(
    size_t value,
    size_t multiple,
    size_t* result,
) pure @safe
{
    if (multiple == 0)
        return false;
    const remainder = value % multiple;
    if (remainder == 0)
    {
        *result = value;
        return true;
    }

    const increment = multiple - remainder;
    if (value > size_t.max - increment)
        return false;
    *result = value + increment;
    return true;
}

private void* byteAddress(void* base, size_t offset) @system
{
    return cast(void*)(cast(ubyte*) base + offset);
}

unittest
{
    import xtb.core.lifetime : needsDeinit;

    static assert(!__traits(isCopyable, VirtualMemoryReservation));
    static assert(needsDeinit!VirtualMemoryReservation);
    static assert(__traits(compiles, () nothrow @nogc @system {
            VirtualMemoryReservation value;
            cast(void) value.base;
            cast(void) value.reservedBytes;
            cast(void) value.active;
            cast(void) value.tryCommit(0, 0);
            cast(void) value.tryDecommit(0, 0);
            value.deinit();
        }));

    VirtualMemoryReservation zero;
    assert(tryReserveVirtualMemory(0, &zero));
    assert(!zero.active);
    assert(zero.reservedBytes == 0);
    assert(zero.tryCommit(0, 0));
    assert(zero.tryDecommit(0, 0));
    assert(!zero.tryCommit(0, 4096));
    assert(!zero.tryDecommit(0, 4096));
    zero.deinit();

    version (linux)
    {
        assert(virtualMemorySupported);
        const pageSize = virtualMemoryPageSize();
        assert(pageSize != 0);

        VirtualMemoryReservation overflow;
        assert(!tryReserveVirtualMemory(size_t.max, &overflow));
        assert(!overflow.active);
        overflow.deinit();

        VirtualMemoryReservation memory;
        assert(tryReserveVirtualMemory(pageSize + 1, &memory));
        assert(memory.active);
        assert(memory.base !is null);
        assert(memory.reservedBytes == pageSize * 2);
        assert(cast(size_t) memory.base % pageSize == 0);

        assert(!memory.tryCommit(1, pageSize));
        assert(!memory.tryCommit(0, pageSize - 1));
        assert(!memory.tryCommit(pageSize * 2, pageSize));

        assert(memory.tryCommit(0, pageSize));
        ubyte* bytes = cast(ubyte*) memory.base;
        bytes[0] = 0xA5;
        bytes[pageSize - 1] = 0x5A;
        assert(bytes[0] == 0xA5);
        assert(bytes[pageSize - 1] == 0x5A);

        assert(memory.tryDecommit(0, pageSize));
        assert(memory.tryCommit(0, pageSize));
        assert(bytes[0] == 0);
        assert(bytes[pageSize - 1] == 0);

        memory.deinit();
        assert(!memory.active);
        assert(memory.base is null);
        assert(memory.reservedBytes == 0);
        memory.deinit();
    }
    else
    {
        assert(!virtualMemorySupported);
        assert(virtualMemoryPageSize() == 0);
        VirtualMemoryReservation unavailable;
        assert(!tryReserveVirtualMemory(4096, &unavailable));
        assert(!unavailable.active);
        assert(!unavailable.tryCommit(0, 4096));
        assert(!unavailable.tryDecommit(0, 4096));
        unavailable.deinit();
    }
}
