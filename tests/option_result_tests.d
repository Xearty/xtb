module tests.option_result_tests;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;

import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.lifetime : deinit, move, needsDeinit;
import xtb.core.memory : Allocator, deallocateArray, tryAllocateArray;
import xtb.core.option;
import xtb.core.result;

static assert(!needsDeinit!(Option!int));
static assert(!needsDeinit!(Result!(int, int)));
static assert(!__traits(hasMember, Option!int, "deinit"));
static assert(!__traits(hasMember, Result!(int, int), "deinit"));
static assert(__traits(isCopyable, Option!(Option!int)));
static assert(__traits(isCopyable,
        Result!(Result!(int, int), int)));
static assert(!__traits(compiles,
        (ref Option!int value) { deinit(value); }));
static assert(!__traits(compiles,
        (ref Result!(int, int) value) { deinit(value); }));

static assert(__traits(compiles, {
        auto inner = some(1);
        auto outer = some(inner);
        auto mapped = move(outer).map!(value => value.unwrap());
    }));

static assert(__traits(compiles, {
        auto inner = Result!(int, int).ok(1);
        auto outer = Result!(Result!(int, int), int).ok(inner);
        auto mapped = move(outer).map!(value => value.unwrap());
    }));

private struct HeapOwner
{
nothrow @nogc:

    Allocator* allocator;
    ubyte[] bytes;
    int id;
    size_t* deinits;

    @disable this(this);

    static HeapOwner create(Allocator* allocator, int id, size_t* deinits)
    {
        HeapOwner result;
        result.allocator = allocator;
        result.id = id;
        result.deinits = deinits;
        result.bytes = allocator.tryAllocateArray!ubyte(16 + cast(size_t) id);
        assert(result.bytes.ptr !is null);
        return result;
    }

    void deinit()
    {
        if (bytes.ptr is null)
            return;
        allocator.deallocateArray(bytes);
        bytes = null;
        if (deinits !is null)
            ++*deinits;
    }
}

static assert(needsDeinit!(Option!HeapOwner));
static assert(needsDeinit!(Result!(HeapOwner, int)));
static assert(needsDeinit!(Result!(int, HeapOwner)));
static assert(__traits(hasMember, Option!HeapOwner, "deinit"));
static assert(__traits(hasMember, Result!(HeapOwner, int), "deinit"));
static assert(__traits(hasMember, Result!(int, HeapOwner), "deinit"));

private struct CopyableDestructorValue
{
nothrow @nogc:

    size_t* destructions;
    bool active;

    ~this()
    {
        if (active)
        {
            ++*destructions;
            active = false;
        }
    }
}

static assert(__traits(isCopyable, CopyableDestructorValue));
static assert(!__traits(isCopyable, Option!CopyableDestructorValue));
static assert(!__traits(isCopyable, Result!(CopyableDestructorValue, int)));
static assert(!__traits(isCopyable, Result!(int, CopyableDestructorValue)));

private struct DestructorValue
{
nothrow @nogc:

    size_t* destructions;
    bool active;

    @disable this(this);

    ~this()
    {
        if (active)
        {
            ++*destructions;
            active = false;
        }
    }
}

private struct DisabledDefaultOwner
{
nothrow @nogc:

    int* deinits;
    bool active;

    @disable this();
    @disable this(this);

    static DisabledDefaultOwner create(int* deinits)
    {
        DisabledDefaultOwner result = void;
        result.deinits = deinits;
        result.active = true;
        return move(result);
    }

    void deinit()
    {
        if (!active)
            return;
        ++*deinits;
        active = false;
    }
}

private void testOptionOwners(Allocator* allocator)
{
    size_t deinits;

    HeapOwner first = HeapOwner.create(allocator, 1, &deinits);
    Option!HeapOwner option = some(move(first));
    assert(option.isSome && option.value.id == 1);
    option.reset();
    assert(option.isNone && deinits == 1);

    HeapOwner second = HeapOwner.create(allocator, 2, &deinits);
    option = some(move(second));
    HeapOwner replacementValue = HeapOwner.create(allocator, 3, &deinits);
    Option!HeapOwner replacement = some(move(replacementValue));
    option = move(replacement);
    assert(option.value.id == 3);
    assert(deinits == 2);

    HeapOwner extracted = option.take();
    assert(option.isNone);
    deinit(option);
    assert(deinits == 2);
    deinit(extracted);
    assert(deinits == 3);

    static assert(needsDeinit!(Option!HeapOwner));
    static assert(!__traits(compiles,
            (ref Option!HeapOwner value) { Option!HeapOwner copy = value; }));
    static assert(!__traits(compiles,
            (Option!HeapOwner value) { return value.map!(item => item.id); }));
}

private void testResultTransitions(Allocator* allocator)
{
    size_t deinits;

    // Ok -> Ok.
    HeapOwner a = HeapOwner.create(allocator, 1, &deinits);
    auto target = Result!(HeapOwner, HeapOwner).ok(move(a));
    HeapOwner b = HeapOwner.create(allocator, 2, &deinits);
    auto source = Result!(HeapOwner, HeapOwner).ok(move(b));
    target = move(source);
    assert(target.isOk && target.value.id == 2);
    assert(deinits == 1);
    deinit(target);
    assert(deinits == 2);

    // Ok -> Err.
    HeapOwner c = HeapOwner.create(allocator, 3, &deinits);
    target = Result!(HeapOwner, HeapOwner).ok(move(c));
    HeapOwner d = HeapOwner.create(allocator, 4, &deinits);
    source = Result!(HeapOwner, HeapOwner).err(move(d));
    target = move(source);
    assert(target.isErr && target.error.id == 4);
    assert(deinits == 3);
    deinit(target);
    assert(deinits == 4);

    // Err -> Ok.
    HeapOwner e = HeapOwner.create(allocator, 5, &deinits);
    target = Result!(HeapOwner, HeapOwner).err(move(e));
    HeapOwner f = HeapOwner.create(allocator, 6, &deinits);
    source = Result!(HeapOwner, HeapOwner).ok(move(f));
    target = move(source);
    assert(target.isOk && target.value.id == 6);
    assert(deinits == 5);
    deinit(target);
    assert(deinits == 6);

    // Err -> Err.
    HeapOwner g = HeapOwner.create(allocator, 7, &deinits);
    target = Result!(HeapOwner, HeapOwner).err(move(g));
    HeapOwner h = HeapOwner.create(allocator, 8, &deinits);
    source = Result!(HeapOwner, HeapOwner).err(move(h));
    target = move(source);
    assert(target.isErr && target.error.id == 8);
    assert(deinits == 7);

    HeapOwner extracted = target.takeError();
    assert(target.isErr);
    deinit(target);
    assert(deinits == 7);
    deinit(extracted);
    assert(deinits == 8);

    static assert(needsDeinit!(Result!(HeapOwner, HeapOwner)));
    static assert(!__traits(compiles,
            (ref Result!(HeapOwner, HeapOwner) value) { Result!(HeapOwner, HeapOwner) copy = value; }));
    static assert(!__traits(compiles,
            (Result!(HeapOwner, int) value) { return value.map!(item => item.id); }));
    static assert(!__traits(compiles,
            (Result!(int, HeapOwner) value) { return value.map!(item => item + 1); }));
}

private void testDisabledDefaultPayload()
{
    int deinits;

    DisabledDefaultOwner optionValue = DisabledDefaultOwner.create(&deinits);
    Option!DisabledDefaultOwner option = some(move(optionValue));
    option.reset();
    assert(deinits == 1);

    DisabledDefaultOwner resultValue = DisabledDefaultOwner.create(&deinits);
    auto result = Result!(DisabledDefaultOwner, int).ok(move(resultValue));
    DisabledDefaultOwner extracted = result.take();
    deinit(result);
    assert(deinits == 1);
    deinit(extracted);
    assert(deinits == 2);
}

private void testDestructorPayloads()
{
    size_t copyableOptionDestructions;
    CopyableDestructorValue copyableOptionValue =
        CopyableDestructorValue(&copyableOptionDestructions, true);
    Option!CopyableDestructorValue copyableOption = some(
        move(copyableOptionValue),
    );
    deinit(copyableOption);
    assert(copyableOptionDestructions == 1);

    size_t copyableResultDestructions;
    CopyableDestructorValue copyableResultValue =
        CopyableDestructorValue(&copyableResultDestructions, true);
    auto copyableResult = Result!(CopyableDestructorValue, int).ok(
        move(copyableResultValue),
    );
    deinit(copyableResult);
    assert(copyableResultDestructions == 1);

    static assert(!hasElaborateDestructor!(Option!DestructorValue));
    static assert(!hasElaborateDestructor!(
            Result!(DestructorValue, DestructorValue)));

    size_t optionDestructions;
    DestructorValue optionalValue = DestructorValue(&optionDestructions, true);
    Option!DestructorValue option = some(move(optionalValue));
    option.reset();
    assert(option.isNone && optionDestructions == 1);

    size_t successDestructions;
    DestructorValue successValue = DestructorValue(&successDestructions, true);
    auto success = Result!(DestructorValue, DestructorValue).ok(
        move(successValue),
    );
    deinit(success);
    assert(successDestructions == 1);

    size_t errorDestructions;
    DestructorValue errorValue = DestructorValue(&errorDestructions, true);
    auto failure = Result!(DestructorValue, DestructorValue).err(
        move(errorValue),
    );
    deinit(failure);
    assert(errorDestructions == 1);

    size_t transferredDestructions;
    DestructorValue transferredValue =
        DestructorValue(&transferredDestructions, true);
    auto transferred = Result!(DestructorValue, int).ok(move(transferredValue));
    DestructorValue extracted = transferred.take();
    deinit(transferred);
    assert(transferredDestructions == 0);
    destroy(extracted);
    assert(transferredDestructions == 1);
}

private void testSimpleMonads()
{
    auto option = some(4).map!(value => value * 3).andThen!(value => some(value + 1));
    assert(option.isSome && option.value == 13);

    auto result = Result!(int, int).ok(5)
        .map!(value => value * 2)
        .andThen!(value => Result!(long, int).ok(value + 7L))
        .mapError!(error => error + 1);
    assert(result.isOk && result.value == 17L);

    auto recovered = Result!(int, int).err(9)
        .orElse!(error => Result!(int, long).ok(error + 1));
    assert(recovered.isOk && recovered.value == 10);
}

extern (C) int main()
{
    AllocationRecord[128] records;
    InstrumentedAllocator instrumented = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    testOptionOwners(instrumented.allocator);
    testResultTransitions(instrumented.allocator);
    testDisabledDefaultPayload();
    testDestructorPayloads();
    testSimpleMonads();

    assert(instrumented.clean);
    assert(instrumented.stats.invalidCalls == 0);
    return 0;
}
