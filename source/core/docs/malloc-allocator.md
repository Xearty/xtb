# Malloc allocator

`mallocAllocator()` returns XTB's process-wide libc-backed allocator. Use it
when allocations should have independent lifetimes and be released
individually.

```d
Allocator* heap = mallocAllocator();

OwnedString name = "xtb".copy(heap);
scope(exit) name.deinit();

Array!int values = Array!int.create(heap);
scope(exit) values.deinit();
values.append(42);
```

The allocator supports reallocation and over-aligned allocations. The allocator
itself has no lifetime to manage; only the allocations and owners created with
it need cleanup.

It is also the usual backing allocator for chunked arenas and is the default
backing allocator used by `ThreadContextScope.acquire()`.

For raw allocations, use the helpers described in
[Allocator interface](allocator.md). Prefer owning XTB types when an ownership
wrapper already exists.
