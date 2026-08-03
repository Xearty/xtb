module xtb.core.hash_map;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.lifetime : move, moveEmplace;
import core.stdc.string : memset;
import xtb.core.hash : HashSeed, hashValue;
import xtb.core.memory : Allocator, deallocate, tryAllocate, tryAllocateZeroed;
import xtb.core.numeric : multiplyOverflows;
import xtb.core.panic : panic, require;

private enum SlotState : ubyte
{
    empty,
    occupied,
    removed,
}

/// Default seeded hash policy. Custom policies use the same pointer-based
/// call shape and may carry copyable, destructor-free state.
struct DefaultHash(K)
{
    HashSeed seed;

    size_t opCall(scope const(K)* key) const
    {
        return hashValue(*key, seed);
    }
}

/// Default equality policy. It uses the key's ordinary value equality.
struct DefaultEqual(K)
{
    bool opCall(scope const(K)* left, scope const(K)* right) const
    {
        return *left == *right;
    }
}

enum SetStatus
{
    inserted,
    replaced,
    outOfMemory,
}

enum AddStatus
{
    inserted,
    alreadyPresent,
    outOfMemory,
}

private struct Entry(K, V)
{
    size_t hash;
    K key;
    V value;
}

private struct ProbeResult
{
    size_t index;
    bool found;
}

version (unittest)
{
    private struct ConstantIntHash
    {
        size_t opCall(scope const(int)*) const pure nothrow @safe @nogc
        {
            return 1;
        }
    }

    private struct TrackedHashValue
    {
    nothrow @nogc:

        int* destructions;
        int value;
        bool active;

        @disable this(this);

        ~this()
        {
            if (active)
                ++*destructions;
        }
    }

    private struct TrackedHashKey
    {
    nothrow @nogc:

        int value;
        int* live;
        bool active;

        this(int value, int* live)
        {
            this.value = value;
            this.live = live;
            active = true;
            ++*live;
        }

        this(this)
        {
            if (active)
                ++*live;
        }

        ~this()
        {
            if (active)
                --*live;
        }
    }

    private struct TrackedKeyHash
    {
        size_t opCall(scope const(TrackedHashKey)* key) const pure nothrow @safe @nogc
        {
            return cast(size_t) key.value;
        }
    }

    private struct TrackedKeyEqual
    {
        bool opCall(
            scope const(TrackedHashKey)* left,
            scope const(TrackedHashKey)* right,
        ) const pure nothrow @safe @nogc
        {
            return left.value == right.value;
        }
    }
}

/// Allocator-owned open-addressed hash table.
///
/// Keys cannot be mutated through the table because changing a key in place
/// would invalidate its stored hash and probe position. Values are exposed as
/// pointers so mutation remains explicit at the call site. Any insertion,
/// removal, clear, reserve, or storage release invalidates cursors. A value
/// replacement preserves cursors but may invalidate a pointer to that value.
/// Iteration order is unspecified. For view-like keys such as `String`, the
/// table owns the view value but not the storage to which it refers.
struct HashMap(K, V, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
nothrow @nogc:

    static assert(__traits(isCopyable, K),
        "HashMap keys must be copyable; store an immutable view or handle instead");
    static assert(__traits(isCopyable, Hasher) &&
            !hasElaborateDestructor!Hasher,
        "HashMap hash policies must be copyable and have no destructor");
    static assert(__traits(isCopyable, Equal) &&
            !hasElaborateDestructor!Equal,
        "HashMap equality policies must be copyable and have no destructor");

    private Allocator* allocator_;
    private SlotState* states_;
    private Entry!(K, V)* entries_;
    private size_t length_;
    private size_t removed_;
    private size_t capacity_;
    private Hasher hasher_;
    private Equal equal_;

    @disable this(this);

    static HashMap create(Allocator* allocator)
    {
        return withPolicies(allocator, Hasher.init, Equal.init);
    }

    static HashMap seeded(Dummy = void)(Allocator* allocator, HashSeed seed)
    {
        static assert(is(Hasher == DefaultHash!K) &&
                is(Equal == DefaultEqual!K),
            "seeded is available only with the default hash policies");
        Hasher hasher;
        hasher.seed = seed;
        return withPolicies(allocator, hasher, Equal.init);
    }

    static HashMap withPolicies(
        Allocator* allocator,
        Hasher hasher,
        Equal equal,
    )
    {
        require(allocator !is null && *allocator !is null,
            "HashMap requires a valid allocator");
        HashMap result;
        result.allocator_ = allocator;
        result.hasher_ = hasher;
        result.equal_ = equal;
        return result;
    }

    static HashMap withCapacity(Dummy = void)(
        Allocator* allocator,
        size_t requested,
        HashSeed seed = HashSeed.init,
    )
    {
        HashMap result = seeded(allocator, seed);
        result.reserve(requested);
        return result;
    }

    ~this()
    {
        deinit();
    }

    void deinit()
    {
        this.clear();
        allocator_.deallocate(entries_, capacity_);
        allocator_.deallocate(states_, capacity_);
        allocator_ = null;
        states_ = null;
        entries_ = null;
        capacity_ = 0;
    }

    size_t length() const pure @safe
    {
        return length_;
    }

    size_t capacity() const pure @safe
    {
        return capacity_;
    }

    bool empty() const pure @safe
    {
        return length_ == 0;
    }

    Allocator* allocator() return
    {
        return allocator_;
    }

    HashMapCursor!(K, V) cursor() return
    {
        return HashMapCursor!(K, V).create(states_, entries_, capacity_);
    }

    ConstHashMapCursor!(K, V) cursor() const return
    {
        return ConstHashMapCursor!(K, V).create(
            states_,
            entries_,
            capacity_,
        );
    }

    /// Returns an input range whose items contain explicit key/value pointers.
    HashMapPointerRange!(K, V) pointerItems() return
    {
        return HashMapPointerRange!(K, V)(cursor());
    }

    /// Returns the read-only pointer-item range for a const map.
    ConstHashMapPointerRange!(K, V) pointerItems() const return
    {
        return ConstHashMapPointerRange!(K, V)(cursor());
    }

    /// Supports `foreach (ref const key, ref value; map)`. The key remains
    /// immutable while the explicit `ref value` permits in-place mutation.
    /// Structural mutation of the map from the loop body is invalid.
    int opApply(
        scope int delegate(ref const(K), ref V) nothrow @nogc callback,
    )
    {
        foreach (index; 0 .. capacity_)
        {
            if (states_[index] != SlotState.occupied)
                continue;
            const result = callback(
                entries_[index].key,
                entries_[index].value,
            );
            if (result != 0)
                return result;
        }
        return 0;
    }

    /// Supports read-only iteration over a const map.
    int opApply(
        scope int delegate(ref const(K), ref const(V)) nothrow @nogc callback,
    ) const
    {
        foreach (index; 0 .. capacity_)
        {
            if (states_[index] != SlotState.occupied)
                continue;
            const result = callback(
                entries_[index].key,
                entries_[index].value,
            );
            if (result != 0)
                return result;
        }
        return 0;
    }
}

private void constructMove(T)(T* destination, ref T source)
{
    static if (__traits(isPOD, T))
        *destination = source;
    else
        moveEmplace(source, *destination);
}

private void destroyElement(T)(T* element)
{
    static if (hasElaborateDestructor!T)
        destroy!false(*element);
}

private size_t maximumLength(size_t capacity) pure @safe
{
    return capacity - capacity / 8;
}

private bool capacityForLength(size_t requested, size_t* output)
{
    require(output !is null, "HashMap capacity output pointer is null");
    if (requested == 0)
    {
        *output = 0;
        return true;
    }

    size_t capacity = 8;
    while (maximumLength(capacity) < requested)
    {
        if (capacity > size_t.max / 2)
            return false;
        capacity *= 2;
    }
    *output = capacity;
    return true;
}

private ProbeResult probe(K, V, Hasher, Equal)(
    ref const HashMap!(K, V, Hasher, Equal) map,
    scope const(K)* key,
    size_t hash,
)
{
    if (map.capacity_ == 0)
        return ProbeResult.init;

    const mask = map.capacity_ - 1;
    size_t index = hash & mask;
    size_t firstRemoved = size_t.max;
    for (;;)
    {
        final switch (map.states_[index])
        {
            case SlotState.empty:
                return ProbeResult(
                    firstRemoved == size_t.max ? index : firstRemoved,
                    false,
                );
            case SlotState.occupied:
                if (map.entries_[index].hash == hash &&
                    map.equal_(&map.entries_[index].key, key))
                    return ProbeResult(index, true);
                break;
            case SlotState.removed:
                if (firstRemoved == size_t.max)
                    firstRemoved = index;
                break;
        }
        index = (index + 1) & mask;
    }
}

private size_t emptyIndex(K, V)(
    const(SlotState)* states,
    size_t capacity,
    size_t hash,
) pure
{
    const mask = capacity - 1;
    size_t index = hash & mask;
    while (states[index] == SlotState.occupied)
        index = (index + 1) & mask;
    return index;
}

private bool tryRehash(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
    size_t capacity,
)
{
    require(capacity >= 8 && (capacity & (capacity - 1)) == 0,
        "invalid HashMap capacity");
    if (multiplyOverflows(Entry!(K, V).sizeof, capacity))
        return false;

    SlotState* states = cast(SlotState*) map.allocator_
        .tryAllocateZeroed!ubyte(capacity);
    if (states is null)
        return false;
    Entry!(K, V)* entries = map.allocator_.tryAllocate!(Entry!(K, V))(capacity);
    if (entries is null)
    {
        map.allocator_.deallocate(states, capacity);
        return false;
    }

    foreach (index; 0 .. map.capacity_)
    {
        if (map.states_[index] != SlotState.occupied)
            continue;
        Entry!(K, V)* source = map.entries_ + index;
        const destinationIndex = emptyIndex!(K, V)(
            states,
            capacity,
            source.hash,
        );
        Entry!(K, V)* destination = entries + destinationIndex;
        destination.hash = source.hash;
        constructMove(&destination.key, source.key);
        constructMove(&destination.value, source.value);
        states[destinationIndex] = SlotState.occupied;
    }

    map.allocator_.deallocate(map.entries_, map.capacity_);
    map.allocator_.deallocate(map.states_, map.capacity_);
    map.entries_ = entries;
    map.states_ = states;
    map.capacity_ = capacity;
    map.removed_ = 0;
    return true;
}

private bool tryPrepareInsert(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
)
{
    if (map.capacity_ == 0)
        return map.tryRehash(8);
    if (map.length_ + map.removed_ < maximumLength(map.capacity_))
        return true;
    if (map.length_ < maximumLength(map.capacity_))
        return map.tryRehash(map.capacity_);
    if (map.capacity_ > size_t.max / 2)
        return false;
    return map.tryRehash(map.capacity_ * 2);
}

bool tryReserve(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
    size_t requested,
)
{
    require(map.allocator_ !is null && *map.allocator_ !is null,
        "HashMap is not initialized");
    size_t capacity;
    if (!capacityForLength(requested, &capacity))
        return false;
    if (capacity <= map.capacity_)
        return true;
    return map.tryRehash(capacity);
}

void reserve(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
    size_t requested,
)
{
    if (!map.tryReserve(requested))
        panic("HashMap allocation failed");
}

SetStatus trySet(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
    K key,
    V value,
)
{
    require(map.allocator_ !is null && *map.allocator_ !is null,
        "HashMap is not initialized");
    const hash = map.hasher_(&key);
    ProbeResult location = map.probe(&key, hash);
    if (location.found)
    {
        move(value, map.entries_[location.index].value);
        return SetStatus.replaced;
    }
    if (!map.tryPrepareInsert())
        return SetStatus.outOfMemory;

    location = map.probe(&key, hash);
    Entry!(K, V)* destination = map.entries_ + location.index;
    const reusedRemoved = map.states_[location.index] == SlotState.removed;
    destination.hash = hash;
    constructMove(&destination.key, key);
    constructMove(&destination.value, value);
    map.states_[location.index] = SlotState.occupied;
    ++map.length_;
    if (reusedRemoved)
        --map.removed_;
    return SetStatus.inserted;
}

bool set(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
    K key,
    V value,
)
{
    const status = map.trySet(move(key), move(value));
    if (status == SetStatus.outOfMemory)
        panic("HashMap allocation failed");
    return status == SetStatus.inserted;
}

AddStatus tryAdd(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
    K key,
    V value,
)
{
    require(map.allocator_ !is null && *map.allocator_ !is null,
        "HashMap is not initialized");
    const hash = map.hasher_(&key);
    ProbeResult location = map.probe(&key, hash);
    if (location.found)
        return AddStatus.alreadyPresent;
    if (!map.tryPrepareInsert())
        return AddStatus.outOfMemory;

    location = map.probe(&key, hash);
    Entry!(K, V)* destination = map.entries_ + location.index;
    const reusedRemoved = map.states_[location.index] == SlotState.removed;
    destination.hash = hash;
    constructMove(&destination.key, key);
    constructMove(&destination.value, value);
    map.states_[location.index] = SlotState.occupied;
    ++map.length_;
    if (reusedRemoved)
        --map.removed_;
    return AddStatus.inserted;
}

bool add(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
    K key,
    V value,
)
{
    const status = map.tryAdd(move(key), move(value));
    if (status == AddStatus.outOfMemory)
        panic("HashMap allocation failed");
    return status == AddStatus.inserted;
}

V* find(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
    scope K key,
)
{
    if (map.capacity_ == 0)
        return null;
    const hash = map.hasher_(&key);
    const location = map.probe(&key, hash);
    return location.found ? &map.entries_[location.index].value : null;
}

const(V)* find(K, V, Hasher, Equal)(
    ref const HashMap!(K, V, Hasher, Equal) map,
    scope K key,
)
{
    if (map.capacity_ == 0)
        return null;
    const hash = map.hasher_(&key);
    const location = map.probe(&key, hash);
    return location.found ? &map.entries_[location.index].value : null;
}

bool contains(K, V, Hasher, Equal)(
    ref const HashMap!(K, V, Hasher, Equal) map,
    scope K key,
)
{
    return map.find(key) !is null;
}

bool remove(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
    scope K key,
)
{
    if (map.capacity_ == 0)
        return false;
    const hash = map.hasher_(&key);
    const location = map.probe(&key, hash);
    if (!location.found)
        return false;

    Entry!(K, V)* entry = map.entries_ + location.index;
    destroyElement(&entry.value);
    destroyElement(&entry.key);
    map.states_[location.index] = SlotState.removed;
    --map.length_;
    ++map.removed_;
    if (map.length_ == 0)
    {
        memset(map.states_, SlotState.empty, map.capacity_);
        map.removed_ = 0;
    }
    return true;
}

void clear(K, V, Hasher, Equal)(ref HashMap!(K, V, Hasher, Equal) map)
{
    foreach (index; 0 .. map.capacity_)
    {
        if (map.states_[index] != SlotState.occupied)
            continue;
        destroyElement(&map.entries_[index].value);
        destroyElement(&map.entries_[index].key);
    }
    if (map.capacity_ != 0)
        memset(map.states_, SlotState.empty, map.capacity_);
    map.length_ = 0;
    map.removed_ = 0;
}

bool tryShrinkToFit(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
)
{
    if (map.length_ == 0)
    {
        map.resetAndRelease();
        return true;
    }
    size_t capacity;
    if (!capacityForLength(map.length_, &capacity))
        return false;
    if (capacity == map.capacity_ && map.removed_ == 0)
        return true;
    return map.tryRehash(capacity);
}

void shrinkToFit(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
)
{
    if (!map.tryShrinkToFit())
        panic("HashMap allocation failed");
}

void resetAndRelease(K, V, Hasher, Equal)(
    ref HashMap!(K, V, Hasher, Equal) map,
)
{
    map.clear();
    map.allocator_.deallocate(map.entries_, map.capacity_);
    map.allocator_.deallocate(map.states_, map.capacity_);
    map.entries_ = null;
    map.states_ = null;
    map.capacity_ = 0;
}

/// Mutable-value cursor. The key pointer is always const.
struct HashMapCursor(K, V)
{
nothrow @nogc:

    private const(SlotState)* states_;
    private Entry!(K, V)* entries_;
    private size_t capacity_;
    private size_t index_;

    private static HashMapCursor create(
        const(SlotState)* states,
        Entry!(K, V)* entries,
        size_t capacity,
    )
    {
        HashMapCursor result = HashMapCursor(states, entries, capacity, 0);
        result.skipEmpty();
        return result;
    }

    bool valid() const pure @safe
    {
        return index_ < capacity_;
    }

    const(K)* key() const return
    {
        require(valid, "invalid HashMap cursor");
        return &entries_[index_].key;
    }

    V* value() return
    {
        require(valid, "invalid HashMap cursor");
        return &entries_[index_].value;
    }

    void advance()
    {
        require(valid, "invalid HashMap cursor");
        ++index_;
        skipEmpty();
    }

    private void skipEmpty()
    {
        while (index_ < capacity_ && states_[index_] != SlotState.occupied)
            ++index_;
    }
}

/// Read-only cursor returned by a const map.
struct ConstHashMapCursor(K, V)
{
nothrow @nogc:

    private const(SlotState)* states_;
    private const(Entry!(K, V))* entries_;
    private size_t capacity_;
    private size_t index_;

    private static ConstHashMapCursor create(
        const(SlotState)* states,
        const(Entry!(K, V))* entries,
        size_t capacity,
    )
    {
        ConstHashMapCursor result = ConstHashMapCursor(
            states,
            entries,
            capacity,
            0,
        );
        result.skipEmpty();
        return result;
    }

    bool valid() const pure @safe
    {
        return index_ < capacity_;
    }

    const(K)* key() const return
    {
        require(valid, "invalid HashMap cursor");
        return &entries_[index_].key;
    }

    const(V)* value() const return
    {
        require(valid, "invalid HashMap cursor");
        return &entries_[index_].value;
    }

    void advance()
    {
        require(valid, "invalid HashMap cursor");
        ++index_;
        skipEmpty();
    }

    private void skipEmpty()
    {
        while (index_ < capacity_ && states_[index_] != SlotState.occupied)
            ++index_;
    }
}

struct HashMapPointerItem(K, V)
{
    const(K)* key;
    V* value;
}

struct ConstHashMapPointerItem(K, V)
{
    const(K)* key;
    const(V)* value;
}

/// Input range for pointer-oriented mutable-map iteration.
struct HashMapPointerRange(K, V)
{
    private HashMapCursor!(K, V) cursor_;

    bool empty() const pure @safe
    {
        return !cursor_.valid;
    }

    HashMapPointerItem!(K, V) front() return
    {
        return HashMapPointerItem!(K, V)(cursor_.key, cursor_.value);
    }

    void popFront()
    {
        cursor_.advance();
    }
}

/// Input range for pointer-oriented const-map iteration.
struct ConstHashMapPointerRange(K, V)
{
    private ConstHashMapCursor!(K, V) cursor_;

    bool empty() const pure @safe
    {
        return !cursor_.valid;
    }

    ConstHashMapPointerItem!(K, V) front() const return
    {
        return ConstHashMapPointerItem!(K, V)(cursor_.key, cursor_.value);
    }

    void popFront()
    {
        cursor_.advance();
    }
}

private struct SetMarker
{
}

/// Allocator-owned set sharing the same probing and lifetime semantics as
/// `HashMap`. Stored values are exposed only as const pointers.
struct HashSet(K, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
nothrow @nogc:

    private HashMap!(K, SetMarker, Hasher, Equal) map_;

    @disable this(this);

    static HashSet create(Allocator* allocator)
    {
        HashSet result;
        result.map_ = typeof(result.map_).create(allocator);
        return result;
    }

    static HashSet seeded(Dummy = void)(Allocator* allocator, HashSeed seed)
    {
        static assert(is(Hasher == DefaultHash!K) &&
                is(Equal == DefaultEqual!K),
            "seeded is available only with the default hash policies");
        HashSet result;
        result.map_ = typeof(result.map_).seeded(allocator, seed);
        return result;
    }

    static HashSet withPolicies(
        Allocator* allocator,
        Hasher hasher,
        Equal equal,
    )
    {
        HashSet result;
        result.map_ = typeof(result.map_).withPolicies(
            allocator,
            hasher,
            equal,
        );
        return result;
    }

    static HashSet withCapacity(Dummy = void)(
        Allocator* allocator,
        size_t requested,
        HashSeed seed = HashSeed.init,
    )
    {
        HashSet result = seeded(allocator, seed);
        result.reserve(requested);
        return result;
    }

    void deinit()
    {
        map_.deinit();
    }

    size_t length() const pure @safe
    {
        return map_.length;
    }

    size_t capacity() const pure @safe
    {
        return map_.capacity;
    }

    bool empty() const pure @safe
    {
        return map_.empty;
    }

    Allocator* allocator() return
    {
        return map_.allocator;
    }

    HashSetCursor!K cursor() return
    {
        return HashSetCursor!K(map_.cursor());
    }

    ConstHashSetCursor!K cursor() const return
    {
        return ConstHashSetCursor!K(map_.cursor());
    }

    /// Returns an input range of const pointers to set elements.
    HashSetPointerRange!K pointerItems() return
    {
        return HashSetPointerRange!K(cursor());
    }

    /// Returns the pointer range for a const set.
    ConstHashSetPointerRange!K pointerItems() const return
    {
        return ConstHashSetPointerRange!K(cursor());
    }

    /// Supports `foreach (ref const value; set)`. Set elements are immutable
    /// because changing one in place would invalidate its probe position.
    int opApply(
        scope int delegate(ref const(K)) nothrow @nogc callback,
    )
    {
        foreach (index; 0 .. map_.capacity_)
        {
            if (map_.states_[index] != SlotState.occupied)
                continue;
            const result = callback(map_.entries_[index].key);
            if (result != 0)
                return result;
        }
        return 0;
    }

    /// Supports the same read-only iteration through a const set.
    int opApply(
        scope int delegate(ref const(K)) nothrow @nogc callback,
    ) const
    {
        foreach (index; 0 .. map_.capacity_)
        {
            if (map_.states_[index] != SlotState.occupied)
                continue;
            const result = callback(map_.entries_[index].key);
            if (result != 0)
                return result;
        }
        return 0;
    }
}

AddStatus tryAdd(K, Hasher, Equal)(
    ref HashSet!(K, Hasher, Equal) set,
    K value,
)
{
    return set.map_.tryAdd(move(value), SetMarker.init);
}

bool add(K, Hasher, Equal)(
    ref HashSet!(K, Hasher, Equal) set,
    K value,
)
{
    return set.map_.add(move(value), SetMarker.init);
}

bool contains(K, Hasher, Equal)(
    ref const HashSet!(K, Hasher, Equal) set,
    scope K value,
)
{
    return set.map_.contains(value);
}

bool remove(K, Hasher, Equal)(
    ref HashSet!(K, Hasher, Equal) set,
    scope K value,
)
{
    return set.map_.remove(value);
}

bool tryReserve(K, Hasher, Equal)(
    ref HashSet!(K, Hasher, Equal) set,
    size_t requested,
)
{
    return set.map_.tryReserve(requested);
}

void reserve(K, Hasher, Equal)(
    ref HashSet!(K, Hasher, Equal) set,
    size_t requested,
)
{
    set.map_.reserve(requested);
}

void clear(K, Hasher, Equal)(ref HashSet!(K, Hasher, Equal) set)
{
    set.map_.clear();
}

bool tryShrinkToFit(K, Hasher, Equal)(ref HashSet!(K, Hasher, Equal) set)
{
    return set.map_.tryShrinkToFit();
}

void shrinkToFit(K, Hasher, Equal)(ref HashSet!(K, Hasher, Equal) set)
{
    set.map_.shrinkToFit();
}

void resetAndRelease(K, Hasher, Equal)(ref HashSet!(K, Hasher, Equal) set)
{
    set.map_.resetAndRelease();
}

struct HashSetCursor(K)
{
    private HashMapCursor!(K, SetMarker) cursor_;

    bool valid() const pure @safe
    {
        return cursor_.valid;
    }

    const(K)* value() const return
    {
        return cursor_.key;
    }

    void advance()
    {
        cursor_.advance();
    }
}

struct ConstHashSetCursor(K)
{
    private ConstHashMapCursor!(K, SetMarker) cursor_;

    bool valid() const pure @safe
    {
        return cursor_.valid;
    }

    const(K)* value() const return
    {
        return cursor_.key;
    }

    void advance()
    {
        cursor_.advance();
    }
}

struct HashSetPointerRange(K)
{
    private HashSetCursor!K cursor_;

    bool empty() const pure @safe
    {
        return !cursor_.valid;
    }

    const(K)* front() const return
    {
        return cursor_.value;
    }

    void popFront()
    {
        cursor_.advance();
    }
}

struct ConstHashSetPointerRange(K)
{
    private ConstHashSetCursor!K cursor_;

    bool empty() const pure @safe
    {
        return !cursor_.valid;
    }

    const(K)* front() const return
    {
        return cursor_.value;
    }

    void popFront()
    {
        cursor_.advance();
    }
}

unittest
{
    import xtb.core.memory : mallocAllocator;
    import xtb.core.types : String;

    HashMap!(String, int) counts = HashMap!(String, int).create(
        mallocAllocator(),
    );
    assert(counts.empty);
    assert(counts.find("missing") is null);
    assert(counts.trySet("one", 1) == SetStatus.inserted);
    assert(counts.set("two", 2));
    assert(!counts.set("two", 22));
    assert(*counts.find("two") == 22);
    assert(counts.tryAdd("two", 222) == AddStatus.alreadyPresent);
    assert(counts.add("three", 3));
    assert(counts.contains("one"));
    assert(!counts.contains("four"));

    size_t visited;
    long total;
    for (auto cursor = counts.cursor(); cursor.valid; cursor.advance())
    {
        ++visited;
        total += *cursor.value;
        *cursor.value += 1;
    }
    assert(visited == counts.length);
    assert(total != 0);
    assert(*counts.find("one") == 2);

    size_t foreachVisited;
    foreach (ref const key, ref value; counts)
    {
        assert(key.length != 0);
        value += 10;
        ++foreachVisited;
    }
    assert(foreachVisited == counts.length);
    assert(*counts.find("one") == 12);

    size_t pointerVisited;
    foreach (item; counts.pointerItems)
    {
        assert(item.key !is null && item.value !is null);
        *item.value += 100;
        ++pointerVisited;
    }
    assert(pointerVisited == counts.length);
    assert(*counts.find("one") == 112);
    size_t breakVisited;
    foreach (ref const key, ref value; counts)
    {
        assert(key.length != 0 && value >= 100);
        ++breakVisited;
        break;
    }
    assert(breakVisited == 1);

    const(HashMap!(String, int))* readOnlyCounts = &counts;
    auto readOnlyCursor = (*readOnlyCounts).cursor();
    static assert(is(typeof(readOnlyCursor.value()) == const(int)*));
    assert(readOnlyCursor.valid);
    size_t constVisited;
    foreach (ref const key, ref const value; *readOnlyCounts)
    {
        assert(key.length != 0 && value >= 10);
        ++constVisited;
    }
    assert(constVisited == counts.length);
    size_t constPointerVisited;
    foreach (item; (*readOnlyCounts).pointerItems)
    {
        static assert(is(typeof(item.value) == const(int)*));
        assert(item.key !is null && item.value !is null);
        ++constPointerVisited;
    }
    assert(constPointerVisited == counts.length);

    assert(counts.remove("two"));
    assert(!counts.remove("two"));
    assert(!counts.contains("two"));
    counts.reserve(400);
    assert(counts.capacity >= 400);
    counts.shrinkToFit();
    assert(counts.capacity >= counts.length);
    counts.clear();
    assert(counts.empty && counts.capacity != 0);
    counts.resetAndRelease();
    assert(counts.capacity == 0);

    HashMap!(int, int) numbers = HashMap!(int, int).create(mallocAllocator());
    foreach (value; 0 .. 256)
        assert(numbers.set(value, value * 2));
    foreach (value; 0 .. 256)
        assert(*numbers.find(value) == value * 2);

    HashMap!(int, int) preallocated = HashMap!(int, int).withCapacity(
        mallocAllocator(),
        32,
    );
    assert(preallocated.capacity >= 32);

    int first;
    int second;
    HashMap!(int*, int) pointers = HashMap!(int*, int).create(
        mallocAllocator(),
    );
    pointers.set(&first, 1);
    pointers.set(&second, 2);
    assert(*pointers.find(&first) == 1);
    assert(*pointers.find(&second) == 2);
}

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        mallocAllocator;

    alias CollisionMap = HashMap!(int, int, ConstantIntHash, DefaultEqual!int);
    CollisionMap collisions = CollisionMap.create(mallocAllocator());
    foreach (value; 0 .. 128)
        assert(collisions.add(value, value * 3));
    foreach (value; 0 .. 128)
        assert(*collisions.find(value) == value * 3);
    foreach (value; 0 .. 128)
        if ((value & 1) == 0)
            assert(collisions.remove(value));
    foreach (value; 128 .. 192)
        assert(collisions.add(value, value * 3));
    foreach (value; 1 .. 128)
        if ((value & 1) != 0)
            assert(*collisions.find(value) == value * 3);

    AllocationRecord[16] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    CollisionMap failing = CollisionMap.create(allocator.handle);
    allocator.failAfter(0);
    assert(failing.tryAdd(1, 10) == AddStatus.outOfMemory);
    assert(failing.empty && allocator.clean);

    allocator.failAfter(1);
    assert(failing.tryAdd(1, 10) == AddStatus.outOfMemory);
    assert(failing.empty && allocator.clean);

    allocator.allowAllocations();
    foreach (value; 0 .. 7)
        assert(failing.add(value, value));
    const previousCapacity = failing.capacity;
    allocator.failAfter(0);
    assert(failing.tryAdd(7, 7) == AddStatus.outOfMemory);
    assert(failing.length == 7 && failing.capacity == previousCapacity);
    assert(failing.trySet(1, 11) == SetStatus.replaced);
    assert(*failing.find(1) == 11);
    assert(!failing.tryReserve(size_t.max));
    assert(failing.remove(0));
    assert(!failing.tryShrinkToFit());
    assert(failing.length == 6 && failing.capacity == previousCapacity);
    foreach (value; 1 .. 7)
        assert(*failing.find(value) == (value == 1 ? 11 : value));
    failing.deinit();
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
}

unittest
{
    import xtb.core.memory : mallocAllocator;

    int destructions;
    {
        HashMap!(int, TrackedHashValue) values =
            HashMap!(int, TrackedHashValue).create(mallocAllocator());
        assert(values.add(1, TrackedHashValue(&destructions, 10, true)));
        assert(values.add(2, TrackedHashValue(&destructions, 20, true)));
        assert(!values.set(1, TrackedHashValue(&destructions, 11, true)));
        assert(destructions == 1);
        assert(values.find(1).value == 11);
        assert(values.remove(2));
        assert(destructions == 2);
        values.clear();
        assert(destructions == 3);
    }
    assert(destructions == 3);

    int liveKeys;
    {
        alias TrackedMap = HashMap!(
            TrackedHashKey,
            int,
            TrackedKeyHash,
            TrackedKeyEqual,
        );
        TrackedMap trackedKeys = TrackedMap.create(mallocAllocator());
        foreach (value; 0 .. 32)
            trackedKeys.add(TrackedHashKey(value, &liveKeys), value);
        assert(liveKeys == 32);
        TrackedHashKey key = TrackedHashKey(7, &liveKeys);
        assert(trackedKeys.remove(key));
        assert(!trackedKeys.contains(key));
        trackedKeys.clear();
    }
    assert(liveKeys == 0);

    HashSet!int values = HashSet!int.seeded(
        mallocAllocator(),
        HashSeed.fromValue(123),
    );
    assert(values.add(3));
    assert(!values.add(3));
    assert(values.tryAdd(7) == AddStatus.inserted);
    assert(values.contains(3) && values.contains(7));
    size_t visited;
    for (auto cursor = values.cursor(); cursor.valid; cursor.advance())
    {
        assert(*cursor.value == 3 || *cursor.value == 7);
        ++visited;
    }
    assert(visited == 2);
    size_t foreachVisited;
    foreach (ref const value; values)
    {
        assert(value == 3 || value == 7);
        ++foreachVisited;
    }
    assert(foreachVisited == values.length);
    size_t pointerVisited;
    foreach (value; values.pointerItems)
    {
        assert(value !is null && (*value == 3 || *value == 7));
        ++pointerVisited;
    }
    assert(pointerVisited == values.length);
    const(HashSet!int)* readOnlyValues = &values;
    size_t constSetVisited;
    foreach (ref const value; *readOnlyValues)
    {
        assert(value == 3 || value == 7);
        ++constSetVisited;
    }
    foreach (value; (*readOnlyValues).pointerItems)
        assert(value !is null && (*value == 3 || *value == 7));
    assert(constSetVisited == values.length);
    assert(values.remove(3));
    assert(!values.contains(3));
    values.shrinkToFit();
    values.resetAndRelease();
    assert(values.empty && values.capacity == 0);

    HashSet!int preallocated = HashSet!int.withCapacity(
        mallocAllocator(),
        48,
    );
    assert(preallocated.capacity >= 48);

    static assert(!__traits(compiles,
            (ref HashMap!(int, int) map) { HashMap!(int, int) copy = map; }));
    static assert(!__traits(compiles,
            (ref HashSet!int set) { HashSet!int copy = set; }));
}
