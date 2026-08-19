module tests.string_owner_tests;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import xtb.core.allocators.arena : Arena;
import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.array : OwnedArray;
import xtb.core.hash_map : AddStatus, OwnedHashMap, OwnedHashSet, SetStatus;
import xtb.core.lifetime : deinit, move, moveAssign, needsDeinit;
import xtb.core.memory : Allocator;
import xtb.core.option : Option, some;
import xtb.core.result : Result;
import xtb.core.string : OwnedString, OwnedStringUnmanaged, StringBuf,
    StringBufUnmanaged, concat, copy, escape, intoOwnedString, join, replace,
    tryConcat, tryCopy, tryEscape, tryIntoOwnedString, tryJoin, tryReplace;
import xtb.core.string_hash_map : OwnedStringHashMap;
import xtb.core.types : String;

static assert(!hasElaborateDestructor!StringBuf);
static assert(!hasElaborateDestructor!OwnedString);
static assert(!hasElaborateDestructor!StringBufUnmanaged);
static assert(!hasElaborateDestructor!OwnedStringUnmanaged);
static assert(needsDeinit!StringBuf);
static assert(needsDeinit!OwnedString);
static assert(needsDeinit!StringBufUnmanaged);
static assert(needsDeinit!OwnedStringUnmanaged);
static assert(!__traits(compiles,
        (ref StringBufUnmanaged value) { deinit(value); }));
static assert(!__traits(compiles,
        (ref OwnedStringUnmanaged value) { deinit(value); }));
static assert(__traits(compiles,
        (ref StringBufUnmanaged value, Allocator* allocator) { deinit(value, allocator); }));
static assert(__traits(compiles,
        (ref OwnedStringUnmanaged value, Allocator* allocator) { deinit(value, allocator); }));
static assert(!__traits(compiles,
        (ref StringBuf left, ref StringBuf right) { left = move(right); }));
static assert(!__traits(compiles,
        (ref OwnedString left, ref OwnedString right) { left = move(right); }));
static assert(!__traits(compiles,
        (ref StringBuf value) { value.tryReplace("a", "b"); }));
static assert(!__traits(compiles,
        (ref StringBufUnmanaged value, Allocator* allocator) {
        value.tryReplace(allocator, "a", "b");
    }));
static assert(!__traits(compiles,
        (Allocator* allocator, ref StringBuf value) {
        auto result = OwnedString.fromStringBuf(allocator, &value);
    }));
static assert(__traits(compiles,
        (ref StringBuf value) { OwnedString result = value.intoOwnedString(); deinit(result); }));
static assert(!__traits(compiles,
        (ref StringBufUnmanaged left, ref StringBufUnmanaged right) { left = move(right); }));
static assert(!__traits(compiles,
        (ref OwnedStringUnmanaged left, ref OwnedStringUnmanaged right) { left = move(right); }));
static assert(needsDeinit!(Option!StringBuf));
static assert(needsDeinit!(Option!OwnedString));
static assert(needsDeinit!(Result!(StringBuf, OwnedString)));
static assert(needsDeinit!(Result!(int, OwnedString)));
static assert(!__traits(compiles,
        (Option!StringBuf value) { return value.map!(item => 1); }));
static assert(!__traits(compiles,
        (Option!OwnedString value) { return value.map!(item => 1); }));
static assert(!__traits(compiles,
        (Result!(StringBuf, int) value) { return value.map!(item => 1); }));
static assert(!__traits(compiles,
        (Result!(int, OwnedString) value) { return value.map!(item => item + 1); }));

private static immutable integrationKeys = [
    "key-00", "key-01", "key-02", "key-03",
    "key-04", "key-05", "key-06", "key-07",
    "key-08", "key-09", "key-10", "key-11",
    "key-12", "key-13", "key-14", "key-15",
    "key-16", "key-17", "key-18", "key-19",
    "key-20", "key-21", "key-22", "key-23",
];

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

private void testOwnedStringTransforms(InstrumentedAllocator* tracked)
{
    OwnedString copied = "copy".copy(tracked.allocator);
    assert(copied.view == "copy");
    assert(tracked.stats.outstandingBytes == copied.byteLength);
    deinit(copied);
    assert(tracked.clean);

    OwnedString concatenated = "left".concat("right", tracked.allocator);
    assert(concatenated.view == "leftright");
    assert(tracked.stats.outstandingBytes == concatenated.byteLength);
    deinit(concatenated);
    assert(tracked.clean);

    OwnedString replaced = "one two one".replace(
        "one",
        "1",
        tracked.allocator,
    );
    assert(replaced.view == "1 two 1");
    assert(tracked.stats.outstandingBytes == replaced.byteLength);
    deinit(replaced);
    assert(tracked.clean);

    String[3] parts = ["a", "b", "c"];
    OwnedString joined = parts[].join("/", tracked.allocator);
    assert(joined.view == "a/b/c");
    assert(tracked.stats.outstandingBytes == joined.byteLength);
    deinit(joined);
    assert(tracked.clean);

    OwnedString escaped = "a\n\t\\b".escape(tracked.allocator);
    assert(escaped.view == "a\\n\\t\\\\b");
    assert(tracked.stats.outstandingBytes == escaped.byteLength);
    deinit(escaped);
    assert(tracked.clean);

    tracked.failAfter(0);
    OwnedString failedCopy;
    OwnedString failedConcat;
    OwnedString failedReplace;
    OwnedString failedJoin;
    OwnedString failedEscape;
    assert(!"copy".tryCopy(tracked.allocator, &failedCopy));
    assert(!"a".tryConcat("b", tracked.allocator, &failedConcat));
    assert(!"a".tryReplace("a", "b", tracked.allocator, &failedReplace));
    assert(!parts[].tryJoin("/", tracked.allocator, &failedJoin));
    assert(!"\n".tryEscape(tracked.allocator, &failedEscape));
    assert(failedCopy.allocator is null && failedCopy.empty);
    assert(failedConcat.allocator is null && failedConcat.empty);
    assert(failedReplace.allocator is null && failedReplace.empty);
    assert(failedJoin.allocator is null && failedJoin.empty);
    assert(failedEscape.allocator is null && failedEscape.empty);
    assert(tracked.clean);
    tracked.allowAllocations();
}

private void testDirectOwnedStringTransforms(InstrumentedAllocator* tracked)
{
    static assert(__traits(compiles,
            (scope const OwnedString* value, Allocator* allocator, Arena* arena) {
            OwnedString clone = value.clone();
            OwnedString concatDefault = value.concat("!");
            OwnedString concatExplicit = value.concat("!", allocator);
            String concatArena = value.concat("!", arena);
            OwnedString replaceDefault = value.replace("a", "b");
            OwnedString replaceExplicit = value.replace("a", "b", allocator);
            String replaceArena = value.replace("a", "b", arena);
            OwnedString escapeDefault = value.escape();
            OwnedString escapeExplicit = value.escape(allocator);
            String escapeArena = value.escape(arena);
            String arenaCopy = value.copy(arena);
        }));

    AllocationRecord[32] otherRecords;
    InstrumentedAllocator other = InstrumentedAllocator.create(
        mallocAllocator(),
        otherRecords[],
    );

    {
        OwnedString source = "hello\nworld".copy(tracked.allocator);
        scope (exit)
            source.deinit();

        OwnedString cloned = source.clone();
        scope (exit)
            cloned.deinit();
        assert(cloned.view == source.view);
        assert(cloned.view.ptr !is source.view.ptr);
        assert(cloned.allocator is source.allocator);

        OwnedString concatenated = source.concat("!");
        scope (exit)
            concatenated.deinit();
        assert(concatenated.view == "hello\nworld!");
        assert(concatenated.allocator is source.allocator);

        OwnedString replaced = concatenated.replace("world", "XTB");
        scope (exit)
            replaced.deinit();
        assert(replaced.view == "hello\nXTB!");
        assert(replaced.allocator is source.allocator);

        OwnedString escaped = replaced.escape();
        scope (exit)
            escaped.deinit();
        assert(escaped.view == "hello\\nXTB!");
        assert(escaped.allocator is source.allocator);

        OwnedString explicitAllocator = source.concat(" other", other.allocator);
        scope (exit)
            explicitAllocator.deinit();
        assert(explicitAllocator.view == "hello\nworld other");
        assert(explicitAllocator.allocator is other.allocator);

        Arena arena = Arena.create(tracked.allocator, 128);
        scope (exit)
            arena.deinit();
        size_t usedBytes;

        String arenaCopy = source.copy(&arena);
        usedBytes += arenaCopy.length;
        assert(arenaCopy == source.view);
        assert(arena.stats.usedBytes == usedBytes);

        String arenaConcat = source.concat(" arena", &arena);
        usedBytes += arenaConcat.length;
        assert(arenaConcat == "hello\nworld arena");
        assert(arena.stats.usedBytes == usedBytes);

        String arenaReplace = source.replace("world", "arena", &arena);
        usedBytes += arenaReplace.length;
        assert(arenaReplace == "hello\narena");
        assert(arena.stats.usedBytes == usedBytes);

        String arenaEscape = source.escape(&arena);
        usedBytes += arenaEscape.length;
        assert(arenaEscape == "hello\\nworld");
        assert(arena.stats.usedBytes == usedBytes);

        tracked.failAfter(0);
        OwnedString failed;
        scope (exit)
            failed.deinit();
        assert(!source.tryConcat(" failure", &failed));
        assert(failed.allocator is null && failed.empty);
        tracked.allowAllocations();
    }

    assert(tracked.clean);
    assert(other.clean);
}

private void testStringBufInPlaceTransforms(InstrumentedAllocator* tracked)
{
    {
        StringBuf buffer = StringBuf.fromString(
            tracked.allocator,
            "cat cat cat",
        );
        scope (exit)
            buffer.deinit();

        assert(buffer.tryReplaceInPlace("cat", "dog"));
        assert(buffer.view == "dog dog dog");
        assert(buffer.tryReplaceInPlace("dog", "x"));
        assert(buffer.view == "x x x");
        assert(buffer.tryReplaceInPlace("x", "something"));
        assert(buffer.view == "something something something");
        assert(buffer.tryReplaceInPlace("", "ignored"));
        assert(buffer.view == "something something something");
    }
    assert(tracked.clean);

    {
        StringBuf aliasedFrom = StringBuf.fromString(
            tracked.allocator,
            "abcabc",
        );
        scope (exit)
            aliasedFrom.deinit();
        String from = aliasedFrom.view[0 .. 3];
        assert(aliasedFrom.tryReplaceInPlace(from, "x"));
        assert(aliasedFrom.view == "xx");
    }
    assert(tracked.clean);

    {
        StringBuf aliasedTo = StringBuf.fromString(
            tracked.allocator,
            "abXYab",
        );
        scope (exit)
            aliasedTo.deinit();
        String to = aliasedTo.view[2 .. 4];
        assert(aliasedTo.tryReplaceInPlace("ab", to));
        assert(aliasedTo.view == "XYXYXY");
    }
    assert(tracked.clean);

    {
        StringBuf growingAliasedFrom = StringBuf.fromString(
            tracked.allocator,
            "aaaaaaaa",
        );
        scope (exit)
            growingAliasedFrom.deinit();
        String from = growingAliasedFrom.view[0 .. 1];
        assert(growingAliasedFrom.tryReplaceInPlace(from, "replacement"));
        assert(growingAliasedFrom.view ==
                "replacementreplacementreplacementreplacement" ~
                "replacementreplacementreplacementreplacement");
    }
    assert(tracked.clean);

    {
        StringBuf growingAliasedTo = StringBuf.fromString(
            tracked.allocator,
            "xLONGx",
        );
        scope (exit)
            growingAliasedTo.deinit();
        String to = growingAliasedTo.view[1 .. 5];
        assert(growingAliasedTo.tryReplaceInPlace("x", to));
        assert(growingAliasedTo.view == "LONGLONGLONG");
    }
    assert(tracked.clean);

    {
        StringBuf escaped = StringBuf.withCapacity(tracked.allocator, 64);
        scope (exit)
            escaped.deinit();
        escaped.append("first\nsecond\t\"quoted\" café🙂");
        const allocationCalls = tracked.stats.allocationCalls;
        assert(escaped.tryEscapeInPlace());
        assert(escaped.view == "first\\nsecond\\t\\\"quoted\\\" café🙂");
        assert(tracked.stats.allocationCalls == allocationCalls);
    }
    assert(tracked.clean);

    {
        StringBuf replaceFailure = StringBuf.fromString(
            tracked.allocator,
            "xxxxxxxx",
        );
        scope (exit)
            replaceFailure.deinit();
        tracked.failAfter(0);
        assert(!replaceFailure.tryReplaceInPlace("x", "replacement"));
        assert(replaceFailure.view == "xxxxxxxx");
        tracked.allowAllocations();
    }
    assert(tracked.clean);

    {
        StringBuf aliasFailure = StringBuf.fromString(
            tracked.allocator,
            "alias-alias",
        );
        scope (exit)
            aliasFailure.deinit();
        String aliasedNeedle = aliasFailure.view[0 .. 5];
        tracked.failAfter(0);
        assert(!aliasFailure.tryReplaceInPlace(aliasedNeedle, "x"));
        assert(aliasFailure.view == "alias-alias");
        tracked.allowAllocations();
    }
    assert(tracked.clean);

    {
        StringBuf escapeFailure = StringBuf.fromString(
            tracked.allocator,
            "\n\n\n\n\n\n\n\n",
        );
        scope (exit)
            escapeFailure.deinit();
        tracked.failAfter(0);
        assert(!escapeFailure.tryEscapeInPlace());
        assert(escapeFailure.view == "\n\n\n\n\n\n\n\n");
        tracked.allowAllocations();
    }
    assert(tracked.clean);
}

private void testStringBufReplacementOutputs(InstrumentedAllocator* tracked)
{
    static assert(__traits(compiles,
            (scope const StringBuf* value, Allocator* allocator, Arena* arena) {
            OwnedString owned = value.replace("cat", "lynx", allocator);
            String temporary = value.replace("cat", "lynx", arena);
        }));
    static assert(!__traits(compiles,
            (scope const StringBuf* value) { auto replaced = value.replace("cat", "lynx"); }));

    StringBuf source = StringBuf.fromString(
        tracked.allocator,
        "cat dog cat",
    );
    scope (exit)
        source.deinit();

    String aliasedFrom = source.view[0 .. 3];
    OwnedString owned = source.replace(
        aliasedFrom,
        "lynx",
        tracked.allocator,
    );
    scope (exit)
        owned.deinit();
    assert(owned.view == "lynx dog lynx");
    assert(owned.allocator is tracked.allocator);
    assert(source.view == "cat dog cat");

    Arena arena = Arena.create(tracked.allocator, 128);
    scope (exit)
        arena.deinit();
    String temporary = source.replace("cat", "tiger", &arena);
    assert(temporary == "tiger dog tiger");
    assert(source.view == "cat dog cat");

    OwnedString failed;
    tracked.failAfter(0);
    assert(!source.tryReplace("cat", "lion", tracked.allocator, &failed));
    assert(failed.allocator is null && failed.empty);
    assert(source.view == "cat dog cat");
    tracked.allowAllocations();
    failed.deinit();
}

private void testArenaStringTransforms(InstrumentedAllocator* tracked)
{
    static assert(is(typeof("copy".copy(cast(Arena*) null)) == String));
    static assert(is(typeof("a".concat("b", cast(Arena*) null)) == String));
    static assert(is(typeof("a".replace("a", "b", cast(Arena*) null)) == String));
    static assert(is(typeof((cast(String[])["a", "b"]).join(
            "/",
            cast(Arena*) null,
            )) == String));
    static assert(is(typeof("a".escape(cast(Arena*) null)) == String));
    static assert(String.sizeof == 2 * (void*).sizeof);
    static assert(OwnedString.sizeof == String.sizeof + (Allocator*).sizeof);

    Arena arena = Arena.create(tracked.allocator, 128);
    size_t expectedUsedBytes;

    String copied = "copy".copy(&arena);
    expectedUsedBytes += copied.length;
    assert(copied == "copy");
    assert(arena.stats.usedBytes == expectedUsedBytes);

    String concatenated = "left".concat("right", &arena);
    expectedUsedBytes += concatenated.length;
    assert(concatenated == "leftright");
    assert(arena.stats.usedBytes == expectedUsedBytes);

    String replaced = "one two one".replace("one", "1", &arena);
    expectedUsedBytes += replaced.length;
    assert(replaced == "1 two 1");
    assert(arena.stats.usedBytes == expectedUsedBytes);

    String[3] parts = ["a", "b", "c"];
    String joined = parts[].join("/", &arena);
    expectedUsedBytes += joined.length;
    assert(joined == "a/b/c");
    assert(arena.stats.usedBytes == expectedUsedBytes);

    String escaped = "a\n\t\\b".escape(&arena);
    expectedUsedBytes += escaped.length;
    assert(escaped == "a\\n\\t\\\\b");
    assert(arena.stats.usedBytes == expectedUsedBytes);

    String empty = "".concat("", &arena);
    assert(empty.length == 0);
    assert(arena.stats.usedBytes == expectedUsedBytes);

    arena.deinit();
    assert(tracked.clean);

    Arena failing = Arena.create(tracked.allocator, 128);
    tracked.failAfter(0);
    String failedCopy = "unchanged-copy";
    String failedConcat = "unchanged-concat";
    String failedReplace = "unchanged-replace";
    String failedJoin = "unchanged-join";
    String failedEscape = "unchanged-escape";
    assert(!"copy".tryCopy(&failing, &failedCopy));
    assert(!"a".tryConcat("b", &failing, &failedConcat));
    assert(!"a".tryReplace("a", "b", &failing, &failedReplace));
    assert(!parts[].tryJoin("/", &failing, &failedJoin));
    assert(!"\n".tryEscape(&failing, &failedEscape));
    assert(failedCopy == "unchanged-copy");
    assert(failedConcat == "unchanged-concat");
    assert(failedReplace == "unchanged-replace");
    assert(failedJoin == "unchanged-join");
    assert(failedEscape == "unchanged-escape");
    assert(failing.stats.usedBytes == 0);
    assert(tracked.clean);
    tracked.allowAllocations();
    failing.deinit();
}

private void testStringBufIntoOwnedString(InstrumentedAllocator* tracked)
{
    {
        StringBuf exact = StringBuf.fromString(tracked.allocator, "exact");
        exact.shrinkToFit();
        const(char)* original = exact.view.ptr;

        OwnedString frozen = exact.intoOwnedString();
        scope (exit)
            frozen.deinit();

        assert(frozen.view == "exact");
        assert(frozen.view.ptr is original);
        assert(frozen.allocator is tracked.allocator);
        assert(exact.allocator is null && exact.empty);
    }
    assert(tracked.clean);

    AllocationRecord[16] foreignRecords;
    InstrumentedAllocator foreign = InstrumentedAllocator.create(
        mallocAllocator(),
        foreignRecords[],
    );
    {
        StringBuf source = StringBuf.fromString(foreign.allocator, "promote");
        const(char)* original = source.view.ptr;

        OwnedString promoted = source.intoOwnedString(tracked.allocator);
        scope (exit)
            promoted.deinit();

        assert(promoted.view == "promote");
        assert(promoted.view.ptr !is original);
        assert(promoted.allocator is tracked.allocator);
        assert(source.allocator is null && source.empty);
        assert(foreign.clean);
    }
    assert(tracked.clean);

    AllocationRecord[8] failingRecords;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(),
        failingRecords[],
    );
    {
        StringBuf retained = StringBuf.fromString(tracked.allocator, "retained");
        scope (exit)
            retained.deinit();
        OwnedString output;
        scope (exit)
            output.deinit();

        failing.failAfter(0);
        assert(!retained.tryIntoOwnedString(failing.allocator, &output));
        assert(retained.view == "retained");
        assert(retained.allocator is tracked.allocator);
        assert(output.allocator is null && output.empty);
        assert(failing.clean);
    }
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

    OwnedString optionalText = OwnedString.fromString(tracked.allocator, "owned-option");
    Option!OwnedString ownedOptional = some(move(optionalText));
    assert(ownedOptional.isSome && ownedOptional.value.view == "owned-option");
    deinit(ownedOptional);
    deinit(optionalText);
    assert(tracked.clean);

    OwnedString error = OwnedString.fromString(tracked.allocator, "error");
    auto failed = Result!(StringBuf, OwnedString).err(move(error));
    assert(failed.isErr && failed.error.view == "error");
    deinit(failed);
    deinit(error);
    assert(tracked.clean);

    OwnedString integerError = OwnedString.fromString(tracked.allocator, "integer-error");
    auto integerFailure = Result!(int, OwnedString).err(move(integerError));
    assert(integerFailure.isErr && integerFailure.error.view == "integer-error");
    deinit(integerFailure);
    deinit(integerError);
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

private void testOwnedArrayIntegration(InstrumentedAllocator* tracked)
{
    OwnedArray!StringBuf values = OwnedArray!StringBuf.create(tracked.allocator);
    foreach (text; integrationKeys)
    {
        StringBuf value = StringBuf.fromString(tracked.allocator, text);
        assert(values.tryAppend(&value));
        assert(value.allocator is null && value.empty);
    }
    assert(values.length == integrationKeys.length);
    assert(values[0] == "key-00" && values[values.length - 1] == "key-23");

    StringBuf popped = values.pop();
    assert(popped == "key-23");
    deinit(popped);
    values.removeAt(0);
    assert(values.length == integrationKeys.length - 2);

    values.clear();
    assert(values.empty);
    deinit(values);
    assert(tracked.clean);

    OwnedArray!StringBuf failing = OwnedArray!StringBuf.create(tracked.allocator);
    StringBuf retained = StringBuf.fromString(tracked.allocator, "retained-array-value");
    tracked.failAfter(0);
    assert(!failing.tryAppend(&retained));
    assert(retained.view == "retained-array-value");
    assert(failing.empty);
    tracked.allowAllocations();
    deinit(retained);
    deinit(failing);
    assert(tracked.clean);
}

private void testOwnedHashMapStringIntegration(InstrumentedAllocator* tracked)
{
    alias Map = OwnedHashMap!(StringBuf, StringBuf);
    Map map = Map.create(tracked.allocator);
    foreach (text; integrationKeys)
    {
        StringBuf key = StringBuf.fromString(tracked.allocator, text);
        StringBuf value = StringBuf.fromString(tracked.allocator, text);
        assert(map.tryAdd(&key, &value) == AddStatus.inserted);
        assert(key.allocator is null && key.empty);
        assert(value.allocator is null && value.empty);
    }
    assert(map.length == integrationKeys.length);

    StringBuf replacementKey = StringBuf.fromString(tracked.allocator, "key-03");
    StringBuf replacementValue = StringBuf.fromString(tracked.allocator, "replacement");
    assert(map.trySet(&replacementKey, &replacementValue) == SetStatus.replaced);
    assert(replacementKey.view == "key-03");
    assert(replacementValue.allocator is null && replacementValue.empty);
    StringBuf* storedReplacement = map.find(&replacementKey);
    assert(storedReplacement !is null && *storedReplacement == "replacement");
    deinit(replacementKey);
    deinit(replacementValue);

    StringBuf duplicateKey = StringBuf.fromString(tracked.allocator, "key-04");
    StringBuf duplicateValue = StringBuf.fromString(tracked.allocator, "duplicate");
    assert(map.tryAdd(&duplicateKey, &duplicateValue) == AddStatus.alreadyPresent);
    assert(duplicateKey.view == "key-04" && duplicateValue.view == "duplicate");
    deinit(duplicateKey);
    deinit(duplicateValue);

    StringBuf takeLookup = StringBuf.fromString(tracked.allocator, "key-05");
    StringBuf takenKey = void;
    StringBuf takenValue = void;
    assert(map.take(&takeLookup, &takenKey, &takenValue));
    assert(takenKey == "key-05" && takenValue == "key-05");
    deinit(takeLookup);
    deinit(takenKey);
    deinit(takenValue);

    StringBuf removeLookup = StringBuf.fromString(tracked.allocator, "key-06");
    assert(map.remove(&removeLookup));
    deinit(removeLookup);

    map.clear();
    assert(map.empty);
    deinit(map);
    assert(tracked.clean);

    Map failing = Map.create(tracked.allocator);
    StringBuf retainedKey = StringBuf.fromString(tracked.allocator, "oom-key");
    StringBuf retainedValue = StringBuf.fromString(tracked.allocator, "oom-value");
    tracked.failAfter(0);
    assert(failing.tryAdd(&retainedKey, &retainedValue) == AddStatus.outOfMemory);
    assert(retainedKey.view == "oom-key" && retainedValue.view == "oom-value");
    assert(failing.empty);
    tracked.allowAllocations();
    deinit(retainedKey);
    deinit(retainedValue);
    deinit(failing);
    assert(tracked.clean);
}

private void testOwnedHashSetStringIntegration(InstrumentedAllocator* tracked)
{
    alias Set = OwnedHashSet!StringBuf;
    Set set = Set.create(tracked.allocator);
    foreach (text; integrationKeys)
    {
        StringBuf value = StringBuf.fromString(tracked.allocator, text);
        assert(set.tryAdd(&value) == AddStatus.inserted);
        assert(value.allocator is null && value.empty);
    }
    assert(set.length == integrationKeys.length);

    StringBuf duplicate = StringBuf.fromString(tracked.allocator, "key-04");
    assert(set.tryAdd(&duplicate) == AddStatus.alreadyPresent);
    assert(duplicate.view == "key-04");
    deinit(duplicate);

    StringBuf takeLookup = StringBuf.fromString(tracked.allocator, "key-05");
    StringBuf taken = void;
    assert(set.take(&takeLookup, &taken));
    assert(taken == "key-05");
    deinit(takeLookup);
    deinit(taken);

    StringBuf removeLookup = StringBuf.fromString(tracked.allocator, "key-06");
    assert(set.remove(&removeLookup));
    deinit(removeLookup);

    set.clear();
    assert(set.empty);
    deinit(set);
    assert(tracked.clean);

    Set failing = Set.create(tracked.allocator);
    StringBuf retained = StringBuf.fromString(tracked.allocator, "oom-set-value");
    tracked.failAfter(0);
    assert(failing.tryAdd(&retained) == AddStatus.outOfMemory);
    assert(retained.view == "oom-set-value");
    assert(failing.empty);
    tracked.allowAllocations();
    deinit(retained);
    deinit(failing);
    assert(tracked.clean);
}

private void testOwnedStringHashMapIntegration(InstrumentedAllocator* tracked)
{
    auto map = OwnedStringHashMap!OwnedString.create(tracked.allocator);
    foreach (text; integrationKeys)
    {
        OwnedString value = OwnedString.fromString(tracked.allocator, text);
        assert(map.tryAdd(text, &value) == AddStatus.inserted);
        assert(value.allocator is null && value.empty);
    }
    assert(map.length == integrationKeys.length);

    OwnedString replacement = OwnedString.fromString(tracked.allocator, "replacement");
    assert(map.trySet("key-03", &replacement) == SetStatus.replaced);
    assert(replacement.allocator is null && replacement.empty);
    OwnedString* stored = map.find("key-03");
    assert(stored !is null && stored.view == "replacement");

    OwnedString duplicate = OwnedString.fromString(tracked.allocator, "duplicate");
    assert(map.tryAdd("key-04", &duplicate) == AddStatus.alreadyPresent);
    assert(duplicate.view == "duplicate");
    deinit(duplicate);

    assert(map.remove("key-05"));
    map.clear();
    assert(map.empty);
    deinit(map);
    deinit(replacement);
    assert(tracked.clean);

    auto failing = OwnedStringHashMap!OwnedString.create(tracked.allocator);
    failing.reserve(8);
    OwnedString retained = OwnedString.fromString(tracked.allocator, "oom-value");
    const failedBefore = tracked.stats.failedCalls;
    tracked.failAfter(0);
    assert(failing.tryAdd("oom-key", &retained) == AddStatus.outOfMemory);
    assert(tracked.stats.failedCalls == failedBefore + 1);
    assert(retained.view == "oom-value");
    assert(failing.empty);
    tracked.allowAllocations();
    deinit(retained);
    deinit(failing);
    assert(tracked.clean);
}

private OwnedArray!StringBuf makeStringArray(
    Allocator* allocator,
    scope const(char)[] prefix,
)
{
    OwnedArray!StringBuf result = OwnedArray!StringBuf.create(allocator);
    StringBuf first = StringBuf.fromString(allocator, prefix);
    result.append(move(first));
    StringBuf second = StringBuf.fromString(allocator, "nested-value");
    result.append(move(second));
    deinit(first);
    deinit(second);
    return move(result);
}

private void testNestedOwnedStringHashMapIntegration(InstrumentedAllocator* tracked)
{
    alias Value = OwnedArray!StringBuf;
    auto map = OwnedStringHashMap!Value.create(tracked.allocator);
    foreach (text; integrationKeys[0 .. 16])
    {
        Value value = makeStringArray(tracked.allocator, text);
        assert(map.tryAdd(text, &value) == AddStatus.inserted);
        assert(value.empty);
        deinit(value);
    }
    assert(map.length == 16);

    Value replacement = makeStringArray(tracked.allocator, "replacement-array");
    assert(map.trySet("key-03", &replacement) == SetStatus.replaced);
    assert(replacement.empty);
    Value* stored = map.find("key-03");
    assert(stored !is null && stored.length == 2);
    assert((*stored)[0] == "replacement-array");
    deinit(replacement);

    Value duplicate = makeStringArray(tracked.allocator, "duplicate-array");
    assert(map.tryAdd("key-04", &duplicate) == AddStatus.alreadyPresent);
    assert(duplicate.length == 2 && duplicate[0] == "duplicate-array");
    deinit(duplicate);

    assert(map.remove("key-05"));
    map.clear();
    assert(map.empty);
    deinit(map);
    assert(tracked.clean);

    auto failing = OwnedStringHashMap!Value.create(tracked.allocator);
    failing.reserve(8);
    Value retained = makeStringArray(tracked.allocator, "oom-array");
    const failedBefore = tracked.stats.failedCalls;
    tracked.failAfter(0);
    assert(failing.tryAdd("oom-nested-key", &retained) == AddStatus.outOfMemory);
    assert(tracked.stats.failedCalls == failedBefore + 1);
    assert(retained.length == 2 && retained[0] == "oom-array");
    assert(failing.empty);
    tracked.allowAllocations();
    deinit(retained);
    deinit(failing);
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
    testOwnedStringTransforms(&tracked);
    testDirectOwnedStringTransforms(&tracked);
    testStringBufInPlaceTransforms(&tracked);
    testStringBufReplacementOutputs(&tracked);
    testArenaStringTransforms(&tracked);
    testStringBufIntoOwnedString(&tracked);
    testOptionResultComposition(&tracked);
    testOwnedContainers(&tracked);
    testOwnedArrayIntegration(&tracked);
    testOwnedHashMapStringIntegration(&tracked);
    testOwnedHashSetStringIntegration(&tracked);
    testOwnedStringHashMapIntegration(&tracked);
    testNestedOwnedStringHashMapIntegration(&tracked);

    assert(tracked.clean);
    assert(tracked.stats.outstandingAllocations == 0);
    assert(tracked.stats.outstandingBytes == 0);
    assert(tracked.stats.invalidCalls == 0);
    return 0;
}
