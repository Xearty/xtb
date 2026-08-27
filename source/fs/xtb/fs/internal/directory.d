module xtb.fs.internal.directory;

nothrow @nogc:

import xtb.os.error : OsError;
import xtb.string : String;
import xtb.fs.internal.file : NativeFileType;

enum NativeDirectoryStatus : ubyte
{
    entry,
    finished,
    failed,
}

struct NativeDirectoryEntry
{
    String name;
    NativeFileType type;
}

struct NativeDirectoryResult
{
    NativeDirectoryStatus status;
    OsError error;
}
