module xtb.serde.json;

nothrow @nogc:

import core.stdc.errno : ERANGE, errno;
import core.stdc.math : isfinite;
import core.stdc.stdio : snprintf;
import core.stdc.stdlib : strtod;
import core.lifetime : move;
import xtb.core.lifetime : moveEmplace;
import core.internal.traits : hasElaborateDestructor;
import xtb.core.array;
import xtb.core.hash_map;
import xtb.core.memory : Allocator, deallocateArray, tryAllocateArray, tryAllocateInit, tryAllocateInitArray;
import xtb.core.option : Option;
import xtb.core.owned_string;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.print : Writer;
import xtb.core.string;
import xtb.core.string_hash_map;
import xtb.core.types : String;
import xtb.core.utf8 : DecodedCodePoint, decodeCodePoint, encodeUtf8,
    isValidUtf8;
import xtb.serde.attributes : AliasName, Flatten, Ignore, KeyCase, OmitDefault,
    Rename, Required, TagLayout;
import xtb.serde.casing : writeCased;
import xtb.serde.error : SerdeError, SerdeErrorKind, SerdeLimits;
import xtb.serde.ownership : Deserialized, abandonDeserialized,
    deserializationAllocator, prepareDeserialized;
import xtb.serde.traits : ArrayElement, FieldSymbol, FieldType, Unqualified,
    applySchemaDefaults, enumCase, enumMemberMatches, enumMemberName, fieldHas,
    fieldMatches, fieldName, fieldOrdinal, fieldShouldOmit, discriminantIndex,
    DiscriminantType, fieldAdapterCount, fieldDefaultValueCount, FieldAdapter,
    HashMapKey, HashMapValue, isArray, isDefaultValueAttribute, isDynamicArray,
    isFixedArray, isHashMap, isOption, isOwnedSerdeValue, isOwnedString,
    isSerdeStruct, isString, isStringBuf, isStringHashMap, isTaggedUnion,
    deinitOwnedValue, initializeOwnedValue, OptionElement, StringHashMapValue,
    payloadIndex, PayloadType, schemaCase,
    serializedFieldCount, taggedUnionLayout, unionCaseIsActive, UnionMemberType,
    validateBorrowedValue, validateOwnedValue, validateValueSchema;

struct JsonWriteOptions
{
    bool pretty;
    ubyte indentWidth = 2;
    KeyCase keyCase = KeyCase.schema;
    KeyCase variantCase = KeyCase.schema;
    size_t maxDepth = 64;
}

struct JsonReadOptions
{
    SerdeLimits limits;
    KeyCase keyCase = KeyCase.schema;
    KeyCase variantCase = KeyCase.schema;
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

SerdeError writeJson(T)(
    ref Writer writer,
    scope const ref T value,
    JsonWriteOptions options = JsonWriteOptions.init,
)
{
    validateValueSchema!T();
    JsonEncoder encoder;
    encoder.writer = &writer;
    encoder.options = options;
    encodeValue(encoder, value, 0);
    writer.flush();
    if (!encoder.error.ok)
        return encoder.error;
    return writer.ok ? success() : simpleError(SerdeErrorKind.outputFailure);
}

SerdeError readJson(T)(
    scope String input,
    Allocator* allocator,
    Deserialized!T* output,
    JsonReadOptions options = JsonReadOptions.init,
)
{
    validateBorrowedValue!T();
    version (XTB_Checked)
    {
        require(options.limits.maxDepth != 0, "JSON max depth must be nonzero");
        require(options.limits.maxCollectionLength != 0,
            "JSON collection limit must be nonzero");
    }

    T* value;
    if (!prepareDeserialized(allocator, output, &value))
        return simpleError(SerdeErrorKind.allocationFailure);
    applySchemaDefaults(value);

    JsonParser parser;
    parser.input = input;
    parser.allocator = deserializationAllocator(output);
    parser.options = options;
    parser.line = 1;
    parser.column = 1;
    parser.skipWhitespace();
    decodeValue(parser, value, 0);
    if (parser.error.ok)
    {
        parser.skipWhitespace();
        if (parser.position != input.length)
            parser.fail(SerdeErrorKind.invalidSyntax);
    }
    if (!parser.error.ok)
    {
        SerdeError error = parser.error;
        abandonDeserialized(output);
        return error;
    }
    return success();
}

SerdeError readJson(T)(
    scope String input,
    Allocator* allocator,
    T* output,
    JsonReadOptions options = JsonReadOptions.init,
) if (isOwnedSerdeValue!T)
{
    validateOwnedValue!T();
    version (XTB_Checked)
    {
        require(allocator !is null && *allocator !is null,
            "serde requires a valid allocator");
        require(output !is null, "owned JSON output pointer is null");
        require(options.limits.maxDepth != 0, "JSON max depth must be nonzero");
        require(options.limits.maxCollectionLength != 0,
            "JSON collection limit must be nonzero");
    }

    T decoded;
    initializeOwnedValue(allocator, &decoded);
    applySchemaDefaults(&decoded);
    JsonParser parser;
    parser.input = input;
    parser.allocator = allocator;
    parser.options = options;
    parser.line = 1;
    parser.column = 1;
    parser.skipWhitespace();
    decodeValue(parser, &decoded, 0);
    if (parser.error.ok)
    {
        parser.skipWhitespace();
        if (parser.position != input.length)
            parser.fail(SerdeErrorKind.invalidSyntax);
    }
    if (!parser.error.ok)
    {
        SerdeError error = parser.error;
        deinitOwnedValue(&decoded);
        return error;
    }
    deinitOwnedValue(output);
    moveEmplace(decoded, *output);
    return success();
}

private struct JsonEncoder
{
nothrow @nogc:

    Writer* writer;
    JsonWriteOptions options;
    SerdeError error;

    void fail(SerdeErrorKind kind)
    {
        if (error.ok)
            error = simpleError(kind);
    }

    void newline(size_t depth)
    {
        if (!options.pretty)
            return;
        writer.put('\n');
        writer.repeat(' ', depth * options.indentWidth);
    }
}

private bool valuesEqual(T, E)(scope const ref T value, scope const ref E expected)
@system
{
    alias U = Unqualified!T;
    static if (isString!U)
    {
        if (value.length != expected.length)
            return false;
        foreach (index, character; value)
            if (character != expected[index])
                return false;
        return true;
    }
    else static if (isStringBuf!U || isOwnedString!U)
    {
        if (value.byteLength != expected.byteLength)
            return false;
        foreach (index; 0 .. value.byteLength)
            if (value.view[index] != expected.view[index])
                return false;
        return true;
    }
    else static if (isOption!U)
    {
        if (value.isSome != expected.isSome)
            return false;
        return value.isNone || valuesEqual(value.value, expected.value);
    }
    else static if (isDynamicArray!U)
    {
        if (value.length != expected.length)
            return false;
        foreach (index, ref const element; value)
            if (!valuesEqual(element, expected[index]))
                return false;
        return true;
    }
    else static if (isArray!U)
    {
        if (value.length != expected.length)
            return false;
        foreach (index; 0 .. value.length)
            if (!valuesEqual(value[index], expected[index]))
                return false;
        return true;
    }
    else static if (isHashMap!U || isStringHashMap!U)
    {
        if (value.length != expected.length)
            return false;
        auto items = value.pointerItems();
        while (!items.empty)
        {
            const expectedValue = expected.find(*items.front.key);
            if (expectedValue is null ||
                !valuesEqual(*items.front.value, *expectedValue))
                return false;
            items.popFront();
        }
        return true;
    }
    else static if (is(U == Pointee*, Pointee))
        return value is expected;
    else static if (isFixedArray!U)
    {
        foreach (index, ref const element; value)
            if (!valuesEqual(element, expected[index]))
                return false;
        return true;
    }
    else static if (isSerdeStruct!U)
    {
        static foreach (index; 0 .. U.tupleof.length)
            static if (!fieldHas!(U, index, Ignore))
                if (!valuesEqual(value.tupleof[index], expected.tupleof[index]))
                    return false;
        return true;
    }
    else
        return value == expected;
}

private bool fieldIsDefault(T, size_t index, F)(scope const ref F value)
@system
{
    static if (fieldDefaultValueCount!(T, index) != 0)
    {
        bool result;
        static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
            static if (isDefaultValueAttribute!(typeof(attribute)))
                {
                auto expected = attribute.value;
                result = valuesEqual(value, expected);
            }
        return result;
    }
    else static if (hasElaborateDestructor!(Unqualified!F) ||
        !__traits(isCopyable, Unqualified!F))
    {
        Unqualified!F defaults;
        return valuesEqual(value, defaults);
    }
    else
    {
        auto expected = Unqualified!T.init.tupleof[index];
        return valuesEqual(value, expected);
    }
}

private void encodeValue(T)(ref JsonEncoder encoder, scope const ref T value, size_t depth)
{
    if (!encoder.error.ok)
        return;
    alias U = Unqualified!T;
    static if (isString!U)
        encodeString(encoder, cast(String) value);
    else static if (isStringBuf!U || isOwnedString!U)
        encodeString(encoder, value.view);
    else static if (is(U == bool))
        encoder.writer.put(value ? "true" : "false");
    else static if (is(U == enum))
        encodeEnum(encoder, value);
    else static if (__traits(isIntegral, U))
        encoder.writer.value(value);
    else static if (__traits(isFloating, U))
        encodeFloat(encoder, value);
    else static if (isOption!U)
    {
        if (value.empty)
            encoder.writer.put("null");
        else
            encodeValue(encoder, value.value, depth);
    }
    else static if (is(U == Pointee*, Pointee))
    {
        if (value is null)
            encoder.writer.put("null");
        else
            encodeValue(encoder, *value, depth);
    }
    else static if (isArray!U)
        encodeArray(encoder, value.slice, depth);
    else static if (isDynamicArray!U || isFixedArray!U)
        encodeArray(encoder, value, depth);
    else static if (isHashMap!U || isStringHashMap!U)
        encodeHashMap(encoder, value, depth);
    else static if (isTaggedUnion!U)
        encodeTaggedUnion(encoder, value, depth);
    else static if (isSerdeStruct!U)
        encodeObject(encoder, value, depth);
}

private void encodeTaggedUnion(T)(
    ref JsonEncoder encoder,
    scope const ref T value,
    size_t depth,
)
{
    alias U = Unqualified!T;
    if (depth >= encoder.options.maxDepth)
    {
        encoder.fail(SerdeErrorKind.depthLimit);
        return;
    }
    encoder.writer.put('{');
    encoder.newline(depth + 1);
    static if (taggedUnionLayout!U == TagLayout.external)
    {
        encodeEnum(encoder, value.tupleof[discriminantIndex!U]);
        encoder.writer.put(encoder.options.pretty ? ": " : ":");
        encodeActiveUnionCase(encoder, value, depth + 1);
    }
    else
    {
        encodeFieldName!(U, discriminantIndex!U)(encoder);
        encoder.writer.put(encoder.options.pretty ? ": " : ":");
        encodeEnum(encoder, value.tupleof[discriminantIndex!U]);
        static if (taggedUnionLayout!U == TagLayout.adjacent)
        {
            encoder.writer.put(',');
            encoder.newline(depth + 1);
            encodeFieldName!(U, payloadIndex!U)(encoder);
            encoder.writer.put(encoder.options.pretty ? ": " : ":");
            encodeActiveUnionCase(encoder, value, depth + 1);
        }
        else
        {
            bool wrote = true;
            encodeActiveUnionFields(encoder, value, depth, &wrote);
        }
    }
    encoder.newline(depth);
    encoder.writer.put('}');
}

private void encodeActiveUnionCase(T)(
    ref JsonEncoder encoder,
    scope const ref T value,
    size_t depth,
)
{
    alias U = Unqualified!T;
    alias P = PayloadType!U;
    bool found;
    static foreach (index; 0 .. P.tupleof.length)
    {
        if (!found && unionCaseIsActive!(P, index)(
                value.tupleof[discriminantIndex!U]))
        {
            encodeValue(encoder,
                value.tupleof[payloadIndex!U].tupleof[index], depth);
            found = true;
        }
    }
    if (!found)
        encoder.fail(SerdeErrorKind.unknownVariant);
}

private void encodeActiveUnionFields(T)(
    ref JsonEncoder encoder,
    scope const ref T value,
    size_t depth,
    bool* wrote,
)
{
    alias U = Unqualified!T;
    alias P = PayloadType!U;
    bool found;
    static foreach (index; 0 .. P.tupleof.length)
    {
        if (!found && unionCaseIsActive!(P, index)(
                value.tupleof[discriminantIndex!U]))
        {
            encodeFields(encoder,
                value.tupleof[payloadIndex!U].tupleof[index], depth, wrote);
            found = true;
        }
    }
    if (!found)
        encoder.fail(SerdeErrorKind.unknownVariant);
}

private void encodeObject(T)(ref JsonEncoder encoder, scope const ref T value, size_t depth)
{
    if (depth >= encoder.options.maxDepth)
    {
        encoder.fail(SerdeErrorKind.depthLimit);
        return;
    }
    encoder.writer.put('{');
    bool wrote;
    encodeFields(encoder, value, depth, &wrote);
    if (wrote)
        encoder.newline(depth);
    encoder.writer.put('}');
}

private void encodeFields(T)(
    ref JsonEncoder encoder,
    scope const ref T value,
    size_t depth,
    bool* wrote,
)
{
    alias U = Unqualified!T;
    static foreach (index; 0 .. U.tupleof.length)
    {
        static if (!fieldHas!(U, index, Ignore))
        {
            static if (fieldHas!(U, index, Flatten))
                encodeFields(encoder, value.tupleof[index], depth, wrote);
            else
                encodeOneField!(U, index)(encoder, value.tupleof[index], depth, wrote);
        }
    }
}

private void encodeOneField(T, size_t index, F)(
    ref JsonEncoder encoder,
    scope const ref F value,
    size_t depth,
    bool* wrote,
)
{
    if (fieldShouldOmit!(T, index)(value))
        return;
    static if (fieldHas!(T, index, OmitDefault))
        if (fieldIsDefault!(T, index)(value))
            return;
    static if (fieldAdapterCount!(T, index) != 0)
    {
        alias Adapter = FieldAdapter!(T, index);
        Adapter.Representation representation;
        const kind = Adapter.encode(value, &representation);
        if (kind != SerdeErrorKind.none)
        {
            encoder.fail(kind);
            return;
        }
        if (*wrote)
            encoder.writer.put(',');
        encoder.newline(depth + 1);
        encodeFieldName!(T, index)(encoder);
        encoder.writer.put(encoder.options.pretty ? ": " : ":");
        encodeValue(encoder, representation, depth + 1);
    }
    else
    {
        if (*wrote)
            encoder.writer.put(',');
        encoder.newline(depth + 1);
        encodeFieldName!(T, index)(encoder);
        encoder.writer.put(encoder.options.pretty ? ": " : ":");
        encodeValue(encoder, value, depth + 1);
    }
    *wrote = true;
}

private void encodeFieldName(T, size_t index)(ref JsonEncoder encoder)
{
    encoder.writer.put('"');
    static if (fieldHas!(T, index, Rename))
        encoder.writer.put(fieldName!(T, index));
    else
    {
        const casing = encoder.options.keyCase == KeyCase.schema
            ? schemaCase!T : encoder.options.keyCase;
        (*encoder.writer).writeCased(fieldName!(T, index), casing);
    }
    encoder.writer.put('"');
}

private void encodeArray(Element)(
    ref JsonEncoder encoder,
    scope const(Element)[] values,
    size_t depth,
)
{
    if (depth >= encoder.options.maxDepth)
    {
        encoder.fail(SerdeErrorKind.depthLimit);
        return;
    }
    encoder.writer.put('[');
    foreach (index, ref const value; values)
    {
        if (index != 0)
            encoder.writer.put(',');
        if (encoder.options.pretty)
            encoder.newline(depth + 1);
        encodeValue(encoder, value, depth + 1);
    }
    if (encoder.options.pretty && values.length != 0)
        encoder.newline(depth);
    encoder.writer.put(']');
}

private void encodeHashMap(T)(
    ref JsonEncoder encoder,
    scope const ref T value,
    size_t depth,
)
{
    if (depth >= encoder.options.maxDepth)
    {
        encoder.fail(SerdeErrorKind.depthLimit);
        return;
    }
    encoder.writer.put('{');
    auto items = value.pointerItems();
    size_t index;
    while (!items.empty)
    {
        if (index++ != 0)
            encoder.writer.put(',');
        if (encoder.options.pretty)
            encoder.newline(depth + 1);
        encodeString(encoder, *items.front.key);
        encoder.writer.put(encoder.options.pretty ? ": " : ":");
        encodeValue(encoder, *items.front.value, depth + 1);
        items.popFront();
    }
    if (encoder.options.pretty && value.length != 0)
        encoder.newline(depth);
    encoder.writer.put('}');
}

private void encodeString(ref JsonEncoder encoder, scope String value)
{
    if (!isValidUtf8(value))
    {
        encoder.fail(SerdeErrorKind.invalidUtf8);
        return;
    }
    encoder.writer.put('"');
    size_t offset;
    while (offset < value.length)
    {
        DecodedCodePoint decoded;
        const utf8Error = decodeCodePoint(value, offset, &decoded);
        if (utf8Error.failed)
        {
            encoder.fail(SerdeErrorKind.invalidUtf8);
            return;
        }
        offset += decoded.byteLength;
        const dchar character = decoded.value;
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
            case '\f':
                encoder.writer.put("\\f");
                break;
            case '\n':
                encoder.writer.put("\\n");
                break;
            case '\r':
                encoder.writer.put("\\r");
                break;
            case '\t':
                encoder.writer.put("\\t");
                break;
            default:
                if (cast(ubyte) character < 0x20)
                {
                    char[7] escaped;
                    snprintf(escaped.ptr, escaped.length, "\\u%04x",
                        cast(uint) cast(ubyte) character);
                    encoder.writer.put(escaped[0 .. 6]);
                }
                else
                    encoder.writer.value(character);
                break;
        }
    }
    encoder.writer.put('"');
}

private void encodeFloat(T)(ref JsonEncoder encoder, T value)
{
    if (!isfinite(cast(double) value))
    {
        encoder.fail(SerdeErrorKind.unsupportedValue);
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
        encoder.writer.put(text[0 .. cast(size_t) count]);
}

private void encodeEnum(T)(ref JsonEncoder encoder, T value)
{
    bool found;
    static foreach (name; __traits(allMembers, T))
    {
        static if (__traits(compiles, __traits(getMember, T, name)))
            if (!found && value == __traits(getMember, T, name))
                {
                encoder.writer.put('"');
                enum renamed = enumMemberName!(T, name) != name;
                if (renamed)
                    encoder.writer.put(enumMemberName!(T, name));
                else
                    {
                    const casing = encoder.options.variantCase == KeyCase.schema
                        ? enumCase!T
                        : encoder.options.variantCase;
                    (*encoder.writer).writeCased(enumMemberName!(T, name), casing);
                }
                encoder.writer.put('"');
                found = true;
            }
    }
    if (!found)
        encoder.fail(SerdeErrorKind.unsupportedValue);
}

private struct JsonParser
{
nothrow @nogc:

    String input;
    Allocator* allocator;
    JsonReadOptions options;
    size_t position;
    size_t line;
    size_t column;
    SerdeError error;

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
        const value = input[position++];
        if (value == '\n')
        {
            ++line;
            column = 1;
        }
        else
            ++column;
        return value;
    }

    bool consume(char expected)
    {
        if (peek != expected)
            return false;
        take();
        return true;
    }

    void skipWhitespace()
    {
        while (!atEnd)
        {
            const value = peek;
            if (value != ' ' && value != '\t' && value != '\n' && value != '\r')
                break;
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
}

private void decodeValue(T)(ref JsonParser parser, T* output, size_t depth)
{
    if (!parser.error.ok)
        return;
    alias U = Unqualified!T;
    parser.skipWhitespace();
    static if (isString!U)
        decodeString(parser, cast(String*) output);
    else static if (isStringBuf!U)
        decodeStringBuf(parser, cast(StringBuf*) output);
    else static if (isOwnedString!U)
        decodeOwnedString(parser, cast(OwnedString*) output);
    else static if (is(U == bool))
        decodeBool(parser, output);
    else static if (is(U == enum))
        decodeEnum(parser, output);
    else static if (__traits(isIntegral, U))
        decodeInteger(parser, output);
    else static if (__traits(isFloating, U))
        decodeFloat(parser, output);
    else static if (isOption!U)
        decodeOption!(OptionElement!U)(parser, cast(U*) output, depth);
    else static if (is(U == Pointee*, Pointee))
        decodePointer(parser, output, depth);
    else static if (isArray!U)
        decodeArray(parser, cast(U*) output, depth);
    else static if (isDynamicArray!U)
        decodeDynamicArray(parser, output, depth);
    else static if (isFixedArray!U)
        decodeFixedArray(parser, output, depth);
    else static if (isHashMap!U)
        decodeHashMap(parser, cast(U*) output, depth);
    else static if (isStringHashMap!U)
        decodeStringHashMap!U(
            parser,
            cast(U*) output,
            depth,
        );
    else static if (isTaggedUnion!U)
        decodeTaggedUnion(parser, output, depth);
    else static if (isSerdeStruct!U)
        decodeObject(parser, output, depth);
}

private void decodeOption(T)(
    ref JsonParser parser,
    Option!T* output,
    size_t depth,
)
{
    if (matchLiteral(parser, "null"))
    {
        // Serde pre-initializes owning Option payload storage before decoding.
        // A JSON null keeps the Option absent, so that hidden storage must be
        // cleaned explicitly even though Option.reset() correctly sees no
        // active logical payload.
        deinitOwnedValue(&(*output).storage());
        (*output).reset();
        return;
    }
    decodeValue(parser, &(*output).storage(), depth);
    if (parser.error.ok)
        (*output).markPresent();
}

private void decodeTaggedUnion(T)(
    ref JsonParser parser,
    T* output,
    size_t depth,
)
{
    alias U = Unqualified!T;
    static if (taggedUnionLayout!U == TagLayout.external)
        decodeExternalTaggedUnion(parser, output, depth);
    else
    {
        DiscriminantType!U tag;
        JsonParser scanner = parser;
        scanTaggedDiscriminant!U(scanner, &tag, depth);
        if (!scanner.error.ok)
        {
            parser.error = scanner.error;
            return;
        }
        output.tupleof[discriminantIndex!U] = tag;
        bool found;
        alias P = PayloadType!U;
        static foreach (index; 0 .. P.tupleof.length)
        {
            if (!found && unionCaseIsActive!(P, index)(tag))
            {
                static if (taggedUnionLayout!U == TagLayout.adjacent)
                    decodeAdjacentTaggedCase!(U, index)(parser, output, depth);
                else
                    decodeInternalTaggedCase!(U, index)(parser, output, depth);
                found = true;
            }
        }
        if (!found)
            parser.fail(SerdeErrorKind.unknownVariant);
    }
}

private void decodeExternalTaggedUnion(T)(
    ref JsonParser parser,
    T* output,
    size_t depth,
)
{
    alias U = Unqualified!T;
    if (depth >= parser.options.limits.maxDepth)
    {
        parser.fail(SerdeErrorKind.depthLimit);
        return;
    }
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    parser.skipWhitespace();
    String name;
    bool owned;
    decodeStringToken(parser, &name, &owned);
    if (parser.error.ok)
        decodeTaggedEnumName(parser, name,
            &output.tupleof[discriminantIndex!U]);
    if (owned)
        parser.allocator.deallocateArray(name.ptr[0 .. name.length + 1]);
    if (!parser.error.ok)
        return;
    parser.skipWhitespace();
    if (!parser.consume(':'))
    {
        parser.fail(SerdeErrorKind.invalidSyntax);
        return;
    }
    parser.skipWhitespace();
    decodeActiveTaggedCase(parser, output, depth + 1);
    if (!parser.error.ok)
        return;
    parser.skipWhitespace();
    if (!parser.consume('}'))
        parser.fail(SerdeErrorKind.invalidSyntax);
}

private void scanTaggedDiscriminant(T)(
    ref JsonParser parser,
    DiscriminantType!T* tag,
    size_t depth,
)
{
    if (depth >= parser.options.limits.maxDepth)
    {
        parser.fail(SerdeErrorKind.depthLimit);
        return;
    }
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    parser.skipWhitespace();
    bool seen;
    size_t fields;
    while (!parser.consume('}'))
    {
        if (fields++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
        String key;
        bool owned;
        decodeStringToken(parser, &key, &owned);
        parser.skipWhitespace();
        if (parser.error.ok && !parser.consume(':'))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.skipWhitespace();
        if (parser.error.ok && fieldMatches!(T, discriminantIndex!T)(
                key, parser.options.keyCase))
        {
            if (seen)
                parser.fail(SerdeErrorKind.duplicateField, key);
            else
            {
                seen = true;
                decodeTaggedEnum(parser, tag);
            }
        }
        else if (parser.error.ok)
            skipValue(parser, depth + 1);
        if (owned)
            parser.allocator.deallocateArray(key.ptr[0 .. key.length + 1]);
        if (!parser.error.ok)
            return;
        parser.skipWhitespace();
        if (parser.consume('}'))
            break;
        if (!parser.consume(','))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();
        if (parser.peek == '}')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
    }
    if (!seen)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, discriminantIndex!T));
}

private void decodeActiveTaggedCase(T)(
    ref JsonParser parser,
    T* output,
    size_t depth,
)
{
    alias U = Unqualified!T;
    alias P = PayloadType!U;
    bool found;
    static foreach (index; 0 .. P.tupleof.length)
    {
        if (!found && unionCaseIsActive!(P, index)(
                output.tupleof[discriminantIndex!U]))
        {
            decodeValue(parser,
                &output.tupleof[payloadIndex!U].tupleof[index], depth);
            found = true;
        }
    }
    if (!found)
        parser.fail(SerdeErrorKind.unknownVariant);
}

private void decodeAdjacentTaggedCase(T, size_t caseIndex)(
    ref JsonParser parser,
    T* output,
    size_t depth,
)
{
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    bool seenTag;
    bool seenPayload;
    size_t fields;
    parser.skipWhitespace();
    while (!parser.consume('}'))
    {
        if (fields++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
        String key;
        bool owned;
        decodeStringToken(parser, &key, &owned);
        parser.skipWhitespace();
        if (parser.error.ok && !parser.consume(':'))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.skipWhitespace();
        if (parser.error.ok && fieldMatches!(T, discriminantIndex!T)(
                key, parser.options.keyCase))
        {
            if (seenTag)
                parser.fail(SerdeErrorKind.duplicateField, key);
            else
            {
                DiscriminantType!T tag;
                decodeTaggedEnum(parser, &tag);
                if (parser.error.ok && tag != output.tupleof[discriminantIndex!T])
                    parser.fail(SerdeErrorKind.unknownVariant);
                seenTag = true;
            }
        }
        else if (parser.error.ok && fieldMatches!(T, payloadIndex!T)(
                key, parser.options.keyCase))
        {
            if (seenPayload)
                parser.fail(SerdeErrorKind.duplicateField, key);
            else
            {
                decodeValue(parser,
                    &output.tupleof[payloadIndex!T].tupleof[caseIndex],
                    depth + 1);
                seenPayload = true;
            }
        }
        else if (parser.error.ok)
        {
            if (parser.options.limits.ignoreUnknownFields)
                skipValue(parser, depth + 1);
            else
                parser.fail(SerdeErrorKind.unknownField, key);
        }
        if (owned)
            parser.allocator.deallocateArray(key.ptr[0 .. key.length + 1]);
        if (!parser.error.ok)
            return;
        parser.skipWhitespace();
        if (parser.consume('}'))
            break;
        if (!parser.consume(','))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();
        if (parser.peek == '}')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
    }
    if (!seenTag)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, discriminantIndex!T));
    else if (!seenPayload)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, payloadIndex!T));
}

private void decodeInternalTaggedCase(T, size_t caseIndex)(
    ref JsonParser parser,
    T* output,
    size_t depth,
)
{
    alias P = PayloadType!T;
    alias C = UnionMemberType!(P, caseIndex);
    applySchemaDefaults(
        &output.tupleof[payloadIndex!T].tupleof[caseIndex]);
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    bool seenTag;
    bool[serializedFieldCount!C] seen;
    size_t fields;
    parser.skipWhitespace();
    while (!parser.consume('}'))
    {
        if (fields++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
        String key;
        bool owned;
        decodeStringToken(parser, &key, &owned);
        parser.skipWhitespace();
        if (parser.error.ok && !parser.consume(':'))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.skipWhitespace();
        if (parser.error.ok && fieldMatches!(T, discriminantIndex!T)(
                key, parser.options.keyCase))
        {
            if (seenTag)
                parser.fail(SerdeErrorKind.duplicateField, key);
            else
            {
                DiscriminantType!T tag;
                decodeTaggedEnum(parser, &tag);
                if (parser.error.ok && tag != output.tupleof[discriminantIndex!T])
                    parser.fail(SerdeErrorKind.unknownVariant);
                seenTag = true;
            }
        }
        else if (parser.error.ok)
        {
            bool matched;
            decodeField(parser,
                &output.tupleof[payloadIndex!T].tupleof[caseIndex],
                key, seen.ptr, 0, depth + 1, &matched);
            if (!matched && parser.error.ok)
            {
                if (parser.options.limits.ignoreUnknownFields)
                    skipValue(parser, depth + 1);
                else
                    parser.fail(SerdeErrorKind.unknownField, key);
            }
        }
        if (owned)
            parser.allocator.deallocateArray(key.ptr[0 .. key.length + 1]);
        if (!parser.error.ok)
            return;
        parser.skipWhitespace();
        if (parser.consume('}'))
            break;
        if (!parser.consume(','))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();
        if (parser.peek == '}')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
    }
    if (!seenTag)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, discriminantIndex!T));
    else
        validateRequired(parser,
            &output.tupleof[payloadIndex!T].tupleof[caseIndex], seen.ptr, 0);
}

private void decodeObject(T)(ref JsonParser parser, T* output, size_t depth)
{
    applySchemaDefaults(output);
    if (depth >= parser.options.limits.maxDepth)
    {
        parser.fail(SerdeErrorKind.depthLimit);
        return;
    }
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    bool[serializedFieldCount!T] seen;
    parser.skipWhitespace();
    if (parser.consume('}'))
    {
        validateRequired(parser, output, seen.ptr, 0);
        return;
    }
    size_t fields;
    for (;;)
    {
        if (fields == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
        ++fields;
        const keyStart = parser.position;
        String key;
        bool keyOwned;
        decodeStringToken(parser, &key, &keyOwned);
        if (!parser.error.ok)
            return;
        const rawKey = parser.input[keyStart + 1 .. parser.position - 1];
        parser.skipWhitespace();
        if (!parser.consume(':'))
        {
            if (keyOwned)
                parser.allocator.deallocateArray(key.ptr[0 .. key.length + 1]);
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();
        bool matched;
        decodeField(parser, output, key, seen.ptr, 0, depth + 1, &matched);
        if (keyOwned && parser.error.field.ptr is key.ptr)
            parser.error.field = rawKey;
        if (keyOwned)
            parser.allocator.deallocateArray(key.ptr[0 .. key.length + 1]);
        if (!parser.error.ok)
            return;
        if (!matched)
        {
            if (!parser.options.limits.ignoreUnknownFields)
            {
                parser.fail(SerdeErrorKind.unknownField, rawKey);
                return;
            }
            skipValue(parser, depth + 1);
            if (!parser.error.ok)
                return;
        }
        parser.skipWhitespace();
        if (parser.consume('}'))
            break;
        if (!parser.consume(','))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();
        if (parser.peek == '}')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
    }
    validateRequired(parser, output, seen.ptr, 0);
}

private void decodeField(T)(
    ref JsonParser parser,
    T* output,
    scope String key,
    bool* seen,
    size_t base,
    size_t depth,
    bool* matched,
)
{
    static foreach (index; 0 .. T.tupleof.length)
    {
        static if (!fieldHas!(T, index, Ignore))
        {
            static if (fieldHas!(T, index, Flatten))
            {
                if (!*matched)
                    decodeField(parser, &output.tupleof[index], key, seen,
                        base + fieldOrdinal!(T, index), depth, matched);
            }
            else
            {
                if (!*matched && fieldMatches!(T, index)(key, parser.options.keyCase))
                {
                    const ordinal = base + fieldOrdinal!(T, index);
                    if (seen[ordinal])
                    {
                        parser.fail(SerdeErrorKind.duplicateField, key);
                        return;
                    }
                    seen[ordinal] = true;
                    *matched = true;
                    static if (fieldAdapterCount!(T, index) != 0)
                        decodeAdaptedValue!(T, index)(parser,
                            &output.tupleof[index], depth);
                    else
                        decodeValue(parser, &output.tupleof[index], depth);
                }
            }
        }
    }
}

private void decodeAdaptedValue(T, size_t index, F)(
    ref JsonParser parser,
    F* output,
    size_t depth,
)
{
    alias Adapter = FieldAdapter!(T, index);
    alias Representation = Adapter.Representation;
    Representation representation;
    static if (isString!Representation)
    {
        bool owned;
        decodeStringToken(parser, cast(String*)&representation, &owned);
        if (parser.error.ok)
        {
            const kind = Adapter.decode(representation, parser.allocator, output);
            if (kind != SerdeErrorKind.none)
                parser.fail(kind);
        }
        if (owned)
            parser.allocator.deallocateArray(representation.ptr[0 .. representation.length + 1]);
    }
    else
    {
        decodeValue(parser, &representation, depth);
        if (parser.error.ok)
        {
            const kind = Adapter.decode(representation, parser.allocator, output);
            if (kind != SerdeErrorKind.none)
                parser.fail(kind);
        }
    }
}

private void validateRequired(T)(
    ref JsonParser parser,
    T* output,
    bool* seen,
    size_t base,
)
{
    static foreach (index; 0 .. T.tupleof.length)
    {
        static if (!fieldHas!(T, index, Ignore))
        {
            static if (fieldHas!(T, index, Flatten))
                validateRequired(parser, &output.tupleof[index], seen,
                    base + fieldOrdinal!(T, index));
            else static if (fieldHas!(T, index, Required))
                if (!seen[base + fieldOrdinal!(T, index)])
                    parser.fail(SerdeErrorKind.missingRequiredField,
                        fieldName!(T, index));
        }
    }
}

private void decodePointer(T)(ref JsonParser parser, T** output, size_t depth)
{
    if (matchLiteral(parser, "null"))
    {
        *output = null;
        return;
    }
    T* value = parser.allocator.tryAllocateInit!T();
    if (value is null)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
    *output = value;
    decodeValue(parser, value, depth);
}

private void decodeBool(ref JsonParser parser, bool* output)
{
    if (matchLiteral(parser, "true"))
        *output = true;
    else if (matchLiteral(parser, "false"))
        *output = false;
    else
        parser.fail(SerdeErrorKind.typeMismatch);
}

private bool matchLiteral(ref JsonParser parser, String literal)
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

private void decodeInteger(T)(ref JsonParser parser, T* output)
{
    const start = parser.position;
    bool negative;
    if (parser.consume('-'))
        negative = true;
    if (parser.atEnd || parser.peek < '0' || parser.peek > '9')
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    ulong magnitude;
    if (parser.consume('0'))
    {
        if (!parser.atEnd && parser.peek >= '0' && parser.peek <= '9')
        {
            parser.fail(SerdeErrorKind.invalidNumber);
            return;
        }
    }
    else
    {
        while (!parser.atEnd && parser.peek >= '0' && parser.peek <= '9')
        {
            const digit = cast(ulong)(parser.take() - '0');
            if (magnitude > (ulong.max - digit) / 10)
            {
                parser.fail(SerdeErrorKind.numberOutOfRange);
                return;
            }
            magnitude = magnitude * 10 + digit;
        }
    }
    if (!parser.atEnd && (parser.peek == '.' || parser.peek == 'e' || parser.peek == 'E'))
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
    if (parser.position == start)
        parser.fail(SerdeErrorKind.typeMismatch);
}

private void decodeFloat(T)(ref JsonParser parser, T* output)
{
    const start = parser.position;
    if (!scanNumber(parser))
        return;
    const length = parser.position - start;
    if (length >= 128)
    {
        parser.fail(SerdeErrorKind.numberOutOfRange);
        return;
    }
    char[128] text;
    foreach (index; 0 .. length)
        text[index] = parser.input[start + index];
    text[length] = '\0';
    char* end;
    errno = 0;
    const value = strtod(text.ptr, &end);
    if (end != text.ptr + length)
        parser.fail(SerdeErrorKind.invalidNumber);
    else if (errno == ERANGE || !isfinite(value) ||
        (T.sizeof <= float.sizeof && !isfinite(cast(float) value)))
        parser.fail(SerdeErrorKind.numberOutOfRange);
    else
        *output = cast(T) value;
}

private bool scanNumber(ref JsonParser parser)
{
    if (parser.consume('-') && parser.atEnd)
    {
        parser.fail(SerdeErrorKind.invalidNumber);
        return false;
    }
    if (parser.consume('0'))
    {
        if (!parser.atEnd && parser.peek >= '0' && parser.peek <= '9')
        {
            parser.fail(SerdeErrorKind.invalidNumber);
            return false;
        }
    }
    else
    {
        if (parser.atEnd || parser.peek < '1' || parser.peek > '9')
        {
            parser.fail(SerdeErrorKind.typeMismatch);
            return false;
        }
        while (!parser.atEnd && parser.peek >= '0' && parser.peek <= '9')
            parser.take();
    }
    if (parser.consume('.'))
    {
        if (parser.atEnd || parser.peek < '0' || parser.peek > '9')
        {
            parser.fail(SerdeErrorKind.invalidNumber);
            return false;
        }
        while (!parser.atEnd && parser.peek >= '0' && parser.peek <= '9')
            parser.take();
    }
    if (parser.consume('e') || parser.consume('E'))
    {
        if (!parser.atEnd && (parser.peek == '+' || parser.peek == '-'))
            parser.take();
        if (parser.atEnd || parser.peek < '0' || parser.peek > '9')
        {
            parser.fail(SerdeErrorKind.invalidNumber);
            return false;
        }
        while (!parser.atEnd && parser.peek >= '0' && parser.peek <= '9')
            parser.take();
    }
    return true;
}

private void decodeEnum(T)(ref JsonParser parser, T* output)
{
    String name;
    bool owned;
    decodeStringToken(parser, &name, &owned);
    if (parser.error.ok && !assignEnumName(name,
            parser.options.variantCase, output))
        parser.fail(SerdeErrorKind.typeMismatch);
    if (owned)
        parser.allocator.deallocateArray(name.ptr[0 .. name.length + 1]);
}

private void decodeTaggedEnum(T)(ref JsonParser parser, T* output)
{
    String name;
    bool owned;
    decodeStringToken(parser, &name, &owned);
    if (parser.error.ok)
        decodeTaggedEnumName(parser, name, output);
    if (owned)
        parser.allocator.deallocateArray(name.ptr[0 .. name.length + 1]);
}

private void decodeTaggedEnumName(T)(
    ref JsonParser parser,
    scope String name,
    T* output,
)
{
    if (!assignEnumName(name, parser.options.variantCase, output))
        parser.fail(SerdeErrorKind.unknownVariant);
}

private bool assignEnumName(T)(scope String name, KeyCase casing, T* output)
{
    bool found;
    static foreach (member; __traits(allMembers, T))
        static if (__traits(compiles, __traits(getMember, T, member)))
            if (!found && enumMemberMatches!(T, member)(name, casing))
                {
                *output = __traits(getMember, T, member);
                found = true;
            }
    return found;
}

private void decodeDynamicArray(T)(ref JsonParser parser, T* output, size_t depth)
{
    alias Element = typeof(T.init[0]);
    JsonParser counter = parser;
    size_t count;
    countArray(counter, depth, &count);
    if (!counter.error.ok)
    {
        parser.error = counter.error;
        return;
    }
    Element[] values = parser.allocator.tryAllocateInitArray!Element(count);
    if (count != 0 && values.ptr is null)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
    *output = values;

    parser.consume('[');
    parser.skipWhitespace();
    if (count == 0)
    {
        parser.consume(']');
        return;
    }
    foreach (index; 0 .. count)
    {
        decodeValue(parser, &values[index], depth + 1);
        if (!parser.error.ok)
            return;
        parser.skipWhitespace();
        if (index + 1 == count)
            parser.consume(']');
        else
        {
            parser.consume(',');
            parser.skipWhitespace();
        }
    }
}

private void decodeArray(Container)(
    ref JsonParser parser,
    Container* output,
    size_t depth,
) if (isArray!Container)
{
    alias Element = ArrayElement!Container;
    JsonParser counter = parser;
    size_t count;
    countArray(counter, depth, &count);
    if (!counter.error.ok)
    {
        parser.error = counter.error;
        return;
    }
    Container values = Container.create(parser.allocator);
    if (!values.tryResize(count))
    {
        values.deinit();
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
    foreach (index; 0 .. count)
        initializeOwnedValue(parser.allocator, &values[index]);
    if (!parser.consume('['))
    {
        values.deinit();
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    parser.skipWhitespace();
    foreach (index; 0 .. count)
    {
        decodeValue(parser, &values[index], depth + 1);
        if (!parser.error.ok)
        {
            values.deinit();
            return;
        }
        parser.skipWhitespace();
        if (index + 1 == count)
        {
            if (!parser.consume(']'))
            {
                values.deinit();
                parser.fail(SerdeErrorKind.invalidSyntax);
                return;
            }
        }
        else
        {
            if (!parser.consume(','))
            {
                values.deinit();
                parser.fail(SerdeErrorKind.invalidSyntax);
                return;
            }
            parser.skipWhitespace();
        }
    }
    if (count == 0 && !parser.consume(']'))
    {
        values.deinit();
        parser.fail(SerdeErrorKind.invalidSyntax);
        return;
    }
    deinitOwnedValue(output);
    moveEmplace(values, *output);
}

private void decodeHashMap(K, V, Hasher, Equal)(
    ref JsonParser parser,
    HashMap!(K, V, Hasher, Equal)* output,
    size_t depth,
)
{
    alias Map = HashMap!(K, V, Hasher, Equal);
    static assert(is(Unqualified!K == String));
    if (depth >= parser.options.limits.maxDepth)
    {
        parser.fail(SerdeErrorKind.depthLimit);
        return;
    }
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }

    Map values = Map.create(parser.allocator);
    scope (exit)
        values.deinit();
    parser.skipWhitespace();
    if (parser.consume('}'))
    {
        moveEmplace(values, *output);
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
        const keyStart = parser.position;
        String key;
        bool keyOwned;
        decodeStringToken(parser, &key, &keyOwned, true);
        if (!parser.error.ok)
            return;
        version (XTB_Checked)
            require(keyOwned, "HashMap key was not allocated");
        const rawKey = parser.input[keyStart + 1 .. parser.position - 1];
        parser.skipWhitespace();
        if (!parser.consume(':'))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();

        V value;
        decodeValue(parser, &value, depth + 1);
        if (!parser.error.ok)
            return;
        final switch (values.tryAdd(&key, &value))
        {
            case AddStatus.inserted:
                break;
            case AddStatus.alreadyPresent:
                parser.fail(SerdeErrorKind.duplicateField, rawKey);
                return;
            case AddStatus.outOfMemory:
                parser.fail(SerdeErrorKind.allocationFailure);
                return;
        }

        parser.skipWhitespace();
        if (parser.consume('}'))
            break;
        if (!parser.consume(','))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();
        if (parser.peek == '}')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
    }
    moveEmplace(values, *output);
}

private void decodeStringHashMap(Map)(
    ref JsonParser parser,
    Map* output,
    size_t depth,
) if (isStringHashMap!Map)
{
    alias V = StringHashMapValue!Map;
    if (depth >= parser.options.limits.maxDepth)
    {
        parser.fail(SerdeErrorKind.depthLimit);
        return;
    }
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }

    Map values = Map.create(parser.allocator);
    scope (exit)
        deinitOwnedValue(&values);
    parser.skipWhitespace();
    if (parser.consume('}'))
    {
        moveEmplace(values, *output);
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
        const keyStart = parser.position;
        OwnedString key;
        scope (exit)
            key.deinit();
        decodeOwnedString(parser, &key);
        if (!parser.error.ok)
            return;
        const rawKey = parser.input[keyStart + 1 .. parser.position - 1];
        parser.skipWhitespace();
        if (!parser.consume(':'))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();

        V value;
        initializeOwnedValue(parser.allocator, &value);
        scope (exit)
            deinitOwnedValue(&value);
        decodeValue(parser, &value, depth + 1);
        if (!parser.error.ok)
            return;
        final switch (values.tryAddMove(&key, &value))
        {
            case AddStatus.inserted:
                break;
            case AddStatus.alreadyPresent:
                parser.fail(SerdeErrorKind.duplicateField, rawKey);
                return;
            case AddStatus.outOfMemory:
                parser.fail(SerdeErrorKind.allocationFailure);
                return;
        }

        parser.skipWhitespace();
        if (parser.consume('}'))
            break;
        if (!parser.consume(','))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();
        if (parser.peek == '}')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
    }
    moveEmplace(values, *output);
}

private void decodeFixedArray(T)(ref JsonParser parser, T* output, size_t depth)
{
    if (depth >= parser.options.limits.maxDepth)
    {
        parser.fail(SerdeErrorKind.depthLimit);
        return;
    }
    if (!parser.consume('['))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    parser.skipWhitespace();
    foreach (index; 0 .. output.length)
    {
        if (index != 0)
        {
            if (!parser.consume(','))
            {
                parser.fail(SerdeErrorKind.typeMismatch);
                return;
            }
            parser.skipWhitespace();
        }
        if (parser.peek == ']')
        {
            parser.fail(SerdeErrorKind.typeMismatch);
            return;
        }
        decodeValue(parser, &(*output)[index], depth + 1);
        if (!parser.error.ok)
            return;
        parser.skipWhitespace();
    }
    if (!parser.consume(']'))
        parser.fail(SerdeErrorKind.typeMismatch);
}

private void countArray(ref JsonParser parser, size_t depth, size_t* count)
{
    if (depth >= parser.options.limits.maxDepth)
    {
        parser.fail(SerdeErrorKind.depthLimit);
        return;
    }
    if (!parser.consume('['))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    parser.skipWhitespace();
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
        parser.skipWhitespace();
        if (parser.consume(']'))
            return;
        if (!parser.consume(','))
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        parser.skipWhitespace();
        if (parser.peek == ']')
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
    }
}

private void skipValue(ref JsonParser parser, size_t depth)
{
    parser.skipWhitespace();
    if (parser.atEnd)
    {
        parser.fail(SerdeErrorKind.unexpectedEnd);
        return;
    }
    if (parser.peek == '"')
    {
        String ignored;
        bool owned;
        decodeStringToken(parser, &ignored, &owned);
        if (owned)
            parser.allocator.deallocateArray(ignored.ptr[0 .. ignored.length + 1]);
        return;
    }
    if (parser.peek == '{')
    {
        if (depth >= parser.options.limits.maxDepth)
        {
            parser.fail(SerdeErrorKind.depthLimit);
            return;
        }
        parser.take();
        parser.skipWhitespace();
        if (parser.consume('}'))
            return;
        size_t count;
        for (;;)
        {
            if (count++ == parser.options.limits.maxCollectionLength)
            {
                parser.fail(SerdeErrorKind.collectionLimit);
                return;
            }
            String key;
            bool owned;
            decodeStringToken(parser, &key, &owned);
            if (owned)
                parser.allocator.deallocateArray(key.ptr[0 .. key.length + 1]);
            parser.skipWhitespace();
            if (!parser.consume(':'))
            {
                parser.fail(SerdeErrorKind.invalidSyntax);
                return;
            }
            skipValue(parser, depth + 1);
            if (!parser.error.ok)
                return;
            parser.skipWhitespace();
            if (parser.consume('}'))
                return;
            if (!parser.consume(','))
            {
                parser.fail(SerdeErrorKind.invalidSyntax);
                return;
            }
            parser.skipWhitespace();
        }
    }
    if (parser.peek == '[')
    {
        size_t ignored;
        countArray(parser, depth, &ignored);
        return;
    }
    if (matchLiteral(parser, "true") || matchLiteral(parser, "false") ||
        matchLiteral(parser, "null"))
        return;
    if (!scanNumber(parser))
        return;
}

private void decodeString(ref JsonParser parser, String* output)
{
    bool owned;
    decodeStringToken(parser, output, &owned, true);
}

private void decodeStringBuf(ref JsonParser parser, StringBuf* output)
{
    String value;
    bool owned;
    decodeStringToken(parser, &value, &owned, true);
    if (!parser.error.ok)
        return;
    version (XTB_Checked)
        require(owned, "owned JSON string was not allocated");
    *output = StringBuf.adoptRaw(
        parser.allocator,
        cast(char*) value.ptr,
        value.length,
        value.length + 1,
    );
}

private void decodeOwnedString(ref JsonParser parser, OwnedString* output)
{
    String value;
    bool owned;
    decodeStringToken(parser, &value, &owned, true, false);
    if (!parser.error.ok)
        return;
    version (XTB_Checked)
        require(owned, "owned JSON string was not allocated");
    OwnedStringUnmanaged storage =
        OwnedStringUnmanaged.adoptExact(value);
    OwnedString result = OwnedString.adoptUnmanaged(
        parser.allocator,
        &storage,
    );
    move(result, *output);
}

private void decodeStringToken(
    ref JsonParser parser,
    String* output,
    bool* owned,
    bool forceCopy = false,
    bool terminate = true,
)
{
    *output = null;
    *owned = false;
    if (!parser.consume('"'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    const start = parser.position;
    size_t decodedLength;
    bool escaped;
    while (!parser.atEnd && parser.peek != '"')
    {
        const value = cast(ubyte) parser.peek;
        if (value < 0x20)
        {
            parser.fail(SerdeErrorKind.invalidSyntax);
            return;
        }
        if (value == '\\')
        {
            escaped = true;
            parser.take();
            if (!scanEscape(parser, &decodedLength))
                return;
        }
        else
        {
            DecodedCodePoint decoded;
            const utf8Error = decodeCodePoint(
                parser.input,
                parser.position,
                &decoded,
            );
            if (utf8Error.failed)
            {
                parser.fail(SerdeErrorKind.invalidUtf8);
                return;
            }
            foreach (_; 0 .. decoded.byteLength)
                parser.take();
            decodedLength += decoded.byteLength;
        }
        if (decodedLength > parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
    }
    if (!parser.consume('"'))
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
    const terminatorLength = terminate ? 1 : 0;
    if (terminatorLength > size_t.max - decodedLength)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
    const allocationLength = decodedLength + terminatorLength;
    char* destination;
    if (allocationLength != 0)
        destination = parser.allocator.tryAllocateArray!char(allocationLength).ptr;
    if (allocationLength != 0 && destination is null)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
    size_t source = start;
    size_t target;
    while (source < end)
    {
        if (parser.input[source] != '\\')
        {
            destination[target++] = parser.input[source++];
            continue;
        }
        ++source;
        decodeEscapeBytes(parser.input, &source, destination, &target);
    }
    if (terminate)
        destination[target] = '\0';
    *output = destination[0 .. target];
    *owned = true;
}

private bool scanEscape(ref JsonParser parser, size_t* decodedLength)
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
        case '/':
        case 'b':
        case 'f':
        case 'n':
        case 'r':
        case 't':
            ++*decodedLength;
            return true;
        case 'u':
            uint codePoint;
            if (!scanHex4(parser, &codePoint))
                return false;
            if (codePoint >= 0xD800 && codePoint <= 0xDBFF)
            {
                if (!parser.consume('\\') || !parser.consume('u'))
                {
                    parser.fail(SerdeErrorKind.invalidEscape);
                    return false;
                }
                uint low;
                if (!scanHex4(parser, &low))
                    return false;
                if (low < 0xDC00 || low > 0xDFFF)
                {
                    parser.fail(SerdeErrorKind.invalidEscape);
                    return false;
                }
                codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + low - 0xDC00;
            }
            else if (codePoint >= 0xDC00 && codePoint <= 0xDFFF)
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

private bool scanHex4(ref JsonParser parser, uint* output)
{
    uint value;
    foreach (_; 0 .. 4)
    {
        if (parser.atEnd)
        {
            parser.fail(SerdeErrorKind.unexpectedEnd);
            return false;
        }
        const digit = hexDigit(parser.take());
        if (digit < 0)
        {
            parser.fail(SerdeErrorKind.invalidEscape);
            return false;
        }
        value = value * 16 + cast(uint) digit;
    }
    *output = value;
    return true;
}

private int hexDigit(char value) pure @safe
{
    if (value >= '0' && value <= '9')
        return value - '0';
    if (value >= 'a' && value <= 'f')
        return value - 'a' + 10;
    if (value >= 'A' && value <= 'F')
        return value - 'A' + 10;
    return -1;
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
        case '/':
            destination[(*target)++] = value;
            return;
        case 'b':
            destination[(*target)++] = '\b';
            return;
        case 'f':
            destination[(*target)++] = '\f';
            return;
        case 'n':
            destination[(*target)++] = '\n';
            return;
        case 'r':
            destination[(*target)++] = '\r';
            return;
        case 't':
            destination[(*target)++] = '\t';
            return;
        case 'u':
            uint codePoint = decodeHex4(input, source);
            if (codePoint >= 0xD800 && codePoint <= 0xDBFF)
            {
                *source += 2;
                const low = decodeHex4(input, source);
                codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + low - 0xDC00;
            }
            appendUtf8(destination, target, codePoint);
            return;
        default:
            return;
    }
}

private uint decodeHex4(scope String input, size_t* source) pure @safe
{
    uint value;
    foreach (_; 0 .. 4)
        value = value * 16 + cast(uint) hexDigit(input[(*source)++]);
    return value;
}

private void appendUtf8(char* output, size_t* position, uint value)
{
    const encoded = encodeUtf8(cast(dchar) value);
    const codeUnits = encoded.codeUnits;
    foreach (index; 0 .. encoded.byteLength)
        output[(*position)++] = codeUnits[index];
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
