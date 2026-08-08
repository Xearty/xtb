module xtb.core.thread_context;

nothrow @nogc:

import xtb.core.arena : Arena, TempArena, pop, push;
import xtb.core.memory : Allocator, allocateInit, dispose, mallocAllocator;
import xtb.core.panic : panic;

version (XTB_Checked) import xtb.core.panic : require;

enum maxScratchArenas = 8;

struct ThreadContext
{
nothrow @nogc:

    private Arena[maxScratchArenas] arenas;
    private size_t arenaCount;
    private Allocator* ownerAllocator;
    private void* logger;

    package void* installedLogger() return
    {
        return logger;
    }

    package void setInstalledLogger(void* value)
    {
        logger = value;
    }
}

private ThreadContext* tlsContext;

ThreadContext* currentThreadContext()
{
    return tlsContext;
}

struct ThreadContextScope
{
nothrow @nogc:

    private ThreadContext* context_;

    @disable this(this);

    static ThreadContextScope acquire(
        size_t scratchArenaCount = 2,
        size_t scratchChunkSize = 64 * 1024,
        Allocator* backingAllocator = null,
    )
    {
        version (XTB_Checked)
        {
            require(tlsContext is null, "thread context already installed");
            require(
                scratchArenaCount != 0 && scratchArenaCount <= maxScratchArenas,
                "invalid scratch arena count",
            );
        }

        if (backingAllocator is null)
            backingAllocator = mallocAllocator();

        ThreadContext* context = backingAllocator.allocateInit!ThreadContext();
        context.ownerAllocator = backingAllocator;
        context.arenaCount = scratchArenaCount;
        foreach (i; 0 .. scratchArenaCount)
            context.arenas[i] = Arena.create(backingAllocator, scratchChunkSize);

        tlsContext = context;
        ThreadContextScope result;
        result.context_ = context;
        return result;
    }

    ~this()
    {
        if (context_ is null)
            return;
        version (XTB_Checked)
        {
            require(tlsContext is context_, "thread context destroyed out of order");
            require(
                context_.logger is null,
                "thread context destroyed with a logger installed",
            );
        }

        Allocator* owner = context_.ownerAllocator;
        ThreadContext* released = context_;
        tlsContext = null;
        context_ = null;
        owner.dispose(released);
    }
}

private Arena* selectScratchArena(scope Allocator*[] conflicts)
{
    ThreadContext* context = tlsContext;
    if (context is null)
        panic("scratch requested without a thread context");

    foreach (i; 0 .. context.arenaCount)
    {
        Arena* candidate = &context.arenas[i];
        Allocator* candidateAllocator = candidate.allocator();
        bool conflictsWithCandidate;
        foreach (conflict; conflicts)
        {
            if (conflict is candidateAllocator)
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

Arena* scratchArena()
{
    return selectScratchArena(null);
}

Arena* scratchArena(Allocator* conflict)
{
    Allocator*[1] conflicts = [conflict];
    return selectScratchArena(conflicts[]);
}

Arena* scratchArena(scope Allocator*[] conflicts)
{
    return selectScratchArena(conflicts);
}

struct ScratchScope
{
nothrow @nogc:

    private TempArena temporary_;

    @disable this(this);

    static ScratchScope acquire()
    {
        return fromArena(scratchArena());
    }

    static ScratchScope acquire(Allocator* conflict)
    {
        return fromArena(scratchArena(conflict));
    }

    static ScratchScope acquire(scope Allocator*[] conflicts)
    {
        return fromArena(scratchArena(conflicts));
    }

    ~this()
    {
        if (temporary_.active)
            temporary_.pop();
    }

    Arena* arena() return
    {
        return temporary_.arena();
    }

    Allocator* allocator() return
    {
        return temporary_.allocator();
    }

    private static ScratchScope fromArena(Arena* arena)
    {
        ScratchScope result;
        result.temporary_ = arena.push();
        return result;
    }
}

unittest
{
    ThreadContextScope context = ThreadContextScope.acquire(3, 128);
    {
        ScratchScope first = ScratchScope.acquire();
        int* value = first.allocator.allocateInit!int();
        *value = 7;

        ScratchScope second = ScratchScope.acquire(first.allocator);
        assert(second.allocator !is first.allocator);

        Allocator*[2] conflicts = [first.allocator, second.allocator];
        ScratchScope third = ScratchScope.acquire(conflicts[]);
        assert(third.allocator !is first.allocator);
        assert(third.allocator !is second.allocator);
    }
}
