module xtb.os.internal.unsupported.terminal;

nothrow @nogc:

import core.stdc.stdio : FILE;

package(xtb.os) bool isTerminal(FILE*) @system
{
    return false;
}
