module xtb.thread.internal.thread_unsupported;

nothrow @nogc:

import xtb.core.types : String;

alias NativeRawThreadFn = int function(void* context) nothrow @nogc;

struct NativeStableStartPacket
{
    NativeRawThreadFn function_;
    void* context;
}

enum NativeThreadStartErrorKind : ubyte
{
    unsupported,
    resourceExhausted,
    permissionDenied,
    invalidConfiguration,
    system,
}

struct NativeThreadHandle
{
    size_t value;
}

struct NativeThreadStartResult
{
    bool succeeded;
    NativeThreadHandle handle;
    NativeThreadStartErrorKind kind;
    int nativeCode;
}

struct NativeJoinResult
{
    bool succeeded;
    int status;
    int nativeCode;
}

enum NativeThreadNameErrorKind : ubyte
{
    unsupported,
    invalidName,
    tooLong,
    threadUnavailable,
    system,
}

struct NativeThreadNameResult
{
    bool succeeded;
    NativeThreadNameErrorKind kind;
    int nativeCode;
}

NativeThreadStartResult startRaw(
    size_t,
    NativeRawThreadFn,
    void*,
)
{
    return NativeThreadStartResult(
        false,
        NativeThreadHandle.init,
        NativeThreadStartErrorKind.unsupported,
        0,
    );
}

NativeThreadStartResult startStable(
    size_t,
    NativeStableStartPacket*,
)
{
    return NativeThreadStartResult(
        false,
        NativeThreadHandle.init,
        NativeThreadStartErrorKind.unsupported,
        0,
    );
}

NativeJoinResult joinThread(NativeThreadHandle)
{
    return NativeJoinResult(false, 0, 0);
}

int detachThread(NativeThreadHandle)
{
    return -1;
}

bool isCurrentThread(NativeThreadHandle)
{
    return false;
}

ulong threadIdValue(NativeThreadHandle)
{
    return 0;
}

ulong currentThreadIdValue()
{
    return 0;
}

void yieldThreadBackend()
{
}

uint hardwareConcurrencyBackend()
{
    return 0;
}

NativeThreadNameResult setCurrentThreadNameBackend(String)
{
    return NativeThreadNameResult(
        false,
        NativeThreadNameErrorKind.unsupported,
        0,
    );
}

NativeThreadNameResult setThreadNameBackend(
    NativeThreadHandle,
    String,
)
{
    return NativeThreadNameResult(
        false,
        NativeThreadNameErrorKind.unsupported,
        0,
    );
}
