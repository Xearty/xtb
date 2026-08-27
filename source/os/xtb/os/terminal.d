module xtb.os.terminal;

nothrow @nogc:

import core.stdc.stdio : FILE;

version (Posix)
    private import backend = xtb.os.internal.posix.terminal;
else
    private import backend = xtb.os.internal.unsupported.terminal;

/// Returns whether `file` refers to a native terminal device.
///
/// This is a low-level capability query only. Environment-based color policy
/// belongs to the terminal domain above the OS boundary.
bool isTerminal(FILE* file) @system
{
    return file !is null && backend.isTerminal(file);
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
