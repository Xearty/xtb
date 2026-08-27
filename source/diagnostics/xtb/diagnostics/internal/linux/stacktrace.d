module xtb.diagnostics.internal.linux.stacktrace;

nothrow @nogc:

import core.stdc.string : memcpy, strlen;
import xtb.diagnostics.stacktrace : StackFrame, StackTrace;
import xtb.os.linux.execinfo : backtrace;
import xtb.os.linux.dynamic_link : Dl_info, dladdr;
import xtb.string : String;

private struct BacktraceState;

private alias ErrorCallback = extern (C) void function(
    void* data,
    const(char)* message,
    int errorNumber,
);
private alias FullCallback = extern (C) int function(
    void* data,
    size_t programCounter,
    const(char)* filename,
    int line,
    const(char)* functionName,
);
private alias SimpleCallback = extern (C) int function(
    void* data,
    size_t programCounter,
);

extern (C) private BacktraceState* backtrace_create_state(
    const(char)* filename,
    int threaded,
    ErrorCallback errorCallback,
    void* data,
);
extern (C) private int backtrace_full(
    BacktraceState* state,
    int skip,
    FullCallback callback,
    ErrorCallback errorCallback,
    void* data,
);
extern (C) private int backtrace_simple(
    BacktraceState* state,
    int skip,
    SimpleCallback callback,
    ErrorCallback errorCallback,
    void* data,
);

struct StackTraceBackendContext
{
nothrow @nogc:

    private BacktraceState* state_;

    bool available() const pure @safe
    {
        return state_ !is null;
    }

    static StackTraceBackendContext create(
        const(char)* permanentExecutablePath,
        bool threadSafe,
    )
    {
        StackTraceBackendContext result;
        result.state_ = backtrace_create_state(
            permanentExecutablePath,
            threadSafe ? 1 : 0,
            &creationError,
            null,
        );
        return result;
    }
}

private extern (C) void creationError(void*, const(char)*, int)
{
}

private struct CaptureState
{
nothrow @nogc:

    StackFrame[] frames;
    char[] text;
    size_t frameCount;
    size_t textWritten;
    size_t textRequired;
    bool framesTruncated;
    bool textTruncated;
    bool backendError;
}

private String copyText(ref CaptureState state, const(char)* value)
@system
{
    if (value is null)
        return null;
    const length = strlen(value);
    if (length == 0)
        return null;
    if (length > size_t.max - state.textRequired)
    {
        state.textRequired = size_t.max;
        state.textTruncated = true;
        return null;
    }
    state.textRequired += length;
    if (length > state.text.length - state.textWritten)
    {
        state.textTruncated = true;
        return null;
    }
    char* destination = state.text.ptr + state.textWritten;
    memcpy(destination, value, length);
    state.textWritten += length;
    return destination[0 .. length];
}

private extern (C) int collectFrame(
    void* data,
    size_t programCounter,
    const(char)* filename,
    int line,
    const(char)* functionName,
)
{
    CaptureState* state = cast(CaptureState*) data;
    if (programCounter == size_t.max)
        return 1;
    if (state.frameCount == state.frames.length)
    {
        state.framesTruncated = true;
        return 1;
    }

    const(char)* resolvedFilename = filename;
    const(char)* resolvedFunctionName = functionName;
    if (resolvedFilename is null || resolvedFunctionName is null)
    {
        Dl_info information;
        if (dladdr(cast(const(void)*) programCounter, &information) != 0)
        {
            if (resolvedFilename is null)
                resolvedFilename = information.dli_fname;
            if (resolvedFunctionName is null)
                resolvedFunctionName = information.dli_sname;
        }
    }
    StackFrame* frame = &state.frames[state.frameCount++];
    frame.programCounter = programCounter;
    frame.filename = copyText(*state, resolvedFilename);
    frame.functionName = copyText(*state, resolvedFunctionName);
    frame.line = line > 0 ? cast(uint) line : 0;
    return 0;
}

private extern (C) void captureError(
    void* data,
    const(char)*,
    int,
)
{
    CaptureState* state = cast(CaptureState*) data;
    state.backendError = true;
}

private extern (C) int collectSimpleFrame(
    void* data,
    size_t programCounter,
)
{
    Dl_info information;
    const found = dladdr(cast(const(void)*) programCounter, &information);
    return collectFrame(
        data,
        programCounter,
        found == 0 ? null : information.dli_fname,
        0,
        found == 0 ? null : information.dli_sname,
    );
}

private void collectExecInfo(ref CaptureState state, uint skipFrames)
{
    void*[128] addresses;
    const count = backtrace(addresses.ptr, cast(int) addresses.length);
    size_t begin = cast(size_t) skipFrames;
    if (begin > cast(size_t) count)
        begin = cast(size_t) count;
    foreach (index; begin .. cast(size_t) count)
        if (collectSimpleFrame(&state, cast(size_t) addresses[index]) != 0)
            break;
}

StackTrace capture(
    ref StackTraceBackendContext context,
    return scope StackFrame[] frameStorage,
    return scope char[] textStorage,
    uint skipFrames,
)
{
    StackTrace result;
    CaptureState state;
    state.frames = frameStorage;
    state.text = textStorage;
    const skip = skipFrames >= int.max - 1
        ? int.max : cast(int) skipFrames + 1;
    if (context.state_ !is null)
    {
        const fullResult = backtrace_full(
            context.state_,
            skip,
            &collectFrame,
            &captureError,
            &state,
        );
        cast(void) fullResult;
        if (state.frameCount == 0 && state.backendError)
        {
            state.backendError = false;
            state.textWritten = 0;
            state.textRequired = 0;
            state.textTruncated = false;
            const simpleResult = backtrace_simple(
                context.state_,
                skip,
                &collectSimpleFrame,
                &captureError,
                &state,
            );
            cast(void) simpleResult;
        }
    }
    if (state.frameCount == 0)
    {
        state.backendError = false;
        collectExecInfo(state, skipFrames);
        if (state.frameCount == 0)
            state.backendError = true;
    }
    result.frames = frameStorage[0 .. state.frameCount];
    result.framesTruncated = state.framesTruncated;
    result.textTruncated = state.textTruncated;
    result.backendError = state.backendError;
    result.textBytesRequired = state.textRequired;
    return result;
}

version (unittest) unittest
{
    import core.stdc.stdlib : malloc;

    CaptureState state;
    StackFrame[1] frames;
    char[3] text;
    state.frames = frames[];
    state.text = text[];
    assert(collectFrame(&state, 1, "file.d".ptr, 7, "function".ptr) == 0);
    assert(state.frameCount == 1);
    assert(state.textTruncated);
    assert(state.textRequired == "file.d".length + "function".length);
    assert(frames[0].filename.length == 0);
    assert(frames[0].functionName.length == 0);

    assert(collectFrame(&state, 2, null, 0, null) == 1);
    assert(state.framesTruncated);

    CaptureState fallbackState;
    StackFrame[1] fallbackFrames;
    char[512] fallbackText;
    fallbackState.frames = fallbackFrames[];
    fallbackState.text = fallbackText[];
    assert(collectFrame(
            &fallbackState,
            cast(size_t)&malloc,
            null,
            0,
            null,
    ) == 0);
    assert(fallbackFrames[0].functionName.length != 0);
}
