module xtb.fs.directory;

nothrow @nogc:

import core.attribute;

import xtb.data_struct;
import xtb.fs.file;
import xtb.fs.internal.directory;
import xtb.fs.internal.file;
import xtb.fs.path;
import xtb.memory;
import xtb.os.error;
import xtb.panic;
import xtb.string;
import xtb.types;

version (linux)
    private import backend = xtb.fs.internal.linux.directory;
else
    private import backend = xtb.fs.internal.unsupported.directory;

enum Access
{
    exists,
    read,
    write,
    execute,
}

/// Visits one directory entry. `path` and `context` are borrowed for the call only.
/// Returning `false` stops the traversal.
alias DirectoryVisitor = bool function(
    scope const Path path,
    FileType type,
    scope void* context,
) nothrow @nogc @system;

enum DirectoryStatus
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

@mustuse struct DirectoryResult
{
    DirectoryStatus status;
    OsError error;

    mixin DataStruct;
}

/// Owns an open native directory handle.
@mustuse struct DirectoryIterator
{
nothrow @nogc:

    /// Opaque owned native directory handle. `null` represents a closed iterator.
    /// A valid handle has single ownership and must be closed before replacement.
    void* directory;

    @disable this(this);
    @disable ref DirectoryIterator opAssign(DirectoryIterator source) return;

    /// Closes this iterator if it is open and reports any native close error.
    OsError close() @system
    {
        return backend.close_directory(&this.directory);
    }

    /// Explicitly ends this iterator's owning lifetime.
    ///
    /// Close errors are discarded; call `close` directly when they matter.
    void deinit() @system
    {
        cast(void) this.close();
    }

    bool valid() const pure @safe
    {
        return backend.directory_valid(this.directory);
    }

    /// Advances this iterator and writes the current entry to `output`.
    ///
    /// `output` must not be null. It is reset to `DirectoryEntry.init` before advancing.
    DirectoryResult next(scope DirectoryEntry* output) @system
    {
        require(this.valid, "invalid DirectoryIterator");
        require(output !is null, "DirectoryEntry output pointer is null");
        *output = DirectoryEntry.init;

        NativeDirectoryEntry native;
        const result = backend.next_directory(this.directory, &native);
        final switch (result.status)
        {
            case NativeDirectoryStatus.entry:
                output.name = native.name;
                output.type = from_native(native.type);
                return DirectoryResult(DirectoryStatus.entry, result.error);
            case NativeDirectoryStatus.finished:
                return DirectoryResult(DirectoryStatus.finished, result.error);
            case NativeDirectoryStatus.failed:
                return DirectoryResult(DirectoryStatus.failed, result.error);
        }
    }
}

/// Opens `path` into `output`.
///
/// `output` must not be null. Any iterator already owned by `output` is closed first.
/// On failure, `output` is left as `DirectoryIterator.init`.
OsError open_directory(scope const Path path, scope DirectoryIterator* output) @system
{
    require(output !is null, "DirectoryIterator output pointer is null");
    const cleanup_error = output.close();
    if (cleanup_error.failed) return cleanup_error;
    return backend.open_directory(path.view, &output.directory);
}

private FileType from_native(NativeFileType type) pure @safe
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

OsError create_directory(scope const Path path, u32 permissions = 0x1C0) @safe // POSIX 0700
{
    return backend.create_directory(path.view, permissions);
}

OsError remove_empty_directory(scope const Path path) @safe
{
    return backend.remove_empty_directory(path.view);
}

OsError remove_file(scope const Path path) @safe
{
    return backend.remove_file(path.view);
}

OsError rename(scope const Path source, scope const Path destination) @safe
{
    return backend.rename_path(source.view, destination.view);
}

/// Writes the current working directory to `output`.
///
/// `output` must not be null. It is cleared before the operation and remains empty on failure.
OsError current_directory(scope StringBuf* output) @system
{
    require(output !is null, "StringBuf output pointer is null");
    output.clear();
    return backend.current_directory(output);
}

/// Writes the current executable path to `output`.
///
/// `output` must not be null. It is cleared before the operation and remains empty on failure.
OsError executable_path(scope StringBuf* output) @system
{
    require(output !is null, "StringBuf output pointer is null");
    output.clear();
    return backend.executable_path(output);
}

/// Queries whether `path` has the requested access and writes the result to `output`.
///
/// `output` must not be null. It is initialized to `false` before the query.
OsError query_access(scope const Path path, Access requested, scope bool* output) @system
{
    require(output !is null, "access output pointer is null");
    *output = false;
    return backend.query_access(path.view, cast(u8) requested, output);
}

/// Writes the canonical form of `path` to `output`.
///
/// `output` must not be null. It is cleared before the operation and remains empty on failure.
OsError canonical_path(scope const Path path, scope StringBuf* output) @system
{
    require(output !is null, "StringBuf output pointer is null");
    output.clear();
    return backend.canonical_path(path.view, output);
}

OsError walk_directory(
    scope const Path root,
    scope Allocator* temporary_allocator,
    DirectoryVisitor visitor,
    scope void* context = null,
    usize maximum_depth = 256,
) @system
{
    require(temporary_allocator !is null, "directory traversal requires a temporary allocator");
    require(visitor !is null, "directory visitor is null");

    bool keep_going = true;
    return walk(root, temporary_allocator, visitor, context, 0, maximum_depth, &keep_going);
}

private OsError walk(
    scope const Path root,
    scope Allocator* temporary_allocator,
    DirectoryVisitor visitor,
    scope void* context,
    usize depth,
    usize maximum_depth,
    scope bool* keep_going,
) @system
{
    if (depth > maximum_depth) return OsError(OsErrorKind.invalidArgument, 0);

    DirectoryIterator iterator;
    OsError error = open_directory(root, &iterator);
    if (error.failed) return error;
    scope (exit) iterator.deinit();

    DirectoryEntry entry;
    StringBuf full = StringBuf.create(temporary_allocator);
    for (;;)
    {
        const result = iterator.next(&entry);
        if (result.status == DirectoryStatus.finished) return OsError.init;
        if (result.status == DirectoryStatus.failed) return result.error;

        full.clear();
        full.append(root.view);
        full.append_component(Path.from_string(entry.name));
        const path = Path.from_string(full.view);
        FileType type = entry.type;
        if (type == FileType.unknown)
        {
            FileMetadata information;
            error = metadata(path, SymlinkMode.no_follow, &information);
            if (error.failed) return error;
            type = information.type;
        }
        if (!visitor(path, type, context))
        {
            *keep_going = false;
            return OsError.init;
        }
        if (type == FileType.directory)
        {
            error = walk(
                path,
                temporary_allocator,
                visitor,
                context,
                depth + 1,
                maximum_depth,
                keep_going,
            );
            if (error.failed) return error;
            if (!*keep_going) return OsError.init;
        }
    }
}
