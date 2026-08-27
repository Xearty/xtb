module xtb.containers.hash_set;

nothrow @nogc:

import xtb.hash : HashSeed;
import xtb.lifetime : canFinalizeWithoutContext, move, moveEmplace;
import xtb.memory : Allocator;
import xtb.panic : panic;

version (XTB_Checked) import xtb.panic : require;
import xtb.containers.hash_map : AddStatus, ConstHashMapCursor, DefaultEqual, DefaultHash,
    DefaultHashMapElementOps, HashMapCursor, HashMapUnmanaged, IsDefaultEqualPolicy,
    IsDefaultHashPolicy, OwnedHashMapElementOps, isSimpleHashValue, requireValidHashAllocator;
import xtb.containers.released_storage : ReleasedStorage;

private struct SetMarker
{
}

/// Allocator-owned set sharing the same probing and lifetime semantics as
/// `HashMap`. Stored values are exposed only as const pointers.
/// Allocator-explicit set sharing the same storage engine as `HashMapUnmanaged`.
struct HashSetUnmanaged(
    K,
    Hasher = DefaultHash!K,
    Equal = DefaultEqual!K,
    ElementOps = DefaultHashMapElementOps!K,
)
{
nothrow @nogc:

private:
    HashMapUnmanaged!(K, SetMarker, Hasher, Equal, K,
        ElementOps, DefaultHashMapElementOps!SetMarker) map_;

public:
    @disable this(this);
    @disable ref HashSetUnmanaged opAssign(HashSetUnmanaged source) return;

    static HashSetUnmanaged withPolicies(Hasher hasher, Equal equal)
    {
        HashSetUnmanaged result;
        auto storage = typeof(result.map_).withPolicies(move(hasher), move(equal));
        moveEmplace(storage, result.map_);
        return move(result);
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t requested,
        scope HashSetUnmanaged* output,
    )
    {
        version (XTB_Checked)
        {
            require(output !is null, "HashSetUnmanaged output pointer is null");
            require(output.map_.capacity == 0 && output.map_.empty,
                "HashSetUnmanaged output is not empty");
        }
        HashSetUnmanaged temporary;
        if (!temporary.tryReserve(allocator, requested))
            return false;
        moveEmplace(temporary, *output);
        return true;
    }

    static HashSetUnmanaged withCapacity(Allocator* allocator, size_t requested)
    {
        HashSetUnmanaged result;
        if (!tryWithCapacity(allocator, requested, &result))
            panic("HashSet allocation failed");
        return move(result);
    }

    static if (IsDefaultHashPolicy!(Hasher, K) && IsDefaultEqualPolicy!(Equal, K))
    {
        static HashSetUnmanaged seeded(HashSeed seed)
        {
            HashSetUnmanaged result;
            auto storage = typeof(result.map_).seeded(seed);
            moveEmplace(storage, result.map_);
            return move(result);
        }

        static HashSetUnmanaged withCapacity(
            Allocator* allocator,
            size_t requested,
            HashSeed seed,
        )
        {
            HashSetUnmanaged result = seeded(seed);
            result.reserve(allocator, requested);
            return move(result);
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

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.set(this);
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

    int opApply(scope int delegate(ref const(K)) nothrow @nogc callback)
    {
        for (auto current = cursor(); current.valid; current.advance())
        {
            const result = callback(*current.value);
            if (result != 0)
                return result;
        }
        return 0;
    }

    int opApply(scope int delegate(ref const(K)) nothrow @nogc callback) const
    {
        for (auto current = cursor(); current.valid; current.advance())
        {
            const result = callback(*current.value);
            if (result != 0)
                return result;
        }
        return 0;
    }

    AddStatus tryAdd(Allocator* allocator, scope K* value) @system
    {
        SetMarker marker;
        return map_.tryAdd(allocator, value, &marker);
    }

    bool add(Allocator* allocator, scope K* value) @system
    {
        SetMarker marker;
        return map_.add(allocator, value, &marker);
    }

    static if (isSimpleHashValue!K)
    {
        AddStatus tryAdd(Allocator* allocator, K value)
        {
            return map_.tryAdd(allocator, value, SetMarker.init);
        }

        bool add(Allocator* allocator, K value)
        {
            return map_.add(allocator, value, SetMarker.init);
        }
    }

    bool contains(scope const(K)* value) const
    {
        return map_.contains(value);
    }

    bool remove(Allocator* allocator, scope const(K)* value)
    {
        return map_.remove(allocator, value);
    }

    bool take(scope const(K)* value, scope K* output) @system
    {
        SetMarker marker = void;
        return map_.take(value, output, &marker);
    }

    static if (isSimpleHashValue!K)
    {
        bool contains(scope K value) const
        {
            return map_.contains(value);
        }

        bool remove(Allocator* allocator, scope K value)
        {
            return map_.remove(allocator, value);
        }

        bool take(scope K value, scope K* output) @system
        {
            SetMarker marker = void;
            return map_.take(&value, output, &marker);
        }
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

/// Managed shallow hash set. Owns table storage but not element cleanup.
struct HashSet(K, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
nothrow @nogc:
    alias Self = HashSet!(K, Hasher, Equal);
    alias Storage = HashSetUnmanaged!(K, Hasher, Equal);
    alias Released = ReleasedStorage!Storage;
private:
    Allocator* allocator_;
    Storage storage_;
public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;
    static Self create(Allocator* allocator) @trusted
    {
        requireValidHashAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    static Self withPolicies(Allocator* allocator, Hasher hasher, Equal equal) @trusted
    {
        requireValidHashAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        Storage storage = Storage.withPolicies(move(hasher), move(equal));
        moveEmplace(storage, result.storage_);
        return move(result);
    }

    static bool tryWithCapacity(Allocator* allocator, size_t requested, scope Self* output) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "HashSet output pointer is null");
            require(output.allocator_ is null, "HashSet output is already initialized");
        }
        Storage storage;
        if (!Storage.tryWithCapacity(allocator, requested, &storage))
            return false;
        output.allocator_ = allocator;
        moveEmplace(storage, output.storage_);
        return true;
    }

    static Self withCapacity(Allocator* allocator, size_t requested) @trusted
    {
        Self result;
        if (!tryWithCapacity(allocator, requested, &result))
            panic("HashSet allocation failed");
        return move(result);
    }

    static if (IsDefaultHashPolicy!(Hasher, K) && IsDefaultEqualPolicy!(Equal, K))
    {
        static Self seeded(Allocator* allocator, HashSeed seed) @trusted
        {
            requireValidHashAllocator(allocator);
            Self result;
            result.allocator_ = allocator;
            Storage storage = Storage.seeded(seed);
            moveEmplace(storage, result.storage_);
            return move(result);
        }

        static Self withCapacity(Allocator* allocator, size_t requested, HashSeed seed) @trusted
        {
            Self result;
            result.allocator_ = allocator;
            Storage storage = Storage.withCapacity(allocator, requested, seed);
            moveEmplace(storage, result.storage_);
            return move(result);
        }
    }
    static Self adopt(scope Released* released) @trusted
    {
        version (XTB_Checked)
            require(released !is null, "released HashSet storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator_ = allocator;
        moveEmplace(storage, result.storage_);
        return move(result);
    }

    void deinit() @trusted
    {
        if (allocator_ !is null)
        {
            storage_.deinit(allocator_);
            allocator_ = null;
        }
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

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.set(this);
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

    AddStatus tryAdd(scope K* value) @system
    {
        return storage_.tryAdd(allocator_, value);
    }

    bool add(scope K* value) @system
    {
        return storage_.add(allocator_, value);
    }

    static if (isSimpleHashValue!K)
    {
        AddStatus tryAdd(K value) @trusted
        {
            return storage_.tryAdd(allocator_, value);
        }

        bool add(K value) @trusted
        {
            return storage_.add(allocator_, value);
        }
    }
    bool contains(scope const(K)* value) const @trusted
    {
        return storage_.contains(value);
    }

    bool remove(scope const(K)* value) @trusted
    {
        return storage_.remove(allocator_, value);
    }

    bool take(scope const(K)* value, scope K* output) @system
    {
        return storage_.take(value, output);
    }

    static if (isSimpleHashValue!K)
    {
        bool contains(scope K value) const @trusted
        {
            return storage_.contains(value);
        }

        bool remove(scope K value) @trusted
        {
            return storage_.remove(allocator_, value);
        }

        bool take(scope K value, scope K* output) @system
        {
            return storage_.take(value, output);
        }
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

    int opApply(scope int delegate(ref const(K)) nothrow @nogc callback)
    {
        return storage_.opApply(callback);
    }

    int opApply(scope int delegate(ref const(K)) nothrow @nogc callback) const
    {
        return storage_.opApply(callback);
    }

    Allocator* allocator() return pure @safe
    {
        return allocator_;
    }

package(xtb.containers):
    static Self adoptUnmanaged(Allocator* allocator, scope Storage* storage) @system
    {
        requireValidHashAllocator(allocator);
        version (XTB_Checked)
            require(storage !is null, "HashSetUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        moveEmplace(*storage, result.storage_);
        return move(result);
    }
}

/// Managed hash set that owns cleanup of stored elements.
struct OwnedHashSet(K, Hasher = DefaultHash!K, Equal = DefaultEqual!K)
{
nothrow @nogc:
    static assert(canFinalizeWithoutContext!K,
        "OwnedHashSet elements must support context-free finalization");
    alias Self = OwnedHashSet!(K, Hasher, Equal);
    alias Storage = HashSetUnmanaged!(K, Hasher, Equal, OwnedHashMapElementOps!K);
private:
    Allocator* allocator_;
    Storage storage_;
public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;
    static Self create(Allocator* allocator) @trusted
    {
        requireValidHashAllocator(allocator);
        Self r;
        r.allocator_ = allocator;
        return r;
    }

    static Self withPolicies(Allocator* allocator, Hasher hasher, Equal equal) @trusted
    {
        requireValidHashAllocator(allocator);
        Self r;
        r.allocator_ = allocator;
        Storage st = Storage.withPolicies(move(hasher), move(equal));
        moveEmplace(st, r.storage_);
        return move(r);
    }

    static bool tryWithCapacity(Allocator* allocator, size_t requested, scope Self* output) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "OwnedHashSet output pointer is null");
            require(output.allocator_ is null, "OwnedHashSet output is already initialized");
        }
        Storage st;
        if (!Storage.tryWithCapacity(allocator, requested, &st))
            return false;
        output.allocator_ = allocator;
        moveEmplace(st, output.storage_);
        return true;
    }

    static Self withCapacity(Allocator* allocator, size_t requested) @trusted
    {
        Self r;
        if (!tryWithCapacity(allocator, requested, &r))
            panic("OwnedHashSet allocation failed");
        return move(r);
    }

    static if (IsDefaultHashPolicy!(Hasher, K) && IsDefaultEqualPolicy!(Equal, K))
    {
        static Self seeded(Allocator* allocator, HashSeed seed) @trusted
        {
            requireValidHashAllocator(allocator);
            Self r;
            r.allocator_ = allocator;
            Storage st = Storage.seeded(seed);
            moveEmplace(st, r.storage_);
            return move(r);
        }

        static Self withCapacity(Allocator* allocator, size_t requested, HashSeed seed) @trusted
        {
            Self r;
            r.allocator_ = allocator;
            Storage st = Storage.withCapacity(allocator, requested, seed);
            moveEmplace(st, r.storage_);
            return move(r);
        }
    }
    void deinit() @trusted
    {
        if (allocator_ !is null)
        {
            storage_.deinit(allocator_);
            allocator_ = null;
        }
    }

    void resetAndRelease() @trusted
    {
        storage_.resetAndRelease(allocator_);
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

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.set(this);
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

    AddStatus tryAdd(scope K* value) @system
    {
        return storage_.tryAdd(allocator_, value);
    }

    bool add(scope K* value) @system
    {
        return storage_.add(allocator_, value);
    }

    static if (isSimpleHashValue!K)
    {
        AddStatus tryAdd(K value) @trusted
        {
            return storage_.tryAdd(allocator_, value);
        }

        bool add(K value) @trusted
        {
            return storage_.add(allocator_, value);
        }
    }
    bool contains(scope const(K)* value) const @trusted
    {
        return storage_.contains(value);
    }

    bool remove(scope const(K)* value) @trusted
    {
        return storage_.remove(allocator_, value);
    }

    bool take(scope const(K)* value, scope K* output) @system
    {
        return storage_.take(value, output);
    }

    static if (isSimpleHashValue!K)
    {
        bool contains(scope K value) const @trusted
        {
            return storage_.contains(value);
        }

        bool remove(scope K value) @trusted
        {
            return storage_.remove(allocator_, value);
        }

        bool take(scope K value, scope K* output) @system
        {
            return storage_.take(value, output);
        }
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

    int opApply(scope int delegate(ref const(K)) nothrow @nogc callback)
    {
        return storage_.opApply(callback);
    }

    int opApply(scope int delegate(ref const(K)) nothrow @nogc callback) const
    {
        return storage_.opApply(callback);
    }

    Allocator* allocator() return pure @safe
    {
        return allocator_;
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
