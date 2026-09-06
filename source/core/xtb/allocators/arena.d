module xtb.allocators.arena;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.lifetime : emplace, forward;
import core.stdc.string : memcpy, memset;
import xtb.allocators.internal.virtual_memory;
import xtb.lifetime;
import xtb.memory;
import xtb.numeric;
import xtb.panic;
import xtb.types;

private enum ArenaStorageKind : u8
{
    none,
    chunked,
    virtual_memory,
}

private struct ArenaChunk
{
    ArenaChunk* next;
    usize allocation_size;
    usize capacity;
    usize offset;
    u8* data;
}

private struct ChunkedArenaStorage
{
nothrow @nogc:

    Allocator* backing_allocator;
    ArenaChunk* first_chunk;
    ArenaChunk* current_chunk;
    usize default_chunk_size;

    void deinit()
    {
        release_chunks(first_chunk);
        backing_allocator = null;
        first_chunk = null;
        current_chunk = null;
        default_chunk_size = 0;
    }

    void release_chunks(ArenaChunk* first)
    {
        ArenaChunk* chunk = first;
        while (chunk !is null)
        {
            ArenaChunk* next = chunk.next;
            backing_allocator.deallocate(
                chunk,
                chunk.allocation_size,
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
    usize committed_bytes;
    usize commit_granularity;
    usize page_size;

    void deinit() @system
    {
        xtb.lifetime.deinit(reservation);
        committed_bytes = 0;
        commit_granularity = 0;
        page_size = 0;
    }
}

private union ArenaStorage
{
    ChunkedArenaStorage chunked;
    VirtualArenaStorage virtual_memory;
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
    usize used_bytes;
    /// Chunk payload capacity or the complete virtual-address reservation.
    usize reserved_bytes;
    /// Reusable chunk payload capacity or the accessible virtual-memory
    /// prefix.
    usize committed_bytes;
    /// Highest `used_bytes` observed since creation.
    usize peak_used_bytes;
    /// Number of allocator-backed chunks; zero for a virtual-memory-backed
    /// arena.
    usize chunk_count;
}

version (XTB_Checked)
{
    private i32 tls_thread_marker;

    private void* current_thread_token()
    {
        return &tls_thread_marker;
    }
}

struct Arena
{
nothrow @nogc:

    Allocator allocator_procedure;
    ArenaStorageState storage;
    usize scope_depth;
    usize used_bytes;
    usize peak_used_bytes;
    usize retention_limit = usize.max;
    version (XTB_Checked)
    {
        usize generation = 1;
        bool poison_rewound_memory;
    }

    @disable this(this);
    @disable ref Arena opAssign(Arena source) return;

    static Arena create(
        Allocator* backing_allocator,
        usize default_chunk_size = 64 * 1024,
    )
    {
        version (XTB_Checked)
        {
            require(backing_allocator !is null && *backing_allocator !is null,
                "arena requires a valid backing allocator");
            require(default_chunk_size != 0, "arena chunk size must be nonzero");
        }

        Arena result;
        emplace(&result.storage.data.chunked);
        result.storage.data.chunked.backing_allocator = backing_allocator;
        result.storage.data.chunked.default_chunk_size = default_chunk_size;
        result.storage.kind = ArenaStorageKind.chunked;
        result.allocator_procedure = &chunked_arena_allocator_procedure;
        return result;
    }

    /// Attempts to create an arena backed by one contiguous virtual-address
    /// reservation. The reservation is the fixed maximum storage capacity, is
    /// inaccessible initially, and becomes readable/writable in
    /// `commit_granularity` increments as allocation grows. The reservation size
    /// and commit granularity are rounded up to native page boundaries.
    /// `try_allocate` returns null once the fixed reservation is exhausted.
    static bool try_create_virtual(
        usize reservation_bytes,
        scope Arena* output,
    ) @system
    {
        return try_create_virtual(
            reservation_bytes,
            64 * 1024,
            output,
        );
    }

    /// Attempts to create a virtual-memory-backed arena with an explicit commit
    /// growth granularity. Expected reservation/commit setup failures return
    /// false and leave `output` unchanged.
    static bool try_create_virtual(
        usize reservation_bytes,
        usize commit_granularity,
        scope Arena* output,
    ) @system
    {
        version (XTB_Checked)
        {
            require(output !is null, "Arena output pointer is null");
            require(output.allocator_procedure is null, "Arena output is already initialized");
            require(reservation_bytes != 0, "virtual arena reservation size must be nonzero");
            require(commit_granularity != 0, "virtual arena commit granularity must be nonzero");
        }

        if (output is null || reservation_bytes == 0 || commit_granularity == 0 ||
            !virtual_memory_supported)
            return false;

        const page_size = virtual_memory_page_size();
        usize normalized_commit_granularity;
        if (page_size == 0 ||
            !round_up_to_multiple(
                commit_granularity,
                page_size,
                &normalized_commit_granularity,
            ))
            return false;

        VirtualMemoryReservation reservation;
        if (!try_reserve_virtual_memory(reservation_bytes, &reservation))
            return false;

        emplace(&output.storage.data.virtual_memory);
        output.storage.data.virtual_memory.commit_granularity = normalized_commit_granularity;
        output.storage.data.virtual_memory.page_size = page_size;
        move_emplace(reservation, output.storage.data.virtual_memory.reservation);
        output.storage.kind = ArenaStorageKind.virtual_memory;
        output.allocator_procedure = &virtual_arena_allocator_procedure;
        return true;
    }

    /// Creates an arena backed by one contiguous virtual-address reservation.
    /// Panics when the reservation cannot be established.
    static Arena create_virtual(
        usize reservation_bytes,
        usize commit_granularity = 64 * 1024,
    ) @system
    {
        Arena result;
        if (!try_create_virtual(
                reservation_bytes,
                commit_granularity,
                &result,
            ))
            panic("virtual arena reservation failed");
        return result;
    }

    Allocator* allocator() return
    {
        return &allocator_procedure;
    }

    void* allocate(usize size, usize alignment = (void*).alignof)

    {
        void* result = try_allocate(size, alignment);
        if (size != 0 && result is null)
            panic("arena allocation failed");
        return result;
    }

    void* try_allocate(usize size, usize alignment = (void*).alignof)

    {
        if (size == 0)
            return null;
        version (XTB_Checked)
            require(is_power_of_two(alignment),
                "arena alignment must be a power of two");

        final switch (storage.kind)
        {
            case ArenaStorageKind.none:
                return null;
            case ArenaStorageKind.chunked:
                return try_allocate_chunked(size, alignment);
            case ArenaStorageKind.virtual_memory:
                return try_allocate_virtual(size, alignment);
        }
    }

    T* try_allocate(T)()
    {
        return cast(T*) try_allocate(T.sizeof, T.alignof);
    }

    T* allocate(T)()
    {
        return cast(T*) allocate(T.sizeof, T.alignof);
    }

    T[] try_allocate_array(T)(usize length)
    {
        if (multiply_overflows(T.sizeof, length))
            return null;
        T* data = cast(T*) try_allocate(
            T.sizeof * length,
            T.alignof,
        );
        if (length != 0 && data is null)
            return null;
        return data[0 .. length];
    }

    T[] allocate_array(T)(usize length)
    {
        if (multiply_overflows(T.sizeof, length))
            panic("arena allocation size overflow");
        T* data = cast(T*) allocate(
            T.sizeof * length,
            T.alignof,
        );
        return data[0 .. length];
    }

    void* allocate_zeroed(usize size, usize alignment = (void*).alignof)

    {
        void* result = allocate(size, alignment);
        if (result !is null)
            memset(result, 0, size);
        return result;
    }

    void* try_allocate_zeroed(usize size, usize alignment = (void*).alignof)

    {
        void* result = try_allocate(size, alignment);
        if (result !is null)
            memset(result, 0, size);
        return result;
    }

    T* try_allocate_zeroed(T)() if (__traits(isPOD, T))
    {
        T* result = try_allocate!T();
        if (result !is null)
            memset(result, 0, T.sizeof);
        return result;
    }

    T* allocate_zeroed(T)() if (__traits(isPOD, T))
    {
        T* result = allocate!T();
        memset(result, 0, T.sizeof);
        return result;
    }

    T[] try_allocate_zeroed_array(T)(usize length) if (__traits(isPOD, T))
    {
        T[] result = try_allocate_array!T(length);
        if (result.ptr !is null)
            memset(result.ptr, 0, T.sizeof * result.length);
        return result;
    }

    T[] allocate_zeroed_array(T)(usize length) if (__traits(isPOD, T))
    {
        T[] result = allocate_array!T(length);
        if (result.ptr !is null)
            memset(result.ptr, 0, T.sizeof * result.length);
        return result;
    }

    /// Attempts to allocate one `T` and establish its `T.init` lifetime.
    /// Arena reclamation does not run `T`'s destructor; callers that require
    /// destruction must perform it explicitly before abandoning the allocation.
    T* try_allocate_init(T)()
    {
        T* result = try_allocate!T();
        if (result !is null)
            emplace(result);
        return result;
    }

    /// Allocates one `T` and establishes its `T.init` lifetime.
    /// Arena reclamation does not run `T`'s destructor.
    T* allocate_init(T)()
    {
        T* result = allocate!T();
        emplace(result);
        return result;
    }

    /// Attempts to allocate and initialize `length` contiguous `T`s.
    /// Any required element destruction remains the caller's responsibility.
    T[] try_allocate_init_array(T)(usize length)
    {
        T[] result = try_allocate_array!T(length);
        foreach (index; 0 .. result.length)
            emplace(result.ptr + index);
        return result;
    }

    /// Allocates and initializes `length` contiguous `T`s.
    /// Any required element destruction remains the caller's responsibility.
    T[] allocate_init_array(T)(usize length)
    {
        T[] result = allocate_array!T(length);
        foreach (index; 0 .. result.length)
            emplace(result.ptr + index);
        return result;
    }

    /// Attempts to allocate and construct one `T`. Destruction, when required,
    /// must be performed explicitly before arena rewind/reclamation.
    T* try_create(T, Args...)(auto ref Args arguments)
    {
        T* result = try_allocate!T();
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
            require(scope_depth == 0, "cannot clear arena with active temporary scopes");

        final switch (storage.kind)
        {
            case ArenaStorageKind.none:
                break;
            case ArenaStorageKind.chunked:
                for (ArenaChunk* chunk = storage.data.chunked.first_chunk; chunk !is null; chunk = chunk
                    .next)
                    chunk.offset = 0;
                storage.data.chunked.current_chunk = storage.data.chunked.first_chunk;
                break;
            case ArenaStorageKind.virtual_memory:
                break;
        }

        used_bytes = 0;
        version (XTB_Checked)
            ++generation;
    }

    void deinit()
    {
        version (XTB_Checked)
            require(scope_depth == 0, "cannot destroy arena with active temporary scopes");

        xtb.lifetime.deinit(storage);
        emplace(&storage);

        allocator_procedure = null;
        scope_depth = 0;
        used_bytes = 0;
        peak_used_bytes = 0;
        retention_limit = usize.max;
        version (XTB_Checked)
        {
            poison_rewound_memory = false;
            ++generation;
        }
    }

    ArenaStats stats() const pure @trusted
    {
        ArenaStats result;
        result.used_bytes = used_bytes;
        result.peak_used_bytes = peak_used_bytes;

        final switch (storage.kind)
        {
            case ArenaStorageKind.none:
                break;
            case ArenaStorageKind.chunked:
                for (const(ArenaChunk)* chunk = storage.data.chunked.first_chunk; chunk !is null; chunk = chunk
                    .next)
                {
                    result.reserved_bytes += chunk.capacity;
                    result.committed_bytes += chunk.capacity;
                    ++result.chunk_count;
                }
                break;
            case ArenaStorageKind.virtual_memory:
                result.reserved_bytes = storage.data.virtual_memory.reservation.reserved_bytes;
                result.committed_bytes = storage.data.virtual_memory.committed_bytes;
                break;
        }
        return result;
    }

    void set_retention_limit(usize bytes)
    {
        retention_limit = bytes;
        if (scope_depth == 0)
            trim_to_retention_limit();
    }

    void set_rewind_poisoning(bool enabled)
    {
        version (XTB_Checked)
            poison_rewound_memory = enabled;
    }

    void trim()
    {
        version (XTB_Checked)
            require(scope_depth == 0, "cannot trim arena with active temporary scopes");

        final switch (storage.kind)
        {
            case ArenaStorageKind.none:
                return;
            case ArenaStorageKind.chunked:
            {
                ArenaChunk* keep = storage.data.chunked.current_chunk;
                if (keep is null)
                {
                    storage.data.chunked.release_chunks(storage.data.chunked.first_chunk);
                    storage.data.chunked.first_chunk = null;
                    return;
                }
                storage.data.chunked.release_chunks(keep.next);
                keep.next = null;
                return;
            }
            case ArenaStorageKind.virtual_memory:
                trim_virtual_to(used_bytes);
                return;
        }
    }

    private void trim_to_retention_limit()
    {
        if (storage.kind == ArenaStorageKind.virtual_memory)
        {
            if (retention_limit >= storage.data.virtual_memory.committed_bytes)
                return;

            usize retain_bytes = retention_limit;
            if (retain_bytes < used_bytes)
                retain_bytes = used_bytes;
            if (retain_bytes > storage.data.virtual_memory.reservation.reserved_bytes)
                retain_bytes = storage.data.virtual_memory.reservation.reserved_bytes;
            trim_virtual_to(retain_bytes);
            return;
        }

        if (storage.kind != ArenaStorageKind.chunked)
            return;

        usize reserved;
        ArenaChunk* previous;
        ArenaChunk* chunk = storage.data.chunked.first_chunk;
        while (chunk !is null)
        {
            if (chunk is storage.data.chunked.current_chunk)
                previous = chunk;
            reserved += chunk.capacity;
            chunk = chunk.next;
        }
        if (reserved <= retention_limit || previous is null)
            return;

        chunk = previous.next;
        while (chunk !is null && reserved > retention_limit)
        {
            ArenaChunk* next = chunk.next;
            reserved -= chunk.capacity;
            storage.data.chunked.backing_allocator.deallocate(
                chunk,
                chunk.allocation_size,
                ArenaChunk.alignof,
            );
            chunk = next;
        }
        previous.next = chunk;
    }

    private void* try_resize_last_chunked(
        void* old_pointer,
        usize old_size,
        usize new_size,
        usize alignment,
    ) @system
    {
        ArenaChunk* chunk = storage.data.chunked.current_chunk;
        if (chunk is null || old_pointer is null || old_size == 0 ||
            (cast(usize) old_pointer & (alignment - 1)) != 0)
            return null;

        const base_address = cast(usize) chunk.data;
        const old_address = cast(usize) old_pointer;
        if (old_address < base_address)
            return null;
        const old_offset = old_address - base_address;
        if (old_offset > chunk.offset || old_size != chunk.offset - old_offset)
            return null;
        if (old_offset > chunk.capacity || new_size > chunk.capacity - old_offset)
            return null;

        const new_offset = old_offset + new_size;
        if (new_size >= old_size)
            used_bytes += new_size - old_size;
        else
            used_bytes -= old_size - new_size;
        chunk.offset = new_offset;
        if (used_bytes > peak_used_bytes)
            peak_used_bytes = used_bytes;
        return old_pointer;
    }

    private void* try_allocate_chunked(usize size, usize alignment)
    {
        ArenaChunk* chunk = storage.data.chunked.current_chunk;
        usize aligned_offset;
        if (chunk is null ||
            !aligned_offset_for(chunk, alignment, &aligned_offset) ||
            aligned_offset > chunk.capacity ||
            size > chunk.capacity - aligned_offset)
        {
            chunk = obtain_chunk(size, alignment);
            if (chunk is null)
                return null;
            if (!aligned_offset_for(chunk, alignment, &aligned_offset))
                return null;
        }

        void* result = chunk.data + aligned_offset;
        const occupied = aligned_offset + size - chunk.offset;
        chunk.offset = aligned_offset + size;
        used_bytes += occupied;
        if (used_bytes > peak_used_bytes)
            peak_used_bytes = used_bytes;
        return result;
    }

    private void* try_resize_last_virtual(
        void* old_pointer,
        usize old_size,
        usize new_size,
        usize alignment,
    ) @system
    {
        void* base_pointer = storage.data.virtual_memory.reservation.base;
        if (base_pointer is null || old_pointer is null || old_size == 0 ||
            (cast(usize) old_pointer & (alignment - 1)) != 0)
            return null;

        const base_address = cast(usize) base_pointer;
        const old_address = cast(usize) old_pointer;
        if (old_address < base_address)
            return null;
        const old_offset = old_address - base_address;
        if (old_offset > used_bytes || old_size != used_bytes - old_offset)
            return null;

        const reserved_bytes = storage.data.virtual_memory.reservation.reserved_bytes;
        if (old_offset > reserved_bytes || new_size > reserved_bytes - old_offset)
            return null;
        const new_end_offset = old_offset + new_size;
        if (new_end_offset > used_bytes && !ensure_virtual_committed(new_end_offset))
            return null;

        used_bytes = new_end_offset;
        if (used_bytes > peak_used_bytes)
            peak_used_bytes = used_bytes;
        return old_pointer;
    }

    private void* try_allocate_virtual(usize size, usize alignment) @system
    {
        void* base_pointer = storage.data.virtual_memory.reservation.base;
        if (base_pointer is null)
            return null;

        const base_address = cast(usize) base_pointer;
        if (used_bytes > usize.max - base_address)
            return null;

        usize aligned_address;
        if (!align_up(base_address + used_bytes, alignment, &aligned_address))
            return null;
        const aligned_offset = aligned_address - base_address;
        const reserved_bytes = storage.data.virtual_memory.reservation.reserved_bytes;
        if (aligned_offset > reserved_bytes || size > reserved_bytes - aligned_offset)
            return null;

        const end_offset = aligned_offset + size;
        if (!ensure_virtual_committed(end_offset))
            return null;

        void* result = cast(u8*) base_pointer + aligned_offset;
        used_bytes = end_offset;
        if (used_bytes > peak_used_bytes)
            peak_used_bytes = used_bytes;
        return result;
    }

    private bool ensure_virtual_committed(usize required_bytes) @system
    {
        if (required_bytes <= storage.data.virtual_memory.committed_bytes)
            return true;

        usize target_bytes;
        if (!round_up_to_multiple(
                required_bytes,
                storage.data.virtual_memory.commit_granularity,
                &target_bytes,
            ) ||
            target_bytes > storage.data.virtual_memory.reservation.reserved_bytes)
            target_bytes = storage.data.virtual_memory.reservation.reserved_bytes;

        if (target_bytes < required_bytes ||
            target_bytes <= storage.data.virtual_memory.committed_bytes)
            return false;

        const bytes = target_bytes - storage.data.virtual_memory.committed_bytes;
        if (!storage.data.virtual_memory.reservation.try_commit(
                storage.data.virtual_memory.committed_bytes,
                bytes,
            ))
            return false;

        storage.data.virtual_memory.committed_bytes = target_bytes;
        return true;
    }

    private void trim_virtual_to(usize keep_bytes) @system
    {
        if (!storage.data.virtual_memory.reservation.active ||
            storage.data.virtual_memory.committed_bytes == 0 ||
            keep_bytes >= storage.data.virtual_memory.committed_bytes)
            return;

        if (storage.data.virtual_memory.page_size == 0)
            panic("virtual arena page size unavailable");

        usize target_bytes;
        if (!round_up_to_multiple(keep_bytes, storage.data.virtual_memory.page_size, &target_bytes) ||
            target_bytes > storage.data.virtual_memory.reservation.reserved_bytes)
            target_bytes = storage.data.virtual_memory.reservation.reserved_bytes;
        if (target_bytes >= storage.data.virtual_memory.committed_bytes)
            return;

        const bytes = storage.data.virtual_memory.committed_bytes - target_bytes;
        if (!storage.data.virtual_memory.reservation.try_decommit(target_bytes, bytes))
            panic("virtual arena decommit failed");
        storage.data.virtual_memory.committed_bytes = target_bytes;
    }

    private ArenaChunk* obtain_chunk(usize size, usize alignment)

    {
        ArenaChunk* tail = storage.data.chunked.current_chunk;
        ArenaChunk* candidate = storage.data.chunked.current_chunk is null
            ? storage.data.chunked.first_chunk : storage.data.chunked.current_chunk.next;

        while (candidate !is null)
        {
            usize offset;
            if (aligned_offset_for(candidate, alignment, &offset) &&
                offset <= candidate.capacity &&
                size <= candidate.capacity - offset)
            {
                storage.data.chunked.current_chunk = candidate;
                return candidate;
            }
            tail = candidate;
            candidate = candidate.next;
        }

        const capacity = size > storage.data.chunked.default_chunk_size
            ? size : storage.data.chunked.default_chunk_size;
        ArenaChunk* created = create_chunk(capacity, alignment);
        if (created is null)
            return null;
        if (storage.data.chunked.first_chunk is null)
            storage.data.chunked.first_chunk = created;
        else
            tail.next = created;
        storage.data.chunked.current_chunk = created;
        return created;
    }

    private ArenaChunk* create_chunk(usize capacity, usize alignment)

    {
        const padding = alignment - 1;
        if (add_overflows(ArenaChunk.sizeof, padding) ||
            add_overflows(ArenaChunk.sizeof + padding, capacity))
            return null;

        const allocation_size = ArenaChunk.sizeof + padding + capacity;
        ArenaChunk* chunk = cast(ArenaChunk*) storage.data.chunked.backing_allocator.try_allocate(
            allocation_size,
            ArenaChunk.alignof,
        );
        if (chunk is null)
            return null;
        *chunk = ArenaChunk.init;
        chunk.allocation_size = allocation_size;
        chunk.capacity = capacity;

        const start = cast(usize)(cast(u8*) chunk + ArenaChunk.sizeof);
        usize aligned_start;
        if (!align_up(start, alignment, &aligned_start))
        {
            storage.data.chunked.backing_allocator.deallocate(
                chunk,
                allocation_size,
                ArenaChunk.alignof,
            );
            return null;
        }
        chunk.data = cast(u8*) aligned_start;
        return chunk;
    }
}

static assert(Arena.allocator_procedure.offsetof == 0);

private bool is_power_of_two(usize value) pure @safe
{
    return value != 0 && (value & (value - 1)) == 0;
}

private bool align_up(usize value, usize alignment, usize* result)
pure @safe
{
    const mask = alignment - 1;
    if (value > usize.max - mask)
        return false;
    *result = (value + mask) & ~mask;
    return true;
}

private bool round_up_to_multiple(
    usize value,
    usize multiple,
    usize* result,
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
    if (value > usize.max - increment)
        return false;
    *result = value + increment;
    return true;
}

private bool aligned_offset_for(
    ArenaChunk* chunk,
    usize alignment,
    usize* result,
) pure @system
{
    const base = cast(usize) chunk.data;
    if (chunk.offset > usize.max - base)
        return false;
    usize aligned_address;
    if (!align_up(base + chunk.offset, alignment, &aligned_address))
        return false;
    *result = aligned_address - base;
    return true;
}

private extern (C) void* chunked_arena_allocator_procedure(
    void* allocator,
    usize new_size,
    void* old_pointer,
    usize old_size,
    usize alignment,
)
{
    Arena* arena = cast(Arena*) allocator;
    if (new_size == 0)
        return null;
    version (XTB_Checked)
    {
        require(arena.storage.kind == ArenaStorageKind.chunked,
            "chunked arena allocator procedure used with a different backing");
        require(is_power_of_two(alignment),
            "arena alignment must be a power of two");
    }

    if (old_pointer !is null && old_size != 0)
    {
        void* resized = arena.try_resize_last_chunked(
            old_pointer,
            old_size,
            new_size,
            alignment,
        );
        if (resized !is null)
            return resized;
    }

    void* replacement = arena.try_allocate_chunked(new_size, alignment);
    if (replacement is null)
        return null;
    if (old_pointer !is null && old_size != 0)
    {
        const amount = old_size < new_size ? old_size : new_size;
        memcpy(replacement, old_pointer, amount);
    }
    return replacement;
}

private extern (C) void* virtual_arena_allocator_procedure(
    void* allocator,
    usize new_size,
    void* old_pointer,
    usize old_size,
    usize alignment,
)
{
    Arena* arena = cast(Arena*) allocator;
    if (new_size == 0)
        return null;
    version (XTB_Checked)
    {
        require(arena.storage.kind == ArenaStorageKind.virtual_memory,
            "virtual arena allocator procedure used with a different backing");
        require(is_power_of_two(alignment),
            "arena alignment must be a power of two");
    }

    if (old_pointer !is null && old_size != 0)
    {
        void* resized = arena.try_resize_last_virtual(
            old_pointer,
            old_size,
            new_size,
            alignment,
        );
        if (resized !is null)
            return resized;
    }

    void* replacement = arena.try_allocate_virtual(new_size, alignment);
    if (replacement is null)
        return null;
    if (old_pointer !is null && old_size != 0)
    {
        const amount = old_size < new_size ? old_size : new_size;
        memcpy(replacement, old_pointer, amount);
    }
    return replacement;
}

struct TempArena
{
nothrow @nogc:

    Arena* arena_pointer;
    ArenaChunk* chunk;
    usize chunk_offset;
    usize used_bytes;
    version (XTB_Checked)
    {
        usize depth;
        usize generation;
        void* thread_token;
    }
    bool active;

    @disable this(this);

    Arena* arena() return
    {
        version (XTB_Checked)
            require(active, "inactive temporary arena");
        return arena_pointer;
    }

    Allocator* allocator() return
    {
        return arena.allocator;
    }
}

TempArena push(Arena* arena)
{
    version (XTB_Checked)
        require(arena !is null, "cannot push a null arena");

    TempArena result;
    result.arena_pointer = arena;
    final switch (arena.storage.kind)
    {
        case ArenaStorageKind.none:
            break;
        case ArenaStorageKind.chunked:
            result.chunk = arena.storage.data.chunked.current_chunk;
            result.chunk_offset = result.chunk is null ? 0 : result.chunk.offset;
            break;
        case ArenaStorageKind.virtual_memory:
            break;
    }
    ++arena.scope_depth;
    result.used_bytes = arena.used_bytes;
    version (XTB_Checked)
    {
        result.depth = arena.scope_depth;
        result.generation = arena.generation;
        result.thread_token = current_thread_token();
    }
    result.active = true;
    return result;
}

void pop(ref TempArena temporary)
{
    version (XTB_Checked)
        require(temporary.active, "temporary arena already popped");
    Arena* arena = temporary.arena_pointer;
    version (XTB_Checked)
    {
        require(arena !is null, "temporary arena has no arena");
        require(temporary.thread_token is current_thread_token(),
            "temporary arena popped on a different thread");
        require(arena.generation == temporary.generation,
            "temporary arena checkpoint generation mismatch");
        require(arena.scope_depth == temporary.depth, "temporary arenas must pop in LIFO order");
    }

    version (XTB_Checked)
    {
        if (arena.poison_rewound_memory)
        {
            final switch (arena.storage.kind)
            {
                case ArenaStorageKind.none:
                    break;
                case ArenaStorageKind.chunked:
                {
                    ArenaChunk* chunk = temporary.chunk is null
                        ? arena.storage.data.chunked.first_chunk : temporary.chunk;
                    bool first = true;
                    for (; chunk !is null; chunk = chunk.next)
                    {
                        const begin = first && temporary.chunk !is null
                            ? temporary.chunk_offset : 0;
                        if (chunk.offset > begin)
                            memset(chunk.data + begin, 0xDD, chunk.offset - begin);
                        first = false;
                    }
                    break;
                }
                case ArenaStorageKind.virtual_memory:
                    if (arena.used_bytes > temporary.used_bytes)
                        memset(
                            cast(u8*) arena.storage.data.virtual_memory.reservation.base +
                                temporary.used_bytes,
                            0xDD,
                            arena.used_bytes - temporary.used_bytes,
                        );
                    break;
            }
        }
    }

    final switch (arena.storage.kind)
    {
        case ArenaStorageKind.none:
            break;
        case ArenaStorageKind.chunked:
            if (temporary.chunk is null)
            {
                for (ArenaChunk* chunk = arena.storage.data.chunked.first_chunk; chunk !is null; chunk = chunk
                    .next)
                    chunk.offset = 0;
                arena.storage.data.chunked.current_chunk = arena.storage.data.chunked.first_chunk;
            }
            else
            {
                temporary.chunk.offset = temporary.chunk_offset;
                for (ArenaChunk* chunk = temporary.chunk.next; chunk !is null; chunk = chunk.next)
                    chunk.offset = 0;
                arena.storage.data.chunked.current_chunk = temporary.chunk;
            }
            break;
        case ArenaStorageKind.virtual_memory:
            break;
    }

    --arena.scope_depth;
    arena.used_bytes = temporary.used_bytes;
    if (arena.scope_depth == 0)
        arena.trim_to_retention_limit();
    temporary.arena_pointer = null;
    temporary.chunk = null;
    temporary.chunk_offset = 0;
    temporary.used_bytes = 0;
    version (XTB_Checked)
    {
        temporary.depth = 0;
        temporary.generation = 0;
        temporary.thread_token = null;
    }
    temporary.active = false;
}

version (unittest)
{
    import xtb.allocators.instrumented;
    import xtb.allocators.malloc;
}

unittest
{
    static assert(!__traits(hasMember, VirtualArenaStorage, "offset"));
    static assert(!__traits(hasMember, TempArena, "offset_"));
    static assert(__traits(hasMember, TempArena, "chunk_offset"));

    version (XTB_Checked)
    {
        static assert(__traits(hasMember, Arena, "generation"));
        static assert(__traits(hasMember, Arena, "poison_rewound_memory"));
        static assert(__traits(hasMember, TempArena, "depth"));
        static assert(__traits(hasMember, TempArena, "generation"));
        static assert(__traits(hasMember, TempArena, "thread_token"));
    }
    else
    {
        static assert(!__traits(hasMember, Arena, "generation"));
        static assert(!__traits(hasMember, Arena, "poison_rewound_memory"));
        static assert(!__traits(hasMember, TempArena, "depth"));
        static assert(!__traits(hasMember, TempArena, "generation"));
        static assert(!__traits(hasMember, TempArena, "thread_token"));
    }

    Arena arena = Arena.create(malloc_allocator(), 64);
    assert(arena.storage.kind == ArenaStorageKind.chunked);
    assert(*arena.allocator == &chunked_arena_allocator_procedure);
    i32* persistent = arena.allocate!i32();
    *persistent = 42;

    TempArena outer = (&arena).push();
    void* first = arena.allocate(48, 16);
    assert((cast(usize) first & 15) == 0);
    TempArena inner = (&arena).push();
    arena.allocate(96, 32);
    inner.pop();
    outer.pop();
    assert(*persistent == 42);
    assert(arena.stats.used_bytes >= i32.sizeof);
    assert(arena.stats.peak_used_bytes >= arena.stats.used_bytes);
    assert(arena.stats.chunk_count >= 1);
    assert(arena.stats.committed_bytes == arena.stats.reserved_bytes);

    i32* typed = arena.allocate!i32();
    *typed = 17;
    assert(*typed == 17);

    i32[] typed_array = arena.allocate_array!i32(4);
    assert(typed_array.length == 4);
    typed_array[3] = 23;
    assert(typed_array[3] == 23);

    struct Initialized
    {
        u32 value = 0xABCD_EF01;
    }

    Initialized* initialized = arena.allocate_init!Initialized();
    assert(initialized.value == Initialized.init.value);
    Initialized[] initialized_array = arena.allocate_init_array!Initialized(2);
    assert(initialized_array.length == 2);
    assert(initialized_array[1].value == Initialized.init.value);

    Initialized* zeroed = arena.allocate_zeroed!Initialized();
    assert(zeroed.value == 0);
    Initialized[] zeroed_array = arena.allocate_zeroed_array!Initialized(2);
    assert(zeroed_array[1].value == 0);

    struct Constructed
    {
    nothrow @nogc:

        i32 value;

        this(i32 value)
        {
            this.value = value;
        }
    }

    Constructed* constructed = arena.create!Constructed(91);
    assert(constructed.value == 91);

    Allocator* arena_allocator = arena.allocator;
    i32* through_allocator = arena_allocator.allocate_init!i32();
    assert(*through_allocator == i32.init);
    u8* allocator_bytes = cast(u8*) arena_allocator.allocate(4, 1);
    allocator_bytes[0] = 0x12;
    allocator_bytes[3] = 0x34;
    u8* reallocated_bytes = cast(u8*) arena_allocator.reallocate(
        8,
        allocator_bytes,
        4,
        1,
    );
    assert(reallocated_bytes is allocator_bytes);
    assert(reallocated_bytes[0] == 0x12);
    assert(reallocated_bytes[3] == 0x34);

    Arena realloc_arena = Arena.create(malloc_allocator(), 64);
    Allocator* realloc_allocator = realloc_arena.allocator;
    const chunked_used_before = realloc_arena.stats.used_bytes;
    u8* chunked_tail = cast(u8*) realloc_allocator.allocate(8, 1);
    chunked_tail[0] = 0xA1;
    chunked_tail[7] = 0xB2;
    u8* grown_chunked_tail = cast(u8*) realloc_allocator.reallocate(
        16,
        chunked_tail,
        8,
        1,
    );
    assert(grown_chunked_tail is chunked_tail);
    assert(grown_chunked_tail[0] == 0xA1);
    assert(grown_chunked_tail[7] == 0xB2);
    assert(realloc_arena.stats.used_bytes == chunked_used_before + 16);
    u8* shrunk_chunked_tail = cast(u8*) realloc_allocator.reallocate(
        4,
        grown_chunked_tail,
        16,
        1,
    );
    assert(shrunk_chunked_tail is chunked_tail);
    assert(realloc_arena.stats.used_bytes == chunked_used_before + 4);
    assert(realloc_allocator.allocate(1, 1) == shrunk_chunked_tail + 4);

    u8* non_last_chunked = cast(u8*) realloc_allocator.allocate(4, 1);
    non_last_chunked[0] = 0xC3;
    cast(void) realloc_allocator.allocate(4, 1);
    u8* moved_chunked = cast(u8*) realloc_allocator.reallocate(
        8,
        non_last_chunked,
        4,
        1,
    );
    assert(moved_chunked !is non_last_chunked);
    assert(moved_chunked[0] == 0xC3);

    u8* deallocated_chunked = cast(u8*) realloc_allocator.allocate(4, 1);
    const chunked_used_before_deallocate = realloc_arena.stats.used_bytes;
    realloc_allocator.deallocate(deallocated_chunked, 4, 1);
    assert(realloc_arena.stats.used_bytes == chunked_used_before_deallocate);
    assert(realloc_allocator.allocate(1, 1) == deallocated_chunked + 4);
    realloc_arena.deinit();

    arena.set_rewind_poisoning(true);
    TempArena poisoned = (&arena).push();
    u8* bytes = cast(u8*) arena.allocate(8, 1);
    bytes[0] = 1;
    poisoned.pop();
    assert(bytes[0] == 0xDD);
    arena.set_retention_limit(64);
    arena.trim();
    arena.deinit();
    assert(arena.storage.kind == ArenaStorageKind.none);

    version (linux)
    {
        const page_size = virtual_memory_page_size();
        assert(page_size != 0);

        Arena virtual_arena = Arena.create_virtual(
            page_size * 8,
            page_size * 2,
        );
        assert(virtual_arena.storage.kind == ArenaStorageKind.virtual_memory);
        assert(*virtual_arena.allocator == &virtual_arena_allocator_procedure);
        ArenaStats initial_virtual_stats = virtual_arena.stats;
        assert(initial_virtual_stats.used_bytes == 0);
        assert(initial_virtual_stats.reserved_bytes == page_size * 8);
        assert(initial_virtual_stats.committed_bytes == 0);
        assert(initial_virtual_stats.chunk_count == 0);

        u8* first_virtual = cast(u8*) virtual_arena.allocate(1, 1);
        assert(first_virtual !is null);
        *first_virtual = 0x7B;
        assert(virtual_arena.stats.committed_bytes == page_size * 2);

        TempArena virtual_temporary = (&virtual_arena).push();
        u8* temporary_bytes = cast(u8*) virtual_arena.allocate(
            page_size * 2,
            1,
        );
        temporary_bytes[0] = 0x42;
        const committed_high_water = virtual_arena.stats.committed_bytes;
        virtual_temporary.pop();
        assert(*first_virtual == 0x7B);
        assert(virtual_arena.stats.committed_bytes == committed_high_water);

        u8* reused_temporary = cast(u8*) virtual_arena.allocate(
            page_size * 2,
            1,
        );
        assert(reused_temporary is temporary_bytes);

        virtual_arena.set_rewind_poisoning(true);
        TempArena poisoned_virtual = (&virtual_arena).push();
        u8* poisoned_virtual_bytes = cast(u8*) virtual_arena.allocate(8, 1);
        poisoned_virtual_bytes[0] = 1;
        poisoned_virtual.pop();
        assert(poisoned_virtual_bytes[0] == 0xDD);
        virtual_arena.set_rewind_poisoning(false);

        virtual_arena.clear();
        assert(virtual_arena.stats.used_bytes == 0);
        assert(virtual_arena.stats.committed_bytes == committed_high_water);
        virtual_arena.set_retention_limit(page_size);
        assert(virtual_arena.stats.committed_bytes == page_size);

        TempArena retained_virtual = (&virtual_arena).push();
        assert(virtual_arena.allocate(page_size * 3, 1) !is null);
        assert(virtual_arena.stats.committed_bytes > page_size);
        retained_virtual.pop();
        assert(virtual_arena.stats.used_bytes == 0);
        assert(virtual_arena.stats.committed_bytes == page_size);

        u8* before_trim = cast(u8*) virtual_arena.allocate(1, 1);
        before_trim[0] = 0xA5;
        virtual_arena.clear();
        virtual_arena.trim();
        assert(virtual_arena.stats.committed_bytes == 0);
        u8* after_trim = cast(u8*) virtual_arena.allocate(1, 1);
        assert(after_trim is before_trim);
        assert(after_trim[0] == 0);

        Allocator* virtual_allocator = virtual_arena.allocator;
        i32* through_virtual_allocator = virtual_allocator.allocate_init!i32();
        assert(*through_virtual_allocator == i32.init);
        u8* virtual_allocator_bytes = cast(u8*) virtual_allocator.allocate(4, 1);
        virtual_allocator_bytes[0] = 0x56;
        virtual_allocator_bytes[3] = 0x78;
        u8* virtual_reallocated_bytes = cast(u8*) virtual_allocator.reallocate(
            8,
            virtual_allocator_bytes,
            4,
            1,
        );
        assert(virtual_reallocated_bytes is virtual_allocator_bytes);
        assert(virtual_reallocated_bytes[0] == 0x56);
        assert(virtual_reallocated_bytes[3] == 0x78);

        Arena virtual_realloc_arena = Arena.create_virtual(page_size * 4, page_size);
        Allocator* virtual_realloc_allocator = virtual_realloc_arena.allocator;
        u8* virtual_tail = cast(u8*) virtual_realloc_allocator.allocate(
            page_size - 8,
            1,
        );
        virtual_tail[0] = 0xD4;
        assert(virtual_realloc_arena.stats.committed_bytes == page_size);
        u8* grown_virtual_tail = cast(u8*) virtual_realloc_allocator.reallocate(
            page_size + 8,
            virtual_tail,
            page_size - 8,
            1,
        );
        assert(grown_virtual_tail is virtual_tail);
        assert(grown_virtual_tail[0] == 0xD4);
        assert(virtual_realloc_arena.stats.used_bytes == page_size + 8);
        assert(virtual_realloc_arena.stats.committed_bytes == page_size * 2);
        u8* shrunk_virtual_tail = cast(u8*) virtual_realloc_allocator.reallocate(
            4,
            grown_virtual_tail,
            page_size + 8,
            1,
        );
        assert(shrunk_virtual_tail is virtual_tail);
        assert(virtual_realloc_arena.stats.used_bytes == 4);
        assert(virtual_realloc_arena.stats.committed_bytes == page_size * 2);
        assert(virtual_realloc_allocator.allocate(1, 1) == shrunk_virtual_tail + 4);

        u8* non_last_virtual = cast(u8*) virtual_realloc_allocator.allocate(4, 1);
        non_last_virtual[0] = 0xE5;
        cast(void) virtual_realloc_allocator.allocate(4, 1);
        u8* relocated_virtual = cast(u8*) virtual_realloc_allocator.reallocate(
            8,
            non_last_virtual,
            4,
            1,
        );
        assert(relocated_virtual !is non_last_virtual);
        assert(relocated_virtual[0] == 0xE5);

        u8* deallocated_virtual = cast(u8*) virtual_realloc_allocator.allocate(4, 1);
        const virtual_used_before_deallocate = virtual_realloc_arena.stats.used_bytes;
        virtual_realloc_allocator.deallocate(deallocated_virtual, 4, 1);
        assert(virtual_realloc_arena.stats.used_bytes == virtual_used_before_deallocate);
        assert(virtual_realloc_allocator.allocate(1, 1) == deallocated_virtual + 4);
        virtual_realloc_arena.deinit();

        virtual_arena.deinit();
        assert(virtual_arena.storage.kind == ArenaStorageKind.none);
        assert(virtual_arena.stats.reserved_bytes == 0);
        assert(virtual_arena.stats.committed_bytes == 0);
        virtual_arena.deinit();

        Arena tiny_virtual;
        assert(Arena.try_create_virtual(
                page_size * 2,
                page_size,
                &tiny_virtual,
        ));
        assert(tiny_virtual.try_allocate(page_size * 2, 1) !is null);
        const full_stats = tiny_virtual.stats;
        assert(full_stats.used_bytes == page_size * 2);
        assert(full_stats.committed_bytes == page_size * 2);
        assert(tiny_virtual.try_allocate(1, 1) is null);
        assert(tiny_virtual.stats.used_bytes == full_stats.used_bytes);
        tiny_virtual.deinit();

        Arena rounded_virtual = Arena.create_virtual(
            page_size * 4 + 1,
            page_size + 1,
        );
        assert(rounded_virtual.stats.reserved_bytes == page_size * 5);
        assert(rounded_virtual.allocate(1, 1) !is null);
        assert(rounded_virtual.stats.committed_bytes == page_size * 2);
        rounded_virtual.deinit();

        Arena failed_virtual;
        assert(!Arena.try_create_virtual(usize.max, &failed_virtual));
        assert(failed_virtual.stats.reserved_bytes == 0);
        failed_virtual.deinit();

        Arena moving_virtual = Arena.create_virtual(page_size * 2, page_size);
        i32* moved_value = moving_virtual.allocate!i32();
        *moved_value = 77;
        Arena moved_virtual = move(moving_virtual);
        assert(moving_virtual.storage.kind == ArenaStorageKind.none);
        assert(*moving_virtual.allocator is null);
        assert(moved_virtual.storage.kind == ArenaStorageKind.virtual_memory);
        assert(*moved_virtual.allocator == &virtual_arena_allocator_procedure);
        assert(moving_virtual.stats.reserved_bytes == 0);
        assert(*moved_value == 77);
        moving_virtual.deinit();
        moved_virtual.deinit();

        Arena replacement_target = Arena.create(malloc_allocator(), 64);
        assert(*replacement_target.allocator == &chunked_arena_allocator_procedure);
        replacement_target.allocate(8, 8);
        Arena replacement_source = Arena.create_virtual(page_size * 2, page_size);
        i32* replacement_value = replacement_source.allocate!i32();
        *replacement_value = 23;
        move_assign(replacement_source, replacement_target);
        assert(replacement_source.stats.reserved_bytes == 0);
        assert(*replacement_source.allocator is null);
        assert(*replacement_target.allocator == &virtual_arena_allocator_procedure);
        assert(replacement_target.stats.chunk_count == 0);
        assert(replacement_target.stats.reserved_bytes == page_size * 2);
        assert(*replacement_value == 23);
        replacement_source.deinit();
        replacement_target.deinit();
    }
    else
    {
        Arena unavailable_virtual;
        assert(!Arena.try_create_virtual(4096, &unavailable_virtual));
        assert(unavailable_virtual.stats.reserved_bytes == 0);
        unavailable_virtual.deinit();
    }

    struct ArenaConstructed
    {
    nothrow @nogc:

        i32* destroyed;

        this(i32* destroyed)
        {
            this.destroyed = destroyed;
        }

        ~this()
        {
            if (destroyed !is null)
                ++*destroyed;
        }
    }

    i32 destructor_calls;
    Arena destructor_arena = Arena.create(malloc_allocator(), 64);

    ArenaConstructed* initialized_destructor =
        destructor_arena.allocate_init!ArenaConstructed();
    initialized_destructor.destroyed = &destructor_calls;
    destroy(*initialized_destructor);
    assert(destructor_calls == 1);

    ArenaConstructed* try_initialized_destructor =
        destructor_arena.try_allocate_init!ArenaConstructed();
    assert(try_initialized_destructor !is null);
    try_initialized_destructor.destroyed = &destructor_calls;
    destructor_arena.allocator.dispose(try_initialized_destructor);
    assert(destructor_calls == 2);

    ArenaConstructed[] initialized_destructors =
        destructor_arena.allocate_init_array!ArenaConstructed(2);
    foreach (ref value; initialized_destructors)
        value.destroyed = &destructor_calls;
    destructor_arena.allocator.dispose_array(initialized_destructors);
    assert(destructor_calls == 4);

    ArenaConstructed[] try_initialized_destructors =
        destructor_arena.try_allocate_init_array!ArenaConstructed(2);
    assert(try_initialized_destructors.length == 2);
    foreach (ref value; try_initialized_destructors)
        value.destroyed = &destructor_calls;
    foreach_reverse (ref value; try_initialized_destructors)
        destroy(value);
    assert(destructor_calls == 6);

    ArenaConstructed* constructed_destructor =
        destructor_arena.create!ArenaConstructed(&destructor_calls);
    destructor_arena.allocator.dispose(constructed_destructor);
    assert(destructor_calls == 7);

    ArenaConstructed* try_constructed_destructor =
        destructor_arena.try_create!ArenaConstructed(&destructor_calls);
    assert(try_constructed_destructor !is null);
    destroy(*try_constructed_destructor);
    assert(destructor_calls == 8);
    destructor_arena.deinit();

    version (linux)
    {
        i32 virtual_destructor_calls;
        const virtual_destructor_page_size = virtual_memory_page_size();
        Arena virtual_destructor_arena = Arena.create_virtual(
            virtual_destructor_page_size * 2,
            virtual_destructor_page_size,
        );
        virtual_destructor_arena.create!ArenaConstructed(
            &virtual_destructor_calls,
        );
        virtual_destructor_arena.clear();
        assert(virtual_destructor_calls == 0);
        virtual_destructor_arena.create!ArenaConstructed(
            &virtual_destructor_calls,
        );
        virtual_destructor_arena.deinit();
        assert(virtual_destructor_calls == 0);
    }

    static assert(hasElaborateDestructor!ArenaConstructed);
    static assert(__traits(compiles, (ref Arena value) {
            value.create!ArenaConstructed(cast(i32*) null);
        }));
    static assert(__traits(compiles, (ref Arena value) { value.allocate_init!ArenaConstructed(); }));
    static assert(__traits(compiles, (ref Arena value) {
            value.allocate_init_array!ArenaConstructed(2);
        }));

    static assert(!hasElaborateDestructor!Arena);
    static assert(needs_deinit!Arena);
    static assert(__traits(compiles, (ref Arena value) @safe { ArenaStats snapshot = value.stats(); }));
    static assert(!__traits(compiles, (ref Arena left, ref Arena right) { left = right; }));

    i32 explicit_deinits;
    struct ExplicitOwner
    {
    nothrow @nogc:

        i32* deinits;

        void deinit()
        {
            ++*deinits;
        }
    }

    Arena abandonment = Arena.create(malloc_allocator(), 64);
    ExplicitOwner* abandoned = abandonment.create!ExplicitOwner();
    abandoned.deinits = &explicit_deinits;
    ArenaConstructed* abandoned_destructor =
        abandonment.create!ArenaConstructed(&destructor_calls);
    abandonment.clear();
    assert(explicit_deinits == 0);
    assert(destructor_calls == 8);
    abandoned = abandonment.create!ExplicitOwner();
    abandoned.deinits = &explicit_deinits;
    abandoned_destructor = abandonment.create!ArenaConstructed(&destructor_calls);
    abandonment.deinit();
    assert(explicit_deinits == 0);
    assert(destructor_calls == 8);

    AllocationRecord[4] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        malloc_allocator(), records[],
    );
    failing.fail_after(0);
    Arena fallible = Arena.create(failing.allocator, 64);
    assert(fallible.try_allocate(8, 8) is null);
    assert(fallible.try_allocate!i32() is null);
    assert(fallible.try_allocate_array!i32(2).length == 0);
    assert(fallible.try_allocate_init!i32() is null);
    assert(fallible.try_allocate_init!ArenaConstructed() is null);
    assert(fallible.try_allocate_init_array!ArenaConstructed(2).length == 0);
    assert(fallible.try_create!Constructed(4) is null);
    assert(fallible.try_create!ArenaConstructed(&destructor_calls) is null);
    assert(destructor_calls == 8);
    assert(fallible.stats.chunk_count == 0);
    fallible.deinit();
}
