module xtb.fs.file;

nothrow @nogc:

import xtb.containers.array;

version (XTB_Checked) import xtb.panic : require;
import xtb.string;
import xtb.types : i64, u16, u32, u64, u8;
import xtb.os.error : OsError, OsErrorKind;
import xtb.fs.path : Path;

import xtb.fs.internal.file : NativeFileMetadata, NativeFileType;

version (linux)
    private import backend = xtb.fs.internal.linux.file;
else
    private import backend = xtb.fs.internal.unsupported.file;

enum FileType : ubyte
{
    unknown,
    regular,
    directory,
    symbolicLink,
    characterDevice,
    blockDevice,
    fifo,
    socket,
}

struct FileMetadata
{
    FileType type;
    u64 size;
    i64 modifiedNanoseconds;
    u32 permissions;
}

enum CreateMode : ubyte
{
    openExisting,
    openOrCreate,
    createNew,
}

enum SymlinkMode : ubyte
{
    noFollow,
    follow,
}

struct OpenOptions
{
    bool read = true;
    bool write;
    CreateMode createMode;
    bool truncate;
    bool append;
    bool closeOnExec = true;
    u16 permissions = 0x180; // POSIX 0600
}

struct IoResult
{
nothrow @nogc:

    OsError error;
    size_t transferred;

    bool complete(size_t requested) const pure @safe
    {
        return error.succeeded && transferred == requested;
    }
}

struct File
{
nothrow @nogc:

    private int descriptor_ = -1;

    @disable this(this);
    @disable ref File opAssign(File source) return;

    /// Closes this file if it is open and reports any native close error.
    OsError close() @system
    {
        if (!valid)
            return OsError.init;
        const descriptor = descriptor_;
        descriptor_ = -1;
        return backend.closeDescriptor(descriptor);
    }

    /// Explicitly ends this file's lifetime.
    ///
    /// Close errors are discarded; call `close` directly when they matter.
    void deinit() @system
    {
        cast(void) close();
    }

    bool valid() const pure @safe
    {
        return descriptor_ >= 0;
    }

    package(xtb) int nativeDescriptor() const pure @safe
    {
        return descriptor_;
    }
}

OsError close(File* file) @system
{
    version (XTB_Checked)
        require(file !is null, "File pointer is null");
    return file.close();
}

OsError flush(File* file) @system
{
    version (XTB_Checked)
        require(file !is null && file.valid, "invalid File for flush");
    return backend.flushDescriptor(file.descriptor_);
}

OsError open(Path path, OpenOptions options, File* output) @system
{
    version (XTB_Checked)
        require(output !is null, "File output pointer is null");
    const cleanupError = close(output);
    if (cleanupError.failed)
        return cleanupError;
    if (!valid(options))
        return OsError(OsErrorKind.invalidArgument, 0);
    int descriptor = -1;
    const error = backend.openFile(
        path.view,
        options.read,
        options.write,
        cast(ubyte) options.createMode,
        options.truncate,
        options.append,
        options.closeOnExec,
        options.permissions,
        &descriptor,
    );
    if (error.failed)
        return error;
    output.descriptor_ = descriptor;
    return OsError.init;
}

private bool valid(OpenOptions options) pure @safe
{
    if (cast(ubyte) options.createMode > cast(ubyte) CreateMode.createNew)
        return false;
    if (!options.read && !options.write)
        return false;
    if ((options.truncate || options.append) && !options.write)
        return false;
    if (options.truncate && options.append)
        return false;
    return true;
}

IoResult readSome(File* file, u8[] output) @system
{
    version (XTB_Checked)
        require(file !is null && file.valid, "invalid File for read");
    const result = backend.readSome(file.descriptor_, output);
    return IoResult(result.error, result.transferred);
}

IoResult writeSome(File* file, scope const(u8)[] input) @system
{
    version (XTB_Checked)
        require(file !is null && file.valid, "invalid File for write");
    const result = backend.writeSome(file.descriptor_, input);
    return IoResult(result.error, result.transferred);
}

IoResult readAll(File* file, u8[] output) @system
{
    size_t total;
    while (total < output.length)
    {
        const result = file.readSome(output[total .. $]);
        total += result.transferred;
        if (result.error.failed || result.transferred == 0)
            return IoResult(result.error, total);
    }
    return IoResult(OsError.init, total);
}

IoResult writeAll(File* file, scope const(u8)[] input) @system
{
    size_t total;
    while (total < input.length)
    {
        const result = file.writeSome(input[total .. $]);
        total += result.transferred;
        if (result.error.failed || result.transferred == 0)
            return IoResult(result.error, total);
    }
    return IoResult(OsError.init, total);
}

OsError metadata(File* file, FileMetadata* output) @system
{
    version (XTB_Checked)
    {
        require(file !is null && file.valid, "invalid File for metadata");
        require(output !is null, "FileMetadata output pointer is null");
    }
    *output = FileMetadata.init;
    NativeFileMetadata native;
    const error = backend.descriptorMetadata(file.descriptor_, &native);
    if (error.failed)
        return error;
    *output = fromNative(native);
    return OsError.init;
}

OsError metadata(Path path, SymlinkMode symlinks, FileMetadata* output) @system
{
    version (XTB_Checked)
        require(output !is null, "FileMetadata output pointer is null");
    *output = FileMetadata.init;
    if (cast(ubyte) symlinks > cast(ubyte) SymlinkMode.follow)
        return OsError(OsErrorKind.invalidArgument, 0);

    NativeFileMetadata native;
    const error = backend.pathMetadata(
        path.view,
        symlinks == SymlinkMode.follow,
        &native,
    );
    if (error.failed)
        return error;
    *output = fromNative(native);
    return OsError.init;
}

private FileMetadata fromNative(NativeFileMetadata native) pure @safe
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
        case NativeFileType.symbolicLink:
            type = FileType.symbolicLink;
            break;
        case NativeFileType.characterDevice:
            type = FileType.characterDevice;
            break;
        case NativeFileType.blockDevice:
            type = FileType.blockDevice;
            break;
        case NativeFileType.fifo:
            type = FileType.fifo;
            break;
        case NativeFileType.socket:
            type = FileType.socket;
            break;
    }
    return FileMetadata(
        type,
        native.size,
        native.modifiedNanoseconds,
        native.permissions,
    );
}

OsError readEntireFile(Path path, ref Array!u8 output) @system
{
    output.clear();
    File file;
    scope (exit)
        file.deinit();
    OsError error = open(path, OpenOptions.init, &file);
    if (error.failed)
        return error;
    FileMetadata information;
    if ((&file).metadata(&information).succeeded && information.size != 0)
    {
        if (information.size > size_t.max ||
            !output.tryReserve(cast(size_t) information.size))
            return OsError(OsErrorKind.system, 0);
    }

    u8[64 * 1024] chunk;
    for (;;)
    {
        const result = (&file).readSome(chunk[]);
        if (result.error.failed)
        {
            output.clear();
            return result.error;
        }
        if (result.transferred == 0)
            return OsError.init;
        if (!output.tryAppend(chunk[0 .. result.transferred]))
        {
            output.clear();
            return OsError(OsErrorKind.system, 0);
        }
    }
}

OsError writeEntireFile(
    Path path,
    scope const(u8)[] input,
    CreateMode createMode = CreateMode.openOrCreate,
) @system
{
    OpenOptions options;
    options.read = false;
    options.write = true;
    options.createMode = createMode;
    options.truncate = true;
    File file;
    scope (exit)
        file.deinit();
    OsError error = open(path, options, &file);
    if (error.failed)
        return error;
    const result = (&file).writeAll(input);
    return result.complete(input.length) ? OsError.init : result.error.failed
        ? result.error
        : OsError(OsErrorKind.system, 0);
}

OsError copyFile(
    Path source,
    Path destination,
    ref Array!u8 buffer,
    CreateMode createMode = CreateMode.openOrCreate,
) @system
{
    OsError error = readEntireFile(source, buffer);
    if (error.failed)
        return error;
    return writeEntireFile(destination, buffer.slice, createMode);
}
