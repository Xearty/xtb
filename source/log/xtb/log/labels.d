module xtb.log.labels;

nothrow @nogc:

import xtb.log.level;
import xtb.types;

/// Built-in level-label spellings.
///
/// `full` uses the ordinary lowercase level names. `three_letter` uses compact
/// uppercase abbreviations. Each preset includes the surrounding brackets.
enum LogLevelLabelPreset : u8
{
    full,
    three_letter,
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
    static LogLevelLabels preset(LogLevelLabelPreset preset) pure @safe
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
        case LogLevelLabelPreset.three_letter:
            return LogLevelLabels("[TRC]", "[DBG]", "[INF]", "[WRN]", "[ERR]", "[FTL]");
        }
    }

    /// Returns the ordinary full-name label set.
    static LogLevelLabels defaults() pure @safe
    {
        return LogLevelLabels.preset(LogLevelLabelPreset.full);
    }

    String label_for(LogLevel level) const pure @safe
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

    /// Returns the widest configured label in bytes.
    usize maximum_width() const pure @safe
    {
        usize result = this.trace.length;
        if (this.debug_.length > result) result = this.debug_.length;
        if (this.info.length > result) result = this.info.length;
        if (this.warning.length > result) result = this.warning.length;
        if (this.error.length > result) result = this.error.length;
        if (this.fatal.length > result) result = this.fatal.length;

        return result;
    }
}

unittest
{
    import xtb.string;

    const full = LogLevelLabels.defaults();
    assert(full.label_for(LogLevel.trace).equal("[trace]"));
    assert(full.label_for(LogLevel.fatal).equal("[fatal]"));
    assert(full.maximum_width == "[warning]".length);

    const compact = LogLevelLabels.preset(LogLevelLabelPreset.three_letter);
    assert(compact.label_for(LogLevel.trace).equal("[TRC]"));
    assert(compact.label_for(LogLevel.debug_).equal("[DBG]"));
    assert(compact.label_for(LogLevel.info).equal("[INF]"));
    assert(compact.label_for(LogLevel.warning).equal("[WRN]"));
    assert(compact.label_for(LogLevel.error).equal("[ERR]"));
    assert(compact.label_for(LogLevel.fatal).equal("[FTL]"));
    assert(compact.maximum_width == "[TRC]".length);
}
