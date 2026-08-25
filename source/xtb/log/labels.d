module xtb.log.labels;

nothrow @nogc:

import xtb.log.level : LogLevel;
import xtb.core.string : String;

/// Built-in level-label spellings.
///
/// `full` uses the ordinary lowercase level names. `threeLetter` uses compact
/// uppercase abbreviations. Each preset includes the surrounding brackets.
enum LogLevelLabelPreset : ubyte
{
    full,
    threeLetter,
}

/// Complete presentation labels selected by log level.
///
/// Each field is emitted exactly as supplied; custom labels may change or omit
/// the conventional brackets. The referenced bytes must outlive every `Logger`
/// configured with this value.
struct LogLevelLabels
{
nothrow @nogc:

    String trace;
    String debug_;
    String info;
    String warning;
    String error;
    String fatal;

    /// Returns one of the built-in label sets.
    static LogLevelLabels preset(LogLevelLabelPreset preset)
    pure @safe
    {
        final switch (preset)
        {
            case LogLevelLabelPreset.full:
                return LogLevelLabels(
                    "[trace]",
                    "[debug]",
                    "[info]",
                    "[warning]",
                    "[error]",
                    "[fatal]",
                );
            case LogLevelLabelPreset.threeLetter:
                return LogLevelLabels(
                    "[TRC]",
                    "[DBG]",
                    "[INF]",
                    "[WRN]",
                    "[ERR]",
                    "[FTL]",
                );
        }
    }

    /// Returns the ordinary full-name label set.
    static LogLevelLabels defaults()
    pure @safe
    {
        return preset(LogLevelLabelPreset.full);
    }

    String labelFor(LogLevel level) const
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

    /// Returns the widest configured label in bytes.
    size_t maximumWidth() const
    pure @safe
    {
        size_t result = trace.length;
        if (debug_.length > result)
            result = debug_.length;
        if (info.length > result)
            result = info.length;
        if (warning.length > result)
            result = warning.length;
        if (error.length > result)
            result = error.length;
        if (fatal.length > result)
            result = fatal.length;
        return result;
    }
}

unittest
{
    import xtb.core.string;

    const full = LogLevelLabels.defaults();
    assert(full.labelFor(LogLevel.trace).equal("[trace]"));
    assert(full.labelFor(LogLevel.fatal).equal("[fatal]"));
    assert(full.maximumWidth == "[warning]".length);

    const compact = LogLevelLabels.preset(LogLevelLabelPreset.threeLetter);
    assert(compact.labelFor(LogLevel.trace).equal("[TRC]"));
    assert(compact.labelFor(LogLevel.debug_).equal("[DBG]"));
    assert(compact.labelFor(LogLevel.info).equal("[INF]"));
    assert(compact.labelFor(LogLevel.warning).equal("[WRN]"));
    assert(compact.labelFor(LogLevel.error).equal("[ERR]"));
    assert(compact.labelFor(LogLevel.fatal).equal("[FTL]"));
    assert(compact.maximumWidth == "[TRC]".length);
}
