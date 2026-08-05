module tests.pretty_print_serde_tests;

import xtb.serde.ownership;

extern (C) int main()
{
    static foreach (testFunction;
        __traits(getUnitTests, xtb.serde.ownership))
        testFunction();
    return 0;
}
