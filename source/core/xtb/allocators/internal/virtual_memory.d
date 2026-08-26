module xtb.allocators.internal.virtual_memory;

nothrow @nogc:

version (linux)
{
    private import backend = xtb.allocators.internal.virtual_memory_linux;
}
else
{
    private import backend = xtb.allocators.internal.virtual_memory_unsupported;
}

version (XTB_Checked) import xtb.panic : require;
import xtb.panic : panic;

/// Whether this target has XTB's native virtual-memory backend.
package(xtb) enum bool virtualMemorySupported =
    backend.virtualMemorySupported;

/// One non-owning page-bounded subrange of a virtual-memory reservation.
///
/// A region never releases the underlying mapping and does not track committed
/// pages. It stores the stable mapped address directly rather than a pointer to
/// its reservation owner, so moving that owner does not invalidate the region.
/// The owner must outlive every region borrowed from it.
package(xtb) struct VirtualMemoryRegion
{
nothrow @nogc:

private:
    void* base_;
    size_t bytes_;

public:
    /// First address in the region, or null for an empty region.
    void* base() @system
    {
        return base_;
    }

    /// Page-rounded size of the region.
    size_t bytes() const pure @safe
    {
        return bytes_;
    }

    bool empty() const pure @safe
    {
        return bytes_ == 0;
    }

    /// Makes a page-aligned subrange readable and writable.
    ///
    /// Returns false for an invalid/non-page-aligned range, an unsupported
    /// backend, or a native commit failure. A zero-length range is always a
    /// successful no-op.
    bool tryCommit(size_t offset, size_t bytes) @system
    {
        if (bytes == 0)
            return true;
        if (!validPageRange(base_, bytes_, offset, bytes))
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
        if (!validPageRange(base_, bytes_, offset, bytes))
            return false;

        return backend.tryDecommitVirtualMemoryBackend(
            byteAddress(base_, offset),
            bytes,
        );
    }

    /// Creates a page-bounded non-owning subregion.
    ///
    /// `output` is updated only on success. Empty regions are represented by
    /// `VirtualMemoryRegion.init`.
    bool tryRegion(
        size_t offset,
        size_t bytes,
        scope VirtualMemoryRegion* output,
    ) @system
    {
        version (XTB_Checked)
            require(output !is null, "VirtualMemoryRegion output is null");

        return tryMakeVirtualMemoryRegion(base_, bytes_, offset, bytes, output);
    }
}

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

    /// Creates a page-bounded non-owning region inside this reservation.
    ///
    /// `output` is updated only on success. Empty regions are represented by
    /// `VirtualMemoryRegion.init`. The reservation must outlive the returned
    /// region.
    bool tryRegion(
        size_t offset,
        size_t bytes,
        scope VirtualMemoryRegion* output,
    ) @system
    {
        version (XTB_Checked)
            require(output !is null, "VirtualMemoryRegion output is null");

        return tryMakeVirtualMemoryRegion(
            base_,
            reservedBytes_,
            offset,
            bytes,
            output,
        );
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

private bool tryMakeVirtualMemoryRegion(
    void* base,
    size_t availableBytes,
    size_t offset,
    size_t bytes,
    scope VirtualMemoryRegion* output,
) @system
{
    if (offset > availableBytes || bytes > availableBytes - offset)
        return false;

    if (bytes == 0)
    {
        if (availableBytes != 0 && !validPageBoundary(base, offset))
            return false;

        *output = VirtualMemoryRegion.init;
        return true;
    }

    if (!validPageRange(base, availableBytes, offset, bytes))
        return false;

    VirtualMemoryRegion result;
    result.base_ = byteAddress(base, offset);
    result.bytes_ = bytes;
    *output = result;
    return true;
}

private bool validPageBoundary(void* base, size_t offset) @system
{
    if (!virtualMemorySupported || base is null)
        return false;

    const pageSize = virtualMemoryPageSize();
    return pageSize != 0 && offset % pageSize == 0;
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
    import xtb.lifetime : move, needsDeinit;

    static assert(__traits(isCopyable, VirtualMemoryRegion));
    static assert(!needsDeinit!VirtualMemoryRegion);
    static assert(__traits(compiles, () nothrow @nogc @system {
            VirtualMemoryRegion value;
            VirtualMemoryRegion output;
            cast(void) value.base;
            cast(void) value.bytes;
            cast(void) value.empty;
            cast(void) value.tryCommit(0, 0);
            cast(void) value.tryDecommit(0, 0);
            cast(void) value.tryRegion(0, 0, &output);
        }));

    static assert(!__traits(isCopyable, VirtualMemoryReservation));
    static assert(needsDeinit!VirtualMemoryReservation);
    static assert(__traits(compiles, () nothrow @nogc @system {
            VirtualMemoryReservation value;
            cast(void) value.base;
            cast(void) value.reservedBytes;
            cast(void) value.active;
            VirtualMemoryRegion region;
            cast(void) value.tryRegion(0, 0, &region);
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
    VirtualMemoryRegion zeroRegion;
    assert(zero.tryRegion(0, 0, &zeroRegion));
    assert(zeroRegion.empty);
    assert(zeroRegion.base is null);
    assert(zeroRegion.bytes == 0);
    assert(zeroRegion.tryCommit(0, 0));
    assert(zeroRegion.tryDecommit(0, 0));
    assert(!zeroRegion.tryCommit(0, 4096));
    assert(!zeroRegion.tryDecommit(0, 4096));
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
        assert(tryReserveVirtualMemory(pageSize * 4, &memory));
        assert(memory.active);
        assert(memory.base !is null);
        assert(memory.reservedBytes == pageSize * 4);
        assert(cast(size_t) memory.base % pageSize == 0);

        assert(!memory.tryCommit(1, pageSize));
        assert(!memory.tryCommit(0, pageSize - 1));
        assert(!memory.tryCommit(pageSize * 4, pageSize));

        VirtualMemoryRegion first;
        VirtualMemoryRegion second;
        assert(memory.tryRegion(0, pageSize * 2, &first));
        assert(memory.tryRegion(pageSize * 2, pageSize * 2, &second));
        assert(!first.empty);
        assert(!second.empty);
        assert(first.bytes == pageSize * 2);
        assert(second.bytes == pageSize * 2);
        assert(cast(ubyte*) second.base == cast(ubyte*) first.base + pageSize * 2);

        VirtualMemoryRegion unchanged = first;
        void* unchangedBase = unchanged.base;
        assert(!memory.tryRegion(1, pageSize, &unchanged));
        assert(!memory.tryRegion(1, 0, &unchanged));
        assert(!memory.tryRegion(pageSize, size_t.max, &unchanged));
        assert(unchanged.base is unchangedBase);
        assert(unchanged.bytes == pageSize * 2);
        assert(!memory.tryRegion(pageSize * 4, pageSize, &unchanged));
        assert(unchanged.base is unchangedBase);
        assert(unchanged.bytes == pageSize * 2);

        VirtualMemoryRegion emptyRegion = first;
        assert(memory.tryRegion(pageSize, 0, &emptyRegion));
        assert(emptyRegion.empty);
        assert(emptyRegion.base is null);

        VirtualMemoryRegion middle;
        assert(first.tryRegion(pageSize, pageSize, &middle));
        assert(middle.base == cast(ubyte*) first.base + pageSize);
        assert(middle.bytes == pageSize);
        assert(!first.tryRegion(pageSize * 2, pageSize, &unchanged));
        assert(!first.tryCommit(pageSize * 2, pageSize));
        assert(!first.tryDecommit(pageSize * 2, pageSize));

        assert(first.tryCommit(0, pageSize * 2));
        assert(second.tryCommit(0, pageSize));
        ubyte* firstBytes = cast(ubyte*) first.base;
        ubyte* secondBytes = cast(ubyte*) second.base;
        firstBytes[0] = 0xA5;
        firstBytes[pageSize] = 0x5A;
        secondBytes[0] = 0xC3;

        assert(middle.tryDecommit(0, pageSize));
        assert(firstBytes[0] == 0xA5);
        assert(secondBytes[0] == 0xC3);
        assert(middle.tryCommit(0, pageSize));
        assert(firstBytes[pageSize] == 0);
        assert(firstBytes[0] == 0xA5);
        assert(secondBytes[0] == 0xC3);

        VirtualMemoryReservation moved = move(memory);
        assert(!memory.active);
        assert(moved.active);
        assert(second.tryDecommit(0, pageSize));
        assert(second.tryCommit(0, pageSize));
        assert(secondBytes[0] == 0);

        moved.deinit();
        assert(!moved.active);
        assert(moved.base is null);
        assert(moved.reservedBytes == 0);
        moved.deinit();
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
