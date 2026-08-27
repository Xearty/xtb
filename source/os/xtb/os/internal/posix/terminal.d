module xtb.os.internal.posix.terminal;

nothrow @nogc:

import core.stdc.stdio : FILE, fileno;
import core.sys.posix.unistd : isatty;

package(xtb.os) bool isTerminal(FILE* file) @system
{
    return isatty(fileno(file)) == 1;
}
