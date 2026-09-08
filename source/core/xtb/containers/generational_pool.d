module xtb.containers.generational_pool;

nothrow @nogc:

import core.attribute;
import core_lifetime = core.lifetime;

import xtb.allocators.internal.virtual_memory;
import xtb.containers.internal.pool_storage;
import xtb.containers.virtual_array;
import xtb.lifetime;
import xtb.numeric;
import xtb.panic;
import xtb.types;

private enum u32 active_bit = u32(1) << 31;
private enum u32 generation_mask = active_bit - 1;

/// Fixed-capacity stable-address typed recycling pool with generational handles.
///
/// Index zero is permanently invalid. Each usable slot stores its active bit and
/// generation in a separate packed state word, leaving `T` untouched while the
/// slot is inactive. Stale-handle rejection is semantic and remains enabled in
/// every build mode.
@mustuse struct GenerationalPool(T)
{
    alias Self = GenerationalPool!T;

    /// Identifies one live incarnation of one stable slot in a
    /// `GenerationalPool!T`.
    ///
    /// `Handle.init` is invalid because index zero is permanently reserved.
    struct Handle
    {
        u32 index;
        u32 generation;

        /// Whether this is a non-null handle representation.
        ///
        /// A non-null handle may still be stale, out of range, or belong to a
        /// different pool instance. Use `GenerationalPool.contains` when
        /// current pool membership matters.
        bool valid() const pure @safe
        {
            return this.index != 0;
        }
    }

    VirtualMemoryReservation reservation;
    VirtualArrayView!T values;
    VirtualArrayView!u32 states;
    VirtualArrayView!u32 free_indices;

    u32 capacity;
    usize next_index;
    usize free_count;
    usize live_count;

    version (XTB_Checked) usize mutation_generation = 1;

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Attempts to create an empty generational pool with `capacity` usable
    /// slots.
    ///
    /// `output` must point to an inert GenerationalPool. Capacity zero succeeds
    /// without requiring virtual-memory support. Nonzero capacity reserves all
    /// address space up front but commits no value/state/free-index pages until
    /// the first virgin allocation. On success, `output` owns the reservation
    /// and its views. On failure, `output` remains inert.
    static bool try_create(u32 capacity, scope Self* output) @system
    {
        require(output !is null, "GenerationalPool output pointer is null");
        require(
            output is null || output.inert,
            "GenerationalPool output is already initialized",
        );

        if (output is null || !output.inert) return false;
        if (capacity == 0) return true;
        if (!virtual_memory_supported) return false;

        const usize page_size = virtual_memory_page_size();
        if (page_size == 0) return false;

        const usize capacity_as_size = cast(usize) capacity;
        if (add_overflows(capacity_as_size, 1)) return false;
        const usize state_capacity = capacity_as_size + 1;

        IndexedPoolStorageLayout layout;
        if (!try_indexed_pool_storage_layout!(T, u32)(
            capacity,
            state_capacity,
            page_size,
            &layout,
        ))
        {
            return false;
        }

        VirtualMemoryReservation reservation;
        if (!try_reserve_virtual_memory(layout.reservation_bytes, &reservation)) return false;
        scope (exit) reservation.deinit();

        VirtualMemoryRegion values_region;
        VirtualMemoryRegion states_region;
        VirtualMemoryRegion free_region;
        if (!try_indexed_pool_storage_regions(
            reservation,
            layout,
            &values_region,
            &states_region,
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

        VirtualArrayView!u32 states;
        if (!VirtualArrayView!u32.try_create(
            states_region,
            layout.state_capacity,
            default_virtual_commit_granularity,
            &states,
        ))
        {
            return false;
        }
        scope (exit) states.deinit();

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
        move_emplace(states, result.states);
        move_emplace(free_indices, result.free_indices);
        result.capacity = capacity;
        result.next_index = 1;
        move_emplace(result, *output);
        return true;
    }

    /// Creates an empty GenerationalPool or panics when its virtual reservation
    /// cannot be established.
    static Self create(u32 capacity) @system
    {
        Self result;
        if (!Self.try_create(capacity, &result)) panic("GenerationalPool reservation failed");
        return move(result);
    }

    /// Activates one raw slot and writes its handle to `output`.
    ///
    /// `output` must be non-null. The slot's storage is not initialized as `T`;
    /// callers must establish the value before using it semantically. Failure
    /// leaves GenerationalPool logical state and `output` unchanged.
    bool try_allocate(scope Handle* output) @system
    {
        require(output !is null, "GenerationalPool handle output is null");
        if (output is null) return false;

        u32 index;
        if (this.free_count != 0)
        {
            const usize stack_index = this.free_count - 1;
            index = this.free_indices[stack_index];
            --this.free_count;

            require(
                index != 0 && index <= this.capacity,
                "GenerationalPool free-index stack is corrupt",
            );
            require(
                index < this.states.provisioned_length,
                "GenerationalPool free-index stack exceeds provisioned state",
            );
            require(
                !state_active(this.states[index]),
                "GenerationalPool free-index stack contains an active slot",
            );
        }
        else
        {
            if (this.next_index == 0 || this.next_index > this.capacity) return false;

            index = cast(u32) this.next_index;
            if (!this.try_provision_virgin(index)) return false;
            ++this.next_index;
        }

        const u32 active_state = activate_state(this.states[index]);
        this.states[index] = active_state;
        ++this.live_count;
        version (XTB_Checked)
            ++this.mutation_generation;

        *output = Handle(index, state_generation(active_state));
        return true;
    }

    /// Activates one raw slot or panics when fixed capacity or virtual backing
    /// is exhausted.
    Handle allocate() @system
    {
        Handle result = Handle.init;
        if (!this.try_allocate(&result)) panic("GenerationalPool capacity or commitment exceeded");
        return result;
    }

    /// Attempts to activate one slot and establish its `T.init` lifetime.
    /// `output` must be non-null and remains unchanged on failure.
    bool try_allocate_init(scope Handle* output) @system
    {
        require(output !is null, "GenerationalPool handle output is null");
        if (output is null) return false;

        Handle result = Handle.init;
        if (!this.try_allocate(&result)) return false;
        core_lifetime.emplace(this.values.ptr + result.index);
        *output = result;
        return true;
    }

    /// Activates one slot and establishes its `T.init` lifetime, or panics when
    /// fixed capacity or virtual backing is exhausted.
    Handle allocate_init() @system
    {
        Handle result = this.allocate();
        core_lifetime.emplace(this.values.ptr + result.index);
        return result;
    }

    /// Attempts to activate and construct one `T` with `emplace`.
    /// `output` must be non-null and remains unchanged on failure.
    bool try_construct(Args...)(scope Handle* output, auto ref Args arguments) @system
    {
        require(output !is null, "GenerationalPool handle output is null");
        if (output is null) return false;

        Handle result = Handle.init;
        if (!this.try_allocate(&result)) return false;
        core_lifetime.emplace(
            this.values.ptr + result.index,
            core_lifetime.forward!arguments,
        );
        *output = result;
        return true;
    }

    /// Activates and constructs one `T`, or panics when fixed capacity or
    /// virtual backing is exhausted.
    Handle construct(Args...)(auto ref Args arguments) @system
    {
        Handle result = this.allocate();
        core_lifetime.emplace(
            this.values.ptr + result.index,
            core_lifetime.forward!arguments,
        );
        return result;
    }

    /// Returns the live value identified by `handle`, or null when the handle is
    /// null, out of range, inactive, or stale. A non-null result borrows this
    /// GenerationalPool storage until the slot is recycled or the pool is
    /// deinitialized.
    inout(T)* get(Handle handle) inout return @trusted
    {
        return this.valid_handle(handle) ? this.values.ptr + handle.index : null;
    }

    /// Whether `handle` currently identifies a live value in this GenerationalPool.
    bool contains(Handle handle) const @trusted
    {
        return this.valid_handle(handle);
    }

    /// Returns an input range over live values in stable index order.
    ///
    /// Structural GenerationalPool mutation invalidates the range. Checked builds diagnose
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
    /// `occupied_slots()` when that additional identity metadata is needed.
    GenerationalPoolIndexedItemsRange!T indexed_items() return @trusted
    {
        return GenerationalPoolIndexedItemsRange!T.create(&this);
    }

    ConstGenerationalPoolIndexedItemsRange!T indexed_items() const return @trusted
    {
        return ConstGenerationalPoolIndexedItemsRange!T.create(&this);
    }

    /// Returns an input range over live slots in stable index order. Each slot
    /// exposes its index, generation, handle, and live value by reference.
    GenerationalPoolOccupiedSlotsRange!T occupied_slots() return @trusted
    {
        return GenerationalPoolOccupiedSlotsRange!T.create(&this);
    }

    ConstGenerationalPoolOccupiedSlotsRange!T occupied_slots() const return @trusted
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
    bool try_deallocate(Handle handle) @system
    {
        if (!this.valid_handle(handle)) return false;

        const u32 index = handle.index;
        this.states[index] = deactivate_and_advance(this.states[index]);
        this.free_indices[this.free_count] = index;
        ++this.free_count;
        --this.live_count;
        version (XTB_Checked)
            ++this.mutation_generation;
        return true;
    }

    /// Recycles one live handle or panics when it is invalid or stale.
    void deallocate(Handle handle) @system
    {
        if (!this.try_deallocate(handle)) panic("GenerationalPool handle is invalid or stale");
    }

    /// Finalizes a live value without external cleanup context, then recycles
    /// its slot.
    static if (can_finalize_without_context!T)
    {
        bool try_dispose(Handle handle) @system
        {
            T* value = this.get(handle);
            if (value is null) return false;

            static if (needs_finalization!T)
                finalize(*value);
            return this.try_deallocate(handle);
        }

        void dispose(Handle handle) @system
        {
            if (!this.try_dispose(handle)) panic("GenerationalPool handle is invalid or stale");
        }
    }

    /// Invalidates every live handle without finalizing or overwriting values.
    /// Previously provisioned pages and per-slot generations remain reusable.
    void clear() @trusted
    {
        const usize provisioned = this.states.provisioned_length;
        foreach (index; 1 .. provisioned)
        {
            const u32 state = this.states[index];
            if (state_active(state)) this.states[index] = deactivate_and_advance(state);
        }

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
        this.states.deinit();
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
        const usize element_count = cast(usize) index + 1;

        // Provision every region needed by this slot's entire future lifecycle
        // before publishing the index. Later deallocation therefore cannot
        // allocate or commit virtual memory.
        if (!this.values.try_ensure_accessible(element_count)) return false;
        if (!this.states.try_ensure_accessible(element_count)) return false;
        if (!this.free_indices.try_ensure_accessible(index)) return false;
        return true;
    }

    private bool valid_handle(Handle handle) const @trusted
    {
        if (handle.index == 0 || handle.index > this.capacity) return false;

        const usize index = cast(usize) handle.index;
        if (index >= this.states.provisioned_length) return false;

        const u32 state = this.states[index];
        return state_active(state) && state_generation(state) == handle.generation;
    }

    private bool inert() const pure @safe
    {
        return !this.reservation.active
            && this.values.inert
            && this.states.inert
            && this.free_indices.inert
            && this.capacity == 0
            && this.next_index == 0
            && this.free_count == 0
            && this.live_count == 0;
    }
}

/// Mutable live-slot view returned by `GenerationalPool.occupied_slots`.
///
/// The view borrows GenerationalPool storage. Structural mutation invalidates it.
struct GenerationalPoolOccupiedSlot(T)
{
    alias Handle = GenerationalPool!T.Handle;

    T* value_ptr;
    u32 index;
    u32 generation;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    Handle handle() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return Handle(this.index, this.generation);
    }

    ref T value() return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return *this.value_ptr;
    }
}

/// Read-only live-slot view returned by a const GenerationalPool.
struct ConstGenerationalPoolOccupiedSlot(T)
{
    alias Handle = GenerationalPool!T.Handle;

    const(T)* value_ptr;
    u32 index;
    u32 generation;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    Handle handle() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return Handle(this.index, this.generation);
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return *this.value_ptr;
    }
}

/// Mutable view of one deliberately provisioned GenerationalPool slot.
///
/// `storage` exposes preserved representation even while inactive and is
/// therefore deliberately `@system`. `value` additionally requires occupancy.
struct GenerationalPoolSlot(T)
{
    alias Handle = GenerationalPool!T.Handle;

    T* storage_ptr;
    u32 index;
    u32 generation;
    bool occupied_state;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    bool occupied() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return this.occupied_state;
    }

    /// Returns the live handle for this slot, or `Handle.init` while inactive.
    Handle handle() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return this.occupied_state ? Handle(this.index, this.generation) : Handle.init;
    }

    ref T value() return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        require(this.occupied_state, "inactive GenerationalPool slot has no live value");

        return *this.storage_ptr;
    }

    ref T storage() return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return *this.storage_ptr;
    }
}

/// Read-only view of one deliberately provisioned GenerationalPool slot.
struct ConstGenerationalPoolSlot(T)
{
    alias Handle = GenerationalPool!T.Handle;

    const(T)* storage_ptr;
    u32 index;
    u32 generation;
    bool occupied_state;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    bool occupied() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return this.occupied_state;
    }

    Handle handle() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return this.occupied_state ? Handle(this.index, this.generation) : Handle.init;
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        require(this.occupied_state, "inactive GenerationalPool slot has no live value");

        return *this.storage_ptr;
    }

    ref const(T) storage() const return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return *this.storage_ptr;
    }
}

/// Mutable live-item view returned by `GenerationalPool.indexed_items`.
struct GenerationalPoolIndexedItem(T)
{
    T* value_ptr;
    u32 index;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    ref T value() return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return *this.value_ptr;
    }
}

/// Read-only live-item view returned by a const `GenerationalPool.indexed_items`.
struct ConstGenerationalPoolIndexedItem(T)
{
    const(T)* value_ptr;
    u32 index;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return *this.value_ptr;
    }
}

/// Input range yielding live GenerationalPool values directly by reference.
struct GenerationalPoolItemsRange(T)
{
    GenerationalPoolOccupiedCursor!T cursor;
    T* values;

    private static GenerationalPoolItemsRange create(GenerationalPool!T* pool) @trusted
    {
        GenerationalPoolItemsRange result;
        result.cursor = GenerationalPoolOccupiedCursor!T.create(pool);
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

/// Read-only input range yielding live GenerationalPool values by const reference.
struct ConstGenerationalPoolItemsRange(T)
{
    GenerationalPoolOccupiedCursor!T cursor;
    const(T)* values;

    private static ConstGenerationalPoolItemsRange create(const(GenerationalPool!T)* pool) @trusted
    {
        ConstGenerationalPoolItemsRange result;
        result.cursor = GenerationalPoolOccupiedCursor!T.create(pool);
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

/// Input range yielding live values with stable indices.
struct GenerationalPoolIndexedItemsRange(T)
{
    GenerationalPoolOccupiedCursor!T cursor;
    T* values;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    private static GenerationalPoolIndexedItemsRange create(GenerationalPool!T* pool) @trusted
    {
        GenerationalPoolIndexedItemsRange result;
        result.cursor = GenerationalPoolOccupiedCursor!T.create(pool);
        result.values = pool.values.ptr;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
            result.states_base = pool.states.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        return this.cursor.empty;
    }

    GenerationalPoolIndexedItem!T front() return @system
    {
        GenerationalPoolIndexedItem!T result;
        result.value_ptr = this.values + this.cursor.index;
        result.index = this.cursor.index;
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
            result.states_base = this.states_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        this.cursor.popFront();
    }
}

/// Read-only input range yielding live values with stable indices.
struct ConstGenerationalPoolIndexedItemsRange(T)
{
    GenerationalPoolOccupiedCursor!T cursor;
    const(T)* values;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    private static ConstGenerationalPoolIndexedItemsRange create(
        const(GenerationalPool!T)* pool,
    ) @trusted
    {
        ConstGenerationalPoolIndexedItemsRange result;
        result.cursor = GenerationalPoolOccupiedCursor!T.create(pool);
        result.values = pool.values.ptr;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
            result.states_base = pool.states.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        return this.cursor.empty;
    }

    ConstGenerationalPoolIndexedItem!T front() const return @system
    {
        ConstGenerationalPoolIndexedItem!T result;
        result.value_ptr = this.values + this.cursor.index;
        result.index = this.cursor.index;
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
            result.states_base = this.states_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        this.cursor.popFront();
    }
}

/// Input range yielding live slots with stable identity metadata.
struct GenerationalPoolOccupiedSlotsRange(T)
{
    GenerationalPoolOccupiedCursor!T cursor;
    T* values;
    const(u32)* states;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    private static GenerationalPoolOccupiedSlotsRange create(GenerationalPool!T* pool) @trusted
    {
        GenerationalPoolOccupiedSlotsRange result;
        result.cursor = GenerationalPoolOccupiedCursor!T.create(pool);
        result.values = pool.values.ptr;
        result.states = pool.states.ptr;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
            result.states_base = pool.states.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        return this.cursor.empty;
    }

    GenerationalPoolOccupiedSlot!T front() return @system
    {
        const u32 index = this.cursor.index;
        const u32 state = this.states[index];
        GenerationalPoolOccupiedSlot!T result;
        result.value_ptr = this.values + index;
        result.index = index;
        result.generation = state_generation(state);
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
            result.states_base = this.states_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        this.cursor.popFront();
    }
}

/// Read-only live-slot range for a const GenerationalPool.
struct ConstGenerationalPoolOccupiedSlotsRange(T)
{
    GenerationalPoolOccupiedCursor!T cursor;
    const(T)* values;
    const(u32)* states;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    private static ConstGenerationalPoolOccupiedSlotsRange create(
        const(GenerationalPool!T)* pool,
    ) @trusted
    {
        ConstGenerationalPoolOccupiedSlotsRange result;
        result.cursor = GenerationalPoolOccupiedCursor!T.create(pool);
        result.values = pool.values.ptr;
        result.states = pool.states.ptr;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
            result.states_base = pool.states.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        return this.cursor.empty;
    }

    ConstGenerationalPoolOccupiedSlot!T front() const return @system
    {
        const u32 index = this.cursor.index;
        const u32 state = this.states[index];
        ConstGenerationalPoolOccupiedSlot!T result;
        result.value_ptr = this.values + index;
        result.index = index;
        result.generation = state_generation(state);
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
            result.states_base = this.states_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        this.cursor.popFront();
    }
}

/// Sequential input range over all deliberately provisioned GenerationalPool slots.
struct GenerationalPoolSlotsRange(T)
{
    T* values;
    const(u32)* states;
    usize current_index;
    usize end_index;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    private static GenerationalPoolSlotsRange create(GenerationalPool!T* pool) @trusted
    {
        GenerationalPoolSlotsRange result;
        result.values = pool.values.ptr;
        result.states = pool.states.ptr;
        result.current_index = 1;
        result.end_index = pool.states.provisioned_length;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
            result.states_base = pool.states.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return this.current_index >= this.end_index;
    }

    GenerationalPoolSlot!T front() return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        require(this.current_index < this.end_index, "front of empty GenerationalPool slots range");

        const u32 index = cast(u32) this.current_index;
        const u32 state = this.states[index];
        GenerationalPoolSlot!T result;
        result.storage_ptr = this.values + index;
        result.index = index;
        result.generation = state_generation(state);
        result.occupied_state = state_active(state);
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
            result.states_base = this.states_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        require(
            this.current_index < this.end_index,
            "popFront of empty GenerationalPool slots range",
        );

        ++this.current_index;
    }
}

/// Read-only sequential range over all deliberately provisioned GenerationalPool slots.
struct ConstGenerationalPoolSlotsRange(T)
{
    const(T)* values;
    const(u32)* states;
    usize current_index;
    usize end_index;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    private static ConstGenerationalPoolSlotsRange create(const(GenerationalPool!T)* pool) @trusted
    {
        ConstGenerationalPoolSlotsRange result;
        result.values = pool.values.ptr;
        result.states = pool.states.ptr;
        result.current_index = 1;
        result.end_index = pool.states.provisioned_length;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
            result.states_base = pool.states.ptr;
        }
        return result;
    }

    bool empty() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return this.current_index >= this.end_index;
    }

    ConstGenerationalPoolSlot!T front() const return @system
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        require(this.current_index < this.end_index, "front of empty GenerationalPool slots range");

        const u32 index = cast(u32) this.current_index;
        const u32 state = this.states[index];
        ConstGenerationalPoolSlot!T result;
        result.storage_ptr = this.values + index;
        result.index = index;
        result.generation = state_generation(state);
        result.occupied_state = state_active(state);
        version (XTB_Checked)
        {
            result.owner = this.owner;
            result.mutation_generation = this.mutation_generation;
            result.values_base = this.values_base;
            result.states_base = this.states_base;
        }
        return result;
    }

    void popFront() @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        require(
            this.current_index < this.end_index,
            "popFront of empty GenerationalPool slots range",
        );

        ++this.current_index;
    }
}

private struct GenerationalPoolOccupiedCursor(T)
{
    const(u32)* states;
    usize current_index;
    usize end_index;
    version (XTB_Checked)
    {
        const(GenerationalPool!T)* owner;
        usize mutation_generation;
        const(T)* values_base;
        const(u32)* states_base;
    }

    private static GenerationalPoolOccupiedCursor create(const(GenerationalPool!T)* pool) @trusted
    {
        GenerationalPoolOccupiedCursor result;
        result.states = pool.states.ptr;
        result.current_index = 1;
        result.end_index = pool.states.provisioned_length;
        version (XTB_Checked)
        {
            result.owner = pool;
            result.mutation_generation = pool.mutation_generation;
            result.values_base = pool.values.ptr;
            result.states_base = pool.states.ptr;
        }
        result.seek_occupied();
        return result;
    }

    pragma(inline, true)
    bool empty() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        return this.current_index >= this.end_index;
    }

    pragma(inline, true)
    u32 index() const @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        require(
            this.current_index < this.end_index,
            "front of empty GenerationalPool occupied range",
        );

        return cast(u32) this.current_index;
    }

    pragma(inline, true)
    void popFront() @trusted
    {
        version (XTB_Checked)
            require_generational_pool_view_valid(
                this.owner,
                this.mutation_generation,
                this.values_base,
                this.states_base,
            );
        require(
            this.current_index < this.end_index,
            "popFront of empty GenerationalPool occupied range",
        );

        ++this.current_index;
        this.seek_occupied();
    }

    pragma(inline, true)
    private void seek_occupied() @trusted
    {
        while (
            this.current_index < this.end_index
            && !state_active(this.states[this.current_index])
        )
        {
            ++this.current_index;
        }
    }
}

version (XTB_Checked) private void require_generational_pool_view_valid(T)(
    scope const GenerationalPool!T* owner,
    usize mutation_generation,
    scope const T* values_base,
    scope const u32* states_base,
) @trusted
{
    require(owner !is null, "GenerationalPool range has no owner");
    require(
        owner.mutation_generation == mutation_generation,
        "GenerationalPool range was invalidated by structural mutation",
    );
    require(
        owner.values.ptr is values_base && owner.states.ptr is states_base,
        "GenerationalPool range was invalidated by move or deinit",
    );
}

pragma(inline, true)
private bool state_active(u32 state) pure @safe
{
    return (state & active_bit) != 0;
}

pragma(inline, true)
private u32 state_generation(u32 state) pure @safe
{
    return state & generation_mask;
}

pragma(inline, true)
private u32 activate_state(u32 state) pure @safe
{
    return active_bit | state_generation(state);
}

pragma(inline, true)
private u32 deactivate_and_advance(u32 state) pure @safe
{
    return (state_generation(state) + 1) & generation_mask;
}

static assert(needs_deinit!(GenerationalPool!u8));
static assert(active_bit == 0x8000_0000u);
static assert(generation_mask == 0x7fff_ffffu);

// Everything below here is test-only.
version (unittest)
{
    import core.stdc.string;

    private alias IntPool = GenerationalPool!i32;
    private alias IntHandle = IntPool.Handle;
}

unittest
{
    static assert(IntHandle.init.index == 0);
    static assert(IntHandle.init.generation == 0);
    static assert(!IntHandle.init.valid);
    static assert(!__traits(compiles,
        (ref IntPool int_pool, GenerationalPool!u32.Handle other_handle)
        {
            int_pool.get(other_handle);
        },
    ));
    static assert(__traits(compiles,
        (ref const IntPool pool, IntHandle handle)
        {
            const capacity = pool.capacity;
            const count = pool.live_count;
            const is_empty = pool.empty;
            const present = pool.contains(handle);
            const i32* value = pool.get(handle);
            auto items = pool.items();
            auto indexed_items = pool.indexed_items();
            auto occupied_slots = pool.occupied_slots();
            auto slots = pool.slots();
            cast(void) items;
            cast(void) indexed_items;
            cast(void) occupied_slots;
            cast(void) slots;
            cast(void) capacity;
            cast(void) count;
            cast(void) is_empty;
            cast(void) present;
            cast(void) value;
        },
    ));

    version (XTB_Checked)
    {
        static assert(__traits(hasMember, IntPool, "mutation_generation"));
        static assert(__traits(hasMember, GenerationalPoolSlot!i32, "owner"));
    }
    else
    {
        static assert(!__traits(hasMember, IntPool, "mutation_generation"));
        static assert(!__traits(hasMember, GenerationalPoolSlot!i32, "owner"));
    }

    assert(!state_active(0));
    assert(state_generation(0) == 0);
    assert(state_active(activate_state(0)));
    assert(state_generation(activate_state(0)) == 0);
    assert(deactivate_and_advance(active_bit | generation_mask) == 0);
    assert(!state_active(deactivate_and_advance(active_bit | generation_mask)));
}

unittest
{
    IntPool zero;
    assert(zero.capacity == 0);
    assert(zero.live_count == 0);
    assert(zero.empty);
    assert(zero.get(IntHandle.init) is null);
    assert(!zero.contains(IntHandle.init));

    IntHandle unchanged = IntHandle(17, 19);
    assert(!zero.try_allocate(&unchanged));
    assert(unchanged == IntHandle(17, 19));

    zero.clear();
    zero.deinit();

    auto zero_created = IntPool.create(0);
    assert(zero_created.capacity == 0);
    zero_created.deinit();
}

unittest
{
    if (!virtual_memory_supported) return;

    auto pool = IntPool.create(3);
    scope (exit) pool.deinit();

    assert(pool.capacity == 3);
    assert(pool.live_count == 0);
    assert(pool.get(IntHandle.init) is null);

    IntHandle first = pool.allocate_init();
    IntHandle second = pool.allocate_init();
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
    assert(pool.live_count == 2);

    const value_committed = pool.values.committed_bytes;
    const state_committed = pool.states.committed_bytes;
    const free_committed = pool.free_indices.committed_bytes;
    assert(pool.try_deallocate(first));
    assert(first.valid); // Non-null representation; pool-relative membership is stale.
    assert(!pool.contains(first));
    assert(pool.get(first) is null);
    assert(!pool.try_deallocate(first));
    assert(pool.values.committed_bytes == value_committed);
    assert(pool.states.committed_bytes == state_committed);
    assert(pool.free_indices.committed_bytes == free_committed);

    IntHandle recycled = pool.allocate();
    assert(recycled.index == first.index);
    assert(recycled.generation == first.generation + 1);
    assert(pool.values.committed_bytes == value_committed);
    assert(pool.states.committed_bytes == state_committed);
    assert(pool.free_indices.committed_bytes == free_committed);
    assert(pool.get(first) is null);
    assert(pool.get(recycled) !is null);

    IntHandle third = pool.allocate_init();
    assert(third.index == 3);
    IntHandle sentinel = IntHandle(77, 88);
    assert(!pool.try_allocate(&sentinel));
    assert(sentinel == IntHandle(77, 88));

    // Exercise generation wrap through the public deallocation path.
    pool.states[recycled.index] = active_bit | generation_mask;
    IntHandle wrap_handle = IntHandle(recycled.index, generation_mask);
    assert(pool.try_deallocate(wrap_handle));
    assert(pool.states[wrap_handle.index] == 0);

    IntHandle wrapped = pool.allocate();
    assert(wrapped.index == wrap_handle.index);
    assert(wrapped.generation == 0);
}

unittest
{
    if (!virtual_memory_supported) return;

    enum u32 free_commit_boundary = 16_385;
    auto pool = GenerationalPool!u8.create(free_commit_boundary);
    scope (exit) pool.deinit();

    foreach (_; 1 .. free_commit_boundary)
    {
        cast(void) pool.allocate();
    }

    const free_bytes_before_boundary = pool.free_indices.committed_bytes;
    const boundary_handle = pool.allocate();
    assert(boundary_handle.index == free_commit_boundary);
    assert(pool.free_indices.committed_bytes > free_bytes_before_boundary);

    const values_committed = pool.values.committed_bytes;
    const states_committed = pool.states.committed_bytes;
    const free_committed = pool.free_indices.committed_bytes;
    pool.deallocate(boundary_handle);
    assert(pool.values.committed_bytes == values_committed);
    assert(pool.states.committed_bytes == states_committed);
    assert(pool.free_indices.committed_bytes == free_committed);
}

unittest
{
    if (!virtual_memory_supported) return;

    struct Representation
    {
        u32 first;
        u32 second;
    }

    auto pool = GenerationalPool!Representation.create(2);
    scope (exit) pool.deinit();

    const handle = pool.allocate_init();
    Representation* representation = pool.get(handle);
    representation.first = 0x1234_5678;
    representation.second = 0x9abc_def0;
    Representation snapshot = *representation;
    const value_committed = pool.values.committed_bytes;
    const state_committed = pool.states.committed_bytes;
    const free_committed = pool.free_indices.committed_bytes;

    assert(pool.try_deallocate(handle));
    assert(memcmp(representation, &snapshot, Representation.sizeof) == 0);
    assert(pool.values.committed_bytes == value_committed);
    assert(pool.states.committed_bytes == state_committed);
    assert(pool.free_indices.committed_bytes == free_committed);

    const reused = pool.allocate();
    assert(reused.index == handle.index);
    assert(memcmp(pool.get(reused), &snapshot, Representation.sizeof) == 0);

    const other_handle = pool.allocate_init();
    Representation* other = pool.get(other_handle);
    other.first = 7;
    other.second = 9;
    Representation other_snapshot = *other;

    pool.clear();
    assert(pool.empty);
    assert(pool.get(reused) is null);
    assert(pool.get(other_handle) is null);
    assert(memcmp(representation, &snapshot, Representation.sizeof) == 0);
    assert(memcmp(other, &other_snapshot, Representation.sizeof) == 0);

    const after_clear_first = pool.allocate();
    const after_clear_second = pool.allocate();
    assert(after_clear_first.index == 1);
    assert(after_clear_second.index == 2);
    assert(after_clear_first.generation == reused.generation + 1);
    assert(after_clear_second.generation == other_handle.generation + 1);
}

unittest
{
    if (!virtual_memory_supported) return;

    auto pool = IntPool.create(6);
    scope (exit) pool.deinit();

    IntHandle one = pool.allocate_init();
    IntHandle two = pool.allocate_init();
    IntHandle three = pool.allocate_init();
    IntHandle four = pool.allocate_init();
    assert(one.valid);
    *pool.get(one) = 10;
    *pool.get(two) = 20;
    *pool.get(three) = 30;
    *pool.get(four) = 40;
    pool.deallocate(two);
    pool.deallocate(four);

    usize item_count;
    foreach (ref item; pool.items())
    {
        item += 100;
        ++item_count;
    }
    assert(item_count == 2);
    assert(*pool.get(one) == 110);
    assert(*pool.get(three) == 130);

    u32[2] indexed_indices;
    usize indexed_count;
    foreach (item; pool.indexed_items())
    {
        indexed_indices[indexed_count++] = item.index;
        assert(item.value == 110 || item.value == 130);
    }
    assert(indexed_count == 2);
    assert(indexed_indices == [1, 3]);

    u32[2] occupied_indices;
    u32[2] occupied_generations;
    usize occupied_count;
    foreach (slot; pool.occupied_slots())
    {
        occupied_indices[occupied_count] = slot.index;
        occupied_generations[occupied_count] = slot.generation;
        assert(slot.handle.index == slot.index);
        assert(slot.handle.generation == slot.generation);
        assert(pool.get(slot.handle) is &slot.value());
        slot.value += 1;
        ++occupied_count;
    }
    assert(occupied_count == 2);
    assert(occupied_indices == [1, 3]);
    assert(occupied_generations == [0, 0]);
    assert(*pool.get(one) == 111);
    assert(*pool.get(three) == 131);

    u32[4] slot_indices;
    u32[4] slot_generations;
    bool[4] slot_occupancy;
    i32[4] slot_representations;
    usize slot_count;
    foreach (slot; pool.slots())
    {
        slot_indices[slot_count] = slot.index;
        slot_generations[slot_count] = slot.generation;
        slot_occupancy[slot_count] = slot.occupied;
        slot_representations[slot_count] = slot.storage;
        if (slot.occupied)
        {
            assert(slot.handle.index == slot.index);
        }
        else
        {
            assert(slot.handle == IntHandle.init);
        }
        ++slot_count;
    }
    assert(slot_count == 4);
    assert(slot_indices == [1, 2, 3, 4]);
    assert(slot_generations == [0, 1, 0, 1]);
    assert(slot_occupancy == [true, false, true, false]);
    assert(slot_representations == [111, 20, 131, 40]);

    auto manual = pool.items();
    assert(!manual.empty);
    assert(&manual.front() is pool.get(one));
    manual.popFront();
    assert(!manual.empty);
    assert(&manual.front() is pool.get(three));
    manual.popFront();
    assert(manual.empty);

    auto independent_left = pool.occupied_slots();
    auto independent_right = pool.occupied_slots();
    independent_left.popFront();
    assert(independent_left.front.index == 3);
    assert(independent_right.front.index == 1);

    const(IntPool)* const_pool = &pool;
    usize const_item_count;
    foreach (ref const item; const_pool.items())
    {
        assert(item == 111 || item == 131);
        ++const_item_count;
    }
    assert(const_item_count == 2);

    usize const_indexed_count;
    foreach (item; const_pool.indexed_items())
    {
        assert(item.index == 1 || item.index == 3);
        assert(item.value == 111 || item.value == 131);
        ++const_indexed_count;
    }
    assert(const_indexed_count == 2);

    usize const_occupied_count;
    foreach (slot; const_pool.occupied_slots())
    {
        assert(slot.index == 1 || slot.index == 3);
        assert(slot.generation == 0);
        assert(const_pool.get(slot.handle) is &slot.value());
        ++const_occupied_count;
    }
    assert(const_occupied_count == 2);

    usize const_slot_count;
    foreach (slot; const_pool.slots())
    {
        assert(slot.index >= 1 && slot.index <= 4);
        cast(void) slot.storage;
        ++const_slot_count;
    }
    assert(const_slot_count == 4);

    pool.clear();
    usize cleared_slot_count;
    foreach (slot; pool.slots())
    {
        assert(!slot.occupied);
        assert(slot.generation == 1);
        assert(slot.handle == IntHandle.init);
        ++cleared_slot_count;
    }
    assert(cleared_slot_count == 4);
    assert(pool.items().empty);
    assert(pool.occupied_slots().empty);
}

unittest
{
    if (!virtual_memory_supported) return;

    enum u32 sparse_range_capacity = 130;
    auto pool = IntPool.create(sparse_range_capacity);
    scope (exit) pool.deinit();

    // Every element is assigned by the following loop before it is read.
    IntHandle[sparse_range_capacity] handles = void;
    foreach (offset; 0 .. sparse_range_capacity)
    {
        IntHandle handle = pool.allocate_init();
        *pool.get(handle) = cast(i32) handle.index;
        handles[offset] = handle;
    }
    foreach (index; 2 .. sparse_range_capacity)
    {
        pool.deallocate(handles[index - 1]);
    }

    u32[2] live_indices;
    usize live_count;
    foreach (slot; pool.occupied_slots())
    {
        live_indices[live_count++] = slot.index;
    }
    assert(live_count == 2);
    assert(live_indices == [1, sparse_range_capacity]);
}

unittest
{
    if (!virtual_memory_supported) return;

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
    auto pool = GenerationalPool!ExplicitOwner.create(2);
    scope (exit) pool.deinit();

    const handle = pool.construct(&explicit_deinits);
    assert(pool.try_dispose(handle));
    assert(explicit_deinits == 1);
    assert(!pool.try_dispose(handle));

    usize shallow_clear_deinits;
    auto shallow_clear_pool = GenerationalPool!ExplicitOwner.create(1);
    const shallow_clear_handle = shallow_clear_pool.construct(&shallow_clear_deinits);
    ExplicitOwner* shallow_clear_owner = shallow_clear_pool.get(shallow_clear_handle);
    shallow_clear_pool.clear();
    assert(shallow_clear_deinits == 0);
    assert(shallow_clear_pool.get(shallow_clear_handle) is null);
    finalize(*shallow_clear_owner);
    assert(shallow_clear_deinits == 1);
    shallow_clear_pool.deinit();

    usize shallow_deinit_count;
    auto shallow_deinit_pool = GenerationalPool!ExplicitOwner.create(1);
    cast(void) shallow_deinit_pool.construct(&shallow_deinit_count);
    shallow_deinit_pool.deinit();
    assert(shallow_deinit_count == 0);
}

unittest
{
    if (!virtual_memory_supported) return;

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
    auto pool = GenerationalPool!DestructorOnly.create(1);
    scope (exit) pool.deinit();

    const handle = pool.construct(&destructions);
    pool.dispose(handle);
    assert(destructions == 1);
}

unittest
{
    struct ContextOwner
    {
    nothrow @nogc:
        void deinit(i32*)
        {
        }
    }

    static assert(!can_finalize_without_context!ContextOwner);
    static assert(!__traits(compiles,
        (ref GenerationalPool!ContextOwner pool, GenerationalPool!ContextOwner.Handle handle)
        {
            pool.dispose(handle);
        },
    ));
}

unittest
{
    if (!virtual_memory_supported) return;

    align(8_192) struct OverAligned
    {
        u8 value;
    }

    auto pool = GenerationalPool!OverAligned.create(2);
    scope (exit) pool.deinit();

    const handle = pool.allocate_init();
    assert(cast(usize) pool.get(handle) % OverAligned.alignof == 0);
}

unittest
{
    if (!virtual_memory_supported) return;

    auto source = IntPool.create(4);
    const source_handle = source.allocate_init();
    *source.get(source_handle) = 91;

    IntPool moved = move(source);
    assert(source.capacity == 0);
    assert(source.empty);
    assert(moved.contains(source_handle));
    assert(*moved.get(source_handle) == 91);
    source.deinit();

    auto target = IntPool.create(1);
    cast(void) target.allocate_init();
    move_assign(moved, target);
    assert(moved.capacity == 0);
    assert(target.contains(source_handle));
    assert(*target.get(source_handle) == 91);
    moved.deinit();
    target.deinit();
}
