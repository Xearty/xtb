module tests.arena_tests;

nothrow @nogc:

import xtb.allocators.arena;
import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.allocators.malloc : mallocAllocator;
import xtb.thread_context;
import xtb.thread_context : ScratchScope, ThreadContextScope;

private void testArenaExplicitCleanup()
{
    AllocationRecord[32] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    Arena arena = Arena.create(tracked.allocator, 64);
    foreach (index; 0 .. 128)
    {
        int[] values = arena.allocateArray!int(17);
        values[0] = cast(int) index;
        assert(values[0] == cast(int) index);
        if ((index & 7) == 7)
            arena.clear();
    }
    assert(tracked.stats.outstandingAllocations != 0);
    arena.deinit();
    assert(tracked.clean);
}

private void testThreadContextReleasesArenas()
{
    AllocationRecord[64] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    {
        ThreadContextScope context = ThreadContextScope.acquire(
            3,
            64,
            tracked.allocator,
        );
        {
            ScratchScope first = ScratchScope.acquire();
            first.arena.allocateArray!ubyte(96);
            ScratchScope second = ScratchScope.acquire(first.allocator);
            second.arena.allocateArray!ubyte(128);
        }
        assert(tracked.stats.outstandingAllocations != 0);
    }

    assert(tracked.clean);
}

extern (C) int main()
{
    testArenaExplicitCleanup();
    testThreadContextReleasesArenas();
    return 0;
}
