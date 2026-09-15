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
Allocator* heap = malloc_allocator();
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

Manual-lifetime XTB owners follow a Zig-style convention: ordinary assignment,
argument passing, returning, and aggregate initialization make shallow copies
of the representation. Such copies alias the same resource. Choose exactly one
alias to keep using and eventually `deinit`; the language does not track that
choice or invalidate the other aliases.

Use `clone` or `copy` when both results must own independent resources. Use
`move(source)` only when resetting the source to an inert, safely
deinitializable state is useful, such as when unconditional scope cleanup is
already registered. Owners that expose `release`/`adopt` can transfer backing
storage as a separate representation-level operation.

Overwriting a live owner with ordinary assignment loses its old resource. Call
`deinit`, `reset`, or a lifetime-aware replacement operation first.

Types whose D destructor performs automatic work remain non-copyable because
each copy would run that work. Address-sensitive values may be copied during
construction, but must remain at a stable address after an internal pointer
escapes or the value is published to another thread.
