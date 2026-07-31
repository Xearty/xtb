module xtb.core.arena;

import core.stdc.string : memcpy, memset;
import xtb.core.memory : Allocator, allocate, deallocate;
import xtb.core.panic : panic, require;
import xtb.core.types : addOverflows;

private struct ArenaChunk
{
    ArenaChunk* next;
    size_t allocationSize;
    size_t capacity;
    size_t offset;
    ubyte* data;
}

struct Arena
{
    Allocator allocator;
    private Allocator* backingAllocator;
    private ArenaChunk* firstChunk;
    private ArenaChunk* currentChunk;
    private size_t defaultChunkSize;
    private size_t scopeDepth;

    @disable this(this);

    static Arena create(
        Allocator* backingAllocator,
        size_t defaultChunkSize = 64 * 1024,
    ) nothrow @nogc
    {
        require(backingAllocator !is null, "arena requires a backing allocator");
        require(defaultChunkSize != 0, "arena chunk size must be nonzero");

        Arena result;
        result.allocator = &arenaAllocatorProcedure;
        result.backingAllocator = backingAllocator;
        result.defaultChunkSize = defaultChunkSize;
        return result;
    }

    Allocator* allocatorHandle() return nothrow @nogc
    {
        return &allocator;
    }

    void* allocate(size_t size, size_t alignment = (void*).alignof)
        nothrow @nogc
    {
        if (size == 0)
            return null;
        if (!isPowerOfTwo(alignment))
            panic("arena alignment must be a power of two");

        ArenaChunk* chunk = currentChunk;
        size_t alignedOffset;
        if (chunk is null ||
            !alignedOffsetFor(chunk, alignment, &alignedOffset) ||
            alignedOffset > chunk.capacity ||
            size > chunk.capacity - alignedOffset)
        {
            chunk = obtainChunk(size, alignment);
            if (!alignedOffsetFor(chunk, alignment, &alignedOffset))
                panic("arena offset overflow");
        }

        void* result = chunk.data + alignedOffset;
        chunk.offset = alignedOffset + size;
        return result;
    }

    void* allocateZeroed(size_t size, size_t alignment = (void*).alignof)
        nothrow @nogc
    {
        void* result = allocate(size, alignment);
        if (result !is null)
            memset(result, 0, size);
        return result;
    }

    void clear() nothrow @nogc
    {
        require(scopeDepth == 0, "cannot clear arena with active temporary scopes");
        for (ArenaChunk* chunk = firstChunk; chunk !is null; chunk = chunk.next)
            chunk.offset = 0;
        currentChunk = firstChunk;
    }

    void deinit() nothrow @nogc
    {
        require(scopeDepth == 0, "cannot destroy arena with active temporary scopes");
        ArenaChunk* chunk = firstChunk;
        while (chunk !is null)
        {
            ArenaChunk* next = chunk.next;
            backingAllocator.deallocate(
                chunk,
                chunk.allocationSize,
                ArenaChunk.alignof,
            );
            chunk = next;
        }

        allocator = null;
        backingAllocator = null;
        firstChunk = null;
        currentChunk = null;
        defaultChunkSize = 0;
        scopeDepth = 0;
    }

    private ArenaChunk* obtainChunk(size_t size, size_t alignment)
        nothrow @nogc
    {
        ArenaChunk* tail = currentChunk;
        ArenaChunk* candidate = currentChunk is null
            ? firstChunk
            : currentChunk.next;

        while (candidate !is null)
        {
            size_t offset;
            if (alignedOffsetFor(candidate, alignment, &offset) &&
                offset <= candidate.capacity &&
                size <= candidate.capacity - offset)
            {
                currentChunk = candidate;
                return candidate;
            }
            tail = candidate;
            candidate = candidate.next;
        }

        const capacity = size > defaultChunkSize ? size : defaultChunkSize;
        ArenaChunk* created = createChunk(capacity, alignment);
        if (firstChunk is null)
            firstChunk = created;
        else
            tail.next = created;
        currentChunk = created;
        return created;
    }

    private ArenaChunk* createChunk(size_t capacity, size_t alignment)
        nothrow @nogc
    {
        const padding = alignment - 1;
        if (addOverflows(ArenaChunk.sizeof, padding) ||
            addOverflows(ArenaChunk.sizeof + padding, capacity))
            panic("arena chunk size overflow");

        const allocationSize = ArenaChunk.sizeof + padding + capacity;
        ArenaChunk* chunk = cast(ArenaChunk*) backingAllocator.allocate(
            allocationSize,
            ArenaChunk.alignof,
        );
        *chunk = ArenaChunk.init;
        chunk.allocationSize = allocationSize;
        chunk.capacity = capacity;

        const start = cast(size_t) (cast(ubyte*) chunk + ArenaChunk.sizeof);
        size_t alignedStart;
        if (!alignUp(start, alignment, &alignedStart))
            panic("arena address overflow");
        chunk.data = cast(ubyte*) alignedStart;
        return chunk;
    }
}

static assert(Arena.allocator.offsetof == 0);

private bool isPowerOfTwo(size_t value) pure nothrow @safe @nogc
{
    return value != 0 && (value & (value - 1)) == 0;
}

private bool alignUp(size_t value, size_t alignment, size_t* result)
    pure nothrow @safe @nogc
{
    const mask = alignment - 1;
    if (value > size_t.max - mask)
        return false;
    *result = (value + mask) & ~mask;
    return true;
}

private bool alignedOffsetFor(
    ArenaChunk* chunk,
    size_t alignment,
    size_t* result,
) pure nothrow @system @nogc
{
    const base = cast(size_t) chunk.data;
    if (chunk.offset > size_t.max - base)
        return false;
    size_t alignedAddress;
    if (!alignUp(base + chunk.offset, alignment, &alignedAddress))
        return false;
    *result = alignedAddress - base;
    return true;
}

private void* arenaAllocatorProcedure(
    void* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) nothrow @nogc
{
    Arena* arena = cast(Arena*) allocator;
    if (newSize == 0)
        return null;

    void* replacement = arena.allocate(newSize, alignment);
    if (oldPointer !is null && oldSize != 0)
    {
        const amount = oldSize < newSize ? oldSize : newSize;
        memcpy(replacement, oldPointer, amount);
    }
    return replacement;
}

struct TempArena
{
    private Arena* arena_;
    private ArenaChunk* chunk_;
    private size_t offset_;
    private size_t depth_;
    private bool active_;

    @disable this(this);

    Arena* arena() return nothrow @nogc
    {
        require(active_, "inactive temporary arena");
        return arena_;
    }

    Allocator* allocator() return nothrow @nogc
    {
        return arena().allocatorHandle();
    }

    bool active() const pure nothrow @safe @nogc
    {
        return active_;
    }
}

TempArena push(Arena* arena) nothrow @nogc
{
    require(arena !is null, "cannot push a null arena");
    TempArena result;
    result.arena_ = arena;
    result.chunk_ = arena.currentChunk;
    result.offset_ = arena.currentChunk is null ? 0 : arena.currentChunk.offset;
    result.depth_ = ++arena.scopeDepth;
    result.active_ = true;
    return result;
}

void pop(ref TempArena temporary) nothrow @nogc
{
    require(temporary.active_, "temporary arena already popped");
    Arena* arena = temporary.arena_;
    require(arena !is null, "temporary arena has no arena");
    require(arena.scopeDepth == temporary.depth_, "temporary arenas must pop in LIFO order");

    if (temporary.chunk_ is null)
    {
        for (ArenaChunk* chunk = arena.firstChunk; chunk !is null; chunk = chunk.next)
            chunk.offset = 0;
        arena.currentChunk = arena.firstChunk;
    }
    else
    {
        temporary.chunk_.offset = temporary.offset_;
        for (ArenaChunk* chunk = temporary.chunk_.next; chunk !is null; chunk = chunk.next)
            chunk.offset = 0;
        arena.currentChunk = temporary.chunk_;
    }

    --arena.scopeDepth;
    temporary.arena_ = null;
    temporary.chunk_ = null;
    temporary.offset_ = 0;
    temporary.depth_ = 0;
    temporary.active_ = false;
}

nothrow @nogc unittest
{
    import xtb.core.memory : mallocAllocator;

    Arena arena = Arena.create(mallocAllocator(), 64);
    int* persistent = cast(int*) arena.allocate(int.sizeof, int.alignof);
    *persistent = 42;

    TempArena outer = (&arena).push();
    void* first = arena.allocate(48, 16);
    assert((cast(size_t) first & 15) == 0);
    TempArena inner = (&arena).push();
    arena.allocate(96, 32);
    inner.pop();
    outer.pop();
    assert(*persistent == 42);
    arena.deinit();
}
