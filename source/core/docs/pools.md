# Virtual arrays and pools

XTB provides three fixed-capacity, stable-address containers:

| Type | Use |
|---|---|
| `VirtualArray!T` | growable logical array whose elements never move |
| `Pool!T` | recyclable stable slots addressed by pointer/index |
| `GenerationalPool!T` | recyclable slots with stale-handle detection |

All three reserve a maximum address range and commit backing storage as needed.
They are explicit owners and must be `deinit`ed.

## `VirtualArray`

```d
VirtualArray!int values = VirtualArray!int.create(1_000_000);
scope(exit) values.deinit();

values.append(10);
int* first = &values[0];
values.resize(10_000);
assert(first is &values[0]);
```

Shrinking or clearing changes the logical length but does not finalize discarded
elements. `trim()` can release unused committed backing without moving the
reservation.

## `Pool`

`Pool!T` keeps stable addresses and stable slot indices. Index zero is reserved.
A recycled slot may later be reused with the **same index and address**, so use
`Pool` only when the application can ensure stale pointers/indices are not used.

```d
Pool!Entity pool = Pool!Entity.create(100_000);
scope(exit) pool.deinit();

Entity* entity = pool.construct(/* ... */);
uint index = pool.indexOf(entity);
assert(pool.get(index) is entity);
pool.deallocate(entity);
```

`deallocate` recycles storage without finalizing `T`; `dispose` finalizes first
when `T` can be finalized without external context.

## `GenerationalPool`

Use `GenerationalPool!T` when handles may outlive the slot they refer to. A
handle contains an index and generation. Recycling advances the generation, so
an old handle no longer resolves even if that index is reused. Stale-handle
rejection is normal semantic behavior and remains enabled in `release-fast`.

```d
GenerationalPool!Entity pool = GenerationalPool!Entity.create(100_000);
scope(exit) pool.deinit();

auto handle = pool.construct(/* ... */);
Entity* entity = pool.get(handle);
pool.deallocate(handle);
assert(pool.get(handle) is null);
```

Handles belong to the pool instance that created them. `tryDeallocate` and
`tryDispose` return `false` for invalid/stale handles; their non-`try` variants
panic instead.

## Iteration

Both pool types provide stable-index-order ranges:

| Range | Contains |
|---|---|
| `items()` | live values |
| `indexedItems()` | live values with indices |
| `occupiedSlots()` | live slot metadata and values |
| `slots()` | every provisioned slot, including inactive slots |

For a generational pool, `occupiedSlots()` also exposes the generation and
handle. Use `slots()` only when inactive slot representation is relevant.
Structural mutation invalidates an existing range; checked builds diagnose use
after invalidation.

`clear()` and `deinit()` are shallow: they do not finalize live values. Clean up
owned values first, or use `dispose` per item where applicable. See the
[deinit protocol](deinit.md) for the general rule.

The containers are not synchronized; use external synchronization for concurrent
access.

See [`entity_component_system_demo.d`](../../../examples/entity_component_system_demo.d)
and [`pool_world_demo.d`](../../../examples/pool_world_demo.d).
