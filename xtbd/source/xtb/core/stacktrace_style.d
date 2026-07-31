module xtb.core.stacktrace_style;

import xtb.core.print : Writer;
import xtb.core.string : String, equal;

enum StackTraceTheme
{
    gruvbox,
    tokyoNight,
    nord,
    dracula,
    catppuccinMocha,
    plain,
}

enum ModuleDisplay
{
    omitted,
    full,
}

struct StackTraceColors
{
    AnsiColor functionName;
    AnsiColor typeName;
    AnsiColor moduleName;
    AnsiColor filePath;
    AnsiColor lineNumber;
    AnsiColor keyword;
    AnsiColor punctuation;
    AnsiColor decoration;
    AnsiColor address;
    AnsiColor warning;

    static StackTraceColors fromTheme(StackTraceTheme theme)
        pure nothrow @safe @nogc
    {
        final switch (theme)
        {
            case StackTraceTheme.gruvbox:
                return fromAnsi8(214, 142, 108, 245, 208, 167, 250, 240, 244, 203);
            case StackTraceTheme.tokyoNight:
                return fromAnsi8(111, 117, 75, 244, 179, 204, 189, 238, 243, 203);
            case StackTraceTheme.nord:
                return fromAnsi8(110, 109, 146, 245, 180, 139, 252, 240, 244, 167);
            case StackTraceTheme.dracula:
                return fromAnsi8(84, 117, 141, 245, 228, 212, 255, 240, 244, 203);
            case StackTraceTheme.catppuccinMocha:
                return fromAnsi8(111, 216, 147, 243, 211, 211, 189, 238, 241, 203);
            case StackTraceTheme.plain:
                return StackTraceColors.init;
        }
    }

    static StackTraceColors fromAnsi8(
        ubyte functionColor,
        ubyte typeColor,
        ubyte moduleColor,
        ubyte pathColor,
        ubyte lineColor,
        ubyte keywordColor,
        ubyte punctuationColor,
        ubyte decorationColor,
        ubyte addressColor,
        ubyte warningColor,
    ) pure nothrow @safe @nogc
    {
        return StackTraceColors(
            AnsiColor(functionColor, true),
            AnsiColor(typeColor, true),
            AnsiColor(moduleColor, true),
            AnsiColor(pathColor, true),
            AnsiColor(lineColor, true),
            AnsiColor(keywordColor, true),
            AnsiColor(punctuationColor, true),
            AnsiColor(decorationColor, true),
            AnsiColor(addressColor, true),
            AnsiColor(warningColor, true),
        );
    }
}

struct AnsiColor
{
    ubyte index;
    bool enabled;
}

struct StackTraceStyle
{
    StackTraceColors colors;
    bool showProgramCounter;
    ModuleDisplay moduleDisplay;

    static StackTraceStyle fromTheme(StackTraceTheme theme)
        pure nothrow @safe @nogc
    {
        return StackTraceStyle(
            StackTraceColors.fromTheme(theme),
            false,
            ModuleDisplay.omitted,
        );
    }
}

void beginAnsi(ref Writer writer, AnsiColor color) nothrow @nogc
{
    if (!color.enabled)
        return;
    writer.put("\x1b[38;5;");
    writer.value(color.index);
    writer.put('m');
}

void endAnsi(ref Writer writer, AnsiColor color) nothrow @nogc
{
    if (color.enabled)
        writer.put("\x1b[0m");
}

private enum SignatureTokenKind
{
    identifier,
    keyword,
    punctuation,
    space,
}

private struct SignatureToken
{
    SignatureTokenKind kind;
    String source;
    size_t end;
}

private bool identifierStart(char value) pure nothrow @safe @nogc
{
    return value == '_' || value == '$' ||
        value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z';
}

private bool identifierPart(char value) pure nothrow @safe @nogc
{
    return identifierStart(value) || value >= '0' && value <= '9';
}

private bool space(char value) pure nothrow @safe @nogc
{
    return value == ' ' || value == '\t' || value == '\r' || value == '\n';
}

private bool keyword(String source) pure nothrow @system @nogc
{
    switch (source)
    {
        case "const", "immutable", "inout", "shared", "scope", "return",
            "ref", "out", "lazy", "auto", "extern", "nothrow", "pure",
            "@safe", "@trusted", "@system", "@nogc", "void", "bool",
            "byte", "ubyte", "short", "ushort", "int", "uint", "long",
            "ulong", "cent", "ucent", "char", "wchar", "dchar", "float",
            "double", "real", "ifloat", "idouble", "ireal", "cfloat",
            "cdouble", "creal", "size_t", "ptrdiff_t":
            return true;
        default:
            return false;
    }
}

private SignatureToken nextToken(String input, size_t start)
    pure nothrow @system @nogc
{
    if (start >= input.length)
        return SignatureToken.init;
    size_t end = start + 1;
    SignatureTokenKind kind = SignatureTokenKind.punctuation;
    if (cast(ubyte) input[start] >= 0x80)
    {
        while (end < input.length && cast(ubyte) input[end] >= 0x80)
            ++end;
    }
    else if (space(input[start]))
    {
        kind = SignatureTokenKind.space;
        while (end < input.length && space(input[end]))
            ++end;
    }
    else if (identifierStart(input[start]) ||
        input[start] == '@' && end < input.length && identifierStart(input[end]))
    {
        kind = SignatureTokenKind.identifier;
        while (end < input.length && identifierPart(input[end]))
            ++end;
    }
    const source = input[start .. end];
    if (kind == SignatureTokenKind.identifier && keyword(source))
        kind = SignatureTokenKind.keyword;
    return SignatureToken(kind, source, end);
}

private size_t nextNonSpace(String input, size_t start)
    pure nothrow @safe @nogc
{
    while (start < input.length && space(input[start]))
        ++start;
    return start;
}

private bool isFunctionIdentifier(String input, size_t end)
    pure nothrow @safe @nogc
{
    size_t next = nextNonSpace(input, end);
    if (next < input.length && input[next] == '(')
        return true;
    if (next < input.length && input[next] == '!')
        return true;
    return false;
}

private bool isModuleIdentifier(String input, size_t end)
    pure nothrow @safe @nogc
{
    const next = nextNonSpace(input, end);
    return next < input.length && input[next] == '.';
}

private bool aggregateIdentifier(String identifier)
    pure nothrow @safe @nogc
{
    return identifier.length != 0 &&
        (identifier[0] == '@' || identifier[0] >= 'A' && identifier[0] <= 'Z');
}

void writeSignature(
    ref Writer writer,
    String signature,
    scope const StackTraceColors* colors,
    ModuleDisplay moduleDisplay = ModuleDisplay.omitted,
) nothrow @nogc
{
    StackTraceColors plain;
    const StackTraceColors* activeColors = colors is null ? &plain : colors;
    size_t offset;
    bool suppressSeparator;
    while (offset < signature.length)
    {
        const token = nextToken(signature, offset);
        if (suppressSeparator && token.kind == SignatureTokenKind.punctuation &&
            token.source.equal("."))
        {
            suppressSeparator = false;
            offset = token.end;
            continue;
        }
        suppressSeparator = false;
        if (moduleDisplay == ModuleDisplay.omitted &&
            token.kind == SignatureTokenKind.identifier &&
            isModuleIdentifier(signature, token.end) &&
            !aggregateIdentifier(token.source))
        {
            suppressSeparator = true;
            offset = token.end;
            continue;
        }
        AnsiColor color;
        final switch (token.kind)
        {
            case SignatureTokenKind.identifier:
                color = isFunctionIdentifier(signature, token.end)
                    ? activeColors.functionName
                    : isModuleIdentifier(signature, token.end)
                        ? aggregateIdentifier(token.source)
                            ? activeColors.typeName : activeColors.moduleName
                        : activeColors.typeName;
                break;
            case SignatureTokenKind.keyword:
                color = activeColors.keyword;
                break;
            case SignatureTokenKind.punctuation:
                color = activeColors.punctuation;
                break;
            case SignatureTokenKind.space:
                break;
        }
        writer.beginAnsi(color);
        writer.put(token.source);
        writer.endAnsi(color);
        offset = token.end;
    }
}

version (unittest)
private struct TestSink
{
    char[] storage;
    size_t written;
}

version (unittest)
private size_t testSink(void* context, scope String bytes) nothrow @nogc
{
    TestSink* sink = cast(TestSink*) context;
    const available = sink.storage.length - sink.written;
    const amount = bytes.length < available ? bytes.length : available;
    foreach (index; 0 .. amount)
        sink.storage[sink.written + index] = bytes[index];
    sink.written += amount;
    return amount;
}

nothrow @nogc unittest
{
    char[512] storage;
    TestSink output = TestSink(storage[]);
    Writer writer = Writer.fromSink(&testSink, &output);
    const colors = StackTraceColors.fromTheme(StackTraceTheme.gruvbox);
    writer.writeSignature(
        "xtb.core.Array!(const(char)[]).append(ref String)",
        &colors,
    );
    const result = writer.finish();
    assert(result.ok);
    assert(output.written != 0);
    assert(storage[0] == '\x1b');

    char[128] plainStorage;
    TestSink plainOutput = TestSink(plainStorage[]);
    Writer plainWriter = Writer.fromSink(&testSink, &plainOutput);
    const plain = StackTraceColors.fromTheme(StackTraceTheme.plain);
    plainWriter.writeSignature("pkg.module.call(int)", &plain);
    assert(plainWriter.finish().ok);
    assert(plainStorage[0 .. plainOutput.written].equal("call(int)"));

    char[128] fullStorage;
    TestSink fullOutput = TestSink(fullStorage[]);
    Writer fullWriter = Writer.fromSink(&testSink, &fullOutput);
    fullWriter.writeSignature("pkg.module.Type.call(int)", &plain, ModuleDisplay.full);
    assert(fullWriter.finish().ok);
    assert(fullStorage[0 .. fullOutput.written].equal("pkg.module.Type.call(int)"));
}
