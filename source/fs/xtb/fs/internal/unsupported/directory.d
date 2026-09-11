module xtb.fs.internal.unsupported.directory;

nothrow @nogc:

import xtb.fs.internal.directory;
import xtb.os.error;
import xtb.string;
import xtb.types;

package(xtb.fs) bool directory_valid(scope const(void)*) pure @safe
{
    return false;
}

package(xtb.fs) OsError close_directory(scope void** directory) pure @safe
{
    *directory = null;
    return OsError.init;
}

package(xtb.fs) OsError open_directory(scope String, scope void**) pure @safe
{
    return unsupported();
}

package(xtb.fs) NativeDirectoryResult next_directory(
    scope void*,
    scope NativeDirectoryEntry*,
) pure @safe
{
    return NativeDirectoryResult(NativeDirectoryStatus.failed, unsupported());
}

package(xtb.fs) OsError create_directory(scope String, u32) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError remove_empty_directory(scope String) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError remove_file(scope String) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError rename_path(scope String, scope String) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError current_directory(scope StringBuf*) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError executable_path(scope StringBuf*) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError query_access(scope String, u8, scope bool*) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError canonical_path(scope String, scope StringBuf*) pure @safe
{
    return unsupported();
}
