module xtb.os.posix.terminal;

nothrow @nogc:

import core.stdc.stdio : FILE, fileno;
import core.sys.posix.unistd : isatty;

/// Returns whether `file` refers to a POSIX terminal device.
bool isTerminal(FILE* file) @system
{
    return file !is null && isatty(fileno(file)) == 1;
}

unittest
{
    import core.stdc.stdio : fclose, tmpfile;

    FILE* file = tmpfile();
    assert(file !is null);
    assert(!isTerminal(file));
    assert(fclose(file) == 0);
    assert(!isTerminal(null));
}
