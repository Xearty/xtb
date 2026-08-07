module xtb.core.string_hash_map;

nothrow @nogc:

import core.lifetime : move;
import xtb.core.hash : HashSeed, hashValue;
import xtb.core.hash_map;
import xtb.core.memory : Allocator;
import xtb.core.owned_string;
import xtb.core.panic : panic;
version (XTB_Checked)
    import xtb.core.panic : require;
import xtb.core.released_storage : ReleasedStorage;
import xtb.core.string;

/// Borrowing string-key map. The map owns the key descriptors but the caller
/// must keep the bytes referenced by every inserted `String` alive.
alias StringViewHashMap(V) = HashMap!(String, V);

/// Unmanaged counterpart of `StringViewHashMap`.
alias StringViewHashMapUnmanaged(V) = HashMapUnmanaged!(String, V);

private struct OwnedStringHash
{
nothrow @nogc:

    HashSeed seed;

    size_t opCall(scope const(OwnedStringUnmanaged)* key) const pure @safe
    {
        return hashValue(key.view, seed);
    }

    size_t opCall(scope const(String)* key) const pure @safe
    {
        return hashValue(*key, seed);
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

private template OwnedStringMapStorage(V)
{
    alias OwnedStringMapStorage = HashMapUnmanaged!(
        OwnedStringUnmanaged,
        V,
        OwnedStringHash,
        OwnedStringEqual,
        String,
        OwnedStringElementOps,
        DefaultHashMapElementOps!V,
    );
}

private enum MoveKeyStatus : ubyte
{
    inserted,
    existing,
    outOfMemory,
}

/// Allocator-explicit map that owns an exact immutable allocation for every
/// nonempty string key while accepting borrowed `String` lookup values.
struct StringHashMapUnmanaged(V)
{
nothrow @nogc:

private:
    OwnedStringMapStorage!V map_;

version (XTB_Checked)
{
    invariant
    {
        require(&this !is null, "StringHashMapUnmanaged pointer is null");
    }
}

public:
    @disable this(this);

    static StringHashMapUnmanaged seeded(HashSeed seed)
    {
        OwnedStringHash hasher;
        hasher.seed = seed;
        StringHashMapUnmanaged result;
        result.map_ = typeof(result.map_).withPolicies(
            hasher,
            OwnedStringEqual.init,
        );
        return move(result);
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t requested,
        scope StringHashMapUnmanaged* output,
    )
    {
        version (XTB_Checked)
        {
            require(output !is null,
                "StringHashMapUnmanaged output pointer is null");
            require(output.map_.capacity == 0 && output.map_.empty,
                "StringHashMapUnmanaged output is not empty");
        }
        StringHashMapUnmanaged temporary;
        if (!temporary.tryReserve(allocator, requested))
            return false;
        *output = move(temporary);
        return true;
    }

    static StringHashMapUnmanaged withCapacity(
        Allocator* allocator,
        size_t requested,
    )
    {
        StringHashMapUnmanaged result;
        if (!tryWithCapacity(allocator, requested, &result))
            panic("StringHashMap allocation failed");
        return move(result);
    }

    static StringHashMapUnmanaged withCapacity(
        Allocator* allocator,
        size_t requested,
        HashSeed seed,
    )
    {
        StringHashMapUnmanaged result = seeded(seed);
        result.reserve(allocator, requested);
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

    StringHashMapCursor!V cursor() return @trusted
    {
        return StringHashMapCursor!V.create(map_.cursor());
    }

    ConstStringHashMapCursor!V cursor() const return @trusted
    {
        return ConstStringHashMapCursor!V.create(map_.cursor());
    }

    StringHashMapPointerRange!V pointerItems() return @trusted
    {
        return StringHashMapPointerRange!V(cursor());
    }

    ConstStringHashMapPointerRange!V pointerItems() const return @trusted
    {
        return ConstStringHashMapPointerRange!V(cursor());
    }

    AddStatus tryAdd(
        Allocator* allocator,
        scope String key,
        V value,
    ) @trusted
    {
        PreparedHashMapInsert prepared;
        final switch (map_.prepareInsert(allocator, key, &prepared))
        {
            case PrepareInsertStatus.alreadyPresent:
                return AddStatus.alreadyPresent;
            case PrepareInsertStatus.outOfMemory:
                return AddStatus.outOfMemory;
            case PrepareInsertStatus.ready:
                break;
        }

        OwnedStringUnmanaged owned;
        if (!OwnedStringUnmanaged.tryFromString(allocator, key, &owned))
            return AddStatus.outOfMemory;
        map_.commitPreparedInsert(&prepared, &owned, &value);
        return AddStatus.inserted;
    }

    bool add(
        Allocator* allocator,
        scope String key,
        V value,
    ) @trusted
    {
        const status = tryAdd(allocator, key, move(value));
        if (status == AddStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == AddStatus.inserted;
    }

    SetStatus trySet(
        Allocator* allocator,
        scope String key,
        V value,
    ) @trusted
    {
        PreparedHashMapInsert prepared;
        final switch (map_.prepareInsert(allocator, key, &prepared))
        {
            case PrepareInsertStatus.alreadyPresent:
                map_.replacePreparedValue(allocator, &prepared, &value);
                return SetStatus.replaced;
            case PrepareInsertStatus.outOfMemory:
                return SetStatus.outOfMemory;
            case PrepareInsertStatus.ready:
                break;
        }

        OwnedStringUnmanaged owned;
        if (!OwnedStringUnmanaged.tryFromString(allocator, key, &owned))
            return SetStatus.outOfMemory;
        map_.commitPreparedInsert(&prepared, &owned, &value);
        return SetStatus.inserted;
    }

    bool set(
        Allocator* allocator,
        scope String key,
        V value,
    ) @trusted
    {
        const status = trySet(allocator, key, move(value));
        if (status == SetStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == SetStatus.inserted;
    }

    V* find(scope String key) return @trusted
    {
        return map_.find(key);
    }

    const(V)* find(scope String key) const return @trusted
    {
        return map_.find(key);
    }

    bool contains(scope String key) const @trusted
    {
        return map_.contains(key);
    }

    bool remove(Allocator* allocator, scope String key) @trusted
    {
        return map_.remove(allocator, key);
    }

    void clear(Allocator* allocator) @trusted
    {
        map_.clear(allocator);
    }

    bool tryReserve(Allocator* allocator, size_t requested) @trusted
    {
        return map_.tryReserve(allocator, requested);
    }

    void reserve(Allocator* allocator, size_t requested) @trusted
    {
        map_.reserve(allocator, requested);
    }

    bool tryShrinkToFit(Allocator* allocator) @trusted
    {
        return map_.tryShrinkToFit(allocator);
    }

    void shrinkToFit(Allocator* allocator) @trusted
    {
        map_.shrinkToFit(allocator);
    }

    AddStatus tryAddMove(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
    ) @trusted
    {
        final switch (tryMoveOwnedString(allocator, key, value, false))
        {
            case MoveKeyStatus.inserted:
                return AddStatus.inserted;
            case MoveKeyStatus.existing:
                return AddStatus.alreadyPresent;
            case MoveKeyStatus.outOfMemory:
                return AddStatus.outOfMemory;
        }
    }

    bool addMove(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
    ) @trusted
    {
        const status = tryAddMove(allocator, key, value);
        if (status == AddStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == AddStatus.inserted;
    }

    SetStatus trySetMove(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
    ) @trusted
    {
        final switch (tryMoveOwnedString(allocator, key, value, true))
        {
            case MoveKeyStatus.inserted:
                return SetStatus.inserted;
            case MoveKeyStatus.existing:
                return SetStatus.replaced;
            case MoveKeyStatus.outOfMemory:
                return SetStatus.outOfMemory;
        }
    }

    bool setMove(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
    ) @trusted
    {
        const status = trySetMove(allocator, key, value);
        if (status == SetStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == SetStatus.inserted;
    }

    AddStatus tryAddMove(
        Allocator* allocator,
        scope StringBuf* key,
        scope V* value,
    ) @trusted
    {
        final switch (tryMoveStringBuf(allocator, key, value, false))
        {
            case MoveKeyStatus.inserted:
                return AddStatus.inserted;
            case MoveKeyStatus.existing:
                return AddStatus.alreadyPresent;
            case MoveKeyStatus.outOfMemory:
                return AddStatus.outOfMemory;
        }
    }

    bool addMove(
        Allocator* allocator,
        scope StringBuf* key,
        scope V* value,
    ) @trusted
    {
        const status = tryAddMove(allocator, key, value);
        if (status == AddStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == AddStatus.inserted;
    }

    SetStatus trySetMove(
        Allocator* allocator,
        scope StringBuf* key,
        scope V* value,
    ) @trusted
    {
        final switch (tryMoveStringBuf(allocator, key, value, true))
        {
            case MoveKeyStatus.inserted:
                return SetStatus.inserted;
            case MoveKeyStatus.existing:
                return SetStatus.replaced;
            case MoveKeyStatus.outOfMemory:
                return SetStatus.outOfMemory;
        }
    }

    bool setMove(
        Allocator* allocator,
        scope StringBuf* key,
        scope V* value,
    ) @trusted
    {
        const status = trySetMove(allocator, key, value);
        if (status == SetStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == SetStatus.inserted;
    }

    int opApply(
        scope int delegate(ref const(String), ref V) nothrow @nogc callback,
    )
    {
        auto current = map_.cursor();
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

    int opApply(
        scope int delegate(ref const(String), ref const(V)) nothrow @nogc callback,
    ) const
    {
        auto current = map_.cursor();
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

private:
    MoveKeyStatus tryMoveOwnedString(
        Allocator* allocator,
        scope OwnedString* key,
        scope V* value,
        bool replace,
    ) @trusted
    {
        requireValidStringHashMapAllocator(allocator);
        version (XTB_Checked)
        {
            require(key !is null, "OwnedString key pointer is null");
            require(value !is null, "StringHashMap value pointer is null");
        }

        PreparedHashMapInsert prepared;
        const status = map_.prepareInsert(allocator, key.view, &prepared);
        if (status == PrepareInsertStatus.alreadyPresent)
        {
            if (!replace)
                return MoveKeyStatus.existing;
            map_.replacePreparedValue(allocator, &prepared, value);
            key.deinit();
            return MoveKeyStatus.existing;
        }
        if (status == PrepareInsertStatus.outOfMemory)
            return MoveKeyStatus.outOfMemory;

        OwnedStringUnmanaged owned;
        if (key.allocator is allocator)
        {
            auto released = key.release();
            Allocator* sourceAllocator;
            owned = released.extract(&sourceAllocator);
            version (XTB_Checked)
                require(sourceAllocator is allocator,
                    "OwnedString allocator changed during release");
        }
        else
        {
            if (!OwnedStringUnmanaged.tryFromString(
                    allocator,
                    key.view,
                    &owned,
            ))
                return MoveKeyStatus.outOfMemory;
        }

        map_.commitPreparedInsert(&prepared, &owned, value);
        if (key.allocator !is null)
            key.deinit();
        return MoveKeyStatus.inserted;
    }

    MoveKeyStatus tryMoveStringBuf(
        Allocator* destination,
        scope StringBuf* key,
        scope V* value,
        bool replace,
    ) @trusted
    {
        requireValidStringHashMapAllocator(destination);
        version (XTB_Checked)
        {
            require(key !is null, "StringBuf key pointer is null");
            require(value !is null, "StringHashMap value pointer is null");
        }

        PreparedHashMapInsert prepared;
        const status = map_.prepareInsert(destination, key.view, &prepared);
        if (status == PrepareInsertStatus.alreadyPresent)
        {
            if (!replace)
                return MoveKeyStatus.existing;
            map_.replacePreparedValue(destination, &prepared, value);
            key.deinit();
            return MoveKeyStatus.existing;
        }
        if (status == PrepareInsertStatus.outOfMemory)
            return MoveKeyStatus.outOfMemory;

        OwnedStringUnmanaged owned;
        if (!key.empty &&
            key.allocator is destination &&
            (key.byteCapacity == key.byteLength || key.tryShrinkToFit()))
        {
            auto released = key.release();
            Allocator* sourceAllocator;
            StringBufUnmanaged raw = released.extract(&sourceAllocator);
            version (XTB_Checked)
                require(sourceAllocator is destination,
                    "StringBuf allocator changed during release");
            owned = OwnedStringUnmanaged.adoptExact(raw.releaseExactStorage());
        }
        else
        {
            if (!OwnedStringUnmanaged.tryFromString(
                    destination,
                    key.view,
                    &owned,
            ))
                return MoveKeyStatus.outOfMemory;
        }

        map_.commitPreparedInsert(&prepared, &owned, value);
        if (key.allocator !is null)
            key.deinit();
        return MoveKeyStatus.inserted;
    }
}

/// RAII owning string-key map. It stores one allocator for the whole map and
/// no allocator or capacity word in individual keys.
struct StringHashMap(V)
{
nothrow @nogc:

    alias Self = StringHashMap!V;
    alias Storage = StringHashMapUnmanaged!V;
    alias Released = ReleasedStorage!Storage;

private:
    Allocator* allocator_;
    Storage storage_;

version (XTB_Checked)
{
    invariant
    {
        require(&this !is null, "StringHashMap pointer is null");
    }
}

public:
    @disable this(this);

    static Self create(Allocator* allocator) @trusted
    {
        requireValidStringHashMapAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    static Self seeded(Allocator* allocator, HashSeed seed) @trusted
    {
        requireValidStringHashMapAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        result.storage_ = Storage.seeded(seed);
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
            require(output !is null, "StringHashMap output pointer is null");
            require(output.allocator_ is null,
                "StringHashMap output is already initialized");
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
            panic("StringHashMap allocation failed");
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

    static Self adopt(scope Released* released) @trusted
    {
        version (XTB_Checked)
            require(released !is null,
                "released StringHashMap storage pointer is null");
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

    StringHashMapCursor!V cursor() return @trusted
    {
        return storage_.cursor;
    }

    ConstStringHashMapCursor!V cursor() const return @trusted
    {
        return storage_.cursor;
    }

    StringHashMapPointerRange!V pointerItems() return @trusted
    {
        return storage_.pointerItems;
    }

    ConstStringHashMapPointerRange!V pointerItems() const return @trusted
    {
        return storage_.pointerItems;
    }

    AddStatus tryAdd(scope String key, V value) @trusted
    {
        return storage_.tryAdd(allocator_, key, move(value));
    }

    bool add(scope String key, V value) @trusted
    {
        return storage_.add(allocator_, key, move(value));
    }

    SetStatus trySet(scope String key, V value) @trusted
    {
        return storage_.trySet(allocator_, key, move(value));
    }

    bool set(scope String key, V value) @trusted
    {
        return storage_.set(allocator_, key, move(value));
    }

    V* find(scope String key) return @trusted
    {
        return storage_.find(key);
    }

    const(V)* find(scope String key) const return @trusted
    {
        return storage_.find(key);
    }

    bool contains(scope String key) const @trusted
    {
        return storage_.contains(key);
    }

    bool remove(scope String key) @trusted
    {
        return storage_.remove(allocator_, key);
    }

    void clear() @trusted
    {
        storage_.clear(allocator_);
    }

    bool tryReserve(size_t requested) @trusted
    {
        return storage_.tryReserve(allocator_, requested);
    }

    void reserve(size_t requested) @trusted
    {
        storage_.reserve(allocator_, requested);
    }

    bool tryShrinkToFit() @trusted
    {
        return storage_.tryShrinkToFit(allocator_);
    }

    void shrinkToFit() @trusted
    {
        storage_.shrinkToFit(allocator_);
    }

    AddStatus tryAddMove(scope OwnedString* key, scope V* value) @trusted
    {
        return storage_.tryAddMove(allocator_, key, value);
    }

    bool addMove(scope OwnedString* key, scope V* value) @trusted
    {
        const status = tryAddMove(key, value);
        if (status == AddStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == AddStatus.inserted;
    }

    SetStatus trySetMove(scope OwnedString* key, scope V* value) @trusted
    {
        return storage_.trySetMove(allocator_, key, value);
    }

    bool setMove(scope OwnedString* key, scope V* value) @trusted
    {
        const status = trySetMove(key, value);
        if (status == SetStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == SetStatus.inserted;
    }

    AddStatus tryAddMove(scope StringBuf* key, scope V* value) @trusted
    {
        return storage_.tryAddMove(allocator_, key, value);
    }

    bool addMove(scope StringBuf* key, scope V* value) @trusted
    {
        const status = tryAddMove(key, value);
        if (status == AddStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == AddStatus.inserted;
    }

    SetStatus trySetMove(scope StringBuf* key, scope V* value) @trusted
    {
        return storage_.trySetMove(allocator_, key, value);
    }

    bool setMove(scope StringBuf* key, scope V* value) @trusted
    {
        const status = trySetMove(key, value);
        if (status == SetStatus.outOfMemory)
            panic("StringHashMap allocation failed");
        return status == SetStatus.inserted;
    }

    int opApply(
        scope int delegate(ref const(String), ref V) nothrow @nogc callback,
    )
    {
        return storage_.opApply(callback);
    }

    int opApply(
        scope int delegate(ref const(String), ref const(V)) nothrow @nogc callback,
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
        requireValidStringHashMapAllocator(allocator);
        version (XTB_Checked)
            require(storage !is null,
                "StringHashMapUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(*storage);
        return move(result);
    }
}


private void requireValidStringHashMapAllocator(Allocator* allocator) @trusted
{
    version (XTB_Checked)
        require(allocator !is null && *allocator !is null,
            "StringHashMap requires a valid allocator");
}

struct StringHashMapCursor(V)
{
nothrow @nogc:

private:
    HashMapCursor!(OwnedStringUnmanaged, V) cursor_;

    static StringHashMapCursor create(
        HashMapCursor!(OwnedStringUnmanaged, V) cursor,
    )
    {
        StringHashMapCursor result;
        result.cursor_ = cursor;
        return result;
    }

public:
    bool valid() const pure @safe
    {
        return cursor_.valid;
    }

    const(String)* key() const return @trusted
    {
        version (XTB_Checked)
            require(valid, "invalid StringHashMap cursor");
        return cursor_.key.viewPointer;
    }

    V* value() return
    {
        return cursor_.value;
    }

    void advance()
    {
        cursor_.advance();
    }
}

struct ConstStringHashMapCursor(V)
{
nothrow @nogc:

private:
    ConstHashMapCursor!(OwnedStringUnmanaged, V) cursor_;

    static ConstStringHashMapCursor create(
        ConstHashMapCursor!(OwnedStringUnmanaged, V) cursor,
    )
    {
        ConstStringHashMapCursor result;
        result.cursor_ = cursor;
        return result;
    }

public:
    bool valid() const pure @safe
    {
        return cursor_.valid;
    }

    const(String)* key() const return @trusted
    {
        version (XTB_Checked)
            require(valid, "invalid StringHashMap cursor");
        return cursor_.key.viewPointer;
    }

    const(V)* value() const return
    {
        return cursor_.value;
    }

    void advance()
    {
        cursor_.advance();
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
private:
    StringHashMapCursor!V cursor_;

public:
    bool empty() const pure @safe
    {
        return !cursor_.valid;
    }

    StringHashMapPointerItem!V front() return
    {
        return StringHashMapPointerItem!V(cursor_.key, cursor_.value);
    }

    void popFront()
    {
        cursor_.advance();
    }
}

struct ConstStringHashMapPointerRange(V)
{
private:
    ConstStringHashMapCursor!V cursor_;

public:
    bool empty() const pure @safe
    {
        return !cursor_.valid;
    }

    ConstStringHashMapPointerItem!V front() const return
    {
        return ConstStringHashMapPointerItem!V(cursor_.key, cursor_.value);
    }

    void popFront()
    {
        cursor_.advance();
    }
}

unittest
{
    import xtb.core.memory : mallocAllocator;
    import xtb.core.string : empty;

    static assert(is(StringViewHashMap!int == HashMap!(String, int)));
    static assert(!__traits(isCopyable, StringHashMap!int));
    static assert(is(typeof((cast(StringHashMap!int*) null).allocator()) ==
        Allocator*));
    static assert(!__traits(compiles,
        (cast(const(StringHashMap!int)*) null).allocator()));

    StringHashMap!int values = StringHashMap!int.create(mallocAllocator());
    StringBuf source = StringBuf.fromString(mallocAllocator(), "alpha");
    source.shrinkToFit();
    const sourcePointer = source.view.ptr;
    int first = 1;
    assert(values.addMove(&source, &first));
    assert(source.allocator is null &&
        source.empty);
    assert(values.find("alpha") !is null && *values.find("alpha") == 1);

    auto cursor = values.cursor();
    assert(cursor.valid && *cursor.key == "alpha");
    assert((*cursor.key).ptr is sourcePointer);

    StringBuf duplicate = StringBuf.fromString(mallocAllocator(), "alpha");
    int duplicateValue = 2;
    assert(values.tryAddMove(&duplicate, &duplicateValue) ==
        AddStatus.alreadyPresent);
    assert(duplicate.view == "alpha" && duplicateValue == 2);

    String mutableSource = "beta";
    assert(values.add(mutableSource, 3));
    assert(values.contains("beta"));
    assert(values.remove("alpha"));
    assert(!values.contains("alpha"));
}

unittest
{
    import xtb.core.memory : mallocAllocator;
    Allocator* allocator = mallocAllocator();
    StringHashMapUnmanaged!int values;
    StringBuf source = StringBuf.fromString(allocator, "unmanaged");
    source.shrinkToFit();
    const sourcePointer = source.view.ptr;
    int value = 42;

    assert(values.tryAddMove(allocator, &source, &value) ==
        AddStatus.inserted);
    assert(source.allocator is null);
    StringHashMapUnmanaged!int* valuesPointer = &values;
    assert(valuesPointer.length == 1);
    assert(valuesPointer.contains("unmanaged"));
    assert(valuesPointer.find("unmanaged") !is null &&
        *valuesPointer.find("unmanaged") == 42);
    assert((*valuesPointer.cursor.key).ptr is sourcePointer);

    const(StringHashMapUnmanaged!int)* constValuesPointer = &values;
    assert(constValuesPointer.length == 1);
    assert(constValuesPointer.contains("unmanaged"));

    valuesPointer.deinit(allocator);
}

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        mallocAllocator;
    AllocationRecord[128] mapRecords;
    AllocationRecord[32] foreignRecords;
    InstrumentedAllocator mapAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        mapRecords[],
    );
    InstrumentedAllocator foreignAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        foreignRecords[],
    );

    StringHashMap!int values = StringHashMap!int.create(mapAllocator.allocator);
    StringBuf exact = StringBuf.fromString(mapAllocator.allocator, "stable");
    const(char)* exactPointer;
    {
            exact.shrinkToFit();
        exactPointer = exact.view.ptr;
    }
    int first = 1;
    assert(values.tryAddMove(&exact, &first) == AddStatus.inserted);
    {
        import xtb.core.string : empty;

        assert(exact.allocator is null && exact.empty);
    }
    assert((*values.cursor.key).ptr is exactPointer);

    String[12] additional = [
        "a", "b", "c", "d", "e", "f",
        "g", "h", "i", "j", "k", "l",
    ];
    foreach (index, key; additional)
        assert(values.add(key, cast(int) index));
    const stable = values.find("stable");
    assert(stable !is null && *stable == 1);
    auto current = values.cursor();
    const(char)* stablePointer;
    while (current.valid)
    {
        if (*current.key == "stable")
            stablePointer = current.key.ptr;
        current.advance();
    }
    assert(stablePointer is exactPointer);

    OwnedString foreign = OwnedString.fromString(
        foreignAllocator.allocator,
        "foreign",
    );
    int foreignValue = 10;
    assert(values.tryAddMove(&foreign, &foreignValue) == AddStatus.inserted);
    {
        assert(foreign.allocator is null && foreign.empty);
    }
    assert(foreignAllocator.clean);

    auto foreignCursor = values.cursor();
    const(char)* foreignStoredPointer;
    while (foreignCursor.valid)
    {
        if (*foreignCursor.key == "foreign")
            foreignStoredPointer = foreignCursor.key.ptr;
        foreignCursor.advance();
    }
    assert(foreignStoredPointer !is null);

    OwnedString replacement = OwnedString.fromString(
        foreignAllocator.allocator,
        "foreign",
    );
    int replacementValue = 20;
    assert(values.trySetMove(&replacement, &replacementValue) ==
        SetStatus.replaced);
    {
        assert(replacement.allocator is null && replacement.empty);
    }
    assert(foreignAllocator.clean);
    assert(*values.find("foreign") == 20);
    foreignCursor = values.cursor();
    while (foreignCursor.valid)
    {
        if (*foreignCursor.key == "foreign")
            assert(foreignCursor.key.ptr is foreignStoredPointer);
        foreignCursor.advance();
    }

    OwnedString duplicate = OwnedString.fromString(
        foreignAllocator.allocator,
        "foreign",
    );
    int duplicateValue = 30;
    assert(values.tryAddMove(&duplicate, &duplicateValue) ==
        AddStatus.alreadyPresent);
    {
        assert(duplicate.view == "foreign" && duplicateValue == 30);
        duplicate.deinit();
    }
    assert(foreignAllocator.clean);

    assert(values.remove("stable"));
    assert(values.find("stable") is null);
    values.deinit();
    assert(mapAllocator.clean);
    assert(mapAllocator.stats.invalidCalls == 0);
    assert(foreignAllocator.clean);
    assert(foreignAllocator.stats.invalidCalls == 0);

    AllocationRecord[16] failedMapRecords;
    AllocationRecord[8] retainedRecords;
    InstrumentedAllocator failedMapAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        failedMapRecords[],
    );
    InstrumentedAllocator retainedAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        retainedRecords[],
    );
    StringHashMap!int failing = StringHashMap!int.create(
        failedMapAllocator.allocator);
    OwnedString retained = OwnedString.fromString(
        retainedAllocator.allocator,
        "retained",
    );
    int retainedValue = 7;
    failedMapAllocator.failAfter(0);
    assert(failing.tryAddMove(&retained, &retainedValue) ==
        AddStatus.outOfMemory);
    {
        assert(retained.view == "retained" && retainedValue == 7);
    }
    assert(failing.empty && failedMapAllocator.clean);

    failedMapAllocator.failAfter(2);
    assert(failing.tryAddMove(&retained, &retainedValue) ==
        AddStatus.outOfMemory);
    {
        assert(retained.view == "retained" && retainedValue == 7);
    }
    assert(failing.empty);
    assert(failing.capacity != 0);
    failing.deinit();
    {
        retained.deinit();
    }
    assert(failedMapAllocator.clean);
    assert(failedMapAllocator.stats.invalidCalls == 0);
    assert(retainedAllocator.clean);
    assert(retainedAllocator.stats.invalidCalls == 0);
}
