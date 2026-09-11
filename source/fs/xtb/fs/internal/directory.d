module xtb.fs.internal.directory;

nothrow @nogc:

import core.attribute;

import xtb.fs.internal.file;
import xtb.os.error;
import xtb.types;

package(xtb.fs) enum NativeDirectoryStatus
{
    entry,
    finished,
    failed,
}

package(xtb.fs) struct NativeDirectoryEntry
{
    // Borrowed from native directory storage until the iterator advances or closes.
    String name;
    NativeFileType type;
}

@mustuse package(xtb.fs) struct NativeDirectoryResult
{
    NativeDirectoryStatus status;
    OsError error;
}
