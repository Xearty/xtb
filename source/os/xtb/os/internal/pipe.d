module xtb.os.internal.pipe;

nothrow @nogc:

import xtb.os.error : OsError;

enum NativePipeReadState : ubyte
{
    data,
    endOfFile,
    wouldBlock,
}

struct NativePipeReadResult
{
    OsError error;
    size_t transferred;
    NativePipeReadState state;
}

enum NativePipeWriteState : ubyte
{
    data,
    peerClosed,
    wouldBlock,
}

struct NativePipeWriteResult
{
    OsError error;
    size_t transferred;
    NativePipeWriteState state;
}
