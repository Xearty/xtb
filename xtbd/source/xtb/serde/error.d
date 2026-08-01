module xtb.serde.error;

nothrow @nogc:

import xtb.core.types : String;

enum SerdeErrorKind : ubyte
{
    none,
    unexpectedEnd,
    invalidSyntax,
    invalidUtf8,
    invalidEscape,
    invalidNumber,
    numberOutOfRange,
    typeMismatch,
    unknownField,
    duplicateField,
    missingRequiredField,
    depthLimit,
    collectionLimit,
    allocationFailure,
    outputFailure,
    unsupportedValue,
}

struct SerdeError
{
nothrow @nogc:

    SerdeErrorKind kind;
    size_t offset;
    size_t line;
    size_t column;
    String field;

    bool ok() const pure @safe
    {
        return kind == SerdeErrorKind.none;
    }
}

struct SerdeLimits
{
    size_t maxDepth = 64;
    size_t maxCollectionLength = 1024 * 1024;
    bool ignoreUnknownFields;
}
