module xtb.memory;

nothrow @nogc:

import core.lifetime : emplace, forward;
import core.stdc.string : memset;
import xtb.lifetime : finalize, needs_finalization;
import xtb.panic : panic;

version (XTB_Checked) import xtb.panic : require;
import xtb.numeric : multiply_overflows;

/// Type-erased allocator callback used by XTB ownership APIs.
///
/// `allocator` is the address of the `Allocator` slot exposed by the owning
/// allocator object. `newSize == 0` requests deallocation of `oldPointer`.
alias Allocator = extern (C) void* function(
    void* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
);

private bool isPowerOfTwo(size_t value) pure @safe
{
    return value != 0 && (value & (value - 1)) == 0;
}

void* tryReallocate(
    Allocator* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
)
{
    if (allocator is null || *allocator is null || !isPowerOfTwo(alignment) ||
        (oldPointer is null && oldSize != 0))
        return null;
    return (*allocator)(allocator, newSize, oldPointer, oldSize, alignment);
}

void* reallocate(
    Allocator* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
)
{
    void* result = tryReallocate(
        allocator,
        newSize,
        oldPointer,
        oldSize,
        alignment,
    );
    if (newSize != 0 && result is null)
        panic("allocation failed");
    return result;
}

void* tryAllocate(
    Allocator* allocator,
    size_t size,
    size_t alignment,
)
{
    return tryReallocate(allocator, size, null, 0, alignment);
}

void* allocate(
    Allocator* allocator,
    size_t size,
    size_t alignment,
)
{
    return reallocate(allocator, size, null, 0, alignment);
}

/// Attempts to reserve uninitialized storage for one `T`.
T* tryAllocate(T)(Allocator* allocator)
{
    return cast(T*) tryAllocate(allocator, T.sizeof, T.alignof);
}

/// Reserves uninitialized storage for one `T`, panicking on failure.
T* allocate(T)(Allocator* allocator)
{
    return cast(T*) allocate(allocator, T.sizeof, T.alignof);
}

/// Attempts to reserve uninitialized storage for `length` contiguous `T`s.
T[] tryAllocateArray(T)(Allocator* allocator, size_t length)
{
    if (multiply_overflows(T.sizeof, length))
        return null;
    T* data = cast(T*) tryAllocate(
        allocator,
        T.sizeof * length,
        T.alignof,
    );
    if (length != 0 && data is null)
        return null;
    return data[0 .. length];
}

/// Reserves uninitialized storage for `length` contiguous `T`s.
T[] allocateArray(T)(Allocator* allocator, size_t length)
{
    if (multiply_overflows(T.sizeof, length))
        panic("allocation size overflow");
    T* data = cast(T*) allocate(
        allocator,
        T.sizeof * length,
        T.alignof,
    );
    return data[0 .. length];
}

T[] tryReallocateArray(T)(
    Allocator* allocator,
    T[] oldValues,
    size_t newLength,
) if (__traits(isPOD, T))
{
    if (multiply_overflows(T.sizeof, oldValues.length) ||
        multiply_overflows(T.sizeof, newLength))
        return null;
    T* data = cast(T*) tryReallocate(
        allocator,
        newLength * T.sizeof,
        oldValues.ptr,
        oldValues.length * T.sizeof,
        T.alignof,
    );
    if (newLength != 0 && data is null)
        return null;
    return data[0 .. newLength];
}

T[] reallocateArray(T)(
    Allocator* allocator,
    T[] oldValues,
    size_t newLength,
) if (__traits(isPOD, T))
{
    if (multiply_overflows(T.sizeof, oldValues.length) ||
        multiply_overflows(T.sizeof, newLength))
        panic("reallocation size overflow");
    T* data = cast(T*) reallocate(
        allocator,
        newLength * T.sizeof,
        oldValues.ptr,
        oldValues.length * T.sizeof,
        T.alignof,
    );
    return data[0 .. newLength];
}

T* tryAllocateZeroed(T)(Allocator* allocator) if (__traits(isPOD, T))
{
    T* result = allocator.tryAllocate!T();
    if (result !is null)
        memset(result, 0, T.sizeof);
    return result;
}

T* allocateZeroed(T)(Allocator* allocator) if (__traits(isPOD, T))
{
    T* result = allocator.allocate!T();
    memset(result, 0, T.sizeof);
    return result;
}

T[] tryAllocateZeroedArray(T)(
    Allocator* allocator,
    size_t length,
) if (__traits(isPOD, T))
{
    T[] result = allocator.tryAllocateArray!T(length);
    if (result.ptr !is null)
        memset(result.ptr, 0, T.sizeof * result.length);
    return result;
}

T[] allocateZeroedArray(T)(
    Allocator* allocator,
    size_t length,
) if (__traits(isPOD, T))
{
    T[] result = allocator.allocateArray!T(length);
    if (result.ptr !is null)
        memset(result.ptr, 0, T.sizeof * result.length);
    return result;
}

/// Attempts to allocate one `T` and establish its `T.init` lifetime.
T* tryAllocateInit(T)(Allocator* allocator)
{
    T* result = allocator.tryAllocate!T();
    if (result !is null)
        emplace(result);
    return result;
}

/// Allocates one `T` and establishes its `T.init` lifetime.
T* allocateInit(T)(Allocator* allocator)
{
    T* result = allocator.allocate!T();
    emplace(result);
    return result;
}

/// Attempts to allocate an array and initialize every element to `T.init`.
T[] tryAllocateInitArray(T)(Allocator* allocator, size_t length)
{
    T[] result = allocator.tryAllocateArray!T(length);
    foreach (index; 0 .. result.length)
        emplace(result.ptr + index);
    return result;
}

/// Allocates an array and initializes every element to `T.init`.
T[] allocateInitArray(T)(Allocator* allocator, size_t length)
{
    T[] result = allocator.allocateArray!T(length);
    foreach (index; 0 .. result.length)
        emplace(result.ptr + index);
    return result;
}

/// Attempts to allocate and construct one `T` with `emplace`.
T* tryCreate(T, Args...)(
    Allocator* allocator,
    auto ref Args arguments,
)
{
    T* result = allocator.tryAllocate!T();
    if (result !is null)
        emplace(result, forward!arguments);
    return result;
}

/// Allocates and constructs one `T` with `emplace`.
T* create(T, Args...)(
    Allocator* allocator,
    auto ref Args arguments,
)
{
    T* result = allocator.allocate!T();
    emplace(result, forward!arguments);
    return result;
}

void deallocate(
    Allocator* allocator,
    void* pointer,
    size_t oldSize,
    size_t alignment,
)
{
    if (pointer is null)
        return;
    version (XTB_Checked)
        require(allocator !is null && *allocator !is null, "invalid allocator");
    (*allocator)(allocator, 0, pointer, oldSize, alignment);
}

/// Releases raw storage for one `T` without running destruction.
void deallocate(T)(Allocator* allocator, T* pointer)
{
    deallocate(allocator, cast(void*) pointer, T.sizeof, T.alignof);
}

/// Releases raw array storage without destroying its elements.
void deallocateArray(T)(Allocator* allocator, T[] values)
{
    if (multiply_overflows(T.sizeof, values.length))
        panic("deallocation size overflow");
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
    if (pointer is null)
        return;
    static if (needs_finalization!T)
        finalize(*pointer);
    allocator.deallocate(pointer);
}

/// Finalizes initialized array elements in reverse order and releases storage.
void disposeArray(T)(Allocator* allocator, T[] values)
{
    static if (needs_finalization!T)
    {
        foreach_reverse (ref value; values)
            finalize(value);
    }
    allocator.deallocateArray(values);
}

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : mallocAllocator;

    Allocator* allocator = mallocAllocator();

    int* single = allocator.allocate!int();
    assert(single !is null);
    *single = 42;
    assert(*single == 42);
    allocator.deallocate(single);

    int[] values = allocator.allocateArray!int(4);
    assert(values.length == 4);
    foreach (index; 0 .. values.length)
        values[index] = cast(int) index;

    values = allocator.reallocateArray(values, 8);
    assert(values.length == 8);
    foreach (index; 0 .. 4)
        assert(values[index] == cast(int) index);
    allocator.deallocateArray(values);

    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(allocator, records[]);
    int[] trackedValues = tracked.allocator.allocateZeroedArray!int(4);
    assert(trackedValues.length == 4);
    assert(trackedValues[3] == 0);
    assert(tracked.stats.outstandingBytes == 4 * int.sizeof);
    tracked.failAfter(0);
    assert(tracked.allocator.tryAllocate!int() is null);
    assert(tracked.stats.failedCalls == 1);
    tracked.allocator.deallocateArray(trackedValues);
    assert(tracked.clean);
}

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : mallocAllocator;

    struct PodWithInitializer
    {
    nothrow @nogc:

        uint value = 0xFFFF_FFFF;
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

        int value;
        int* destroyed;

        this(int value, int* destroyed)
        {
            this.value = value;
            this.destroyed = destroyed;
        }

        ~this()
        {
            if (destroyed !is null)
                ++*destroyed;
        }
    }

    struct TrackedInit
    {
    nothrow @nogc:

        int* destroyed;

        ~this()
        {
            if (destroyed !is null)
                ++*destroyed;
        }
    }

    struct ExplicitOwner
    {
    nothrow @nogc:

        int* deinitialized;

        void deinit()
        {
            if (deinitialized !is null)
                ++*deinitialized;
        }
    }

    static assert(__traits(isPOD, PodWithInitializer));
    static assert(!__traits(compiles,
            mallocAllocator().allocateZeroed!Owning()));
    static assert(!__traits(compiles,
            mallocAllocator().allocateZeroedArray!Owning(2)));
    static assert(!__traits(compiles,
            mallocAllocator().reallocateArray!Owning(cast(Owning[]) null, 1)));
    static assert(!__traits(compiles,
            mallocAllocator().allocate!int(4)));

    PodWithInitializer* zeroed = mallocAllocator()
        .allocateZeroed!PodWithInitializer();
    assert(zeroed.value == 0);
    mallocAllocator().deallocate(zeroed);

    PodWithInitializer* initialized = mallocAllocator()
        .allocateInit!PodWithInitializer();
    assert(initialized.value == PodWithInitializer.init.value);
    mallocAllocator().deallocate(initialized);

    PodWithInitializer source;
    source.value = 17;
    PodWithInitializer* copied = mallocAllocator()
        .create!PodWithInitializer(source);
    assert(copied.value == 17);
    mallocAllocator().dispose(copied);

    struct MoveOnly
    {
        int value;

        @disable this(this);
    }

    import core.lifetime : move;

    MoveOnly movable;
    movable.value = 29;
    MoveOnly* moved = mallocAllocator().create!MoveOnly(move(movable));
    assert(moved.value == 29);
    mallocAllocator().dispose(moved);

    PodWithInitializer[] initializedValues = mallocAllocator()
        .allocateInitArray!PodWithInitializer(3);
    assert(initializedValues.length == 3);
    foreach (value; initializedValues)
        assert(value.value == PodWithInitializer.init.value);
    mallocAllocator().deallocateArray(initializedValues);

    PodWithInitializer[] zeroedValues = mallocAllocator()
        .allocateZeroedArray!PodWithInitializer(3);
    foreach (value; zeroedValues)
        assert(value.value == 0);
    mallocAllocator().deallocateArray(zeroedValues);

    int destroyed;
    Constructed* constructed = mallocAllocator()
        .create!Constructed(73, &destroyed);
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
    assert(failing.allocator.tryCreate!Constructed(1, &destroyed) is null);

    TrackedInit[] tracked = mallocAllocator().allocateInitArray!TrackedInit(3);
    foreach (ref value; tracked)
        value.destroyed = &destroyed;
    mallocAllocator().disposeArray(tracked);
    assert(destroyed == 4);

    int explicitDeinits;
    ExplicitOwner* explicitOwner = mallocAllocator().allocateInit!ExplicitOwner();
    explicitOwner.deinitialized = &explicitDeinits;
    mallocAllocator().dispose(explicitOwner);
    assert(explicitDeinits == 1);

    ExplicitOwner[] explicitOwners = mallocAllocator()
        .allocateInitArray!ExplicitOwner(3);
    foreach (ref owner; explicitOwners)
        owner.deinitialized = &explicitDeinits;
    mallocAllocator().disposeArray(explicitOwners);
    assert(explicitDeinits == 4);
}
