module xtb.serde.json.types;

nothrow @nogc:

import core.stdc.errno : ERANGE, errno;
import core.stdc.math : isfinite;
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
