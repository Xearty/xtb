module xtb.fs.internal.unsupported.file;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.string : String;
import xtb.types : u8;
import xtb.fs.internal.file : NativeFileMetadata, NativeIoResult;

package(xtb.fs) OsError closeDescriptor(int) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError flushDescriptor(int) pure @safe
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
    int*,
) pure @safe
{
    return unsupported();
}

package(xtb.fs) NativeIoResult readSome(int, u8[]) pure @safe
{
    return NativeIoResult(unsupported(), 0);
}

package(xtb.fs) NativeIoResult writeSome(int, scope const(u8)[]) pure @safe
{
    return NativeIoResult(unsupported(), 0);
}

package(xtb.fs) OsError descriptorMetadata(int, NativeFileMetadata*) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError pathMetadata(String, bool, NativeFileMetadata*) pure @safe
{
    return unsupported();
}
