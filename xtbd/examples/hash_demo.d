module examples.hash_demo;

import xtb.core;

extern (C) int main() nothrow @nogc
{
    HashMap!(String, int) inventory = HashMap!(String, int).seeded(
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
    for (auto item = inventory.cursor(); item.valid; item.advance())
        formatln!"  {}: {}"(*item.key, *item.value);

    HashSet!String labels = HashSet!String.create(mallocAllocator());
    labels.add("fresh");
    labels.add("local");
    labels.add("fresh");
    formatln!"unique labels: {}"(labels.length);

    // String keys are borrowed views. These literals live for the program's
    // duration; dynamic key bytes must likewise outlive their table entry.
    assert(inventory.contains("oranges"));
    assert(labels.contains("fresh"));
    return 0;
}
