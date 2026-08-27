module xtb.process.internal.process_backend;

nothrow @nogc:

import xtb.os.error : OsError;
import xtb.types : u32, u64;

enum NativeRouteKind : ubyte
{
    inherited,
    nullDevice,
    descriptor,
    mergeWithStdout,
}

struct NativeRoute
{
    NativeRouteKind kind;
    int descriptor = -1;
}

struct NativeSpawnOptions
{
    NativeRoute stdin;
    NativeRoute stdout;
    NativeRoute stderr;
    bool isolatedTree;
    bool clearSignalMask = true;
    const(char)* workingDirectory;
}

enum NativeWaitState : ubyte
{
    running,
    exited,
    signaled,
}

struct NativeWaitResult
{
    OsError error;
    NativeWaitState state;
    u32 code;
    bool coreDumped;
}

enum NativeSignal : ubyte
{
    terminate,
    kill,
}

enum NativeProcessWatchState : ubyte
{
    opened,
    unavailable,
}

struct NativeProcessWatchResult
{
    OsError error;
    NativeProcessWatchState state;
    int descriptor = -1;
}

struct NativeWatchWaitResult
{
    OsError error;
    bool ready;
}

struct NativeActivityDescriptors
{
    int stdinDescriptor = -1;
    int stdoutDescriptor = -1;
    int stderrDescriptor = -1;
    int processDescriptor = -1;
}
