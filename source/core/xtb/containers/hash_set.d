module xtb.containers.hash_set;

nothrow @nogc:

import core.attribute;

import xtb.containers.hash_map;
import xtb.containers.released_storage;
import xtb.hash;
import xtb.lifetime;
import xtb.memory;
import xtb.panic;
import xtb.types;

private struct SetMarker
{
}

/// Allocator-explicit set sharing the probing and lifetime semantics of
/// `HashMapUnmanaged`. Stored values are exposed only as const pointers. Allocator
/// arguments must be valid and must identify the backing map's owner when storage is live.
@mustuse struct HashSetUnmanaged(
    K,
    Hasher = DefaultHash!K,
    Equal = DefaultEqual!K,
    ElementOps = DefaultHashMapElementOps!K,
)
{
    /// Backing map that owns the set's table storage through the supplied allocator.
    HashMapUnmanaged!(
        K,
        SetMarker,
        Hasher,
        Equal,
        K,
        ElementOps,
        DefaultHashMapElementOps!SetMarker,
    ) map;

    @disable this(this);
    @disable ref HashSetUnmanaged opAssign(HashSetUnmanaged source) return;

    static HashSetUnmanaged with_policies(Hasher hasher, Equal equal)
    {
        HashSetUnmanaged result;
        auto storage = typeof(result.map).with_policies(move(hasher), move(equal));
        move_emplace(storage, result.map);
        return move(result);
    }

    /// Attempts to reserve unmanaged set storage for `requested` values.
    ///
    /// `output` must be non-null and point to an inert set: its backing map must own
    /// no table storage and have zero slot counts. On allocation failure, `output`
    /// remains unchanged.
    static bool try_with_capacity(
        Allocator* allocator,
        usize requested,
        scope HashSetUnmanaged* output,
    ) @system
    {
        require(output !is null, "HashSetUnmanaged output pointer is null");
        require(
            output.map.states is null
                && output.map.entries is null
                && output.map.length == 0
                && output.map.removed == 0
                && output.map.capacity == 0,
            "HashSetUnmanaged output is not inert",
        );
        HashSetUnmanaged temporary;
        if (!temporary.try_reserve(allocator, requested)) return false;
        move_emplace(temporary, *output);
        return true;
    }

    static HashSetUnmanaged with_capacity(Allocator* allocator, usize requested)
    {
        HashSetUnmanaged result;
        if (!HashSetUnmanaged.try_with_capacity(allocator, requested, &result))
            panic("HashSet allocation failed");

        return move(result);
    }

    static if (is_default_hash_policy!(Hasher, K) && is_default_equal_policy!(Equal, K))
    {
        static HashSetUnmanaged seeded(HashSeed seed)
        {
            HashSetUnmanaged result;
            auto storage = typeof(result.map).seeded(seed);
            move_emplace(storage, result.map);
            return move(result);
        }

        static HashSetUnmanaged with_capacity(Allocator* allocator, usize requested, HashSeed seed)
        {
            auto result = HashSetUnmanaged.seeded(seed);
            result.reserve(allocator, requested);
            return move(result);
        }
    }

    void deinit(Allocator* allocator)
    {
        this.map.deinit(allocator);
    }

    void reset_and_release(Allocator* allocator)
    {
        this.map.reset_and_release(allocator);
    }

    usize length() const pure @safe
    {
        return this.map.length;
    }

    usize capacity() const pure @safe
    {
        return this.map.capacity;
    }

    bool empty() const pure @safe
    {
        return this.map.empty;
    }

    void pretty_describe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.set(this);
    }

    HashSetCursor!K cursor() return
    {
        return HashSetCursor!K(this.map.cursor());
    }

    ConstHashSetCursor!K cursor() const return
    {
        return ConstHashSetCursor!K(this.map.cursor());
    }

    HashSetPointerRange!K pointer_items() return
    {
        return HashSetPointerRange!K(this.cursor());
    }

    ConstHashSetPointerRange!K pointer_items() const return
    {
        return ConstHashSetPointerRange!K(this.cursor());
    }

    // Foreach is a D language hook.
    i32 opApply(scope i32 delegate(ref const(K)) nothrow @nogc callback)
    {
        HashSetCursor!K current = this.cursor();
        while (current.valid)
        {
            const i32 result = callback(*current.value);
            if (result != 0) return result;
            current.advance();
        }
        return 0;
    }

    i32 opApply(scope i32 delegate(ref const(K)) nothrow @nogc callback) const
    {
        ConstHashSetCursor!K current = this.cursor();
        while (current.valid)
        {
            const i32 result = callback(*current.value);
            if (result != 0) return result;
            current.advance();
        }
        return 0;
    }

    /// `value` must be non-null, must not point into this set's live table storage,
    /// and is consumed only on insertion.
    AddStatus try_add(Allocator* allocator, scope K* value) @system
    {
        SetMarker marker;
        return this.map.try_add(allocator, value, &marker);
    }

    /// `value` must be non-null, must not point into this set's live table storage,
    /// and is consumed only on insertion.
    bool add(Allocator* allocator, scope K* value) @system
    {
        SetMarker marker;
        return this.map.add(allocator, value, &marker);
    }

    static if (is_simple_hash_value!K)
    {
        AddStatus try_add(Allocator* allocator, K value)
        {
            return this.map.try_add(allocator, value, SetMarker.init);
        }

        bool add(Allocator* allocator, K value)
        {
            return this.map.add(allocator, value, SetMarker.init);
        }
    }

    /// `value` must be non-null.
    bool contains(scope const(K)* value) const
    {
        return this.map.contains(value);
    }

    /// `value` must be non-null.
    bool remove(Allocator* allocator, scope const(K)* value)
    {
        return this.map.remove(allocator, value);
    }

    /// Transfers a stored value without running element cleanup.
    ///
    /// `value` and `output` must be non-null and must not overlap. `output` must
    /// point to dead/uninitialized storage outside the set. If `value` is absent,
    /// `output` remains untouched.
    bool take(scope const(K)* value, scope K* output) @system
    {
        SetMarker marker = void;
        return this.map.take(value, output, &marker);
    }

    static if (is_simple_hash_value!K)
    {
        bool contains(scope K value) const
        {
            return this.map.contains(value);
        }

        bool remove(Allocator* allocator, scope K value)
        {
            return this.map.remove(allocator, value);
        }

        /// `output` must be non-null and point to dead/uninitialized storage outside
        /// the set. If `value` is absent, `output` remains untouched.
        bool take(scope K value, scope K* output) @system
        {
            SetMarker marker = void;
            return this.map.take(&value, output, &marker);
        }
    }

    bool try_reserve(Allocator* allocator, usize requested)
    {
        return this.map.try_reserve(allocator, requested);
    }

    void reserve(Allocator* allocator, usize requested)
    {
        this.map.reserve(allocator, requested);
    }

    void clear(Allocator* allocator)
    {
        this.map.clear(allocator);
    }

    bool try_shrink_to_fit(Allocator* allocator)
    {
        return this.map.try_shrink_to_fit(allocator);
    }

    void shrink_to_fit(Allocator* allocator)
    {
        this.map.shrink_to_fit(allocator);
    }
}

/// Managed shallow hash set. Owns table storage but not element cleanup and retains
/// the allocator supplied at construction until storage ownership is released.
@mustuse struct HashSet(K, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
    alias Self = HashSet!(K, Hasher, Equal);
    alias Storage = HashSetUnmanaged!(K, Hasher, Equal);
    alias Released = ReleasedStorage!Storage;

    /// Allocator that owns `storage`; null only for an inert or released value.
    Allocator* allocator;
    /// Backing set storage owned through `allocator` while this value is live.
    Storage storage;

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

    /// Attempts to create an empty managed set with capacity for `requested` values.
    ///
    /// `output` must be non-null and point to an inert set: it must have no allocator
    /// binding or backing storage and zero slot counts. On allocation failure,
    /// `output` remains unchanged.
    static bool try_with_capacity(Allocator* allocator, usize requested, scope Self* output) @system
    {
        require(output !is null, "HashSet output pointer is null");
        require(
            output.allocator is null
                && output.storage.map.states is null
                && output.storage.map.entries is null
                && output.storage.map.length == 0
                && output.storage.map.removed == 0
                && output.storage.map.capacity == 0,
            "HashSet output is not inert",
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
            panic("HashSet allocation failed");

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
        require(released !is null, "released HashSet storage pointer is null");
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

    void pretty_describe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.set(this);
    }

    HashSetCursor!K cursor() return @trusted
    {
        return this.storage.cursor();
    }

    ConstHashSetCursor!K cursor() const return @trusted
    {
        return this.storage.cursor();
    }

    HashSetPointerRange!K pointer_items() return @trusted
    {
        return this.storage.pointer_items();
    }

    ConstHashSetPointerRange!K pointer_items() const return @trusted
    {
        return this.storage.pointer_items();
    }

    /// `value` must be non-null, must not point into this set's live table storage,
    /// and is consumed only on insertion.
    AddStatus try_add(scope K* value) @system
    {
        return this.storage.try_add(this.allocator, value);
    }

    /// `value` must be non-null, must not point into this set's live table storage,
    /// and is consumed only on insertion.
    bool add(scope K* value) @system
    {
        return this.storage.add(this.allocator, value);
    }

    static if (is_simple_hash_value!K)
    {
        AddStatus try_add(K value) @trusted
        {
            return this.storage.try_add(this.allocator, value);
        }

        bool add(K value) @trusted
        {
            return this.storage.add(this.allocator, value);
        }
    }

    /// `value` must be non-null.
    bool contains(scope const(K)* value) const @system
    {
        return this.storage.contains(value);
    }

    /// `value` must be non-null.
    bool remove(scope const(K)* value) @system
    {
        return this.storage.remove(this.allocator, value);
    }

    /// Transfers a stored value without running element cleanup.
    ///
    /// `value` and `output` must be non-null and must not overlap. `output` must
    /// point to dead/uninitialized storage outside the set. If `value` is absent,
    /// `output` remains untouched.
    bool take(scope const(K)* value, scope K* output) @system
    {
        return this.storage.take(value, output);
    }

    static if (is_simple_hash_value!K)
    {
        bool contains(scope K value) const @trusted
        {
            return this.storage.contains(value);
        }

        bool remove(scope K value) @trusted
        {
            return this.storage.remove(this.allocator, value);
        }

        /// `output` must be non-null and point to dead/uninitialized storage outside
        /// the set. If `value` is absent, `output` remains untouched.
        bool take(scope K value, scope K* output) @system
        {
            return this.storage.take(value, output);
        }
    }

    bool try_reserve(usize requested) @trusted
    {
        return this.storage.try_reserve(this.allocator, requested);
    }

    void reserve(usize requested) @trusted
    {
        this.storage.reserve(this.allocator, requested);
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

    i32 opApply(scope i32 delegate(ref const(K)) nothrow @nogc callback)
    {
        return this.storage.opApply(callback);
    }

    i32 opApply(scope i32 delegate(ref const(K)) nothrow @nogc callback) const
    {
        return this.storage.opApply(callback);
    }

    package(xtb.containers) static Self adopt_unmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        require_valid_hash_allocator(allocator);
        require(storage !is null, "HashSetUnmanaged pointer is null");
        Self result;
        result.allocator = allocator;
        move_emplace(*storage, result.storage);
        return move(result);
    }
}

/// Managed hash set that owns cleanup of stored elements and retains the allocator
/// supplied at construction for storage and element cleanup.
@mustuse struct OwnedHashSet(K, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
    static assert(
        can_finalize_without_context!K,
        "OwnedHashSet elements must support context-free finalization",
    );
    alias Self = OwnedHashSet!(K, Hasher, Equal);
    alias Storage = HashSetUnmanaged!(K, Hasher, Equal, OwnedHashMapElementOps!K);

    /// Allocator that owns `storage`; null only while this value is inert.
    Allocator* allocator;
    /// Backing set storage and elements owned through `allocator`.
    Storage storage;

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

    /// Attempts to create an empty owned set with capacity for `requested` values.
    ///
    /// `output` must be non-null and point to an inert set: it must have no allocator
    /// binding or backing storage and zero slot counts. On allocation failure,
    /// `output` remains unchanged.
    static bool try_with_capacity(Allocator* allocator, usize requested, scope Self* output) @system
    {
        require(output !is null, "OwnedHashSet output pointer is null");
        require(
            output.allocator is null
                && output.storage.map.states is null
                && output.storage.map.entries is null
                && output.storage.map.length == 0
                && output.storage.map.removed == 0
                && output.storage.map.capacity == 0,
            "OwnedHashSet output is not inert",
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
            panic("OwnedHashSet allocation failed");

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

    void pretty_describe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.set(this);
    }

    HashSetCursor!K cursor() return @trusted
    {
        return this.storage.cursor();
    }

    ConstHashSetCursor!K cursor() const return @trusted
    {
        return this.storage.cursor();
    }

    HashSetPointerRange!K pointer_items() return @trusted
    {
        return this.storage.pointer_items();
    }

    ConstHashSetPointerRange!K pointer_items() const return @trusted
    {
        return this.storage.pointer_items();
    }

    /// `value` must be non-null, must not point into this set's live table storage,
    /// and is consumed only on insertion.
    AddStatus try_add(scope K* value) @system
    {
        return this.storage.try_add(this.allocator, value);
    }

    /// `value` must be non-null, must not point into this set's live table storage,
    /// and is consumed only on insertion.
    bool add(scope K* value) @system
    {
        return this.storage.add(this.allocator, value);
    }

    static if (is_simple_hash_value!K)
    {
        AddStatus try_add(K value) @trusted
        {
            return this.storage.try_add(this.allocator, value);
        }

        bool add(K value) @trusted
        {
            return this.storage.add(this.allocator, value);
        }
    }

    /// `value` must be non-null.
    bool contains(scope const(K)* value) const @system
    {
        return this.storage.contains(value);
    }

    /// `value` must be non-null.
    bool remove(scope const(K)* value) @system
    {
        return this.storage.remove(this.allocator, value);
    }

    /// Transfers a stored value without running element cleanup.
    ///
    /// `value` and `output` must be non-null and must not overlap. `output` must
    /// point to dead/uninitialized storage outside the set. If `value` is absent,
    /// `output` remains untouched.
    bool take(scope const(K)* value, scope K* output) @system
    {
        return this.storage.take(value, output);
    }

    static if (is_simple_hash_value!K)
    {
        bool contains(scope K value) const @trusted
        {
            return this.storage.contains(value);
        }

        bool remove(scope K value) @trusted
        {
            return this.storage.remove(this.allocator, value);
        }

        /// `output` must be non-null and point to dead/uninitialized storage outside
        /// the set. If `value` is absent, `output` remains untouched.
        bool take(scope K value, scope K* output) @system
        {
            return this.storage.take(value, output);
        }
    }

    bool try_reserve(usize requested) @trusted
    {
        return this.storage.try_reserve(this.allocator, requested);
    }

    void reserve(usize requested) @trusted
    {
        this.storage.reserve(this.allocator, requested);
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

    i32 opApply(scope i32 delegate(ref const(K)) nothrow @nogc callback)
    {
        return this.storage.opApply(callback);
    }

    i32 opApply(scope i32 delegate(ref const(K)) nothrow @nogc callback) const
    {
        return this.storage.opApply(callback);
    }
}

/// Cursor borrowing a set. Structural mutation, storage release, or deinitialization
/// of the originating set invalidates the cursor and pointers obtained from it.
struct HashSetCursor(K)
{
    HashMapCursor!(K, SetMarker) cursor;

    bool valid() const pure @safe
    {
        return this.cursor.valid;
    }

    /// Requires a valid cursor and returns a non-null pointer borrowed from the set.
    const(K)* value() const return
    {
        return this.cursor.key;
    }

    void advance()
    {
        this.cursor.advance();
    }
}

/// Read-only cursor borrowing a const set. Structural mutation, storage release, or
/// deinitialization of the originating set invalidates the cursor and borrowed pointers.
struct ConstHashSetCursor(K)
{
    ConstHashMapCursor!(K, SetMarker) cursor;

    bool valid() const pure @safe
    {
        return this.cursor.valid;
    }

    /// Requires a valid cursor and returns a non-null pointer borrowed from the set.
    const(K)* value() const return
    {
        return this.cursor.key;
    }

    void advance()
    {
        this.cursor.advance();
    }
}

/// Input range borrowing a set and exposing non-null pointers to stored values.
/// The originating set's structural mutation, storage release, or deinitialization
/// invalidates the range and pointers obtained from it.
struct HashSetPointerRange(K)
{
    HashSetCursor!K cursor;

    bool empty() const pure @safe
    {
        return !this.cursor.valid;
    }

    /// Requires a non-empty range and returns a non-null pointer borrowed from the set.
    const(K)* front() const return
    {
        return this.cursor.value;
    }

    // Input-range primitive required by D.
    void popFront()
    {
        this.cursor.advance();
    }
}

/// Input range borrowing a const set and exposing non-null pointers to stored values.
/// The originating set's structural mutation, storage release, or deinitialization
/// invalidates the range and pointers obtained from it.
struct ConstHashSetPointerRange(K)
{
    ConstHashSetCursor!K cursor;

    bool empty() const pure @safe
    {
        return !this.cursor.valid;
    }

    /// Requires a non-empty range and returns a non-null pointer borrowed from the set.
    const(K)* front() const return
    {
        return this.cursor.value;
    }

    // Input-range primitive required by D.
    void popFront()
    {
        this.cursor.advance();
    }
}
