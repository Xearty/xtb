module xtb.os.internal.unsupported.pipe;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.os.handle : NativeHandle;
import xtb.os.internal.pipe : NativePipeReadResult, NativePipeReadState,
    NativePipeWriteResult, NativePipeWriteState;
import xtb.types : u8;

package(xtb.os) OsError createPipeImpl(
    bool,
    bool,
    NativeHandle*,
    NativeHandle*,
) pure @safe
{
    return unsupported();
}

package(xtb.os) OsError closeHandleImpl(NativeHandle) pure @safe
{
    return unsupported();
}

package(xtb.os) NativePipeReadResult readSomeImpl(
    NativeHandle,
    u8[],
) pure @safe
{
    return NativePipeReadResult(unsupported(), 0, NativePipeReadState.data);
}

package(xtb.os) NativePipeWriteResult writeSomeImpl(
    NativeHandle,
    scope const(u8)[],
) pure @safe
{
    return NativePipeWriteResult(unsupported(), 0, NativePipeWriteState.data);
}
