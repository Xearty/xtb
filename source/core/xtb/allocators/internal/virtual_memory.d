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

import xtb.panic;
import xtb.types;

/// Whether this target has XTB's native virtual-memory backend.
package(xtb) enum bool virtual_memory_supported = backend.virtual_memory_supported;

/// One non-owning page-bounded subrange of a virtual-memory reservation.
///
/// A region never releases the underlying mapping and does not track committed
/// pages. It stores the stable mapped address directly rather than a pointer to
/// its reservation owner, so moving that owner does not invalidate the region.
/// The owner must outlive every region borrowed from it.
package(xtb) struct VirtualMemoryRegion
{
nothrow @nogc:

    /// First address in the region, or null for an empty region.
    ///
    /// Callers that mutate `base` or `bytes` must keep them describing the same
    /// page-bounded range. The `@system` region operations rely on that invariant.
    void* base;

    /// Page-rounded size of the region.
    usize bytes;

    bool empty() const pure @safe
    {
        return this.bytes == 0;
    }

    /// Makes a page-aligned subrange readable and writable.
    ///
    /// Returns false for an invalid/non-page-aligned range, an unsupported
    /// backend, or a native commit failure. A zero-length range is always a
    /// successful no-op.
    bool try_commit(usize offset, usize bytes) @system
    {
        if (bytes == 0) return true;
        if (!valid_page_range(this.base, this.bytes, offset, bytes)) return false;

        return backend.try_commit_virtual_memory_backend(
            byte_address(this.base, offset),
            bytes,
        );
    }

    /// Returns a page-aligned subrange to its inaccessible, uncommitted state.
    ///
    /// Successful decommit discards the previous anonymous-page contents; a
    /// later successful commit observes zero-filled pages. Returns false under
    /// the same conditions as `try_commit`, plus native decommit failure. A
    /// zero-length range is always a successful no-op.
    bool try_decommit(usize offset, usize bytes) @system
    {
        if (bytes == 0) return true;
        if (!valid_page_range(this.base, this.bytes, offset, bytes)) return false;

        return backend.try_decommit_virtual_memory_backend(
            byte_address(this.base, offset),
            bytes,
        );
    }

    /// Creates a page-bounded non-owning subregion.
    ///
    /// `output` is updated only on success. Empty regions are represented by
    /// `VirtualMemoryRegion.init`.
    bool try_region(usize offset, usize bytes, scope VirtualMemoryRegion* output) @system
    {
        require(output !is null, "virtual-memory region output is null");
        return try_make_virtual_memory_region(this.base, this.bytes, offset, bytes, output);
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

    /// First address in the reserved range, or null for the inert state.
    ///
    /// Callers that mutate `base` or `reserved_bytes` must keep them describing
    /// the same reservation owned by this value. `deinit` relies on that invariant.
    void* base;

    /// Page-rounded size of the reserved address range.
    usize reserved_bytes;

    @disable this(this);
    @disable ref VirtualMemoryReservation opAssign(
        VirtualMemoryReservation source,
    ) return;

    bool active() const pure @safe
    {
        return this.base !is null;
    }

    /// Creates a page-bounded non-owning region inside this reservation.
    ///
    /// `output` is updated only on success. Empty regions are represented by
    /// `VirtualMemoryRegion.init`. The reservation must outlive the returned
    /// region.
    bool try_region(usize offset, usize bytes, scope VirtualMemoryRegion* output) @system
    {
        require(output !is null, "virtual-memory region output is null");
        return try_make_virtual_memory_region(
            this.base,
            this.reserved_bytes,
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
    bool try_commit(usize offset, usize bytes) @system
    {
        if (bytes == 0) return true;
        if (!valid_page_range(this.base, this.reserved_bytes, offset, bytes)) return false;

        return backend.try_commit_virtual_memory_backend(
            byte_address(this.base, offset),
            bytes,
        );
    }

    /// Returns a page-aligned subrange to its inaccessible, uncommitted state.
    ///
    /// Successful decommit discards the previous anonymous-page contents; a
    /// later successful commit observes zero-filled pages. Returns false under
    /// the same conditions as `try_commit`, plus native decommit failure. A
    /// zero-length range is always a successful no-op.
    bool try_decommit(usize offset, usize bytes) @system
    {
        if (bytes == 0) return true;
        if (!valid_page_range(this.base, this.reserved_bytes, offset, bytes)) return false;

        return backend.try_decommit_virtual_memory_backend(
            byte_address(this.base, offset),
            bytes,
        );
    }

    /// Releases the complete reservation. The inert state is accepted.
    void deinit() @system
    {
        if (this.base is null)
        {
            this.reserved_bytes = 0;
            return;
        }

        void* released_base = this.base;
        const released_bytes = this.reserved_bytes;
        this.base = null;
        this.reserved_bytes = 0;

        if (!backend.release_virtual_memory_backend(released_base, released_bytes))
        {
            panic("virtual-memory release failed");
        }
    }
}

/// Returns the native VM page size, or zero when virtual memory is unsupported.
package(xtb) usize virtual_memory_page_size() @safe
{
    return backend.virtual_memory_page_size_backend();
}

/// Attempts to reserve at least `bytes` of contiguous virtual address space.
///
/// `output` must point to an inert reservation. The actual reservation is
/// rounded up to a whole number of native pages and starts inaccessible. A
/// zero-byte request succeeds and leaves `output` inert. Unsupported targets,
/// size overflow, page-size failure, and native reservation failure return
/// false and leave `output` inert.
package(xtb) bool try_reserve_virtual_memory(
    usize bytes,
    scope VirtualMemoryReservation* output,
) @system
{
    require(output !is null, "virtual-memory reservation output is null");
    require(!output.active, "virtual-memory reservation output is active");

    if (bytes == 0) return true;
    if (!virtual_memory_supported) return false;

    const usize page_size = virtual_memory_page_size();
    usize reserved_bytes;
    if (page_size == 0 || !round_up_to_multiple(bytes, page_size, &reserved_bytes))
    {
        return false;
    }

    void* reservation_base = backend.try_reserve_virtual_memory_backend(reserved_bytes);
    if (reservation_base is null) return false;

    output.base = reservation_base;
    output.reserved_bytes = reserved_bytes;
    return true;
}

private bool try_make_virtual_memory_region(
    void* base,
    usize available_bytes,
    usize offset,
    usize bytes,
    scope VirtualMemoryRegion* output,
) @system
{
    if (offset > available_bytes || bytes > available_bytes - offset) return false;

    if (bytes == 0)
    {
        if (available_bytes != 0 && !valid_page_boundary(base, offset)) return false;

        *output = VirtualMemoryRegion.init;
        return true;
    }

    if (!valid_page_range(base, available_bytes, offset, bytes)) return false;

    VirtualMemoryRegion result = VirtualMemoryRegion(
        base: byte_address(base, offset),
        bytes: bytes,
    );
    *output = result;
    return true;
}

private bool valid_page_boundary(void* base, usize offset) @safe
{
    if (!virtual_memory_supported || base is null) return false;

    const usize page_size = virtual_memory_page_size();
    return page_size != 0 && offset % page_size == 0;
}

private bool valid_page_range(
    void* base,
    usize reserved_bytes,
    usize offset,
    usize bytes,
) @safe
{
    if (!virtual_memory_supported || base is null) return false;
    if (offset > reserved_bytes || bytes > reserved_bytes - offset) return false;

    const usize page_size = virtual_memory_page_size();
    return page_size != 0
        && offset % page_size == 0
        && bytes % page_size == 0;
}

private bool round_up_to_multiple(
    usize value,
    usize multiple,
    usize* result,
) pure @safe
{
    if (multiple == 0) return false;

    const remainder = value % multiple;
    if (remainder == 0)
    {
        *result = value;
        return true;
    }

    const increment = multiple - remainder;
    if (value > usize.max - increment) return false;

    *result = value + increment;
    return true;
}

private void* byte_address(void* base, usize offset) @system
{
    return cast(void*)(cast(u8*) base + offset);
}

version (unittest)
{
    import xtb.lifetime;
}

unittest
{
    static assert(__traits(isCopyable, VirtualMemoryRegion));
    static assert(!needs_deinit!VirtualMemoryRegion);
    static assert(__traits(compiles, () nothrow @nogc @system
    {
        VirtualMemoryRegion value;
        VirtualMemoryRegion output;
        cast(void) value.base;
        cast(void) value.bytes;
        cast(void) value.empty;
        cast(void) value.try_commit(0, 0);
        cast(void) value.try_decommit(0, 0);
        cast(void) value.try_region(0, 0, &output);
    }));

    static assert(!__traits(isCopyable, VirtualMemoryReservation));
    static assert(needs_deinit!VirtualMemoryReservation);
    static assert(__traits(compiles, () nothrow @nogc @system
    {
        VirtualMemoryReservation value;
        cast(void) value.base;
        cast(void) value.reserved_bytes;
        cast(void) value.active;
        VirtualMemoryRegion region;
        cast(void) value.try_region(0, 0, &region);
        cast(void) value.try_commit(0, 0);
        cast(void) value.try_decommit(0, 0);
        value.deinit();
    }));
}

unittest
{
    VirtualMemoryReservation zero;
    assert(try_reserve_virtual_memory(0, &zero));
    assert(!zero.active);
    assert(zero.reserved_bytes == 0);
    assert(zero.try_commit(0, 0));
    assert(zero.try_decommit(0, 0));
    assert(!zero.try_commit(0, 4096));
    assert(!zero.try_decommit(0, 4096));

    VirtualMemoryRegion zero_region;
    assert(zero.try_region(0, 0, &zero_region));
    assert(zero_region.empty);
    assert(zero_region.base is null);
    assert(zero_region.bytes == 0);
    assert(zero_region.try_commit(0, 0));
    assert(zero_region.try_decommit(0, 0));
    assert(!zero_region.try_commit(0, 4096));
    assert(!zero_region.try_decommit(0, 4096));
    zero.deinit();
}

unittest
{
    version (linux)
    {
        assert(virtual_memory_supported);
        const usize page_size = virtual_memory_page_size();
        assert(page_size != 0);

        VirtualMemoryReservation overflow;
        assert(!try_reserve_virtual_memory(usize.max, &overflow));
        assert(!overflow.active);
        overflow.deinit();

        VirtualMemoryReservation memory;
        assert(try_reserve_virtual_memory(page_size * 4, &memory));
        assert(memory.active);
        assert(memory.base !is null);
        assert(memory.reserved_bytes == page_size * 4);
        assert(cast(usize) memory.base % page_size == 0);

        assert(!memory.try_commit(1, page_size));
        assert(!memory.try_commit(0, page_size - 1));
        assert(!memory.try_commit(page_size * 4, page_size));

        VirtualMemoryRegion first;
        VirtualMemoryRegion second;
        assert(memory.try_region(0, page_size * 2, &first));
        assert(memory.try_region(page_size * 2, page_size * 2, &second));
        assert(!first.empty);
        assert(!second.empty);
        assert(first.bytes == page_size * 2);
        assert(second.bytes == page_size * 2);
        assert(cast(u8*) second.base == cast(u8*) first.base + page_size * 2);

        VirtualMemoryRegion unchanged = first;
        void* unchanged_base = unchanged.base;
        assert(!memory.try_region(1, page_size, &unchanged));
        assert(!memory.try_region(1, 0, &unchanged));
        assert(!memory.try_region(page_size, usize.max, &unchanged));
        assert(unchanged.base is unchanged_base);
        assert(unchanged.bytes == page_size * 2);
        assert(!memory.try_region(page_size * 4, page_size, &unchanged));
        assert(unchanged.base is unchanged_base);
        assert(unchanged.bytes == page_size * 2);

        VirtualMemoryRegion empty_region = first;
        assert(memory.try_region(page_size, 0, &empty_region));
        assert(empty_region.empty);
        assert(empty_region.base is null);

        VirtualMemoryRegion middle;
        assert(first.try_region(page_size, page_size, &middle));
        assert(middle.base == cast(u8*) first.base + page_size);
        assert(middle.bytes == page_size);
        assert(!first.try_region(page_size * 2, page_size, &unchanged));
        assert(!first.try_commit(page_size * 2, page_size));
        assert(!first.try_decommit(page_size * 2, page_size));

        assert(first.try_commit(0, page_size * 2));
        assert(second.try_commit(0, page_size));
        u8* first_bytes = cast(u8*) first.base;
        u8* second_bytes = cast(u8*) second.base;
        first_bytes[0] = 0xA5;
        first_bytes[page_size] = 0x5A;
        second_bytes[0] = 0xC3;

        assert(middle.try_decommit(0, page_size));
        assert(first_bytes[0] == 0xA5);
        assert(second_bytes[0] == 0xC3);
        assert(middle.try_commit(0, page_size));
        assert(first_bytes[page_size] == 0);
        assert(first_bytes[0] == 0xA5);
        assert(second_bytes[0] == 0xC3);

        VirtualMemoryReservation moved = move(memory);
        assert(!memory.active);
        assert(moved.active);
        assert(second.try_decommit(0, page_size));
        assert(second.try_commit(0, page_size));
        assert(second_bytes[0] == 0);

        moved.deinit();
        assert(!moved.active);
        assert(moved.base is null);
        assert(moved.reserved_bytes == 0);
        moved.deinit();
    }
    else
    {
        assert(!virtual_memory_supported);
        assert(virtual_memory_page_size() == 0);

        VirtualMemoryReservation unavailable;
        assert(!try_reserve_virtual_memory(4096, &unavailable));
        assert(!unavailable.active);
        assert(!unavailable.try_commit(0, 4096));
        assert(!unavailable.try_decommit(0, 4096));
        unavailable.deinit();
    }
}
