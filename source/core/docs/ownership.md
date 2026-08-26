# Ownership and lifetimes

XTB does not rely on the GC. Values that own resources make that ownership
explicit and are cleaned up explicitly.
See the [explicit deinit protocol](deinit.md) for implementing and using generic cleanup.

| Kind | Examples | Lifetime |
|---|---|---|
| borrowed view | `String`, slices | valid while the backing storage is valid; no `deinit` |
| allocator-bound owner | `StringBuf`, `OwnedString`, `Array!T`, maps and sets | owns allocated storage; call `deinit` |
| deep owner | `OwnedArray!T` | owns storage and finalizes live elements |
| region allocation | `Arena`, `ScratchScope` | allocations are reclaimed together with the region |

Register cleanup next to an owning value when it survives the current
expression:

```d
Allocator* heap = mallocAllocator();
OwnedString name = "xtb".copy(heap);
scope(exit) name.deinit();
```

String transformation overloads that take `Arena*` return borrowed values whose
bytes belong to the arena:

```d
Arena arena = Arena.create(heap);
scope(exit) arena.deinit();

String path = "//api//users".replace("//", "/", &arena);
```

`path` needs no cleanup, but it must not outlive `arena`. Copy into an
allocator-bound owner when a value must cross that lifetime boundary:

```d
OwnedString persistent = path.copy(heap);
scope(exit) persistent.deinit();
```

## Shallow and deep containers

`Array!T` owns its backing allocation but does not finalize discarded elements.
Use it for non-owning/trivial elements or when element cleanup is managed
elsewhere. `OwnedArray!T` owns both the allocation and element cleanup.

Types with an `Unmanaged` suffix store no allocator pointer. Allocation and
cleanup operations therefore receive the allocator explicitly; prefer the
allocator-bound variants unless that distinction is useful to the containing
type.

## Transfers

XTB owners are non-copyable. Use `move` to transfer an ownership obligation;
the moved-from value is reset to a safely deinitializable state. Owners that
expose `release`/`adopt` can transfer their backing storage without copying.
