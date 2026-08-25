module xtb.os.file;

nothrow @nogc:

import xtb.core.containers.array;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.string;
import xtb.core.thread_context : ScratchScope;
import xtb.core.types : i64, u16, u32, u64, u8;
import xtb.os.error : OsError, OsErrorKind, lastError, unsupported;
import xtb.os.path : Path;

version (linux) import core.sys.posix.sys.stat : NativeStat = stat_t;

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
        version (linux)
        {
            import core.sys.posix.unistd : nativeClose = close;

            const descriptor = descriptor_;
            descriptor_ = -1;
            return nativeClose(descriptor) == 0 ? OsError.init : lastError();
        }
        else
        {
            descriptor_ = -1;
            return unsupported();
        }
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
    version (linux)
    {
        import core.sys.posix.unistd : fsync;

        return fsync(file.descriptor_) == 0 ? OsError.init : lastError();
    }
    else
        return unsupported();
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
    version (linux)
    {
        import core.sys.posix.fcntl : O_APPEND, O_CLOEXEC, O_CREAT, O_EXCL,
            O_RDONLY, O_RDWR, O_TRUNC, O_WRONLY, open;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
        int flags = options.read && options.write ? O_RDWR : options.write ? O_WRONLY : O_RDONLY;
        if (options.createMode != CreateMode.openExisting)
            flags |= O_CREAT;
        if (options.truncate)
            flags |= O_TRUNC;
        if (options.append)
            flags |= O_APPEND;
        if (options.createMode == CreateMode.createNew)
            flags |= O_EXCL;
        if (options.closeOnExec)
            flags |= O_CLOEXEC;
        const descriptor = open(native.checkedCString, flags, cast(uint) options.permissions);
        if (descriptor < 0)
            return lastError();
        output.descriptor_ = descriptor;
        return OsError.init;
    }
    else
        return unsupported();
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
    version (linux)
    {
        import core.stdc.errno : EINTR, errno;
        import core.sys.posix.unistd : read;

        for (;;)
        {
            const amount = read(file.descriptor_, output.ptr, output.length);
            if (amount >= 0)
                return IoResult(OsError.init, cast(size_t) amount);
            if (errno != EINTR)
                return IoResult(lastError(), 0);
        }
    }
    else
        return IoResult(unsupported(), 0);
}

IoResult writeSome(File* file, scope const(u8)[] input) @system
{
    version (XTB_Checked)
        require(file !is null && file.valid, "invalid File for write");
    version (linux)
    {
        import core.stdc.errno : EINTR, errno;
        import core.sys.posix.unistd : write;

        for (;;)
        {
            const amount = write(file.descriptor_, input.ptr, input.length);
            if (amount >= 0)
                return IoResult(OsError.init, cast(size_t) amount);
            if (errno != EINTR)
                return IoResult(lastError(), 0);
        }
    }
    else
        return IoResult(unsupported(), 0);
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
    version (linux)
    {
        import core.sys.posix.sys.stat : fstat, stat_t;

        stat_t native;
        if (fstat(file.descriptor_, &native) != 0)
            return lastError();
        return convert(native, output)
            ? OsError.init : OsError(OsErrorKind.invalidArgument, 0);
    }
    else
        return unsupported();
}

OsError metadata(Path path, SymlinkMode symlinks, FileMetadata* output) @system
{
    version (XTB_Checked)
        require(output !is null, "FileMetadata output pointer is null");
    *output = FileMetadata.init;
    if (cast(ubyte) symlinks > cast(ubyte) SymlinkMode.follow)
        return OsError(OsErrorKind.invalidArgument, 0);
    version (linux)
    {
        import core.sys.posix.sys.stat : lstat, stat, stat_t;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf nativePath = StringBuf.fromString(scratch.allocator, path.view);
        stat_t native;
        const state = symlinks == SymlinkMode.follow
            ? stat(nativePath.checkedCString, &native) : lstat(nativePath.checkedCString, &native);
        if (state != 0)
            return lastError();
        return convert(native, output)
            ? OsError.init : OsError(OsErrorKind.invalidArgument, 0);
    }
    else
        return unsupported();
}

version (linux) private bool convert(
    ref const NativeStat native,
    FileMetadata* output,
) pure @system
{
    import core.sys.posix.sys.stat : S_IFBLK, S_IFCHR, S_IFDIR, S_IFIFO,
        S_IFLNK, S_IFMT, S_IFREG, S_IFSOCK;

    FileType type;
    switch (native.st_mode & S_IFMT)
    {
        case S_IFREG:
            type = FileType.regular;
            break;
        case S_IFDIR:
            type = FileType.directory;
            break;
        case S_IFLNK:
            type = FileType.symbolicLink;
            break;
        case S_IFCHR:
            type = FileType.characterDevice;
            break;
        case S_IFBLK:
            type = FileType.blockDevice;
            break;
        case S_IFIFO:
            type = FileType.fifo;
            break;
        case S_IFSOCK:
            type = FileType.socket;
            break;
        default:
            type = FileType.unknown;
            break;
    }
    i64 seconds;
    i64 nanoseconds;
    static if (__traits(hasMember, NativeStat, "st_mtim"))
    {
        seconds = cast(i64) native.st_mtim.tv_sec;
        nanoseconds = cast(i64) native.st_mtim.tv_nsec;
    }
    else
    {
        seconds = cast(i64) native.st_mtime;
        nanoseconds = cast(i64) native.st_mtimensec;
    }
    if (native.st_size < 0 || nanoseconds < 0 ||
        nanoseconds >= 1_000_000_000)
        return false;
    enum i64 nanosecondsPerSecond = 1_000_000_000L;
    if (seconds < i64.min / nanosecondsPerSecond ||
        seconds > i64.max / nanosecondsPerSecond)
        return false;
    *output = FileMetadata(
        type,
        cast(u64) native.st_size,
        seconds * nanosecondsPerSecond + nanoseconds,
        cast(u32) native.st_mode & 0xFFF,
    );
    return true;
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

version (linux) pure @system unittest
{
    import core.sys.posix.sys.stat : S_IFREG;

    NativeStat native;
    native.st_mode = S_IFREG | 0x180;
    native.st_size = 7;
    static if (__traits(hasMember, NativeStat, "st_mtim"))
    {
        native.st_mtim.tv_sec = -1;
        native.st_mtim.tv_nsec = 500_000_000;
    }
    else
    {
        native.st_mtime = -1;
        native.st_mtimensec = 500_000_000;
    }
    FileMetadata result;
    assert(convert(native, &result));
    assert(result.type == FileType.regular);
    assert(result.size == 7);
    assert(result.modifiedNanoseconds == -500_000_000);
}
