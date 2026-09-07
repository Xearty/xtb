module xtb.containers.pool;

nothrow @nogc:

import core.attribute;
import core.bitop;
import core_lifetime = core.lifetime;
import core.stdc.string;

import xtb.allocators.internal.virtual_memory;
import xtb.containers.internal.pool_storage;
import xtb.containers.virtual_array;
import xtb.lifetime;
import xtb.numeric;
import xtb.panic;
import xtb.types;

private enum usize occupied_bits_per_word = usize.sizeof * 8;

/// Fixed-capacity stable-address typed recycling pool backed by one virtual
/// memory reservation.
///
/// Index zero is permanently invalid. Live/dead state lives in a compact
/// occupancy bitmap and recycled slots are tracked by integer indices, so Pool
/// never stores allocator metadata in `T` and never overwrites an inactive
/// element representation merely to recycle its storage. The representation
/// fields form one coupled ownership state: the three views borrow from
/// `reservation`, and the counts/indices describe the logical state inside
/// those provisioned views.
@mustuse struct Pool(T)
{
    alias Self = Pool!T;

    VirtualMemoryReservation reservation;
    VirtualArrayView!T values;
    VirtualArrayView!usize occupied_words;
    VirtualArrayView!u32 free_indices;

    u32 capacity;
    usize next_index;
    usize free_count;
    usize live_count;

    version (XTB_Checked) usize mutation_generation = 1;

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Attempts to create an empty Pool with `capacity` usable slots.
    ///
    /// `output` must point to an inert Pool. Capacity zero succeeds without
    /// requiring virtual-memory support. Nonzero capacity reserves all address
    /// space up front but commits no slot/state pages until the first virgin
    /// allocation. On success, `output` owns the reservation and its views. On
    /// failure, `output` remains inert.
    static bool try_create(u32 capacity, scope Self* output) @system
    {
        require(output !is null, "Pool output pointer is null");
        require(
            output is null || output.inert,
            "Pool output is already initialized",
        );

        if (output is null || !output.inert) return false;
        if (capacity == 0) return true;
        if (!virtual_memory_supported) return false;

        const usize page_size = virtual_memory_page_size();
        if (page_size == 0) return false;

        IndexedPoolStorageLayout layout;
        if (!try_pool_layout!T(capacity, page_size, &layout)) return false;

        VirtualMemoryReservation reservation;
        if (!try_reserve_virtual_memory(layout.reservation_bytes, &reservation)) return false;
        scope (exit) reservation.deinit();

        VirtualMemoryRegion values_region;
        VirtualMemoryRegion occupied_region;
        VirtualMemoryRegion free_region;
        if (!try_indexed_pool_storage_regions(
            reservation,
            layout,
            &values_region,
            &occupied_region,
            &free_region,
        ))
        {
            return false;
        }

        VirtualArrayView!T values;
        if (!VirtualArrayView!T.try_create(
            values_region,
            layout.value_capacity,
            default_virtual_commit_granularity,
            &values,
        ))
        {
            return false;
        }
        scope (exit) values.deinit();

        VirtualArrayView!usize occupied_words;
        if (!VirtualArrayView!usize.try_create(
            occupied_region,
            layout.state_capacity,
            default_virtual_commit_granularity,
            &occupied_words,
        ))
        {
            return false;
        }
        scope (exit) occupied_words.deinit();

        VirtualArrayView!u32 free_indices;
        if (!VirtualArrayView!u32.try_create(
            free_region,
            capacity,
            default_virtual_commit_granularity,
            &free_indices,
        ))
        {
            return false;
        }
        scope (exit) free_indices.deinit();

        Self result;
        move_emplace(reservation, result.reservation);
        move_emplace(values, result.values);
        move_emplace(occupied_words, result.occupied_words);
        move_emplace(free_indices, result.free_indices);
        result.capacity = capacity;
        result.next_index = 1;
        move_emplace(result, *output);
        return true;
    }

    /// Creates an empty Pool or panics when its virtual reservation cannot be
    /// established.
    static Self create(u32 capacity) @system
    {
        Self result;
        if (!Self.try_create(capacity, &result)) panic("Pool reservation failed");
        return move(result);
    }

    /// Activates one raw slot and returns its stable storage address.
    ///
    /// The returned non-null pointer borrows storage from this Pool until that
    /// slot is recycled or the Pool is deinitialized. The storage is not
    /// initialized as `T`; callers must establish the value before using
    /// semantic live-item APIs. Failure returns null and leaves Pool logical
    /// state unchanged.
    T* try_allocate() @system
    {
        u32 index;
        if (this.free_count != 0)
        {
            const stack_index = this.free_count - 1;
            index = this.free_indices[stack_index];
            --this.free_count;

            require(
                index != 0 && index <= this.capacity,
                "Pool free-index stack is corrupt",
            );
            require(!this.occupied(index), "Pool free-index stack contains an occupied slot");
        }
        else
        {
            if (this.next_index == 0 || this.next_index > this.capacity) return null;

            index = cast(u32) this.next_index;
            if (!this.try_provision_virgin(index)) return null;

            ++this.next_index;
        }

        this.set_occupied(index, true);
        ++this.live_count;
        version (XTB_Checked)
            ++this.mutation_generation;
        return this.values.ptr + index;
    }

    /// Activates one raw slot or panics when fixed capacity or virtual backing
    /// is exhausted.
    T* allocate() @system
    {
        T* result = this.try_allocate();
        if (result is null) panic("Pool capacity or commitment exceeded");
        return result;
    }

    /// Attempts to activate one slot and establish its `T.init` lifetime.
    T* try_allocate_init() @system
    {
        T* result = this.try_allocate();
        if (result !is null) core_lifetime.emplace(result);
        return result;
    }

    /// Activates one slot and establishes its `T.init` lifetime, or panics when
    /// fixed capacity or virtual backing is exhausted.
    T* allocate_init() @system
    {
        T* result = this.allocate();
        core_lifetime.emplace(result);
        return result;
    }

    /// Attempts to activate and construct one `T` with `emplace`.
    T* try_construct(Args...)(auto ref Args arguments) @system
    {
        T* result = this.try_allocate();
        if (result !is null) core_lifetime.emplace(result, core_lifetime.forward!arguments);
        return result;
    }

    /// Activates and constructs one `T`, or panics when fixed capacity or
    /// virtual backing is exhausted.
    T* construct(Args...)(auto ref Args arguments) @system
    {
        T* result = this.allocate();
        core_lifetime.emplace(result, core_lifetime.forward!arguments);
        return result;
    }

    /// Recycles one occupied slot without finalizing or overwriting `T`.
    ///
    /// Every virgin allocation provisions enough free-index storage for its
    /// future recycle before publishing the slot, so deallocation never needs
    /// to allocate or commit virtual memory. `value` must be non-null and point
    /// to a currently occupied slot owned by this Pool.
    void deallocate(T* value) @system
    {
        require(value !is null, "Pool deallocation pointer is null");

        u32 index;
        version (XTB_Checked)
        {
            index = this.checked_physical_index(value);
            require(index != 0, "Pool deallocation pointer does not belong to Pool");
            require(this.occupied(index), "Pool slot is already inactive");
            require(
                this.free_count < this.free_indices.provisioned_length,
                "Pool free-index provisioning invariant violated",
            );
        }
        else
        {
            const value_address = cast(usize) value;
            const base_address = cast(usize) this.values.ptr;
            index = cast(u32)((value_address - base_address) / T.sizeof);
        }

        this.set_occupied(index, false);
        this.free_indices[this.free_count] = index;
        ++this.free_count;
        --this.live_count;
        version (XTB_Checked)
            ++this.mutation_generation;
    }

    /// Finalizes a live value without external cleanup context, then recycles
    /// its slot. The Pool itself does not overwrite the post-finalization
    /// representation. `value` must be non-null and point to a currently
    /// occupied slot owned by this Pool.
    static if (can_finalize_without_context!T)
    {
        void dispose(T* value) @system
        {
            require(value !is null, "Pool disposal pointer is null");

            version (XTB_Checked)
            {
                const u32 index = this.checked_physical_index(value);
                require(
                    index != 0 && this.occupied(index),
                    "Pool disposal requires an occupied Pool slot",
                );
            }

            static if (needs_finalization!T)
                finalize(*value);
            this.deallocate(value);
        }
    }

    /// Returns the live value at `index`, or null for zero, out-of-capacity, or
    /// inactive indices. A non-null result borrows from this Pool and remains
    /// valid until that slot is recycled or the Pool is deinitialized.
    inout(T)* get(u32 index) inout return @trusted
    {
        if (!this.occupied(index)) return null;
        return this.values.ptr + index;
    }

    /// Returns the stable index of an occupied value owned by this Pool, or
    /// zero when the pointer is null, foreign, misaligned, or inactive.
    u32 index_of(scope const T* value) const @trusted
    {
        const u32 index = this.physical_index(value);
        return index != 0 && this.occupied(index) ? index : 0;
    }

    /// Whether `index` currently denotes an occupied slot.
    bool contains(u32 index) const @trusted
    {
        return this.occupied(index);
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
    /// `occupied_slots()` and performs no second bitmap scan.
    PoolOccupiedSlotsRange!T indexed_items() return @trusted
    {
        return PoolOccupiedSlotsRange!T.create(&this);
    }

    ConstPoolOccupiedSlotsRange!T indexed_items() const return @trusted
    {
        return ConstPoolOccupiedSlotsRange!T.create(&this);
    }

    /// Returns an input range over occupied slots in stable index order.
    /// Each slot exposes its index and live value by reference.
    PoolOccupiedSlotsRange!T occupied_slots() return @trusted
    {
        return PoolOccupiedSlotsRange!T.create(&this);
    }

    ConstPoolOccupiedSlotsRange!T occupied_slots() const return @trusted
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
        const usize word_count = this.occupied_words.provisioned_length;
        if (word_count != 0)
            memset(this.occupied_words.ptr, 0, word_count * usize.sizeof);

        this.free_count = 0;
        this.live_count = 0;
        this.next_index = this.capacity == 0 ? 0 : 1;
        version (XTB_Checked)
            ++this.mutation_generation;
    }

    /// Ends all local views and releases the complete virtual reservation.
    /// Live values are not finalized.
    void deinit() @system
    {
        version (XTB_Checked)
            ++this.mutation_generation;
        this.values.deinit();
        this.occupied_words.deinit();
        this.free_indices.deinit();
        this.reservation.deinit();
        this.capacity = 0;
        this.next_index = 0;
        this.free_count = 0;
        this.live_count = 0;
    }

    bool empty() const pure @safe
    {
        return this.live_count == 0;
    }

    private bool try_provision_virgin(u32 index) @system
    {
        const value_count = cast(usize) index + 1;
        const usize word_index = occupied_word_index(index);

        // Provision all storage needed by this slot's entire future lifecycle
        // before publishing the index. Advancing one view's raw high-water is
        // harmless if a later view fails: Pool logical state remains unchanged
        // and a retry reuses the already committed prefix.
        if (!this.values.try_ensure_accessible(value_count)) return false;
        if (!this.occupied_words.try_ensure_accessible(word_index + 1)) return false;
        if (!this.free_indices.try_ensure_accessible(index)) return false;
        return true;
    }

    private bool occupied(u32 index) const @trusted
    {
        if (index == 0 || index > this.capacity) return false;

        const usize word_index = occupied_word_index(index);
        if (word_index >= this.occupied_words.provisioned_length) return false;

        return (this.occupied_words[word_index] & occupied_bit(index)) != 0;
    }

    private void set_occupied(u32 index, bool value) @trusted
    {
        const usize word_index = occupied_word_index(index);
        const usize bit = occupied_bit(index);
        if (value)
        {
            this.occupied_words[word_index] |= bit;
        }
        else
        {
            this.occupied_words[word_index] &= ~bit;
        }
    }

    private u32 physical_index(scope const T* value) const @trusted
    {
        if (value is null || this.values.ptr is null || this.values.provisioned_length <= 1)
            return 0;

        const base_address = cast(usize) this.values.ptr;
        const value_address = cast(usize) value;
        if (value_address < base_address) return 0;

        const usize byte_offset = value_address - base_address;
        if (byte_offset % T.sizeof != 0) return 0;

        const usize index = byte_offset / T.sizeof;
        if (index == 0 || index >= this.values.provisioned_length || index > this.capacity)
            return 0;

        return cast(u32) index;
    }

    version (XTB_Checked) private u32 checked_physical_index(scope const T* value) const @trusted
    {
        return this.physical_index(value);
    }

    private bool inert() const pure @safe
    {
        return !this.reservation.active
            && this.values.inert
            && this.occupied_words.inert
            && this.free_indices.inert
            && this.capacity == 0
            && this.next_index == 0
            && this.free_count == 0
            && this.live_count == 0;
    }
}

/// Mutable occupied-slot view returned by `Pool.occupied_slots`.
///
/// The view borrows Pool storage. Structural Pool mutation invalidates it.
struct PoolOccupiedSlot(T)
{
    T* value_ptr;
    u32 index;
    version (XTB_Checked)
    {
        const(Pool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
    }

    ref T value() return @system
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);

        return *this.value_ptr;
    }
}

/// Read-only occupied-slot view returned by a const Pool.
struct ConstPoolOccupiedSlot(T)
{
    const(T)* value_ptr;
    u32 index;
    version (XTB_Checked)
    {
        const(Pool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);

        return *this.value_ptr;
    }
}

/// Mutable view of one deliberately provisioned Pool slot.
///
/// `storage` exposes preserved representation even while inactive and is
/// therefore deliberately `@system`. `value` additionally requires occupancy.
struct PoolSlot(T)
{
    T* storage_ptr;
    u32 index;
    bool occupied_state;
    version (XTB_Checked)
    {
        const(Pool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
    }

    bool occupied() const @trusted
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);

        return this.occupied_state;
    }

    ref T value() return @system
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);
        require(this.occupied_state, "inactive Pool slot has no live value");

        return *this.storage_ptr;
    }

    ref T storage() return @system
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);

        return *this.storage_ptr;
    }
}

/// Read-only view of one deliberately provisioned slot from a const Pool.
struct ConstPoolSlot(T)
{
    const(T)* storage_ptr;
    u32 index;
    bool occupied_state;
    version (XTB_Checked)
    {
        const(Pool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
    }

    bool occupied() const @trusted
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);

        return this.occupied_state;
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);
        require(this.occupied_state, "inactive Pool slot has no live value");

        return *this.storage_ptr;
    }

    ref const(T) storage() const return @system
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);

        return *this.storage_ptr;
    }
}

/// Input range yielding occupied Pool values directly by reference.
struct PoolItemsRange(T)
{
    PoolOccupiedCursor!T cursor;
    T* values;

    private static PoolItemsRange create(Pool!T* pool) @trusted
    {
        PoolItemsRange result;
        result.cursor = PoolOccupiedCursor!T.create(pool);
        result.values = pool.values.ptr;
        return result;
    }

    bool empty() const @trusted
    {
        return this.cursor.empty;
    }

    ref T front() return @system
    {
        return this.values[this.cursor.index];
    }

    void popFront() @trusted
    {
        this.cursor.popFront();
    }
}

/// Read-only input range yielding occupied Pool values by const reference.
struct ConstPoolItemsRange(T)
{
    PoolOccupiedCursor!T cursor;
    const(T)* values;

    private static ConstPoolItemsRange create(const(Pool!T)* pool) @trusted
    {
        ConstPoolItemsRange result;
        result.cursor = PoolOccupiedCursor!T.create(pool);
        result.values = pool.values.ptr;
        return result;
    }

    bool empty() const @trusted
    {
        return this.cursor.empty;
    }

    ref const(T) front() const return @system
    {
        return this.values[this.cursor.index];
    }

    void popFront() @trusted
    {
        this.cursor.popFront();
    }
}

/// Input range yielding occupied slots with stable indices and live values.
struct PoolOccupiedSlotsRange(T)
{
    PoolOccupiedCursor!T cursor;
    T* values;
    version (XTB_Checked)
    {
        const(Pool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
    }

    private static PoolOccupiedSlotsRange create(Pool!T* pool) @trusted
    {
        PoolOccupiedSlotsRange result;
        result.cursor = PoolOccupiedCursor!T.create(pool);
        result.values = pool.values.ptr;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        return this.cursor.empty;
    }

    PoolOccupiedSlot!T front() return @system
    {
        const u32 index = this.cursor.index;
        PoolOccupiedSlot!T result;
        result.value_ptr = this.values + index;
        result.index = index;
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        this.cursor.popFront();
    }
}

/// Read-only occupied-slot range for a const Pool.
struct ConstPoolOccupiedSlotsRange(T)
{
    PoolOccupiedCursor!T cursor;
    const(T)* values;
    version (XTB_Checked)
    {
        const(Pool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
    }

    private static ConstPoolOccupiedSlotsRange create(const(Pool!T)* pool) @trusted
    {
        ConstPoolOccupiedSlotsRange result;
        result.cursor = PoolOccupiedCursor!T.create(pool);
        result.values = pool.values.ptr;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        return this.cursor.empty;
    }

    ConstPoolOccupiedSlot!T front() const return @system
    {
        const u32 index = this.cursor.index;
        ConstPoolOccupiedSlot!T result;
        result.value_ptr = this.values + index;
        result.index = index;
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        this.cursor.popFront();
    }
}

/// Sequential input range over all deliberately provisioned Pool slots.
struct PoolSlotsRange(T)
{
    T* values;
    const(usize)* occupied_words;
    usize current_index;
    usize end_index;
    version (XTB_Checked)
    {
        const(Pool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
    }

    private static PoolSlotsRange create(Pool!T* pool) @trusted
    {
        PoolSlotsRange result;
        result.values = pool.values.ptr;
        result.occupied_words = pool.occupied_words.ptr;
        result.current_index = 1;
        result.end_index = pool.values.provisioned_length;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);

        return this.current_index >= this.end_index;
    }

    PoolSlot!T front() return @system
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);
        require(this.current_index < this.end_index, "front of empty Pool slots range");

        const u32 index = cast(u32) this.current_index;
        PoolSlot!T result;
        result.storage_ptr = this.values + index;
        result.index = index;
        result.occupied_state = pool_occupied_bit(this.occupied_words, index);
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);
        require(this.current_index < this.end_index, "popFront of empty Pool slots range");

        ++this.current_index;
    }
}

/// Read-only sequential range over all deliberately provisioned slots.
struct ConstPoolSlotsRange(T)
{
    const(T)* values;
    const(usize)* occupied_words;
    usize current_index;
    usize end_index;
    version (XTB_Checked)
    {
        const(Pool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
    }

    private static ConstPoolSlotsRange create(const(Pool!T)* pool) @trusted
    {
        ConstPoolSlotsRange result;
        result.values = pool.values.ptr;
        result.occupied_words = pool.occupied_words.ptr;
        result.current_index = 1;
        result.end_index = pool.values.provisioned_length;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);

        return this.current_index >= this.end_index;
    }

    ConstPoolSlot!T front() const return @system
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);
        require(this.current_index < this.end_index, "front of empty Pool slots range");

        const u32 index = cast(u32) this.current_index;
        ConstPoolSlot!T result;
        result.storage_ptr = this.values + index;
        result.index = index;
        result.occupied_state = pool_occupied_bit(this.occupied_words, index);
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);
        require(this.current_index < this.end_index, "popFront of empty Pool slots range");

        ++this.current_index;
    }
}

private struct PoolOccupiedCursor(T)
{
    const(usize)* occupied_words;
    usize word_count;
    usize word_index;
    usize live_bits;
    version (XTB_Checked)
    {
        const(Pool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
    }

    private static PoolOccupiedCursor create(const(Pool!T)* pool) @trusted
    {
        PoolOccupiedCursor result;
        result.occupied_words = pool.occupied_words.ptr;
        result.word_count = pool.occupied_words.provisioned_length;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
        }
        result.seek_occupied_word();
        return result;
    }

    pragma(inline, true)
    bool empty() const @trusted
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);

        return this.live_bits == 0;
    }

    pragma(inline, true)
    u32 index() const @trusted
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);
        require(this.live_bits != 0, "front of empty Pool occupied range");

        return cast(u32)(this.word_index * occupied_bits_per_word + bsf(this.live_bits));
    }

    pragma(inline, true)
    void popFront() @trusted
    {
        version (XTB_Checked)
            require_pool_view_valid(this.owner, this.mutation_generation, this.values_base);
        require(this.live_bits != 0, "popFront of empty Pool occupied range");

        this.live_bits &= this.live_bits - 1;
        if (this.live_bits != 0) return;

        ++this.word_index;
        this.seek_occupied_word();
    }

    private void seek_occupied_word() @trusted
    {
        while (this.word_index < this.word_count)
        {
            this.live_bits = this.occupied_words[this.word_index];
            if (this.live_bits != 0) return;

            ++this.word_index;
        }
        this.live_bits = 0;
    }
}

private bool pool_occupied_bit(scope const usize* occupied_words, u32 index) @trusted
{
    return (occupied_words[occupied_word_index(index)] & occupied_bit(index)) != 0;
}

version (XTB_Checked) private void require_pool_view_valid(T)(
    scope const Pool!T* owner,
    usize mutation_generation,
    scope const T* values_base,
) @trusted
{
    require(owner !is null, "Pool range has no owner");
    require(
        owner.mutation_generation == mutation_generation,
        "Pool range was invalidated by structural mutation",
    );
    require(
        owner.values.ptr is values_base,
        "Pool range was invalidated by move or deinit",
    );
}

static assert(needs_deinit!(Pool!u8));

private bool try_pool_layout(T)(
    u32 capacity,
    usize page_size,
    scope IndexedPoolStorageLayout* output,
) pure @safe
{
    if (output is null || capacity == 0 || page_size == 0) return false;

    const usize capacity_as_size = cast(usize) capacity;
    if (add_overflows(capacity_as_size, 1)) return false;
    const usize value_capacity = capacity_as_size + 1;

    usize occupied_word_count = value_capacity / occupied_bits_per_word;
    if (value_capacity % occupied_bits_per_word != 0) ++occupied_word_count;

    return try_indexed_pool_storage_layout!(T, usize)(
        capacity,
        occupied_word_count,
        page_size,
        output,
    );
}

private usize occupied_word_index(u32 index) pure @safe
{
    return cast(usize) index / occupied_bits_per_word;
}

private usize occupied_bit(u32 index) pure @safe
{
    return (cast(usize) 1) << (cast(usize) index % occupied_bits_per_word);
}

// Everything below here is test-only.
unittest
{
    static assert(__traits(compiles, (ref const Pool!i32 pool)
    {
        const auto capacity = pool.capacity;
        const auto count = pool.live_count;
        const auto is_empty = pool.empty;
        auto items = pool.items();
        auto indexed_items = pool.indexed_items();
        auto occupied_slots = pool.occupied_slots();
        auto slots = pool.slots();
        cast(void) capacity;
        cast(void) count;
        cast(void) is_empty;
        cast(void) items;
        cast(void) indexed_items;
        cast(void) occupied_slots;
        cast(void) slots;
    }));

    version (XTB_Checked)
    {
        static assert(__traits(hasMember, Pool!i32, "mutation_generation"));
    }
    else
    {
        static assert(!__traits(hasMember, Pool!i32, "mutation_generation"));
    }

    Pool!i32 zero;
    assert(zero.capacity == 0);
    assert(zero.live_count == 0);
    assert(zero.empty);
    assert(zero.try_allocate() is null);
    zero.clear();
    zero.deinit();

    Pool!i32 zero_created = Pool!i32.create(0);
    assert(zero_created.capacity == 0);
    zero_created.deinit();

    if (!virtual_memory_supported)
        return;

    Pool!i32 pool = Pool!i32.create(4);
    scope (exit) pool.deinit();

    assert(pool.capacity == 4);
    assert(pool.live_count == 0);
    assert(pool.get(0) is null);
    assert(!pool.contains(0));

    i32* first = pool.allocate_init();
    i32* second = pool.allocate_init();
    *first = 11;
    *second = 22;
    assert(pool.index_of(first) == 1);
    assert(pool.index_of(second) == 2);
    assert(pool.get(1) is first);
    assert(pool.get(2) is second);
    assert(pool.live_count == 2);

    const value_committed = pool.values.committed_bytes;
    const occupied_committed = pool.occupied_words.committed_bytes;
    const free_committed = pool.free_indices.committed_bytes;
    pool.deallocate(first);
    assert(pool.values.committed_bytes == value_committed);
    assert(pool.occupied_words.committed_bytes == occupied_committed);
    assert(pool.free_indices.committed_bytes == free_committed);
    assert(pool.index_of(first) == 0);
    assert(pool.get(1) is null);
    assert(pool.live_count == 1);

    i32* recycled = pool.try_allocate();
    assert(recycled is first);
    assert(pool.values.committed_bytes == value_committed);
    assert(pool.occupied_words.committed_bytes == occupied_committed);
    assert(pool.free_indices.committed_bytes == free_committed);
    assert(*recycled == 11);
    pool.deallocate(recycled);

    i32* third = pool.allocate_init();
    i32* fourth = pool.allocate_init();
    assert(pool.index_of(third) == 1);
    assert(pool.index_of(fourth) == 3);
    i32* last = pool.allocate_init();
    assert(pool.index_of(last) == 4);
    assert(pool.try_allocate() is null);
    assert(pool.try_allocate_init() is null);

    const u32 bitmap_capacity = cast(u32)(occupied_bits_per_word + 2);
    Pool!u8 bitmap_pool = Pool!u8.create(bitmap_capacity);
    scope (exit) bitmap_pool.deinit();
    for (u32 index = 1; index <= bitmap_capacity; ++index)
    {
        u8* value = bitmap_pool.allocate_init();
        assert(bitmap_pool.index_of(value) == index);
    }
    assert(bitmap_pool.contains(cast(u32) occupied_bits_per_word));
    assert(bitmap_pool.contains(cast(u32)(occupied_bits_per_word + 1)));

    usize dense_range_count;
    foreach (ref value; bitmap_pool.items())
    {
        cast(void) value;
        ++dense_range_count;
    }
    assert(dense_range_count == bitmap_capacity);

    enum u32 sparse_capacity = cast(u32)(occupied_bits_per_word * 2 + 2);
    Pool!u32 sparse_ranges = Pool!u32.create(sparse_capacity);
    scope (exit) sparse_ranges.deinit();
    u32*[sparse_capacity] sparse_values;
    for (u32 offset = 0; offset < sparse_capacity; ++offset)
    {
        u32* value = sparse_ranges.allocate_init();
        *value = offset + 1;
        sparse_values[offset] = value;
    }
    for (u32 index = 2; index <= sparse_capacity; ++index)
    {
        if (index != occupied_bits_per_word * 2 + 1)
            sparse_ranges.deallocate(sparse_values[index - 1]);
    }
    u32[2] sparse_indices;
    usize sparse_count;
    foreach (slot; sparse_ranges.occupied_slots())
        sparse_indices[sparse_count++] = slot.index;
    assert(sparse_count == 2);
    assert(sparse_indices[0] == 1);
    assert(sparse_indices[1] == occupied_bits_per_word * 2 + 1);

    enum u32 free_commit_boundary = 16_385;
    Pool!u8 commit_boundary = Pool!u8.create(free_commit_boundary);
    scope (exit) commit_boundary.deinit();
    foreach (_; 1 .. free_commit_boundary)
        commit_boundary.allocate();
    const free_bytes_before_boundary = commit_boundary.free_indices.committed_bytes;
    u8* boundary_value = commit_boundary.allocate();
    assert(commit_boundary.index_of(boundary_value) == free_commit_boundary);
    assert(commit_boundary.free_indices.committed_bytes > free_bytes_before_boundary);
    const free_bytes_after_boundary = commit_boundary.free_indices.committed_bytes;
    commit_boundary.deallocate(boundary_value);
    assert(commit_boundary.free_indices.committed_bytes == free_bytes_after_boundary);

    Pool!i32 reuse_order = Pool!i32.create(4);
    scope (exit) reuse_order.deinit();
    i32* reuse_one = reuse_order.allocate_init();
    i32* reuse_two = reuse_order.allocate_init();
    i32* reuse_three = reuse_order.allocate_init();
    reuse_order.deallocate(reuse_one);
    reuse_order.deallocate(reuse_three);
    assert(reuse_order.allocate() is reuse_three);
    assert(reuse_order.allocate() is reuse_one);
    assert(reuse_order.index_of(reuse_two) == 2);

    struct Representation
    {
        u32 first;
        u32 second;
    }

    Pool!Representation representations = Pool!Representation.create(3);
    scope (exit) representations.deinit();
    Representation* representation = representations.allocate_init();
    representation.first = 0x1234_5678;
    representation.second = 0x9ABC_DEF0;
    Representation snapshot = *representation;
    representations.deallocate(representation);
    assert(memcmp(representation, &snapshot, Representation.sizeof) == 0);
    Representation* same_representation = representations.allocate();
    assert(same_representation is representation);
    assert(memcmp(same_representation, &snapshot, Representation.sizeof) == 0);

    Representation* other_representation = representations.allocate_init();
    other_representation.first = 7;
    other_representation.second = 9;
    Representation other_snapshot = *other_representation;
    representations.clear();
    assert(representations.live_count == 0);
    assert(representations.empty);
    assert(representations.index_of(same_representation) == 0);
    assert(representations.index_of(other_representation) == 0);
    assert(memcmp(same_representation, &snapshot, Representation.sizeof) == 0);
    assert(memcmp(other_representation, &other_snapshot, Representation.sizeof) == 0);

    Pool!i32 ranges = Pool!i32.create(8);
    scope (exit) ranges.deinit();
    i32* range_one = ranges.allocate_init();
    i32* range_two = ranges.allocate_init();
    i32* range_three = ranges.allocate_init();
    i32* range_four = ranges.allocate_init();
    *range_one = 10;
    *range_two = 20;
    *range_three = 30;
    *range_four = 40;
    ranges.deallocate(range_two);
    ranges.deallocate(range_four);

    usize item_count;
    foreach (ref item; ranges.items())
    {
        item += 100;
        ++item_count;
    }
    assert(item_count == 2);
    assert(*range_one == 110);
    assert(*range_three == 130);
    assert(*range_two == 20);
    assert(*range_four == 40);

    u32[2] indexed_indices;
    usize indexed_count;
    foreach (item; ranges.indexed_items())
    {
        indexed_indices[indexed_count++] = item.index;
        item.value += 1;
    }
    assert(indexed_count == 2);
    assert(indexed_indices == [1, 3]);
    assert(*range_one == 111);
    assert(*range_three == 131);

    u32[2] occupied_indices;
    usize occupied_count;
    foreach (slot; ranges.occupied_slots())
    {
        occupied_indices[occupied_count++] = slot.index;
        slot.value += 1;
    }
    assert(occupied_count == 2);
    assert(occupied_indices == [1, 3]);
    assert(*range_one == 112);
    assert(*range_three == 132);

    u32[4] slot_indices;
    bool[4] slot_occupancy;
    i32[4] slot_representations;
    usize slot_count;
    foreach (slot; ranges.slots())
    {
        slot_indices[slot_count] = slot.index;
        slot_occupancy[slot_count] = slot.occupied;
        slot_representations[slot_count] = slot.storage;
        ++slot_count;
    }
    assert(slot_count == 4);
    assert(slot_indices == [1, 2, 3, 4]);
    assert(slot_occupancy == [true, false, true, false]);
    assert(slot_representations == [112, 20, 132, 40]);

    auto manual = ranges.items();
    assert(!manual.empty);
    assert(&manual.front() is range_one);
    manual.popFront();
    assert(!manual.empty);
    assert(&manual.front() is range_three);
    manual.popFront();
    assert(manual.empty);

    auto independent_left = ranges.items();
    auto independent_right = ranges.items();
    independent_left.popFront();
    assert(&independent_left.front() is range_three);
    assert(&independent_right.front() is range_one);

    const(Pool!i32)* const_ranges = &ranges;
    usize const_item_count;
    foreach (ref const item; const_ranges.items())
    {
        assert(item == 112 || item == 132);
        ++const_item_count;
    }
    assert(const_item_count == 2);

    usize const_indexed_count;
    foreach (item; const_ranges.indexed_items())
    {
        assert(item.index == 1 || item.index == 3);
        assert(item.value == 112 || item.value == 132);
        ++const_indexed_count;
    }
    assert(const_indexed_count == 2);

    usize const_occupied_count;
    foreach (slot; const_ranges.occupied_slots())
    {
        assert(slot.index == 1 || slot.index == 3);
        assert(slot.value == 112 || slot.value == 132);
        ++const_occupied_count;
    }
    assert(const_occupied_count == 2);

    usize const_slot_count;
    foreach (slot; const_ranges.slots())
    {
        assert(slot.index >= 1 && slot.index <= 4);
        cast(void) slot.storage;
        ++const_slot_count;
    }
    assert(const_slot_count == 4);

    ranges.clear();
    usize cleared_slot_count;
    foreach (slot; ranges.slots())
    {
        assert(!slot.occupied);
        ++cleared_slot_count;
    }
    assert(cleared_slot_count == 4);
    assert(ranges.items().empty);
    assert(ranges.occupied_slots().empty);

    struct Tiny
    {
        u8 value;
    }

    Pool!Tiny tiny = Pool!Tiny.create(2);
    scope (exit) tiny.deinit();
    Tiny* tiny_value = tiny.allocate_init();
    assert(tiny.index_of(tiny_value) == 1);

    align(8_192) struct OverAligned
    {
        u8 value;
    }

    Pool!OverAligned over_aligned = Pool!OverAligned.create(2);
    scope (exit) over_aligned.deinit();
    OverAligned* aligned_value = over_aligned.allocate_init();
    assert(cast(usize) aligned_value % OverAligned.alignof == 0);
    assert(over_aligned.index_of(aligned_value) == 1);

    struct ExplicitOwner
    {
        nothrow @nogc:
        usize* deinit_count;
        bool active;

        @disable this(this);

        this(usize* deinit_count)
        {
            this.deinit_count = deinit_count;
            this.active = true;
        }

        void deinit()
        {
            if (this.active)
            {
                ++*this.deinit_count;
                this.active = false;
            }
        }
    }

    usize explicit_deinits;
    Pool!ExplicitOwner explicit_pool = Pool!ExplicitOwner.create(2);
    scope (exit) explicit_pool.deinit();
    ExplicitOwner* explicit_owner = explicit_pool.construct(&explicit_deinits);
    explicit_pool.dispose(explicit_owner);
    assert(explicit_deinits == 1);
    assert(!explicit_owner.active);
    assert(explicit_pool.live_count == 0);

    usize shallow_clear_deinits;
    Pool!ExplicitOwner shallow_clear_pool = Pool!ExplicitOwner.create(1);
    ExplicitOwner* shallow_clear_owner = shallow_clear_pool.construct(&shallow_clear_deinits);
    shallow_clear_pool.clear();
    assert(shallow_clear_deinits == 0);
    finalize(*shallow_clear_owner);
    assert(shallow_clear_deinits == 1);
    shallow_clear_pool.deinit();

    usize shallow_deinit_count;
    Pool!ExplicitOwner shallow_deinit_pool = Pool!ExplicitOwner.create(1);
    shallow_deinit_pool.construct(&shallow_deinit_count);
    shallow_deinit_pool.deinit();
    assert(shallow_deinit_count == 0);

    struct DestructorOnly
    {
        nothrow @nogc:
        usize* destructions;

        @disable this(this);

        this(usize* destructions)
        {
            this.destructions = destructions;
        }

        ~this()
        {
            ++*this.destructions;
        }
    }

    usize destructions;
    Pool!DestructorOnly destructor_pool = Pool!DestructorOnly.create(1);
    scope (exit) destructor_pool.deinit();
    DestructorOnly* destructor_value = destructor_pool.construct(&destructions);
    destructor_pool.dispose(destructor_value);
    assert(destructions == 1);

    struct ContextOwner
    {
        nothrow @nogc:
        void deinit(i32*)
        {
        }
    }

    static assert(!can_finalize_without_context!ContextOwner);
    static assert(!__traits(compiles, (ref Pool!ContextOwner context_pool, ContextOwner* value)
    {
        context_pool.dispose(value);
    }));

    Pool!i32 source = Pool!i32.create(8);
    i32* source_value = source.allocate_init();
    *source_value = 77;
    Pool!i32 moved = move(source);
    assert(source.capacity == 0);
    assert(source.empty);
    assert(moved.capacity == 8);
    assert(moved.get(1) !is null && *moved.get(1) == 77);
    source.deinit();

    Pool!i32 target = Pool!i32.create(2);
    target.allocate_init();
    move_assign(moved, target);
    assert(moved.capacity == 0);
    assert(target.capacity == 8);
    assert(target.get(1) !is null && *target.get(1) == 77);
    moved.deinit();
    target.deinit();
}
