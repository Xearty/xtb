# XTB fixed-capacity pools implementation plan

## Status

**Implementation in progress. Step 1 of 8 is complete and verified.**

This is the execution plan for `design_spec/pools.md`. The design document is
authoritative for semantics; this document defines implementation order,
validation gates, and delivery boundaries.

Maintain both documents with every step. If implementation reveals a materially
simpler, safer, or faster representation, update the design and this plan in the
same commit rather than carrying a known-worse design forward.

Each step is delivered as an independently buildable commit. The cumulative
mbox begins with Step 1 and grows by one commit per completed step.

## Step 1 — bounded virtual-memory regions — COMPLETE

Add a non-owning `VirtualMemoryRegion` below future virtual containers.

Implemented contract:

- the existing `VirtualMemoryReservation` remains the sole mapping owner;
- a reservation can create a page-bounded region with `tryRegion`;
- a region can create a nested page-bounded region;
- regions store stable mapped addresses, never pointers to owner fields;
- regions are copyable borrowed values because they own no mutable commitment
  bookkeeping;
- region commit/decommit is bounded to the region and preserves the existing
  zero-length no-op behavior;
- failed region construction leaves its output unchanged;
- empty regions use `VirtualMemoryRegion.init`;
- moving the reservation owner does not invalidate already-created regions;
- releasing the reservation invalidates all of its borrowed regions just as
  destroying an owner invalidates ordinary borrowed slices.

Acceptance coverage:

- page alignment and out-of-bounds rejection;
- zero-sized reservation/region behavior;
- nested subregions;
- adjacent-region commit/decommit independence;
- decommit/recommit zero filling;
- output preservation on failed region construction;
- reservation move with a live borrowed region;
- BetterC `nothrow @nogc` attribute compilation.

Commit target: `refactor(core): add bounded virtual memory regions`.

## Step 2 — `VirtualArray!T` ownership and storage core

Introduce the public move-only owner while keeping the initial API deliberately
small.

Implement:

- `VirtualArray!T.tryCreate/create` with a fixed maximum capacity;
- valid `.init` and explicit `deinit`;
- stable typed base pointer;
- `capacity`, `length`, indexing, and logical-prefix slicing;
- checked byte-size/element-count arithmetic;
- no relocation after successful creation;
- internal prefix provisioning/commit bookkeeping;
- configurable/default commit granularity;
- capacity zero;
- arbitrary `T.alignof`, including alignments larger than the OS page size.

The implementation must over-reserve/choose an aligned typed base when native
reservation alignment is insufficient for `T.alignof`; it must not assume a
page-aligned reservation is automatically aligned for every D type.

Acceptance gate:

- creation/failure leaves outputs transactionally valid;
- repeated growth keeps `ptr` stable;
- exact capacity and one-past-capacity behavior;
- multiplication/alignment overflow;
- page and commit-granularity crossings;
- moves/moveAssign where supported by XTB lifetime rules;
- zero state and repeated deinit;
- over-aligned element types;
- BetterC attributes and public safety boundaries.

Commit target: `feat(core): add fixed-capacity virtual array storage`.

## Step 3 — complete and harden `VirtualArray!T`

Make `VirtualArray!T` a robust first-class container before any Pool code may
depend on it.

Add the Array-like operations that transfer cleanly to fixed virtual capacity:

- `tryResize/resize`;
- append operations;
- pop/back where appropriate;
- `clear` retaining committed pages;
- `trim` decommitting the unused committed suffix without changing capacity;
- lifetime-aware construction/default-initialization and explicit cleanup
  operations where they are sound under the fixed-capacity model.

`resize(smaller)` must not automatically decommit. `trim()` is the explicit
physical-backing reduction operation; `shrinkToFit` is intentionally not used
because reserved capacity remains fixed.

Failure contract: a failed logical operation leaves length and existing element
contents unchanged. Harmless additional committed pages may remain after a
native operation fails, but they must not become part of the promised logical
prefix.

Acceptance gate:

- broad normal/boundary/failure tests;
- nontrivial and move-only values where supported;
- destructor/explicit-deinit behavior matching documented ownership semantics;
- trim/regrow zero-fill behavior for newly recommitted raw backing;
- stable references/pointers across every growth path;
- ASan;
- release-safe and release-fast;
- full debug suite.

**Pool work does not begin until this step is comprehensively clean.**

Commit target: `feat(core): complete virtual array container`.

## Step 4 — internal `VirtualArrayView!T`

Add the raw non-owning storage view used to partition one reservation.

Representation owns local bookkeeping, not mapping lifetime:

- `VirtualMemoryRegion region_`;
- typed stable data pointer;
- fixed capacity;
- provisioned element high-water;
- committed byte prefix;
- commit granularity.

The view is non-copyable because two mutable copies could disagree about
provision/commit state. Moving it is safe because the region stores the mapped
address directly rather than an owner pointer.

Central operation: `tryEnsureAccessible(elementCount)`.

It:

- commits enough pages for the requested typed prefix;
- never constructs `T`;
- advances `provisionedLength_` only to the explicitly requested element
  high-water;
- does not claim extra elements merely because page rounding made their bytes
  accessible;
- never releases the parent reservation.

Acceptance gate:

- adjacent typed views in one reservation;
- independent commit/decommit boundaries;
- moves;
- no owner-pointer dependency;
- over-aligned layouts;
- provisioned-element high-water distinct from page-rounded committed storage.

Commit target: `feat(core): add internal virtual array views`.

## Step 5 — fixed-capacity `Pool!T`

Implement plain Pool directly over one virtual reservation; do not depend on
Arena.

Reservation layout:

```text
T values[capacity + 1]             // index 0 invalid
occupancy bitmap                   // machine-word bits
uint freeIndices[capacity]
```

All three regions are page-separated so one view can trim/decommit without
changing another region.

Virgin-index publication is transactional. Before index `i` can become visible,
Pool must provision:

1. value storage through `i`;
2. the occupancy word containing `i`;
3. free-index storage sufficient to recycle `i` later.

Only then may Pool advance its virgin frontier and mark the slot occupied. This
is the core invariant that makes `deallocate()` infallible and prevents it from
ever allocating or committing memory.

Implement:

- fixed maximum capacity and index zero invalid;
- raw allocate / initialized allocate / typed construction;
- `deallocate` preserving every byte of inactive `T` storage;
- `dispose` finalizing then recycling where context-free cleanup is valid;
- `get`, occupancy/index queries, counts, clear, move, deinit;
- checked misuse diagnostics that disappear where they are not semantic.

`clear` is shallow: it does not finalize values and does not overwrite preserved
inactive representations.

Acceptance gate:

- tiny and over-aligned `T`;
- exact/full capacity and failure paths;
- recycled allocation without VM calls;
- deallocation proven not to commit/allocate;
- representation preservation after deallocation and clear;
- explicit-deinit and D-destructor cases;
- moves and zero-state cleanup;
- ASan and full debug suite.

Commit target: `refactor(core): add fixed virtual pool storage` (or a more
accurate `feat` message if no public Pool exists in the implementation baseline).

## Step 6 — Pool ranges

Add three allocation-free range APIs:

```d
pool.items()
pool.occupiedSlots()
pool.slots()
```

`items()` is the hottest path and yields `ref T` directly.

`items()` and `occupiedSlots()` share optimized bitmap traversal: load a machine
word, skip zero words, use trailing-zero/set-bit removal to visit only live
indices.

`occupiedSlots()` yields a lightweight proxy exposing index plus `ref T`.

`slots()` walks every deliberately provisioned slot, including inactive slots,
and exposes index, occupancy, checked live `value`, and raw representation
`storage` access. It must not scan the full maximum capacity when only a small
prefix has ever been provisioned.

Checked builds should diagnose structural invalidation of an active range if a
small checked-only mutation generation is sufficient; no such bookkeeping
belongs in release-fast unless required for semantics.

Acceptance gate:

- empty/dense/sparse traversal;
- stable order;
- mutation through returned refs;
- inactive slot representation access;
- early termination/manual range use;
- multiple independent ranges;
- optimized-code comparison/benchmark against the equivalent handwritten bitmap
  loop to ensure the range abstraction disappears.

Commit target: `feat(core): add pool slot and item ranges`.

## Step 7 — `GenerationalPool!T`

Implement a distinct generational container over the same region/view
foundation rather than layering it on `Pool!T`.

Layout:

```text
T values[capacity + 1]
uint states[capacity + 1]
uint freeIndices[capacity]
```

Packed state:

```text
bit 31      active
bits 0..30  generation
```

Generation zero is valid. Index zero remains invalid so `Handle.init` is
naturally invalid.

Handle:

```d
struct Handle
{
    uint index;
    uint generation;
}
```

A handle identifies one specific live incarnation of one stable slot. It does
not provide storage-independent logical identity.

Never increment the packed state value directly. Isolate active-bit and
generation arithmetic behind small helpers so generation wrap cannot carry into
the active bit. Explicitly define/test generation wrap from `0x7fff_ffff` to
zero.

Stale-handle rejection is semantic and remains enabled in release-fast.
`clear()` must invalidate every live handle by advancing each live slot's
generation before marking it inactive.

Acceptance gate:

- valid/stale/null handles;
- same index reused with a new generation;
- generation wrap;
- clear invalidation;
- packed-state correctness in all build modes;
- no deallocation VM calls;
- preserved inactive `T` representation;
- ASan/full debug/release-fast validation.

Commit target: `feat(core): add generational pool`.

## Step 8 — generational ranges, benchmarks, docs, and final audit

Give `GenerationalPool!T` the same range vocabulary:

```d
items()          // ref T
occupiedSlots()  // index + generation + handle + ref T
slots()          // all provisioned slots + state/storage metadata
```

Initially scan the packed state array directly. Do not add a second occupancy
bitmap or other summary index unless benchmarks demonstrate a real need.

Benchmark/review:

- dense and sparse plain Pool iteration;
- range versus handwritten bitmap loop;
- recycled allocation/deallocation;
- generational handle lookup;
- generational state scanning;
- large reserved capacity with a small live set;
- page-boundary growth and physical backing;
- metadata/cache footprint.

Final repository audit covers lifetime correctness, stale handles, overflow,
alignment, range invalidation, move correctness, unchecked overhead, naming,
documentation/examples, and public aggregate exports.

Commit target: documentation may stay with feature commits; use a final docs
commit only for genuinely cross-cutting material that could not accurately land
earlier.

## Validation policy

Every step leaves the repository buildable. At minimum run the focused unit and
integration tests, the core example, release-safe/release-fast builds relevant
to the changed component, ASan for affected core paths, `dfmt`, `dscanner`, and
`git diff --check`.

Run the full debug suite at Steps 3, 5, 7, and on the final tree. Run it earlier
whenever a low-level change has broad enough blast radius to justify it.

The critical dependency gates are:

```text
Step 3 comprehensively clean
        ↓
Pool may depend on VirtualArray machinery

Step 4 comprehensively clean
        ↓
Pool may partition one reservation

Step 5 proves deallocation never allocates/commits
        ↓
Ranges may rely on stable provision/recycling invariants

Step 7 proves stale-handle semantics in every build mode
        ↓
Generational ranges/API are finalized
```
