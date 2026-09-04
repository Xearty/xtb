module xtb.allocators.arena;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.lifetime : emplace, forward;
import core.stdc.string : memcpy, memset;
import xtb.allocators.internal.virtual_memory : VirtualMemoryReservation,
    tryReserveVirtualMemory, virtualMemoryPageSize, virtualMemorySupported;
import xtb.lifetime : move_emplace, needs_deinit, structuralDeinit = deinit, tagged_by;
import xtb.memory : Allocator, allocate, deallocate, tryAllocate;
import xtb.panic : panic;

version (XTB_Checked) import xtb.panic : require;
import xtb.numeric : add_overflows, multiply_overflows;

private enum ArenaStorageKind : ubyte
{
    none,
    chunked,
    virtualMemory,
}

private struct ArenaChunk
{
    ArenaChunk* next;
    size_t allocationSize;
    size_t capacity;
    size_t offset;
    ubyte* data;
}

private struct ChunkedArenaStorage
{
nothrow @nogc:

    Allocator* backingAllocator;
    ArenaChunk* firstChunk;
    ArenaChunk* currentChunk;
    size_t defaultChunkSize;

    void deinit()
    {
        releaseChunks(firstChunk);
        backingAllocator = null;
        firstChunk = null;
        currentChunk = null;
        defaultChunkSize = 0;
    }

    void releaseChunks(ArenaChunk* first)
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
}

private struct VirtualArenaStorage
{
nothrow @nogc:

    VirtualMemoryReservation reservation;
    size_t committedBytes;
    size_t commitGranularity;
    size_t pageSize;

    void deinit() @system
    {
        structuralDeinit(reservation);
        committedBytes = 0;
        commitGranularity = 0;
        pageSize = 0;
    }
}

private union ArenaStorage
{
    ChunkedArenaStorage chunked;
    VirtualArenaStorage virtualMemory;
}

/// Tagged backend state. Exactly one union member is live when `kind` is active.
private struct ArenaStorageState
{
    @disable this(this);
    @disable ref ArenaStorageState opAssign(ArenaStorageState source) return;

    ArenaStorageKind kind;
    @tagged_by("kind", ArenaStorageKind.none)
    ArenaStorage data;
}

static assert(needs_deinit!ChunkedArenaStorage);
static assert(needs_deinit!VirtualArenaStorage);
static assert(needs_deinit!ArenaStorageState);

struct ArenaStats
{
nothrow @nogc:

    /// Bytes occupied by the current bump-allocation prefix, including
    /// alignment padding.
    size_t usedBytes;
    /// Chunk payload capacity or the complete virtual-address reservation.
    size_t reservedBytes;
    /// Reusable chunk payload capacity or the accessible virtual-memory
    /// prefix.
    size_t committedBytes;
    /// Highest `usedBytes` observed since creation.
    size_t peakUsedBytes;
    /// Number of allocator-backed chunks; zero for a virtual-memory-backed
    /// arena.
    size_t chunkCount;
}

version (XTB_Checked)
{
    private int tlsThreadMarker;

    private void* currentThreadToken()
    {
        return &tlsThreadMarker;
    }
}

struct Arena
{
nothrow @nogc:

    private Allocator allocator_;
    private ArenaStorageState storage_;
    private size_t scopeDepth;
    private size_t usedBytes_;
    private size_t peakUsedBytes_;
    private size_t retentionLimit = size_t.max;
    version (XTB_Checked)
    {
        private size_t generation_ = 1;
        private bool poisonRewoundMemory_;
    }

    @disable this(this);
    @disable ref Arena opAssign(Arena source) return;

    static Arena create(
        Allocator* backingAllocator,
        size_t defaultChunkSize = 64 * 1024,
    )
    {
        version (XTB_Checked)
        {
            require(backingAllocator !is null && *backingAllocator !is null,
                "arena requires a valid backing allocator");
            require(defaultChunkSize != 0, "arena chunk size must be nonzero");
        }

        Arena result;
        emplace(&result.storage_.data.chunked);
        result.storage_.data.chunked.backingAllocator = backingAllocator;
        result.storage_.data.chunked.defaultChunkSize = defaultChunkSize;
        result.storage_.kind = ArenaStorageKind.chunked;
        result.allocator_ = &chunkedArenaAllocatorProcedure;
        return result;
    }

    /// Attempts to create an arena backed by one contiguous virtual-address
    /// reservation. The reservation is the fixed maximum storage capacity, is
    /// inaccessible initially, and becomes readable/writable in
    /// `commitGranularity` increments as allocation grows. The reservation size
    /// and commit granularity are rounded up to native page boundaries.
    /// `tryAllocate` returns null once the fixed reservation is exhausted.
    static bool tryCreateVirtual(
        size_t reservationBytes,
        scope Arena* output,
    ) @system
    {
        return tryCreateVirtual(
            reservationBytes,
            64 * 1024,
            output,
        );
    }

    /// Attempts to create a virtual-memory-backed arena with an explicit commit
    /// growth granularity. Expected reservation/commit setup failures return
    /// false and leave `output` unchanged.
    static bool tryCreateVirtual(
        size_t reservationBytes,
        size_t commitGranularity,
        scope Arena* output,
    ) @system
    {
        version (XTB_Checked)
        {
            require(output !is null, "Arena output pointer is null");
            require(output.allocator_ is null, "Arena output is already initialized");
            require(reservationBytes != 0, "virtual arena reservation size must be nonzero");
            require(commitGranularity != 0, "virtual arena commit granularity must be nonzero");
        }

        if (output is null || reservationBytes == 0 || commitGranularity == 0 ||
            !virtualMemorySupported)
            return false;

        const pageSize = virtualMemoryPageSize();
        size_t normalizedCommitGranularity;
        if (pageSize == 0 ||
            !roundUpToMultiple(
                commitGranularity,
                pageSize,
                &normalizedCommitGranularity,
            ))
            return false;

        VirtualMemoryReservation reservation;
        if (!tryReserveVirtualMemory(reservationBytes, &reservation))
            return false;

        emplace(&output.storage_.data.virtualMemory);
        output.storage_.data.virtualMemory.commitGranularity = normalizedCommitGranularity;
        output.storage_.data.virtualMemory.pageSize = pageSize;
        move_emplace(reservation, output.storage_.data.virtualMemory.reservation);
        output.storage_.kind = ArenaStorageKind.virtualMemory;
        output.allocator_ = &virtualArenaAllocatorProcedure;
        return true;
    }

    /// Creates an arena backed by one contiguous virtual-address reservation.
    /// Panics when the reservation cannot be established.
    static Arena createVirtual(
        size_t reservationBytes,
        size_t commitGranularity = 64 * 1024,
    ) @system
    {
        Arena result;
        if (!tryCreateVirtual(
                reservationBytes,
                commitGranularity,
                &result,
            ))
            panic("virtual arena reservation failed");
        return result;
    }

    Allocator* allocator() return
    {
        return &allocator_;
    }

    void* allocate(size_t size, size_t alignment = (void*).alignof)

    {
        void* result = tryAllocate(size, alignment);
        if (size != 0 && result is null)
            panic("arena allocation failed");
        return result;
    }

    void* tryAllocate(size_t size, size_t alignment = (void*).alignof)

    {
        if (size == 0)
            return null;
        version (XTB_Checked)
            require(isPowerOfTwo(alignment),
                "arena alignment must be a power of two");

        final switch (storage_.kind)
        {
            case ArenaStorageKind.none:
                return null;
            case ArenaStorageKind.chunked:
                return tryAllocateChunked(size, alignment);
            case ArenaStorageKind.virtualMemory:
                return tryAllocateVirtual(size, alignment);
        }
    }

    T* tryAllocate(T)()
    {
        return cast(T*) tryAllocate(T.sizeof, T.alignof);
    }

    T* allocate(T)()
    {
        return cast(T*) allocate(T.sizeof, T.alignof);
    }

    T[] tryAllocateArray(T)(size_t length)
    {
        if (multiply_overflows(T.sizeof, length))
            return null;
        T* data = cast(T*) tryAllocate(
            T.sizeof * length,
            T.alignof,
        );
        if (length != 0 && data is null)
            return null;
        return data[0 .. length];
    }

    T[] allocateArray(T)(size_t length)
    {
        if (multiply_overflows(T.sizeof, length))
            panic("arena allocation size overflow");
        T* data = cast(T*) allocate(
            T.sizeof * length,
            T.alignof,
        );
        return data[0 .. length];
    }

    void* allocateZeroed(size_t size, size_t alignment = (void*).alignof)

    {
        void* result = allocate(size, alignment);
        if (result !is null)
            memset(result, 0, size);
        return result;
    }

    void* tryAllocateZeroed(size_t size, size_t alignment = (void*).alignof)

    {
        void* result = tryAllocate(size, alignment);
        if (result !is null)
            memset(result, 0, size);
        return result;
    }

    T* tryAllocateZeroed(T)() if (__traits(isPOD, T))
    {
        T* result = tryAllocate!T();
        if (result !is null)
            memset(result, 0, T.sizeof);
        return result;
    }

    T* allocateZeroed(T)() if (__traits(isPOD, T))
    {
        T* result = allocate!T();
        memset(result, 0, T.sizeof);
        return result;
    }

    T[] tryAllocateZeroedArray(T)(size_t length) if (__traits(isPOD, T))
    {
        T[] result = tryAllocateArray!T(length);
        if (result.ptr !is null)
            memset(result.ptr, 0, T.sizeof * result.length);
        return result;
    }

    T[] allocateZeroedArray(T)(size_t length) if (__traits(isPOD, T))
    {
        T[] result = allocateArray!T(length);
        if (result.ptr !is null)
            memset(result.ptr, 0, T.sizeof * result.length);
        return result;
    }

    /// Attempts to allocate one `T` and establish its `T.init` lifetime.
    /// Arena reclamation does not run `T`'s destructor; callers that require
    /// destruction must perform it explicitly before abandoning the allocation.
    T* tryAllocateInit(T)()
    {
        T* result = tryAllocate!T();
        if (result !is null)
            emplace(result);
        return result;
    }

    /// Allocates one `T` and establishes its `T.init` lifetime.
    /// Arena reclamation does not run `T`'s destructor.
    T* allocateInit(T)()
    {
        T* result = allocate!T();
        emplace(result);
        return result;
    }

    /// Attempts to allocate and initialize `length` contiguous `T`s.
    /// Any required element destruction remains the caller's responsibility.
    T[] tryAllocateInitArray(T)(size_t length)
    {
        T[] result = tryAllocateArray!T(length);
        foreach (index; 0 .. result.length)
            emplace(result.ptr + index);
        return result;
    }

    /// Allocates and initializes `length` contiguous `T`s.
    /// Any required element destruction remains the caller's responsibility.
    T[] allocateInitArray(T)(size_t length)
    {
        T[] result = allocateArray!T(length);
        foreach (index; 0 .. result.length)
            emplace(result.ptr + index);
        return result;
    }

    /// Attempts to allocate and construct one `T`. Destruction, when required,
    /// must be performed explicitly before arena rewind/reclamation.
    T* tryCreate(T, Args...)(auto ref Args arguments)
    {
        T* result = tryAllocate!T();
        if (result !is null)
            emplace(result, forward!arguments);
        return result;
    }

    /// Allocates and constructs one `T`. Destruction, when required, must be
    /// performed explicitly before arena rewind/reclamation.
    T* create(T, Args...)(auto ref Args arguments)
    {
        T* result = allocate!T();
        emplace(result, forward!arguments);
        return result;
    }

    void clear()
    {
        version (XTB_Checked)
            require(scopeDepth == 0, "cannot clear arena with active temporary scopes");

        final switch (storage_.kind)
        {
            case ArenaStorageKind.none:
                break;
            case ArenaStorageKind.chunked:
                for (ArenaChunk* chunk = storage_.data.chunked.firstChunk; chunk !is null; chunk = chunk
                    .next)
                    chunk.offset = 0;
                storage_.data.chunked.currentChunk = storage_.data.chunked.firstChunk;
                break;
            case ArenaStorageKind.virtualMemory:
                break;
        }

        usedBytes_ = 0;
        version (XTB_Checked)
            ++generation_;
    }

    void deinit()
    {
        version (XTB_Checked)
            require(scopeDepth == 0, "cannot destroy arena with active temporary scopes");

        structuralDeinit(storage_);
        emplace(&storage_);

        allocator_ = null;
        scopeDepth = 0;
        usedBytes_ = 0;
        peakUsedBytes_ = 0;
        retentionLimit = size_t.max;
        version (XTB_Checked)
        {
            poisonRewoundMemory_ = false;
            ++generation_;
        }
    }

    ArenaStats stats() const pure @trusted
    {
        ArenaStats result;
        result.usedBytes = usedBytes_;
        result.peakUsedBytes = peakUsedBytes_;

        final switch (storage_.kind)
        {
            case ArenaStorageKind.none:
                break;
            case ArenaStorageKind.chunked:
                for (const(ArenaChunk)* chunk = storage_.data.chunked.firstChunk; chunk !is null; chunk = chunk
                    .next)
                {
                    result.reservedBytes += chunk.capacity;
                    result.committedBytes += chunk.capacity;
                    ++result.chunkCount;
                }
                break;
            case ArenaStorageKind.virtualMemory:
                result.reservedBytes = storage_.data.virtualMemory.reservation.reservedBytes;
                result.committedBytes = storage_.data.virtualMemory.committedBytes;
                break;
        }
        return result;
    }

    void setRetentionLimit(size_t bytes)
    {
        retentionLimit = bytes;
        if (scopeDepth == 0)
            trimToRetentionLimit();
    }

    void setRewindPoisoning(bool enabled)
    {
        version (XTB_Checked)
            poisonRewoundMemory_ = enabled;
    }

    void trim()
    {
        version (XTB_Checked)
            require(scopeDepth == 0, "cannot trim arena with active temporary scopes");

        final switch (storage_.kind)
        {
            case ArenaStorageKind.none:
                return;
            case ArenaStorageKind.chunked:
            {
                ArenaChunk* keep = storage_.data.chunked.currentChunk;
                if (keep is null)
                {
                    storage_.data.chunked.releaseChunks(storage_.data.chunked.firstChunk);
                    storage_.data.chunked.firstChunk = null;
                    return;
                }
                storage_.data.chunked.releaseChunks(keep.next);
                keep.next = null;
                return;
            }
            case ArenaStorageKind.virtualMemory:
                trimVirtualTo(usedBytes_);
                return;
        }
    }

    private void trimToRetentionLimit()
    {
        if (storage_.kind == ArenaStorageKind.virtualMemory)
        {
            if (retentionLimit >= storage_.data.virtualMemory.committedBytes)
                return;

            size_t retainBytes = retentionLimit;
            if (retainBytes < usedBytes_)
                retainBytes = usedBytes_;
            if (retainBytes > storage_.data.virtualMemory.reservation.reservedBytes)
                retainBytes = storage_.data.virtualMemory.reservation.reservedBytes;
            trimVirtualTo(retainBytes);
            return;
        }

        if (storage_.kind != ArenaStorageKind.chunked)
            return;

        size_t reserved;
        ArenaChunk* previous;
        ArenaChunk* chunk = storage_.data.chunked.firstChunk;
        while (chunk !is null)
        {
            if (chunk is storage_.data.chunked.currentChunk)
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
            storage_.data.chunked.backingAllocator.deallocate(
                chunk,
                chunk.allocationSize,
                ArenaChunk.alignof,
            );
            chunk = next;
        }
        previous.next = chunk;
    }

    private void* tryResizeLastChunked(
        void* oldPointer,
        size_t oldSize,
        size_t newSize,
        size_t alignment,
    ) @system
    {
        ArenaChunk* chunk = storage_.data.chunked.currentChunk;
        if (chunk is null || oldPointer is null || oldSize == 0 ||
            (cast(size_t) oldPointer & (alignment - 1)) != 0)
            return null;

        const baseAddress = cast(size_t) chunk.data;
        const oldAddress = cast(size_t) oldPointer;
        if (oldAddress < baseAddress)
            return null;
        const oldOffset = oldAddress - baseAddress;
        if (oldOffset > chunk.offset || oldSize != chunk.offset - oldOffset)
            return null;
        if (oldOffset > chunk.capacity || newSize > chunk.capacity - oldOffset)
            return null;

        const newOffset = oldOffset + newSize;
        if (newSize >= oldSize)
            usedBytes_ += newSize - oldSize;
        else
            usedBytes_ -= oldSize - newSize;
        chunk.offset = newOffset;
        if (usedBytes_ > peakUsedBytes_)
            peakUsedBytes_ = usedBytes_;
        return oldPointer;
    }

    private void* tryAllocateChunked(size_t size, size_t alignment)
    {
        ArenaChunk* chunk = storage_.data.chunked.currentChunk;
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

    private void* tryResizeLastVirtual(
        void* oldPointer,
        size_t oldSize,
        size_t newSize,
        size_t alignment,
    ) @system
    {
        void* basePointer = storage_.data.virtualMemory.reservation.base;
        if (basePointer is null || oldPointer is null || oldSize == 0 ||
            (cast(size_t) oldPointer & (alignment - 1)) != 0)
            return null;

        const baseAddress = cast(size_t) basePointer;
        const oldAddress = cast(size_t) oldPointer;
        if (oldAddress < baseAddress)
            return null;
        const oldOffset = oldAddress - baseAddress;
        if (oldOffset > usedBytes_ || oldSize != usedBytes_ - oldOffset)
            return null;

        const reservedBytes = storage_.data.virtualMemory.reservation.reservedBytes;
        if (oldOffset > reservedBytes || newSize > reservedBytes - oldOffset)
            return null;
        const newEndOffset = oldOffset + newSize;
        if (newEndOffset > usedBytes_ && !ensureVirtualCommitted(newEndOffset))
            return null;

        usedBytes_ = newEndOffset;
        if (usedBytes_ > peakUsedBytes_)
            peakUsedBytes_ = usedBytes_;
        return oldPointer;
    }

    private void* tryAllocateVirtual(size_t size, size_t alignment) @system
    {
        void* basePointer = storage_.data.virtualMemory.reservation.base;
        if (basePointer is null)
            return null;

        const baseAddress = cast(size_t) basePointer;
        if (usedBytes_ > size_t.max - baseAddress)
            return null;

        size_t alignedAddress;
        if (!alignUp(baseAddress + usedBytes_, alignment, &alignedAddress))
            return null;
        const alignedOffset = alignedAddress - baseAddress;
        const reservedBytes = storage_.data.virtualMemory.reservation.reservedBytes;
        if (alignedOffset > reservedBytes || size > reservedBytes - alignedOffset)
            return null;

        const endOffset = alignedOffset + size;
        if (!ensureVirtualCommitted(endOffset))
            return null;

        void* result = cast(ubyte*) basePointer + alignedOffset;
        usedBytes_ = endOffset;
        if (usedBytes_ > peakUsedBytes_)
            peakUsedBytes_ = usedBytes_;
        return result;
    }

    private bool ensureVirtualCommitted(size_t requiredBytes) @system
    {
        if (requiredBytes <= storage_.data.virtualMemory.committedBytes)
            return true;

        size_t targetBytes;
        if (!roundUpToMultiple(
                requiredBytes,
                storage_.data.virtualMemory.commitGranularity,
                &targetBytes,
            ) ||
            targetBytes > storage_.data.virtualMemory.reservation.reservedBytes)
            targetBytes = storage_.data.virtualMemory.reservation.reservedBytes;

        if (targetBytes < requiredBytes ||
            targetBytes <= storage_.data.virtualMemory.committedBytes)
            return false;

        const bytes = targetBytes - storage_.data.virtualMemory.committedBytes;
        if (!storage_.data.virtualMemory.reservation.tryCommit(
                storage_.data.virtualMemory.committedBytes,
                bytes,
            ))
            return false;

        storage_.data.virtualMemory.committedBytes = targetBytes;
        return true;
    }

    private void trimVirtualTo(size_t keepBytes) @system
    {
        if (!storage_.data.virtualMemory.reservation.active ||
            storage_.data.virtualMemory.committedBytes == 0 ||
            keepBytes >= storage_.data.virtualMemory.committedBytes)
            return;

        if (storage_.data.virtualMemory.pageSize == 0)
            panic("virtual arena page size unavailable");

        size_t targetBytes;
        if (!roundUpToMultiple(keepBytes, storage_.data.virtualMemory.pageSize, &targetBytes) ||
            targetBytes > storage_.data.virtualMemory.reservation.reservedBytes)
            targetBytes = storage_.data.virtualMemory.reservation.reservedBytes;
        if (targetBytes >= storage_.data.virtualMemory.committedBytes)
            return;

        const bytes = storage_.data.virtualMemory.committedBytes - targetBytes;
        if (!storage_.data.virtualMemory.reservation.tryDecommit(targetBytes, bytes))
            panic("virtual arena decommit failed");
        storage_.data.virtualMemory.committedBytes = targetBytes;
    }

    private ArenaChunk* obtainChunk(size_t size, size_t alignment)

    {
        ArenaChunk* tail = storage_.data.chunked.currentChunk;
        ArenaChunk* candidate = storage_.data.chunked.currentChunk is null
            ? storage_.data.chunked.firstChunk : storage_.data.chunked.currentChunk.next;

        while (candidate !is null)
        {
            size_t offset;
            if (alignedOffsetFor(candidate, alignment, &offset) &&
                offset <= candidate.capacity &&
                size <= candidate.capacity - offset)
            {
                storage_.data.chunked.currentChunk = candidate;
                return candidate;
            }
            tail = candidate;
            candidate = candidate.next;
        }

        const capacity = size > storage_.data.chunked.defaultChunkSize
            ? size : storage_.data.chunked.defaultChunkSize;
        ArenaChunk* created = createChunk(capacity, alignment);
        if (created is null)
            return null;
        if (storage_.data.chunked.firstChunk is null)
            storage_.data.chunked.firstChunk = created;
        else
            tail.next = created;
        storage_.data.chunked.currentChunk = created;
        return created;
    }

    private ArenaChunk* createChunk(size_t capacity, size_t alignment)

    {
        const padding = alignment - 1;
        if (add_overflows(ArenaChunk.sizeof, padding) ||
            add_overflows(ArenaChunk.sizeof + padding, capacity))
            return null;

        const allocationSize = ArenaChunk.sizeof + padding + capacity;
        ArenaChunk* chunk = cast(ArenaChunk*) storage_.data.chunked.backingAllocator.tryAllocate(
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
            storage_.data.chunked.backingAllocator.deallocate(
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

static assert(Arena.allocator_.offsetof == 0);

private bool isPowerOfTwo(size_t value) pure @safe
{
    return value != 0 && (value & (value - 1)) == 0;
}

private bool alignUp(size_t value, size_t alignment, size_t* result)
pure @safe
{
    const mask = alignment - 1;
    if (value > size_t.max - mask)
        return false;
    *result = (value + mask) & ~mask;
    return true;
}

private bool roundUpToMultiple(
    size_t value,
    size_t multiple,
    size_t* result,
) pure @safe
{
    if (multiple == 0)
        return false;
    const remainder = value % multiple;
    if (remainder == 0)
    {
        *result = value;
        return true;
    }

    const increment = multiple - remainder;
    if (value > size_t.max - increment)
        return false;
    *result = value + increment;
    return true;
}

private bool alignedOffsetFor(
    ArenaChunk* chunk,
    size_t alignment,
    size_t* result,
) pure @system
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

private extern (C) void* chunkedArenaAllocatorProcedure(
    void* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
)
{
    Arena* arena = cast(Arena*) allocator;
    if (newSize == 0)
        return null;
    version (XTB_Checked)
    {
        require(arena.storage_.kind == ArenaStorageKind.chunked,
            "chunked arena allocator procedure used with a different backing");
        require(isPowerOfTwo(alignment),
            "arena alignment must be a power of two");
    }

    if (oldPointer !is null && oldSize != 0)
    {
        void* resized = arena.tryResizeLastChunked(
            oldPointer,
            oldSize,
            newSize,
            alignment,
        );
        if (resized !is null)
            return resized;
    }

    void* replacement = arena.tryAllocateChunked(newSize, alignment);
    if (replacement is null)
        return null;
    if (oldPointer !is null && oldSize != 0)
    {
        const amount = oldSize < newSize ? oldSize : newSize;
        memcpy(replacement, oldPointer, amount);
    }
    return replacement;
}

private extern (C) void* virtualArenaAllocatorProcedure(
    void* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
)
{
    Arena* arena = cast(Arena*) allocator;
    if (newSize == 0)
        return null;
    version (XTB_Checked)
    {
        require(arena.storage_.kind == ArenaStorageKind.virtualMemory,
            "virtual arena allocator procedure used with a different backing");
        require(isPowerOfTwo(alignment),
            "arena alignment must be a power of two");
    }

    if (oldPointer !is null && oldSize != 0)
    {
        void* resized = arena.tryResizeLastVirtual(
            oldPointer,
            oldSize,
            newSize,
            alignment,
        );
        if (resized !is null)
            return resized;
    }

    void* replacement = arena.tryAllocateVirtual(newSize, alignment);
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
nothrow @nogc:

    private Arena* arena_;
    private ArenaChunk* chunk_;
    private size_t chunkOffset_;
    private size_t usedBytes_;
    version (XTB_Checked)
    {
        private size_t depth_;
        private size_t generation_;
        private void* threadToken_;
    }
    private bool active_;

    @disable this(this);

    Arena* arena() return
    {
        version (XTB_Checked)
            require(active_, "inactive temporary arena");
        return arena_;
    }

    Allocator* allocator() return
    {
        return arena.allocator;
    }

    bool active() const pure @safe
    {
        return active_;
    }
}

TempArena push(Arena* arena)
{
    version (XTB_Checked)
        require(arena !is null, "cannot push a null arena");

    TempArena result;
    result.arena_ = arena;
    final switch (arena.storage_.kind)
    {
        case ArenaStorageKind.none:
            break;
        case ArenaStorageKind.chunked:
            result.chunk_ = arena.storage_.data.chunked.currentChunk;
            result.chunkOffset_ = result.chunk_ is null ? 0 : result.chunk_.offset;
            break;
        case ArenaStorageKind.virtualMemory:
            break;
    }
    ++arena.scopeDepth;
    result.usedBytes_ = arena.usedBytes_;
    version (XTB_Checked)
    {
        result.depth_ = arena.scopeDepth;
        result.generation_ = arena.generation_;
        result.threadToken_ = currentThreadToken();
    }
    result.active_ = true;
    return result;
}

void pop(ref TempArena temporary)
{
    version (XTB_Checked)
        require(temporary.active_, "temporary arena already popped");
    Arena* arena = temporary.arena_;
    version (XTB_Checked)
    {
        require(arena !is null, "temporary arena has no arena");
        require(temporary.threadToken_ is currentThreadToken(),
            "temporary arena popped on a different thread");
        require(arena.generation_ == temporary.generation_,
            "temporary arena checkpoint generation mismatch");
        require(arena.scopeDepth == temporary.depth_, "temporary arenas must pop in LIFO order");
    }

    version (XTB_Checked)
    {
        if (arena.poisonRewoundMemory_)
        {
            final switch (arena.storage_.kind)
            {
                case ArenaStorageKind.none:
                    break;
                case ArenaStorageKind.chunked:
                {
                    ArenaChunk* chunk = temporary.chunk_ is null
                        ? arena.storage_.data.chunked.firstChunk : temporary.chunk_;
                    bool first = true;
                    for (; chunk !is null; chunk = chunk.next)
                    {
                        const begin = first && temporary.chunk_ !is null
                            ? temporary.chunkOffset_ : 0;
                        if (chunk.offset > begin)
                            memset(chunk.data + begin, 0xDD, chunk.offset - begin);
                        first = false;
                    }
                    break;
                }
                case ArenaStorageKind.virtualMemory:
                    if (arena.usedBytes_ > temporary.usedBytes_)
                        memset(
                            cast(ubyte*) arena.storage_.data.virtualMemory.reservation.base +
                                temporary.usedBytes_,
                            0xDD,
                            arena.usedBytes_ - temporary.usedBytes_,
                        );
                    break;
            }
        }
    }

    final switch (arena.storage_.kind)
    {
        case ArenaStorageKind.none:
            break;
        case ArenaStorageKind.chunked:
            if (temporary.chunk_ is null)
            {
                for (ArenaChunk* chunk = arena.storage_.data.chunked.firstChunk; chunk !is null; chunk = chunk
                    .next)
                    chunk.offset = 0;
                arena.storage_.data.chunked.currentChunk = arena.storage_.data.chunked.firstChunk;
            }
            else
            {
                temporary.chunk_.offset = temporary.chunkOffset_;
                for (ArenaChunk* chunk = temporary.chunk_.next; chunk !is null; chunk = chunk.next)
                    chunk.offset = 0;
                arena.storage_.data.chunked.currentChunk = temporary.chunk_;
            }
            break;
        case ArenaStorageKind.virtualMemory:
            break;
    }

    --arena.scopeDepth;
    arena.usedBytes_ = temporary.usedBytes_;
    if (arena.scopeDepth == 0)
        arena.trimToRetentionLimit();
    temporary.arena_ = null;
    temporary.chunk_ = null;
    temporary.chunkOffset_ = 0;
    temporary.usedBytes_ = 0;
    version (XTB_Checked)
    {
        temporary.depth_ = 0;
        temporary.generation_ = 0;
        temporary.threadToken_ = null;
    }
    temporary.active_ = false;
}

unittest
{
    import xtb.allocators.malloc : mallocAllocator;
    import xtb.lifetime : move, move_assign;

    static assert(!__traits(hasMember, VirtualArenaStorage, "offset"));
    static assert(!__traits(hasMember, TempArena, "offset_"));
    static assert(__traits(hasMember, TempArena, "chunkOffset_"));

    version (XTB_Checked)
    {
        static assert(__traits(hasMember, Arena, "generation_"));
        static assert(__traits(hasMember, Arena, "poisonRewoundMemory_"));
        static assert(__traits(hasMember, TempArena, "depth_"));
        static assert(__traits(hasMember, TempArena, "generation_"));
        static assert(__traits(hasMember, TempArena, "threadToken_"));
    }
    else
    {
        static assert(!__traits(hasMember, Arena, "generation_"));
        static assert(!__traits(hasMember, Arena, "poisonRewoundMemory_"));
        static assert(!__traits(hasMember, TempArena, "depth_"));
        static assert(!__traits(hasMember, TempArena, "generation_"));
        static assert(!__traits(hasMember, TempArena, "threadToken_"));
    }

    Arena arena = Arena.create(mallocAllocator(), 64);
    assert(arena.storage_.kind == ArenaStorageKind.chunked);
    assert(*arena.allocator == &chunkedArenaAllocatorProcedure);
    int* persistent = arena.allocate!int();
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
    assert(arena.stats.committedBytes == arena.stats.reservedBytes);

    int* typed = arena.allocate!int();
    *typed = 17;
    assert(*typed == 17);

    int[] typedArray = arena.allocateArray!int(4);
    assert(typedArray.length == 4);
    typedArray[3] = 23;
    assert(typedArray[3] == 23);

    struct Initialized
    {
        uint value = 0xABCD_EF01;
    }

    Initialized* initialized = arena.allocateInit!Initialized();
    assert(initialized.value == Initialized.init.value);
    Initialized[] initializedArray = arena.allocateInitArray!Initialized(2);
    assert(initializedArray.length == 2);
    assert(initializedArray[1].value == Initialized.init.value);

    Initialized* zeroed = arena.allocateZeroed!Initialized();
    assert(zeroed.value == 0);
    Initialized[] zeroedArray = arena.allocateZeroedArray!Initialized(2);
    assert(zeroedArray[1].value == 0);

    struct Constructed
    {
    nothrow @nogc:

        int value;

        this(int value)
        {
            this.value = value;
        }
    }

    Constructed* constructed = arena.create!Constructed(91);
    assert(constructed.value == 91);

    import xtb.memory : allocateInit, reallocate;

    Allocator* arenaAllocator = arena.allocator;
    int* throughAllocator = arenaAllocator.allocateInit!int();
    assert(*throughAllocator == int.init);
    ubyte* allocatorBytes = cast(ubyte*) arenaAllocator.allocate(4, 1);
    allocatorBytes[0] = 0x12;
    allocatorBytes[3] = 0x34;
    ubyte* reallocatedBytes = cast(ubyte*) arenaAllocator.reallocate(
        8,
        allocatorBytes,
        4,
        1,
    );
    assert(reallocatedBytes is allocatorBytes);
    assert(reallocatedBytes[0] == 0x12);
    assert(reallocatedBytes[3] == 0x34);

    Arena reallocArena = Arena.create(mallocAllocator(), 64);
    Allocator* reallocAllocator = reallocArena.allocator;
    const chunkedUsedBefore = reallocArena.stats.usedBytes;
    ubyte* chunkedTail = cast(ubyte*) reallocAllocator.allocate(8, 1);
    chunkedTail[0] = 0xA1;
    chunkedTail[7] = 0xB2;
    ubyte* grownChunkedTail = cast(ubyte*) reallocAllocator.reallocate(
        16,
        chunkedTail,
        8,
        1,
    );
    assert(grownChunkedTail is chunkedTail);
    assert(grownChunkedTail[0] == 0xA1);
    assert(grownChunkedTail[7] == 0xB2);
    assert(reallocArena.stats.usedBytes == chunkedUsedBefore + 16);
    ubyte* shrunkChunkedTail = cast(ubyte*) reallocAllocator.reallocate(
        4,
        grownChunkedTail,
        16,
        1,
    );
    assert(shrunkChunkedTail is chunkedTail);
    assert(reallocArena.stats.usedBytes == chunkedUsedBefore + 4);
    assert(reallocAllocator.allocate(1, 1) == shrunkChunkedTail + 4);

    ubyte* nonLastChunked = cast(ubyte*) reallocAllocator.allocate(4, 1);
    nonLastChunked[0] = 0xC3;
    cast(void) reallocAllocator.allocate(4, 1);
    ubyte* movedChunked = cast(ubyte*) reallocAllocator.reallocate(
        8,
        nonLastChunked,
        4,
        1,
    );
    assert(movedChunked !is nonLastChunked);
    assert(movedChunked[0] == 0xC3);

    ubyte* deallocatedChunked = cast(ubyte*) reallocAllocator.allocate(4, 1);
    const chunkedUsedBeforeDeallocate = reallocArena.stats.usedBytes;
    reallocAllocator.deallocate(deallocatedChunked, 4, 1);
    assert(reallocArena.stats.usedBytes == chunkedUsedBeforeDeallocate);
    assert(reallocAllocator.allocate(1, 1) == deallocatedChunked + 4);
    reallocArena.deinit();

    arena.setRewindPoisoning(true);
    TempArena poisoned = (&arena).push();
    ubyte* bytes = cast(ubyte*) arena.allocate(8, 1);
    bytes[0] = 1;
    poisoned.pop();
    assert(bytes[0] == 0xDD);
    arena.setRetentionLimit(64);
    arena.trim();
    arena.deinit();
    assert(arena.storage_.kind == ArenaStorageKind.none);

    version (linux)
    {
        const pageSize = virtualMemoryPageSize();
        assert(pageSize != 0);

        Arena virtualArena = Arena.createVirtual(
            pageSize * 8,
            pageSize * 2,
        );
        assert(virtualArena.storage_.kind == ArenaStorageKind.virtualMemory);
        assert(*virtualArena.allocator == &virtualArenaAllocatorProcedure);
        ArenaStats initialVirtualStats = virtualArena.stats;
        assert(initialVirtualStats.usedBytes == 0);
        assert(initialVirtualStats.reservedBytes == pageSize * 8);
        assert(initialVirtualStats.committedBytes == 0);
        assert(initialVirtualStats.chunkCount == 0);

        ubyte* firstVirtual = cast(ubyte*) virtualArena.allocate(1, 1);
        assert(firstVirtual !is null);
        *firstVirtual = 0x7B;
        assert(virtualArena.stats.committedBytes == pageSize * 2);

        TempArena virtualTemporary = (&virtualArena).push();
        ubyte* temporaryBytes = cast(ubyte*) virtualArena.allocate(
            pageSize * 2,
            1,
        );
        temporaryBytes[0] = 0x42;
        const committedHighWater = virtualArena.stats.committedBytes;
        virtualTemporary.pop();
        assert(*firstVirtual == 0x7B);
        assert(virtualArena.stats.committedBytes == committedHighWater);

        ubyte* reusedTemporary = cast(ubyte*) virtualArena.allocate(
            pageSize * 2,
            1,
        );
        assert(reusedTemporary is temporaryBytes);

        virtualArena.setRewindPoisoning(true);
        TempArena poisonedVirtual = (&virtualArena).push();
        ubyte* poisonedVirtualBytes = cast(ubyte*) virtualArena.allocate(8, 1);
        poisonedVirtualBytes[0] = 1;
        poisonedVirtual.pop();
        assert(poisonedVirtualBytes[0] == 0xDD);
        virtualArena.setRewindPoisoning(false);

        virtualArena.clear();
        assert(virtualArena.stats.usedBytes == 0);
        assert(virtualArena.stats.committedBytes == committedHighWater);
        virtualArena.setRetentionLimit(pageSize);
        assert(virtualArena.stats.committedBytes == pageSize);

        TempArena retainedVirtual = (&virtualArena).push();
        assert(virtualArena.allocate(pageSize * 3, 1) !is null);
        assert(virtualArena.stats.committedBytes > pageSize);
        retainedVirtual.pop();
        assert(virtualArena.stats.usedBytes == 0);
        assert(virtualArena.stats.committedBytes == pageSize);

        ubyte* beforeTrim = cast(ubyte*) virtualArena.allocate(1, 1);
        beforeTrim[0] = 0xA5;
        virtualArena.clear();
        virtualArena.trim();
        assert(virtualArena.stats.committedBytes == 0);
        ubyte* afterTrim = cast(ubyte*) virtualArena.allocate(1, 1);
        assert(afterTrim is beforeTrim);
        assert(afterTrim[0] == 0);

        Allocator* virtualAllocator = virtualArena.allocator;
        int* throughVirtualAllocator = virtualAllocator.allocateInit!int();
        assert(*throughVirtualAllocator == int.init);
        ubyte* virtualAllocatorBytes = cast(ubyte*) virtualAllocator.allocate(4, 1);
        virtualAllocatorBytes[0] = 0x56;
        virtualAllocatorBytes[3] = 0x78;
        ubyte* virtualReallocatedBytes = cast(ubyte*) virtualAllocator.reallocate(
            8,
            virtualAllocatorBytes,
            4,
            1,
        );
        assert(virtualReallocatedBytes is virtualAllocatorBytes);
        assert(virtualReallocatedBytes[0] == 0x56);
        assert(virtualReallocatedBytes[3] == 0x78);

        Arena virtualReallocArena = Arena.createVirtual(pageSize * 4, pageSize);
        Allocator* virtualReallocAllocator = virtualReallocArena.allocator;
        ubyte* virtualTail = cast(ubyte*) virtualReallocAllocator.allocate(
            pageSize - 8,
            1,
        );
        virtualTail[0] = 0xD4;
        assert(virtualReallocArena.stats.committedBytes == pageSize);
        ubyte* grownVirtualTail = cast(ubyte*) virtualReallocAllocator.reallocate(
            pageSize + 8,
            virtualTail,
            pageSize - 8,
            1,
        );
        assert(grownVirtualTail is virtualTail);
        assert(grownVirtualTail[0] == 0xD4);
        assert(virtualReallocArena.stats.usedBytes == pageSize + 8);
        assert(virtualReallocArena.stats.committedBytes == pageSize * 2);
        ubyte* shrunkVirtualTail = cast(ubyte*) virtualReallocAllocator.reallocate(
            4,
            grownVirtualTail,
            pageSize + 8,
            1,
        );
        assert(shrunkVirtualTail is virtualTail);
        assert(virtualReallocArena.stats.usedBytes == 4);
        assert(virtualReallocArena.stats.committedBytes == pageSize * 2);
        assert(virtualReallocAllocator.allocate(1, 1) == shrunkVirtualTail + 4);

        ubyte* nonLastVirtual = cast(ubyte*) virtualReallocAllocator.allocate(4, 1);
        nonLastVirtual[0] = 0xE5;
        cast(void) virtualReallocAllocator.allocate(4, 1);
        ubyte* relocatedVirtual = cast(ubyte*) virtualReallocAllocator.reallocate(
            8,
            nonLastVirtual,
            4,
            1,
        );
        assert(relocatedVirtual !is nonLastVirtual);
        assert(relocatedVirtual[0] == 0xE5);

        ubyte* deallocatedVirtual = cast(ubyte*) virtualReallocAllocator.allocate(4, 1);
        const virtualUsedBeforeDeallocate = virtualReallocArena.stats.usedBytes;
        virtualReallocAllocator.deallocate(deallocatedVirtual, 4, 1);
        assert(virtualReallocArena.stats.usedBytes == virtualUsedBeforeDeallocate);
        assert(virtualReallocAllocator.allocate(1, 1) == deallocatedVirtual + 4);
        virtualReallocArena.deinit();

        virtualArena.deinit();
        assert(virtualArena.storage_.kind == ArenaStorageKind.none);
        assert(virtualArena.stats.reservedBytes == 0);
        assert(virtualArena.stats.committedBytes == 0);
        virtualArena.deinit();

        Arena tinyVirtual;
        assert(Arena.tryCreateVirtual(
                pageSize * 2,
                pageSize,
                &tinyVirtual,
        ));
        assert(tinyVirtual.tryAllocate(pageSize * 2, 1) !is null);
        const fullStats = tinyVirtual.stats;
        assert(fullStats.usedBytes == pageSize * 2);
        assert(fullStats.committedBytes == pageSize * 2);
        assert(tinyVirtual.tryAllocate(1, 1) is null);
        assert(tinyVirtual.stats.usedBytes == fullStats.usedBytes);
        tinyVirtual.deinit();

        Arena roundedVirtual = Arena.createVirtual(
            pageSize * 4 + 1,
            pageSize + 1,
        );
        assert(roundedVirtual.stats.reservedBytes == pageSize * 5);
        assert(roundedVirtual.allocate(1, 1) !is null);
        assert(roundedVirtual.stats.committedBytes == pageSize * 2);
        roundedVirtual.deinit();

        Arena failedVirtual;
        assert(!Arena.tryCreateVirtual(size_t.max, &failedVirtual));
        assert(failedVirtual.stats.reservedBytes == 0);
        failedVirtual.deinit();

        Arena movingVirtual = Arena.createVirtual(pageSize * 2, pageSize);
        int* movedValue = movingVirtual.allocate!int();
        *movedValue = 77;
        Arena movedVirtual = move(movingVirtual);
        assert(movingVirtual.storage_.kind == ArenaStorageKind.none);
        assert(*movingVirtual.allocator is null);
        assert(movedVirtual.storage_.kind == ArenaStorageKind.virtualMemory);
        assert(*movedVirtual.allocator == &virtualArenaAllocatorProcedure);
        assert(movingVirtual.stats.reservedBytes == 0);
        assert(*movedValue == 77);
        movingVirtual.deinit();
        movedVirtual.deinit();

        Arena replacementTarget = Arena.create(mallocAllocator(), 64);
        assert(*replacementTarget.allocator == &chunkedArenaAllocatorProcedure);
        replacementTarget.allocate(8, 8);
        Arena replacementSource = Arena.createVirtual(pageSize * 2, pageSize);
        int* replacementValue = replacementSource.allocate!int();
        *replacementValue = 23;
        move_assign(replacementSource, replacementTarget);
        assert(replacementSource.stats.reservedBytes == 0);
        assert(*replacementSource.allocator is null);
        assert(*replacementTarget.allocator == &virtualArenaAllocatorProcedure);
        assert(replacementTarget.stats.chunkCount == 0);
        assert(replacementTarget.stats.reservedBytes == pageSize * 2);
        assert(*replacementValue == 23);
        replacementSource.deinit();
        replacementTarget.deinit();
    }
    else
    {
        Arena unavailableVirtual;
        assert(!Arena.tryCreateVirtual(4096, &unavailableVirtual));
        assert(unavailableVirtual.stats.reservedBytes == 0);
        unavailableVirtual.deinit();
    }

    struct ArenaConstructed
    {
    nothrow @nogc:

        int* destroyed;

        this(int* destroyed)
        {
            this.destroyed = destroyed;
        }

        ~this()
        {
            if (destroyed !is null)
                ++*destroyed;
        }
    }

    import xtb.memory : dispose, disposeArray;

    int destructorCalls;
    Arena destructorArena = Arena.create(mallocAllocator(), 64);

    ArenaConstructed* initializedDestructor =
        destructorArena.allocateInit!ArenaConstructed();
    initializedDestructor.destroyed = &destructorCalls;
    destroy(*initializedDestructor);
    assert(destructorCalls == 1);

    ArenaConstructed* tryInitializedDestructor =
        destructorArena.tryAllocateInit!ArenaConstructed();
    assert(tryInitializedDestructor !is null);
    tryInitializedDestructor.destroyed = &destructorCalls;
    destructorArena.allocator.dispose(tryInitializedDestructor);
    assert(destructorCalls == 2);

    ArenaConstructed[] initializedDestructors =
        destructorArena.allocateInitArray!ArenaConstructed(2);
    foreach (ref value; initializedDestructors)
        value.destroyed = &destructorCalls;
    destructorArena.allocator.disposeArray(initializedDestructors);
    assert(destructorCalls == 4);

    ArenaConstructed[] tryInitializedDestructors =
        destructorArena.tryAllocateInitArray!ArenaConstructed(2);
    assert(tryInitializedDestructors.length == 2);
    foreach (ref value; tryInitializedDestructors)
        value.destroyed = &destructorCalls;
    foreach_reverse (ref value; tryInitializedDestructors)
        destroy(value);
    assert(destructorCalls == 6);

    ArenaConstructed* constructedDestructor =
        destructorArena.create!ArenaConstructed(&destructorCalls);
    destructorArena.allocator.dispose(constructedDestructor);
    assert(destructorCalls == 7);

    ArenaConstructed* tryConstructedDestructor =
        destructorArena.tryCreate!ArenaConstructed(&destructorCalls);
    assert(tryConstructedDestructor !is null);
    destroy(*tryConstructedDestructor);
    assert(destructorCalls == 8);
    destructorArena.deinit();

    version (linux)
    {
        int virtualDestructorCalls;
        const virtualDestructorPageSize = virtualMemoryPageSize();
        Arena virtualDestructorArena = Arena.createVirtual(
            virtualDestructorPageSize * 2,
            virtualDestructorPageSize,
        );
        virtualDestructorArena.create!ArenaConstructed(
            &virtualDestructorCalls,
        );
        virtualDestructorArena.clear();
        assert(virtualDestructorCalls == 0);
        virtualDestructorArena.create!ArenaConstructed(
            &virtualDestructorCalls,
        );
        virtualDestructorArena.deinit();
        assert(virtualDestructorCalls == 0);
    }

    static assert(hasElaborateDestructor!ArenaConstructed);
    static assert(__traits(compiles, (ref Arena value) {
            value.create!ArenaConstructed(cast(int*) null);
        }));
    static assert(__traits(compiles, (ref Arena value) { value.allocateInit!ArenaConstructed(); }));
    static assert(__traits(compiles, (ref Arena value) {
            value.allocateInitArray!ArenaConstructed(2);
        }));

    static assert(!hasElaborateDestructor!Arena);
    static assert(needs_deinit!Arena);
    static assert(__traits(compiles, (ref Arena value) @safe { ArenaStats snapshot = value.stats(); }));
    static assert(!__traits(compiles, (ref Arena left, ref Arena right) { left = right; }));

    int explicitDeinits;
    struct ExplicitOwner
    {
    nothrow @nogc:

        int* deinits;

        void deinit()
        {
            ++*deinits;
        }
    }

    Arena abandonment = Arena.create(mallocAllocator(), 64);
    ExplicitOwner* abandoned = abandonment.create!ExplicitOwner();
    abandoned.deinits = &explicitDeinits;
    ArenaConstructed* abandonedDestructor =
        abandonment.create!ArenaConstructed(&destructorCalls);
    abandonment.clear();
    assert(explicitDeinits == 0);
    assert(destructorCalls == 8);
    abandoned = abandonment.create!ExplicitOwner();
    abandoned.deinits = &explicitDeinits;
    abandonedDestructor = abandonment.create!ArenaConstructed(&destructorCalls);
    abandonment.deinit();
    assert(explicitDeinits == 0);
    assert(destructorCalls == 8);

    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;

    AllocationRecord[4] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(), records[],
    );
    failing.failAfter(0);
    Arena fallible = Arena.create(failing.allocator, 64);
    assert(fallible.tryAllocate(8, 8) is null);
    assert(fallible.tryAllocate!int() is null);
    assert(fallible.tryAllocateArray!int(2).length == 0);
    assert(fallible.tryAllocateInit!int() is null);
    assert(fallible.tryAllocateInit!ArenaConstructed() is null);
    assert(fallible.tryAllocateInitArray!ArenaConstructed(2).length == 0);
    assert(fallible.tryCreate!Constructed(4) is null);
    assert(fallible.tryCreate!ArenaConstructed(&destructorCalls) is null);
    assert(destructorCalls == 8);
    assert(fallible.stats.chunkCount == 0);
    fallible.deinit();
}
