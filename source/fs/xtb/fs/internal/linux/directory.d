module xtb.fs.internal.linux.directory;

nothrow @nogc:

import core.stdc.errno;
import core.stdc.stdlib;

import xtb.containers.array;
import xtb.fs.internal.directory;
import xtb.fs.internal.file;
import xtb.os.error;
import xtb.os.posix.directory;
import xtb.os.posix.error;
import xtb.string;
import xtb.thread_context;
import xtb.types;
import xtb.utf8;

package(xtb.fs) bool directory_valid(scope const(void)* directory) pure @safe
{
    return directory !is null;
}

// `directory` must not be null.
package(xtb.fs) OsError close_directory(scope void** directory) @system
{
    if (*directory is null) return OsError.init;

    DIR* native_directory = cast(DIR*) *directory;
    *directory = null;
    return closedir(native_directory) == 0 ? OsError.init : lastError();
}

// `output` must not be null.
package(xtb.fs) OsError open_directory(scope String path, scope void** output) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native_path = StringBuf.from_string(scratch.allocator, path);
    *output = opendir(native_path.checked_c_string);
    return *output is null ? lastError() : OsError.init;
}

// `directory` must be a valid native directory handle and `output` must not be null.
package(xtb.fs) NativeDirectoryResult next_directory(
    scope void* directory,
    scope NativeDirectoryEntry* output,
) @system
{
    *output = NativeDirectoryEntry.init;
    for (;;)
    {
        errno = 0;
        const native_entry = readdir(cast(DIR*) directory);
        if (native_entry is null)
        {
            return errno == 0
                ? NativeDirectoryResult(NativeDirectoryStatus.finished, OsError.init)
                : NativeDirectoryResult(NativeDirectoryStatus.failed, lastError());
        }

        const checked = from_c_string(native_entry.d_name.ptr);
        if (checked.failed)
        {
            return NativeDirectoryResult(
                NativeDirectoryStatus.failed,
                OsError(OsErrorKind.invalidData, 0),
            );
        }

        const name = checked.value;
        if (name == "." || name == "..") continue;

        output.name = name;
        output.type = from_directory_type(native_entry.d_type);
        return NativeDirectoryResult(NativeDirectoryStatus.entry, OsError.init);
    }
}

private NativeFileType from_directory_type(u8 value) pure @safe
{
    switch (value)
    {
        case DT_REG:
            return NativeFileType.regular;
        case DT_DIR:
            return NativeFileType.directory;
        case DT_LNK:
            return NativeFileType.symbolic_link;
        case DT_CHR:
            return NativeFileType.character_device;
        case DT_BLK:
            return NativeFileType.block_device;
        case DT_FIFO:
            return NativeFileType.fifo;
        case DT_SOCK:
            return NativeFileType.socket;
        default:
            return NativeFileType.unknown;
    }
}

package(xtb.fs) OsError create_directory(scope String path, u32 permissions) @trusted
{
    // The temporary buffer owns a NUL-terminated path for the duration of the POSIX call.
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native_path = StringBuf.from_string(scratch.allocator, path);
    return mkdir(native_path.checked_c_string, permissions) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError remove_empty_directory(scope String path) @trusted
{
    // The temporary buffer owns a NUL-terminated path for the duration of the POSIX call.
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native_path = StringBuf.from_string(scratch.allocator, path);
    return rmdir(native_path.checked_c_string) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError remove_file(scope String path) @trusted
{
    // The temporary buffer owns a NUL-terminated path for the duration of the POSIX call.
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native_path = StringBuf.from_string(scratch.allocator, path);
    return unlink(native_path.checked_c_string) == 0 ? OsError.init : lastError();
}

package(xtb.fs) OsError rename_path(scope String source, scope String destination) @trusted
{
    // Both temporary buffers own NUL-terminated paths for the duration of the POSIX call.
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native_source = StringBuf.from_string(scratch.allocator, source);
    StringBuf native_destination = StringBuf.from_string(scratch.allocator, destination);
    return rename(native_source.checked_c_string, native_destination.checked_c_string) == 0
        ? OsError.init
        : lastError();
}

// `output` must not be null.
package(xtb.fs) OsError current_directory(scope StringBuf* output) @system
{
    char* buffer = getcwd(null, 0);
    scope (exit) free(buffer);

    if (buffer is null) return lastError();

    const checked = from_c_string(buffer);
    if (checked.failed) return OsError(OsErrorKind.invalidData, 0);

    output.append(checked.value);
    return OsError.init;
}

// `output` must not be null.
package(xtb.fs) OsError executable_path(scope StringBuf* output) @system
{
    ScratchScope scratch = ScratchScope.acquire(output.allocator);
    Array!char buffer = Array!char.with_length(scratch.allocator, 256);
    for (;;)
    {
        const isize amount = readlink("/proc/self/exe".ptr, buffer.slice.ptr, buffer.length);
        if (amount < 0) return lastError();

        if (cast(usize) amount < buffer.length)
        {
            const checked = (cast(const(u8)[]) buffer.slice[0 .. cast(usize) amount]).as_string;
            if (checked.failed) return OsError(OsErrorKind.invalidData, 0);

            output.append(checked.value);
            return OsError.init;
        }

        if (buffer.length > usize.max / 2) return OsError(OsErrorKind.system, 0);

        buffer.resize(buffer.length * 2);
    }
}

// `output` must not be null.
package(xtb.fs) OsError query_access(scope String path, u8 requested, scope bool* output) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native_path = StringBuf.from_string(scratch.allocator, path);
    i32 mode;
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

    if (access(native_path.checked_c_string, mode) == 0)
    {
        *output = true;
        return OsError.init;
    }

    const error = lastError();
    if (error.kind == OsErrorKind.notFound || error.kind == OsErrorKind.permissionDenied)
        return OsError.init;

    return error;
}

// `output` must not be null.
package(xtb.fs) OsError canonical_path(scope String path, scope StringBuf* output) @system
{
    ScratchScope scratch = ScratchScope.acquire(output.allocator);
    StringBuf native_path = StringBuf.from_string(scratch.allocator, path);
    char* resolved = realpath(native_path.checked_c_string, null);
    scope (exit) free(resolved);

    if (resolved is null) return lastError();

    const checked = from_c_string(resolved);
    if (checked.failed) return OsError(OsErrorKind.invalidData, 0);

    output.append(checked.value);
    return OsError.init;
}
