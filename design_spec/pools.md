# XTB Fixed-Capacity Pools and Virtual Storage Design

## Status

**Approved design — implementation in progress. Steps 1–2 are implemented and verified.**

Maintain this document together with `design_spec/pools_implementation_plan.md`. If implementation reveals a materially simpler, safer, or faster representation, update the design in the same step rather than preserving incidental details from the original proposal.

This document supersedes the earlier proposed Arena-backed `Pool!T` representation. The fixed-capacity virtual-memory design below better satisfies the requirements that emerged during review:

- pool elements keep stable addresses;
- inactive elements preserve their representation;
- pool elements contain no free-list pointers;
- iteration over live elements is efficient;
- slot indices are first-class and stable;
- `Handle.init` is invalid for generational pools;
- deallocation is infallible and does not allocate or commit memory;
- maximum capacity is explicit;
- physical memory is committed only as the pool grows;
- `Pool!T` and `GenerationalPool!T` share a common virtual-storage foundation without forcing generational metadata onto the plain pool;
- virtual-memory details stay below the pool implementation.

The design introduces a robust public `VirtualArray!T` container and an internal virtual-array storage view used to partition one reservation into several typed regions.

---

## 1. Design principles

The implementation should follow these rules.

### 1.1 Fixed maximum capacity

A pool is created with a maximum number of items:

```d
Pool!Entity pool = Pool!Entity.create(1_000_000);
scope(exit) pool.deinit();
```

The maximum capacity never changes. The pool reserves enough **virtual address space** for that capacity at creation time, but it does not commit/touch physical pages for every element up front.

This trades an effectively cheap 64-bit virtual-address reservation for:

- stable addresses;
- stable indices;
- no relocation;
- no block lookup tables;
- no per-item allocation calls;
- simple O(1) index-to-element lookup;
- predictable maximum memory geometry.

### 1.2 Index zero is invalid

Pool indices start at `1`.

```text
0        invalid / null index
1        first usable slot
2        second usable slot
...
```

The wasted slot is negligible and provides a useful universal sentinel.

For generational handles:

```d
Handle.init == Handle(0, 0)
```

is therefore naturally invalid without special initialization logic.

Generation `0` itself remains valid. Only index `0` is the null sentinel.

### 1.3 Item representation and lifetime state are separate

The `T` storage must contain only `T`.

Pool metadata must not be embedded in or overlaid onto inactive `T` storage.

In particular, the design rejects the original free-list representation:

```text
live:  T
free:  FreeSlot* next
```

because freeing an item destroys its representation and introduces pointer-shaped data into item storage.

Instead:

```text
values[index]       object representation
state[index]        occupancy / generation metadata
freeIndices[...]    recycling stack
```

`deallocate()` changes metadata only. It does not write to `values[index]`.

### 1.4 Deallocation must be infallible

Once a slot has been made usable, recycling it must require:

- no allocator call;
- no virtual-memory commit;
- no capacity growth;
- no failure path.

The pool guarantees this by provisioning free-index storage alongside each newly exposed virgin index.

### 1.5 Plain and generational pools remain distinct

`Pool!T` should not pay for generation counters it does not use.

`GenerationalPool!T` should provide real stale-handle protection in release builds, not merely checked-build diagnostics.

They should share internal storage/layout helpers where useful, but remain separate public abstractions.

### 1.6 Explicit lifetime semantics remain XTB-style

Pool bulk operations are shallow unless the operation explicitly says otherwise.

- `deallocate` — marks storage inactive; does not finalize `T`.
- `dispose` — finalizes a live `T`, then marks the slot inactive.
- `clear` — marks the pool empty; does not finalize values.
- `deinit` — releases backing virtual memory; does not walk/finalize live values.

This matches XTB's existing explicit-lifetime philosophy for Arena and Array.

---

# 2. Layering

The intended dependency stack is:

```text
internal virtual-memory substrate
        │
        ├── virtual Arena backing
        │
        └── VirtualArray storage engine
                    │
                    ├── public VirtualArray!T
                    │
                    ├── Pool!T
                    │
                    └── GenerationalPool!T
```

The pools should not depend on `Arena`.

Once a fixed maximum capacity is known, direct indexed virtual storage is a better representation than an Arena allocating individual pool slots.

---

# 3. Virtual-memory region primitive

The current internal virtual-memory reservation remains the owner of an address-space mapping.

Conceptually:

```d
package(xtb) struct VirtualMemoryReservation
{
    void* base;
    size_t size;

    @disable this(this);

    void deinit();
}
```

The storage-view design uses one additional internal concept: a **non-owning virtual-memory region**. Step 1 implements it as an intentionally copyable borrowed value:

```d
package(xtb) struct VirtualMemoryRegion
{
    void* base();
    size_t bytes() const;
    bool empty() const;

    bool tryRegion(size_t offset, size_t bytes, VirtualMemoryRegion* output);
    bool tryCommit(size_t offset, size_t bytes);
    bool tryDecommit(size_t offset, size_t bytes);
}
```

A reservation exposes the same bounded `tryRegion` construction operation. Region boundaries are page-aligned, failed region creation leaves its output unchanged, and an empty region is represented by `VirtualMemoryRegion.init`.

A region:

- does not release the mapping;
- is copyable because it owns neither mapping lifetime nor commitment bookkeeping;
- is created only from a valid reservation/subrange;
- constrains commit/decommit operations to its own bounds;
- contains the stable mapped address rather than a pointer to the owner object.

The later `VirtualArrayView!T` is deliberately different: it is non-copyable because it owns mutable provision/commit bookkeeping even though it still borrows the mapping itself.

This is important for movable owners. A `Pool` may move, but the VM address does not. Internal views must therefore not contain pointers to fields inside the old `Pool` struct.

Pool subregions must start and end on page boundaries so one view can commit or decommit pages without affecting another view.

---

# 4. `VirtualArray!T`

`VirtualArray!T` should be a first-class, public XTB container rather than merely a Pool implementation detail.

It provides a fixed maximum capacity, stable addresses, and on-demand virtual-memory backing.

## 4.1 Core contract

```d
VirtualArray!T array = VirtualArray!T.create(maxCapacity);
scope(exit) array.deinit();
```

Properties:

- move-only owner;
- zero state is valid;
- fixed `capacity`;
- runtime `length`;
- stable `ptr` for the owner's lifetime;
- growth never reallocates or copies existing elements;
- growing logical length commits pages as necessary;
- shrinking logical length does not automatically decommit pages;
- `trim()` explicitly decommits pages beyond the live logical prefix when possible;
- `clear()` is shallow and retains committed pages;
- `deinit()` releases the mapping and is shallow with respect to `T` values;
- ordinary XTB explicit cleanup APIs should be provided where they make sense, mirroring `Array!T` semantics.

## 4.2 Suggested creation API

```d
static bool tryCreate(
    size_t capacity,
    scope VirtualArray* output,
);

static VirtualArray create(size_t capacity);
```

A later overload may accept commit granularity:

```d
static VirtualArray create(
    size_t capacity,
    size_t commitGranularity,
);
```

The implemented storage core:

- detects `capacity * T.sizeof` overflow;
- computes an address alignment compatible with both `T.alignof` and the native
  VM page size;
- when that alignment exceeds reservation alignment, over-reserves only the
  alignment slack needed to choose an interior typed base while retaining the
  original reservation base for release;
- keeps the typed region page-bounded so all later commit/decommit operations
  stay isolated;
- rounds commit granularity up to native pages and clamps the final commit to
  the page-rounded typed region;
- leaves `output` untouched on failure;
- supports capacity `0` as the inert, valid empty owner even when VM support is
  unavailable.

The raw storage primitive `tryEnsureAccessible(elementCount)` is package-only.
It may commit pages but does not construct `T` and does not advance logical
`length`. This distinction prevents accessible bytes from being mistaken for
live D values.

## 4.3 Logical length and accessible storage

The public array owns normal logical element state:

```text
capacity          maximum number of elements
length            logical array length
accessible prefix VM pages currently committed/read-write
```

The accessible prefix may be larger than `length` because commitment is page/granularity rounded.

`slice()` exposes only `[0 .. length)`.

It must never expose `[0 .. capacity)` as a normal slice because the uncommitted tail may be inaccessible.

## 4.4 Growth

Growth is transactional at the logical level:

```d
if (!array.tryResize(newLength))
{
    // logical length and existing values unchanged
}
```

Committing extra pages before a later failure is acceptable as an internal optimization: extra committed capacity does not change the logical contents of the array.

For types that support default initialization, growing `resize` constructs the newly added logical elements according to the same lifetime conventions as `Array!T`.

The completed public container layer provides:

```d
bool tryResize(size_t requested);
void resize(size_t requested);

bool tryAppend(scope T* value);
void append(T value);

// Copyable T only.
bool tryAppend(scope const(T)[] values);
void append(scope const(T)[] values);

ref T back();
T pop();
void clear();
void trim();
```

All successful growth paths preserve `ptr`. Pointer-based move append performs VM provisioning before consuming the source, so failure is transactional at the logical and ownership levels.

Operations such as `append`, `pop`, `back`, `clear`, indexing, and slicing mirror `Array!T` where their semantics transfer cleanly.

`appendAssumeCapacity` is deliberately omitted: fixed reserved capacity does not imply that the target pages are committed, so append can still fail at the VM commitment boundary. `tryAppend` remains the explicit fallible primitive.

The fixed-capacity nature means:

```d
array.tryAppend(&value)
```

fails when `length == capacity` rather than reallocating.

## 4.5 Shrinking and trimming

Logical shrink:

```d
array.resize(smallerLength);
```

must not issue an OS operation merely because the array shrank.

This prevents grow/shrink workloads from repeatedly committing and decommitting pages.

Physical reclamation is explicit:

```d
array.trim();
```

`trim()` decommits only whole pages that do not contain any logical element storage.

## 4.6 Lifetime

`VirtualArray!T` follows XTB's existing shallow container conventions.

`clear()` and `deinit()` do not recursively finalize logical elements.

Like `Array!T`, `VirtualArray!T` owns backing storage but is shallow with respect to element cleanup. Growing operations establish real `T` lifetimes through default construction, move construction, or copy construction, but shrinking, `clear()`, `trim()`, and `deinit()` never finalize discarded elements. Cleanup-bearing values must therefore be finalized explicitly by the caller before shallow discard; an owning virtual-array variant should be introduced separately if that semantic is needed.

## 4.7 Stable addresses

This must be a tested contract:

```d
T* original = &array[10];
array.resize(100_000);
assert(original is &array[10]);
```

No successful operation short of `deinit()` may relocate the reservation.

---

# 5. Internal `VirtualArrayView!T`

The Pool needs several arrays inside **one** reservation. Those arrays cannot each own/release their own mapping.

An internal `VirtualArrayView!T` provides this capability.

The name refers to a virtual-storage view, not a D range.

## 5.1 Ownership

A view is non-owning:

```text
VirtualMemoryReservation owns mapping
        │
        ├── VirtualArrayView!T
        ├── VirtualArrayView!uint
        └── VirtualArrayView!uint
```

A view never calls `munmap`/release.

The parent Pool releases the one reservation.

## 5.2 Representation

Conceptually:

```d
package(xtb) struct VirtualArrayView(T)
{
    VirtualMemoryRegion region_;
    T* data_;
    size_t capacity_;
    size_t provisionedLength_;
    size_t committedBytes_;
    size_t commitGranularity_;

    @disable this(this);
}
```

The view is non-copyable because two mutable copies could disagree about commitment state.

It has a local `deinit()` that resets only the borrow/bookkeeping and never releases or decommits the parent mapping. This gives the bookkeeping a single explicit lifetime and lets XTB's move machinery reconstruct moved-from views to the inert state.

Moving it is safe because it stores stable mapping addresses, not a pointer to the reservation owner. Moving the reservation owner itself also leaves existing views valid until that owner is actually deinitialized.

## 5.3 Raw storage semantics

Unlike public `VirtualArray!T`, this internal view does **not** own logical `T` lifetimes.

Its central operation is closer to:

```d
bool tryEnsureAccessible(size_t elementCount);
```

rather than public array `resize()`.

`tryEnsureAccessible`:

- checks `elementCount <= capacity`;
- commits enough pages for the requested prefix;
- advances `provisionedLength_` only to the requested element high-water, even when page rounding makes additional trailing element storage physically accessible;
- does not default-construct, move, copy, initialize, or finalize `T`;
- leaves existing bytes untouched;
- is monotonic in its provisioned high-water;
- changes bookkeeping only after successful commitment.

`trim()` may decommit whole pages beyond the provisioned prefix. It does not reduce `provisionedLength_`, because that high-water records which slot representations the owning Pool has deliberately made part of its storage model.

The owning `VirtualArray!T` and internal view share the same private prefix-commit and prefix-trim helpers so their page/granularity behavior cannot drift.

This raw distinction is important for Pool value storage, where inactive `T` bytes are intentionally retained without claiming every accessible slot is a live D object.

## 5.4 Why this is not a normal slice

A normal `T[]` says every element in the slice is accessible storage and generally represents ordinary typed elements.

`VirtualArrayView!T` additionally owns commitment state and fixed maximum virtual capacity. It is an internal storage-management object, not merely pointer + length.

---

# 6. Pool reservation layout

A Pool owns one reservation containing three page-separated regions.

For plain `Pool!T`:

```text
┌──────────────────────────────────────────┐
│ values                                   │
│ T[capacity + 1]                          │
│ index 0 unused                           │
├──────────── page-aligned boundary ───────┤
│ occupancy bitmap                         │
│ size_t[ceil((capacity + 1) / wordBits)]  │
├──────────── page-aligned boundary ───────┤
│ free-index stack                         │
│ uint[capacity]                           │
└──────────────────────────────────────────┘
```

For `GenerationalPool!T`:

```text
┌──────────────────────────────────────────┐
│ values                                   │
│ T[capacity + 1]                          │
│ index 0 unused                           │
├──────────── page-aligned boundary ───────┤
│ packed state                             │
│ uint[capacity + 1]                       │
├──────────── page-aligned boundary ───────┤
│ free-index stack                         │
│ uint[capacity]                           │
└──────────────────────────────────────────┘
```

The few pages of alignment padding cost virtual address space, not committed physical memory, and greatly simplify independent region commitment.

All size/offset calculations must use checked overflow helpers before reserving anything.

---

# 7. `Pool!T`

**Implementation status: Step 5 complete.**

`Pool!T` is a fixed-capacity, stable-index, stable-address typed pool with no generational handles.

The implementation additionally reuses `VirtualArray`'s package-internal typed-region geometry helper for page rounding, overflow checks, and over-aligned base selection. Pool therefore does not maintain a second copy of the virtual-array alignment arithmetic. The three regions still live in one reservation and each begins at an address compatible with both native page boundaries and its element alignment.

## 7.1 Representation

Conceptually:

```d
struct Pool(T)
{
    VirtualMemoryReservation reservation_;

    VirtualArrayView!T values_;
    VirtualArrayView!size_t occupiedWords_;
    VirtualArrayView!uint freeIndices_;

    uint capacity_;
    size_t nextIndex_;
    size_t freeCount_;
    size_t liveCount_;

    version (XTB_Checked)
        size_t mutationGeneration_;
}
```

`nextIndex_` starts at `1`. Creation reserves the complete address-space layout but commits **zero** value, occupancy, or free-index pages.

Index `0` is never occupied and its occupancy bit remains clear.

`capacity_` is the number of usable indices, not the number of reserved `T` entries. The value region therefore reserves `capacity + 1` entries.

## 7.2 State

Plain Pool needs only one occupancy bit per index.

```text
0 = inactive
1 = occupied
```

Machine-word storage is preferred:

```d
size_t[] occupiedWords;
```

rather than one byte per slot.

Benefits:

- ~1 bit of persistent state per slot;
- 8x less state traffic than `ubyte` occupancy;
- live iteration can skip an entire machine word of dead slots at once;
- O(1) occupancy lookup.

## 7.3 Free-index stack

Freed indices are stored in a compact LIFO stack:

```text
freeIndices[0 .. freeCount)
```

The stack contains indices only, never pointers.

Recycling is therefore cache-friendly and independent of `T` representation.

## 7.4 Provisioning invariant

The critical invariant is:

> Before index `i` is ever returned to the caller, enough value/state/free-index storage has already been committed to support both its active lifetime and a future infallible deallocation.

For a new sequential index `i`, the Pool ensures:

```text
values             accessible through index i
occupied bitmap    accessible through bit i
freeIndices        accessible for at least i stack entries
```

Only after all three requirements succeed may the pool publish index `i` as active and advance the sequential frontier.

If commitment fails, Pool logical state remains unchanged. Any pages committed before the failure may remain committed and be reused by a retry.

This means `deallocate()` never calls `tryEnsureAccessible()`. The implementation tests this invariant by recording all three view commit counters before deallocation and recycled allocation and requiring them to remain unchanged, including across a free-index commit-boundary provisioning test.

## 7.5 Allocation

Allocation first reuses a free index:

```text
if freeCount != 0
    index = freeIndices[--freeCount]
else
    index = nextIndex
    provision(index)
    ++nextIndex
```

Then:

```text
set occupied bit
++liveCount
return &values[index]
```

Recycled allocation performs no VM operation.

## 7.6 Suggested API

```d
static bool tryCreate(uint capacity, scope Pool* output);
static Pool create(uint capacity);

T* tryAllocate();
T* allocate();

T* tryAllocateInit();
T* allocateInit();

T* tryConstruct(Args...)(auto ref Args args);
T* construct(Args...)(auto ref Args args);

void deallocate(T* value);

static if (canFinalizeWithoutContext!T)
    void dispose(T* value);

T* get(uint index);
const(T)* get(uint index) const;

uint indexOf(scope const T* value) const;
bool contains(uint index) const;

void clear();
void deinit();

uint capacity() const;
size_t liveCount() const;
bool empty() const;
```

The exact nullable annotations/attributes should follow existing XTB conventions.

`indexOf(value)` returns the index only when `value` denotes the currently occupied item at that slot; otherwise it returns `0`. Internal pointer-to-slot recovery used by checked deallocation may still compute the physical slot index before testing occupancy.

Raw `allocate` is a low-level operation: it activates a slot without constructing `T` and should therefore be `@system`. Until the caller initializes that storage, semantic APIs such as `items()`, `occupiedSlots()`, and `value()` must not be used on that slot. `allocateInit` and `construct` are the preferred APIs when a live `T` is wanted.

## 7.7 `deallocate`

Given `T* value`, the index is recovered with pointer arithmetic against the contiguous value region.

Checked builds verify:

- pointer is non-null;
- pointer lies in the provisioned values prefix;
- pointer is exactly aligned to a `T` element boundary;
- index is not `0`;
- occupancy bit is currently set;
- pointer belongs to this Pool.

Then:

```text
clear occupied bit
freeIndices[freeCount++] = index
--liveCount
```

No write is performed to `*value`.

This preserves the inactive representation byte-for-byte for storage-only deallocation.

## 7.8 `dispose`

`dispose(value)` explicitly finalizes the live value and then recycles the slot.

The representation after disposal is whatever the finalizer/deinit operation leaves behind; the Pool itself does not overwrite it.

`dispose` only exists when XTB can finalize `T` without external cleanup context.

## 7.9 `clear`

`clear()` is shallow.

For plain Pool it can be efficient:

```text
zero occupied bitmap over provisioned state words
freeCount = 0
liveCount = 0
nextIndex = 1
```

It does not touch `values`.

Previously provisioned value pages remain accessible, so old inactive representations remain available to `slots()`.

The virtual-storage high-water/accessibility prefix is not reset merely because the logical Pool was cleared.

This also means subsequent sequential allocations can reuse already committed pages without OS work.

## 7.10 No automatic trim

Pool should not automatically decommit inactive value pages.

Decommitting them would discard the preserved inactive representation, violating a core Pool contract.

An explicit future operation that intentionally discards inactive representations could be considered separately, but is not part of the initial API.

---

# 8. `GenerationalPool!T`

`GenerationalPool!T` adds stale-handle detection while retaining the same stable values and free-index architecture.

## 8.1 Handle

```d
struct Handle
{
    uint index;
    uint generation;
}
```

Rules:

- `index == 0` means invalid/null handle;
- `Handle.init` is invalid;
- generation `0` is valid;
- a handle is meaningful only with the `GenerationalPool` instance that created it;
- the handle identifies a specific lifetime/incarnation of one stable pool slot.

A handle does not provide global identity across different Pool instances.

## 8.2 Packed state

Each usable index has one `uint` state word.

```text
bit 31      occupied/active
bits 0..30  generation
```

Conceptually:

```d
enum activeBit = uint(1) << 31;
enum generationMask = activeBit - 1;
```

Helpers encapsulate the encoding:

```d
bool stateActive(uint state);
uint stateGeneration(uint state);
uint activateState(uint state);
uint deactivateAndAdvance(uint state);
```

Pool logic should not scatter masks throughout the implementation.

The bit operations are negligible compared with memory access, while packed state halves metadata traffic compared with two `uint` fields per slot.

## 8.3 Generation evolution

A new never-used slot starts as:

```text
inactive, generation 0
```

Activation preserves its current generation and sets the active bit.

Deactivation:

1. clears the active bit;
2. increments generation modulo `2^31`;
3. stores the new inactive generation.

Generation zero is allowed after wrap.

The implementation must never increment the packed state directly in a way that can carry into the active bit. Generation arithmetic is always masked explicitly.

After `2^31` retirements of the **same index**, generation wrap can theoretically make an ancient stale handle compare equal again. This is a documented limitation of a 31-bit generation counter.

## 8.4 Handle validation

Validation is semantic and remains present in release builds:

```text
handle.index != 0
handle.index <= provisioned range
state is active
generation(state) == handle.generation
```

`get(handle)` returns `null` when any condition fails.

Generational safety must not depend on `XTB_Checked`.

## 8.5 Primary API

The generational pool should be handle-oriented.

Suggested shape:

```d
static bool tryCreate(uint capacity, scope GenerationalPool* output);
static GenerationalPool create(uint capacity);

bool tryAllocate(scope Handle* output);
Handle allocate();

bool tryAllocateInit(scope Handle* output);
Handle allocateInit();

bool tryConstruct(Args...)(scope Handle* output, auto ref Args args);
Handle construct(Args...)(auto ref Args args);

T* get(Handle handle);
const(T)* get(Handle handle) const;
bool contains(Handle handle) const;

bool tryDeallocate(Handle handle);
void deallocate(Handle handle);

static if (canFinalizeWithoutContext!T)
{
    bool tryDispose(Handle handle);
    void dispose(Handle handle);
}

void clear();
void deinit();
```

`tryDeallocate` is useful when stale handles are expected control flow.

`deallocate` must still validate in release builds and should fail loudly through XTB's always-active panic path if the handle is invalid/stale. It must not become unsafe merely because checked diagnostics are disabled.

The same rule applies to `dispose`.

## 8.6 Allocation

The same free-index/provisioning strategy as plain Pool applies.

For selected index `i`:

```text
state = states[i]
assert inactive
state = activateState(state)
return Handle(i, generation(state))
```

The caller obtains the element with:

```d
T* value = pool.get(handle);
```

The extra lookup is O(1), inlinable, and is the point at which generation safety is enforced.

As with plain Pool, raw `allocate` is `@system`: it creates an active slot lifetime without constructing `T`. `allocateInit` and `construct` are the normal typed-object operations.

## 8.7 Deallocation

For a valid handle:

```text
states[index] = deactivateAndAdvance(states[index])
freeIndices[freeCount++] = index
--liveCount
```

`values[index]` is not modified.

The old handle becomes invalid immediately.

## 8.8 `clear`

`clear()` must invalidate every currently live handle.

Therefore, unlike plain Pool, it must inspect the provisioned state entries:

```text
for each provisioned index:
    if active:
        state = deactivateAndAdvance(state)

freeCount = 0
liveCount = 0
nextIndex = 1
```

There is no need to populate the free-index stack. Resetting the sequential frontier to `1` causes future allocations to walk the already provisioned indices again, reusing their preserved generation values.

The value region remains untouched.

---

# 9. Iteration model

Both pools expose three distinct range APIs:

```d
pool.items()
pool.occupiedSlots()
pool.slots()
```

These are range-style external iterators, not `opApply`.

Reasons:

- iteration state is explicit and first-class;
- no required delegate invocation per element;
- methods are statically dispatched and highly inlinable;
- ranges can be stored, paused, copied where appropriate, and passed to algorithms;
- bitmap traversal state maps naturally to a small range struct.

No heap allocation, GC, runtime polymorphism, or virtual dispatch is required.

## 9.1 `items()`

The common hot path.

```d
foreach (ref item; pool.items())
    item.update();
```

It yields only live `T` values.

The range's `front` is `ref T`.

No slot proxy is introduced when the caller only needs values.

### Plain Pool traversal

`items()` scans occupancy words and skips zero words.

For a nonzero machine word:

```text
bits = occupiedWord
while bits != 0:
    bit = trailingZeroCount(bits)
    index = wordBase + bit
    yield values[index]
    bits &= bits - 1
```

This makes sparse iteration approximately proportional to:

```text
number of occupancy words + number of live elements
```

rather than the number of provisioned slots.

### Generational Pool traversal

The states are `uint` rather than a bitset. Initial implementation may scan state entries sequentially and test `activeBit`.

A later summary bitmap can be added only if profiling shows it is worthwhile. Do not duplicate occupancy metadata preemptively.

## 9.2 `occupiedSlots()`

This range yields only live slots while exposing identity metadata.

Plain Pool proxy:

```d
struct OccupiedPoolSlot(T)
{
    uint index() const;
    ref T value() return;
}
```

Usage:

```d
foreach (slot; pool.occupiedSlots())
    process(slot.index, slot.value);
```

Generational proxy:

```d
struct OccupiedGenerationalPoolSlot(T)
{
    uint index() const;
    uint generation() const;
    Handle handle() const;
    ref T value() return;
}
```

Usage:

```d
foreach (slot; pool.occupiedSlots())
    process(slot.handle, slot.value);
```

`items()` and `occupiedSlots()` should share the same underlying live-slot cursor logic where practical. They differ only in what `front` exposes.

## 9.3 `slots()`

`slots()` walks every **provisioned** slot, live or inactive.

It does not walk the entire maximum capacity because unprovisioned value pages may still be inaccessible (`PROT_NONE`).

Plain slot proxy:

```d
struct PoolSlot(T)
{
    uint index() const;
    bool occupied() const;

    ref T value() return;       // requires occupied
    ref T storage() @system return;
}
```

Generational slot proxy:

```d
struct GenerationalPoolSlot(T)
{
    uint index() const;
    bool occupied() const;
    uint generation() const;

    Handle handle() const;      // requires occupied
    ref T value() return;       // requires occupied
    ref T storage() @system return;
}
```

### `value` vs `storage`

`value` denotes a semantically live `T` and requires the slot to be occupied.

`storage` exposes the preserved `T`-sized representation even when inactive.

Because inactive storage may not contain a currently live D object, `storage` should be explicitly `@system`. It still returns `ref T`, preserving the direct-reference ergonomics discussed for slot inspection, while making the lifetime risk visible in the type system.

## 9.4 Provisioned range

The upper bound for `slots()` comes from the value view's **provisioned element high-water** (`provisionedLength_`), not from `nextIndex_` and not from the number of `T` objects that merely fit inside page-rounded committed bytes.

This distinction matters after `clear()`:

```text
nextIndex        reset to 1
provisioned high-water remains unchanged
```

Therefore old inactive representations remain inspectable through `slots()`.

## 9.5 Range invalidation

Structural Pool mutations invalidate outstanding ranges:

- allocation;
- deallocation/disposal;
- clear;
- deinit;
- any future operation changing occupancy or provisioned length.

Mutating a live `T` through a yielded `ref` does not invalidate the range.

In `XTB_Checked`, Pool may maintain a checked-only mutation generation captured by ranges to diagnose use after structural mutation. This state must compile out of unchecked/release-fast builds.

---

# 10. Cache locality

The design intentionally uses a structure-of-arrays layout:

```text
values:       T T T T T T T T ...
state:        compact metadata ...
freeIndices:  uint uint uint ...
```

This is preferable to:

```text
[state T][state T][state T]...
```

for workloads that iterate values, because value cache lines contain only `T` representations.

Plain Pool state is especially compact at one bit per slot.

The free-index stack is contiguous and pointer-free.

No pool element contains linked-list pointers.

---

# 11. Complexity

## `Pool!T`

| Operation | Complexity | Notes |
|---|---:|---|
| recycled allocate | O(1) | no VM operation |
| virgin allocate | amortized O(1) | may commit pages |
| deallocate | O(1) | infallible, no commit |
| `get(index)` | O(1) | occupancy bit test |
| `indexOf(ptr)` | O(1) | pointer arithmetic |
| `clear()` | O(state words) | values untouched |
| `items()` | O(state words + live) | skips empty words |
| `slots()` | O(provisioned slots) | includes inactive |

## `GenerationalPool!T`

| Operation | Complexity | Notes |
|---|---:|---|
| recycled allocate | O(1) | no VM operation |
| virgin allocate | amortized O(1) | may commit pages |
| `get(handle)` | O(1) | active + generation check |
| deallocate | O(1) | generation advances |
| `clear()` | O(provisioned slots) | must invalidate live handles |
| `items()` | O(provisioned slots) initially | state scan |
| `slots()` | O(provisioned slots) | includes inactive |

---

# 12. Failure semantics

## Creation failures

`tryCreate` fails without modifying the output owner when:

- size arithmetic overflows;
- alignment/layout computation overflows;
- reservation fails;
- platform cannot provide required VM behavior.

## Allocation failures

A Pool allocation can fail only when:

- fixed capacity is exhausted; or
- a virgin index requires VM commitment and commitment fails.

Recycled allocations should not require commitment.

## Deallocation failures

Plain Pool `deallocate(T*)` has no expected failure path. Invalid pointer/double-free are caller contract violations and checked-build diagnostics should catch them.

Generational Pool deliberately treats stale handles as semantic data:

- `tryDeallocate(handle)` returns `false`;
- `deallocate(handle)` validates even in release and panics if invalid/stale.

## Partial VM commitment

If provisioning a virgin slot commits one region and then a later region commit fails, it is acceptable to retain those newly committed pages.

The Pool's externally observable state must remain unchanged:

- no index published;
- occupancy inactive;
- frontier not advanced;
- counts unchanged.

---

# 13. Thread safety

Initial `VirtualArray`, `Pool`, and `GenerationalPool` are **not thread-safe**.

No internal atomics or locks should be added.

Users requiring concurrent access must provide external synchronization.

A future concurrent pool would be a different abstraction because free-index and occupancy/generation transitions would require a different design.

---

# 14. Module organization

Recommended layout:

```text
source/xtb/core/
    virtual_array.d
    pool.d
    generational_pool.d

source/xtb/core/allocators/internal/
    virtual_memory.d
    virtual_memory_linux.d
    virtual_memory_unsupported.d
```

If the existing VM substrate is moved to a more general `xtb.core.internal` location for reuse by a future public `xtb.os.virtual_memory`, `VirtualArray` should depend on that internal facade rather than on OS-specific modules directly.

The pools themselves should know nothing about `mmap`, `mprotect`, page flags, or platform-specific APIs.

---

# 15. Testing requirements

`VirtualArray!T` is infrastructure, not a Pool-only helper. It should receive its own exhaustive unit/integration tests before Pool depends on it.

## 15.1 `VirtualArray!T`

Required coverage:

### Ownership and zero state

- `.init` is valid;
- `deinit()` on zero state is safe;
- repeated `deinit()` is safe if that matches XTB owner conventions;
- move construction transfers ownership exactly once;
- move assignment correctly releases/replaces prior storage according to XTB lifetime helpers.

### Capacity arithmetic

- capacity `0`;
- capacity `1`;
- normal capacities;
- multiplication overflow;
- reservation-layout overflow;
- over-aligned `T`;
- page-boundary and commit-granularity boundary sizes.

### Stable addressing

- pointers to existing elements remain identical after growth;
- appends/resizes never relocate;
- shrinking and regrowing preserve the base address.

### Commitment behavior

- creation reserves but does not expose the full capacity as accessible logical storage;
- growth commits enough storage;
- crossing a page/commit-granularity boundary works;
- shrinking retains commitment;
- `trim()` decommits only safe whole-page suffixes;
- regrowth after trim recommits correctly.

### Logical element behavior

- default initialization on supported `resize` growth;
- append/pop/index/slice behavior;
- capacity exhaustion is reported without mutation;
- `clear()` is shallow;
- `deinit()` is shallow;
- explicit cleanup operations match `Array!T` conventions for owning/nontrivial `T`.

### Attributes/build modes

- BetterC;
- `nothrow`;
- `@nogc`;
- safe API remains callable from `@safe` where intended;
- unsafe raw-storage boundaries are narrowly `@trusted`/`@system`;
- release-fast compilation;
- ASan where applicable.

## 15.2 Internal `VirtualArrayView!T`

Required coverage:

- subregion bounds;
- page-aligned region separation;
- non-copyability;
- movement without owner-pointer invalidation;
- independent commitment of adjacent views;
- ensure-accessible overflow/capacity failure;
- provisioned element high-water remains distinct from page-rounded committed byte coverage;
- no element initialization performed by raw storage growth;
- no release of the parent reservation.

## 15.3 `Pool!T`

Required coverage:

- capacity `0`, `1`, multiple bitmap words;
- index `0` always invalid/inactive;
- sequential virgin indices begin at `1`;
- capacity exhaustion;
- LIFO recycled-index reuse;
- tiny `T`;
- large `T`;
- over-aligned `T`;
- `T` containing pointer-looking values does not affect Pool metadata;
- deallocation preserves every byte of inactive `T` representation;
- recycled allocation does not commit or allocate;
- deallocation does not commit or allocate;
- free-index provisioning invariant around page boundaries;
- double-free diagnostics in `XTB_Checked`;
- foreign/misaligned pointer diagnostics;
- `get`, `contains`, `indexOf`;
- shallow `clear` and `deinit`;
- `dispose` finalization behavior;
- moves;
- full/dense pool;
- sparse pool;
- clear followed by reuse of already committed/provisioned slots.

### Range tests

For `items`, `occupiedSlots`, and `slots`:

- empty Pool;
- one element;
- first usable index (`1`);
- bitmap word boundaries;
- sparse occupancy;
- dense occupancy;
- freed holes;
- reuse;
- after clear;
- correct `ref T` mutation;
- correct indices;
- inactive `storage` representation access;
- structural mutation invalidation diagnostics when checked-generation validation is enabled.

## 15.4 `GenerationalPool!T`

All applicable Pool tests plus:

- `Handle.init` invalid;
- index zero never issued;
- first live generation may be `0`;
- stale handle invalid immediately after deallocation;
- reused index receives incremented generation;
- `get` rejects stale handle in release builds;
- `tryDeallocate` rejects stale handle without affecting current occupant;
- `deallocate` fails loudly on stale handle;
- active bit is never contaminated by generation increment;
- generation wrapping from `generationMask` to `0` via test-only/internal state setup;
- clear invalidates every previously live handle;
- inactive generations survive clear/reuse correctly;
- occupied slot range reports matching handle/generation;
- plain `items()` still yields only `ref T` with no proxy requirement.

## 15.5 Repository validation

For each implementation stage:

- exact core example build/run;
- core unit tests;
- Pool-specific integration tests;
- full debug suite;
- release-safe library build;
- release-fast library build;
- release-fast core unit compilation;
- ASan core + Pool integration;
- `dfmt`;
- `dscanner`;
- `git diff --check`;
- independent patch/mbox apply reconstruction when packaging commits.

---

# 16. Benchmarks

Correctness comes first, but the representation should be benchmarked after implementation.

Useful benchmarks:

- virgin allocation throughput;
- recycled allocation/deallocation throughput;
- Pool allocation versus old Arena-backed Pool;
- dense `items()` iteration;
- 50% occupancy iteration;
- sparse occupancy iteration;
- `items()` versus direct hand-written bitmap loop to verify range abstraction disappears under optimization;
- `occupiedSlots()` versus `items()`;
- `GenerationalPool.get(handle)` cost;
- state scan cost for generational iteration;
- page-boundary growth/commit behavior;
- large-capacity/small-live-set physical-memory behavior.

Do not add summary bitmaps, SIMD traversal, or other secondary indexes until profiling demonstrates a real need.

---

# 17. Implementation plan

The authoritative staged plan lives in `design_spec/pools_implementation_plan.md`. The implementation is intentionally gated so Pool never depends on a partially proven virtual-storage container.

Current progress:

1. **Complete** — bounded non-owning `VirtualMemoryRegion`.
2. **Complete** — `VirtualArray!T` ownership/storage core.
3. **Complete** — complete and harden `VirtualArray!T`.
4. **Complete** — internal `VirtualArrayView!T`.
5. **Complete** — fixed-capacity `Pool!T`.
6. Pending — Pool ranges.
7. Pending — `GenerationalPool!T`.
8. Pending — generational ranges, documentation, benchmarks, and final audit.

---

# 18. Explicit non-goals

The first implementation should **not** include:

- thread-safe/concurrent pools;
- moving/compacting pools;
- global handles that identify an object across Pool instances;
- dynamically unbounded pool capacity;
- per-slot linked-list pointers;
- intrusive hooks inside `T`;
- automatic element finalization during `clear`/`deinit`;
- automatic decommit of inactive Pool values;
- a second occupancy bitmap for GenerationalPool merely to accelerate iteration;
- public arbitrary construction of virtual-array storage views;
- platform-specific VM calls in Pool code.

These can be reconsidered only with concrete use cases or benchmark evidence.

---

# 19. Final intended model

The plain Pool should be mentally simple:

```text
Pool!T

fixed max capacity
stable indices 1..N
stable T addresses

values[index]       = preserved representation
occupied[index]     = one lifetime bit
freeIndices[]       = reusable indices
```

The generational Pool adds exactly the identity information it needs:

```text
GenerationalPool!T

values[index]       = preserved representation
state[index]        = active bit + generation
freeIndices[]       = reusable indices
Handle              = { index, generation }
```

Both are backed by one fixed virtual reservation whose typed regions commit pages automatically through internal `VirtualArrayView`s.

Iteration remains explicit and purpose-specific:

```d
foreach (ref value; pool.items())
    ...;

foreach (slot; pool.occupiedSlots())
    ... slot.index ... slot.value ...;

foreach (slot; pool.slots())
    ... slot.occupied ... slot.storage ...;
```

The design keeps the common path small, the memory representation predictable, item storage clean, and the VM details below the container layer.
