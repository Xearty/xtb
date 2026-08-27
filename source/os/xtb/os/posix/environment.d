module xtb.os.posix.environment;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import core.stdc.stdlib : getenv;
import xtb.os.error : OsError, OsErrorKind;

/// Looks up a process-environment entry using a permanent native C string.
///
/// The returned pointer is borrowed from the process environment and may be
/// invalidated by a later environment mutation.
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

    const value = getenv(name);
    if (value is null)
        return OsError(OsErrorKind.notFound, 0);
    *output = value;
    return OsError.init;
}
