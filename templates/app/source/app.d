module app;

import greeting : greetingSubject;
import xtb;

extern (C) int main() nothrow @nogc
{
    ThreadContextScope context = ThreadContextScope.acquire();
    ScratchScope scratch = ScratchScope.acquire();

    StringBuf message = StringBuf.create(scratch.allocator);
    message.format!"All your {} are belong to us."(greetingSubject);

    writeln(message);

    return 0;
}
