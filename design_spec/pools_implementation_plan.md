# XTB fixed-capacity pools implementation plan

## Status

**Implementation in progress. Steps 1–5 of 8 are complete and verified.**

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

## Step 2 — `VirtualArray!T` ownership and storage core — COMPLETE

Added public `xtb.core.virtual_array.VirtualArray!T` as a move-only owner over one
fixed virtual reservation.

Implemented contract:

- `tryCreate/create` reserve a fixed maximum typed capacity and never relocate;
- capacity zero succeeds as the inert state without requiring VM support;
- the complete typed capacity starts inaccessible and is committed lazily;
- `ptr` is stable for every nonzero-capacity owner and may point into an
  inaccessible tail, so it is `@system`;
- `slice` and indexing expose only logical `[0 .. length)`, which remains empty
  until lifetime-aware operations arrive in Step 3;
- package-internal `tryEnsureAccessible(elementCount)` commits raw typed storage
  without constructing `T` or changing logical length;
- commitment grows in a normalized page-multiple granularity and clamps the
  final growth to the page-rounded typed region;
- `capacity * T.sizeof`, page rounding, commit-granularity rounding, alignment
  geometry, and address arithmetic are overflow checked;
- when `T.alignof` exceeds native page alignment, creation over-reserves enough
  address space to choose an interior base aligned to both the page size and
  `T.alignof`; the original reservation remains the release owner;
- failed creation leaves an inert output unchanged;
- move/moveAssign preserve the mapped address and reconstruct the source to the
  valid inert state;
- `deinit` is shallow, repeatable, and releases the whole reservation.

Implementation refinement:

Step 2 intentionally does **not** publish raw-provisioning as logical array
growth. A committed page does not establish a D `T` lifetime. `length` therefore
remains independent of committed storage, and Step 3 will be the only public
layer that advances it through lifetime-aware resize/append operations.

Acceptance coverage:

- zero capacity and repeated deinit;
- reservation/element-count overflow;
- non-page commit granularity normalization;
- repeated provisioning across granularity boundaries with a stable pointer;
- exact capacity and one-past-capacity rejection;
- move and moveAssign;
- element alignment larger than the native page size;
- BetterC `nothrow @nogc` attribute compilation;
- full debug-suite regression coverage.

Commit target: `feat(core): add fixed-capacity virtual array storage`.

## Step 3 — complete and harden `VirtualArray!T` — COMPLETE

Completed the public logical-container layer over the fixed virtual storage.

Implemented contract:

- `tryResize/resize` default-initialize newly added elements when `T` supports
  default initialization; shrinking is shallow and never decommits by itself;
- `tryAppend(scope T*)` moves only after storage provisioning succeeds, so
  failure preserves both the source and all existing array contents;
- copyable `T` also supports slice append, including slices that alias the same
  `VirtualArray`;
- `append(T)`, `back`, and `pop` mirror the transfer semantics of `Array!T`;
- `clear` is shallow and retains committed pages;
- `trim` is the explicit physical-reclamation operation and decommits only
  complete pages beyond the logical prefix while preserving fixed capacity and
  the stable base address;
- recommitting pages previously discarded by `trim` observes the VM substrate's
  fresh zero-filled backing;
- logical operations never relocate existing elements;
- `VirtualArray!T` deliberately follows shallow `Array!T` ownership semantics:
  discarded values are not finalized by resize-shrink, clear, trim, or deinit.

Implementation refinements:

- `appendAssumeCapacity` is intentionally omitted. Reserved virtual capacity does
  not imply that the target pages are committed, so an "assume capacity" API
  would incorrectly suggest that append cannot fail. `tryAppend` is the correct
  primitive.
- No separate element-cleanup API was added in this step because ordinary
  `Array!T` is also shallow. Callers that own cleanup-bearing elements must
  explicitly finalize them before shallow discard, or a future owning virtual
  array abstraction can provide those semantics separately.

Acceptance coverage:

- zero/exact/one-past capacity behavior;
- default initialization and logical shrink/regrow;
- scalar move append and aliased slice copy append;
- transactional append/resize failure;
- stable pointers across every growth path;
- `back` and ownership-transferring `pop`;
- explicit-deinit and destructor-only move-only values;
- shallow clear/deinit behavior;
- trim, retained live pages, recommit zero-fill, and unchanged virtual capacity;
- over-aligned `T`;
- BetterC `nothrow @nogc` and `@safe`/`@system` boundaries;
- full debug-suite regression coverage.

Commit target: `feat(core): complete virtual array container`.

## Step 4 — internal `VirtualArrayView!T` — COMPLETE

Added the raw non-owning storage view used to partition one reservation.

Implemented representation and contract:

- `VirtualMemoryRegion region_` owns the bounded borrow, never mapping lifetime;
- typed stable data pointer;
- fixed capacity;
- monotonic provisioned element high-water;
- committed byte prefix;
- normalized commit granularity;
- the view is non-copyable because mutable bookkeeping must have one source of
  truth;
- local `deinit` ends/reset the borrow without releasing or decommitting the
  parent mapping, and makes XTB moves reconstruct the source to the inert state;
- moving the reservation owner does not invalidate the view because no owner
  field address is stored;
- capacity zero accepts only an empty region;
- nonzero creation validates `capacity * T.sizeof`, region bounds, and `T`
  alignment without committing pages.

Central operation `tryEnsureAccessible(elementCount)`:

- commits enough pages for the requested typed prefix;
- never constructs, initializes, moves, copies, or finalizes `T`;
- advances `provisionedLength_` only to the explicitly requested element
  high-water;
- does not claim extra elements merely because page/granularity rounding made
  their bytes accessible;
- is monotonic and transactional in its bookkeeping;
- never releases the parent reservation.

`trim()` may decommit only whole pages beyond the provisioned prefix. It does not
reduce the provisioned element high-water or fixed capacity.

Implementation refinement:

The owning `VirtualArray` and borrowed `VirtualArrayView` now share private
prefix-commit and prefix-trim helpers. This keeps page rounding, granularity
clamping, and decommit behavior identical instead of maintaining two subtly
different VM-growth implementations.

Acceptance coverage:

- adjacent typed views in one reservation;
- independent commit/decommit boundaries;
- moved reservation owner with live views;
- moved view reconstructs source to inert state;
- no owner-pointer dependency;
- over-aligned region acceptance and deliberate misalignment rejection;
- capacity/multiplication failure leaves output inert;
- provisioned-element high-water remains distinct from page-rounded committed
  storage;
- bytes already present in newly provisioned raw storage are not initialized;
- view `deinit` does not release the parent reservation;
- BetterC `nothrow @nogc` and `@safe`/`@system` boundary compilation.

Commit target: `feat(core): add internal virtual array views`.

## Step 5 — fixed-capacity `Pool!T` — COMPLETE

Added public `xtb.core.pool.Pool!T` directly over one fixed virtual reservation;
Pool has no Arena or backing allocator dependency.

Implemented layout:

```text
T values[capacity + 1]             // index 0 invalid
occupancy bitmap                   // machine-word bits
uint freeIndices[capacity]
```

All three regions are page-bounded and independently provisioned through
`VirtualArrayView`. Creation reserves the complete address-space layout while
committing zero pages.

Implemented contract:

- fixed maximum `uint` capacity with index zero permanently invalid;
- stable indices and stable `T*` addresses for the Pool lifetime;
- raw `tryAllocate/allocate`, initialized `tryAllocateInit/allocateInit`, and
  `tryConstruct/construct`;
- virgin allocation provisions value storage, the containing occupancy word,
  and enough free-index stack storage for that index before publishing it;
- any partial VM provisioning failure leaves Pool logical state unchanged;
- recycled allocation pops a compact LIFO integer index and performs no VM
  operation;
- `deallocate` clears occupancy and pushes the index without committing,
  allocating, finalizing, or writing `T`;
- `dispose` is available only when `T` can be finalized without external
  cleanup context;
- `get`, `contains`, `indexOf`, capacity/live-count/empty queries;
- shallow `clear` resets logical occupancy/frontiers but preserves value bytes
  and all provisioned/committed storage;
- shallow repeatable `deinit` releases the one reservation without walking live
  values;
- move/moveAssign preserve the reservation and reconstruct the source to the
  inert state;
- checked builds diagnose double-free, foreign-pointer free, and misaligned
  pointer free.

Implementation refinements:

- `VirtualArray` now exposes package-internal `VirtualArrayRegionGeometry`, the
  default VM commit granularity, and address-alignment helper. Owning
  `VirtualArray` and Pool therefore share the exact same typed-capacity
  overflow/page/alignment geometry instead of duplicating it.
- `VirtualArrayView` gained a const `ptr` overload so const Pool lookup can use
  the same bounded raw-storage view without casting away const.
- Pool does not carry range-invalidation generation yet; that checked-only
  field belongs with the ranges that consume it in Step 6.

Acceptance coverage:

- capacity zero and exact/full capacity;
- sequential indices beginning at one and bitmap traversal across multiple
  occupancy words;
- LIFO recycled reuse;
- a free-index 64 KiB commit-boundary case proving publication provisions the
  next recycle slot before exposure;
- commit counters unchanged by deallocation and recycled allocation;
- tiny and 32 KiB-over-aligned `T`;
- byte-for-byte inactive representation preservation after deallocation and
  shallow clear;
- explicit-deinit and D-destructor disposal;
- shallow clear/deinit do not finalize values;
- context-requiring finalizers do not expose `dispose`;
- moves and zero-state cleanup;
- checked double-free/foreign/misaligned-pointer death tests;
- full debug suite, focused ASan core/integration, release-safe and
  release-fast library builds, formatter/linter/diff checks.

Commit target: `feat(core): add fixed-capacity virtual pool`.

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
