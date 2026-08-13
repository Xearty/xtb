module xtb.core.string_hash_set;

nothrow @nogc:

import xtb.core.lifetime : move, moveEmplace;
import xtb.core.hash : HashSeed;
import xtb.core.hash_map : AddStatus, HashSet, HashSetUnmanaged;
import xtb.core.memory : Allocator;
import xtb.core.owned_string : OwnedString;
import xtb.core.panic : panic;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.released_storage : ReleasedStorage;
import xtb.core.string : StringBuf;
import xtb.core.string_hash_map : ConstStringHashMapCursor,
    StringHashMapCursor, StringHashMapUnmanaged;
import xtb.core.types : String;

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
struct StringHashSetUnmanaged
{
nothrow @nogc:

private:
    StringHashMapUnmanaged!StringSetMarker map_;

    version (XTB_Checked)
    {
        invariant
        {
            require(&this !is null, "StringHashSetUnmanaged pointer is null");
        }
    }

public:
    @disable this(this);
    @disable ref StringHashSetUnmanaged opAssign(StringHashSetUnmanaged source) return;

    static StringHashSetUnmanaged seeded(HashSeed seed) @trusted
    {
        StringHashSetUnmanaged result;
        auto map = typeof(result.map_).seeded(seed);
        moveEmplace(map, result.map_);
        return move(result);
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t requested,
        scope StringHashSetUnmanaged* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null,
                "StringHashSetUnmanaged output pointer is null");
            require(output.map_.capacity == 0 && output.map_.empty,
                "StringHashSetUnmanaged output is not empty");
        }
        StringHashMapUnmanaged!StringSetMarker map;
        if (!typeof(map).tryWithCapacity(allocator, requested, &map))
            return false;
        moveEmplace(map, output.map_);
        return true;
    }

    static StringHashSetUnmanaged withCapacity(
        Allocator* allocator,
        size_t requested,
    ) @trusted
    {
        StringHashSetUnmanaged result;
        if (!tryWithCapacity(allocator, requested, &result))
            panic("StringHashSet allocation failed");
        return move(result);
    }

    static StringHashSetUnmanaged withCapacity(
        Allocator* allocator,
        size_t requested,
        HashSeed seed,
    ) @trusted
    {
        StringHashSetUnmanaged result = seeded(seed);
        result.map_.reserve(allocator, requested);
        return move(result);
    }

    void deinit(Allocator* allocator) @trusted
    {
        map_.deinit(allocator);
    }

    void resetAndRelease(Allocator* allocator) @trusted
    {
        map_.resetAndRelease(allocator);
    }

    size_t length() const pure @trusted
    {
        return map_.length;
    }

    size_t capacity() const pure @trusted
    {
        return map_.capacity;
    }

    bool empty() const pure @trusted
    {
        return map_.empty;
    }

    StringHashSetCursor cursor() return @trusted
    {
        return StringHashSetCursor.create(map_.cursor);
    }

    ConstStringHashSetCursor cursor() const return @trusted
    {
        return ConstStringHashSetCursor.create(map_.cursor);
    }

    StringHashSetPointerRange pointerItems() return @trusted
    {
        return StringHashSetPointerRange(cursor());
    }

    ConstStringHashSetPointerRange pointerItems() const return @trusted
    {
        return ConstStringHashSetPointerRange(cursor());
    }

    AddStatus tryAdd(Allocator* allocator, scope String value) @trusted
    {
        return map_.tryAdd(allocator, value, StringSetMarker.init);
    }

    bool add(Allocator* allocator, scope String value) @trusted
    {
        const status = tryAdd(allocator, value);
        if (status == AddStatus.outOfMemory)
            panic("StringHashSet allocation failed");
        return status == AddStatus.inserted;
    }

    AddStatus tryAddMove(
        Allocator* allocator,
        scope OwnedString* value,
    ) @trusted
    {
        StringSetMarker marker;
        return map_.tryAddMove(allocator, value, &marker);
    }

    AddStatus tryAddMove(
        Allocator* allocator,
        scope StringBuf* value,
    ) @trusted
    {
        StringSetMarker marker;
        return map_.tryAddMove(allocator, value, &marker);
    }

    bool addMove(Allocator* allocator, scope OwnedString* value) @trusted
    {
        const status = tryAddMove(allocator, value);
        if (status == AddStatus.outOfMemory)
            panic("StringHashSet allocation failed");
        return status == AddStatus.inserted;
    }

    bool addMove(Allocator* allocator, scope StringBuf* value) @trusted
    {
        const status = tryAddMove(allocator, value);
        if (status == AddStatus.outOfMemory)
            panic("StringHashSet allocation failed");
        return status == AddStatus.inserted;
    }

    bool contains(scope String value) const @trusted
    {
        return map_.contains(value);
    }

    bool remove(Allocator* allocator, scope String value) @trusted
    {
        return map_.remove(allocator, value);
    }

    bool tryReserve(Allocator* allocator, size_t requested) @trusted
    {
        return map_.tryReserve(allocator, requested);
    }

    void reserve(Allocator* allocator, size_t requested) @trusted
    {
        map_.reserve(allocator, requested);
    }

    void clear(Allocator* allocator) @trusted
    {
        map_.clear(allocator);
    }

    bool tryShrinkToFit(Allocator* allocator) @trusted
    {
        return map_.tryShrinkToFit(allocator);
    }

    void shrinkToFit(Allocator* allocator) @trusted
    {
        map_.shrinkToFit(allocator);
    }

    int opApply(
        scope int delegate(ref const(String)) nothrow @nogc callback,
    ) @trusted
    {
        auto current = map_.cursor;
        while (current.valid)
        {
            const result = callback(*current.key);
            if (result != 0)
                return result;
            current.advance();
        }
        return 0;
    }

    int opApply(
        scope int delegate(ref const(String)) nothrow @nogc callback,
    ) const @trusted
    {
        auto current = map_.cursor;
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
struct StringHashSet
{
nothrow @nogc:

    alias Storage = StringHashSetUnmanaged;
    alias Released = ReleasedStorage!Storage;

private:
    Allocator* allocator_;
    Storage storage_;

    version (XTB_Checked)
    {
        invariant
        {
            require(&this !is null, "StringHashSet pointer is null");
        }
    }

public:
    @disable this(this);
    @disable ref StringHashSet opAssign(StringHashSet source) return;

    static StringHashSet create(Allocator* allocator) @trusted
    {
        requireValidStringHashSetAllocator(allocator);
        StringHashSet result;
        result.allocator_ = allocator;
        return result;
    }

    static StringHashSet seeded(
        Allocator* allocator,
        HashSeed seed,
    ) @trusted
    {
        requireValidStringHashSetAllocator(allocator);
        StringHashSet result;
        result.allocator_ = allocator;
        Storage storage = Storage.seeded(seed);
        moveEmplace(storage, result.storage_);
        return move(result);
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t requested,
        scope StringHashSet* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "StringHashSet output pointer is null");
            require(output.allocator_ is null,
                "StringHashSet output is already initialized");
        }
        Storage storage;
        if (!Storage.tryWithCapacity(allocator, requested, &storage))
            return false;
        output.allocator_ = allocator;
        moveEmplace(storage, output.storage_);
        return true;
    }

    static StringHashSet withCapacity(
        Allocator* allocator,
        size_t requested,
    ) @trusted
    {
        StringHashSet result;
        if (!tryWithCapacity(allocator, requested, &result))
            panic("StringHashSet allocation failed");
        return move(result);
    }

    static StringHashSet withCapacity(
        Allocator* allocator,
        size_t requested,
        HashSeed seed,
    ) @trusted
    {
        requireValidStringHashSetAllocator(allocator);
        StringHashSet result;
        result.allocator_ = allocator;
        Storage storage = Storage.withCapacity(allocator, requested, seed);
        moveEmplace(storage, result.storage_);
        return move(result);
    }

    static StringHashSet adopt(scope Released* released) @trusted
    {
        version (XTB_Checked)
            require(released !is null,
                "released StringHashSet storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        StringHashSet result;
        result.allocator_ = allocator;
        moveEmplace(storage, result.storage_);
        return move(result);
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

    StringHashSetCursor cursor() return @trusted
    {
        return storage_.cursor;
    }

    ConstStringHashSetCursor cursor() const return @trusted
    {
        return storage_.cursor;
    }

    StringHashSetPointerRange pointerItems() return @trusted
    {
        return storage_.pointerItems;
    }

    ConstStringHashSetPointerRange pointerItems() const return @trusted
    {
        return storage_.pointerItems;
    }

    AddStatus tryAdd(scope String value) @trusted
    {
        return storage_.tryAdd(allocator_, value);
    }

    bool add(scope String value) @trusted
    {
        return storage_.add(allocator_, value);
    }

    AddStatus tryAddMove(scope OwnedString* value) @trusted
    {
        return storage_.tryAddMove(allocator_, value);
    }

    AddStatus tryAddMove(scope StringBuf* value) @trusted
    {
        return storage_.tryAddMove(allocator_, value);
    }

    bool addMove(scope OwnedString* value) @trusted
    {
        return storage_.addMove(allocator_, value);
    }

    bool addMove(scope StringBuf* value) @trusted
    {
        return storage_.addMove(allocator_, value);
    }

    bool contains(scope String value) const @trusted
    {
        return storage_.contains(value);
    }

    bool remove(scope String value) @trusted
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

    // `foreach` is a D language hook.
    int opApply(
        scope int delegate(ref const(String)) nothrow @nogc callback,
    ) @trusted
    {
        return storage_.opApply(callback);
    }

    int opApply(
        scope int delegate(ref const(String)) nothrow @nogc callback,
    ) const @trusted
    {
        return storage_.opApply(callback);
    }

    Allocator* allocator() return pure @safe
    {
        return allocator_;
    }
}

struct StringHashSetCursor
{
nothrow @nogc:

private:
    StringHashMapCursor!StringSetMarker cursor_;

    static StringHashSetCursor create(
        StringHashMapCursor!StringSetMarker cursor,
    ) @safe
    {
        StringHashSetCursor result;
        result.cursor_ = cursor;
        return result;
    }

public:
    bool valid() const pure nothrow @safe @nogc
    {
        return cursor_.valid;
    }

    const(String)* value() const return nothrow @trusted @nogc
    {
        return cursor_.key;
    }

    void advance() nothrow @trusted @nogc
    {
        cursor_.advance();
    }
}

struct ConstStringHashSetCursor
{
nothrow @nogc:

private:
    ConstStringHashMapCursor!StringSetMarker cursor_;

    static ConstStringHashSetCursor create(
        ConstStringHashMapCursor!StringSetMarker cursor,
    ) @safe
    {
        ConstStringHashSetCursor result;
        result.cursor_ = cursor;
        return result;
    }

public:
    bool valid() const pure nothrow @safe @nogc
    {
        return cursor_.valid;
    }

    const(String)* value() const return nothrow @trusted @nogc
    {
        return cursor_.key;
    }

    void advance() nothrow @trusted @nogc
    {
        cursor_.advance();
    }
}

struct StringHashSetPointerRange
{
private:
    StringHashSetCursor cursor_;

public:
    bool empty() const pure nothrow @safe @nogc
    {
        return !cursor_.valid;
    }

    const(String)* front() const return nothrow @trusted @nogc
    {
        return cursor_.value;
    }

    void popFront() nothrow @trusted @nogc
    {
        cursor_.advance();
    }
}

struct ConstStringHashSetPointerRange
{
private:
    ConstStringHashSetCursor cursor_;

public:
    bool empty() const pure nothrow @safe @nogc
    {
        return !cursor_.valid;
    }

    const(String)* front() const return nothrow @trusted @nogc
    {
        return cursor_.value;
    }

    void popFront() nothrow @trusted @nogc
    {
        cursor_.advance();
    }
}

private void requireValidStringHashSetAllocator(Allocator* allocator) @trusted
{
    version (XTB_Checked)
        require(allocator !is null && *allocator !is null,
            "StringHashSet requires a valid allocator");
}

unittest
{
    import xtb.core.allocators.malloc : mallocAllocator;
    import xtb.core.owned_string : OwnedString;
    import xtb.core.string : StringBuf;

    static assert(is(StringViewHashSet == HashSet!String));
    static assert(!__traits(isCopyable, StringHashSet));
    static assert(!__traits(isCopyable, StringHashSetUnmanaged));
    static assert(!__traits(compiles,
            (ref StringHashSetUnmanaged left, ref StringHashSetUnmanaged right) { left = move(right); }));
    static assert(__traits(compiles, (scope StringHashSet* value) @safe {
            Allocator* allocator = value.allocator;
        }));
    static assert(!__traits(compiles,
            (scope const StringHashSet* value) @safe { Allocator* allocator = value.allocator; }));

    StringViewHashSet borrowed = StringViewHashSet.create(mallocAllocator());
    {
        assert(borrowed.add("borrowed"));
        assert(borrowed.contains("borrowed"));
    }
    borrowed.deinit();

    StringHashSetUnmanaged unmanaged;
    StringHashSetUnmanaged* unmanagedPointer = &unmanaged;
    assert(unmanagedPointer.add(mallocAllocator(), "unmanaged"));
    assert(unmanagedPointer.length == 1);
    assert(unmanagedPointer.contains("unmanaged"));
    unmanagedPointer.deinit(mallocAllocator());

    StringHashSet values = StringHashSet.create(mallocAllocator());
    StringHashSet* valuesPointer = &values;
    assert(valuesPointer.add("alpha"));
    assert(!values.add("alpha"));
    assert(values.contains("alpha"));
    assert(valuesPointer.contains("alpha"));

    StringBuf buffer = StringBuf.fromString(mallocAllocator(), "beta");
    const(char)* bufferPointer;
    {
        buffer.shrinkToFit();
        bufferPointer = buffer.view.ptr;
    }
    assert(values.tryAddMove(&buffer) == AddStatus.inserted);
    {
        import xtb.core.string : empty;

        assert(buffer.allocator is null && buffer.empty);
    }

    OwnedString owned = OwnedString.fromString(mallocAllocator(), "gamma");
    const(char)* ownedPointer;
    {
        ownedPointer = owned.view.ptr;
    }
    assert(valuesPointer.addMove(&owned));
    {
        assert(owned.allocator is null && owned.empty);
    }

    auto transferCursor = values.cursor;
    bool sawBuffer;
    bool sawOwned;
    while (transferCursor.valid)
    {
        if (*transferCursor.value == "beta")
        {
            assert(transferCursor.value.ptr is bufferPointer);
            sawBuffer = true;
        }
        else if (*transferCursor.value == "gamma")
        {
            assert(transferCursor.value.ptr is ownedPointer);
            sawOwned = true;
        }
        transferCursor.advance();
    }
    assert(sawBuffer && sawOwned);

    StringBuf duplicate = StringBuf.fromString(mallocAllocator(), "beta");
    assert(values.tryAddMove(&duplicate) == AddStatus.alreadyPresent);
    {
        assert(duplicate.view == "beta");
        duplicate.deinit();
    }

    size_t visited;
    foreach (ref const value; values)
    {
        assert(value == "alpha" || value == "beta" || value == "gamma");
        ++visited;
    }
    assert(visited == values.length);

    size_t pointerVisited;
    foreach (value; values.pointerItems)
    {
        assert(value !is null);
        ++pointerVisited;
    }
    assert(pointerVisited == values.length);

    assert(valuesPointer.remove("alpha"));
    assert(!values.contains("alpha"));

    auto released = values.release();
    assert(values.allocator is null && values.empty);
    StringHashSet adopted = StringHashSet.adopt(&released);
    assert(adopted.contains("beta") && adopted.contains("gamma"));
    adopted.deinit();
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;
    import xtb.core.owned_string : OwnedString;

    AllocationRecord[16] setRecords;
    AllocationRecord[8] sourceRecords;
    InstrumentedAllocator setAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        setRecords[],
    );
    InstrumentedAllocator sourceAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        sourceRecords[],
    );

    StringHashSet values = StringHashSet.create(setAllocator.allocator);
    OwnedString retained = OwnedString.fromString(
        sourceAllocator.allocator,
        "retained",
    );

    setAllocator.failAfter(0);
    assert(values.tryAddMove(&retained) == AddStatus.outOfMemory);
    {
        assert(retained.view == "retained");
    }
    assert(values.empty && setAllocator.clean);

    setAllocator.failAfter(2);
    assert(values.tryAddMove(&retained) == AddStatus.outOfMemory);
    {
        assert(retained.view == "retained");
    }
    assert(values.empty && values.capacity != 0);

    values.deinit();
    {
        retained.deinit();
    }
    assert(setAllocator.clean && sourceAllocator.clean);
    assert(setAllocator.stats.invalidCalls == 0);
    assert(sourceAllocator.stats.invalidCalls == 0);
}
