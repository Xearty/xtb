module xtb.fs.internal.unsupported.file;

nothrow @nogc:

import xtb.fs.internal.file;
import xtb.os.error;
import xtb.os.handle;
import xtb.types;

package(xtb.fs) OsError close_handle(NativeHandle) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError flush_handle(NativeHandle) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError open_file(
    scope String,
    bool,
    bool,
    u8,
    bool,
    bool,
    bool,
    u16,
    scope NativeHandle*,
) pure @safe
{
    return unsupported();
}

package(xtb.fs) NativeIOResult read_some(NativeHandle, scope u8[]) pure @safe
{
    return NativeIOResult(unsupported(), 0);
}

package(xtb.fs) NativeIOResult write_some(NativeHandle, scope const(u8)[]) pure @safe
{
    return NativeIOResult(unsupported(), 0);
}

package(xtb.fs) OsError handle_metadata(NativeHandle, scope NativeFileMetadata*) pure @safe
{
    return unsupported();
}

package(xtb.fs) OsError path_metadata(scope String, bool, scope NativeFileMetadata*) pure @safe
{
    return unsupported();
}
