module xtb.os.environment;

nothrow @nogc:

import xtb.core.panic : require;
import xtb.core.string : String, StringBuf, checkedCString, fromCString;
import xtb.core.thread_context : ScratchScope;
import xtb.os.error : OsError, OsErrorKind, unsupported;
import xtb.os.path : Path;

/// Returns a process-owned view, potentially invalidated by environment changes.
OsError environmentVariable(String name, String* output) @system
{
    require(output !is null, "environment output pointer is null");
    *output = null;
    Path key;
    if (!Path.tryFromString(name, &key))
        return OsError(OsErrorKind.invalidArgument, 0);
    version (linux)
    {
        import core.stdc.stdlib : getenv;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, key.view);
        const value = getenv(native.checkedCString);
        if (value is null)
            return OsError(OsErrorKind.notFound, 0);
        *output = fromCString(value);
        return OsError.init;
    }
    else
        return unsupported();
}
