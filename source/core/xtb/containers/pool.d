module xtb.containers.pool;

nothrow @nogc:

import core.bitop : bsf;
import core.lifetime : emplace, forward;
import core.stdc.string : memset;
import xtb.allocators.internal.virtual_memory : VirtualMemoryRegion,
    VirtualMemoryReservation, tryReserveVirtualMemory, virtualMemoryPageSize,
    virtualMemorySupported;
import xtb.lifetime : can_finalize_without_context, finalize, move, move_emplace,
    needs_deinit, needs_finalization;
import xtb.numeric : add_overflows;
import xtb.panic : panic;
import xtb.containers.internal.pool_storage : IndexedPoolStorageLayout,
    tryIndexedPoolStorageLayout, tryIndexedPoolStorageRegions;
import xtb.containers.virtual_array : defaultVirtualCommitGranularity, VirtualArrayView;

version (XTB_Checked) import xtb.panic : require;

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

    version (XTB_Checked) size_t mutationGeneration_ = 1;

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

        IndexedPoolStorageLayout layout;
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
        if (!tryIndexedPoolStorageRegions(
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
                layout.stateCapacity,
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
        move_emplace(reservation, result.reservation_);
        move_emplace(values, result.values_);
        move_emplace(occupiedWords, result.occupiedWords_);
        move_emplace(freeIndices, result.freeIndices_);
        result.capacity_ = capacity;
        result.nextIndex_ = 1;
        move_emplace(result, *output);
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
            index = freeIndices_[stackIndex];
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
        version (XTB_Checked)
            ++mutationGeneration_;
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
        freeIndices_[freeCount_] = index;
        ++freeCount_;
        --liveCount_;
        version (XTB_Checked)
            ++mutationGeneration_;
    }

    /// Finalizes a live value without external cleanup context, then recycles
    /// its slot. The Pool itself does not overwrite the post-finalization
    /// representation.
    static if (can_finalize_without_context!T)
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

            static if (needs_finalization!T)
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

    /// Returns an input range over occupied values in stable index order.
    ///
    /// Structural Pool mutation invalidates the range. Checked builds diagnose
    /// use after invalidation; unchecked builds carry no mutation-generation
    /// bookkeeping.
    PoolItemsRange!T items() return @trusted
    {
        return PoolItemsRange!T.create(&this);
    }

    ConstPoolItemsRange!T items() const return @trusted
    {
        return ConstPoolItemsRange!T.create(&this);
    }

    /// Returns occupied values together with their stable indices.
    ///
    /// This uses the same occupied-slot cursor as `items()` and
    /// `occupiedSlots()` and performs no second bitmap scan.
    PoolOccupiedSlotsRange!T indexedItems() return @trusted
    {
        return PoolOccupiedSlotsRange!T.create(&this);
    }

    ConstPoolOccupiedSlotsRange!T indexedItems() const return @trusted
    {
        return ConstPoolOccupiedSlotsRange!T.create(&this);
    }

    /// Returns an input range over occupied slots in stable index order.
    /// Each slot exposes its index and live value by reference.
    PoolOccupiedSlotsRange!T occupiedSlots() return @trusted
    {
        return PoolOccupiedSlotsRange!T.create(&this);
    }

    ConstPoolOccupiedSlotsRange!T occupiedSlots() const return @trusted
    {
        return ConstPoolOccupiedSlotsRange!T.create(&this);
    }

    /// Returns an input range over every deliberately provisioned slot,
    /// including inactive slots whose preserved representation may be inspected.
    /// The range never walks the untouched tail of the maximum capacity.
    PoolSlotsRange!T slots() return @trusted
    {
        return PoolSlotsRange!T.create(&this);
    }

    ConstPoolSlotsRange!T slots() const return @trusted
    {
        return ConstPoolSlotsRange!T.create(&this);
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
        version (XTB_Checked)
            ++mutationGeneration_;
    }

    /// Ends all local views and releases the complete virtual reservation.
    /// Live values are not finalized.
    void deinit() @system
    {
        version (XTB_Checked)
            ++mutationGeneration_;
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

        return (occupiedWords_[wordIndex] & occupiedBit(index)) != 0;
    }

    void setOccupied(uint index, bool value) @trusted
    {
        const wordIndex = occupiedWordIndex(index);
        const bit = occupiedBit(index);
        if (value)
            occupiedWords_[wordIndex] |= bit;
        else
            occupiedWords_[wordIndex] &= ~bit;
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

/// Mutable occupied-slot view returned by `Pool.occupiedSlots`.
///
/// The view borrows Pool storage. Structural Pool mutation invalidates it.
struct PoolOccupiedSlot(T)
{
nothrow @nogc:

private:
    T* value_;
    uint index_;
    version (XTB_Checked)
    {
        const(Pool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    ref T value() return @system
    {
        version (XTB_Checked)
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
        return *value_;
    }
}

/// Read-only occupied-slot view returned by a const Pool.
struct ConstPoolOccupiedSlot(T)
{
nothrow @nogc:

private:
    const(T)* value_;
    uint index_;
    version (XTB_Checked)
    {
        const(Pool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
        return *value_;
    }
}

/// Mutable view of one deliberately provisioned Pool slot.
///
/// `storage` exposes preserved representation even while inactive and is
/// therefore deliberately `@system`. `value` additionally requires occupancy.
struct PoolSlot(T)
{
nothrow @nogc:

private:
    T* storage_;
    uint index_;
    bool occupied_;
    version (XTB_Checked)
    {
        const(Pool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    bool occupied() const @trusted
    {
        version (XTB_Checked)
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
        return occupied_;
    }

    ref T value() return @system
    {
        version (XTB_Checked)
        {
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
            require(occupied_, "inactive Pool slot has no live value");
        }
        return *storage_;
    }

    ref T storage() return @system
    {
        version (XTB_Checked)
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
        return *storage_;
    }
}

/// Read-only view of one deliberately provisioned slot from a const Pool.
struct ConstPoolSlot(T)
{
nothrow @nogc:

private:
    const(T)* storage_;
    uint index_;
    bool occupied_;
    version (XTB_Checked)
    {
        const(Pool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    bool occupied() const @trusted
    {
        version (XTB_Checked)
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
        return occupied_;
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
        {
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
            require(occupied_, "inactive Pool slot has no live value");
        }
        return *storage_;
    }

    ref const(T) storage() const return @system
    {
        version (XTB_Checked)
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
        return *storage_;
    }
}

/// Input range yielding occupied Pool values directly by reference.
struct PoolItemsRange(T)
{
nothrow @nogc:

private:
    PoolOccupiedCursor!T cursor_;
    T* values_;

    static PoolItemsRange create(Pool!T* pool) @trusted
    {
        PoolItemsRange result;
        result.cursor_ = PoolOccupiedCursor!T.create(pool);
        result.values_ = pool.values_.ptr;
        return result;
    }

public:
    bool empty() const @trusted
    {
        return cursor_.empty;
    }

    ref T front() return @system
    {
        return values_[cursor_.index];
    }

    void popFront() @trusted
    {
        cursor_.popFront();
    }
}

/// Read-only input range yielding occupied Pool values by const reference.
struct ConstPoolItemsRange(T)
{
nothrow @nogc:

private:
    PoolOccupiedCursor!T cursor_;
    const(T)* values_;

    static ConstPoolItemsRange create(const(Pool!T)* pool) @trusted
    {
        ConstPoolItemsRange result;
        result.cursor_ = PoolOccupiedCursor!T.create(pool);
        result.values_ = pool.values_.ptr;
        return result;
    }

public:
    bool empty() const @trusted
    {
        return cursor_.empty;
    }

    ref const(T) front() const return @system
    {
        return values_[cursor_.index];
    }

    void popFront() @trusted
    {
        cursor_.popFront();
    }
}

/// Input range yielding occupied slots with stable indices and live values.
struct PoolOccupiedSlotsRange(T)
{
nothrow @nogc:

private:
    PoolOccupiedCursor!T cursor_;
    T* values_;
    version (XTB_Checked)
    {
        const(Pool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
    }

    static PoolOccupiedSlotsRange create(Pool!T* pool) @trusted
    {
        PoolOccupiedSlotsRange result;
        result.cursor_ = PoolOccupiedCursor!T.create(pool);
        result.values_ = pool.values_.ptr;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        return cursor_.empty;
    }

    PoolOccupiedSlot!T front() return @system
    {
        const index = cursor_.index;
        PoolOccupiedSlot!T result;
        result.value_ = values_ + index;
        result.index_ = index;
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        cursor_.popFront();
    }
}

/// Read-only occupied-slot range for a const Pool.
struct ConstPoolOccupiedSlotsRange(T)
{
nothrow @nogc:

private:
    PoolOccupiedCursor!T cursor_;
    const(T)* values_;
    version (XTB_Checked)
    {
        const(Pool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
    }

    static ConstPoolOccupiedSlotsRange create(const(Pool!T)* pool) @trusted
    {
        ConstPoolOccupiedSlotsRange result;
        result.cursor_ = PoolOccupiedCursor!T.create(pool);
        result.values_ = pool.values_.ptr;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        return cursor_.empty;
    }

    ConstPoolOccupiedSlot!T front() const return @system
    {
        const index = cursor_.index;
        ConstPoolOccupiedSlot!T result;
        result.value_ = values_ + index;
        result.index_ = index;
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        cursor_.popFront();
    }
}

/// Sequential input range over all deliberately provisioned Pool slots.
struct PoolSlotsRange(T)
{
nothrow @nogc:

private:
    T* values_;
    const(size_t)* occupiedWords_;
    size_t index_;
    size_t endIndex_;
    version (XTB_Checked)
    {
        const(Pool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
    }

    static PoolSlotsRange create(Pool!T* pool) @trusted
    {
        PoolSlotsRange result;
        result.values_ = pool.values_.ptr;
        result.occupiedWords_ = pool.occupiedWords_.ptr;
        result.index_ = 1;
        result.endIndex_ = pool.values_.provisionedLength;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        version (XTB_Checked)
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
        return index_ >= endIndex_;
    }

    PoolSlot!T front() return @system
    {
        version (XTB_Checked)
        {
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
            require(index_ < endIndex_, "front of empty Pool slots range");
        }

        const index = cast(uint) index_;
        PoolSlot!T result;
        result.storage_ = values_ + index;
        result.index_ = index;
        result.occupied_ = poolOccupiedBit(occupiedWords_, index);
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        version (XTB_Checked)
        {
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
            require(index_ < endIndex_, "popFront of empty Pool slots range");
        }
        ++index_;
    }
}

/// Read-only sequential range over all deliberately provisioned slots.
struct ConstPoolSlotsRange(T)
{
nothrow @nogc:

private:
    const(T)* values_;
    const(size_t)* occupiedWords_;
    size_t index_;
    size_t endIndex_;
    version (XTB_Checked)
    {
        const(Pool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
    }

    static ConstPoolSlotsRange create(const(Pool!T)* pool) @trusted
    {
        ConstPoolSlotsRange result;
        result.values_ = pool.values_.ptr;
        result.occupiedWords_ = pool.occupiedWords_.ptr;
        result.index_ = 1;
        result.endIndex_ = pool.values_.provisionedLength;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        version (XTB_Checked)
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
        return index_ >= endIndex_;
    }

    ConstPoolSlot!T front() const return @system
    {
        version (XTB_Checked)
        {
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
            require(index_ < endIndex_, "front of empty Pool slots range");
        }

        const index = cast(uint) index_;
        ConstPoolSlot!T result;
        result.storage_ = values_ + index;
        result.index_ = index;
        result.occupied_ = poolOccupiedBit(occupiedWords_, index);
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        version (XTB_Checked)
        {
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
            require(index_ < endIndex_, "popFront of empty Pool slots range");
        }
        ++index_;
    }
}

private struct PoolOccupiedCursor(T)
{
nothrow @nogc:

private:
    const(size_t)* occupiedWords_;
    size_t wordCount_;
    size_t wordIndex_;
    size_t liveBits_;
    version (XTB_Checked)
    {
        const(Pool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
    }

    static PoolOccupiedCursor create(const(Pool!T)* pool) @trusted
    {
        PoolOccupiedCursor result;
        result.occupiedWords_ = pool.occupiedWords_.ptr;
        result.wordCount_ = pool.occupiedWords_.provisionedLength;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
        }
        result.seekOccupiedWord();
        return result;
    }

public:
    pragma(inline, true)
    bool empty() const @trusted
    {
        version (XTB_Checked)
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
        return liveBits_ == 0;
    }

    pragma(inline, true)
    uint index() const @trusted
    {
        version (XTB_Checked)
        {
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
            require(liveBits_ != 0, "front of empty Pool occupied range");
        }

        return cast(uint)(wordIndex_ * occupiedBitsPerWord + bsf(liveBits_));
    }

    pragma(inline, true)
    void popFront() @trusted
    {
        version (XTB_Checked)
        {
            requirePoolViewValid(owner_, mutationGeneration_, valuesBase_);
            require(liveBits_ != 0, "popFront of empty Pool occupied range");
        }

        liveBits_ &= liveBits_ - 1;
        if (liveBits_ == 0)
        {
            ++wordIndex_;
            seekOccupiedWord();
        }
    }

private:
    pragma(inline, true)
    void seekOccupiedWord() @trusted
    {
        while (wordIndex_ < wordCount_)
        {
            liveBits_ = occupiedWords_[wordIndex_];
            if (liveBits_ != 0)
                return;
            ++wordIndex_;
        }
        liveBits_ = 0;
    }
}

private bool poolOccupiedBit(scope const size_t* occupiedWords, uint index) @trusted
{
    return (occupiedWords[occupiedWordIndex(index)] & occupiedBit(index)) != 0;
}

version (XTB_Checked) private void requirePoolViewValid(T)(
    scope const Pool!T* owner,
    size_t mutationGeneration,
    scope const T* valuesBase,
) @trusted
{
    require(owner !is null, "Pool range has no owner");
    require(owner.mutationGeneration_ == mutationGeneration,
        "Pool range was invalidated by structural mutation");
    require(owner.values_.ptr is valuesBase,
        "Pool range was invalidated by move or deinit");
}

static assert(needs_deinit!(Pool!ubyte));

private bool tryPoolLayout(T)(
    uint capacity,
    size_t pageSize,
    scope IndexedPoolStorageLayout* output,
) pure @safe
{
    if (output is null || capacity == 0 || pageSize == 0)
        return false;

    const capacityAsSize = cast(size_t) capacity;
    if (add_overflows(capacityAsSize, 1))
        return false;
    const valueCapacity = capacityAsSize + 1;

    size_t occupiedWordCount = valueCapacity / occupiedBitsPerWord;
    if (valueCapacity % occupiedBitsPerWord != 0)
        ++occupiedWordCount;

    return tryIndexedPoolStorageLayout!(T, size_t)(
        capacity,
        occupiedWordCount,
        pageSize,
        output,
    );
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
    import xtb.lifetime : move_assign;

    static assert(__traits(compiles, (ref const Pool!int pool) {
            const auto capacity = pool.capacity;
            const auto count = pool.liveCount;
            const auto isEmpty = pool.empty;
            auto items = pool.items();
            auto indexedItems = pool.indexedItems();
            auto occupiedSlots = pool.occupiedSlots();
            auto slots = pool.slots();
            cast(void) capacity;
            cast(void) count;
            cast(void) isEmpty;
            cast(void) items;
            cast(void) indexedItems;
            cast(void) occupiedSlots;
            cast(void) slots;
        }));

    version (XTB_Checked)
        static assert(__traits(hasMember, Pool!int, "mutationGeneration_"));
    else
        static assert(!__traits(hasMember, Pool!int, "mutationGeneration_"));

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

    size_t denseRangeCount;
    foreach (ref value; bitmapPool.items())
    {
        cast(void) value;
        ++denseRangeCount;
    }
    assert(denseRangeCount == bitmapCapacity);

    enum uint sparseCapacity = cast(uint)(occupiedBitsPerWord * 2 + 2);
    Pool!uint sparseRanges = Pool!uint.create(sparseCapacity);
    scope (exit)
        sparseRanges.deinit();
    uint*[sparseCapacity] sparseValues;
    foreach (offset; 0 .. sparseCapacity)
    {
        uint* value = sparseRanges.allocateInit();
        *value = cast(uint)(offset + 1);
        sparseValues[offset] = value;
    }
    foreach (index; 2 .. sparseCapacity + 1)
    {
        if (index != occupiedBitsPerWord * 2 + 1)
            sparseRanges.deallocate(sparseValues[index - 1]);
    }
    uint[2] sparseIndices;
    size_t sparseCount;
    foreach (slot; sparseRanges.occupiedSlots())
        sparseIndices[sparseCount++] = slot.index;
    assert(sparseCount == 2);
    assert(sparseIndices[0] == 1);
    assert(sparseIndices[1] == occupiedBitsPerWord * 2 + 1);

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

    Pool!int ranges = Pool!int.create(8);
    scope (exit)
        ranges.deinit();
    int* rangeOne = ranges.allocateInit();
    int* rangeTwo = ranges.allocateInit();
    int* rangeThree = ranges.allocateInit();
    int* rangeFour = ranges.allocateInit();
    *rangeOne = 10;
    *rangeTwo = 20;
    *rangeThree = 30;
    *rangeFour = 40;
    ranges.deallocate(rangeTwo);
    ranges.deallocate(rangeFour);

    size_t itemCount;
    foreach (ref item; ranges.items())
    {
        item += 100;
        ++itemCount;
    }
    assert(itemCount == 2);
    assert(*rangeOne == 110);
    assert(*rangeThree == 130);
    assert(*rangeTwo == 20);
    assert(*rangeFour == 40);

    uint[2] indexedIndices;
    size_t indexedCount;
    foreach (item; ranges.indexedItems())
    {
        indexedIndices[indexedCount++] = item.index;
        item.value += 1;
    }
    assert(indexedCount == 2);
    assert(indexedIndices == [1, 3]);
    assert(*rangeOne == 111);
    assert(*rangeThree == 131);

    uint[2] occupiedIndices;
    size_t occupiedCount;
    foreach (slot; ranges.occupiedSlots())
    {
        occupiedIndices[occupiedCount++] = slot.index;
        slot.value += 1;
    }
    assert(occupiedCount == 2);
    assert(occupiedIndices == [1, 3]);
    assert(*rangeOne == 112);
    assert(*rangeThree == 132);

    uint[4] slotIndices;
    bool[4] slotOccupancy;
    int[4] slotRepresentations;
    size_t slotCount;
    foreach (slot; ranges.slots())
    {
        slotIndices[slotCount] = slot.index;
        slotOccupancy[slotCount] = slot.occupied;
        slotRepresentations[slotCount] = slot.storage;
        ++slotCount;
    }
    assert(slotCount == 4);
    assert(slotIndices == [1, 2, 3, 4]);
    assert(slotOccupancy == [true, false, true, false]);
    assert(slotRepresentations == [112, 20, 132, 40]);

    auto manual = ranges.items();
    assert(!manual.empty);
    assert(&manual.front() is rangeOne);
    manual.popFront();
    assert(!manual.empty);
    assert(&manual.front() is rangeThree);
    manual.popFront();
    assert(manual.empty);

    auto independentLeft = ranges.items();
    auto independentRight = ranges.items();
    independentLeft.popFront();
    assert(&independentLeft.front() is rangeThree);
    assert(&independentRight.front() is rangeOne);

    const(Pool!int)* constRanges = &ranges;
    size_t constItemCount;
    foreach (ref const item; constRanges.items())
    {
        assert(item == 112 || item == 132);
        ++constItemCount;
    }
    assert(constItemCount == 2);

    size_t constIndexedCount;
    foreach (item; constRanges.indexedItems())
    {
        assert(item.index == 1 || item.index == 3);
        assert(item.value == 112 || item.value == 132);
        ++constIndexedCount;
    }
    assert(constIndexedCount == 2);

    size_t constOccupiedCount;
    foreach (slot; constRanges.occupiedSlots())
    {
        assert(slot.index == 1 || slot.index == 3);
        assert(slot.value == 112 || slot.value == 132);
        ++constOccupiedCount;
    }
    assert(constOccupiedCount == 2);

    size_t constSlotCount;
    foreach (slot; constRanges.slots())
    {
        assert(slot.index >= 1 && slot.index <= 4);
        cast(void) slot.storage;
        ++constSlotCount;
    }
    assert(constSlotCount == 4);

    ranges.clear();
    size_t clearedSlotCount;
    foreach (slot; ranges.slots())
    {
        assert(!slot.occupied);
        ++clearedSlotCount;
    }
    assert(clearedSlotCount == 4);
    assert(ranges.items().empty);
    assert(ranges.occupiedSlots().empty);

    struct Tiny
    {
        ubyte value;
    }

    Pool!Tiny tiny = Pool!Tiny.create(2);
    scope (exit)
        tiny.deinit();
    Tiny* tinyValue = tiny.allocateInit();
    assert(tiny.indexOf(tinyValue) == 1);

    align(8_192) struct OverAligned
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

    static assert(!can_finalize_without_context!ContextOwner);
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
    move_assign(moved, target);
    assert(moved.capacity == 0);
    assert(target.capacity == 8);
    assert(target.get(1) !is null && *target.get(1) == 77);
    moved.deinit();
    target.deinit();
}
