module xtb.fs.internal.unsupported.directory;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.string : String, StringBuf;
import xtb.fs.internal.directory : NativeDirectoryEntry, NativeDirectoryResult,
    NativeDirectoryStatus;

package(xtb.fs) bool directoryValid(const(void)*) pure @safe
{
    return false;
}

package(xtb.fs) OsError closeDirectory(void** directory) pure @safe
{
    *directory = null;
    return OsError.init;
}

package(xtb.fs) OsError openDirectory(String, void**) pure @safe
{
    return unsupported();
}

package(xtb.fs) NativeDirectoryResult nextDirectory(
    void*,
    NativeDirectoryEntry*,
) pure @safe
{
    return NativeDirectoryResult(NativeDirectoryStatus.failed, unsupported());
}

package(xtb.fs) OsError createDirectory(String, uint) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError removeEmptyDirectory(String) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError removeFile(String) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError renamePath(String, String) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError currentDirectory(ref StringBuf) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError executablePath(ref StringBuf) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError queryAccess(String, ubyte, bool*) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError canonicalPath(String, ref StringBuf) pure @safe
{
    return unsupported();
}
