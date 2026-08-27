module xtb.os.internal.unsupported.pipe;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.os.handle : NativeHandle;
import xtb.types : u8;

package(xtb.os) enum PipeReadState : ubyte
{
    data,
    endOfFile,
    wouldBlock,
}

package(xtb.os) struct PipeReadResult
{
    OsError error;
    size_t transferred;
    PipeReadState state;
}

package(xtb.os) enum PipeWriteState : ubyte
{
    data,
    peerClosed,
    wouldBlock,
}

package(xtb.os) struct PipeWriteResult
{
    OsError error;
    size_t transferred;
    PipeWriteState state;
}

package(xtb.os) OsError createPipe(
    bool,
    bool,
    NativeHandle*,
    NativeHandle*,
) pure @safe
{
    return unsupported();
}

package(xtb.os) OsError closeHandle(NativeHandle) pure @safe
{
    return unsupported();
}

package(xtb.os) PipeReadResult readSome(
    NativeHandle,
    u8[],
) pure @safe
{
    return PipeReadResult(unsupported(), 0, PipeReadState.data);
}

package(xtb.os) PipeWriteResult writeSome(
    NativeHandle,
    scope const(u8)[],
) pure @safe
{
    return PipeWriteResult(unsupported(), 0, PipeWriteState.data);
}
