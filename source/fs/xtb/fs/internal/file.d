module xtb.fs.internal.file;

nothrow @nogc:

import xtb.os.error : OsError;
import xtb.types : i64, u32, u64;

enum NativeFileType : ubyte
{
    unknown,
    regular,
    directory,
    symbolicLink,
    characterDevice,
    blockDevice,
    fifo,
    socket,
}

struct NativeFileMetadata
{
    NativeFileType type;
    u64 size;
    i64 modifiedNanoseconds;
    u32 permissions;
}

struct NativeIoResult
{
    OsError error;
    size_t transferred;
}
