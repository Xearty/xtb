module xtb.containers.virtual_array;

nothrow @nogc:

import core.lifetime : emplace;
import core.stdc.string : memmove;
import xtb.allocators.internal.virtual_memory : VirtualMemoryRegion,
    VirtualMemoryReservation, tryReserveVirtualMemory, virtualMemoryPageSize,
    virtualMemorySupported;
import xtb.lifetime : move, move_emplace, needs_deinit;
import xtb.numeric : add_overflows, multiply_overflows;
import xtb.panic : panic;

version (XTB_Checked) import xtb.panic : require;

package(xtb.containers) enum size_t defaultVirtualCommitGranularity = 64 * 1024;

private template supportsDefaultInitialization(T)
{
    enum supportsDefaultInitialization = __traits(compiles, () { T value; });
}

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
        return tryCreate(capacity, defaultVirtualCommitGranularity, output);
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
        if (!virtualMemorySupported)
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

        VirtualArrayRegionGeometry geometry;
        if (!tryVirtualArrayRegionGeometry!T(capacity, pageSize, &geometry))
            return false;
        if (add_overflows(geometry.regionBytes, geometry.alignmentSlack))
            return false;
        const reservationBytes = geometry.regionBytes + geometry.alignmentSlack;

        VirtualMemoryReservation reservation;
        if (!tryReserveVirtualMemory(reservationBytes, &reservation))
            return false;
        scope (exit)
            reservation.deinit();

        void* alignedBase;
        if (!tryAlignAddressUp(reservation.base, geometry.baseAlignment, &alignedBase))
            return false;

        const reservationAddress = cast(size_t) reservation.base;
        const alignedAddress = cast(size_t) alignedBase;
        const regionOffset = alignedAddress - reservationAddress;

        VirtualMemoryRegion region;
        if (!reservation.tryRegion(regionOffset, geometry.regionBytes, &region))
            return false;

        Self result;
        move_emplace(reservation, result.reservation_);
        result.region_ = region;
        result.data_ = cast(T*) alignedBase;
        result.capacity_ = capacity;
        result.commitGranularity_ = normalizedCommitGranularity;
        move_emplace(result, *output);
        return true;
    }

    /// Creates an empty fixed-capacity array or panics when reservation setup
    /// fails.
    static Self create(
        size_t capacity,
        size_t commitGranularity = defaultVirtualCommitGranularity,
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
    inout(T)* ptr() inout return @system
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
    inout(T)[] slice() inout return @system
    {
        return data_[0 .. length_];
    }

    static if (supportsDefaultInitialization!T)
    {
        /// Resizes the logical array, default-initializing newly added values.
        /// Shrinking is shallow and retains committed pages.
        bool tryResize(size_t requested) @trusted
        {
            if (requested <= length_)
            {
                length_ = requested;
                return true;
            }
            if (!tryEnsureAccessible(requested))
                return false;
            while (length_ < requested)
            {
                constructInitial(data_ + length_);
                ++length_;
            }
            return true;
        }

        /// Resizes the logical array or panics when fixed capacity or virtual
        /// backing cannot satisfy the requested length.
        void resize(size_t requested) @trusted
        {
            if (!tryResize(requested))
                panic("VirtualArray capacity or commitment exceeded");
        }
    }

    /// Attempts to append by moving from `*value` only after backing storage
    /// for the new element is accessible. Failure leaves both operands
    /// unchanged.
    bool tryAppend(scope T* value) @system
    {
        version (XTB_Checked)
            require(value !is null, "VirtualArray append value pointer is null");
        if (value is null || length_ >= capacity_)
            return false;
        if (!tryEnsureAccessible(length_ + 1))
            return false;
        constructMove(data_ + length_, *value);
        ++length_;
        return true;
    }

    /// Appends by move or panics when fixed capacity or virtual backing is
    /// exhausted.
    void append(T value) @trusted
    {
        if (!tryAppend(&value))
            panic("VirtualArray capacity or commitment exceeded");
    }

    static if (__traits(isCopyable, T))
    {
        /// Attempts to append a copy of every value. Failure leaves logical
        /// contents unchanged. The source may alias the current array.
        bool tryAppend(scope const(T)[] values) @trusted
        {
            if (values.length > capacity_ - length_)
                return false;
            if (values.length == 0)
                return true;

            const oldLength = length_;
            const newLength = oldLength + values.length;
            if (!tryEnsureAccessible(newLength))
                return false;

            static if (__traits(isPOD, T))
            {
                memmove(
                    data_ + oldLength,
                    values.ptr,
                    values.length * T.sizeof,
                );
                length_ = newLength;
            }
            else
            {
                foreach (ref value; values)
                {
                    constructCopy(data_ + length_, value);
                    ++length_;
                }
            }
            return true;
        }

        /// Appends copied values or panics when fixed capacity or virtual
        /// backing is exhausted.
        void append(scope const(T)[] values) @trusted
        {
            if (!tryAppend(values))
                panic("VirtualArray capacity or commitment exceeded");
        }
    }

    /// Returns a reference to the last logical element.
    ref inout(T) back() inout return @system
    {
        version (XTB_Checked)
            require(length_ != 0, "cannot access back of empty VirtualArray");
        return data_[length_ - 1];
    }

    /// Removes and transfers the last logical element without finalizing it.
    T pop() @trusted
    {
        version (XTB_Checked)
            require(length_ != 0, "cannot pop an empty VirtualArray");
        --length_;
        T result = void;
        static if (__traits(isPOD, T) && !needs_deinit!T)
            result = data_[length_];
        else
            move_emplace(data_[length_], result);
        return result;
    }

    /// Discards all logical elements without finalizing them and retains all
    /// currently committed pages.
    void clear() @safe
    {
        length_ = 0;
    }

    /// Decommits whole pages that lie entirely beyond the logical array. The
    /// fixed virtual capacity and stable base address are unchanged.
    void trim() @trusted
    {
        if (committedBytes_ == 0)
            return;

        const pageSize = virtualMemoryPageSize();
        if (pageSize == 0)
            panic("VirtualArray page size unavailable");

        const liveBytes = length_ * T.sizeof;
        if (!tryTrimCommittedPrefix(
                region_,
                liveBytes,
                pageSize,
                &committedBytes_,
            ))
            panic("VirtualArray decommit failed");
    }

    ref inout(T) opIndex(size_t index) inout return @system
    {
        version (XTB_Checked)
            require(index < length_, "VirtualArray index out of bounds");
        return data_[index];
    }

package(xtb.containers):
    /// Makes the raw typed prefix `[0 .. elementCount)` accessible without
    /// constructing elements or changing logical length.
    ///
    /// Container operations use this storage primitive before establishing
    /// any new `T` lifetimes. Failure leaves commitment bookkeeping and logical
    /// state unchanged.
    bool tryEnsureAccessible(size_t elementCount) @system
    {
        if (elementCount > capacity_)
            return false;
        if (elementCount == 0)
            return true;

        const requiredBytes = elementCount * T.sizeof;
        return tryEnsureCommittedPrefix(
            region_,
            requiredBytes,
            commitGranularity_,
            &committedBytes_,
        );
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

static assert(needs_deinit!(VirtualArray!ubyte));

/// Non-owning fixed-capacity typed storage over one bounded virtual-memory
/// region.
///
/// A view never releases its underlying mapping and never constructs or
/// finalizes `T`. It owns only its local provision/commit bookkeeping, so it is
/// deliberately non-copyable. `deinit` ends that local borrow and resets the
/// view without touching the parent reservation.
package(xtb.containers) struct VirtualArrayView(T)
{
nothrow @nogc:

    alias Self = VirtualArrayView!T;

private:
    VirtualMemoryRegion region_;
    T* data_;
    size_t capacity_;
    size_t provisionedLength_;
    size_t committedBytes_;
    size_t commitGranularity_;

public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Attempts to bind an inert view to `region`.
    ///
    /// `region` must be page-bounded, large enough for `capacity` elements,
    /// and aligned for `T`. Capacity zero requires an empty region. The output
    /// is modified only on success. No pages are committed by creation.
    static bool tryCreate(
        VirtualMemoryRegion region,
        size_t capacity,
        size_t commitGranularity,
        scope Self* output,
    ) @system
    {
        version (XTB_Checked)
        {
            require(output !is null, "VirtualArrayView output pointer is null");
            require(output is null || output.inert,
                "VirtualArrayView output is already initialized");
            require(commitGranularity != 0,
                "VirtualArrayView commit granularity must be nonzero");
        }

        if (output is null || !output.inert || commitGranularity == 0)
            return false;
        if (capacity == 0)
            return region.empty;
        if (region.empty || multiply_overflows(capacity, T.sizeof))
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
        if (dataBytes > region.bytes)
            return false;

        void* base = region.base;
        if (base is null || cast(size_t) base % T.alignof != 0)
            return false;

        Self result;
        result.region_ = region;
        result.data_ = cast(T*) base;
        result.capacity_ = capacity;
        result.commitGranularity_ = normalizedCommitGranularity;
        move_emplace(result, *output);
        return true;
    }

    /// Ends this view's local borrow. The underlying virtual-memory mapping and
    /// all committed pages remain owned by and attached to the parent.
    void deinit() @safe
    {
        region_ = VirtualMemoryRegion.init;
        data_ = null;
        capacity_ = 0;
        provisionedLength_ = 0;
        committedBytes_ = 0;
        commitGranularity_ = 0;
    }

    /// Stable typed base of this region, or null for the inert state.
    ///
    /// Only `[0 .. provisionedLength)` is promised by the view to have
    /// accessible storage. Extra elements may happen to fit in page-rounded
    /// committed bytes but are not provisioned by that fact alone.
    inout(T)* ptr() inout return @system
    {
        return data_;
    }

    const(T)* ptr() const return @system
    {
        return data_;
    }

    size_t capacity() const pure @safe
    {
        return capacity_;
    }

    size_t provisionedLength() const pure @safe
    {
        return provisionedLength_;
    }

    size_t committedBytes() const pure @safe
    {
        return committedBytes_;
    }

    /// Accesses one deliberately provisioned raw-storage element.
    ref inout(T) opIndex(size_t index) inout return @system
    {
        version (XTB_Checked)
            require(index < provisionedLength_,
                "VirtualArrayView index out of bounds");
        return data_[index];
    }

    bool inert() const pure @safe
    {
        return region_.empty &&
            data_ is null &&
            capacity_ == 0 &&
            provisionedLength_ == 0 &&
            committedBytes_ == 0 &&
            commitGranularity_ == 0;
    }

    /// Makes raw storage for `[0 .. elementCount)` accessible without
    /// constructing `T` values.
    ///
    /// Provisioning is monotonic. Page/granularity rounding may commit bytes
    /// covering more elements, but `provisionedLength` advances only to the
    /// explicitly requested high-water. Failure leaves all bookkeeping
    /// unchanged (native commitment may conservatively remain larger only if a
    /// backend can partially commit before reporting failure).
    bool tryEnsureAccessible(size_t elementCount) @system
    {
        if (elementCount > capacity_)
            return false;
        if (elementCount <= provisionedLength_)
            return true;

        const requiredBytes = elementCount * T.sizeof;
        if (!tryEnsureCommittedPrefix(
                region_,
                requiredBytes,
                commitGranularity_,
                &committedBytes_,
            ))
            return false;

        provisionedLength_ = elementCount;
        return true;
    }

    /// Decommits whole pages that are not needed by the provisioned prefix.
    /// The provisioned element high-water and fixed capacity are unchanged.
    void trim() @trusted
    {
        if (committedBytes_ == 0)
            return;

        const pageSize = virtualMemoryPageSize();
        if (pageSize == 0)
            panic("VirtualArrayView page size unavailable");

        const provisionedBytes = provisionedLength_ * T.sizeof;
        if (!tryTrimCommittedPrefix(
                region_,
                provisionedBytes,
                pageSize,
                &committedBytes_,
            ))
            panic("VirtualArrayView decommit failed");
    }
}

static assert(needs_deinit!(VirtualArrayView!ubyte));

/// Page-bounded geometry for one fixed-capacity typed virtual-array region.
///
/// This is shared by owning arrays and internal multi-region containers such
/// as Pool so alignment/overflow rules cannot drift between representations.
package(xtb.containers) struct VirtualArrayRegionGeometry
{
    size_t regionBytes;
    size_t baseAlignment;
    size_t alignmentSlack;
}

package(xtb.containers) bool tryVirtualArrayRegionGeometry(T)(
    size_t capacity,
    size_t pageSize,
    scope VirtualArrayRegionGeometry* output,
) pure @safe
{
    if (output is null || pageSize == 0 || multiply_overflows(capacity, T.sizeof))
        return false;

    const dataBytes = capacity * T.sizeof;
    size_t regionBytes;
    if (!tryRoundUpToMultiple(dataBytes, pageSize, &regionBytes))
        return false;

    size_t baseAlignment;
    if (!tryLeastCommonMultiple(pageSize, T.alignof, &baseAlignment))
        return false;

    VirtualArrayRegionGeometry result;
    result.regionBytes = regionBytes;
    result.baseAlignment = baseAlignment;
    // A page-aligned base needs at most this much slack to reach an address
    // aligned to both the native page size and T.alignof.
    result.alignmentSlack = baseAlignment - pageSize;
    *output = result;
    return true;
}

private bool tryEnsureCommittedPrefix(
    VirtualMemoryRegion region,
    size_t requiredBytes,
    size_t commitGranularity,
    scope size_t* committedBytes,
) @system
{
    if (committedBytes is null || requiredBytes > region.bytes)
        return false;
    if (requiredBytes <= *committedBytes)
        return true;

    size_t targetCommitted;
    if (!tryRoundUpToMultiple(
            requiredBytes,
            commitGranularity,
            &targetCommitted,
        ) || targetCommitted > region.bytes)
        targetCommitted = region.bytes;

    if (targetCommitted < requiredBytes || targetCommitted < *committedBytes)
        return false;

    const additionalBytes = targetCommitted - *committedBytes;
    if (!region.tryCommit(*committedBytes, additionalBytes))
        return false;

    *committedBytes = targetCommitted;
    return true;
}

private bool tryTrimCommittedPrefix(
    VirtualMemoryRegion region,
    size_t retainedBytes,
    size_t pageSize,
    scope size_t* committedBytes,
) @system
{
    if (committedBytes is null || retainedBytes > region.bytes)
        return false;

    size_t targetCommitted;
    if (!tryRoundUpToMultiple(retainedBytes, pageSize, &targetCommitted) ||
        targetCommitted > region.bytes)
        targetCommitted = region.bytes;
    if (targetCommitted >= *committedBytes)
        return true;

    const decommitBytes = *committedBytes - targetCommitted;
    if (!region.tryDecommit(targetCommitted, decommitBytes))
        return false;

    *committedBytes = targetCommitted;
    return true;
}

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
    if (add_overflows(value, increment))
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
    if (multiply_overflows(reduced, right))
        return false;
    *output = reduced * right;
    return true;
}

package(xtb.containers) bool tryAlignAddressUp(
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
    if (add_overflows(value, increment))
        return false;
    *output = cast(void*)(value + increment);
    return true;
}

private void constructInitial(T)(T* destination) @system
{
    static if (__traits(isPOD, T))
        *destination = T.init;
    else
        emplace(destination);
}

private void constructMove(T)(T* destination, ref T source) @system
{
    static if (__traits(isPOD, T) && !needs_deinit!T)
        *destination = source;
    else
        move_emplace(source, *destination);
}

private void constructCopy(T, U)(T* destination, ref U source) @system
{
    static if (__traits(isPOD, T))
        *destination = source;
    else
        emplace(destination, source);
}

unittest
{
    import xtb.lifetime : deinitValue = deinit, move_assign;

    struct ExplicitOwner
    {
    nothrow @nogc:

        size_t* deinits;
        bool active;

        @disable this(this);

        this(size_t* deinits)
        {
            this.deinits = deinits;
            active = true;
        }

        void deinit()
        {
            if (!active)
                return;
            active = false;
            ++*deinits;
        }
    }

    struct DestructorOnly
    {
        size_t* destructions;
        bool armed;

        @disable this(this);

        ~this() nothrow @nogc
        {
            if (!armed)
                return;
            armed = false;
            ++*destructions;
        }
    }

    static assert(!__traits(isCopyable, VirtualArray!int));
    static assert(needs_deinit!(VirtualArray!int));
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
            cast(void) value.tryResize(0);
            value.resize(0);
            value.append(1);
            cast(void) value.pop();
            value.clear();
            value.trim();
        }));
    static assert(!__traits(compiles, () nothrow @nogc @safe {
            VirtualArray!int value;
            cast(void) value.ptr;
        }));
    static assert(__traits(compiles, (ref const(VirtualArray!int) value)
            nothrow @nogc @system {
            const(int)* pointer = value.ptr;
            const(int)[] values = value.slice;
            ref const(int) back = value.back();
            ref const(int) indexed = value[0];
            cast(void) pointer;
            cast(void) values;
            cast(void) back;
            cast(void) indexed;
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
    assert(zero.tryResize(0));
    assert(!zero.tryResize(1));
    zero.deinit();
    zero.deinit();

    version (linux)
    {
        const pageSize = virtualMemoryPageSize();
        assert(pageSize != 0);

        VirtualArray!int values = VirtualArray!int.create(8, pageSize);
        scope (exit)
            values.deinit();
        int* valuesBase = values.ptr;
        assert(values.tryResize(3));
        assert(values.length == 3);
        assert(values[0] == 0 && values[1] == 0 && values[2] == 0);
        values[0] = 10;
        values[1] = 20;
        values[2] = 30;
        assert(&values[0] is valuesBase);

        int candidate = 40;
        assert(values.tryAppend(&candidate));
        assert(values.length == 4);
        assert(values.back == 40);
        assert(values.ptr is valuesBase);

        values.append(values.slice[0 .. 2]);
        assert(values.length == 6);
        assert(values[4] == 10 && values[5] == 20);
        assert(values.ptr is valuesBase);

        int popped = values.pop();
        assert(popped == 20);
        assert(values.length == 5);
        assert(values.back == 10);

        assert(!values.tryResize(values.capacity + 1));
        assert(values.length == 5);
        assert(values[0] == 10 && values[4] == 10);
        values.resize(2);
        assert(values.length == 2);
        assert(values[0] == 10 && values[1] == 20);
        assert(values.ptr is valuesBase);

        values.resize(values.capacity);
        assert(values.ptr is valuesBase);
        int overflowCandidate = 77;
        assert(!values.tryAppend(&overflowCandidate));
        assert(overflowCandidate == 77);
        assert(values.length == values.capacity);

        const retainedCommit = values.committedBytes_;
        values.clear();
        assert(values.empty);
        assert(values.committedBytes_ == retainedCommit);
        values.trim();
        assert(values.committedBytes_ == 0);
        assert(values.ptr is valuesBase);

        // Trimming decommits pages outside the logical prefix. Recommitting raw
        // storage must expose fresh zero-filled pages without relocating data.
        VirtualArray!ubyte trimmed = VirtualArray!ubyte.create(pageSize * 3, pageSize);
        scope (exit)
            trimmed.deinit();
        ubyte* trimmedBase = trimmed.ptr;
        trimmed.resize(pageSize);
        assert(trimmed.tryEnsureAccessible(pageSize * 3));
        trimmed.ptr[pageSize * 2] = 0xa5;
        assert(trimmed.committedBytes_ == pageSize * 3);
        trimmed.trim();
        assert(trimmed.committedBytes_ == pageSize);
        assert(trimmed.ptr is trimmedBase);
        assert(trimmed.tryEnsureAccessible(pageSize * 3));
        assert(trimmed.ptr is trimmedBase);
        assert(trimmed.ptr[pageSize * 2] == 0);

        size_t explicitDeinits;
        VirtualArray!ExplicitOwner owners = VirtualArray!ExplicitOwner.create(2, pageSize);
        ExplicitOwner owner = ExplicitOwner(&explicitDeinits);
        assert(owners.tryAppend(&owner));
        assert(!owner.active);
        assert(owners.length == 1);
        owners.clear();
        assert(explicitDeinits == 0);
        owners.deinit();
        assert(explicitDeinits == 0);

        VirtualArray!ExplicitOwner transferred = VirtualArray!ExplicitOwner.create(1, pageSize);
        ExplicitOwner transferredSource = ExplicitOwner(&explicitDeinits);
        assert(transferred.tryAppend(&transferredSource));
        ExplicitOwner rejected = ExplicitOwner(&explicitDeinits);
        assert(!transferred.tryAppend(&rejected));
        assert(rejected.active);
        deinitValue(rejected);
        assert(explicitDeinits == 1);
        ExplicitOwner transferredValue = transferred.pop();
        assert(transferred.empty);
        assert(transferredValue.active);
        deinitValue(transferredValue);
        assert(explicitDeinits == 2);
        transferred.deinit();

        size_t destructions;
        VirtualArray!DestructorOnly destructorValues =
            VirtualArray!DestructorOnly.create(1, pageSize);
        DestructorOnly destructorSource;
        destructorSource.destructions = &destructions;
        destructorSource.armed = true;
        assert(destructorValues.tryAppend(&destructorSource));
        assert(!destructorSource.armed);
        DestructorOnly destructorValue = destructorValues.pop();
        assert(destructorValue.armed);
        destroy(destructorValue);
        assert(destructions == 1);
        destructorValues.deinit();

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
        move_assign(moved, replacement);
        assert(moved.ptr is null);
        assert(replacement.ptr is original);
        assert(replacement.capacity == pageSize * 4 + 17);
        replacement.deinit();

        align(8_192) struct OverAligned
        {
            ubyte value;
        }

        // Keep the fixture below LLVM 18's 16 KiB IR alignment ceiling.
        // Exercise the over-page-aligned path only when the host page size is
        // smaller than the representable test alignment.
        if (OverAligned.alignof > pageSize)
        {
            VirtualArray!OverAligned aligned;
            assert(VirtualArray!OverAligned.tryCreate(3, pageSize, &aligned));
            scope (exit)
                aligned.deinit();
            assert(aligned.ptr !is null);
            assert(cast(size_t) aligned.ptr % OverAligned.alignof == 0);
            assert(aligned.tryResize(3));
            OverAligned* alignedBase = aligned.ptr;
            aligned[0].value = 1;
            aligned[2].value = 3;
            assert(aligned.ptr is alignedBase);
            assert(aligned.ptr[0].value == 1);
            assert(aligned.ptr[2].value == 3);
        }
    }
}

unittest
{
    static assert(!__traits(isCopyable, VirtualArrayView!int));
    static assert(needs_deinit!(VirtualArrayView!int));
    static assert(__traits(compiles, () nothrow @nogc @safe {
            VirtualArrayView!int view;
            cast(void) view.capacity;
            cast(void) view.provisionedLength;
            cast(void) view.committedBytes;
            cast(void) view.inert;
            view.deinit();
        }));
    static assert(!__traits(compiles, () nothrow @nogc @safe {
            VirtualArrayView!int view;
            cast(void) view.ptr;
        }));
    static assert(__traits(compiles, (ref const(VirtualArrayView!int) view)
            nothrow @nogc @system {
            const(int)* pointer = view.ptr;
            ref const(int) indexed = view[0];
            cast(void) pointer;
            cast(void) indexed;
        }));

    VirtualArrayView!int zero;
    assert(VirtualArrayView!int.tryCreate(
            VirtualMemoryRegion.init,
            0,
            1,
            &zero,
    ));
    assert(zero.inert);
    assert(zero.tryEnsureAccessible(0));
    assert(!zero.tryEnsureAccessible(1));
    zero.trim();
    zero.deinit();

    version (linux)
    {
        const pageSize = virtualMemoryPageSize();
        assert(pageSize != 0);

        VirtualMemoryReservation reservation;
        assert(tryReserveVirtualMemory(pageSize * 6, &reservation));
        scope (exit)
            reservation.deinit();

        VirtualMemoryRegion firstRegion;
        VirtualMemoryRegion secondRegion;
        VirtualMemoryRegion moveRegion;
        assert(reservation.tryRegion(0, pageSize * 2, &firstRegion));
        assert(reservation.tryRegion(pageSize * 2, pageSize * 2, &secondRegion));
        assert(reservation.tryRegion(pageSize * 4, pageSize * 2, &moveRegion));

        VirtualArrayView!ubyte first;
        VirtualArrayView!ubyte second;
        assert(VirtualArrayView!ubyte.tryCreate(
                firstRegion,
                pageSize * 2,
                pageSize * 2,
                &first,
        ));
        assert(VirtualArrayView!ubyte.tryCreate(
                secondRegion,
                pageSize * 2,
                pageSize,
                &second,
        ));
        scope (exit)
        {
            first.deinit();
            second.deinit();
        }

        assert(first.capacity == pageSize * 2);
        assert(first.provisionedLength == 0);
        assert(first.committedBytes == 0);
        assert(second.committedBytes == 0);

        // Provisioning one byte commits according to granularity but does not
        // claim the trailing elements covered by those pages.
        assert(first.tryEnsureAccessible(1));
        assert(first.provisionedLength == 1);
        assert(first.committedBytes == pageSize * 2);
        assert(second.provisionedLength == 0);
        assert(second.committedBytes == 0);

        // Raw provisioning never initializes newly promised element storage.
        // This byte is physically accessible because of page rounding, but it
        // is deliberately outside the current provisioned high-water.
        first.ptr[pageSize] = 0xa5;
        assert(first.tryEnsureAccessible(pageSize + 1));
        assert(first.provisionedLength == pageSize + 1);
        assert(first[pageSize] == 0xa5);

        assert(second.tryEnsureAccessible(pageSize + 1));
        assert(second.provisionedLength == pageSize + 1);
        assert(second.committedBytes == pageSize * 2);
        second[0] = 0x22;
        assert(first[0] == 0);

        // A separate view can trim its committed suffix without changing the
        // adjacent region or its own provisioned element high-water.
        VirtualArrayView!ubyte trimming;
        assert(VirtualArrayView!ubyte.tryCreate(
                moveRegion,
                pageSize * 2,
                pageSize * 2,
                &trimming,
        ));
        assert(trimming.tryEnsureAccessible(1));
        assert(trimming.committedBytes == pageSize * 2);
        trimming.ptr[pageSize] = 0x7b;
        trimming.trim();
        assert(trimming.provisionedLength == 1);
        assert(trimming.committedBytes == pageSize);
        assert(second[0] == 0x22);
        assert(trimming.tryEnsureAccessible(pageSize + 1));
        assert(trimming[pageSize] == 0);

        // Moving the reservation owner does not invalidate borrowed views;
        // the region stores the stable mapped address rather than owner state.
        VirtualMemoryReservation movedReservation = move(reservation);
        assert(!reservation.active);
        assert(movedReservation.active);
        ubyte* trimmingBase = trimming.ptr;
        assert(trimming.tryEnsureAccessible(pageSize * 2));
        assert(trimming.ptr is trimmingBase);

        VirtualArrayView!ubyte movedView = move(trimming);
        assert(trimming.inert);
        assert(movedView.ptr is trimmingBase);
        assert(movedView.provisionedLength == pageSize * 2);
        movedView.deinit();
        assert(movedView.inert);

        // Ending views does not release the parent reservation.
        first.deinit();
        second.deinit();
        assert(movedReservation.active);
        VirtualMemoryRegion stillBorrowable;
        assert(movedReservation.tryRegion(0, pageSize, &stillBorrowable));
        assert(stillBorrowable.tryCommit(0, pageSize));
        (cast(ubyte*) stillBorrowable.base)[0] = 0x44;
        assert((cast(ubyte*) stillBorrowable.base)[0] == 0x44);
        movedReservation.deinit();

        // Capacity/size failure is transactional.
        VirtualMemoryReservation smallReservation;
        assert(tryReserveVirtualMemory(pageSize, &smallReservation));
        scope (exit)
            smallReservation.deinit();
        VirtualMemoryRegion smallRegion;
        assert(smallReservation.tryRegion(0, pageSize, &smallRegion));

        VirtualArrayView!ulong overflow;
        assert(!VirtualArrayView!ulong.tryCreate(
                smallRegion,
                size_t.max / ulong.sizeof + 1,
                pageSize,
                &overflow,
        ));
        assert(overflow.inert);

        VirtualArrayView!ubyte tooLarge;
        assert(!VirtualArrayView!ubyte.tryCreate(
                smallRegion,
                pageSize + 1,
                pageSize,
                &tooLarge,
        ));
        assert(tooLarge.inert);

        // Over-aligned views are accepted when the supplied page-bounded
        // region starts at an address satisfying T.alignof, and rejected when
        // the same region is deliberately shifted by one page.
        align(8_192) struct OverAlignedViewValue
        {
            ubyte value;
        }

        // See the matching owning-array test above for the backend limit.
        if (OverAlignedViewValue.alignof > pageSize)
        {
            const alignedRegionBytes = OverAlignedViewValue.sizeof;
            const alignedReservationBytes = OverAlignedViewValue.alignof +
                alignedRegionBytes + pageSize;
            VirtualMemoryReservation alignedReservation;
            assert(tryReserveVirtualMemory(
                    alignedReservationBytes,
                    &alignedReservation,
            ));
            scope (exit)
                alignedReservation.deinit();

            void* alignedBase;
            assert(tryAlignAddressUp(
                    alignedReservation.base,
                    OverAlignedViewValue.alignof,
                    &alignedBase,
            ));
            const alignedOffset = cast(size_t) alignedBase -
                cast(size_t) alignedReservation.base;
            VirtualMemoryRegion alignedRegion;
            assert(alignedReservation.tryRegion(
                    alignedOffset,
                    alignedRegionBytes,
                    &alignedRegion,
            ));

            VirtualArrayView!OverAlignedViewValue alignedView;
            assert(VirtualArrayView!OverAlignedViewValue.tryCreate(
                    alignedRegion,
                    1,
                    pageSize,
                    &alignedView,
            ));
            scope (exit)
                alignedView.deinit();
            assert(cast(size_t) alignedView.ptr % OverAlignedViewValue.alignof == 0);
            assert(alignedView.tryEnsureAccessible(1));
            alignedView[0].value = 9;
            assert(alignedView[0].value == 9);

            if (alignedOffset + pageSize + alignedRegionBytes <=
                alignedReservation.reservedBytes)
            {
                VirtualMemoryRegion misalignedRegion;
                assert(alignedReservation.tryRegion(
                        alignedOffset + pageSize,
                        alignedRegionBytes,
                        &misalignedRegion,
                ));
                VirtualArrayView!OverAlignedViewValue misalignedView;
                assert(!VirtualArrayView!OverAlignedViewValue.tryCreate(
                        misalignedRegion,
                        1,
                        pageSize,
                        &misalignedView,
                ));
                assert(misalignedView.inert);
            }
        }
    }
}
