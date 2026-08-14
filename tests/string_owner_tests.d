module tests.string_owner_tests;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.array : OwnedArray;
import xtb.core.hash_map : AddStatus, OwnedHashMap;
import xtb.core.lifetime : deinit, move, moveAssign, needsDeinit;
import xtb.core.option : Option, some;
import xtb.core.owned_string : OwnedString, OwnedStringUnmanaged;
import xtb.core.result : Result;
import xtb.core.string : StringBuf, StringBufUnmanaged;

static assert(!hasElaborateDestructor!StringBuf);
static assert(!hasElaborateDestructor!OwnedString);
static assert(!hasElaborateDestructor!StringBufUnmanaged);
static assert(!hasElaborateDestructor!OwnedStringUnmanaged);
static assert(needsDeinit!StringBuf);
static assert(needsDeinit!OwnedString);
static assert(!__traits(compiles,
        (ref StringBuf left, ref StringBuf right) { left = move(right); }));
static assert(!__traits(compiles,
        (ref OwnedString left, ref OwnedString right) { left = move(right); }));
static assert(!__traits(compiles,
        (ref StringBufUnmanaged left, ref StringBufUnmanaged right) {
        left = move(right);
    }));
static assert(!__traits(compiles,
        (ref OwnedStringUnmanaged left, ref OwnedStringUnmanaged right) {
        left = move(right);
    }));

private void testStringBufMoveReplacement(InstrumentedAllocator* tracked)
{
    StringBuf source = StringBuf.fromString(tracked.allocator, "source");
    StringBuf target = StringBuf.fromString(tracked.allocator, "target");
    assert(tracked.stats.outstandingAllocations == 2);

    moveAssign(source, target);
    assert(source.allocator is null && source.empty);
    assert(target.view == "source");
    assert(tracked.stats.outstandingAllocations == 1);

    deinit(source);
    deinit(target);
    assert(tracked.clean);
}

private void testOwnedStringMoveReplacement(InstrumentedAllocator* tracked)
{
    OwnedString source = OwnedString.fromString(tracked.allocator, "source");
    OwnedString target = OwnedString.fromString(tracked.allocator, "target");
    assert(tracked.stats.outstandingAllocations == 2);

    moveAssign(source, target);
    assert(source.allocator is null && source.empty);
    assert(target.view == "source");
    assert(tracked.stats.outstandingAllocations == 1);

    deinit(source);
    deinit(target);
    assert(tracked.clean);
}

private void testReleasedStorage(InstrumentedAllocator* tracked)
{
    StringBuf source = StringBuf.fromString(tracked.allocator, "released");
    auto released = source.release();
    assert(source.allocator is null && source.empty);
    assert(released.allocator is tracked.allocator);
    assert(released.storage.view == "released");

    StringBuf adopted = StringBuf.adopt(&released);
    assert(released.allocator is null && released.storage.empty);
    assert(adopted.view == "released");
    deinit(adopted);
    deinit(source);
    assert(tracked.clean);

    OwnedString exactString = OwnedString.fromString(tracked.allocator, "exact");
    auto immutableReleased = exactString.release();
    assert(exactString.allocator is null && exactString.empty);
    OwnedString immutableAdopted = OwnedString.adopt(&immutableReleased);
    assert(immutableAdopted.view == "exact");
    deinit(immutableAdopted);
    deinit(exactString);
    assert(tracked.clean);
}


private void testConstructionFailure(InstrumentedAllocator* tracked)
{
    tracked.failAfter(0);

    StringBuf buffer;
    assert(!StringBuf.tryFromString(tracked.allocator, "buffer", &buffer));
    assert(buffer.allocator is null && buffer.empty);

    OwnedString text;
    assert(!OwnedString.tryFromString(tracked.allocator, "text", &text));
    assert(text.allocator is null && text.empty);
    assert(tracked.clean);
    assert(tracked.stats.invalidCalls == 0);

    tracked.allowAllocations();
    deinit(buffer);
    deinit(text);
    assert(tracked.clean);
}

private void testOptionResultComposition(InstrumentedAllocator* tracked)
{
    StringBuf optionalValue = StringBuf.fromString(tracked.allocator, "option");
    Option!StringBuf optional = some(move(optionalValue));
    assert(optional.isSome && optional.value == "option");
    deinit(optional);
    deinit(optionalValue);
    assert(tracked.clean);

    OwnedString error = OwnedString.fromString(tracked.allocator, "error");
    auto failed = Result!(StringBuf, OwnedString).err(move(error));
    assert(failed.isErr && failed.error.view == "error");
    deinit(failed);
    deinit(error);
    assert(tracked.clean);

    StringBuf success = StringBuf.fromString(tracked.allocator, "ok");
    auto succeeded = Result!(StringBuf, OwnedString).ok(move(success));
    assert(succeeded.isOk && succeeded.value == "ok");
    deinit(succeeded);
    deinit(success);
    assert(tracked.clean);
}

private void testOwnedContainers(InstrumentedAllocator* tracked)
{
    OwnedArray!StringBuf values = OwnedArray!StringBuf.create(tracked.allocator);
    foreach (text; ["alpha", "beta", "gamma"])
    {
        StringBuf value = StringBuf.fromString(tracked.allocator, text);
        values.append(move(value));
        deinit(value);
    }
    assert(values.length == 3);
    assert(values[1] == "beta");
    deinit(values);
    assert(tracked.clean);

    alias Map = OwnedHashMap!(StringBuf, OwnedString);
    Map map = Map.create(tracked.allocator);
    StringBuf key = StringBuf.fromString(tracked.allocator, "key");
    OwnedString value = OwnedString.fromString(tracked.allocator, "value");
    assert(map.tryAdd(&key, &value) == AddStatus.inserted);
    assert(key.allocator is null && key.empty);
    assert(value.allocator is null && value.empty);
    deinit(map);
    deinit(key);
    deinit(value);
    assert(tracked.clean);
}

extern (C) int main()
{
    AllocationRecord[256] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    testStringBufMoveReplacement(&tracked);
    testOwnedStringMoveReplacement(&tracked);
    testReleasedStorage(&tracked);
    testConstructionFailure(&tracked);
    testOptionResultComposition(&tracked);
    testOwnedContainers(&tracked);

    assert(tracked.clean);
    assert(tracked.stats.outstandingAllocations == 0);
    assert(tracked.stats.outstandingBytes == 0);
    assert(tracked.stats.invalidCalls == 0);
    return 0;
}
