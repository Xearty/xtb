module xtb.allocators.instrumented;

nothrow @nogc:

import xtb.memory;
import xtb.panic;
import xtb.types;

/// One live allocation tracked by `InstrumentedAllocator`.
struct AllocationRecord
{
    void* pointer;
    usize size;
    usize alignment;
}

/// Allocation counters exposed by `InstrumentedAllocator`.
struct AllocatorStats
{
    usize allocation_calls;
    usize reallocation_calls;
    usize deallocation_calls;
    usize failed_calls;
    usize invalid_calls;
    usize outstanding_allocations;
    usize outstanding_bytes;
    usize peak_outstanding_bytes;
}

/// Caller-storage-backed allocator wrapper for deterministic tests/diagnostics.
struct InstrumentedAllocator
{
nothrow @nogc:

    Allocator allocator_procedure;
    Allocator* backing;
    AllocationRecord[] records;
    AllocatorStats stats;
    usize successes_before_failure = usize.max;

    @disable this(this);

    /// Creates an allocator backed by `backing` and caller-owned record storage.
    /// `backing` must not be null, and both inputs must outlive the result.
    static InstrumentedAllocator create(
        Allocator* backing,
        return scope AllocationRecord[] records,
    )
    {
        require(
            backing !is null && *backing !is null,
            "instrumented allocator requires a valid backing allocator",
        );

        InstrumentedAllocator result;
        result.allocator_procedure = &instrumented_allocator_procedure;
        result.backing = backing;
        result.records = records;
        foreach (ref record; records)
            record = AllocationRecord.init;

        return result;
    }

    /// Returns the non-null embedded allocator slot borrowed from this wrapper.
    Allocator* allocator() return
    {
        return &this.allocator_procedure;
    }

    void fail_after(usize successful_calls)
    {
        this.successes_before_failure = successful_calls;
    }

    void allow_allocations()
    {
        this.successes_before_failure = usize.max;
    }

    bool clean() const pure @safe
    {
        return this.stats.outstanding_allocations == 0 && this.stats.outstanding_bytes == 0;
    }
}

static assert(InstrumentedAllocator.allocator_procedure.offsetof == 0);

private AllocationRecord* find_record(
    InstrumentedAllocator* allocator,
    void* pointer,
)
{
    foreach (ref record; allocator.records)
        if (record.pointer is pointer) return &record;

    return null;
}

private AllocationRecord* free_record(InstrumentedAllocator* allocator)
{
    foreach (ref record; allocator.records)
        if (record.pointer is null) return &record;

    return null;
}

private extern (C) void* instrumented_allocator_procedure(
    void* context,
    usize new_size,
    void* old_pointer,
    usize old_size,
    usize alignment,
) @system
{
    InstrumentedAllocator* allocator = cast(InstrumentedAllocator*) context;
    AllocationRecord* old_record;
    if (old_pointer !is null)
    {
        old_record = find_record(allocator, old_pointer);
        if (
            old_record is null
            || old_record.size != old_size
            || old_record.alignment != alignment
        )
        {
            ++allocator.stats.invalid_calls;
            return null;
        }
    }
    else if (old_size != 0)
    {
        ++allocator.stats.invalid_calls;
        return null;
    }

    if (new_size == 0)
    {
        if (old_pointer is null) return null;

        ++allocator.stats.deallocation_calls;
        allocator.backing.deallocate(old_pointer, old_size, alignment);
        --allocator.stats.outstanding_allocations;
        allocator.stats.outstanding_bytes -= old_size;
        *old_record = AllocationRecord.init;
        return null;
    }

    if (allocator.successes_before_failure == 0)
    {
        ++allocator.stats.failed_calls;
        return null;
    }

    AllocationRecord* destination_record = old_record;
    if (destination_record is null)
    {
        destination_record = free_record(allocator);
        if (destination_record is null)
        {
            ++allocator.stats.failed_calls;
            return null;
        }

        ++allocator.stats.allocation_calls;
    }
    else
    {
        ++allocator.stats.reallocation_calls;
    }

    void* replacement = allocator.backing.try_reallocate(
        new_size,
        old_pointer,
        old_size,
        alignment,
    );
    if (replacement is null)
    {
        ++allocator.stats.failed_calls;
        return null;
    }

    if (allocator.successes_before_failure != usize.max)
        --allocator.successes_before_failure;

    if (old_record is null)
    {
        ++allocator.stats.outstanding_allocations;
        allocator.stats.outstanding_bytes += new_size;
    }
    else
    {
        allocator.stats.outstanding_bytes -= old_size;
        allocator.stats.outstanding_bytes += new_size;
    }

    if (allocator.stats.outstanding_bytes > allocator.stats.peak_outstanding_bytes)
        allocator.stats.peak_outstanding_bytes = allocator.stats.outstanding_bytes;

    *destination_record = AllocationRecord(replacement, new_size, alignment);
    return replacement;
}

unittest
{
    import xtb.allocators.malloc;

    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        malloc_allocator(),
        records[],
    );
    i32[] values = tracked.allocator.allocate_zeroed_array!i32(4);
    assert(values.length == 4);
    assert(values[3] == 0);
    assert(tracked.stats.outstanding_bytes == 4 * i32.sizeof);
    tracked.fail_after(0);
    assert(tracked.allocator.try_allocate!i32() is null);
    assert(tracked.stats.failed_calls == 1);
    tracked.allocator.deallocate_array(values);
    assert(tracked.clean);
}
