module xtb.core.arena;

import core.stdc.string : memcpy, memset;
import xtb.core.memory : Allocator, allocate, deallocate, tryAllocate;
import xtb.core.panic : panic, require;
import xtb.core.print : Writer;
import xtb.core.types : addOverflows;

private struct ArenaChunk
{
    ArenaChunk* next;
    size_t allocationSize;
    size_t capacity;
    size_t offset;
    ubyte* data;
}

struct ArenaStats
{
    size_t usedBytes;
    size_t reservedBytes;
    size_t peakUsedBytes;
    size_t chunkCount;

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writer.put("ArenaStats(used=");
        writer.value(usedBytes);
        writer.put(", reserved=");
        writer.value(reservedBytes);
        writer.put(", peak=");
        writer.value(peakUsedBytes);
        writer.put(", chunks=");
        writer.value(chunkCount);
        writer.put(')');
    }
}

private int tlsThreadMarker;

private void* currentThreadToken() nothrow @nogc
{
    return &tlsThreadMarker;
}

struct Arena
{
    Allocator allocator;
    private Allocator* backingAllocator;
    private ArenaChunk* firstChunk;
    private ArenaChunk* currentChunk;
    private size_t defaultChunkSize;
    private size_t scopeDepth;
    private size_t usedBytes_;
    private size_t peakUsedBytes_;
    private size_t retentionLimit = size_t.max;
    private size_t generation_ = 1;
    private bool poisonRewoundMemory_;

    @disable this(this);

    ~this() nothrow @nogc
    {
        deinit();
    }

    static Arena create(
        Allocator* backingAllocator,
        size_t defaultChunkSize = 64 * 1024,
    ) nothrow @nogc
    {
        require(backingAllocator !is null && *backingAllocator !is null,
            "arena requires a valid backing allocator");
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
        void* result = tryAllocate(size, alignment);
        if (size != 0 && result is null)
            panic("arena allocation failed");
        return result;
    }

    void* tryAllocate(size_t size, size_t alignment = (void*).alignof)
    nothrow @nogc
    {
        if (size == 0)
            return null;
        require(isPowerOfTwo(alignment),
            "arena alignment must be a power of two");

        ArenaChunk* chunk = currentChunk;
        size_t alignedOffset;
        if (chunk is null ||
            !alignedOffsetFor(chunk, alignment, &alignedOffset) ||
            alignedOffset > chunk.capacity ||
            size > chunk.capacity - alignedOffset)
        {
            chunk = obtainChunk(size, alignment);
            if (chunk is null)
                return null;
            if (!alignedOffsetFor(chunk, alignment, &alignedOffset))
                return null;
        }

        void* result = chunk.data + alignedOffset;
        const occupied = alignedOffset + size - chunk.offset;
        chunk.offset = alignedOffset + size;
        usedBytes_ += occupied;
        if (usedBytes_ > peakUsedBytes_)
            peakUsedBytes_ = usedBytes_;
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

    void* tryAllocateZeroed(size_t size, size_t alignment = (void*).alignof)
    nothrow @nogc
    {
        void* result = tryAllocate(size, alignment);
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
        usedBytes_ = 0;
        ++generation_;
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
        usedBytes_ = 0;
        peakUsedBytes_ = 0;
        retentionLimit = size_t.max;
        ++generation_;
    }

    ArenaStats stats() const pure nothrow @safe @nogc
    {
        ArenaStats result;
        result.usedBytes = usedBytes_;
        result.peakUsedBytes = peakUsedBytes_;
        for (const(ArenaChunk)* chunk = firstChunk; chunk !is null; chunk = chunk.next)
        {
            result.reservedBytes += chunk.capacity;
            ++result.chunkCount;
        }
        return result;
    }

    void setRetentionLimit(size_t bytes) nothrow @nogc
    {
        retentionLimit = bytes;
        if (scopeDepth == 0)
            trimToRetentionLimit();
    }

    void setRewindPoisoning(bool enabled) nothrow @nogc
    {
        poisonRewoundMemory_ = enabled;
    }

    void trim() nothrow @nogc
    {
        require(scopeDepth == 0, "cannot trim arena with active temporary scopes");
        ArenaChunk* keep = currentChunk;
        if (keep is null)
        {
            releaseChunks(firstChunk);
            firstChunk = null;
            return;
        }
        releaseChunks(keep.next);
        keep.next = null;
    }

    private void trimToRetentionLimit() nothrow @nogc
    {
        size_t reserved;
        ArenaChunk* previous;
        ArenaChunk* chunk = firstChunk;
        while (chunk !is null)
        {
            if (chunk is currentChunk)
                previous = chunk;
            reserved += chunk.capacity;
            chunk = chunk.next;
        }
        if (reserved <= retentionLimit || previous is null)
            return;

        chunk = previous.next;
        while (chunk !is null && reserved > retentionLimit)
        {
            ArenaChunk* next = chunk.next;
            reserved -= chunk.capacity;
            backingAllocator.deallocate(
                chunk,
                chunk.allocationSize,
                ArenaChunk.alignof,
            );
            chunk = next;
        }
        previous.next = chunk;
    }

    private void releaseChunks(ArenaChunk* first) nothrow @nogc
    {
        ArenaChunk* chunk = first;
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
    }

    private ArenaChunk* obtainChunk(size_t size, size_t alignment)
    nothrow @nogc
    {
        ArenaChunk* tail = currentChunk;
        ArenaChunk* candidate = currentChunk is null
            ? firstChunk : currentChunk.next;

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
        if (created is null)
            return null;
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
            return null;

        const allocationSize = ArenaChunk.sizeof + padding + capacity;
        ArenaChunk* chunk = cast(ArenaChunk*) backingAllocator.tryAllocate(
            allocationSize,
            ArenaChunk.alignof,
        );
        if (chunk is null)
            return null;
        *chunk = ArenaChunk.init;
        chunk.allocationSize = allocationSize;
        chunk.capacity = capacity;

        const start = cast(size_t)(cast(ubyte*) chunk + ArenaChunk.sizeof);
        size_t alignedStart;
        if (!alignUp(start, alignment, &alignedStart))
        {
            backingAllocator.deallocate(
                chunk,
                allocationSize,
                ArenaChunk.alignof,
            );
            return null;
        }
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

private extern (C) void* arenaAllocatorProcedure(
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

    void* replacement = arena.tryAllocate(newSize, alignment);
    if (replacement is null)
        return null;
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
    private size_t usedBytes_;
    private size_t generation_;
    private void* threadToken_;
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
    result.usedBytes_ = arena.usedBytes_;
    result.generation_ = arena.generation_;
    result.threadToken_ = currentThreadToken();
    result.active_ = true;
    return result;
}

void pop(ref TempArena temporary) nothrow @nogc
{
    require(temporary.active_, "temporary arena already popped");
    Arena* arena = temporary.arena_;
    require(arena !is null, "temporary arena has no arena");
    require(temporary.threadToken_ is currentThreadToken(),
        "temporary arena popped on a different thread");
    require(arena.generation_ == temporary.generation_,
        "temporary arena checkpoint generation mismatch");
    require(arena.scopeDepth == temporary.depth_, "temporary arenas must pop in LIFO order");

    if (arena.poisonRewoundMemory_)
    {
        ArenaChunk* chunk = temporary.chunk_ is null
            ? arena.firstChunk : temporary.chunk_;
        bool first = true;
        for (; chunk !is null; chunk = chunk.next)
        {
            const begin = first && temporary.chunk_ !is null
                ? temporary.offset_ : 0;
            if (chunk.offset > begin)
                memset(chunk.data + begin, 0xDD, chunk.offset - begin);
            first = false;
        }
    }

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
    arena.usedBytes_ = temporary.usedBytes_;
    if (arena.scopeDepth == 0)
        arena.trimToRetentionLimit();
    temporary.arena_ = null;
    temporary.chunk_ = null;
    temporary.offset_ = 0;
    temporary.depth_ = 0;
    temporary.usedBytes_ = 0;
    temporary.generation_ = 0;
    temporary.threadToken_ = null;
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
    assert(arena.stats.usedBytes >= int.sizeof);
    assert(arena.stats.peakUsedBytes >= arena.stats.usedBytes);
    assert(arena.stats.chunkCount >= 1);
    arena.setRewindPoisoning(true);
    TempArena poisoned = (&arena).push();
    ubyte* bytes = cast(ubyte*) arena.allocate(8, 1);
    bytes[0] = 1;
    poisoned.pop();
    assert(bytes[0] == 0xDD);
    arena.setRetentionLimit(64);
    arena.trim();
    arena.deinit();

    import xtb.core.memory : AllocationRecord, InstrumentedAllocator;

    AllocationRecord[4] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(), records[],
    );
    failing.failAfter(0);
    Arena fallible = Arena.create(failing.handle, 64);
    assert(fallible.tryAllocate(8, 8) is null);
    assert(fallible.stats.chunkCount == 0);
    fallible.deinit();
}
