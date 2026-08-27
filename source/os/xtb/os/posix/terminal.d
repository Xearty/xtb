module xtb.os.posix.terminal;

nothrow @nogc:

import core.sys.posix.unistd : isatty;
import xtb.os.handle : NativeHandle;
import xtb.os.posix.handle : fileDescriptor;

/// Returns whether `handle` refers to a POSIX terminal device.
bool isTerminal(NativeHandle handle) @system
{
    const descriptor = fileDescriptor(handle);
    return descriptor >= 0 && isatty(descriptor) == 1;
}

unittest
{
    import core.stdc.stdio : FILE, fclose, tmpfile;
    import xtb.os.posix.stdio : fileHandle;

    assert(!isTerminal(NativeHandle.init));

    FILE* file = tmpfile();
    assert(file !is null);
    assert(!isTerminal(fileHandle(file)));
    assert(fclose(file) == 0);
}
