module xtb.diagnostics.stacktrace_style;

nothrow @nogc:

import xtb.ansi;
import xtb.diagnostics.demangle;
import xtb.fmt.ansi;
import xtb.fmt.writer;
import xtb.panic;
import xtb.string;
import xtb.types;

enum StackTraceTheme
{
    solar,
    warm_ash,
    zenburn,
    gruvbox,
    tokyo_night,
    nord,
    dracula,
    one_dark,
    monokai,
    catppuccin_mocha,
    everforest,
    solarized,
    firewatch,
    muted_earth,
    hokusai_mist,
    harbor_dusk,
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
    single_line,
}

struct SignatureFormat
{
    SignatureLayout layout = SignatureLayout.multiline;
    usize max_columns = 100;
    usize continuation_indent = 4;
}

struct StackTraceColors
{
    nothrow @nogc:

    ANSIColor function_name;
    ANSIColor type_name;
    ANSIColor module_name;
    ANSIColor file_path;
    ANSIColor line_number;
    ANSIColor keyword;
    ANSIColor punctuation;
    ANSIColor decoration;
    ANSIColor address;
    ANSIColor warning;

    static StackTraceColors from_theme(StackTraceTheme theme)
    @safe
    {
        static foreach (definition; theme_definitions)
        {
            if (theme == definition.theme)
                return definition.colors;
        }

        require(false, "invalid stack-trace theme");
        return StackTraceColors.init;
    }

    static StackTraceColors from_ansi8(
        u8 function_color,
        u8 type_color,
        u8 module_color,
        u8 path_color,
        u8 line_color,
        u8 keyword_color,
        u8 punctuation_color,
        u8 decoration_color,
        u8 address_color,
        u8 warning_color,
    ) pure @safe
    {
        return StackTraceColors(
            ANSIColor.indexed(function_color),
            ANSIColor.indexed(type_color),
            ANSIColor.indexed(module_color),
            ANSIColor.indexed(path_color),
            ANSIColor.indexed(line_color),
            ANSIColor.indexed(keyword_color),
            ANSIColor.indexed(punctuation_color),
            ANSIColor.indexed(decoration_color),
            ANSIColor.indexed(address_color),
            ANSIColor.indexed(warning_color),
        );
    }
}

private struct ThemeDefinition
{
    StackTraceTheme theme;
    StackTraceColors colors;
}

private enum theme_definitions = [
    ThemeDefinition(
        StackTraceTheme.solar,
        StackTraceColors.from_ansi8(220, 110, 81, 244, 203, 152, 252, 250, 250, 8),
    ),
    ThemeDefinition(
        StackTraceTheme.warm_ash,
        StackTraceColors.from_ansi8(220, 250, 245, 240, 203, 152, 252, 239, 247, 238),
    ),
    ThemeDefinition(
        StackTraceTheme.zenburn,
        StackTraceColors.from_ansi8(228, 187, 109, 240, 248, 223, 188, 239, 229, 237),
    ),
    ThemeDefinition(
        StackTraceTheme.gruvbox,
        StackTraceColors.from_ansi8(142, 214, 109, 244, 243, 208, 223, 241, 223, 239),
    ),
    ThemeDefinition(
        StackTraceTheme.tokyo_night,
        StackTraceColors.from_ansi8(111, 179, 117, 60, 60, 141, 146, 239, 110, 238),
    ),
    ThemeDefinition(
        StackTraceTheme.nord,
        StackTraceColors.from_ansi8(110, 186, 109, 240, 239, 139, 255, 238, 252, 237),
    ),
    ThemeDefinition(
        StackTraceTheme.dracula,
        StackTraceColors.from_ansi8(84, 228, 117, 61, 239, 212, 255, 238, 255, 237),
    ),
    ThemeDefinition(
        StackTraceTheme.one_dark,
        StackTraceColors.from_ansi8(75, 180, 73, 241, 240, 176, 249, 238, 249, 237),
    ),
    ThemeDefinition(
        StackTraceTheme.monokai,
        StackTraceColors.from_ansi8(148, 179, 81, 242, 242, 197, 255, 240, 252, 238),
    ),
    ThemeDefinition(
        StackTraceTheme.catppuccin_mocha,
        StackTraceColors.from_ansi8(111, 216, 147, 243, 241, 211, 189, 238, 189, 237),
    ),
    ThemeDefinition(
        StackTraceTheme.everforest,
        StackTraceColors.from_ansi8(144, 180, 109, 245, 240, 174, 187, 239, 187, 238),
    ),
    ThemeDefinition(
        StackTraceTheme.solarized,
        StackTraceColors.from_ansi8(221, 116, 67, 241, 244, 208, 252, 239, 246, 237),
    ),
    ThemeDefinition(
        StackTraceTheme.firewatch,
        StackTraceColors.from_ansi8(208, 179, 68, 241, 160, 202, 252, 239, 247, 237),
    ),
    ThemeDefinition(
        StackTraceTheme.muted_earth,
        StackTraceColors.from_ansi8(143, 180, 108, 244, 242, 137, 252, 240, 247, 238),
    ),
    ThemeDefinition(
        StackTraceTheme.hokusai_mist,
        StackTraceColors.from_ansi8(110, 179, 109, 244, 240, 140, 187, 238, 187, 237),
    ),
    ThemeDefinition(
        StackTraceTheme.harbor_dusk,
        StackTraceColors.from_ansi8(110, 180, 67, 242, 59, 215, 187, 240, 187, 238),
    ),
    ThemeDefinition(
        StackTraceTheme.experiment,
        StackTraceColors.init,
    ),
    ThemeDefinition(
        StackTraceTheme.plain,
        StackTraceColors.init,
    ),
];

static assert(theme_definitions.length == __traits(allMembers, StackTraceTheme).length);
static foreach (left_index, left; theme_definitions)
{
    static foreach (right_index, right; theme_definitions)
    {
        static if (left_index < right_index)
            static assert(left.theme != right.theme, "duplicate stack-trace theme");
    }
}

struct StackTraceStyle
{
    nothrow @nogc:

    StackTraceColors colors;
    bool show_program_counter;
    ModuleDisplay module_display;
    SignatureDetail signature_detail;
    SignatureLayout signature_layout;
    usize signature_columns;

    static StackTraceStyle from_theme(StackTraceTheme theme)
    @safe
    {
        return StackTraceStyle(
            StackTraceColors.from_theme(theme),
            false,
            ModuleDisplay.omitted,
            SignatureDetail.overload_identity,
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
    usize end;
}

private bool identifier_start(char value) pure @safe
{
    return value == '_'
        || value == '$'
        || (value >= 'a' && value <= 'z')
        || (value >= 'A' && value <= 'Z');
}

private bool identifier_part(char value) pure @safe
{
    return identifier_start(value) || (value >= '0' && value <= '9');
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

private bool primitive_type(String source) pure @system
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

private SignatureToken next_token(String input, usize start) pure @system
{
    if (start >= input.length)
        return SignatureToken.init;

    usize end = start + 1;
    SignatureTokenKind kind = SignatureTokenKind.punctuation;
    if (cast(u8) input[start] >= 0x80)
    {
        while (end < input.length && cast(u8) input[end] >= 0x80)
            ++end;
    }
    else if (space(input[start]))
    {
        kind = SignatureTokenKind.space;
        while (end < input.length && space(input[end]))
            ++end;
    }
    else
    {
        const attribute_identifier = input[start] == '@'
            && end < input.length
            && identifier_start(input[end]);
        if (identifier_start(input[start]) || attribute_identifier)
        {
            kind = SignatureTokenKind.identifier;
            while (end < input.length && identifier_part(input[end]))
                ++end;
        }
    }

    const source = input[start .. end];
    if (kind == SignatureTokenKind.identifier)
    {
        if (primitive_type(source))
            kind = SignatureTokenKind.type;
        else if (keyword(source))
            kind = SignatureTokenKind.keyword;
    }

    return SignatureToken(kind, source, end);
}

private usize next_non_space(String input, usize start) pure @safe
{
    while (start < input.length && space(input[start]))
        ++start;

    return start;
}

private bool is_function_identifier(String input, usize end) pure @safe
{
    const next = next_non_space(input, end);
    if (next < input.length && input[next] == '(')
        return true;

    if (next < input.length && input[next] == '!')
        return true;

    return false;
}

private bool is_module_identifier(String input, usize end) pure @safe
{
    const next = next_non_space(input, end);
    return next < input.length && input[next] == '.';
}

private bool aggregate_identifier(String identifier) pure @safe
{
    return identifier.length != 0
        && (identifier[0] == '@'
            || (identifier[0] >= 'A' && identifier[0] <= 'Z'));
}

private usize visible_width(
    String signature,
    ModuleDisplay module_display,
) pure @system
{
    usize width;
    usize offset;
    bool suppress_separator;
    while (offset < signature.length)
    {
        const token = next_token(signature, offset);
        if (
            suppress_separator
            && token.kind == SignatureTokenKind.punctuation
            && token.source == "."
        )
        {
            suppress_separator = false;
            offset = token.end;
            continue;
        }

        suppress_separator = false;
        if (
            module_display == ModuleDisplay.omitted
            && token.kind == SignatureTokenKind.identifier
            && is_module_identifier(signature, token.end)
            && !aggregate_identifier(token.source)
        )
        {
            suppress_separator = true;
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
    usize open;
    usize close;
    bool found;
}

private ParameterList outer_parameter_list(String signature) pure @safe
{
    usize depth;
    usize candidate;
    bool has_candidate;
    ParameterList result;
    foreach (offset, character; signature)
    {
        const return_arrow = depth == 0
            && character == '-'
            && offset + 1 < signature.length
            && signature[offset + 1] == '>';
        if (return_arrow)
            break;

        if (character == '(')
        {
            if (depth == 0)
            {
                candidate = offset;
                has_candidate = true;
            }

            ++depth;
        }
        else if (character == ')' && depth != 0)
        {
            --depth;
            if (depth == 0 && has_candidate)
                result = ParameterList(candidate, offset, true);
        }
    }

    return result;
}

void write_signature(
    ref Writer writer,
    String signature,
    scope const StackTraceColors* colors,
    ModuleDisplay module_display = ModuleDisplay.omitted,
    SignatureFormat format = SignatureFormat.init,
)
{
    if (signature.length == 0)
        return;

    StackTraceColors plain;
    const StackTraceColors* active_colors = colors is null ? &plain : colors;
    const parameters = outer_parameter_list(signature);
    if (!parameters.found)
    {
        writer.begin_ansi(active_colors.function_name);
        writer.put(signature);
        writer.end_ansi(active_colors.function_name);
        return;
    }

    usize offset;
    bool suppress_separator;
    bool suppress_space;
    const multiline = format.layout == SignatureLayout.multiline
        && format.max_columns != 0
        && parameters.close > parameters.open + 1
        && visible_width(signature, module_display) > format.max_columns;
    bool inside_parameters;
    usize nested_parentheses;
    while (offset < signature.length)
    {
        const token = next_token(signature, offset);
        const token_offset = offset;
        if (multiline && token_offset == parameters.close)
        {
            writer.put('\n');
            writer.repeat(' ', format.continuation_indent);
            inside_parameters = false;
        }

        if (
            suppress_separator
            && token.kind == SignatureTokenKind.punctuation
            && token.source == "."
        )
        {
            suppress_separator = false;
            offset = token.end;
            continue;
        }

        suppress_separator = false;
        if (suppress_space && token.kind == SignatureTokenKind.space)
        {
            suppress_space = false;
            offset = token.end;
            continue;
        }

        suppress_space = false;
        if (
            module_display == ModuleDisplay.omitted
            && token.kind == SignatureTokenKind.identifier
            && is_module_identifier(signature, token.end)
            && !aggregate_identifier(token.source)
        )
        {
            suppress_separator = true;
            offset = token.end;
            continue;
        }

        ANSIColor color;
        final switch (token.kind)
        {
            case SignatureTokenKind.identifier:
            {
                const function_identifier = is_function_identifier(signature, token.end);
                const module_identifier = is_module_identifier(signature, token.end);
                const aggregate = aggregate_identifier(token.source);
                color = function_identifier
                    ? active_colors.function_name
                    : module_identifier
                    ? aggregate ? active_colors.type_name : active_colors.module_name
                    : active_colors.type_name;
                break;
            }

            case SignatureTokenKind.type:
                color = active_colors.type_name;
                break;

            case SignatureTokenKind.keyword:
                color = active_colors.keyword;
                break;

            case SignatureTokenKind.punctuation:
                color = active_colors.punctuation;
                break;

            case SignatureTokenKind.space:
                break;
        }

        writer.begin_ansi(color);
        writer.put(token.source);
        writer.end_ansi(color);
        offset = token.end;
        if (!multiline || token.kind != SignatureTokenKind.punctuation)
            continue;

        if (token_offset == parameters.open)
        {
            writer.put('\n');
            writer.repeat(' ', format.continuation_indent + 4);
            suppress_space = true;
            inside_parameters = true;
            nested_parentheses = 0;
        }
        else if (inside_parameters && token.source == "(")
        {
            ++nested_parentheses;
        }
        else if (inside_parameters && token.source == ")" && nested_parentheses != 0)
        {
            --nested_parentheses;
        }
        else if (inside_parameters && nested_parentheses == 0 && token.source == ",")
        {
            writer.put('\n');
            writer.repeat(' ', format.continuation_indent + 4);
            suppress_space = true;
        }
    }
}

version (unittest)
{
    private struct TestSink
    {
        char[] storage;
        usize written;
    }

    private usize test_sink(
        void* context,
        scope const(u8)[] bytes,
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
}

unittest
{
    char[512] storage;
    TestSink output = TestSink(storage[]);
    Writer writer = Writer.from_sink(&test_sink, &output);
    const colors = StackTraceColors.from_theme(StackTraceTheme.gruvbox);
    const default_style = StackTraceStyle.from_theme(StackTraceTheme.gruvbox);
    assert(default_style.signature_detail == SignatureDetail.overload_identity);
    assert(default_style.signature_layout == SignatureLayout.multiline);
    assert(default_style.signature_columns == 100);
    assert(next_token("int", 0).kind == SignatureTokenKind.type);
    assert(next_token("void", 0).kind == SignatureTokenKind.type);
    assert(next_token("const", 0).kind == SignatureTokenKind.keyword);
    writer.write_signature(
        "xtb.Array!(const(char)[]).append(ref String)",
        &colors,
    );
    const result = writer.result;
    assert(result.ok);
    assert(output.written != 0);
    assert(storage[0] == '\x1b');

    char[128] rgb_storage;
    TestSink rgb_output = TestSink(rgb_storage[]);
    Writer rgb_writer = Writer.from_sink(&test_sink, &rgb_output);
    StackTraceColors rgb_colors;
    rgb_colors.function_name = ANSIColor.rgb(1, 2, 3);
    rgb_writer.write_signature("call(int)", &rgb_colors);
    assert(rgb_writer.result.ok);
    assert(
        rgb_storage[0 .. rgb_output.written] == "\x1b[38;2;1;2;3mcall\x1b[0m(int)",
    );

    char[128] bare_storage;
    TestSink bare_output = TestSink(bare_storage[]);
    Writer bare_writer = Writer.from_sink(&test_sink, &bare_output);
    bare_writer.write_signature("main", &rgb_colors);
    assert(bare_writer.result.ok);
    assert(
        bare_storage[0 .. bare_output.written] == "\x1b[38;2;1;2;3mmain\x1b[0m",
    );

    char[128] c_storage;
    TestSink c_output = TestSink(c_storage[]);
    Writer c_writer = Writer.from_sink(&test_sink, &c_output);
    c_writer.write_signature("__libc_start_main", &rgb_colors);
    assert(c_writer.result.ok);
    assert(
        c_storage[0 .. c_output.written] == "\x1b[38;2;1;2;3m__libc_start_main\x1b[0m",
    );

    char[1] empty_storage;
    TestSink empty_output = TestSink(empty_storage[]);
    Writer empty_writer = Writer.from_sink(&test_sink, &empty_output);
    empty_writer.write_signature("", &rgb_colors);
    assert(empty_writer.result.ok);
    assert(empty_output.written == 0);

    char[128] plain_storage;
    TestSink plain_output = TestSink(plain_storage[]);
    Writer plain_writer = Writer.from_sink(&test_sink, &plain_output);
    const plain = StackTraceColors.from_theme(StackTraceTheme.plain);
    plain_writer.write_signature("pkg.module.call(int)", &plain);
    assert(plain_writer.result.ok);
    assert(plain_storage[0 .. plain_output.written] == "call(int)");

    char[128] full_storage;
    TestSink full_output = TestSink(full_storage[]);
    Writer full_writer = Writer.from_sink(&test_sink, &full_output);
    full_writer.write_signature("pkg.module.Type.call(int)", &plain, ModuleDisplay.full);
    assert(full_writer.result.ok);
    assert(full_storage[0 .. full_output.written] == "pkg.module.Type.call(int)");

    char[256] multiline_storage;
    TestSink multiline_output = TestSink(multiline_storage[]);
    Writer multiline_writer = Writer.from_sink(&test_sink, &multiline_output);
    multiline_writer.write_signature(
        "render(int, delegate(int, long) -> void, const(char)[]) -> bool nothrow",
        &plain,
        ModuleDisplay.omitted,
        SignatureFormat(SignatureLayout.multiline, 30, 4),
    );
    assert(multiline_writer.result.ok);
    const expected_multiline = "render(\n        int,\n        delegate(int, long) -> void,\n"
        ~ "        const(char)[]\n    ) -> bool nothrow";
    assert(multiline_storage[0 .. multiline_output.written] == expected_multiline);

    char[128] single_storage;
    TestSink single_output = TestSink(single_storage[]);
    Writer single_writer = Writer.from_sink(&test_sink, &single_output);
    single_writer.write_signature(
        "call(int, const(char)[], long)",
        &plain,
        ModuleDisplay.omitted,
        SignatureFormat(SignatureLayout.single_line, 1, 4),
    );
    assert(single_writer.result.ok);
    assert(single_storage[0 .. single_output.written] == "call(int, const(char)[], long)");

    enum boundary_signature = "call(int, const(char)[], long)";
    char[128] boundary_storage;
    TestSink boundary_output = TestSink(boundary_storage[]);
    Writer boundary_writer = Writer.from_sink(&test_sink, &boundary_output);
    boundary_writer.write_signature(
        boundary_signature,
        &plain,
        ModuleDisplay.omitted,
        SignatureFormat(
            SignatureLayout.multiline,
            boundary_signature.length,
            4,
        ),
    );
    assert(boundary_writer.result.ok);
    assert(boundary_storage[0 .. boundary_output.written] == boundary_signature);
}
