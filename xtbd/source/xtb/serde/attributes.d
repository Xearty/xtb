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

struct Flatten
{
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

enum ignore = Ignore();
enum required = Required();
enum omitDefault = OmitDefault();
enum flatten = Flatten();
