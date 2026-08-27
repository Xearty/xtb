module xtb.os.internal.unsupported.pipe;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.os.internal.pipe : NativePipeReadResult, NativePipeReadState,
    NativePipeWriteResult, NativePipeWriteState;
import xtb.types : u8;

package(xtb.os) OsError createPipeImpl(bool, bool, int*, int*) pure @safe
{
    return unsupported();
}

package(xtb.os) OsError closeDescriptorImpl(int) pure @safe
{
    return unsupported();
}

package(xtb.os) NativePipeReadResult readSomeImpl(int, u8[]) pure @safe
{
    return NativePipeReadResult(unsupported(), 0, NativePipeReadState.data);
}

package(xtb.os) NativePipeWriteResult writeSomeImpl(
    int,
    scope const(u8)[],
) pure @safe
{
    return NativePipeWriteResult(unsupported(), 0, NativePipeWriteState.data);
}
