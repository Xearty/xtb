module xtb.log.palette;

nothrow @nogc:

import xtb.ansi;
import xtb.log.level;
import xtb.types;

struct LogLevelStyle
{
    ANSIStyle label;
    ANSIStyle message;
}

/// Built-in log palette choices.
///
/// `basic` uses only the terminal's sixteen configurable ANSI colors and keeps
/// message text unstyled. `extended` uses the 256-color palette and shades
/// message text by severity. `true_color` uses RGB colors and the same severity
/// brightness progression. The two enhanced presets target dark backgrounds.
enum LogPalettePreset : u8
{
    basic,
    extended,
    true_color,
}

/// Presentation styles selected by log level. The zero value is uncolored.
struct LogPalette
{
nothrow @nogc:

    LogLevelStyle trace;
    LogLevelStyle debug_;
    LogLevelStyle info;
    LogLevelStyle warning;
    LogLevelStyle error;
    LogLevelStyle fatal;

    /// Returns one of the built-in palettes.
    static LogPalette preset(LogPalettePreset preset) @safe
    {
        final switch (preset)
        {
        case LogPalettePreset.basic:
            return LogPalette.basic_preset();
        case LogPalettePreset.extended:
            return LogPalette.extended_preset();
        case LogPalettePreset.true_color:
            return LogPalette.true_color_preset();
        }
    }

    private static LogPalette basic_preset() @safe
    {
        LogPalette result;
        result.trace.label = ANSIStyle.foreground(ANSIColor.bright_black);
        result.debug_.label = ANSIStyle.foreground(ANSIColor.bright_blue);
        result.info.label = ANSIStyle.foreground(ANSIColor.green);
        result.warning.label = ANSIStyle.foreground(ANSIColor.yellow);
        result.error.label = ANSIStyle.foreground(ANSIColor.bright_red);
        result.fatal.label = ANSIStyle.foreground(ANSIColor.bright_red).bold;
        return result;
    }

    private static LogPalette extended_preset() @safe
    {
        LogPalette result;
        result.trace = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.indexed(244)).dim,
            ANSIStyle.foreground(ANSIColor.indexed(242)),
        );
        result.debug_ = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.indexed(75)),
            ANSIStyle.foreground(ANSIColor.indexed(244)),
        );
        result.info = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.indexed(42)),
            ANSIStyle.foreground(ANSIColor.indexed(246)),
        );
        result.warning = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.indexed(214)).bold,
            ANSIStyle.foreground(ANSIColor.indexed(248)),
        );
        result.error = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.indexed(203)),
            ANSIStyle.foreground(ANSIColor.indexed(250)),
        );
        result.fatal = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.indexed(231))
                .with_background(ANSIColor.indexed(160))
                .bold,
            ANSIStyle.foreground(ANSIColor.indexed(255)),
        );
        return result;
    }

    private static LogPalette true_color_preset() @safe
    {
        LogPalette result;
        result.trace = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.rgb(128, 128, 128)).dim,
            ANSIStyle.foreground(ANSIColor.rgb(105, 110, 120)),
        );
        result.debug_ = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.rgb(198, 120, 221)),
            ANSIStyle.foreground(ANSIColor.rgb(125, 130, 140)),
        );
        result.info = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.rgb(86, 182, 194)),
            ANSIStyle.foreground(ANSIColor.rgb(150, 155, 165)),
        );
        result.warning = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.rgb(255, 175, 0)).bold,
            ANSIStyle.foreground(ANSIColor.rgb(175, 180, 190)),
        );
        result.error = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.rgb(255, 95, 95)),
            ANSIStyle.foreground(ANSIColor.rgb(205, 210, 220)),
        );
        result.fatal = LogLevelStyle(
            ANSIStyle.foreground(ANSIColor.rgb(255, 255, 255))
                .with_background(ANSIColor.rgb(190, 48, 48))
                .bold,
            ANSIStyle.foreground(ANSIColor.rgb(238, 240, 245)),
        );
        return result;
    }

    /// Returns the portable sixteen-color palette.
    static LogPalette defaults() @safe
    {
        return LogPalette.preset(LogPalettePreset.basic);
    }

    LogLevelStyle style_for(LogLevel level) const pure @safe
    {
        final switch (level)
        {
        case LogLevel.trace:
            return this.trace;
        case LogLevel.debug_:
            return this.debug_;
        case LogLevel.info:
            return this.info;
        case LogLevel.warning:
            return this.warning;
        case LogLevel.error:
            return this.error;
        case LogLevel.fatal:
            return this.fatal;
        }
    }
}

unittest
{
    import xtb.string;

    const basic = LogPalette.preset(LogPalettePreset.basic);
    assert(LogPalette.defaults() == basic);
    assert(ansi_sequence(basic.trace.label).view.equal("\x1b[90m"));
    assert(ansi_sequence(basic.debug_.label).view.equal("\x1b[94m"));
    assert(ansi_sequence(basic.info.label).view.equal("\x1b[32m"));
    assert(ansi_sequence(basic.warning.label).view.equal("\x1b[33m"));
    assert(ansi_sequence(basic.error.label).view.equal("\x1b[91m"));
    assert(ansi_sequence(basic.fatal.label).view.equal("\x1b[1;91m"));
    assert(!basic.trace.message.enabled);
    assert(!basic.debug_.message.enabled);
    assert(!basic.info.message.enabled);
    assert(!basic.warning.message.enabled);
    assert(!basic.error.message.enabled);
    assert(!basic.fatal.message.enabled);

    const extended = LogPalette.preset(LogPalettePreset.extended);
    assert(ansi_sequence(extended.trace.label).view.equal("\x1b[2;38;5;244m"));
    assert(ansi_sequence(extended.debug_.label).view.equal("\x1b[38;5;75m"));
    assert(ansi_sequence(extended.info.label).view.equal("\x1b[38;5;42m"));
    assert(ansi_sequence(extended.warning.label).view.equal("\x1b[1;38;5;214m"));
    assert(ansi_sequence(extended.error.label).view.equal("\x1b[38;5;203m"));
    assert(ansi_sequence(extended.fatal.label).view.equal(
        "\x1b[1;38;5;231;48;5;160m",
    ));
    assert(ansi_sequence(extended.trace.message).view.equal("\x1b[38;5;242m"));
    assert(ansi_sequence(extended.debug_.message).view.equal("\x1b[38;5;244m"));
    assert(ansi_sequence(extended.info.message).view.equal("\x1b[38;5;246m"));
    assert(ansi_sequence(extended.warning.message).view.equal("\x1b[38;5;248m"));
    assert(ansi_sequence(extended.error.message).view.equal("\x1b[38;5;250m"));
    assert(ansi_sequence(extended.fatal.message).view.equal("\x1b[38;5;255m"));

    const true_color = LogPalette.preset(LogPalettePreset.true_color);
    assert(ansi_sequence(true_color.trace.label).view.equal("\x1b[2;38;2;128;128;128m"));
    assert(ansi_sequence(true_color.debug_.label).view.equal("\x1b[38;2;198;120;221m"));
    assert(ansi_sequence(true_color.info.label).view.equal("\x1b[38;2;86;182;194m"));
    assert(ansi_sequence(true_color.warning.label).view.equal("\x1b[1;38;2;255;175;0m"));
    assert(ansi_sequence(true_color.error.label).view.equal("\x1b[38;2;255;95;95m"));
    assert(ansi_sequence(true_color.fatal.label).view.equal(
        "\x1b[1;38;2;255;255;255;48;2;190;48;48m",
    ));
    assert(ansi_sequence(true_color.trace.message).view.equal("\x1b[38;2;105;110;120m"));
    assert(ansi_sequence(true_color.debug_.message).view.equal("\x1b[38;2;125;130;140m"));
    assert(ansi_sequence(true_color.info.message).view.equal("\x1b[38;2;150;155;165m"));
    assert(ansi_sequence(true_color.warning.message).view.equal("\x1b[38;2;175;180;190m"));
    assert(ansi_sequence(true_color.error.message).view.equal("\x1b[38;2;205;210;220m"));
    assert(ansi_sequence(true_color.fatal.message).view.equal("\x1b[38;2;238;240;245m"));
}
