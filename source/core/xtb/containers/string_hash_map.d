module xtb.containers.string_hash_map;

nothrow @nogc:

import core.attribute;

import xtb.containers.hash_map;
import xtb.containers.released_storage;
import xtb.hash;
import xtb.lifetime;
import xtb.memory;
import xtb.panic;
import xtb.string;
import xtb.types;

/// Borrowing string-key map. The map owns the key descriptors but the caller
/// must keep the bytes referenced by every inserted `String` alive.
alias StringViewHashMap(V) = HashMap!(String, V);

/// Unmanaged counterpart of `StringViewHashMap`.
alias StringViewHashMapUnmanaged(V) = HashMapUnmanaged!(String, V);

private struct OwnedStringHash
{
nothrow @nogc:

    HashSeed seed;

    usize opCall(scope const(OwnedStringUnmanaged)* key) const pure @safe
    {
        return hash_value(key.view, this.seed);
    }

    usize opCall(scope const(String)* key) const pure @safe
    {
        return hash_value(*key, this.seed);
    }
}

private struct OwnedStringEqual
{
nothrow @nogc:

    bool opCall(
        scope const(OwnedStringUnmanaged)* left,
        scope const(OwnedStringUnmanaged)* right,
    ) const pure @safe
    {
        return left.view.equal(right.view);
    }

    bool opCall(
        scope const(OwnedStringUnmanaged)* left,
        scope const(String)* right,
    ) const pure @safe
    {
        return left.view.equal(*right);
    }
}

private struct OwnedStringElementOps
{
nothrow @nogc:

    static void destroy(
        Allocator* allocator,
        OwnedStringUnmanaged* key,
    )
    {
        key.deinit(allocator);
    }
}

private struct OwnedStringHashMapValueOps(T)
{
nothrow @nogc:

    static assert(
        can_finalize_without_context!T,
        "OwnedStringHashMap values must support context-free finalization",
    );

    static void destroy(Allocator*, T* value)
    {
        static if (needs_finalization!T)
            finalize(*value);
    }
}

private template is_simple_string_hash_value(T)
{
    enum is_simple_string_hash_value = __traits(isCopyable, T)
        && !needs_deinit!T
        && !has_d_destructor!T;
}

private template OwnedStringMapStorage(V, ValueOps)
{
    alias OwnedStringMapStorage = HashMapUnmanaged!(
        OwnedStringUnmanaged,
        V,
        OwnedStringHash,
        OwnedStringEqual,
        String,
        OwnedStringElementOps,
        ValueOps,
    );
}

private enum MoveKeyStatus : u8
{
    inserted,
    existing,
    out_of_memory,
}

private enum ExistingKeyMode
{
    keep,
    replace,
}

/// Allocator-explicit map that owns an exact immutable allocation for every
/// nonempty string key while accepting borrowed `String` lookup values.
@mustuse struct StringHashMapUnmanaged(V, ValueOps = DefaultHashMapElementOps!V)
{
nothrow @nogc:

    OwnedStringMapStorage!(V, ValueOps) map;

    invariant
    {
        require(&this !is null, "StringHashMapUnmanaged pointer is null");
    }

    @disable this(this);
    @disable ref StringHashMapUnmanaged opAssign(StringHashMapUnmanaged source) return;

    static StringHashMapUnmanaged seeded(HashSeed seed)
    {
        OwnedStringHash hasher;
        hasher.seed = seed;
        StringHashMapUnmanaged result;
        auto map = typeof(result.map).with_policies(
            hasher,
            OwnedStringEqual.init,
        );
        move_emplace(map, result.map);
        return move(result);
    }

    static bool try_with_capacity(
        Allocator* allocator,
        usize requested,
        scope StringHashMapUnmanaged* output,
    )
    {
        require(
            output !is null,
            "StringHashMapUnmanaged output pointer is null",
        );
        require(
            output.map.capacity == 0 && output.map.empty,
            "StringHashMapUnmanaged output is not empty",
        );
        StringHashMapUnmanaged temporary;
        if (!temporary.try_reserve(allocator, requested))
            return false;

        move_emplace(temporary, *output);
        return true;
    }

    static StringHashMapUnmanaged with_capacity(
        Allocator* allocator,
        usize requested,
    )
    {
        StringHashMapUnmanaged result;
        if (!StringHashMapUnmanaged.try_with_capacity(allocator, requested, &result))
            panic("StringHashMap allocation failed");

        return move(result);
    }

    static StringHashMapUnmanaged with_capacity(
        Allocator* allocator,
        usize requested,
        HashSeed seed,
    )
    {
        StringHashMapUnmanaged result = StringHashMapUnmanaged.seeded(seed);
        result.reserve(allocator, requested);
        return move(result);
    }

    void deinit(Allocator* allocator) @trusted
    {
        this.map.deinit(allocator);
    }

    void reset_and_release(Allocator* allocator) @trusted
    {
        this.map.reset_and_release(allocator);
    }

    usize length() const pure @trusted
    {
        return this.map.length;
    }

    usize capacity() const pure @trusted
    {
        return this.map.capacity;
    }

    bool empty() const pure @trusted
    {
        return this.map.empty;
    }

    void pretty_describe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.map(this);
    }

    StringHashMapCursor!V cursor() return @trusted
    {
        return StringHashMapCursor!V.create(this.map.cursor());
    }

    ConstStringHashMapCursor!V cursor() const return @trusted
    {
        return ConstStringHashMapCursor!V.create(this.map.cursor());
    }

    StringHashMapPointerRange!V pointer_items() return @trusted
    {
        return StringHashMapPointerRange!V(this.cursor());
    }

    ConstStringHashMapPointerRange!V pointer_items() const return @trusted
    {
        return ConstStringHashMapPointerRange!V(this.cursor());
    }

    /// Fallible insertion that consumes `*value` only on success.
    AddStatus try_add(
        Allocator* allocator,
        scope String key,
        scope V* value,
    ) @system
    {
        require(value !is null, "StringHashMap value pointer is null");
        require(
            !this.map.aliases_entry_storage(key.ptr),
            "StringHashMap key bytes alias table storage",
        );
        if (this.map.aliases_entry_storage(value))
        {
            require(
                this.map.find(key) !is null,
                "StringHashMap insertion value aliases table storage",
            );
        }

        PreparedHashMapInsert prepared;
        final switch (this.map.prepare_insert(allocator, key, &prepared))
        {
        case PrepareInsertStatus.already_present:
            return AddStatus.already_present;
        case PrepareInsertStatus.out_of_memory:
            return AddStatus.out_of_memory;
        case PrepareInsertStatus.ready:
            break;
        }

        OwnedStringUnmanaged owned;
        if (!OwnedStringUnmanaged.try_from_string(allocator, key, &owned))
            return AddStatus.out_of_memory;

        this.map.commit_prepared_insert(&prepared, &owned, value);
        return AddStatus.inserted;
    }

    bool add(
        Allocator* allocator,
        scope String key,
        scope V* value,
    ) @system
    {
        const status = this.try_add(allocator, key, value);
        if (status == AddStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == AddStatus.inserted;
    }

    /// Fallible insert-or-replace. Replacement consumes only `*value`.
    SetStatus try_set(
        Allocator* allocator,
        scope String key,
        scope V* value,
    ) @system
    {
        require(value !is null, "StringHashMap value pointer is null");
        require(
            !this.map.aliases_entry_storage(key.ptr),
            "StringHashMap key bytes alias table storage",
        );
        if (this.map.aliases_entry_storage(value))
        {
            V* destination = this.map.find(key);
            require(
                destination !is null && value is destination,
                "StringHashMap replacement value aliases another table entry",
            );
        }

        PreparedHashMapInsert prepared;
        final switch (this.map.prepare_insert(allocator, key, &prepared))
        {
        case PrepareInsertStatus.already_present:
            this.map.replace_prepared_value(allocator, &prepared, value);
            return SetStatus.replaced;
        case PrepareInsertStatus.out_of_memory:
            return SetStatus.out_of_memory;
        case PrepareInsertStatus.ready:
            break;
        }

        OwnedStringUnmanaged owned;
        if (!OwnedStringUnmanaged.try_from_string(allocator, key, &owned))
            return SetStatus.out_of_memory;

        this.map.commit_prepared_insert(&prepared, &owned, value);
        return SetStatus.inserted;
    }

    bool set(
        Allocator* allocator,
        scope String key,
        scope V* value,
    ) @system
    {
        const status = this.try_set(allocator, key, value);
        if (status == SetStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == SetStatus.inserted;
    }

    static if (is_simple_string_hash_value!V)
    {
        AddStatus try_add(Allocator* allocator, scope String key, V value) @trusted
        {
            return this.try_add(allocator, key, &value);
        }

        bool add(Allocator* allocator, scope String key, V value) @trusted
        {
            return this.add(allocator, key, &value);
        }

        SetStatus try_set(Allocator* allocator, scope String key, V value) @trusted
        {
            return this.try_set(allocator, key, &value);
        }

        bool set(Allocator* allocator, scope String key, V value) @trusted
        {
            return this.set(allocator, key, &value);
        }
    }

    V* find(scope String key) return @trusted
    {
        return this.map.find(key);
    }

    const(V)* find(scope String key) const return @trusted
    {
        return this.map.find(key);
    }

    bool contains(scope String key) const @trusted
    {
        return this.map.contains(key);
    }

    bool remove(Allocator* allocator, scope String key) @trusted
    {
        return this.map.remove(allocator, key);
    }

    void clear(Allocator* allocator) @trusted
    {
        this.map.clear(allocator);
    }

    bool try_reserve(Allocator* allocator, usize requested) @trusted
    {
        return this.map.try_reserve(allocator, requested);
    }

    void reserve(Allocator* allocator, usize requested) @trusted
    {
        this.map.reserve(allocator, requested);
    }

    bool try_shrink_to_fit(Allocator* allocator) @trusted
    {
        return this.map.try_shrink_to_fit(allocator);
    }

    void shrink_to_fit(Allocator* allocator) @trusted
    {
        this.map.shrink_to_fit(allocator);
    }

    AddStatus try_add_move(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
    ) @trusted
    {
        const status = this.try_move_owned_string(
            allocator,
            key,
            value,
            ExistingKeyMode.keep,
        );
        final switch (status)
        {
        case MoveKeyStatus.inserted:
            return AddStatus.inserted;
        case MoveKeyStatus.existing:
            return AddStatus.already_present;
        case MoveKeyStatus.out_of_memory:
            return AddStatus.out_of_memory;
        }
    }

    bool add_move(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
    ) @trusted
    {
        const status = this.try_add_move(allocator, key, value);
        if (status == AddStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == AddStatus.inserted;
    }

    SetStatus try_set_move(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
    ) @trusted
    {
        const status = this.try_move_owned_string(
            allocator,
            key,
            value,
            ExistingKeyMode.replace,
        );
        final switch (status)
        {
        case MoveKeyStatus.inserted:
            return SetStatus.inserted;
        case MoveKeyStatus.existing:
            return SetStatus.replaced;
        case MoveKeyStatus.out_of_memory:
            return SetStatus.out_of_memory;
        }
    }

    bool set_move(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
    ) @trusted
    {
        const status = this.try_set_move(allocator, key, value);
        if (status == SetStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == SetStatus.inserted;
    }

    AddStatus try_add_move(
        Allocator* allocator,
        scope StringBuf* key,
        scope V* value,
    ) @trusted
    {
        const status = this.try_move_string_buf(
            allocator,
            key,
            value,
            ExistingKeyMode.keep,
        );
        final switch (status)
        {
        case MoveKeyStatus.inserted:
            return AddStatus.inserted;
        case MoveKeyStatus.existing:
            return AddStatus.already_present;
        case MoveKeyStatus.out_of_memory:
            return AddStatus.out_of_memory;
        }
    }

    bool add_move(
        Allocator* allocator,
        scope StringBuf* key,
        scope V* value,
    ) @trusted
    {
        const status = this.try_add_move(allocator, key, value);
        if (status == AddStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == AddStatus.inserted;
    }

    SetStatus try_set_move(
        Allocator* allocator,
        scope StringBuf* key,
        scope V* value,
    ) @trusted
    {
        const status = this.try_move_string_buf(
            allocator,
            key,
            value,
            ExistingKeyMode.replace,
        );
        final switch (status)
        {
        case MoveKeyStatus.inserted:
            return SetStatus.inserted;
        case MoveKeyStatus.existing:
            return SetStatus.replaced;
        case MoveKeyStatus.out_of_memory:
            return SetStatus.out_of_memory;
        }
    }

    bool set_move(
        Allocator* allocator,
        scope StringBuf* key,
        scope V* value,
    ) @trusted
    {
        const status = this.try_set_move(allocator, key, value);
        if (status == SetStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == SetStatus.inserted;
    }

    i32 opApply(
        scope i32 delegate(ref const(String), ref V) nothrow @nogc @system callback,
    )
    {
        auto current = this.map.cursor();
        while (current.valid)
        {
            const String key = current.key.view;
            const result = callback(key, *current.value);
            if (result != 0)
                return result;

            current.advance();
        }
        return 0;
    }

    i32 opApply(
        scope i32 delegate(ref const(String), ref const(V)) nothrow @nogc @system callback,
    ) const
    {
        auto current = this.map.cursor();
        while (current.valid)
        {
            const String key = current.key.view;
            const result = callback(key, *current.value);
            if (result != 0)
                return result;

            current.advance();
        }
        return 0;
    }

    private MoveKeyStatus try_move_owned_string(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
        ExistingKeyMode existing_key_mode,
    ) @trusted
    {
        require_valid_string_hash_map_allocator(allocator);
        require(key !is null, "OwnedString key pointer is null");
        require(value !is null, "StringHashMap value pointer is null");
        require(
            !string_hash_storage_overlaps(key, value),
            "StringHashMap key and value storage overlap",
        );
        require(
            !this.map.aliases_entry_storage(key),
            "StringHashMap move key aliases table storage",
        );
        if (this.map.aliases_entry_storage(value))
        {
            V* existing_value = this.map.find(key.view);
            require(
                existing_value !is null
                    && (existing_key_mode == ExistingKeyMode.keep
                        || value is existing_value),
                "StringHashMap value aliases incompatible table storage",
            );
        }

        PreparedHashMapInsert prepared;
        const status = this.map.prepare_insert(allocator, key.view, &prepared);
        if (status == PrepareInsertStatus.already_present)
        {
            if (existing_key_mode == ExistingKeyMode.keep)
                return MoveKeyStatus.existing;

            this.map.replace_prepared_value(allocator, &prepared, value);
            return MoveKeyStatus.existing;
        }
        if (status == PrepareInsertStatus.out_of_memory)
            return MoveKeyStatus.out_of_memory;

        OwnedStringUnmanaged owned;
        if (key.allocator is allocator)
        {
            auto released = key.release();
            Allocator* source_allocator;
            auto extracted = released.extract(&source_allocator);
            move_emplace(extracted, owned);
            require(source_allocator is allocator, "OwnedString allocator changed during release");
        }
        else
        {
            if (!OwnedStringUnmanaged.try_from_string(allocator, key.view, &owned))
                return MoveKeyStatus.out_of_memory;
        }

        this.map.commit_prepared_insert(&prepared, &owned, value);
        if (key.allocator !is null)
            key.deinit();

        return MoveKeyStatus.inserted;
    }

    private MoveKeyStatus try_move_string_buf(
        Allocator* destination,
        scope StringBuf* key,
        scope V* value,
        ExistingKeyMode existing_key_mode,
    ) @trusted
    {
        require_valid_string_hash_map_allocator(destination);
        require(key !is null, "StringBuf key pointer is null");
        require(value !is null, "StringHashMap value pointer is null");
        require(
            !string_hash_storage_overlaps(key, value),
            "StringHashMap key and value storage overlap",
        );
        require(
            !this.map.aliases_entry_storage(key),
            "StringHashMap move key aliases table storage",
        );
        if (this.map.aliases_entry_storage(value))
        {
            V* existing_value = this.map.find(key.view);
            require(
                existing_value !is null
                    && (existing_key_mode == ExistingKeyMode.keep
                        || value is existing_value),
                "StringHashMap value aliases incompatible table storage",
            );
        }

        PreparedHashMapInsert prepared;
        const status = this.map.prepare_insert(destination, key.view, &prepared);
        if (status == PrepareInsertStatus.already_present)
        {
            if (existing_key_mode == ExistingKeyMode.keep)
                return MoveKeyStatus.existing;

            this.map.replace_prepared_value(destination, &prepared, value);
            return MoveKeyStatus.existing;
        }
        if (status == PrepareInsertStatus.out_of_memory)
            return MoveKeyStatus.out_of_memory;

        OwnedStringUnmanaged owned;
        if (!key.empty
            && key.allocator is destination
            && (key.byte_capacity == key.byte_length || key.try_shrink_to_fit()))
        {
            auto released = key.release();
            Allocator* source_allocator;
            StringBufUnmanaged raw = released.extract(&source_allocator);
            require(source_allocator is destination, "StringBuf allocator changed during release");
            auto exact = raw.release_exact_storage();
            auto adopted = OwnedStringUnmanaged.adopt_exact(&exact);
            move_emplace(adopted, owned);
        }
        else
        {
            if (!OwnedStringUnmanaged.try_from_string(destination, key.view, &owned))
                return MoveKeyStatus.out_of_memory;
        }

        this.map.commit_prepared_insert(&prepared, &owned, value);
        if (key.allocator !is null)
            key.deinit();

        return MoveKeyStatus.inserted;
    }
}

@mustuse package(xtb) struct BasicStringHashMap(V, ValueOps, bool owns_values)
{
nothrow @nogc:

    alias Self = BasicStringHashMap!(V, ValueOps, owns_values);
    alias Storage = StringHashMapUnmanaged!(V, ValueOps);
    static if (!owns_values)
        alias Released = ReleasedStorage!Storage;

    Allocator* allocator;
    Storage storage;

    invariant
    {
        require(&this !is null, "StringHashMap pointer is null");
    }

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(Allocator* allocator) @trusted
    {
        require_valid_string_hash_map_allocator(allocator);
        Self result;
        result.allocator = allocator;
        return result;
    }

    static Self seeded(Allocator* allocator, HashSeed seed) @trusted
    {
        require_valid_string_hash_map_allocator(allocator);
        Self result;
        result.allocator = allocator;
        Storage storage = Storage.seeded(seed);
        move_emplace(storage, result.storage);
        return move(result);
    }

    static bool try_with_capacity(
        Allocator* allocator,
        usize requested,
        scope Self* output,
    ) @trusted
    {
        require(output !is null, "StringHashMap output pointer is null");
        require(
            output.allocator is null,
            "StringHashMap output is already initialized",
        );
        Storage storage;
        if (!Storage.try_with_capacity(allocator, requested, &storage))
            return false;

        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static Self with_capacity(
        Allocator* allocator,
        usize requested,
    ) @trusted
    {
        Self result;
        if (!Self.try_with_capacity(allocator, requested, &result))
            panic("StringHashMap allocation failed");

        return move(result);
    }

    static Self with_capacity(
        Allocator* allocator,
        usize requested,
        HashSeed seed,
    ) @trusted
    {
        Self result;
        result.allocator = allocator;
        Storage storage = Storage.with_capacity(
            allocator,
            requested,
            seed,
        );
        move_emplace(storage, result.storage);
        return move(result);
    }

    static if (!owns_values)
    {
        static Self adopt(scope Released* released) @trusted
        {
            require(
                released !is null,
                "released StringHashMap storage pointer is null",
            );
            Allocator* allocator;
            Storage storage = released.extract(&allocator);
            Self result;
            result.allocator = allocator;
            move_emplace(storage, result.storage);
            return move(result);
        }
    }

    void deinit() @trusted
    {
        if (this.allocator is null)
            return;

        this.storage.deinit(this.allocator);
        this.allocator = null;
    }

    void reset_and_release() @trusted
    {
        this.storage.reset_and_release(this.allocator);
    }

    static if (!owns_values)
    {
        Released release() @trusted
        {
            auto result = Released.from_owned_parts(this.allocator, &this.storage);
            this.allocator = null;
            return move(result);
        }
    }

    usize length() const pure @trusted
    {
        return this.storage.length;
    }

    usize capacity() const pure @trusted
    {
        return this.storage.capacity;
    }

    bool empty() const pure @trusted
    {
        return this.storage.empty;
    }

    void pretty_describe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.map(this);
    }

    StringHashMapCursor!V cursor() return @trusted
    {
        return this.storage.cursor;
    }

    ConstStringHashMapCursor!V cursor() const return @trusted
    {
        return this.storage.cursor;
    }

    StringHashMapPointerRange!V pointer_items() return @trusted
    {
        return this.storage.pointer_items;
    }

    ConstStringHashMapPointerRange!V pointer_items() const return @trusted
    {
        return this.storage.pointer_items;
    }

    AddStatus try_add(scope String key, scope V* value) @system
    {
        return this.storage.try_add(this.allocator, key, value);
    }

    bool add(scope String key, scope V* value) @system
    {
        return this.storage.add(this.allocator, key, value);
    }

    SetStatus try_set(scope String key, scope V* value) @system
    {
        return this.storage.try_set(this.allocator, key, value);
    }

    bool set(scope String key, scope V* value) @system
    {
        return this.storage.set(this.allocator, key, value);
    }

    static if (is_simple_string_hash_value!V)
    {
        AddStatus try_add(scope String key, V value) @trusted
        {
            return this.storage.try_add(this.allocator, key, value);
        }

        bool add(scope String key, V value) @trusted
        {
            return this.storage.add(this.allocator, key, value);
        }

        SetStatus try_set(scope String key, V value) @trusted
        {
            return this.storage.try_set(this.allocator, key, value);
        }

        bool set(scope String key, V value) @trusted
        {
            return this.storage.set(this.allocator, key, value);
        }
    }

    V* find(scope String key) return @trusted
    {
        return this.storage.find(key);
    }

    const(V)* find(scope String key) const return @trusted
    {
        return this.storage.find(key);
    }

    bool contains(scope String key) const @trusted
    {
        return this.storage.contains(key);
    }

    bool remove(scope String key) @trusted
    {
        return this.storage.remove(this.allocator, key);
    }

    void clear() @trusted
    {
        this.storage.clear(this.allocator);
    }

    bool try_reserve(usize requested) @trusted
    {
        return this.storage.try_reserve(this.allocator, requested);
    }

    void reserve(usize requested) @trusted
    {
        this.storage.reserve(this.allocator, requested);
    }

    bool try_shrink_to_fit() @trusted
    {
        return this.storage.try_shrink_to_fit(this.allocator);
    }

    void shrink_to_fit() @trusted
    {
        this.storage.shrink_to_fit(this.allocator);
    }

    AddStatus try_add_move(scope OwnedString* key, scope V* value) @trusted
    {
        return this.storage.try_add_move(this.allocator, key, value);
    }

    bool add_move(scope OwnedString* key, scope V* value) @trusted
    {
        const status = this.try_add_move(key, value);
        if (status == AddStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == AddStatus.inserted;
    }

    SetStatus try_set_move(scope OwnedString* key, scope V* value) @trusted
    {
        return this.storage.try_set_move(this.allocator, key, value);
    }

    bool set_move(scope OwnedString* key, scope V* value) @trusted
    {
        const status = this.try_set_move(key, value);
        if (status == SetStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == SetStatus.inserted;
    }

    AddStatus try_add_move(scope StringBuf* key, scope V* value) @trusted
    {
        return this.storage.try_add_move(this.allocator, key, value);
    }

    bool add_move(scope StringBuf* key, scope V* value) @trusted
    {
        const status = this.try_add_move(key, value);
        if (status == AddStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == AddStatus.inserted;
    }

    SetStatus try_set_move(scope StringBuf* key, scope V* value) @trusted
    {
        return this.storage.try_set_move(this.allocator, key, value);
    }

    bool set_move(scope StringBuf* key, scope V* value) @trusted
    {
        const status = this.try_set_move(key, value);
        if (status == SetStatus.out_of_memory)
            panic("StringHashMap allocation failed");

        return status == SetStatus.inserted;
    }

    i32 opApply(
        scope i32 delegate(ref const(String), ref V) nothrow @nogc @system callback,
    )
    {
        return this.storage.opApply(callback);
    }

    i32 opApply(
        scope i32 delegate(ref const(String), ref const(V)) nothrow @nogc @system callback,
    ) const
    {
        return this.storage.opApply(callback);
    }

    static if (!owns_values)
    {
        package(xtb.containers) static Self adopt_unmanaged(
            Allocator* allocator,
            scope Storage* storage,
        ) @system
        {
            require_valid_string_hash_map_allocator(allocator);
            require(
                storage !is null,
                "StringHashMapUnmanaged pointer is null",
            );
            Self result;
            result.allocator = allocator;
            move_emplace(*storage, result.storage);
            return move(result);
        }
    }
}

private bool string_hash_storage_overlaps(A, B)(
    scope const(A)* left,
    scope const(B)* right,
) pure @system
{
    const left_address = cast(usize) left;
    const right_address = cast(usize) right;
    if (left_address <= right_address)
        return right_address - left_address < A.sizeof;

    return left_address - right_address < B.sizeof;
}

private void require_valid_string_hash_map_allocator(Allocator* allocator) @trusted
{
    require(
        allocator !is null && *allocator !is null,
        "StringHashMap requires a valid allocator",
    );
}

/// Explicit owner for string keys with shallow value-discard semantics.
/// Owns exact immutable key allocations and backing storage, but never
/// deinitializes values merely because an entry is discarded.
alias StringHashMap(V) = BasicStringHashMap!(
    V,
    DefaultHashMapElementOps!V,
    false,
);

/// Explicit owner for string keys and values. Values are deinitialized when
/// entries are discarded; rehash and transfer operations only relocate them.
alias OwnedStringHashMap(V) = BasicStringHashMap!(
    V,
    OwnedStringHashMapValueOps!V,
    true,
);

struct StringHashMapCursor(V)
{
nothrow @nogc:

    HashMapCursor!(OwnedStringUnmanaged, V) cursor;

    private static StringHashMapCursor create(
        HashMapCursor!(OwnedStringUnmanaged, V) cursor,
    )
    {
        StringHashMapCursor result;
        result.cursor = cursor;
        return result;
    }

    bool valid() const pure @safe
    {
        return this.cursor.valid;
    }

    const(String)* key() const return @trusted
    {
        require(this.valid, "invalid StringHashMap cursor");
        return this.cursor.key.view_pointer;
    }

    V* value() return
    {
        return this.cursor.value;
    }

    void advance()
    {
        this.cursor.advance();
    }
}

struct ConstStringHashMapCursor(V)
{
nothrow @nogc:

    ConstHashMapCursor!(OwnedStringUnmanaged, V) cursor;

    private static ConstStringHashMapCursor create(
        ConstHashMapCursor!(OwnedStringUnmanaged, V) cursor,
    )
    {
        ConstStringHashMapCursor result;
        result.cursor = cursor;
        return result;
    }

    bool valid() const pure @safe
    {
        return this.cursor.valid;
    }

    const(String)* key() const return @trusted
    {
        require(this.valid, "invalid StringHashMap cursor");
        return this.cursor.key.view_pointer;
    }

    const(V)* value() const return
    {
        return this.cursor.value;
    }

    void advance()
    {
        this.cursor.advance();
    }
}

struct StringHashMapPointerItem(V)
{
    const(String)* key;
    V* value;
}

struct ConstStringHashMapPointerItem(V)
{
    const(String)* key;
    const(V)* value;
}

struct StringHashMapPointerRange(V)
{
    StringHashMapCursor!V cursor;

    bool empty() const pure @safe
    {
        return !this.cursor.valid;
    }

    StringHashMapPointerItem!V front() return
    {
        return StringHashMapPointerItem!V(this.cursor.key, this.cursor.value);
    }

    void popFront()
    {
        this.cursor.advance();
    }
}

struct ConstStringHashMapPointerRange(V)
{
    ConstStringHashMapCursor!V cursor;

    bool empty() const pure @safe
    {
        return !this.cursor.valid;
    }

    ConstStringHashMapPointerItem!V front() const return
    {
        return ConstStringHashMapPointerItem!V(this.cursor.key, this.cursor.value);
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
}

unittest
{
    static assert(is(StringViewHashMap!i32 == HashMap!(String, i32)));
    static assert(!__traits(isCopyable, StringHashMap!i32));

    enum unmanaged_assignment_compiles = __traits(
        compiles,
        (ref StringHashMapUnmanaged!i32 left, ref StringHashMapUnmanaged!i32 right)
        {
            left = move(right);
        },
    );
    static assert(!unmanaged_assignment_compiles);

    enum mutable_allocator_access_compiles = __traits(
        compiles,
        (scope StringHashMap!i32* value) @safe
        {
            Allocator* allocator = value.allocator;
        },
    );
    static assert(mutable_allocator_access_compiles);

    enum const_allocator_access_compiles = __traits(
        compiles,
        (scope const StringHashMap!i32* value) @safe
        {
            Allocator* allocator = value.allocator;
        },
    );
    static assert(!const_allocator_access_compiles);

    StringHashMap!i32 values = StringHashMap!i32.create(malloc_allocator());
    StringBuf source = StringBuf.from_string(malloc_allocator(), "alpha");
    source.shrink_to_fit();
    const source_pointer = source.view.ptr;
    i32 first = 1;
    assert(values.add_move(&source, &first));
    assert(source.allocator is null && source.empty);
    assert(values.find("alpha") !is null && *values.find("alpha") == 1);

    auto cursor = values.cursor();
    assert(cursor.valid && *cursor.key == "alpha");
    assert((*cursor.key).ptr is source_pointer);

    StringBuf duplicate = StringBuf.from_string(malloc_allocator(), "alpha");
    i32 duplicate_value = 2;
    assert(
        values.try_add_move(&duplicate, &duplicate_value) == AddStatus.already_present,
    );
    assert(duplicate.view == "alpha" && duplicate_value == 2);

    String mutable_source = "beta";
    assert(values.add(mutable_source, 3));
    assert(values.contains("beta"));
    assert(values.remove("alpha"));
    assert(!values.contains("alpha"));
    duplicate.deinit();
    values.deinit();
}

unittest
{
    OwnedStringHashMap!StringBuf values = OwnedStringHashMap!StringBuf.create(malloc_allocator());
    StringBuf key = StringBuf.from_string(malloc_allocator(), "self");
    StringBuf payload = StringBuf.from_string(malloc_allocator(), "payload");
    assert(values.add_move(&key, &payload));

    StringBuf* stored = values.find("self");
    assert(stored !is null && stored.view == "payload");
    assert(values.try_add("self", stored) == AddStatus.already_present);
    assert(values.try_set("self", stored) == SetStatus.replaced);
    StringBuf replacement_key = StringBuf.from_string(malloc_allocator(), "self");
    assert(values.try_set_move(&replacement_key, stored) == SetStatus.replaced);
    assert(stored.view == "payload");
    assert(replacement_key.view == "self" && replacement_key.allocator !is null);

    replacement_key.deinit();
    values.deinit();
}

unittest
{
    Allocator* allocator = malloc_allocator();
    StringHashMapUnmanaged!i32 values;
    StringBuf source = StringBuf.from_string(allocator, "unmanaged");
    source.shrink_to_fit();
    const source_pointer = source.view.ptr;
    i32 value = 42;

    assert(values.try_add_move(allocator, &source, &value) == AddStatus.inserted);
    assert(source.allocator is null);
    StringHashMapUnmanaged!i32* values_pointer = &values;
    assert(values_pointer.length == 1);
    assert(values_pointer.contains("unmanaged"));
    assert(
        values_pointer.find("unmanaged") !is null
            && *values_pointer.find("unmanaged") == 42,
    );
    assert((*values_pointer.cursor.key).ptr is source_pointer);

    const(StringHashMapUnmanaged!i32)* const_values_pointer = &values;
    assert(const_values_pointer.length == 1);
    assert(const_values_pointer.contains("unmanaged"));

    values_pointer.deinit(allocator);
}

unittest
{
    AllocationRecord[128] map_records;
    AllocationRecord[32] foreign_records;
    InstrumentedAllocator map_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        map_records[],
    );
    InstrumentedAllocator foreign_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        foreign_records[],
    );

    StringHashMap!i32 values = StringHashMap!i32.create(map_allocator.allocator);
    StringBuf exact = StringBuf.from_string(map_allocator.allocator, "stable");
    const(char)* exact_pointer;
    {
        exact.shrink_to_fit();
        exact_pointer = exact.view.ptr;
    }
    i32 first = 1;
    assert(values.try_add_move(&exact, &first) == AddStatus.inserted);
    {

        assert(exact.allocator is null && exact.empty);
    }
    assert((*values.cursor.key).ptr is exact_pointer);

    String[12] additional = [
        "a",
        "b",
        "c",
        "d",
        "e",
        "f",
        "g",
        "h",
        "i",
        "j",
        "k",
        "l",
    ];
    foreach (index, key; additional)
        assert(values.add(key, cast(i32) index));

    const stable = values.find("stable");
    assert(stable !is null && *stable == 1);
    auto current = values.cursor();
    const(char)* stable_pointer;
    while (current.valid)
    {
        if (*current.key == "stable")
            stable_pointer = current.key.ptr;

        current.advance();
    }
    assert(stable_pointer is exact_pointer);

    OwnedString foreign = OwnedString.from_string(
        foreign_allocator.allocator,
        "foreign",
    );
    i32 foreign_value = 10;
    assert(values.try_add_move(&foreign, &foreign_value) == AddStatus.inserted);
    {
        assert(foreign.allocator is null && foreign.empty);
    }
    assert(foreign_allocator.clean);

    auto foreign_cursor = values.cursor();
    const(char)* foreign_stored_pointer;
    while (foreign_cursor.valid)
    {
        if (*foreign_cursor.key == "foreign")
            foreign_stored_pointer = foreign_cursor.key.ptr;

        foreign_cursor.advance();
    }
    assert(foreign_stored_pointer !is null);

    OwnedString replacement = OwnedString.from_string(
        foreign_allocator.allocator,
        "foreign",
    );
    i32 replacement_value = 20;
    assert(values.try_set_move(&replacement, &replacement_value) == SetStatus.replaced);
    assert(replacement.view == "foreign" && replacement.allocator !is null);
    assert(!foreign_allocator.clean);
    replacement.deinit();
    assert(foreign_allocator.clean);
    assert(*values.find("foreign") == 20);
    foreign_cursor = values.cursor();
    while (foreign_cursor.valid)
    {
        if (*foreign_cursor.key == "foreign")
            assert(foreign_cursor.key.ptr is foreign_stored_pointer);

        foreign_cursor.advance();
    }

    OwnedString duplicate = OwnedString.from_string(
        foreign_allocator.allocator,
        "foreign",
    );
    i32 duplicate_value = 30;
    assert(
        values.try_add_move(&duplicate, &duplicate_value) == AddStatus.already_present,
    );
    {
        assert(duplicate.view == "foreign" && duplicate_value == 30);
        duplicate.deinit();
    }
    assert(foreign_allocator.clean);

    assert(values.remove("stable"));
    assert(values.find("stable") is null);
    values.deinit();
    assert(map_allocator.clean);
    assert(map_allocator.stats.invalid_calls == 0);
    assert(foreign_allocator.clean);
    assert(foreign_allocator.stats.invalid_calls == 0);

    AllocationRecord[16] failed_map_records;
    AllocationRecord[8] retained_records;
    InstrumentedAllocator failed_map_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        failed_map_records[],
    );
    InstrumentedAllocator retained_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        retained_records[],
    );
    StringHashMap!i32 failing = StringHashMap!i32.create(failed_map_allocator.allocator);
    OwnedString retained = OwnedString.from_string(
        retained_allocator.allocator,
        "retained",
    );
    i32 retained_value = 7;
    failed_map_allocator.fail_after(0);
    assert(
        failing.try_add_move(&retained, &retained_value) == AddStatus.out_of_memory,
    );
    {
        assert(retained.view == "retained" && retained_value == 7);
    }
    assert(failing.empty && failed_map_allocator.clean);

    failed_map_allocator.fail_after(2);
    assert(
        failing.try_add_move(&retained, &retained_value) == AddStatus.out_of_memory,
    );
    {
        assert(retained.view == "retained" && retained_value == 7);
    }
    assert(failing.empty);
    assert(failing.capacity != 0);
    failing.deinit();
    {
        retained.deinit();
    }
    assert(failed_map_allocator.clean);
    assert(failed_map_allocator.stats.invalid_calls == 0);
    assert(retained_allocator.clean);
    assert(retained_allocator.stats.invalid_calls == 0);
}
