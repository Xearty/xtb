module xtb.diagnostics.stacktrace;

nothrow @nogc:

import xtb.ansi;
import xtb.diagnostics.demangle;
import xtb.diagnostics.stacktrace_style;
import xtb.fmt.ansi;
import xtb.fmt.writer;
import xtb.types;

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

version (linux)
{
    import stacktrace_backend = xtb.diagnostics.internal.linux.stacktrace;
}
else
{
    import stacktrace_backend = xtb.diagnostics.internal.unsupported.stacktrace;
}

struct StackTraceContext
{
    nothrow @nogc:

    stacktrace_backend.StackTraceBackendContext backend;

    bool available() const pure @safe
    {
        return this.backend.available;
    }

    /**
     * Creates a stack-trace context.
     *
     * `permanent_executable_path` may be null. When non-null, its storage must
     * remain valid for the lifetime of the returned context.
     */
    static StackTraceContext create(
        const(char)* permanent_executable_path = null,
        bool thread_safe = true,
    )
    {
        StackTraceContext result;
        result.backend = stacktrace_backend.StackTraceBackendContext.create(
            permanent_executable_path,
            thread_safe,
        );
        return result;
    }
}

/// Captures a trace whose frame and text views borrow from the supplied storage.
StackTrace capture(
    ref StackTraceContext context,
    return scope StackFrame[] frame_storage,
    return scope char[] text_storage,
    u32 skip_frames = 0,
)
{
    return stacktrace_backend.capture(
        context.backend,
        frame_storage,
        text_storage,
        skip_frames,
    );
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

private void begin_color(ref Writer writer, ANSIColor color)
{
    writer.begin_ansi(color);
}

private void end_color(ref Writer writer, ANSIColor color)
{
    writer.end_ansi(color);
}

/**
 * Renders a stack trace without appending a trailing newline.
 *
 * `trace` may be null, in which case a null-trace marker is rendered.
 * `requested_style` may be null to use the default style.
 *
 * Callers that write the trace as standalone output are responsible for their
 * own record/line terminator. This keeps the formatter composable with logger
 * records and other writer destinations.
 */
void write_stack_trace(
    ref Writer writer,
    scope const(StackTrace)* trace,
    return scope char[] signature_storage,
    scope const(StackTraceStyle)* requested_style = null,
)
{
    StackTraceStyle default_style = StackTraceStyle.from_theme(StackTraceTheme.gruvbox);
    const style = requested_style is null ? &default_style : requested_style;
    const colors = &style.colors;
    if (trace is null)
    {
        begin_color(writer, colors.warning);
        writer.put("<null stack trace>");
        end_color(writer, colors.warning);
        return;
    }

    bool line_written;
    void start_line()
    {
        if (line_written) writer.put('\n');

        line_written = true;
    }

    start_line();
    begin_color(writer, colors.decoration);
    writer.put("Stack trace");
    end_color(writer, colors.decoration);
    writer.put(" (most recent call first):");
    const index_width = trace.frames.length == 0
        ? 1
        : decimal_digits(trace.frames.length - 1);
    foreach (index, frame; trace.frames)
    {
        start_line();
        writer.repeat(' ', index_width - decimal_digits(index));
        begin_color(writer, colors.decoration);
        writer.put('[');
        end_color(writer, colors.decoration);
        begin_color(writer, colors.line_number);
        writer.value(index);
        end_color(writer, colors.line_number);
        begin_color(writer, colors.decoration);
        writer.put("] ");
        end_color(writer, colors.decoration);
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
            begin_color(writer, colors.warning);
            writer.put("<unknown symbol>");
            end_color(writer, colors.warning);
        }
        if (style.show_program_counter || frame.function_name.length == 0)
        {
            writer.put("  ");
            begin_color(writer, colors.address);
            writer.put("pc=");
            writer.value(hexadecimal(frame.program_counter));
            end_color(writer, colors.address);
        }
        if (frame.filename.length != 0)
        {
            writer.put('\n');
            writer.repeat(' ', index_width + 3);
            begin_color(writer, colors.decoration);
            writer.put("↳ ");
            end_color(writer, colors.decoration);
            begin_color(writer, colors.file_path);
            writer.put(frame.filename);
            end_color(writer, colors.file_path);
            if (frame.line != 0)
            {
                begin_color(writer, colors.decoration);
                writer.put(':');
                end_color(writer, colors.decoration);
                begin_color(writer, colors.line_number);
                writer.value(frame.line);
                end_color(writer, colors.line_number);
            }
        }
    }

    if (trace.frames_truncated)
    {
        start_line();
        begin_color(writer, colors.warning);
        writer.put("<additional frames omitted>");
        end_color(writer, colors.warning);
    }

    if (trace.text_truncated)
    {
        start_line();
        begin_color(writer, colors.warning);
        writer.put("<some symbols omitted: text storage exhausted>");
        end_color(writer, colors.warning);
    }

    if (trace.backend_error && trace.frames.length == 0)
    {
        start_line();
        begin_color(writer, colors.warning);
        writer.put("<stack trace unavailable>");
        end_color(writer, colors.warning);
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
        StackTraceContext context = StackTraceContext.create();
        StackFrame[32] frames;
        char[4096] text;
        StackTrace trace = context.capture(frames[], text[], 0);

        assert(context.available);
        assert(trace.frames.length != 0 || trace.backend_error);
    }
}

unittest
{
    StackFrame[1] frames = [
        StackFrame(
            0x1234,
            "main.d",
            "_D3app3runFiZi",
            9,
        ),
    ];
    StackTrace trace;
    trace.frames = frames[];
    StackTraceStyle style = StackTraceStyle.from_theme(StackTraceTheme.plain);
    TraceCapture capture;
    Writer writer = Writer.from_sink(&trace_capture_sink, &capture);
    char[256] signature_storage;

    writer.write_stack_trace(&trace, signature_storage[], &style);

    assert(writer.result.ok);
    assert(
        capture.bytes[0 .. capture.length]
            == "Stack trace (most recent call first):\n"
            ~ "[0] run(int)\n"
            ~ "    ↳ main.d:9",
    );
}
