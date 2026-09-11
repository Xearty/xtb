module xtb.fs.directory;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.memory : Allocator;
import xtb.string;
import xtb.types : String;
import xtb.os.error : OsError, OsErrorKind;
import xtb.fs.file : FileMetadata, FileType, SymlinkMode, metadata;
import xtb.fs.path : Path, append_component;
import xtb.fs.internal.directory : NativeDirectoryEntry, NativeDirectoryStatus;
import xtb.fs.internal.file : NativeFileType;

version (linux)
    private import backend = xtb.fs.internal.linux.directory;
else
    private import backend = xtb.fs.internal.unsupported.directory;

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

    private void* directory_;

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
        return backend.directory_valid(directory_);
    }
}

OsError close(DirectoryIterator* iterator) @system
{
    version (XTB_Checked)
        require(iterator !is null, "DirectoryIterator pointer is null");
    return backend.close_directory(&iterator.directory_);
}

OsError openDirectory(Path path, DirectoryIterator* output) @system
{
    version (XTB_Checked)
        require(output !is null, "DirectoryIterator output pointer is null");
    const cleanupError = close(output);
    if (cleanupError.failed)
        return cleanupError;
    return backend.open_directory(path.view, &output.directory_);
}

DirectoryResult next(DirectoryIterator* iterator, DirectoryEntry* output) @system
{
    version (XTB_Checked)
    {
        require(iterator !is null && iterator.valid, "invalid DirectoryIterator");
        require(output !is null, "DirectoryEntry output pointer is null");
    }
    *output = DirectoryEntry.init;
    NativeDirectoryEntry native;
    const result = backend.next_directory(iterator.directory_, &native);
    final switch (result.status)
    {
        case NativeDirectoryStatus.entry:
            output.name = native.name;
            output.type = fromNative(native.type);
            return DirectoryResult(DirectoryStatus.entry, result.error);
        case NativeDirectoryStatus.finished:
            return DirectoryResult(DirectoryStatus.finished, result.error);
        case NativeDirectoryStatus.failed:
            return DirectoryResult(DirectoryStatus.failed, result.error);
    }
}

private FileType fromNative(NativeFileType type) pure @safe
{
    final switch (type)
    {
        case NativeFileType.unknown:
            return FileType.unknown;
        case NativeFileType.regular:
            return FileType.regular;
        case NativeFileType.directory:
            return FileType.directory;
        case NativeFileType.symbolic_link:
            return FileType.symbolic_link;
        case NativeFileType.character_device:
            return FileType.character_device;
        case NativeFileType.block_device:
            return FileType.block_device;
        case NativeFileType.fifo:
            return FileType.fifo;
        case NativeFileType.socket:
            return FileType.socket;
    }
}

OsError createDirectory(Path path, uint permissions = 0x1C0)  // POSIX 0700
@system
{
    return backend.create_directory(path.view, permissions);
}

OsError removeEmptyDirectory(Path path) @system
{
    return backend.remove_empty_directory(path.view);
}

OsError removeFile(Path path) @system
{
    return backend.remove_file(path.view);
}

OsError rename(Path source, Path destination) @system
{
    return backend.rename_path(source.view, destination.view);
}

OsError currentDirectory(ref StringBuf output) @system
{
    output.clear();
    return backend.current_directory(&output);
}

OsError executablePath(ref StringBuf output) @system
{
    output.clear();
    return backend.executable_path(&output);
}

OsError queryAccess(Path path, Access requested, bool* output) @system
{
    version (XTB_Checked)
        require(output !is null, "access output pointer is null");
    *output = false;
    return backend.query_access(path.view, cast(ubyte) requested, output);
}

OsError canonicalPath(Path path, ref StringBuf output) @system
{
    output.clear();
    return backend.canonical_path(path.view, &output);
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
        full.append_component(Path.from_string(entry.name));
        const path = Path.from_string(full.view);
        FileType type = entry.type;
        if (type == FileType.unknown)
        {
            FileMetadata information;
            error = metadata(path, SymlinkMode.no_follow, &information);
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
