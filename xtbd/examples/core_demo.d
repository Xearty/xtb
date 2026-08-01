module examples.core_demo;

import xtb.core;

extern (C) int main() nothrow @nogc
{
    ThreadContextScope context = ThreadContextScope.acquire();
    ScratchScope scratch = ScratchScope.acquire();

    Array!int numbers = Array!int.create(scratch.allocator);
    foreach (number; 1 .. 6)
        numbers.append(number);

    StringBuf message = StringBuf.create(scratch.allocator);
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

    char[128] logStorage;
    Logger logger = stderrLogger(logStorage[], LogLevel.info);
    logger.logf!"processed {} values"(LogLevel.info, numbers.length);
    return 0;
}
