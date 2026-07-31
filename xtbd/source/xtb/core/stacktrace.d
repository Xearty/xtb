module xtb.core.stacktrace;

import core.stdc.string : memcpy, strlen;
import xtb.core.print : Writer, hexadecimal;
import xtb.core.string : String;

struct StackFrame
{
    size_t programCounter;
    String filename;
    String functionName;
    uint line;
}

struct StackTrace
{
    StackFrame[] frames;
    bool framesTruncated;
    bool textTruncated;
    bool backendError;
    size_t textBytesRequired;
}

struct StackTraceContext
{
    version (linux)
        private BacktraceState* state;

    bool available() const pure nothrow @safe @nogc
    {
        version (linux)
            return state !is null;
        else
            return false;
    }

    static StackTraceContext create(
        const(char)* permanentExecutablePath = null,
        bool threadSafe = true,
    ) nothrow @nogc
    {
        StackTraceContext result;
        version (linux)
            result.state = backtrace_create_state(
                permanentExecutablePath,
                threadSafe ? 1 : 0,
                &creationError,
                null,
            );
        return result;
    }
}

version (linux)
{
    import core.sys.posix.dlfcn : Dl_info, dladdr;
    import core.sys.linux.execinfo : backtrace;

    private struct BacktraceState;

    private alias ErrorCallback = extern(C) void function(
        void* data,
        const(char)* message,
        int errorNumber,
    ) nothrow @nogc;
    private alias FullCallback = extern(C) int function(
        void* data,
        size_t programCounter,
        const(char)* filename,
        int line,
        const(char)* functionName,
    ) nothrow @nogc;
    private alias SimpleCallback = extern(C) int function(
        void* data,
        size_t programCounter,
    ) nothrow @nogc;

    extern(C) private BacktraceState* backtrace_create_state(
        const(char)* filename,
        int threaded,
        ErrorCallback errorCallback,
        void* data,
    ) nothrow @nogc;
    extern(C) private int backtrace_full(
        BacktraceState* state,
        int skip,
        FullCallback callback,
        ErrorCallback errorCallback,
        void* data,
    ) nothrow @nogc;
    extern(C) private int backtrace_simple(
        BacktraceState* state,
        int skip,
        SimpleCallback callback,
        ErrorCallback errorCallback,
        void* data,
    ) nothrow @nogc;

    private extern(C) void creationError(void*, const(char)*, int)
        nothrow @nogc
    {
    }

    private struct CaptureState
    {
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
        nothrow @system @nogc
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

    private extern(C) int collectFrame(
        void* data,
        size_t programCounter,
        const(char)* filename,
        int line,
        const(char)* functionName,
    ) nothrow @nogc
    {
        CaptureState* state = cast(CaptureState*) data;
        if (programCounter == size_t.max)
            return 1;
        if (state.frameCount == state.frames.length)
        {
            state.framesTruncated = true;
            return 1;
        }
        StackFrame* frame = &state.frames[state.frameCount++];
        frame.programCounter = programCounter;
        frame.filename = copyText(*state, filename);
        frame.functionName = copyText(*state, functionName);
        frame.line = line > 0 ? cast(uint) line : 0;
        return 0;
    }

    private extern(C) void captureError(
        void* data,
        const(char)*,
        int,
    ) nothrow @nogc
    {
        CaptureState* state = cast(CaptureState*) data;
        state.backendError = true;
    }

    private extern(C) int collectSimpleFrame(
        void* data,
        size_t programCounter,
    ) nothrow @nogc
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
        nothrow @nogc
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
}

StackTrace capture(
    ref StackTraceContext context,
    return scope StackFrame[] frameStorage,
    return scope char[] textStorage,
    uint skipFrames = 0,
) nothrow @nogc
{
    StackTrace result;
    version (linux)
    {
        CaptureState state;
        state.frames = frameStorage;
        state.text = textStorage;
        const skip = skipFrames >= int.max - 1
            ? int.max : cast(int) skipFrames + 1;
        if (context.state !is null)
        {
            const fullResult = backtrace_full(
                context.state,
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
                    context.state,
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
    }
    else
        result.backendError = true;
    return result;
}

void writeStackTrace(ref Writer writer, scope const StackTrace* trace)
    nothrow @nogc
{
    if (trace is null)
    {
        writer.put("<null stack trace>\n");
        return;
    }
    foreach (index, frame; trace.frames)
    {
        writer.put('[');
        writer.value(index);
        writer.put("] ");
        if (frame.functionName.length != 0)
            writer.put(frame.functionName);
        else
        {
            writer.put("pc=");
            writer.value(hexadecimal(cast(size_t) frame.programCounter));
        }
        if (frame.filename.length != 0)
        {
            writer.put("\n    at ");
            writer.put(frame.filename);
            if (frame.line != 0)
            {
                writer.put(':');
                writer.value(frame.line);
            }
        }
        writer.put('\n');
    }
    if (trace.framesTruncated)
        writer.put("<additional frames omitted>\n");
    if (trace.textTruncated)
        writer.put("<some symbols omitted: text storage exhausted>\n");
    if (trace.backendError && trace.frames.length == 0)
        writer.put("<stack trace unavailable>\n");
}

nothrow @nogc unittest
{
    version (linux)
    {
        StackTraceContext context = StackTraceContext.create();
        StackFrame[32] frames;
        char[4096] text;
        StackTrace trace = context.capture(frames[], text[], 0);
        assert(context.available);
        assert(trace.frames.length != 0 || trace.backendError);
    }
}
