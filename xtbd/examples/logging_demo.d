module examples.logging_demo;

import core.stdc.stdio : FILE, stderr;
import xtb.core;
import xtb.os : shouldUseAnsi;

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
        RequestId(0x2a),
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
    const ansi = shouldUseAnsi(cast(FILE*) stderr);
    const outputStyle = ansi ? LogStyle.ansi : LogStyle.plain;

    char[512] messageStorage;
    Logger logger = stderrLogger(
        messageStorage[],
        LogLevel.trace,
        outputStyle,
    );

    // Explicit logger calls need neither TLS installation nor a thread context.
    if (!logger.logEveryLevel("default palette"))
        return 1;

    LogPalette palette = LogPalette.defaults();
    palette.trace = AnsiStyle.foreground(AnsiColor.indexed(244)).dim;
    palette.debug_ = AnsiStyle.foreground(AnsiColor.brightMagenta);
    palette.info = AnsiStyle.foreground(AnsiColor.brightCyan);
    palette.warning = AnsiStyle.foreground(AnsiColor.indexed(214)).bold;
    palette.error = AnsiStyle.foreground(AnsiColor.rgb(255, 95, 95));
    palette.critical = AnsiStyle.foreground(AnsiColor.brightWhite)
        .withBackground(AnsiColor.red)
        .bold;
    logger.setPalette(palette);
    if (!logger.logEveryLevel("custom palette"))
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

    // Install the same borrowed logger for concise application-level calls.
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
        info("current logger: colored palette restored");

        const selectedLevel = LogLevel.warning;
        log(selectedLevel, "dynamic level: selected at runtime");
        if (!flushLogger())
            return 1;
    }

    return 0;
}
