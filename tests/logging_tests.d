module tests.logging_tests;

import core.stdc.stdio : FILE, fclose, fread, rewind, tmpfile;
import xtb.core;

static assert(__traits(isCopyable, LogSinkRef));
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

    TeeLogSink plainFiles = TeeLogSink.create(
        plainFileLogSink(firstFile),
        plainFileLogSink(secondFile),
    );
    TeeLogSink outputs = TeeLogSink.create(
        ansiFileLogSink(terminal),
        plainFiles.sinkRef(),
    );

    LogPalette palette = LogPalette.preset(LogPalettePreset.trueColor);

    char[2_048] storage;
    Logger logger = Logger.create(
        outputs.sinkRef(),
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

    if (!containsEscape(terminalText) || containsEscape(firstText))
        return 1;
    if (firstLength != secondLength || !firstText.equal(secondText))
        return 1;
    if (!firstText.startsWith("[warning] prefix "))
        return 1;
    if (!firstText.endsWith(" formatted-once suffix\n"))
        return 1;
    if (!firstText.contains(longText[]))
        return 1;

    return 0;
}
