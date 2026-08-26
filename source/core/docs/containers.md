# Container ownership

XTB distinguishes containers that own only their backing storage from containers
that also own cleanup of their elements.

| Container | What it owns |
|---|---|
| `Array!T` | backing allocation only |
| `OwnedArray!T` | backing allocation and every live element |
| `HashMap!(K, V)` | table storage; keys and values are shallow |
| `OwnedHashMap!(K, V)` | table storage plus key/value cleanup |
| `HashSet!T` | table storage; elements are shallow |
| `OwnedHashSet!T` | table storage plus element cleanup |

A shallow container never calls `deinit` merely because an element is removed,
replaced, cleared, or the container itself is deinitialized. Use it for trivial
or borrowed values, or when element lifetime is managed elsewhere.

```d
Array!int values = Array!int.create(heap);
scope(exit) values.deinit();
values.append(1);
values.append(2);
```

Use an owned container when the container should destroy discarded values:

```d
OwnedArray!OwnedString names = OwnedArray!OwnedString.create(heap);
scope(exit) names.deinit();

names.append("alpha".copy(heap));
names.append("beta".copy(heap));
names.removeAt(0); // deinitializes "alpha"
```

Owned containers require elements that can be finalized without extra cleanup
context. Operations such as `pop` or `take` transfer a value out instead of
finalizing it; the caller then owns its cleanup obligation.

## String-key containers

String keys have an additional ownership choice:

| Container | String bytes | Values |
|---|---|---|
| `StringViewHashMap!V` | borrowed | shallow |
| `StringViewHashSet` | borrowed | shallow |
| `StringHashMap!V` | owned | shallow |
| `OwnedStringHashMap!V` | owned | owned |
| `StringHashSet` | owned | — |

Generic `HashMap!String` / `HashSet!String` behave like other shallow hash
containers: they store the `String` view but do not own the referenced bytes.
Use the string-owning variants when keys must survive independently of their
input storage.

## Managed and unmanaged forms

Managed containers store their `Allocator*`, so normal operations and `deinit`
do not need the allocator repeated. Types ending in `Unmanaged` store only the
container state and receive an allocator explicitly for allocating or freeing
operations.

Prefer the managed form for ordinary standalone values. The unmanaged form is
useful when another type already owns the allocator relationship and wants a
smaller embedded container.

All owning containers are move-only. Use `move` for ownership transfer; where a
container exposes `release` / `adopt`, those operations transfer its backing
storage without copying it.
