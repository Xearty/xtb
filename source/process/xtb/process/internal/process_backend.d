module xtb.process.internal.process_backend;

nothrow @nogc:

import xtb.os.error : OsError;
import xtb.os.handle : NativeHandle;
import xtb.types : u32, u64;

struct NativeProcessId
{
nothrow @nogc:

    private u64 value_;

    bool valid() const pure @safe
    {
        return value_ != 0;
    }

    package(xtb.process) static NativeProcessId fromNativeValue(
        u64 value,
    ) pure @safe
    {
        return NativeProcessId(value);
    }

    package(xtb.process) u64 nativeValue() const pure @safe
    {
        return value_;
    }
}

enum NativeRouteKind : ubyte
{
    inherited,
    nullDevice,
    handle,
    mergeWithStdout,
}

struct NativeRoute
{
    NativeRouteKind kind;
    NativeHandle handle;
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
    NativeHandle handle;
}

struct NativeWatchWaitResult
{
    OsError error;
    bool ready;
}

struct NativeActivityHandles
{
    NativeHandle stdin;
    NativeHandle stdout;
    NativeHandle stderr;
    NativeHandle process;
}
