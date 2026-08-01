module xtb.serde.toml;

nothrow @nogc:

import core.stdc.errno : ERANGE, errno;
import core.stdc.math : isfinite, isnan, signbit;
import core.stdc.stdio : snprintf;
import core.stdc.stdlib : strtod;
import xtb.core.memory : Allocator, deallocate, tryAllocate;
import xtb.core.panic : require;
import xtb.core.print : Writer;
import xtb.core.types : String;
import xtb.serde.attributes : Flatten, Ignore, KeyCase, OmitDefault, Rename,
    Required;
import xtb.serde.casing : writeCased;
import xtb.serde.error : SerdeError, SerdeErrorKind, SerdeLimits;
import xtb.serde.ownership : Deserialized, abandonDeserialized,
    prepareDeserialized;
import xtb.serde.traits : FieldType, Unqualified, fieldHas, fieldMatches,
    fieldName, isDynamicArray, isFixedArray, isSerdeStruct, isString,
    schemaCase, validateSchema;

struct TomlWriteOptions
{
    KeyCase keyCase = KeyCase.schema;
    size_t maxDepth = 64;
}

struct TomlReadOptions
{
    SerdeLimits limits;
    KeyCase keyCase = KeyCase.schema;
}

private SerdeError success() pure @safe
{
    return SerdeError.init;
}

private SerdeError simpleError(SerdeErrorKind kind) pure @safe
{
    SerdeError result;
    result.kind = kind;
    result.line = 1;
    result.column = 1;
    return result;
}

SerdeError writeToml(T)(
    ref Writer writer,
    scope const ref T value,
    TomlWriteOptions options = TomlWriteOptions.init,
)
{
    validateSchema!T();
    TomlEncoder encoder;
    encoder.writer = &writer;
    encoder.options = options;
    encodeRoot(encoder, value);
    writer.flush();
    if (!encoder.error.ok)
        return encoder.error;
    return writer.ok ? success() : simpleError(SerdeErrorKind.outputFailure);
}

SerdeError readToml(T)(
    scope String input,
    Allocator* allocator,
    Deserialized!T* output,
    TomlReadOptions options = TomlReadOptions.init,
)
{
    validateSchema!T();
    require(options.limits.maxDepth != 0, "TOML max depth must be nonzero");
    require(options.limits.maxCollectionLength != 0,
        "TOML collection limit must be nonzero");

    T* value;
    if (!prepareDeserialized(allocator, output, &value))
        return simpleError(SerdeErrorKind.allocationFailure);

    TomlParser parser;
    parser.input = input;
    parser.allocator = allocator;
    parser.options = options;
    parser.line = 1;
    parser.column = 1;
    bool[tomlNodeCount!T] seen;
    parseDocument(parser, value, seen.ptr);
    if (parser.error.ok)
        validateRequired(parser, value, seen.ptr, 0);
    parser.clearTablePath();
    if (!parser.error.ok)
    {
        SerdeError error = parser.error;
        abandonDeserialized(output);
        return error;
    }
    return success();
}

private struct TomlEncoder
{
nothrow @nogc:

    Writer* writer;
    TomlWriteOptions options;
    SerdeError error;

    void fail(SerdeErrorKind kind)
    {
        if (error.ok)
            error = simpleError(kind);
    }
}

private bool isDefaultValue(T)(scope const ref T value) pure @safe
{
    alias U = Unqualified!T;
    static if (isString!U || isDynamicArray!U)
        return value.length == 0;
    else static if (is(U == Pointee*, Pointee))
        return value is null;
    else static if (isFixedArray!U)
    {
        foreach (ref const element; value)
            if (!isDefaultValue(element))
                return false;
        return true;
    }
    else static if (isSerdeStruct!U)
    {
        static foreach (index; 0 .. U.tupleof.length)
            static if (!fieldHas!(U, index, Ignore))
                if (!isDefaultValue(value.tupleof[index]))
                    return false;
        return true;
    }
    else
        return value == U.init;
}

private void encodeRoot(T)(ref TomlEncoder encoder, scope const ref T value)
{
    bool wrote;
    static foreach (index; 0 .. Unqualified!T.tupleof.length)
    {
        static if (!fieldHas!(T, index, Ignore))
        {
            static if (fieldHas!(T, index, Flatten))
                encodeFlattened(encoder, value.tupleof[index], &wrote, 0);
            else
                encodeRootField!(T, index)(encoder, value.tupleof[index], &wrote);
        }
    }
}

private void encodeFlattened(T)(
    ref TomlEncoder encoder,
    scope const ref T value,
    bool* wrote,
    size_t depth,
)
{
    static foreach (index; 0 .. Unqualified!T.tupleof.length)
    {
        static if (!fieldHas!(T, index, Ignore))
        {
            static if (fieldHas!(T, index, Flatten))
                encodeFlattened(encoder, value.tupleof[index], wrote, depth);
            else
                encodeRootField!(T, index)(encoder, value.tupleof[index], wrote, depth);
        }
    }
}

private void encodeRootField(T, size_t index, F)(
    ref TomlEncoder encoder,
    scope const ref F value,
    bool* wrote,
    size_t depth = 0,
)
{
    enum omit = fieldHas!(T, index, OmitDefault);
    if ((omit && isDefaultValue(value)) || nullPointer(value))
        return;
    if (*wrote)
        encoder.writer.put('\n');
    encodeKey!(T, index)(encoder);
    encoder.writer.put(" = ");
    encodeValue(encoder, value, depth);
    *wrote = true;
}

private bool nullPointer(T)(scope const ref T value) pure @safe
{
    static if (is(Unqualified!T == Pointee*, Pointee))
        return value is null;
    else
        return false;
}

private void encodeKey(T, size_t index)(ref TomlEncoder encoder)
{
    static if (fieldHas!(T, index, Rename))
        encodeKeyText(encoder, fieldName!(T, index), KeyCase.preserve);
    else
    {
        const casing = encoder.options.keyCase == KeyCase.schema
            ? schemaCase!T : encoder.options.keyCase;
        encodeKeyText(encoder, fieldName!(T, index), casing);
    }
}

private void encodeKeyText(ref TomlEncoder encoder, String value, KeyCase casing)
{
    if (casing != KeyCase.preserve || bareKey(value))
        (*encoder.writer).writeCased(value, casing);
    else
        encodeString(encoder, value);
}

private bool bareKey(scope String value) pure @safe
{
    if (value.length == 0)
        return false;
    foreach (character; value)
        if (!((character >= 'a' && character <= 'z') ||
                (character >= 'A' && character <= 'Z') ||
                (character >= '0' && character <= '9') || character == '_' ||
                character == '-'))
            return false;
    return true;
}

private void encodeValue(T)(ref TomlEncoder encoder, scope const ref T value, size_t depth)
{
    if (!encoder.error.ok)
        return;
    if (depth >= encoder.options.maxDepth)
    {
        encoder.fail(SerdeErrorKind.depthLimit);
        return;
    }
    alias U = Unqualified!T;
    static if (isString!U)
        encodeString(encoder, cast(String) value);
    else static if (is(U == bool))
        encoder.writer.put(value ? "true" : "false");
    else static if (is(U == enum))
        encodeEnum(encoder, value);
    else static if (__traits(isIntegral, U))
        encoder.writer.value(value);
    else static if (__traits(isFloating, U))
        encodeFloat(encoder, value);
    else static if (is(U == Pointee*, Pointee))
    {
        if (value is null)
            encoder.fail(SerdeErrorKind.unsupportedValue);
        else
            encodeValue(encoder, *value, depth);
    }
    else static if (isDynamicArray!U || isFixedArray!U)
        encodeArray(encoder, value, depth);
    else static if (isSerdeStruct!U)
        encodeInlineTable(encoder, value, depth);
}

private void encodeInlineTable(T)(
    ref TomlEncoder encoder,
    scope const ref T value,
    size_t depth,
)
{
    encoder.writer.put("{ ");
    bool wrote;
    encodeInlineFields(encoder, value, depth, &wrote);
    encoder.writer.put(wrote ? " }" : "}");
}

private void encodeInlineFields(T)(
    ref TomlEncoder encoder,
    scope const ref T value,
    size_t depth,
    bool* wrote,
)
{
    static foreach (index; 0 .. Unqualified!T.tupleof.length)
    {
        static if (!fieldHas!(T, index, Ignore))
        {
            static if (fieldHas!(T, index, Flatten))
                encodeInlineFields(encoder, value.tupleof[index], depth, wrote);
            else
                encodeInlineField!(T, index)(encoder, value.tupleof[index], depth, wrote);
        }
    }
}

private void encodeInlineField(T, size_t index, F)(
    ref TomlEncoder encoder,
    scope const ref F value,
    size_t depth,
    bool* wrote,
)
{
    enum omit = fieldHas!(T, index, OmitDefault);
    if ((omit && isDefaultValue(value)) || nullPointer(value))
        return;
    if (*wrote)
        encoder.writer.put(", ");
    encodeKey!(T, index)(encoder);
    encoder.writer.put(" = ");
    encodeValue(encoder, value, depth + 1);
    *wrote = true;
}

private void encodeArray(T)(ref TomlEncoder encoder, scope const ref T value, size_t depth)
{
    encoder.writer.put('[');
    foreach (index, ref const element; value)
    {
        if (index != 0)
            encoder.writer.put(", ");
        encodeValue(encoder, element, depth + 1);
    }
    encoder.writer.put(']');
}

private void encodeString(ref TomlEncoder encoder, scope String value)
{
    if (!validUtf8(value))
    {
        encoder.fail(SerdeErrorKind.invalidUtf8);
        return;
    }
    encoder.writer.put('"');
    foreach (character; value)
    {
        switch (character)
        {
            case '"':
                encoder.writer.put("\\\"");
                break;
            case '\\':
                encoder.writer.put("\\\\");
                break;
            case '\b':
                encoder.writer.put("\\b");
                break;
            case '\t':
                encoder.writer.put("\\t");
                break;
            case '\n':
                encoder.writer.put("\\n");
                break;
            case '\f':
                encoder.writer.put("\\f");
                break;
            case '\r':
                encoder.writer.put("\\r");
                break;
            default:
                if (cast(ubyte) character < 0x20 || cast(ubyte) character == 0x7f)
                {
                    char[7] escaped;
                    snprintf(escaped.ptr, escaped.length, "\\u%04x",
                        cast(uint) cast(ubyte) character);
                    encoder.writer.put(escaped[0 .. 6]);
                }
                else
                    encoder.writer.put(character);
                break;
        }
    }
    encoder.writer.put('"');
}

private void encodeFloat(T)(ref TomlEncoder encoder, T value)
{
    if (isnan(cast(double) value))
    {
        encoder.writer.put("nan");
        return;
    }
    if (!isfinite(cast(double) value))
    {
        encoder.writer.put(signbit(cast(double) value) ? "-inf" : "inf");
        return;
    }
    char[64] text;
    static if (T.sizeof <= float.sizeof)
        const count = snprintf(text.ptr, text.length, "%.9g", cast(double) value);
    else
        const count = snprintf(text.ptr, text.length, "%.17g", cast(double) value);
    if (count <= 0 || cast(size_t) count >= text.length)
        encoder.fail(SerdeErrorKind.unsupportedValue);
    else
    {
        encoder.writer.put(text[0 .. cast(size_t) count]);
        bool floatingMarker;
        foreach (character; text[0 .. cast(size_t) count])
            if (character == '.' || character == 'e' || character == 'E')
                floatingMarker = true;
        if (!floatingMarker)
            encoder.writer.put(".0");
    }
}

private void encodeEnum(T)(ref TomlEncoder encoder, T value)
{
    bool found;
    static foreach (name; __traits(allMembers, T))
        static if (__traits(compiles, __traits(getMember, T, name)))
            if (!found && value == __traits(getMember, T, name))
                {
                encodeString(encoder, name);
                found = true;
            }
    if (!found)
        encoder.fail(SerdeErrorKind.unsupportedValue);
}

private struct ParsedKey
{
    String value;
    bool owned;
}

private struct TomlParser
{
nothrow @nogc:

    String input;
    Allocator* allocator;
    TomlReadOptions options;
    size_t position;
    size_t line;
    size_t column;
    SerdeError error;
    ParsedKey[64] tablePath;
    size_t tablePathLength;

    bool atEnd() const pure @safe
    {
        return position == input.length;
    }

    char peek() const pure @safe
    {
        return atEnd ? '\0' : input[position];
    }

    char take()
    {
        if (atEnd)
            return '\0';
        const result = input[position++];
        if (result == '\n')
        {
            ++line;
            column = 1;
        }
        else
            ++column;
        return result;
    }

    bool consume(char expected)
    {
        if (peek != expected)
            return false;
        take();
        return true;
    }

    void horizontalSpace()
    {
        while (!atEnd && (peek == ' ' || peek == '\t'))
            take();
    }

    void spaceAndComments()
    {
        for (;;)
        {
            while (!atEnd && (peek == ' ' || peek == '\t' || peek == '\r' || peek == '\n'))
                take();
            if (peek != '#')
                return;
            while (!atEnd && peek != '\n')
                take();
        }
    }

    void valueSpace()
    {
        for (;;)
        {
            while (!atEnd && (peek == ' ' || peek == '\t' || peek == '\r' || peek == '\n'))
                take();
            if (peek != '#')
                return;
            while (!atEnd && peek != '\n')
                take();
        }
    }

    void fail(SerdeErrorKind kind, String field = null)
    {
        if (!error.ok)
            return;
        error.kind = kind;
        error.offset = position;
        error.line = line;
        error.column = column;
        error.field = field;
    }

    void clearTablePath()
    {
        foreach (index; 0 .. tablePathLength)
        {
            if (tablePath[index].owned)
                allocator.deallocate(cast(char*) tablePath[index].value.ptr,
                    tablePath[index].value.length + 1);
            tablePath[index] = ParsedKey.init;
        }
        tablePathLength = 0;
    }
}

private size_t nodeWidth(T, size_t index)() pure @safe
{
    alias F = FieldType!(T, index);
    static if (fieldHas!(T, index, Ignore))
        return 0;
    else static if (fieldHas!(T, index, Flatten))
        return tomlNodeCount!F;
    else static if (isSerdeStruct!F)
        return 1 + tomlNodeCount!F;
    else static if (is(Unqualified!F == Pointee*, Pointee) && isSerdeStruct!Pointee)
        return 1 + tomlNodeCount!Pointee;
    else
        return 1;
}

private size_t countNodes(T, size_t index = 0)() pure @safe
{
    static if (index == Unqualified!T.tupleof.length)
        return 0;
    else
        return nodeWidth!(T, index) + countNodes!(T, index + 1);
}

private enum tomlNodeCount(T) = countNodes!T;

private size_t countNodesBefore(T, size_t target, size_t index = 0)()
pure @safe
{
    static if (index == target)
        return 0;
    else
        return nodeWidth!(T, index) + countNodesBefore!(T, target, index + 1);
}

private enum nodeOrdinal(T, size_t index) = countNodesBefore!(T, index);

private void parseDocument(T)(ref TomlParser parser, T* output, bool* seen)
{
    parser.spaceAndComments();
    size_t assignments;
    while (!parser.atEnd && parser.error.ok)
    {
        if (parser.peek == '[')
        {
            parseTableHeader(parser);
            parser.spaceAndComments();
            continue;
        }
        if (assignments++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            break;
        }
        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        if (!parser.error.ok)
        {
            clearKeys(parser, key[], keyLength);
            break;
        }
        parser.horizontalSpace();
        if (!parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        bool matched;
        if (parser.error.ok)
            decodePath(parser, output, parser.tablePath[], parser.tablePathLength,
                key[], keyLength, 0, 0, seen, 0, &matched);
        String diagnosticKey = keyLength == 0 ? null : key[keyLength - 1].value;
        if (!matched && parser.error.ok)
        {
            if (parser.options.limits.ignoreUnknownFields)
                skipValue(parser, 0);
            else
                parser.fail(SerdeErrorKind.unknownField, diagnosticKey);
        }
        preserveDiagnostic(parser, key[], keyLength);
        clearKeys(parser, key[], keyLength);
        if (!parser.error.ok)
            break;
        parser.horizontalSpace();
        if (parser.peek == '#')
            while (!parser.atEnd && parser.peek != '\n')
                parser.take();
        if (!parser.atEnd && parser.peek != '\n' && parser.peek != '\r')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            break;
        }
        parser.spaceAndComments();
    }
}

private void parseTableHeader(ref TomlParser parser)
{
    parser.clearTablePath();
    parser.consume('[');
    if (parser.peek == '[')
    {
        parser.fail(SerdeErrorKind.unsupportedValue);
        return;
    }
    parser.horizontalSpace();
    parseKeyPath(parser, parser.tablePath[], &parser.tablePathLength, ']');
    parser.horizontalSpace();
    if (!parser.consume(']'))
    {
        parser.fail(SerdeErrorKind.invalidSyntax);
        return;
    }
    parser.horizontalSpace();
    if (parser.peek == '#')
        while (!parser.atEnd && parser.peek != '\n')
            parser.take();
    if (!parser.atEnd && parser.peek != '\n' && parser.peek != '\r')
        parser.fail(SerdeErrorKind.invalidSyntax);
}

private void parseKeyPath(
    ref TomlParser parser,
    ParsedKey[] destination,
    size_t* length,
    char terminator = '=',
)
{
    for (;;)
    {
        if (*length == destination.length || *length == parser.options.limits.maxDepth)
        {
            parser.fail(SerdeErrorKind.depthLimit);
            return;
        }
        parseKey(parser, &destination[*length]);
        if (!parser.error.ok)
            return;
        ++*length;
        parser.horizontalSpace();
        if (!parser.consume('.'))
            return;
        parser.horizontalSpace();
        if (parser.peek == terminator)
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
    }
}

private void parseKey(ref TomlParser parser, ParsedKey* output)
{
    if (parser.peek == '"' || parser.peek == '\'')
    {
        decodeStringToken(parser, &output.value, &output.owned, true);
        return;
    }
    const start = parser.position;
    while (!parser.atEnd && ((parser.peek >= 'a' && parser.peek <= 'z') ||
            (parser.peek >= 'A' && parser.peek <= 'Z') ||
            (parser.peek >= '0' && parser.peek <= '9') || parser.peek == '_' ||
            parser.peek == '-'))
        parser.take();
    if (parser.position == start)
        parser.fail(SerdeErrorKind.invalidSyntax);
    else
        output.value = parser.input[start .. parser.position];
}

private void preserveDiagnostic(
    ref TomlParser parser,
    ParsedKey[] keys,
    size_t length,
)
{
    if (parser.error.field.ptr is null)
        return;
    foreach (index; 0 .. length)
        if (keys[index].owned && parser.error.field.ptr is keys[index].value.ptr)
        {
            parser.error.field = null;
            return;
        }
}

private void clearKeys(ref TomlParser parser, ParsedKey[] keys, size_t length)
{
    foreach (index; 0 .. length)
    {
        if (keys[index].owned)
            parser.allocator.deallocate(cast(char*) keys[index].value.ptr,
                keys[index].value.length + 1);
        keys[index] = ParsedKey.init;
    }
}

private void decodePath(T)(
    ref TomlParser parser,
    T* output,
    ParsedKey[] prefix,
    size_t prefixLength,
    ParsedKey[] suffix,
    size_t suffixLength,
    size_t prefixIndex,
    size_t suffixIndex,
    bool* seen,
    size_t base,
    bool* matched,
)
{
    const inPrefix = prefixIndex < prefixLength;
    const key = inPrefix ? prefix[prefixIndex].value : suffix[suffixIndex].value;
    static foreach (index; 0 .. Unqualified!T.tupleof.length)
    {
        static if (!fieldHas!(T, index, Ignore))
        {
            static if (fieldHas!(T, index, Flatten))
            {
                if (!*matched)
                    decodePath(parser, &output.tupleof[index], prefix, prefixLength,
                        suffix, suffixLength, prefixIndex, suffixIndex, seen,
                        base + nodeOrdinal!(T, index), matched);
            }
            else
                decodePathField!(T, index)(parser, output, key, prefix, prefixLength,
                    suffix, suffixLength, prefixIndex, suffixIndex, seen, base, matched);
        }
    }
}

private void decodePathField(T, size_t index)(
    ref TomlParser parser,
    T* output,
    scope String key,
    ParsedKey[] prefix,
    size_t prefixLength,
    ParsedKey[] suffix,
    size_t suffixLength,
    size_t prefixIndex,
    size_t suffixIndex,
    bool* seen,
    size_t base,
    bool* matched,
)
{
    if (*matched || !fieldMatches!(T, index)(key, parser.options.keyCase))
        return;
    const ordinal = base + nodeOrdinal!(T, index);
    const inPrefix = prefixIndex < prefixLength;
    const nextPrefix = prefixIndex + (inPrefix ? 1 : 0);
    const nextSuffix = suffixIndex + (inPrefix ? 0 : 1);
    const atEnd = nextPrefix == prefixLength && nextSuffix == suffixLength;
    alias F = FieldType!(T, index);
    if (atEnd)
    {
        if (seen[ordinal])
        {
            parser.fail(SerdeErrorKind.duplicateField, key);
            return;
        }
        seen[ordinal] = true;
        *matched = true;
        static if (isSerdeStruct!F)
            decodeInlineTable(parser, &output.tupleof[index], 0, seen + ordinal + 1);
        else static if (is(Unqualified!F == Pointee*, Pointee) &&
            isSerdeStruct!Pointee)
        {
            output.tupleof[index] = parser.allocator.tryAllocate!Pointee();
            if (output.tupleof[index] is null)
            {
                parser.fail(SerdeErrorKind.allocationFailure);
                return;
            }
            *output.tupleof[index] = Pointee.init;
            decodeInlineTable(parser, output.tupleof[index], 0, seen + ordinal + 1);
        }
        else
            decodeValue(parser, &output.tupleof[index], 0);
    }
    else static if (isSerdeStruct!F)
    {
        seen[ordinal] = true;
        decodePath(parser, &output.tupleof[index], prefix, prefixLength,
            suffix, suffixLength, nextPrefix, nextSuffix, seen, ordinal + 1, matched);
    }
    else static if (is(Unqualified!F == Pointee*, Pointee) && isSerdeStruct!Pointee)
    {
        if (output.tupleof[index] is null)
        {
            output.tupleof[index] = parser.allocator.tryAllocate!Pointee();
            if (output.tupleof[index] is null)
            {
                parser.fail(SerdeErrorKind.allocationFailure);
                return;
            }
            *output.tupleof[index] = Pointee.init;
        }
        seen[ordinal] = true;
        decodePath(parser, output.tupleof[index], prefix, prefixLength,
            suffix, suffixLength, nextPrefix, nextSuffix, seen, ordinal + 1, matched);
    }
    else
    {
        *matched = true;
        parser.fail(SerdeErrorKind.typeMismatch, key);
    }
}

private void validateRequired(T)(
    ref TomlParser parser,
    T* output,
    bool* seen,
    size_t base,
)
{
    static foreach (index; 0 .. Unqualified!T.tupleof.length)
        validateRequiredField!(T, index)(parser, output, seen, base);
}

private void validateRequiredField(T, size_t index)(
    ref TomlParser parser,
    T* output,
    bool* seen,
    size_t base,
)
{
    static if (!fieldHas!(T, index, Ignore))
    {
        const ordinal = base + nodeOrdinal!(T, index);
        static if (fieldHas!(T, index, Flatten))
            validateRequired(parser, &output.tupleof[index], seen, ordinal);
        else
        {
            static if (fieldHas!(T, index, Required))
                if (!seen[ordinal])
                    parser.fail(SerdeErrorKind.missingRequiredField,
                        fieldName!(T, index));
            alias F = FieldType!(T, index);
            static if (isSerdeStruct!F)
            {
                if (seen[ordinal])
                    validateRequired(parser, &output.tupleof[index], seen,
                        ordinal + 1);
            }
            else static if (is(Unqualified!F == Pointee*, Pointee) &&
                isSerdeStruct!Pointee)
            {
                if (seen[ordinal] && output.tupleof[index]!is null)
                    validateRequired(parser, output.tupleof[index], seen,
                        ordinal + 1);
            }
        }
    }
}

private void decodeValue(T)(ref TomlParser parser, T* output, size_t depth)
{
    parser.valueSpace();
    if (depth >= parser.options.limits.maxDepth)
    {
        parser.fail(SerdeErrorKind.depthLimit);
        return;
    }
    if (looksLikeDateTime(parser.input, parser.position))
    {
        parser.fail(SerdeErrorKind.unsupportedValue);
        return;
    }
    alias U = Unqualified!T;
    static if (isString!U)
        decodeString(parser, cast(String*) output);
    else static if (is(U == bool))
        decodeBool(parser, output);
    else static if (is(U == enum))
        decodeEnum(parser, output);
    else static if (__traits(isIntegral, U))
        decodeInteger(parser, output);
    else static if (__traits(isFloating, U))
        decodeFloat(parser, output);
    else static if (is(U == Pointee*, Pointee))
        decodePointer(parser, output, depth);
    else static if (isDynamicArray!U)
        decodeDynamicArray(parser, output, depth);
    else static if (isFixedArray!U)
        decodeFixedArray(parser, output, depth);
    else static if (isSerdeStruct!U)
        decodeInlineTable(parser, output, depth);
}

private void decodeInlineTable(T)(
    ref TomlParser parser,
    T* output,
    size_t depth,
    bool* externalSeen = null,
)
{
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    bool[tomlNodeCount!T] localSeen;
    bool* seen = externalSeen is null ? localSeen.ptr : externalSeen;
    parser.horizontalSpace();
    if (parser.consume('}'))
    {
        validateRequired(parser, output, seen, 0);
        return;
    }
    size_t count;
    for (;;)
    {
        if (count++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        parser.horizontalSpace();
        if (!parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        bool matched;
        if (parser.error.ok)
            decodePath(parser, output, null, 0, key[], keyLength, 0, 0,
                seen, 0, &matched);
        if (!matched && parser.error.ok)
        {
            if (parser.options.limits.ignoreUnknownFields)
                skipValue(parser, depth + 1);
            else
                parser.fail(SerdeErrorKind.unknownField,
                    key[keyLength - 1].value);
        }
        preserveDiagnostic(parser, key[], keyLength);
        clearKeys(parser, key[], keyLength);
        if (!parser.error.ok)
            return;
        parser.horizontalSpace();
        if (parser.consume('}'))
            break;
        if (!parser.consume(','))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.horizontalSpace();
        if (parser.peek == '}')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
    }
    validateRequired(parser, output, seen, 0);
}

private void decodePointer(T)(ref TomlParser parser, T** output, size_t depth)
{
    T* value = parser.allocator.tryAllocate!T();
    if (value is null)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
    *value = T.init;
    *output = value;
    decodeValue(parser, value, depth);
}

private void decodeBool(ref TomlParser parser, bool* output)
{
    if (matchLiteral(parser, "true"))
        *output = true;
    else if (matchLiteral(parser, "false"))
        *output = false;
    else
        parser.fail(SerdeErrorKind.typeMismatch);
}

private bool matchLiteral(ref TomlParser parser, String literal)
{
    if (literal.length > parser.input.length - parser.position)
        return false;
    foreach (index, value; literal)
        if (parser.input[parser.position + index] != value)
            return false;
    foreach (_; 0 .. literal.length)
        parser.take();
    return true;
}

private void decodeInteger(T)(ref TomlParser parser, T* output)
{
    bool negative;
    bool positive;
    if (parser.consume('+'))
        positive = true;
    else if (parser.consume('-'))
        negative = true;
    uint radix = 10;
    if (parser.peek == '0' && parser.position + 1 < parser.input.length)
    {
        const marker = parser.input[parser.position + 1];
        if (marker == 'x' || marker == 'o' || marker == 'b')
        {
            if (negative || positive)
            {
                parser.fail(SerdeErrorKind.invalidNumber);
                return;
            }
            parser.take();
            parser.take();
            radix = marker == 'x' ? 16 : marker == 'o' ? 8 : 2;
        }
    }
    ulong magnitude;
    bool digitSeen;
    bool underscore;
    bool leadingZero;
    while (!parser.atEnd)
    {
        if (parser.peek == '_')
        {
            if (!digitSeen || underscore)
            {
                parser.fail(SerdeErrorKind.invalidNumber);
                return;
            }
            underscore = true;
            parser.take();
            continue;
        }
        const digit = integerDigit(parser.peek);
        if (digit < 0 || cast(uint) digit >= radix)
            break;
        parser.take();
        if (!digitSeen)
            leadingZero = digit == 0;
        else if (radix == 10 && leadingZero)
        {
            parser.fail(SerdeErrorKind.invalidNumber);
            return;
        }
        digitSeen = true;
        underscore = false;
        if (magnitude > (ulong.max - cast(uint) digit) / radix)
        {
            parser.fail(SerdeErrorKind.numberOutOfRange);
            return;
        }
        magnitude = magnitude * radix + cast(uint) digit;
    }
    if (!digitSeen || underscore)
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    static if (__traits(isUnsigned, T))
    {
        if (negative || magnitude > T.max)
            parser.fail(SerdeErrorKind.numberOutOfRange);
        else
            *output = cast(T) magnitude;
    }
    else
    {
        enum ulong negativeLimit = cast(ulong)(0UL - cast(ulong) T.min);
        if ((!negative && magnitude > cast(ulong) T.max) ||
            (negative && magnitude > negativeLimit))
            parser.fail(SerdeErrorKind.numberOutOfRange);
        else if (negative)
            *output = magnitude == negativeLimit ? T.min : cast(T)-cast(long) magnitude;
        else
            *output = cast(T) magnitude;
    }
}

private int integerDigit(char value) pure @safe
{
    if (value >= '0' && value <= '9')
        return value - '0';
    if (value >= 'a' && value <= 'f')
        return value - 'a' + 10;
    if (value >= 'A' && value <= 'F')
        return value - 'A' + 10;
    return -1;
}

private void decodeFloat(T)(ref TomlParser parser, T* output)
{
    bool negative;
    if (parser.consume('+'))
    {
    }
    else if (parser.consume('-'))
        negative = true;
    if (matchLiteral(parser, "inf"))
    {
        *output = negative ? -T.infinity : T.infinity;
        return;
    }
    if (matchLiteral(parser, "nan"))
    {
        *output = T.nan;
        return;
    }
    const start = parser.position - (negative ? 1 : 0);
    while (!parser.atEnd && ((parser.peek >= '0' && parser.peek <= '9') ||
            parser.peek == '_' || parser.peek == '.' || parser.peek == 'e' ||
            parser.peek == 'E' || parser.peek == '+' || parser.peek == '-'))
        parser.take();
    const rawLength = parser.position - start;
    if (rawLength >= 128)
    {
        parser.fail(SerdeErrorKind.numberOutOfRange);
        return;
    }
    char[128] text;
    size_t length;
    bool floatingMarker;
    foreach (character; parser.input[start .. parser.position])
    {
        if (character != '_')
            text[length++] = character;
        if (character == '.' || character == 'e' || character == 'E')
            floatingMarker = true;
    }
    text[length] = '\0';
    char* end;
    errno = 0;
    const value = strtod(text.ptr, &end);
    if (!floatingMarker || end != text.ptr + length)
        parser.fail(SerdeErrorKind.invalidNumber);
    else if (errno == ERANGE ||
        (T.sizeof <= float.sizeof && !isfinite(cast(float) value)))
        parser.fail(SerdeErrorKind.numberOutOfRange);
    else
        *output = cast(T) value;
}

private void decodeEnum(T)(ref TomlParser parser, T* output)
{
    String name;
    bool owned;
    decodeStringToken(parser, &name, &owned, true);
    if (!parser.error.ok)
        return;
    bool found;
    static foreach (member; __traits(allMembers, T))
        static if (__traits(compiles, __traits(getMember, T, member)))
            if (!found && equalBytes(name, member))
                {
                *output = __traits(getMember, T, member);
                found = true;
            }
    if (owned)
        parser.allocator.deallocate(cast(char*) name.ptr, name.length + 1);
    if (!found)
        parser.fail(SerdeErrorKind.typeMismatch);
}

private void decodeDynamicArray(T)(ref TomlParser parser, T* output, size_t depth)
{
    alias Element = typeof(T.init[0]);
    TomlParser counter = parser;
    counter.tablePathLength = 0;
    size_t count;
    countArray(counter, depth, &count);
    if (!counter.error.ok)
    {
        parser.error = counter.error;
        return;
    }
    Element* values = parser.allocator.tryAllocate!Element(count);
    if (count != 0 && values is null)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
    foreach (index; 0 .. count)
        values[index] = Element.init;
    *output = values[0 .. count];
    parser.consume('[');
    parser.valueSpace();
    foreach (index; 0 .. count)
    {
        decodeValue(parser, &values[index], depth + 1);
        if (!parser.error.ok)
            return;
        parser.valueSpace();
        if (index + 1 < count)
        {
            if (!parser.consume(','))
            {
                parser.fail(SerdeErrorKind.invalidSyntax);
                return;
            }
            parser.valueSpace();
        }
        else if (parser.consume(','))
            parser.valueSpace();
    }
    if (!parser.consume(']'))
        parser.fail(SerdeErrorKind.invalidSyntax);
}

private void decodeFixedArray(T)(ref TomlParser parser, T* output, size_t depth)
{
    if (!parser.consume('['))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    parser.valueSpace();
    foreach (index; 0 .. output.length)
    {
        if (index != 0)
        {
            if (!parser.consume(','))
            {
                parser.fail(SerdeErrorKind.typeMismatch);
                return;
            }
            parser.valueSpace();
        }
        decodeValue(parser, &(*output)[index], depth + 1);
        if (!parser.error.ok)
            return;
        parser.valueSpace();
    }
    if (!parser.consume(']'))
        parser.fail(SerdeErrorKind.typeMismatch);
}

private void countArray(ref TomlParser parser, size_t depth, size_t* count)
{
    if (!parser.consume('['))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    parser.valueSpace();
    if (parser.consume(']'))
        return;
    for (;;)
    {
        if (*count == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
        ++*count;
        skipValue(parser, depth + 1);
        if (!parser.error.ok)
            return;
        parser.valueSpace();
        if (parser.consume(']'))
            return;
        if (!parser.consume(','))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.valueSpace();
        if (parser.consume(']'))
            return;
    }
}

private void skipValue(ref TomlParser parser, size_t depth)
{
    parser.valueSpace();
    if (parser.peek == '"' || parser.peek == '\'')
    {
        String value;
        bool owned;
        decodeStringToken(parser, &value, &owned);
        if (owned)
            parser.allocator.deallocate(cast(char*) value.ptr, value.length + 1);
        return;
    }
    if (parser.peek == '[')
    {
        size_t count;
        countArray(parser, depth, &count);
        return;
    }
    if (parser.peek == '{')
    {
        parser.take();
        parser.horizontalSpace();
        if (parser.consume('}'))
            return;
        for (;;)
        {
            ParsedKey[64] keys;
            size_t length;
            parseKeyPath(parser, keys[], &length);
            clearKeys(parser, keys[], length);
            parser.horizontalSpace();
            if (!parser.consume('='))
            {
                parser.fail(SerdeErrorKind.invalidSyntax);
                return;
            }
            skipValue(parser, depth + 1);
            parser.horizontalSpace();
            if (parser.consume('}'))
                return;
            if (!parser.consume(','))
            {
                parser.fail(SerdeErrorKind.invalidSyntax);
                return;
            }
            parser.horizontalSpace();
        }
    }
    const start = parser.position;
    while (!parser.atEnd && parser.peek != ',' && parser.peek != ']' &&
        parser.peek != '}' && parser.peek != '#' && parser.peek != '\n' &&
        parser.peek != '\r' && parser.peek != ' ' && parser.peek != '\t')
        parser.take();
    if (parser.position == start)
        parser.fail(SerdeErrorKind.invalidSyntax);
}

private void decodeString(ref TomlParser parser, String* output)
{
    bool owned;
    decodeStringToken(parser, output, &owned, true);
}

private void decodeStringToken(
    ref TomlParser parser,
    String* output,
    bool* owned,
    bool forceCopy = false,
)
{
    *output = null;
    *owned = false;
    const quote = parser.peek;
    if (quote != '"' && quote != '\'')
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    if (parser.position + 2 < parser.input.length &&
        parser.input[parser.position + 1] == quote &&
        parser.input[parser.position + 2] == quote)
    {
        parser.fail(SerdeErrorKind.unsupportedValue);
        return;
    }
    parser.take();
    const start = parser.position;
    size_t decodedLength;
    bool escaped;
    while (!parser.atEnd && parser.peek != quote)
    {
        const value = cast(ubyte) parser.peek;
        if (value == '\n' || value == '\r' || value < 0x20 && value != '\t')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        if (quote == '"' && value == '\\')
        {
            escaped = true;
            parser.take();
            if (!scanEscape(parser, &decodedLength))
                return;
        }
        else
        {
            const width = utf8Width(parser.input, parser.position);
            if (width == 0)
            {
                parser.fail(SerdeErrorKind.invalidUtf8);
                return;
            }
            foreach (_; 0 .. width)
                parser.take();
            decodedLength += width;
        }
        if (decodedLength > parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
    }
    if (!parser.consume(quote))
    {
        parser.fail(SerdeErrorKind.unexpectedEnd);
        return;
    }
    const end = parser.position - 1;
    if (!escaped && !forceCopy)
    {
        *output = parser.input[start .. end];
        return;
    }
    char* destination = parser.allocator.tryAllocate!char(decodedLength + 1);
    if (destination is null)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
    size_t source = start;
    size_t target;
    while (source < end)
    {
        if (quote == '"' && parser.input[source] == '\\')
        {
            ++source;
            decodeEscapeBytes(parser.input, &source, destination, &target);
        }
        else
            destination[target++] = parser.input[source++];
    }
    destination[target] = '\0';
    *output = destination[0 .. target];
    *owned = true;
}

private bool scanEscape(ref TomlParser parser, size_t* decodedLength)
{
    if (parser.atEnd)
    {
        parser.fail(SerdeErrorKind.unexpectedEnd);
        return false;
    }
    const value = parser.take();
    switch (value)
    {
        case '"':
        case '\\':
        case 'b':
        case 't':
        case 'n':
        case 'f':
        case 'r':
            ++*decodedLength;
            return true;
        case 'u':
        case 'U':
            const digits = value == 'u' ? 4 : 8;
            uint codePoint;
            foreach (_; 0 .. digits)
            {
                if (parser.atEnd)
                {
                    parser.fail(SerdeErrorKind.unexpectedEnd);
                    return false;
                }
                const digit = integerDigit(parser.take());
                if (digit < 0 || digit >= 16)
                {
                    parser.fail(SerdeErrorKind.invalidEscape);
                    return false;
                }
                codePoint = codePoint * 16 + cast(uint) digit;
            }
            if (codePoint > 0x10ffff ||
                (codePoint >= 0xd800 && codePoint <= 0xdfff))
            {
                parser.fail(SerdeErrorKind.invalidEscape);
                return false;
            }
            *decodedLength += codePoint < 0x80 ? 1 : codePoint < 0x800 ? 2 : codePoint < 0x10000 ? 3 : 4;
            return true;
        default:
            parser.fail(SerdeErrorKind.invalidEscape);
            return false;
    }
}

private void decodeEscapeBytes(
    scope String input,
    size_t* source,
    char* destination,
    size_t* target,
)
{
    const value = input[(*source)++];
    switch (value)
    {
        case '"':
        case '\\':
            destination[(*target)++] = value;
            return;
        case 'b':
            destination[(*target)++] = '\b';
            return;
        case 't':
            destination[(*target)++] = '\t';
            return;
        case 'n':
            destination[(*target)++] = '\n';
            return;
        case 'f':
            destination[(*target)++] = '\f';
            return;
        case 'r':
            destination[(*target)++] = '\r';
            return;
        case 'u':
        case 'U':
            const digits = value == 'u' ? 4 : 8;
            uint codePoint;
            foreach (_; 0 .. digits)
                codePoint = codePoint * 16 + cast(uint) integerDigit(input[(*source)++]);
            appendUtf8(destination, target, codePoint);
            return;
        default:
            return;
    }
}

private void appendUtf8(char* output, size_t* position, uint value)
{
    if (value < 0x80)
        output[(*position)++] = cast(char) value;
    else if (value < 0x800)
    {
        output[(*position)++] = cast(char)(0xc0 | (value >> 6));
        output[(*position)++] = cast(char)(0x80 | (value & 0x3f));
    }
    else if (value < 0x10000)
    {
        output[(*position)++] = cast(char)(0xe0 | (value >> 12));
        output[(*position)++] = cast(char)(0x80 | ((value >> 6) & 0x3f));
        output[(*position)++] = cast(char)(0x80 | (value & 0x3f));
    }
    else
    {
        output[(*position)++] = cast(char)(0xf0 | (value >> 18));
        output[(*position)++] = cast(char)(0x80 | ((value >> 12) & 0x3f));
        output[(*position)++] = cast(char)(0x80 | ((value >> 6) & 0x3f));
        output[(*position)++] = cast(char)(0x80 | (value & 0x3f));
    }
}

private bool validUtf8(scope String value) pure @safe
{
    size_t position;
    while (position < value.length)
    {
        const width = utf8Width(value, position);
        if (width == 0)
            return false;
        position += width;
    }
    return true;
}

private size_t utf8Width(scope String value, size_t position) pure @safe
{
    const first = cast(ubyte) value[position];
    if (first < 0x80)
        return 1;
    size_t width;
    uint minimum;
    uint codePoint;
    if (first >= 0xc2 && first <= 0xdf)
    {
        width = 2;
        minimum = 0x80;
        codePoint = first & 0x1f;
    }
    else if (first >= 0xe0 && first <= 0xef)
    {
        width = 3;
        minimum = 0x800;
        codePoint = first & 0x0f;
    }
    else if (first >= 0xf0 && first <= 0xf4)
    {
        width = 4;
        minimum = 0x10000;
        codePoint = first & 0x07;
    }
    else
        return 0;
    if (width > value.length - position)
        return 0;
    foreach (index; 1 .. width)
    {
        const next = cast(ubyte) value[position + index];
        if ((next & 0xc0) != 0x80)
            return 0;
        codePoint = (codePoint << 6) | (next & 0x3f);
    }
    if (codePoint < minimum || codePoint > 0x10ffff ||
        (codePoint >= 0xd800 && codePoint <= 0xdfff))
        return 0;
    return width;
}

private bool equalBytes(scope String left, scope String right) pure @safe
{
    if (left.length != right.length)
        return false;
    foreach (index, value; left)
        if (value != right[index])
            return false;
    return true;
}

private bool looksLikeDateTime(scope String input, size_t start) pure @safe
{
    size_t position = start;
    if (position < input.length && (input[position] == '+' || input[position] == '-'))
        ++position;
    bool digit;
    for (; position < input.length; ++position)
    {
        const value = input[position];
        if ((value >= '0' && value <= '9') || value == '.')
        {
            digit = true;
            continue;
        }
        if (value == ':' || value == 'T' || value == 't' || value == 'Z' || value == 'z')
            return digit;
        if (value == '-')
        {
            if (position != 0 && (input[position - 1] == 'e' || input[position - 1] == 'E'))
                continue;
            return digit;
        }
        if (value == '_' || value == '+' || value == 'e' || value == 'E')
            continue;
        break;
    }
    return false;
}
