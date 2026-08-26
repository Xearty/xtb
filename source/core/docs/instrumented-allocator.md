# Instrumented allocator

`InstrumentedAllocator` wraps another allocator for deterministic tests and
allocation diagnostics. It tracks live allocations in caller-provided storage
and exposes counters for allocations, reallocations, failures, and outstanding
bytes. The wrapper owns neither its backing allocator nor record storage and
requires no `deinit`; both must outlive the wrapper.

```d
AllocationRecord[64] records;
InstrumentedAllocator tracked = InstrumentedAllocator.create(
    mallocAllocator(),
    records[],
);

Array!int values = Array!int.create(tracked.allocator);
scope(exit) values.deinit();
values.append(42);

assert(tracked.stats.outstandingAllocations == 1);
```

The record array bounds how many allocations can be live simultaneously through
the wrapper. Running out of record slots is reported as an allocation failure.

Use `failAfter(n)` to make allocation/reallocation fail after `n` successful
calls. `allowAllocations()` disables failure injection again:

```d
tracked.failAfter(0);
assert(tracked.allocator.tryAllocate!int() is null);
tracked.allowAllocations();
```

`clean` is useful at the end of tests to check that no tracked allocations
remain. `stats.invalidCalls` records invalid deallocation/reallocation metadata
seen by the wrapper.
