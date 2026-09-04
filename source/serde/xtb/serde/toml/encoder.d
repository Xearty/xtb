module xtb.serde.toml.encoder;

nothrow @nogc:

import core.stdc.errno : ERANGE, errno;
import core.stdc.math : isfinite, isnan, signbit;
import core.stdc.stdio : snprintf;
import core.stdc.stdlib : strtod;
import xtb.lifetime : has_d_destructor, move_emplace;
import xtb.containers.array;
import xtb.containers.hash_map;
import xtb.memory : Allocator, deallocateArray, tryAllocateArray, tryAllocateInit, tryAllocateInitArray;
import xtb.option : Option;

version (XTB_Checked) import xtb.panic : require;
import xtb.fmt.writer : Writer;
import xtb.string;
import xtb.containers.string_hash_map;
import xtb.types : String;
import xtb.utf8 : DecodedCodePoint, decode_code_point, encode_utf8,
    is_valid_utf8;
import xtb.serde.attributes : SerdeFlatten, SerdeIgnore, KeyCase, SerdeOmitDefault, SerdeRename,
    SerdeRequired, TagLayout;
import xtb.serde.internal.casing : writeCased;
import xtb.serde.error : SerdeError, SerdeErrorKind, SerdeLimits;
import xtb.serde.ownership : Deserialized, abandonDeserialized,
    deserializationAllocator, isDeserialized, prepareDeserialized;
import xtb.serde.internal.traits : ArrayElement, FieldSymbol, FieldType, Unqualified, fieldHas,
    applySchemaDefaults, enumCase, enumMemberMatches, enumMemberName,
    discriminantIndex, DiscriminantType, fieldMatches, fieldName,
    fieldShouldOmit, fieldAdapterCount, fieldDefaultValueCount, FieldAdapter,
    HashMapKey, HashMapValue, isArray, isDefaultValueAttribute, isDynamicArray,
    isFixedArray, isHashMap, isOwnedHashMap, isOption, isOwnedString, isSerdeStruct, isString,
    isStringBuf, isStringHashMap, isTaggedUnion, deinitOwnedValue, initializeOwnedValue,
    OptionElement, payloadIndex, PayloadType, StringHashMapValue,
    schemaCase, serializedFieldCount, taggedUnionLayout, unionCaseIsActive,
    UnionMemberType, validateBorrowedSchema, validateBorrowedValue,
    validateOwnedSchema, validateOwnedValue, validateSchema, validateValueSchema;

import xtb.serde.toml.types : TomlWriteOptions, success, simpleError;

SerdeError writeToml(T)(
    ref Writer writer,
    scope const ref T value,
    TomlWriteOptions options = TomlWriteOptions.init,
) if (isSerdeStruct!T || isHashMap!T || isOwnedHashMap!T || isStringHashMap!T)
{
    static if (isHashMap!T || isOwnedHashMap!T || isStringHashMap!T)
        validateValueSchema!T();
    else
        validateSchema!T();
    TomlEncoder encoder;
    encoder.writer = &writer;
    encoder.options = options;
    encodeRoot(encoder, value);
    if (!encoder.error.ok)
        return encoder.error;
    return writer.ok ? success() : simpleError(SerdeErrorKind.outputFailure);
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
    else static if (has_d_destructor!(Unqualified!F) ||
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

private void encodeRoot(T)(ref TomlEncoder encoder, scope const ref T value)
{
    static if (isHashMap!T || isOwnedHashMap!T || isStringHashMap!T)
        encodeHashMapRoot(encoder, value);
    else static if (isTaggedUnion!T)
        encodeTaggedRoot(encoder, value);
    else
    {
        bool wrote;
        static foreach (index; 0 .. Unqualified!T.tupleof.length)
        {
            static if (!fieldHas!(T, index, SerdeIgnore))
            {
                static if (fieldHas!(T, index, SerdeFlatten))
                    encodeFlattened(encoder, value.tupleof[index], &wrote, 0);
                else
                    encodeRootField!(T, index)(encoder, value.tupleof[index], &wrote);
            }
        }
    }
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

private void encodeHashMapRoot(T)(
    ref TomlEncoder encoder,
    scope const ref T value,
)
{
    auto items = value.pointerItems();
    bool wrote;
    while (!items.empty)
    {
        if (wrote)
            encoder.writer.put('\n');
        encodeKeyText(encoder, serdeMapKey(*items.front.key), KeyCase.preserve);
        encoder.writer.put(" = ");
        encodeValue(encoder, *items.front.value, 0);
        wrote = true;
        items.popFront();
    }
}

private void encodeTaggedRoot(T)(
    ref TomlEncoder encoder,
    scope const ref T value,
)
{
    alias U = Unqualified!T;
    static if (taggedUnionLayout!U == TagLayout.external)
    {
        encodeEnum(encoder, value.tupleof[discriminantIndex!U]);
        encoder.writer.put(" = ");
        encodeActiveUnionCase(encoder, value, 0);
    }
    else
    {
        encodeKey!(U, discriminantIndex!U)(encoder);
        encoder.writer.put(" = ");
        encodeEnum(encoder, value.tupleof[discriminantIndex!U]);
        encoder.writer.put('\n');
        static if (taggedUnionLayout!U == TagLayout.adjacent)
        {
            encodeKey!(U, payloadIndex!U)(encoder);
            encoder.writer.put(" = ");
            encodeActiveUnionCase(encoder, value, 0);
        }
        else
        {
            bool wrote;
            encodeActiveUnionRootFields(encoder, value, &wrote);
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
        static if (!fieldHas!(T, index, SerdeIgnore))
        {
            static if (fieldHas!(T, index, SerdeFlatten))
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
    if (fieldShouldOmit!(T, index)(value))
        return;
    static if (fieldHas!(T, index, SerdeOmitDefault))
        if (fieldIsDefault!(T, index)(value))
            return;
    if (absentValue(value))
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
            encoder.writer.put('\n');
        encodeKey!(T, index)(encoder);
        encoder.writer.put(" = ");
        encodeValue(encoder, representation, depth);
    }
    else
    {
        if (*wrote)
            encoder.writer.put('\n');
        encodeKey!(T, index)(encoder);
        encoder.writer.put(" = ");
        encodeValue(encoder, value, depth);
    }
    *wrote = true;
}

private bool absentValue(T)(scope const ref T value) pure @safe
{
    static if (isOption!T)
        return value.empty;
    else static if (is(Unqualified!T == Pointee*, Pointee))
        return value is null;
    else
        return false;
}

private void encodeKey(T, size_t index)(ref TomlEncoder encoder)
{
    static if (fieldHas!(T, index, SerdeRename))
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
            encoder.fail(SerdeErrorKind.unsupportedValue);
        else
            encodeValue(encoder, value.value, depth);
    }
    else static if (is(U == Pointee*, Pointee))
    {
        if (value is null)
            encoder.fail(SerdeErrorKind.unsupportedValue);
        else
            encodeValue(encoder, *value, depth);
    }
    else static if (isArray!U)
        encodeArray(encoder, value.slice, depth);
    else static if (isDynamicArray!U || isFixedArray!U)
        encodeArray(encoder, value, depth);
    else static if (isHashMap!U || isOwnedHashMap!U || isStringHashMap!U)
        encodeHashMapInline(encoder, value, depth);
    else static if (isTaggedUnion!U)
        encodeTaggedInline(encoder, value, depth);
    else static if (isSerdeStruct!U)
        encodeInlineTable(encoder, value, depth);
}

private void encodeHashMapInline(T)(
    ref TomlEncoder encoder,
    scope const ref T value,
    size_t depth,
)
{
    encoder.writer.put("{ ");
    auto items = value.pointerItems();
    bool wrote;
    while (!items.empty)
    {
        if (wrote)
            encoder.writer.put(", ");
        encodeKeyText(encoder, serdeMapKey(*items.front.key), KeyCase.preserve);
        encoder.writer.put(" = ");
        encodeValue(encoder, *items.front.value, depth + 1);
        wrote = true;
        items.popFront();
    }
    encoder.writer.put(wrote ? " }" : "}");
}

private void encodeTaggedInline(T)(
    ref TomlEncoder encoder,
    scope const ref T value,
    size_t depth,
)
{
    alias U = Unqualified!T;
    encoder.writer.put("{ ");
    static if (taggedUnionLayout!U == TagLayout.external)
    {
        encodeEnum(encoder, value.tupleof[discriminantIndex!U]);
        encoder.writer.put(" = ");
        encodeActiveUnionCase(encoder, value, depth + 1);
    }
    else
    {
        encodeKey!(U, discriminantIndex!U)(encoder);
        encoder.writer.put(" = ");
        encodeEnum(encoder, value.tupleof[discriminantIndex!U]);
        static if (taggedUnionLayout!U == TagLayout.adjacent)
        {
            encoder.writer.put(", ");
            encodeKey!(U, payloadIndex!U)(encoder);
            encoder.writer.put(" = ");
            encodeActiveUnionCase(encoder, value, depth + 1);
        }
        else
        {
            bool wrote = true;
            encodeActiveUnionInlineFields(encoder, value, depth, &wrote);
        }
    }
    encoder.writer.put(" }");
}

private void encodeActiveUnionCase(T)(
    ref TomlEncoder encoder,
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

private void encodeActiveUnionInlineFields(T)(
    ref TomlEncoder encoder,
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
            encodeInlineFields(encoder,
                value.tupleof[payloadIndex!U].tupleof[index], depth, wrote);
            found = true;
        }
    }
    if (!found)
        encoder.fail(SerdeErrorKind.unknownVariant);
}

private void encodeActiveUnionRootFields(T)(
    ref TomlEncoder encoder,
    scope const ref T value,
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
            encodeFlattened(encoder,
                value.tupleof[payloadIndex!U].tupleof[index], wrote, 0);
            found = true;
        }
    }
    if (!found)
        encoder.fail(SerdeErrorKind.unknownVariant);
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
        static if (!fieldHas!(T, index, SerdeIgnore))
        {
            static if (fieldHas!(T, index, SerdeFlatten))
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
    if (fieldShouldOmit!(T, index)(value))
        return;
    static if (fieldHas!(T, index, SerdeOmitDefault))
        if (fieldIsDefault!(T, index)(value))
            return;
    if (absentValue(value))
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
            encoder.writer.put(", ");
        encodeKey!(T, index)(encoder);
        encoder.writer.put(" = ");
        encodeValue(encoder, representation, depth + 1);
    }
    else
    {
        if (*wrote)
            encoder.writer.put(", ");
        encodeKey!(T, index)(encoder);
        encoder.writer.put(" = ");
        encodeValue(encoder, value, depth + 1);
    }
    *wrote = true;
}

private void encodeArray(Element)(
    ref TomlEncoder encoder,
    scope const(Element)[] value,
    size_t depth,
)
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
    if (!is_valid_utf8(value))
    {
        encoder.fail(SerdeErrorKind.invalidUtf8);
        return;
    }
    encoder.writer.put('"');
    size_t offset;
    while (offset < value.length)
    {
        DecodedCodePoint decoded;
        const utf8Error = decode_code_point(value, offset, &decoded);
        if (utf8Error.failed)
        {
            encoder.fail(SerdeErrorKind.invalidUtf8);
            return;
        }
        offset += decoded.byte_length;
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
                    encoder.writer.value(character);
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
                enum renamed = enumMemberName!(T, name) != name;
                if (renamed)
                    encodeString(encoder, enumMemberName!(T, name));
                else
                    {
                    const casing = encoder.options.variantCase == KeyCase.schema
                        ? enumCase!T
                        : encoder.options.variantCase;
                    encoder.writer.put('"');
                    (*encoder.writer).writeCased(enumMemberName!(T, name), casing);
                    encoder.writer.put('"');
                }
                found = true;
            }
    if (!found)
        encoder.fail(SerdeErrorKind.unsupportedValue);
}
