module examples.core_demo;

import xtb.core;

extern(C) int main() nothrow @nogc
{
    ThreadContextScope context = ThreadContextScope.acquire();
    ScratchScope scratch = ScratchScope.acquire();

    Array!int numbers = Array!int.init(scratch.allocator);
    foreach (number; 1 .. 6)
        numbers.append(number);

    StringBuf message = StringBuf.init(scratch.allocator);
    message.formatTo!"{} {}"("core values:", numbers.length);
    writeln(message.view);

    StringBuf path = StringBuf.fromString(scratch.allocator, "assets");
    path.append('/');
    path.append("image.bmp");
    formatln!"path={}, first={}, last={}"(
        path.view,
        numbers[0],
        numbers[numbers.length - 1],
    );
    return 0;
}
