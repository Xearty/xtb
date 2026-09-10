module xtb.diagnostics.stacktrace;

nothrow @nogc:

import xtb.diagnostics.demangle;
import xtb.diagnostics.stacktrace_style;
import xtb.fmt.ansi;
import xtb.fmt.writer;
import xtb.types;

version (linux)
{
    import stacktrace_backend = xtb.diagnostics.internal.linux.stacktrace;
}
else
{
    import stacktrace_backend = xtb.diagnostics.internal.unsupported.stacktrace;
}

struct StackFrame
{
    usize program_counter;
    String filename;
    String function_name;
    u32 line;
}

struct StackTrace
{
    StackFrame[] frames;
    bool frames_truncated;
    bool text_truncated;
    bool backend_error;
    usize text_bytes_required;
}

enum StackTraceThreadSafety
{
    disabled,
    enabled,
}

struct StackTraceContext
{
    nothrow @nogc:

    stacktrace_backend.StackTraceBackendContext backend;

    bool available() const pure @safe
    {
        return this.backend.available;
    }

    /// Creates a stack-trace context.
    ///
    /// `permanent_executable_path` may be null. When non-null, it must point to
    /// a null-terminated string whose storage remains valid for the lifetime of
    /// the returned context.
    static StackTraceContext create(
        return scope const(char)* permanent_executable_path = null,
        StackTraceThreadSafety thread_safety = StackTraceThreadSafety.enabled,
    ) @system
    {
        StackTraceContext result;
        result.backend = stacktrace_backend.StackTraceBackendContext.create(
            permanent_executable_path,
            thread_safety == StackTraceThreadSafety.enabled,
        );
        return result;
    }

    /// Captures a trace whose frame and text views borrow from the supplied storage.
    ///
    /// The returned trace remains valid only while `frame_storage` and `text_storage`
    /// remain valid and unmodified.
    StackTrace capture(
        return scope StackFrame[] frame_storage,
        return scope char[] text_storage,
        u32 skip_frames = 0,
    ) @trusted
    {
        // Backends use native callbacks internally but confine every write to
        // the supplied slices; return scope preserves the borrowed views.
        return stacktrace_backend.capture(
            this.backend,
            frame_storage,
            text_storage,
            skip_frames,
        );
    }
}

private usize decimal_digits(usize value) pure @safe
{
    usize result = 1;
    while (value >= 10)
    {
        value /= 10;
        ++result;
    }
    return result;
}

/// Renders a stack trace without appending a trailing newline.
///
/// `trace` may be null, in which case a null-trace marker is rendered.
/// `signature_storage` is writable scratch storage used while demangling frame
/// names; its contents are unspecified after this function returns.
/// `requested_style` may be null to use the default style.
///
/// Callers that write the trace as standalone output are responsible for their
/// own record/line terminator. This keeps the formatter composable with logger
/// records and other writer destinations.
void write_stack_trace(
    ref Writer writer,
    scope const(StackTrace)* trace,
    scope char[] signature_storage,
    scope const(StackTraceStyle)* requested_style = null,
)
{
    auto default_style = StackTraceStyle.from_theme(StackTraceTheme.gruvbox);
    const style = requested_style is null ? &default_style : requested_style;
    const colors = &style.colors;

    if (trace is null)
    {
        writer.begin_ansi(colors.warning);
        writer.put("<null stack trace>");
        writer.end_ansi(colors.warning);
        return;
    }

    bool line_written;
    void start_line()
    {
        if (line_written) writer.put('\n');

        line_written = true;
    }

    start_line();
    writer.begin_ansi(colors.decoration);
    writer.put("Stack trace");
    writer.end_ansi(colors.decoration);
    writer.put(" (most recent call first):");

    const index_width = trace.frames.length == 0
        ? 1
        : decimal_digits(trace.frames.length - 1);
    foreach (index, const ref frame; trace.frames)
    {
        start_line();
        writer.repeat(' ', index_width - decimal_digits(index));
        writer.begin_ansi(colors.decoration);
        writer.put('[');
        writer.end_ansi(colors.decoration);
        writer.begin_ansi(colors.line_number);
        writer.value(index);
        writer.end_ansi(colors.line_number);
        writer.begin_ansi(colors.decoration);
        writer.put("] ");
        writer.end_ansi(colors.decoration);

        if (frame.function_name.length != 0)
        {
            String function_display;
            cast(void) try_demangle_d(
                frame.function_name,
                style.signature_detail,
                signature_storage,
                &function_display,
            );
            const signature_format = SignatureFormat(
                style.signature_layout,
                style.signature_columns,
                index_width + 3,
            );
            writer.write_signature(
                function_display,
                colors,
                style.module_display,
                signature_format,
            );
        }
        else
        {
            writer.begin_ansi(colors.warning);
            writer.put("<unknown symbol>");
            writer.end_ansi(colors.warning);
        }

        if (style.show_program_counter || frame.function_name.length == 0)
        {
            writer.put("  ");
            writer.begin_ansi(colors.address);
            writer.put("pc=");
            writer.value(hexadecimal(frame.program_counter));
            writer.end_ansi(colors.address);
        }

        if (frame.filename.length != 0)
        {
            writer.put('\n');
            writer.repeat(' ', index_width + 3);
            writer.begin_ansi(colors.decoration);
            writer.put("↳ ");
            writer.end_ansi(colors.decoration);
            writer.begin_ansi(colors.file_path);
            writer.put(frame.filename);
            writer.end_ansi(colors.file_path);

            if (frame.line != 0)
            {
                writer.begin_ansi(colors.decoration);
                writer.put(':');
                writer.end_ansi(colors.decoration);
                writer.begin_ansi(colors.line_number);
                writer.value(frame.line);
                writer.end_ansi(colors.line_number);
            }
        }
    }

    if (trace.frames_truncated)
    {
        start_line();
        writer.begin_ansi(colors.warning);
        writer.put("<additional frames omitted>");
        writer.end_ansi(colors.warning);
    }

    if (trace.text_truncated)
    {
        start_line();
        writer.begin_ansi(colors.warning);
        writer.put("<some symbols omitted: text storage exhausted>");
        writer.end_ansi(colors.warning);
    }

    if (trace.backend_error && trace.frames.length == 0)
    {
        start_line();
        writer.begin_ansi(colors.warning);
        writer.put("<stack trace unavailable>");
        writer.end_ansi(colors.warning);
    }
}

version (unittest)
{
    import core.stdc.string;

    private struct TraceCapture
    {
        char[2048] bytes;
        usize length;
    }

    private usize trace_capture_sink(
        void* context,
        scope const(u8)[] bytes,
    )
    {
        TraceCapture* capture = cast(TraceCapture*) context;
        const available = capture.bytes.length - capture.length;
        const amount = bytes.length < available ? bytes.length : available;

        memcpy(capture.bytes.ptr + capture.length, bytes.ptr, amount);
        capture.length += amount;
        return amount;
    }
}

unittest
{
    version (linux)
    {
        auto context = StackTraceContext.create(null, StackTraceThreadSafety.disabled);
        StackFrame[32] frames;
        char[4096] text;
        StackTrace trace = context.capture(frames[], text[], 0);

        assert(context.available);
        assert(trace.frames.length != 0 || trace.backend_error);
    }
}

unittest
{
    StackFrame[1] frames = [StackFrame(0x1234, "main.d", "_D3app3runFiZi", 9)];
    StackTrace trace;
    trace.frames = frames[];
    auto style = StackTraceStyle.from_theme(StackTraceTheme.plain);
    TraceCapture capture;
    auto writer = Writer.from_sink(&trace_capture_sink, &capture);
    char[256] signature_storage;

    writer.write_stack_trace(&trace, signature_storage[], &style);

    enum expected = "Stack trace (most recent call first):\n"
        ~ "[0] run(int)\n"
        ~ "    ↳ main.d:9";
    const output = capture.bytes[0 .. capture.length];

    assert(writer.result.ok);
    assert(output == expected);
}
