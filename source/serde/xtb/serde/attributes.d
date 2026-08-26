module xtb.serde.attributes;

nothrow @nogc:

struct SerdeRename
{
    string value;
}

struct SerdeAliasName
{
    string value;
}

struct SerdeIgnore
{
}

struct SerdeRequired
{
}

struct SerdeOmitDefault
{
}

struct SerdeDefaultValue(T)
{
    T value;
}

struct SerdeOmitIf(alias predicate)
{
    alias test = predicate;
}

struct SerdeWith(alias adapter)
{
    enum isSerdeAdapter = true;
    alias implementation = adapter;
}

struct SerdeFlatten
{
}

enum TagLayout : ubyte
{
    external,
    internal,
    adjacent,
}

struct SerdeTaggedUnion
{
    TagLayout layout;
}

struct SerdeDiscriminant
{
}

struct SerdePayload
{
}

struct SerdeCaseOf(T)
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

struct SerdeFieldCase
{
    KeyCase value;
}

struct SerdeVariantCase
{
    KeyCase value;
}

SerdeRename serdeRename(string value) pure @safe
{
    return SerdeRename(value);
}

SerdeAliasName serdeAliasName(string value) pure @safe
{
    return SerdeAliasName(value);
}

SerdeFieldCase serdeFieldCase(KeyCase value) pure @safe
{
    return SerdeFieldCase(value);
}

SerdeVariantCase serdeVariantCase(KeyCase value) pure @safe
{
    return SerdeVariantCase(value);
}

SerdeDefaultValue!T serdeDefaultValue(T)(T value) pure @safe
{
    return SerdeDefaultValue!T(value);
}

SerdeTaggedUnion serdeTaggedUnion(TagLayout layout) pure @safe
{
    return SerdeTaggedUnion(layout);
}

SerdeCaseOf!T serdeCaseOf(T)(T value) pure @safe
{
    return SerdeCaseOf!T(value);
}

enum serdeIgnore = SerdeIgnore();
enum serdeRequired = SerdeRequired();
enum serdeOmitDefault = SerdeOmitDefault();
enum serdeOmitIf(alias predicate) = SerdeOmitIf!predicate();
enum serdeWith(alias adapter) = SerdeWith!adapter();
enum serdeFlatten = SerdeFlatten();
enum serdeDiscriminant = SerdeDiscriminant();
enum serdePayload = SerdePayload();
