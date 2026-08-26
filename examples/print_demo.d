module examples.print_demo;

import xtb.fmt.print;
import xtb.fmt.fixed_buffer;
import xtb.fmt.format;
import xtb.allocators.malloc : mallocAllocator;
import xtb.string;

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

extern (C) int main() nothrow @nogc
{
    writeln("hello from BetterC");
    formatln!"integer={}, hex={}, ratio={}"(
        42,
        hexadecimal(0xBEEF).digits(8),
        fixed(1.0 / 3.0, 4),
    );
    writeln("custom value: ", Point(12, -7));

    String name = "interpolation";
    int count = 3;
    writeln(i"native $(name): count=$(count), point=$(Point(4, 9))");
    formatln(i"wrappers stay explicit: hex=$(hexadecimal(48879).upper()), ratio=$(fixed(1.0 / 3.0, 3))");
    writeln(i"nested sequences: [$(i"$(name):$(count)")]");

    StringBuf text = formatString(
        mallocAllocator(),
        i"owned output: $(name) has $(count) values",
    );
    writeln(text);

    StringBuf builder = StringBuf.create(mallocAllocator());
    builder.format(i"builder output: $(Point(-2, 8))");
    writeln(builder);

    char[24] storage;
    const fixedResult = storage[].formatBuffer(i"fixed output: $(count)");
    writeln(
        "fixed buffer: ",
        storage[0 .. fixedResult.written],
        ", required=",
        fixedResult.required,
        ", truncated=",
        fixedResult.truncated,
    );

    builder.deinit();
    text.deinit();
    return 0;
}
