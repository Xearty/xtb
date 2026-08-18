module tests.attribute_namespace_tests;

nothrow @nogc:

import xtb.cli;
import xtb.serde;

struct MixedSchema
{
    @(cliAliasName("colour"), serdeAliasName("colour"))
    bool color;

    @(cliRequired, serdeRequired)
    uint value;
}

static assert(__traits(compiles, cliAliasName("alternate")));
static assert(__traits(compiles, serdeAliasName("alternate")));
static assert(!__traits(compiles, aliasName("legacy")));
static assert(!__traits(compiles, required));

extern (C) int main()
{
    return 0;
}
