module xtb.core.containers.generational_pool;

nothrow @nogc:

import core.lifetime : emplace, forward;
import xtb.core.allocators.internal.virtual_memory : VirtualMemoryRegion,
    VirtualMemoryReservation, tryReserveVirtualMemory, virtualMemoryPageSize,
    virtualMemorySupported;
import xtb.core.lifetime : canFinalizeWithoutContext, finalize, move, moveEmplace,
    needsDeinit, needsFinalization;
import xtb.core.numeric : addOverflows;
import xtb.core.panic : panic;
import xtb.core.containers.internal.pool_storage : IndexedPoolStorageLayout,
    tryIndexedPoolStorageLayout, tryIndexedPoolStorageRegions;
import xtb.core.containers.virtual_array : defaultVirtualCommitGranularity, VirtualArrayView;

version (XTB_Checked) import xtb.core.panic : require;

private enum uint activeBit = uint(1) << 31;
private enum uint generationMask = activeBit - 1;

/// Fixed-capacity stable-address typed recycling pool with generational handles.
///
/// Index zero is permanently invalid. Each usable slot stores its active bit and
/// generation in a separate packed state word, leaving `T` untouched while the
/// slot is inactive. Stale-handle rejection is semantic and remains enabled in
/// every build mode.
struct GenerationalPool(T)
{
nothrow @nogc:

    alias Self = GenerationalPool!T;

    /// Identifies one live incarnation of one stable slot in a
    /// `GenerationalPool!T`.
    ///
    /// `Handle.init` is invalid because index zero is permanently reserved.
    struct Handle
    {
        uint index;
        uint generation;

        /// Whether this is a non-null handle representation.
        ///
        /// A non-null handle may still be stale, out of range, or belong to a
        /// different pool instance. Use `GenerationalPool.contains` when
        /// current pool membership matters.
        bool valid() const pure @safe
        {
            return index != 0;
        }
    }

private:
    VirtualMemoryReservation reservation_;
    VirtualArrayView!T values_;
    VirtualArrayView!uint states_;
    VirtualArrayView!uint freeIndices_;

    uint capacity_;
    size_t nextIndex_;
    size_t freeCount_;
    size_t liveCount_;

    version (XTB_Checked) size_t mutationGeneration_ = 1;

public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Attempts to create an empty generational pool with `capacity` usable
    /// slots.
    ///
    /// Capacity zero succeeds as the inert state without requiring virtual
    /// memory support. Nonzero capacity reserves all address space up front but
    /// commits no value/state/free-index pages until the first virgin
    /// allocation.
    static bool tryCreate(uint capacity, scope Self* output) @system
    {
        version (XTB_Checked)
        {
            require(output !is null, "GenerationalPool output pointer is null");
            require(output is null || output.inert,
                "GenerationalPool output is already initialized");
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

        const capacityAsSize = cast(size_t) capacity;
        if (addOverflows(capacityAsSize, 1))
            return false;
        const stateCapacity = capacityAsSize + 1;

        IndexedPoolStorageLayout layout;
        if (!tryIndexedPoolStorageLayout!(T, uint)(
                capacity,
                stateCapacity,
                pageSize,
                &layout,
            ))
            return false;

        VirtualMemoryReservation reservation;
        if (!tryReserveVirtualMemory(layout.reservationBytes, &reservation))
            return false;
        scope (exit)
            reservation.deinit();

        VirtualMemoryRegion valuesRegion;
        VirtualMemoryRegion statesRegion;
        VirtualMemoryRegion freeRegion;
        if (!tryIndexedPoolStorageRegions(
                reservation,
                layout,
                &valuesRegion,
                &statesRegion,
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

        VirtualArrayView!uint states;
        if (!VirtualArrayView!uint.tryCreate(
                statesRegion,
                layout.stateCapacity,
                defaultVirtualCommitGranularity,
                &states,
            ))
            return false;
        scope (exit)
            states.deinit();

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
        moveEmplace(states, result.states_);
        moveEmplace(freeIndices, result.freeIndices_);
        result.capacity_ = capacity;
        result.nextIndex_ = 1;
        moveEmplace(result, *output);
        return true;
    }

    /// Creates an empty GenerationalPool or panics when its virtual reservation
    /// cannot be established.
    static Self create(uint capacity) @system
    {
        Self result;
        if (!tryCreate(capacity, &result))
            panic("GenerationalPool reservation failed");
        return move(result);
    }

    /// Activates one raw slot and writes its handle to `output`.
    ///
    /// The slot's storage is not initialized as `T`; callers must establish the
    /// value before using it semantically. Failure leaves Pool logical state and
    /// `output` unchanged.
    bool tryAllocate(scope Handle* output) @system
    {
        version (XTB_Checked)
            require(output !is null, "GenerationalPool handle output is null");
        if (output is null)
            return false;

        uint index;
        if (freeCount_ != 0)
        {
            const stackIndex = freeCount_ - 1;
            index = freeIndices_[stackIndex];
            --freeCount_;

            version (XTB_Checked)
            {
                require(index != 0 && index <= capacity_,
                    "GenerationalPool free-index stack is corrupt");
                require(index < states_.provisionedLength,
                    "GenerationalPool free-index stack exceeds provisioned state");
                require(!stateActive(states_[index]),
                    "GenerationalPool free-index stack contains an active slot");
            }
        }
        else
        {
            if (nextIndex_ == 0 || nextIndex_ > capacity_)
                return false;

            index = cast(uint) nextIndex_;
            if (!tryProvisionVirgin(index))
                return false;
            ++nextIndex_;
        }

        const activeState = activateState(states_[index]);
        states_[index] = activeState;
        ++liveCount_;
        version (XTB_Checked)
            ++mutationGeneration_;

        *output = Handle(index, stateGeneration(activeState));
        return true;
    }

    /// Activates one raw slot or panics when fixed capacity or virtual backing
    /// is exhausted.
    Handle allocate() @system
    {
        Handle result;
        if (!tryAllocate(&result))
            panic("GenerationalPool capacity or commitment exceeded");
        return result;
    }

    /// Attempts to activate one slot and establish its `T.init` lifetime.
    bool tryAllocateInit(scope Handle* output) @system
    {
        version (XTB_Checked)
            require(output !is null, "GenerationalPool handle output is null");
        if (output is null)
            return false;

        Handle result;
        if (!tryAllocate(&result))
            return false;
        emplace(values_.ptr + result.index);
        *output = result;
        return true;
    }

    /// Activates one slot and establishes its `T.init` lifetime, or panics when
    /// fixed capacity or virtual backing is exhausted.
    Handle allocateInit() @system
    {
        Handle result = allocate();
        emplace(values_.ptr + result.index);
        return result;
    }

    /// Attempts to activate and construct one `T` with `emplace`.
    bool tryConstruct(Args...)(scope Handle* output, auto ref Args arguments) @system
    {
        version (XTB_Checked)
            require(output !is null, "GenerationalPool handle output is null");
        if (output is null)
            return false;

        Handle result;
        if (!tryAllocate(&result))
            return false;
        emplace(values_.ptr + result.index, forward!arguments);
        *output = result;
        return true;
    }

    /// Activates and constructs one `T`, or panics when fixed capacity or
    /// virtual backing is exhausted.
    Handle construct(Args...)(auto ref Args arguments) @system
    {
        Handle result = allocate();
        emplace(values_.ptr + result.index, forward!arguments);
        return result;
    }

    /// Returns the live value identified by `handle`, or null when the handle is
    /// null, out of range, inactive, or stale.
    T* get(Handle handle) return @trusted
    {
        return validHandle(handle) ? values_.ptr + handle.index : null;
    }

    const(T)* get(Handle handle) const return @trusted
    {
        return validHandle(handle) ? values_.ptr + handle.index : null;
    }

    /// Whether `handle` currently identifies a live value in this Pool.
    bool contains(Handle handle) const @trusted
    {
        return validHandle(handle);
    }

    /// Returns an input range over live values in stable index order.
    ///
    /// Structural Pool mutation invalidates the range. Checked builds diagnose
    /// use after invalidation; unchecked builds carry no mutation-generation
    /// bookkeeping.
    GenerationalPoolItemsRange!T items() return @trusted
    {
        return GenerationalPoolItemsRange!T.create(&this);
    }

    ConstGenerationalPoolItemsRange!T items() const return @trusted
    {
        return ConstGenerationalPoolItemsRange!T.create(&this);
    }

    /// Returns live values together with their stable indices.
    ///
    /// This uses the same live-item cursor as `items()` and performs no second
    /// state scan. It deliberately omits generation/handle materialization; use
    /// `occupiedSlots()` when that additional identity metadata is needed.
    GenerationalPoolIndexedItemsRange!T indexedItems() return @trusted
    {
        return GenerationalPoolIndexedItemsRange!T.create(&this);
    }

    ConstGenerationalPoolIndexedItemsRange!T indexedItems() const return @trusted
    {
        return ConstGenerationalPoolIndexedItemsRange!T.create(&this);
    }

    /// Returns an input range over live slots in stable index order. Each slot
    /// exposes its index, generation, handle, and live value by reference.
    GenerationalPoolOccupiedSlotsRange!T occupiedSlots() return @trusted
    {
        return GenerationalPoolOccupiedSlotsRange!T.create(&this);
    }

    ConstGenerationalPoolOccupiedSlotsRange!T occupiedSlots() const return @trusted
    {
        return ConstGenerationalPoolOccupiedSlotsRange!T.create(&this);
    }

    /// Returns an input range over every deliberately provisioned slot,
    /// including inactive slots whose preserved representation may be inspected.
    /// The range never walks the untouched tail of maximum capacity.
    GenerationalPoolSlotsRange!T slots() return @trusted
    {
        return GenerationalPoolSlotsRange!T.create(&this);
    }

    ConstGenerationalPoolSlotsRange!T slots() const return @trusted
    {
        return ConstGenerationalPoolSlotsRange!T.create(&this);
    }

    /// Attempts to recycle the slot identified by `handle` without finalizing
    /// or overwriting `T`.
    ///
    /// Invalid and stale handles are normal failure and return false in every
    /// build mode. Successful deallocation performs no allocation or virtual
    /// memory commitment.
    bool tryDeallocate(Handle handle) @system
    {
        if (!validHandle(handle))
            return false;

        const index = handle.index;
        states_[index] = deactivateAndAdvance(states_[index]);
        freeIndices_[freeCount_] = index;
        ++freeCount_;
        --liveCount_;
        version (XTB_Checked)
            ++mutationGeneration_;
        return true;
    }

    /// Recycles one live handle or panics when it is invalid or stale.
    void deallocate(Handle handle) @system
    {
        if (!tryDeallocate(handle))
            panic("GenerationalPool handle is invalid or stale");
    }

    /// Finalizes a live value without external cleanup context, then recycles
    /// its slot.
    static if (canFinalizeWithoutContext!T)
    {
        bool tryDispose(Handle handle) @system
        {
            T* value = get(handle);
            if (value is null)
                return false;

            static if (needsFinalization!T)
                finalize(*value);
            return tryDeallocate(handle);
        }

        void dispose(Handle handle) @system
        {
            if (!tryDispose(handle))
                panic("GenerationalPool handle is invalid or stale");
        }
    }

    /// Invalidates every live handle without finalizing or overwriting values.
    /// Previously provisioned pages and per-slot generations remain reusable.
    void clear() @trusted
    {
        const provisioned = states_.provisionedLength;
        foreach (index; 1 .. provisioned)
        {
            const state = states_[index];
            if (stateActive(state))
                states_[index] = deactivateAndAdvance(state);
        }

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
        states_.deinit();
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
        const elementCount = cast(size_t) index + 1;

        // Provision every region needed by this slot's entire future lifecycle
        // before publishing the index. Later deallocation therefore cannot
        // allocate or commit virtual memory.
        if (!values_.tryEnsureAccessible(elementCount))
            return false;
        if (!states_.tryEnsureAccessible(elementCount))
            return false;
        if (!freeIndices_.tryEnsureAccessible(index))
            return false;
        return true;
    }

    bool validHandle(Handle handle) const @trusted
    {
        if (handle.index == 0 || handle.index > capacity_)
            return false;

        const index = cast(size_t) handle.index;
        if (index >= states_.provisionedLength)
            return false;

        const state = states_[index];
        return stateActive(state) && stateGeneration(state) == handle.generation;
    }

    bool inert() const pure @safe
    {
        return !reservation_.active &&
            values_.inert &&
            states_.inert &&
            freeIndices_.inert &&
            capacity_ == 0 &&
            nextIndex_ == 0 &&
            freeCount_ == 0 &&
            liveCount_ == 0;
    }
}

/// Mutable live-slot view returned by `GenerationalPool.occupiedSlots`.
///
/// The view borrows Pool storage. Structural Pool mutation invalidates it.
struct GenerationalPoolOccupiedSlot(T)
{
nothrow @nogc:

    alias Handle = GenerationalPool!T.Handle;

private:
    T* value_;
    uint index_;
    uint generation_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    uint generation() const pure @safe
    {
        return generation_;
    }

    Handle handle() const @trusted
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return Handle(index_, generation_);
    }

    ref T value() return @system
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return *value_;
    }
}

/// Read-only live-slot view returned by a const GenerationalPool.
struct ConstGenerationalPoolOccupiedSlot(T)
{
nothrow @nogc:

    alias Handle = GenerationalPool!T.Handle;

private:
    const(T)* value_;
    uint index_;
    uint generation_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    uint generation() const pure @safe
    {
        return generation_;
    }

    Handle handle() const @trusted
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return Handle(index_, generation_);
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return *value_;
    }
}

/// Mutable view of one deliberately provisioned GenerationalPool slot.
///
/// `storage` exposes preserved representation even while inactive and is
/// therefore deliberately `@system`. `value` additionally requires occupancy.
struct GenerationalPoolSlot(T)
{
nothrow @nogc:

    alias Handle = GenerationalPool!T.Handle;

private:
    T* storage_;
    uint index_;
    uint generation_;
    bool occupied_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    uint generation() const pure @safe
    {
        return generation_;
    }

    bool occupied() const @trusted
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return occupied_;
    }

    /// Returns the live handle for this slot, or `Handle.init` while inactive.
    Handle handle() const @trusted
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return occupied_ ? Handle(index_, generation_) : Handle.init;
    }

    ref T value() return @system
    {
        version (XTB_Checked)
        {
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
            require(occupied_, "inactive GenerationalPool slot has no live value");
        }
        return *storage_;
    }

    ref T storage() return @system
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return *storage_;
    }
}

/// Read-only view of one deliberately provisioned GenerationalPool slot.
struct ConstGenerationalPoolSlot(T)
{
nothrow @nogc:

    alias Handle = GenerationalPool!T.Handle;

private:
    const(T)* storage_;
    uint index_;
    uint generation_;
    bool occupied_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    uint generation() const pure @safe
    {
        return generation_;
    }

    bool occupied() const @trusted
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return occupied_;
    }

    Handle handle() const @trusted
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return occupied_ ? Handle(index_, generation_) : Handle.init;
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
        {
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
            require(occupied_, "inactive GenerationalPool slot has no live value");
        }
        return *storage_;
    }

    ref const(T) storage() const return @system
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return *storage_;
    }
}

/// Mutable live-item view returned by `GenerationalPool.indexedItems`.
struct GenerationalPoolIndexedItem(T)
{
nothrow @nogc:

private:
    T* value_;
    uint index_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    ref T value() return @system
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return *value_;
    }
}

/// Read-only live-item view returned by a const `GenerationalPool.indexedItems`.
struct ConstGenerationalPoolIndexedItem(T)
{
nothrow @nogc:

private:
    const(T)* value_;
    uint index_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

public:
    uint index() const pure @safe
    {
        return index_;
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return *value_;
    }
}

/// Input range yielding live GenerationalPool values directly by reference.
struct GenerationalPoolItemsRange(T)
{
nothrow @nogc:

private:
    GenerationalPoolOccupiedCursor!T cursor_;
    T* values_;

    static GenerationalPoolItemsRange create(GenerationalPool!T* pool) @trusted
    {
        GenerationalPoolItemsRange result;
        result.cursor_ = GenerationalPoolOccupiedCursor!T.create(pool);
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

/// Read-only input range yielding live GenerationalPool values by const reference.
struct ConstGenerationalPoolItemsRange(T)
{
nothrow @nogc:

private:
    GenerationalPoolOccupiedCursor!T cursor_;
    const(T)* values_;

    static ConstGenerationalPoolItemsRange create(const(GenerationalPool!T)* pool) @trusted
    {
        ConstGenerationalPoolItemsRange result;
        result.cursor_ = GenerationalPoolOccupiedCursor!T.create(pool);
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

/// Input range yielding live values with stable indices.
struct GenerationalPoolIndexedItemsRange(T)
{
nothrow @nogc:

private:
    GenerationalPoolOccupiedCursor!T cursor_;
    T* values_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

    static GenerationalPoolIndexedItemsRange create(GenerationalPool!T* pool) @trusted
    {
        GenerationalPoolIndexedItemsRange result;
        result.cursor_ = GenerationalPoolOccupiedCursor!T.create(pool);
        result.values_ = pool.values_.ptr;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
            result.statesBase_ = pool.states_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        return cursor_.empty;
    }

    GenerationalPoolIndexedItem!T front() return @system
    {
        GenerationalPoolIndexedItem!T result;
        result.value_ = values_ + cursor_.index;
        result.index_ = cursor_.index;
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
            result.statesBase_ = statesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        cursor_.popFront();
    }
}

/// Read-only input range yielding live values with stable indices.
struct ConstGenerationalPoolIndexedItemsRange(T)
{
nothrow @nogc:

private:
    GenerationalPoolOccupiedCursor!T cursor_;
    const(T)* values_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

    static ConstGenerationalPoolIndexedItemsRange create(
        const(GenerationalPool!T)* pool,
    ) @trusted
    {
        ConstGenerationalPoolIndexedItemsRange result;
        result.cursor_ = GenerationalPoolOccupiedCursor!T.create(pool);
        result.values_ = pool.values_.ptr;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
            result.statesBase_ = pool.states_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        return cursor_.empty;
    }

    ConstGenerationalPoolIndexedItem!T front() const return @system
    {
        ConstGenerationalPoolIndexedItem!T result;
        result.value_ = values_ + cursor_.index;
        result.index_ = cursor_.index;
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
            result.statesBase_ = statesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        cursor_.popFront();
    }
}

/// Input range yielding live slots with stable identity metadata.
struct GenerationalPoolOccupiedSlotsRange(T)
{
nothrow @nogc:

private:
    GenerationalPoolOccupiedCursor!T cursor_;
    T* values_;
    const(uint)* states_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

    static GenerationalPoolOccupiedSlotsRange create(GenerationalPool!T* pool) @trusted
    {
        GenerationalPoolOccupiedSlotsRange result;
        result.cursor_ = GenerationalPoolOccupiedCursor!T.create(pool);
        result.values_ = pool.values_.ptr;
        result.states_ = pool.states_.ptr;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
            result.statesBase_ = pool.states_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        return cursor_.empty;
    }

    GenerationalPoolOccupiedSlot!T front() return @system
    {
        const index = cursor_.index;
        const state = states_[index];
        GenerationalPoolOccupiedSlot!T result;
        result.value_ = values_ + index;
        result.index_ = index;
        result.generation_ = stateGeneration(state);
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
            result.statesBase_ = statesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        cursor_.popFront();
    }
}

/// Read-only live-slot range for a const GenerationalPool.
struct ConstGenerationalPoolOccupiedSlotsRange(T)
{
nothrow @nogc:

private:
    GenerationalPoolOccupiedCursor!T cursor_;
    const(T)* values_;
    const(uint)* states_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

    static ConstGenerationalPoolOccupiedSlotsRange create(const(GenerationalPool!T)* pool) @trusted
    {
        ConstGenerationalPoolOccupiedSlotsRange result;
        result.cursor_ = GenerationalPoolOccupiedCursor!T.create(pool);
        result.values_ = pool.values_.ptr;
        result.states_ = pool.states_.ptr;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
            result.statesBase_ = pool.states_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        return cursor_.empty;
    }

    ConstGenerationalPoolOccupiedSlot!T front() const return @system
    {
        const index = cursor_.index;
        const state = states_[index];
        ConstGenerationalPoolOccupiedSlot!T result;
        result.value_ = values_ + index;
        result.index_ = index;
        result.generation_ = stateGeneration(state);
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
            result.statesBase_ = statesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        cursor_.popFront();
    }
}

/// Sequential input range over all deliberately provisioned GenerationalPool slots.
struct GenerationalPoolSlotsRange(T)
{
nothrow @nogc:

private:
    T* values_;
    const(uint)* states_;
    size_t index_;
    size_t endIndex_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

    static GenerationalPoolSlotsRange create(GenerationalPool!T* pool) @trusted
    {
        GenerationalPoolSlotsRange result;
        result.values_ = pool.values_.ptr;
        result.states_ = pool.states_.ptr;
        result.index_ = 1;
        result.endIndex_ = pool.states_.provisionedLength;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
            result.statesBase_ = pool.states_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return index_ >= endIndex_;
    }

    GenerationalPoolSlot!T front() return @system
    {
        version (XTB_Checked)
        {
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
            require(index_ < endIndex_, "front of empty GenerationalPool slots range");
        }

        const index = cast(uint) index_;
        const state = states_[index];
        GenerationalPoolSlot!T result;
        result.storage_ = values_ + index;
        result.index_ = index;
        result.generation_ = stateGeneration(state);
        result.occupied_ = stateActive(state);
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
            result.statesBase_ = statesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        version (XTB_Checked)
        {
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
            require(index_ < endIndex_, "popFront of empty GenerationalPool slots range");
        }
        ++index_;
    }
}

/// Read-only sequential range over all deliberately provisioned GenerationalPool slots.
struct ConstGenerationalPoolSlotsRange(T)
{
nothrow @nogc:

private:
    const(T)* values_;
    const(uint)* states_;
    size_t index_;
    size_t endIndex_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

    static ConstGenerationalPoolSlotsRange create(const(GenerationalPool!T)* pool) @trusted
    {
        ConstGenerationalPoolSlotsRange result;
        result.values_ = pool.values_.ptr;
        result.states_ = pool.states_.ptr;
        result.index_ = 1;
        result.endIndex_ = pool.states_.provisionedLength;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
            result.statesBase_ = pool.states_.ptr;
        }
        return result;
    }

public:
    bool empty() const @trusted
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return index_ >= endIndex_;
    }

    ConstGenerationalPoolSlot!T front() const return @system
    {
        version (XTB_Checked)
        {
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
            require(index_ < endIndex_, "front of empty GenerationalPool slots range");
        }

        const index = cast(uint) index_;
        const state = states_[index];
        ConstGenerationalPoolSlot!T result;
        result.storage_ = values_ + index;
        result.index_ = index;
        result.generation_ = stateGeneration(state);
        result.occupied_ = stateActive(state);
        version (XTB_Checked)
        {
            result.owner_ = owner_;
            result.mutationGeneration_ = mutationGeneration_;
            result.valuesBase_ = valuesBase_;
            result.statesBase_ = statesBase_;
        }
        return result;
    }

    void popFront() @trusted
    {
        version (XTB_Checked)
        {
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
            require(index_ < endIndex_, "popFront of empty GenerationalPool slots range");
        }
        ++index_;
    }
}

private struct GenerationalPoolOccupiedCursor(T)
{
nothrow @nogc:

private:
    const(uint)* states_;
    size_t index_;
    size_t endIndex_;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner_;
        size_t mutationGeneration_;
        const(T)* valuesBase_;
        const(uint)* statesBase_;
    }

    static GenerationalPoolOccupiedCursor create(const(GenerationalPool!T)* pool) @trusted
    {
        GenerationalPoolOccupiedCursor result;
        result.states_ = pool.states_.ptr;
        result.index_ = 1;
        result.endIndex_ = pool.states_.provisionedLength;
        version (XTB_Checked)
        {
            result.owner_ = pool;
            result.mutationGeneration_ = pool.mutationGeneration_;
            result.valuesBase_ = pool.values_.ptr;
            result.statesBase_ = pool.states_.ptr;
        }
        result.seekOccupied();
        return result;
    }

public:
    pragma(inline, true)
    bool empty() const @trusted
    {
        version (XTB_Checked)
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
        return index_ >= endIndex_;
    }

    pragma(inline, true)
    uint index() const @trusted
    {
        version (XTB_Checked)
        {
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
            require(index_ < endIndex_, "front of empty GenerationalPool occupied range");
        }
        return cast(uint) index_;
    }

    pragma(inline, true)
    void popFront() @trusted
    {
        version (XTB_Checked)
        {
            requireGenerationalPoolViewValid(owner_, mutationGeneration_, valuesBase_, statesBase_);
            require(index_ < endIndex_, "popFront of empty GenerationalPool occupied range");
        }
        ++index_;
        seekOccupied();
    }

private:
    pragma(inline, true)
    void seekOccupied() @trusted
    {
        while (index_ < endIndex_ && !stateActive(states_[index_]))
            ++index_;
    }
}

version (XTB_Checked) private void requireGenerationalPoolViewValid(T)(
    scope const GenerationalPool!T* owner,
    size_t mutationGeneration,
    scope const T* valuesBase,
    scope const uint* statesBase,
) @trusted
{
    require(owner !is null, "GenerationalPool range has no owner");
    require(owner.mutationGeneration_ == mutationGeneration,
        "GenerationalPool range was invalidated by structural mutation");
    require(owner.values_.ptr is valuesBase && owner.states_.ptr is statesBase,
        "GenerationalPool range was invalidated by move or deinit");
}

pragma(inline, true)
private bool stateActive(uint state) pure @safe
{
    return (state & activeBit) != 0;
}

pragma(inline, true)
private uint stateGeneration(uint state) pure @safe
{
    return state & generationMask;
}

pragma(inline, true)
private uint activateState(uint state) pure @safe
{
    return activeBit | stateGeneration(state);
}

pragma(inline, true)
private uint deactivateAndAdvance(uint state) pure @safe
{
    return (stateGeneration(state) + 1) & generationMask;
}

static assert(needsDeinit!(GenerationalPool!ubyte));
static assert(activeBit == 0x8000_0000u);
static assert(generationMask == 0x7fff_ffffu);

unittest
{
    import core.stdc.string : memcmp;
    import xtb.core.lifetime : moveAssign;

    alias IntPool = GenerationalPool!int;
    alias IntHandle = IntPool.Handle;

    static assert(IntHandle.init.index == 0);
    static assert(IntHandle.init.generation == 0);
    static assert(!IntHandle.init.valid);
    static assert(!__traits(compiles,
            (ref IntPool intPool, GenerationalPool!uint.Handle otherHandle) {
            intPool.get(otherHandle);
        }));
    static assert(__traits(compiles, (ref const IntPool pool, IntHandle handle) {
            const auto capacity = pool.capacity;
            const auto count = pool.liveCount;
            const auto isEmpty = pool.empty;
            const auto present = pool.contains(handle);
            const int* value = pool.get(handle);
            auto items = pool.items();
            auto indexedItems = pool.indexedItems();
            auto occupiedSlots = pool.occupiedSlots();
            auto slots = pool.slots();
            cast(void) items;
            cast(void) indexedItems;
            cast(void) occupiedSlots;
            cast(void) slots;
            cast(void) capacity;
            cast(void) count;
            cast(void) isEmpty;
            cast(void) present;
            cast(void) value;
        }));

    version (XTB_Checked)
    {
        static assert(__traits(hasMember, IntPool, "mutationGeneration_"));
        static assert(__traits(hasMember, GenerationalPoolSlot!int, "owner_"));
    }
    else
    {
        static assert(!__traits(hasMember, IntPool, "mutationGeneration_"));
        static assert(!__traits(hasMember, GenerationalPoolSlot!int, "owner_"));
    }

    assert(!stateActive(0));
    assert(stateGeneration(0) == 0);
    assert(stateActive(activateState(0)));
    assert(stateGeneration(activateState(0)) == 0);
    assert(deactivateAndAdvance(activeBit | generationMask) == 0);
    assert(!stateActive(deactivateAndAdvance(activeBit | generationMask)));

    IntPool zero;
    assert(zero.capacity == 0);
    assert(zero.liveCount == 0);
    assert(zero.empty);
    assert(zero.get(IntHandle.init) is null);
    assert(!zero.contains(IntHandle.init));
    IntHandle unchanged = IntHandle(17, 19);
    assert(!zero.tryAllocate(&unchanged));
    assert(unchanged == IntHandle(17, 19));
    zero.clear();
    zero.deinit();

    IntPool zeroCreated = IntPool.create(0);
    assert(zeroCreated.capacity == 0);
    zeroCreated.deinit();

    if (!virtualMemorySupported)
        return;

    IntPool pool = IntPool.create(3);
    scope (exit)
        pool.deinit();

    assert(pool.capacity == 3);
    assert(pool.liveCount == 0);
    assert(pool.get(IntHandle.init) is null);

    IntHandle first = pool.allocateInit();
    IntHandle second = pool.allocateInit();
    *pool.get(first) = 11;
    *pool.get(second) = 22;
    assert(first.index == 1 && first.generation == 0);
    assert(second.index == 2 && second.generation == 0);
    assert(first.valid);
    assert(second.valid);
    assert(pool.contains(first));
    assert(pool.contains(second));
    assert(*pool.get(first) == 11);
    assert(*pool.get(second) == 22);
    assert(pool.liveCount == 2);

    const valueCommitted = pool.values_.committedBytes;
    const stateCommitted = pool.states_.committedBytes;
    const freeCommitted = pool.freeIndices_.committedBytes;
    assert(pool.tryDeallocate(first));
    assert(first.valid); // non-null representation; pool-relative membership is stale
    assert(!pool.contains(first));
    assert(pool.get(first) is null);
    assert(!pool.tryDeallocate(first));
    assert(pool.values_.committedBytes == valueCommitted);
    assert(pool.states_.committedBytes == stateCommitted);
    assert(pool.freeIndices_.committedBytes == freeCommitted);

    IntHandle recycled = pool.allocate();
    assert(recycled.index == first.index);
    assert(recycled.generation == first.generation + 1);
    assert(pool.values_.committedBytes == valueCommitted);
    assert(pool.states_.committedBytes == stateCommitted);
    assert(pool.freeIndices_.committedBytes == freeCommitted);
    assert(pool.get(first) is null);
    assert(pool.get(recycled) !is null);

    enum uint freeCommitBoundary = 16_385;
    GenerationalPool!ubyte commitBoundary =
        GenerationalPool!ubyte.create(freeCommitBoundary);
    scope (exit)
        commitBoundary.deinit();
    foreach (_; 1 .. freeCommitBoundary)
        commitBoundary.allocate();
    const freeBytesBeforeBoundary = commitBoundary.freeIndices_.committedBytes;
    auto boundaryHandle = commitBoundary.allocate();
    assert(boundaryHandle.index == freeCommitBoundary);
    assert(commitBoundary.freeIndices_.committedBytes > freeBytesBeforeBoundary);
    const boundaryValuesCommitted = commitBoundary.values_.committedBytes;
    const boundaryStatesCommitted = commitBoundary.states_.committedBytes;
    const boundaryFreeCommitted = commitBoundary.freeIndices_.committedBytes;
    commitBoundary.deallocate(boundaryHandle);
    assert(commitBoundary.values_.committedBytes == boundaryValuesCommitted);
    assert(commitBoundary.states_.committedBytes == boundaryStatesCommitted);
    assert(commitBoundary.freeIndices_.committedBytes == boundaryFreeCommitted);

    IntHandle third = pool.allocateInit();
    assert(third.index == 3);
    IntHandle sentinel = IntHandle(77, 88);
    assert(!pool.tryAllocate(&sentinel));
    assert(sentinel == IntHandle(77, 88));

    // Exercise generation wrap through the public deallocation path.
    pool.states_[recycled.index] = activeBit | generationMask;
    IntHandle wrapHandle = IntHandle(recycled.index, generationMask);
    assert(pool.tryDeallocate(wrapHandle));
    assert(pool.states_[wrapHandle.index] == 0);
    IntHandle wrapped = pool.allocate();
    assert(wrapped.index == wrapHandle.index);
    assert(wrapped.generation == 0);

    struct Representation
    {
        uint first;
        uint second;
    }

    GenerationalPool!Representation representations =
        GenerationalPool!Representation.create(2);
    scope (exit)
        representations.deinit();
    auto representationHandle = representations.allocateInit();
    Representation* representation = representations.get(representationHandle);
    representation.first = 0x1234_5678;
    representation.second = 0x9abc_def0;
    Representation snapshot = *representation;
    const representationValueCommitted = representations.values_.committedBytes;
    const representationStateCommitted = representations.states_.committedBytes;
    const representationFreeCommitted = representations.freeIndices_.committedBytes;
    assert(representations.tryDeallocate(representationHandle));
    assert(memcmp(representation, &snapshot, Representation.sizeof) == 0);
    assert(representations.values_.committedBytes == representationValueCommitted);
    assert(representations.states_.committedBytes == representationStateCommitted);
    assert(representations.freeIndices_.committedBytes == representationFreeCommitted);

    auto representationReused = representations.allocate();
    assert(representationReused.index == representationHandle.index);
    assert(memcmp(representations.get(representationReused), &snapshot,
            Representation.sizeof) == 0);

    auto otherHandle = representations.allocateInit();
    Representation* other = representations.get(otherHandle);
    other.first = 7;
    other.second = 9;
    Representation otherSnapshot = *other;
    representations.clear();
    assert(representations.empty);
    assert(representations.get(representationReused) is null);
    assert(representations.get(otherHandle) is null);
    assert(memcmp(representation, &snapshot, Representation.sizeof) == 0);
    assert(memcmp(other, &otherSnapshot, Representation.sizeof) == 0);

    auto afterClearFirst = representations.allocate();
    auto afterClearSecond = representations.allocate();
    assert(afterClearFirst.index == 1);
    assert(afterClearSecond.index == 2);
    assert(afterClearFirst.generation == representationReused.generation + 1);
    assert(afterClearSecond.generation == otherHandle.generation + 1);

    IntPool ranges = IntPool.create(6);
    scope (exit)
        ranges.deinit();
    IntHandle rangeOne = ranges.allocateInit();
    IntHandle rangeTwo = ranges.allocateInit();
    IntHandle rangeThree = ranges.allocateInit();
    IntHandle rangeFour = ranges.allocateInit();
    assert(rangeOne.valid);
    *ranges.get(rangeOne) = 10;
    *ranges.get(rangeTwo) = 20;
    *ranges.get(rangeThree) = 30;
    *ranges.get(rangeFour) = 40;
    ranges.deallocate(rangeTwo);
    ranges.deallocate(rangeFour);

    size_t itemCount;
    foreach (ref item; ranges.items())
    {
        item += 100;
        ++itemCount;
    }
    assert(itemCount == 2);
    assert(*ranges.get(rangeOne) == 110);
    assert(*ranges.get(rangeThree) == 130);

    uint[2] indexedIndices;
    size_t indexedCount;
    foreach (item; ranges.indexedItems())
    {
        indexedIndices[indexedCount++] = item.index;
        assert(item.value == 110 || item.value == 130);
    }
    assert(indexedCount == 2);
    assert(indexedIndices == [1, 3]);

    uint[2] occupiedIndices;
    uint[2] occupiedGenerations;
    size_t occupiedCount;
    foreach (slot; ranges.occupiedSlots())
    {
        occupiedIndices[occupiedCount] = slot.index;
        occupiedGenerations[occupiedCount] = slot.generation;
        assert(slot.handle.index == slot.index);
        assert(slot.handle.generation == slot.generation);
        assert(ranges.get(slot.handle) is &slot.value());
        slot.value += 1;
        ++occupiedCount;
    }
    assert(occupiedCount == 2);
    assert(occupiedIndices == [1, 3]);
    assert(occupiedGenerations == [0, 0]);
    assert(*ranges.get(rangeOne) == 111);
    assert(*ranges.get(rangeThree) == 131);

    uint[4] slotIndices;
    uint[4] slotGenerations;
    bool[4] slotOccupancy;
    int[4] slotRepresentations;
    size_t slotCount;
    foreach (slot; ranges.slots())
    {
        slotIndices[slotCount] = slot.index;
        slotGenerations[slotCount] = slot.generation;
        slotOccupancy[slotCount] = slot.occupied;
        slotRepresentations[slotCount] = slot.storage;
        if (slot.occupied)
            assert(slot.handle.index == slot.index);
        else
            assert(slot.handle == IntHandle.init);
        ++slotCount;
    }
    assert(slotCount == 4);
    assert(slotIndices == [1, 2, 3, 4]);
    assert(slotGenerations == [0, 1, 0, 1]);
    assert(slotOccupancy == [true, false, true, false]);
    assert(slotRepresentations == [111, 20, 131, 40]);

    auto manual = ranges.items();
    assert(!manual.empty);
    assert(&manual.front() is ranges.get(rangeOne));
    manual.popFront();
    assert(!manual.empty);
    assert(&manual.front() is ranges.get(rangeThree));
    manual.popFront();
    assert(manual.empty);

    auto independentLeft = ranges.occupiedSlots();
    auto independentRight = ranges.occupiedSlots();
    independentLeft.popFront();
    assert(independentLeft.front.index == 3);
    assert(independentRight.front.index == 1);

    const(IntPool)* constRanges = &ranges;
    size_t constItemCount;
    foreach (ref const item; constRanges.items())
    {
        assert(item == 111 || item == 131);
        ++constItemCount;
    }
    assert(constItemCount == 2);

    size_t constIndexedCount;
    foreach (item; constRanges.indexedItems())
    {
        assert(item.index == 1 || item.index == 3);
        assert(item.value == 111 || item.value == 131);
        ++constIndexedCount;
    }
    assert(constIndexedCount == 2);

    size_t constOccupiedCount;
    foreach (slot; constRanges.occupiedSlots())
    {
        assert(slot.index == 1 || slot.index == 3);
        assert(slot.generation == 0);
        assert(constRanges.get(slot.handle) is &slot.value());
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
        assert(slot.generation == 1);
        assert(slot.handle == IntHandle.init);
        ++clearedSlotCount;
    }
    assert(clearedSlotCount == 4);
    assert(ranges.items().empty);
    assert(ranges.occupiedSlots().empty);

    enum uint sparseRangeCapacity = 130;
    IntPool sparseRanges = IntPool.create(sparseRangeCapacity);
    scope (exit)
        sparseRanges.deinit();
    IntHandle[sparseRangeCapacity] sparseHandles;
    foreach (offset; 0 .. sparseRangeCapacity)
    {
        const handle = sparseRanges.allocateInit();
        *sparseRanges.get(handle) = cast(int) handle.index;
        sparseHandles[offset] = handle;
    }
    foreach (index; 2 .. sparseRangeCapacity)
        sparseRanges.deallocate(sparseHandles[index - 1]);

    uint[2] sparseLiveIndices;
    size_t sparseLiveCount;
    foreach (slot; sparseRanges.occupiedSlots())
        sparseLiveIndices[sparseLiveCount++] = slot.index;
    assert(sparseLiveCount == 2);
    assert(sparseLiveIndices == [1, sparseRangeCapacity]);

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
    GenerationalPool!ExplicitOwner explicitPool =
        GenerationalPool!ExplicitOwner.create(2);
    scope (exit)
        explicitPool.deinit();
    auto explicitHandle = explicitPool.construct(&explicitDeinits);
    assert(explicitPool.tryDispose(explicitHandle));
    assert(explicitDeinits == 1);
    assert(!explicitPool.tryDispose(explicitHandle));

    size_t shallowClearDeinits;
    GenerationalPool!ExplicitOwner shallowClearPool =
        GenerationalPool!ExplicitOwner.create(1);
    auto shallowClearHandle = shallowClearPool.construct(&shallowClearDeinits);
    ExplicitOwner* shallowClearOwner = shallowClearPool.get(shallowClearHandle);
    shallowClearPool.clear();
    assert(shallowClearDeinits == 0);
    assert(shallowClearPool.get(shallowClearHandle) is null);
    finalize(*shallowClearOwner);
    assert(shallowClearDeinits == 1);
    shallowClearPool.deinit();

    size_t shallowDeinitCount;
    GenerationalPool!ExplicitOwner shallowDeinitPool =
        GenerationalPool!ExplicitOwner.create(1);
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
    GenerationalPool!DestructorOnly destructorPool =
        GenerationalPool!DestructorOnly.create(1);
    scope (exit)
        destructorPool.deinit();
    auto destructorHandle = destructorPool.construct(&destructions);
    destructorPool.dispose(destructorHandle);
    assert(destructions == 1);

    struct ContextOwner
    {
    nothrow @nogc:
        void deinit(int*)
        {
        }
    }

    static assert(!canFinalizeWithoutContext!ContextOwner);
    static assert(!__traits(compiles,
            (ref GenerationalPool!ContextOwner contextPool,
            GenerationalPool!ContextOwner.Handle handle) { contextPool.dispose(handle); }));

    align(32_768) struct OverAligned
    {
        ubyte value;
    }

    GenerationalPool!OverAligned overAligned =
        GenerationalPool!OverAligned.create(2);
    scope (exit)
        overAligned.deinit();
    auto alignedHandle = overAligned.allocateInit();
    assert(cast(size_t) overAligned.get(alignedHandle) % OverAligned.alignof == 0);

    IntPool source = IntPool.create(4);
    auto sourceHandle = source.allocateInit();
    *source.get(sourceHandle) = 91;
    IntPool moved = move(source);
    assert(source.capacity == 0);
    assert(source.empty);
    assert(moved.contains(sourceHandle));
    assert(*moved.get(sourceHandle) == 91);
    source.deinit();

    IntPool target = IntPool.create(1);
    target.allocateInit();
    moveAssign(moved, target);
    assert(moved.capacity == 0);
    assert(target.contains(sourceHandle));
    assert(*target.get(sourceHandle) == 91);
    moved.deinit();
    target.deinit();
}
