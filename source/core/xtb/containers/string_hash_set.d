module xtb.containers.string_hash_set;

nothrow @nogc:

import core.attribute;

import xtb.containers.hash_map;
import xtb.containers.hash_set;
import xtb.containers.released_storage;
import xtb.containers.string_hash_map;
import xtb.hash;
import xtb.lifetime;
import xtb.memory;
import xtb.panic;
import xtb.string;
import xtb.types;

/// Borrowing string-key set. The set owns each `String` descriptor, but the
/// caller must keep the bytes referenced by every inserted value alive.
alias StringViewHashSet = HashSet!String;

/// Unmanaged counterpart of `StringViewHashSet`.
alias StringViewHashSetUnmanaged = HashSetUnmanaged!String;

private struct StringSetMarker
{
}

/// Allocator-explicit set that owns an exact immutable allocation for every
/// nonempty string. Operations are allocator-explicit members.
@mustuse struct StringHashSetUnmanaged
{
nothrow @nogc:

    StringHashMapUnmanaged!StringSetMarker map;

    invariant
    {
        require(&this !is null, "StringHashSetUnmanaged pointer is null");
    }

    @disable this(this);
    @disable ref StringHashSetUnmanaged opAssign(StringHashSetUnmanaged source) return;

    static StringHashSetUnmanaged seeded(HashSeed seed) @trusted
    {
        StringHashSetUnmanaged result;
        auto map = typeof(result.map).seeded(seed);
        move_emplace(map, result.map);
        return move(result);
    }

    static bool try_with_capacity(
        Allocator* allocator,
        usize requested,
        scope StringHashSetUnmanaged* output,
    ) @trusted
    {
        require(
            output !is null,
            "StringHashSetUnmanaged output pointer is null",
        );
        require(
            output.map.capacity == 0 && output.map.empty,
            "StringHashSetUnmanaged output is not empty",
        );
        StringHashMapUnmanaged!StringSetMarker map;
        if (!typeof(map).try_with_capacity(allocator, requested, &map))
            return false;
        move_emplace(map, output.map);
        return true;
    }

    static StringHashSetUnmanaged with_capacity(
        Allocator* allocator,
        usize requested,
    ) @trusted
    {
        StringHashSetUnmanaged result;
        if (!StringHashSetUnmanaged.try_with_capacity(allocator, requested, &result))
            panic("StringHashSet allocation failed");

        return move(result);
    }

    static StringHashSetUnmanaged with_capacity(
        Allocator* allocator,
        usize requested,
        HashSeed seed,
    ) @trusted
    {
        StringHashSetUnmanaged result = StringHashSetUnmanaged.seeded(seed);
        result.map.reserve(allocator, requested);
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

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.set(this);
    }

    StringHashSetCursor cursor() return @trusted
    {
        return StringHashSetCursor.create(this.map.cursor);
    }

    ConstStringHashSetCursor cursor() const return @trusted
    {
        return ConstStringHashSetCursor.create(this.map.cursor);
    }

    StringHashSetPointerRange pointer_items() return @trusted
    {
        return StringHashSetPointerRange(this.cursor());
    }

    ConstStringHashSetPointerRange pointer_items() const return @trusted
    {
        return ConstStringHashSetPointerRange(this.cursor());
    }

    AddStatus try_add(Allocator* allocator, scope String value) @trusted
    {
        return this.map.try_add(allocator, value, StringSetMarker.init);
    }

    bool add(Allocator* allocator, scope String value) @trusted
    {
        const status = this.try_add(allocator, value);
        if (status == AddStatus.out_of_memory)
            panic("StringHashSet allocation failed");

        return status == AddStatus.inserted;
    }

    AddStatus try_add_move(
        Allocator* allocator,
        scope OwnedString* value,
    ) @trusted
    {
        StringSetMarker marker;
        return this.map.try_add_move(allocator, value, &marker);
    }

    AddStatus try_add_move(
        Allocator* allocator,
        scope StringBuf* value,
    ) @trusted
    {
        StringSetMarker marker;
        return this.map.try_add_move(allocator, value, &marker);
    }

    bool add_move(Allocator* allocator, scope OwnedString* value) @trusted
    {
        const status = this.try_add_move(allocator, value);
        if (status == AddStatus.out_of_memory)
            panic("StringHashSet allocation failed");

        return status == AddStatus.inserted;
    }

    bool add_move(Allocator* allocator, scope StringBuf* value) @trusted
    {
        const status = this.try_add_move(allocator, value);
        if (status == AddStatus.out_of_memory)
            panic("StringHashSet allocation failed");

        return status == AddStatus.inserted;
    }

    bool contains(scope String value) const @trusted
    {
        return this.map.contains(value);
    }

    bool remove(Allocator* allocator, scope String value) @trusted
    {
        return this.map.remove(allocator, value);
    }

    bool try_reserve(Allocator* allocator, usize requested) @trusted
    {
        return this.map.try_reserve(allocator, requested);
    }

    void reserve(Allocator* allocator, usize requested) @trusted
    {
        this.map.reserve(allocator, requested);
    }

    void clear(Allocator* allocator) @trusted
    {
        this.map.clear(allocator);
    }

    bool try_shrink_to_fit(Allocator* allocator) @trusted
    {
        return this.map.try_shrink_to_fit(allocator);
    }

    void shrink_to_fit(Allocator* allocator) @trusted
    {
        this.map.shrink_to_fit(allocator);
    }

    i32 opApply(
        scope i32 delegate(ref const(String)) nothrow @nogc callback,
    ) @trusted
    {
        auto current = this.map.cursor;
        while (current.valid)
        {
            const result = callback(*current.key);
            if (result != 0)
                return result;
            current.advance();
        }
        return 0;
    }

    i32 opApply(
        scope i32 delegate(ref const(String)) nothrow @nogc callback,
    ) const @trusted
    {
        auto current = this.map.cursor;
        while (current.valid)
        {
            const result = callback(*current.key);
            if (result != 0)
                return result;
            current.advance();
        }
        return 0;
    }
}

/// Explicit owner for every inserted string and the set backing storage.
@mustuse struct StringHashSet
{
nothrow @nogc:

    alias Storage = StringHashSetUnmanaged;
    alias Released = ReleasedStorage!Storage;

    Allocator* allocator;
    Storage storage;

    invariant
    {
        require(&this !is null, "StringHashSet pointer is null");
    }

    @disable this(this);
    @disable ref StringHashSet opAssign(StringHashSet source) return;

    static StringHashSet create(Allocator* allocator) @trusted
    {
        require_valid_string_hash_set_allocator(allocator);
        StringHashSet result;
        result.allocator = allocator;
        return result;
    }

    static StringHashSet seeded(
        Allocator* allocator,
        HashSeed seed,
    ) @trusted
    {
        require_valid_string_hash_set_allocator(allocator);
        StringHashSet result;
        result.allocator = allocator;
        Storage storage = Storage.seeded(seed);
        move_emplace(storage, result.storage);
        return move(result);
    }

    static bool try_with_capacity(
        Allocator* allocator,
        usize requested,
        scope StringHashSet* output,
    ) @trusted
    {
        require(output !is null, "StringHashSet output pointer is null");
        require(
            output.allocator is null,
            "StringHashSet output is already initialized",
        );
        Storage storage;
        if (!Storage.try_with_capacity(allocator, requested, &storage))
            return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static StringHashSet with_capacity(
        Allocator* allocator,
        usize requested,
    ) @trusted
    {
        StringHashSet result;
        if (!StringHashSet.try_with_capacity(allocator, requested, &result))
            panic("StringHashSet allocation failed");

        return move(result);
    }

    static StringHashSet with_capacity(
        Allocator* allocator,
        usize requested,
        HashSeed seed,
    ) @trusted
    {
        require_valid_string_hash_set_allocator(allocator);
        StringHashSet result;
        result.allocator = allocator;
        Storage storage = Storage.with_capacity(allocator, requested, seed);
        move_emplace(storage, result.storage);
        return move(result);
    }

    static StringHashSet adopt(scope Released* released) @trusted
    {
        require(
            released !is null,
            "released StringHashSet storage pointer is null",
        );
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        StringHashSet result;
        result.allocator = allocator;
        move_emplace(storage, result.storage);
        return move(result);
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

    Released release() @trusted
    {
        auto result = Released.from_owned_parts(this.allocator, &this.storage);
        this.allocator = null;
        return move(result);
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

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.set(this);
    }

    StringHashSetCursor cursor() return @trusted
    {
        return this.storage.cursor;
    }

    ConstStringHashSetCursor cursor() const return @trusted
    {
        return this.storage.cursor;
    }

    StringHashSetPointerRange pointer_items() return @trusted
    {
        return this.storage.pointer_items;
    }

    ConstStringHashSetPointerRange pointer_items() const return @trusted
    {
        return this.storage.pointer_items;
    }

    AddStatus try_add(scope String value) @trusted
    {
        return this.storage.try_add(this.allocator, value);
    }

    bool add(scope String value) @trusted
    {
        return this.storage.add(this.allocator, value);
    }

    AddStatus try_add_move(scope OwnedString* value) @trusted
    {
        return this.storage.try_add_move(this.allocator, value);
    }

    AddStatus try_add_move(scope StringBuf* value) @trusted
    {
        return this.storage.try_add_move(this.allocator, value);
    }

    bool add_move(scope OwnedString* value) @trusted
    {
        return this.storage.add_move(this.allocator, value);
    }

    bool add_move(scope StringBuf* value) @trusted
    {
        return this.storage.add_move(this.allocator, value);
    }

    bool contains(scope String value) const @trusted
    {
        return this.storage.contains(value);
    }

    bool remove(scope String value) @trusted
    {
        return this.storage.remove(this.allocator, value);
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

    // `foreach` is a D language hook.
    i32 opApply(
        scope i32 delegate(ref const(String)) nothrow @nogc callback,
    ) @trusted
    {
        return this.storage.opApply(callback);
    }

    i32 opApply(
        scope i32 delegate(ref const(String)) nothrow @nogc callback,
    ) const @trusted
    {
        return this.storage.opApply(callback);
    }

}

struct StringHashSetCursor
{
nothrow @nogc:

    StringHashMapCursor!StringSetMarker cursor;

    private static StringHashSetCursor create(
        StringHashMapCursor!StringSetMarker cursor,
    ) @safe
    {
        StringHashSetCursor result;
        result.cursor = cursor;
        return result;
    }

    bool valid() const pure @safe
    {
        return this.cursor.valid;
    }

    const(String)* value() const return @trusted
    {
        return this.cursor.key;
    }

    void advance() @trusted
    {
        this.cursor.advance();
    }
}

struct ConstStringHashSetCursor
{
nothrow @nogc:

    ConstStringHashMapCursor!StringSetMarker cursor;

    private static ConstStringHashSetCursor create(
        ConstStringHashMapCursor!StringSetMarker cursor,
    ) @safe
    {
        ConstStringHashSetCursor result;
        result.cursor = cursor;
        return result;
    }

    bool valid() const pure @safe
    {
        return this.cursor.valid;
    }

    const(String)* value() const return @trusted
    {
        return this.cursor.key;
    }

    void advance() @trusted
    {
        this.cursor.advance();
    }
}

struct StringHashSetPointerRange
{
nothrow @nogc:

    StringHashSetCursor cursor;

    bool empty() const pure @safe
    {
        return !this.cursor.valid;
    }

    const(String)* front() const return @trusted
    {
        return this.cursor.value;
    }

    void popFront() @trusted
    {
        this.cursor.advance();
    }
}

struct ConstStringHashSetPointerRange
{
nothrow @nogc:

    ConstStringHashSetCursor cursor;

    bool empty() const pure @safe
    {
        return !this.cursor.valid;
    }

    const(String)* front() const return @trusted
    {
        return this.cursor.value;
    }

    void popFront() @trusted
    {
        this.cursor.advance();
    }
}

private void require_valid_string_hash_set_allocator(Allocator* allocator) @trusted
{
    require(
        allocator !is null && *allocator !is null,
        "StringHashSet requires a valid allocator",
    );
}

// Everything below here is test-only.
version (unittest)
{
    import xtb.allocators.instrumented;
    import xtb.allocators.malloc;
}

unittest
{
    static assert(is(StringViewHashSet == HashSet!String));
    static assert(!__traits(isCopyable, StringHashSet));
    static assert(!__traits(isCopyable, StringHashSetUnmanaged));
    static assert(!__traits(
        compiles,
        (ref StringHashSetUnmanaged left, ref StringHashSetUnmanaged right)
        {
            left = move(right);
        },
    ));
    static assert(__traits(
        compiles,
        (scope StringHashSet* value) @safe
        {
            Allocator* allocator = value.allocator;
        },
    ));
    static assert(!__traits(
        compiles,
        (scope const StringHashSet* value) @safe
        {
            Allocator* allocator = value.allocator;
        },
    ));

    StringViewHashSet borrowed = StringViewHashSet.create(malloc_allocator());
    {
        assert(borrowed.add("borrowed"));
        assert(borrowed.contains("borrowed"));
    }
    borrowed.deinit();

    StringHashSetUnmanaged unmanaged;
    StringHashSetUnmanaged* unmanaged_pointer = &unmanaged;
    assert(unmanaged_pointer.add(malloc_allocator(), "unmanaged"));
    assert(unmanaged_pointer.length == 1);
    assert(unmanaged_pointer.contains("unmanaged"));
    unmanaged_pointer.deinit(malloc_allocator());

    StringHashSet values = StringHashSet.create(malloc_allocator());
    StringHashSet* values_pointer = &values;
    assert(values_pointer.add("alpha"));
    assert(!values.add("alpha"));
    assert(values.contains("alpha"));
    assert(values_pointer.contains("alpha"));

    StringBuf buffer = StringBuf.from_string(malloc_allocator(), "beta");
    const(char)* buffer_pointer;
    {
        buffer.shrink_to_fit();
        buffer_pointer = buffer.view.ptr;
    }
    assert(values.try_add_move(&buffer) == AddStatus.inserted);
    {
        import xtb.string : empty;

        assert(buffer.allocator is null && buffer.empty);
    }

    OwnedString owned = OwnedString.from_string(malloc_allocator(), "gamma");
    const(char)* owned_pointer;
    {
        owned_pointer = owned.view.ptr;
    }
    assert(values_pointer.add_move(&owned));
    {
        assert(owned.allocator is null && owned.empty);
    }

    auto transfer_cursor = values.cursor;
    bool saw_buffer;
    bool saw_owned;
    while (transfer_cursor.valid)
    {
        if (*transfer_cursor.value == "beta")
        {
            assert(transfer_cursor.value.ptr is buffer_pointer);
            saw_buffer = true;
        }
        else if (*transfer_cursor.value == "gamma")
        {
            assert(transfer_cursor.value.ptr is owned_pointer);
            saw_owned = true;
        }
        transfer_cursor.advance();
    }
    assert(saw_buffer && saw_owned);

    StringBuf duplicate = StringBuf.from_string(malloc_allocator(), "beta");
    assert(values.try_add_move(&duplicate) == AddStatus.already_present);
    {
        assert(duplicate.view == "beta");
        duplicate.deinit();
    }

    usize visited;
    foreach (ref const value; values)
    {
        assert(value == "alpha" || value == "beta" || value == "gamma");
        ++visited;
    }
    assert(visited == values.length);

    usize pointer_visited;
    foreach (value; values.pointer_items)
    {
        assert(value !is null);
        ++pointer_visited;
    }
    assert(pointer_visited == values.length);

    assert(values_pointer.remove("alpha"));
    assert(!values.contains("alpha"));

    auto released = values.release();
    assert(values.allocator is null && values.empty);
    StringHashSet adopted = StringHashSet.adopt(&released);
    assert(adopted.contains("beta") && adopted.contains("gamma"));
    adopted.deinit();
}

unittest
{
    AllocationRecord[16] set_records;
    AllocationRecord[8] source_records;
    InstrumentedAllocator set_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        set_records[],
    );
    InstrumentedAllocator source_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        source_records[],
    );

    StringHashSet values = StringHashSet.create(set_allocator.allocator);
    OwnedString retained = OwnedString.from_string(
        source_allocator.allocator,
        "retained",
    );

    set_allocator.fail_after(0);
    assert(values.try_add_move(&retained) == AddStatus.out_of_memory);
    {
        assert(retained.view == "retained");
    }
    assert(values.empty && set_allocator.clean);

    set_allocator.fail_after(2);
    assert(values.try_add_move(&retained) == AddStatus.out_of_memory);
    {
        assert(retained.view == "retained");
    }
    assert(values.empty && values.capacity != 0);

    values.deinit();
    {
        retained.deinit();
    }
    assert(set_allocator.clean && source_allocator.clean);
    assert(set_allocator.stats.invalid_calls == 0);
    assert(source_allocator.stats.invalid_calls == 0);
}
