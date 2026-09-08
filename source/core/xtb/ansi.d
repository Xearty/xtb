module xtb.ansi;

nothrow @nogc:

import xtb.flag_set;
import xtb.types;

enum ANSIColorKind : u8
{
    none,
    default_,
    basic,
    indexed,
    rgb,
}

/// The sixteen colors in the terminal's configured ANSI palette.
enum ANSIBasicColor : u8
{
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
}

/// A terminal color. The zero value means that no color is emitted.
///
/// `kind` selects how `first`, `second`, and `third` are interpreted. Values
/// created through the factories below always preserve that representation.
struct ANSIColor
{
nothrow @nogc pure @safe:

    ANSIColorKind kind;
    u8 first;
    u8 second;
    u8 third;

    enum default_ = ANSIColor(ANSIColorKind.default_);
    enum black = ANSIColor.basic(ANSIBasicColor.black);
    enum red = ANSIColor.basic(ANSIBasicColor.red);
    enum green = ANSIColor.basic(ANSIBasicColor.green);
    enum yellow = ANSIColor.basic(ANSIBasicColor.yellow);
    enum blue = ANSIColor.basic(ANSIBasicColor.blue);
    enum magenta = ANSIColor.basic(ANSIBasicColor.magenta);
    enum cyan = ANSIColor.basic(ANSIBasicColor.cyan);
    enum white = ANSIColor.basic(ANSIBasicColor.white);
    enum bright_black = ANSIColor.basic(ANSIBasicColor.bright_black);
    enum bright_red = ANSIColor.basic(ANSIBasicColor.bright_red);
    enum bright_green = ANSIColor.basic(ANSIBasicColor.bright_green);
    enum bright_yellow = ANSIColor.basic(ANSIBasicColor.bright_yellow);
    enum bright_blue = ANSIColor.basic(ANSIBasicColor.bright_blue);
    enum bright_magenta = ANSIColor.basic(ANSIBasicColor.bright_magenta);
    enum bright_cyan = ANSIColor.basic(ANSIBasicColor.bright_cyan);
    enum bright_white = ANSIColor.basic(ANSIBasicColor.bright_white);

    static ANSIColor basic(ANSIBasicColor color)
    {
        return ANSIColor(ANSIColorKind.basic, cast(u8) color);
    }

    static ANSIColor indexed(u8 index)
    {
        return ANSIColor(ANSIColorKind.indexed, index);
    }

    static ANSIColor rgb(u8 red, u8 green, u8 blue)
    {
        return ANSIColor(ANSIColorKind.rgb, red, green, blue);
    }

    /// Creates a style that uses this color as its foreground.
    @property ANSIStyle foreground() const
    {
        return ANSIStyle.foreground(this);
    }

    /// Creates a style that uses this color as its background.
    @property ANSIStyle background() const
    {
        return ANSIStyle.background(this);
    }

    bool enabled() const
    {
        return this.kind != ANSIColorKind.none;
    }
}

enum ANSIAttribute : u8
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

alias ANSIAttributes = FlagSet!ANSIAttribute;

/// A complete SGR style. Builder operations return changed values.
struct ANSIStyle
{
nothrow @nogc:

    ANSIColor foreground_color;
    ANSIColor background_color;
    ANSIAttributes attributes;

    static ANSIStyle foreground(ANSIColor color) pure @safe
    {
        return ANSIStyle(foreground_color: color);
    }

    static ANSIStyle background(ANSIColor color) pure @safe
    {
        return ANSIStyle(background_color: color);
    }

    ANSIStyle with_foreground(ANSIColor color) const pure @safe
    {
        ANSIStyle result = this;
        result.foreground_color = color;
        return result;
    }

    ANSIStyle with_background(ANSIColor color) const pure @safe
    {
        ANSIStyle result = this;
        result.background_color = color;
        return result;
    }

    ANSIStyle with_attribute(ANSIAttribute attribute) const @safe
    {
        ANSIStyle result = this;
        result.attributes.enable(attribute);
        return result;
    }

    bool has(ANSIAttribute attribute) const @safe
    {
        return this.attributes.contains(attribute);
    }

    bool enabled() const pure @safe
    {
        return !this.attributes.is_empty
            || this.foreground_color.enabled
            || this.background_color.enabled;
    }

    @property ANSIStyle bold() const @safe
    {
        return this.with_attribute(ANSIAttribute.bold);
    }

    @property ANSIStyle dim() const @safe
    {
        return this.with_attribute(ANSIAttribute.dim);
    }

    @property ANSIStyle italic() const @safe
    {
        return this.with_attribute(ANSIAttribute.italic);
    }

    @property ANSIStyle underline() const @safe
    {
        return this.with_attribute(ANSIAttribute.underline);
    }

    @property ANSIStyle blink() const @safe
    {
        return this.with_attribute(ANSIAttribute.blink);
    }

    @property ANSIStyle reverse() const @safe
    {
        return this.with_attribute(ANSIAttribute.reverse);
    }

    @property ANSIStyle hidden() const @safe
    {
        return this.with_attribute(ANSIAttribute.hidden);
    }

    @property ANSIStyle strikethrough() const @safe
    {
        return this.with_attribute(ANSIAttribute.strikethrough);
    }
}

/// A stack-owned, allocation-free encoded ANSI control sequence.
///
/// `length` is the initialized prefix of `bytes` and must not exceed its
/// capacity. `view` borrows that prefix from the sequence.
struct ANSISequence
{
nothrow @nogc @safe:

    enum usize capacity = 96;

    char[capacity] bytes;
    usize length;

    String view() const return pure
    {
        // `length` is public representation state. Clamp a malformed value so
        // the returned slice remains within `bytes` in every build mode.
        const end = this.length <= ANSISequence.capacity
            ? this.length
            : ANSISequence.capacity;
        return this.bytes[0 .. end];
    }

    bool empty() const pure
    {
        return this.length == 0;
    }

    private void append(char value)
    {
        this.bytes[this.length++] = value;
    }

    private void append(String value)
    {
        foreach (character; value)
            this.append(character);
    }

    private void append_decimal(u8 value)
    {
        char[3] reversed;
        usize count;
        do
        {
            reversed[count++] = cast(char)('0' + value % 10);
            value /= 10;
        }
        while (value != 0);

        while (count != 0)
            this.append(reversed[--count]);
    }

    private void append_parameter(u8 value, scope bool* first)
    {
        if (!*first) this.append(';');

        *first = false;
        this.append_decimal(value);
    }

    private void append_color(ANSIColor color, bool background, scope bool* first)
    {
        final switch (color.kind)
        {
        case ANSIColorKind.none:
            return;
        case ANSIColorKind.default_:
            this.append_parameter(background ? 49 : 39, first);
            return;
        case ANSIColorKind.basic:
            const bright = color.first >= 8;
            const base = background ? (bright ? 100 : 40) : (bright ? 90 : 30);
            this.append_parameter(cast(u8)(base + color.first % 8), first);
            return;
        case ANSIColorKind.indexed:
            this.append_parameter(background ? 48 : 38, first);
            this.append_parameter(5, first);
            this.append_parameter(color.first, first);
            return;
        case ANSIColorKind.rgb:
            this.append_parameter(background ? 48 : 38, first);
            this.append_parameter(2, first);
            this.append_parameter(color.first, first);
            this.append_parameter(color.second, first);
            this.append_parameter(color.third, first);
            return;
        }
    }
}

ANSISequence ansi_sequence(ANSIStyle style) @safe
{
    ANSISequence result;
    if (!style.enabled) return result;

    result.append("\x1b[");
    bool first = true;
    static foreach (name; __traits(allMembers, ANSIAttribute))
    {
        if (style.has(__traits(getMember, ANSIAttribute, name)))
        {
            result.append_parameter(cast(u8) __traits(getMember, ANSIAttribute, name), &first);
        }
    }

    result.append_color(style.foreground_color, false, &first);
    result.append_color(style.background_color, true, &first);
    result.append('m');
    return result;
}

ANSISequence ansi_reset_sequence() pure @safe
{
    ANSISequence result;
    result.bytes[0 .. 4] = "\x1b[0m";
    result.length = 4;
    return result;
}

version (unittest)
{
    import xtb.string;
}

unittest
{
    const standard = ansi_sequence(
        ANSIStyle.foreground(ANSIColor.red).with_background(ANSIColor.blue),
    );
    assert(standard.view.equal("\x1b[31;44m"));
    assert(ansi_sequence(ANSIColor.bright_red.foreground.bold).view.equal("\x1b[1;91m"));
    assert(ansi_sequence(ANSIColor.blue.background).view.equal("\x1b[44m"));

    const rgb = ansi_sequence(ANSIStyle.foreground(ANSIColor.rgb(1, 20, 255)));
    assert(rgb.view.equal("\x1b[38;2;1;20;255m"));

    const terminal_defaults = ansi_sequence(
        ANSIStyle.foreground(ANSIColor.default_).with_background(ANSIColor.default_),
    );
    assert(terminal_defaults.view.equal("\x1b[39;49m"));
}

unittest
{
    const style = ANSIStyle.foreground(ANSIColor.bright_red)
        .with_background(ANSIColor.indexed(17))
        .bold
        .underline;
    assert(ansi_sequence(style).view.equal("\x1b[1;4;91;48;5;17m"));
    assert(style.has(ANSIAttribute.bold));
    assert(style.has(ANSIAttribute.underline));
    assert(!style.has(ANSIAttribute.italic));

    ANSIStyle attributes;
    static foreach (name; __traits(allMembers, ANSIAttribute))
        attributes = attributes.with_attribute(__traits(getMember, ANSIAttribute, name));

    assert(ansi_sequence(attributes).view.equal("\x1b[1;2;3;4;5;7;8;9m"));
}

unittest
{
    assert(ansi_sequence(ANSIStyle.init).empty);
}

unittest
{
    assert(ansi_reset_sequence().view.equal("\x1b[0m"));
}

unittest
{
    ANSISequence malformed;
    malformed.length = ANSISequence.capacity + 1;

    assert(malformed.view.length == ANSISequence.capacity);
}
