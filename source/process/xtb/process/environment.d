module xtb.process.environment;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.string;
import xtb.thread_context : ScratchScope;
import xtb.os.error : OsError, OsErrorKind, unsupported;

version (Posix)
    private import xtb.os.posix.environment : osEnvironmentVariable = environmentVariable;
else
    private OsError osEnvironmentVariable(
        const(char)*,
        const(char)** output,
    ) pure @safe
{
    if (output !is null)
        *output = null;
    return unsupported();
}

private bool validEnvironmentName(String name) pure @safe
{
    if (name.length == 0)
        return false;
    foreach (character; name)
        if (character == '\0' || character == '=')
            return false;
    return true;
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
    const(char)* value;
    const error = osEnvironmentVariable(native.checkedCString, &value);
    if (error.failed)
        return error;
    const checked = fromCString(value);
    if (checked.failed)
        return OsError(OsErrorKind.invalidData, 0);
    *output = checked.value;
    return OsError.init;
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
