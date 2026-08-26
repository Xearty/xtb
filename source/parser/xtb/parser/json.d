module xtb.parser.json;

nothrow @nogc:

import core.stdc.errno : ERANGE, errno;
import core.stdc.math : isfinite;
import core.stdc.stdlib : strtod;
import xtb.allocators.arena : Arena;

version (XTB_Checked) import xtb.panic : require;
import xtb.types : String;
import xtb.utf8 : DecodedCodePoint, EncodedCodePoint, decodeCodePoint,
    encodeUtf8, encodedUtf8Length;
import xtb.parser.parser : Grammar, ParseContext, ParseErrorKind, ParseOutcome,
    ParseState, Parser, Rule, Tokenizer, Unit;

/// JSON value category.
enum JsonKind : ubyte
{
    null_,
    boolean,
    number,
    string,
    array,
    object,
}

/// Arena-backed tagged union. Strings and collections use the parse output arena.
struct JsonValue
{
    JsonKind kind;

    union
    {
        bool boolean;
        double number;
        String string;
        JsonValue[] array;
        JsonMember[] object;
    }
}

struct JsonMember
{
    String key;
    JsonValue value;
}

private bool isHex(char value) pure @safe
{
    return (value >= '0' && value <= '9') ||
        (value >= 'a' && value <= 'f') ||
        (value >= 'A' && value <= 'F');
}

private uint hexValue(char value) pure @safe
{
    if (value >= '0' && value <= '9')
        return cast(uint)(value - '0');
    if (value >= 'a' && value <= 'f')
        return cast(uint)(value - 'a' + 10);
    return cast(uint)(value - 'A' + 10);
}

private bool scanHex4(String input, size_t offset, uint* value) @trusted
{
    if (offset > input.length || input.length - offset < 4)
        return false;
    uint result;
    foreach (index; 0 .. 4)
    {
        const current = input[offset + index];
        if (!isHex(current))
            return false;
        result = (result << 4) | hexValue(current);
    }
    *value = result;
    return true;
}

private struct EscapeScan
{
    dchar value;
    size_t nextOffset;
}

private bool scanUnicodeEscape(
    String input,
    size_t escapeOffset,
    EscapeScan* output,
) @trusted
{
    // escapeOffset points at the 'u' after a backslash.
    uint first;
    if (!scanHex4(input, escapeOffset + 1, &first))
        return false;
    size_t next = escapeOffset + 5;

    if (first >= 0xD800 && first <= 0xDBFF)
    {
        if (next > input.length || input.length - next < 6 ||
            input[next] != '\\' || input[next + 1] != 'u')
            return false;
        uint second;
        if (!scanHex4(input, next + 2, &second) ||
            second < 0xDC00 || second > 0xDFFF)
            return false;
        const scalar = 0x10000u + ((first - 0xD800u) << 10) + (second - 0xDC00u);
        output.value = cast(dchar) scalar;
        output.nextOffset = next + 6;
        return true;
    }

    if (first >= 0xDC00 && first <= 0xDFFF)
        return false;

    output.value = cast(dchar) first;
    output.nextOffset = next;
    return true;
}

private struct JsonNumberNode
{
nothrow @nogc:
    ParseOutcome!double parse(ref ParseState state) @trusted
    {
        const input = state.input;
        const start = state.offset;
        size_t cursor = start;
        if (cursor < input.length && input[cursor] == '-')
            ++cursor;
        if (cursor >= input.length)
        {
            state.fail(ParseErrorKind.expected, cursor, "JSON number");
            return ParseOutcome!double.failure();
        }
        if (input[cursor] == '0')
        {
            ++cursor;
            if (cursor < input.length && input[cursor] >= '0' && input[cursor] <= '9')
            {
                state.fail(ParseErrorKind.invalidSyntax, cursor,
                    "JSON number without leading zeroes");
                return ParseOutcome!double.failure();
            }
        }
        else
        {
            if (input[cursor] < '1' || input[cursor] > '9')
            {
                state.fail(ParseErrorKind.expected, cursor, "JSON number");
                return ParseOutcome!double.failure();
            }
            do
                ++cursor;
            while (cursor < input.length && input[cursor] >= '0' && input[cursor] <= '9');
        }
        if (cursor < input.length && input[cursor] == '.')
        {
            ++cursor;
            const fractionStart = cursor;
            while (cursor < input.length && input[cursor] >= '0' && input[cursor] <= '9')
                ++cursor;
            if (cursor == fractionStart)
            {
                state.fail(ParseErrorKind.invalidSyntax, cursor, "JSON fraction digit");
                return ParseOutcome!double.failure();
            }
        }
        if (cursor < input.length && (input[cursor] == 'e' || input[cursor] == 'E'))
        {
            ++cursor;
            if (cursor < input.length && (input[cursor] == '+' || input[cursor] == '-'))
                ++cursor;
            const exponentStart = cursor;
            while (cursor < input.length && input[cursor] >= '0' && input[cursor] <= '9')
                ++cursor;
            if (cursor == exponentStart)
            {
                state.fail(ParseErrorKind.invalidSyntax, cursor, "JSON exponent digit");
                return ParseOutcome!double.failure();
            }
        }
        const length = cursor - start;
        if (length >= 128)
        {
            state.fail(ParseErrorKind.numberOutOfRange, cursor, "JSON number in range");
            return ParseOutcome!double.failure();
        }
        char[128] text;
        foreach (index; 0 .. length)
            text[index] = input[start + index];
        text[length] = '\0';
        char* end;
        errno = 0;
        const value = strtod(text.ptr, &end);
        if (end != text.ptr + length)
        {
            state.fail(ParseErrorKind.invalidSyntax, start, "JSON number");
            return ParseOutcome!double.failure();
        }
        if (errno == ERANGE || !isfinite(value))
        {
            state.fail(ParseErrorKind.numberOutOfRange, cursor, "JSON number in range");
            return ParseOutcome!double.failure();
        }
        state.setOffset(cursor);
        return ParseOutcome!double.succeed(value);
    }
}

private struct JsonStringNode
{
nothrow @nogc:
    ParseOutcome!String parse(ref ParseState state) @trusted
    {
        const input = state.input;
        const start = state.offset;
        if (start >= input.length || input[start] != '"')
        {
            state.fail(ParseErrorKind.expected, start, "JSON string");
            return ParseOutcome!String.failure();
        }

        size_t cursor = start + 1;
        size_t decodedLength;
        while (cursor < input.length && input[cursor] != '"')
        {
            const currentByte = cast(ubyte) input[cursor];
            if (currentByte < 0x20)
            {
                state.fail(ParseErrorKind.invalidSyntax, cursor, "JSON string character");
                state.setOffset(cursor);
                return ParseOutcome!String.failure();
            }
            if (input[cursor] == '\\')
            {
                ++cursor;
                if (cursor >= input.length)
                {
                    state.fail(ParseErrorKind.invalidSyntax, cursor, "JSON escape");
                    state.setOffset(cursor);
                    return ParseOutcome!String.failure();
                }
                switch (input[cursor])
                {
                    case '"', '\\', '/', 'b', 'f', 'n', 'r', 't':
                        ++decodedLength;
                        ++cursor;
                        break;
                    case 'u':
                        EscapeScan escaped;
                        if (!scanUnicodeEscape(input, cursor, &escaped))
                        {
                            state.fail(ParseErrorKind.invalidSyntax, cursor, "valid Unicode escape");
                            state.setOffset(cursor);
                            return ParseOutcome!String.failure();
                        }
                        decodedLength += encodedUtf8Length(escaped.value);
                        cursor = escaped.nextOffset;
                        break;
                    default:
                        state.fail(ParseErrorKind.invalidSyntax, cursor, "valid JSON escape");
                        state.setOffset(cursor);
                        return ParseOutcome!String.failure();
                }
                continue;
            }

            DecodedCodePoint decoded;
            const utf8Error = decodeCodePoint(input, cursor, &decoded);
            if (utf8Error.failed)
            {
                state.fail(ParseErrorKind.invalidSyntax, cursor, "valid UTF-8");
                state.setOffset(cursor);
                return ParseOutcome!String.failure();
            }
            decodedLength += decoded.byteLength;
            cursor += decoded.byteLength;
        }

        if (cursor >= input.length)
        {
            state.fail(ParseErrorKind.invalidSyntax, cursor, "closing quote");
            state.setOffset(cursor);
            return ParseOutcome!String.failure();
        }

        version (XTB_Checked)
            require(state.context !is null && state.context.outputArena !is null,
                "JSON string parsing requires a parse output arena");

        char[] storage = state.context.outputArena.allocateArray!char(decodedLength);
        size_t source = start + 1;
        size_t target;
        while (source < cursor)
        {
            if (input[source] != '\\')
            {
                DecodedCodePoint decoded;
                const utf8Error = decodeCodePoint(input, source, &decoded);
                if (utf8Error.failed)
                {
                    state.fail(ParseErrorKind.invalidSyntax, source, "valid UTF-8");
                    state.setOffset(source);
                    return ParseOutcome!String.failure();
                }
                foreach (index; 0 .. decoded.byteLength)
                    storage[target++] = input[source + index];
                source += decoded.byteLength;
                continue;
            }

            ++source;
            switch (input[source])
            {
                case '"':
                    storage[target++] = '"';
                    ++source;
                    break;
                case '\\':
                    storage[target++] = '\\';
                    ++source;
                    break;
                case '/':
                    storage[target++] = '/';
                    ++source;
                    break;
                case 'b':
                    storage[target++] = '\b';
                    ++source;
                    break;
                case 'f':
                    storage[target++] = '\f';
                    ++source;
                    break;
                case 'n':
                    storage[target++] = '\n';
                    ++source;
                    break;
                case 'r':
                    storage[target++] = '\r';
                    ++source;
                    break;
                case 't':
                    storage[target++] = '\t';
                    ++source;
                    break;
                case 'u':
                    EscapeScan escaped;
                    if (!scanUnicodeEscape(input, source, &escaped))
                    {
                        state.fail(ParseErrorKind.invalidSyntax, source, "valid Unicode escape");
                        state.setOffset(source);
                        return ParseOutcome!String.failure();
                    }
                    const EncodedCodePoint encoded = encodeUtf8(escaped.value);
                    const bytes = encoded.codeUnits;
                    foreach (index; 0 .. encoded.byteLength)
                        storage[target++] = bytes[index];
                    source = escaped.nextOffset;
                    break;
                default:
                    state.fail(ParseErrorKind.invalidSyntax, source, "valid JSON escape");
                    state.setOffset(source);
                    return ParseOutcome!String.failure();
            }
        }

        state.setOffset(cursor + 1);
        return ParseOutcome!String.succeed(cast(String) storage);
    }
}

private JsonValue makeNull(String) pure @safe
{
    JsonValue value;
    value.kind = JsonKind.null_;
    return value;
}

private JsonValue makeTrue(String) pure @trusted
{
    JsonValue value;
    value.kind = JsonKind.boolean;
    value.boolean = true;
    return value;
}

private JsonValue makeFalse(String) pure @trusted
{
    JsonValue value;
    value.kind = JsonKind.boolean;
    value.boolean = false;
    return value;
}

private JsonValue makeNumber(double number) pure @trusted
{
    JsonValue value;
    value.kind = JsonKind.number;
    value.number = number;
    return value;
}

private JsonValue makeString(String string) pure @trusted
{
    JsonValue value;
    value.kind = JsonKind.string;
    value.string = string;
    return value;
}

private JsonValue makeArray(JsonValue[] array) pure @trusted
{
    JsonValue value;
    value.kind = JsonKind.array;
    value.array = array;
    return value;
}

private JsonValue makeObject(JsonMember[] object) pure @trusted
{
    JsonValue value;
    value.kind = JsonKind.object;
    value.object = object;
    return value;
}

/// Builds a complete RFC 8259 JSON document parser in `grammar`.
///
/// Arrays, objects, and decoded strings allocate only from `ParseContext.outputArena`.
Parser!JsonValue jsonDocument(Grammar* grammar) @trusted
{
    version (XTB_Checked)
        require(grammar !is null, "JSON parser requires a grammar");

    Parser!Unit trivia = grammar.asciiWhitespace0().skip();
    Tokenizer token = grammar.tokenizer(trivia);
    Rule!JsonValue value = grammar.rule!JsonValue("JSON value");

    Parser!String stringToken = grammar.custom!String(JsonStringNode.init).before(trivia);
    Parser!JsonValue stringValue = stringToken.map!makeString();
    Parser!JsonValue numberValue = grammar.custom!double(JsonNumberNode.init)
        .before(trivia)
        .map!makeNumber();
    Parser!JsonValue trueValue = token.literal("true").map!makeTrue();
    Parser!JsonValue falseValue = token.literal("false").map!makeFalse();
    Parser!JsonValue nullValue = token.literal("null").map!makeNull();

    Parser!(JsonValue[]) arrayItems =
        value.parser.sepBy(token.literal(",")).collect();
    Parser!JsonValue arrayValue = arrayItems
        .between(token.literal("[").cut(), token.literal("]"))
        .map!makeArray()
        .named("JSON array");

    Parser!JsonMember member = stringToken
        .before(token.literal(":"))
        .then(value.parser)
        .mapTuple!JsonMember();
    Parser!(JsonMember[]) objectMembers =
        member.sepBy(token.literal(",")).collect();
    Parser!JsonValue objectValue = objectMembers
        .between(token.literal("{").cut(), token.literal("}"))
        .map!makeObject()
        .named("JSON object");

    value.define(grammar.choice(
            stringValue,
            numberValue,
            trueValue,
            falseValue,
            nullValue,
            arrayValue,
            objectValue,
    ));

    return trivia
        .after(value.parser)
        .before(grammar.eof())
        .named("JSON document");
}

/// Returns the first object member whose key equals `key`, or null.
const(JsonValue)* findMember(return scope const JsonValue* object, String key) @trusted
{
    if (object is null || object.kind != JsonKind.object)
        return null;
    foreach (ref const member; object.object)
        if (member.key == key)
            return &member.value;
    return null;
}
