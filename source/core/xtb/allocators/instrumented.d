module xtb.allocators.instrumented;

nothrow @nogc:

import xtb.memory : Allocator, deallocate, tryReallocate;

version (XTB_Checked) import xtb.panic : require;

/// One live allocation tracked by `InstrumentedAllocator`.
struct AllocationRecord
{
    void* pointer;
    size_t size;
    size_t alignment;
}

/// Allocation counters exposed by `InstrumentedAllocator`.
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

/// Caller-storage-backed allocator wrapper for deterministic tests/diagnostics.
struct InstrumentedAllocator
{
nothrow @nogc:

    private Allocator allocator_;
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
        result.allocator_ = &instrumentedAllocatorProcedure;
        result.backing = backing;
        result.records = records;
        foreach (ref record; records)
            record = AllocationRecord.init;
        return result;
    }

    Allocator* allocator() return
    {
        return &allocator_;
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

static assert(InstrumentedAllocator.allocator_.offsetof == 0);

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
) @system
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
        allocator.backing.deallocate(oldPointer, oldSize, alignment);
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

    void* replacement = allocator.backing.tryReallocate(
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
    import xtb.allocators.malloc : mallocAllocator;
    import xtb.memory : allocateZeroedArray, deallocateArray, tryAllocate;

    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    int[] values = tracked.allocator.allocateZeroedArray!int(4);
    assert(values.length == 4);
    assert(values[3] == 0);
    assert(tracked.stats.outstandingBytes == 4 * int.sizeof);
    tracked.failAfter(0);
    assert(tracked.allocator.tryAllocate!int() is null);
    assert(tracked.stats.failedCalls == 1);
    tracked.allocator.deallocateArray(values);
    assert(tracked.clean);
}
