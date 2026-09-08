module xtb.fmt.ansi;

nothrow @nogc:

import core.lifetime;

import xtb.ansi;
import xtb.fmt.writer;
import xtb.panic;
import xtb.types;

struct ANSIReset
{
nothrow @nogc:

    void format_to(ref Writer writer) const
    {
        writer.reset_ansi();
    }
}

enum ansi_reset = ANSIReset.init;

/// Printable values rendered under one ANSI style scope.
///
/// Values are captured by value and formatted through the ordinary XTB
/// printable-value path. Ending the style emits a full SGR reset, so styled
/// values intentionally do not form nestable style scopes.
struct Styled(Values...)
{
nothrow @nogc:

    Values values;
    ANSIStyle style;

    void format_to(ref Writer writer)
    {
        writer.begin_ansi(this.style);
        static foreach (index; 0 .. Values.length)
            writer.value(this.values[index]);
        writer.end_ansi(this.style);
    }

    void format_to(ref Writer writer) const
    {
        writer.begin_ansi(this.style);
        static foreach (index; 0 .. Values.length)
            writer.value(this.values[index]);
        writer.end_ansi(this.style);
    }
}

/// Wraps one or more printable `values` in `style` without allocating.
auto styled(Values...)(auto ref Values values, ANSIStyle style) if (Values.length != 0)
{
    return Styled!Values(forward!values, style);
}

/// A non-owning view over a `Writer` that conditionally emits ANSI SGR styling.
///
/// `ansi_enabled` is an explicit rendering decision made by the caller; this
/// type does not inspect the output destination or environment. The referenced
/// `Writer` must remain valid for the lifetime of this view.
struct ANSIWriter
{
nothrow @nogc:

    /// Borrowed destination. It must remain non-null and live while this view is used.
    Writer* writer;
    /// Whether ANSI SGR styling is emitted by `styled`.
    bool ansi_enabled;

    /// Creates an ANSI-capable view over `writer`.
    /// `ansi_enabled` is deliberately required: policy belongs to the caller.
    static ANSIWriter from_writer(return scope Writer* writer, bool ansi_enabled) @safe
    {
        require(writer !is null, "ANSI writer is null");
        return ANSIWriter(writer, ansi_enabled);
    }

    bool ok() const pure @safe
    {
        return this.writer.ok;
    }

    usize written() const pure @safe
    {
        return this.writer.written;
    }

    void put(char value)
    {
        this.writer.put(value);
    }

    void put(scope String value)
    {
        this.writer.put(value);
    }

    void repeat(char value, usize count)
    {
        this.writer.repeat(value, count);
    }

    void value(T)(auto ref T value)
    {
        this.writer.value(value);
    }

    /// Writes one or more ordinary `Writer.value` values under trailing `style`.
    /// When ANSI is disabled, this is exactly equivalent to writing the values
    /// without styling. The emitted reset is a full SGR reset, so this helper
    /// intentionally does not expose nestable begin/end style scopes.
    void styled(Values...)(auto ref Values values, ANSIStyle style) if (Values.length != 0)
    {
        if (this.ansi_enabled) begin_ansi(*this.writer, style);

        static foreach (index; 0 .. Values.length)
            this.writer.value(values[index]);

        if (this.ansi_enabled) end_ansi(*this.writer, style);
    }
}

void begin_ansi(ref Writer writer, ANSIStyle style)
{
    const sequence = ansi_sequence(style);
    writer.put(sequence.view);
}

void begin_ansi(ref Writer writer, ANSIColor foreground)
{
    writer.begin_ansi(ANSIStyle.foreground(foreground));
}

void reset_ansi(ref Writer writer)
{
    const sequence = ansi_reset_sequence();
    writer.put(sequence.view);
}

void end_ansi(ref Writer writer, ANSIStyle style)
{
    if (style.enabled)
        writer.reset_ansi();
}

void end_ansi(ref Writer writer, ANSIColor foreground)
{
    if (foreground.enabled)
        writer.reset_ansi();
}

version (unittest)
{
    import xtb.fmt.fixed_buffer;
    import xtb.fmt.format;
    import xtb.string;

    private struct ANSIWriterTestSinkState
    {
        char[256] storage;
        usize length;
    }

    private usize ansi_writer_test_sink(void* context, scope const(u8)[] bytes) @system
    {
        // Tests pass a live ANSIWriterTestSinkState as the opaque sink context.
        auto state = cast(ANSIWriterTestSinkState*) context;
        if (state is null || bytes.length > state.storage.length - state.length) return 0;

        foreach (index, value; bytes)
            state.storage[state.length + index] = cast(char) value;

        state.length += bytes.length;
        return bytes.length;
    }
}

unittest
{
    ANSIWriterTestSinkState state;
    auto output = Writer.from_sink(&ansi_writer_test_sink, &state);

    static assert(!__traits(compiles, ANSIWriter.from_writer(&output)));
    static assert(__traits(compiles, ANSIWriter.from_writer(&output, false)));
    static assert(!__traits(compiles, () @safe
    {
        Writer local_output;
        return ANSIWriter.from_writer(&local_output, false);
    }));
}

unittest
{
    ANSIWriterTestSinkState state;
    auto output = Writer.from_sink(&ansi_writer_test_sink, &state);
    auto plain = ANSIWriter.from_writer(&output, false);

    assert(!plain.ansi_enabled);
    assert(plain.ok);
    assert(plain.written == 0);

    plain.put('A');
    plain.put("B");
    plain.repeat('c', 2);
    const style = ANSIStyle.foreground(ANSIColor.bright_red).bold;
    plain.styled(" value=", hexadecimal(42), style);

    assert(state.length != 0);
    assert(plain.written == state.length);
    assert(state.storage[0 .. state.length].equal("ABcc value=0x2a"));

    const result = output.result;
    assert(result.ok);
    assert(result.written == state.length);
}

unittest
{
    ANSIWriterTestSinkState state;
    auto output = Writer.from_sink(&ansi_writer_test_sink, &state);
    auto ansi_writer = ANSIWriter.from_writer(&output, true);
    const style = ANSIStyle.foreground(ANSIColor.bright_red).bold;

    assert(ansi_writer.ansi_enabled);
    ansi_writer.styled("value=", 42, '!', style);

    const result = output.result;
    assert(result.ok);
    assert(result.written == state.length);
    assert(state.storage[0 .. state.length].equal("\x1b[1;91mvalue=42!\x1b[0m"));
}

unittest
{
    ANSIWriterTestSinkState state;
    auto output = Writer.from_sink(&ansi_writer_test_sink, &state);
    const style = ANSIStyle.foreground(ANSIColor.bright_red)
        .with_background(ANSIColor.indexed(17))
        .bold
        .underline;

    begin_ansi(output, style);
    output.put("failure");
    reset_ansi(output);

    assert(output.ok);
    assert(state.storage[0 .. state.length].equal("\x1b[1;4;91;48;5;17mfailure\x1b[0m"));
}

unittest
{
    char[128] storage;

    const plain_result = write_buffer(storage[], styled(42, ANSIStyle.init));
    assert(plain_result.ok);
    assert(storage[0 .. plain_result.written].equal("42"));

    const grouped_result = write_buffer(
        storage[],
        styled("value=", 42, '!', ANSIColor.bright_red.foreground),
    );
    assert(grouped_result.ok);
    assert(storage[0 .. grouped_result.written].equal("\x1b[91mvalue=42!\x1b[0m"));

    const formatted_result = write_buffer(
        storage[],
        styled(formatted!"#{}:{}"(7u, 3u), ANSIColor.bright_cyan.foreground.bold),
    );
    assert(formatted_result.ok);
    assert(storage[0 .. formatted_result.written].equal("\x1b[1;96m#7:3\x1b[0m"));
}

unittest
{
    char[32] storage;

    const result = write_buffer(storage[], "value", ansi_reset);

    assert(result.ok);
    assert(storage[0 .. result.written].equal("value\x1b[0m"));
}
