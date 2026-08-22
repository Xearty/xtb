module examples.logging_demo;

import core.stdc.stdio : FILE, fclose, stderr, tmpfile;
import xtb.core;
import xtb.os : TimestampLogPrefix, shouldUseAnsi;

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
        AnsiStyle.foreground(AnsiColor.brightRed),
        RequestId(0x2a),
        ansiReset,
        " failed",
    ).delivered && delivered;
    delivered = logger.criticalf!"{}: subsystem {} is unavailable"(
        paletteName,
        "storage",
    ).delivered && delivered;
    return delivered;
}

extern (C) int main() nothrow @nogc
{
    const terminalSupportsAnsi = shouldUseAnsi(cast(FILE*) stderr);

    // Ordinary plain logging is still the smallest built-in configuration.
    char[256] plainStorage;
    Logger plain = stderrLogger(
        plainStorage[],
        LogLevel.info,
        LogStyle.plain,
    );
    if (!plain.info("plain logger: application starting").delivered || !plain.flush())
        return 1;

    // Tee one formatting pass to terminal presentation and a timestamped plain
    // file branch. The timestamp provider's style is ignored by the plain sink,
    // so the logfile contains no ANSI bytes and the terminal has no timestamp.
    // `tmpfile` keeps the example self-cleaning; a real application would pass
    // its long-lived logfile `FILE*` here instead.
    FILE* logFile = tmpfile();
    if (logFile is null)
        return 1;
    scope (exit)
        fclose(logFile);

    LogSinkRef terminal = terminalSupportsAnsi
        ? ansiFileLogSink(cast(FILE*) stderr) : plainFileLogSink(cast(FILE*) stderr);
    TimestampLogPrefix timestamp = TimestampLogPrefix.create();
    PrefixLogSink timestampedFile = PrefixLogSink.create(
        plainFileLogSink(logFile),
        timestamp.prefixRef(),
    );
    TeeLogSink tee = TeeLogSink.create(terminal, timestampedFile.sinkRef());

    char[512] messageStorage;
    Logger logger = Logger.create(
        tee.sinkRef(),
        messageStorage[],
        LogLevel.trace,
    );

    // `basic` is the default and uses only the terminal's configurable 4-bit
    // colors. It leaves message text at the terminal default.
    if (!logger.logEveryLevel("basic preset"))
        return 1;

    // `extended` uses the 256-color palette and progressively brighter gray
    // message text as severity increases.
    logger.setPalette(LogPalettePreset.extended);
    if (!logger.logEveryLevel("extended preset"))
        return 1;

    // `trueColor` is tuned for dark terminals. Its error label intentionally
    // uses RGB #ff5f5f while preserving the same message-brightness progression.
    logger.setPalette(LogPalettePreset.trueColor);
    if (!logger.logEveryLevel("true-color preset"))
        return 1;

    // A preset is still an ordinary value and can be customized before use.
    LogPalette palette = LogPalette.preset(LogPalettePreset.trueColor);
    palette.warning.message = AnsiStyle.foreground(AnsiColor.rgb(210, 215, 225));
    logger.setPalette(palette);
    if (!logger.warning("customized preset: warning message override").delivered)
        return 1;

    // Filtering happens before custom formatting.
    logger.setMinimumLevel(LogLevel.warning);
    size_t formatCalls;
    FormatProbe probe = FormatProbe(&formatCalls);
    const filtered = logger.info(probe);
    if (filtered.status != LogStatus.filtered || formatCalls != 0)
        return 1;
    logger.warningf!"filtered formatter calls={}"(formatCalls);
    logger.setMinimumLevel(LogLevel.trace);

    // Streaming keeps one atomic record while allowing the logical message to
    // exceed its staging buffer without allocation or truncation.
    char[8] streamStorage;
    Logger streaming = Logger.create(
        tee.sinkRef(),
        streamStorage[],
        LogLevel.info,
    );
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

    // Install the same borrowed tee-backed logger for concise application calls.
    ThreadContextScope context = ThreadContextScope.acquire();
    {
        ThreadLoggerScope logging = ThreadLoggerScope.install(&logger);
        if (enabled(LogLevel.trace))
            trace("current logger: guarded trace computation");
        infof!"current logger: processed {} records"(42);

        // Nested installation temporarily redirects output and restores `logger`.
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
        info("current logger: tee-backed palette restored");

        const selectedLevel = LogLevel.warning;
        log(selectedLevel, "dynamic level: selected at runtime");
        if (!flushLogger())
            return 1;
    }

    // `logger` borrows `tee`; `tee` borrows both sink references; the file must
    // remain open through the final flush. No object in this chain owns another.
    if (!logger.flush())
        return 1;

    return 0;
}
