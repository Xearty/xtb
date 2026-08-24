# Virtual arrays and pools

XTB's virtual containers reserve a fixed maximum address range up front and
commit physical backing lazily. They are BetterC containers: no GC, exceptions,
classes, or hidden element cleanup are involved.

The public types are:

```d
VirtualArray!T
Pool!T
GenerationalPool!T
```

`Pool!T` and `GenerationalPool!T` require a maximum capacity at creation. Index
zero is permanently invalid in both pool families.

## VirtualArray

`VirtualArray!T` is a fixed-capacity owning array whose element addresses never
move. Creation reserves address space for the maximum capacity but does not
commit the whole range.

```d
VirtualArray!int values = VirtualArray!int.create(1_000_000);
scope (exit) values.deinit();

values.append(10);
values.append(20);
values.resize(100);

int* first = &values[0];
values.resize(10_000);
assert(first is &values[0]);
```

Growing operations commit additional pages when needed. Shrinking and `clear()`
change logical length but retain committed pages for reuse. `trim()` decommits
unused backing while preserving the fixed capacity and stable base address.

Like XTB's shallow `Array!T`, shrinking, clearing, and deinitializing a
`VirtualArray` do not walk discarded elements or invoke element cleanup. Code
that stores explicit owners must discharge their cleanup obligations before
abandoning them.

## Pool

`Pool!T` is a stable-address, stable-index recycling pool. It owns one virtual
reservation partitioned into three page-separated regions:

```text
T values[capacity + 1]
occupancy bitmap
uint freeIndices[capacity]
```

The first usable item has index 1. Values never move and Pool never stores
recycling metadata inside `T`, so deallocation preserves the inactive value's
byte representation.

```d
Pool!Entity entities = Pool!Entity.create(100_000);
scope (exit) entities.deinit();

Entity* entity = entities.construct(/* ... */);
uint index = entities.indexOf(entity);

entities.deallocate(entity); // storage only; representation remains

Entity* reused = entities.allocate();
assert(entities.indexOf(reused) == index);
```

Use `dispose` instead of `deallocate` when `T` has context-free cleanup that
should run before recycling:

```d
pool.dispose(value);
```

Virgin allocation provisions all storage needed to recycle the slot later
before it publishes the index. Consequently a successful `deallocate()` does
not allocate memory or commit virtual pages.

`clear()` is shallow. It removes all live Pool state and resets sequential
allocation while preserving committed pages and existing value representations.
`deinit()` is also shallow and releases the complete reservation.

## GenerationalPool

`GenerationalPool!T` adds stale-handle detection while keeping `T` untouched.
Its storage is:

```text
T values[capacity + 1]
uint states[capacity + 1]
uint freeIndices[capacity]
```

Each state packs one active bit and a 31-bit generation. Generation zero is a
normal generation. Index zero is reserved, so a zero-initialized handle is
naturally invalid:

```d
alias EntityPool = GenerationalPool!Entity;

EntityPool pool = EntityPool.create(100_000);
scope (exit) pool.deinit();

EntityPool.Handle handle = pool.construct(/* ... */);
Entity* entity = pool.get(handle);

pool.deallocate(handle);
assert(pool.get(handle) is null); // stale
```

A recycled slot retains its index and advances its generation. Handles are
relative to the `GenerationalPool!T` instance that created them; they do not
carry a global Pool identity and must not be mixed between two pools of the same
`T`. `Handle.valid` only reports whether the handle is non-null (`index != 0`);
a non-null handle may still be stale or foreign. `get` and `contains` perform
the pool-relative check and reject null, inactive, out-of-range, and stale
handles in every build mode. `tryDeallocate`/`tryDispose` report stale handles
as ordinary failure; their infallible counterparts panic on invalid or stale
handles.

`clear()` advances the generation of every live slot before resetting the
allocation frontier, so every previously live handle becomes stale while value
representations remain untouched.

The generation uses 31 bits because the high bit stores activity. After
`2^31` recycle cycles of the same slot the generation wraps, so a sufficiently
old handle with the same index can theoretically compare equal again. This is
an explicit bounded-generation handle contract rather than permanent global
identity.

## Iteration

Both pool types expose the same three range names.

### `items()`

The common hot path yields only live values directly by reference:

```d
foreach (ref entity; pool.items())
    entity.update();
```

Plain Pool walks its occupancy bitmap word-wise and skips empty words.
GenerationalPool scans its packed state prefix and tests the active bit.

### `indexedItems()`

Use this when the common live-item traversal also needs the stable index. It
uses the same occupancy cursor as the other live ranges and performs no second
bitmap/state scan:

```d
foreach (item; pool.indexedItems())
    formatln!"slot {}: {}"(item.index, item.value);
```

The entry intentionally contains only the stable index and live value. For a
`GenerationalPool`, use `occupiedSlots()` when the generation or complete handle
is also needed. Existing `items()` remains the minimum-overhead direct-`ref T`
range.

### `occupiedSlots()`

Use this when live values and the full slot identity view are both needed.

Plain Pool slots expose:

```text
index
ref T value
```

GenerationalPool slots additionally expose:

```text
generation
handle
```

Example:

```d
foreach (slot; pool.occupiedSlots())
{
    auto handle = slot.handle;
    slot.value.update();
}
```

### `slots()`

`slots()` walks every deliberately provisioned slot, including inactive ones.
It does not walk untouched maximum-capacity storage.

```d
foreach (slot; pool.slots())
{
    if (slot.occupied)
        use(slot.value);

    inspectRepresentation(slot.storage);
}
```

For GenerationalPool, each slot also exposes its current generation. Its
`handle` is the live handle when occupied and `Handle.init` when inactive.

`storage` deliberately exposes the `T` representation even when no live `T`
object exists there, so it is an `@system` boundary. `value` likewise requires
the slot to be occupied.

Structural pool mutation invalidates all ranges and escaped slot proxies.
Checked builds diagnose use after allocation, deallocation, clear, move, or
deinit. The diagnostic generation/base snapshots compile out when
`XTB_Checked` is disabled.

## Entity-component-system example

`examples/entity_component_system_demo.d` builds a small ECS directly from the
virtual containers. Entity identity comes from `GenerationalPool!Entity`; each
component type uses a sparse `Pool` plus a `VirtualArray!uint` entity-index map.
Systems join component stores by iterating only present components and doing
O(1) lookup into the other store. The example also demonstrates stale-handle
rejection after entity-index reuse, two-phase destruction while Pool ranges are
active, and `occupiedSlots()` when the stable component-pool index is needed.

Run it with:

```text
just run example entity-component-system
```

## Pool world example

`examples/pool_world_demo.d` builds a small game-world-style object graph from
generational pools. An `Entity` owns typed handles to independently pooled
position, health, render, and optional attack state; systems traverse the pools
that contain the data they operate on and resolve cross-pool relationships by
generational handle.

The movement system deliberately uses `slots()` and updates every provisioned
`Position` representation without an occupancy branch. Fresh virtual pages are
zero-filled, Pool recycling does not overwrite `T`, and construction replaces a
reused slot before it becomes semantically live, so inactive numerical position
state can be updated harmlessly. Other systems use live-item iteration when
liveness matters. The multi-tick simulation also demonstrates destruction,
immediate slot reuse with a new generation, a stale attack target being rejected,
and explicit retargeting.

This is object composition over pools rather than an entity-component system.

Run it with:

```text
just run example pool-world
```

## Lifetime and ownership rules

The containers are explicit owners and are non-copyable. Transfer ownership
with XTB's move helpers and release them with `deinit`.

Pool operations distinguish storage recycling from value finalization:

```text
deallocate  recycle storage only
dispose     finalize when context-free, then recycle
clear       shallow bulk logical reset
deinit      shallow reservation release
```

Neither pool walks live values during `clear` or `deinit`.

Raw `allocate` activates a slot without constructing `T`; it is intended for
low-level callers that establish the value lifetime themselves. Prefer
`allocateInit` or `construct` for ordinary live values.

## Performance model

All element addresses are stable because none of these containers reallocate
or move their reserved storage.

Plain Pool uses one occupancy bit per slot and a 32-bit free-index stack.
GenerationalPool uses one 32-bit packed state and one 32-bit free-index entry per
capacity slot in virtual address space. Only pages actually provisioned by use
are committed.

`just benchmark pools` runs opt-in microbenchmarks for dense/sparse iteration,
index scanning, recycling, generational handle lookup, state scanning, and a
large-reservation/small-live-set case. Output is grouped into aligned scan and
operation tables; when stdout is an ANSI-capable terminal, section/header
colors aid visual parsing while `NO_COLOR`, `TERM=dumb`, and redirected output
remain plain. Scan benchmarks report occupancy plus three normalizations
together: nanoseconds per yielded live item, nanoseconds per deliberately
provisioned slot, and microseconds per complete scan. The first describes
useful-item cost, the second isolates raw traversal cost, and the third gives
the wall-clock cost of traversing the whole pool. Reporting all three avoids
making sparse pools look slower merely because scan overhead is amortized
across fewer live values.

Scan timings use a warm-up followed by five substantially longer timed samples
and report the median sample. The benchmark prints the scans-per-sample, sample
count, and warm-up count in its header. This avoids interpreting sub-millisecond
scheduler/preemption noise as a property of an iterator layout.

Plain `Pool` also reports nonzero and zero occupancy-bitmap word counts and
benchmarks two 12.5%-occupied layouts with the same 512 live slots. The
benchmark deliberately mirrors Pool's real bitmap coordinates: index `0` is
reserved, so capacity 4096 covers bitmap indices `0..4096`, requiring **65**
64-bit words, and slot `index` belongs to word `index / 64`. The benchmark
prints this geometry before the table and derives the displayed nonzero-word
counts from the live indices that were actually created.

The **interleaved** layout keeps every eighth slot live. This leaves at least
one live bit in every one of the 65 bitmap words, so **65/65 words are
nonzero** and `items()` cannot skip a whole occupancy word. The **clustered**
layout instead keeps the actual bitmap words `0, 8, 16, ..., 64` live and
clears the seven words between them. It still has exactly 512 live slots, but
only **9/65 words are nonzero** and **56 whole words are zero/skippable**. The
fixture validates these invariants at runtime before timing begins, so a future
capacity/layout change cannot silently make the benchmark labels false.

The benchmark is intended to guide representation changes; the current design
deliberately avoids a second GenerationalPool occupancy bitmap until workload
measurements justify the additional duplicated state invariant.

The containers are not synchronized. Concurrent access requires external
synchronization.
