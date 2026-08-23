module xtb.core.pool;

nothrow @nogc:

import core.lifetime : emplace, forward;
import core.stdc.string : memset;
import xtb.core.allocators.internal.virtual_memory : VirtualMemoryRegion,
    VirtualMemoryReservation, tryReserveVirtualMemory, virtualMemoryPageSize,
    virtualMemorySupported;
import xtb.core.lifetime : canFinalizeWithoutContext, finalize, move, moveEmplace,
    needsDeinit, needsFinalization;
import xtb.core.numeric : addOverflows;
import xtb.core.panic : panic;
import xtb.core.virtual_array : defaultVirtualCommitGranularity,
    tryAlignAddressUp, tryVirtualArrayRegionGeometry, VirtualArrayRegionGeometry,
    VirtualArrayView;

version (XTB_Checked) import xtb.core.panic : require;

private enum size_t occupiedBitsPerWord = size_t.sizeof * 8;

/// Fixed-capacity stable-address typed recycling pool backed by one virtual
/// memory reservation.
///
/// Index zero is permanently invalid. Live/dead state lives in a compact
/// occupancy bitmap and recycled slots are tracked by integer indices, so Pool
/// never stores allocator metadata in `T` and never overwrites an inactive
/// element representation merely to recycle its storage.
struct Pool(T)
{
nothrow @nogc:

    alias Self = Pool!T;

private:
    VirtualMemoryReservation reservation_;
    VirtualArrayView!T values_;
    VirtualArrayView!size_t occupiedWords_;
    VirtualArrayView!uint freeIndices_;

    uint capacity_;
    size_t nextIndex_;
    size_t freeCount_;
    size_t liveCount_;

public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Attempts to create an empty Pool with `capacity` usable slots.
    ///
    /// Capacity zero succeeds as the inert state without requiring virtual
    /// memory support. Nonzero capacity reserves all address space up front but
    /// commits no slot/state pages until the first virgin allocation.
    static bool tryCreate(uint capacity, scope Self* output) @system
    {
        version (XTB_Checked)
        {
            require(output !is null, "Pool output pointer is null");
            require(output is null || output.inert,
                "Pool output is already initialized");
        }

        if (output is null || !output.inert)
            return false;
        if (capacity == 0)
            return true;
        if (!virtualMemorySupported)
            return false;

        const pageSize = virtualMemoryPageSize();
        if (pageSize == 0)
            return false;

        PoolLayout layout;
        if (!tryPoolLayout!T(capacity, pageSize, &layout))
            return false;

        VirtualMemoryReservation reservation;
        if (!tryReserveVirtualMemory(layout.reservationBytes, &reservation))
            return false;
        scope (exit)
            reservation.deinit();

        VirtualMemoryRegion valuesRegion;
        VirtualMemoryRegion occupiedRegion;
        VirtualMemoryRegion freeRegion;
        if (!tryPoolRegions(
                reservation,
                layout,
                &valuesRegion,
                &occupiedRegion,
                &freeRegion,
            ))
            return false;

        VirtualArrayView!T values;
        if (!VirtualArrayView!T.tryCreate(
                valuesRegion,
                layout.valueCapacity,
                defaultVirtualCommitGranularity,
                &values,
            ))
            return false;
        scope (exit)
            values.deinit();

        VirtualArrayView!size_t occupiedWords;
        if (!VirtualArrayView!size_t.tryCreate(
                occupiedRegion,
                layout.occupiedWordCount,
                defaultVirtualCommitGranularity,
                &occupiedWords,
            ))
            return false;
        scope (exit)
            occupiedWords.deinit();

        VirtualArrayView!uint freeIndices;
        if (!VirtualArrayView!uint.tryCreate(
                freeRegion,
                capacity,
                defaultVirtualCommitGranularity,
                &freeIndices,
            ))
            return false;
        scope (exit)
            freeIndices.deinit();

        Self result;
        moveEmplace(reservation, result.reservation_);
        moveEmplace(values, result.values_);
        moveEmplace(occupiedWords, result.occupiedWords_);
        moveEmplace(freeIndices, result.freeIndices_);
        result.capacity_ = capacity;
        result.nextIndex_ = 1;
        moveEmplace(result, *output);
        return true;
    }

    /// Creates an empty Pool or panics when its virtual reservation cannot be
    /// established.
    static Self create(uint capacity) @system
    {
        Self result;
        if (!tryCreate(capacity, &result))
            panic("Pool reservation failed");
        return move(result);
    }

    /// Activates one raw slot and returns its stable storage address.
    ///
    /// The returned storage is not initialized as `T`; callers must establish
    /// the value before using semantic live-item APIs. Failure leaves Pool
    /// logical state unchanged.
    T* tryAllocate() @system
    {
        uint index;
        if (freeCount_ != 0)
        {
            const stackIndex = freeCount_ - 1;
            index = freeIndices_.ptr[stackIndex];
            --freeCount_;

            version (XTB_Checked)
            {
                require(index != 0 && index <= capacity_,
                    "Pool free-index stack is corrupt");
                require(!occupied(index),
                    "Pool free-index stack contains an occupied slot");
            }
        }
        else
        {
            if (nextIndex_ == 0 || nextIndex_ > capacity_)
                return null;

            index = cast(uint) nextIndex_;
            if (!tryProvisionVirgin(index))
                return null;
            ++nextIndex_;
        }

        setOccupied(index, true);
        ++liveCount_;
        return values_.ptr + index;
    }

    /// Activates one raw slot or panics when fixed capacity or virtual backing
    /// is exhausted.
    T* allocate() @system
    {
        T* result = tryAllocate();
        if (result is null)
            panic("Pool capacity or commitment exceeded");
        return result;
    }

    /// Attempts to activate one slot and establish its `T.init` lifetime.
    T* tryAllocateInit() @system
    {
        T* result = tryAllocate();
        if (result !is null)
            emplace(result);
        return result;
    }

    /// Activates one slot and establishes its `T.init` lifetime, or panics when
    /// fixed capacity or virtual backing is exhausted.
    T* allocateInit() @system
    {
        T* result = allocate();
        emplace(result);
        return result;
    }

    /// Attempts to activate and construct one `T` with `emplace`.
    T* tryConstruct(Args...)(auto ref Args arguments) @system
    {
        T* result = tryAllocate();
        if (result !is null)
            emplace(result, forward!arguments);
        return result;
    }

    /// Activates and constructs one `T`, or panics when fixed capacity or
    /// virtual backing is exhausted.
    T* construct(Args...)(auto ref Args arguments) @system
    {
        T* result = allocate();
        emplace(result, forward!arguments);
        return result;
    }

    /// Recycles one occupied slot without finalizing or overwriting `T`.
    ///
    /// Every virgin allocation provisions enough free-index storage for its
    /// future recycle before publishing the slot, so deallocation never needs
    /// to allocate or commit virtual memory.
    void deallocate(T* value) @system
    {
        uint index;
        version (XTB_Checked)
        {
            require(value !is null, "Pool deallocation pointer is null");
            index = checkedPhysicalIndex(value);
            require(index != 0, "Pool deallocation pointer does not belong to Pool");
            require(occupied(index), "Pool slot is already inactive");
            require(freeCount_ < freeIndices_.provisionedLength,
                "Pool free-index provisioning invariant violated");
        }
        else
        {
            const valueAddress = cast(size_t) value;
            const baseAddress = cast(size_t) values_.ptr;
            index = cast(uint)((valueAddress - baseAddress) / T.sizeof);
        }

        setOccupied(index, false);
        freeIndices_.ptr[freeCount_] = index;
        ++freeCount_;
        --liveCount_;
    }

    /// Finalizes a live value without external cleanup context, then recycles
    /// its slot. The Pool itself does not overwrite the post-finalization
    /// representation.
    static if (canFinalizeWithoutContext!T)
    {
        void dispose(T* value) @system
        {
            version (XTB_Checked)
            {
                require(value !is null, "Pool disposal pointer is null");
                const index = checkedPhysicalIndex(value);
                require(index != 0 && occupied(index),
                    "Pool disposal requires an occupied Pool slot");
            }

            static if (needsFinalization!T)
                finalize(*value);
            deallocate(value);
        }
    }

    /// Returns the live value at `index`, or null for zero, out-of-capacity, or
    /// inactive indices.
    T* get(uint index) return @trusted
    {
        if (!occupied(index))
            return null;
        return values_.ptr + index;
    }

    const(T)* get(uint index) const return @trusted
    {
        if (!occupied(index))
            return null;
        return values_.ptr + index;
    }

    /// Returns the stable index of an occupied value owned by this Pool, or
    /// zero when the pointer is null, foreign, misaligned, or inactive.
    uint indexOf(scope const T* value) const @trusted
    {
        const index = physicalIndex(value);
        return index != 0 && occupied(index) ? index : 0;
    }

    /// Whether `index` currently denotes an occupied slot.
    bool contains(uint index) const @trusted
    {
        return occupied(index);
    }

    /// Discards all live Pool state without finalizing or overwriting values.
    /// Previously provisioned pages remain committed and reusable.
    void clear() @trusted
    {
        const wordCount = occupiedWords_.provisionedLength;
        if (wordCount != 0)
            memset(occupiedWords_.ptr, 0, wordCount * size_t.sizeof);

        freeCount_ = 0;
        liveCount_ = 0;
        nextIndex_ = capacity_ == 0 ? 0 : 1;
    }

    /// Ends all local views and releases the complete virtual reservation.
    /// Live values are not finalized.
    void deinit() @system
    {
        values_.deinit();
        occupiedWords_.deinit();
        freeIndices_.deinit();
        reservation_.deinit();
        capacity_ = 0;
        nextIndex_ = 0;
        freeCount_ = 0;
        liveCount_ = 0;
    }

    uint capacity() const pure @safe
    {
        return capacity_;
    }

    size_t liveCount() const pure @safe
    {
        return liveCount_;
    }

    bool empty() const pure @safe
    {
        return liveCount_ == 0;
    }

private:
    bool tryProvisionVirgin(uint index) @system
    {
        const valueCount = cast(size_t) index + 1;
        const wordIndex = occupiedWordIndex(index);

        // Provision all storage needed by this slot's entire future lifecycle
        // before publishing the index. Advancing one view's raw high-water is
        // harmless if a later view fails: Pool logical state remains unchanged
        // and a retry reuses the already committed prefix.
        if (!values_.tryEnsureAccessible(valueCount))
            return false;
        if (!occupiedWords_.tryEnsureAccessible(wordIndex + 1))
            return false;
        if (!freeIndices_.tryEnsureAccessible(index))
            return false;
        return true;
    }

    bool occupied(uint index) const @trusted
    {
        if (index == 0 || index > capacity_)
            return false;

        const wordIndex = occupiedWordIndex(index);
        if (wordIndex >= occupiedWords_.provisionedLength)
            return false;

        return (occupiedWords_.ptr[wordIndex] & occupiedBit(index)) != 0;
    }

    void setOccupied(uint index, bool value) @trusted
    {
        const wordIndex = occupiedWordIndex(index);
        const bit = occupiedBit(index);
        if (value)
            occupiedWords_.ptr[wordIndex] |= bit;
        else
            occupiedWords_.ptr[wordIndex] &= ~bit;
    }

    uint physicalIndex(scope const T* value) const @trusted
    {
        if (value is null || values_.ptr is null || values_.provisionedLength <= 1)
            return 0;

        const baseAddress = cast(size_t) values_.ptr;
        const valueAddress = cast(size_t) value;
        if (valueAddress < baseAddress)
            return 0;

        const byteOffset = valueAddress - baseAddress;
        if (byteOffset % T.sizeof != 0)
            return 0;

        const index = byteOffset / T.sizeof;
        if (index == 0 || index >= values_.provisionedLength || index > capacity_)
            return 0;
        return cast(uint) index;
    }

    version (XTB_Checked) uint checkedPhysicalIndex(scope const T* value) const @trusted
    {
        return physicalIndex(value);
    }

    bool inert() const pure @safe
    {
        return !reservation_.active &&
            values_.inert &&
            occupiedWords_.inert &&
            freeIndices_.inert &&
            capacity_ == 0 &&
            nextIndex_ == 0 &&
            freeCount_ == 0 &&
            liveCount_ == 0;
    }
}

static assert(needsDeinit!(Pool!ubyte));

private struct PoolLayout
{
    VirtualArrayRegionGeometry values;
    VirtualArrayRegionGeometry occupiedWords;
    VirtualArrayRegionGeometry freeIndices;
    size_t valueCapacity;
    size_t occupiedWordCount;
    size_t reservationBytes;
}

private bool tryPoolLayout(T)(
    uint capacity,
    size_t pageSize,
    scope PoolLayout* output,
) pure @safe
{
    if (output is null || capacity == 0 || pageSize == 0)
        return false;

    const capacityAsSize = cast(size_t) capacity;
    if (addOverflows(capacityAsSize, 1))
        return false;
    const valueCapacity = capacityAsSize + 1;

    size_t occupiedWordCount = valueCapacity / occupiedBitsPerWord;
    if (valueCapacity % occupiedBitsPerWord != 0)
        ++occupiedWordCount;

    PoolLayout result;
    result.valueCapacity = valueCapacity;
    result.occupiedWordCount = occupiedWordCount;
    if (!tryVirtualArrayRegionGeometry!T(
            valueCapacity,
            pageSize,
            &result.values,
        ))
        return false;
    if (!tryVirtualArrayRegionGeometry!size_t(
            occupiedWordCount,
            pageSize,
            &result.occupiedWords,
        ))
        return false;
    if (!tryVirtualArrayRegionGeometry!uint(
            capacityAsSize,
            pageSize,
            &result.freeIndices,
        ))
        return false;

    size_t total;
    if (!tryAddRegionBytes(total, result.values) ||
        !tryAddRegionBytes(total, result.occupiedWords) ||
        !tryAddRegionBytes(total, result.freeIndices))
        return false;
    result.reservationBytes = total;
    *output = result;
    return true;
}

private bool tryAddRegionBytes(
    ref size_t total,
    scope const VirtualArrayRegionGeometry geometry,
) pure @safe
{
    if (addOverflows(total, geometry.alignmentSlack))
        return false;
    total += geometry.alignmentSlack;
    if (addOverflows(total, geometry.regionBytes))
        return false;
    total += geometry.regionBytes;
    return true;
}

private bool tryPoolRegions(
    ref VirtualMemoryReservation reservation,
    scope const PoolLayout layout,
    scope VirtualMemoryRegion* values,
    scope VirtualMemoryRegion* occupiedWords,
    scope VirtualMemoryRegion* freeIndices,
) @system
{
    if (values is null || occupiedWords is null || freeIndices is null)
        return false;

    const reservationBase = cast(size_t) reservation.base;
    size_t cursor = reservationBase;

    void* valuesBase;
    if (!tryAlignAddressUp(
            cast(void*) cursor,
            layout.values.baseAlignment,
            &valuesBase,
        ))
        return false;
    const valuesAddress = cast(size_t) valuesBase;
    if (valuesAddress < reservationBase)
        return false;
    const valuesOffset = valuesAddress - reservationBase;
    if (!reservation.tryRegion(valuesOffset, layout.values.regionBytes, values))
        return false;
    if (addOverflows(valuesAddress, layout.values.regionBytes))
        return false;
    cursor = valuesAddress + layout.values.regionBytes;

    void* occupiedBase;
    if (!tryAlignAddressUp(
            cast(void*) cursor,
            layout.occupiedWords.baseAlignment,
            &occupiedBase,
        ))
        return false;
    const occupiedAddress = cast(size_t) occupiedBase;
    if (occupiedAddress < reservationBase)
        return false;
    const occupiedOffset = occupiedAddress - reservationBase;
    if (!reservation.tryRegion(
            occupiedOffset,
            layout.occupiedWords.regionBytes,
            occupiedWords,
        ))
        return false;
    if (addOverflows(occupiedAddress, layout.occupiedWords.regionBytes))
        return false;
    cursor = occupiedAddress + layout.occupiedWords.regionBytes;

    void* freeBase;
    if (!tryAlignAddressUp(
            cast(void*) cursor,
            layout.freeIndices.baseAlignment,
            &freeBase,
        ))
        return false;
    const freeAddress = cast(size_t) freeBase;
    if (freeAddress < reservationBase)
        return false;
    const freeOffset = freeAddress - reservationBase;
    if (!reservation.tryRegion(
            freeOffset,
            layout.freeIndices.regionBytes,
            freeIndices,
        ))
        return false;

    return true;
}

private size_t occupiedWordIndex(uint index) pure @safe
{
    return cast(size_t) index / occupiedBitsPerWord;
}

private size_t occupiedBit(uint index) pure @safe
{
    return size_t(1) << (cast(size_t) index % occupiedBitsPerWord);
}

unittest
{
    import core.stdc.string : memcmp;
    import xtb.core.lifetime : moveAssign;

    static assert(__traits(compiles, (ref const Pool!int pool) {
            const auto capacity = pool.capacity;
            const auto count = pool.liveCount;
            const auto isEmpty = pool.empty;
            cast(void) capacity;
            cast(void) count;
            cast(void) isEmpty;
        }));

    Pool!int zero;
    assert(zero.capacity == 0);
    assert(zero.liveCount == 0);
    assert(zero.empty);
    assert(zero.tryAllocate() is null);
    zero.clear();
    zero.deinit();

    Pool!int zeroCreated = Pool!int.create(0);
    assert(zeroCreated.capacity == 0);
    zeroCreated.deinit();

    if (!virtualMemorySupported)
        return;

    Pool!int pool = Pool!int.create(4);
    scope (exit)
        pool.deinit();

    assert(pool.capacity == 4);
    assert(pool.liveCount == 0);
    assert(pool.get(0) is null);
    assert(!pool.contains(0));

    int* first = pool.allocateInit();
    int* second = pool.allocateInit();
    *first = 11;
    *second = 22;
    assert(pool.indexOf(first) == 1);
    assert(pool.indexOf(second) == 2);
    assert(pool.get(1) is first);
    assert(pool.get(2) is second);
    assert(pool.liveCount == 2);

    const valueCommitted = pool.values_.committedBytes;
    const occupiedCommitted = pool.occupiedWords_.committedBytes;
    const freeCommitted = pool.freeIndices_.committedBytes;
    pool.deallocate(first);
    assert(pool.values_.committedBytes == valueCommitted);
    assert(pool.occupiedWords_.committedBytes == occupiedCommitted);
    assert(pool.freeIndices_.committedBytes == freeCommitted);
    assert(pool.indexOf(first) == 0);
    assert(pool.get(1) is null);
    assert(pool.liveCount == 1);

    int* recycled = pool.tryAllocate();
    assert(recycled is first);
    assert(pool.values_.committedBytes == valueCommitted);
    assert(pool.occupiedWords_.committedBytes == occupiedCommitted);
    assert(pool.freeIndices_.committedBytes == freeCommitted);
    assert(*recycled == 11);
    pool.deallocate(recycled);

    int* third = pool.allocateInit();
    int* fourth = pool.allocateInit();
    assert(pool.indexOf(third) == 1);
    assert(pool.indexOf(fourth) == 3);
    int* last = pool.allocateInit();
    assert(pool.indexOf(last) == 4);
    assert(pool.tryAllocate() is null);
    assert(pool.tryAllocateInit() is null);

    const uint bitmapCapacity = cast(uint)(occupiedBitsPerWord + 2);
    Pool!ubyte bitmapPool = Pool!ubyte.create(bitmapCapacity);
    scope (exit)
        bitmapPool.deinit();
    foreach (index; 1 .. bitmapCapacity + 1)
    {
        ubyte* value = bitmapPool.allocateInit();
        assert(bitmapPool.indexOf(value) == index);
    }
    assert(bitmapPool.contains(cast(uint) occupiedBitsPerWord));
    assert(bitmapPool.contains(cast(uint)(occupiedBitsPerWord + 1)));

    enum uint freeCommitBoundary = 16_385;
    Pool!ubyte commitBoundary = Pool!ubyte.create(freeCommitBoundary);
    scope (exit)
        commitBoundary.deinit();
    foreach (index; 1 .. freeCommitBoundary)
        commitBoundary.allocate();
    const freeBytesBeforeBoundary = commitBoundary.freeIndices_.committedBytes;
    ubyte* boundaryValue = commitBoundary.allocate();
    assert(commitBoundary.indexOf(boundaryValue) == freeCommitBoundary);
    assert(commitBoundary.freeIndices_.committedBytes > freeBytesBeforeBoundary);
    const freeBytesAfterBoundary = commitBoundary.freeIndices_.committedBytes;
    commitBoundary.deallocate(boundaryValue);
    assert(commitBoundary.freeIndices_.committedBytes == freeBytesAfterBoundary);

    Pool!int reuseOrder = Pool!int.create(4);
    scope (exit)
        reuseOrder.deinit();
    int* reuseOne = reuseOrder.allocateInit();
    int* reuseTwo = reuseOrder.allocateInit();
    int* reuseThree = reuseOrder.allocateInit();
    reuseOrder.deallocate(reuseOne);
    reuseOrder.deallocate(reuseThree);
    assert(reuseOrder.allocate() is reuseThree);
    assert(reuseOrder.allocate() is reuseOne);
    assert(reuseOrder.indexOf(reuseTwo) == 2);

    struct Representation
    {
        uint first;
        uint second;
    }

    Pool!Representation representations = Pool!Representation.create(3);
    scope (exit)
        representations.deinit();
    Representation* representation = representations.allocateInit();
    representation.first = 0x1234_5678;
    representation.second = 0x9abc_def0;
    Representation snapshot = *representation;
    representations.deallocate(representation);
    assert(memcmp(representation, &snapshot, Representation.sizeof) == 0);
    Representation* sameRepresentation = representations.allocate();
    assert(sameRepresentation is representation);
    assert(memcmp(sameRepresentation, &snapshot, Representation.sizeof) == 0);

    Representation* otherRepresentation = representations.allocateInit();
    otherRepresentation.first = 7;
    otherRepresentation.second = 9;
    Representation otherSnapshot = *otherRepresentation;
    representations.clear();
    assert(representations.liveCount == 0);
    assert(representations.empty);
    assert(representations.indexOf(sameRepresentation) == 0);
    assert(representations.indexOf(otherRepresentation) == 0);
    assert(memcmp(sameRepresentation, &snapshot, Representation.sizeof) == 0);
    assert(memcmp(otherRepresentation, &otherSnapshot, Representation.sizeof) == 0);

    struct Tiny
    {
        ubyte value;
    }

    Pool!Tiny tiny = Pool!Tiny.create(2);
    scope (exit)
        tiny.deinit();
    Tiny* tinyValue = tiny.allocateInit();
    assert(tiny.indexOf(tinyValue) == 1);

    align(32_768) struct OverAligned
    {
        ubyte value;
    }

    Pool!OverAligned overAligned = Pool!OverAligned.create(2);
    scope (exit)
        overAligned.deinit();
    OverAligned* alignedValue = overAligned.allocateInit();
    assert(cast(size_t) alignedValue % OverAligned.alignof == 0);
    assert(overAligned.indexOf(alignedValue) == 1);

    struct ExplicitOwner
    {
    nothrow @nogc:
        size_t* deinitCount;
        bool active;

        @disable this(this);

        this(size_t* deinitCount)
        {
            this.deinitCount = deinitCount;
            active = true;
        }

        void deinit()
        {
            if (active)
            {
                ++*deinitCount;
                active = false;
            }
        }
    }

    size_t explicitDeinits;
    Pool!ExplicitOwner explicitPool = Pool!ExplicitOwner.create(2);
    scope (exit)
        explicitPool.deinit();
    ExplicitOwner* explicitOwner = explicitPool.construct(&explicitDeinits);
    explicitPool.dispose(explicitOwner);
    assert(explicitDeinits == 1);
    assert(!explicitOwner.active);
    assert(explicitPool.liveCount == 0);

    size_t shallowClearDeinits;
    Pool!ExplicitOwner shallowClearPool = Pool!ExplicitOwner.create(1);
    ExplicitOwner* shallowClearOwner = shallowClearPool.construct(&shallowClearDeinits);
    shallowClearPool.clear();
    assert(shallowClearDeinits == 0);
    finalize(*shallowClearOwner);
    assert(shallowClearDeinits == 1);
    shallowClearPool.deinit();

    size_t shallowDeinitCount;
    Pool!ExplicitOwner shallowDeinitPool = Pool!ExplicitOwner.create(1);
    shallowDeinitPool.construct(&shallowDeinitCount);
    shallowDeinitPool.deinit();
    assert(shallowDeinitCount == 0);

    struct DestructorOnly
    {
    nothrow @nogc:
        size_t* destructions;

        @disable this(this);

        this(size_t* destructions)
        {
            this.destructions = destructions;
        }

        ~this()
        {
            ++*destructions;
        }
    }

    size_t destructions;
    Pool!DestructorOnly destructorPool = Pool!DestructorOnly.create(1);
    scope (exit)
        destructorPool.deinit();
    DestructorOnly* destructorValue = destructorPool.construct(&destructions);
    destructorPool.dispose(destructorValue);
    assert(destructions == 1);

    struct ContextOwner
    {
    nothrow @nogc:
        void deinit(int*)
        {
        }
    }

    static assert(!canFinalizeWithoutContext!ContextOwner);
    static assert(!__traits(compiles, (ref Pool!ContextOwner contextPool,
            ContextOwner* value) { contextPool.dispose(value); }));

    Pool!int source = Pool!int.create(8);
    int* sourceValue = source.allocateInit();
    *sourceValue = 77;
    Pool!int moved = move(source);
    assert(source.capacity == 0);
    assert(source.empty);
    assert(moved.capacity == 8);
    assert(moved.get(1) !is null && *moved.get(1) == 77);
    source.deinit();

    Pool!int target = Pool!int.create(2);
    target.allocateInit();
    moveAssign(moved, target);
    assert(moved.capacity == 0);
    assert(target.capacity == 8);
    assert(target.get(1) !is null && *target.get(1) == 77);
    moved.deinit();
    target.deinit();
}
