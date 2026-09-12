module xtb.fs.memory_map;

nothrow @nogc:

import core.attribute;

import xtb.fs.file;
import xtb.fs.path;
import xtb.os.error;
import xtb.os.handle;
import xtb.panic;
import xtb.types;

version (Posix)
    private import os_memory_map = xtb.os.posix.memory_map;
else
{
    private OsError os_map_read_only(NativeHandle, usize, scope void**) pure @safe
    {
        return unsupported();
    }

    private OsError os_unmap(void*, usize) pure @safe
    {
        return unsupported();
    }
}

/// An owning read-only mapping of a complete filesystem file.
@mustuse struct MappedFile
{
nothrow @nogc:

    /// Address of the owned mapping, or null when this value is unmapped.
    /// When non-null, it must identify a readable mapping of `length` bytes.
    void* address;

    /// Length in bytes of the mapping starting at `address`.
    usize length;

    @disable this(this);
    @disable ref MappedFile opAssign(MappedFile source) return;

    /// Explicitly ends this mapping's owning lifetime.
    ///
    /// Unmap errors are discarded; call `unmap` directly when they matter.
    void deinit() @system
    {
        cast(void) this.unmap();
    }

    /// Releases this file-backed mapping.
    ///
    /// This value must be unmapped or own the mapping described by `address` and `length`.
    OsError unmap() @system
    {
        if (this.address is null)
        {
            this.length = 0;
            return OsError.init;
        }

        void* address = this.address;
        const usize length = this.length;
        this.address = null;
        this.length = 0;

        version (Posix)
            return os_memory_map.unmap(address, length);
        else
            return os_unmap(address, length);
    }

    /// Returns a borrowed view of the mapped bytes.
    ///
    /// This value must be unmapped or own the mapping described by `address` and `length`.
    const(u8)[] bytes() const return scope @system
    {
        return (cast(const(u8)*) this.address)[0 .. this.length];
    }

    bool empty() const pure @safe
    {
        return this.length == 0;
    }
}

/// Maps the complete file at `path` read-only into `output`.
///
/// `output` must not be null and must point to `MappedFile.init` or a valid owned mapping.
/// Any mapping already owned by `output` is released first. On failure, `output` is left as
/// `MappedFile.init`.
OsError map_read_only(scope const Path path, scope MappedFile* output) @system
{
    require(output !is null, "MappedFile output pointer is null");

    const cleanup_error = output.unmap();
    if (cleanup_error.failed) return cleanup_error;

    File file;
    const open_error = open(path, OpenOptions.init, &file);
    scope (exit) file.deinit();
    if (open_error.failed) return open_error;

    FileMetadata information;
    const metadata_error = file.metadata(&information);
    if (metadata_error.failed) return metadata_error;
    if (information.size > usize.max) return OsError(OsErrorKind.invalidArgument, 0);
    if (information.size == 0) return OsError.init;

    void* address;
    version (Posix)
        const mapping_error = os_memory_map.mapReadOnly(
            file.handle,
            cast(usize) information.size,
            &address,
        );
    else
        const mapping_error = os_map_read_only(file.handle, cast(usize) information.size, &address);
    if (mapping_error.failed) return mapping_error;

    output.address = address;
    output.length = cast(usize) information.size;
    return OsError.init;
}
