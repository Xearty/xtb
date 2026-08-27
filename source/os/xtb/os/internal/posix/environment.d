module xtb.os.internal.posix.environment;

nothrow @nogc:

import core.stdc.stdlib : getenv;
import xtb.os.error : OsError, OsErrorKind;

package(xtb.os) OsError environmentVariableImpl(
    const(char)* name,
    const(char)** output,
) @system
{
    const value = getenv(name);
    if (value is null)
        return OsError(OsErrorKind.notFound, 0);
    *output = value;
    return OsError.init;
}
