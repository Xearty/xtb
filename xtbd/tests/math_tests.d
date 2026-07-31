module tests.math_tests;

import xtb.math.matrix;
import xtb.math.random;
import xtb.math.noise;
import xtb.math.scalar;
import xtb.math.vector;

extern (C) int main()
{
    static foreach (testFunction; __traits(getUnitTests, xtb.math.scalar))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.math.vector))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.math.matrix))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.math.random))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.math.noise))
        testFunction();
    return 0;
}
