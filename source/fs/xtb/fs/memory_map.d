module xtb.fs.memory_map;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.fs.file : File, FileMetadata, OpenOptions, metadata, open;
import xtb.fs.path : Path;
import xtb.os.error : OsError, OsErrorKind, unsupported;
import xtb.os.handle : NativeHandle;
import xtb.types : u8;

version (Posix)
{
    private import xtb.os.posix.memory_map : osMapReadOnly = mapReadOnly,
        osUnmap = unmap;
}
else
{
    private OsError osMapReadOnly(
        NativeHandle,
        size_t,
        void**,
    ) pure @safe
    {
        return unsupported();
    }

    private OsError osUnmap(void*, size_t) pure @safe
    {
        return unsupported();
    }
}

/// An owning read-only mapping of a complete filesystem file.
struct MappedFile
{
nothrow @nogc:

    private void* address_;
    private size_t length_;

    @disable this(this);
    @disable ref MappedFile opAssign(MappedFile source) return;

    /// Explicitly ends this mapping's owning lifetime.
    ///
    /// Unmap errors are discarded; call `unmap` directly when they matter.
    void deinit() @system
    {
        cast(void) unmap(&this);
    }

    const(u8)[] bytes() const return @system
    {
        return (cast(const(u8)*) address_)[0 .. length_];
    }

    bool empty() const pure @safe
    {
        return length_ == 0;
    }
}

/// Maps the complete file at `path` read-only.
OsError mapReadOnly(Path path, MappedFile* output) @system
{
    version (XTB_Checked)
        require(output !is null, "MappedFile output pointer is null");

    const cleanupError = unmap(output);
    if (cleanupError.failed)
        return cleanupError;

    File file;
    const openError = open(path, OpenOptions.init, &file);
    if (openError.failed)
        return openError;
    scope (exit)
        file.deinit();

    FileMetadata information;
    const metadataError = metadata(&file, &information);
    if (metadataError.failed)
        return metadataError;
    if (information.size > size_t.max)
        return OsError(OsErrorKind.invalidArgument, 0);
    if (information.size == 0)
        return OsError.init;

    void* address;
    const mappingError = osMapReadOnly(
        file.nativeHandle,
        cast(size_t) information.size,
        &address,
    );
    if (mappingError.failed)
        return mappingError;
    output.address_ = address;
    output.length_ = cast(size_t) information.size;
    return OsError.init;
}

/// Explicitly releases a file-backed mapping.
OsError unmap(MappedFile* mapping) @system
{
    version (XTB_Checked)
        require(mapping !is null, "MappedFile pointer is null");
    if (mapping.address_ is null)
    {
        mapping.length_ = 0;
        return OsError.init;
    }

    void* address = mapping.address_;
    size_t length = mapping.length_;
    mapping.address_ = null;
    mapping.length_ = 0;
    return osUnmap(address, length);
}
