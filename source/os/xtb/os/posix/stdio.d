module xtb.os.posix.stdio;

nothrow @nogc:

import core.stdc.stdio : FILE;
import core.sys.posix.stdio : fileno;
import xtb.os.handle : NativeHandle;
import xtb.os.posix.handle : fromFileDescriptor;

/// Returns the native handle backing `file`, or an invalid handle for null.
NativeHandle fileHandle(FILE* file) @system
{
    return file is null ? NativeHandle.init : fromFileDescriptor(fileno(file));
}

unittest
{
    import core.stdc.stdio : fclose, tmpfile;

    assert(!fileHandle(null).valid);

    FILE* file = tmpfile();
    assert(file !is null);
    assert(fileHandle(file).valid);
    assert(fclose(file) == 0);
}
