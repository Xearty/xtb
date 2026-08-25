module xtb.diagnostics.stacktrace_style;

nothrow @nogc:

import xtb.diagnostics.demangle : SignatureDetail;
public import xtb.core.ansi : AnsiColor;
import xtb.core.fmt.ansi : beginAnsi, endAnsi;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.fmt.writer : Writer;
import xtb.core.string;

enum StackTraceTheme
{
    solar,
    warmAsh,
    zenburn,
    gruvbox,
    tokyoNight,
    nord,
    dracula,
    oneDark,
    monokai,
    catppuccinMocha,
    everforest,
    solarized,
    firewatch,
    mutedEarth,
    hokusaiMist,
    harborDusk,
    experiment,
    plain,
}

enum ModuleDisplay
{
    omitted,
    full,
}

enum SignatureLayout
{
    multiline,
    singleLine,
}

struct SignatureFormat
{
    SignatureLayout layout = SignatureLayout.multiline;
    size_t maxColumns = 100;
    size_t continuationIndent = 4;
}

struct StackTraceColors
{
nothrow @nogc:

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
    @safe
    {
        static foreach (definition; themeDefinitions)
            if (theme == definition.theme)
                return definition.colors;
        version (XTB_Checked)
            require(false, "invalid stack-trace theme");
        return StackTraceColors.init;
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
    ) pure @safe
    {
        return StackTraceColors(
            AnsiColor.indexed(functionColor),
            AnsiColor.indexed(typeColor),
            AnsiColor.indexed(moduleColor),
            AnsiColor.indexed(pathColor),
            AnsiColor.indexed(
                lineColor),
            AnsiColor.indexed(keywordColor),
            AnsiColor.indexed(punctuationColor),
            AnsiColor.indexed(decorationColor),
            AnsiColor.indexed(addressColor),
            AnsiColor.indexed(warningColor),
        );
    }
}

private struct ThemeDefinition
{
    StackTraceTheme theme;
    StackTraceColors colors;
}

private enum themeDefinitions = [
    ThemeDefinition(StackTraceTheme.solar,
        StackTraceColors.fromAnsi8(220, 110, 81, 244, 203, 152, 252, 250, 250, 8)),
    ThemeDefinition(StackTraceTheme.warmAsh,
        StackTraceColors.fromAnsi8(220, 250, 245, 240, 203, 152, 252, 239, 247, 238)),
    ThemeDefinition(StackTraceTheme.zenburn,
        StackTraceColors.fromAnsi8(228, 187, 109, 240, 248, 223, 188, 239, 229, 237)),
    ThemeDefinition(StackTraceTheme.gruvbox,
        StackTraceColors.fromAnsi8(142, 214, 109, 244, 243, 208, 223, 241, 223, 239)),
    ThemeDefinition(StackTraceTheme.tokyoNight,
        StackTraceColors.fromAnsi8(111, 179, 117, 60, 60, 141, 146, 239, 110, 238)),
    ThemeDefinition(StackTraceTheme.nord,
        StackTraceColors.fromAnsi8(110, 186, 109, 240, 239, 139, 255, 238, 252, 237)),
    ThemeDefinition(StackTraceTheme.dracula,
        StackTraceColors.fromAnsi8(84, 228, 117, 61, 239, 212, 255, 238, 255, 237)),
    ThemeDefinition(StackTraceTheme.oneDark,
        StackTraceColors.fromAnsi8(75, 180, 73, 241, 240, 176, 249, 238, 249, 237)),
    ThemeDefinition(StackTraceTheme.monokai,
        StackTraceColors.fromAnsi8(148, 179, 81, 242, 242, 197, 255, 240, 252, 238)),
    ThemeDefinition(StackTraceTheme.catppuccinMocha,
        StackTraceColors.fromAnsi8(111, 216, 147, 243, 241, 211, 189, 238, 189, 237)),
    ThemeDefinition(StackTraceTheme.everforest,
        StackTraceColors.fromAnsi8(144, 180, 109, 245, 240, 174, 187, 239, 187, 238)),
    ThemeDefinition(StackTraceTheme.solarized,
        StackTraceColors.fromAnsi8(221, 116, 67, 241, 244, 208, 252, 239, 246, 237)),
    ThemeDefinition(StackTraceTheme.firewatch,
        StackTraceColors.fromAnsi8(208, 179, 68, 241, 160, 202, 252, 239, 247, 237)),
    ThemeDefinition(StackTraceTheme.mutedEarth,
        StackTraceColors.fromAnsi8(143, 180, 108, 244, 242, 137, 252, 240, 247, 238)),
    ThemeDefinition(StackTraceTheme.hokusaiMist,
        StackTraceColors.fromAnsi8(110, 179, 109, 244, 240, 140, 187, 238, 187, 237)),
    ThemeDefinition(StackTraceTheme.harborDusk,
        StackTraceColors.fromAnsi8(110, 180, 67, 242, 59, 215, 187, 240, 187, 238)),
    ThemeDefinition(StackTraceTheme.experiment, StackTraceColors.init),
    ThemeDefinition(StackTraceTheme.plain, StackTraceColors.init),
];

static assert(themeDefinitions.length == __traits(allMembers, StackTraceTheme).length);
static foreach (leftIndex, left; themeDefinitions)
    static foreach (rightIndex, right; themeDefinitions)
        static if (leftIndex < rightIndex)
            static assert(left.theme != right.theme, "duplicate stack-trace theme");

struct StackTraceStyle
{
nothrow @nogc:

    StackTraceColors colors;
    bool showProgramCounter;
    ModuleDisplay moduleDisplay;
    SignatureDetail signatureDetail;
    SignatureLayout signatureLayout;
    size_t signatureColumns;

    static StackTraceStyle fromTheme(StackTraceTheme theme)
    @safe
    {
        return StackTraceStyle(
            StackTraceColors.fromTheme(theme),
            false,
            ModuleDisplay.omitted,
            SignatureDetail.overloadIdentity,
            SignatureLayout.multiline,
            100,
        );
    }
}

private enum SignatureTokenKind
{
    identifier,
    type,
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

private bool identifierStart(char value) pure @safe
{
    return value == '_' || value == '$' ||
        value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z';
}

private bool identifierPart(char value) pure @safe
{
    return identifierStart(value) || value >= '0' && value <= '9';
}

private bool space(char value) pure @safe
{
    return value == ' ' || value == '\t' || value == '\r' || value == '\n';
}

private bool keyword(String source) pure @system
{
    switch (source)
    {
        case "const", "immutable", "inout", "shared", "scope", "return",
        "ref", "out", "lazy", "auto", "extern", "nothrow", "pure",
        "@safe", "@trusted", "@system", "@nogc", "function", "delegate",
        "typeof":
            return true;
        default:
            return false;
    }
}

private bool primitiveType(String source) pure @system
{
    switch (source)
    {
        case "void", "bool", "byte", "ubyte", "short", "ushort", "int",
        "uint", "long", "ulong", "cent", "ucent", "char", "wchar",
        "dchar", "float", "double", "real", "ifloat", "idouble",
        "ireal", "cfloat", "cdouble", "creal", "size_t", "ptrdiff_t":
            return true;
        default:
            return false;
    }
}

private SignatureToken nextToken(String input, size_t start)
pure @system
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
    if (kind == SignatureTokenKind.identifier)
    {
        if (primitiveType(source))
            kind = SignatureTokenKind.type;
        else if (keyword(source))
            kind = SignatureTokenKind.keyword;
    }
    return SignatureToken(kind, source, end);
}

private size_t nextNonSpace(String input, size_t start)
pure @safe
{
    while (start < input.length && space(input[start]))
        ++start;
    return start;
}

private bool isFunctionIdentifier(String input, size_t end)
pure @safe
{
    size_t next = nextNonSpace(input, end);
    if (next < input.length && input[next] == '(')
        return true;
    if (next < input.length && input[next] == '!')
        return true;
    return false;
}

private bool isModuleIdentifier(String input, size_t end)
pure @safe
{
    const next = nextNonSpace(input, end);
    return next < input.length && input[next] == '.';
}

private bool aggregateIdentifier(String identifier)
pure @safe
{
    return identifier.length != 0 &&
        (identifier[0] == '@' || identifier[0] >= 'A' && identifier[0] <= 'Z');
}

private size_t visibleWidth(
    String signature,
    ModuleDisplay moduleDisplay,
) pure @system
{
    size_t width;
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
        width += token.source.length;
        offset = token.end;
    }
    return width;
}

private struct ParameterList
{
    size_t open;
    size_t close;
    bool found;
}

private ParameterList outerParameterList(String signature)
pure @safe
{
    size_t depth;
    size_t candidate;
    bool hasCandidate;
    ParameterList result;
    foreach (offset, character; signature)
    {
        if (depth == 0 && character == '-' && offset + 1 < signature.length &&
            signature[offset + 1] == '>')
            break;
        if (character == '(')
        {
            if (depth == 0)
            {
                candidate = offset;
                hasCandidate = true;
            }
            ++depth;
        }
        else if (character == ')' && depth != 0)
        {
            --depth;
            if (depth == 0 && hasCandidate)
                result = ParameterList(candidate, offset, true);
        }
    }
    return result;
}

void writeSignature(
    ref Writer writer,
    String signature,
    scope const StackTraceColors* colors,
    ModuleDisplay moduleDisplay = ModuleDisplay.omitted,
    SignatureFormat format = SignatureFormat.init,
)
{
    if (signature.length == 0)
        return;

    StackTraceColors plain;
    const StackTraceColors* activeColors = colors is null ? &plain : colors;
    const parameters = outerParameterList(signature);
    if (!parameters.found)
    {
        writer.beginAnsi(activeColors.functionName);
        writer.put(signature);
        writer.endAnsi(activeColors.functionName);
        return;
    }

    size_t offset;
    bool suppressSeparator;
    bool suppressSpace;
    const multiline = format.layout == SignatureLayout.multiline &&
        format.maxColumns != 0 && parameters.close > parameters.open + 1 &&
        visibleWidth(signature, moduleDisplay) > format.maxColumns;
    bool insideParameters;
    size_t nestedParentheses;
    while (offset < signature.length)
    {
        const token = nextToken(signature, offset);
        const tokenOffset = offset;
        if (multiline && tokenOffset == parameters.close)
        {
            writer.put('\n');
            writer.repeat(' ', format.continuationIndent);
            insideParameters = false;
        }
        if (suppressSeparator && token.kind == SignatureTokenKind.punctuation &&
            token.source.equal("."))
        {
            suppressSeparator = false;
            offset = token.end;
            continue;
        }
        suppressSeparator = false;
        if (suppressSpace && token.kind == SignatureTokenKind.space)
        {
            suppressSpace = false;
            offset = token.end;
            continue;
        }
        suppressSpace = false;
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
                    ? activeColors.typeName : activeColors.moduleName : activeColors.typeName;
                break;
            case SignatureTokenKind.type:
                color = activeColors.typeName;
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
        if (!multiline || token.kind != SignatureTokenKind.punctuation)
            continue;
        if (tokenOffset == parameters.open)
        {
            writer.put('\n');
            writer.repeat(' ', format.continuationIndent + 4);
            suppressSpace = true;
            insideParameters = true;
            nestedParentheses = 0;
        }
        else if (insideParameters && token.source.equal("("))
            ++nestedParentheses;
        else if (insideParameters && token.source.equal(")") &&
            nestedParentheses != 0)
            --nestedParentheses;
        else if (insideParameters && nestedParentheses == 0 &&
            token.source.equal(","))
        {
            writer.put('\n');
            writer.repeat(' ', format.continuationIndent + 4);
            suppressSpace = true;
        }
    }
}

version (unittest) private struct TestSink
{
    char[] storage;
    size_t written;
}

version (unittest) private size_t testSink(
    void* context,
    scope const(ubyte)[] bytes,
)
{
    TestSink* sink = cast(TestSink*) context;
    const available = sink.storage.length - sink.written;
    const amount = bytes.length < available ? bytes.length : available;
    foreach (index; 0 .. amount)
        sink.storage[sink.written + index] = cast(char) bytes[index];
    sink.written += amount;
    return amount;
}

unittest
{
    char[512] storage;
    TestSink output = TestSink(storage[]);
    Writer writer = Writer.fromSink(&testSink, &output);
    const colors = StackTraceColors.fromTheme(StackTraceTheme.gruvbox);
    const defaultStyle = StackTraceStyle.fromTheme(StackTraceTheme.gruvbox);
    assert(defaultStyle.signatureDetail == SignatureDetail.overloadIdentity);
    assert(defaultStyle.signatureLayout == SignatureLayout.multiline);
    assert(defaultStyle.signatureColumns == 100);
    assert(nextToken("int", 0).kind == SignatureTokenKind.type);
    assert(nextToken("void", 0).kind == SignatureTokenKind.type);
    assert(nextToken("const", 0).kind == SignatureTokenKind.keyword);
    writer.writeSignature(
        "xtb.core.Array!(const(char)[]).append(ref String)",
        &colors,
    );
    const result = writer.result;
    assert(result.ok);
    assert(output.written != 0);
    assert(storage[0] == '\x1b');

    char[128] rgbStorage;
    TestSink rgbOutput = TestSink(rgbStorage[]);
    Writer rgbWriter = Writer.fromSink(&testSink, &rgbOutput);
    StackTraceColors rgbColors;
    rgbColors.functionName = AnsiColor.rgb(1, 2, 3);
    rgbWriter.writeSignature("call(int)", &rgbColors);
    assert(rgbWriter.result.ok);
    assert(rgbStorage[0 .. rgbOutput.written].equal(
            "\x1b[38;2;1;2;3mcall\x1b[0m(int)",
    ));

    char[128] bareStorage;
    TestSink bareOutput = TestSink(bareStorage[]);
    Writer bareWriter = Writer.fromSink(&testSink, &bareOutput);
    bareWriter.writeSignature("main", &rgbColors);
    assert(bareWriter.result.ok);
    assert(bareStorage[0 .. bareOutput.written].equal(
            "\x1b[38;2;1;2;3mmain\x1b[0m",
    ));

    char[128] cStorage;
    TestSink cOutput = TestSink(cStorage[]);
    Writer cWriter = Writer.fromSink(&testSink, &cOutput);
    cWriter.writeSignature("__libc_start_main", &rgbColors);
    assert(cWriter.result.ok);
    assert(cStorage[0 .. cOutput.written].equal(
            "\x1b[38;2;1;2;3m__libc_start_main\x1b[0m",
    ));

    char[1] emptyStorage;
    TestSink emptyOutput = TestSink(emptyStorage[]);
    Writer emptyWriter = Writer.fromSink(&testSink, &emptyOutput);
    emptyWriter.writeSignature("", &rgbColors);
    assert(emptyWriter.result.ok);
    assert(emptyOutput.written == 0);

    char[128] plainStorage;
    TestSink plainOutput = TestSink(plainStorage[]);
    Writer plainWriter = Writer.fromSink(&testSink, &plainOutput);
    const plain = StackTraceColors.fromTheme(StackTraceTheme.plain);
    plainWriter.writeSignature("pkg.module.call(int)", &plain);
    assert(plainWriter.result.ok);
    assert(plainStorage[0 .. plainOutput.written].equal("call(int)"));

    char[128] fullStorage;
    TestSink fullOutput = TestSink(fullStorage[]);
    Writer fullWriter = Writer.fromSink(&testSink, &fullOutput);
    fullWriter.writeSignature("pkg.module.Type.call(int)", &plain, ModuleDisplay.full);
    assert(fullWriter.result.ok);
    assert(fullStorage[0 .. fullOutput.written].equal("pkg.module.Type.call(int)"));

    char[256] multilineStorage;
    TestSink multilineOutput = TestSink(multilineStorage[]);
    Writer multilineWriter = Writer.fromSink(&testSink, &multilineOutput);
    multilineWriter.writeSignature(
        "render(int, delegate(int, long) -> void, const(char)[]) -> bool nothrow",
        &plain,
        ModuleDisplay.omitted,
        SignatureFormat(SignatureLayout.multiline, 30, 4),
    );
    assert(multilineWriter.result.ok);
    assert(multilineStorage[0 .. multilineOutput.written].equal(
            "render(\n        int,\n        delegate(int, long) -> void,\n" ~
            "        const(char)[]\n    ) -> bool nothrow",
    ));

    char[128] singleStorage;
    TestSink singleOutput = TestSink(singleStorage[]);
    Writer singleWriter = Writer.fromSink(&testSink, &singleOutput);
    singleWriter.writeSignature(
        "call(int, const(char)[], long)",
        &plain,
        ModuleDisplay.omitted,
        SignatureFormat(SignatureLayout.singleLine, 1, 4),
    );
    assert(singleWriter.result.ok);
    assert(singleStorage[0 .. singleOutput.written].equal(
            "call(int, const(char)[], long)",
    ));

    enum boundarySignature = "call(int, const(char)[], long)";
    char[128] boundaryStorage;
    TestSink boundaryOutput = TestSink(boundaryStorage[]);
    Writer boundaryWriter = Writer.fromSink(&testSink, &boundaryOutput);
    boundaryWriter.writeSignature(
        boundarySignature,
        &plain,
        ModuleDisplay.omitted,
        SignatureFormat(
            SignatureLayout.multiline,
            boundarySignature.length,
            4,
    ),
    );
    assert(boundaryWriter.result.ok);
    assert(boundaryStorage[0 .. boundaryOutput.written].equal(boundarySignature));
}
