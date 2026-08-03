module xtb.os.environment;

nothrow @nogc:

import xtb.core.panic : require;
import xtb.core.string : String, StringBuf, cString, fromCString;
import xtb.core.thread_context : ScratchScope;
import xtb.os.error : OsError, OsErrorKind, unsupported;

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

    version (Posix)
    {
        import core.stdc.stdlib : getenv;

        return getenv(name);
    }
    else
        return null;
}

private OsError environmentVariableCString(
    const(char)* name,
    String* output,
) @system
{
    require(output !is null, "environment output pointer is null");
    *output = null;
    if (name is null || name[0] == '\0')
        return OsError(OsErrorKind.invalidArgument, 0);

    version (Posix)
    {
        const value = rawEnvironmentVariable(name);
        if (value is null)
            return OsError(OsErrorKind.notFound, 0);
        const checked = fromCString(value);
        if (checked.failed)
            return OsError(OsErrorKind.invalidData, 0);
        *output = checked.value;
        return OsError.init;
    }
    else
        return unsupported();
}

/// Returns a process-owned view, potentially invalidated by environment changes.
OsError environmentVariable(String name, String* output) @system
{
    require(output !is null, "environment output pointer is null");
    *output = null;
    if (!validEnvironmentName(name))
        return OsError(OsErrorKind.invalidArgument, 0);
    version (Posix)
    {
        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, name);
        return environmentVariableCString(native.cString, output);
    }
    else
        return unsupported();
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
