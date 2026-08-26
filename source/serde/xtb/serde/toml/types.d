module xtb.serde.toml.types;

nothrow @nogc:

import core.stdc.errno : ERANGE, errno;
import core.stdc.math : isfinite, isnan, signbit;
import core.stdc.stdio : snprintf;
import core.stdc.stdlib : strtod;
import xtb.lifetime : hasDDestructor, moveEmplace;
import xtb.containers.array;
import xtb.containers.hash_map;
import xtb.memory : Allocator, deallocateArray, tryAllocateArray, tryAllocateInit, tryAllocateInitArray;
import xtb.option : Option;

version (XTB_Checked) import xtb.panic : require;
import xtb.fmt.writer : Writer;
import xtb.string;
import xtb.containers.string_hash_map;
import xtb.types : String;
import xtb.utf8 : DecodedCodePoint, decodeCodePoint, encodeUtf8,
    isValidUtf8;
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

struct TomlWriteOptions
{
    KeyCase keyCase = KeyCase.schema;
    KeyCase variantCase = KeyCase.schema;
    size_t maxDepth = 64;
}

struct TomlReadOptions
{
    SerdeLimits limits;
    KeyCase keyCase = KeyCase.schema;
    KeyCase variantCase = KeyCase.schema;
}

package(xtb.serde.toml) SerdeError success() pure @safe
{
    return SerdeError.init;
}

package(xtb.serde.toml) SerdeError simpleError(SerdeErrorKind kind) pure @safe
{
    SerdeError result;
    result.kind = kind;
    result.line = 1;
    result.column = 1;
    return result;
}
