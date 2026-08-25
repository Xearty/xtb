module xtb.os.internal.posix.environment;

nothrow @nogc:

import core.stdc.stdlib : getenv;
import xtb.core.string : fromCString;
import xtb.core.types : String;
import xtb.os.error : OsError, OsErrorKind;

package(xtb.os) const(char)* rawEnvironmentVariableImpl(const(char)* name) @system
{
    return getenv(name);
}

package(xtb.os) OsError environmentVariableCStringImpl(
    const(char)* name,
    String* output,
) @system
{
    const value = rawEnvironmentVariableImpl(name);
    if (value is null)
        return OsError(OsErrorKind.notFound, 0);
    const checked = fromCString(value);
    if (checked.failed)
        return OsError(OsErrorKind.invalidData, 0);
    *output = checked.value;
    return OsError.init;
}
