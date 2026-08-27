module xtb.os.environment;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.os.error : OsError, OsErrorKind;

version (Posix)
    private import backend = xtb.os.internal.posix.environment;
else
    private import backend = xtb.os.internal.unsupported.environment;

/// Looks up a process-environment entry using a permanent native C string.
///
/// The returned pointer is borrowed from the process environment and may be
/// invalidated by a later environment mutation. This is a low-level mechanism;
/// validation of domain-specific environment names belongs to callers.
OsError environmentVariable(
    const(char)* name,
    const(char)** output,
) @system
{
    version (XTB_Checked)
        require(output !is null, "environment output pointer is null");
    *output = null;
    if (name is null || name[0] == '\0')
        return OsError(OsErrorKind.invalidArgument, 0);
    return backend.environmentVariableImpl(name, output);
}
