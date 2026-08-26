module xtb.fmt.ansi;

nothrow @nogc:

import core.lifetime : forward;
import xtb.ansi : AnsiColor, AnsiSequence, AnsiStyle, ansiResetSequence, ansiSequence;
import xtb.fmt.writer : Writer;
import xtb.types : String, u8;

version (XTB_Checked) import xtb.panic : require;

version (unittest) import xtb.string : equal;

struct AnsiReset
{
nothrow @nogc:

    void formatTo(ref Writer writer) const
    {
        writer.resetAnsi();
    }
}

enum ansiReset = AnsiReset.init;

/// Printable values rendered under one ANSI style scope.
///
/// Values are captured by value and formatted through the ordinary XTB
/// printable-value path. Ending the style emits a full SGR reset, so styled
/// values intentionally do not form nestable style scopes.
struct Styled(Values...)
{
nothrow @nogc:

    Values values;
    AnsiStyle style;

    void formatTo(ref Writer writer)
    {
        writer.beginAnsi(style);
        static foreach (index; 0 .. Values.length)
            writer.value(values[index]);
        writer.endAnsi(style);
    }

    void formatTo(ref Writer writer) const
    {
        writer.beginAnsi(style);
        static foreach (index; 0 .. Values.length)
            writer.value(values[index]);
        writer.endAnsi(style);
    }
}

/// Wraps one or more printable `values` in `style` without allocating.
auto styled(Values...)(auto ref Values values, AnsiStyle style) if (Values.length != 0)
{
    return Styled!Values(forward!values, style);
}

/// A non-owning view over a `Writer` that conditionally emits ANSI SGR styling.
///
/// `ansiEnabled` is an explicit rendering decision made by the caller; this
/// type does not inspect the output destination or environment. The referenced
/// `Writer` must remain valid for the lifetime of this view.
struct AnsiWriter
{
nothrow @nogc:

    private Writer* writer_;
    private bool ansiEnabled_;

    /// Creates an ANSI-capable view over `writer`.
    /// `ansiEnabled` is deliberately required: policy belongs to the caller.
    static AnsiWriter fromWriter(Writer* writer, bool ansiEnabled)
    {
        version (XTB_Checked)
            require(writer !is null, "AnsiWriter requires a non-null Writer pointer");

        AnsiWriter result;
        result.writer_ = writer;
        result.ansiEnabled_ = ansiEnabled;
        return result;
    }

    bool ansiEnabled() const pure @safe
    {
        return ansiEnabled_;
    }

    bool ok() const pure @safe
    {
        return writer_.ok;
    }

    size_t written() const pure @safe
    {
        return writer_.written;
    }

    void put(char value)
    {
        writer_.put(value);
    }

    void put(scope String value)
    {
        writer_.put(value);
    }

    void repeat(char value, size_t count)
    {
        writer_.repeat(value, count);
    }

    void value(T)(auto ref T value)
    {
        writer_.value(value);
    }

    /// Writes one or more ordinary `Writer.value` values under trailing `style`.
    /// When ANSI is disabled, this is exactly equivalent to writing the values
    /// without styling. The emitted reset is a full SGR reset, so this helper
    /// intentionally does not expose nestable begin/end style scopes.
    void styled(Values...)(auto ref Values values, AnsiStyle style) if (Values.length != 0)
    {
        if (ansiEnabled_)
            beginAnsi(*writer_, style);

        static foreach (index; 0 .. Values.length)
            writer_.value(values[index]);

        if (ansiEnabled_)
            endAnsi(*writer_, style);
    }
}

void beginAnsi(ref Writer writer, AnsiStyle style)
{
    const sequence = ansiSequence(style);
    writer.put(sequence.view);
}

void beginAnsi(ref Writer writer, AnsiColor foreground)
{
    writer.beginAnsi(AnsiStyle.foreground(foreground));
}

void resetAnsi(ref Writer writer)
{
    const sequence = ansiResetSequence();
    writer.put(sequence.view);
}

void endAnsi(ref Writer writer, AnsiStyle style)
{
    if (style.enabled)
        writer.resetAnsi();
}

void endAnsi(ref Writer writer, AnsiColor foreground)
{
    if (foreground.enabled)
        writer.resetAnsi();
}

version (unittest) private struct AnsiWriterTestSinkState
{
    char[256] storage;
    size_t length;
}

version (unittest) private size_t ansiWriterTestSink(
    void* context,
    scope const(ubyte)[] bytes,
)
{
    AnsiWriterTestSinkState* state = cast(AnsiWriterTestSinkState*) context;
    if (state is null || bytes.length > state.storage.length - state.length)
        return 0;

    foreach (index, value; bytes)
        state.storage[state.length + index] = cast(char) value;
    state.length += bytes.length;
    return bytes.length;
}

unittest
{
    import xtb.fmt.writer : hexadecimal;

    AnsiWriterTestSinkState state;
    Writer output = Writer.fromSink(&ansiWriterTestSink, &state);

    static assert(!__traits(compiles, AnsiWriter.fromWriter(&output)));
    static assert(__traits(compiles, AnsiWriter.fromWriter(&output, false)));

    AnsiWriter plain = AnsiWriter.fromWriter(&output, false);
    assert(!plain.ansiEnabled);
    assert(plain.ok);
    assert(plain.written == 0);

    plain.put('A');
    plain.put("B");
    plain.repeat('c', 2);
    const plainStyle = AnsiStyle.foreground(AnsiColor.brightRed).bold;
    plain.styled(" value=", hexadecimal(42), plainStyle);
    assert(state.length != 0);
    assert(plain.written == state.length);
    assert(state.storage[0 .. state.length].equal("ABcc value=0x2a"));

    const plainResult = output.result;
    assert(plainResult.ok);
    assert(plainResult.written == state.length);

    state = AnsiWriterTestSinkState.init;
    output = Writer.fromSink(&ansiWriterTestSink, &state);
    AnsiWriter styled = AnsiWriter.fromWriter(&output, true);
    assert(styled.ansiEnabled);

    const style = AnsiStyle.foreground(AnsiColor.brightRed).bold;
    styled.styled("value=", 42, '!', style);
    const styledResult = output.result;
    assert(styledResult.ok);
    assert(styledResult.written == state.length);
    assert(state.storage[0 .. state.length].equal(
            "\x1b[1;91mvalue=42!\x1b[0m",
    ));
}

unittest
{
    import xtb.fmt.fixed_buffer : writeBuffer;
    import xtb.string;

    AnsiWriterTestSinkState state;
    char[128] storage;
    const style = AnsiStyle.foreground(AnsiColor.brightRed)
        .withBackground(AnsiColor.indexed(17))
        .bold
        .underline;
    Writer styleWriter = Writer.fromSink(&ansiWriterTestSink, &state);
    beginAnsi(styleWriter, style);
    styleWriter.put("failure");
    resetAnsi(styleWriter);
    assert(styleWriter.ok);
    assert(state.storage[0 .. state.length].equal(
            "\x1b[1;4;91;48;5;17mfailure\x1b[0m",
    ));
    state = AnsiWriterTestSinkState.init;

    import xtb.fmt.format : formatted;

    const plainStyledResult = writeBuffer(storage[], styled(42, AnsiStyle.init));
    assert(plainStyledResult.ok);
    assert(storage[0 .. plainStyledResult.written].equal("42"));

    const groupedStyledResult = writeBuffer(
        storage[],
        styled("value=", 42, '!', AnsiColor.brightRed.foreground),
    );
    assert(groupedStyledResult.ok);
    assert(storage[0 .. groupedStyledResult.written].equal(
            "\x1b[91mvalue=42!\x1b[0m",
    ));

    const styledResult = writeBuffer(
        storage[],
        styled(formatted!"#{}:{}"(7u, 3u), AnsiColor.brightCyan.foreground.bold),
    );
    assert(styledResult.ok);
    assert(storage[0 .. styledResult.written].equal(
            "\x1b[1;96m#7:3\x1b[0m",
    ));
}
