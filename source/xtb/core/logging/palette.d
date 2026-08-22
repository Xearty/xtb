module xtb.core.logging.palette;

nothrow @nogc:

import xtb.core.ansi : AnsiColor, AnsiStyle, ansiSequence;
import xtb.core.logging.level : LogLevel;
import xtb.core.string;

struct LogLevelStyle
{
    AnsiStyle label;
    AnsiStyle message;
}

/// Built-in log palette choices.
///
/// `basic` uses only the terminal's sixteen configurable ANSI colors and keeps
/// message text unstyled. `extended` uses the 256-color palette and shades
/// message text by severity. `trueColor` uses RGB colors and the same severity
/// brightness progression. The two enhanced presets target dark backgrounds.
enum LogPalettePreset : ubyte
{
    basic,
    extended,
    trueColor,
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
    static LogPalette preset(LogPalettePreset preset)
    @safe
    {
        final switch (preset)
        {
            case LogPalettePreset.basic:
                return basicPreset();
            case LogPalettePreset.extended:
                return extendedPreset();
            case LogPalettePreset.trueColor:
                return trueColorPreset();
        }
    }

    private static LogPalette basicPreset()
    @safe
    {
        LogPalette result;
        result.trace.label = AnsiStyle.foreground(AnsiColor.brightBlack);
        result.debug_.label = AnsiStyle.foreground(AnsiColor.brightBlue);
        result.info.label = AnsiStyle.foreground(AnsiColor.green);
        result.warning.label = AnsiStyle.foreground(AnsiColor.yellow);
        result.error.label = AnsiStyle.foreground(AnsiColor.brightRed);
        result.fatal.label = AnsiStyle.foreground(AnsiColor.brightRed).bold;
        return result;
    }

    private static LogPalette extendedPreset()
    @safe
    {
        LogPalette result;
        result.trace = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(244)).dim,
            AnsiStyle.foreground(AnsiColor.indexed(242)),
        );
        result.debug_ = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(75)),
            AnsiStyle.foreground(AnsiColor.indexed(244)),
        );
        result.info = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(42)),
            AnsiStyle.foreground(AnsiColor.indexed(246)),
        );
        result.warning = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(214)).bold,
            AnsiStyle.foreground(AnsiColor.indexed(248)),
        );
        result.error = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(203)),
            AnsiStyle.foreground(AnsiColor.indexed(250)),
        );
        result.fatal = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(231))
                .withBackground(AnsiColor.indexed(160))
                .bold,
            AnsiStyle.foreground(AnsiColor.indexed(255)),
        );
        return result;
    }

    private static LogPalette trueColorPreset()
    @safe
    {
        LogPalette result;
        result.trace = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(128, 128, 128)).dim,
            AnsiStyle.foreground(AnsiColor.rgb(105, 110, 120)),
        );
        result.debug_ = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(198, 120, 221)),
            AnsiStyle.foreground(AnsiColor.rgb(125, 130, 140)),
        );
        result.info = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(86, 182, 194)),
            AnsiStyle.foreground(AnsiColor.rgb(150, 155, 165)),
        );
        result.warning = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(255, 175, 0)).bold,
            AnsiStyle.foreground(AnsiColor.rgb(175, 180, 190)),
        );
        result.error = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(255, 95, 95)),
            AnsiStyle.foreground(AnsiColor.rgb(205, 210, 220)),
        );
        result.fatal = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(255, 255, 255))
                .withBackground(AnsiColor.rgb(190, 48, 48))
                .bold,
            AnsiStyle.foreground(AnsiColor.rgb(238, 240, 245)),
        );
        return result;
    }

    /// Returns the portable sixteen-color palette.
    static LogPalette defaults()
    @safe
    {
        return preset(LogPalettePreset.basic);
    }

    LogLevelStyle styleFor(LogLevel level) const
    pure @safe
    {
        final switch (level)
        {
            case LogLevel.trace:
                return trace;
            case LogLevel.debug_:
                return debug_;
            case LogLevel.info:
                return info;
            case LogLevel.warning:
                return warning;
            case LogLevel.error:
                return error;
            case LogLevel.fatal:
                return fatal;
        }
    }
}

unittest
{
    const basic = LogPalette.preset(LogPalettePreset.basic);
    assert(LogPalette.defaults() == basic);
    assert(ansiSequence(basic.trace.label).view.equal("\x1b[90m"));
    assert(ansiSequence(basic.debug_.label).view.equal("\x1b[94m"));
    assert(ansiSequence(basic.info.label).view.equal("\x1b[32m"));
    assert(ansiSequence(basic.warning.label).view.equal("\x1b[33m"));
    assert(ansiSequence(basic.error.label).view.equal("\x1b[91m"));
    assert(ansiSequence(basic.fatal.label).view.equal("\x1b[1;91m"));
    assert(!basic.trace.message.enabled);
    assert(!basic.debug_.message.enabled);
    assert(!basic.info.message.enabled);
    assert(!basic.warning.message.enabled);
    assert(!basic.error.message.enabled);
    assert(!basic.fatal.message.enabled);

    const extended = LogPalette.preset(LogPalettePreset.extended);
    assert(ansiSequence(extended.trace.label).view.equal("\x1b[2;38;5;244m"));
    assert(ansiSequence(extended.debug_.label).view.equal("\x1b[38;5;75m"));
    assert(ansiSequence(extended.info.label).view.equal("\x1b[38;5;42m"));
    assert(ansiSequence(extended.warning.label).view.equal("\x1b[1;38;5;214m"));
    assert(ansiSequence(extended.error.label).view.equal("\x1b[38;5;203m"));
    assert(ansiSequence(extended.fatal.label).view.equal(
            "\x1b[1;38;5;231;48;5;160m",
    ));
    assert(ansiSequence(extended.trace.message).view.equal("\x1b[38;5;242m"));
    assert(ansiSequence(extended.debug_.message).view.equal("\x1b[38;5;244m"));
    assert(ansiSequence(extended.info.message).view.equal("\x1b[38;5;246m"));
    assert(ansiSequence(extended.warning.message).view.equal("\x1b[38;5;248m"));
    assert(ansiSequence(extended.error.message).view.equal("\x1b[38;5;250m"));
    assert(ansiSequence(extended.fatal.message).view.equal("\x1b[38;5;255m"));

    const trueColor = LogPalette.preset(LogPalettePreset.trueColor);
    assert(ansiSequence(trueColor.trace.label).view.equal("\x1b[2;38;2;128;128;128m"));
    assert(ansiSequence(trueColor.debug_.label).view.equal("\x1b[38;2;198;120;221m"));
    assert(ansiSequence(trueColor.info.label).view.equal("\x1b[38;2;86;182;194m"));
    assert(ansiSequence(trueColor.warning.label).view.equal("\x1b[1;38;2;255;175;0m"));
    assert(ansiSequence(trueColor.error.label).view.equal("\x1b[38;2;255;95;95m"));
    assert(ansiSequence(trueColor.fatal.label).view.equal(
            "\x1b[1;38;2;255;255;255;48;2;190;48;48m",
    ));
    assert(ansiSequence(trueColor.trace.message).view.equal("\x1b[38;2;105;110;120m"));
    assert(ansiSequence(trueColor.debug_.message).view.equal("\x1b[38;2;125;130;140m"));
    assert(ansiSequence(trueColor.info.message).view.equal("\x1b[38;2;150;155;165m"));
    assert(ansiSequence(trueColor.warning.message).view.equal("\x1b[38;2;175;180;190m"));
    assert(ansiSequence(trueColor.error.message).view.equal("\x1b[38;2;205;210;220m"));
    assert(ansiSequence(trueColor.fatal.message).view.equal("\x1b[38;2;238;240;245m"));
}
