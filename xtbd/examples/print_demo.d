module examples.print_demo;

import xtb.core.print;

struct Point
{
    int x;
    int y;

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writer.put("Point(");
        writer.value(x);
        writer.put(", ");
        writer.value(y);
        writer.put(')');
    }
}

extern(C) int main() nothrow @nogc
{
    writeln("hello from BetterC");
    formatln!"integer={}, hex={}, ratio={}"(
        42,
        hexadecimal(0xBEEF).digits(8),
        fixed(1.0 / 3.0, 4),
    );
    writeln("custom value: ", Point(12, -7));
    return 0;
}
