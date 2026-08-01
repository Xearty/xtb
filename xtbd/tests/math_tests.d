module tests.math_tests;

import xtb.math.matrix;
import xtb.math.random;
import xtb.math.noise;
import xtb.math.scalar;
import xtb.math.vector;

private bool cStringEqual(const(char)* left, const(char)* right)
nothrow @system @nogc
{
    if (left is null || right is null)
        return left is right;
    size_t index;
    while (left[index] != '\0' && right[index] != '\0')
    {
        if (left[index] != right[index])
            return false;
        ++index;
    }
    return left[index] == right[index];
}

extern (C) int main(int argc, char** argv)
{
    if (argc == 2 && cStringEqual(argv[1], "--panic-random-bound"))
    {
        Random random = Random.seeded(1);
        random.below(0);
        return 2;
    }
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
