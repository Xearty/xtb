module xtb.os.internal.unsupported.environment;

nothrow @nogc:

import xtb.core.types : String;
import xtb.os.error : OsError, unsupported;

package(xtb.os) const(char)* rawEnvironmentVariableImpl(const(char)*) @system
{
    return null;
}

package(xtb.os) OsError environmentVariableCStringImpl(const(char)*, String*) @system
{
    return unsupported();
}
