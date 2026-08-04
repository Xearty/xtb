module app;

import xtb.core;

extern (C) int main() nothrow @nogc
{
    ThreadContextScope context = ThreadContextScope.acquire();
    ScratchScope scratch = ScratchScope.acquire();

    StringBuf message = StringBuf.fromString(scratch.allocator, "hello");
    message.append(" from an xtb application");
    writeln(message.view);

    return 0;
}
