module xtb.containers.hash_map;

nothrow @nogc:

import core.attribute;
import core.stdc.string;

import xtb.containers.released_storage;
import xtb.hash;
import xtb.lifetime;
import xtb.memory;
import xtb.numeric;
import xtb.panic;
import xtb.types;

private enum SlotState : u8
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

    usize opCall(scope const(K)* key) const
    {
        static if (__traits(compiles, hash_value(*key, this.seed)))
        {
            return hash_value(*key, this.seed);
        }
        else static if (__traits(compiles, (*key).toHash()))
        {
            return hash_value((*key).toHash(), this.seed);
        }
        else
        {
            static assert(false, "DefaultHash requires hash_value(value) or value.toHash()");
        }
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
    out_of_memory,
}

enum AddStatus
{
    inserted,
    already_present,
    out_of_memory,
}

package(xtb.containers) enum PrepareInsertStatus
{
    ready,
    already_present,
    out_of_memory,
}

/// Package-private token proving that a concrete insertion slot has been
/// prepared and that committing the entry cannot allocate.
package(xtb.containers) struct PreparedHashMapInsert
{
    void* entries_identity;
    usize capacity_identity;
    usize index;
    usize hash;
    bool reused_removed;
    bool found;
}

/// Shallow element policy used by ordinary hash containers.
struct DefaultHashMapElementOps(T)
{
    static void destroy(Allocator*, T*)
    {
    }
}

package(xtb.containers) struct OwnedHashMapElementOps(T)
{
    static assert(
        can_finalize_without_context!T,
        "owned hash elements must support context-free finalization",
    );

    static void destroy(Allocator*, T* element)
    {
        static if (needs_finalization!T)
            finalize(*element);
    }
}

package(xtb.containers) template is_simple_hash_value(T)
{
    enum is_simple_hash_value = __traits(isCopyable, T)
        && !needs_deinit!T
        && !has_d_destructor!T;
}

package(xtb.containers) template is_default_hash_policy(Hasher, K)
{
    static if (is(Hasher == DefaultHash!U, U))
    {
        enum is_default_hash_policy = is(U == K);
    }
    else
    {
        enum is_default_hash_policy = false;
    }
}

package(xtb.containers) template is_default_equal_policy(Equal, K)
{
    static if (is(Equal == DefaultEqual!U, U))
    {
        enum is_default_equal_policy = is(U == K);
    }
    else
    {
        enum is_default_equal_policy = false;
    }
}

private struct Entry(K, V)
{
    usize hash;
    K key;
    V value;
}

private struct ProbeResult
{
    usize index;
    bool found;
}

/// Allocator-owned open-addressed hash table.
///
/// Keys cannot be mutated through the table because changing a key in place
/// would invalidate its stored hash and probe position. Values are exposed as
/// pointers so mutation remains explicit at the call site. Any insertion,
/// removal, clear, reserve, or storage release invalidates cursors. A value
/// replacement preserves cursors but may invalidate a pointer to that value.
/// Iteration order is unspecified. For view-like keys such as `String`, the
/// table owns the view value but not the storage to which it refers. While the
/// table is live, zero capacity uses null `states` and `entries`; nonzero
/// capacity owns both allocations and `length`/`removed` describe their slot
/// states. Explicitly deinitialize a live value with the allocator that owns
/// those allocations.
@mustuse struct HashMapUnmanaged(
    K,
    V,
    Hasher = DefaultHash!K,
    Equal = DefaultEqual!K,
    Lookup = K,
    KeyOps = DefaultHashMapElementOps!K,
    ValueOps = DefaultHashMapElementOps!V,
)
{
    static assert(
        __traits(isCopyable, Hasher)
            && !has_d_destructor!Hasher
            && !needs_deinit!Hasher,
        "HashMap hash policies must be copyable and require no cleanup",
    );
    static assert(
        __traits(isCopyable, Equal)
            && !has_d_destructor!Equal
            && !needs_deinit!Equal,
        "HashMap equality policies must be copyable and require no cleanup",
    );
    static assert(
        __traits(compiles, KeyOps.destroy(cast(Allocator*) null, cast(K*) null)),
        "HashMap key lifetime policy must provide destroy(Allocator*, K*)",
    );
    static assert(
        __traits(compiles, ValueOps.destroy(cast(Allocator*) null, cast(V*) null)),
        "HashMap value lifetime policy must provide destroy(Allocator*, V*)",
    );

    SlotState* states;
    Entry!(K, V)* entries;
    usize length;
    usize removed;
    usize capacity;
    Hasher hasher;
    Equal equal;

    @disable this(this);
    @disable ref HashMapUnmanaged opAssign(HashMapUnmanaged source) return;

    static HashMapUnmanaged with_policies(Hasher hasher, Equal equal)
    {
        HashMapUnmanaged result;
        move_emplace(hasher, result.hasher);
        move_emplace(equal, result.equal);
        return result;
    }

    /// Attempts to reserve an unmanaged table with capacity for `requested` entries.
    ///
    /// `output` must be inert: it must own no backing storage and have zero slot
    /// counts. On allocation failure, `output` remains unchanged.
    static bool try_with_capacity(
        Allocator* allocator,
        usize requested,
        scope HashMapUnmanaged* output,
    ) @system
    {
        require(output !is null, "HashMapUnmanaged output pointer is null");
        require(
            output.states is null
                && output.entries is null
                && output.length == 0
                && output.removed == 0
                && output.capacity == 0,
            "HashMapUnmanaged output is not empty",
        );
        HashMapUnmanaged temporary;
        if (!temporary.try_reserve(allocator, requested)) return false;
        move_emplace(temporary, *output);
        return true;
    }

    static HashMapUnmanaged with_capacity(Allocator* allocator, usize requested)
    {
        HashMapUnmanaged result;
        if (!HashMapUnmanaged.try_with_capacity(allocator, requested, &result))
            panic("HashMap allocation failed");

        return result;
    }

    static if (is_default_hash_policy!(Hasher, K) && is_default_equal_policy!(Equal, K))
    {
        static HashMapUnmanaged seeded(HashSeed seed)
        {
            Hasher hasher;
            hasher.seed = seed;
            return HashMapUnmanaged.with_policies(hasher, Equal.init);
        }

        static HashMapUnmanaged with_capacity(Allocator* allocator, usize requested, HashSeed seed)
        {
            auto result = HashMapUnmanaged.seeded(seed);
            result.reserve(allocator, requested);
            return result;
        }
    }

    void deinit(Allocator* allocator)
    {
        if (this.capacity != 0) require_valid_hash_allocator(allocator);
        this.clear(allocator);
        if (this.capacity != 0)
        {
            allocator.deallocate_array(this.entries[0 .. this.capacity]);
            allocator.deallocate_array(this.states[0 .. this.capacity]);
        }
    }

    void reset_and_release(Allocator* allocator)
    {
        if (this.capacity != 0) require_valid_hash_allocator(allocator);
        this.clear(allocator);
        if (this.capacity != 0)
        {
            allocator.deallocate_array(this.entries[0 .. this.capacity]);
            allocator.deallocate_array(this.states[0 .. this.capacity]);
        }
        this.entries = null;
        this.states = null;
        this.capacity = 0;
        this.length = 0;
        this.removed = 0;
    }

    bool empty() const pure @safe
    {
        return this.length == 0;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.map(this);
    }

    HashMapCursor!(K, V) cursor() return
    {
        return HashMapCursor!(K, V).create(this.states, this.entries, this.capacity);
    }

    ConstHashMapCursor!(K, V) cursor() const return
    {
        return ConstHashMapCursor!(K, V).create(this.states, this.entries, this.capacity);
    }

    HashMapPointerRange!(K, V) pointer_items() return
    {
        return HashMapPointerRange!(K, V)(this.cursor());
    }

    ConstHashMapPointerRange!(K, V) pointer_items() const return
    {
        return ConstHashMapPointerRange!(K, V)(this.cursor());
    }

    i32 opApply(scope i32 delegate(ref const(K), ref V) nothrow @nogc callback)
    {
        for (usize index = 0; index < this.capacity; ++index)
        {
            if (this.states[index] != SlotState.occupied) continue;
            const i32 result = callback(this.entries[index].key, this.entries[index].value);
            if (result != 0) return result;
        }
        return 0;
    }

    i32 opApply(scope i32 delegate(ref const(K), ref const(V)) nothrow @nogc callback) const
    {
        for (usize index = 0; index < this.capacity; ++index)
        {
            if (this.states[index] != SlotState.occupied) continue;
            const i32 result = callback(this.entries[index].key, this.entries[index].value);
            if (result != 0) return result;
        }
        return 0;
    }

    bool try_reserve(Allocator* allocator, usize requested)
    {
        require_valid_hash_allocator(allocator);
        usize target_capacity;
        if (!capacity_for_length(requested, target_capacity)) return false;
        if (target_capacity <= this.capacity) return true;

        return this.try_rehash(allocator, target_capacity);
    }

    void reserve(Allocator* allocator, usize requested)
    {
        if (!this.try_reserve(allocator, requested)) panic("HashMap allocation failed");
    }

    /// Fallible insertion that consumes caller ownership only on success.
    /// `key` and `value` must be non-null and must not overlap each other or
    /// live table storage. Duplicate and allocation-failure paths leave both
    /// inputs unchanged.
    AddStatus try_add(Allocator* allocator, scope K* key, scope V* value) @system
    {
        require(key !is null, "HashMap insertion key pointer is null");
        require(value !is null, "HashMap insertion value pointer is null");
        require(
            !hash_storage_overlaps(key, value),
            "HashMap insertion key and value storage overlap",
        );
        require_valid_hash_allocator(allocator);
        const usize hash = this.hasher(key);
        ProbeResult location = this.probe_stored(key, hash);
        if (location.found) return AddStatus.already_present;
        require(
            !this.points_into_entry_storage(key),
            "HashMap insertion key aliases table storage",
        );
        require(
            !this.points_into_entry_storage(value),
            "HashMap insertion value aliases table storage",
        );
        if (!this.try_prepare_insert(allocator)) return AddStatus.out_of_memory;

        location = this.probe_stored(key, hash);
        Entry!(K, V)* destination = this.entries + location.index;
        const reused_removed = this.states[location.index] == SlotState.removed;
        destination.hash = hash;
        construct_hash_move(&destination.key, *key);
        construct_hash_move(&destination.value, *value);
        this.states[location.index] = SlotState.occupied;
        ++this.length;
        if (reused_removed) --this.removed;
        return AddStatus.inserted;
    }

    bool add(Allocator* allocator, scope K* key, scope V* value) @system
    {
        const AddStatus status = this.try_add(allocator, key, value);
        if (status == AddStatus.out_of_memory) panic("HashMap allocation failed");
        return status == AddStatus.inserted;
    }

    /// Fallible insert-or-replace. `key` and `value` must be non-null and must
    /// not overlap each other or unrelated live table storage. On insertion
    /// both inputs are consumed. On replacement only `*value` is consumed and
    /// `*key` is unchanged.
    SetStatus try_set(Allocator* allocator, scope K* key, scope V* value) @system
    {
        require(key !is null, "HashMap insertion key pointer is null");
        require(value !is null, "HashMap insertion value pointer is null");
        require(
            !hash_storage_overlaps(key, value),
            "HashMap insertion key and value storage overlap",
        );
        require_valid_hash_allocator(allocator);
        const usize hash = this.hasher(key);
        ProbeResult location = this.probe_stored(key, hash);
        if (location.found)
        {
            V* destination = &this.entries[location.index].value;
            require(
                !this.points_into_entry_storage(value) || value is destination,
                "HashMap replacement value aliases another table entry",
            );
            if (destination !is value)
                replace_hash_element!ValueOps(allocator, destination, *value);

            return SetStatus.replaced;
        }
        require(
            !this.points_into_entry_storage(key),
            "HashMap insertion key aliases table storage",
        );
        require(
            !this.points_into_entry_storage(value),
            "HashMap insertion value aliases table storage",
        );
        if (!this.try_prepare_insert(allocator)) return SetStatus.out_of_memory;

        location = this.probe_stored(key, hash);
        Entry!(K, V)* destination = this.entries + location.index;
        const reused_removed = this.states[location.index] == SlotState.removed;
        destination.hash = hash;
        construct_hash_move(&destination.key, *key);
        construct_hash_move(&destination.value, *value);
        this.states[location.index] = SlotState.occupied;
        ++this.length;
        if (reused_removed) --this.removed;
        return SetStatus.inserted;
    }

    bool set(Allocator* allocator, scope K* key, scope V* value) @system
    {
        const SetStatus status = this.try_set(allocator, key, value);
        if (status == SetStatus.out_of_memory) panic("HashMap allocation failed");
        return status == SetStatus.inserted;
    }

    static if (is_simple_hash_value!K && is_simple_hash_value!V)
    {
        SetStatus try_set(Allocator* allocator, K key, V value)
        {
            require_valid_hash_allocator(allocator);
            const usize hash = this.hasher(&key);
            ProbeResult location = this.probe_stored(&key, hash);
            if (location.found)
            {
                replace_hash_element!ValueOps(
                    allocator,
                    &this.entries[location.index].value,
                    value,
                );
                return SetStatus.replaced;
            }
            if (!this.try_prepare_insert(allocator)) return SetStatus.out_of_memory;

            location = this.probe_stored(&key, hash);
            Entry!(K, V)* destination = this.entries + location.index;
            const reused_removed = this.states[location.index] == SlotState.removed;
            destination.hash = hash;
            construct_hash_move(&destination.key, key);
            construct_hash_move(&destination.value, value);
            this.states[location.index] = SlotState.occupied;
            ++this.length;
            if (reused_removed) --this.removed;
            return SetStatus.inserted;
        }

        bool set(Allocator* allocator, K key, V value)
        {
            const SetStatus status = this.try_set(allocator, move(key), move(value));
            if (status == SetStatus.out_of_memory) panic("HashMap allocation failed");
            return status == SetStatus.inserted;
        }

        AddStatus try_add(Allocator* allocator, K key, V value)
        {
            require_valid_hash_allocator(allocator);
            const usize hash = this.hasher(&key);
            ProbeResult location = this.probe_stored(&key, hash);
            if (location.found) return AddStatus.already_present;
            if (!this.try_prepare_insert(allocator)) return AddStatus.out_of_memory;

            location = this.probe_stored(&key, hash);
            Entry!(K, V)* destination = this.entries + location.index;
            const reused_removed = this.states[location.index] == SlotState.removed;
            destination.hash = hash;
            construct_hash_move(&destination.key, key);
            construct_hash_move(&destination.value, value);
            this.states[location.index] = SlotState.occupied;
            ++this.length;
            if (reused_removed) --this.removed;
            return AddStatus.inserted;
        }

        bool add(Allocator* allocator, K key, V value)
        {
            const AddStatus status = this.try_add(allocator, move(key), move(value));
            if (status == AddStatus.out_of_memory) panic("HashMap allocation failed");
            return status == AddStatus.inserted;
        }
    }

    V* find(scope const(Lookup)* key) return
    {
        require(key !is null, "HashMap lookup key pointer is null");
        if (this.capacity == 0) return null;
        const usize hash = this.hasher(key);
        const ProbeResult location = this.probe_lookup(key, hash);
        return location.found ? &this.entries[location.index].value : null;
    }

    const(V)* find(scope const(Lookup)* key) const return
    {
        require(key !is null, "HashMap lookup key pointer is null");
        if (this.capacity == 0) return null;
        const usize hash = this.hasher(key);
        const ProbeResult location = this.probe_lookup(key, hash);
        return location.found ? &this.entries[location.index].value : null;
    }

    bool contains(scope const(Lookup)* key) const
    {
        return this.find(key) !is null;
    }

    bool remove(Allocator* allocator, scope const(Lookup)* key)
    {
        require(key !is null, "HashMap removal key pointer is null");
        if (this.capacity == 0) return false;
        require_valid_hash_allocator(allocator);
        const usize hash = this.hasher(key);
        const ProbeResult location = this.probe_lookup(key, hash);
        if (!location.found) return false;

        Entry!(K, V)* entry = this.entries + location.index;
        ValueOps.destroy(allocator, &entry.value);
        KeyOps.destroy(allocator, &entry.key);
        this.mark_removed(location.index);
        return true;
    }

    /// Transfers an entry without running key/value cleanup.
    ///
    /// `key`, `key_output`, and `value_output` must be non-null and their
    /// storage must not overlap. The outputs must point to dead/uninitialized
    /// storage outside the table. If the key is absent, both outputs remain
    /// untouched.
    bool take(scope const(Lookup)* key, scope K* key_output, scope V* value_output) @system
    {
        require(key !is null, "HashMap take key pointer is null");
        require(key_output !is null, "HashMap take key output pointer is null");
        require(value_output !is null, "HashMap take value output pointer is null");
        require(
            !hash_storage_overlaps(key_output, value_output),
            "HashMap take key and value output storage overlap",
        );
        require(
            !hash_storage_overlaps(key, key_output),
            "HashMap take lookup key overlaps key output storage",
        );
        require(
            !hash_storage_overlaps(key, value_output),
            "HashMap take lookup key overlaps value output storage",
        );
        require(
            !this.points_into_entry_storage(key_output),
            "HashMap take key output aliases table storage",
        );
        require(
            !this.points_into_entry_storage(value_output),
            "HashMap take value output aliases table storage",
        );
        if (this.capacity == 0) return false;
        const usize hash = this.hasher(key);
        const ProbeResult location = this.probe_lookup(key, hash);
        if (!location.found) return false;

        Entry!(K, V)* entry = this.entries + location.index;
        construct_hash_move(key_output, entry.key);
        construct_hash_move(value_output, entry.value);
        this.mark_removed(location.index);
        return true;
    }

    static if (is_simple_hash_value!Lookup)
    {
        V* find(scope Lookup key) return
        {
            return this.find(&key);
        }

        const(V)* find(scope Lookup key) const return
        {
            return this.find(&key);
        }

        bool contains(scope Lookup key) const
        {
            return this.contains(&key);
        }

        bool remove(Allocator* allocator, scope Lookup key)
        {
            return this.remove(allocator, &key);
        }

        bool take(scope Lookup key, scope K* key_output, scope V* value_output) @system
        {
            return this.take(&key, key_output, value_output);
        }
    }

    private void mark_removed(usize index)
    {
        this.states[index] = SlotState.removed;
        --this.length;
        ++this.removed;
        if (this.length == 0)
        {
            memset(this.states, SlotState.empty, this.capacity);
            this.removed = 0;
        }
    }

    void clear(Allocator* allocator)
    {
        if (this.length != 0) require_valid_hash_allocator(allocator);
        for (usize index = 0; index < this.capacity; ++index)
        {
            if (this.states[index] != SlotState.occupied) continue;
            ValueOps.destroy(allocator, &this.entries[index].value);
            KeyOps.destroy(allocator, &this.entries[index].key);
        }
        if (this.capacity != 0) memset(this.states, SlotState.empty, this.capacity);
        this.length = 0;
        this.removed = 0;
    }

    bool try_shrink_to_fit(Allocator* allocator)
    {
        require_valid_hash_allocator(allocator);
        if (this.length == 0)
        {
            this.reset_and_release(allocator);
            return true;
        }
        usize target_capacity;
        if (!capacity_for_length(this.length, target_capacity)) return false;
        if (target_capacity == this.capacity && this.removed == 0) return true;

        return this.try_rehash(allocator, target_capacity);
    }

    void shrink_to_fit(Allocator* allocator)
    {
        if (!this.try_shrink_to_fit(allocator)) panic("HashMap allocation failed");
    }

    package(xtb.containers) PrepareInsertStatus prepare_insert(
        Allocator* allocator,
        scope Lookup key,
        scope PreparedHashMapInsert* prepared,
    )
    {
        require_valid_hash_allocator(allocator);
        require(prepared !is null, "prepared HashMap insertion output pointer is null");
        require(
            prepared.entries_identity is null && prepared.capacity_identity == 0,
            "prepared HashMap insertion output is not empty",
        );

        const usize hash = this.hasher(&key);
        ProbeResult location = this.probe_lookup(&key, hash);
        if (location.found)
        {
            prepared.entries_identity = this.entries;
            prepared.capacity_identity = this.capacity;
            prepared.index = location.index;
            prepared.hash = hash;
            prepared.found = true;
            return PrepareInsertStatus.already_present;
        }

        if (!this.try_prepare_insert(allocator)) return PrepareInsertStatus.out_of_memory;

        location = this.probe_lookup(&key, hash);
        require(!location.found, "HashMap changed during prepared insertion");
        prepared.entries_identity = this.entries;
        prepared.capacity_identity = this.capacity;
        prepared.index = location.index;
        prepared.hash = hash;
        prepared.reused_removed =
            this.states[location.index] == SlotState.removed;
        return PrepareInsertStatus.ready;
    }

    package(xtb.containers) void commit_prepared_insert(
        scope PreparedHashMapInsert* prepared,
        scope K* key,
        scope V* value,
    ) @system
    {
        require(prepared !is null, "prepared HashMap insertion pointer is null");
        require(key !is null, "HashMap insertion key pointer is null");
        require(value !is null, "HashMap insertion value pointer is null");
        require(!prepared.found, "cannot commit an already-present HashMap insertion");
        require(
            prepared.entries_identity is this.entries
                && prepared.capacity_identity == this.capacity
                && prepared.index < this.capacity,
            "stale prepared HashMap insertion",
        );
        require(
            this.states[prepared.index] != SlotState.occupied,
            "prepared HashMap insertion slot is occupied",
        );
        require(
            !this.points_into_entry_storage(key),
            "prepared HashMap insertion key aliases table storage",
        );
        require(
            !this.points_into_entry_storage(value),
            "prepared HashMap insertion value aliases table storage",
        );

        Entry!(K, V)* destination = this.entries + prepared.index;
        destination.hash = prepared.hash;
        construct_hash_move(&destination.key, *key);
        construct_hash_move(&destination.value, *value);
        this.states[prepared.index] = SlotState.occupied;
        ++this.length;
        if (prepared.reused_removed) --this.removed;
        *prepared = PreparedHashMapInsert.init;
    }

    package(xtb.containers) void replace_prepared_value(
        Allocator* allocator,
        scope PreparedHashMapInsert* prepared,
        scope V* value,
    ) @system
    {
        require_valid_hash_allocator(allocator);
        require(prepared !is null, "prepared HashMap insertion pointer is null");
        require(value !is null, "HashMap replacement value pointer is null");
        require(prepared.found, "cannot replace through an absent HashMap insertion");
        require(
            prepared.entries_identity is this.entries
                && prepared.capacity_identity == this.capacity
                && prepared.index < this.capacity
                && this.states[prepared.index] == SlotState.occupied,
            "stale prepared HashMap replacement",
        );
        V* destination = &this.entries[prepared.index].value;
        require(
            !this.points_into_entry_storage(value) || value is destination,
            "prepared HashMap replacement aliases another table entry",
        );
        if (destination !is value) replace_hash_element!ValueOps(allocator, destination, *value);
        *prepared = PreparedHashMapInsert.init;
    }

    package(xtb.containers) bool aliases_entry_storage(T)(scope const(T)* pointer) const @system
    {
        return this.points_into_entry_storage(pointer);
    }

    private bool points_into_entry_storage(T)(scope const(T)* pointer) const @system
    {
        if (this.entries is null || pointer is null || this.capacity == 0) return false;
        const begin = cast(usize) this.entries;
        const address = cast(usize) pointer;
        if (address < begin) return false;
        return address - begin < this.capacity * Entry!(K, V).sizeof;
    }

    ProbeResult probe_stored(scope const(K)* key, usize hash) const
    {
        if (this.capacity == 0) return ProbeResult.init;

        const mask = this.capacity - 1;
        usize index = hash & mask;
        usize first_removed = usize.max;
        while (true)
        {
            final switch (this.states[index])
            {
                case SlotState.empty:
                    return ProbeResult(
                        first_removed == usize.max ? index : first_removed,
                        false,
                    );
                case SlotState.occupied:
                    if (this.entries[index].hash == hash
                        && this.equal(&this.entries[index].key, key))
                    {
                        return ProbeResult(index, true);
                    }
                    break;
                case SlotState.removed:
                    if (first_removed == usize.max) first_removed = index;
                    break;
            }
            index = (index + 1) & mask;
        }
    }

    ProbeResult probe_lookup(scope const(Lookup)* key, usize hash) const
    {
        if (this.capacity == 0) return ProbeResult.init;

        const mask = this.capacity - 1;
        usize index = hash & mask;
        usize first_removed = usize.max;
        while (true)
        {
            final switch (this.states[index])
            {
                case SlotState.empty:
                    return ProbeResult(
                        first_removed == usize.max ? index : first_removed,
                        false,
                    );
                case SlotState.occupied:
                    if (this.entries[index].hash == hash
                        && this.equal(&this.entries[index].key, key))
                    {
                        return ProbeResult(index, true);
                    }
                    break;
                case SlotState.removed:
                    if (first_removed == usize.max) first_removed = index;
                    break;
            }
            index = (index + 1) & mask;
        }
    }

    bool try_rehash(Allocator* allocator, usize capacity)
    {
        require(capacity >= 8 && (capacity & (capacity - 1)) == 0, "invalid HashMap capacity");
        if (multiply_overflows(Entry!(K, V).sizeof, capacity)) return false;

        SlotState* new_states = allocator.try_allocate_zeroed_array!SlotState(capacity).ptr;
        if (new_states is null) return false;
        Entry!(K, V)* new_entries = allocator.try_allocate_array!(Entry!(K, V))(capacity).ptr;
        if (new_entries is null)
        {
            allocator.deallocate_array(new_states[0 .. capacity]);
            return false;
        }

        for (usize index = 0; index < this.capacity; ++index)
        {
            if (this.states[index] != SlotState.occupied) continue;
            Entry!(K, V)* source = this.entries + index;
            const usize destination_index = empty_hash_index(new_states, capacity, source.hash);
            Entry!(K, V)* destination = new_entries + destination_index;
            destination.hash = source.hash;
            construct_hash_move(&destination.key, source.key);
            construct_hash_move(&destination.value, source.value);
            new_states[destination_index] = SlotState.occupied;
        }

        if (this.capacity != 0)
        {
            allocator.deallocate_array(this.entries[0 .. this.capacity]);
            allocator.deallocate_array(this.states[0 .. this.capacity]);
        }
        this.entries = new_entries;
        this.states = new_states;
        this.capacity = capacity;
        this.removed = 0;
        return true;
    }

    bool try_prepare_insert(Allocator* allocator)
    {
        if (this.capacity == 0) return this.try_rehash(allocator, 8);
        if (this.length + this.removed < maximum_hash_length(this.capacity)) return true;
        if (this.length < maximum_hash_length(this.capacity))
            return this.try_rehash(allocator, this.capacity);

        if (this.capacity > usize.max / 2) return false;
        return this.try_rehash(allocator, this.capacity * 2);
    }
}

@mustuse struct HashMap(K, V, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
    alias Self = HashMap!(K, V, Hasher, Equal);
    alias Storage = HashMapUnmanaged!(
        K,
        V,
        Hasher,
        Equal,
        K,
        DefaultHashMapElementOps!K,
        DefaultHashMapElementOps!V,
    );
    alias Released = ReleasedStorage!Storage;

    /// Allocator that owns `storage`; null only for an inert or released value.
    Allocator* allocator;
    /// Backing table owned through `allocator` while this value is live.
    Storage storage;

    invariant
    {
        require(&this !is null, "HashMap pointer is null");
    }

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(Allocator* allocator) @safe
    {
        require_valid_hash_allocator(allocator);
        Self result;
        result.allocator = allocator;
        return result;
    }

    static Self with_policies(Allocator* allocator, Hasher hasher, Equal equal) @trusted
    {
        require_valid_hash_allocator(allocator);
        Self result;
        result.allocator = allocator;
        auto storage = Storage.with_policies(move(hasher), move(equal));
        move_emplace(storage, result.storage);
        return move(result);
    }

    /// Attempts to create an empty managed map with capacity for `requested` entries.
    ///
    /// `output` must be inert: it must have no allocator binding or backing
    /// storage and zero slot counts. On allocation failure, `output` remains unchanged.
    static bool try_with_capacity(
        Allocator* allocator,
        usize requested,
        scope Self* output,
    ) @system
    {
        require(output !is null, "HashMap output pointer is null");
        require(
            output.allocator is null
                && output.storage.states is null
                && output.storage.entries is null
                && output.storage.length == 0
                && output.storage.removed == 0
                && output.storage.capacity == 0,
            "HashMap output is not inert",
        );
        Storage storage;
        if (!Storage.try_with_capacity(allocator, requested, &storage)) return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static Self with_capacity(Allocator* allocator, usize requested) @trusted
    {
        Self result;
        if (!Self.try_with_capacity(allocator, requested, &result))
            panic("HashMap allocation failed");

        return move(result);
    }

    static if (is_default_hash_policy!(Hasher, K) && is_default_equal_policy!(Equal, K))
    {
        static Self seeded(Allocator* allocator, HashSeed seed) @trusted
        {
            require_valid_hash_allocator(allocator);
            Self result;
            result.allocator = allocator;
            auto storage = Storage.seeded(seed);
            move_emplace(storage, result.storage);
            return move(result);
        }

        static Self with_capacity(Allocator* allocator, usize requested, HashSeed seed) @trusted
        {
            Self result;
            result.allocator = allocator;
            auto storage = Storage.with_capacity(allocator, requested, seed);
            move_emplace(storage, result.storage);
            return move(result);
        }
    }

    /// Adopts storage previously returned by `release`.
    ///
    /// `released` must be non-null and is consumed by this operation.
    static Self adopt(scope Released* released) @system
    {
        require(released !is null, "released HashMap storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator = allocator;
        move_emplace(storage, result.storage);
        return move(result);
    }

    void deinit() @trusted
    {
        if (this.allocator is null) return;
        this.storage.deinit(this.allocator);
        this.allocator = null;
    }

    void reset_and_release() @trusted
    {
        this.storage.reset_and_release(this.allocator);
    }

    Released release() @trusted
    {
        auto result = Released.from_owned_parts(this.allocator, &this.storage);
        this.allocator = null;
        return move(result);
    }

    usize length() const pure @safe
    {
        return this.storage.length;
    }

    usize capacity() const pure @safe
    {
        return this.storage.capacity;
    }

    bool empty() const pure @safe
    {
        return this.storage.empty;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.map(this);
    }

    HashMapCursor!(K, V) cursor() return @trusted
    {
        return this.storage.cursor();
    }

    ConstHashMapCursor!(K, V) cursor() const return @trusted
    {
        return this.storage.cursor();
    }

    HashMapPointerRange!(K, V) pointer_items() return @trusted
    {
        return this.storage.pointer_items();
    }

    ConstHashMapPointerRange!(K, V) pointer_items() const return @trusted
    {
        return this.storage.pointer_items();
    }

    bool try_reserve(usize requested) @trusted
    {
        return this.storage.try_reserve(this.allocator, requested);
    }

    void reserve(usize requested) @trusted
    {
        this.storage.reserve(this.allocator, requested);
    }

    /// `key` and `value` must be non-null. Consumption matches unmanaged `try_set`.
    SetStatus try_set(scope K* key, scope V* value) @system
    {
        return this.storage.try_set(this.allocator, key, value);
    }

    /// `key` and `value` must be non-null. Consumption matches unmanaged `set`.
    bool set(scope K* key, scope V* value) @system
    {
        return this.storage.set(this.allocator, key, value);
    }

    /// `key` and `value` must be non-null and are consumed only on insertion.
    AddStatus try_add(scope K* key, scope V* value) @system
    {
        return this.storage.try_add(this.allocator, key, value);
    }

    /// `key` and `value` must be non-null and are consumed only on insertion.
    bool add(scope K* key, scope V* value) @system
    {
        return this.storage.add(this.allocator, key, value);
    }

    static if (is_simple_hash_value!K && is_simple_hash_value!V)
    {
        SetStatus try_set(K key, V value) @trusted
        {
            return this.storage.try_set(this.allocator, key, value);
        }

        bool set(K key, V value) @trusted
        {
            return this.storage.set(this.allocator, key, value);
        }

        AddStatus try_add(K key, V value) @trusted
        {
            return this.storage.try_add(this.allocator, key, value);
        }

        bool add(K key, V value) @trusted
        {
            return this.storage.add(this.allocator, key, value);
        }
    }

    /// `key` must be non-null. The returned pointer borrows from this map.
    V* find(scope const(K)* key) return @trusted
    {
        return this.storage.find(key);
    }

    /// `key` must be non-null. The returned pointer borrows from this map.
    const(V)* find(scope const(K)* key) const return @trusted
    {
        return this.storage.find(key);
    }

    /// `key` must be non-null.
    bool contains(scope const(K)* key) const @trusted
    {
        return this.storage.contains(key);
    }

    /// `key` must be non-null.
    bool remove(scope const(K)* key) @trusted
    {
        return this.storage.remove(this.allocator, key);
    }

    /// Pointer and output-storage requirements match unmanaged `take`.
    bool take(scope const(K)* key, scope K* key_output, scope V* value_output) @system
    {
        return this.storage.take(key, key_output, value_output);
    }

    static if (is_simple_hash_value!K)
    {
        V* find(scope K key) return @trusted
        {
            return this.storage.find(key);
        }

        const(V)* find(scope K key) const return @trusted
        {
            return this.storage.find(key);
        }

        bool contains(scope K key) const @trusted
        {
            return this.storage.contains(key);
        }

        bool remove(scope K key) @trusted
        {
            return this.storage.remove(this.allocator, key);
        }

        bool take(scope K key, scope K* key_output, scope V* value_output) @system
        {
            return this.storage.take(&key, key_output, value_output);
        }
    }

    void clear() @trusted
    {
        this.storage.clear(this.allocator);
    }

    bool try_shrink_to_fit() @trusted
    {
        return this.storage.try_shrink_to_fit(this.allocator);
    }

    void shrink_to_fit() @trusted
    {
        this.storage.shrink_to_fit(this.allocator);
    }

    // Foreach is a D language hook.
    i32 opApply(scope i32 delegate(ref const(K), ref V) nothrow @nogc callback)
    {
        return this.storage.opApply(callback);
    }

    i32 opApply(scope i32 delegate(ref const(K), ref const(V)) nothrow @nogc callback) const
    {
        return this.storage.opApply(callback);
    }

    package(xtb.containers) static Self adopt_unmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        require_valid_hash_allocator(allocator);
        require(storage !is null, "HashMapUnmanaged pointer is null");
        Self result;
        result.allocator = allocator;
        move_emplace(*storage, result.storage);
        return move(result);
    }
}

/// Managed hash map that owns cleanup of stored keys and values.
@mustuse struct OwnedHashMap(K, V, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
    static assert(
        can_finalize_without_context!K && can_finalize_without_context!V,
        "OwnedHashMap keys and values must support context-free finalization",
    );

    alias Self = OwnedHashMap!(K, V, Hasher, Equal);
    alias Storage = HashMapUnmanaged!(
        K,
        V,
        Hasher,
        Equal,
        K,
        OwnedHashMapElementOps!K,
        OwnedHashMapElementOps!V,
    );

    /// Allocator that owns `storage`; null only while this value is inert.
    Allocator* allocator;
    /// Backing table and stored elements owned through `allocator`.
    Storage storage;

    invariant
    {
        require(&this !is null, "OwnedHashMap pointer is null");
    }

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(Allocator* allocator) @safe
    {
        require_valid_hash_allocator(allocator);
        Self result;
        result.allocator = allocator;
        return result;
    }

    static Self with_policies(Allocator* allocator, Hasher hasher, Equal equal) @trusted
    {
        require_valid_hash_allocator(allocator);
        Self result;
        result.allocator = allocator;
        auto storage = Storage.with_policies(move(hasher), move(equal));
        move_emplace(storage, result.storage);
        return move(result);
    }

    /// Attempts to create an empty owned map with capacity for `requested` entries.
    ///
    /// `output` must be inert: it must have no allocator binding or backing
    /// storage and zero slot counts. On allocation failure, `output` remains unchanged.
    static bool try_with_capacity(
        Allocator* allocator,
        usize requested,
        scope Self* output,
    ) @system
    {
        require(output !is null, "OwnedHashMap output pointer is null");
        require(
            output.allocator is null
                && output.storage.states is null
                && output.storage.entries is null
                && output.storage.length == 0
                && output.storage.removed == 0
                && output.storage.capacity == 0,
            "OwnedHashMap output is not inert",
        );
        Storage storage;
        if (!Storage.try_with_capacity(allocator, requested, &storage)) return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static Self with_capacity(Allocator* allocator, usize requested) @trusted
    {
        Self result;
        if (!Self.try_with_capacity(allocator, requested, &result))
            panic("OwnedHashMap allocation failed");

        return move(result);
    }

    static if (is_default_hash_policy!(Hasher, K) && is_default_equal_policy!(Equal, K))
    {
        static Self seeded(Allocator* allocator, HashSeed seed) @trusted
        {
            require_valid_hash_allocator(allocator);
            Self result;
            result.allocator = allocator;
            auto storage = Storage.seeded(seed);
            move_emplace(storage, result.storage);
            return move(result);
        }

        static Self with_capacity(Allocator* allocator, usize requested, HashSeed seed) @trusted
        {
            Self result;
            result.allocator = allocator;
            auto storage = Storage.with_capacity(allocator, requested, seed);
            move_emplace(storage, result.storage);
            return move(result);
        }
    }

    void deinit() @trusted
    {
        if (this.allocator is null) return;
        this.storage.deinit(this.allocator);
        this.allocator = null;
    }

    void reset_and_release() @trusted
    {
        this.storage.reset_and_release(this.allocator);
    }

    usize length() const pure @safe
    {
        return this.storage.length;
    }

    usize capacity() const pure @safe
    {
        return this.storage.capacity;
    }

    bool empty() const pure @safe
    {
        return this.storage.empty;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.map(this);
    }

    HashMapCursor!(K, V) cursor() return @trusted
    {
        return this.storage.cursor();
    }

    ConstHashMapCursor!(K, V) cursor() const return @trusted
    {
        return this.storage.cursor();
    }

    HashMapPointerRange!(K, V) pointer_items() return @trusted
    {
        return this.storage.pointer_items();
    }

    ConstHashMapPointerRange!(K, V) pointer_items() const return @trusted
    {
        return this.storage.pointer_items();
    }

    bool try_reserve(usize requested) @trusted
    {
        return this.storage.try_reserve(this.allocator, requested);
    }

    void reserve(usize requested) @trusted
    {
        this.storage.reserve(this.allocator, requested);
    }

    /// `key` and `value` must be non-null. Consumption matches unmanaged `try_set`.
    SetStatus try_set(scope K* key, scope V* value) @system
    {
        return this.storage.try_set(this.allocator, key, value);
    }

    /// `key` and `value` must be non-null. Consumption matches unmanaged `set`.
    bool set(scope K* key, scope V* value) @system
    {
        return this.storage.set(this.allocator, key, value);
    }

    /// `key` and `value` must be non-null and are consumed only on insertion.
    AddStatus try_add(scope K* key, scope V* value) @system
    {
        return this.storage.try_add(this.allocator, key, value);
    }

    /// `key` and `value` must be non-null and are consumed only on insertion.
    bool add(scope K* key, scope V* value) @system
    {
        return this.storage.add(this.allocator, key, value);
    }

    static if (is_simple_hash_value!K && is_simple_hash_value!V)
    {
        SetStatus try_set(K key, V value) @trusted
        {
            return this.storage.try_set(this.allocator, key, value);
        }

        bool set(K key, V value) @trusted
        {
            return this.storage.set(this.allocator, key, value);
        }

        AddStatus try_add(K key, V value) @trusted
        {
            return this.storage.try_add(this.allocator, key, value);
        }

        bool add(K key, V value) @trusted
        {
            return this.storage.add(this.allocator, key, value);
        }
    }

    /// `key` must be non-null. The returned pointer borrows from this map.
    V* find(scope const(K)* key) return @trusted
    {
        return this.storage.find(key);
    }

    /// `key` must be non-null. The returned pointer borrows from this map.
    const(V)* find(scope const(K)* key) const return @trusted
    {
        return this.storage.find(key);
    }

    /// `key` must be non-null.
    bool contains(scope const(K)* key) const @trusted
    {
        return this.storage.contains(key);
    }

    /// `key` must be non-null.
    bool remove(scope const(K)* key) @trusted
    {
        return this.storage.remove(this.allocator, key);
    }

    /// Pointer and output-storage requirements match unmanaged `take`.
    bool take(scope const(K)* key, scope K* key_output, scope V* value_output) @system
    {
        return this.storage.take(key, key_output, value_output);
    }

    static if (is_simple_hash_value!K)
    {
        V* find(scope K key) return @trusted
        {
            return this.storage.find(key);
        }

        const(V)* find(scope K key) const return @trusted
        {
            return this.storage.find(key);
        }

        bool contains(scope K key) const @trusted
        {
            return this.storage.contains(key);
        }

        bool remove(scope K key) @trusted
        {
            return this.storage.remove(this.allocator, key);
        }

        bool take(scope K key, scope K* key_output, scope V* value_output) @system
        {
            return this.storage.take(&key, key_output, value_output);
        }
    }

    void clear() @trusted
    {
        this.storage.clear(this.allocator);
    }

    bool try_shrink_to_fit() @trusted
    {
        return this.storage.try_shrink_to_fit(this.allocator);
    }

    void shrink_to_fit() @trusted
    {
        this.storage.shrink_to_fit(this.allocator);
    }

    // Foreach is a D language hook.
    i32 opApply(scope i32 delegate(ref const(K), ref V) nothrow @nogc callback)
    {
        return this.storage.opApply(callback);
    }

    i32 opApply(scope i32 delegate(ref const(K), ref const(V)) nothrow @nogc callback) const
    {
        return this.storage.opApply(callback);
    }
}

private bool hash_storage_overlaps(A, B)(
    scope const(A)* left,
    scope const(B)* right,
) pure @system
{
    const left_address = cast(usize) left;
    const right_address = cast(usize) right;
    if (left_address <= right_address) return right_address - left_address < A.sizeof;
    return left_address - right_address < B.sizeof;
}

package(xtb.containers) void require_valid_hash_allocator(Allocator* allocator) @trusted
{
    require(
        allocator !is null && *allocator !is null,
        "HashMap requires a valid allocator",
    );
}

private void construct_hash_move(T)(T* destination, ref T source)
{
    move_emplace(source, *destination);
}

private void replace_hash_element(alias Ops, T)(
    Allocator* allocator,
    T* destination,
    ref T source,
)
{
    Ops.destroy(allocator, destination);
    construct_hash_move(destination, source);
}

private usize maximum_hash_length(usize capacity) pure @safe
{
    return capacity - capacity / 8;
}

private bool capacity_for_length(usize requested, scope ref usize output)
{
    if (requested == 0)
    {
        output = 0;
        return true;
    }

    usize capacity = 8;
    while (maximum_hash_length(capacity) < requested)
    {
        if (capacity > usize.max / 2) return false;
        capacity *= 2;
    }
    output = capacity;
    return true;
}

private usize empty_hash_index(const(SlotState)* states, usize capacity, usize hash) pure
{
    const mask = capacity - 1;
    usize index = hash & mask;
    while (states[index] == SlotState.occupied)
        index = (index + 1) & mask;

    return index;
}

struct HashMapCursor(K, V)
{
    const(SlotState)* states;
    Entry!(K, V)* entries;
    usize capacity;
    usize index;

    private static HashMapCursor create(
        const(SlotState)* states,
        Entry!(K, V)* entries,
        usize capacity,
    )
    {
        auto result = HashMapCursor(states, entries, capacity, 0);
        result.skip_empty();
        return result;
    }

    bool valid() const pure @safe
    {
        return this.index < this.capacity;
    }

    const(K)* key() const return
    {
        require(this.valid, "invalid HashMap cursor");
        return &this.entries[this.index].key;
    }

    V* value() return
    {
        require(this.valid, "invalid HashMap cursor");
        return &this.entries[this.index].value;
    }

    void advance()
    {
        require(this.valid, "invalid HashMap cursor");
        ++this.index;
        this.skip_empty();
    }

    private void skip_empty()
    {
        while (this.index < this.capacity && this.states[this.index] != SlotState.occupied)
            ++this.index;
    }
}

/// Read-only cursor returned by a const map.
struct ConstHashMapCursor(K, V)
{
    const(SlotState)* states;
    const(Entry!(K, V))* entries;
    usize capacity;
    usize index;

    private static ConstHashMapCursor create(
        const(SlotState)* states,
        const(Entry!(K, V))* entries,
        usize capacity,
    )
    {
        auto result = ConstHashMapCursor(states, entries, capacity, 0);
        result.skip_empty();
        return result;
    }

    bool valid() const pure @safe
    {
        return this.index < this.capacity;
    }

    const(K)* key() const return
    {
        require(this.valid, "invalid HashMap cursor");
        return &this.entries[this.index].key;
    }

    const(V)* value() const return
    {
        require(this.valid, "invalid HashMap cursor");
        return &this.entries[this.index].value;
    }

    void advance()
    {
        require(this.valid, "invalid HashMap cursor");
        ++this.index;
        this.skip_empty();
    }

    private void skip_empty()
    {
        while (this.index < this.capacity && this.states[this.index] != SlotState.occupied)
            ++this.index;
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
    HashMapCursor!(K, V) cursor;

    bool empty() const pure @safe
    {
        return !this.cursor.valid;
    }

    HashMapPointerItem!(K, V) front() return
    {
        return HashMapPointerItem!(K, V)(this.cursor.key, this.cursor.value);
    }

    void popFront()
    {
        this.cursor.advance();
    }
}

/// Input range for pointer-oriented const-map iteration.
struct ConstHashMapPointerRange(K, V)
{
    ConstHashMapCursor!(K, V) cursor;

    bool empty() const pure @safe
    {
        return !this.cursor.valid;
    }

    ConstHashMapPointerItem!(K, V) front() const return
    {
        return ConstHashMapPointerItem!(K, V)(this.cursor.key, this.cursor.value);
    }

    void popFront()
    {
        this.cursor.advance();
    }
}

// Everything below here is test-only.
version (unittest)
{
    import xtb.allocators.instrumented;
    import xtb.allocators.malloc;
    import xtb.containers.hash_set;
}

version (unittest)
{
    private struct ConstantIntHash
    {
        usize opCall(scope const(i32)*) const pure nothrow @nogc @safe
        {
            return 1;
        }
    }

    private struct ParityHash
    {
        bool parity;

        usize opCall(scope const(i32)* key) const pure nothrow @nogc @safe
        {
            return this.parity ? cast(usize)(*key & 1) : cast(usize)*key;
        }
    }

    private struct ParityEqual
    {
        bool parity;

        bool opCall(
            scope const(i32)* left,
            scope const(i32)* right,
        ) const pure nothrow @nogc @safe
        {
            return this.parity ? ((*left & 1) == (*right & 1)) : *left == *right;
        }
    }

    private struct CleanupHashPolicy
    {
    nothrow @nogc:

        usize opCall(scope const(i32)* key) const pure @safe
        {
            return cast(usize)*key;
        }

        void deinit()
        {
        }
    }

    private struct TrackedHashValue
    {
    nothrow @nogc:

        i32* destructions;
        i32 value;
        bool active;

        @disable this(this);

        void deinit()
        {
            if (!this.active) return;

            this.active = false;
            ++*this.destructions;
        }
    }

    private struct TrackedHashKey
    {
    nothrow @nogc:

        i32 value;
        i32* live;
        bool active;

        this(i32 value, i32* live)
        {
            this.value = value;
            this.live = live;
            this.active = true;
            ++*this.live;
        }

        @disable this(this);

        void deinit()
        {
            if (!this.active) return;

            this.active = false;
            --*this.live;
        }
    }

    private struct TrackedKeyHash
    {
        usize opCall(scope const(TrackedHashKey)* key) const pure nothrow @nogc @safe
        {
            return cast(usize) key.value;
        }
    }

    private struct TrackedKeyEqual
    {
        bool opCall(
            scope const(TrackedHashKey)* left,
            scope const(TrackedHashKey)* right,
        ) const pure nothrow @nogc @safe
        {
            return left.value == right.value;
        }
    }
}

unittest
{
    auto counts = HashMap!(String, i32).create(malloc_allocator());
    assert(counts.empty);
    assert(counts.find("missing") is null);
    assert(counts.try_set("one", 1) == SetStatus.inserted);
    assert(counts.set("two", 2));
    assert(!counts.set("two", 22));
    assert(*counts.find("two") == 22);
    assert(counts.try_add("two", 222) == AddStatus.already_present);
    assert(counts.add("three", 3));
    assert(counts.contains("one"));
    assert(!counts.contains("four"));

    usize visited;
    i64 total;
    auto cursor = counts.cursor();
    while (cursor.valid)
    {
        ++visited;
        total += *cursor.value;
        *cursor.value += 1;
        cursor.advance();
    }
    assert(visited == counts.length);
    assert(total != 0);
    assert(*counts.find("one") == 2);

    usize foreach_visited;
    foreach (ref const key, ref value; counts)
    {
        assert(key.length != 0);
        value += 10;
        ++foreach_visited;
    }
    assert(foreach_visited == counts.length);
    assert(*counts.find("one") == 12);

    usize pointer_visited;
    foreach (item; counts.pointer_items)
    {
        assert(item.key !is null && item.value !is null);
        *item.value += 100;
        ++pointer_visited;
    }
    assert(pointer_visited == counts.length);
    assert(*counts.find("one") == 112);
    usize break_visited;
    foreach (ref const key, ref value; counts)
    {
        assert(key.length != 0 && value >= 100);
        ++break_visited;
        break;
    }
    assert(break_visited == 1);

    const(HashMap!(String, i32))* read_only_counts = &counts;
    auto read_only_cursor = (*read_only_counts).cursor();
    static assert(is(typeof(read_only_cursor.value()) == const(i32)*));
    assert(read_only_cursor.valid);
    usize const_visited;
    foreach (ref const key, ref const value; *read_only_counts)
    {
        assert(key.length != 0 && value >= 10);
        ++const_visited;
    }
    assert(const_visited == counts.length);
    usize const_pointer_visited;
    foreach (item; (*read_only_counts).pointer_items)
    {
        static assert(is(typeof(item.value) == const(i32)*));
        assert(item.key !is null && item.value !is null);
        ++const_pointer_visited;
    }
    assert(const_pointer_visited == counts.length);

    assert(counts.remove("two"));
    assert(!counts.remove("two"));
    assert(!counts.contains("two"));
    counts.reserve(400);
    assert(counts.capacity >= 400);
    counts.shrink_to_fit();
    assert(counts.capacity >= counts.length);
    counts.clear();
    assert(counts.empty && counts.capacity != 0);
    counts.reset_and_release();
    assert(counts.capacity == 0);

    auto numbers = HashMap!(i32, i32).create(malloc_allocator());
    foreach (value; 0 .. 256)
        assert(numbers.set(value, value * 2));

    foreach (value; 0 .. 256)
        assert(*numbers.find(value) == value * 2);

    auto preallocated = HashMap!(i32, i32).with_capacity(malloc_allocator(), 32);
    assert(preallocated.capacity >= 32);

    i32 first;
    i32 second;
    auto pointers = HashMap!(i32*, i32).create(malloc_allocator());
    pointers.set(&first, 1);
    pointers.set(&second, 2);
    assert(*pointers.find(&first) == 1);
    assert(*pointers.find(&second) == 2);

    numbers.deinit();
    preallocated.deinit();
    pointers.deinit();
}

unittest
{
    alias CollisionMap = HashMap!(i32, i32, ConstantIntHash, DefaultEqual!i32);
    auto collisions = CollisionMap.create(malloc_allocator());
    foreach (value; 0 .. 128)
        assert(collisions.add(value, value * 3));

    foreach (value; 0 .. 128)
        assert(*collisions.find(value) == value * 3);

    foreach (value; 0 .. 128)
    {
        if ((value & 1) == 0) assert(collisions.remove(value));
    }
    foreach (value; 128 .. 192)
        assert(collisions.add(value, value * 3));

    foreach (value; 1 .. 128)
    {
        if ((value & 1) != 0) assert(*collisions.find(value) == value * 3);
    }
    collisions.deinit();

    AllocationRecord[16] records;
    auto allocator = InstrumentedAllocator.create(malloc_allocator(), records[]);
    auto failing = CollisionMap.create(allocator.allocator);
    allocator.fail_after(0);
    assert(failing.try_add(1, 10) == AddStatus.out_of_memory);
    assert(failing.empty && allocator.clean);

    allocator.fail_after(1);
    assert(failing.try_add(1, 10) == AddStatus.out_of_memory);
    assert(failing.empty && allocator.clean);

    allocator.allow_allocations();
    foreach (value; 0 .. 7)
        assert(failing.add(value, value));

    const previous_capacity = failing.capacity;
    allocator.fail_after(0);
    assert(failing.try_add(7, 7) == AddStatus.out_of_memory);
    assert(failing.length == 7 && failing.capacity == previous_capacity);
    assert(failing.try_set(1, 11) == SetStatus.replaced);
    assert(*failing.find(1) == 11);
    assert(!failing.try_reserve(usize.max));
    assert(failing.remove(0));
    assert(!failing.try_shrink_to_fit());
    assert(failing.length == 6 && failing.capacity == previous_capacity);
    foreach (value; 1 .. 7)
        assert(*failing.find(value) == (value == 1 ? 11 : value));

    failing.deinit();
    assert(allocator.clean);
    assert(allocator.stats.invalid_calls == 0);
}

unittest
{
    i32 destructions;
    {
        auto values = OwnedHashMap!(i32, TrackedHashValue).create(malloc_allocator());
        i32 key1 = 1;
        i32 key2 = 2;
        auto value1 = TrackedHashValue(&destructions, 10, true);
        auto value2 = TrackedHashValue(&destructions, 20, true);
        assert(values.add(&key1, &value1));
        assert(values.add(&key2, &value2));
        auto replacement = TrackedHashValue(&destructions, 11, true);
        assert(!values.set(&key1, &replacement));
        assert(destructions == 1);
        assert(values.find(1).value == 11);
        assert(values.remove(2));
        assert(destructions == 2);
        values.clear();
        assert(destructions == 3);
        values.deinit();
    }
    assert(destructions == 3);

    i32 live_keys;
    {
        alias TrackedMap = OwnedHashMap!(
            TrackedHashKey,
            i32,
            TrackedKeyHash,
            TrackedKeyEqual,
        );
        auto tracked_keys = TrackedMap.create(malloc_allocator());
        foreach (value; 0 .. 32)
        {
            auto tracked = TrackedHashKey(value, &live_keys);
            i32 stored = value;
            assert(tracked_keys.add(&tracked, &stored));
        }
        assert(live_keys == 32);
        auto key = TrackedHashKey(7, &live_keys);
        assert(tracked_keys.remove(&key));
        assert(!tracked_keys.contains(&key));
        tracked_keys.clear();
        assert(live_keys == 1);
        deinit(key);
        tracked_keys.deinit();
    }
    assert(live_keys == 0);

    auto values = HashSet!i32.seeded(malloc_allocator(), HashSeed.from_value(123));
    assert(values.add(3));
    assert(!values.add(3));
    assert(values.try_add(7) == AddStatus.inserted);
    assert(values.contains(3) && values.contains(7));
    usize visited;
    auto set_cursor = values.cursor();
    while (set_cursor.valid)
    {
        assert(*set_cursor.value == 3 || *set_cursor.value == 7);
        ++visited;
        set_cursor.advance();
    }
    assert(visited == 2);
    usize foreach_visited;
    foreach (ref const value; values)
    {
        assert(value == 3 || value == 7);
        ++foreach_visited;
    }
    assert(foreach_visited == values.length);
    usize pointer_visited;
    foreach (value; values.pointer_items)
    {
        assert(value !is null && (*value == 3 || *value == 7));
        ++pointer_visited;
    }
    assert(pointer_visited == values.length);
    const(HashSet!i32)* read_only_values = &values;
    usize const_set_visited;
    foreach (ref const value; *read_only_values)
    {
        assert(value == 3 || value == 7);
        ++const_set_visited;
    }
    foreach (value; (*read_only_values).pointer_items)
        assert(value !is null && (*value == 3 || *value == 7));

    assert(const_set_visited == values.length);
    assert(values.remove(3));
    assert(!values.contains(3));
    values.shrink_to_fit();
    values.reset_and_release();
    assert(values.empty && values.capacity == 0);

    auto preallocated = HashSet!i32.with_capacity(malloc_allocator(), 48);
    assert(preallocated.capacity >= 48);
    preallocated.deinit();

    static assert(!__traits(compiles, (ref HashMap!(i32, i32) map)
    {
        HashMap!(i32, i32) copy = map;
    }));
    static assert(!__traits(compiles, (ref HashSet!i32 set)
    {
        HashSet!i32 copy = set;
    }));
}

unittest
{
    alias IntMap = HashMap!(i32, i32);
    alias IntMapStorage = HashMapUnmanaged!(i32, i32);
    alias IntSet = HashSet!i32;
    alias IntSetStorage = HashSetUnmanaged!i32;

    static assert(IntMap.sizeof == IntMapStorage.sizeof + (Allocator*).sizeof);
    static assert(IntSet.sizeof == IntSetStorage.sizeof + (Allocator*).sizeof);
    static assert(!__traits(isCopyable, IntMapStorage));
    static assert(!__traits(compiles, (ref IntMapStorage left, ref IntMapStorage right)
    {
        left = move(right);
    }));
    static assert(!__traits(compiles, HashMapUnmanaged!(
        i32,
        i32,
        CleanupHashPolicy,
        DefaultEqual!i32,
    ).init));
    static assert(!__traits(isCopyable, IntMap));
    static assert(!__traits(isCopyable, IntMap.Released));
    static assert(!__traits(isCopyable, IntSetStorage));
    static assert(!__traits(isCopyable, IntSet));
    static assert(!__traits(isCopyable, IntSet.Released));
    static assert(__traits(compiles, (scope IntMap* value) @safe
    {
        Allocator* allocator = value.allocator;
    }));
    static assert(!__traits(compiles, (scope const IntMap* value) @safe
    {
        Allocator* allocator = value.allocator;
    }));
    static assert(__traits(compiles, (scope IntSet* value) @safe
    {
        Allocator* allocator = value.allocator;
    }));
    static assert(!__traits(compiles, (scope const IntSet* value) @safe
    {
        Allocator* allocator = value.allocator;
    }));
    static assert(__traits(compiles, () @safe
    {
        IntMap.Released released;
        ref IntMapStorage storage = released.storage;
    }));

    IntMapStorage zero_map;
    zero_map.deinit(null);
    IntMapStorage reset_map;
    reset_map.reset_and_release(null);
    assert(reset_map.empty && reset_map.capacity == 0);

    IntSetStorage zero_set;
    zero_set.deinit(null);
    IntSetStorage reset_set;
    reset_set.reset_and_release(null);
    assert(reset_set.empty && reset_set.capacity == 0);

    AllocationRecord[32] records;
    auto tracked = InstrumentedAllocator.create(malloc_allocator(), records[]);

    {
        auto map = IntMap.create(tracked.allocator);
        map.set(1, 10);
        IntMap.Released released = map.release();

        assert(map.allocator is null && map.empty);
        assert(released.allocator is tracked.allocator);
        assert(*released.storage.find(1) == 10);
        released.storage.set(released.allocator, 2, 20);
        assert(*released.storage.find(2) == 20);
        deinit(released);
    }
    assert(tracked.clean);

    {
        auto source = IntMap.create(tracked.allocator);
        source.set(3, 30);
        IntMap.Released released = source.release();
        auto adopted = IntMap.adopt(&released);

        assert(source.allocator is null && source.empty);
        assert(released.allocator is null && released.storage.empty);
        assert(adopted.allocator is tracked.allocator);
        assert(*adopted.find(3) == 30);
        adopted.deinit();
    }
    assert(tracked.clean);

    {
        auto source = IntMap.create(tracked.allocator);
        source.set(4, 40);
        IntMap.Released released = source.release();
        Allocator* allocator;
        IntMapStorage storage = released.extract(&allocator);

        assert(allocator is tracked.allocator);
        assert(released.allocator is null && released.storage.empty);
        storage.set(allocator, 5, 50);
        assert(*storage.find(4) == 40);
        assert(*storage.find(5) == 50);
        storage.deinit(allocator);
    }
    assert(tracked.clean);

    {
        auto set = IntSet.create(tracked.allocator);
        set.add(7);
        IntSet.Released released = set.release();

        assert(set.allocator is null && set.empty);
        assert(released.allocator is tracked.allocator);
        assert(released.storage.contains(7));
        released.storage.add(released.allocator, 8);
        assert(released.storage.contains(8));

        auto adopted = IntSet.adopt(&released);
        assert(released.allocator is null && released.storage.empty);
        assert(adopted.contains(7) && adopted.contains(8));
        adopted.deinit();
    }
    assert(tracked.clean);
}

unittest
{
    alias IntMap = HashMap!(i32, i32);
    alias IntMapStorage = HashMapUnmanaged!(i32, i32);
    alias IntSet = HashSet!i32;
    alias IntSetStorage = HashSetUnmanaged!i32;

    {
        AllocationRecord[8] records;
        auto allocator = InstrumentedAllocator.create(malloc_allocator(), records[]);
        IntMapStorage output;

        allocator.fail_after(0);
        assert(!IntMapStorage.try_with_capacity(allocator.allocator, 32, &output));
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.fail_after(1);
        assert(!IntMapStorage.try_with_capacity(allocator.allocator, 32, &output));
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.allow_allocations();
        assert(IntMapStorage.try_with_capacity(allocator.allocator, 32, &output));
        assert(output.capacity >= 32);
        output.deinit(allocator.allocator);
        assert(allocator.clean && allocator.stats.invalid_calls == 0);
    }

    {
        AllocationRecord[8] records;
        auto allocator = InstrumentedAllocator.create(malloc_allocator(), records[]);
        IntMap output;

        allocator.fail_after(1);
        assert(!IntMap.try_with_capacity(allocator.allocator, 32, &output));
        assert(output.allocator is null);
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.allow_allocations();
        assert(IntMap.try_with_capacity(allocator.allocator, 32, &output));
        assert(output.allocator is allocator.allocator);
        assert(output.capacity >= 32);
        output.deinit();
        assert(allocator.clean && allocator.stats.invalid_calls == 0);
    }

    {
        AllocationRecord[8] records;
        auto allocator = InstrumentedAllocator.create(malloc_allocator(), records[]);
        IntSetStorage output;

        allocator.fail_after(1);
        assert(!IntSetStorage.try_with_capacity(allocator.allocator, 32, &output));
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.allow_allocations();
        assert(IntSetStorage.try_with_capacity(allocator.allocator, 32, &output));
        assert(output.capacity >= 32);
        output.deinit(allocator.allocator);
        assert(allocator.clean && allocator.stats.invalid_calls == 0);
    }

    {
        AllocationRecord[8] records;
        auto allocator = InstrumentedAllocator.create(malloc_allocator(), records[]);
        IntSet output;

        allocator.fail_after(1);
        assert(!IntSet.try_with_capacity(allocator.allocator, 32, &output));
        assert(output.allocator is null);
        assert(output.empty && output.capacity == 0 && allocator.clean);

        allocator.allow_allocations();
        assert(IntSet.try_with_capacity(allocator.allocator, 32, &output));
        assert(output.allocator is allocator.allocator);
        assert(output.capacity >= 32);
        output.deinit();
        assert(allocator.clean && allocator.stats.invalid_calls == 0);
    }
}

unittest
{
    alias ManagedMap = HashMap!(i32, i32);
    alias UnmanagedMap = HashMapUnmanaged!(i32, i32);

    AllocationRecord[128] managed_records;
    AllocationRecord[128] unmanaged_records;
    auto managed_allocator = InstrumentedAllocator.create(malloc_allocator(), managed_records[]);
    auto unmanaged_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        unmanaged_records[],
    );

    auto managed = ManagedMap.create(managed_allocator.allocator);
    UnmanagedMap unmanaged;

    foreach (value; 0 .. 160)
    {
        assert(
            managed.try_set(value, value * 3)
                == unmanaged.try_set(unmanaged_allocator.allocator, value, value * 3)
        );
    }
    foreach (value; 0 .. 80)
    {
        if ((value & 1) == 0)
        {
            assert(
                managed.remove(value)
                    == unmanaged.remove(unmanaged_allocator.allocator, value)
            );
        }
    }
    foreach (value; 80 .. 120)
    {
        assert(
            managed.try_set(value, value * 5)
                == unmanaged.try_set(unmanaged_allocator.allocator, value, value * 5)
        );
    }
    assert(managed.try_reserve(384));
    assert(unmanaged.try_reserve(unmanaged_allocator.allocator, 384));
    assert(managed.try_shrink_to_fit());
    assert(unmanaged.try_shrink_to_fit(unmanaged_allocator.allocator));

    assert(managed.length == unmanaged.length);
    assert(managed.capacity == unmanaged.capacity);
    foreach (value; 0 .. 160)
    {
        const(i32)* managed_value = managed.find(value);
        const(i32)* unmanaged_value = unmanaged.find(value);
        assert((managed_value is null) == (unmanaged_value is null));
        if (managed_value !is null) assert(*managed_value == *unmanaged_value);
    }

    auto managed_cursor = managed.cursor;
    auto unmanaged_cursor = unmanaged.cursor;
    while (managed_cursor.valid || unmanaged_cursor.valid)
    {
        assert(managed_cursor.valid == unmanaged_cursor.valid);
        assert(*managed_cursor.key == *unmanaged_cursor.key);
        assert(*managed_cursor.value == *unmanaged_cursor.value);
        managed_cursor.advance();
        unmanaged_cursor.advance();
    }
    assert(managed_allocator.stats == unmanaged_allocator.stats);

    const managed_stats_before_clear = managed_allocator.stats;
    const unmanaged_stats_before_clear = unmanaged_allocator.stats;
    managed.clear();
    unmanaged.clear(unmanaged_allocator.allocator);
    assert(managed_allocator.stats == managed_stats_before_clear);
    assert(unmanaged_allocator.stats == unmanaged_stats_before_clear);

    managed.deinit();
    unmanaged.deinit(unmanaged_allocator.allocator);
    assert(managed_allocator.stats == unmanaged_allocator.stats);
    assert(managed_allocator.clean && unmanaged_allocator.clean);
}

unittest
{
    alias PolicyMap = HashMap!(i32, i32, ParityHash, ParityEqual);
    alias PolicyStorage = HashMapUnmanaged!(i32, i32, ParityHash, ParityEqual);

    AllocationRecord[32] records;
    auto allocator = InstrumentedAllocator.create(malloc_allocator(), records[]);

    ParityHash parity_hash;
    parity_hash.parity = true;
    ParityEqual parity_equal;
    parity_equal.parity = true;

    auto managed = PolicyMap.with_policies(allocator.allocator, parity_hash, parity_equal);
    managed.set(1, 10);
    assert(managed.find(3) !is null);
    managed.reset_and_release();
    assert(managed.allocator is allocator.allocator);
    managed.set(5, 50);
    assert(managed.find(7) !is null);
    managed.deinit();
    assert(managed.allocator is null && allocator.clean);

    auto unmanaged = PolicyStorage.with_policies(parity_hash, parity_equal);
    unmanaged.set(allocator.allocator, 1, 10);
    assert(unmanaged.find(3) !is null);
    unmanaged.reset_and_release(allocator.allocator);
    unmanaged.set(allocator.allocator, 5, 50);
    assert(unmanaged.find(7) !is null);
    unmanaged.deinit(allocator.allocator);
    assert(allocator.clean && allocator.stats.invalid_calls == 0);
}
