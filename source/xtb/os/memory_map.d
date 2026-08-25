module xtb.os.memory_map;

nothrow @nogc:

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.types : u8;
import xtb.os.error : OsError;
import xtb.os.path : Path;

version (linux)
    private import backend = xtb.os.internal.linux.memory_map;
else
    private import backend = xtb.os.internal.unsupported.memory_map;

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
    return backend.unmapImpl(address, length);
}

OsError mapReadOnly(Path path, MappedFile* output) @system
{
    version (XTB_Checked)
        require(output !is null, "MappedFile output pointer is null");
    const cleanupError = unmap(output);
    if (cleanupError.failed)
        return cleanupError;

    void* address;
    size_t length;
    const error = backend.mapReadOnlyImpl(path, &address, &length);
    if (error.failed)
        return error;
    output.address_ = address;
    output.length_ = length;
    return OsError.init;
}
