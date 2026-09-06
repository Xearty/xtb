module xtb.containers.virtual_array;

nothrow @nogc:

import core.attribute;
import core_lifetime = core.lifetime;
import core.stdc.string;

import xtb.allocators.internal.virtual_memory;
import xtb.lifetime;
import xtb.numeric;
import xtb.panic;
import xtb.types;

package(xtb.containers) enum usize default_virtual_commit_granularity = 64 * 1024;

private template supports_default_initialization(T)
{
    enum supports_default_initialization = __traits(compiles, ()
    {
        T value;
    });
}

/// Fixed-capacity contiguous storage backed by one virtual-memory reservation.
///
/// `VirtualArray` reserves its complete maximum capacity once, never relocates,
/// and commits a readable/writable prefix on demand. The zero state is valid
/// and explicit `deinit` releases only the reservation; it does not finalize
/// logical elements. The representation fields describe one coupled state:
/// `data` and `region` belong to `reservation`, `length <= capacity`, and the
/// logical prefix is accessible. Direct field mutation must preserve those
/// relationships.
@mustuse struct VirtualArray(T)
{
    alias Self = VirtualArray!T;

    VirtualMemoryReservation reservation;
    VirtualMemoryRegion region;
    T* data;
    usize capacity;
    usize length;
    usize committed_bytes;
    usize commit_granularity;

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Attempts to create an empty fixed-capacity array.
    ///
    /// The complete typed capacity is reserved but starts inaccessible. `output`
    /// must be non-null and inert and is modified only after creation succeeds.
    /// Capacity zero succeeds without requiring virtual-memory support and
    /// produces the inert state.
    static bool try_create(
        usize capacity,
        scope Self* output,
    ) @system
    {
        return Self.try_create(capacity, default_virtual_commit_granularity, output);
    }

    /// Attempts to create an empty fixed-capacity array with explicit commit
    /// growth granularity. `output` must be non-null and inert, and
    /// `commit_granularity` must be nonzero. The granularity is rounded up to
    /// native pages.
    static bool try_create(
        usize capacity,
        usize commit_granularity,
        scope Self* output,
    ) @system
    {
        require(output !is null, "VirtualArray output pointer is null");
        require(
            output is null || output.inert,
            "VirtualArray output is already initialized",
        );
        require(
            commit_granularity != 0,
            "VirtualArray commit granularity must be nonzero",
        );

        if (output is null || !output.inert || commit_granularity == 0) return false;
        if (capacity == 0) return true;
        if (!virtual_memory_supported) return false;

        const usize page_size = virtual_memory_page_size();
        if (page_size == 0) return false;

        usize normalized_commit_granularity;
        const granularity_normalized = try_round_up_to_multiple(
            commit_granularity,
            page_size,
            &normalized_commit_granularity,
        );
        if (!granularity_normalized) return false;

        VirtualArrayRegionGeometry geometry;
        if (!try_virtual_array_region_geometry!T(capacity, page_size, &geometry)) return false;
        if (add_overflows(geometry.region_bytes, geometry.alignment_slack)) return false;
        const reservation_bytes = geometry.region_bytes + geometry.alignment_slack;

        VirtualMemoryReservation reservation;
        if (!try_reserve_virtual_memory(reservation_bytes, &reservation)) return false;
        scope (exit) reservation.deinit();

        void* aligned_base;
        if (!try_align_address_up(reservation.base, geometry.base_alignment, &aligned_base))
        {
            return false;
        }

        const reservation_address = cast(usize) reservation.base;
        const aligned_address = cast(usize) aligned_base;
        const region_offset = aligned_address - reservation_address;

        VirtualMemoryRegion region;
        if (!reservation.try_region(region_offset, geometry.region_bytes, &region)) return false;

        Self result;
        move_emplace(reservation, result.reservation);
        result.region = region;
        result.data = cast(T*) aligned_base;
        result.capacity = capacity;
        result.commit_granularity = normalized_commit_granularity;
        move_emplace(result, *output);
        return true;
    }

    /// Creates an empty fixed-capacity array or panics when reservation setup
    /// fails.
    static Self create(
        usize capacity,
        usize commit_granularity = default_virtual_commit_granularity,
    ) @system
    {
        Self result;
        if (!Self.try_create(capacity, commit_granularity, &result))
            panic("VirtualArray reservation failed");

        return move(result);
    }

    /// Releases the complete virtual-memory reservation. Logical elements are
    /// not finalized. Repeated deinitialization and the zero state are valid.
    void deinit() @system
    {
        this.reservation.deinit();
        this.region = VirtualMemoryRegion.init;
        this.data = null;
        this.capacity = 0;
        this.length = 0;
        this.committed_bytes = 0;
        this.commit_granularity = 0;
    }

    /// Stable address of element zero, or null for zero capacity.
    ///
    /// The pointer borrows from this array and becomes invalid when its
    /// reservation is released. Only elements in `[0 .. length)` may be
    /// dereferenced by public callers; the remaining reserved tail may still be
    /// inaccessible.
    inout(T)* ptr() inout return @system
    {
        return this.data;
    }

    bool empty() const pure @safe
    {
        return this.length == 0;
    }

    /// Returns only the logical, committed prefix. The slice borrows from this
    /// array and must not be used after those elements cease to be logical or
    /// the reservation is released.
    inout(T)[] slice() inout return @system
    {
        return this.data[0 .. this.length];
    }

    static if (supports_default_initialization!T)
    {
        /// Resizes the logical array, default-initializing newly added values.
        /// Shrinking is shallow and retains committed pages.
        bool try_resize(usize requested) @trusted
        {
            if (requested <= this.length)
            {
                this.length = requested;
                return true;
            }
            if (!this.try_ensure_accessible(requested)) return false;

            while (this.length < requested)
            {
                construct_initial(this.data + this.length);
                ++this.length;
            }
            return true;
        }

        /// Resizes the logical array or panics when fixed capacity or virtual
        /// backing cannot satisfy the requested length.
        void resize(usize requested) @trusted
        {
            if (!this.try_resize(requested))
                panic("VirtualArray capacity or commitment exceeded");
        }
    }

    /// Attempts to append by moving from `*value` only after backing storage
    /// for the new element is accessible. `value` must be non-null. Failure
    /// leaves both operands unchanged.
    bool try_append(scope T* value) @system
    {
        require(value !is null, "VirtualArray append value pointer is null");
        if (value is null || this.length >= this.capacity) return false;
        if (!this.try_ensure_accessible(this.length + 1)) return false;
        construct_move(this.data + this.length, *value);
        ++this.length;
        return true;
    }

    /// Appends by move or panics when fixed capacity or virtual backing is
    /// exhausted.
    void append(T value) @trusted
    {
        if (!this.try_append(&value))
            panic("VirtualArray capacity or commitment exceeded");
    }

    static if (__traits(isCopyable, T))
    {
        /// Attempts to append a copy of every value. Failure leaves logical
        /// contents unchanged. The source may alias the current array.
        bool try_append(scope const(T)[] values) @trusted
        {
            if (values.length > this.capacity - this.length) return false;
            if (values.length == 0) return true;

            const old_length = this.length;
            const new_length = old_length + values.length;
            if (!this.try_ensure_accessible(new_length)) return false;

            static if (__traits(isPOD, T))
            {
                core.stdc.string.memmove(
                    this.data + old_length,
                    values.ptr,
                    values.length * T.sizeof,
                );
                this.length = new_length;
            }
            else
            {
                foreach (const ref value; values)
                {
                    construct_copy(this.data + this.length, value);
                    ++this.length;
                }
            }
            return true;
        }

        /// Appends copied values or panics when fixed capacity or virtual
        /// backing is exhausted.
        void append(scope const(T)[] values) @trusted
        {
            if (!this.try_append(values))
                panic("VirtualArray capacity or commitment exceeded");
        }
    }

    /// Returns a reference to the last logical element. The reference remains
    /// valid while that element remains logical and the reservation remains
    /// initialized.
    ref inout(T) back() inout return @system
    {
        require(this.length != 0, "cannot access back of empty VirtualArray");
        return this.data[this.length - 1];
    }

    /// Removes and transfers the last logical element without finalizing it.
    T pop() @trusted
    {
        require(this.length != 0, "cannot pop an empty VirtualArray");
        --this.length;
        T result = void;
        static if (__traits(isPOD, T) && !needs_deinit!T)
        {
            result = this.data[this.length];
        }
        else
        {
            move_emplace(this.data[this.length], result);
        }
        return result;
    }

    /// Discards all logical elements without finalizing them and retains all
    /// currently committed pages.
    void clear() @safe
    {
        this.length = 0;
    }

    /// Decommits whole pages that lie entirely beyond the logical array. The
    /// fixed virtual capacity and stable base address are unchanged.
    void trim() @trusted
    {
        if (this.committed_bytes == 0) return;

        const usize page_size = virtual_memory_page_size();
        if (page_size == 0) panic("VirtualArray page size unavailable");

        const live_bytes = this.length * T.sizeof;
        const trim_succeeded = try_trim_committed_prefix(
            this.region,
            live_bytes,
            page_size,
            &this.committed_bytes,
        );
        if (!trim_succeeded) panic("VirtualArray decommit failed");
    }

    /// Returns a reference valid while the indexed element remains logical and
    /// the reservation remains initialized.
    ref inout(T) opIndex(usize index) inout return @system
    {
        require(index < this.length, "VirtualArray index out of bounds");
        return this.data[index];
    }

    /// Makes the raw typed prefix `[0 .. element_count)` accessible without
    /// constructing elements or changing logical length.
    ///
    /// Container operations use this storage primitive before establishing
    /// any new `T` lifetimes. Failure leaves commitment bookkeeping and logical
    /// state unchanged.
    package(xtb.containers) bool try_ensure_accessible(usize element_count) @system
    {
        if (element_count > this.capacity) return false;
        if (element_count == 0) return true;

        const required_bytes = element_count * T.sizeof;
        return try_ensure_committed_prefix(
            this.region,
            required_bytes,
            this.commit_granularity,
            &this.committed_bytes,
        );
    }

    private bool inert() const pure @safe
    {
        return !this.reservation.active
            && this.region.empty
            && this.data is null
            && this.capacity == 0
            && this.length == 0
            && this.committed_bytes == 0
            && this.commit_granularity == 0;
    }
}

static assert(needs_deinit!(VirtualArray!u8));

/// Non-owning fixed-capacity typed storage over one bounded virtual-memory
/// region.
///
/// A view never releases its underlying mapping and never constructs or
/// finalizes `T`. It owns only its local provision/commit bookkeeping, so it is
/// deliberately non-copyable. `deinit` ends that local borrow and resets the
/// view without touching the parent reservation. The representation fields
/// describe one coupled state: `data` is the base of `region`,
/// `provisioned_length <= capacity`, and the provisioned prefix is accessible.
/// Direct field mutation must preserve those relationships.
package(xtb.containers) struct VirtualArrayView(T)
{
    alias Self = VirtualArrayView!T;

    VirtualMemoryRegion region;
    T* data;
    usize capacity;
    usize provisioned_length;
    usize committed_bytes;
    usize commit_granularity;

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Attempts to bind an inert view to `region`.
    ///
    /// `region` must be page-bounded, large enough for `capacity` elements,
    /// and aligned for `T`. Capacity zero requires an empty region. `output`
    /// must be non-null and inert, and `commit_granularity` must be nonzero.
    /// The output is modified only on success. No pages are committed by
    /// creation.
    static bool try_create(
        VirtualMemoryRegion region,
        usize capacity,
        usize commit_granularity,
        scope Self* output,
    ) @system
    {
        require(output !is null, "VirtualArrayView output pointer is null");
        require(
            output is null || output.inert,
            "VirtualArrayView output is already initialized",
        );
        require(
            commit_granularity != 0,
            "VirtualArrayView commit granularity must be nonzero",
        );

        if (output is null || !output.inert || commit_granularity == 0) return false;
        if (capacity == 0) return region.empty;
        if (region.empty || multiply_overflows(capacity, T.sizeof)) return false;

        const usize page_size = virtual_memory_page_size();
        if (page_size == 0) return false;

        usize normalized_commit_granularity;
        const granularity_normalized = try_round_up_to_multiple(
            commit_granularity,
            page_size,
            &normalized_commit_granularity,
        );
        if (!granularity_normalized) return false;

        const data_bytes = capacity * T.sizeof;
        if (data_bytes > region.bytes) return false;

        void* base = region.base;
        if (base is null || cast(usize) base % T.alignof != 0) return false;

        Self result;
        result.region = region;
        result.data = cast(T*) base;
        result.capacity = capacity;
        result.commit_granularity = normalized_commit_granularity;
        move_emplace(result, *output);
        return true;
    }

    /// Ends this view's local borrow. The underlying virtual-memory mapping and
    /// all committed pages remain owned by and attached to the parent.
    void deinit() @safe
    {
        this.region = VirtualMemoryRegion.init;
        this.data = null;
        this.capacity = 0;
        this.provisioned_length = 0;
        this.committed_bytes = 0;
        this.commit_granularity = 0;
    }

    /// Stable typed base of this region, or null for the inert state.
    ///
    /// The pointer borrows from this view and may be used only while the view is
    /// bound and the parent mapping remains alive. Only
    /// `[0 .. provisioned_length)` is promised by the view to have accessible
    /// storage. Extra elements may happen to fit in page-rounded committed bytes
    /// but are not provisioned by that fact alone.
    inout(T)* ptr() inout return @system
    {
        return this.data;
    }

    const(T)* ptr() const return @system
    {
        return this.data;
    }

    /// Accesses one deliberately provisioned raw-storage element. The returned
    /// reference may be used only while the view is bound and the parent mapping
    /// remains alive.
    ref inout(T) opIndex(usize index) inout return @system
    {
        require(
            index < this.provisioned_length,
            "VirtualArrayView index out of bounds",
        );
        return this.data[index];
    }

    bool inert() const pure @safe
    {
        return this.region.empty
            && this.data is null
            && this.capacity == 0
            && this.provisioned_length == 0
            && this.committed_bytes == 0
            && this.commit_granularity == 0;
    }

    /// Makes raw storage for `[0 .. element_count)` accessible without
    /// constructing `T` values.
    ///
    /// Provisioning is monotonic. Page/granularity rounding may commit bytes
    /// covering more elements, but `provisioned_length` advances only to the
    /// explicitly requested high-water. Failure leaves all bookkeeping
    /// unchanged (native commitment may conservatively remain larger only if a
    /// backend can partially commit before reporting failure).
    bool try_ensure_accessible(usize element_count) @system
    {
        if (element_count > this.capacity) return false;
        if (element_count <= this.provisioned_length) return true;

        const required_bytes = element_count * T.sizeof;
        const commitment_succeeded = try_ensure_committed_prefix(
            this.region,
            required_bytes,
            this.commit_granularity,
            &this.committed_bytes,
        );
        if (!commitment_succeeded) return false;

        this.provisioned_length = element_count;
        return true;
    }

    /// Decommits whole pages that are not needed by the provisioned prefix.
    /// The provisioned element high-water and fixed capacity are unchanged.
    void trim() @trusted
    {
        if (this.committed_bytes == 0) return;

        const usize page_size = virtual_memory_page_size();
        if (page_size == 0) panic("VirtualArrayView page size unavailable");

        const provisioned_bytes = this.provisioned_length * T.sizeof;
        const trim_succeeded = try_trim_committed_prefix(
            this.region,
            provisioned_bytes,
            page_size,
            &this.committed_bytes,
        );
        if (!trim_succeeded) panic("VirtualArrayView decommit failed");
    }
}

static assert(needs_deinit!(VirtualArrayView!u8));

/// Page-bounded geometry for one fixed-capacity typed virtual-array region.
///
/// This is shared by owning arrays and internal multi-region containers such
/// as Pool so alignment/overflow rules cannot drift between representations.
package(xtb.containers) struct VirtualArrayRegionGeometry
{
    usize region_bytes;
    usize base_alignment;
    usize alignment_slack;
}

package(xtb.containers) bool try_virtual_array_region_geometry(T)(
    usize capacity,
    usize page_size,
    scope VirtualArrayRegionGeometry* output,
) pure @safe
{
    if (output is null || page_size == 0 || multiply_overflows(capacity, T.sizeof)) return false;

    const data_bytes = capacity * T.sizeof;
    usize region_bytes;
    if (!try_round_up_to_multiple(data_bytes, page_size, &region_bytes)) return false;

    usize base_alignment;
    if (!try_least_common_multiple(page_size, T.alignof, &base_alignment)) return false;

    VirtualArrayRegionGeometry result;
    result.region_bytes = region_bytes;
    result.base_alignment = base_alignment;
    // A page-aligned base needs at most this much slack to reach an address
    // aligned to both the native page size and T.alignof.
    result.alignment_slack = base_alignment - page_size;
    *output = result;
    return true;
}

private bool try_ensure_committed_prefix(
    VirtualMemoryRegion region,
    usize required_bytes,
    usize commit_granularity,
    scope usize* committed_bytes,
) @system
{
    if (committed_bytes is null || required_bytes > region.bytes) return false;
    if (required_bytes <= *committed_bytes) return true;

    usize target_committed;
    const rounded = try_round_up_to_multiple(
        required_bytes,
        commit_granularity,
        &target_committed,
    );
    if (!rounded || target_committed > region.bytes) target_committed = region.bytes;

    if (target_committed < required_bytes || target_committed < *committed_bytes) return false;

    const additional_bytes = target_committed - *committed_bytes;
    if (!region.try_commit(*committed_bytes, additional_bytes)) return false;

    *committed_bytes = target_committed;
    return true;
}

private bool try_trim_committed_prefix(
    VirtualMemoryRegion region,
    usize retained_bytes,
    usize page_size,
    scope usize* committed_bytes,
) @system
{
    if (committed_bytes is null || retained_bytes > region.bytes) return false;

    usize target_committed;
    const rounded = try_round_up_to_multiple(retained_bytes, page_size, &target_committed);
    if (!rounded || target_committed > region.bytes) target_committed = region.bytes;
    if (target_committed >= *committed_bytes) return true;

    const decommit_bytes = *committed_bytes - target_committed;
    if (!region.try_decommit(target_committed, decommit_bytes)) return false;

    *committed_bytes = target_committed;
    return true;
}

private bool try_round_up_to_multiple(
    usize value,
    usize multiple,
    scope usize* output,
) pure @safe
{
    if (output is null || multiple == 0) return false;

    const remainder = value % multiple;
    if (remainder == 0)
    {
        *output = value;
        return true;
    }

    const increment = multiple - remainder;
    if (add_overflows(value, increment)) return false;

    *output = value + increment;
    return true;
}

private usize greatest_common_divisor(usize left, usize right) pure @safe
{
    while (right != 0)
    {
        const remainder = left % right;
        left = right;
        right = remainder;
    }
    return left;
}

private bool try_least_common_multiple(
    usize left,
    usize right,
    scope usize* output,
) pure @safe
{
    if (output is null || left == 0 || right == 0) return false;

    const usize divisor = greatest_common_divisor(left, right);
    const reduced = left / divisor;
    if (multiply_overflows(reduced, right)) return false;

    *output = reduced * right;
    return true;
}

package(xtb.containers) bool try_align_address_up(
    void* address,
    usize alignment,
    scope void** output,
) @system
{
    if (output is null || address is null || alignment == 0) return false;

    const value = cast(usize) address;
    const remainder = value % alignment;
    if (remainder == 0)
    {
        *output = address;
        return true;
    }

    const increment = alignment - remainder;
    if (add_overflows(value, increment)) return false;

    *output = cast(void*)(value + increment);
    return true;
}

private void construct_initial(T)(T* destination) @system
{
    static if (__traits(isPOD, T))
    {
        *destination = T.init;
    }
    else
    {
        core_lifetime.emplace(destination);
    }
}

private void construct_move(T)(T* destination, ref T source) @system
{
    static if (__traits(isPOD, T) && !needs_deinit!T)
    {
        *destination = source;
    }
    else
    {
        move_emplace(source, *destination);
    }
}

private void construct_copy(T, U)(T* destination, ref U source) @system
{
    static if (__traits(isPOD, T))
    {
        *destination = source;
    }
    else
    {
        core_lifetime.emplace(destination, source);
    }
}

unittest
{
    struct ExplicitOwner
    {
    nothrow @nogc:

        usize* deinits;
        bool active;

        @disable this(this);

        this(usize* deinits)
        {
            this.deinits = deinits;
            this.active = true;
        }

        void deinit()
        {
            if (!this.active) return;

            this.active = false;
            ++*this.deinits;
        }
    }

    struct DestructorOnly
    {
        usize* destructions;
        bool armed;

        @disable this(this);

        ~this() nothrow @nogc
        {
            if (!this.armed) return;

            this.armed = false;
            ++*this.destructions;
        }
    }

    static assert(!__traits(isCopyable, VirtualArray!i32));
    static assert(needs_deinit!(VirtualArray!i32));
    static assert(__traits(compiles, () nothrow @nogc @system
    {
        VirtualArray!i32 value;
        cast(void) value.ptr;
        cast(void) value.length;
        cast(void) value.capacity;
        cast(void) value.empty;
        cast(void) value.slice;
        cast(void) value.try_ensure_accessible(0);
        value.deinit();
    }));
    static assert(__traits(compiles, () nothrow @nogc @safe
    {
        VirtualArray!i32 value;
        cast(void) value.length;
        cast(void) value.capacity;
        cast(void) value.empty;
        cast(void) value.try_resize(0);
        value.resize(0);
        value.append(1);
        cast(void) value.pop();
        value.clear();
        value.trim();
    }));
    static assert(!__traits(compiles, () nothrow @nogc @safe
    {
        VirtualArray!i32 value;
        cast(void) value.ptr;
    }));
    static assert(__traits(compiles, (ref const(VirtualArray!i32) value) nothrow @nogc @system
    {
        const(i32)* pointer = value.ptr;
        const(i32)[] values = value.slice;
        ref const(i32) back = value.back();
        ref const(i32) indexed = value[0];
        cast(void) pointer;
        cast(void) values;
        cast(void) back;
        cast(void) indexed;
    }));

    VirtualArray!i32 zero;
    assert(VirtualArray!i32.try_create(0, &zero));
    assert(zero.ptr is null);
    assert(zero.length == 0);
    assert(zero.capacity == 0);
    assert(zero.empty);
    assert(zero.slice.length == 0);
    assert(zero.try_ensure_accessible(0));
    assert(!zero.try_ensure_accessible(1));
    assert(zero.try_resize(0));
    assert(!zero.try_resize(1));
    zero.deinit();
    zero.deinit();

    version (linux)
    {
        const usize page_size = virtual_memory_page_size();
        assert(page_size != 0);

        auto values = VirtualArray!i32.create(8, page_size);
        scope (exit) values.deinit();

        i32* values_base = values.ptr;
        assert(values.try_resize(3));
        assert(values.length == 3);
        assert(values[0] == 0 && values[1] == 0 && values[2] == 0);
        values[0] = 10;
        values[1] = 20;
        values[2] = 30;
        assert(&values[0] is values_base);

        i32 candidate = 40;
        assert(values.try_append(&candidate));
        assert(values.length == 4);
        assert(values.back == 40);
        assert(values.ptr is values_base);

        values.append(values.slice[0 .. 2]);
        assert(values.length == 6);
        assert(values[4] == 10 && values[5] == 20);
        assert(values.ptr is values_base);

        i32 popped = values.pop();
        assert(popped == 20);
        assert(values.length == 5);
        assert(values.back == 10);

        assert(!values.try_resize(values.capacity + 1));
        assert(values.length == 5);
        assert(values[0] == 10 && values[4] == 10);
        values.resize(2);
        assert(values.length == 2);
        assert(values[0] == 10 && values[1] == 20);
        assert(values.ptr is values_base);

        values.resize(values.capacity);
        assert(values.ptr is values_base);
        i32 overflow_candidate = 77;
        assert(!values.try_append(&overflow_candidate));
        assert(overflow_candidate == 77);
        assert(values.length == values.capacity);

        const retained_commit = values.committed_bytes;
        values.clear();
        assert(values.empty);
        assert(values.committed_bytes == retained_commit);
        values.trim();
        assert(values.committed_bytes == 0);
        assert(values.ptr is values_base);

        // Trimming decommits pages outside the logical prefix. Recommitting raw
        // storage must expose fresh zero-filled pages without relocating data.
        auto trimmed = VirtualArray!u8.create(page_size * 3, page_size);
        scope (exit) trimmed.deinit();

        u8* trimmed_base = trimmed.ptr;
        trimmed.resize(page_size);
        assert(trimmed.try_ensure_accessible(page_size * 3));
        trimmed.ptr[page_size * 2] = 0xA5;
        assert(trimmed.committed_bytes == page_size * 3);
        trimmed.trim();
        assert(trimmed.committed_bytes == page_size);
        assert(trimmed.ptr is trimmed_base);
        assert(trimmed.try_ensure_accessible(page_size * 3));
        assert(trimmed.ptr is trimmed_base);
        assert(trimmed.ptr[page_size * 2] == 0);

        usize explicit_deinits;
        auto owners = VirtualArray!ExplicitOwner.create(2, page_size);
        auto owner = ExplicitOwner(&explicit_deinits);
        assert(owners.try_append(&owner));
        assert(!owner.active);
        assert(owners.length == 1);
        owners.clear();
        assert(explicit_deinits == 0);
        owners.deinit();
        assert(explicit_deinits == 0);

        auto transferred = VirtualArray!ExplicitOwner.create(1, page_size);
        auto transferred_source = ExplicitOwner(&explicit_deinits);
        assert(transferred.try_append(&transferred_source));
        auto rejected = ExplicitOwner(&explicit_deinits);
        assert(!transferred.try_append(&rejected));
        assert(rejected.active);
        xtb.lifetime.deinit(rejected);
        assert(explicit_deinits == 1);
        ExplicitOwner transferred_value = transferred.pop();
        assert(transferred.empty);
        assert(transferred_value.active);
        xtb.lifetime.deinit(transferred_value);
        assert(explicit_deinits == 2);
        transferred.deinit();

        usize destructions;
        auto destructor_values = VirtualArray!DestructorOnly.create(1, page_size);
        DestructorOnly destructor_source;
        destructor_source.destructions = &destructions;
        destructor_source.armed = true;
        assert(destructor_values.try_append(&destructor_source));
        assert(!destructor_source.armed);
        DestructorOnly destructor_value = destructor_values.pop();
        assert(destructor_value.armed);
        destroy(destructor_value);
        assert(destructions == 1);
        destructor_values.deinit();

        VirtualArray!u8 overflow;
        assert(!VirtualArray!u8.try_create(usize.max, usize.max, &overflow));
        assert(overflow.capacity == 0);

        VirtualArray!u64 multiplied_overflow;
        assert(!VirtualArray!u64.try_create(usize.max / u64.sizeof + 1, &multiplied_overflow));
        assert(multiplied_overflow.ptr is null);

        VirtualArray!u8 array;
        assert(VirtualArray!u8.try_create(page_size * 4 + 17, page_size + 1, &array));
        scope (exit) array.deinit();

        assert(array.capacity == page_size * 4 + 17);
        assert(array.length == 0);
        assert(array.committed_bytes == 0);
        assert(array.ptr !is null);
        assert(cast(usize) array.ptr % u8.alignof == 0);
        u8* original = array.ptr;

        assert(array.try_ensure_accessible(1));
        assert(array.ptr is original);
        assert(array.committed_bytes == page_size * 2);
        array.ptr[0] = 0x11;

        assert(array.try_ensure_accessible(page_size * 2));
        assert(array.ptr is original);
        assert(array.committed_bytes == page_size * 2);

        assert(array.try_ensure_accessible(page_size * 2 + 1));
        assert(array.ptr is original);
        assert(array.committed_bytes == page_size * 4);
        array.ptr[page_size * 2] = 0x22;
        assert(array.ptr[0] == 0x11);

        assert(array.try_ensure_accessible(array.capacity));
        assert(array.ptr is original);
        assert(array.committed_bytes == array.region.bytes);
        array.ptr[array.capacity - 1] = 0x33;
        assert(array.ptr[array.capacity - 1] == 0x33);
        assert(!array.try_ensure_accessible(array.capacity + 1));

        VirtualArray!u8 moved = move(array);
        assert(array.ptr is null);
        assert(array.capacity == 0);
        assert(moved.ptr is original);
        assert(moved.capacity == page_size * 4 + 17);
        assert(moved.ptr[0] == 0x11);
        assert(moved.ptr[page_size * 2] == 0x22);
        assert(moved.ptr[moved.capacity - 1] == 0x33);

        auto replacement = VirtualArray!u8.create(page_size);
        u8* replacement_old = replacement.ptr;
        assert(replacement_old !is null);
        move_assign(moved, replacement);
        assert(moved.ptr is null);
        assert(replacement.ptr is original);
        assert(replacement.capacity == page_size * 4 + 17);
        replacement.deinit();

        align(8_192) struct OverAligned
        {
            u8 value;
        }

        // Keep the fixture below LLVM 18's 16 KiB IR alignment ceiling.
        // Exercise the over-page-aligned path only when the host page size is
        // smaller than the representable test alignment.
        if (OverAligned.alignof > page_size)
        {
            VirtualArray!OverAligned aligned;
            assert(VirtualArray!OverAligned.try_create(3, page_size, &aligned));
            scope (exit) aligned.deinit();

            assert(aligned.ptr !is null);
            assert(cast(usize) aligned.ptr % OverAligned.alignof == 0);
            assert(aligned.try_resize(3));
            OverAligned* aligned_base = aligned.ptr;
            aligned[0].value = 1;
            aligned[2].value = 3;
            assert(aligned.ptr is aligned_base);
            assert(aligned.ptr[0].value == 1);
            assert(aligned.ptr[2].value == 3);
        }
    }
}

unittest
{
    static assert(!__traits(isCopyable, VirtualArrayView!i32));
    static assert(needs_deinit!(VirtualArrayView!i32));
    static assert(__traits(compiles, () nothrow @nogc @safe
    {
        VirtualArrayView!i32 view;
        cast(void) view.capacity;
        cast(void) view.provisioned_length;
        cast(void) view.committed_bytes;
        cast(void) view.inert;
        view.deinit();
    }));
    static assert(!__traits(compiles, () nothrow @nogc @safe
    {
        VirtualArrayView!i32 view;
        cast(void) view.ptr;
    }));
    static assert(__traits(compiles,
        (ref const(VirtualArrayView!i32) view) nothrow @nogc @system
        {
            const(i32)* pointer = view.ptr;
            ref const(i32) indexed = view[0];
            cast(void) pointer;
            cast(void) indexed;
        },
    ));

    VirtualArrayView!i32 zero;
    assert(VirtualArrayView!i32.try_create(VirtualMemoryRegion.init, 0, 1, &zero));
    assert(zero.inert);
    assert(zero.try_ensure_accessible(0));
    assert(!zero.try_ensure_accessible(1));
    zero.trim();
    zero.deinit();

    version (linux)
    {
        const usize page_size = virtual_memory_page_size();
        assert(page_size != 0);

        VirtualMemoryReservation reservation;
        assert(try_reserve_virtual_memory(page_size * 6, &reservation));
        scope (exit) reservation.deinit();

        VirtualMemoryRegion first_region;
        VirtualMemoryRegion second_region;
        VirtualMemoryRegion move_region;
        assert(reservation.try_region(0, page_size * 2, &first_region));
        assert(reservation.try_region(page_size * 2, page_size * 2, &second_region));
        assert(reservation.try_region(page_size * 4, page_size * 2, &move_region));

        VirtualArrayView!u8 first;
        VirtualArrayView!u8 second;
        assert(VirtualArrayView!u8.try_create(first_region, page_size * 2, page_size * 2, &first));
        assert(VirtualArrayView!u8.try_create(second_region, page_size * 2, page_size, &second));
        scope (exit)
        {
            first.deinit();
            second.deinit();
        }

        assert(first.capacity == page_size * 2);
        assert(first.provisioned_length == 0);
        assert(first.committed_bytes == 0);
        assert(second.committed_bytes == 0);

        // Provisioning one byte commits according to granularity but does not
        // claim the trailing elements covered by those pages.
        assert(first.try_ensure_accessible(1));
        assert(first.provisioned_length == 1);
        assert(first.committed_bytes == page_size * 2);
        assert(second.provisioned_length == 0);
        assert(second.committed_bytes == 0);

        // Raw provisioning never initializes newly promised element storage.
        // This byte is physically accessible because of page rounding, but it
        // is deliberately outside the current provisioned high-water.
        first.ptr[page_size] = 0xA5;
        assert(first.try_ensure_accessible(page_size + 1));
        assert(first.provisioned_length == page_size + 1);
        assert(first[page_size] == 0xA5);

        assert(second.try_ensure_accessible(page_size + 1));
        assert(second.provisioned_length == page_size + 1);
        assert(second.committed_bytes == page_size * 2);
        second[0] = 0x22;
        assert(first[0] == 0);

        // A separate view can trim its committed suffix without changing the
        // adjacent region or its own provisioned element high-water.
        VirtualArrayView!u8 trimming;
        const trimming_created = VirtualArrayView!u8.try_create(
            move_region,
            page_size * 2,
            page_size * 2,
            &trimming,
        );
        assert(trimming_created);
        assert(trimming.try_ensure_accessible(1));
        assert(trimming.committed_bytes == page_size * 2);
        trimming.ptr[page_size] = 0x7B;
        trimming.trim();
        assert(trimming.provisioned_length == 1);
        assert(trimming.committed_bytes == page_size);
        assert(second[0] == 0x22);
        assert(trimming.try_ensure_accessible(page_size + 1));
        assert(trimming[page_size] == 0);

        // Moving the reservation owner does not invalidate borrowed views;
        // the region stores the stable mapped address rather than owner state.
        VirtualMemoryReservation moved_reservation = move(reservation);
        assert(!reservation.active);
        assert(moved_reservation.active);
        u8* trimming_base = trimming.ptr;
        assert(trimming.try_ensure_accessible(page_size * 2));
        assert(trimming.ptr is trimming_base);

        VirtualArrayView!u8 moved_view = move(trimming);
        assert(trimming.inert);
        assert(moved_view.ptr is trimming_base);
        assert(moved_view.provisioned_length == page_size * 2);
        moved_view.deinit();
        assert(moved_view.inert);

        // Ending views does not release the parent reservation.
        first.deinit();
        second.deinit();
        assert(moved_reservation.active);
        VirtualMemoryRegion still_borrowable;
        assert(moved_reservation.try_region(0, page_size, &still_borrowable));
        assert(still_borrowable.try_commit(0, page_size));
        (cast(u8*) still_borrowable.base)[0] = 0x44;
        assert((cast(u8*) still_borrowable.base)[0] == 0x44);
        moved_reservation.deinit();

        // Capacity/size failure is transactional.
        VirtualMemoryReservation small_reservation;
        assert(try_reserve_virtual_memory(page_size, &small_reservation));
        scope (exit) small_reservation.deinit();

        VirtualMemoryRegion small_region;
        assert(small_reservation.try_region(0, page_size, &small_region));

        VirtualArrayView!u64 overflow;
        const overflow_created = VirtualArrayView!u64.try_create(
            small_region,
            usize.max / u64.sizeof + 1,
            page_size,
            &overflow,
        );
        assert(!overflow_created);
        assert(overflow.inert);

        VirtualArrayView!u8 too_large;
        assert(!VirtualArrayView!u8.try_create(small_region, page_size + 1, page_size, &too_large));
        assert(too_large.inert);

        // Over-aligned views are accepted when the supplied page-bounded
        // region starts at an address satisfying T.alignof, and rejected when
        // the same region is deliberately shifted by one page.
        align(8_192) struct OverAlignedViewValue
        {
            u8 value;
        }

        // See the matching owning-array test above for the backend limit.
        if (OverAlignedViewValue.alignof > page_size)
        {
            const aligned_region_bytes = OverAlignedViewValue.sizeof;
            const aligned_reservation_bytes = OverAlignedViewValue.alignof
                + aligned_region_bytes
                + page_size;
            VirtualMemoryReservation aligned_reservation;
            assert(try_reserve_virtual_memory(aligned_reservation_bytes, &aligned_reservation));
            scope (exit) aligned_reservation.deinit();

            void* aligned_base;
            const address_aligned = try_align_address_up(
                aligned_reservation.base,
                OverAlignedViewValue.alignof,
                &aligned_base,
            );
            assert(address_aligned);
            const aligned_offset = cast(usize) aligned_base
                - cast(usize) aligned_reservation.base;
            VirtualMemoryRegion aligned_region;
            const aligned_region_created = aligned_reservation.try_region(
                aligned_offset,
                aligned_region_bytes,
                &aligned_region,
            );
            assert(aligned_region_created);

            VirtualArrayView!OverAlignedViewValue aligned_view;
            const aligned_view_created = VirtualArrayView!OverAlignedViewValue.try_create(
                aligned_region,
                1,
                page_size,
                &aligned_view,
            );
            assert(aligned_view_created);
            scope (exit) aligned_view.deinit();

            assert(cast(usize) aligned_view.ptr % OverAlignedViewValue.alignof == 0);
            assert(aligned_view.try_ensure_accessible(1));
            aligned_view[0].value = 9;
            assert(aligned_view[0].value == 9);

            if (aligned_offset + page_size + aligned_region_bytes
                <= aligned_reservation.reserved_bytes)
            {
                VirtualMemoryRegion misaligned_region;
                const region_created = aligned_reservation.try_region(
                    aligned_offset + page_size,
                    aligned_region_bytes,
                    &misaligned_region,
                );
                assert(region_created);

                VirtualArrayView!OverAlignedViewValue misaligned_view;
                const misaligned_view_created = VirtualArrayView!OverAlignedViewValue.try_create(
                    misaligned_region,
                    1,
                    page_size,
                    &misaligned_view,
                );
                assert(!misaligned_view_created);
                assert(misaligned_view.inert);
            }
        }
    }
}
