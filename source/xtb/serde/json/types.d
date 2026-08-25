module xtb.serde.json.types;

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

package(xtb.serde.json) SerdeError success() pure @safe
{
    return SerdeError.init;
}

package(xtb.serde.json) SerdeError simpleError(SerdeErrorKind kind) pure @safe
{
    SerdeError result;
    result.kind = kind;
    result.line = 1;
    result.column = 1;
    return result;
}
