module xtb.core.hash_map;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.lifetime : move, moveEmplace;
import core.stdc.string : memset;
import xtb.core.hash : HashSeed, hashValue;
import xtb.core.memory : Allocator, deallocate, tryAllocate, tryAllocateZeroed;
import xtb.core.numeric : multiplyOverflows;
import xtb.core.panic : panic;
version (XTB_Checked)
    import xtb.core.panic : require;
import xtb.core.released_storage : ReleasedStorage;

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

package(xtb) enum PrepareInsertStatus
{
    ready,
    alreadyPresent,
    outOfMemory,
}

/// Package-private token proving that a concrete insertion slot has been
/// prepared and that committing the entry cannot allocate.
package(xtb) struct PreparedHashMapInsert
{
private:
    void* entriesIdentity_;
    size_t capacityIdentity_;
    size_t index_;
    size_t hash_;
    bool reusedRemoved_;
    bool found_;
}

/// Default allocator-aware element lifetime policy used by `HashMapUnmanaged`.
struct DefaultHashMapElementOps(T)
{
    static void destroy(Allocator*, T* element)
    {
        static if (hasElaborateDestructor!T)
            object.destroy!false(*element);
    }
}

private template IsDefaultHashPolicy(Hasher, K)
{
    static if (is(Hasher == DefaultHash!U, U))
        enum IsDefaultHashPolicy = is(U == K);
    else
        enum IsDefaultHashPolicy = false;
}

private template IsDefaultEqualPolicy(Equal, K)
{
    static if (is(Equal == DefaultEqual!U, U))
        enum IsDefaultEqualPolicy = is(U == K);
    else
        enum IsDefaultEqualPolicy = false;
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

    private struct ParityHash
    {
        bool parity;

        size_t opCall(scope const(int)* key) const pure nothrow @safe @nogc
        {
            return parity ? cast(size_t) (*key & 1) : cast(size_t) *key;
        }
    }

    private struct ParityEqual
    {
        bool parity;

        bool opCall(
            scope const(int)* left,
            scope const(int)* right,
        ) const pure nothrow @safe @nogc
        {
            return parity ? ((*left & 1) == (*right & 1)) : *left == *right;
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
struct HashMapUnmanaged(
    K,
    V,
    Hasher = DefaultHash!K,
    Equal = DefaultEqual!K,
    Lookup = K,
    KeyOps = DefaultHashMapElementOps!K,
    ValueOps = DefaultHashMapElementOps!V,
)
{
nothrow @nogc:

    static assert(__traits(isCopyable, Hasher) &&
            !hasElaborateDestructor!Hasher,
        "HashMap hash policies must be copyable and have no destructor");
    static assert(__traits(isCopyable, Equal) &&
            !hasElaborateDestructor!Equal,
        "HashMap equality policies must be copyable and have no destructor");
    static assert(__traits(compiles,
            KeyOps.destroy(cast(Allocator*) null, cast(K*) null)),
        "HashMap key lifetime policy must provide destroy(Allocator*, K*)");
    static assert(__traits(compiles,
            ValueOps.destroy(cast(Allocator*) null, cast(V*) null)),
        "HashMap value lifetime policy must provide destroy(Allocator*, V*)");

private:
    SlotState* states_;
    Entry!(K, V)* entries_;
    size_t length_;
    size_t removed_;
    size_t capacity_;
    Hasher hasher_;
    Equal equal_;

public:
    @disable this(this);

    static HashMapUnmanaged withPolicies(
        Hasher hasher,
        Equal equal,
    )
    {
        HashMapUnmanaged result;
        result.hasher_ = move(hasher);
        result.equal_ = move(equal);
        return result;
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t requested,
        scope HashMapUnmanaged* output,
    )
    {
        version (XTB_Checked)
        {
            require(output !is null,
                "HashMapUnmanaged output pointer is null");
            require(output.states_ is null && output.entries_ is null &&
                    output.length_ == 0 && output.removed_ == 0 &&
                    output.capacity_ == 0,
                "HashMapUnmanaged output is not empty");
        }
        HashMapUnmanaged temporary;
        if (!temporary.tryReserve(allocator, requested))
            return false;
        *output = move(temporary);
        return true;
    }

    static HashMapUnmanaged withCapacity(
        Allocator* allocator,
        size_t requested,
    )
    {
        HashMapUnmanaged result;
        if (!tryWithCapacity(allocator, requested, &result))
            panic("HashMap allocation failed");
        return result;
    }

    static if (IsDefaultHashPolicy!(Hasher, K) &&
            IsDefaultEqualPolicy!(Equal, K))
    {
        static HashMapUnmanaged seeded(HashSeed seed)
        {
            Hasher hasher;
            hasher.seed = seed;
            return withPolicies(hasher, Equal.init);
        }

        static HashMapUnmanaged withCapacity(
            Allocator* allocator,
            size_t requested,
            HashSeed seed,
        )
        {
            HashMapUnmanaged result = seeded(seed);
            result.reserve(allocator, requested);
            return result;
        }
    }

    void deinit(Allocator* allocator)
    {
        if (capacity_ != 0)
            requireValidHashAllocator(allocator);
        clear(allocator);
        if (capacity_ != 0)
        {
            allocator.deallocate(entries_, capacity_);
            allocator.deallocate(states_, capacity_);
        }
        this = HashMapUnmanaged.init;
    }

    void resetAndRelease(Allocator* allocator)
    {
        if (capacity_ != 0)
            requireValidHashAllocator(allocator);
        clear(allocator);
        if (capacity_ != 0)
        {
            allocator.deallocate(entries_, capacity_);
            allocator.deallocate(states_, capacity_);
        }
        entries_ = null;
        states_ = null;
        capacity_ = 0;
        length_ = 0;
        removed_ = 0;
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

    HashMapPointerRange!(K, V) pointerItems() return
    {
        return HashMapPointerRange!(K, V)(cursor());
    }

    ConstHashMapPointerRange!(K, V) pointerItems() const return
    {
        return ConstHashMapPointerRange!(K, V)(cursor());
    }

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

    bool tryReserve(Allocator* allocator, size_t requested)
    {
        requireValidHashAllocator(allocator);
        size_t capacity;
        if (!capacityForLength(requested, &capacity))
            return false;
        if (capacity <= capacity_)
            return true;
        return tryRehash(allocator, capacity);
    }

    void reserve(Allocator* allocator, size_t requested)
    {
        if (!tryReserve(allocator, requested))
            panic("HashMap allocation failed");
    }

    static if (__traits(isCopyable, K))
    {
        SetStatus trySet(Allocator* allocator, K key, V value)
        {
            requireValidHashAllocator(allocator);
            const hash = hasher_(&key);
            ProbeResult location = probeStored(&key, hash);
            if (location.found)
            {
                replaceHashElement!ValueOps(
                    allocator,
                    &entries_[location.index].value,
                    value,
                );
                return SetStatus.replaced;
            }
            if (!tryPrepareInsert(allocator))
                return SetStatus.outOfMemory;

            location = probeStored(&key, hash);
            Entry!(K, V)* destination = entries_ + location.index;
            const reusedRemoved = states_[location.index] == SlotState.removed;
            destination.hash = hash;
            constructHashMove(&destination.key, key);
            constructHashMove(&destination.value, value);
            states_[location.index] = SlotState.occupied;
            ++length_;
            if (reusedRemoved)
                --removed_;
            return SetStatus.inserted;
        }

        bool set(Allocator* allocator, K key, V value)
        {
            const status = trySet(allocator, move(key), move(value));
            if (status == SetStatus.outOfMemory)
                panic("HashMap allocation failed");
            return status == SetStatus.inserted;
        }

        AddStatus tryAdd(Allocator* allocator, K key, V value)
        {
            requireValidHashAllocator(allocator);
            const hash = hasher_(&key);
            ProbeResult location = probeStored(&key, hash);
            if (location.found)
                return AddStatus.alreadyPresent;
            if (!tryPrepareInsert(allocator))
                return AddStatus.outOfMemory;

            location = probeStored(&key, hash);
            Entry!(K, V)* destination = entries_ + location.index;
            const reusedRemoved = states_[location.index] == SlotState.removed;
            destination.hash = hash;
            constructHashMove(&destination.key, key);
            constructHashMove(&destination.value, value);
            states_[location.index] = SlotState.occupied;
            ++length_;
            if (reusedRemoved)
                --removed_;
            return AddStatus.inserted;
        }

        bool add(Allocator* allocator, K key, V value)
        {
            const status = tryAdd(allocator, move(key), move(value));
            if (status == AddStatus.outOfMemory)
                panic("HashMap allocation failed");
            return status == AddStatus.inserted;
        }
    }

    V* find(scope Lookup key) return
    {
        if (capacity_ == 0)
            return null;
        const hash = hasher_(&key);
        const location = probeLookup(&key, hash);
        return location.found ? &entries_[location.index].value : null;
    }

    const(V)* find(scope Lookup key) const return
    {
        if (capacity_ == 0)
            return null;
        const hash = hasher_(&key);
        const location = probeLookup(&key, hash);
        return location.found ? &entries_[location.index].value : null;
    }

    bool contains(scope Lookup key) const
    {
        return find(key) !is null;
    }

    bool remove(Allocator* allocator, scope Lookup key)
    {
        if (capacity_ == 0)
            return false;
        requireValidHashAllocator(allocator);
        const hash = hasher_(&key);
        const location = probeLookup(&key, hash);
        if (!location.found)
            return false;

        Entry!(K, V)* entry = entries_ + location.index;
        ValueOps.destroy(allocator, &entry.value);
        KeyOps.destroy(allocator, &entry.key);
        states_[location.index] = SlotState.removed;
        --length_;
        ++removed_;
        if (length_ == 0)
        {
            memset(states_, SlotState.empty, capacity_);
            removed_ = 0;
        }
        return true;
    }

    void clear(Allocator* allocator)
    {
        if (length_ != 0)
            requireValidHashAllocator(allocator);
        foreach (index; 0 .. capacity_)
        {
            if (states_[index] != SlotState.occupied)
                continue;
            ValueOps.destroy(allocator, &entries_[index].value);
            KeyOps.destroy(allocator, &entries_[index].key);
        }
        if (capacity_ != 0)
            memset(states_, SlotState.empty, capacity_);
        length_ = 0;
        removed_ = 0;
    }

    bool tryShrinkToFit(Allocator* allocator)
    {
        requireValidHashAllocator(allocator);
        if (length_ == 0)
        {
            resetAndRelease(allocator);
            return true;
        }
        size_t capacity;
        if (!capacityForLength(length_, &capacity))
            return false;
        if (capacity == capacity_ && removed_ == 0)
            return true;
        return tryRehash(allocator, capacity);
    }

    void shrinkToFit(Allocator* allocator)
    {
        if (!tryShrinkToFit(allocator))
            panic("HashMap allocation failed");
    }

package(xtb):
    PrepareInsertStatus prepareInsert(
        Allocator* allocator,
        scope Lookup key,
        scope PreparedHashMapInsert* prepared,
    )
    {
        requireValidHashAllocator(allocator);
        version (XTB_Checked)
        {
            require(prepared !is null,
                "prepared HashMap insertion output pointer is null");
            require(prepared.entriesIdentity_ is null &&
                    prepared.capacityIdentity_ == 0,
                "prepared HashMap insertion output is not empty");
        }

        const hash = hasher_(&key);
        ProbeResult location = probeLookup(&key, hash);
        if (location.found)
        {
            prepared.entriesIdentity_ = entries_;
            prepared.capacityIdentity_ = capacity_;
            prepared.index_ = location.index;
            prepared.hash_ = hash;
            prepared.found_ = true;
            return PrepareInsertStatus.alreadyPresent;
        }

        if (!tryPrepareInsert(allocator))
            return PrepareInsertStatus.outOfMemory;

        location = probeLookup(&key, hash);
        version (XTB_Checked)
            require(!location.found,
                "HashMap changed during prepared insertion");
        prepared.entriesIdentity_ = entries_;
        prepared.capacityIdentity_ = capacity_;
        prepared.index_ = location.index;
        prepared.hash_ = hash;
        prepared.reusedRemoved_ =
            states_[location.index] == SlotState.removed;
        return PrepareInsertStatus.ready;
    }

    void commitPreparedInsert(
        scope PreparedHashMapInsert* prepared,
        scope K* key,
        scope V* value,
    ) @system
    {
        version (XTB_Checked)
        {
            require(prepared !is null,
                "prepared HashMap insertion pointer is null");
            require(key !is null, "HashMap insertion key pointer is null");
            require(value !is null, "HashMap insertion value pointer is null");
            require(!prepared.found_,
                "cannot commit an already-present HashMap insertion");
            require(prepared.entriesIdentity_ is entries_ &&
                    prepared.capacityIdentity_ == capacity_ &&
                    prepared.index_ < capacity_,
                "stale prepared HashMap insertion");
            require(states_[prepared.index_] != SlotState.occupied,
                "prepared HashMap insertion slot is occupied");
        }

        Entry!(K, V)* destination = entries_ + prepared.index_;
        destination.hash = prepared.hash_;
        constructHashMove(&destination.key, *key);
        constructHashMove(&destination.value, *value);
        states_[prepared.index_] = SlotState.occupied;
        ++length_;
        if (prepared.reusedRemoved_)
            --removed_;
        *prepared = PreparedHashMapInsert.init;
    }

    void replacePreparedValue(
        Allocator* allocator,
        scope PreparedHashMapInsert* prepared,
        scope V* value,
    ) @system
    {
        requireValidHashAllocator(allocator);
        version (XTB_Checked)
        {
            require(prepared !is null,
                "prepared HashMap insertion pointer is null");
            require(value !is null, "HashMap replacement value pointer is null");
            require(prepared.found_,
                "cannot replace through an absent HashMap insertion");
            require(prepared.entriesIdentity_ is entries_ &&
                    prepared.capacityIdentity_ == capacity_ &&
                    prepared.index_ < capacity_ &&
                    states_[prepared.index_] == SlotState.occupied,
                "stale prepared HashMap replacement");
        }

        replaceHashElement!ValueOps(
            allocator,
            &entries_[prepared.index_].value,
            *value,
        );
        *prepared = PreparedHashMapInsert.init;
    }

private:
    ProbeResult probeStored(scope const(K)* key, size_t hash) const
    {
        if (capacity_ == 0)
            return ProbeResult.init;

        const mask = capacity_ - 1;
        size_t index = hash & mask;
        size_t firstRemoved = size_t.max;
        for (;;)
        {
            final switch (states_[index])
            {
                case SlotState.empty:
                    return ProbeResult(
                        firstRemoved == size_t.max ? index : firstRemoved,
                        false,
                    );
                case SlotState.occupied:
                    if (entries_[index].hash == hash &&
                        equal_(&entries_[index].key, key))
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

    ProbeResult probeLookup(scope const(Lookup)* key, size_t hash) const
    {
        if (capacity_ == 0)
            return ProbeResult.init;

        const mask = capacity_ - 1;
        size_t index = hash & mask;
        size_t firstRemoved = size_t.max;
        for (;;)
        {
            final switch (states_[index])
            {
                case SlotState.empty:
                    return ProbeResult(
                        firstRemoved == size_t.max ? index : firstRemoved,
                        false,
                    );
                case SlotState.occupied:
                    if (entries_[index].hash == hash &&
                        equal_(&entries_[index].key, key))
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

    bool tryRehash(Allocator* allocator, size_t capacity)
    {
        version (XTB_Checked)
            require(capacity >= 8 && (capacity & (capacity - 1)) == 0,
                "invalid HashMap capacity");
        if (multiplyOverflows(Entry!(K, V).sizeof, capacity))
            return false;

        SlotState* states = cast(SlotState*) allocator
            .tryAllocateZeroed!ubyte(capacity);
        if (states is null)
            return false;
        Entry!(K, V)* entries = allocator
            .tryAllocate!(Entry!(K, V))(capacity);
        if (entries is null)
        {
            allocator.deallocate(states, capacity);
            return false;
        }

        foreach (index; 0 .. capacity_)
        {
            if (states_[index] != SlotState.occupied)
                continue;
            Entry!(K, V)* source = entries_ + index;
            const destinationIndex = emptyHashIndex(
                states,
                capacity,
                source.hash,
            );
            Entry!(K, V)* destination = entries + destinationIndex;
            destination.hash = source.hash;
            constructHashMove(&destination.key, source.key);
            constructHashMove(&destination.value, source.value);
            states[destinationIndex] = SlotState.occupied;
        }

        if (capacity_ != 0)
        {
            allocator.deallocate(entries_, capacity_);
            allocator.deallocate(states_, capacity_);
        }
        entries_ = entries;
        states_ = states;
        capacity_ = capacity;
        removed_ = 0;
        return true;
    }

    bool tryPrepareInsert(Allocator* allocator)
    {
        if (capacity_ == 0)
            return tryRehash(allocator, 8);
        if (length_ + removed_ < maximumHashLength(capacity_))
            return true;
        if (length_ < maximumHashLength(capacity_))
            return tryRehash(allocator, capacity_);
        if (capacity_ > size_t.max / 2)
            return false;
        return tryRehash(allocator, capacity_ * 2);
    }
}

struct HashMap(K, V, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
nothrow @nogc:

    static assert(__traits(isCopyable, K),
        "HashMap keys must be copyable; use StringHashMap for owned string keys");

    alias Self = HashMap!(K, V, Hasher, Equal);
    alias Storage = HashMapUnmanaged!(K, V, Hasher, Equal);
    alias Released = ReleasedStorage!Storage;

private:
    Allocator* allocator_;
    Storage storage_;

version (XTB_Checked)
{
    invariant
    {
        require(&this !is null, "HashMap pointer is null");
    }
}

public:
    @disable this(this);

    static Self create(Allocator* allocator) @trusted
    {
        requireValidHashAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    static Self withPolicies(
        Allocator* allocator,
        Hasher hasher,
        Equal equal,
    ) @trusted
    {
        requireValidHashAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        result.storage_ = Storage.withPolicies(move(hasher), move(equal));
        return move(result);
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t requested,
        scope Self* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "HashMap output pointer is null");
            require(output.allocator_ is null,
                "HashMap output is already initialized");
        }
        Storage storage;
        if (!Storage.tryWithCapacity(allocator, requested, &storage))
            return false;
        output.allocator_ = allocator;
        output.storage_ = move(storage);
        return true;
    }

    static Self withCapacity(
        Allocator* allocator,
        size_t requested,
    ) @trusted
    {
        Self result;
        if (!tryWithCapacity(allocator, requested, &result))
            panic("HashMap allocation failed");
        return move(result);
    }

    static if (IsDefaultHashPolicy!(Hasher, K) &&
            IsDefaultEqualPolicy!(Equal, K))
    {
        static Self seeded(Allocator* allocator, HashSeed seed) @trusted
        {
            requireValidHashAllocator(allocator);
            Self result;
            result.allocator_ = allocator;
            result.storage_ = Storage.seeded(seed);
            return move(result);
        }

        static Self withCapacity(
            Allocator* allocator,
            size_t requested,
            HashSeed seed,
        ) @trusted
        {
            Self result;
            result.allocator_ = allocator;
            result.storage_ = Storage.withCapacity(
                allocator,
                requested,
                seed,
            );
            return move(result);
        }
    }

    static Self adopt(scope Released* released) @trusted
    {
        version (XTB_Checked)
            require(released !is null,
                "released HashMap storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(storage);
        return move(result);
    }

    ~this() @trusted
    {
        this.deinit();
    }

    void deinit() @trusted
    {
        if (allocator_ is null)
            return;
        storage_.deinit(allocator_);
        allocator_ = null;
    }

    void resetAndRelease() @trusted
    {
        storage_.resetAndRelease(allocator_);
    }

    Released release() @trusted
    {
        auto result = Released.fromOwnedParts(allocator_, &storage_);
        allocator_ = null;
        return move(result);
    }

    size_t length() const pure @trusted
    {
        return storage_.length;
    }

    size_t capacity() const pure @trusted
    {
        return storage_.capacity;
    }

    bool empty() const pure @trusted
    {
        return storage_.empty;
    }

    HashMapCursor!(K, V) cursor() return @trusted
    {
        return storage_.cursor();
    }

    ConstHashMapCursor!(K, V) cursor() const return @trusted
    {
        return storage_.cursor();
    }

    HashMapPointerRange!(K, V) pointerItems() return @trusted
    {
        return storage_.pointerItems();
    }

    ConstHashMapPointerRange!(K, V) pointerItems() const return @trusted
    {
        return storage_.pointerItems();
    }

    bool tryReserve(size_t requested) @trusted
    {
        return storage_.tryReserve(allocator_, requested);
    }

    void reserve(size_t requested) @trusted
    {
        storage_.reserve(allocator_, requested);
    }

    SetStatus trySet(K key, V value) @trusted
    {
        return storage_.trySet(allocator_, move(key), move(value));
    }

    bool set(K key, V value) @trusted
    {
        return storage_.set(allocator_, move(key), move(value));
    }

    AddStatus tryAdd(K key, V value) @trusted
    {
        return storage_.tryAdd(allocator_, move(key), move(value));
    }

    bool add(K key, V value) @trusted
    {
        return storage_.add(allocator_, move(key), move(value));
    }

    V* find(scope K key) return @trusted
    {
        return storage_.find(key);
    }

    const(V)* find(scope K key) const return @trusted
    {
        return storage_.find(key);
    }

    bool contains(scope K key) const @trusted
    {
        return storage_.contains(key);
    }

    bool remove(scope K key) @trusted
    {
        return storage_.remove(allocator_, key);
    }

    void clear() @trusted
    {
        storage_.clear(allocator_);
    }

    bool tryShrinkToFit() @trusted
    {
        return storage_.tryShrinkToFit(allocator_);
    }

    void shrinkToFit() @trusted
    {
        storage_.shrinkToFit(allocator_);
    }

    // Foreach is a D language hook.
    int opApply(
        scope int delegate(ref const(K), ref V) nothrow @nogc callback,
    )
    {
        return storage_.opApply(callback);
    }

    int opApply(
        scope int delegate(ref const(K), ref const(V)) nothrow @nogc callback,
    ) const
    {
        return storage_.opApply(callback);
    }

    Allocator* allocator() return pure @safe
    {
        return allocator_;
    }

package(xtb):
    static Self adoptUnmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        requireValidHashAllocator(allocator);
        version (XTB_Checked)
            require(storage !is null,
                "HashMapUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(*storage);
        return move(result);
    }
}


private void requireValidHashAllocator(Allocator* allocator) @trusted
{
    version (XTB_Checked)
        require(allocator !is null && *allocator !is null,
            "HashMap requires a valid allocator");
}

private void constructHashMove(T)(T* destination, ref T source)
{
    static if (__traits(isPOD, T))
        *destination = source;
    else
        moveEmplace(source, *destination);
}

private void replaceHashElement(alias Ops, T)(
    Allocator* allocator,
    T* destination,
    ref T source,
)
{
    Ops.destroy(allocator, destination);
    constructHashMove(destination, source);
}

private size_t maximumHashLength(size_t capacity) pure @safe
{
    return capacity - capacity / 8;
}

private bool capacityForLength(size_t requested, size_t* output)
{
    version (XTB_Checked)
        require(output !is null, "HashMap capacity output pointer is null");
    if (requested == 0)
    {
        *output = 0;
        return true;
    }

    size_t capacity = 8;
    while (maximumHashLength(capacity) < requested)
    {
        if (capacity > size_t.max / 2)
            return false;
        capacity *= 2;
    }
    *output = capacity;
    return true;
}

private size_t emptyHashIndex(
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
        version (XTB_Checked)
            require(valid, "invalid HashMap cursor");
        return &entries_[index_].key;
    }

    V* value() return
    {
        version (XTB_Checked)
            require(valid, "invalid HashMap cursor");
        return &entries_[index_].value;
    }

    void advance()
    {
        version (XTB_Checked)
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
        version (XTB_Checked)
            require(valid, "invalid HashMap cursor");
        return &entries_[index_].key;
    }

    const(V)* value() const return
    {
        version (XTB_Checked)
            require(valid, "invalid HashMap cursor");
        return &entries_[index_].value;
    }

    void advance()
    {
        version (XTB_Checked)
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
struct HashSetUnmanaged(
    K,
    Hasher = DefaultHash!K,
    Equal = DefaultEqual!K,
)
{
nothrow @nogc:

private:
    HashMapUnmanaged!(K, SetMarker, Hasher, Equal) map_;

public:
    @disable this(this);

    static HashSetUnmanaged withPolicies(Hasher hasher, Equal equal)
    {
        HashSetUnmanaged result;
        result.map_ = typeof(result.map_).withPolicies(
            move(hasher),
            move(equal),
        );
        return result;
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t requested,
        scope HashSetUnmanaged* output,
    )
    {
        version (XTB_Checked)
        {
            require(output !is null,
                "HashSetUnmanaged output pointer is null");
            require(output.map_.capacity == 0 && output.map_.empty,
                "HashSetUnmanaged output is not empty");
        }
        HashSetUnmanaged temporary;
        if (!temporary.tryReserve(allocator, requested))
            return false;
        *output = move(temporary);
        return true;
    }

    static HashSetUnmanaged withCapacity(
        Allocator* allocator,
        size_t requested,
    )
    {
        HashSetUnmanaged result;
        if (!tryWithCapacity(allocator, requested, &result))
            panic("HashSet allocation failed");
        return result;
    }

    static if (IsDefaultHashPolicy!(Hasher, K) &&
            IsDefaultEqualPolicy!(Equal, K))
    {
        static HashSetUnmanaged seeded(HashSeed seed)
        {
            HashSetUnmanaged result;
            result.map_ = typeof(result.map_).seeded(seed);
            return result;
        }

        static HashSetUnmanaged withCapacity(
            Allocator* allocator,
            size_t requested,
            HashSeed seed,
        )
        {
            HashSetUnmanaged result = seeded(seed);
            result.reserve(allocator, requested);
            return result;
        }
    }

    void deinit(Allocator* allocator)
    {
        map_.deinit(allocator);
    }

    void resetAndRelease(Allocator* allocator)
    {
        map_.resetAndRelease(allocator);
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

    HashSetCursor!K cursor() return
    {
        return HashSetCursor!K(map_.cursor());
    }

    ConstHashSetCursor!K cursor() const return
    {
        return ConstHashSetCursor!K(map_.cursor());
    }

    HashSetPointerRange!K pointerItems() return
    {
        return HashSetPointerRange!K(cursor());
    }

    ConstHashSetPointerRange!K pointerItems() const return
    {
        return ConstHashSetPointerRange!K(cursor());
    }

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

    AddStatus tryAdd(Allocator* allocator, K value)
    {
        return map_.tryAdd(allocator, move(value), SetMarker.init);
    }

    bool add(Allocator* allocator, K value)
    {
        return map_.add(allocator, move(value), SetMarker.init);
    }

    bool contains(scope K value) const
    {
        return map_.contains(value);
    }

    bool remove(Allocator* allocator, scope K value)
    {
        return map_.remove(allocator, value);
    }

    bool tryReserve(Allocator* allocator, size_t requested)
    {
        return map_.tryReserve(allocator, requested);
    }

    void reserve(Allocator* allocator, size_t requested)
    {
        map_.reserve(allocator, requested);
    }

    void clear(Allocator* allocator)
    {
        map_.clear(allocator);
    }

    bool tryShrinkToFit(Allocator* allocator)
    {
        return map_.tryShrinkToFit(allocator);
    }

    void shrinkToFit(Allocator* allocator)
    {
        map_.shrinkToFit(allocator);
    }
}

struct HashSet(K, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
nothrow @nogc:

    alias Self = HashSet!(K, Hasher, Equal);
    alias Storage = HashSetUnmanaged!(K, Hasher, Equal);
    alias Released = ReleasedStorage!Storage;

private:
    Allocator* allocator_;
    Storage storage_;

version (XTB_Checked)
{
    invariant
    {
        require(&this !is null, "HashSet pointer is null");
    }
}

public:
    @disable this(this);

    static Self create(Allocator* allocator) @trusted
    {
        requireValidHashAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    static Self withPolicies(
        Allocator* allocator,
        Hasher hasher,
        Equal equal,
    ) @trusted
    {
        requireValidHashAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        result.storage_ = Storage.withPolicies(move(hasher), move(equal));
        return move(result);
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t requested,
        scope Self* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "HashSet output pointer is null");
            require(output.allocator_ is null,
                "HashSet output is already initialized");
        }
        Storage storage;
        if (!Storage.tryWithCapacity(allocator, requested, &storage))
            return false;
        output.allocator_ = allocator;
        output.storage_ = move(storage);
        return true;
    }

    static Self withCapacity(
        Allocator* allocator,
        size_t requested,
    ) @trusted
    {
        Self result;
        if (!tryWithCapacity(allocator, requested, &result))
            panic("HashSet allocation failed");
        return move(result);
    }

    static if (IsDefaultHashPolicy!(Hasher, K) &&
            IsDefaultEqualPolicy!(Equal, K))
    {
        static Self seeded(Allocator* allocator, HashSeed seed) @trusted
        {
            requireValidHashAllocator(allocator);
            Self result;
            result.allocator_ = allocator;
            result.storage_ = Storage.seeded(seed);
            return move(result);
        }

        static Self withCapacity(
            Allocator* allocator,
            size_t requested,
            HashSeed seed,
        ) @trusted
        {
            Self result;
            result.allocator_ = allocator;
            result.storage_ = Storage.withCapacity(
                allocator,
                requested,
                seed,
            );
            return move(result);
        }
    }

    static Self adopt(scope Released* released) @trusted
    {
        version (XTB_Checked)
            require(released !is null,
                "released HashSet storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(storage);
        return move(result);
    }

    ~this() @trusted
    {
        this.deinit();
    }

    void deinit() @trusted
    {
        if (allocator_ is null)
            return;
        storage_.deinit(allocator_);
        allocator_ = null;
    }

    void resetAndRelease() @trusted
    {
        storage_.resetAndRelease(allocator_);
    }

    Released release() @trusted
    {
        auto result = Released.fromOwnedParts(allocator_, &storage_);
        allocator_ = null;
        return move(result);
    }

    size_t length() const pure @trusted
    {
        return storage_.length;
    }

    size_t capacity() const pure @trusted
    {
        return storage_.capacity;
    }

    bool empty() const pure @trusted
    {
        return storage_.empty;
    }

    HashSetCursor!K cursor() return @trusted
    {
        return storage_.cursor();
    }

    ConstHashSetCursor!K cursor() const return @trusted
    {
        return storage_.cursor();
    }

    HashSetPointerRange!K pointerItems() return @trusted
    {
        return storage_.pointerItems();
    }

    ConstHashSetPointerRange!K pointerItems() const return @trusted
    {
        return storage_.pointerItems();
    }

    AddStatus tryAdd(K value) @trusted
    {
        return storage_.tryAdd(allocator_, move(value));
    }

    bool add(K value) @trusted
    {
        return storage_.add(allocator_, move(value));
    }

    bool contains(scope K value) const @trusted
    {
        return storage_.contains(value);
    }

    bool remove(scope K value) @trusted
    {
        return storage_.remove(allocator_, value);
    }

    bool tryReserve(size_t requested) @trusted
    {
        return storage_.tryReserve(allocator_, requested);
    }

    void reserve(size_t requested) @trusted
    {
        storage_.reserve(allocator_, requested);
    }

    void clear() @trusted
    {
        storage_.clear(allocator_);
    }

    bool tryShrinkToFit() @trusted
    {
        return storage_.tryShrinkToFit(allocator_);
    }

    void shrinkToFit() @trusted
    {
        storage_.shrinkToFit(allocator_);
    }

    int opApply(
        scope int delegate(ref const(K)) nothrow @nogc callback,
    )
    {
        return storage_.opApply(callback);
    }

    int opApply(
        scope int delegate(ref const(K)) nothrow @nogc callback,
    ) const
    {
        return storage_.opApply(callback);
    }

    Allocator* allocator() return pure @safe
    {
        return allocator_;
    }

package(xtb):
    static Self adoptUnmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        requireValidHashAllocator(allocator);
        version (XTB_Checked)
            require(storage !is null,
                "HashSetUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(*storage);
        return move(result);
    }
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

unittest
{
    import xtb.core.memory : AllocationRecord, Allocator,
        InstrumentedAllocator, mallocAllocator;

    alias IntMap = HashMap!(int, int);
    alias IntMapStorage = HashMapUnmanaged!(int, int);
    alias IntSet = HashSet!int;
    alias IntSetStorage = HashSetUnmanaged!int;

    static assert(IntMap.sizeof ==
        IntMapStorage.sizeof + (Allocator*).sizeof);
    static assert(IntSet.sizeof ==
        IntSetStorage.sizeof + (Allocator*).sizeof);
    static assert(!__traits(isCopyable, IntMapStorage));
    static assert(!__traits(isCopyable, IntMap));
    static assert(!__traits(isCopyable, IntMap.Released));
    static assert(!__traits(isCopyable, IntSetStorage));
    static assert(!__traits(isCopyable, IntSet));
    static assert(!__traits(isCopyable, IntSet.Released));
    static assert(is(typeof((cast(IntMap*) null).allocator()) == Allocator*));
    static assert(!__traits(compiles,
        (cast(const(IntMap)*) null).allocator()));
    static assert(is(typeof((cast(IntSet*) null).allocator()) == Allocator*));
    static assert(!__traits(compiles,
        (cast(const(IntSet)*) null).allocator()));
    static assert(!__traits(compiles, () @safe {
        IntMap.Released released;
        ref IntMapStorage storage = released.storage;
    }));

    IntMapStorage zeroMap;
    zeroMap.deinit(null);
    zeroMap.resetAndRelease(null);
    assert(zeroMap.empty && zeroMap.capacity == 0);

    IntSetStorage zeroSet;
    zeroSet.deinit(null);
    zeroSet.resetAndRelease(null);
    assert(zeroSet.empty && zeroSet.capacity == 0);

    AllocationRecord[32] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    {
        IntMap map = IntMap.create(tracked.handle);
        map.set(1, 10);
        IntMap.Released released = map.release();

        assert(map.allocator is null && map.empty);
        assert(released.allocator is tracked.handle);
        assert(*released.storage.find(1) == 10);
        released.storage.set(released.allocator, 2, 20);
        assert(*released.storage.find(2) == 20);
    }
    assert(tracked.clean);

    {
        IntMap source = IntMap.create(tracked.handle);
        source.set(3, 30);
        IntMap.Released released = source.release();
        IntMap adopted = IntMap.adopt(&released);

        assert(source.allocator is null && source.empty);
        assert(released.allocator is null && released.storage.empty);
        assert(adopted.allocator is tracked.handle);
        assert(*adopted.find(3) == 30);
    }
    assert(tracked.clean);

    {
        IntMap source = IntMap.create(tracked.handle);
        source.set(4, 40);
        IntMap.Released released = source.release();
        Allocator* allocator;
        IntMapStorage storage = released.extract(&allocator);

        assert(allocator is tracked.handle);
        assert(released.allocator is null && released.storage.empty);
        storage.set(allocator, 5, 50);
        assert(*storage.find(4) == 40);
        assert(*storage.find(5) == 50);
        storage.deinit(allocator);
    }
    assert(tracked.clean);

    {
        IntSet set = IntSet.create(tracked.handle);
        set.add(7);
        IntSet.Released released = set.release();

        assert(set.allocator is null && set.empty);
        assert(released.allocator is tracked.handle);
        assert(released.storage.contains(7));
        released.storage.add(released.allocator, 8);
        assert(released.storage.contains(8));

        IntSet adopted = IntSet.adopt(&released);
        assert(released.allocator is null && released.storage.empty);
        assert(adopted.contains(7) && adopted.contains(8));
    }
    assert(tracked.clean);
}

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        mallocAllocator;

    alias IntMap = HashMap!(int, int);
    alias IntMapStorage = HashMapUnmanaged!(int, int);
    alias IntSet = HashSet!int;
    alias IntSetStorage = HashSetUnmanaged!int;

    {
        AllocationRecord[8] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );
        IntMapStorage output;

        allocator.failAfter(0);
        assert(!IntMapStorage.tryWithCapacity(
            allocator.handle,
            32,
            &output,
        ));
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.failAfter(1);
        assert(!IntMapStorage.tryWithCapacity(
            allocator.handle,
            32,
            &output,
        ));
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.allowAllocations();
        assert(IntMapStorage.tryWithCapacity(
            allocator.handle,
            32,
            &output,
        ));
        assert(output.capacity >= 32);
        output.deinit(allocator.handle);
        assert(allocator.clean && allocator.stats.invalidCalls == 0);
    }

    {
        AllocationRecord[8] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );
        IntMap output;

        allocator.failAfter(1);
        assert(!IntMap.tryWithCapacity(
            allocator.handle,
            32,
            &output,
        ));
        assert(output.allocator is null);
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.allowAllocations();
        assert(IntMap.tryWithCapacity(
            allocator.handle,
            32,
            &output,
        ));
        assert(output.allocator is allocator.handle);
        assert(output.capacity >= 32);
        output.deinit();
        assert(allocator.clean && allocator.stats.invalidCalls == 0);
    }

    {
        AllocationRecord[8] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );
        IntSetStorage output;

        allocator.failAfter(1);
        assert(!IntSetStorage.tryWithCapacity(
            allocator.handle,
            32,
            &output,
        ));
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.allowAllocations();
        assert(IntSetStorage.tryWithCapacity(
            allocator.handle,
            32,
            &output,
        ));
        assert(output.capacity >= 32);
        output.deinit(allocator.handle);
        assert(allocator.clean && allocator.stats.invalidCalls == 0);
    }

    {
        AllocationRecord[8] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );
        IntSet output;

        allocator.failAfter(1);
        assert(!IntSet.tryWithCapacity(
            allocator.handle,
            32,
            &output,
        ));
        assert(output.allocator is null);
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.allowAllocations();
        assert(IntSet.tryWithCapacity(
            allocator.handle,
            32,
            &output,
        ));
        assert(output.allocator is allocator.handle);
        assert(output.capacity >= 32);
        output.deinit();
        assert(allocator.clean && allocator.stats.invalidCalls == 0);
    }
}

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        mallocAllocator;

    alias ManagedMap = HashMap!(int, int);
    alias UnmanagedMap = HashMapUnmanaged!(int, int);

    AllocationRecord[128] managedRecords;
    AllocationRecord[128] unmanagedRecords;
    InstrumentedAllocator managedAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        managedRecords[],
    );
    InstrumentedAllocator unmanagedAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        unmanagedRecords[],
    );

    ManagedMap managed = ManagedMap.create(managedAllocator.handle);
    UnmanagedMap unmanaged;

    foreach (value; 0 .. 160)
    {
        assert(managed.trySet(value, value * 3) ==
            unmanaged.trySet(unmanagedAllocator.handle, value, value * 3));
    }
    foreach (value; 0 .. 80)
    {
        if ((value & 1) == 0)
            assert(managed.remove(value) ==
                unmanaged.remove(unmanagedAllocator.handle, value));
    }
    foreach (value; 80 .. 120)
    {
        assert(managed.trySet(value, value * 5) ==
            unmanaged.trySet(unmanagedAllocator.handle, value, value * 5));
    }
    assert(managed.tryReserve(384));
    assert(unmanaged.tryReserve(unmanagedAllocator.handle, 384));
    assert(managed.tryShrinkToFit());
    assert(unmanaged.tryShrinkToFit(unmanagedAllocator.handle));

    assert(managed.length == unmanaged.length);
    assert(managed.capacity == unmanaged.capacity);
    foreach (value; 0 .. 160)
    {
        const managedValue = managed.find(value);
        const unmanagedValue = unmanaged.find(value);
        assert((managedValue is null) == (unmanagedValue is null));
        if (managedValue !is null)
            assert(*managedValue == *unmanagedValue);
    }

    auto managedCursor = managed.cursor;
    auto unmanagedCursor = unmanaged.cursor;
    while (managedCursor.valid || unmanagedCursor.valid)
    {
        assert(managedCursor.valid == unmanagedCursor.valid);
        assert(*managedCursor.key == *unmanagedCursor.key);
        assert(*managedCursor.value == *unmanagedCursor.value);
        managedCursor.advance();
        unmanagedCursor.advance();
    }
    assert(managedAllocator.stats == unmanagedAllocator.stats);

    const managedStatsBeforeClear = managedAllocator.stats;
    const unmanagedStatsBeforeClear = unmanagedAllocator.stats;
    managed.clear();
    unmanaged.clear(unmanagedAllocator.handle);
    assert(managedAllocator.stats == managedStatsBeforeClear);
    assert(unmanagedAllocator.stats == unmanagedStatsBeforeClear);

    managed.deinit();
    unmanaged.deinit(unmanagedAllocator.handle);
    assert(managedAllocator.stats == unmanagedAllocator.stats);
    assert(managedAllocator.clean && unmanagedAllocator.clean);
}

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        mallocAllocator;

    alias PolicyMap = HashMap!(int, int, ParityHash, ParityEqual);
    alias PolicyStorage = HashMapUnmanaged!(
        int,
        int,
        ParityHash,
        ParityEqual,
    );

    AllocationRecord[32] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    ParityHash parityHash;
    parityHash.parity = true;
    ParityEqual parityEqual;
    parityEqual.parity = true;

    PolicyMap managed = PolicyMap.withPolicies(
        allocator.handle,
        parityHash,
        parityEqual,
    );
    managed.set(1, 10);
    assert(managed.find(3) !is null);
    managed.resetAndRelease();
    assert(managed.allocator is allocator.handle);
    managed.set(5, 50);
    assert(managed.find(7) !is null);
    managed.deinit();
    assert(managed.allocator is null && allocator.clean);

    PolicyStorage unmanaged = PolicyStorage.withPolicies(
        parityHash,
        parityEqual,
    );
    unmanaged.set(allocator.handle, 1, 10);
    assert(unmanaged.find(3) !is null);
    unmanaged.resetAndRelease(allocator.handle);
    unmanaged.set(allocator.handle, 5, 50);
    assert(unmanaged.find(7) !is null);
    unmanaged.deinit(allocator.handle);

    unmanaged.set(allocator.handle, 9, 90);
    assert(unmanaged.find(11) is null);
    unmanaged.deinit(allocator.handle);
    assert(allocator.clean && allocator.stats.invalidCalls == 0);
}
