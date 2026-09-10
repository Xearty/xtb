module xtb.thread_context;

nothrow @nogc:

import core.attribute;

import xtb.allocators.arena;
import xtb.allocators.malloc;
import xtb.lifetime;
import xtb.memory;
import xtb.panic;
import xtb.types;

enum max_scratch_arenas = 8;

/// Per-thread scratch state owned by `ThreadContextScope`.
struct ThreadContext
{
    Arena[max_scratch_arenas] arenas;
    usize arena_count;
    Allocator* owner_allocator;
    usize attachment_count;
}

private ThreadContext* tls_context;

/// Returns the current thread context, or null when none is installed.
/// The returned pointer is borrowed and remains valid only while its owning
/// `ThreadContextScope` is active.
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
    require(context !is null, "thread context attachment requires an installed context");
    require(
        context.attachment_count != usize.max,
        "thread context attachment count overflow",
    );

    ++context.attachment_count;
    return context;
}

/// Releases one attachment previously registered on `context`.
package(xtb) void detach_thread_context(ThreadContext* context)
{
    require(context !is null, "thread context attachment is null");
    require(tls_context is context, "thread context attachment released out of context");
    require(context.attachment_count != 0, "thread context attachment underflow");

    --context.attachment_count;
}

/// Owns the thread context installed by `acquire` and removes it on scope exit.
@mustuse struct ThreadContextScope
{
nothrow @nogc:

    /// Context owned by this scope. Null denotes an inactive scope.
    ThreadContext* context;

    @disable this(this);

    /// Installs a thread context with the requested scratch arena capacity.
    /// `backing_allocator` may be null to use `malloc_allocator()`.
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

        if (backing_allocator is null) backing_allocator = malloc_allocator();

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
    if (context is null) panic("scratch requested without a thread context");

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

        if (!conflicts_with_candidate) return candidate;
    }

    panic("no non-conflicting scratch arena");
}

/// Returns a non-null scratch arena borrowed from the current thread context.
/// The returned pointer remains valid while the owning `ThreadContextScope` is active.
Arena* scratch_arena()
{
    return select_scratch_arena(null);
}

/// Returns a non-null scratch arena that differs from `conflict`.
/// `conflict` may be null. The returned pointer is borrowed from the current
/// thread context and remains valid while its owning `ThreadContextScope` is active.
Arena* scratch_arena(Allocator* conflict)
{
    Allocator*[1] conflicts = [conflict];
    return select_scratch_arena(conflicts[]);
}

/// Returns a non-null scratch arena that differs from every allocator in `conflicts`.
/// The slice may be null or empty; null allocator elements exclude no arena.
/// The returned pointer is borrowed from the current thread context and remains
/// valid while its owning `ThreadContextScope` is active.
Arena* scratch_arena(scope Allocator*[] conflicts)
{
    return select_scratch_arena(conflicts);
}

/// Owns one scratch-arena checkpoint and rewinds it on scope exit.
@mustuse struct ScratchScope
{
nothrow @nogc:

    /// Temporary arena checkpoint owned by this scope.
    TempArena temporary;

    @disable this(this);

    /// Acquires a checkpoint from any scratch arena in the current thread context.
    static ScratchScope acquire()
    {
        return ScratchScope.from_arena(scratch_arena());
    }

    /// Acquires a checkpoint from an arena other than `conflict`.
    /// `conflict` may be null.
    static ScratchScope acquire(Allocator* conflict)
    {
        return ScratchScope.from_arena(scratch_arena(conflict));
    }

    /// Acquires a checkpoint from an arena not present in `conflicts`.
    /// The slice may be null or empty; null allocator elements exclude no arena.
    static ScratchScope acquire(scope Allocator*[] conflicts)
    {
        return ScratchScope.from_arena(scratch_arena(conflicts));
    }

    ~this()
    {
        if (this.temporary.active) this.temporary.pop();
    }

    /// Returns the selected non-null arena borrowed from the active thread context.
    /// The returned pointer remains valid while the owning `ThreadContextScope` is active.
    Arena* arena() return
    {
        return this.temporary.arena;
    }

    /// Returns the selected arena's non-null borrowed allocator slot.
    /// The returned pointer remains valid while the owning `ThreadContextScope` is active.
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
