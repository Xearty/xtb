module xtb.serde.json.encoder;

nothrow @nogc:

import core.stdc.errno : ERANGE, errno;
import core.stdc.math : isfinite;
import core.stdc.stdio : snprintf;
import core.stdc.stdlib : strtod;
import xtb.core.lifetime : hasDDestructor, moveEmplace;
import xtb.core.containers.array;
import xtb.core.containers.hash_map;
import xtb.core.memory : Allocator, deallocateArray, tryAllocateArray, tryAllocateInit, tryAllocateInitArray;
import xtb.core.option : Option;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.fmt.writer : Writer;
import xtb.core.string;
import xtb.core.containers.string_hash_map;
import xtb.core.types : String;
import xtb.core.utf8 : DecodedCodePoint, decodeCodePoint, encodeUtf8,
    isValidUtf8;
import xtb.serde.attributes : SerdeAliasName, SerdeFlatten, SerdeIgnore, KeyCase, SerdeOmitDefault,
    SerdeRename, SerdeRequired, TagLayout;
import xtb.serde.internal.casing : writeCased;
import xtb.serde.error : SerdeError, SerdeErrorKind, SerdeLimits;
import xtb.serde.ownership : Deserialized, abandonDeserialized,
    deserializationAllocator, isDeserialized, prepareDeserialized;
import xtb.serde.internal.traits : ArrayElement, FieldSymbol, FieldType, Unqualified,
    applySchemaDefaults, enumCase, enumMemberMatches, enumMemberName, fieldHas,
    fieldMatches, fieldName, fieldOrdinal, fieldShouldOmit, discriminantIndex,
    DiscriminantType, fieldAdapterCount, fieldDefaultValueCount, FieldAdapter,
    HashMapKey, HashMapValue, isArray, isDefaultValueAttribute, isDynamicArray,
    isFixedArray, isHashMap, isOwnedHashMap, isOption, isOwnedSerdeValue, isOwnedString,
    isSerdeStruct, isString, isStringBuf, isStringHashMap, isTaggedUnion,
    deinitOwnedValue, initializeOwnedValue, OptionElement, StringHashMapValue,
    payloadIndex, PayloadType, schemaCase,
    serializedFieldCount, taggedUnionLayout, unionCaseIsActive, UnionMemberType,
    validateBorrowedValue, validateOwnedValue, validateValueSchema;

import xtb.serde.json.types : JsonWriteOptions, success, simpleError;

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
    if (!encoder.error.ok)
        return encoder.error;
    return writer.ok ? success() : simpleError(SerdeErrorKind.outputFailure);
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
    else static if (isHashMap!U || isOwnedHashMap!U || isStringHashMap!U)
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
            static if (!fieldHas!(U, index, SerdeIgnore))
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
    else static if (hasDDestructor!(Unqualified!F) ||
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
    else static if (isHashMap!U || isOwnedHashMap!U || isStringHashMap!U)
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
        static if (!fieldHas!(U, index, SerdeIgnore))
        {
            static if (fieldHas!(U, index, SerdeFlatten))
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
    static if (fieldHas!(T, index, SerdeOmitDefault))
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
    static if (fieldHas!(T, index, SerdeRename))
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

private String serdeMapKey(K)(scope const ref K key)
{
    alias U = Unqualified!K;
    static if (isString!U)
        return cast(String) key;
    else static if (isOwnedString!U)
        return key.view;
    else
        static assert(false, "unsupported serde map key type: " ~ U.stringof);
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
        encodeString(encoder, serdeMapKey(*items.front.key));
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
