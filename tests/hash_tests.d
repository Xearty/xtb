module tests.hash_tests;

nothrow @nogc:

import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.allocators.malloc : mallocAllocator;
import xtb.containers.hash_map;
import xtb.containers.hash_set;
import xtb.lifetime : deinit, move;
import xtb.memory : Allocator, deallocateArray, tryAllocateArray;
import xtb.string : OwnedString, StringBuf;
import xtb.containers.string_hash_map : OwnedStringHashMap, StringHashMap;
import xtb.containers.string_hash_set : StringHashSet;

private struct HeapOwner
{
nothrow @nogc:

    Allocator* allocator;
    ubyte[] bytes;
    int id;
    size_t* deinits;

    @disable this(this);

    static HeapOwner create(
        Allocator* allocator,
        int id,
        size_t* deinits,
    )
    {
        HeapOwner result;
        result.allocator = allocator;
        result.id = id;
        result.deinits = deinits;
        const size = cast(size_t)(13 + (id & 7));
        result.bytes = allocator.tryAllocateArray!ubyte(size);
        assert(result.bytes.ptr !is null);
        return result;
    }

    static HeapOwner probe(int id)
    {
        HeapOwner result;
        result.id = id;
        return result;
    }

    void deinit()
    {
        if (bytes.ptr is null)
            return;
        allocator.deallocateArray(bytes);
        if (deinits !is null)
            ++*deinits;
    }
}

private struct HeapOwnerHash
{
    size_t opCall(scope const(HeapOwner)* value) const pure nothrow @safe @nogc
    {
        return cast(size_t) value.id * cast(size_t) 0x9E3779B1U;
    }
}

private struct HeapOwnerEqual
{
    bool opCall(
        scope const(HeapOwner)* left,
        scope const(HeapOwner)* right,
    ) const pure nothrow @safe @nogc
    {
        return left.id == right.id;
    }
}

private struct DisabledDefaultOwner
{
nothrow @nogc:

    Allocator* allocator;
    ubyte[] bytes;
    int id;
    size_t* deinits;

    @disable this();
    @disable this(this);

    static DisabledDefaultOwner create(
        Allocator* allocator,
        int id,
        size_t* deinits,
    )
    {
        DisabledDefaultOwner result = void;
        result.allocator = allocator;
        result.id = id;
        result.deinits = deinits;
        result.bytes = allocator.tryAllocateArray!ubyte(9 + cast(size_t)(id & 3));
        assert(result.bytes.ptr !is null);
        return move(result);
    }

    static DisabledDefaultOwner probe(int id)
    {
        DisabledDefaultOwner result = void;
        result.allocator = null;
        result.bytes = null;
        result.id = id;
        result.deinits = null;
        return move(result);
    }

    void deinit()
    {
        if (bytes.ptr is null)
            return;
        allocator.deallocateArray(bytes);
        if (deinits !is null)
            ++*deinits;
    }
}

private struct DisabledDefaultOwnerHash
{
    size_t opCall(scope const(DisabledDefaultOwner)* value) const pure nothrow @safe @nogc
    {
        return cast(size_t) value.id * cast(size_t) 0x9E3779B1U;
    }
}

private struct DisabledDefaultOwnerEqual
{
    bool opCall(
        scope const(DisabledDefaultOwner)* left,
        scope const(DisabledDefaultOwner)* right,
    ) const pure nothrow @safe @nogc
    {
        return left.id == right.id;
    }
}

private struct ConstantCollisionHash
{
    size_t opCall(scope const(int)*) const pure nothrow @safe @nogc
    {
        return 1;
    }
}

private struct CountingOwner
{
nothrow @nogc:

    int id;
    size_t* deinits;

    @disable this(this);

    void deinit()
    {
        if (deinits !is null)
            ++*deinits;
    }
}

private struct CountingOwnerHash
{
    size_t opCall(scope const(CountingOwner)* value) const pure nothrow @safe @nogc
    {
        return cast(size_t) value.id;
    }
}

private struct CountingOwnerEqual
{
    bool opCall(
        scope const(CountingOwner)* left,
        scope const(CountingOwner)* right,
    ) const pure nothrow @safe @nogc
    {
        return left.id == right.id;
    }
}

private struct DestructorOwner
{
nothrow @nogc:

    int id;
    size_t* destructions;
    bool armed;

    @disable this(this);

    ~this()
    {
        if (armed)
        {
            ++*destructions;
            armed = false;
        }
    }
}

private struct DestructorOwnerHash
{
    size_t opCall(scope const(DestructorOwner)* value) const pure nothrow @safe @nogc
    {
        return cast(size_t) value.id;
    }
}

private struct DestructorOwnerEqual
{
    bool opCall(
        scope const(DestructorOwner)* left,
        scope const(DestructorOwner)* right,
    ) const pure nothrow @safe @nogc
    {
        return left.id == right.id;
    }
}

private struct ContextOwner
{
    int id;

    @disable this(this);

    void deinit(Allocator*) nothrow @nogc
    {
    }
}

private struct ContextOwnerHash
{
    size_t opCall(scope const(ContextOwner)* value) const pure nothrow @safe @nogc
    {
        return cast(size_t) value.id;
    }
}

private struct ContextOwnerEqual
{
    bool opCall(
        scope const(ContextOwner)* left,
        scope const(ContextOwner)* right,
    ) const pure nothrow @safe @nogc
    {
        return left.id == right.id;
    }
}

private alias StringBufOwnerMap = OwnedHashMap!(StringBuf, int);
private alias StringBufOwnerSet = OwnedHashSet!StringBuf;

private alias OwnerMap = OwnedHashMap!(
    HeapOwner,
    HeapOwner,
    HeapOwnerHash,
    HeapOwnerEqual,
);
private alias OwnerSet = OwnedHashSet!(
    HeapOwner,
    HeapOwnerHash,
    HeapOwnerEqual,
);
private alias ShallowOwnerMap = HashMap!(
    HeapOwner,
    HeapOwner,
    HeapOwnerHash,
    HeapOwnerEqual,
);
private alias DisabledOwnerMap = OwnedHashMap!(
    DisabledDefaultOwner,
    DisabledDefaultOwner,
    DisabledDefaultOwnerHash,
    DisabledDefaultOwnerEqual,
);
private alias ShallowCountingMap = HashMap!(
    CountingOwner,
    CountingOwner,
    CountingOwnerHash,
    CountingOwnerEqual,
);
private alias DestructorOwnerMap = OwnedHashMap!(int, DestructorOwner);
private alias DestructorOwnerSet = OwnedHashSet!(
    DestructorOwner,
    DestructorOwnerHash,
    DestructorOwnerEqual,
);

static assert(__traits(compiles, StringBufOwnerMap.create(mallocAllocator())));
static assert(__traits(compiles, StringBufOwnerSet.create(mallocAllocator())));
static assert(!__traits(isCopyable, OwnerMap));
static assert(!__traits(compiles,
        (ref HashMapUnmanaged!(int, int) left, ref HashMapUnmanaged!(int, int) right) {
        left = move(right);
    }));
static assert(!__traits(compiles,
        (ref HashSetUnmanaged!int left, ref HashSetUnmanaged!int right) { left = move(right); }));
static assert(!__traits(isCopyable, OwnerSet));
static assert(__traits(compiles, (ref OwnerMap map, HeapOwner* key, HeapOwner* value) {
        map.tryAdd(key, value);
    }));
static assert(!__traits(compiles, (ref OwnerMap map, HeapOwner key, HeapOwner value) {
        map.tryAdd(move(key), move(value));
    }));
static assert(!__traits(compiles, (ref OwnerMap left, ref OwnerMap right) { left = move(right); }));
static assert(!__traits(hasMember, OwnerMap, "release"));
static assert(!__traits(hasMember, OwnerSet, "release"));
static assert(!is(StringHashMap!HeapOwner == OwnedStringHashMap!HeapOwner));
static assert(!__traits(compiles, StringHashMap!(HeapOwner, DefaultHashMapElementOps!HeapOwner)));
static assert(__traits(hasMember, StringHashMap!HeapOwner, "release"));
static assert(!__traits(hasMember, OwnedStringHashMap!HeapOwner, "release"));
static assert(__traits(compiles,
        (ref OwnedStringHashMap!HeapOwner map, HeapOwner* value) { map.tryAdd("key", value); }));
static assert(!__traits(compiles,
        (ref OwnedStringHashMap!HeapOwner map, HeapOwner value) { map.tryAdd("key", move(value)); }));
static assert(__traits(compiles, () { DestructorOwnerMap map; }));
static assert(__traits(compiles, () { DestructorOwnerSet set; }));
static assert(__traits(compiles, () { OwnedStringHashMap!DestructorOwner map; }));
static assert(!__traits(compiles, () {
        OwnedHashSet!(ContextOwner, ContextOwnerHash, ContextOwnerEqual) set;
    }));
static assert(!__traits(compiles, () { OwnedHashMap!(int, ContextOwner) map; }));
static assert(!__traits(compiles, () { OwnedStringHashMap!ContextOwner map; }));

private void assertClean(ref const InstrumentedAllocator allocator)
{
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
}

private void testSafeSelfValueReplacement() @system
{
    HashMap!(int, int) map = HashMap!(int, int).create(mallocAllocator());
    assert(map.set(1, 10));
    int key = 1;
    int* stored = map.find(1);
    assert(stored !is null && *stored == 10);
    assert(map.trySet(&key, stored) == SetStatus.replaced);
    assert(*stored == 10);
    assert(map.tryAdd(&key, stored) == AddStatus.alreadyPresent);
    assert(*stored == 10);
    deinit(map);
}

private void testOwnedMapRelocationAndDiscard() @system
{
    AllocationRecord[128] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    size_t deinits;
    OwnerMap map = OwnerMap.create(tracked.allocator);

    foreach (id; 0 .. 24)
    {
        HeapOwner key = HeapOwner.create(tracked.allocator, id, &deinits);
        HeapOwner value = HeapOwner.create(tracked.allocator, 1000 + id, &deinits);
        assert(map.add(&key, &value));
        assert(key.bytes.ptr is null && value.bytes.ptr is null);
    }
    assert(deinits == 0);

    map.reserve(128);
    assert(deinits == 0);
    HeapOwner lookup = HeapOwner.probe(5);
    assert(map.contains(&lookup));
    assert(map.remove(&lookup));
    assert(deinits == 2);

    map.shrinkToFit();
    assert(deinits == 2);
    map.clear();
    assert(deinits == 48);
    deinit(map);
    assertClean(tracked);
}

private void testOwnedMapFailurePreservesInputs() @system
{
    AllocationRecord[64] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    size_t deinits;
    OwnerMap map = OwnerMap.create(tracked.allocator);

    foreach (id; 0 .. 7)
    {
        HeapOwner key = HeapOwner.create(tracked.allocator, id, &deinits);
        HeapOwner value = HeapOwner.create(tracked.allocator, 100 + id, &deinits);
        assert(map.add(&key, &value));
    }

    HeapOwner duplicateKey = HeapOwner.create(tracked.allocator, 3, &deinits);
    HeapOwner duplicateValue = HeapOwner.create(tracked.allocator, 900, &deinits);
    HeapOwner absentKey = HeapOwner.create(tracked.allocator, 99, &deinits);
    HeapOwner absentValue = HeapOwner.create(tracked.allocator, 999, &deinits);
    HeapOwner setKey = HeapOwner.create(tracked.allocator, 100, &deinits);
    HeapOwner setValue = HeapOwner.create(tracked.allocator, 1000, &deinits);

    tracked.failAfter(0);
    assert(map.tryAdd(&duplicateKey, &duplicateValue) == AddStatus.alreadyPresent);
    assert(duplicateKey.bytes.ptr !is null && duplicateValue.bytes.ptr !is null);
    const previousLength = map.length;
    const previousCapacity = map.capacity;
    assert(map.tryAdd(&absentKey, &absentValue) == AddStatus.outOfMemory);
    assert(absentKey.bytes.ptr !is null && absentValue.bytes.ptr !is null);
    assert(map.length == previousLength && map.capacity == previousCapacity);
    assert(map.trySet(&setKey, &setValue) == SetStatus.outOfMemory);
    assert(setKey.bytes.ptr !is null && setValue.bytes.ptr !is null);
    assert(map.length == previousLength && map.capacity == previousCapacity);
    tracked.allowAllocations();

    deinit(duplicateKey);
    deinit(duplicateValue);
    deinit(absentKey);
    deinit(absentValue);
    deinit(setKey);
    deinit(setValue);
    deinit(map);
    assert(deinits == 20);
    assertClean(tracked);
}

private void testOwnedMapReplacementAndTransfer() @system
{
    AllocationRecord[32] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    size_t deinits;
    OwnerMap map = OwnerMap.create(tracked.allocator);

    HeapOwner key = HeapOwner.create(tracked.allocator, 1, &deinits);
    HeapOwner value = HeapOwner.create(tracked.allocator, 10, &deinits);
    assert(map.add(&key, &value));

    HeapOwner replacementKey = HeapOwner.create(tracked.allocator, 1, &deinits);
    HeapOwner replacementValue = HeapOwner.create(tracked.allocator, 20, &deinits);
    assert(map.trySet(&replacementKey, &replacementValue) == SetStatus.replaced);
    assert(deinits == 1);
    assert(replacementKey.bytes.ptr !is null);
    assert(replacementValue.bytes.ptr is null);

    HeapOwner lookup = HeapOwner.probe(1);
    HeapOwner keyOutput = void;
    HeapOwner valueOutput = void;
    assert(map.take(&lookup, &keyOutput, &valueOutput));
    assert(map.empty && deinits == 1);
    assert(keyOutput.id == 1 && valueOutput.id == 20);

    deinit(replacementKey);
    deinit(keyOutput);
    deinit(valueOutput);
    deinit(map);
    assert(deinits == 4);
    assertClean(tracked);
}

private void testOwnedSetFailurePreservesInput() @system
{
    AllocationRecord[48] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    size_t deinits;
    OwnerSet set = OwnerSet.create(tracked.allocator);

    foreach (id; 0 .. 7)
    {
        HeapOwner value = HeapOwner.create(tracked.allocator, id, &deinits);
        assert(set.add(&value));
    }

    HeapOwner duplicate = HeapOwner.create(tracked.allocator, 3, &deinits);
    HeapOwner absent = HeapOwner.create(tracked.allocator, 99, &deinits);
    const previousLength = set.length;
    const previousCapacity = set.capacity;
    tracked.failAfter(0);
    assert(set.tryAdd(&duplicate) == AddStatus.alreadyPresent);
    assert(duplicate.bytes.ptr !is null);
    assert(set.tryAdd(&absent) == AddStatus.outOfMemory);
    assert(absent.bytes.ptr !is null);
    assert(set.length == previousLength && set.capacity == previousCapacity);
    tracked.allowAllocations();

    deinit(duplicate);
    deinit(absent);
    deinit(set);
    assert(deinits == 9);
    assertClean(tracked);
}

private void testOwnedSetTransferAndDiscard() @system
{
    AllocationRecord[64] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    size_t deinits;
    OwnerSet set = OwnerSet.create(tracked.allocator);

    foreach (id; 0 .. 12)
    {
        HeapOwner value = HeapOwner.create(tracked.allocator, id, &deinits);
        assert(set.add(&value));
    }
    set.reserve(64);
    assert(deinits == 0);

    HeapOwner lookup3 = HeapOwner.probe(3);
    HeapOwner transferred = void;
    assert(set.take(&lookup3, &transferred));
    assert(deinits == 0 && transferred.id == 3);

    HeapOwner lookup4 = HeapOwner.probe(4);
    assert(set.remove(&lookup4));
    assert(deinits == 1);
    deinit(transferred);
    assert(deinits == 2);
    deinit(set);
    assert(deinits == 12);
    assertClean(tracked);
}

private void testShallowMapDoesNotCleanElements() @system
{
    size_t deinits;
    ShallowCountingMap map = ShallowCountingMap.create(mallocAllocator());
    foreach (id; 0 .. 8)
    {
        CountingOwner key = CountingOwner(id, &deinits);
        CountingOwner value = CountingOwner(100 + id, &deinits);
        assert(map.add(&key, &value));
    }
    CountingOwner lookup = CountingOwner(2, null);
    assert(map.remove(&lookup));
    map.clear();
    deinit(map);
    assert(deinits == 0);
}

private void testShallowMapTransfersBeforeDiscard() @system
{
    AllocationRecord[96] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    size_t deinits;
    ShallowOwnerMap map = ShallowOwnerMap.create(tracked.allocator);

    foreach (id; 0 .. 20)
    {
        HeapOwner key = HeapOwner.create(tracked.allocator, id, &deinits);
        HeapOwner value = HeapOwner.create(tracked.allocator, 500 + id, &deinits);
        assert(map.add(&key, &value));
    }
    map.reserve(96);
    assert(deinits == 0);

    while (!map.empty)
    {
        auto cursor = map.cursor();
        assert(cursor.valid);
        HeapOwner key = void;
        HeapOwner value = void;
        assert(map.take(cursor.key, &key, &value));
        deinit(key);
        deinit(value);
    }
    assert(deinits == 40);
    deinit(map);
    assertClean(tracked);
}

private void testDisabledDefaultOwnedMap() @system
{
    AllocationRecord[64] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    size_t deinits;
    DisabledOwnerMap map = DisabledOwnerMap.create(tracked.allocator);

    foreach (id; 0 .. 18)
    {
        DisabledDefaultOwner key = DisabledDefaultOwner.create(
            tracked.allocator, id, &deinits);
        DisabledDefaultOwner value = DisabledDefaultOwner.create(
            tracked.allocator, 100 + id, &deinits);
        assert(map.add(&key, &value));
        assert(key.bytes.ptr is null && value.bytes.ptr is null);
    }
    map.reserve(128);
    assert(deinits == 0);
    DisabledDefaultOwner lookup = DisabledDefaultOwner.probe(4);
    assert(map.remove(&lookup));
    assert(deinits == 2);
    deinit(map);
    assert(deinits == 36);
    assertClean(tracked);
}

private void testCollisionStressAgainstReference() @system
{
    AllocationRecord[256] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    alias CollisionMap = HashMap!(int, int, ConstantCollisionHash, DefaultEqual!int);
    CollisionMap map = CollisionMap.create(tracked.allocator);
    bool[128] present;
    int[128] expected;
    uint state = 0xC001D00D;

    foreach (iteration; 0 .. 20_000)
    {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        const key = cast(int)(state & 127);
        const operation = (state >> 8) % 6;
        const value = cast(int)(state ^ (state >> 16));

        final switch (operation)
        {
            case 0:
            {
                const status = map.trySet(key, value);
                assert(status != SetStatus.outOfMemory);
                assert((status == SetStatus.inserted) == !present[key]);
                present[key] = true;
                expected[key] = value;
                break;
            }
            case 1:
            {
                const status = map.tryAdd(key, value);
                assert(status != AddStatus.outOfMemory);
                assert((status == AddStatus.inserted) == !present[key]);
                if (!present[key])
                {
                    present[key] = true;
                    expected[key] = value;
                }
                break;
            }
            case 2:
                assert(map.remove(key) == present[key]);
                present[key] = false;
                break;
            case 3:
            {
                const found = map.find(key);
                assert((found !is null) == present[key]);
                if (found !is null)
                    assert(*found == expected[key]);
                break;
            }
            case 4:
                assert(map.tryReserve(cast(size_t)((state >> 16) & 255)));
                break;
            case 5:
                assert(map.tryShrinkToFit());
                break;
        }

        if ((iteration & 255) == 0)
        {
            foreach (probe; 0 .. 128)
            {
                const found = map.find(probe);
                assert((found !is null) == present[probe]);
                if (found !is null)
                    assert(*found == expected[probe]);
            }
        }
    }

    deinit(map);
    assertClean(tracked);
}

private void testRepeatedOwnedMapCleanup() @system
{
    AllocationRecord[96] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    size_t deinits;

    foreach (iteration; 0 .. 64)
    {
        OwnerMap map = OwnerMap.create(tracked.allocator);
        foreach (id; 0 .. 16)
        {
            HeapOwner key = HeapOwner.create(tracked.allocator, id, &deinits);
            HeapOwner value = HeapOwner.create(
                tracked.allocator,
                1000 + id,
                &deinits,
            );
            assert(map.add(&key, &value));
        }
        map.reserve(96);
        foreach (id; 0 .. 8)
        {
            HeapOwner lookup = HeapOwner.probe(id);
            assert(map.remove(&lookup));
        }
        map.shrinkToFit();
        map.clear();
        deinit(map);
        assertClean(tracked);
    }
    assert(deinits == 64 * 32);
}

private void testMoveOnlyStringBufKeys() @system
{
    AllocationRecord[64] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(), records[]);
    StringBufOwnerMap map = StringBufOwnerMap.create(tracked.allocator);

    static immutable keys = ["alpha", "beta", "gamma", "delta"];
    foreach (index, keyText; keys)
    {
        StringBuf key = StringBuf.fromString(tracked.allocator, keyText);
        int value = cast(int) index;
        assert(map.add(&key, &value));
        assert(key.allocator is null);
    }

    map.reserve(64);
    StringBuf lookup = StringBuf.fromString(tracked.allocator, "beta");
    assert(map.contains(&lookup));
    assert(map.remove(&lookup));
    lookup.deinit();
    deinit(map);
    assertClean(tracked);

    StringBufOwnerSet set = StringBufOwnerSet.create(tracked.allocator);
    StringBuf setValue = StringBuf.fromString(tracked.allocator, "set-value");
    assert(set.add(&setValue));
    assert(setValue.allocator is null);
    set.reserve(32);
    StringBuf setLookup = StringBuf.fromString(tracked.allocator, "set-value");
    assert(set.remove(&setLookup));
    setLookup.deinit();
    deinit(set);
    assertClean(tracked);
}

private void testOwnedStringMapValueOwnership() @system
{
    AllocationRecord[96] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    size_t deinits;
    auto map = OwnedStringHashMap!HeapOwner.create(tracked.allocator);

    static immutable keys = [
        "a", "b", "c", "d", "e", "f", "g", "h",
        "i", "j", "k", "l", "m", "n", "o", "p",
    ];
    foreach (index, key; keys)
    {
        HeapOwner value = HeapOwner.create(
            tracked.allocator, cast(int) index, &deinits);
        assert(map.add(key, &value));
        assert(value.bytes.ptr is null);
    }
    assert(deinits == 0);
    map.reserve(64);
    assert(deinits == 0);

    HeapOwner replacement = HeapOwner.create(tracked.allocator, 99, &deinits);
    assert(map.trySet("a", &replacement) == SetStatus.replaced);
    assert(replacement.bytes.ptr is null);
    assert(deinits == 1);

    HeapOwner duplicate = HeapOwner.create(tracked.allocator, 100, &deinits);
    assert(map.tryAdd("a", &duplicate) == AddStatus.alreadyPresent);
    assert(duplicate.bytes.ptr !is null);

    map.reserve(128);
    tracked.failAfter(0);
    HeapOwner retained = HeapOwner.create(mallocAllocator(), 101, null);
    assert(map.tryAdd("allocation-fails", &retained) == AddStatus.outOfMemory);
    assert(retained.bytes.ptr !is null);
    tracked.allowAllocations();
    deinit(retained);
    deinit(duplicate);

    assert(map.remove("b"));
    assert(deinits == 3);
    deinit(map);
    assert(deinits == 18);
    assertClean(tracked);
}

private void testShallowStringMapDoesNotCleanValues() @system
{
    size_t deinits;
    auto map = StringHashMap!CountingOwner.create(mallocAllocator());
    CountingOwner first = CountingOwner(1, &deinits);
    CountingOwner second = CountingOwner(2, &deinits);
    assert(map.add("first", &first));
    assert(map.add("second", &second));
    assert(map.remove("first"));
    map.clear();
    deinit(map);
    assert(deinits == 0);
}

private void testDestructorOwnedContainers() @system
{
    size_t destructions;

    DestructorOwnerMap map = DestructorOwnerMap.create(mallocAllocator());
    int firstKey = 1;
    DestructorOwner firstValue = DestructorOwner(1, &destructions, true);
    assert(map.add(&firstKey, &firstValue));
    assert(!firstValue.armed);
    assert(map.remove(1));
    assert(destructions == 1);

    int secondKey = 2;
    DestructorOwner secondValue = DestructorOwner(2, &destructions, true);
    assert(map.add(&secondKey, &secondValue));
    deinit(map);
    assert(destructions == 2);

    DestructorOwnerSet set = DestructorOwnerSet.create(mallocAllocator());
    DestructorOwner setValue = DestructorOwner(3, &destructions, true);
    assert(set.add(&setValue));
    DestructorOwner setProbe = DestructorOwner(3, null, false);
    assert(set.remove(&setProbe));
    assert(destructions == 3);
    deinit(set);

    auto stringMap =
        OwnedStringHashMap!DestructorOwner.create(mallocAllocator());
    DestructorOwner stringValue = DestructorOwner(4, &destructions, true);
    assert(stringMap.add("value", &stringValue));
    assert(stringMap.remove("value"));
    assert(destructions == 4);
    deinit(stringMap);
}

private void testStringSetExplicitCleanup() @system
{
    AllocationRecord[64] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(), records[]);
    StringHashSet set = StringHashSet.create(tracked.allocator);
    assert(set.add("alpha"));
    assert(set.add("beta"));
    assert(set.add("gamma"));
    set.reserve(32);
    assert(set.remove("beta"));
    deinit(set);
    assertClean(tracked);
}

extern (C) int main() nothrow @nogc
{
    testSafeSelfValueReplacement();
    testOwnedMapRelocationAndDiscard();
    testOwnedMapFailurePreservesInputs();
    testOwnedMapReplacementAndTransfer();
    testOwnedSetFailurePreservesInput();
    testOwnedSetTransferAndDiscard();
    testShallowMapDoesNotCleanElements();
    testShallowMapTransfersBeforeDiscard();
    testDisabledDefaultOwnedMap();
    testCollisionStressAgainstReference();
    testRepeatedOwnedMapCleanup();
    testMoveOnlyStringBufKeys();
    testOwnedStringMapValueOwnership();
    testShallowStringMapDoesNotCleanValues();
    testDestructorOwnedContainers();
    testStringSetExplicitCleanup();
    return 0;
}
