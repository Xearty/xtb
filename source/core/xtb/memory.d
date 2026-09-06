module xtb.memory;

nothrow @nogc:

import core_lifetime = core.lifetime;
import core.stdc.string;

import xtb.lifetime;
import xtb.numeric;
import xtb.panic;
import xtb.types;

/// Type-erased allocator callback used by XTB ownership APIs.
///
/// `allocator` is the address of the `Allocator` slot exposed by the owning
/// allocator object. `new_size == 0` requests deallocation of `old_pointer`.
alias Allocator = extern (C) void* function(
    void* allocator,
    usize new_size,
    void* old_pointer,
    usize old_size,
    usize alignment,
) nothrow @nogc;

private bool is_power_of_two(usize value) pure @safe
{
    return value != 0 && (value & (value - 1)) == 0;
}

void* try_reallocate(
    Allocator* allocator,
    usize new_size,
    void* old_pointer,
    usize old_size,
    usize alignment,
)
{
    if (
        allocator is null
        || *allocator is null
        || !is_power_of_two(alignment)
        || (old_pointer is null && old_size != 0)
    )
    {
        return null;
    }

    return (*allocator)(allocator, new_size, old_pointer, old_size, alignment);
}

void* reallocate(
    Allocator* allocator,
    usize new_size,
    void* old_pointer,
    usize old_size,
    usize alignment,
)
{
    void* result = try_reallocate(
        allocator,
        new_size,
        old_pointer,
        old_size,
        alignment,
    );
    if (new_size != 0 && result is null) panic("allocation failed");

    return result;
}

void* try_allocate(Allocator* allocator, usize size, usize alignment)
{
    return try_reallocate(allocator, size, null, 0, alignment);
}

void* allocate(Allocator* allocator, usize size, usize alignment)
{
    return reallocate(allocator, size, null, 0, alignment);
}

/// Attempts to reserve uninitialized storage for one `T`.
T* try_allocate(T)(Allocator* allocator)
{
    return cast(T*) try_allocate(allocator, T.sizeof, T.alignof);
}

/// Reserves uninitialized storage for one `T`, panicking on failure.
T* allocate(T)(Allocator* allocator)
{
    return cast(T*) allocate(allocator, T.sizeof, T.alignof);
}

/// Attempts to reserve uninitialized storage for `length` contiguous `T`s.
T[] try_allocate_array(T)(Allocator* allocator, usize length)
{
    if (multiply_overflows(T.sizeof, length)) return null;

    T* data = cast(T*) try_allocate(
        allocator,
        T.sizeof * length,
        T.alignof,
    );
    if (length != 0 && data is null) return null;

    return data[0 .. length];
}

/// Reserves uninitialized storage for `length` contiguous `T`s.
T[] allocate_array(T)(Allocator* allocator, usize length)
{
    if (multiply_overflows(T.sizeof, length)) panic("allocation size overflow");

    T* data = cast(T*) allocate(
        allocator,
        T.sizeof * length,
        T.alignof,
    );
    return data[0 .. length];
}

T[] try_reallocate_array(T)(Allocator* allocator, T[] old_values, usize new_length)
if (__traits(isPOD, T))
{
    if (
        multiply_overflows(T.sizeof, old_values.length)
        || multiply_overflows(T.sizeof, new_length)
    )
    {
        return null;
    }

    T* data = cast(T*) try_reallocate(
        allocator,
        new_length * T.sizeof,
        old_values.ptr,
        old_values.length * T.sizeof,
        T.alignof,
    );
    if (new_length != 0 && data is null) return null;

    return data[0 .. new_length];
}

T[] reallocate_array(T)(Allocator* allocator, T[] old_values, usize new_length)
if (__traits(isPOD, T))
{
    if (
        multiply_overflows(T.sizeof, old_values.length)
        || multiply_overflows(T.sizeof, new_length)
    )
    {
        panic("reallocation size overflow");
    }

    T* data = cast(T*) reallocate(
        allocator,
        new_length * T.sizeof,
        old_values.ptr,
        old_values.length * T.sizeof,
        T.alignof,
    );
    return data[0 .. new_length];
}

T* try_allocate_zeroed(T)(Allocator* allocator)
if (__traits(isPOD, T))
{
    T* result = allocator.try_allocate!T();
    if (result !is null) memset(result, 0, T.sizeof);

    return result;
}

T* allocate_zeroed(T)(Allocator* allocator)
if (__traits(isPOD, T))
{
    T* result = allocator.allocate!T();
    memset(result, 0, T.sizeof);
    return result;
}

T[] try_allocate_zeroed_array(T)(Allocator* allocator, usize length)
if (__traits(isPOD, T))
{
    T[] result = allocator.try_allocate_array!T(length);
    if (result.ptr !is null) memset(result.ptr, 0, T.sizeof * result.length);

    return result;
}

T[] allocate_zeroed_array(T)(Allocator* allocator, usize length)
if (__traits(isPOD, T))
{
    T[] result = allocator.allocate_array!T(length);
    if (result.ptr !is null) memset(result.ptr, 0, T.sizeof * result.length);

    return result;
}

/// Attempts to allocate one `T` and establish its `T.init` lifetime.
T* try_allocate_init(T)(Allocator* allocator)
{
    T* result = allocator.try_allocate!T();
    if (result !is null) core_lifetime.emplace(result);

    return result;
}

/// Allocates one `T` and establishes its `T.init` lifetime.
T* allocate_init(T)(Allocator* allocator)
{
    T* result = allocator.allocate!T();
    core_lifetime.emplace(result);
    return result;
}

/// Attempts to allocate an array and initialize every element to `T.init`.
T[] try_allocate_init_array(T)(Allocator* allocator, usize length)
{
    T[] result = allocator.try_allocate_array!T(length);
    foreach (index; 0 .. result.length)
        core_lifetime.emplace(result.ptr + index);

    return result;
}

/// Allocates an array and initializes every element to `T.init`.
T[] allocate_init_array(T)(Allocator* allocator, usize length)
{
    T[] result = allocator.allocate_array!T(length);
    foreach (index; 0 .. result.length)
        core_lifetime.emplace(result.ptr + index);

    return result;
}

/// Attempts to allocate and construct one `T` with `emplace`.
T* try_create(T, Args...)(Allocator* allocator, auto ref Args arguments)
{
    T* result = allocator.try_allocate!T();
    if (result !is null) core_lifetime.emplace(result, core_lifetime.forward!arguments);

    return result;
}

/// Allocates and constructs one `T` with `emplace`.
T* create(T, Args...)(Allocator* allocator, auto ref Args arguments)
{
    T* result = allocator.allocate!T();
    core_lifetime.emplace(result, core_lifetime.forward!arguments);
    return result;
}

void deallocate(Allocator* allocator, void* pointer, usize old_size, usize alignment)
{
    if (pointer is null) return;

    require(allocator !is null && *allocator !is null, "invalid allocator");
    (*allocator)(allocator, 0, pointer, old_size, alignment);
}

/// Releases raw storage for one `T` without running destruction.
void deallocate(T)(Allocator* allocator, T* pointer)
{
    deallocate(allocator, cast(void*) pointer, T.sizeof, T.alignof);
}

/// Releases raw array storage without destroying its elements.
void deallocate_array(T)(Allocator* allocator, T[] values)
{
    if (multiply_overflows(T.sizeof, values.length)) panic("deallocation size overflow");

    deallocate(
        allocator,
        cast(void*) values.ptr,
        T.sizeof * values.length,
        T.alignof,
    );
}

/// Finalizes one initialized `T` according to its lifetime domain and releases
/// the raw allocation. Explicit-deinit values use XTB `deinit`; legacy/lexical
/// destructor-bearing values retain D destruction until their owning API is
/// migrated or deliberately kept RAII.
void dispose(T)(Allocator* allocator, T* pointer)
{
    if (pointer is null) return;

    static if (needs_finalization!T)
    {
        finalize(*pointer);
    }

    allocator.deallocate(pointer);
}

/// Finalizes initialized array elements in reverse order and releases storage.
void dispose_array(T)(Allocator* allocator, T[] values)
{
    static if (needs_finalization!T)
    {
        foreach_reverse (ref value; values)
            finalize(value);
    }

    allocator.deallocate_array(values);
}

version (unittest)
{
    import xtb.allocators.instrumented;
    import xtb.allocators.malloc;
}

unittest
{
    Allocator* allocator = mallocAllocator();

    i32* single = allocator.allocate!i32();
    assert(single !is null);
    *single = 42;
    assert(*single == 42);
    allocator.deallocate(single);

    i32[] values = allocator.allocate_array!i32(4);
    assert(values.length == 4);
    foreach (index; 0 .. values.length)
        values[index] = cast(i32) index;

    values = allocator.reallocate_array(values, 8);
    assert(values.length == 8);
    foreach (index; 0 .. 4)
        assert(values[index] == cast(i32) index);
    allocator.deallocate_array(values);

    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(allocator, records[]);
    i32[] tracked_values = tracked.allocator.allocate_zeroed_array!i32(4);
    assert(tracked_values.length == 4);
    assert(tracked_values[3] == 0);
    assert(tracked.stats.outstandingBytes == 4 * i32.sizeof);

    tracked.failAfter(0);
    assert(tracked.allocator.try_allocate!i32() is null);
    assert(tracked.stats.failedCalls == 1);

    tracked.allocator.deallocate_array(tracked_values);
    assert(tracked.clean);
}

unittest
{
    struct MoveOnly
    {
        i32 value;

        @disable this(this);
    }

    struct PODWithInitializer
    {
    nothrow @nogc:

        u32 value = 0xFFFF_FFFF;
    }

    struct Owning
    {
    nothrow @nogc:

        void* pointer;

        ~this()
        {
        }
    }

    struct Constructed
    {
    nothrow @nogc:

        i32 value;
        i32* destroyed;

        this(i32 value, i32* destroyed)
        {
            this.value = value;
            this.destroyed = destroyed;
        }

        ~this()
        {
            if (this.destroyed !is null) ++*this.destroyed;
        }
    }

    struct TrackedInit
    {
    nothrow @nogc:

        i32* destroyed;

        ~this()
        {
            if (this.destroyed !is null) ++*this.destroyed;
        }
    }

    struct ExplicitOwner
    {
    nothrow @nogc:

        i32* deinitialized;

        void deinit()
        {
            if (this.deinitialized !is null) ++*this.deinitialized;
        }
    }

    static assert(__traits(isPOD, PODWithInitializer));
    static assert(!__traits(compiles, mallocAllocator().allocate_zeroed!Owning()));
    static assert(!__traits(compiles, mallocAllocator().allocate_zeroed_array!Owning(2)));
    static assert(!__traits(
        compiles,
        mallocAllocator().reallocate_array!Owning(cast(Owning[]) null, 1),
    ));
    static assert(!__traits(compiles, mallocAllocator().allocate!i32(4)));

    PODWithInitializer* zeroed = mallocAllocator().allocate_zeroed!PODWithInitializer();
    assert(zeroed.value == 0);
    mallocAllocator().deallocate(zeroed);

    PODWithInitializer* initialized = mallocAllocator().allocate_init!PODWithInitializer();
    assert(initialized.value == PODWithInitializer.init.value);
    mallocAllocator().deallocate(initialized);

    PODWithInitializer source;
    source.value = 17;
    PODWithInitializer* copied = mallocAllocator().create!PODWithInitializer(source);
    assert(copied.value == 17);
    mallocAllocator().dispose(copied);

    MoveOnly movable;
    movable.value = 29;
    MoveOnly* moved = mallocAllocator().create!MoveOnly(core_lifetime.move(movable));
    assert(moved.value == 29);
    mallocAllocator().dispose(moved);

    PODWithInitializer[] initialized_values = mallocAllocator()
        .allocate_init_array!PODWithInitializer(3);
    assert(initialized_values.length == 3);
    foreach (value; initialized_values)
        assert(value.value == PODWithInitializer.init.value);
    mallocAllocator().deallocate_array(initialized_values);

    PODWithInitializer[] zeroed_values = mallocAllocator()
        .allocate_zeroed_array!PODWithInitializer(3);
    foreach (value; zeroed_values)
        assert(value.value == 0);
    mallocAllocator().deallocate_array(zeroed_values);

    i32 destroyed;
    Constructed* constructed = mallocAllocator().create!Constructed(73, &destroyed);
    assert(constructed.value == 73);
    assert(constructed.destroyed is &destroyed);
    mallocAllocator().dispose(constructed);
    assert(destroyed == 1);

    AllocationRecord[2] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    failing.failAfter(0);
    assert(failing.allocator.try_create!Constructed(1, &destroyed) is null);

    TrackedInit[] tracked = mallocAllocator().allocate_init_array!TrackedInit(3);
    foreach (ref value; tracked)
        value.destroyed = &destroyed;
    mallocAllocator().dispose_array(tracked);
    assert(destroyed == 4);

    i32 explicit_deinits;
    ExplicitOwner* explicit_owner = mallocAllocator().allocate_init!ExplicitOwner();
    explicit_owner.deinitialized = &explicit_deinits;
    mallocAllocator().dispose(explicit_owner);
    assert(explicit_deinits == 1);

    ExplicitOwner[] explicit_owners = mallocAllocator().allocate_init_array!ExplicitOwner(3);
    foreach (ref owner; explicit_owners)
        owner.deinitialized = &explicit_deinits;
    mallocAllocator().dispose_array(explicit_owners);
    assert(explicit_deinits == 4);
}
