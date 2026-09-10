module xtb.diagnostics.internal.linux.stacktrace;

nothrow @nogc:

import core.stdc.stdint;
import core.stdc.string;

import xtb.diagnostics.stacktrace;
import xtb.os.linux.dynamic_link;
import xtb.os.linux.execinfo;
import xtb.types;

private struct backtrace_state;

private alias backtrace_error_callback = extern (C) void function(
    void*,
    const(char)*,
    int,
) nothrow @nogc;
private alias backtrace_full_callback = extern (C) int function(
    void*,
    uintptr_t,
    const(char)*,
    int,
    const(char)*,
) nothrow @nogc;
private alias backtrace_simple_callback = extern (C) int function(
    void*,
    uintptr_t,
) nothrow @nogc;

extern (C) private backtrace_state* backtrace_create_state(
    const(char)* filename,
    int threaded,
    backtrace_error_callback error_callback,
    void* data,
);
extern (C) private int backtrace_full(
    backtrace_state* state,
    int skip,
    backtrace_full_callback callback,
    backtrace_error_callback error_callback,
    void* data,
);
extern (C) private int backtrace_simple(
    backtrace_state* state,
    int skip,
    backtrace_simple_callback callback,
    backtrace_error_callback error_callback,
    void* data,
);

struct StackTraceBackendContext
{
    nothrow @nogc:

    backtrace_state* state;

    bool available() const pure @safe
    {
        return this.state !is null;
    }

    /**
     * Creates a backend context.
     *
     * `permanent_executable_path` may be null. When non-null, it must point to
     * a null-terminated string whose storage remains valid for the lifetime of
     * the returned context.
     */
    static StackTraceBackendContext create(
        return scope const(char)* permanent_executable_path,
        bool thread_safe,
    ) @system
    {
        StackTraceBackendContext result;
        result.state = backtrace_create_state(
            permanent_executable_path,
            thread_safe ? 1 : 0,
            &creation_error,
            null,
        );
        return result;
    }
}

private extern (C) void creation_error(void*, const(char)*, int) {}

private struct CaptureState
{
    StackFrame[] frames;
    char[] text;
    usize frame_count;
    usize text_written;
    usize text_required;
    bool frames_truncated;
    bool text_truncated;
    bool backend_error;
}

private String copy_text(ref CaptureState state, scope const(char)* value) @system
{
    if (value is null) return null;

    const length = strlen(value);
    if (length == 0) return null;

    if (length > usize.max - state.text_required)
    {
        state.text_required = usize.max;
        state.text_truncated = true;
        return null;
    }

    state.text_required += length;
    if (length > state.text.length - state.text_written)
    {
        state.text_truncated = true;
        return null;
    }

    char* destination = state.text.ptr + state.text_written;
    memcpy(destination, value, length);
    state.text_written += length;
    return destination[0 .. length];
}

private extern (C) int collect_frame(
    void* data,
    uintptr_t program_counter,
    const(char)* filename,
    int line,
    const(char)* function_name,
) @system
{
    CaptureState* state = cast(CaptureState*) data;
    if (program_counter == uintptr_t.max) return 1;

    if (state.frame_count == state.frames.length)
    {
        state.frames_truncated = true;
        return 1;
    }

    const(char)* resolved_filename = filename;
    const(char)* resolved_function_name = function_name;
    if (resolved_filename is null || resolved_function_name is null)
    {
        Dl_info information;
        if (dladdr(cast(const(void)*) program_counter, &information) != 0)
        {
            if (resolved_filename is null) resolved_filename = information.dli_fname;
            if (resolved_function_name is null) resolved_function_name = information.dli_sname;
        }
    }

    StackFrame* frame = &state.frames[state.frame_count];
    ++state.frame_count;

    frame.program_counter = cast(usize) program_counter;
    frame.filename = copy_text(*state, resolved_filename);
    frame.function_name = copy_text(*state, resolved_function_name);
    frame.line = line > 0 ? cast(u32) line : 0;
    return 0;
}

private extern (C) void capture_error(
    void* data,
    const(char)*,
    int,
) @system
{
    CaptureState* state = cast(CaptureState*) data;
    state.backend_error = true;
}

private extern (C) int collect_simple_frame(
    void* data,
    uintptr_t program_counter,
) @system
{
    Dl_info information;
    const found = dladdr(cast(const(void)*) program_counter, &information);
    return collect_frame(
        data,
        program_counter,
        found == 0 ? null : information.dli_fname,
        0,
        found == 0 ? null : information.dli_sname,
    );
}

private void collect_exec_info(ref CaptureState state, u32 skip_frames) @system
{
    void*[128] addresses;
    const count = backtrace(addresses.ptr, cast(i32) addresses.length);
    usize begin = cast(usize) skip_frames;
    if (begin > cast(usize) count) begin = cast(usize) count;

    foreach (index; begin .. cast(usize) count)
    {
        const collect_result = collect_simple_frame(
            &state,
            cast(uintptr_t) addresses[index],
        );
        if (collect_result != 0) break;
    }
}

StackTrace capture(
    ref StackTraceBackendContext context,
    return scope StackFrame[] frame_storage,
    return scope char[] text_storage,
    u32 skip_frames,
) @system
{
    StackTrace result;
    CaptureState state;
    state.frames = frame_storage;
    state.text = text_storage;

    const skip = skip_frames >= i32.max - 1
        ? i32.max
        : cast(i32) skip_frames + 1;
    if (context.state !is null)
    {
        cast(void) backtrace_full(
            context.state,
            skip,
            &collect_frame,
            &capture_error,
            &state,
        );

        if (state.frame_count == 0 && state.backend_error)
        {
            state.backend_error = false;
            state.text_written = 0;
            state.text_required = 0;
            state.text_truncated = false;

            cast(void) backtrace_simple(
                context.state,
                skip,
                &collect_simple_frame,
                &capture_error,
                &state,
            );
        }
    }

    if (state.frame_count == 0)
    {
        state.backend_error = false;
        collect_exec_info(state, skip_frames);
        if (state.frame_count == 0) state.backend_error = true;
    }

    result.frames = frame_storage[0 .. state.frame_count];
    result.frames_truncated = state.frames_truncated;
    result.text_truncated = state.text_truncated;
    result.backend_error = state.backend_error;
    result.text_bytes_required = state.text_required;
    return result;
}

version (unittest)
{
    import core.stdc.stdlib;
}

unittest
{
    CaptureState state;
    StackFrame[1] frames;
    char[3] text;
    state.frames = frames[];
    state.text = text[];

    assert(collect_frame(&state, 1, "file.d".ptr, 7, "function".ptr) == 0);
    assert(state.frame_count == 1);
    assert(state.text_truncated);
    assert(state.text_required == "file.d".length + "function".length);
    assert(frames[0].filename.length == 0);
    assert(frames[0].function_name.length == 0);

    assert(collect_frame(&state, 2, null, 0, null) == 1);
    assert(state.frames_truncated);
}

unittest
{
    CaptureState state;
    StackFrame[1] frames;
    char[512] text;
    state.frames = frames[];
    state.text = text[];

    assert(collect_frame(
        &state,
        cast(uintptr_t) &malloc,
        null,
        0,
        null,
    ) == 0);
    assert(frames[0].function_name.length != 0);
}
