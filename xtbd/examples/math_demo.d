module examples.math_demo;

import xtb.core;
import xtb.math;

extern (C) int main() nothrow @nogc
{
    const model = translation(Vector3(3, 1, -2)) * rotation(Vector3(0, 1, 0),
            radians(30)) * scaling(Vector3(2, 2, 2));
    const point = model * Vector4(1, 0, 0, 1);
    formatln!"transformed point: ({}, {}, {})"(fixed(point.x, 3),
            fixed(point.y, 3), fixed(point.z, 3));

    ValueNoise1D noise = ValueNoise1D.create(mallocAllocator(), 16, 0xC0FFEE);
    foreach (index; 0 .. 8)
    {
        const position = cast(float) index * 0.5f;
        formatln!"noise({}) = {}"(fixed(position, 1), fixed(noise.sample(position), 4));
    }
    return 0;
}
