module xtb.terminal;

nothrow @nogc:

import core.stdc.stdio : FILE;
import core.stdc.string : strcmp;
import xtb.os.environment : osEnvironmentVariable = environmentVariable;
import xtb.os.terminal : isTerminal;

/// User policy for ANSI presentation selection.
enum AnsiMode : ubyte
{
    automatic,
    always,
    never,
}

private bool automaticAnsiAllowed(
    bool terminal,
    const(char)* noColor,
    const(char)* forceColor,
    const(char)* term,
) @system
{
    if (noColor !is null && noColor[0] != '\0')
        return false;
    if (forceColor !is null && forceColor[0] != '\0')
        return true;
    if (!terminal)
        return false;
    return term is null || strcmp(term, "dumb".ptr) != 0;
}

private const(char)* environmentValue(const(char)* name) @system
{
    const(char)* value;
    return osEnvironmentVariable(name, &value).succeeded ? value : null;
}

/**
 * Resolves whether ANSI styling should be used for `file`.
 *
 * Automatic mode honors a non-empty `NO_COLOR` first, then a non-empty
 * `CLICOLOR_FORCE`, and otherwise requires a terminal that is not advertised
 * as `TERM=dumb`. `always` and `never` are explicit application overrides.
 */
bool shouldUseAnsi(FILE* file, AnsiMode mode = AnsiMode.automatic) @system
{
    if (file is null || mode == AnsiMode.never)
        return false;
    if (mode == AnsiMode.always)
        return true;

    return automaticAnsiAllowed(
        isTerminal(file),
        environmentValue("NO_COLOR".ptr),
        environmentValue("CLICOLOR_FORCE".ptr),
        environmentValue("TERM".ptr),
    );
}

unittest
{
    import core.stdc.stdio : fclose, tmpfile;

    assert(automaticAnsiAllowed(true, null, null, null));
    assert(automaticAnsiAllowed(true, null, null, "xterm-256color".ptr));
    assert(!automaticAnsiAllowed(true, null, null, "dumb".ptr));
    assert(!automaticAnsiAllowed(false, null, null, null));
    assert(automaticAnsiAllowed(false, null, "1".ptr, "dumb".ptr));
    assert(!automaticAnsiAllowed(true, "1".ptr, "1".ptr, null));

    FILE* file = tmpfile();
    assert(file !is null);
    assert(!shouldUseAnsi(file, AnsiMode.never));
    assert(shouldUseAnsi(file, AnsiMode.always));
    assert(fclose(file) == 0);
    assert(!shouldUseAnsi(null, AnsiMode.always));
}
