module xtb.serde.traits;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import xtb.core.array : Array;
import xtb.core.memory : Allocator;
import xtb.core.option : Option;
import xtb.core.string : StringBuf;
import xtb.core.types : String;
import xtb.serde.attributes;
import xtb.serde.casing : casedNamesEqual, matchesCased;

template Unqualified(T)
{
    alias Unqualified = typeof(cast() T.init);
}

enum isString(T) = is(Unqualified!T == String) ||
    is(Unqualified!T == immutable(char)[]);

enum isStringBuf(T) = is(Unqualified!T == StringBuf);

template ArrayElement(T)
{
    static if (is(Unqualified!T == Array!Element, Element))
        alias ArrayElement = Element;
    else
        static assert(false, T.stringof ~ " is not an Array");
}

enum isArray(T) = is(Unqualified!T == Array!Element, Element);

template OptionElement(T)
{
    static if (is(Unqualified!T == Option!Element, Element))
        alias OptionElement = Element;
    else
        static assert(false, T.stringof ~ " is not an Option");
}

enum isOption(T) = is(Unqualified!T == Option!Element, Element);

enum isDynamicArray(T) = is(Unqualified!T == Element[], Element) &&
    !is(Element == char) && !is(Element == const(char)) &&
    !is(Element == immutable(char));

enum isFixedArray(T) = is(Unqualified!T == Element[N], Element, size_t N) &&
    !is(Element == char) && !is(Element == const(char)) &&
    !is(Element == immutable(char));

enum isSerdeStruct(T) = is(Unqualified!T == struct) && !isStringBuf!T &&
    !isArray!T && !isOption!T &&
    !__traits(hasMember, Unqualified!T, "__dtor");

private bool containsAttribute(A, Attributes...)(Attributes attributes)
pure @safe
{
    bool result;
    static foreach (attribute; attributes)
        static if (is(typeof(attribute) == A))
            result = true;
    return result;
}

private size_t countAttribute(A, Attributes...)(Attributes attributes)
pure @safe
{
    size_t result;
    static foreach (attribute; attributes)
        static if (is(typeof(attribute) == A))
            ++result;
    return result;
}

template FieldSymbol(T, size_t index)
{
    enum sourceName = __traits(identifier, Unqualified!T.tupleof[index]);
    alias FieldSymbol = __traits(getMember, Unqualified!T, sourceName);
}

template FieldType(T, size_t index)
{
    alias FieldType = typeof(Unqualified!T.tupleof[index]);
}

enum fieldHas(T, size_t index, A) = containsAttribute!A(
        __traits(getAttributes, FieldSymbol!(T, index)),
    );

enum fieldAttributeCount(T, size_t index, A) = countAttribute!A(
        __traits(getAttributes, FieldSymbol!(T, index)),
    );

template isDefaultValueAttribute(A)
{
    static if (is(A == DefaultValue!Value, Value))
        enum isDefaultValueAttribute = true;
    else
        enum isDefaultValueAttribute = false;
}

template isOmitIfAttribute(A)
{
    static if (is(A == OmitIf!predicate, alias predicate))
        enum isOmitIfAttribute = true;
    else
        enum isOmitIfAttribute = false;
}

private size_t countDefaultValues(Attributes...)(Attributes attributes)
pure @safe
{
    size_t result;
    static foreach (attribute; attributes)
        static if (isDefaultValueAttribute!(typeof(attribute)))
            ++result;
    return result;
}

private size_t countOmitPredicates(Attributes...)(Attributes attributes)
pure @safe
{
    size_t result;
    static foreach (attribute; attributes)
        static if (isOmitIfAttribute!(typeof(attribute)))
            ++result;
    return result;
}

enum fieldDefaultValueCount(T, size_t index) = countDefaultValues(
        __traits(getAttributes, FieldSymbol!(T, index)),
    );

enum fieldOmitPredicateCount(T, size_t index) = countOmitPredicates(
        __traits(getAttributes, FieldSymbol!(T, index)),
    );

string fieldName(T, size_t index)() pure @safe
{
    string result = __traits(identifier, Unqualified!T.tupleof[index]);
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        static if (is(typeof(attribute) == Rename))
            result = attribute.value;
    return result;
}

bool fieldMatches(T, size_t index)(scope String candidate) pure @safe
{
    return fieldMatches!(T, index)(candidate, KeyCase.schema);
}

bool fieldMatches(T, size_t index)(scope String candidate, KeyCase overrideCase)
pure @safe
{
    enum renamed = fieldHas!(T, index, Rename);
    const casing = overrideCase == KeyCase.schema ? schemaCase!T : overrideCase;
    if (renamed ? stringEqual(candidate, fieldName!(T, index)) : matchesCased(candidate, fieldName!(T, index), casing))
        return true;
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        static if (is(typeof(attribute) == AliasName))
            if (stringEqual(candidate, attribute.value))
                return true;
    return false;
}

KeyCase schemaCase(T)() pure @safe
{
    KeyCase result = KeyCase.preserve;
    static foreach (attribute; __traits(getAttributes, Unqualified!T))
        static if (is(typeof(attribute) == FieldCase))
            result = attribute.value;
    return result;
}

KeyCase enumCase(T)() pure @safe
{
    KeyCase result = KeyCase.preserve;
    static foreach (attribute; __traits(getAttributes, Unqualified!T))
        static if (is(typeof(attribute) == VariantCase))
            result = attribute.value;
    return result;
}

template EnumMemberSymbol(T, string member)
{
    alias EnumMemberSymbol = __traits(getMember, Unqualified!T, member);
}

string enumMemberName(T, string member)() pure @safe
{
    string result = member;
    static foreach (attribute; __traits(getAttributes,
            EnumMemberSymbol!(T, member)))
        static if (is(typeof(attribute) == Rename))
            result = attribute.value;
    return result;
}

bool enumMemberMatches(T, string member)(
    scope String candidate,
    KeyCase overrideCase = KeyCase.schema,
) pure @safe
{
    enum renamed = containsAttribute!Rename(__traits(getAttributes,
                EnumMemberSymbol!(T, member)));
    const casing = overrideCase == KeyCase.schema ? enumCase!T : overrideCase;
    if (renamed
        ? stringEqual(candidate, enumMemberName!(T, member)) : matchesCased(candidate, enumMemberName!(
            T, member), casing))
        return true;
    static foreach (attribute; __traits(getAttributes,
            EnumMemberSymbol!(T, member)))
        static if (is(typeof(attribute) == AliasName))
            if (stringEqual(candidate, attribute.value))
                return true;
    return false;
}

package(xtb.serde) void applySchemaDefaults(T)(T* output)
{
    alias U = Unqualified!T;
    static if (isSerdeStruct!U)
    {
        static foreach (index; 0 .. U.tupleof.length)
        {
            static if (!fieldHas!(U, index, Ignore))
            {
                static foreach (attribute; __traits(getAttributes, FieldSymbol!(U, index)))
                    static if (isDefaultValueAttribute!(typeof(attribute)))
                        output.tupleof[index] = attribute.value;
                static if (fieldDefaultValueCount!(U, index) == 0 &&
                    isSerdeStruct!(FieldType!(U, index)))
                    applySchemaDefaults(&output.tupleof[index]);
            }
        }
    }
}

bool fieldShouldOmit(T, size_t index, F)(scope const ref F value)
{
    bool result;
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        static if (isOmitIfAttribute!(typeof(attribute)))
            if (attribute.test(value))
                result = true;
    return result;
}

private bool invokeOmitPredicate(alias predicate, F)(scope const ref F value)
{
    return predicate(value);
}

private bool stringEqual(scope String left, scope String right) pure @safe
{
    if (left.length != right.length)
        return false;
    foreach (index, value; left)
        if (value != right[index])
            return false;
    return true;
}

private size_t fieldWidth(T, size_t index)() pure @safe
{
    static if (fieldHas!(T, index, Ignore))
        return 0;
    else static if (fieldHas!(T, index, Flatten))
        return serializedFieldCount!(FieldType!(T, index));
    else
        return 1;
}

private size_t countFields(T, size_t index = 0)() pure @safe
{
    static if (index == Unqualified!T.tupleof.length)
        return 0;
    else
        return fieldWidth!(T, index) + countFields!(T, index + 1);
}

enum serializedFieldCount(T) = countFields!T;

private size_t countFieldsBefore(T, size_t target, size_t index = 0)()
pure @safe
{
    static if (index == target)
        return 0;
    else
        return fieldWidth!(T, index) + countFieldsBefore!(T, target, index + 1);
}

enum fieldOrdinal(T, size_t index) = countFieldsBefore!(T, index);

private bool supportedValue(T)() pure @safe
{
    alias U = Unqualified!T;
    static if (isString!U || isStringBuf!U || is(U == bool) || is(U == enum) ||
        __traits(isIntegral, U) || __traits(isFloating, U))
        return true;
    else static if (isOption!U)
        return supportedValue!(OptionElement!U);
    else static if (is(U == Pointee*, Pointee))
        return supportedValue!Pointee;
    else static if (isDynamicArray!U)
        return supportedValue!(typeof(U.init[0]));
    else static if (isArray!U)
        return supportedValue!(ArrayElement!U);
    else static if (isFixedArray!U)
        return supportedValue!(typeof(U.init[0]));
    else static if (isSerdeStruct!U)
    {
        bool result = true;
        static foreach (index; 0 .. U.tupleof.length)
            static if (!fieldHas!(U, index, Ignore))
                result = result && supportedValue!(FieldType!(U, index));
        return result;
    }
    else
        return false;
}

enum isSupportedValue(T) = supportedValue!T;

void validateSchema(T)()
{
    alias U = Unqualified!T;
    static assert(isSerdeStruct!U,
        "serde document root must be a struct without a user-defined destructor");
    static assert(countAttribute!FieldCase(__traits(getAttributes, U)) <= 1,
        "a serde struct may have at most one @fieldCase");
    static assert(schemaCase!U != KeyCase.schema,
        "@fieldCase(KeyCase.schema) is not a concrete casing policy");
    static foreach (index; 0 .. U.tupleof.length)
        validateFieldSchema!(U, index)();
    static foreach (left; 0 .. serializedFieldCount!U)
        static foreach (right; left + 1 .. serializedFieldCount!U)
            static assert(!leafNamesOverlap!U(left, right),
                "serialized field names and aliases must be unique after flattening");
}

private bool borrowedValue(T)() pure @safe
{
    alias U = Unqualified!T;
    static if (isString!U || is(U == bool) || is(U == enum) ||
        __traits(isIntegral, U) || __traits(isFloating, U))
        return true;
    else static if (isOption!U)
        return borrowedValue!(OptionElement!U);
    else static if (is(U == Pointee*, Pointee))
        return borrowedValue!Pointee;
    else static if (isDynamicArray!U)
        return borrowedValue!(typeof(U.init[0]));
    else static if (isFixedArray!U)
        return borrowedValue!(typeof(U.init[0]));
    else static if (isSerdeStruct!U && !hasElaborateDestructor!U)
    {
        bool result = true;
        static foreach (index; 0 .. U.tupleof.length)
            static if (!fieldHas!(U, index, Ignore))
                result = result && borrowedValue!(FieldType!(U, index));
        return result;
    }
    else
        return false;
}

private bool ownedValue(T)() pure @safe
{
    alias U = Unqualified!T;
    static if (isStringBuf!U || is(U == bool) || is(U == enum) ||
        __traits(isIntegral, U) || __traits(isFloating, U))
        return true;
    else static if (isOption!U)
        return ownedValue!(OptionElement!U);
    else static if (isArray!U)
        return ownedValue!(ArrayElement!U);
    else static if (isFixedArray!U)
        return ownedValue!(typeof(U.init[0]));
    else static if (isSerdeStruct!U)
    {
        bool result = true;
        static foreach (index; 0 .. U.tupleof.length)
            static if (!fieldHas!(U, index, Ignore))
                result = result && ownedValue!(FieldType!(U, index));
        return result;
    }
    else
        return false;
}

void validateBorrowedSchema(T)()
{
    validateSchema!T();
    static assert(borrowedValue!T,
        "Deserialized schemas use String, slices, and pointers; owning containers require direct decoding");
}

void validateOwnedSchema(T)()
{
    validateSchema!T();
    static assert(ownedValue!T,
        "directly decoded schemas use StringBuf and Array; String, slices, and raw pointers require Deserialized");
}

package(xtb.serde) void initializeOwnedValue(T)(
    Allocator* allocator,
    T* output,
)
{
    alias U = Unqualified!T;
    static if (isStringBuf!U)
        *cast(StringBuf*) output = StringBuf.create(allocator);
    else static if (isOption!U)
        initializeOwnedValue(allocator, &(*output).storage());
    else static if (isArray!U)
        *cast(U*) output = U.create(allocator);
    else static if (isFixedArray!U)
        foreach (index; 0 .. output.length)
            initializeOwnedValue(allocator, &(*output)[index]);
    else static if (isSerdeStruct!U)
                {
                static foreach (index; 0 .. U.tupleof.length)
                    initializeOwnedValue(allocator, &output.tupleof[index]);
            }
}

private bool fieldsOverlap(A, size_t left, B, size_t right)() pure @safe
{
    enum leftCase = fieldHas!(A, left, Rename) ? KeyCase.preserve : schemaCase!A;
    enum rightCase = fieldHas!(B, right, Rename) ? KeyCase.preserve : schemaCase!B;
    if (casedNamesEqual(fieldName!(A, left), leftCase,
            fieldName!(B, right), rightCase))
        return true;
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(A, left)))
        static if (is(typeof(attribute) == AliasName))
            if (fieldMatches!(B, right)(attribute.value, KeyCase.schema))
                return true;
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(B, right)))
        static if (is(typeof(attribute) == AliasName))
            if (fieldMatches!(A, left)(attribute.value, KeyCase.schema))
                return true;
    return false;
}

private bool fieldOverlapsOrdinal(A, size_t left, B)(size_t ordinal)
pure @safe
{
    size_t base;
    static foreach (index; 0 .. Unqualified!B.tupleof.length)
    {
        static if (!fieldHas!(B, index, Ignore))
        {
            static if (fieldHas!(B, index, Flatten))
            {
                if (ordinal >= base && ordinal < base +
                    serializedFieldCount!(FieldType!(B, index)))
                    return fieldOverlapsOrdinal!(A, left, FieldType!(B, index))(
                        ordinal - base);
                base += serializedFieldCount!(FieldType!(B, index));
            }
            else
            {
                if (ordinal == base)
                    return fieldsOverlap!(A, left, B, index);
                ++base;
            }
        }
    }
    return false;
}

private bool leafOverlapAcross(A, B)(size_t left, size_t right) pure @safe
{
    size_t base;
    static foreach (index; 0 .. Unqualified!A.tupleof.length)
    {
        static if (!fieldHas!(A, index, Ignore))
        {
            static if (fieldHas!(A, index, Flatten))
            {
                if (left >= base && left < base +
                    serializedFieldCount!(FieldType!(A, index)))
                    return leafOverlapAcross!(FieldType!(A, index), B)(
                        left - base, right);
                base += serializedFieldCount!(FieldType!(A, index));
            }
            else
            {
                if (left == base)
                    return fieldOverlapsOrdinal!(A, index, B)(right);
                ++base;
            }
        }
    }
    return false;
}

private bool leafNamesOverlap(T)(size_t left, size_t right) pure @safe
{
    return leafOverlapAcross!(T, T)(left, right);
}

private void validateFieldSchema(T, size_t index)()
{
    alias F = FieldType!(T, index);
    enum ignored = fieldHas!(T, index, Ignore);
    enum flattened = fieldHas!(T, index, Flatten);
    enum serdeAttributeCount =
        fieldAttributeCount!(T, index, Rename) +
        fieldAttributeCount!(T, index, AliasName) +
        fieldAttributeCount!(T, index, Ignore) +
        fieldAttributeCount!(T, index, Required) +
        fieldAttributeCount!(T, index, OmitDefault) +
        fieldAttributeCount!(T, index, Flatten) +
        fieldDefaultValueCount!(T, index) +
        fieldOmitPredicateCount!(T, index);

    static assert(fieldAttributeCount!(T, index, Rename) <= 1,
        "a serde field may have at most one @rename");
    static assert(!ignored || serdeAttributeCount == 1,
        "@ignore cannot be combined with another serde attribute");
    static assert(!flattened || isSerdeStruct!F,
        "@flatten requires a struct field without a destructor");
    static assert(fieldDefaultValueCount!(T, index) <= 1,
        "a serde field may have at most one @defaultValue");
    static assert(fieldOmitPredicateCount!(T, index) <= 1,
        "a serde field may have at most one @omitIf");
    static assert(fieldDefaultValueCount!(T, index) == 0 ||
            !hasElaborateDestructor!(
                Unqualified!F),
        "@defaultValue currently requires a field without an elaborate destructor");
    static assert(fieldDefaultValueCount!(T, index) == 0 || !flattened,
        "@defaultValue cannot be combined with @flatten");
    static assert(fieldOmitPredicateCount!(T, index) == 0 ||
            fieldAttributeCount!(T, index, OmitDefault) == 0,
        "@omitIf cannot be combined with @omitDefault");
    static assert(ignored || isSupportedValue!F,
        "unsupported serde field type: " ~ F.stringof);
    static if (!ignored)
        static assert(fieldName!(T, index).length != 0,
            "serialized field names must not be empty");
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
    {
        static if (is(typeof(attribute) == AliasName))
            static assert(attribute.value.length != 0,
                "serialized field aliases must not be empty");
        else static if (isDefaultValueAttribute!(typeof(attribute)))
            static assert(is(typeof(attribute.value) : Unqualified!F),
                "@defaultValue must be assignable to its field type");
        else static if (isOmitIfAttribute!(typeof(attribute)))
            static assert(__traits(compiles,
                    invokeOmitPredicate!(typeof(attribute).test, F)(
                    *cast(const(F)*) null)),
                "@omitIf predicate must accept the field by const reference");
    }
    static if (flattened)
        validateSchema!F();
}
