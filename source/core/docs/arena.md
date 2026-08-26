# Arena allocator

`Arena` groups many allocations under one lifetime. Individual deallocation is
ignored; storage is reclaimed by rewinding or destroying the arena.

```d
Allocator* heap = mallocAllocator();
Arena arena = Arena.create(heap);
scope(exit) arena.deinit();

int[] values = arena.allocateArray!int(128);
String path = "//api//users".replace("//", "/", &arena);
```

`Arena.create` uses allocator-backed chunks and grows by allocating more chunks
as needed. `arena.allocator` exposes the same arena through `Allocator*` for APIs
that accept the generic allocator interface.

`clear()` rewinds the whole arena while retaining reusable storage. `trim()` can
release retained storage that is no longer needed. `stats()` reports used,
reserved, committed, and peak usage.

Arena reclamation does **not** call `deinit` or destructors for objects allocated
inside it. Perform required cleanup before `clear`, `pop`, or `deinit`.

## Temporary checkpoints

`push` creates a checkpoint and `pop` rewinds allocations made after it:

```d
TempArena temporary = (&arena).push();
scope(exit) temporary.pop();

int[] scratch = temporary.allocator.allocateArray!int(256);
```

Temporary arenas must pop in LIFO order. `ScratchScope` builds this checkpoint
pattern on top of the thread context; see [Thread context and scratch arenas](thread-context.md).

## Virtual-backed arena

`Arena.createVirtual` reserves one fixed contiguous virtual-address range and
commits pages as allocations grow:

```d
Arena arena = Arena.createVirtual(1UL << 30); // 1 GiB address reservation
scope(exit) arena.deinit();
```

The reservation is the arena's maximum capacity. `tryCreateVirtual` reports
unsupported targets or reservation failure without panicking. Unlike a chunked
arena, growth does not require additional backing-allocator allocations and
addresses remain inside one reservation.

See [Explicit deinit protocol](deinit.md) for cleanup semantics.
