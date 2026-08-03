module xtb.os.terminal;

nothrow @nogc:

import core.stdc.stdio : FILE, fileno;
import core.stdc.string : strcmp;
import xtb.core.ansi : AnsiMode;
import xtb.os.environment : rawEnvironmentVariable;

private bool environmentAllowsAnsi(
    const(char)* noColor,
    const(char)* term,
) @system
{
    if (noColor !is null && noColor[0] != '\0')
        return false;
    return term is null || strcmp(term, "dumb".ptr) != 0;
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

    version (Posix)
    {
        import core.sys.posix.unistd : isatty;

        if (isatty(fileno(file)) != 1)
            return false;

        return environmentAllowsAnsi(
            rawEnvironmentVariable("NO_COLOR".ptr),
            rawEnvironmentVariable("TERM".ptr),
        );
    }
    else
        return false;
}

unittest
{
    import core.stdc.stdio : fclose, tmpfile;

    assert(environmentAllowsAnsi(null, null));
    assert(environmentAllowsAnsi("".ptr, "xterm-256color".ptr));
    assert(!environmentAllowsAnsi("1".ptr, "xterm-256color".ptr));
    assert(!environmentAllowsAnsi(null, "dumb".ptr));

    FILE* file = tmpfile();
    assert(file !is null);
    assert(!shouldUseAnsi(file, AnsiMode.never));
    assert(shouldUseAnsi(file, AnsiMode.always));
    assert(!shouldUseAnsi(file, AnsiMode.automatic));
    assert(fclose(file) == 0);
    assert(!shouldUseAnsi(null, AnsiMode.always));
}
