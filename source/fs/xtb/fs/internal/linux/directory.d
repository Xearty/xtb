module xtb.fs.internal.linux.directory;

nothrow @nogc:

import core.stdc.errno : errno;
import core.stdc.stdlib : free;
import core.stdc.stdio : nativeRename = rename;
import core.sys.posix.dirent : DIR, DT_BLK, DT_CHR, DT_DIR, DT_FIFO, DT_LNK,
    DT_REG, DT_SOCK, closedir, opendir, readdir;
import core.sys.posix.stdlib : realpath;
import core.sys.posix.sys.stat : mkdir;
import core.sys.posix.unistd : F_OK, R_OK, W_OK, X_OK, access, getcwd,
    readlink, rmdir, unlink;
import xtb.containers.array : Array;
import xtb.os.error : OsError, OsErrorKind, lastError;
import xtb.string;
import xtb.thread_context : ScratchScope;
import xtb.types : u8;
import xtb.fs.internal.directory : NativeDirectoryEntry, NativeDirectoryResult,
    NativeDirectoryStatus;
import xtb.fs.internal.file : NativeFileType;

package(xtb.fs) bool directoryValid(const(void)* directory) pure @safe
{
    return directory !is null;
}

package(xtb.fs) OsError closeDirectory(void** directory) @system
{
    if (*directory is null)
        return OsError.init;
    auto native = cast(DIR*)*directory;
    *directory = null;
    return closedir(native) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError openDirectory(String path, void** output) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native = StringBuf.fromString(scratch.allocator, path);
    *output = opendir(native.checkedCString);
    return *output is null ? lastError() : OsError.init;
}

package(xtb.fs) NativeDirectoryResult nextDirectory(
    void* directory,
    NativeDirectoryEntry* output,
) @system
{
    *output = NativeDirectoryEntry.init;
    for (;;)
    {
        errno = 0;
        const native = readdir(cast(DIR*) directory);
        if (native is null)
            return errno == 0
                ? NativeDirectoryResult(NativeDirectoryStatus.finished, OsError.init)
                : NativeDirectoryResult(NativeDirectoryStatus.failed, lastError());
        const checked = fromCString(native.d_name.ptr);
        if (checked.failed)
            return NativeDirectoryResult(
                NativeDirectoryStatus.failed,
                OsError(OsErrorKind.invalidData, 0),
            );
        const name = checked.value;
        if (name == "." || name == "..")
            continue;
        output.name = name;
        output.type = fromDirectoryType(native.d_type);
        return NativeDirectoryResult(NativeDirectoryStatus.entry, OsError.init);
    }
}

private NativeFileType fromDirectoryType(ubyte value) pure @safe
{
    switch (value)
    {
        case DT_REG:
            return NativeFileType.regular;
        case DT_DIR:
            return NativeFileType.directory;
        case DT_LNK:
            return NativeFileType.symbolicLink;
        case DT_CHR:
            return NativeFileType.characterDevice;
        case DT_BLK:
            return NativeFileType.blockDevice;
        case DT_FIFO:
            return NativeFileType.fifo;
        case DT_SOCK:
            return NativeFileType.socket;
        default:
            return NativeFileType.unknown;
    }
}

package(xtb.fs) OsError createDirectory(String path, uint permissions) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native = StringBuf.fromString(scratch.allocator, path);
    return mkdir(native.checkedCString, permissions) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError removeEmptyDirectory(String path) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native = StringBuf.fromString(scratch.allocator, path);
    return rmdir(native.checkedCString) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError removeFile(String path) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native = StringBuf.fromString(scratch.allocator, path);
    return unlink(native.checkedCString) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError renamePath(String source, String destination) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf from = StringBuf.fromString(scratch.allocator, source);
    StringBuf to = StringBuf.fromString(scratch.allocator, destination);
    return nativeRename(from.checkedCString, to.checkedCString) == 0
        ? OsError.init : lastError();
}

package(xtb.fs) OsError currentDirectory(ref StringBuf output) @system
{
    char* buffer = getcwd(null, 0);
    if (buffer is null)
        return lastError();
    const checked = fromCString(buffer);
    if (checked.failed)
    {
        free(buffer);
        return OsError(OsErrorKind.invalidData, 0);
    }
    output.append(checked.value);
    free(buffer);
    return OsError.init;
}

package(xtb.fs) OsError executablePath(ref StringBuf output) @system
{
    ScratchScope scratch = ScratchScope.acquire(output.allocator);
    Array!char buffer = Array!char.withLength(scratch.allocator, 256);
    for (;;)
    {
        const amount = readlink("/proc/self/exe".ptr, buffer.slice.ptr, buffer.length);
        if (amount < 0)
            return lastError();
        if (cast(size_t) amount < buffer.length)
        {
            const checked = (cast(const(u8)[])
                buffer.slice[0 .. cast(size_t) amount]).asString;
            if (checked.failed)
                return OsError(OsErrorKind.invalidData, 0);
            output.append(checked.value);
            return OsError.init;
        }
        if (buffer.length > size_t.max / 2)
            return OsError(OsErrorKind.system, 0);
        buffer.resize(buffer.length * 2);
    }
}

package(xtb.fs) OsError queryAccess(
    String path,
    ubyte requested,
    bool* output,
) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native = StringBuf.fromString(scratch.allocator, path);
    int mode;
    switch (requested)
    {
        case 0:
            mode = F_OK;
            break;
        case 1:
            mode = R_OK;
            break;
        case 2:
            mode = W_OK;
            break;
        case 3:
            mode = X_OK;
            break;
        default:
            return OsError(OsErrorKind.invalidArgument, 0);
    }
    if (access(native.checkedCString, mode) == 0)
    {
        *output = true;
        return OsError.init;
    }
    const error = lastError();
    if (error.kind == OsErrorKind.notFound || error.kind == OsErrorKind.permissionDenied)
        return OsError.init;
    return error;
}

package(xtb.fs) OsError canonicalPath(String path, ref StringBuf output) @system
{
    ScratchScope scratch = ScratchScope.acquire(output.allocator);
    StringBuf native = StringBuf.fromString(scratch.allocator, path);
    char* resolved = realpath(native.checkedCString, null);
    if (resolved is null)
        return lastError();
    const checked = fromCString(resolved);
    if (checked.failed)
    {
        free(resolved);
        return OsError(OsErrorKind.invalidData, 0);
    }
    output.append(checked.value);
    free(resolved);
    return OsError.init;
}
