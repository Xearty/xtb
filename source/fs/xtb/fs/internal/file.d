module xtb.fs.internal.file;

nothrow @nogc:

import xtb.os.error;
import xtb.types;

package(xtb.fs) enum NativeFileType : u8
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

package(xtb.fs) struct NativeFileMetadata
{
    NativeFileType type;
    u64 size;
    i64 modified_nanoseconds;
    u32 permissions;
}

package(xtb.fs) struct NativeIOResult
{
    OsError error;
    usize transferred;
}
