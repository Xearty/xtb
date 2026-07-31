module xtb.core.thread_context;

import core.stdc.string : memset;
import xtb.core.arena : Arena, TempArena, pop, push;
import xtb.core.memory : Allocator, allocate, deallocate, mallocAllocator;
import xtb.core.panic : panic, require;

enum maxScratchArenas = 8;

struct ThreadContext
{
    private Arena[maxScratchArenas] arenas;
    private size_t arenaCount;
    private Allocator* ownerAllocator;
}

private ThreadContext* tlsContext;

ThreadContext* currentThreadContext() nothrow @nogc
{
    return tlsContext;
}

struct ThreadContextScope
{
    private ThreadContext* context_;

    @disable this(this);

    static ThreadContextScope acquire(
        size_t scratchArenaCount = 2,
        size_t scratchChunkSize = 64 * 1024,
        Allocator* backingAllocator = null,
    ) nothrow @nogc
    {
        require(tlsContext is null, "thread context already installed");
        require(
            scratchArenaCount != 0 && scratchArenaCount <= maxScratchArenas,
            "invalid scratch arena count",
        );

        if (backingAllocator is null)
            backingAllocator = mallocAllocator();

        ThreadContext* context = backingAllocator.allocate!ThreadContext();
        memset(context, 0, ThreadContext.sizeof);
        context.ownerAllocator = backingAllocator;
        context.arenaCount = scratchArenaCount;
        foreach (i; 0 .. scratchArenaCount)
            context.arenas[i] = Arena.create(backingAllocator, scratchChunkSize);

        tlsContext = context;
        ThreadContextScope result;
        result.context_ = context;
        return result;
    }

    ~this() nothrow @nogc
    {
        if (context_ is null)
            return;
        require(tlsContext is context_, "thread context destroyed out of order");

        foreach (i; 0 .. context_.arenaCount)
            context_.arenas[i].deinit();

        Allocator* owner = context_.ownerAllocator;
        ThreadContext* released = context_;
        tlsContext = null;
        context_ = null;
        owner.deallocate(released);
    }
}

private Arena* selectScratchArena(scope Allocator*[] conflicts)
    nothrow @nogc
{
    ThreadContext* context = tlsContext;
    if (context is null)
        panic("scratch requested without a thread context");

    foreach (i; 0 .. context.arenaCount)
    {
        Arena* candidate = &context.arenas[i];
        Allocator* handle = candidate.allocatorHandle();
        bool conflictsWithCandidate;
        foreach (conflict; conflicts)
        {
            if (conflict is handle)
            {
                conflictsWithCandidate = true;
                break;
            }
        }
        if (!conflictsWithCandidate)
            return candidate;
    }
    panic("no non-conflicting scratch arena");
}

Arena* scratchArena() nothrow @nogc
{
    return selectScratchArena(null);
}

Arena* scratchArena(Allocator* conflict) nothrow @nogc
{
    Allocator*[1] conflicts = [conflict];
    return selectScratchArena(conflicts[]);
}

Arena* scratchArena(scope Allocator*[] conflicts) nothrow @nogc
{
    return selectScratchArena(conflicts);
}

struct ScratchScope
{
    private TempArena temporary_;

    @disable this(this);

    static ScratchScope acquire() nothrow @nogc
    {
        return fromArena(scratchArena());
    }

    static ScratchScope acquire(Allocator* conflict) nothrow @nogc
    {
        return fromArena(scratchArena(conflict));
    }

    static ScratchScope acquire(scope Allocator*[] conflicts) nothrow @nogc
    {
        return fromArena(scratchArena(conflicts));
    }

    ~this() nothrow @nogc
    {
        if (temporary_.active)
            temporary_.pop();
    }

    Arena* arena() return nothrow @nogc
    {
        return temporary_.arena();
    }

    Allocator* allocator() return nothrow @nogc
    {
        return temporary_.allocator();
    }

    private static ScratchScope fromArena(Arena* arena) nothrow @nogc
    {
        ScratchScope result;
        result.temporary_ = arena.push();
        return result;
    }
}

nothrow @nogc unittest
{
    ThreadContextScope context = ThreadContextScope.acquire(3, 128);
    {
        ScratchScope first = ScratchScope.acquire();
        int* value = first.allocator.allocate!int();
        *value = 7;

        ScratchScope second = ScratchScope.acquire(first.allocator);
        assert(second.allocator !is first.allocator);

        Allocator*[2] conflicts = [first.allocator, second.allocator];
        ScratchScope third = ScratchScope.acquire(conflicts[]);
        assert(third.allocator !is first.allocator);
        assert(third.allocator !is second.allocator);
    }
}
