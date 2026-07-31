module xtb.os.file;

import xtb.core.array : Array, clear, tryResize;
import xtb.core.panic : require;
import xtb.core.string : StringBuf, checkedCString;
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
    u64 modifiedNanoseconds;
    u32 permissions;
}

struct OpenOptions
{
    bool read = true;
    bool write;
    bool create;
    bool truncate;
    bool append;
    bool exclusive;
    u16 permissions = 0x180; // POSIX 0600
}

struct IoResult
{
    OsError error;
    size_t transferred;

    bool complete(size_t requested) const pure nothrow @safe @nogc
    {
        return error.succeeded && transferred == requested;
    }
}

struct File
{
    private int descriptor_ = -1;

    @disable this(this);

    ~this() nothrow @nogc
    {
        deinit();
    }

    void deinit() nothrow @nogc
    {
        version (linux)
        {
            import core.sys.posix.unistd : close;

            if (descriptor_ >= 0)
                close(descriptor_);
        }
        descriptor_ = -1;
    }

    bool valid() const pure nothrow @safe @nogc
    {
        return descriptor_ >= 0;
    }
}

OsError flush(File* file) nothrow @system @nogc
{
    require(file !is null && file.valid, "invalid File for flush");
    version (linux)
    {
        import core.sys.posix.unistd : fsync;

        return fsync(file.descriptor_) == 0 ? OsError.init : lastError();
    }
    else
        return unsupported();
}

OsError open(Path path, OpenOptions options, File* output) nothrow @system @nogc
{
    require(output !is null, "File output pointer is null");
    output.deinit();
    if (!valid(options))
        return OsError(OsErrorKind.invalidArgument, 0);
    version (linux)
    {
        import core.sys.posix.fcntl : O_APPEND, O_CREAT, O_EXCL, O_RDONLY,
            O_RDWR, O_TRUNC, O_WRONLY, open;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
        int flags = options.read && options.write ? O_RDWR : options.write ? O_WRONLY : O_RDONLY;
        if (options.create)
            flags |= O_CREAT;
        if (options.truncate)
            flags |= O_TRUNC;
        if (options.append)
            flags |= O_APPEND;
        if (options.exclusive)
            flags |= O_EXCL;
        const descriptor = open(native.checkedCString, flags, cast(uint) options.permissions);
        if (descriptor < 0)
            return lastError();
        output.descriptor_ = descriptor;
        return OsError.init;
    }
    else
        return unsupported();
}

private bool valid(OpenOptions options) pure nothrow @safe @nogc
{
    if (!options.read && !options.write)
        return false;
    if ((options.truncate || options.append) && !options.write)
        return false;
    if (options.exclusive && !options.create)
        return false;
    return true;
}

IoResult readSome(File* file, u8[] output) nothrow @system @nogc
{
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

IoResult writeSome(File* file, scope const(u8)[] input) nothrow @system @nogc
{
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

IoResult readAll(File* file, u8[] output) nothrow @system @nogc
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

IoResult writeAll(File* file, scope const(u8)[] input) nothrow @system @nogc
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

OsError metadata(File* file, FileMetadata* output) nothrow @system @nogc
{
    require(file !is null && file.valid, "invalid File for metadata");
    require(output !is null, "FileMetadata output pointer is null");
    version (linux)
    {
        import core.sys.posix.sys.stat : fstat, stat_t;

        stat_t native;
        if (fstat(file.descriptor_, &native) != 0)
            return lastError();
        *output = convert(native);
        return OsError.init;
    }
    else
        return unsupported();
}

OsError metadata(Path path, bool followLinks, FileMetadata* output) nothrow @system @nogc
{
    require(output !is null, "FileMetadata output pointer is null");
    version (linux)
    {
        import core.sys.posix.sys.stat : lstat, stat, stat_t;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf nativePath = StringBuf.fromString(scratch.allocator, path.view);
        stat_t native;
        const state = followLinks ? stat(nativePath.checkedCString, &native) : lstat(
                nativePath.checkedCString, &native);
        if (state != 0)
            return lastError();
        *output = convert(native);
        return OsError.init;
    }
    else
        return unsupported();
}

version (linux) private FileMetadata convert(ref const(NativeStat) native) pure nothrow @system @nogc
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
    return FileMetadata(type, cast(u64) native.st_size,
            cast(u64) native.st_mtime * 1_000_000_000UL, cast(u32) native.st_mode & 0xFFF);
}

OsError readEntireFile(Path path, ref Array!u8 output) nothrow @system @nogc
{
    output.clear();
    File file;
    OsError error = open(path, OpenOptions.init, &file);
    if (error.failed)
        return error;
    FileMetadata information;
    error = (&file).metadata(&information);
    if (error.failed)
        return error;
    if (information.size > size_t.max || !output.tryResize(cast(size_t) information.size))
        return OsError(OsErrorKind.system, 0);
    const result = (&file).readAll(output.slice);
    if (result.error.failed || result.transferred != output.length)
    {
        output.clear();
        return result.error.failed ? result.error : OsError(OsErrorKind.system, 0);
    }
    return OsError.init;
}

OsError writeEntireFile(Path path, scope const(u8)[] input, bool exclusive = false) nothrow @system @nogc
{
    OpenOptions options;
    options.read = false;
    options.write = true;
    options.create = true;
    options.truncate = true;
    options.exclusive = exclusive;
    File file;
    OsError error = open(path, options, &file);
    if (error.failed)
        return error;
    const result = (&file).writeAll(input);
    return result.complete(input.length) ? OsError.init : result.error.failed
        ? result.error : OsError(OsErrorKind.system, 0);
}

OsError copyFile(Path source, Path destination, ref Array!u8 buffer, bool exclusive = false) nothrow @system @nogc
{
    OsError error = readEntireFile(source, buffer);
    if (error.failed)
        return error;
    return writeEntireFile(destination, buffer.slice, exclusive);
}
