module tests.lifetime_tests;

import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.lifetime;
import xtb.core.memory : Allocator, allocateInit, allocateInitArray,
    deallocateArray, dispose, disposeArray, tryAllocateArray;

private struct AllocationOwner
{
nothrow @nogc:

    Allocator* allocator;
    ubyte[] storage;

    @disable this(this);

    static bool tryCreate(
        Allocator* allocator,
        size_t size,
        AllocationOwner* output,
    )
    {
        ubyte[] allocation = allocator.tryAllocateArray!ubyte(size);
        if (allocation.ptr is null)
            return false;
        output.allocator = allocator;
        output.storage = allocation;
        return true;
    }

    static AllocationOwner create(Allocator* allocator, size_t size)
    {
        AllocationOwner result;
        assert(tryCreate(allocator, size, &result));
        return result;
    }

    void deinit()
    {
        if (storage.ptr is null)
            return;
        allocator.deallocateArray(storage);
    }
}

private void assertAllocatorClean(ref const InstrumentedAllocator allocator)
{
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
}

private void emplaceOwner(
    ref AllocationOwner destination,
    Allocator* allocator,
    size_t size,
) @system
{
    AllocationOwner source = AllocationOwner.create(allocator, size);
    moveEmplace(source, destination);

    // A successful XTB move leaves the source in a live moved-from state that
    // remains safe to deinitialize.
    deinit(source);
}

private enum PayloadKind : ubyte
{
    none,
    primary,
    secondary,
}

private union Payload
{
    AllocationOwner primary;

    @taggedCase(PayloadKind.secondary)
    AllocationOwner differentlyNamed;
}

private struct Envelope
{
    AllocationOwner header;
    PayloadKind kind;

    @taggedBy("kind", PayloadKind.none)
    Payload payload;
}

private struct DoubleEnvelope
{
    PayloadKind firstKind;

    @taggedBy("firstKind", PayloadKind.none)
    Payload firstPayload;

    PayloadKind secondKind;

    @taggedBy("secondKind", PayloadKind.none)
    Payload secondPayload;
}

private void testStructuralAndTaggedCleanup() @system
{
    struct Pair
    {
        AllocationOwner first;
        int* borrowed;
        AllocationOwner second;
    }

    AllocationRecord[16] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Allocator* allocator = tracked.allocator();

    Pair pair;
    emplaceOwner(pair.first, allocator, 17);
    emplaceOwner(pair.second, allocator, 31);
    assert(tracked.stats.outstandingAllocations == 2);
    deinit(pair);
    assertAllocatorClean(tracked);

    Envelope primary;
    emplaceOwner(primary.header, allocator, 11);
    primary.kind = PayloadKind.primary;
    emplaceOwner(primary.payload.primary, allocator, 23);
    assert(tracked.stats.outstandingAllocations == 2);
    deinit(primary);
    assertAllocatorClean(tracked);

    Envelope secondary;
    emplaceOwner(secondary.header, allocator, 13);
    secondary.kind = PayloadKind.secondary;
    emplaceOwner(secondary.payload.differentlyNamed, allocator, 29);
    assert(tracked.stats.outstandingAllocations == 2);
    deinit(secondary);
    assertAllocatorClean(tracked);

    Envelope inactive;
    deinit(inactive);
    assertAllocatorClean(tracked);

    DoubleEnvelope doubleEnvelope;
    doubleEnvelope.firstKind = PayloadKind.primary;
    emplaceOwner(doubleEnvelope.firstPayload.primary, allocator, 37);
    doubleEnvelope.secondKind = PayloadKind.secondary;
    emplaceOwner(
        doubleEnvelope.secondPayload.differentlyNamed,
        allocator,
        39,
    );
    assert(tracked.stats.outstandingAllocations == 2);
    deinit(doubleEnvelope);
    assertAllocatorClean(tracked);

    AllocationOwner[4] fixed;
    foreach (index; 0 .. fixed.length)
        emplaceOwner(fixed[index], allocator, index + 1);
    assert(tracked.stats.outstandingAllocations == fixed.length);
    deinit(fixed);
    assertAllocatorClean(tracked);
}

private void testMoveReplacementCleanup() @system
{
    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Allocator* allocator = tracked.allocator();

    AllocationOwner source = AllocationOwner.create(allocator, 41);
    AllocationOwner target = AllocationOwner.create(allocator, 43);
    assert(tracked.stats.outstandingAllocations == 2);

    moveAssign(source, target);
    assert(tracked.stats.outstandingAllocations == 1);

    // The source was moved from, but is still a valid deinit target.
    deinit(source);
    assert(tracked.stats.outstandingAllocations == 1);

    deinit(target);
    assertAllocatorClean(tracked);

    AllocationOwner self = AllocationOwner.create(allocator, 45);
    moveAssign(self, self);
    assert(tracked.stats.outstandingAllocations == 1);
    deinit(self);
    assertAllocatorClean(tracked);
}

private void testAllocatorDisposalCleanup() @system
{
    AllocationRecord[16] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Allocator* allocator = tracked.allocator();

    AllocationOwner* single = allocator.allocateInit!AllocationOwner();
    emplaceOwner(*single, allocator, 47);
    assert(tracked.stats.outstandingAllocations == 2);
    allocator.dispose(single);
    assertAllocatorClean(tracked);

    AllocationOwner[] values = allocator.allocateInitArray!AllocationOwner(3);
    foreach (index; 0 .. values.length)
        emplaceOwner(values[index], allocator, 53 + index);
    assert(tracked.stats.outstandingAllocations == values.length + 1);
    allocator.disposeArray(values);
    assertAllocatorClean(tracked);
}

private void testAllocationFailureDoesNotLeak() @system
{
    AllocationRecord[4] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Allocator* allocator = tracked.allocator();

    tracked.failAfter(1);
    AllocationOwner first;
    assert(AllocationOwner.tryCreate(allocator, 59, &first));

    AllocationOwner failed;
    assert(!AllocationOwner.tryCreate(allocator, 61, &failed));
    assert(failed.storage.ptr is null);
    assert(tracked.stats.outstandingAllocations == 1);
    assert(tracked.stats.failedCalls == 1);
    assert(tracked.stats.invalidCalls == 0);

    deinit(first);
    assertAllocatorClean(tracked);
    tracked.allowAllocations();
}

private void testMovementStress() @system
{
    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Allocator* allocator = tracked.allocator();

    foreach (iteration; 0 .. 4_096)
    {
        AllocationOwner first = AllocationOwner.create(
            allocator,
            17 + iteration % 13,
        );
        AllocationOwner second = AllocationOwner.create(
            allocator,
            31 + iteration % 11,
        );
        AllocationOwner third = AllocationOwner.create(
            allocator,
            47 + iteration % 7,
        );

        AllocationOwner moved = move(first);
        assert(first.storage.ptr is null);
        moveAssign(second, moved);
        assert(second.storage.ptr is null);

        AllocationOwner taken = move(moved);
        assert(moved.storage.ptr is null);
        moveAssign(third, taken);
        assert(third.storage.ptr is null);

        deinit(first);
        deinit(second);
        deinit(moved);
        deinit(third);
        deinit(taken);
        assertAllocatorClean(tracked);
    }
}

private void testRepeatedCleanup() @system
{
    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Allocator* allocator = tracked.allocator();

    foreach (iteration; 0 .. 128)
    {
        Envelope value;
        value.kind = (iteration & 1) == 0
            ? PayloadKind.primary : PayloadKind.secondary;
        if (value.kind == PayloadKind.primary)
            emplaceOwner(value.payload.primary, allocator, 67);
        else
            emplaceOwner(value.payload.differentlyNamed, allocator, 71);
        deinit(value);
        assertAllocatorClean(tracked);
    }
}

extern (C) int main()
{
    static foreach (testFunction; __traits(getUnitTests, xtb.core.lifetime))
        testFunction();

    testStructuralAndTaggedCleanup();
    testMoveReplacementCleanup();
    testAllocatorDisposalCleanup();
    testAllocationFailureDoesNotLeak();
    testMovementStress();
    testRepeatedCleanup();
    return 0;
}
