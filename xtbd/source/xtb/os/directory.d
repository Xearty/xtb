module xtb.os.directory;

import xtb.core.panic : require;
import xtb.core.memory : Allocator;
import xtb.core.string : String, StringBuf, append, checkedCString, clear, fromCString;
import xtb.core.thread_context : ScratchScope;
import xtb.core.types : u8;
import xtb.os.error : OsError, OsErrorKind, lastError, unsupported;
import xtb.os.file : FileType;
import xtb.os.path : Path, appendComponent;

enum Access : ubyte
{
    exists,
    read,
    write,
    execute,
}

alias DirectoryVisitor = bool function(Path path, FileType type, void* context) nothrow @nogc;

enum DirectoryStatus : ubyte
{
    entry,
    finished,
    failed,
}

struct DirectoryEntry
{
    /// Borrowed until the iterator advances or closes.
    String name;
    FileType type;
}

struct DirectoryResult
{
    DirectoryStatus status;
    OsError error;
}

struct DirectoryIterator
{
    version (linux)
    {
        import core.sys.posix.dirent : DIR;

        private DIR* directory_;
    }

    @disable this(this);

    ~this() nothrow @nogc
    {
        deinit();
    }

    void deinit() nothrow @nogc
    {
        version (linux)
        {
            import core.sys.posix.dirent : closedir;

            if (directory_ !is null)
                closedir(directory_);
            directory_ = null;
        }
    }

    bool valid() const pure nothrow @safe @nogc
    {
        version (linux)
            return directory_ !is null;
        else
            return false;
    }
}

OsError openDirectory(Path path, DirectoryIterator* output) nothrow @system @nogc
{
    require(output !is null, "DirectoryIterator output pointer is null");
    output.deinit();
    version (linux)
    {
        import core.sys.posix.dirent : opendir;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
        output.directory_ = opendir(native.checkedCString);
        return output.directory_ is null ? lastError() : OsError.init;
    }
    else
        return unsupported();
}

DirectoryResult next(DirectoryIterator* iterator, DirectoryEntry* output) nothrow @system @nogc
{
    require(iterator !is null && iterator.valid, "invalid DirectoryIterator");
    require(output !is null, "DirectoryEntry output pointer is null");
    version (linux)
    {
        import core.stdc.errno : errno;
        import core.sys.posix.dirent : readdir;

        for (;;)
        {
            errno = 0;
            const native = readdir(iterator.directory_);
            if (native is null)
                return errno == 0 ? DirectoryResult(DirectoryStatus.finished, OsError.init) : DirectoryResult(
                        DirectoryStatus.failed, lastError());
            String name = fromCString(native.d_name.ptr);
            if (name == "." || name == "..")
                continue;
            output.name = name;
            output.type = fromDirectoryType(native.d_type);
            return DirectoryResult(DirectoryStatus.entry, OsError.init);
        }
    }
    else
        return DirectoryResult(DirectoryStatus.failed, unsupported());
}

version (linux) private FileType fromDirectoryType(ubyte value) pure nothrow @safe @nogc
{
    import core.sys.posix.dirent : DT_BLK, DT_CHR, DT_DIR, DT_FIFO, DT_LNK, DT_REG, DT_SOCK;

    switch (value)
    {
    case DT_REG:
        return FileType.regular;
    case DT_DIR:
        return FileType.directory;
    case DT_LNK:
        return FileType.symbolicLink;
    case DT_CHR:
        return FileType.characterDevice;
    case DT_BLK:
        return FileType.blockDevice;
    case DT_FIFO:
        return FileType.fifo;
    case DT_SOCK:
        return FileType.socket;
    default:
        return FileType.unknown;
    }
}

OsError createDirectory(Path path, uint permissions = 0x1C0) // POSIX 0700
nothrow @system @nogc
{
    version (linux)
    {
        import core.sys.posix.sys.stat : mkdir;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
        return mkdir(native.checkedCString, permissions) == 0 ? OsError.init : lastError();
    }
    else
        return unsupported();
}

OsError removeEmptyDirectory(Path path) nothrow @system @nogc
{
    version (linux)
    {
        import core.sys.posix.unistd : rmdir;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
        return rmdir(native.checkedCString) == 0 ? OsError.init : lastError();
    }
    else
        return unsupported();
}

OsError removeFile(Path path) nothrow @system @nogc
{
    version (linux)
    {
        import core.sys.posix.unistd : unlink;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
        return unlink(native.checkedCString) == 0 ? OsError.init : lastError();
    }
    else
        return unsupported();
}

OsError rename(Path source, Path destination) nothrow @system @nogc
{
    version (linux)
    {
        import core.stdc.stdio : rename;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf from = StringBuf.fromString(scratch.allocator, source.view);
        StringBuf to = StringBuf.fromString(scratch.allocator, destination.view);
        return rename(from.checkedCString, to.checkedCString) == 0 ? OsError.init : lastError();
    }
    else
        return unsupported();
}

OsError currentDirectory(ref StringBuf output) nothrow @system @nogc
{
    output.clear();
    version (linux)
    {
        import core.sys.posix.unistd : getcwd;

        char[4096] buffer;
        if (getcwd(buffer.ptr, buffer.length) is null)
            return lastError();
        output.append(fromCString(buffer.ptr));
        return OsError.init;
    }
    else
        return unsupported();
}

OsError executablePath(ref StringBuf output) nothrow @system @nogc
{
    output.clear();
    version (linux)
    {
        import core.sys.posix.unistd : readlink;

        char[4096] buffer;
        const amount = readlink("/proc/self/exe".ptr, buffer.ptr, buffer.length);
        if (amount < 0)
            return lastError();
        if (cast(size_t) amount == buffer.length)
            return OsError(OsErrorKind.system, 0);
        output.append(buffer[0 .. cast(size_t) amount]);
        return OsError.init;
    }
    else
        return unsupported();
}

OsError queryAccess(Path path, Access requested, bool* output) nothrow @system @nogc
{
    require(output !is null, "access output pointer is null");
    *output = false;
    version (linux)
    {
        import core.sys.posix.unistd : F_OK, R_OK, W_OK, X_OK, access;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
        int mode;
        final switch (requested)
        {
        case Access.exists:
            mode = F_OK;
            break;
        case Access.read:
            mode = R_OK;
            break;
        case Access.write:
            mode = W_OK;
            break;
        case Access.execute:
            mode = X_OK;
            break;
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
    else
        return unsupported();
}

OsError canonicalPath(Path path, ref StringBuf output) nothrow @system @nogc
{
    output.clear();
    version (linux)
    {
        import core.stdc.stdlib : free;
        import core.sys.posix.stdlib : realpath;

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
        char* resolved = realpath(native.checkedCString, null);
        if (resolved is null)
            return lastError();
        output.append(fromCString(resolved));
        free(resolved);
        return OsError.init;
    }
    else
        return unsupported();
}

OsError walkDirectory(Path root, Allocator* temporaryAllocator,
        DirectoryVisitor visitor, void* context = null, size_t maximumDepth = 256) nothrow @system @nogc
{
    require(temporaryAllocator !is null, "directory traversal requires a temporary allocator");
    require(visitor !is null, "directory visitor is null");
    bool keepGoing = true;
    return walk(root, temporaryAllocator, visitor, context, 0, maximumDepth, &keepGoing);
}

private OsError walk(Path root, Allocator* temporaryAllocator, DirectoryVisitor visitor,
        void* context, size_t depth, size_t maximumDepth, bool* keepGoing) nothrow @system @nogc
{
    if (depth > maximumDepth)
        return OsError(OsErrorKind.invalidArgument, 0);
    DirectoryIterator iterator;
    OsError error = openDirectory(root, &iterator);
    if (error.failed)
        return error;
    DirectoryEntry entry;
    for (;;)
    {
        const result = (&iterator).next(&entry);
        if (result.status == DirectoryStatus.finished)
            return OsError.init;
        if (result.status == DirectoryStatus.failed)
            return result.error;

        StringBuf full = StringBuf.fromString(temporaryAllocator, root.view);
        full.appendComponent(Path.fromString(entry.name));
        const path = Path.fromString(full.view);
        FileType type = entry.type;
        if (type == FileType.unknown)
        {
            import xtb.os.file : FileMetadata, metadata;

            FileMetadata information;
            error = metadata(path, false, &information);
            if (error.failed)
                return error;
            type = information.type;
        }
        if (!visitor(path, type, context))
        {
            *keepGoing = false;
            return OsError.init;
        }
        if (type == FileType.directory)
        {
            error = walk(path, temporaryAllocator, visitor, context, depth + 1,
                    maximumDepth, keepGoing);
            if (error.failed)
                return error;
            if (!*keepGoing)
                return OsError.init;
        }
    }
}
