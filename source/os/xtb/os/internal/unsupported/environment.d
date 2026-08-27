module xtb.os.internal.unsupported.environment;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;

package(xtb.os) OsError environmentVariableImpl(
    const(char)*,
    const(char)**,
) pure @safe
{
    return unsupported();
}
