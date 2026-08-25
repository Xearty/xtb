module xtb.serde.ownership;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.stdc.string : memcpy;
import xtb.core.lifetime : needsDeinit;
import xtb.core.memory : Allocator, tryAllocateInit;
import xtb.core.numeric : addOverflows;

version (XTB_Checked) import xtb.core.panic : require;

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
    private Allocator allocator_;
    Allocator* backing;
    AllocationHeader* first;

    @disable this(this);
    @disable ref AllocationTracker opAssign(AllocationTracker source) return;

    void initialize(Allocator* backing)
    {
        version (XTB_Checked)
            require(this.backing is null && first is null,
                "allocation tracker is already initialized");
        allocator_ = &trackingAllocatorProcedure;
        this.backing = backing;
    }

    Allocator* allocator() return
    {
        return &allocator_;
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
        allocator_ = null;
        backing = null;
        first = null;
    }
}

static assert(AllocationTracker.allocator_.offsetof == 0);

/// Explicit owner for one document-owned decoded graph.
///
/// Ordinary scope exit does not release tracked allocations. Call `deinit`
/// after the decoded graph and every borrowed view into it are no longer used.
struct Deserialized(T)
{
nothrow @nogc:

    private AllocationTracker tracker_;
    private T* value_;

    @disable this(this);
    @disable ref Deserialized opAssign(Deserialized source) return;

    bool empty() const pure @safe
    {
        return value_ is null;
    }

    ref T value() return @system
    {
        version (XTB_Checked)
            require(value_ !is null, "empty deserialized value");
        return *value_;
    }

    ref const(T) value() const return @system
    {
        version (XTB_Checked)
            require(value_ !is null, "empty deserialized value");
        return *value_;
    }

    T* pointer() return @system
    {
        return value_;
    }

    /// Describes the owning wrapper as a transparent view of its decoded value.
    /// This prevents allocator bookkeeping from affecting diagnostic output or
    /// layout while preserving the decoded type's own pretty customization.
    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        if (value_ is null)
        {
            pretty.value(null);
            return;
        }
        pretty.value(*value_);
    }

    void deinit()
    {
        tracker_.deinit();
        value_ = null;
    }
}

static assert(!hasElaborateDestructor!(Deserialized!int));
static assert(needsDeinit!(Deserialized!int));
static assert(!__traits(isCopyable, Deserialized!int));

package(xtb.serde) template isDeserialized(T)
{
    static if (is(T == Deserialized!Value, Value))
        enum isDeserialized = true;
    else
        enum isDeserialized = false;
}

package(xtb.serde) bool prepareDeserialized(T)(
    Allocator* allocator,
    Deserialized!T* output,
    T** value,
)
{
    version (XTB_Checked)
    {
        require(allocator !is null && *allocator !is null,
            "serde requires a valid allocator");
        require(output !is null, "deserialized output pointer is null");
        require(value !is null, "deserialized value pointer is null");
    }
    output.deinit();
    output.tracker_.initialize(allocator);
    T* created = output.tracker_.allocator.tryAllocateInit!T();
    if (created is null)
    {
        output.tracker_.deinit();
        *value = null;
        return false;
    }
    output.value_ = created;
    *value = created;
    return true;
}

package(xtb.serde) Allocator* deserializationAllocator(T)(
    Deserialized!T* output,
)
{
    version (XTB_Checked)
        require(output !is null && output.value_ !is null,
            "deserialized output is not prepared");
    return output.tracker_.allocator;
}

package(xtb.serde) void abandonDeserialized(T)(Deserialized!T* output)
{
    version (XTB_Checked)
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

version (unittest)
{
    private struct PrettyPrintOwnershipRecord
    {
        int id;
    }

    private struct PrettyPrintDirectHolder
    {
        PrettyPrintOwnershipRecord item;
        int tail;
    }

    private struct PrettyPrintDecodedHolder
    {
        Deserialized!PrettyPrintOwnershipRecord item;
        int tail;

        @disable this(this);

        void deinit() nothrow @nogc
        {
            item.deinit();
        }
    }
}

unittest
{
    import xtb.core.allocators.malloc : mallocAllocator;
    import xtb.core.fmt.pretty_print : PrettyPrintOptions, pretty;
    import xtb.core.fmt.fixed_buffer : writeBuffer;
    import xtb.core.string;

    const plain = PrettyPrintOptions.init.withoutColors();

    Deserialized!PrettyPrintOwnershipRecord decoded;
    char[16] emptyStorage;
    const emptyResult = writeBuffer(emptyStorage[], decoded.pretty(plain));
    assert(emptyResult.ok);
    assert(!emptyResult.truncated);
    assert(emptyStorage[0 .. emptyResult.written].equal("null"));

    PrettyPrintOwnershipRecord* value;
    assert(prepareDeserialized(mallocAllocator(), &decoded, &value));
    assert(value !is null);
    value.id = 17;

    char[128] valueStorage;
    const valueResult = writeBuffer(valueStorage[], decoded.pretty(plain));
    assert(valueResult.ok);
    assert(!valueResult.truncated);
    assert(valueStorage[0 .. valueResult.written].equal(
            "PrettyPrintOwnershipRecord {id: 17}",
    ));

    PrettyPrintOptions automatic = plain;
    automatic.showTypeNames = false;

    PrettyPrintDirectHolder directHolder = PrettyPrintDirectHolder(
        PrettyPrintOwnershipRecord(17),
        9,
    );
    char[128] directStorage;
    const directResult = writeBuffer(
        directStorage[],
        directHolder.pretty(automatic),
    );
    assert(directResult.ok);
    assert(!directResult.truncated);
    assert(directStorage[0 .. directResult.written].equal(
            "{item: {id: 17}, tail: 9}",
    ));

    PrettyPrintDecodedHolder decodedHolder;
    PrettyPrintOwnershipRecord* nestedValue;
    assert(prepareDeserialized(
            mallocAllocator(),
            &decodedHolder.item,
            &nestedValue,
    ));
    nestedValue.id = 17;
    decodedHolder.tail = 9;
    char[128] decodedStorage;
    const decodedResult = writeBuffer(
        decodedStorage[],
        decodedHolder.pretty(automatic),
    );
    assert(decodedResult.ok);
    assert(!decodedResult.truncated);
    assert(decodedStorage[0 .. decodedResult.written].equal(
            directStorage[0 .. directResult.written],
    ));
    decodedHolder.deinit();

    decoded.deinit();
    char[16] releasedStorage;
    const releasedResult = writeBuffer(
        releasedStorage[],
        decoded.pretty(plain),
    );
    assert(releasedResult.ok);
    assert(!releasedResult.truncated);
    assert(releasedStorage[0 .. releasedResult.written].equal("null"));
}
