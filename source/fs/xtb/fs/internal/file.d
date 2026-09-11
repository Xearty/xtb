module xtb.fs.internal.file;

nothrow @nogc:

import xtb.os.error;
import xtb.types;

enum NativeFileType : u8
{
    unknown,
    regular,
    directory,
    symbolic_link,
    character_device,
    block_device,
    fifo,
    socket,
}

struct NativeFileMetadata
{
    NativeFileType type;
    u64 size;
    i64 modified_nanoseconds;
    u32 permissions;
}

struct NativeIOResult
{
    OsError error;
    usize transferred;
}
