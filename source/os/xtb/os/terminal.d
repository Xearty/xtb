module xtb.os.terminal;

nothrow @nogc:

import core.stdc.stdio : FILE;

version (Posix)
    private import backend = xtb.os.internal.posix.terminal;
else
    private import backend = xtb.os.internal.unsupported.terminal;

/// User policy for OS-aware ANSI capability selection.
enum AnsiMode : ubyte
{
    automatic,
    always,
    never,
}

/**
 * Resolves whether ANSI styling should be used for `file`.
 *
 * Automatic mode is conservative: on POSIX it requires a terminal file
 * descriptor, rejects `TERM=dumb`, and honors a non-empty `NO_COLOR` value.
 * Platforms without a locally implemented detector return `false`. `always`
 * and `never` are explicit application overrides.
 */
bool shouldUseAnsi(FILE* file, AnsiMode mode = AnsiMode.automatic) @system
{
    if (file is null || mode == AnsiMode.never)
        return false;
    if (mode == AnsiMode.always)
        return true;

    return backend.terminalSupportsAnsi(file);
}

unittest
{
    import core.stdc.stdio : fclose, tmpfile;

    FILE* file = tmpfile();
    assert(file !is null);
    assert(!shouldUseAnsi(file, AnsiMode.never));
    assert(shouldUseAnsi(file, AnsiMode.always));
    assert(!shouldUseAnsi(file, AnsiMode.automatic));
    assert(fclose(file) == 0);
    assert(!shouldUseAnsi(null, AnsiMode.always));
}
