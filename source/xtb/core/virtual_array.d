module xtb.core.virtual_array;

nothrow @nogc:

import xtb.core.allocators.internal.virtual_memory : VirtualMemoryRegion,
    VirtualMemoryReservation, tryReserveVirtualMemory, virtualMemoryPageSize,
    virtualMemorySupported;
import xtb.core.lifetime : move, moveEmplace, needsDeinit;
import xtb.core.numeric : addOverflows, multiplyOverflows;
import xtb.core.panic : panic;

version (XTB_Checked) import xtb.core.panic : require;

private enum size_t defaultCommitGranularity = 64 * 1024;

/// Fixed-capacity contiguous storage backed by one virtual-memory reservation.
///
/// `VirtualArray` reserves its complete maximum capacity once, never relocates,
/// and commits a readable/writable prefix on demand. The zero state is valid
/// and explicit `deinit` releases only the reservation; it does not finalize
/// logical elements.
struct VirtualArray(T)
{
nothrow @nogc:

    alias Self = VirtualArray!T;

private:
    VirtualMemoryReservation reservation_;
    VirtualMemoryRegion region_;
    T* data_;
    size_t capacity_;
    size_t length_;
    size_t committedBytes_;
    size_t commitGranularity_;

public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Attempts to create an empty fixed-capacity array.
    ///
    /// The complete typed capacity is reserved but starts inaccessible. The
    /// output is modified only after creation succeeds. Capacity zero succeeds
    /// without requiring virtual-memory support and produces the inert state.
    static bool tryCreate(
        size_t capacity,
        scope Self* output,
    ) @system
    {
        return tryCreate(capacity, defaultCommitGranularity, output);
    }

    /// Attempts to create an empty fixed-capacity array with explicit commit
    /// growth granularity. The granularity is rounded up to native pages.
    static bool tryCreate(
        size_t capacity,
        size_t commitGranularity,
        scope Self* output,
    ) @system
    {
        version (XTB_Checked)
        {
            require(output !is null, "VirtualArray output pointer is null");
            require(output is null || output.inert,
                "VirtualArray output is already initialized");
            require(commitGranularity != 0,
                "VirtualArray commit granularity must be nonzero");
        }

        if (output is null || !output.inert || commitGranularity == 0)
            return false;
        if (capacity == 0)
            return true;
        if (!virtualMemorySupported || multiplyOverflows(capacity, T.sizeof))
            return false;

        const pageSize = virtualMemoryPageSize();
        if (pageSize == 0)
            return false;

        size_t normalizedCommitGranularity;
        if (!tryRoundUpToMultiple(
                commitGranularity,
                pageSize,
                &normalizedCommitGranularity,
            ))
            return false;

        const dataBytes = capacity * T.sizeof;
        size_t regionBytes;
        if (!tryRoundUpToMultiple(dataBytes, pageSize, &regionBytes))
            return false;

        size_t baseAlignment;
        if (!tryLeastCommonMultiple(pageSize, T.alignof, &baseAlignment))
            return false;

        // A page-aligned reservation base needs at most
        // `baseAlignment - pageSize` extra bytes to reach a boundary aligned to
        // both the VM page size and T.alignof.
        const alignmentSlack = baseAlignment - pageSize;
        if (addOverflows(regionBytes, alignmentSlack))
            return false;
        const reservationBytes = regionBytes + alignmentSlack;

        VirtualMemoryReservation reservation;
        if (!tryReserveVirtualMemory(reservationBytes, &reservation))
            return false;
        scope (exit)
            reservation.deinit();

        void* alignedBase;
        if (!tryAlignAddressUp(reservation.base, baseAlignment, &alignedBase))
            return false;

        const reservationAddress = cast(size_t) reservation.base;
        const alignedAddress = cast(size_t) alignedBase;
        const regionOffset = alignedAddress - reservationAddress;

        VirtualMemoryRegion region;
        if (!reservation.tryRegion(regionOffset, regionBytes, &region))
            return false;

        Self result;
        moveEmplace(reservation, result.reservation_);
        result.region_ = region;
        result.data_ = cast(T*) alignedBase;
        result.capacity_ = capacity;
        result.commitGranularity_ = normalizedCommitGranularity;
        moveEmplace(result, *output);
        return true;
    }

    /// Creates an empty fixed-capacity array or panics when reservation setup
    /// fails.
    static Self create(
        size_t capacity,
        size_t commitGranularity = defaultCommitGranularity,
    ) @system
    {
        Self result;
        if (!tryCreate(capacity, commitGranularity, &result))
            panic("VirtualArray reservation failed");
        return move(result);
    }

    /// Releases the complete virtual-memory reservation. Logical elements are
    /// not finalized. Repeated deinitialization and the zero state are valid.
    void deinit() @system
    {
        reservation_.deinit();
        region_ = VirtualMemoryRegion.init;
        data_ = null;
        capacity_ = 0;
        length_ = 0;
        committedBytes_ = 0;
        commitGranularity_ = 0;
    }

    /// Stable address of element zero, or null for zero capacity.
    ///
    /// Only elements in `[0 .. length)` may be dereferenced by public callers;
    /// the remaining reserved tail may still be inaccessible.
    T* ptr() return @system
    {
        return data_;
    }

    size_t length() const pure @safe
    {
        return length_;
    }

    size_t capacity() const pure @safe
    {
        return capacity_;
    }

    bool empty() const pure @safe
    {
        return length_ == 0;
    }

    /// Returns only the logical, committed prefix.
    T[] slice() return @system
    {
        return data_[0 .. length_];
    }

    const(T)[] slice() const return @system
    {
        return data_[0 .. length_];
    }

    ref T opIndex(size_t index) return @system
    {
        version (XTB_Checked)
            require(index < length_, "VirtualArray index out of bounds");
        return data_[index];
    }

    ref const(T) opIndex(size_t index) const return @system
    {
        version (XTB_Checked)
            require(index < length_, "VirtualArray index out of bounds");
        return data_[index];
    }

package(xtb):
    /// Makes the raw typed prefix `[0 .. elementCount)` accessible without
    /// constructing elements or changing logical length.
    ///
    /// This is the storage primitive used by the container operations added in
    /// the next implementation step. Failure leaves commitment bookkeeping and
    /// logical state unchanged.
    bool tryEnsureAccessible(size_t elementCount) @system
    {
        if (elementCount > capacity_)
            return false;
        if (elementCount == 0)
            return true;

        const requiredBytes = elementCount * T.sizeof;
        if (requiredBytes <= committedBytes_)
            return true;

        size_t targetCommitted;
        if (!tryRoundUpToMultiple(
                requiredBytes,
                commitGranularity_,
                &targetCommitted,
            ) || targetCommitted > region_.bytes)
            targetCommitted = region_.bytes;

        if (targetCommitted < requiredBytes || targetCommitted < committedBytes_)
            return false;

        const additionalBytes = targetCommitted - committedBytes_;
        if (!region_.tryCommit(committedBytes_, additionalBytes))
            return false;

        committedBytes_ = targetCommitted;
        return true;
    }

private:
    bool inert() const pure @safe
    {
        return !reservation_.active &&
            region_.empty &&
            data_ is null &&
            capacity_ == 0 &&
            length_ == 0 &&
            committedBytes_ == 0 &&
            commitGranularity_ == 0;
    }
}

static assert(needsDeinit!(VirtualArray!ubyte));

private bool tryRoundUpToMultiple(
    size_t value,
    size_t multiple,
    scope size_t* output,
) pure @safe
{
    if (output is null || multiple == 0)
        return false;

    const remainder = value % multiple;
    if (remainder == 0)
    {
        *output = value;
        return true;
    }

    const increment = multiple - remainder;
    if (addOverflows(value, increment))
        return false;
    *output = value + increment;
    return true;
}

private size_t greatestCommonDivisor(size_t left, size_t right) pure @safe
{
    while (right != 0)
    {
        const remainder = left % right;
        left = right;
        right = remainder;
    }
    return left;
}

private bool tryLeastCommonMultiple(
    size_t left,
    size_t right,
    scope size_t* output,
) pure @safe
{
    if (output is null || left == 0 || right == 0)
        return false;

    const divisor = greatestCommonDivisor(left, right);
    const reduced = left / divisor;
    if (multiplyOverflows(reduced, right))
        return false;
    *output = reduced * right;
    return true;
}

private bool tryAlignAddressUp(
    void* address,
    size_t alignment,
    scope void** output,
) @system
{
    if (output is null || address is null || alignment == 0)
        return false;

    const value = cast(size_t) address;
    const remainder = value % alignment;
    if (remainder == 0)
    {
        *output = address;
        return true;
    }

    const increment = alignment - remainder;
    if (addOverflows(value, increment))
        return false;
    *output = cast(void*)(value + increment);
    return true;
}

unittest
{
    import xtb.core.lifetime : moveAssign;

    static assert(!__traits(isCopyable, VirtualArray!int));
    static assert(needsDeinit!(VirtualArray!int));
    static assert(__traits(compiles, () nothrow @nogc @system {
            VirtualArray!int value;
            cast(void) value.ptr;
            cast(void) value.length;
            cast(void) value.capacity;
            cast(void) value.empty;
            cast(void) value.slice;
            cast(void) value.tryEnsureAccessible(0);
            value.deinit();
        }));
    static assert(__traits(compiles, () nothrow @nogc @safe {
            VirtualArray!int value;
            cast(void) value.length;
            cast(void) value.capacity;
            cast(void) value.empty;
        }));
    static assert(!__traits(compiles, () nothrow @nogc @safe {
            VirtualArray!int value;
            cast(void) value.ptr;
        }));

    VirtualArray!int zero;
    assert(VirtualArray!int.tryCreate(0, &zero));
    assert(zero.ptr is null);
    assert(zero.length == 0);
    assert(zero.capacity == 0);
    assert(zero.empty);
    assert(zero.slice.length == 0);
    assert(zero.tryEnsureAccessible(0));
    assert(!zero.tryEnsureAccessible(1));
    zero.deinit();
    zero.deinit();

    version (linux)
    {
        const pageSize = virtualMemoryPageSize();
        assert(pageSize != 0);

        VirtualArray!ubyte overflow;
        assert(!VirtualArray!ubyte.tryCreate(
                size_t.max,
                size_t.max,
                &overflow,
        ));
        assert(overflow.capacity == 0);

        VirtualArray!ulong multipliedOverflow;
        assert(!VirtualArray!ulong.tryCreate(
                size_t.max / ulong.sizeof + 1,
                &multipliedOverflow,
        ));
        assert(multipliedOverflow.ptr is null);

        VirtualArray!ubyte array;
        assert(VirtualArray!ubyte.tryCreate(
                pageSize * 4 + 17,
                pageSize + 1,
                &array,
        ));
        scope (exit)
            array.deinit();
        assert(array.capacity == pageSize * 4 + 17);
        assert(array.length == 0);
        assert(array.committedBytes_ == 0);
        assert(array.ptr !is null);
        assert(cast(size_t) array.ptr % ubyte.alignof == 0);
        ubyte* original = array.ptr;

        assert(array.tryEnsureAccessible(1));
        assert(array.ptr is original);
        assert(array.committedBytes_ == pageSize * 2);
        array.ptr[0] = 0x11;

        assert(array.tryEnsureAccessible(pageSize * 2));
        assert(array.ptr is original);
        assert(array.committedBytes_ == pageSize * 2);

        assert(array.tryEnsureAccessible(pageSize * 2 + 1));
        assert(array.ptr is original);
        assert(array.committedBytes_ == pageSize * 4);
        array.ptr[pageSize * 2] = 0x22;
        assert(array.ptr[0] == 0x11);

        assert(array.tryEnsureAccessible(array.capacity));
        assert(array.ptr is original);
        assert(array.committedBytes_ == array.region_.bytes);
        array.ptr[array.capacity - 1] = 0x33;
        assert(array.ptr[array.capacity - 1] == 0x33);
        assert(!array.tryEnsureAccessible(array.capacity + 1));

        VirtualArray!ubyte moved = move(array);
        assert(array.ptr is null);
        assert(array.capacity == 0);
        assert(moved.ptr is original);
        assert(moved.capacity == pageSize * 4 + 17);
        assert(moved.ptr[0] == 0x11);
        assert(moved.ptr[pageSize * 2] == 0x22);
        assert(moved.ptr[moved.capacity - 1] == 0x33);

        VirtualArray!ubyte replacement = VirtualArray!ubyte.create(pageSize);
        ubyte* replacementOld = replacement.ptr;
        assert(replacementOld !is null);
        moveAssign(moved, replacement);
        assert(moved.ptr is null);
        assert(replacement.ptr is original);
        assert(replacement.capacity == pageSize * 4 + 17);
        replacement.deinit();

        align(32_768) struct OverAligned
        {
            ubyte value;
        }

        assert(OverAligned.alignof > pageSize);
        VirtualArray!OverAligned aligned;
        assert(VirtualArray!OverAligned.tryCreate(3, pageSize, &aligned));
        scope (exit)
            aligned.deinit();
        assert(aligned.ptr !is null);
        assert(cast(size_t) aligned.ptr % OverAligned.alignof == 0);
        assert(aligned.tryEnsureAccessible(3));
        OverAligned* alignedBase = aligned.ptr;
        aligned.ptr[0].value = 1;
        aligned.ptr[2].value = 3;
        assert(aligned.ptr is alignedBase);
        assert(aligned.ptr[0].value == 1);
        assert(aligned.ptr[2].value == 3);
    }
}
