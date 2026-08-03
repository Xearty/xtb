module fuzz.serde_fuzz;

import xtb.core.memory : mallocAllocator;
import xtb.core.types : String;
import xtb.serde.attributes : KeyCase, fieldCase;
import xtb.serde.error : SerdeLimits;
import xtb.serde.json : JsonReadOptions, readJson;
import xtb.serde.ownership : Deserialized;
import xtb.serde.toml : TomlReadOptions, readToml;

private struct FuzzChild
{
    String text;
    long number;
}

@fieldCase(KeyCase.snake)
private struct FuzzDocument
{
    String name;
    FuzzChild child;
    FuzzChild[] children;
    bool enabled;
    double ratio;
}

extern (C) int LLVMFuzzerTestOneInput(const ubyte* data, size_t size)
nothrow @nogc
{
    String input = size == 0 ? null : cast(String) data[0 .. size];
    SerdeLimits limits;
    limits.maxDepth = 16;
    limits.maxCollectionLength = 1024;
    limits.ignoreUnknownFields = true;

    JsonReadOptions jsonOptions;
    jsonOptions.limits = limits;
    Deserialized!FuzzDocument json;
    readJson(input, mallocAllocator(), &json, jsonOptions);

    TomlReadOptions tomlOptions;
    tomlOptions.limits = limits;
    Deserialized!FuzzDocument toml;
    readToml(input, mallocAllocator(), &toml, tomlOptions);
    return 0;
}
