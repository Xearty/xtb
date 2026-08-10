# Arena Regions and Arena-Native Arrays

## Status

Feature proposal. This is the canonical design for adding allocation-only arena
regions, native arena reallocation, and arena-native arrays to xtb.

The feature is not yet implemented. API sketches are normative where they state
ownership, lifetime, destruction, or build-mode behavior. Exact overload sets
may be adjusted during implementation to match the existing `Array!T` surface,
provided those rules remain unchanged.

This proposal supersedes the earlier arena-container, region-rationale,
zero-cost, usage-migration, and example documents.

---

## 1. Summary

xtb should distinguish three jobs that are currently all represented by an
`Arena*` or an `Allocator*`:

- `Arena*` owns chunks and may clear, rewind, tune, or deinitialize them;
- `ArenaRegion*` grants allocation from one current arena lifetime, but no
  control over that lifetime;
- `ArenaArray!T` is a growable array whose storage and discarded element
  lifetimes belong to an `ArenaRegion`.

The first feature increment adds:

1. `ArenaRegion`, acquired as the `.region` property of an `Arena` or
   `ScratchScope`;
2. native arena resize/reallocation primitives;
3. `ArenaArrayUnmanaged!T`, a compact explicit-region array;
4. `ArenaArray!T`, a region-bound convenience array;
5. one private array-storage implementation shared by the public ordinary and
   arena array families;
6. migration of the parser's private `ArenaList!T` to `ArenaArray!T`.

The central lifetime rule is deliberately simple:

> Arena containers accept every `T`, never call element destructors, and leave
> the correctness of abandoning `T` to the caller.

That rule applies at scope exit, region rewind, `clear`, removal, shrinking,
replacement, relocation, and arena destruction. There is no destructor trait,
annotation, generated cleanup walk, cleanup registry, or runtime ownership
mode.

Checked builds diagnose common region mistakes. Release-fast gives
`ArenaRegion*` the same pointer representation and successful hot path as a
direct `Arena*`; all region-only diagnostics disappear.

---

## 2. Goals and non-goals

### 2.1 Goals

The feature must:

- make large nested arena graphs discardable in O(1) container work;
- provide a standard growable arena array instead of one-off local containers;
- make allocation-only APIs visibly less powerful than `Arena*` APIs;
- tie scratch-facing handles to the lexical `ScratchScope` through DIP1000
  where supported by D;
- diagnose null, inactive, stale, wrong-depth, and wrong-thread region use in
  checked builds while imposing no region cost in release-fast;
- reuse the current region through helper call trees, especially when both TLS
  scratch arenas already have live allocations;
- preserve ordinary `Array!T` source behavior, destruction, allocation failure
  behavior, and performance;
- support recursive representations such as a node containing
  `ArenaArray!Node` without recursive template-instantiation problems;
- compile under BetterC without the GC, exceptions, classes, `TypeInfo`, or
  runtime reflection.

### 2.2 Non-goals for the first increment

The first increment does not add:

- `ArenaStringBuf`, `ArenaHashMap`, `ArenaHashSet`, or an arena box;
- `ArenaArray.shrinkToFit`;
- generic deep cloning or promotion to an arbitrary allocator;
- automatic destruction of selected arena values;
- cleanup callback registries;
- runtime per-container ownership policies;
- synchronization for sharing arenas across threads;
- proof that pointers or slices inside an element belong to the same region.

These exclusions keep the first implementation narrow enough to validate its
lifetime and code-generation claims before more containers depend on it.

---

## 3. Ownership model

### 3.1 `Arena` is the owner and control surface

`Arena` continues to own its chunks and backing allocator. Operations that
change the lifetime of existing allocations remain owner operations:

- `clear`;
- `deinit`;
- `push` and `pop`;
- retention and poisoning controls;
- statistics and other arena-level policy.

Code needing any of those operations receives `Arena*`. A grammar object that
owns an arena, a request object that resets its arena between requests, and the
thread context that manages its TLS arenas all remain owner-level code.

An arena must have a stable address after any allocator adapter, region, or
arena-backed value retains a pointer to it. A by-value factory may initialize
an arena before that binding occurs, but an active arena owner must not be moved.

### 3.2 `ArenaRegion` is an allocation-only capability

`ArenaRegion` exposes allocation, construction, and native reallocation. It
does not expose clear, rewind, deinit, retention policy, or checkpoint control.

Public arena-native containers accept only `ArenaRegion*`. There is no
`ArenaArray.create(Arena*)` overload. Owner code obtains the capability through
the `.region` property:

```d
Arena arena = Arena.create(backingAllocator);
ArenaArray!Node nodes = ArenaArray!Node.create(arena.region);

ScratchScope scratch = ScratchScope.acquire(outputAllocator);
ArenaArray!Token tokens = ArenaArray!Token.create(scratch.region);
```

Zero-argument accessors are declared with D's required `()` but used as
properties: `.allocator`, `.arena`, and `.region`.

The usual style does not introduce a local named `region` merely to forward
it once. Helpers that allocate repeatedly receive a parameter named `region`:

```d
ParseStatus parseModule(
    ArenaRegion* region,
    scope const(Token)[] tokens,
    scope ArenaArray!Node* nodes,
);

ParseStatus parseFile(String source, Allocator* outputAllocator)
{
    ScratchScope scratch = ScratchScope.acquire(outputAllocator);
    ArenaArray!Token tokens = lex(scratch.region, source);
    ArenaArray!Node nodes = ArenaArray!Node.create(scratch.region);
    return parseModule(scratch.region, tokens.slice, &nodes);
}
```

### 3.3 `ArenaArrayUnmanaged!T` stores no provider

The unmanaged form contains exactly three words:

```d
private T* data_;
private size_t length_;
private size_t capacity_;
```

Operations that may allocate receive an explicit `ArenaRegion*`. Nonallocating
operations do not. The caller must consistently use the same live region for a
particular active value. The type stores no region, epoch, allocator tag, or
provenance metadata.

This form is useful in low-level layouts where the surrounding object already
provides the region or where one bound pointer per nested array is undesirable.
It is `@system`: the implementation cannot verify that two supplied regions
refer to the same lifetime.

### 3.4 `ArenaArray!T` stores its region

The bound form stores an `ArenaRegion*` plus the same three storage words. It
uses that region for every allocating member call and exposes it as `.region`.
It does not expose a separate allocator binding; generic allocation remains
available as `array.region.allocator` when genuinely needed.

In release-fast, this has the same four-word layout as a direct arena-bound
array containing `Arena*`, data, length, and capacity. Checked builds may append
diagnostic snapshots and therefore have a different ABI.

### 3.5 Ordinary owners keep ordinary RAII

`Array!T`, `StringBuf`, `HashMap`, files, mappings, threads, locks, and other
ordinary owners keep their existing destruction rules. They may use
`region.allocator` for backing storage without becoming arena containers:

```d
ScratchScope scratch = ScratchScope.acquire();

// Element destructors run before scratch rewinds because this owner is
// declared after the scope and is destroyed first.
Array!File files = Array!File.create(scratch.region.allocator);

// No element destructor is ever called.
ArenaArray!AstNode nodes = ArenaArray!AstNode.create(scratch.region);
```

Allocator choice and destruction policy are separate concerns. An ordinary
owner backed by an arena still owns its logical elements. An arena-native
container discards its logical elements even when `T` declares a destructor.

---

## 4. Why `ArenaRegion` is worth having

An `ArenaRegion*` does not make arena allocation memory-safe. It is useful
because it expresses a narrower and shorter-lived relationship than `Arena*`
without charging for that distinction in release-fast.

### 4.1 It removes lifetime-ending authority from helpers

This helper can invalidate every outstanding allocation:

```d
void collectNames(Arena* arena, scope ArenaArray!String* names)
{
    // The signature unnecessarily permits arena.clear(), push(), and pop().
}
```

The region form communicates and enforces the intended authority:

```d
void collectNames(ArenaRegion* region, scope ArenaArray!String* names)
{
    // Can allocate, but cannot clear or rewind the arena.
}
```

This is an API design benefit even when checks are compiled out.

### 4.2 It gives scratch results a lexical lifetime source

The physical TLS `Arena` outlives every individual scratch scope. Returning a
bare `Arena*` therefore exposes the long physical lifetime, not the short
logical one. `ScratchScope.region` is declared `return scope`, so safe callers
cannot normally return a container tied to a local scope:

```d
ArenaArray!int invalid()
{
    ScratchScope scratch = ScratchScope.acquire();
    return ArenaArray!int.create(scratch.region); // must not compile safely
}
```

Minimal DMD and LDC probes for the proposed shape reject this escape. The
production declarations still require checked-in compiler tests.

### 4.3 It distinguishes consecutive uses of the same TLS arena

The same TLS arena address is reused:

```d
{
    ScratchScope first = ScratchScope.acquire();
    // first.region refers to TLS arena A, region period 12.
}
{
    ScratchScope second = ScratchScope.acquire();
    // second.region may refer to the same arena A, now region period 13.
}
```

A bare `Arena*` sees the same address in both blocks. In checked builds the
holder, bound containers, and arena maintain diagnostic epoch/depth/thread
state so a container from period 12 is rejected during period 13. The epoch is
diagnostic state, not allocation state.

### 4.4 It avoids accidental third-arena acquisition

xtb normally installs two TLS scratch arenas. A real operation may have live
temporary data in one and exclude an output allocator backed by the other. A
nested helper that blindly calls `ScratchScope.acquire` then has no valid
arena. Passing the current `ArenaRegion*` lets the entire synchronous call tree
share one lifetime:

```d
void tokenize(ArenaRegion* region, String source, scope ArenaArray!Token* out);
void parse(ArenaRegion* region, scope const(Token)[] input,
    scope ArenaArray!Node* out);

ScratchScope scratch = ScratchScope.acquire(outputAllocator);
ArenaArray!Token tokens = ArenaArray!Token.create(scratch.region);
tokenize(scratch.region, source, &tokens);

ArenaArray!Node nodes = ArenaArray!Node.create(scratch.region);
parse(scratch.region, tokens.slice, &nodes);
```

The design does not make nested scratch checkpoints impossible. Low-level code
may still push/pop deliberately when it truly needs an earlier rewind and can
prove LIFO behavior.

### 4.5 What it does not prevent

`ArenaRegion` does not prove:

- that an element's internal pointers refer to the same region;
- that a borrowed slice has not escaped through `@system` code;
- that an arena owner was not moved after binding;
- that the owner will not call `clear` behind borrowers;
- that a destructor-dependent value is sensible in an arena container;
- that an unsynchronized caller-owned arena is safe for concurrent use;
- that a shallow copy into persistent storage copied pointees as well.

It also cannot safely inspect a region object after that object's own storage
lifetime has ended. Checked diagnostics catch misuse while the diagnostic
holder is still valid; they are not a substitute for the language lifetime
contract.

For an `Arena`-embedded root region, an old raw region pointer aliases the same
embedded object if `.region` is acquired again after `clear`. Bound containers
retain their own checked epoch snapshot and remain diagnosable. A bare escaped
region pointer cannot carry a per-acquisition snapshot, so owner discipline is
still required.

---

## 5. Destruction and element lifetime

### 5.1 Any `T` is permitted

`ArenaArray!T` and `ArenaArrayUnmanaged!T` have no declaration constraint and
no delayed validation based on `hasElaborateDestructor`, `isPOD`, a UDA, or a
library trait. Recursive types instantiate naturally:

```d
struct Node
{
    String name;
    ArenaArray!Node children;
}
```

This avoids conditional struct-template completion cycles and avoids claiming
that structural reflection can prove semantic cleanup requirements.

### 5.2 Arena containers never invoke element destructors

The following operations perform zero element destruction:

- arena-array scope exit;
- `clear`;
- shrinking `resize`;
- `removeAt` and range removal;
- `pop` after moving out the result;
- replacement;
- growth and relocation;
- arena rewind, `Arena.clear`, and `Arena.deinit`.

This remains true when `T` has a destructor. Choosing such a `T` means the
caller explicitly accepts that the destructor will not run for values stored
in the arena container.

The library will test this behavior with destructor-bearing probe types. It is
not undefined or an implementation accident; it is the container's contract.

### 5.3 Three meanings of `clear`

The name follows the owning object's policy:

| Operation | Element destructors | Storage effect |
| --- | --- | --- |
| `Array!T.clear` | Runs them | Retains capacity |
| `ArenaArray!T.clear` | Never runs them | Sets length to zero; retains capacity |
| `Arena.clear` | Never runs them | Invalidates and resets all arena allocations |

An `ArenaArray.clear` followed by appends may establish new element lifetimes
over old logical slots. The prior values are abandoned.

### 5.4 Resources use an ordinary cleanup table

If correctness requires cleanup, keep the owners in an ordinary container:

```d
ScratchScope scratch = ScratchScope.acquire();
ArenaArray!AstNode graph = ArenaArray!AstNode.create(scratch.region);
Array!File openFiles = Array!File.create(scratch.region.allocator);

// Build graph and append acquired files to openFiles.
// Reverse destruction closes files before scratch rewinds.
```

This may still require an O(number of resources) cleanup walk. That is
necessary work. The win is that millions of plain graph nodes do not need to be
walked merely to find a small, explicit resource table.

### 5.5 Early arena clear requires an inner lifetime

An arena cannot be cleared while a scratch checkpoint is active. Checked
`Arena.clear` rejects `scopeDepth != 0`, and popping the `ScratchScope` normally
already performs the desired rewind.

For a persistent arena owner, end all arena-backed ordinary owners before
clearing:

```d
Arena arena = Arena.create(backingAllocator);

{
    ArenaArray!Node nodes = ArenaArray!Node.create(arena.region);
    Array!File files = Array!File.create(arena.region.allocator);
    build(&nodes, &files);
} // files destroys elements; nodes has no destructor

arena.clear();
```

There is no special `endRegion` call. Lexical scope and the owner-level clear
make the ordering visible.

---

## 6. Proposed public API

The declarations below show the intended shape. They omit repetitive
attributes and overloads where those simply mirror `Array!T`. The implemented
API must apply `pure`, `nothrow`, `@nogc`, `@safe`, `@trusted`, `@system`,
`scope`, and `return scope` according to the real contract rather than for
appearance.

### 6.1 `ArenaRegion`

```d
struct ArenaRegion
{
nothrow @nogc:
    @disable this(this);

    Allocator* allocator() return;
    package(xtb) Arena* arena() return;

    void* tryAllocate(size_t size, size_t alignment = (void*).alignof);
    void* allocate(size_t size, size_t alignment = (void*).alignof);

    T* tryAllocate(T)();
    T* allocate(T)();
    T[] tryAllocateArray(T)(size_t length);
    T[] allocateArray(T)(size_t length);

    T* tryAllocateInit(T)();
    T* allocateInit(T)();
    T[] tryAllocateInitArray(T)(size_t length);
    T[] allocateInitArray(T)(size_t length);

    T* tryCreate(T, Args...)(auto ref Args arguments);
    T* create(T, Args...)(auto ref Args arguments);

    bool tryResizeLastAllocation(
        void* pointer,
        size_t oldSize,
        size_t newSize,
    );

    void* tryReallocate(
        size_t newSize,
        void* oldPointer,
        size_t oldSize,
        size_t alignment = (void*).alignof,
    );
}
```

The allocation and construction vocabulary mirrors `Arena` and
`xtb.core.memory`: raw allocation does not establish `T.init`; `allocateInit*`
does; `create` constructs from arguments. None of these operations registers a
destructor.

`.arena` is package-private so implementation code can delegate without
restoring owner-level authority to ordinary users. `.allocator` is public for
ordinary RAII owners and generic allocator-based algorithms whose entire
lifetime remains inside the region.

### 6.2 Arena holder properties

```d
struct Arena
{
    ArenaRegion* region() return;
    Allocator* allocator() return;
}

struct ScratchScope
{
    ArenaRegion* region() return scope;
    Arena* arena() return scope;
    Allocator* allocator() return scope;
}
```

Existing `.arena` and `.allocator` uses remain valid. A call changes to
`.region` only when its callee needs region allocation or creates an
arena-native container.

### 6.3 `ArenaArrayUnmanaged!T`

```d
struct ArenaArrayUnmanaged(T)
{
nothrow @nogc:
    @disable this(this);

    static bool tryWithCapacity(
        return scope ArenaRegion* region,
        size_t capacity,
        scope ArenaArrayUnmanaged* output,
    ) @system;

    static ArenaArrayUnmanaged withCapacity(
        return scope ArenaRegion* region,
        size_t capacity,
    ) @system;

    static ArenaArrayUnmanaged withLength(
        return scope ArenaRegion* region,
        size_t length,
    ) @system;

    static if (__traits(isCopyable, T))
    {
        static ArenaArrayUnmanaged fromSlice(
            return scope ArenaRegion* region,
            scope const(T)[] values,
        ) @system;
    }

    size_t length() const pure @safe;
    size_t capacity() const pure @safe;
    bool empty() const pure @safe;
    T[] slice() return @system;
    const(T)[] slice() const return @system;
    ref T opIndex(size_t index) return @system;
    ref const(T) opIndex(size_t index) const return @system;

    bool tryReserve(ArenaRegion* region, size_t requested) @system;
    void reserve(ArenaRegion* region, size_t requested) @system;
    bool tryResize(ArenaRegion* region, size_t requested) @system;
    void resize(ArenaRegion* region, size_t requested) @system;
    bool tryAppend(ArenaRegion* region, T value) @system;
    void append(ArenaRegion* region, T value) @system;
    void appendAssumeCapacity(T value) @system;
    T pop() @system;
    void clear() @system;
    void removeAt(size_t index) @system;
}
```

Slice append, insertion, range removal, assignment, and iteration should match
the ordinary unmanaged array where their semantics are already settled.
Allocating overloads always put `region` first, matching allocator-explicit
`ArrayUnmanaged` operations.

There is deliberately no destructor, `deinit`, `resetAndRelease`, `release`,
`adopt`, provider accessor, or `shrinkToFit`.

### 6.4 `ArenaArray!T`

```d
struct ArenaArray(T)
{
nothrow @nogc:
    @disable this(this);

    static ArenaArray create(return scope ArenaRegion* region) @trusted;

    static bool tryWithCapacity(
        return scope ArenaRegion* region,
        size_t capacity,
        scope ArenaArray* output,
    ) @trusted;

    static ArenaArray withCapacity(
        return scope ArenaRegion* region,
        size_t capacity,
    ) @trusted;

    static ArenaArray withLength(
        return scope ArenaRegion* region,
        size_t length,
    ) @trusted;

    static if (__traits(isCopyable, T))
    {
        static ArenaArray fromSlice(
            return scope ArenaRegion* region,
            scope const(T)[] values,
        ) @trusted;
    }

    ArenaRegion* region() return;
    size_t length() const pure @safe;
    size_t capacity() const pure @safe;
    bool empty() const pure @safe;
    T[] slice() return @system;
    const(T)[] slice() const return @system;
    ref T opIndex(size_t index) return @system;
    ref const(T) opIndex(size_t index) const return @system;

    bool tryReserve(size_t requested) @trusted;
    void reserve(size_t requested) @trusted;
    bool tryResize(size_t requested) @trusted;
    void resize(size_t requested) @trusted;
    bool tryAppend(T value) @trusted;
    void append(T value) @trusted;
    void appendAssumeCapacity(T value) @trusted;
    T pop() @trusted;
    void clear() @trusted;
    void removeAt(size_t index) @trusted;
}
```

The zero state is valid and inert. Factories bind a region. Fallible factories
require an empty output and leave it empty on failure. Move construction and
move assignment leave the source inert. Replacing an active destination is
allowed because abandoning its previous metadata omits no destruction or
deallocation obligation; its bytes still belong to the arena.

Metadata-only accessors read only the handle. Operations that dereference
storage or allocate validate the live region once at their checked public
boundary, not once per element. `clear` only changes the handle's length and is
valid as metadata abandonment; it does not make stale storage usable again.

### 6.5 Deliberately absent generic `clone`

There is no `ArenaArray.clone(Allocator*)`. Such a name suggests persistent
independence, but copying the top-level elements does not copy pointees or
slice bytes:

```d
struct ParsedNode
{
    String name;             // May point into scratch.
    ArenaArray!ParsedNode children;
}
```

For flat scalar data, callers may explicitly make a shallow value copy:

```d
Array!uint persistent = Array!uint.fromSlice(
    outputAllocator,
    temporary.slice,
);
```

Domain values use a transactional conversion that understands their ownership:

```d
static bool tryFromParsed(
    Allocator* outputAllocator,
    scope const(ParsedNode)* source,
    scope OwnedNode* output,
);
```

The conversion allocates every persistent byte from `outputAllocator`, cleans
up partial ordinary ownership on failure, and publishes `output` only after
success.

---

## 7. Shared array implementation without a public policy type

The public types remain handwritten, explicit structs:

- `ArrayUnmanaged!T`;
- `Array!T`;
- `ArenaArrayUnmanaged!T`;
- `ArenaArray!T`.

There is no public `ArrayImpl!(T, Policy)`, reflection-generated forwarding
surface, or mixin that synthesizes the managed APIs. This preserves readable
documentation, predictable diagnostics, LSP discoverability, and independent
ownership contracts.

The implementations should share private storage algorithms in
`xtb.core.array`. A conceptual split is:

```d
private struct RawArrayStorage(T)
{
    T* data;
    size_t length;
    size_t capacity;
}

private bool tryReserveStorage(T, Provider)(
    scope RawArrayStorage!T* storage,
    Provider provider,
    size_t requested,
);
```

`Provider` is compile-time-specialized private machinery. The ordinary path
deallocates old storage and destroys elements according to the current
`Array!T` contract. The arena path never deallocates or destroys and delegates
growth to `ArenaRegion`. Branches that select those policies must disappear at
compile time.

The refactor is accepted only if the ordinary public declarations and behavior
remain explicit and its focused tests pass before and after the internal
change. This feature is not permission to redesign `Array!T`.

---

## 8. Native arena reallocation and array growth

### 8.1 Why the primitive belongs to `Arena`

The arena knows its current chunk and cursor. An array module should not inspect
arena chunks, and an allocator adapter cannot safely infer typed movement. The
arena therefore provides representation-neutral byte primitives; array code
chooses whether byte copying or typed movement is valid.

### 8.2 In-place resize of the latest allocation

`tryResizeLastAllocation(pointer, oldSize, newSize)` succeeds only when:

- `pointer` and the size pair satisfy the documented null/zero contract;
- `pointer` belongs to the current chunk;
- `pointer + oldSize` is exactly the current allocation cursor;
- the new end fits and arithmetic does not overflow.

On success it moves the cursor and updates `usedBytes` consistently. Growing
may update the peak; shrinking never reduces the historical peak. Alignment
padding before the allocation may remain consumed because the operation does
not retain a prior-cursor token.

This operation never copies bytes and never interprets an object. It is safe
for an arena array to try it before deciding how to relocate any `T`.

### 8.3 Raw byte reallocation

The raw `tryReallocate` follows the arena's monotonic ownership model:

- null/zero old storage behaves as a fresh allocation;
- the latest allocation grows or shrinks in place when possible;
- a non-latest shrink may keep the same address without reclaiming bytes;
- a grow that cannot extend allocates replacement storage and copies
  `min(oldSize, newSize)` bytes;
- `newSize == 0` returns null and abandons or reclaims the old range as the
  latest-allocation rules permit;
- allocation failure leaves the old allocation valid and unchanged.

The fallback byte copy is for POD or otherwise explicitly raw storage only.
Typed callers must not use it to relocate arbitrary D values. The arena
allocator adapter may use it because the generic allocator reallocation
contract is itself raw-byte-oriented.

All pointer-range, alignment, and overflow validation is checked before pointer
arithmetic can wrap. Required calculations are outside removable checked
contracts.

### 8.4 POD arena-array growth

For POD `T`, array growth may use raw arena reallocation:

```text
newCapacity = growthPolicy(requested)
replacement = region.tryReallocate(
    newCapacity * T.sizeof,
    data,
    capacity * T.sizeof,
    T.alignof)
commit data and capacity only when replacement succeeds
```

This can extend the last allocation without copying. A non-latest array grows
by allocating and byte-copying while its old storage remains arena-owned.

### 8.5 Non-POD arena-array growth

For non-POD `T`:

1. attempt `tryResizeLastAllocation` so the common latest-allocation case can
   keep every object at the same address;
2. if that fails, allocate a larger raw `T` range;
3. move-construct every live element into the replacement using the same
   lifetime helpers as the ordinary array core;
4. treat every old source slot as abandoned, without destruction;
5. commit the new pointer and capacity.

Allocation happens before movement. Under BetterC and the array's `nothrow`
contract, the move loop does not introduce a recoverable failure, so an
allocation failure preserves the entire old array and a successful allocation
can be committed after movement.

The private implementation needs an explicit raw-destination move helper. Its
precondition is that the destination bytes contain no live value, or that the
prior value's lifetime has deliberately been abandoned. It must not invoke the
destination destructor as a side effect.

### 8.6 Removal, insertion, and replacement

POD elements use overlap-safe byte movement where appropriate. Non-POD
elements use typed move construction:

- before overwriting a removed/replaced slot, its old lifetime is deliberately
  abandoned without destruction;
- shifted source elements are moved into raw or abandoned destinations;
- moved-from source slots are never later destroyed by the arena container;
- `pop` move-constructs a caller-owned result, then reduces length;
- growing `resize` establishes `T.init`; shrinking only reduces length.

Copyable slice overloads preserve the ordinary array's alias handling. Source
offsets are recorded before growth and resolved against the new storage after
growth. Overflow or unsupported overlap returns failure before mutation.

This machinery is low-level and belongs in a small `@trusted`/`@system`
implementation boundary. The public contract is not that D automatically
forgets values; it is that the arena array implementation deliberately manages
their lifetimes without destruction.

### 8.7 Monotonic memory consequence

An old array block remains occupied until its containing arena checkpoint ends
unless it was the latest allocation and resized in place. Repeated growth can
therefore use more peak memory than a reallocating heap array. Callers should
use `withCapacity` or `reserve` when a useful estimate exists.

There is no first-version `shrinkToFit`: a name suggesting general reclamation
would be misleading when most old blocks cannot be reclaimed.

---

## 9. Checked diagnostics and zero-cost release-fast

### 9.1 Required release-fast outcome

In release-fast, these must compile to the same effective pointer and
allocation path after inlining:

```d
void* throughArena(Arena* arena, size_t size)
{
    return arena.allocate(size);
}

void* throughRegion(ArenaRegion* region, size_t size)
{
    return region.allocate(size);
}
```

The region path adds:

- no null or active branch;
- no epoch, depth, or thread comparison;
- no load of a wrapped `Arena*` field;
- no region-binding or invalidation stores;
- no diagnostic field in `ArenaArray`;
- no out-of-line adapter call.

Normal allocation branches, arithmetic, failure behavior, and array growth are
not region overhead and remain.

### 9.2 Checked representation

Checked builds use a real diagnostic object:

```d
struct ArenaRegion
{
    private Arena* arena_;
    private ulong epoch_;
    private size_t depth_;
    private void* threadToken_;
    private bool active_;
}
```

Binding captures one diagnostic region period. Validation checks:

1. the region is active;
2. its arena is non-null;
3. its epoch matches the arena's current diagnostic epoch;
4. its checkpoint depth matches the arena's active depth;
5. a TLS region's thread token matches the current thread.

The diagnostic epoch advances whenever a new region period begins, including
successive scratch scopes that reuse the same arena at the same depth. It is a
checked-only counter. Allocation behavior, output initialization, and required
state mutation never depend on it.

A checked bound `ArenaArray` snapshots enough identity to reject a pre-clear or
pre-rewind container even if an embedded root-region object later rebinds at
the same address. A compound operation validates once before its storage loop.

### 9.3 Release-fast representation

Release-fast uses `ArenaRegion` as a nominal, opaque view. Its pointer bits are
the underlying `Arena*` bits:

```d
struct ArenaRegion
{
    private ubyte opaque_;

    pragma(inline, true)
    private Arena* arena() return @trusted
    {
        return cast(Arena*) &this;
    }
}
```

No method reads `opaque_`. Calls are made through a trusted pointer view of an
actual arena. The cast and forwarding methods are forced inline and must be
verified with generated-code probes under both DMD and LDC.

`Arena` already requires its allocator adapter at offset zero because the
adapter casts back to its owner. Release-fast overlays the root region name at
that same address:

```d
struct Arena
{
    union
    {
        Allocator allocator_;       // offset zero
        ArenaRegion rootRegion_;    // offset zero
    }
    // Existing arena state follows.
}
```

Thus `arena.region` computes `cast(ArenaRegion*)&arena` with no additional
storage or binding. Static assertions protect both offset-zero invariants.

Checked `Arena` instead stores a real `rootRegion_` and a diagnostic epoch. On
`clear`/`deinit` it invalidates that region and advances the epoch before
invalidating storage. The next `.region` access binds the current root period.

### 9.4 `ScratchScope` representation

Checked `ScratchScope` embeds an `ArenaRegion` and binds it after pushing its
`TempArena`. Its destructor invalidates the region before popping.

Release-fast adds no region field. `.region` casts the `Arena*` already stored
in `TempArena`; acquisition and destruction remain the existing push/pop path.
`return scope` ties the exposed capability to the holder even though the
physical TLS arena lives longer.

### 9.5 Contract policy by build mode

Every `require` import and call remains inside `version (XTB_Checked)`. Adjacent
checks use one scoped version block. Conditions inspect already-computed state;
necessary calculations, mutations, and output initialization never occur only
inside a removable contract.

In checked builds, a null, inactive, stale, wrong-depth, or wrong-thread region
panics at the nearest relevant public boundary. In release-fast, those are
documented contract violations and may cause undefined behavior. The public
safety annotations must be truthful under that policy; operations whose safety
depends on a caller maintaining the region contract remain `@trusted` or
`@system` rather than being advertised as independently `@safe`.

Checked and release-fast public layouts differ. Objects compiled with and
without `XTB_Checked` are not ABI-compatible and must not be mixed.

### 9.6 Expected cost

Release-fast cost:

- zero additional arena or scratch-holder storage;
- one region pointer in bound arena containers, equal to the `Arena*` a direct
  design would store;
- zero region-specific checks or loads on the successful path.

Checked cost:

- one diagnostic region holder per active `ScratchScope` or root arena;
- diagnostic snapshots in a bound arena container;
- one validation at relevant public operation boundaries;
- epoch increments and invalidation stores at lifetime transitions.

Those costs are intentional diagnostics, not part of release-fast behavior.

---

## 10. Usage in real programs

### 10.1 Selection guide

| Need | Use |
| --- | --- |
| Clear, rewind, deinit, or tune chunks | `Arena*` |
| Allocate within one caller-controlled arena lifetime | `ArenaRegion*` |
| Generic temporary allocation with ordinary RAII | `region.allocator` |
| Growable values discarded with their region | `ArenaArray!T` |
| Compact storage with an externally supplied region | `ArenaArrayUnmanaged!T` |
| Individually released memory or destructor-dependent elements | `Array!T` |
| Persistent result independent of scratch | Caller output allocator and a domain conversion |

The existence of a new type does not require converting every scratch use.
Flat local `Array!int` or `StringBuf` values already work well with
`scratch.allocator` and should remain ordinary owners unless arena-native
nesting or explicit region semantics provides a concrete benefit.

### 10.2 Full operation with two TLS arenas and an output allocator

The following invented example has the ownership shape expected in a compiler:

```d
struct CompileError
{
    String message;
}

struct CompiledUnit
{
    Array!uint instructions;
    StringBuf symbolBytes;

    @disable this(this);

    ~this()
    {
        deinit();
    }

    static CompiledUnit create(Allocator* allocator)
    {
        CompiledUnit result;
        result.instructions = Array!uint.create(allocator);
        result.symbolBytes = StringBuf.create(allocator);
        return move(result);
    }

    void deinit()
    {
        symbolBytes.deinit();
        instructions.deinit();
    }
}

struct Token
{
    String spelling; // Borrows source for the duration of compileUnit.
}

struct AstNode
{
    String spelling;
    ArenaArray!AstNode children;
}

Result!(CompiledUnit, CompileError) compileUnit(
    Allocator* outputAllocator,
    Allocator* sourceAllocator,
    String source,
)
{
    mixin ResultReturns;

    // Declared first, so an error path destroys persistent partial output
    // after all later scratch-backed locals have ended.
    CompiledUnit output = CompiledUnit.create(outputAllocator);

    // Neither live input nor output may be backed by the selected scratch
    // arena. Failure to find a non-conflicting TLS arena is a panic.
    Allocator*[2] conflicts = [outputAllocator, sourceAllocator];
    ScratchScope scratch = ScratchScope.acquire(conflicts[]);

    ArenaArray!Token tokens = ArenaArray!Token.create(scratch.region);
    if (!tryLex(scratch.region, source, &tokens))
        return err(CompileError("invalid token"));

    ArenaArray!AstNode syntax = ArenaArray!AstNode.create(scratch.region);
    if (!tryParse(scratch.region, tokens.slice, &syntax))
        return err(CompileError("invalid syntax"));

    // This is a domain conversion, not ArenaArray.clone. Every retained byte
    // is copied or encoded using outputAllocator.
    if (!tryLower(outputAllocator, syntax.slice, &output))
        return err(CompileError("output allocation failed"));

    return ok(move(output));
}
```

The helpers reuse `scratch.region`; they do not acquire nested scratch scopes.
On every error path, arena arrays do nothing, `ScratchScope` rewinds once, and
ordinary output members clean their partial ownership. On success, no scratch
pointer may remain in `CompiledUnit`.

If `source` is known not to be allocator-backed, its allocator is omitted from
the conflict list. Conversely, every allocator that may back live input or
output must be included even if it was reached indirectly through a container.

### 10.3 Resource-bearing temporary work

Arena-native graph structure and ordinary resources can coexist without a
parallel manual-cleanup convention:

```d
Result!(OwnedModule, LoadError) loadModule(
    Allocator* outputAllocator,
    String path,
)
{
    mixin ResultReturns;

    OwnedModule output = OwnedModule.create(outputAllocator);
    ScratchScope scratch = ScratchScope.acquire(outputAllocator);

    ArenaArray!AstNode nodes = ArenaArray!AstNode.create(scratch.region);
    Array!File includes = Array!File.create(scratch.region.allocator);
    StringBuf text = StringBuf.create(scratch.region.allocator);

    auto loaded = readAndParse(path, scratch.region, &includes, &text, &nodes);
    if (!loaded)
        return err(loaded.takeError());
    if (!tryPromoteModule(outputAllocator, nodes.slice, &output))
        return err(LoadError.outOfMemory);
    return ok(move(output));
}
```

Reverse declaration order is important: `text` and `includes` finish their
ordinary destruction before `scratch` rewinds their backing bytes. `nodes` has
no destructor and needs no `scope(exit)`.

### 10.4 Nested graph

Arena arrays solve the case where ordinary array ownership would recursively
infect every node with teardown work:

```d
struct SceneNode
{
    String name;
    ArenaArray!SceneNode children;
}

SceneNode* addNode(
    ArenaRegion* region,
    String name,
)
{
    SceneNode* result = region.create!SceneNode();
    result.name = name;
    result.children = ArenaArray!SceneNode.create(region);
    return result;
}
```

Discarding the region does not traverse `children`, including arrays nested at
every depth. The name bytes must either be borrowed for the full region
lifetime or copied into that region by the caller.

### 10.5 Persistent arena owner

A persistent owner can expose an allocation capability while retaining reset
authority internally:

```d
struct Document
{
private:
    Arena arena_;                 // Declared first, destroyed last.
    ArenaArray!Node nodes_;
    Node* root_;

public:
    @disable this(this);

    ~this()
    {
        deinit();
    }

    static Document create(Allocator* backingAllocator)
    {
        Document result;
        result.arena_ = Arena.create(backingAllocator);
        // Do not bind nodes_ or retain &result.arena_ here. The returned
        // Document does not yet have its final address.
        return move(result);
    }

    void deinit()
    {
        nodes_.clear();
        root_ = null;
        arena_.deinit();
    }

    bool tryBuild(String source)
    {
        nodes_ = ArenaArray!Node.create(arena_.region);
        return tryParse(arena_.region, source, &nodes_, &root_);
    }

    void clear()
    {
        // No ordinary arena-backed owners may still need destruction here.
        nodes_.clear();
        root_ = null;
        arena_.clear();
    }
}
```

The caller constructs `Document` in its final location before calling
`tryBuild`, and does not later move an active document. A checked container
created before `clear` is stale even if its stored bytes have not yet been
overwritten; `tryBuild` binds a fresh container to the new region period.

### 10.6 Cross-thread work

TLS scratch handles never cross a thread boundary:

```d
void consumeJobs(const(Job)[] jobs) nothrow @nogc
{
    // ...
}

// Wrong: the worker may start after scratch has rewound and the region is
// bound to the submitting thread.
ScratchScope scratch = ScratchScope.acquire();
ArenaArray!Job jobs = ArenaArray!Job.create(scratch.region);
auto started = spawn!consumeJobs(
    spawnAllocator,
    cast(const(Job)[]) jobs.slice,
);
```

Build an owned task using a suitable output allocator, then acquire scratch on
the worker after that worker installs its `ThreadContextScope`:

```d
Result!(OwnedResult, WorkerError) runOwnedJob(
    OwnedJob job,
    Allocator* resultAllocator,
)
{
    mixin ResultReturns;
    ThreadContextScope context = ThreadContextScope.acquire();
    ScratchScope scratch = ScratchScope.acquire(resultAllocator);
    ArenaArray!WorkItem work = ArenaArray!WorkItem.create(scratch.region);
    if (!tryProcess(scratch.region, &job, &work))
        return err(WorkerError.failed);
    return buildOwnedResult(resultAllocator, work.slice);
}

OwnedJob job = OwnedJob.fromInput(jobAllocator, input);
auto started = spawn!runOwnedJob(
    spawnAllocator,
    move(job),
    resultAllocator,
);
if (!started)
    panic("worker start failed");
auto handle = started.unwrap();
auto outcome = handle.join();
```

Caller-owned arenas may be transferred sequentially under an external
ownership protocol, but they remain unsynchronized. A TLS region always stores
a checked thread token. `spawnAllocator` and `resultAllocator` must satisfy the
ordinary `spawn` lifetime and cross-thread allocator contracts through join.

---

## 11. Parser migration

The current parser contains a private `ArenaList!T` with `Arena*`, data,
length, and capacity fields. It doubles capacity, allocates a new array, and
`memcpy`s existing elements. That local type is both the immediate use case and
a useful integration test for the public feature.

### 11.1 Parse output context

Collection output needs allocation authority, not arena reset authority. The
context changes conceptually from:

```d
struct ParseContext
{
    Arena* outputArena;
    void* userData;
}
```

to:

```d
struct ParseContext
{
    ArenaRegion* outputRegion;
    void* userData;

    static ParseContext create(
        return scope ArenaRegion* outputRegion = null,
        void* userData = null,
    );
}
```

The actual declaration must preserve the region lifetime through the parse
entry points; this is part of the DIP1000 compilation test matrix, not merely a
field rename.

Callers that own output storage write:

```d
Arena outputArena = Arena.create(backingAllocator);
ParseContext context = ParseContext.create(outputArena.region, userData);
auto result = parser.parse(input, &context);
```

Scratch output writes:

```d
ScratchScope scratch = ScratchScope.acquire();
ParseContext context = ParseContext.create(scratch.region, userData);
auto result = parser.parse(input, &context);
```

The result is borrowed from the supplied region and must not outlive it.

### 11.2 Collector replacement

The private collector becomes ordinary public machinery:

```d
ArenaArray!T values = ArenaArray!T.create(
    state.context_.outputRegion,
);

while (true)
{
    ParseOutcome!T item = invokeParser(parser, state);
    if (!item.success)
        break;
    values.append(move(item.value));
}

return ParseOutcome!(T[]).succeed(values.slice);
```

The exact loop retains the parser's committed-failure and progress checks. The
migration removes only `ArenaList`; it is not a parser behavior change.

The current collector is constrained to copyable, destructor-free `T` because
it uses `memcpy`. The arena array itself accepts all `T` and uses typed movement
for non-POD values. Parser combinator constraints may remain where parser
semantics independently require copying; they must not be inherited merely
from the old private storage implementation.

### 11.3 Grammar remains owner-level

`Grammar` embeds and owns an `Arena`, constructs the immutable parser graph,
and deinitializes the whole graph. Its `.arena` owner access and internal raw
node construction need not be mechanically changed to regions.

When grammar code creates an arena-native container, it uses
`arena_.region`. Code that only allocates a parser node may continue using the
owner internally. This keeps the migration based on authority and lifetime,
not on a rule that every `Arena*` is obsolete.

---

## 12. Failure, aliasing, and lifecycle rules

### 12.1 Allocation failure

Arena-array failure follows the ordinary container convention:

- `tryWithCapacity`, `tryReserve`, `tryResize`, `tryAppend`, and `tryInsert`
  return `false` for capacity overflow or allocation failure;
- infallible forms panic;
- a failed growth preserves the old pointer, length, capacity, and live stored
  elements;
- fallible factories require an empty output and publish it only on success;
- necessary output initialization is never hidden in `XTB_Checked` contracts.

Arena allocation cannot roll back an older unrelated allocation, but a failed
attempt must not commit new array metadata. Non-POD relocation allocates before
moving, and BetterC array movement is `nothrow`.

An append parameter or other caller-owned temporary retains its normal D
lifetime. The no-destruction rule applies to element lifetimes once stored in
an arena container; it does not suppress destruction of unrelated stack
temporaries on a failed call.

### 12.2 Aliasing

Appending or inserting a slice that aliases the same array must either:

- preserve the ordinary array's supported semantics by recording offsets and
  resolving them after growth; or
- reject an unsupported non-POD overlap before mutation.

Pointer comparisons and byte offsets must avoid overflow. A checked contract
cannot perform calculations required by the release-fast path.

### 12.3 Borrowed views

`.slice` and `opIndex` expose storage only while the region remains live and
the array operation has not invalidated the relevant address. Growth may move
the array even though the old bytes remain allocated, so old slices and element
pointers are invalid after any operation that may grow or shift storage.

Arena lifetime alone does not provide address stability for a growable array.
Callers needing stable element addresses allocate nodes individually and keep
an arena array of pointers or indices.

### 12.4 Declaration order

An ordinary owner backed by a region allocator must be destroyed before the
holder that rewinds the region. The idiomatic order is:

```d
PersistentOutput output = PersistentOutput.create(outputAllocator);
ScratchScope scratch = ScratchScope.acquire(output.allocator);
ArenaArray!PlainData temporary = ArenaArray!PlainData.create(scratch.region);
Array!Resource resources = Array!Resource.create(scratch.region.allocator);
StringBuf builder = StringBuf.create(scratch.region.allocator);
```

D destroys these in reverse order: builder, resources, temporary (no
destructor), scratch, then unmoved output. Do not declare an arena-backed
ordinary owner before the holder whose allocator it stores.

`ScratchScope` already owns rewind and ordinary owners already own `deinit`.
Parallel `scope(exit)` cleanup is unnecessary and risks double cleanup.

### 12.5 Explicit owner clear

Calling `Arena.clear` is an owner-level unsafe lifetime transition. All
borrowed views and containers from the previous root region become invalid.
Checked container snapshots diagnose later use, but the type system does not
make `clear` statically exclusive with every `@system` alias.

`Arena.clear` remains invalid while any `TempArena` checkpoint is active.
Ending a `ScratchScope` is the supported way to rewind scratch; calling clear
on its underlying arena in the same active lexical scope is not.

---

## 13. Safety and threading boundary

### 13.1 What safe code can rely on

Where the compiler accepts the final DIP1000 declarations, safe code should
not be able to return a region-bound handle derived from a local
`ScratchScope`. Bounds-checked metadata access and checked-build region
diagnostics provide additional protection.

This does not make all arena APIs `@safe`. Returning mutable raw slices,
manually ending object lifetimes without destructors, opaque release-fast
pointer views, and unmanaged provider consistency require small audited
`@trusted` or public `@system` boundaries.

### 13.2 Thread rules

- TLS scratch regions are thread-affine and may not be captured by `spawn`, a
  structured `ThreadScope`, or any asynchronous callback.
- Worker temporary allocation comes from a `ThreadContextScope` installed by
  that worker.
- A caller-owned arena is unsynchronized. It may be transferred sequentially
  only when no old thread retains access.
- An allocator used for persistent cross-thread output must itself support the
  required cross-thread allocation/deallocation pattern.

Checked TLS regions compare a thread token at relevant calls. Release-fast
performs no token load or comparison.

### 13.3 Unsafe escape remains a contract violation

`@system` code can cast, store, or return any pointer. A stale region whose
holder storage is already dead cannot be safely inspected even in a checked
build. Rewind poisoning and sanitizers are useful additional diagnostics, but
no claim in this proposal treats runtime validation as complete temporal
memory safety.

---

## 14. Test and verification plan

Implementation is incomplete until all of the following pass under BetterC.

### 14.1 Lifetime compilation tests

Checked-in compile-pass/compile-fail fixtures must cover DMD and LDC for:

- passing `scratch.region` through synchronous helper calls;
- constructing a local `ArenaArray` from it;
- rejecting return of that array from the local scratch lifetime;
- rejecting storage of the region in a longer-lived safe owner;
- accepting a caller-owned root arena region with a sufficient lifetime;
- recursive `Node` containing `ArenaArray!Node`;
- `ParseContext` preserving the output-region lifetime through parse calls.

Any compiler-specific limitation must be documented in the public annotations;
it must not be papered over with a broad `@trusted` facade.

### 14.2 Arena reallocation tests

Test:

- null/zero combinations;
- exact latest-allocation detection;
- latest grow and shrink;
- insufficient current-chunk space;
- non-latest shrink without false reclamation;
- non-latest grow with byte preservation;
- movement to a later or newly allocated chunk;
- alignment and padding;
- addition and multiplication overflow;
- allocation failure preserving old storage;
- `usedBytes`, peak, chunk offsets, and retention interaction;
- behavior across `push`/`pop` checkpoints;
- poisoning of rewound memory.

### 14.3 Arena-array behavior tests

Run the ordinary array test matrix against the arena family where semantics
match:

- valid zero state and non-copyability;
- capacity growth and overflow;
- `withCapacity`, `withLength`, and `fromSlice`;
- append, insert, remove, range remove, pop, resize, clear, indexing, and
  iteration;
- self-aliased slice append/insert boundaries;
- POD in-place and relocating growth;
- non-POD typed movement;
- unmanaged explicit-region calls;
- move construction and replacement of an active destination;
- failed operations preserving state.

Use a destructor-counting `T` to prove that stored element destructors are not
called by clear, shrink, remove, replacement, relocation, container scope exit,
checkpoint pop, `Arena.clear`, or `Arena.deinit`. Separately prove that move
construction occurs exactly once and that caller-owned temporaries retain their
ordinary lifetime behavior.

### 14.4 Checked diagnostics

Death/regression tests cover:

- null and inactive regions;
- a container after root `Arena.clear`;
- a container after scratch rewind while its holder storage remains
  inspectable;
- successive scopes reusing the same TLS arena and depth;
- wrong checkpoint depth and non-LIFO misuse;
- wrong-thread TLS access;
- uninitialized outputs and bounds violations.

The unmanaged array cannot prove provider provenance. Checked calls validate
the supplied region itself, while same-region consistency remains documented
caller responsibility.

### 14.5 Release-fast structure and code generation

Static and generated-code checks cover:

- allocator and root-region offset zero;
- `ArenaRegion*` pointer equality with its underlying `Arena*`;
- no release-fast region field in `ScratchScope`;
- no release-fast diagnostic fields in `ArenaArray`;
- expected three-word unmanaged and four-word bound layouts;
- equivalent DMD and LDC optimized code for direct arena and region allocation;
- absence of region validation, binding, invalidation, and diagnostic epoch
  work in release-fast;
- no accidental element-destruction calls in arena-array code generation.

### 14.6 Integration and full project checks

- Preserve every existing `Array!T` test before and after the private storage
  refactor.
- Replace parser `ArenaList` and run parser regression/failure tests.
- Add a two-TLS-arena plus output-allocator integration test proving helpers
  reuse one region.
- Add resource-table tests for success and every early return.
- Add a shallow-promotion regression proving nested scratch pointers are not
  mistaken for persistent output.
- Compile affected examples.
- Run formatting checks and the complete test suite in every supported build
  mode, including `-betterC` and release-fast.

No new test executable should be added without following `docs/testing.md`.

---

## 15. Implementation sequence

### Phase 0: prove the boundary

1. Check in minimal DMD/LDC lifetime fixtures for the final holder and return
   annotations.
2. Check in optimized code-generation probes for direct `Arena*` versus
   `ArenaRegion*`.
3. Finalize public attributes only after both probes reflect the claimed
   behavior.

### Phase 1: native arena operations

1. Add latest-allocation detection and in-place resize to
   `xtb.core.allocators.arena`.
2. Add raw reallocation with the POD/raw fallback contract.
3. Route the arena allocator adapter through the native primitive where valid.
4. Complete bookkeeping, overflow, checkpoint, and failure tests.

No array module dependency is introduced into the arena module.

### Phase 2: private array storage refactor

1. Capture a focused baseline for `ArrayUnmanaged!T` and `Array!T`.
2. Extract only the private algorithms needed for provider-specialized growth
   and destruction policy.
3. Keep all four public structs handwritten.
4. Re-run the ordinary array suite before adding new public behavior.

### Phase 3: region and arena arrays

1. Add checked and release-fast `ArenaRegion` representations.
2. Integrate root `Arena.region` and lexical `ScratchScope.region`.
3. Add `ArenaArrayUnmanaged!T` and its complete tests.
4. Add bound `ArenaArray!T`, checked snapshots, and its complete tests.
5. Re-export stable public modules from the relevant `package.d`.

### Phase 4: parser consumer

1. Change parse-output allocation authority to `ArenaRegion*`.
2. Replace the private `ArenaList!T` collector.
3. Preserve parser control flow, error attachment, and progress behavior.
4. Run parser, cross-module, lifetime, and full regression tests.

### Phase 5: verification and documentation

1. Run the generated-code comparison in release-fast.
2. Compile affected examples.
3. Run all supported checked, release-safe, and release-fast BetterC tests.
4. Document the final public API and the destructor-abandonment contract.

Later arena containers require separate proposals informed by this array's
measured ergonomics, diagnostics, and code generation.

---

## 16. Rejected alternatives

### 16.1 Use only `Arena*`

This can implement allocation but cannot express the shorter scratch lifetime,
grants reset authority to every helper, and cannot distinguish successive uses
of the same TLS arena in diagnostics. It remains correct for actual owners.

### 16.2 Store an `Arena*` inside every release-fast region wrapper

The obvious wrapper adds an arena-pointer load and holder storage. The opaque
view achieves the same static type distinction without either cost and is
contained in an audited boundary.

### 16.3 Validate regions in release-fast

Unconditional epoch/thread/depth checks contradict the required direct-arena
performance. xtb's checked-build policy already provides the right place for
programming-contract diagnostics. Release-fast violations remain explicit
undefined behavior.

### 16.4 Restrict `T` with a destructor or discardability trait

A structural trait cannot prove whether a particular value requires cleanup,
whether its allocator is an arena, or whether a nested pointer owns a resource.
Putting a conditional trait on the struct declaration also creates completion
cycles for recursive types. The proposal instead states the container's
behavior and lets callers choose representations consciously.

### 16.5 Run some destructors in arena containers

Selective destruction recreates operation-dependent walks, complicates moves
and removals, and makes bulk abandonment no longer uniform. Values that require
destruction belong in ordinary owners or explicit compact cleanup tables.

### 16.6 Use ordinary `Array!T` everywhere

This remains a good choice for flat temporaries and resources. It is not a full
replacement for arena arrays because embedding ordinary owning containers
throughout a graph gives the graph a recursive destruction obligation, even
when backing deallocation is a no-op.

### 16.7 Generate public wrappers from one policy template

This reduces source repetition at the cost of public readability, compiler
diagnostics, documentation, and LSP discoverability. Private compile-time
specialization captures the useful reuse without making ownership policy a
public abstraction.

### 16.8 Offer both `Arena*` and `ArenaRegion*` constructors

Two equivalent-looking constructors weaken the capability boundary and make
lifetime guidance inconsistent. Owners already have an immediate `.region`
property, so the additional overload saves no meaningful ceremony.

### 16.9 Provide a generic `clone`

A shallow top-level copy cannot guarantee independence from scratch. Plain
values already have `Array.fromSlice`; domain-specific promotion is the only
honest operation for nested ownership.

### 16.10 Register cleanup callbacks with the arena

A registry adds allocation, ordering, failure, and reentrancy machinery while
turning arena clear back into a potentially large destruction walk. Ordinary
RAII cleanup tables are simpler and preserve existing library conventions.

### 16.11 Replace RAII with explicit `deinit` plus `scope(exit)` everywhere

Owning xtb structs already expose explicit `deinit` and use their destructors
to make ordinary lexical ownership reliable. Repeating those calls in
`scope(exit)` is more error-prone and does not improve arena graph teardown.
The useful split is ordinary RAII for resources and no destruction for
arena-native values.

---

## 17. Library fit and recommendation

The feature fits xtb when kept at this boundary.

It matches the library's explicit ownership vocabulary: arenas own bytes,
regions borrow allocation authority, ordinary containers own logical elements,
and arena containers abandon them. It uses existing `.allocator`, `.arena`,
and `.region` property style; requires no GC, exceptions, reflection, or hidden
allocator selection; preserves `ScratchScope` RAII; and gives `Array`-like
operations familiar short names.

The ergonomic cost is one additional public concept and a parallel array type.
That cost is justified for nested arena structures and allocation-only helper
APIs, but not for every temporary buffer. Users can still write
`Array!int.create(scratch.allocator)` when ordinary RAII is already sufficient.

The correctness boundary is honest rather than absolute. `ArenaRegion`
prevents excess authority and improves compile-time lifetime expression;
checked builds catch common stale/depth/thread mistakes. It does not prove deep
pointer provenance, destructor suitability, owner immobility, or every
`@system` escape. Arena arrays make the deliberate no-destruction choice
visible in the type name and documentation instead of trying to infer it.

The recommendation is to implement Phases 0 through 4 as one feature, with the
parser migration as the required real consumer. Do not add further arena
containers until the lifetime fixtures, destructor-abandonment tests, ordinary
array compatibility suite, and release-fast code-generation comparison all
pass.

The intended mental model is:

> Keep lifetime control on `Arena*`, pass allocation through `ArenaRegion*`,
> store discardable graph structure in arena-native containers, and keep every
> resource requiring cleanup in an ordinary owner that dies before the region.
