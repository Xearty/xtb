module examples.logging_demo;

import core.stdc.stdio : FILE, fclose, ferror, fread, fwrite, rewind, stderr, tmpfile;
import xtb;
import xtb.log;
import xtb.terminal : shouldUseAnsi;

private struct RequestId
{
    uint value;

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writer.put("request-");
        writer.value(hexadecimal(value).digits(8).upper);
    }
}

private struct FormatProbe
{
    size_t* calls;

    void formatTo(ref Writer writer) nothrow @nogc
    {
        ++*calls;
        writer.put("expensive value");
    }
}

private bool writeTerminal(FILE* terminal, scope String text)
nothrow @nogc
{
    return text.length == 0 || fwrite(text.ptr, 1, text.length, terminal) == text.length;
}

private bool terminalSection(FILE* terminal, scope String title)
nothrow @nogc
{
    return writeTerminal(terminal, "\n=== ") &&
        writeTerminal(terminal, title) &&
        writeTerminal(terminal, " ===\n");
}

private bool copyFileToTerminal(FILE* file, FILE* terminal)
nothrow @nogc
{
    rewind(file);
    char[256] storage;
    while (true)
    {
        const read = fread(storage.ptr, 1, storage.length, file);
        if (read != 0 && fwrite(storage.ptr, 1, read, terminal) != read)
            return false;
        if (read != storage.length)
            return ferror(file) == 0;
    }
}

private bool showcasePrefix(void*, LogPrefixWriter* output)
nothrow @nogc
{
    if (output is null)
        return false;

    return output.write(
        "semantic-prefix ",
        AnsiStyle.foreground(AnsiColor.brightCyan).dim,
    ) && output.writeAnsi("\x1b[35membedded-SGR\x1b[0m ");
}

private bool logEveryLevel(ref Logger logger, String paletteName)
nothrow @nogc
{
    String endpoint = "https://api.example.test/v1/items";
    uint attempt = 2;
    bool delivered = true;
    delivered = logger.trace(paletteName, ": trace details")
        .delivered && delivered;
    delivered = logger.debugf!"{}: worker {} entered queue {}"(
        paletteName,
        3,
        7,
    ).delivered && delivered;
    delivered = logger.info(
        i"$(paletteName): sending attempt $(attempt) to $(endpoint)",
    ).delivered && delivered;
    delivered = logger.warning(paletteName, ": retry budget is ", 1)
        .delivered && delivered;
    delivered = logger.error(
        paletteName,
        ": ",
        styled(
            RequestId(0x2a),
            AnsiStyle.foreground(AnsiColor.brightRed),
    ),
    " failed",
    ).delivered && delivered;
    delivered = logger.fatalf!"{}: subsystem {} is unavailable"(
        paletteName,
        "storage",
    ).delivered && delivered;
    return delivered;
}

private bool logTimestampPalette(
    LogSinkRef presentation,
    LogPalettePreset preset,
    AnsiStyle timestampStyle,
    String paletteName,
)
nothrow @nogc
{
    LogTimestampOptions options = LogTimestampOptions.defaults();
    options.style = timestampStyle;

    TimestampLogPrefix timestamp = TimestampLogPrefix.create(options);
    PrefixLogSink timestamped = PrefixLogSink.create(
        presentation,
        timestamp.prefixRef(),
    );
    char[512] storage;
    Logger logger = Logger.create(
        timestamped.sinkRef(),
        storage[],
        LogLevel.trace,
        LogPalette.preset(preset),
    );
    logger.setCallsitesEnabled(true);

    return logger.logEveryLevel(paletteName) && logger.flush();
}

extern (C) int main() nothrow @nogc
{
    FILE* terminalFile = cast(FILE*) stderr;
    const terminalSupportsAnsi = shouldUseAnsi(terminalFile);
    LogSinkRef terminalPresentation = terminalSupportsAnsi
        ? ansiFileLogSink(terminalFile) : plainFileLogSink(terminalFile);

    // Keep the first section deliberately plain so the contrast with terminal
    // presentation is visible even when this example is run on an ANSI TTY.
    if (!terminalSection(terminalFile, "plain presentation"))
        return 1;
    char[256] plainStorage;
    Logger plain = stderrLogger(
        plainStorage[],
        LogLevel.trace,
        LogStyle.plain,
    );
    if (!plain.info(
            "plain sink: ",
            styled(
            "formatter ANSI is stripped",
            AnsiStyle.foreground(AnsiColor.brightRed).bold,
        ),
        " but the text remains",
        ).delivered || !plain.flush())
        return 1;

    char[512] terminalStorage;
    Logger terminal = Logger.create(
        terminalPresentation,
        terminalStorage[],
        LogLevel.trace,
    );

    // Level-specific helpers, format-string helpers, interpolation, ordinary
    // variadic values, and custom `formatTo` values all share the same path.
    if (!terminalSection(terminalFile, "levels and formatting"))
        return 1;
    terminal.setCallsitesEnabled(true);
    terminal.setPalette(LogPalettePreset.basic);
    if (!terminal.logEveryLevel("basic preset"))
        return 1;

    // Messages align after the natural closing level bracket by default. The
    // option can be disabled when compact, unpadded output is preferred.
    if (!terminalSection(terminalFile, "message alignment"))
        return 1;
    terminal.setCallsitesEnabled(false);
    if (!terminal.info("aligned message").delivered ||
        !terminal.warning("aligned message")
            .delivered ||
            !terminal.fatal("aligned message").delivered)
        return 1;
    terminal.setMessageAlignmentEnabled(false);
    if (!terminal.info("unaligned message").delivered ||
        !terminal.warning("unaligned message")
            .delivered ||
            !terminal.fatal("unaligned message").delivered)
        return 1;
    terminal.setMessageAlignmentEnabled(true);

    // Level spelling is independent from severity colors and message alignment.
    // The compact preset uses equal-width three-letter labels, while custom
    // labels are complete presentation tokens and may use arbitrary spellings.
    if (!terminalSection(terminalFile, "level label presets and customization"))
        return 1;
    terminal.setLevelLabels(LogLevelLabelPreset.threeLetter);
    if (!terminal.logEveryLevel("three-letter labels"))
        return 1;

    LogLevelLabels customLabels = LogLevelLabels.defaults();
    customLabels.trace = "{trace}";
    customLabels.debug_ = "{debug}";
    customLabels.info = "{i}";
    customLabels.warning = "{warning}";
    customLabels.error = "{error}";
    customLabels.fatal = "{FATAL}";
    terminal.setLevelLabels(customLabels);
    if (!terminal.logEveryLevel("custom labels"))
        return 1;

    terminal.setLevelLabels(LogLevelLabelPreset.full);
    terminal.setCallsitesEnabled(true);

    // Enhanced palettes style both the level and message. Presets are normal
    // values, so callers can customize individual severities before use.
    if (!terminalSection(terminalFile, "palette presets"))
        return 1;
    terminal.setPalette(LogPalettePreset.extended);
    if (!terminal.logEveryLevel("extended preset"))
        return 1;
    terminal.setPalette(LogPalettePreset.trueColor);
    if (!terminal.logEveryLevel("true-color preset"))
        return 1;

    LogPalette palette = LogPalette.preset(LogPalettePreset.trueColor);
    palette.warning.label = AnsiStyle.foreground(AnsiColor.brightMagenta).bold;
    palette.warning.message = AnsiStyle.foreground(AnsiColor.rgb(210, 215, 225));
    terminal.setPalette(palette);
    if (!terminal.warning("custom palette: warning label and message override").delivered)
        return 1;

    // Timestamp prefixes and trailing callsites compose with the same palette
    // presets. This section deliberately uses a 16-color, 256-color, and RGB
    // timestamp style so an ANSI terminal shows the complete
    // `timestamp [level] message  (function:line)` presentation under each
    // matching logging color scheme.
    if (!terminalSection(terminalFile, "date/time across color schemes"))
        return 1;
    if (!logTimestampPalette(
            terminalPresentation,
            LogPalettePreset.basic,
            AnsiStyle.foreground(AnsiColor.brightBlack)
            .dim,
            "basic timestamp",
        ) || !logTimestampPalette(
            terminalPresentation,
            LogPalettePreset.extended,
            AnsiStyle.foreground(AnsiColor.indexed(110))
            .dim,
            "extended timestamp",
        ) || !logTimestampPalette(
            terminalPresentation,
            LogPalettePreset.trueColor,
            AnsiStyle.foreground(AnsiColor.rgb(130, 170, 190)).dim,
            "true-color timestamp",
        ))
        return 1;

    // Callsite capture is runtime-configurable and requires no extra argument
    // at the logging call. The trailing context stays neutral/dim on ANSI TTYs.
    if (!terminalSection(terminalFile, "optional callsites"))
        return 1;
    terminal.setCallsitesEnabled(false);
    if (!terminal.info("callsites disabled").delivered)
        return 1;
    terminal.setCallsitesEnabled(true);
    if (!terminal.info("callsites enabled").delivered)
        return 1;

    // Formatter-emitted SGR is preserved by ANSI presentation and stripped by
    // plain presentation. A full reset inside a message restores the palette's
    // configured base message style for the remainder of that message.
    if (!terminalSection(terminalFile, "message ANSI and base-style restoration"))
        return 1;
    terminal.setPalette(LogPalettePreset.extended);
    if (!terminal.info(
            "message styling: ",
            styled(
            "inline magenta",
            AnsiStyle.foreground(AnsiColor.brightMagenta)
            .bold,
        ),
        " then the base message style resumes",
        ).delivered)
        return 1;

    // Filtering happens before custom formatting. `enabled` provides the same
    // cheap decision for guarding application work that should not be computed.
    if (!terminalSection(terminalFile, "filtering"))
        return 1;
    terminal.setMinimumLevel(LogLevel.warning);
    size_t formatCalls;
    FormatProbe probe = FormatProbe(&formatCalls);
    const filtered = terminal.info(probe);
    if (filtered.status != LogStatus.filtered || formatCalls != 0)
        return 1;
    if (!terminal.warningf!"info enabled={} formatter calls={} status=filtered"(
            terminal.enabled(LogLevel.info),
            formatCalls,
        ).delivered)
        return 1;
    terminal.setMinimumLevel(LogLevel.trace);

    // Ordinary logging is bounded by the caller-provided message buffer. The
    // result reports both the safely delivered prefix and the formatter demand.
    if (!terminalSection(terminalFile, "bounded logging and LogResult"))
        return 1;
    char[24] boundedStorage;
    Logger bounded = Logger.create(
        terminalPresentation,
        boundedStorage[],
        LogLevel.info,
        LogPalette.preset(LogPalettePreset.basic),
    );
    bounded.setCallsitesEnabled(true);
    const truncated = bounded.warning(
        "this bounded message is deliberately longer than twenty-four bytes",
    );
    if (truncated.status != LogStatus.truncated)
        return 1;
    if (!terminal.infof!"bounded result: written={} required={} truncated={}"(
            truncated.written,
            truncated.required,
            truncated.status == LogStatus.truncated,
        ).delivered)
        return 1;

    // Streaming keeps one atomic record but uses the logger buffer only as
    // staging. Generic `Writer` formatting and pretty printing can participate
    // while the logical message grows well beyond that tiny staging buffer.
    if (!terminalSection(terminalFile, "unbounded streaming"))
        return 1;
    char[8] streamStorage;
    Logger streaming = Logger.create(
        terminalPresentation,
        streamStorage[],
        LogLevel.info,
        LogPalette.preset(LogPalettePreset.extended),
    );
    streaming.setCallsitesEnabled(true);
    int[12] attemptHistory;
    foreach (index, ref attemptNumber; attemptHistory)
        attemptNumber = cast(int) index + 1;
    const diagnosticPretty = PrettyPrintOptions.defaults()
        .withoutColors()
        .withLayout(PrettyPrintLayout.expanded);
    const streamed = streaming.stream(
        LogLevel.info,
        (scope ref LogMessageWriter output) {
        Writer formatter = output.writer();
        output.write("streamed diagnostic: ");
        formatter.write(RequestId(0x2a), " attempt=", 3, ": ");
        output.write("this message is much larger than eight bytes");
        output.write("\nattempt history: ");
        formatter.write(attemptHistory.pretty(diagnosticPretty));
    },
    );
    if (!streamed.delivered)
        return 1;

    // Prefix providers run once during record setup and write through the
    // resolved presentation path. Semantic styles and explicit embedded SGR
    // therefore work for ANSI sinks and are harmlessly stripped by plain sinks.
    if (!terminalSection(terminalFile, "colored setup prefixes"))
        return 1;
    PrefixLogSink prefixedTerminal = PrefixLogSink.create(
        terminalPresentation,
        LogPrefixRef.create(&showcasePrefix, null),
    );
    char[256] prefixStorage;
    Logger prefixLogger = Logger.create(
        prefixedTerminal.sinkRef(),
        prefixStorage[],
        LogLevel.info,
    );
    prefixLogger.setCallsitesEnabled(true);
    if (!prefixLogger.info("prefixes are emitted before the level").delivered ||
        !prefixLogger.flush())
        return 1;

    // The OS layer provides a ready-made allocation-free timestamp prefix.
    // This configuration demonstrates UTC, milliseconds, a custom separator,
    // and a caller-selected prefix style.
    if (!terminalSection(terminalFile, "timestamp options: UTC + milliseconds"))
        return 1;
    LogTimestampOptions timestampOptions = LogTimestampOptions.defaults();
    timestampOptions.zone = LogTimestampZone.utc;
    timestampOptions.milliseconds = true;
    timestampOptions.separator = " | ";
    timestampOptions.style = AnsiStyle.foreground(AnsiColor.brightBlack).dim;
    TimestampLogPrefix terminalTimestamp = TimestampLogPrefix.create(timestampOptions);
    PrefixLogSink timestampedTerminal = PrefixLogSink.create(
        terminalPresentation,
        terminalTimestamp.prefixRef(),
    );
    char[256] timestampStorage;
    Logger timestampLogger = Logger.create(
        timestampedTerminal.sinkRef(),
        timestampStorage[],
        LogLevel.info,
    );
    timestampLogger.setCallsitesEnabled(true);
    if (!timestampLogger.info("timestamped terminal record").delivered ||
        !timestampLogger.flush())
        return 1;

    // A tee resolves each branch once. Callsite capture remains enabled on the
    // logger, while a setup-only decorator removes it from the terminal branch.
    // The sibling plain-file branch keeps both its timestamp and callsite. The
    // file is echoed afterward so both branch presentations are visible here.
    if (!terminalSection(terminalFile, "tee and branch-local callsite suppression"))
        return 1;
    FILE* logFile = tmpfile();
    if (logFile is null)
        return 1;
    scope (exit)
        fclose(logFile);

    WithoutCallsiteLogSink terminalWithoutCallsite =
        WithoutCallsiteLogSink.create(terminalPresentation);
    TimestampLogPrefix fileTimestamp = TimestampLogPrefix.create(timestampOptions);
    PrefixLogSink timestampedFile = PrefixLogSink.create(
        plainFileLogSink(logFile),
        fileTimestamp.prefixRef(),
    );
    TeeLogSink tee = TeeLogSink.create(
        terminalWithoutCallsite.sinkRef(),
        timestampedFile.sinkRef(),
    );
    char[256] teeStorage;
    Logger teeLogger = Logger.create(
        tee.sinkRef(),
        teeStorage[],
        LogLevel.info,
    );
    teeLogger.setCallsitesEnabled(true);
    if (!teeLogger.info("terminal branch suppresses this callsite").delivered ||
        !teeLogger.flush())
        return 1;

    if (!writeTerminal(terminalFile, "captured plain sibling branch:\n") ||
        !copyFileToTerminal(logFile, terminalFile))
        return 1;

    // Thread-local installation keeps application calls concise, supports
    // `enabled`, nests safely, restores the previous logger, and still accepts
    // a level selected dynamically at runtime.
    if (!terminalSection(terminalFile, "current-thread logger"))
        return 1;
    terminal.setPalette(LogPalettePreset.basic);
    terminal.setCallsitesEnabled(true);
    ThreadContextScope context = ThreadContextScope.acquire();
    {
        ThreadLoggerScope logging = ThreadLoggerScope.install(&terminal);
        if (enabled(LogLevel.trace))
            trace("current logger: guarded trace computation");
        infof!"current logger: processed {} records"(42);

        char[256] nestedStorage;
        Logger nested = stderrLogger(
            nestedStorage[],
            LogLevel.info,
            LogStyle.plain,
        );
        {
            ThreadLoggerScope redirected = ThreadLoggerScope.install(&nested);
            info("nested logger: deliberately plain output");
        }
        info("current logger: outer logger restored");

        const selectedLevel = LogLevel.warning;
        log(selectedLevel, "dynamic level: selected at runtime");
        if (!flushLogger())
            return 1;
    }

    if (!terminal.flush())
        return 1;
    return 0;
}
