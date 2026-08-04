module app;

import xtb.core;

extern (C) int main() nothrow @nogc
{
    ThreadContextScope context = ThreadContextScope.acquire();
    ScratchScope scratch = ScratchScope.acquire();

    String possession = "codebase";
    
    StringBuf message = formatString!"All your {} are belong to us."(
        scratch.allocator,
        possession,
    );

    writeln(message);

    return 0;
}
