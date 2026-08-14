module xtb.os.directory;

nothrow @nogc:

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.array;
import xtb.core.memory : Allocator;
import xtb.core.string;
import xtb.core.thread_context : ScratchScope;
import xtb.core.types : u8;
import xtb.os.error : OsError, OsErrorKind, lastError, unsupported;
import xtb.os.file : FileMetadata, FileType, SymlinkMode, metadata;
import xtb.os.path : Path, appendComponent;

enum Access : ubyte
{
    exists,
    read,
    write,
    execute,
}

alias DirectoryVisitor = bool function(Path path, FileType type, void* context);

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
nothrow @nogc:

    version (linux)
    {
        import core.sys.posix.dirent : DIR;

        private DIR* directory_;
    }

    @disable this(this);
    @disable ref DirectoryIterator opAssign(DirectoryIterator source) return;

    /// Explicitly ends this iterator's owning lifetime.
    ///
    /// Close errors are discarded; call `close` directly when they matter.
    void deinit() @system
    {
        cast(void) close(&this);
    }

    bool valid() const pure @safe
    {
        version (linux)
            return directory_ !is null;
        else
            return false;
    }
}

OsError close(DirectoryIterator* iterator) @system
{
    version (XTB_Checked)
        require(iterator !is null, "DirectoryIterator pointer is null");
    version (linux)
    {
        import core.sys.posix.dirent : closedir;

        if (iterator.directory_ is null)
            return OsError.init;
        auto directory = iterator.directory_;
        iterator.directory_ = null;
        return closedir(directory) == 0 ? OsError.init : lastError();
    }
    else
        return OsError.init;
}

OsError openDirectory(Path path, DirectoryIterator* output) @system
{
    version (XTB_Checked)
        require(output !is null, "DirectoryIterator output pointer is null");
    const cleanupError = close(output);
    if (cleanupError.failed)
        return cleanupError;
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

DirectoryResult next(DirectoryIterator* iterator, DirectoryEntry* output) @system
{
    version (XTB_Checked)
    {
        require(iterator !is null && iterator.valid, "invalid DirectoryIterator");
        require(output !is null, "DirectoryEntry output pointer is null");
    }
    *output = DirectoryEntry.init;
    version (linux)
    {
        import core.stdc.errno : errno;
        import core.sys.posix.dirent : readdir;

        for (;;)
        {
            errno = 0;
            const native = readdir(iterator.directory_);
            if (native is null)
                return errno == 0 ? DirectoryResult(DirectoryStatus.finished, OsError.init)
                    : DirectoryResult(
                        DirectoryStatus.failed, lastError());
            const checked = fromCString(native.d_name.ptr);
            if (checked.failed)
                return DirectoryResult(
                    DirectoryStatus.failed,
                    OsError(OsErrorKind.invalidData, 0),
                );
            const name = checked.value;
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

version (linux) private FileType fromDirectoryType(ubyte value) pure @safe
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

OsError createDirectory(Path path, uint permissions = 0x1C0)  // POSIX 0700
@system
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

OsError removeEmptyDirectory(Path path) @system
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

OsError removeFile(Path path) @system
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

OsError rename(Path source, Path destination) @system
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

OsError currentDirectory(ref StringBuf output) @system
{
    output.clear();
    version (linux)
    {
        import core.stdc.stdlib : free;
        import core.sys.posix.unistd : getcwd;

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
    else
        return unsupported();
}

OsError executablePath(ref StringBuf output) @system
{
    output.clear();
    version (linux)
    {
        import core.sys.posix.unistd : readlink;

        ScratchScope scratch = ScratchScope.acquire(output.allocator);
        Array!char buffer = Array!char.withLength(scratch.allocator, 256);
        for (;;)
        {
            const amount = readlink("/proc/self/exe".ptr, buffer.slice.ptr, buffer.length);
            if (amount < 0)
                return lastError();
            if (cast(size_t) amount < buffer.length)
            {
                const checked = (cast(const(ubyte)[])
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
    else
        return unsupported();
}

OsError queryAccess(Path path, Access requested, bool* output) @system
{
    version (XTB_Checked)
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

OsError canonicalPath(Path path, ref StringBuf output) @system
{
    output.clear();
    version (linux)
    {
        import core.stdc.stdlib : free;
        import core.sys.posix.stdlib : realpath;

        ScratchScope scratch = ScratchScope.acquire(output.allocator);
        StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
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
    else
        return unsupported();
}

OsError walkDirectory(Path root, Allocator* temporaryAllocator,
    DirectoryVisitor visitor, void* context = null, size_t maximumDepth = 256) @system
{
    version (XTB_Checked)
    {
        require(temporaryAllocator !is null, "directory traversal requires a temporary allocator");
        require(visitor !is null, "directory visitor is null");
    }
    bool keepGoing = true;
    return walk(root, temporaryAllocator, visitor, context, 0, maximumDepth, &keepGoing);
}

private OsError walk(Path root, Allocator* temporaryAllocator, DirectoryVisitor visitor,
    void* context, size_t depth, size_t maximumDepth, bool* keepGoing) @system
{
    if (depth > maximumDepth)
        return OsError(OsErrorKind.invalidArgument, 0);
    DirectoryIterator iterator;
    OsError error = openDirectory(root, &iterator);
    if (error.failed)
        return error;
    scope (exit)
        iterator.deinit();
    DirectoryEntry entry;
    StringBuf full = StringBuf.create(temporaryAllocator);
    for (;;)
    {
        const result = (&iterator).next(&entry);
        if (result.status == DirectoryStatus.finished)
            return OsError.init;
        if (result.status == DirectoryStatus.failed)
            return result.error;

        full.clear();
        full.append(root.view);
        full.appendComponent(Path.fromString(entry.name));
        const path = Path.fromString(full.view);
        FileType type = entry.type;
        if (type == FileType.unknown)
        {
            FileMetadata information;
            error = metadata(path, SymlinkMode.noFollow, &information);
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
