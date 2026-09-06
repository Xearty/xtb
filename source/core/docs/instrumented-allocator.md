# Instrumented allocator

`InstrumentedAllocator` wraps another allocator for deterministic tests and
allocation diagnostics. It tracks live allocations in caller-provided storage
and exposes counters for allocations, reallocations, failures, and outstanding
bytes. The wrapper owns neither its backing allocator nor record storage and
requires no `deinit`; both must outlive the wrapper.

```d
AllocationRecord[64] records;
InstrumentedAllocator tracked = InstrumentedAllocator.create(
    malloc_allocator(),
    records[],
);

Array!i32 values = Array!i32.create(tracked.allocator);
scope (exit) values.deinit();
values.append(42);

assert(tracked.stats.outstanding_allocations == 1);
```

The record array bounds how many allocations can be live simultaneously through
the wrapper. Running out of record slots is reported as an allocation failure.

Use `fail_after(n)` to make allocation/reallocation fail after `n` successful
calls. `allow_allocations()` disables failure injection again:

```d
tracked.fail_after(0);
assert(tracked.allocator.try_allocate!i32() is null);
tracked.allow_allocations();
```

`clean` is useful at the end of tests to check that no tracked allocations
remain. `stats.invalid_calls` records invalid deallocation/reallocation metadata
seen by the wrapper.
