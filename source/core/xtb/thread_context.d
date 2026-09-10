module xtb.thread_context;

nothrow @nogc:

import xtb.allocators.arena;
import xtb.allocators.malloc;
import xtb.lifetime;
import xtb.memory;
import xtb.panic;
import xtb.types;

enum max_scratch_arenas = 8;

struct ThreadContext
{
nothrow @nogc:

    Arena[max_scratch_arenas] arenas;
    usize arena_count;
    Allocator* owner_allocator;
    usize attachment_count;
}

private ThreadContext* tls_context;

/// Returns the current thread context, or null when none is installed.
ThreadContext* current_thread_context()
{
    return tls_context;
}

/// Registers one scoped facility that requires the current thread context.
/// Internal XTB components must balance every successful attachment with
/// `detach_thread_context` before the context scope ends.
package(xtb) ThreadContext* attach_thread_context()
{
    ThreadContext* context = tls_context;
    require(context !is null, "thread-context attachment requires an installed context");
    require(
        context.attachment_count != usize.max,
        "thread-context attachment count overflow",
    );
    ++context.attachment_count;
    return context;
}

/// Releases one attachment previously registered on `context`.
package(xtb) void detach_thread_context(ThreadContext* context)
{
    require(context !is null, "thread-context attachment is null");
    require(tls_context is context, "thread-context attachment released out of context");
    require(context.attachment_count != 0, "thread-context attachment underflow");
    --context.attachment_count;
}

struct ThreadContextScope
{
nothrow @nogc:

    ThreadContext* context;

    @disable this(this);

    static ThreadContextScope acquire(
        usize scratch_arena_count = 2,
        usize scratch_chunk_size = 64 * 1024,
        Allocator* backing_allocator = null,
    )
    {
        require(tls_context is null, "thread context already installed");
        require(
            scratch_arena_count != 0 && scratch_arena_count <= max_scratch_arenas,
            "invalid scratch arena count",
        );

        if (backing_allocator is null)
            backing_allocator = malloc_allocator();

        ThreadContext* context = backing_allocator.allocate_init!ThreadContext();
        context.owner_allocator = backing_allocator;
        context.arena_count = scratch_arena_count;
        foreach (i; 0 .. scratch_arena_count)
        {
            Arena arena = Arena.create(backing_allocator, scratch_chunk_size);
            move_emplace(arena, context.arenas[i]);
        }

        tls_context = context;
        ThreadContextScope result;
        result.context = context;
        return result;
    }

    ~this()
    {
        if (this.context is null) return;

        require(tls_context is this.context, "thread context destroyed out of order");
        require(
            this.context.attachment_count == 0,
            "thread context destroyed with attachments installed",
        );

        Allocator* owner = this.context.owner_allocator;
        ThreadContext* released = this.context;
        tls_context = null;
        this.context = null;
        owner.dispose(released);
    }
}

private Arena* select_scratch_arena(scope Allocator*[] conflicts)
{
    ThreadContext* context = tls_context;
    if (context is null)
        panic("scratch requested without a thread context");

    foreach (i; 0 .. context.arena_count)
    {
        Arena* candidate = &context.arenas[i];
        Allocator* candidate_allocator = candidate.allocator;
        bool conflicts_with_candidate;
        foreach (conflict; conflicts)
        {
            if (conflict is candidate_allocator)
            {
                conflicts_with_candidate = true;
                break;
            }
        }
        if (!conflicts_with_candidate)
            return candidate;
    }
    panic("no non-conflicting scratch arena");
}

/// Returns a scratch arena that does not conflict with any supplied allocator.
Arena* scratch_arena()
{
    return select_scratch_arena(null);
}

Arena* scratch_arena(Allocator* conflict)
{
    Allocator*[1] conflicts = [conflict];
    return select_scratch_arena(conflicts[]);
}

Arena* scratch_arena(scope Allocator*[] conflicts)
{
    return select_scratch_arena(conflicts);
}

struct ScratchScope
{
nothrow @nogc:

    TempArena temporary;

    @disable this(this);

    static ScratchScope acquire()
    {
        return ScratchScope.from_arena(scratch_arena());
    }

    static ScratchScope acquire(Allocator* conflict)
    {
        return ScratchScope.from_arena(scratch_arena(conflict));
    }

    static ScratchScope acquire(scope Allocator*[] conflicts)
    {
        return ScratchScope.from_arena(scratch_arena(conflicts));
    }

    ~this()
    {
        if (this.temporary.active) this.temporary.pop();
    }

    Arena* arena() return
    {
        return this.temporary.arena;
    }

    Allocator* allocator() return
    {
        return this.temporary.allocator;
    }

    private static ScratchScope from_arena(Arena* arena)
    {
        ScratchScope result;
        result.temporary = arena.push();
        return result;
    }
}

unittest
{
    ThreadContextScope context = ThreadContextScope.acquire(3, 128);
    {
        ScratchScope first = ScratchScope.acquire();
        i32* value = first.allocator.allocate_init!i32();
        *value = 7;

        ScratchScope second = ScratchScope.acquire(first.allocator);
        assert(second.allocator !is first.allocator);

        Allocator*[2] conflicts = [first.allocator, second.allocator];
        ScratchScope third = ScratchScope.acquire(conflicts[]);
        assert(third.allocator !is first.allocator);
        assert(third.allocator !is second.allocator);
    }
}
