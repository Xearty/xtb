module xtb.fs.file;

nothrow @nogc:

import core.attribute;

import xtb.containers.array;
import xtb.fs.internal.file;
import xtb.fs.path;
import xtb.os.error;
import xtb.os.handle;
import xtb.panic;
import xtb.types;

version (linux)
    private import backend = xtb.fs.internal.linux.file;
else
    private import backend = xtb.fs.internal.unsupported.file;

enum FileType
{
    unknown,
    regular,
    directory,
    symbolic_link,
    character_device,
    block_device,
    fifo,
    socket,
}

struct FileMetadata
{
    FileType type;
    u64 size;
    i64 modified_nanoseconds;
    u32 permissions;
}

enum CreateMode
{
    open_existing,
    open_or_create,
    create_new,
}

enum SymlinkMode
{
    no_follow,
    follow,
}

struct OpenOptions
{
    bool read = true;
    bool write;
    CreateMode create_mode;
    bool truncate;
    bool append;
    bool close_on_exec = true;
    u16 permissions = 0x180; // POSIX 0600
}

@mustuse struct IOResult
{
nothrow @nogc:

    OsError error;
    usize transferred;

    bool complete(usize requested) const pure @safe
    {
        return this.error.succeeded && this.transferred == requested;
    }
}

/// Owns an open native file handle.
@mustuse struct File
{
nothrow @nogc:

    /// Owned native handle. `NativeHandle.init` represents a closed file.
    /// A valid handle has single ownership and must be closed before replacement.
    NativeHandle handle;

    @disable this(this);
    @disable ref File opAssign(File source) return;

    /// Closes this file if it is open and reports any native close error.
    OsError close() @safe
    {
        if (!this.valid) return OsError.init;

        const handle = this.handle;
        this.handle = NativeHandle.init;
        return backend.close_handle(handle);
    }

    /// Explicitly ends this file's lifetime.
    ///
    /// Close errors are discarded; call `close` directly when they matter.
    void deinit() @safe
    {
        cast(void) this.close();
    }

    bool valid() const pure @safe
    {
        return this.handle.valid;
    }

    OsError flush() @safe
    {
        require(this.valid, "invalid File for flush");
        return backend.flush_handle(this.handle);
    }

    IOResult read_some(scope u8[] output) @safe
    {
        require(this.valid, "invalid File for read");
        const result = backend.read_some(this.handle, output);
        return IOResult(result.error, result.transferred);
    }

    IOResult write_some(scope const(u8)[] input) @safe
    {
        require(this.valid, "invalid File for write");
        const result = backend.write_some(this.handle, input);
        return IOResult(result.error, result.transferred);
    }

    IOResult read_all(scope u8[] output) @safe
    {
        usize total;
        while (total < output.length)
        {
            const result = this.read_some(output[total .. $]);
            total += result.transferred;
            if (result.error.failed || result.transferred == 0)
                return IOResult(result.error, total);
        }
        return IOResult(OsError.init, total);
    }

    IOResult write_all(scope const(u8)[] input) @safe
    {
        usize total;
        while (total < input.length)
        {
            const result = this.write_some(input[total .. $]);
            total += result.transferred;
            if (result.error.failed || result.transferred == 0)
                return IOResult(result.error, total);
        }
        return IOResult(OsError.init, total);
    }

    /// Reads metadata for this open file into `output`.
    ///
    /// `output` must not be null. On failure, it is left as `FileMetadata.init`.
    OsError metadata(scope FileMetadata* output) @system
    {
        require(output !is null, "FileMetadata output pointer is null");
        require(this.valid, "invalid File for metadata");
        *output = FileMetadata.init;

        NativeFileMetadata native;
        const error = backend.handle_metadata(this.handle, &native);
        if (error.failed) return error;

        *output = from_native(native);
        return OsError.init;
    }
}

/// Opens `path` into `output` using `options`.
///
/// `output` must not be null. Any file already owned by `output` is closed first.
/// On failure, `output` is left as `File.init`.
OsError open(scope const Path path, OpenOptions options, scope File* output) @system
{
    require(output !is null, "File output pointer is null");
    const cleanup_error = output.close();
    if (cleanup_error.failed) return cleanup_error;
    if (!valid_open_options(options)) return OsError(OsErrorKind.invalidArgument, 0);

    NativeHandle handle;
    const error = backend.open_file(
        path.view,
        options.read,
        options.write,
        cast(u8) options.create_mode,
        options.truncate,
        options.append,
        options.close_on_exec,
        options.permissions,
        &handle,
    );
    if (error.failed) return error;

    output.handle = handle;
    return OsError.init;
}

private bool valid_open_options(OpenOptions options) pure @safe
{
    if (
        options.create_mode < CreateMode.open_existing ||
        options.create_mode > CreateMode.create_new
    )
    {
        return false;
    }
    if (!options.read && !options.write) return false;
    if ((options.truncate || options.append) && !options.write) return false;
    if (options.truncate && options.append) return false;
    return true;
}

/// Reads metadata for `path` into `output`.
///
/// `output` must not be null. On failure, it is left as `FileMetadata.init`.
OsError metadata(scope const Path path, SymlinkMode symlinks, scope FileMetadata* output) @system
{
    require(output !is null, "FileMetadata output pointer is null");
    *output = FileMetadata.init;
    if (symlinks < SymlinkMode.no_follow || symlinks > SymlinkMode.follow)
        return OsError(OsErrorKind.invalidArgument, 0);

    NativeFileMetadata native;
    const error = backend.path_metadata(path.view, symlinks == SymlinkMode.follow, &native);
    if (error.failed) return error;

    *output = from_native(native);
    return OsError.init;
}

private FileMetadata from_native(NativeFileMetadata native) pure @safe
{
    FileType type;
    final switch (native.type)
    {
        case NativeFileType.unknown:
            type = FileType.unknown;
            break;
        case NativeFileType.regular:
            type = FileType.regular;
            break;
        case NativeFileType.directory:
            type = FileType.directory;
            break;
        case NativeFileType.symbolic_link:
            type = FileType.symbolic_link;
            break;
        case NativeFileType.character_device:
            type = FileType.character_device;
            break;
        case NativeFileType.block_device:
            type = FileType.block_device;
            break;
        case NativeFileType.fifo:
            type = FileType.fifo;
            break;
        case NativeFileType.socket:
            type = FileType.socket;
            break;
    }
    return FileMetadata(type, native.size, native.modified_nanoseconds, native.permissions);
}

/// Reads the complete file at `path` into `output`.
///
/// `output` must not be null. It is cleared before reading and is empty on failure.
OsError read_entire_file(scope const Path path, scope Array!u8* output) @system
{
    require(output !is null, "Array output pointer is null");
    output.clear();

    File file;
    scope (exit) file.deinit();

    OsError error = open(path, OpenOptions.init, &file);
    if (error.failed) return error;

    FileMetadata information;
    if (file.metadata(&information).succeeded && information.size != 0)
    {
        if (information.size > usize.max || !output.try_reserve(cast(usize) information.size))
            return OsError(OsErrorKind.system, 0);
    }

    u8[64 * 1024] chunk;
    for (;;)
    {
        const result = file.read_some(chunk[]);
        if (result.error.failed)
        {
            output.clear();
            return result.error;
        }
        if (result.transferred == 0) return OsError.init;
        if (!output.try_append(chunk[0 .. result.transferred]))
        {
            output.clear();
            return OsError(OsErrorKind.system, 0);
        }
    }
}

OsError write_entire_file(
    scope const Path path,
    scope const(u8)[] input,
    CreateMode create_mode = CreateMode.open_or_create,
) @system
{
    OpenOptions options;
    options.read = false;
    options.write = true;
    options.create_mode = create_mode;
    options.truncate = true;

    File file;
    scope (exit) file.deinit();

    OsError error = open(path, options, &file);
    if (error.failed) return error;

    const result = file.write_all(input);
    if (result.complete(input.length)) return OsError.init;
    if (result.error.failed) return result.error;
    return OsError(OsErrorKind.system, 0);
}

/// Copies `source` to `destination` using `buffer` as temporary storage.
///
/// `buffer` must not be null.
OsError copy_file(
    scope const Path source,
    scope const Path destination,
    scope Array!u8* buffer,
    CreateMode create_mode = CreateMode.open_or_create,
) @system
{
    OsError error = read_entire_file(source, buffer);
    if (error.failed) return error;
    return write_entire_file(destination, buffer.slice, create_mode);
}
