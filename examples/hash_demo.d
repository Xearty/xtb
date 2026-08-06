module examples.hash_demo;

import xtb.core;

static assert(is(StringViewHashMap!int == HashMap!(String, int)));

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

    HashSet!String labels = HashSet!String.create(mallocAllocator());
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
    StringBuf generated = StringBuf.fromString(mallocAllocator(), "generated");
    int generatedValue = 2;
    assert(owned.addMove(&generated, &generatedValue));
    assert(generated.allocator is null && generated.empty);
    assert(*owned.find("generated") == 2);

    assert(labels.contains("fresh"));
    return 0;
}
