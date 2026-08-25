module xtb.os.internal.posix.terminal;

nothrow @nogc:

import core.stdc.stdio : FILE, fileno;
import core.stdc.string : strcmp;
import core.sys.posix.unistd : isatty;
import xtb.os.environment : rawEnvironmentVariable;

private bool environmentAllowsAnsi(const(char)* noColor, const(char)* term) @system
{
    if (noColor !is null && noColor[0] != '\0')
        return false;
    return term is null || strcmp(term, "dumb".ptr) != 0;
}

package(xtb.os) bool terminalSupportsAnsi(FILE* file) @system
{
    if (isatty(fileno(file)) != 1)
        return false;
    return environmentAllowsAnsi(
        rawEnvironmentVariable("NO_COLOR".ptr),
        rawEnvironmentVariable("TERM".ptr),
    );
}

unittest
{
    assert(environmentAllowsAnsi(null, null));
    assert(environmentAllowsAnsi("".ptr, "xterm-256color".ptr));
    assert(!environmentAllowsAnsi("1".ptr, "xterm-256color".ptr));
    assert(!environmentAllowsAnsi(null, "dumb".ptr));
}
