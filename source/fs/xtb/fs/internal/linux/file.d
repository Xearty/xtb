module xtb.fs.internal.linux.file;

nothrow @nogc:

import core.stdc.errno : EINTR, errno;
import core.sys.posix.fcntl : O_APPEND, O_CLOEXEC, O_CREAT, O_EXCL,
    O_RDONLY, O_RDWR, O_TRUNC, O_WRONLY, nativeOpen = open;
import core.sys.posix.sys.stat : S_IFBLK, S_IFCHR, S_IFDIR, S_IFIFO,
    S_IFLNK, S_IFMT, S_IFREG, S_IFSOCK, fstat, lstat, stat, stat_t;
import core.sys.posix.unistd : fsync, nativeClose = close, read, write;
import xtb.os.error : OsError, OsErrorKind, lastError;
import xtb.string : String, StringBuf;
import xtb.thread_context : ScratchScope;
import xtb.types : i64, u32, u64, u8;
import xtb.fs.internal.file : NativeFileMetadata, NativeFileType, NativeIoResult;

package(xtb.fs) OsError closeDescriptor(int descriptor) @system
{
    return nativeClose(descriptor) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError flushDescriptor(int descriptor) @system
{
    return fsync(descriptor) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError openFile(
    String path,
    bool readEnabled,
    bool writeEnabled,
    ubyte createMode,
    bool truncate,
    bool append,
    bool closeOnExec,
    ushort permissions,
    int* output,
) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native = StringBuf.fromString(scratch.allocator, path);
    int flags = readEnabled && writeEnabled ? O_RDWR : writeEnabled ? O_WRONLY : O_RDONLY;
    if (createMode != 0)
        flags |= O_CREAT;
    if (truncate)
        flags |= O_TRUNC;
    if (append)
        flags |= O_APPEND;
    if (createMode == 2)
        flags |= O_EXCL;
    if (closeOnExec)
        flags |= O_CLOEXEC;
    const descriptor = nativeOpen(native.checkedCString, flags, cast(uint) permissions);
    if (descriptor < 0)
        return lastError();
    *output = descriptor;
    return OsError.init;
}

package(xtb.fs) NativeIoResult readSome(int descriptor, u8[] output) @system
{
    for (;;)
    {
        const amount = read(descriptor, output.ptr, output.length);
        if (amount >= 0)
            return NativeIoResult(OsError.init, cast(size_t) amount);
        if (errno != EINTR)
            return NativeIoResult(lastError(), 0);
    }
}

package(xtb.fs) NativeIoResult writeSome(
    int descriptor,
    scope const(u8)[] input,
) @system
{
    for (;;)
    {
        const amount = write(descriptor, input.ptr, input.length);
        if (amount >= 0)
            return NativeIoResult(OsError.init, cast(size_t) amount);
        if (errno != EINTR)
            return NativeIoResult(lastError(), 0);
    }
}

package(xtb.fs) OsError descriptorMetadata(
    int descriptor,
    NativeFileMetadata* output,
) @system
{
    stat_t native;
    if (fstat(descriptor, &native) != 0)
        return lastError();
    return convert(native, output)
        ? OsError.init : OsError(OsErrorKind.invalidArgument, 0);
}

package(xtb.fs) OsError pathMetadata(
    String path,
    bool followSymlinks,
    NativeFileMetadata* output,
) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf nativePath = StringBuf.fromString(scratch.allocator, path);
    stat_t native;
    const state = followSymlinks
        ? stat(nativePath.checkedCString, &native) : lstat(nativePath.checkedCString, &native);
    if (state != 0)
        return lastError();
    return convert(native, output)
        ? OsError.init : OsError(OsErrorKind.invalidArgument, 0);
}

private bool convert(
    ref const stat_t native,
    NativeFileMetadata* output,
) pure @system
{
    NativeFileType type;
    switch (native.st_mode & S_IFMT)
    {
        case S_IFREG:
            type = NativeFileType.regular;
            break;
        case S_IFDIR:
            type = NativeFileType.directory;
            break;
        case S_IFLNK:
            type = NativeFileType.symbolicLink;
            break;
        case S_IFCHR:
            type = NativeFileType.characterDevice;
            break;
        case S_IFBLK:
            type = NativeFileType.blockDevice;
            break;
        case S_IFIFO:
            type = NativeFileType.fifo;
            break;
        case S_IFSOCK:
            type = NativeFileType.socket;
            break;
        default:
            type = NativeFileType.unknown;
            break;
    }
    i64 seconds;
    i64 nanoseconds;
    static if (__traits(hasMember, stat_t, "st_mtim"))
    {
        seconds = cast(i64) native.st_mtim.tv_sec;
        nanoseconds = cast(i64) native.st_mtim.tv_nsec;
    }
    else
    {
        seconds = cast(i64) native.st_mtime;
        nanoseconds = cast(i64) native.st_mtimensec;
    }
    if (native.st_size < 0 || nanoseconds < 0 || nanoseconds >= 1_000_000_000)
        return false;
    enum i64 nanosecondsPerSecond = 1_000_000_000L;
    if (seconds < i64.min / nanosecondsPerSecond ||
        seconds > i64.max / nanosecondsPerSecond)
        return false;
    *output = NativeFileMetadata(
        type,
        cast(u64) native.st_size,
        seconds * nanosecondsPerSecond + nanoseconds,
        cast(u32) native.st_mode & 0xFFF,
    );
    return true;
}

pure @system unittest
{
    stat_t native;
    native.st_mode = S_IFREG | 0x180;
    native.st_size = 7;
    static if (__traits(hasMember, stat_t, "st_mtim"))
    {
        native.st_mtim.tv_sec = -1;
        native.st_mtim.tv_nsec = 500_000_000;
    }
    else
    {
        native.st_mtime = -1;
        native.st_mtimensec = 500_000_000;
    }
    NativeFileMetadata result;
    assert(convert(native, &result));
    assert(result.type == NativeFileType.regular);
    assert(result.size == 7);
    assert(result.modifiedNanoseconds == -500_000_000);
}
