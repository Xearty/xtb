module xtb.serde.attributes;

nothrow @nogc:

struct Rename
{
    string value;
}

struct AliasName
{
    string value;
}

struct Ignore
{
}

struct Required
{
}

struct OmitDefault
{
}

struct DefaultValue(T)
{
    T value;
}

struct OmitIf(alias predicate)
{
    alias test = predicate;
}

struct WithSerde(alias adapter)
{
    enum isSerdeAdapter = true;
    alias implementation = adapter;
}

struct Flatten
{
}

enum TagLayout : ubyte
{
    external,
    internal,
    adjacent,
}

struct TaggedUnion
{
    TagLayout layout;
}

struct Discriminant
{
}

struct Payload
{
}

struct CaseOf(T)
{
    T value;
}

enum KeyCase : ubyte
{
    schema,
    preserve,
    camel,
    pascal,
    snake,
    screamingSnake,
    kebab,
}

struct FieldCase
{
    KeyCase value;
}

struct VariantCase
{
    KeyCase value;
}

Rename rename(string value) pure @safe
{
    return Rename(value);
}

AliasName aliasName(string value) pure @safe
{
    return AliasName(value);
}

FieldCase fieldCase(KeyCase value) pure @safe
{
    return FieldCase(value);
}

VariantCase variantCase(KeyCase value) pure @safe
{
    return VariantCase(value);
}

DefaultValue!T defaultValue(T)(T value) pure @safe
{
    return DefaultValue!T(value);
}

TaggedUnion taggedUnion(TagLayout layout) pure @safe
{
    return TaggedUnion(layout);
}

CaseOf!T caseOf(T)(T value) pure @safe
{
    return CaseOf!T(value);
}

enum ignore = Ignore();
enum required = Required();
enum omitDefault = OmitDefault();
enum omitIf(alias predicate) = OmitIf!predicate();
enum withSerde(alias adapter) = WithSerde!adapter();
enum flatten = Flatten();
enum discriminant = Discriminant();
enum payload = Payload();
