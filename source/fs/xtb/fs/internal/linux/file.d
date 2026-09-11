module xtb.fs.internal.linux.file;

nothrow @nogc:

import core.stdc.errno;

import xtb.fs.internal.file;
import xtb.os.error;
import xtb.os.handle;
import xtb.os.posix.error;
import xtb.os.posix.file;
import xtb.os.posix.handle;
import xtb.string;
import xtb.thread_context;
import xtb.types;

package(xtb.fs) OsError close_handle(NativeHandle handle) @trusted
{
    return close(to_descriptor(handle)) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError flush_handle(NativeHandle handle) @trusted
{
    return fsync(to_descriptor(handle)) == 0 ? OsError.init : lastError();
}

// `output` must not be null.
package(xtb.fs) OsError open_file(
    scope String path,
    bool read_enabled,
    bool write_enabled,
    u8 create_mode,
    bool truncate,
    bool append,
    bool close_on_exec,
    u16 permissions,
    scope NativeHandle* output,
) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native_path = StringBuf.from_string(scratch.allocator, path);
    i32 flags = O_RDONLY;
    if (read_enabled && write_enabled)
    {
        flags = O_RDWR;
    }
    else if (write_enabled)
    {
        flags = O_WRONLY;
    }
    if (create_mode != 0) flags |= O_CREAT;
    if (truncate) flags |= O_TRUNC;
    if (append) flags |= O_APPEND;
    if (create_mode == 2) flags |= O_EXCL;
    if (close_on_exec) flags |= O_CLOEXEC;
    const i32 descriptor = open(native_path.checked_c_string, flags, cast(u32) permissions);
    if (descriptor < 0) return lastError();
    *output = from_descriptor(descriptor);
    return OsError.init;
}

package(xtb.fs) NativeIOResult read_some(NativeHandle handle, scope u8[] output) @trusted
{
    // POSIX read uses the scoped slice only for this call and does not retain its pointer.
    for (;;)
    {
        const isize amount = read(to_descriptor(handle), output.ptr, output.length);
        if (amount >= 0) return NativeIOResult(OsError.init, cast(usize) amount);
        if (errno != EINTR) return NativeIOResult(lastError(), 0);
    }
}

package(xtb.fs) NativeIOResult write_some(NativeHandle handle, scope const(u8)[] input) @trusted
{
    // POSIX write uses the scoped slice only for this call and does not retain its pointer.
    for (;;)
    {
        const isize amount = write(to_descriptor(handle), input.ptr, input.length);
        if (amount >= 0) return NativeIOResult(OsError.init, cast(usize) amount);
        if (errno != EINTR) return NativeIOResult(lastError(), 0);
    }
}

// `output` must not be null.
package(xtb.fs) OsError handle_metadata(
    NativeHandle handle,
    scope NativeFileMetadata* output,
) @system
{
    stat_t native;
    if (fstat(to_descriptor(handle), &native) != 0) return lastError();
    return convert(native, output)
        ? OsError.init
        : OsError(OsErrorKind.invalidArgument, 0);
}

private NativeHandle from_descriptor(i32 descriptor) pure @safe
{
    return fromFileDescriptor(descriptor);
}

private i32 to_descriptor(NativeHandle handle) pure @safe
{
    return fileDescriptor(handle);
}

// `output` must not be null.
package(xtb.fs) OsError path_metadata(
    scope String path,
    bool follow_symlinks,
    scope NativeFileMetadata* output,
) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native_path = StringBuf.from_string(scratch.allocator, path);
    stat_t native;
    const i32 status = follow_symlinks
        ? stat(native_path.checked_c_string, &native)
        : lstat(native_path.checked_c_string, &native);
    if (status != 0) return lastError();
    return convert(native, output)
        ? OsError.init
        : OsError(OsErrorKind.invalidArgument, 0);
}

// `output` must not be null.
private bool convert(scope const ref stat_t native, scope NativeFileMetadata* output) pure @system
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
            type = NativeFileType.symbolic_link;
            break;
        case S_IFCHR:
            type = NativeFileType.character_device;
            break;
        case S_IFBLK:
            type = NativeFileType.block_device;
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
    if (native.st_size < 0 || nanoseconds < 0 || nanoseconds >= 1_000_000_000) return false;
    enum i64 nanoseconds_per_second = 1_000_000_000L;
    if (seconds < i64.min / nanoseconds_per_second || seconds > i64.max / nanoseconds_per_second)
        return false;
    *output = NativeFileMetadata(
        type,
        cast(u64) native.st_size,
        seconds * nanoseconds_per_second + nanoseconds,
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
    assert(result.modified_nanoseconds == -500_000_000);
}
