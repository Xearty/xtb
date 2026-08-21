module tests.logging_tests;

import core.stdc.stdio : FILE, fclose, fread, rewind, tmpfile;
import xtb.core;

static assert(__traits(isCopyable, LogSinkRef));
static assert(__traits(isCopyable, LogPrefixRef));
static assert(!__traits(isCopyable, PrefixLogSink));
static assert(!__traits(isCopyable, TeeLogSink));
static assert(!__traits(isCopyable, Logger));

private struct FormatProbe
{
    size_t* calls;

    void formatTo(ref Writer writer) nothrow @nogc
    {
        ++*calls;
        writer.put("formatted-once");
    }
}

private struct FixedPrefix
{
    String text;
    AnsiStyle style;
}

private bool writeFixedPrefix(void* context, LogPrefixWriter* output) nothrow @nogc
{
    FixedPrefix* prefix = cast(FixedPrefix*) context;
    return prefix !is null && output !is null &&
        output.write(prefix.text, prefix.style);
}

private size_t readFile(FILE* file, char[] destination) nothrow @system @nogc
{
    rewind(file);
    return fread(destination.ptr, 1, destination.length, file);
}

private bool containsEscape(scope String value) nothrow pure @safe @nogc
{
    foreach (character; value)
        if (character == '\x1b')
            return true;
    return false;
}

extern (C) int main() nothrow @nogc
{
    FILE* terminal = tmpfile();
    if (terminal is null)
        return 1;
    scope (exit)
        assert(fclose(terminal) == 0);

    FILE* firstFile = tmpfile();
    if (firstFile is null)
        return 1;
    scope (exit)
        assert(fclose(firstFile) == 0);

    FILE* secondFile = tmpfile();
    if (secondFile is null)
        return 1;
    scope (exit)
        assert(fclose(secondFile) == 0);

    FixedPrefix filePrefix = FixedPrefix("file-only ");
    PrefixLogSink prefixedFile = PrefixLogSink.create(
        plainFileLogSink(firstFile),
        LogPrefixRef.create(&writeFixedPrefix, &filePrefix),
    );
    TeeLogSink plainFiles = TeeLogSink.create(
        prefixedFile.sinkRef(),
        plainFileLogSink(secondFile),
    );
    TeeLogSink outputs = TeeLogSink.create(
        ansiFileLogSink(terminal),
        plainFiles.sinkRef(),
    );
    FixedPrefix sharedPrefix = FixedPrefix(
        "shared ",
        AnsiStyle.foreground(AnsiColor.brightBlack).dim,
    );
    PrefixLogSink sharedOutput = PrefixLogSink.create(
        outputs.sinkRef(),
        LogPrefixRef.create(&writeFixedPrefix, &sharedPrefix),
    );

    LogPalette palette = LogPalette.preset(LogPalettePreset.trueColor);

    char[2_048] storage;
    Logger logger = Logger.create(
        sharedOutput.sinkRef(),
        storage[],
        LogLevel.trace,
        palette,
    );

    char[768] longText;
    foreach (ref value; longText)
        value = 'x';
    size_t formatCalls;
    FormatProbe probe = FormatProbe(&formatCalls);
    const result = logger.warning(
        "prefix ",
        AnsiStyle.foreground(AnsiColor.green),
        longText[],
        ansiReset,
        " ",
        probe,
        " suffix",
    );
    if (!result.delivered || formatCalls != 1 || !logger.flush())
        return 1;

    char[4_096] terminalBytes;
    char[4_096] firstBytes;
    char[4_096] secondBytes;
    const terminalLength = readFile(terminal, terminalBytes[]);
    const firstLength = readFile(firstFile, firstBytes[]);
    const secondLength = readFile(secondFile, secondBytes[]);
    const terminalText = cast(String) terminalBytes[0 .. terminalLength];
    const firstText = cast(String) firstBytes[0 .. firstLength];
    const secondText = cast(String) secondBytes[0 .. secondLength];

    if (!containsEscape(terminalText) || containsEscape(firstText) ||
        containsEscape(secondText))
        return 1;
    if (!terminalText.contains("shared ") || !terminalText.contains("[warning]") ||
        terminalText.contains("file-only "))
        return 1;
    if (!firstText.startsWith("file-only shared [warning] prefix ") ||
        !secondText.startsWith("shared [warning] prefix "))
        return 1;
    if (!firstText.endsWith(" formatted-once suffix\n") ||
        !secondText.endsWith(" formatted-once suffix\n"))
        return 1;
    if (!firstText.contains(longText[]) || !secondText.contains(longText[]))
        return 1;

    return 0;
}
