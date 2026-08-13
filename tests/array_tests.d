module tests.array_tests;

import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.array;
import xtb.core.lifetime : deinit, move, moveAssign;
import xtb.core.memory : Allocator, deallocateArray, tryAllocateArray;
import xtb.core.string : StringBuf;

private struct PodOwner
{
nothrow @nogc:

    Allocator* allocator;
    ubyte[] bytes;

    static PodOwner create(Allocator* allocator, size_t size)
    {
        PodOwner result;
        result.allocator = allocator;
        result.bytes = allocator.tryAllocateArray!ubyte(size);
        assert(result.bytes.ptr !is null);
        return result;
    }

    void deinit()
    {
        if (bytes.ptr !is null)
            allocator.deallocateArray(bytes);
    }
}

static assert(__traits(isPOD, PodOwner));

private void assertClean(ref const InstrumentedAllocator allocator)
{
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
}

private void testPointerMoveConsumesExplicitPodOwner() @system
{
    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    OwnedArray!PodOwner values = OwnedArray!PodOwner.create(tracked.allocator);
    PodOwner source = PodOwner.create(tracked.allocator, 31);
    assert(values.tryAppend(&source));
    assert(source.allocator is null);
    assert(source.bytes.ptr is null);
    assert(values.length == 1);
    assert(tracked.stats.outstandingAllocations == 2);

    deinit(source);
    deinit(values);
    assertClean(tracked);
}

private void testRepeatedOwnedArrayCleanup() @system
{
    AllocationRecord[32] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    foreach (iteration; 0 .. 128)
    {
        OwnedArray!StringBuf values = OwnedArray!StringBuf.create(
            tracked.allocator,
        );
        foreach (index; 0 .. 4)
        {
            StringBuf value = StringBuf.fromString(
                tracked.allocator,
                (index & 1) == 0 ? "alpha" : "beta",
            );
            values.append(move(value));
        }

        values.removeAt(1);
        values.resize(2);
        StringBuf transferred = values.pop();
        assert(transferred == "alpha");
        deinit(transferred);
        values.clear();
        deinit(values);
        assertClean(tracked);
    }
}

private void testFallibleAppendPreservesOwnership() @system
{
    AllocationRecord[16] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    OwnedArray!StringBuf values = OwnedArray!StringBuf.withCapacity(
        tracked.allocator,
        1,
    );
    StringBuf first = StringBuf.fromString(tracked.allocator, "first");
    values.append(move(first));
    while (values.length < values.capacity)
    {
        StringBuf filler = StringBuf.fromString(tracked.allocator, "filler");
        values.appendAssumeCapacity(move(filler));
    }

    StringBuf candidate = StringBuf.fromString(tracked.allocator, "candidate");
    const oldLength = values.length;
    tracked.failAfter(0);
    assert(!values.tryAppend(&candidate));
    assert(candidate == "candidate");
    assert(values.length == oldLength);
    assert(!values.tryInsert(0, &candidate));
    assert(candidate == "candidate");
    assert(values.length == oldLength && values[0] == "first");
    tracked.allowAllocations();

    deinit(candidate);
    deinit(values);
    assertClean(tracked);
}

private void testAliasingPointerMovesDoNotLeak() @system
{
    {
        AllocationRecord[16] records;
        InstrumentedAllocator tracked = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );

        OwnedArray!PodOwner values = OwnedArray!PodOwner.withCapacity(
            tracked.allocator,
            1,
        );
        PodOwner owner = PodOwner.create(tracked.allocator, 17);
        values.append(move(owner));
        assert(values.tryAppend(&values[0]));
        assert(values.length == 2);
        assert(values[0].allocator is null && values[0].bytes.ptr is null);
        assert(values[1].bytes.length == 17);
        deinit(values);
        assertClean(tracked);
    }

    {
        AllocationRecord[16] records;
        InstrumentedAllocator tracked = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );

        OwnedArray!PodOwner values = OwnedArray!PodOwner.withCapacity(
            tracked.allocator,
            2,
        );
        PodOwner first = PodOwner.create(tracked.allocator, 11);
        PodOwner second = PodOwner.create(tracked.allocator, 23);
        values.append(move(first));
        values.append(move(second));
        assert(first.allocator is null && first.bytes.ptr is null);
        assert(second.allocator is null && second.bytes.ptr is null);
        assert(values.tryInsert(0, &values[1]));
        assert(values.length == 3);
        assert(values[0].bytes.length == 23);
        assert(values[1].bytes.length == 11);
        assert(values[2].allocator is null && values[2].bytes.ptr is null);
        deinit(values);
        assertClean(tracked);
    }
}

private void testMoveAssignmentReleasesReplacedOwners() @system
{
    {
        AllocationRecord[16] records;
        InstrumentedAllocator tracked = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );

        Array!int source = Array!int.fromSlice(tracked.allocator, [1, 2, 3]);
        Array!int target = Array!int.fromSlice(tracked.allocator, [9]);
        assert(tracked.stats.outstandingAllocations == 2);
        moveAssign(source, target);
        assert(source.allocator is null && source.empty);
        assert(target.slice == [1, 2, 3]);
        assert(tracked.stats.outstandingAllocations == 1);
        deinit(source);
        deinit(target);
        assertClean(tracked);
    }

    {
        AllocationRecord[16] records;
        InstrumentedAllocator tracked = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );

        OwnedArray!PodOwner source = OwnedArray!PodOwner.create(
            tracked.allocator,
        );
        PodOwner sourceOwner = PodOwner.create(tracked.allocator, 19);
        source.append(move(sourceOwner));
        OwnedArray!PodOwner target = OwnedArray!PodOwner.create(
            tracked.allocator,
        );
        PodOwner targetOwner = PodOwner.create(tracked.allocator, 29);
        target.append(move(targetOwner));
        assert(tracked.stats.outstandingAllocations == 4);

        moveAssign(source, target);
        assert(source.allocator is null && source.empty);
        assert(target.length == 1 && target[0].bytes.length == 19);
        assert(tracked.stats.outstandingAllocations == 2);
        deinit(source);
        deinit(target);
        assertClean(tracked);
    }
}

private void testReleasedStorageNeedsExplicitCleanup() @system
{
    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    Array!int values = Array!int.fromSlice(tracked.allocator, [1, 2, 3]);
    Array!int.Released released = values.release();
    assert(tracked.stats.outstandingAllocations == 1);
    deinit(released);
    assertClean(tracked);
}

extern (C) int main()
{
    static foreach (testFunction; __traits(getUnitTests, xtb.core.array))
        testFunction();

    testPointerMoveConsumesExplicitPodOwner();
    testRepeatedOwnedArrayCleanup();
    testFallibleAppendPreservesOwnership();
    testAliasingPointerMovesDoNotLeak();
    testMoveAssignmentReleasesReplacedOwners();
    testReleasedStorageNeedsExplicitCleanup();
    return 0;
}
