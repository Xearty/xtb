module xtb.os.environment;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.string;
import xtb.thread_context : ScratchScope;
import xtb.os.error : OsError, OsErrorKind;

version (Posix)
    private import backend = xtb.os.internal.posix.environment;
else
    private import backend = xtb.os.internal.unsupported.environment;

private bool validEnvironmentName(String name) pure @safe
{
    if (name.length == 0)
        return false;
    foreach (character; name)
        if (character == '\0' || character == '=')
            return false;
    return true;
}

/// Internal allocation-free boundary for callers with a permanent C string.
package const(char)* rawEnvironmentVariable(const(char)* name) @system
{
    if (name is null || name[0] == '\0')
        return null;
    return backend.rawEnvironmentVariableImpl(name);
}

private OsError environmentVariableCString(
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

/// Returns a process-owned view, potentially invalidated by environment changes.
OsError environmentVariable(String name, String* output) @system
{
    version (XTB_Checked)
        require(output !is null, "environment output pointer is null");
    *output = null;
    if (!validEnvironmentName(name))
        return OsError(OsErrorKind.invalidArgument, 0);
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native = StringBuf.fromString(scratch.allocator, name);
    return environmentVariableCString(native.checkedCString, output);
}

unittest
{
    String output = "unchanged";
    assert(environmentVariable("", &output).kind == OsErrorKind.invalidArgument);
    assert(output is null);
    assert(environmentVariable("A=B", &output).kind ==
            OsErrorKind.invalidArgument);
    assert(environmentVariable("A\0B", &output).kind ==
            OsErrorKind.invalidArgument);
}
