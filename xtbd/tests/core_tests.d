module tests.core_tests;

import xtb.core.types;
import xtb.core.memory;
import xtb.core.arena;
import xtb.core.thread_context;
import xtb.core.array;
import xtb.core.list;
import xtb.core.logger;
import xtb.core.string;
import xtb.core.print;

extern(C) int main()
{
    static foreach (testFunction; __traits(getUnitTests, xtb.core.types))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.memory))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.arena))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.thread_context))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.array))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.list))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.logger))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.string))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.print))
        testFunction();
    return 0;
}
