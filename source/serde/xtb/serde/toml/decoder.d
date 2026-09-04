module xtb.serde.toml.decoder;

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

import xtb.serde.toml.types : TomlReadOptions, success, simpleError;

SerdeError readToml(T)(
    scope String input,
    Allocator* allocator,
    Deserialized!T* output,
    TomlReadOptions options = TomlReadOptions.init,
) if (isSerdeStruct!T || isHashMap!T)
{
    static if (isHashMap!T)
        validateBorrowedValue!T();
    else
        validateBorrowedSchema!T();
    version (XTB_Checked)
    {
        require(options.limits.maxDepth != 0, "TOML max depth must be nonzero");
        require(options.limits.maxCollectionLength != 0,
            "TOML collection limit must be nonzero");
    }

    T* value;
    if (!prepareDeserialized(allocator, output, &value))
        return simpleError(SerdeErrorKind.allocationFailure);
    applySchemaDefaults(value);

    TomlParser parser;
    parser.input = input;
    parser.allocator = deserializationAllocator(output);
    parser.options = options;
    parser.line = 1;
    parser.column = 1;
    static if (isHashMap!T)
        parseHashMapDocument(parser, value);
    else static if (isTaggedUnion!T)
        decodeTaggedDocument(parser, value);
    else
    {
        bool[tomlNodeCount!T] seen;
        parseDocument(parser, value, seen.ptr);
        if (parser.error.ok)
            validateRequired(parser, value, seen.ptr, 0);
    }
    parser.clearTablePath();
    if (!parser.error.ok)
    {
        SerdeError error = parser.error;
        abandonDeserialized(output);
        return error;
    }
    return success();
}

SerdeError readToml(T)(
    scope String input,
    Allocator* allocator,
    T* output,
    TomlReadOptions options = TomlReadOptions.init,
) if ((isSerdeStruct!T || isOwnedHashMap!T || isStringHashMap!T) && !isDeserialized!T)
{
    static if (isOwnedHashMap!T || isStringHashMap!T)
        validateOwnedValue!T();
    else
        validateOwnedSchema!T();
    version (XTB_Checked)
    {
        require(allocator !is null && *allocator !is null,
            "serde requires a valid allocator");
        require(output !is null, "owned TOML output pointer is null");
        require(options.limits.maxDepth != 0, "TOML max depth must be nonzero");
        require(options.limits.maxCollectionLength != 0,
            "TOML collection limit must be nonzero");
    }

    T decoded;
    initializeOwnedValue(allocator, &decoded);
    static if (isSerdeStruct!T)
        applySchemaDefaults(&decoded);
    TomlParser parser;
    parser.input = input;
    parser.allocator = allocator;
    parser.options = options;
    parser.line = 1;
    parser.column = 1;
    static if (isOwnedHashMap!T)
        parseOwnedHashMapDocument(parser, &decoded);
    else static if (isStringHashMap!T)
        parseStringHashMapDocument!T(parser, &decoded);
    else
    {
        bool[tomlNodeCount!T] seen;
        parseDocument(parser, &decoded, seen.ptr);
        if (parser.error.ok)
            validateRequired(parser, &decoded, seen.ptr, 0);
    }
    parser.clearTablePath();
    if (!parser.error.ok)
    {
        SerdeError error = parser.error;
        deinitOwnedValue(&decoded);
        return error;
    }
    deinitOwnedValue(output);
    move_emplace(decoded, *output);
    return success();
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
                allocator.deallocateArray(
                    (cast(char*) tablePath[index].value.ptr)[
                    0 .. tablePath[index].value.length + 1
            ],
                );
            tablePath[index] = ParsedKey.init;
        }
        tablePathLength = 0;
    }
}

private size_t nodeWidth(T, size_t index)() pure @safe
{
    alias F = FieldType!(T, index);
    static if (fieldHas!(T, index, SerdeIgnore))
        return 0;
    else static if (fieldHas!(T, index, SerdeFlatten))
        return tomlNodeCount!F;
    else static if (isTaggedUnion!F)
        return 1;
    else static if (isOption!F && isTaggedUnion!(OptionElement!F))
        return 1;
    else static if (is(Unqualified!F == TaggedPointee*, TaggedPointee) &&
        isTaggedUnion!TaggedPointee)
        return 1;
    else static if (isSerdeStruct!F)
        return 1 + tomlNodeCount!F;
    else static if (isOption!F && isSerdeStruct!(OptionElement!F))
        return 1 + tomlNodeCount!(OptionElement!F);
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

private void decodeTaggedDocument(T)(ref TomlParser parser, T* output)
{
    alias U = Unqualified!T;
    static if (taggedUnionLayout!U == TagLayout.external)
        decodeExternalTaggedDocument(parser, output);
    else
    {
        DiscriminantType!U tag;
        TomlParser scanner = parser;
        scanDocumentDiscriminant!U(scanner, &tag);
        if (!scanner.error.ok)
        {
            parser.error = scanner.error;
            return;
        }
        output.tupleof[discriminantIndex!U] = tag;
        alias P = PayloadType!U;
        bool found;
        static foreach (index; 0 .. P.tupleof.length)
        {
            if (!found && unionCaseIsActive!(P, index)(tag))
            {
                static if (taggedUnionLayout!U == TagLayout.adjacent)
                    decodeAdjacentTaggedDocumentCase!(U, index)(parser, output);
                else
                    decodeInternalTaggedDocumentCase!(U, index)(parser, output);
                found = true;
            }
        }
        if (!found)
            parser.fail(SerdeErrorKind.unknownVariant);
    }
}

private void decodeExternalTaggedDocument(T)(
    ref TomlParser parser,
    T* output,
)
{
    alias U = Unqualified!T;
    parser.spaceAndComments();
    if (parser.atEnd || parser.peek == '[')
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    ParsedKey[64] key;
    size_t keyLength;
    parseKeyPath(parser, key[], &keyLength);
    if (parser.error.ok && keyLength != 1)
        parser.fail(SerdeErrorKind.invalidSyntax);
    if (parser.error.ok)
        decodeTaggedEnumName(parser, key[0].value,
            &output.tupleof[discriminantIndex!U]);
    parser.horizontalSpace();
    if (parser.error.ok && !parser.consume('='))
        parser.fail(SerdeErrorKind.invalidSyntax);
    parser.horizontalSpace();
    if (parser.error.ok)
        decodeActiveTaggedCase(parser, output, 0);
    preserveDiagnostic(parser, key[], keyLength);
    clearKeys(parser, key[], keyLength);
    if (parser.error.ok)
        finishDocumentEntry(parser);
    if (parser.error.ok && !parser.atEnd)
        parser.fail(SerdeErrorKind.invalidSyntax);
}

private void scanDocumentDiscriminant(T)(
    ref TomlParser parser,
    DiscriminantType!T* tag,
)
{
    parser.spaceAndComments();
    bool seen;
    size_t assignments;
    while (!parser.atEnd && parser.error.ok)
    {
        if (parser.peek == '[')
        {
            parser.fail(SerdeErrorKind.unsupportedValue);
            break;
        }
        if (assignments++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            break;
        }
        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        if (parser.error.ok && keyLength == 1 &&
            fieldMatches!(T, discriminantIndex!T)(key[0].value,
                parser.options.keyCase))
        {
            if (seen)
                parser.fail(SerdeErrorKind.duplicateField, key[0].value);
            else
            {
                seen = true;
                decodeTaggedEnum(parser, tag);
            }
        }
        else if (parser.error.ok)
            skipValue(parser, 0);
        preserveDiagnostic(parser, key[], keyLength);
        clearKeys(parser, key[], keyLength);
        if (parser.error.ok)
            finishDocumentEntry(parser);
    }
    if (parser.error.ok && !seen)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, discriminantIndex!T));
}

private void decodeAdjacentTaggedDocumentCase(T, size_t caseIndex)(
    ref TomlParser parser,
    T* output,
)
{
    parser.spaceAndComments();
    bool seenTag;
    bool seenPayload;
    size_t assignments;
    while (!parser.atEnd && parser.error.ok)
    {
        if (parser.peek == '[')
        {
            parser.fail(SerdeErrorKind.unsupportedValue);
            break;
        }
        if (assignments++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            break;
        }
        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        if (parser.error.ok && keyLength == 1 &&
            fieldMatches!(T, discriminantIndex!T)(key[0].value,
                parser.options.keyCase))
        {
            if (seenTag)
                parser.fail(SerdeErrorKind.duplicateField, key[0].value);
            else
            {
                DiscriminantType!T tag;
                decodeTaggedEnum(parser, &tag);
                if (parser.error.ok && tag != output.tupleof[discriminantIndex!T])
                    parser.fail(SerdeErrorKind.unknownVariant);
                seenTag = true;
            }
        }
        else if (parser.error.ok && keyLength == 1 &&
            fieldMatches!(T, payloadIndex!T)(key[0].value,
                parser.options.keyCase))
        {
            if (seenPayload)
                parser.fail(SerdeErrorKind.duplicateField, key[0].value);
            else
            {
                decodeValue(parser,
                    &output.tupleof[payloadIndex!T].tupleof[caseIndex], 0);
                seenPayload = true;
            }
        }
        else if (parser.error.ok)
        {
            if (parser.options.limits.ignoreUnknownFields)
                skipValue(parser, 0);
            else
                parser.fail(SerdeErrorKind.unknownField,
                    key[keyLength - 1].value);
        }
        preserveDiagnostic(parser, key[], keyLength);
        clearKeys(parser, key[], keyLength);
        if (parser.error.ok)
            finishDocumentEntry(parser);
    }
    if (parser.error.ok && !seenTag)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, discriminantIndex!T));
    else if (parser.error.ok && !seenPayload)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, payloadIndex!T));
}

private void decodeInternalTaggedDocumentCase(T, size_t caseIndex)(
    ref TomlParser parser,
    T* output,
)
{
    alias P = PayloadType!T;
    alias C = UnionMemberType!(P, caseIndex);
    applySchemaDefaults(
        &output.tupleof[payloadIndex!T].tupleof[caseIndex]);
    parser.spaceAndComments();
    bool seenTag;
    bool[tomlNodeCount!C] seen;
    size_t assignments;
    while (!parser.atEnd && parser.error.ok)
    {
        if (parser.peek == '[')
        {
            parser.fail(SerdeErrorKind.unsupportedValue);
            break;
        }
        if (assignments++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            break;
        }
        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        if (parser.error.ok && keyLength == 1 &&
            fieldMatches!(T, discriminantIndex!T)(key[0].value,
                parser.options.keyCase))
        {
            if (seenTag)
                parser.fail(SerdeErrorKind.duplicateField, key[0].value);
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
            decodePath(parser,
                &output.tupleof[payloadIndex!T].tupleof[caseIndex],
                null, 0, key[], keyLength, 0, 0, seen.ptr, 0, &matched);
            if (!matched && parser.error.ok)
            {
                if (parser.options.limits.ignoreUnknownFields)
                    skipValue(parser, 0);
                else
                    parser.fail(SerdeErrorKind.unknownField,
                        key[keyLength - 1].value);
            }
        }
        preserveDiagnostic(parser, key[], keyLength);
        clearKeys(parser, key[], keyLength);
        if (parser.error.ok)
            finishDocumentEntry(parser);
    }
    if (parser.error.ok && !seenTag)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, discriminantIndex!T));
    else if (parser.error.ok)
        validateRequired(parser,
            &output.tupleof[payloadIndex!T].tupleof[caseIndex], seen.ptr, 0);
}

private void finishDocumentEntry(ref TomlParser parser)
{
    parser.horizontalSpace();
    if (parser.peek == '#')
        while (!parser.atEnd && parser.peek != '\n')
            parser.take();
    if (!parser.atEnd && parser.peek != '\n' && parser.peek != '\r')
    {
        parser.fail(SerdeErrorKind.invalidSyntax);
        return;
    }
    parser.spaceAndComments();
}

private void parseHashMapDocument(K, V, Hasher, Equal)(
    ref TomlParser parser,
    HashMap!(K, V, Hasher, Equal)* output,
)
{
    alias Map = HashMap!(K, V, Hasher, Equal);
    static assert(is(Unqualified!K == String));
    Map values = Map.create(parser.allocator);
    scope (exit)
        values.deinit();
    parser.spaceAndComments();
    size_t assignments;
    while (!parser.atEnd && parser.error.ok)
    {
        if (parser.peek == '[')
        {
            parser.fail(SerdeErrorKind.unsupportedValue);
            break;
        }
        if (assignments++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            break;
        }
        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        if (parser.error.ok && keyLength != 1)
            parser.fail(SerdeErrorKind.unsupportedValue);
        if (parser.error.ok && !ownParsedKey(parser, &key[0]))
            break;
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        V value;
        if (parser.error.ok)
            decodeValue(parser, &value, 0);
        if (parser.error.ok)
        {
            final switch (values.tryAdd(&key[0].value, &value))
            {
                case AddStatus.inserted:
                    key[0].owned = false;
                    break;
                case AddStatus.alreadyPresent:
                    parser.fail(SerdeErrorKind.duplicateField, key[0].value);
                    break;
                case AddStatus.outOfMemory:
                    parser.fail(SerdeErrorKind.allocationFailure);
                    break;
            }
        }
        preserveDiagnostic(parser, key[], keyLength);
        clearKeys(parser, key[], keyLength);
        if (parser.error.ok)
            finishDocumentEntry(parser);
    }
    if (parser.error.ok)
        move_emplace(values, *output);
}

private void parseOwnedHashMapDocument(K, V, Hasher, Equal)(
    ref TomlParser parser,
    OwnedHashMap!(K, V, Hasher, Equal)* output,
)
{
    alias Map = OwnedHashMap!(K, V, Hasher, Equal);
    static assert(is(Unqualified!K == OwnedString));
    Map values = Map.create(parser.allocator);
    scope (exit)
        values.deinit();
    parser.spaceAndComments();
    size_t assignments;
    while (!parser.atEnd && parser.error.ok)
    {
        if (parser.peek == '[')
        {
            parser.fail(SerdeErrorKind.unsupportedValue);
            break;
        }
        if (assignments++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            break;
        }

        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        if (parser.error.ok && keyLength != 1)
            parser.fail(SerdeErrorKind.unsupportedValue);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();

        OwnedString ownedKey;
        scope (exit)
            ownedKey.deinit();
        if (parser.error.ok &&
            !OwnedString.tryFromString(
                parser.allocator,
                key[0].value,
                &ownedKey,
            ))
            parser.fail(SerdeErrorKind.allocationFailure);

        V value;
        initializeOwnedValue(parser.allocator, &value);
        scope (exit)
            deinitOwnedValue(&value);
        if (parser.error.ok)
            decodeValue(parser, &value, 0);
        if (parser.error.ok)
        {
            final switch (values.tryAdd(&ownedKey, &value))
            {
                case AddStatus.inserted:
                    break;
                case AddStatus.alreadyPresent:
                    parser.fail(SerdeErrorKind.duplicateField, key[0].value);
                    break;
                case AddStatus.outOfMemory:
                    parser.fail(SerdeErrorKind.allocationFailure);
                    break;
            }
        }
        preserveDiagnostic(parser, key[], keyLength);
        clearKeys(parser, key[], keyLength);
        if (parser.error.ok)
            finishDocumentEntry(parser);
    }
    if (parser.error.ok)
        move_emplace(values, *output);
}

private void parseStringHashMapDocument(Map)(
    ref TomlParser parser,
    Map* output,
) if (isStringHashMap!Map)
{
    alias V = StringHashMapValue!Map;
    Map values = Map.create(parser.allocator);
    scope (exit)
        deinitOwnedValue(&values);
    parser.spaceAndComments();
    size_t assignments;
    while (!parser.atEnd && parser.error.ok)
    {
        if (parser.peek == '[')
        {
            parser.fail(SerdeErrorKind.unsupportedValue);
            break;
        }
        if (assignments++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            break;
        }

        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        if (parser.error.ok && keyLength != 1)
            parser.fail(SerdeErrorKind.unsupportedValue);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();

        OwnedString ownedKey;
        scope (exit)
            ownedKey.deinit();
        if (parser.error.ok &&
            !OwnedString.tryFromString(
                parser.allocator,
                key[0].value,
                &ownedKey,
            ))
            parser.fail(SerdeErrorKind.allocationFailure);

        V value;
        initializeOwnedValue(parser.allocator, &value);
        scope (exit)
            deinitOwnedValue(&value);
        if (parser.error.ok)
            decodeValue(parser, &value, 0);
        if (parser.error.ok)
        {
            final switch (values.tryAddMove(&ownedKey, &value))
            {
                case AddStatus.inserted:
                    break;
                case AddStatus.alreadyPresent:
                    parser.fail(SerdeErrorKind.duplicateField, key[0].value);
                    break;
                case AddStatus.outOfMemory:
                    parser.fail(SerdeErrorKind.allocationFailure);
                    break;
            }
        }
        preserveDiagnostic(parser, key[], keyLength);
        clearKeys(parser, key[], keyLength);
        if (parser.error.ok)
            finishDocumentEntry(parser);
    }
    if (parser.error.ok)
        move_emplace(values, *output);
}

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
            parser.allocator.deallocateArray(
                keys[index].value.ptr[0 .. keys[index].value.length + 1],
            );
        keys[index] = ParsedKey.init;
    }
}

private bool ownParsedKey(ref TomlParser parser, ParsedKey* key)
{
    if (key.owned)
        return true;
    char* copy = parser.allocator.tryAllocateArray!char(key.value.length + 1).ptr;
    if (copy is null)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return false;
    }
    foreach (index, character; key.value)
        copy[index] = character;
    copy[key.value.length] = '\0';
    key.value = copy[0 .. key.value.length];
    key.owned = true;
    return true;
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
        static if (!fieldHas!(T, index, SerdeIgnore))
        {
            static if (fieldHas!(T, index, SerdeFlatten))
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
        static if (fieldAdapterCount!(T, index) != 0)
            decodeAdaptedValue!(T, index)(parser, &output.tupleof[index], 0);
        else static if (isTaggedUnion!F)
            decodeTaggedInline(parser, &output.tupleof[index], 0);
        else static if (isOption!F && isTaggedUnion!(OptionElement!F))
        {
            applySchemaDefaults(&output.tupleof[index].storage());
            decodeTaggedInline(parser, &output.tupleof[index].storage(), 0);
            if (parser.error.ok)
                output.tupleof[index].markPresent();
        }
        else static if (is(Unqualified!F == TaggedPointee*, TaggedPointee) &&
            isTaggedUnion!TaggedPointee)
        {
            output.tupleof[index] = parser.allocator.tryAllocateInit!TaggedPointee();
            if (output.tupleof[index] is null)
            {
                parser.fail(SerdeErrorKind.allocationFailure);
                return;
            }
            applySchemaDefaults(output.tupleof[index]);
            decodeTaggedInline(parser, output.tupleof[index], 0);
        }
        else static if (isSerdeStruct!F)
            decodeInlineTable(parser, &output.tupleof[index], 0, seen + ordinal + 1);
        else static if (isOption!F && isSerdeStruct!(OptionElement!F))
        {
            applySchemaDefaults(&output.tupleof[index].storage());
            decodeInlineTable(parser, &output.tupleof[index].storage(), 0,
                seen + ordinal + 1);
            if (parser.error.ok)
                output.tupleof[index].markPresent();
        }
        else static if (is(Unqualified!F == Pointee*, Pointee) &&
            isSerdeStruct!Pointee)
        {
            output.tupleof[index] = parser.allocator.tryAllocateInit!Pointee();
            if (output.tupleof[index] is null)
            {
                parser.fail(SerdeErrorKind.allocationFailure);
                return;
            }
            applySchemaDefaults(output.tupleof[index]);
            decodeInlineTable(parser, output.tupleof[index], 0, seen + ordinal + 1);
        }
        else
            decodeValue(parser, &output.tupleof[index], 0);
    }
    else static if (isTaggedUnion!F ||
        (isOption!F && isTaggedUnion!(OptionElement!F)) ||
        (is(Unqualified!F == TaggedPointee*, TaggedPointee) &&
            isTaggedUnion!TaggedPointee))
        return;
    else static if (isSerdeStruct!F)
    {
        seen[ordinal] = true;
        decodePath(parser, &output.tupleof[index], prefix, prefixLength,
            suffix, suffixLength, nextPrefix, nextSuffix, seen, ordinal + 1, matched);
    }
    else static if (isOption!F && isSerdeStruct!(OptionElement!F))
    {
        if (output.tupleof[index].isNone)
        {
            applySchemaDefaults(&output.tupleof[index].storage());
            output.tupleof[index].markPresent();
        }
        seen[ordinal] = true;
        decodePath(parser, &output.tupleof[index].storage(), prefix, prefixLength,
            suffix, suffixLength, nextPrefix, nextSuffix, seen, ordinal + 1,
            matched);
    }
    else static if (is(Unqualified!F == Pointee*, Pointee) && isSerdeStruct!Pointee)
    {
        if (output.tupleof[index] is null)
        {
            output.tupleof[index] = parser.allocator.tryAllocateInit!Pointee();
            if (output.tupleof[index] is null)
            {
                parser.fail(SerdeErrorKind.allocationFailure);
                return;
            }
            applySchemaDefaults(output.tupleof[index]);
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
    static if (!fieldHas!(T, index, SerdeIgnore))
    {
        const ordinal = base + nodeOrdinal!(T, index);
        static if (fieldHas!(T, index, SerdeFlatten))
            validateRequired(parser, &output.tupleof[index], seen, ordinal);
        else
        {
            static if (fieldHas!(T, index, SerdeRequired))
                if (!seen[ordinal])
                    parser.fail(SerdeErrorKind.missingRequiredField,
                        fieldName!(T, index));
            alias F = FieldType!(T, index);
            static if (isTaggedUnion!F ||
                (isOption!F && isTaggedUnion!(OptionElement!F)) ||
                (is(Unqualified!F == TaggedPointee*, TaggedPointee) &&
                    isTaggedUnion!TaggedPointee))
            {
            }
            else static if (isSerdeStruct!F)
            {
                if (seen[ordinal])
                    validateRequired(parser, &output.tupleof[index], seen,
                        ordinal + 1);
            }
            else static if (isOption!F && isSerdeStruct!(OptionElement!F))
            {
                if (seen[ordinal] && output.tupleof[index].isSome)
                    validateRequired(parser, &output.tupleof[index].storage(), seen,
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
        decodeHashMapInline(parser, cast(U*) output, depth);
    else static if (isOwnedHashMap!U)
        decodeOwnedHashMapInline(parser, cast(U*) output, depth);
    else static if (isStringHashMap!U)
        decodeStringHashMapInline!U(parser, cast(U*) output, depth);
    else static if (isTaggedUnion!U)
        decodeTaggedInline(parser, output, depth);
    else static if (isSerdeStruct!U)
        decodeInlineTable(parser, output, depth);
}

private void decodeAdaptedValue(T, size_t index, F)(
    ref TomlParser parser,
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

private void decodeOption(T)(
    ref TomlParser parser,
    Option!T* output,
    size_t depth,
)
{
    decodeValue(parser, &(*output).storage(), depth);
    if (parser.error.ok)
        (*output).markPresent();
}

private void decodeTaggedInline(T)(
    ref TomlParser parser,
    T* output,
    size_t depth,
)
{
    alias U = Unqualified!T;
    static if (taggedUnionLayout!U == TagLayout.external)
        decodeExternalTaggedInline(parser, output, depth);
    else
    {
        DiscriminantType!U tag;
        TomlParser scanner = parser;
        scanner.tablePathLength = 0;
        scanInlineDiscriminant!U(scanner, &tag, depth);
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
                    decodeAdjacentTaggedInlineCase!(U, index)(
                        parser, output, depth);
                else
                    decodeInternalTaggedInlineCase!(U, index)(
                        parser, output, depth);
                found = true;
            }
        }
        if (!found)
            parser.fail(SerdeErrorKind.unknownVariant);
    }
}

private void decodeExternalTaggedInline(T)(
    ref TomlParser parser,
    T* output,
    size_t depth,
)
{
    alias U = Unqualified!T;
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    parser.horizontalSpace();
    ParsedKey[64] key;
    size_t keyLength;
    parseKeyPath(parser, key[], &keyLength);
    if (parser.error.ok && keyLength != 1)
        parser.fail(SerdeErrorKind.invalidSyntax);
    if (parser.error.ok)
        decodeTaggedEnumName(parser, key[0].value,
            &output.tupleof[discriminantIndex!U]);
    parser.horizontalSpace();
    if (parser.error.ok && !parser.consume('='))
        parser.fail(SerdeErrorKind.invalidSyntax);
    parser.horizontalSpace();
    if (parser.error.ok)
        decodeActiveTaggedCase(parser, output, depth + 1);
    preserveDiagnostic(parser, key[], keyLength);
    clearKeys(parser, key[], keyLength);
    if (!parser.error.ok)
        return;
    parser.horizontalSpace();
    if (!parser.consume('}'))
        parser.fail(SerdeErrorKind.invalidSyntax);
}

private void scanInlineDiscriminant(T)(
    ref TomlParser parser,
    DiscriminantType!T* tag,
    size_t depth,
)
{
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    parser.horizontalSpace();
    bool seen;
    size_t fields;
    while (!parser.consume('}'))
    {
        if (fields++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        if (parser.error.ok && keyLength == 1 &&
            fieldMatches!(T, discriminantIndex!T)(key[0].value,
                parser.options.keyCase))
        {
            if (seen)
                parser.fail(SerdeErrorKind.duplicateField, key[0].value);
            else
            {
                seen = true;
                decodeTaggedEnum(parser, tag);
            }
        }
        else if (parser.error.ok)
            skipValue(parser, depth + 1);
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
    if (!seen)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, discriminantIndex!T));
}

private void decodeActiveTaggedCase(T)(
    ref TomlParser parser,
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

private void decodeAdjacentTaggedInlineCase(T, size_t caseIndex)(
    ref TomlParser parser,
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
    parser.horizontalSpace();
    while (!parser.consume('}'))
    {
        if (fields++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        if (parser.error.ok && keyLength == 1 &&
            fieldMatches!(T, discriminantIndex!T)(key[0].value,
                parser.options.keyCase))
        {
            if (seenTag)
                parser.fail(SerdeErrorKind.duplicateField, key[0].value);
            else
            {
                DiscriminantType!T tag;
                decodeTaggedEnum(parser, &tag);
                if (parser.error.ok && tag != output.tupleof[discriminantIndex!T])
                    parser.fail(SerdeErrorKind.unknownVariant);
                seenTag = true;
            }
        }
        else if (parser.error.ok && keyLength == 1 &&
            fieldMatches!(T, payloadIndex!T)(key[0].value,
                parser.options.keyCase))
        {
            if (seenPayload)
                parser.fail(SerdeErrorKind.duplicateField, key[0].value);
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
    if (!seenTag)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, discriminantIndex!T));
    else if (!seenPayload)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, payloadIndex!T));
}

private void decodeInternalTaggedInlineCase(T, size_t caseIndex)(
    ref TomlParser parser,
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
    bool[tomlNodeCount!C] seen;
    size_t fields;
    parser.horizontalSpace();
    while (!parser.consume('}'))
    {
        if (fields++ == parser.options.limits.maxCollectionLength)
        {
            parser.fail(SerdeErrorKind.collectionLimit);
            return;
        }
        ParsedKey[64] key;
        size_t keyLength;
        parseKeyPath(parser, key[], &keyLength);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        if (parser.error.ok && keyLength == 1 &&
            fieldMatches!(T, discriminantIndex!T)(key[0].value,
                parser.options.keyCase))
        {
            if (seenTag)
                parser.fail(SerdeErrorKind.duplicateField, key[0].value);
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
            decodePath(parser,
                &output.tupleof[payloadIndex!T].tupleof[caseIndex],
                null, 0, key[], keyLength, 0, 0, seen.ptr, 0, &matched);
            if (!matched && parser.error.ok)
            {
                if (parser.options.limits.ignoreUnknownFields)
                    skipValue(parser, depth + 1);
                else
                    parser.fail(SerdeErrorKind.unknownField,
                        key[keyLength - 1].value);
            }
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
    if (!seenTag)
        parser.fail(SerdeErrorKind.missingRequiredField,
            fieldName!(T, discriminantIndex!T));
    else
        validateRequired(parser,
            &output.tupleof[payloadIndex!T].tupleof[caseIndex], seen.ptr, 0);
}

private void decodeHashMapInline(K, V, Hasher, Equal)(
    ref TomlParser parser,
    HashMap!(K, V, Hasher, Equal)* output,
    size_t depth,
)
{
    alias Map = HashMap!(K, V, Hasher, Equal);
    static assert(is(Unqualified!K == String));
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    Map values = Map.create(parser.allocator);
    scope (exit)
        values.deinit();
    parser.horizontalSpace();
    if (parser.consume('}'))
    {
        move_emplace(values, *output);
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
        if (parser.error.ok && keyLength != 1)
            parser.fail(SerdeErrorKind.unsupportedValue);
        if (parser.error.ok && !ownParsedKey(parser, &key[0]))
            return;
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();
        V value;
        if (parser.error.ok)
            decodeValue(parser, &value, depth + 1);
        if (parser.error.ok)
        {
            final switch (values.tryAdd(&key[0].value, &value))
            {
                case AddStatus.inserted:
                    key[0].owned = false;
                    break;
                case AddStatus.alreadyPresent:
                    parser.fail(SerdeErrorKind.duplicateField, key[0].value);
                    break;
                case AddStatus.outOfMemory:
                    parser.fail(SerdeErrorKind.allocationFailure);
                    break;
            }
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
    move_emplace(values, *output);
}

private void decodeOwnedHashMapInline(K, V, Hasher, Equal)(
    ref TomlParser parser,
    OwnedHashMap!(K, V, Hasher, Equal)* output,
    size_t depth,
)
{
    alias Map = OwnedHashMap!(K, V, Hasher, Equal);
    static assert(is(Unqualified!K == OwnedString));
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    Map values = Map.create(parser.allocator);
    scope (exit)
        values.deinit();
    parser.horizontalSpace();
    if (parser.consume('}'))
    {
        move_emplace(values, *output);
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
        if (parser.error.ok && keyLength != 1)
            parser.fail(SerdeErrorKind.unsupportedValue);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();

        OwnedString ownedKey;
        scope (exit)
            ownedKey.deinit();
        if (parser.error.ok &&
            !OwnedString.tryFromString(
                parser.allocator,
                key[0].value,
                &ownedKey,
            ))
            parser.fail(SerdeErrorKind.allocationFailure);

        V value;
        initializeOwnedValue(parser.allocator, &value);
        scope (exit)
            deinitOwnedValue(&value);
        if (parser.error.ok)
            decodeValue(parser, &value, depth + 1);
        if (parser.error.ok)
        {
            final switch (values.tryAdd(&ownedKey, &value))
            {
                case AddStatus.inserted:
                    break;
                case AddStatus.alreadyPresent:
                    parser.fail(SerdeErrorKind.duplicateField, key[0].value);
                    break;
                case AddStatus.outOfMemory:
                    parser.fail(SerdeErrorKind.allocationFailure);
                    break;
            }
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
    move_emplace(values, *output);
}

private void decodeStringHashMapInline(Map)(
    ref TomlParser parser,
    Map* output,
    size_t depth,
) if (isStringHashMap!Map)
{
    alias V = StringHashMapValue!Map;
    if (!parser.consume('{'))
    {
        parser.fail(SerdeErrorKind.typeMismatch);
        return;
    }
    Map values = Map.create(parser.allocator);
    scope (exit)
        deinitOwnedValue(&values);
    parser.horizontalSpace();
    if (parser.consume('}'))
    {
        move_emplace(values, *output);
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
        if (parser.error.ok && keyLength != 1)
            parser.fail(SerdeErrorKind.unsupportedValue);
        parser.horizontalSpace();
        if (parser.error.ok && !parser.consume('='))
            parser.fail(SerdeErrorKind.invalidSyntax);
        parser.horizontalSpace();

        OwnedString ownedKey;
        scope (exit)
            ownedKey.deinit();
        if (parser.error.ok &&
            !OwnedString.tryFromString(
                parser.allocator,
                key[0].value,
                &ownedKey,
            ))
            parser.fail(SerdeErrorKind.allocationFailure);

        V value;
        initializeOwnedValue(parser.allocator, &value);
        scope (exit)
            deinitOwnedValue(&value);
        if (parser.error.ok)
            decodeValue(parser, &value, depth + 1);
        if (parser.error.ok)
        {
            final switch (values.tryAddMove(&ownedKey, &value))
            {
                case AddStatus.inserted:
                    break;
                case AddStatus.alreadyPresent:
                    parser.fail(SerdeErrorKind.duplicateField, key[0].value);
                    break;
                case AddStatus.outOfMemory:
                    parser.fail(SerdeErrorKind.allocationFailure);
                    break;
            }
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
    move_emplace(values, *output);
}

private void decodeInlineTable(T)(
    ref TomlParser parser,
    T* output,
    size_t depth,
    bool* externalSeen = null,
)
{
    applySchemaDefaults(output);
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
    T* value = parser.allocator.tryAllocateInit!T();
    if (value is null)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
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
    if (parser.error.ok && !assignEnumName(name,
            parser.options.variantCase, output))
        parser.fail(SerdeErrorKind.typeMismatch);
    if (owned)
        parser.allocator.deallocateArray(name.ptr[0 .. name.length + 1]);
}

private void decodeTaggedEnum(T)(ref TomlParser parser, T* output)
{
    String name;
    bool owned;
    decodeStringToken(parser, &name, &owned, true);
    if (parser.error.ok)
        decodeTaggedEnumName(parser, name, output);
    if (owned)
        parser.allocator.deallocateArray(name.ptr[0 .. name.length + 1]);
}

private void decodeTaggedEnumName(T)(
    ref TomlParser parser,
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
    Element[] values = parser.allocator.tryAllocateInitArray!Element(count);
    if (count != 0 && values.ptr is null)
    {
        parser.fail(SerdeErrorKind.allocationFailure);
        return;
    }
    *output = values;
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

private void decodeArray(Container)(
    ref TomlParser parser,
    Container* output,
    size_t depth,
) if (isArray!Container)
{
    alias Element = ArrayElement!Container;
    TomlParser counter = parser;
    counter.tablePathLength = 0;
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
    parser.valueSpace();
    foreach (index; 0 .. count)
    {
        decodeValue(parser, &values[index], depth + 1);
        if (!parser.error.ok)
        {
            values.deinit();
            return;
        }
        parser.valueSpace();
        if (index + 1 < count)
        {
            if (!parser.consume(','))
            {
                values.deinit();
                parser.fail(SerdeErrorKind.invalidSyntax);
                return;
            }
            parser.valueSpace();
        }
        else if (parser.consume(','))
            parser.valueSpace();
    }
    if (!parser.consume(']'))
    {
        values.deinit();
        parser.fail(SerdeErrorKind.invalidSyntax);
        return;
    }
    deinitOwnedValue(output);
    move_emplace(values, *output);
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
            parser.allocator.deallocateArray(value.ptr[0 .. value.length + 1]);
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

private void decodeStringBuf(ref TomlParser parser, StringBuf* output)
{
    String value;
    bool owned;
    decodeStringToken(parser, &value, &owned, true);
    if (!parser.error.ok)
        return;
    version (XTB_Checked)
        require(owned, "owned TOML string was not allocated");
    StringBuf result = StringBuf.adoptRaw(
        parser.allocator,
        cast(char*) value.ptr,
        value.length,
        value.length + 1,
    );
    move_emplace(result, *output);
}

private void decodeOwnedString(ref TomlParser parser, OwnedString* output)
{
    String value;
    bool owned;
    decodeStringToken(parser, &value, &owned, true, false);
    if (!parser.error.ok)
        return;
    version (XTB_Checked)
        require(owned, "owned TOML string was not allocated");
    auto raw = RawArrayStorage!char.adopt(
        cast(char*) value.ptr,
        value.length,
        value.length,
    );
    OwnedStringUnmanaged storage =
        OwnedStringUnmanaged.adoptExact(&raw);
    OwnedString result = OwnedString.adoptUnmanaged(
        parser.allocator,
        &storage,
    );
    move_emplace(result, *output);
}

private void decodeStringToken(
    ref TomlParser parser,
    String* output,
    bool* owned,
    bool forceCopy = false,
    bool terminate = true,
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
        if (value == '\n' || value == '\r' ||
            (value < 0x20 && value != '\t'))
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
            DecodedCodePoint decoded;
            const utf8Error = decode_code_point(
                parser.input,
                parser.position,
                &decoded,
            );
            if (utf8Error.failed)
            {
                parser.fail(SerdeErrorKind.invalidUtf8);
                return;
            }
            foreach (_; 0 .. decoded.byte_length)
                parser.take();
            decodedLength += decoded.byte_length;
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
        if (quote == '"' && parser.input[source] == '\\')
        {
            ++source;
            decodeEscapeBytes(parser.input, &source, destination, &target);
        }
        else
            destination[target++] = parser.input[source++];
    }
    if (terminate)
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
    const encoded = encode_utf8(cast(dchar) value);
    const codeUnits = encoded.bytes;
    foreach (index; 0 .. encoded.byte_length)
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
