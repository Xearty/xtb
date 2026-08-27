module xtb.fs.memory_map;

nothrow @nogc:

import xtb.fs.path : Path;
import xtb.os.error : OsError;
import xtb.os.memory_map : MemoryMapping, mapFileReadOnly, osUnmap = unmap;

alias MappedFile = MemoryMapping;

/// Maps the complete file at `path` read-only.
OsError mapReadOnly(Path path, MappedFile* output) @system
{
    return mapFileReadOnly(path.view, output);
}

/// Explicitly releases a file-backed mapping.
OsError unmap(MappedFile* mapping) @system
{
    return osUnmap(mapping);
}
