module xtb.fs.memory_map;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.fs.file : File, FileMetadata, OpenOptions, metadata, open;
import xtb.fs.path : Path;
import xtb.os.error : OsError, OsErrorKind;
import xtb.os.memory_map : MemoryMapping, osMapReadOnly = mapReadOnly, osUnmap = unmap;

alias MappedFile = MemoryMapping;

/// Maps the complete file at `path` read-only.
OsError mapReadOnly(Path path, MappedFile* output) @system
{
    version (XTB_Checked)
        require(output !is null, "MappedFile output pointer is null");

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

    return osMapReadOnly(
        file.nativeHandle,
        cast(size_t) information.size,
        output,
    );
}

/// Explicitly releases a file-backed mapping.
OsError unmap(MappedFile* mapping) @system
{
    return osUnmap(mapping);
}
