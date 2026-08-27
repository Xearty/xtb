module xtb.fs.internal.unsupported.file;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.os.handle : NativeHandle;
import xtb.string : String;
import xtb.types : u8;
import xtb.fs.internal.file : NativeFileMetadata, NativeIoResult;

package(xtb.fs) OsError closeHandle(NativeHandle) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError flushHandle(NativeHandle) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError openFile(
    String,
    bool,
    bool,
    ubyte,
    bool,
    bool,
    bool,
    ushort,
    NativeHandle*,
) pure @safe
{
    return unsupported();
}

package(xtb.fs) NativeIoResult readSome(NativeHandle, u8[]) pure @safe
{
    return NativeIoResult(unsupported(), 0);
}

package(xtb.fs) NativeIoResult writeSome(
    NativeHandle,
    scope const(u8)[],
) pure @safe
{
    return NativeIoResult(unsupported(), 0);
}

package(xtb.fs) OsError handleMetadata(
    NativeHandle,
    NativeFileMetadata*,
) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError pathMetadata(String, bool, NativeFileMetadata*) pure @safe
{
    return unsupported();
}
