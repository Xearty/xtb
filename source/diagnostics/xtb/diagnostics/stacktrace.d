module xtb.diagnostics.stacktrace;

nothrow @nogc:

import core.stdc.string : memcpy;
import xtb.diagnostics.demangle : tryDemangleD;
import xtb.ansi : AnsiColor;
import xtb.fmt.ansi : beginAnsi, endAnsi;
import xtb.fmt.writer : Writer, hexadecimal;
import xtb.string;
import xtb.diagnostics.stacktrace_style : StackTraceColors, StackTraceStyle,
    StackTraceTheme, SignatureFormat, writeSignature;

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

version (linux)
    import Backend = xtb.diagnostics.internal.linux.stacktrace;
else
    import Backend = xtb.diagnostics.internal.unsupported.stacktrace;

struct StackTraceContext
{
nothrow @nogc:

    private Backend.StackTraceBackendContext backend_;

    bool available() const pure @safe
    {
        return backend_.available;
    }

    static StackTraceContext create(
        const(char)* permanentExecutablePath = null,
        bool threadSafe = true,
    )
    {
        StackTraceContext result;
        result.backend_ = Backend.StackTraceBackendContext.create(
            permanentExecutablePath,
            threadSafe,
        );
        return result;
    }
}

StackTrace capture(
    ref StackTraceContext context,
    return scope StackFrame[] frameStorage,
    return scope char[] textStorage,
    uint skipFrames = 0,
)
{
    return Backend.capture(
        context.backend_,
        frameStorage,
        textStorage,
        skipFrames,
    );
}

private size_t decimalDigits(size_t value) pure @safe
{
    size_t result = 1;
    while (value >= 10)
    {
        value /= 10;
        ++result;
    }
    return result;
}

private void beginColor(ref Writer writer, AnsiColor color)
{
    writer.beginAnsi(color);
}

private void endColor(
    ref Writer writer,
    scope const StackTraceColors*,
    AnsiColor color,
)
{
    writer.endAnsi(color);
}

/// Renders a stack trace without appending a trailing newline.
///
/// Callers that write the trace as standalone output are responsible for their
/// own record/line terminator. This keeps the formatter composable with logger
/// records and other writer destinations.
void writeStackTrace(
    ref Writer writer,
    scope const StackTrace* trace,
    return scope char[] signatureStorage,
    scope const StackTraceStyle* requestedStyle = null,
)
{
    StackTraceStyle defaultStyle = StackTraceStyle.fromTheme(
        StackTraceTheme.gruvbox,
    );
    const style = requestedStyle is null ? &defaultStyle : requestedStyle;
    const colors = &style.colors;
    if (trace is null)
    {
        beginColor(writer, colors.warning);
        writer.put("<null stack trace>");
        endColor(writer, colors, colors.warning);
        return;
    }

    bool lineWritten;
    void startLine()
    {
        if (lineWritten)
            writer.put('\n');
        lineWritten = true;
    }

    startLine();
    beginColor(writer, colors.decoration);
    writer.put("Stack trace");
    endColor(writer, colors, colors.decoration);
    writer.put(" (most recent call first):");
    const indexWidth = trace.frames.length == 0
        ? 1 : decimalDigits(trace.frames.length - 1);
    foreach (index, frame; trace.frames)
    {
        startLine();
        writer.repeat(' ', indexWidth - decimalDigits(index));
        beginColor(writer, colors.decoration);
        writer.put('[');
        endColor(writer, colors, colors.decoration);
        beginColor(writer, colors.lineNumber);
        writer.value(index);
        endColor(writer, colors, colors.lineNumber);
        beginColor(writer, colors.decoration);
        writer.put("] ");
        endColor(writer, colors, colors.decoration);
        if (frame.functionName.length != 0)
        {
            String functionDisplay;
            cast(void) tryDemangleD(
                frame.functionName,
                signatureStorage,
                &functionDisplay,
                style.signatureDetail,
            );
            writer.writeSignature(
                functionDisplay,
                colors,
                style.moduleDisplay,
                SignatureFormat(
                    style.signatureLayout,
                    style.signatureColumns,
                    indexWidth + 3,
            ),
            );
        }
        else
        {
            beginColor(writer, colors.warning);
            writer.put("<unknown symbol>");
            endColor(writer, colors, colors.warning);
        }
        if (style.showProgramCounter || frame.functionName.length == 0)
        {
            writer.put("  ");
            beginColor(writer, colors.address);
            writer.put("pc=");
            writer.value(hexadecimal(cast(size_t) frame.programCounter));
            endColor(writer, colors, colors.address);
        }
        if (frame.filename.length != 0)
        {
            writer.put('\n');
            writer.repeat(' ', indexWidth + 3);
            beginColor(writer, colors.decoration);
            writer.put("↳ ");
            endColor(writer, colors, colors.decoration);
            beginColor(writer, colors.filePath);
            writer.put(frame.filename);
            endColor(writer, colors, colors.filePath);
            if (frame.line != 0)
            {
                beginColor(writer, colors.decoration);
                writer.put(':');
                endColor(writer, colors, colors.decoration);
                beginColor(writer, colors.lineNumber);
                writer.value(frame.line);
                endColor(writer, colors, colors.lineNumber);
            }
        }
    }
    if (trace.framesTruncated)
    {
        startLine();
        beginColor(writer, colors.warning);
        writer.put("<additional frames omitted>");
        endColor(writer, colors, colors.warning);
    }
    if (trace.textTruncated)
    {
        startLine();
        beginColor(writer, colors.warning);
        writer.put("<some symbols omitted: text storage exhausted>");
        endColor(writer, colors, colors.warning);
    }
    if (trace.backendError && trace.frames.length == 0)
    {
        startLine();
        beginColor(writer, colors.warning);
        writer.put("<stack trace unavailable>");
        endColor(writer, colors, colors.warning);
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
        assert(trace.frames.length != 0 || trace.backendError);
    }
}

version (unittest)
{
    private struct TraceCapture
    {
    nothrow @nogc:

        char[2048] bytes;
        size_t length;
    }

    private size_t traceCaptureSink(
        void* context,
        scope const(ubyte)[] bytes,
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
    import xtb.string;

    StackFrame[1] frames = [StackFrame(
            0x1234,
            "main.d",
            "_D3app3runFiZi",
            9,
        )];
    StackTrace trace;
    trace.frames = frames[];
    StackTraceStyle style = StackTraceStyle.fromTheme(StackTraceTheme.plain);
    TraceCapture capture;
    Writer writer = Writer.fromSink(&traceCaptureSink, &capture);
    char[256] signatureStorage;
    writer.writeStackTrace(&trace, signatureStorage[], &style);
    assert(writer.result.ok);
    assert(capture.bytes[0 .. capture.length].equal(
            "Stack trace (most recent call first):\n" ~
            "[0] run(int)\n" ~
            "    ↳ main.d:9",
    ));
}
