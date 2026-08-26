module tests.logging_tests;

import core.stdc.stdio : FILE, fclose, fread, rewind, tmpfile;
import xtb;
import xtb.log;

static assert(__traits(isCopyable, LogSinkRef));
static assert(__traits(isCopyable, LogPrefixRef));
static assert(!__traits(isCopyable, PrefixLogSink));
static assert(!__traits(isCopyable, WithoutCallsiteLogSink));
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
        styled(longText[], AnsiStyle.foreground(AnsiColor.green)),
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

    FILE* sourceTerminal = tmpfile();
    if (sourceTerminal is null)
        return 1;
    scope (exit)
        assert(fclose(sourceTerminal) == 0);

    FILE* sourceFile = tmpfile();
    if (sourceFile is null)
        return 1;
    scope (exit)
        assert(fclose(sourceFile) == 0);

    WithoutCallsiteLogSink terminalWithoutCallsite = WithoutCallsiteLogSink.create(
        ansiFileLogSink(sourceTerminal),
    );
    TeeLogSink sourceOutputs = TeeLogSink.create(
        terminalWithoutCallsite.sinkRef(),
        plainFileLogSink(sourceFile),
    );
    char[256] sourceStorage;
    Logger sourceLogger = Logger.create(sourceOutputs.sinkRef(), sourceStorage[]);
    sourceLogger.setCallsitesEnabled(true);
    const sourceFunction = cast(String) __FUNCTION__;
    const sourceLine = __LINE__ + 1;
    if (!sourceLogger.error("callsite routing").delivered || !sourceLogger.flush())
        return 1;

    char[1_024] sourceTerminalBytes;
    char[1_024] sourceFileBytes;
    const sourceTerminalLength = readFile(sourceTerminal, sourceTerminalBytes[]);
    const sourceFileLength = readFile(sourceFile, sourceFileBytes[]);
    const sourceTerminalText = cast(String) sourceTerminalBytes[0 .. sourceTerminalLength];
    const sourceFileText = cast(String) sourceFileBytes[0 .. sourceFileLength];
    if (!sourceTerminalText.contains("[error]") ||
        !sourceTerminalText.contains(
            "callsite routing") ||
        sourceTerminalText.contains(sourceFunction))
        return 1;

    char[512] expectedSourceStorage;
    const expectedSource = formatBuffer!"[error]   callsite routing  ({}:{})\n"(
        expectedSourceStorage[],
        sourceFunction,
        sourceLine,
    );
    if (expectedSource.truncated ||
        !sourceFileText.equal(expectedSourceStorage[0 .. expectedSource.written]))
        return 1;

    return 0;
}
