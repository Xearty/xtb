module xtb.core.ansi;

nothrow @nogc:

import xtb.core.flag_set : FlagSet, enable;
import xtb.core.writer : Writer;
import xtb.core.string;

version (XTB_Checked) import xtb.core.panic : require;

/// User policy for OS-aware ANSI capability selection.
enum AnsiMode : ubyte
{
    automatic,
    always,
    never,
}

enum AnsiColorKind : ubyte
{
    none,
    default_,
    basic,
    indexed,
    rgb,
}

/// The sixteen colors in the terminal's configured ANSI palette.
enum AnsiBasicColor : ubyte
{
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    brightBlack,
    brightRed,
    brightGreen,
    brightYellow,
    brightBlue,
    brightMagenta,
    brightCyan,
    brightWhite,
}

/// A terminal color. The zero value means that no color is emitted.
struct AnsiColor
{
nothrow @nogc pure @safe:

    private AnsiColorKind kind_;
    private ubyte first_;
    private ubyte second_;
    private ubyte third_;

    enum default_ = AnsiColor(AnsiColorKind.default_);
    enum black = AnsiColor.basic(AnsiBasicColor.black);
    enum red = AnsiColor.basic(AnsiBasicColor.red);
    enum green = AnsiColor.basic(AnsiBasicColor.green);
    enum yellow = AnsiColor.basic(AnsiBasicColor.yellow);
    enum blue = AnsiColor.basic(AnsiBasicColor.blue);
    enum magenta = AnsiColor.basic(AnsiBasicColor.magenta);
    enum cyan = AnsiColor.basic(AnsiBasicColor.cyan);
    enum white = AnsiColor.basic(AnsiBasicColor.white);
    enum brightBlack = AnsiColor.basic(AnsiBasicColor.brightBlack);
    enum brightRed = AnsiColor.basic(AnsiBasicColor.brightRed);
    enum brightGreen = AnsiColor.basic(AnsiBasicColor.brightGreen);
    enum brightYellow = AnsiColor.basic(AnsiBasicColor.brightYellow);
    enum brightBlue = AnsiColor.basic(AnsiBasicColor.brightBlue);
    enum brightMagenta = AnsiColor.basic(AnsiBasicColor.brightMagenta);
    enum brightCyan = AnsiColor.basic(AnsiBasicColor.brightCyan);
    enum brightWhite = AnsiColor.basic(AnsiBasicColor.brightWhite);

    static AnsiColor basic(AnsiBasicColor color)
    {
        return AnsiColor(AnsiColorKind.basic, cast(ubyte) color);
    }

    static AnsiColor indexed(ubyte index)
    {
        return AnsiColor(AnsiColorKind.indexed, index);
    }

    static AnsiColor rgb(ubyte red, ubyte green, ubyte blue)
    {
        return AnsiColor(AnsiColorKind.rgb, red, green, blue);
    }

    AnsiColorKind kind() const
    {
        return kind_;
    }

    bool enabled() const
    {
        return kind_ != AnsiColorKind.none;
    }
}

enum AnsiAttribute : ubyte
{
    bold = 1,
    dim = 2,
    italic = 3,
    underline = 4,
    blink = 5,
    reverse = 7,
    hidden = 8,
    strikethrough = 9,
}

alias AnsiAttributes = FlagSet!AnsiAttribute;

/// A complete SGR style. Builder operations return changed values.
struct AnsiStyle
{
nothrow @nogc:

    AnsiColor foregroundColor;
    AnsiColor backgroundColor;
    private AnsiAttributes attributes_;

    static AnsiStyle foreground(AnsiColor color)
    pure @safe
    {
        AnsiStyle result;
        result.foregroundColor = color;
        return result;
    }

    static AnsiStyle background(AnsiColor color)
    pure @safe
    {
        AnsiStyle result;
        result.backgroundColor = color;
        return result;
    }

    AnsiStyle withForeground(AnsiColor color) const
    pure @safe
    {
        AnsiStyle result = this;
        result.foregroundColor = color;
        return result;
    }

    AnsiStyle withBackground(AnsiColor color) const
    pure @safe
    {
        AnsiStyle result = this;
        result.backgroundColor = color;
        return result;
    }

    AnsiStyle withAttribute(AnsiAttribute attribute) const
    @safe
    {
        AnsiStyle result = this;
        result.attributes_.enable(attribute);
        return result;
    }

    bool has(AnsiAttribute attribute) const
    @safe
    {
        return attributes_.contains(attribute);
    }

    bool enabled() const
    pure @safe
    {
        return !attributes_.isEmpty || foregroundColor.enabled ||
            backgroundColor.enabled;
    }

    @property AnsiStyle bold() const
    @safe
    {
        return withAttribute(AnsiAttribute.bold);
    }

    @property AnsiStyle dim() const
    @safe
    {
        return withAttribute(AnsiAttribute.dim);
    }

    @property AnsiStyle italic() const
    @safe
    {
        return withAttribute(AnsiAttribute.italic);
    }

    @property AnsiStyle underline() const
    @safe
    {
        return withAttribute(AnsiAttribute.underline);
    }

    @property AnsiStyle blink() const
    @safe
    {
        return withAttribute(AnsiAttribute.blink);
    }

    @property AnsiStyle reverse() const
    @safe
    {
        return withAttribute(AnsiAttribute.reverse);
    }

    @property AnsiStyle hidden() const
    @safe
    {
        return withAttribute(AnsiAttribute.hidden);
    }

    @property AnsiStyle strikethrough() const
    @safe
    {
        return withAttribute(AnsiAttribute.strikethrough);
    }

    void formatTo(ref Writer writer) const
    {
        writer.beginAnsi(this);
    }
}

/// A stack-owned, allocation-free encoded ANSI control sequence.
struct AnsiSequence
{
nothrow @nogc pure @safe:

    enum capacity = 96;

    private char[capacity] bytes_;
    private ubyte length_;

    String view() const return @trusted
    {
        return bytes_[0 .. length_];
    }

    bool empty() const
    {
        return length_ == 0;
    }
}

struct AnsiReset
{
nothrow @nogc:

    void formatTo(ref Writer writer) const
    {
        writer.resetAnsi();
    }
}

enum ansiReset = AnsiReset.init;

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

    /// Writes one or more ordinary `Writer.value` values under `style`.
    /// When ANSI is disabled, this is exactly equivalent to writing the values
    /// without styling. The emitted reset is a full SGR reset, so this helper
    /// intentionally does not expose nestable begin/end style scopes.
    void styled(Values...)(AnsiStyle style, auto ref Values values) if (Values.length != 0)
    {
        if (ansiEnabled_)
            beginAnsi(*writer_, style);

        static foreach (index; 0 .. Values.length)
            writer_.value(values[index]);

        if (ansiEnabled_)
            endAnsi(*writer_, style);
    }
}

private void append(ref AnsiSequence sequence, char value)
pure @safe
{
    assert(sequence.length_ < sequence.bytes_.length);
    sequence.bytes_[sequence.length_++] = value;
}

private void append(ref AnsiSequence sequence, String value)
pure @safe
{
    foreach (character; value)
        sequence.append(character);
}

private void appendDecimal(ref AnsiSequence sequence, ubyte value)
pure @safe
{
    char[3] reversed;
    ubyte count;
    do
    {
        reversed[count++] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    while (count != 0)
        sequence.append(reversed[--count]);
}

private void appendParameter(ref AnsiSequence sequence, ubyte value, bool* first)
pure @safe
{
    if (!*first)
        sequence.append(';');
    *first = false;
    sequence.appendDecimal(value);
}

private void appendColor(
    ref AnsiSequence sequence,
    AnsiColor color,
    bool background,
    bool* first,
) pure @safe
{
    final switch (color.kind_)
    {
        case AnsiColorKind.none:
            return;
        case AnsiColorKind.default_:
            sequence.appendParameter(background ? 49 : 39, first);
            return;
        case AnsiColorKind.basic:
            const bright = color.first_ >= 8;
            const base = background
                ? (bright ? 100 : 40) : (bright ? 90 : 30);
            sequence.appendParameter(
                cast(ubyte)(base + color.first_ % 8),
                first,
            );
            return;
        case AnsiColorKind.indexed:
            sequence.appendParameter(background ? 48 : 38, first);
            sequence.appendParameter(5, first);
            sequence.appendParameter(color.first_, first);
            return;
        case AnsiColorKind.rgb:
            sequence.appendParameter(background ? 48 : 38, first);
            sequence.appendParameter(2, first);
            sequence.appendParameter(color.first_, first);
            sequence.appendParameter(color.second_, first);
            sequence.appendParameter(color.third_, first);
            return;
    }
}

AnsiSequence ansiSequence(AnsiStyle style)
@safe
{
    AnsiSequence result;
    if (!style.enabled)
        return result;

    result.append("\x1b[");
    bool first = true;
    static foreach (name; __traits(allMembers, AnsiAttribute))
    {
        if (style.has(__traits(getMember, AnsiAttribute, name)))
            result.appendParameter(
                cast(ubyte) __traits(getMember, AnsiAttribute, name),
                &first,
            );
    }
    result.appendColor(style.foregroundColor, false, &first);
    result.appendColor(style.backgroundColor, true, &first);
    result.append('m');
    return result;
}

AnsiSequence ansiResetSequence()
pure @safe
{
    AnsiSequence result;
    result.append("\x1b[0m");
    return result;
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
    import xtb.core.writer : hexadecimal;

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
    plain.styled(
        AnsiStyle.foreground(AnsiColor.brightRed).bold,
        " value=",
        hexadecimal(42),
    );
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
    styled.styled(style, "value=", 42, '!');
    const styledResult = output.result;
    assert(styledResult.ok);
    assert(styledResult.written == state.length);
    assert(state.storage[0 .. state.length].equal(
            "\x1b[1;91mvalue=42!\x1b[0m",
    ));
}

unittest
{
    import xtb.core.print : writeBuffer;
    import xtb.core.string;

    char[128] storage;
    const style = AnsiStyle.foreground(AnsiColor.brightRed)
        .withBackground(AnsiColor.indexed(17))
        .bold
        .underline;
    const result = writeBuffer(storage[], style, "failure", ansiReset);
    assert(result.ok);
    assert(storage[0 .. result.written].equal(
            "\x1b[1;4;91;48;5;17mfailure\x1b[0m",
    ));

    const rgb = ansiSequence(AnsiStyle.foreground(AnsiColor.rgb(1, 20, 255)));
    assert(rgb.view.equal("\x1b[38;2;1;20;255m"));
    const standard = ansiSequence(
        AnsiStyle.foreground(AnsiColor.red)
            .withBackground(AnsiColor.blue),
    );
    assert(standard.view.equal("\x1b[31;44m"));
    const terminalDefaults = ansiSequence(
        AnsiStyle.foreground(AnsiColor.default_)
            .withBackground(AnsiColor.default_),
    );
    assert(terminalDefaults.view.equal("\x1b[39;49m"));

    AnsiStyle attributes;
    static foreach (name; __traits(allMembers, AnsiAttribute))
        attributes = attributes.withAttribute(
            __traits(getMember, AnsiAttribute, name),
        );
    assert(ansiSequence(attributes).view.equal("\x1b[1;2;3;4;5;7;8;9m"));
    assert(ansiSequence(AnsiStyle.init).empty);
    assert(style.has(AnsiAttribute.bold));
    assert(style.has(AnsiAttribute.underline));
    assert(!style.has(AnsiAttribute.italic));
}
