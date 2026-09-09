module tests.string_owner_tests;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import xtb.allocators.arena : Arena;
import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.allocators.malloc : malloc_allocator;
import xtb.containers.array : OwnedArray;
import xtb.containers.hash_map : AddStatus, OwnedHashMap, SetStatus;
import xtb.containers.hash_set : OwnedHashSet;
import xtb.lifetime : deinit, move, move_assign, needs_deinit;
import xtb.memory : Allocator;
import xtb.option : Option, some;
import xtb.result : Result;
import xtb.string : OwnedString, OwnedStringUnmanaged, StringBuf,
    StringBufUnmanaged, concat, copy, escape, join, replace, try_concat,
    try_copy, try_escape, try_join, try_replace;
import xtb.containers.string_hash_map : OwnedStringHashMap;
import xtb.types : String;

static assert(!hasElaborateDestructor!StringBuf);
static assert(!hasElaborateDestructor!OwnedString);
static assert(!hasElaborateDestructor!StringBufUnmanaged);
static assert(!hasElaborateDestructor!OwnedStringUnmanaged);
static assert(needs_deinit!StringBuf);
static assert(needs_deinit!OwnedString);
static assert(needs_deinit!StringBufUnmanaged);
static assert(needs_deinit!OwnedStringUnmanaged);
static assert(__traits(compiles,
        (Allocator* allocator, Arena* arena, ref StringBuf buffer,
        scope ref const OwnedString first,
        scope ref const OwnedString second) {
        StringBuf copy = StringBuf.from_string(allocator, first);
        StringBuf output;
        StringBuf.try_from_string(allocator, first, &output);
        buffer.equal(first);
        buffer.append(first);
        buffer.try_append(first);
        buffer.append_assume_capacity(first);
        buffer.insert(0, first);
        buffer.try_insert(0, first);
        buffer.prepend(first);
        buffer.try_prepend(first);
        buffer.append_escaped(first);
        buffer.try_append_escaped(first);
        buffer.compare(first);
        buffer.find(first);
        buffer.find_last(first);
        buffer.contains(first);
        buffer.starts_with(first);
        buffer.ends_with(first);
        buffer.assign(first);
        buffer.try_assign(first);
        buffer.remove_prefix(first);
        buffer.remove_suffix(first);
        auto parts = buffer.split(first, allocator);
        buffer.replace_in_place(first, second);
        buffer.replace_in_place(first, "second");
        buffer.replace_in_place("first", second);
        buffer.try_replace_in_place(first, second);
        OwnedString owned = buffer.replace(first, second, allocator);
        String temporary = buffer.replace(first, second, arena);
        OwnedString tryOwned;
        String tryTemporary;
        buffer.try_replace(first, second, allocator, &tryOwned);
        buffer.try_replace(first, second, arena, &tryTemporary);
        bool same = buffer == first;
        bool reverseSame = first == buffer;
    }));
static assert(!__traits(compiles,
        (Allocator* allocator, ref StringBuf buffer) {
        buffer.append(OwnedString.from_string(allocator, "temporary"));
    }));
static assert(!__traits(compiles,
        (Allocator* allocator, ref StringBuf buffer,
        scope ref const OwnedString replacement) {
        buffer.replace_in_place(
        OwnedString.from_string(allocator, "temporary"),
        replacement,
        );
    }));
static assert(__traits(compiles,
        (Allocator* allocator, ref StringBufUnmanaged buffer,
        scope ref const OwnedString first,
        scope ref const OwnedString second) {
        auto copy = StringBufUnmanaged.from_string(allocator, first);
        StringBufUnmanaged output;
        StringBufUnmanaged.try_from_string(allocator, first, &output);
        buffer.append(allocator, first);
        buffer.try_append(allocator, first);
        buffer.append_assume_capacity(first);
        buffer.insert(allocator, 0, first);
        buffer.try_insert(allocator, 0, first);
        buffer.prepend(allocator, first);
        buffer.try_prepend(allocator, first);
        buffer.append_escaped(allocator, first);
        buffer.try_append_escaped(allocator, first);
        buffer.replace_in_place(allocator, first, second);
        buffer.replace_in_place(allocator, first, "second");
        buffer.replace_in_place(allocator, "first", second);
        buffer.try_replace_in_place(allocator, first, second);
        bool same = buffer == first;
        bool reverseSame = first == buffer;
    }));
static assert(!__traits(compiles,
        (Allocator* allocator, ref StringBufUnmanaged buffer) {
        buffer.append(
        allocator,
        OwnedString.from_string(allocator, "temporary"),
        );
    }));
static assert(!__traits(compiles,
        (Allocator* allocator, ref StringBufUnmanaged buffer,
        scope ref const OwnedString replacement) {
        buffer.replace_in_place(
        allocator,
        OwnedString.from_string(allocator, "temporary"),
        replacement,
        );
    }));
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
        (ref StringBuf value) { value.try_replace("a", "b"); }));
static assert(!__traits(compiles,
        (ref StringBufUnmanaged value, Allocator* allocator) {
        value.try_replace(allocator, "a", "b");
    }));
static assert(!__traits(compiles,
        (Allocator* allocator, ref StringBuf value) {
        auto result = OwnedString.from_stringBuf(allocator, &value);
    }));
static assert(!__traits(compiles,
        (ref StringBufUnmanaged left, ref StringBufUnmanaged right) { left = move(right); }));
static assert(!__traits(compiles,
        (ref OwnedStringUnmanaged left, ref OwnedStringUnmanaged right) { left = move(right); }));
static assert(needs_deinit!(Option!StringBuf));
static assert(needs_deinit!(Option!OwnedString));
static assert(needs_deinit!(Result!(StringBuf, OwnedString)));
static assert(needs_deinit!(Result!(int, OwnedString)));
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

private void testOwnedStringStringBufInputs(InstrumentedAllocator* tracked)
{
    {
        OwnedString source = OwnedString.from_string(
            tracked.allocator,
            "source",
        );
        scope (exit)
            source.deinit();
        OwnedString replacement = OwnedString.from_string(
            tracked.allocator,
            "replacement",
        );
        scope (exit)
            replacement.deinit();

        StringBuf buffer = StringBuf.from_string(tracked.allocator, source);
        scope (exit)
            buffer.deinit();
        assert(buffer == source);
        assert(source == buffer);
        assert(buffer.equal(source));
        assert(buffer.compare(source) == 0);
        assert(buffer.contains(source));
        assert(buffer.starts_with(source));
        assert(buffer.ends_with(source));
        assert(buffer.find(source) == 0);
        assert(buffer.find_last(source) == 0);

        buffer.clear();
        buffer.append(source);
        buffer.prepend(source);
        buffer.insert(source.byte_length, replacement);
        assert(buffer.view == "sourcereplacementsource");

        buffer.assign(source);
        buffer.replace_in_place(source, replacement);
        assert(buffer.view == replacement.view);

        buffer.clear();
        buffer.append_escaped(replacement);
        assert(buffer.view == replacement.view);

        buffer.assign(source);
        assert(buffer.remove_prefix(source));
        assert(buffer.empty);
        buffer.assign(source);
        assert(buffer.remove_suffix(source));
        assert(buffer.empty);

        buffer.assign("leftsourceleft");
        auto parts = buffer.split(source, tracked.allocator);
        scope (exit)
            parts.deinit();
        assert(parts.length == 2);
        assert(parts[0] == "left" && parts[1] == "left");

        OwnedString replaced = buffer.replace(
            source,
            replacement,
            tracked.allocator,
        );
        scope (exit)
            replaced.deinit();
        assert(replaced.view == "leftreplacementleft");

        StringBufUnmanaged unmanaged = StringBufUnmanaged.from_string(
            tracked.allocator,
            source,
        );
        scope (exit)
            unmanaged.deinit(tracked.allocator);
        assert(unmanaged == source);
        assert(source == unmanaged);

        unmanaged.clear();
        unmanaged.append(tracked.allocator, source);
        unmanaged.prepend(tracked.allocator, source);
        unmanaged.insert(
            tracked.allocator,
            source.byte_length,
            replacement,
        );
        assert(unmanaged.view == "sourcereplacementsource");

        unmanaged.clear();
        unmanaged.append_escaped(tracked.allocator, replacement);
        assert(unmanaged.view == replacement.view);
        unmanaged.replace_in_place(
            tracked.allocator,
            replacement,
            source,
        );
        assert(unmanaged.view == source.view);
    }
    assert(tracked.clean);
}

private void testStringBufMoveReplacement(InstrumentedAllocator* tracked)
{
    StringBuf source = StringBuf.from_string(tracked.allocator, "source");
    StringBuf target = StringBuf.from_string(tracked.allocator, "target");
    assert(tracked.stats.outstanding_allocations == 2);

    move_assign(source, target);
    assert(source.allocator is null && source.empty);
    assert(target.view == "source");
    assert(tracked.stats.outstanding_allocations == 1);

    deinit(source);
    deinit(target);
    assert(tracked.clean);
}

private void testOwnedStringMoveReplacement(InstrumentedAllocator* tracked)
{
    OwnedString source = OwnedString.from_string(tracked.allocator, "source");
    OwnedString target = OwnedString.from_string(tracked.allocator, "target");
    assert(tracked.stats.outstanding_allocations == 2);

    move_assign(source, target);
    assert(source.allocator is null && source.empty);
    assert(target.view == "source");
    assert(tracked.stats.outstanding_allocations == 1);

    deinit(source);
    deinit(target);
    assert(tracked.clean);
}

private void testReleasedStorage(InstrumentedAllocator* tracked)
{
    StringBuf source = StringBuf.from_string(tracked.allocator, "released");
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

    OwnedString exactString = OwnedString.from_string(tracked.allocator, "exact");
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
    tracked.fail_after(0);

    StringBuf buffer;
    assert(!StringBuf.try_from_string(tracked.allocator, "buffer", &buffer));
    assert(buffer.allocator is null && buffer.empty);

    OwnedString text;
    assert(!OwnedString.try_from_string(tracked.allocator, "text", &text));
    assert(text.allocator is null && text.empty);
    assert(tracked.clean);
    assert(tracked.stats.invalid_calls == 0);

    tracked.allow_allocations();
    deinit(buffer);
    deinit(text);
    assert(tracked.clean);
}

private void testOwnedStringTransforms(InstrumentedAllocator* tracked)
{
    OwnedString copied = "copy".copy(tracked.allocator);
    assert(copied.view == "copy");
    assert(tracked.stats.outstanding_bytes == copied.byte_length);
    deinit(copied);
    assert(tracked.clean);

    OwnedString concatenated = "left".concat("right", tracked.allocator);
    assert(concatenated.view == "leftright");
    assert(tracked.stats.outstanding_bytes == concatenated.byte_length);
    deinit(concatenated);
    assert(tracked.clean);

    OwnedString replaced = "one two one".replace(
        "one",
        "1",
        tracked.allocator,
    );
    assert(replaced.view == "1 two 1");
    assert(tracked.stats.outstanding_bytes == replaced.byte_length);
    deinit(replaced);
    assert(tracked.clean);

    String[3] parts = ["a", "b", "c"];
    OwnedString joined = parts[].join("/", tracked.allocator);
    assert(joined.view == "a/b/c");
    assert(tracked.stats.outstanding_bytes == joined.byte_length);
    deinit(joined);
    assert(tracked.clean);

    OwnedString escaped = "a\n\t\\b".escape(tracked.allocator);
    assert(escaped.view == "a\\n\\t\\\\b");
    assert(tracked.stats.outstanding_bytes == escaped.byte_length);
    deinit(escaped);
    assert(tracked.clean);

    tracked.fail_after(0);
    OwnedString failedCopy;
    OwnedString failedConcat;
    OwnedString failedReplace;
    OwnedString failedJoin;
    OwnedString failedEscape;
    assert(!"copy".try_copy(tracked.allocator, &failedCopy));
    assert(!"a".try_concat("b", tracked.allocator, &failedConcat));
    assert(!"a".try_replace("a", "b", tracked.allocator, &failedReplace));
    assert(!parts[].try_join("/", tracked.allocator, &failedJoin));
    assert(!"\n".try_escape(tracked.allocator, &failedEscape));
    assert(failedCopy.allocator is null && failedCopy.empty);
    assert(failedConcat.allocator is null && failedConcat.empty);
    assert(failedReplace.allocator is null && failedReplace.empty);
    assert(failedJoin.allocator is null && failedJoin.empty);
    assert(failedEscape.allocator is null && failedEscape.empty);
    assert(tracked.clean);
    tracked.allow_allocations();
}

private void testDirectOwnedStringTransforms(InstrumentedAllocator* tracked)
{
    static assert(__traits(compiles,
            (scope const OwnedString* value, Allocator* allocator, Arena* arena) {
            OwnedString clone = value.clone(allocator);
            OwnedString concatExplicit = value.concat("!", allocator);
            String concatArena = value.concat("!", arena);
            OwnedString replaceExplicit = value.replace("a", "b", allocator);
            String replaceArena = value.replace("a", "b", arena);
            OwnedString escapeExplicit = value.escape(allocator);
            String escapeArena = value.escape(arena);
            String arenaCopy = value.copy(arena);
            OwnedString output;
            value.try_clone(allocator, &output);
        }));
    static assert(!__traits(compiles,
            (scope const OwnedString* value) { auto result = value.clone(); }));
    static assert(!__traits(compiles,
            (scope const OwnedString* value) { auto result = value.concat("!"); }));
    static assert(!__traits(compiles,
            (scope const OwnedString* value) { auto result = value.replace("a", "b"); }));
    static assert(!__traits(compiles,
            (scope const OwnedString* value) { auto result = value.escape(); }));
    static assert(!__traits(compiles,
            (scope const OwnedString* value, scope OwnedString* output) { value.try_clone(output); }));
    static assert(!__traits(compiles,
            (scope const OwnedString* value, scope OwnedString* output) {
            value.try_concat("!", output);
        }));
    static assert(!__traits(compiles,
            (scope const OwnedString* value, scope OwnedString* output) {
            value.try_replace("a", "b", output);
        }));
    static assert(!__traits(compiles,
            (scope const OwnedString* value, scope OwnedString* output) { value.try_escape(output); }));

    AllocationRecord[32] otherRecords;
    InstrumentedAllocator other = InstrumentedAllocator.create(
        malloc_allocator(),
        otherRecords[],
    );

    {
        OwnedString source = "hello\nworld".copy(tracked.allocator);
        scope (exit)
            source.deinit();

        OwnedString cloned = source.clone(tracked.allocator);
        scope (exit)
            cloned.deinit();
        assert(cloned.view == source.view);
        assert(cloned.view.ptr !is source.view.ptr);
        assert(cloned.allocator is source.allocator);

        OwnedString concatenated = source.concat("!", tracked.allocator);
        scope (exit)
            concatenated.deinit();
        assert(concatenated.view == "hello\nworld!");
        assert(concatenated.allocator is source.allocator);

        OwnedString replaced = concatenated.replace(
            "world",
            "XTB",
            tracked.allocator,
        );
        scope (exit)
            replaced.deinit();
        assert(replaced.view == "hello\nXTB!");
        assert(replaced.allocator is source.allocator);

        OwnedString escaped = replaced.escape(tracked.allocator);
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
        assert(arena.stats.used_bytes == usedBytes);

        String arenaConcat = source.concat(" arena", &arena);
        usedBytes += arenaConcat.length;
        assert(arenaConcat == "hello\nworld arena");
        assert(arena.stats.used_bytes == usedBytes);

        String arenaReplace = source.replace("world", "arena", &arena);
        usedBytes += arenaReplace.length;
        assert(arenaReplace == "hello\narena");
        assert(arena.stats.used_bytes == usedBytes);

        String arenaEscape = source.escape(&arena);
        usedBytes += arenaEscape.length;
        assert(arenaEscape == "hello\\nworld");
        assert(arena.stats.used_bytes == usedBytes);

        tracked.fail_after(0);
        OwnedString failed;
        scope (exit)
            failed.deinit();
        assert(!source.try_concat(" failure", tracked.allocator, &failed));
        assert(failed.allocator is null && failed.empty);
        tracked.allow_allocations();
    }

    assert(tracked.clean);
    assert(other.clean);
}

private void testStringBufInPlaceTransforms(InstrumentedAllocator* tracked)
{
    {
        StringBuf buffer = StringBuf.from_string(
            tracked.allocator,
            "cat cat cat",
        );
        scope (exit)
            buffer.deinit();

        assert(buffer.try_replace_in_place("cat", "dog"));
        assert(buffer.view == "dog dog dog");
        assert(buffer.try_replace_in_place("dog", "x"));
        assert(buffer.view == "x x x");
        assert(buffer.try_replace_in_place("x", "something"));
        assert(buffer.view == "something something something");
        assert(buffer.try_replace_in_place("", "ignored"));
        assert(buffer.view == "something something something");
    }
    assert(tracked.clean);

    {
        StringBuf aliasedFrom = StringBuf.from_string(
            tracked.allocator,
            "abcabc",
        );
        scope (exit)
            aliasedFrom.deinit();
        String from = aliasedFrom.view[0 .. 3];
        assert(aliasedFrom.try_replace_in_place(from, "x"));
        assert(aliasedFrom.view == "xx");
    }
    assert(tracked.clean);

    {
        StringBuf aliasedTo = StringBuf.from_string(
            tracked.allocator,
            "abXYab",
        );
        scope (exit)
            aliasedTo.deinit();
        String to = aliasedTo.view[2 .. 4];
        assert(aliasedTo.try_replace_in_place("ab", to));
        assert(aliasedTo.view == "XYXYXY");
    }
    assert(tracked.clean);

    {
        StringBuf growingAliasedFrom = StringBuf.from_string(
            tracked.allocator,
            "aaaaaaaa",
        );
        scope (exit)
            growingAliasedFrom.deinit();
        String from = growingAliasedFrom.view[0 .. 1];
        assert(growingAliasedFrom.try_replace_in_place(from, "replacement"));
        assert(growingAliasedFrom.view ==
                "replacementreplacementreplacementreplacement" ~
                "replacementreplacementreplacementreplacement");
    }
    assert(tracked.clean);

    {
        StringBuf growingAliasedTo = StringBuf.from_string(
            tracked.allocator,
            "xLONGx",
        );
        scope (exit)
            growingAliasedTo.deinit();
        String to = growingAliasedTo.view[1 .. 5];
        assert(growingAliasedTo.try_replace_in_place("x", to));
        assert(growingAliasedTo.view == "LONGLONGLONG");
    }
    assert(tracked.clean);

    {
        StringBuf escaped = StringBuf.with_capacity(tracked.allocator, 64);
        scope (exit)
            escaped.deinit();
        escaped.append("first\nsecond\t\"quoted\" café🙂");
        const allocationCalls = tracked.stats.allocation_calls;
        assert(escaped.try_escape_in_place());
        assert(escaped.view == "first\\nsecond\\t\\\"quoted\\\" café🙂");
        assert(tracked.stats.allocation_calls == allocationCalls);
    }
    assert(tracked.clean);

    {
        StringBuf replaceFailure = StringBuf.from_string(
            tracked.allocator,
            "xxxxxxxx",
        );
        scope (exit)
            replaceFailure.deinit();
        tracked.fail_after(0);
        assert(!replaceFailure.try_replace_in_place("x", "replacement"));
        assert(replaceFailure.view == "xxxxxxxx");
        tracked.allow_allocations();
    }
    assert(tracked.clean);

    {
        StringBuf aliasFailure = StringBuf.from_string(
            tracked.allocator,
            "alias-alias",
        );
        scope (exit)
            aliasFailure.deinit();
        String aliasedNeedle = aliasFailure.view[0 .. 5];
        tracked.fail_after(0);
        assert(!aliasFailure.try_replace_in_place(aliasedNeedle, "x"));
        assert(aliasFailure.view == "alias-alias");
        tracked.allow_allocations();
    }
    assert(tracked.clean);

    {
        StringBuf escapeFailure = StringBuf.from_string(
            tracked.allocator,
            "\n\n\n\n\n\n\n\n",
        );
        scope (exit)
            escapeFailure.deinit();
        tracked.fail_after(0);
        assert(!escapeFailure.try_escape_in_place());
        assert(escapeFailure.view == "\n\n\n\n\n\n\n\n");
        tracked.allow_allocations();
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

    StringBuf source = StringBuf.from_string(
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
    tracked.fail_after(0);
    assert(!source.try_replace("cat", "lion", tracked.allocator, &failed));
    assert(failed.allocator is null && failed.empty);
    assert(source.view == "cat dog cat");
    tracked.allow_allocations();
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
    assert(arena.stats.used_bytes == expectedUsedBytes);

    String concatenated = "left".concat("right", &arena);
    expectedUsedBytes += concatenated.length;
    assert(concatenated == "leftright");
    assert(arena.stats.used_bytes == expectedUsedBytes);

    String replaced = "one two one".replace("one", "1", &arena);
    expectedUsedBytes += replaced.length;
    assert(replaced == "1 two 1");
    assert(arena.stats.used_bytes == expectedUsedBytes);

    String[3] parts = ["a", "b", "c"];
    String joined = parts[].join("/", &arena);
    expectedUsedBytes += joined.length;
    assert(joined == "a/b/c");
    assert(arena.stats.used_bytes == expectedUsedBytes);

    String escaped = "a\n\t\\b".escape(&arena);
    expectedUsedBytes += escaped.length;
    assert(escaped == "a\\n\\t\\\\b");
    assert(arena.stats.used_bytes == expectedUsedBytes);

    String empty = "".concat("", &arena);
    assert(empty.length == 0);
    assert(arena.stats.used_bytes == expectedUsedBytes);

    arena.deinit();
    assert(tracked.clean);

    Arena failing = Arena.create(tracked.allocator, 128);
    tracked.fail_after(0);
    String failedCopy = "unchanged-copy";
    String failedConcat = "unchanged-concat";
    String failedReplace = "unchanged-replace";
    String failedJoin = "unchanged-join";
    String failedEscape = "unchanged-escape";
    assert(!"copy".try_copy(&failing, &failedCopy));
    assert(!"a".try_concat("b", &failing, &failedConcat));
    assert(!"a".try_replace("a", "b", &failing, &failedReplace));
    assert(!parts[].try_join("/", &failing, &failedJoin));
    assert(!"\n".try_escape(&failing, &failedEscape));
    assert(failedCopy == "unchanged-copy");
    assert(failedConcat == "unchanged-concat");
    assert(failedReplace == "unchanged-replace");
    assert(failedJoin == "unchanged-join");
    assert(failedEscape == "unchanged-escape");
    assert(failing.stats.used_bytes == 0);
    assert(tracked.clean);
    tracked.allow_allocations();
    failing.deinit();
}

private void testStringBufCopies(InstrumentedAllocator* tracked)
{
    static assert(__traits(compiles,
            (scope const StringBuf* value, Allocator* allocator, Arena* arena) {
            OwnedString owned = value.copy(allocator);
            String temporary = value.copy(arena);
        }));
    static assert(!__traits(compiles,
            (scope const StringBuf* value) { auto copied = value.copy(); }));

    {
        StringBuf source = StringBuf.create(tracked.allocator);
        scope (exit)
            source.deinit();
        const allocationCalls = tracked.stats.allocation_calls;

        OwnedString copied = source.copy(tracked.allocator);
        scope (exit)
            copied.deinit();
        assert(copied.empty);
        assert(copied.allocator is tracked.allocator);
        assert(source.empty);
        assert(source.allocator is tracked.allocator);
        assert(tracked.stats.allocation_calls == allocationCalls);
    }
    assert(tracked.clean);

    {
        StringBuf source = StringBuf.from_string(tracked.allocator, "same");
        scope (exit)
            source.deinit();
        const(char)* original = source.view.ptr;

        OwnedString copied = source.copy(tracked.allocator);
        scope (exit)
            copied.deinit();

        assert(copied.view == "same");
        assert(copied.view.ptr !is original);
        assert(copied.allocator is tracked.allocator);
        assert(source.view == "same");
        assert(source.allocator is tracked.allocator);
    }
    assert(tracked.clean);

    AllocationRecord[16] foreignRecords;
    InstrumentedAllocator foreign = InstrumentedAllocator.create(
        malloc_allocator(),
        foreignRecords[],
    );
    {
        StringBuf source = StringBuf.from_string(foreign.allocator, "foreign");
        scope (exit)
            source.deinit();
        const(char)* original = source.view.ptr;

        OwnedString copied = source.copy(tracked.allocator);
        scope (exit)
            copied.deinit();

        assert(copied.view == "foreign");
        assert(copied.view.ptr !is original);
        assert(copied.allocator is tracked.allocator);
        assert(source.view == "foreign");
        assert(source.allocator is foreign.allocator);
    }
    assert(foreign.clean);
    assert(tracked.clean);

    {
        StringBuf source = StringBuf.from_string(tracked.allocator, "temporary");
        scope (exit)
            source.deinit();
        Arena arena = Arena.create(tracked.allocator, 128);
        scope (exit)
            arena.deinit();

        String copied = source.copy(&arena);
        assert(copied == "temporary");
        assert(copied.ptr !is source.view.ptr);
        assert(source.view == "temporary");
    }
    assert(tracked.clean);

    AllocationRecord[8] failingRecords;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        malloc_allocator(),
        failingRecords[],
    );
    {
        StringBuf retained = StringBuf.from_string(tracked.allocator, "retained");
        scope (exit)
            retained.deinit();
        OwnedString output;
        scope (exit)
            output.deinit();

        failing.fail_after(0);
        assert(!retained.try_copy(failing.allocator, &output));
        assert(retained.view == "retained");
        assert(retained.allocator is tracked.allocator);
        assert(output.allocator is null && output.empty);
        assert(failing.clean);

        Arena failingArena = Arena.create(failing.allocator, 128);
        String arenaOutput = "unchanged";
        assert(!retained.try_copy(&failingArena, &arenaOutput));
        assert(arenaOutput == "unchanged");
        assert(retained.view == "retained");
        failingArena.deinit();
    }
    assert(tracked.clean);
}

private void testOptionResultComposition(InstrumentedAllocator* tracked)
{
    StringBuf optionalValue = StringBuf.from_string(tracked.allocator, "option");
    Option!StringBuf optional = some(move(optionalValue));
    assert(optional.is_some && optional.value == "option");
    deinit(optional);
    deinit(optionalValue);
    assert(tracked.clean);

    OwnedString optionalText = OwnedString.from_string(tracked.allocator, "owned-option");
    Option!OwnedString ownedOptional = some(move(optionalText));
    assert(ownedOptional.is_some && ownedOptional.value.view == "owned-option");
    deinit(ownedOptional);
    deinit(optionalText);
    assert(tracked.clean);

    OwnedString error = OwnedString.from_string(tracked.allocator, "error");
    auto failed = Result!(StringBuf, OwnedString).err(move(error));
    assert(failed.is_err && failed.error.view == "error");
    deinit(failed);
    deinit(error);
    assert(tracked.clean);

    OwnedString integerError = OwnedString.from_string(tracked.allocator, "integer-error");
    auto integerFailure = Result!(int, OwnedString).err(move(integerError));
    assert(integerFailure.is_err && integerFailure.error.view == "integer-error");
    deinit(integerFailure);
    deinit(integerError);
    assert(tracked.clean);

    StringBuf success = StringBuf.from_string(tracked.allocator, "ok");
    auto succeeded = Result!(StringBuf, OwnedString).ok(move(success));
    assert(succeeded.is_ok && succeeded.value == "ok");
    deinit(succeeded);
    deinit(success);
    assert(tracked.clean);
}

private void testOwnedContainers(InstrumentedAllocator* tracked)
{
    OwnedArray!StringBuf values = OwnedArray!StringBuf.create(tracked.allocator);
    foreach (text; ["alpha", "beta", "gamma"])
    {
        StringBuf value = StringBuf.from_string(tracked.allocator, text);
        values.append(move(value));
        deinit(value);
    }
    assert(values.length == 3);
    assert(values[1] == "beta");
    deinit(values);
    assert(tracked.clean);

    alias Map = OwnedHashMap!(StringBuf, OwnedString);
    Map map = Map.create(tracked.allocator);
    StringBuf key = StringBuf.from_string(tracked.allocator, "key");
    OwnedString value = OwnedString.from_string(tracked.allocator, "value");
    assert(map.try_add(&key, &value) == AddStatus.inserted);
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
        StringBuf value = StringBuf.from_string(tracked.allocator, text);
        assert(values.try_append(&value));
        assert(value.allocator is null && value.empty);
    }
    assert(values.length == integrationKeys.length);
    assert(values[0] == "key-00" && values[values.length - 1] == "key-23");

    StringBuf popped = values.pop();
    assert(popped == "key-23");
    deinit(popped);
    values.remove_at(0);
    assert(values.length == integrationKeys.length - 2);

    values.clear();
    assert(values.empty);
    deinit(values);
    assert(tracked.clean);

    OwnedArray!StringBuf failing = OwnedArray!StringBuf.create(tracked.allocator);
    StringBuf retained = StringBuf.from_string(tracked.allocator, "retained-array-value");
    tracked.fail_after(0);
    assert(!failing.try_append(&retained));
    assert(retained.view == "retained-array-value");
    assert(failing.empty);
    tracked.allow_allocations();
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
        StringBuf key = StringBuf.from_string(tracked.allocator, text);
        StringBuf value = StringBuf.from_string(tracked.allocator, text);
        assert(map.try_add(&key, &value) == AddStatus.inserted);
        assert(key.allocator is null && key.empty);
        assert(value.allocator is null && value.empty);
    }
    assert(map.length == integrationKeys.length);

    StringBuf replacementKey = StringBuf.from_string(tracked.allocator, "key-03");
    StringBuf replacementValue = StringBuf.from_string(tracked.allocator, "replacement");
    assert(map.try_set(&replacementKey, &replacementValue) == SetStatus.replaced);
    assert(replacementKey.view == "key-03");
    assert(replacementValue.allocator is null && replacementValue.empty);
    StringBuf* storedReplacement = map.find(&replacementKey);
    assert(storedReplacement !is null && *storedReplacement == "replacement");
    deinit(replacementKey);
    deinit(replacementValue);

    StringBuf duplicateKey = StringBuf.from_string(tracked.allocator, "key-04");
    StringBuf duplicateValue = StringBuf.from_string(tracked.allocator, "duplicate");
    assert(map.try_add(&duplicateKey, &duplicateValue) == AddStatus.already_present);
    assert(duplicateKey.view == "key-04" && duplicateValue.view == "duplicate");
    deinit(duplicateKey);
    deinit(duplicateValue);

    StringBuf takeLookup = StringBuf.from_string(tracked.allocator, "key-05");
    StringBuf takenKey = void;
    StringBuf takenValue = void;
    assert(map.take(&takeLookup, &takenKey, &takenValue));
    assert(takenKey == "key-05" && takenValue == "key-05");
    deinit(takeLookup);
    deinit(takenKey);
    deinit(takenValue);

    StringBuf removeLookup = StringBuf.from_string(tracked.allocator, "key-06");
    assert(map.remove(&removeLookup));
    deinit(removeLookup);

    map.clear();
    assert(map.empty);
    deinit(map);
    assert(tracked.clean);

    Map failing = Map.create(tracked.allocator);
    StringBuf retainedKey = StringBuf.from_string(tracked.allocator, "oom-key");
    StringBuf retainedValue = StringBuf.from_string(tracked.allocator, "oom-value");
    tracked.fail_after(0);
    assert(failing.try_add(&retainedKey, &retainedValue) == AddStatus.out_of_memory);
    assert(retainedKey.view == "oom-key" && retainedValue.view == "oom-value");
    assert(failing.empty);
    tracked.allow_allocations();
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
        StringBuf value = StringBuf.from_string(tracked.allocator, text);
        assert(set.try_add(&value) == AddStatus.inserted);
        assert(value.allocator is null && value.empty);
    }
    assert(set.length == integrationKeys.length);

    StringBuf duplicate = StringBuf.from_string(tracked.allocator, "key-04");
    assert(set.try_add(&duplicate) == AddStatus.already_present);
    assert(duplicate.view == "key-04");
    deinit(duplicate);

    StringBuf takeLookup = StringBuf.from_string(tracked.allocator, "key-05");
    StringBuf taken = void;
    assert(set.take(&takeLookup, &taken));
    assert(taken == "key-05");
    deinit(takeLookup);
    deinit(taken);

    StringBuf removeLookup = StringBuf.from_string(tracked.allocator, "key-06");
    assert(set.remove(&removeLookup));
    deinit(removeLookup);

    set.clear();
    assert(set.empty);
    deinit(set);
    assert(tracked.clean);

    Set failing = Set.create(tracked.allocator);
    StringBuf retained = StringBuf.from_string(tracked.allocator, "oom-set-value");
    tracked.fail_after(0);
    assert(failing.try_add(&retained) == AddStatus.out_of_memory);
    assert(retained.view == "oom-set-value");
    assert(failing.empty);
    tracked.allow_allocations();
    deinit(retained);
    deinit(failing);
    assert(tracked.clean);
}

private void testOwnedStringHashMapIntegration(InstrumentedAllocator* tracked)
{
    auto map = OwnedStringHashMap!OwnedString.create(tracked.allocator);
    foreach (text; integrationKeys)
    {
        OwnedString value = OwnedString.from_string(tracked.allocator, text);
        assert(map.try_add(text, &value) == AddStatus.inserted);
        assert(value.allocator is null && value.empty);
    }
    assert(map.length == integrationKeys.length);

    OwnedString replacement = OwnedString.from_string(tracked.allocator, "replacement");
    assert(map.try_set("key-03", &replacement) == SetStatus.replaced);
    assert(replacement.allocator is null && replacement.empty);
    OwnedString* stored = map.find("key-03");
    assert(stored !is null && stored.view == "replacement");

    OwnedString duplicate = OwnedString.from_string(tracked.allocator, "duplicate");
    assert(map.try_add("key-04", &duplicate) == AddStatus.already_present);
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
    OwnedString retained = OwnedString.from_string(tracked.allocator, "oom-value");
    const failedBefore = tracked.stats.failed_calls;
    tracked.fail_after(0);
    assert(failing.try_add("oom-key", &retained) == AddStatus.out_of_memory);
    assert(tracked.stats.failed_calls == failedBefore + 1);
    assert(retained.view == "oom-value");
    assert(failing.empty);
    tracked.allow_allocations();
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
    StringBuf first = StringBuf.from_string(allocator, prefix);
    result.append(move(first));
    StringBuf second = StringBuf.from_string(allocator, "nested-value");
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
        assert(map.try_add(text, &value) == AddStatus.inserted);
        assert(value.empty);
        deinit(value);
    }
    assert(map.length == 16);

    Value replacement = makeStringArray(tracked.allocator, "replacement-array");
    assert(map.try_set("key-03", &replacement) == SetStatus.replaced);
    assert(replacement.empty);
    Value* stored = map.find("key-03");
    assert(stored !is null && stored.length == 2);
    assert((*stored)[0] == "replacement-array");
    deinit(replacement);

    Value duplicate = makeStringArray(tracked.allocator, "duplicate-array");
    assert(map.try_add("key-04", &duplicate) == AddStatus.already_present);
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
    const failedBefore = tracked.stats.failed_calls;
    tracked.fail_after(0);
    assert(failing.try_add("oom-nested-key", &retained) == AddStatus.out_of_memory);
    assert(tracked.stats.failed_calls == failedBefore + 1);
    assert(retained.length == 2 && retained[0] == "oom-array");
    assert(failing.empty);
    tracked.allow_allocations();
    deinit(retained);
    deinit(failing);
    assert(tracked.clean);
}

extern (C) int main()
{
    AllocationRecord[256] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        malloc_allocator(),
        records[],
    );

    testOwnedStringStringBufInputs(&tracked);
    testStringBufMoveReplacement(&tracked);
    testOwnedStringMoveReplacement(&tracked);
    testReleasedStorage(&tracked);
    testConstructionFailure(&tracked);
    testOwnedStringTransforms(&tracked);
    testDirectOwnedStringTransforms(&tracked);
    testStringBufInPlaceTransforms(&tracked);
    testStringBufReplacementOutputs(&tracked);
    testArenaStringTransforms(&tracked);
    testStringBufCopies(&tracked);
    testOptionResultComposition(&tracked);
    testOwnedContainers(&tracked);
    testOwnedArrayIntegration(&tracked);
    testOwnedHashMapStringIntegration(&tracked);
    testOwnedHashSetStringIntegration(&tracked);
    testOwnedStringHashMapIntegration(&tracked);
    testNestedOwnedStringHashMapIntegration(&tracked);

    assert(tracked.clean);
    assert(tracked.stats.outstanding_allocations == 0);
    assert(tracked.stats.outstanding_bytes == 0);
    assert(tracked.stats.invalid_calls == 0);
    return 0;
}
