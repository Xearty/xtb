module tests.pretty_print_tests;

import xtb.core.pretty_print;

extern (C) int main()
{
    static foreach (testFunction; __traits(getUnitTests, xtb.core.pretty_print))
        testFunction();
    return 0;
}
