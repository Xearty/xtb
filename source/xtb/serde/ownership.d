module xtb.serde.ownership;

nothrow @nogc:

import core.stdc.string : memcpy;
import xtb.core.memory : Allocator, tryAllocate;
import xtb.core.numeric : addOverflows;
import xtb.core.panic : require;

private struct AllocationHeader
{
    AllocationHeader* next;
    void* payload;
    size_t payloadSize;
    size_t payloadAlignment;
    size_t allocationSize;
    size_t allocationAlignment;
}

private struct AllocationTracker
{
nothrow @nogc:

    Allocator allocator;
    Allocator* backing;
    AllocationHeader* first;

    static AllocationTracker create(Allocator* backing)
    {
        AllocationTracker result;
        result.allocator = &trackingAllocatorProcedure;
        result.backing = backing;
        return result;
    }

    Allocator* handle() return
    {
        return &allocator;
    }

    void deinit()
    {
        AllocationHeader* allocation = first;
        while (allocation !is null)
        {
            AllocationHeader* next = allocation.next;
            (*backing)(backing, 0, allocation, allocation.allocationSize,
                allocation.allocationAlignment);
            allocation = next;
        }
        allocator = null;
        backing = null;
        first = null;
    }
}

static assert(AllocationTracker.allocator.offsetof == 0);

struct Deserialized(T)
{
nothrow @nogc:

    private AllocationTracker tracker_;
    private T* value_;

    @disable this(this);

    ~this()
    {
        deinit();
    }

    bool empty() const pure @safe
    {
        return value_ is null;
    }

    ref T value() return @system
    {
        require(value_ !is null, "empty deserialized value");
        return *value_;
    }

    ref const(T) value() const return @system
    {
        require(value_ !is null, "empty deserialized value");
        return *value_;
    }

    T* pointer() return @system
    {
        return value_;
    }

    void deinit()
    {
        tracker_.deinit();
        value_ = null;
    }
}

package(xtb.serde) bool prepareDeserialized(T)(
    Allocator* allocator,
    Deserialized!T* output,
    T** value,
)
{
    require(allocator !is null && *allocator !is null,
        "serde requires a valid allocator");
    require(output !is null, "deserialized output pointer is null");
    require(value !is null, "deserialized value pointer is null");
    output.deinit();
    output.tracker_ = AllocationTracker.create(allocator);
    T* created = output.tracker_.handle.tryAllocate!T();
    if (created is null)
    {
        output.tracker_.deinit();
        *value = null;
        return false;
    }
    *created = T.init;
    output.value_ = created;
    *value = created;
    return true;
}

package(xtb.serde) Allocator* deserializationAllocator(T)(
    Deserialized!T* output,
)
{
    require(output !is null && output.value_ !is null,
        "deserialized output is not prepared");
    return output.tracker_.handle;
}

package(xtb.serde) void abandonDeserialized(T)(Deserialized!T* output)
{
    require(output !is null, "deserialized output pointer is null");
    output.deinit();
}

private AllocationHeader* findAllocation(
    ref AllocationTracker tracker,
    void* payload,
    AllocationHeader** previous,
)
{
    AllocationHeader* prior;
    for (AllocationHeader* allocation = tracker.first; allocation !is null; allocation = allocation
        .next)
    {
        if (allocation.payload is payload)
        {
            *previous = prior;
            return allocation;
        }
        prior = allocation;
    }
    *previous = null;
    return null;
}

private extern (C) void* trackingAllocatorProcedure(
    void* context,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
)
{
    AllocationTracker* tracker = cast(AllocationTracker*) context;
    if (tracker is null || tracker.backing is null || *tracker.backing is null ||
        !isPowerOfTwo(alignment))
        return null;

    AllocationHeader* previous;
    AllocationHeader* oldAllocation;
    if (oldPointer !is null)
    {
        oldAllocation = findAllocation(*tracker, oldPointer, &previous);
        if (oldAllocation is null || oldAllocation.payloadSize != oldSize ||
            oldAllocation.payloadAlignment != alignment)
            return null;
    }
    else if (oldSize != 0)
        return null;

    if (newSize == 0)
    {
        if (oldAllocation is null)
            return null;
        unlink(*tracker, oldAllocation, previous);
        return null;
    }

    const padding = alignment - 1;
    if (addOverflows(AllocationHeader.sizeof, padding) ||
        addOverflows(AllocationHeader.sizeof + padding, newSize))
        return null;
    const allocationSize = AllocationHeader.sizeof + padding + newSize;
    const allocationAlignment = alignment > AllocationHeader.alignof
        ? alignment : AllocationHeader.alignof;
    AllocationHeader* allocation = cast(AllocationHeader*)(*tracker.backing)(
        tracker.backing,
        allocationSize,
        null,
        0,
        allocationAlignment,
    );
    if (allocation is null)
        return null;

    const start = cast(size_t)(cast(ubyte*) allocation + AllocationHeader.sizeof);
    const payloadAddress = (start + padding) & ~padding;
    *allocation = AllocationHeader.init;
    allocation.payload = cast(void*) payloadAddress;
    allocation.payloadSize = newSize;
    allocation.payloadAlignment = alignment;
    allocation.allocationSize = allocationSize;
    allocation.allocationAlignment = allocationAlignment;
    allocation.next = tracker.first;
    tracker.first = allocation;

    if (oldAllocation !is null)
    {
        const amount = oldSize < newSize ? oldSize : newSize;
        if (amount != 0)
            memcpy(allocation.payload, oldPointer, amount);
        oldAllocation = findAllocation(*tracker, oldPointer, &previous);
        unlink(*tracker, oldAllocation, previous);
    }
    return allocation.payload;
}

private void unlink(
    ref AllocationTracker tracker,
    AllocationHeader* allocation,
    AllocationHeader* previous,
)
{
    if (previous is null)
        tracker.first = allocation.next;
    else
        previous.next = allocation.next;
    (*tracker.backing)(tracker.backing, 0, allocation,
        allocation.allocationSize, allocation.allocationAlignment);
}

private bool isPowerOfTwo(size_t value) pure @safe
{
    return value != 0 && (value & (value - 1)) == 0;
}
