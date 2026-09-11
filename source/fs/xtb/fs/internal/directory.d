module xtb.fs.internal.directory;

nothrow @nogc:

import xtb.fs.internal.file;
import xtb.os.error;
import xtb.types;

package(xtb.fs) enum NativeDirectoryStatus : u8
{
    entry,
    finished,
    failed,
}

package(xtb.fs) struct NativeDirectoryEntry
{
    String name;
    NativeFileType type;
}

package(xtb.fs) struct NativeDirectoryResult
{
    NativeDirectoryStatus status;
    OsError error;
}
