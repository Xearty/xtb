module xtb.os.internal.environment;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.types : String;
import xtb.os.error : OsError, OsErrorKind;

version (Posix)
    private import backend = xtb.os.internal.posix.environment;
else
    private import backend = xtb.os.internal.unsupported.environment;

/// Internal allocation-free boundary for XTB domains with a permanent C string.
package(xtb) const(char)* rawEnvironmentVariable(const(char)* name) @system
{
    if (name is null || name[0] == '\0')
        return null;
    return backend.rawEnvironmentVariableImpl(name);
}

/// Internal native-string environment lookup used by process-domain wrappers.
package(xtb) OsError environmentVariableCString(
    const(char)* name,
    String* output,
) @system
{
    version (XTB_Checked)
        require(output !is null, "environment output pointer is null");
    *output = null;
    if (name is null || name[0] == '\0')
        return OsError(OsErrorKind.invalidArgument, 0);
    return backend.environmentVariableCStringImpl(name, output);
}
