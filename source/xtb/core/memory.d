module xtb.core.memory;

nothrow @nogc:

import core.stdc.stdlib : free, malloc, realloc;

version (Posix)
    import core.sys.posix.stdlib : posix_memalign;
else
    import core.stdc.stdlib : aligned_alloc;
import core.stdc.string : memcpy, memset;
import xtb.core.panic : panic;
version (XTB_Checked)
    import xtb.core.panic : require;
import xtb.core.numeric : multiplyOverflows;

alias Allocator = extern (C) void* function(
    void* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
);

private __gshared Allocator mallocAllocatorSlot = &mallocAllocatorProcedure;

Allocator* mallocAllocator()
{
    return &mallocAllocatorSlot;
}

private bool isPowerOfTwo(size_t value) pure @safe
{
    return value != 0 && (value & (value - 1)) == 0;
}

private size_t normalizedAlignment(size_t alignment) pure @safe
{
    const minimum = (void*).alignof;
    return alignment < minimum ? minimum : alignment;
}

private extern (C) void* mallocAllocatorProcedure(
    void*,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
)
{
    alignment = normalizedAlignment(alignment);
    if (!isPowerOfTwo(alignment))
        return null;

    if (newSize == 0)
    {
        free(oldPointer);
        return null;
    }

    if (alignment <= (void*).alignof)
        return realloc(oldPointer, newSize);

    void* replacement;
    version (Posix)
    {
        if (posix_memalign(&replacement, alignment, newSize) != 0)
            replacement = null;
    }
    else
    {
        size_t allocationSize;
        const remainder = newSize & (alignment - 1);
        if (remainder != 0)
        {
            const addition = alignment - remainder;
            if (addition > size_t.max - newSize)
                return null;
            allocationSize = newSize + addition;
        }
        else
            allocationSize = newSize;
        replacement = aligned_alloc(alignment, allocationSize);
    }
    if (replacement is null)
        return null;

    if (oldPointer !is null)
    {
        const copySize = oldSize < newSize ? oldSize : newSize;
        if (copySize != 0)
            memcpy(replacement, oldPointer, copySize);
        free(oldPointer);
    }
    return replacement;
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

T* tryAllocate(T)(Allocator* allocator, size_t count = 1)
{
    if (multiplyOverflows(T.sizeof, count))
        return null;
    return cast(T*) tryAllocate(allocator, T.sizeof * count, T.alignof);
}

T* allocate(T)(Allocator* allocator, size_t count = 1)
{
    if (multiplyOverflows(T.sizeof, count))
        panic("allocation size overflow");
    return cast(T*) allocate(allocator, T.sizeof * count, T.alignof);
}

T* tryReallocate(T)(
    Allocator* allocator,
    T* oldPointer,
    size_t oldCount,
    size_t newCount,
) if (__traits(isPOD, T))
{
    if (multiplyOverflows(T.sizeof, oldCount) ||
        multiplyOverflows(T.sizeof, newCount))
        return null;
    return cast(T*) tryReallocate(
        allocator,
        newCount * T.sizeof,
        oldPointer,
        oldCount * T.sizeof,
        T.alignof,
    );
}

T* reallocate(T)(
    Allocator* allocator,
    T* oldPointer,
    size_t oldCount,
    size_t newCount,
) if (__traits(isPOD, T))
{
    if (multiplyOverflows(T.sizeof, oldCount) ||
        multiplyOverflows(T.sizeof, newCount))
        panic("reallocation size overflow");
    return cast(T*) reallocate(
        allocator,
        newCount * T.sizeof,
        oldPointer,
        oldCount * T.sizeof,
        T.alignof,
    );
}

T* tryAllocateZeroed(T)(Allocator* allocator, size_t count = 1) if (__traits(isPOD, T))
{
    T* result = allocator.tryAllocate!T(count);
    if (result !is null)
        memset(result, 0, T.sizeof * count);
    return result;
}

T* allocateZeroed(T)(Allocator* allocator, size_t count = 1) if (__traits(isPOD, T))
{
    T* result = allocator.allocate!T(count);
    if (result !is null)
        memset(result, 0, T.sizeof * count);
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

void deallocate(T)(Allocator* allocator, T* pointer, size_t count = 1)
{
    if (multiplyOverflows(T.sizeof, count))
        panic("deallocation size overflow");
    deallocate(allocator, pointer, T.sizeof * count, T.alignof);
}

struct AllocationRecord
{
    void* pointer;
    size_t size;
    size_t alignment;
}

struct AllocatorStats
{
    size_t allocationCalls;
    size_t reallocationCalls;
    size_t deallocationCalls;
    size_t failedCalls;
    size_t invalidCalls;
    size_t outstandingAllocations;
    size_t outstandingBytes;
    size_t peakOutstandingBytes;
}

struct InstrumentedAllocator
{
nothrow @nogc:

    Allocator allocator;
    private Allocator* backing;
    private AllocationRecord[] records;
    private AllocatorStats stats_;
    private size_t successesBeforeFailure = size_t.max;

    @disable this(this);

    static InstrumentedAllocator create(
        Allocator* backing,
        return scope AllocationRecord[] records,
    )
    {
        version (XTB_Checked)
            require(backing !is null && *backing !is null,
                "instrumented allocator requires a valid backing allocator");
        InstrumentedAllocator result;
        result.allocator = &instrumentedAllocatorProcedure;
        result.backing = backing;
        result.records = records;
        foreach (ref record; records)
            record = AllocationRecord.init;
        return result;
    }

    Allocator* handle() return
    {
        return &allocator;
    }

    AllocatorStats stats() const pure @safe
    {
        return stats_;
    }

    void failAfter(size_t successfulCalls)
    {
        successesBeforeFailure = successfulCalls;
    }

    void allowAllocations()
    {
        successesBeforeFailure = size_t.max;
    }

    bool clean() const pure @safe
    {
        return stats_.outstandingAllocations == 0 && stats_.outstandingBytes == 0;
    }
}

static assert(InstrumentedAllocator.allocator.offsetof == 0);

private AllocationRecord* findRecord(
    ref InstrumentedAllocator allocator,
    void* pointer,
)
{
    foreach (ref record; allocator.records)
        if (record.pointer is pointer)
            return &record;
    return null;
}

private AllocationRecord* freeRecord(ref InstrumentedAllocator allocator)
{
    foreach (ref record; allocator.records)
        if (record.pointer is null)
            return &record;
    return null;
}

private extern (C) void* instrumentedAllocatorProcedure(
    void* context,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
)
{
    InstrumentedAllocator* allocator = cast(InstrumentedAllocator*) context;
    AllocationRecord* oldRecord;
    if (oldPointer !is null)
    {
        oldRecord = findRecord(*allocator, oldPointer);
        if (oldRecord is null || oldRecord.size != oldSize ||
            oldRecord.alignment != alignment)
        {
            ++allocator.stats_.invalidCalls;
            return null;
        }
    }
    else if (oldSize != 0)
    {
        ++allocator.stats_.invalidCalls;
        return null;
    }

    if (newSize == 0)
    {
        if (oldPointer is null)
            return null;
        ++allocator.stats_.deallocationCalls;
        (*allocator.backing)(allocator.backing, 0, oldPointer, oldSize, alignment);
        --allocator.stats_.outstandingAllocations;
        allocator.stats_.outstandingBytes -= oldSize;
        *oldRecord = AllocationRecord.init;
        return null;
    }

    if (allocator.successesBeforeFailure == 0)
    {
        ++allocator.stats_.failedCalls;
        return null;
    }

    AllocationRecord* destinationRecord = oldRecord;
    if (destinationRecord is null)
    {
        destinationRecord = freeRecord(*allocator);
        if (destinationRecord is null)
        {
            ++allocator.stats_.failedCalls;
            return null;
        }
        ++allocator.stats_.allocationCalls;
    }
    else
        ++allocator.stats_.reallocationCalls;

    void* replacement = (*allocator.backing)(
        allocator.backing,
        newSize,
        oldPointer,
        oldSize,
        alignment,
    );
    if (replacement is null)
    {
        ++allocator.stats_.failedCalls;
        return null;
    }
    if (allocator.successesBeforeFailure != size_t.max)
        --allocator.successesBeforeFailure;

    if (oldRecord is null)
    {
        ++allocator.stats_.outstandingAllocations;
        allocator.stats_.outstandingBytes += newSize;
    }
    else
    {
        allocator.stats_.outstandingBytes -= oldSize;
        allocator.stats_.outstandingBytes += newSize;
    }
    if (allocator.stats_.outstandingBytes > allocator.stats_.peakOutstandingBytes)
        allocator.stats_.peakOutstandingBytes = allocator.stats_.outstandingBytes;
    *destinationRecord = AllocationRecord(replacement, newSize, alignment);
    return replacement;
}

unittest
{
    Allocator* allocator = mallocAllocator();
    int* values = allocator.allocate!int(4);
    assert(values !is null);
    foreach (i; 0 .. 4)
        values[i] = cast(int) i;

    values = cast(int*) allocator.reallocate(
        8 * int.sizeof,
        values,
        4 * int.sizeof,
        int.alignof,
    );
    foreach (i; 0 .. 4)
        assert(values[i] == cast(int) i);
    allocator.deallocate(values, 8);

    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(allocator, records[]);
    int* trackedValues = tracked.handle.allocateZeroed!int(4);
    assert(trackedValues[3] == 0);
    assert(tracked.stats.outstandingBytes == 4 * int.sizeof);
    tracked.failAfter(0);
    assert(tracked.handle.tryAllocate!int() is null);
    assert(tracked.stats.failedCalls == 1);
    tracked.handle.deallocate(trackedValues, 4);
    assert(tracked.clean);
}

unittest
{
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

    static assert(__traits(isPOD, PodWithInitializer));
    static assert(!__traits(compiles,
            mallocAllocator().allocateZeroed!Owning()));
    static assert(!__traits(compiles,
            mallocAllocator().reallocate!Owning(null, 0, 1)));

    PodWithInitializer* value = mallocAllocator()
        .allocateZeroed!PodWithInitializer();
    assert(value.value == 0);
    mallocAllocator().deallocate(value);
}
