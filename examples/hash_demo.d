module examples.hash_demo;

import xtb;

static assert(is(StringViewHashMap!int == HashMap!(String, int)));
static assert(is(StringViewHashSet == HashSet!String));

extern (C) int main() nothrow @nogc
{
    StringViewHashMap!int inventory = StringViewHashMap!int.seeded(
        mallocAllocator(),
        HashSeed.fromValue(0x7862_7464),
    );
    inventory.set("apples", 12);
    inventory.set("pears", 7);
    inventory.set("oranges", 9);

    if (int* apples = inventory.find("apples"))
        *apples += 3;
    inventory.set("pears", 8);

    formatln!"inventory ({} kinds):"(inventory.length);
    foreach (ref const name, ref count; inventory)
        formatln!"  {}: {}"(name, count);

    StringViewHashSet labels = StringViewHashSet.create(mallocAllocator());
    labels.add("fresh");
    labels.add("local");
    labels.add("fresh");
    formatln!"unique labels: {}"(labels.length);
    foreach (ref const label; labels)
        formatln!"  {}"(label);

    // Choose pointer-oriented foreach when pointer access is more convenient.
    foreach (item; inventory.pointerItems)
        assert(item.key !is null && item.value !is null);

    // StringViewHashMap keys are borrowed. These literals live for the
    // program's duration; dynamic key bytes must likewise outlive their entry.
    assert(inventory.contains("oranges"));

    // StringHashMap copies borrowed keys and can also consume an existing
    // owner. Lookups still accept allocation-free String views.
    StringHashMap!int owned = StringHashMap!int.create(mallocAllocator());
    owned.set("literal", 1);
    StringBuf movedKey = StringBuf.fromString(mallocAllocator(), "moved");
    int movedValue = 2;
    assert(owned.addMove(&movedKey, &movedValue));
    assert(movedKey.allocator is null && movedKey.empty);
    assert(*owned.find("moved") == 2);

    StringHashSet ownedLabels = StringHashSet.create(mallocAllocator());
    ownedLabels.add("persistent");
    StringBuf movedLabel = StringBuf.fromString(
        mallocAllocator(),
        "moved-label",
    );
    assert((&ownedLabels).addMove(&movedLabel));
    assert(movedLabel.allocator is null && movedLabel.empty);
    assert(ownedLabels.contains("moved-label"));

    assert(labels.contains("fresh"));

    ownedLabels.deinit();
    owned.deinit();
    labels.deinit();
    inventory.deinit();
    return 0;
}
