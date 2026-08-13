module xtb.serde.traits;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import xtb.core.lifetime : deinitValue = deinit, moveEmplace, needsDeinit;
import xtb.core.array;
import xtb.core.hash_map;
import xtb.core.memory : Allocator;
import xtb.core.option : Option;
import xtb.core.result : Result;
import xtb.core.owned_string;
import xtb.core.string;
import xtb.core.string_hash_map;
import xtb.core.string_hash_set : StringHashSet, StringHashSetUnmanaged;
import xtb.core.types : String;
import xtb.serde.attributes;
import xtb.serde.casing : casedNamesEqual, matchesCased;
import xtb.serde.error : SerdeErrorKind;

template Unqualified(T)
{
    alias Unqualified = typeof(cast() T.init);
}

enum isString(T) = is(Unqualified!T == String) ||
    is(Unqualified!T == immutable(char)[]);

enum isStringBuf(T) = is(Unqualified!T == StringBuf);
enum isOwnedString(T) = is(Unqualified!T == OwnedString);

template ArrayElement(T)
{
    static if (is(Unqualified!T == Array!Element, Element))
        alias ArrayElement = Element;
    else static if (is(Unqualified!T == OwnedArray!Element, Element))
        alias ArrayElement = Element;
    else
        static assert(false, T.stringof ~ " is not an Array/OwnedArray");
}

enum isShallowArray(T) = is(Unqualified!T == Array!Element, Element);
enum isOwnedArray(T) = is(Unqualified!T == OwnedArray!Element, Element);
enum isArray(T) = isShallowArray!T || isOwnedArray!T;

template OptionElement(T)
{
    static if (is(Unqualified!T == Option!Element, Element))
        alias OptionElement = Element;
    else
        static assert(false, T.stringof ~ " is not an Option");
}

enum isOption(T) = is(Unqualified!T == Option!Element, Element);
enum isResult(T) = is(Unqualified!T == Result!(Value, Error), Value, Error);

enum isHashMap(T) = is(Unqualified!T == HashMap!(Key, Value, Hasher, Equal),
        Key, Value, Hasher, Equal);
enum isOwnedHashMap(T) = is(
        Unqualified!T == OwnedHashMap!(Key, Value, Hasher, Equal),
        Key, Value, Hasher, Equal,
    );

template HashMapKey(T)
{
    static if (is(Unqualified!T == HashMap!(Key, Value, Hasher, Equal),
            Key, Value, Hasher, Equal))
        alias HashMapKey = Key;
    else
        static assert(false, T.stringof ~ " is not a HashMap");
}

template HashMapValue(T)
{
    static if (is(Unqualified!T == HashMap!(Key, Value, Hasher, Equal),
            Key, Value, Hasher, Equal))
        alias HashMapValue = Value;
    else
        static assert(false, T.stringof ~ " is not a HashMap");
}

enum isHashSet(T) = is(
        Unqualified!T == HashSet!(Key, Hasher, Equal),
        Key, Hasher, Equal,
    );
enum isOwnedHashSet(T) = is(
        Unqualified!T == OwnedHashSet!(Key, Hasher, Equal),
        Key, Hasher, Equal,
    );

enum isStringHashSet(T) = is(Unqualified!T == StringHashSet);

template StringHashMapValue(T)
{
    alias U = Unqualified!T;
    static if (is(U == BasicStringHashMap!(Value, ValueOps, OwnsValues),
            Value, ValueOps, bool OwnsValues))
        alias StringHashMapValue = Value;
    else
        static assert(false, T.stringof ~ " is not a StringHashMap");
}

template isStringHashMap(T)
{
    alias U = Unqualified!T;
    static if (is(U == BasicStringHashMap!(Value, ValueOps, OwnsValues),
            Value, ValueOps, bool OwnsValues))
        enum isStringHashMap = true;
    else
        enum isStringHashMap = false;
}

template isOwnedStringHashMap(T)
{
    alias U = Unqualified!T;
    static if (is(U == BasicStringHashMap!(Value, ValueOps, OwnsValues),
            Value, ValueOps, bool OwnsValues))
        enum isOwnedStringHashMap = OwnsValues;
    else
        enum isOwnedStringHashMap = false;
}

enum isArrayUnmanaged(T) =
    is(Unqualified!T == ArrayUnmanaged!Element, Element);

enum isStringBufUnmanaged(T) =
    is(Unqualified!T == StringBufUnmanaged);

enum isHashMapUnmanaged(T) = is(
        Unqualified!T == HashMapUnmanaged!(
            Key,
            Value,
            Hasher,
            Equal,
            Lookup,
            KeyOps,
            ValueOps,
    ),
    Key, Value, Hasher, Equal, Lookup, KeyOps, ValueOps,
    );

enum isHashSetUnmanaged(T) = is(
        Unqualified!T == HashSetUnmanaged!(Key, Hasher, Equal, ElementOps),
        Key, Hasher, Equal, ElementOps,
    );

enum isUnmanagedContainer(T) = isArrayUnmanaged!T ||
    isStringBufUnmanaged!T || isHashMapUnmanaged!T ||
    isHashSetUnmanaged!T || is(Unqualified!T == StringHashSetUnmanaged) ||
    is(Unqualified!T == OwnedStringUnmanaged) ||
    is(Unqualified!T == StringHashMapUnmanaged!(Value, ValueOps), Value, ValueOps);

private enum isSerdeHashMapKey(T) = is(Unqualified!T == String);

enum isDynamicArray(T) = is(Unqualified!T == Element[], Element) &&
    !is(Element == char) && !is(Element == const(char)) &&
    !is(Element == immutable(char));

enum isFixedArray(T) = is(Unqualified!T == Element[N], Element, size_t N) &&
    !is(Element == char) && !is(Element == const(char)) &&
    !is(Element == immutable(char));

enum isSerdeUnion(T) = is(Unqualified!T == union);

enum isSerdeStruct(T) = is(Unqualified!T == struct) && !isStringBuf!T &&
    !isOwnedString!T && !isArray!T && !isOption!T && !isResult!T &&
    !isHashMap!T && !isOwnedHashMap!T && !isHashSet!T &&
    !isOwnedHashSet!T && !isStringHashMap!T && !isStringHashSet!T &&
    !isUnmanagedContainer!T &&
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

// Type-level compiler attributes such as core.attribute.mustuse are returned
// by __traits(getAttributes) as types rather than values. Inspect the symbol
// directly here so serde's own type UDA detection does not try to pass those
// types as function arguments.
private template symbolAttributeCount(alias Symbol, A)
{
    enum size_t symbolAttributeCount = compute();

    private size_t compute()() pure @safe
    {
        size_t result;
        static foreach (attribute; __traits(getAttributes, Symbol))
        {
            static if (is(attribute == A))
                ++result;
            else static if (__traits(compiles, typeof(attribute)))
                static if (is(typeof(attribute) == A))
                    ++result;
        }
        return result;
    }
}

enum isTaggedUnion(T) = is(Unqualified!T == struct) &&
    symbolAttributeCount!(Unqualified!T, TaggedUnion) == 1;

template FieldSymbol(T, size_t index)
{
    enum sourceName = __traits(identifier, Unqualified!T.tupleof[index]);
    alias FieldSymbol = __traits(getMember, Unqualified!T, sourceName);
}

template FieldType(T, size_t index)
{
    alias FieldType = typeof(Unqualified!T.tupleof[index]);
}

template UnionMemberSymbol(T, size_t index)
{
    enum sourceName = __traits(identifier, Unqualified!T.tupleof[index]);
    alias UnionMemberSymbol = __traits(getMember, Unqualified!T, sourceName);
}

template UnionMemberType(T, size_t index)
{
    alias UnionMemberType = typeof(Unqualified!T.tupleof[index]);
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

template isWithSerdeAttribute(A)
{
    static if (__traits(hasMember, A, "isSerdeAdapter") &&
        __traits(hasMember, A, "implementation"))
        enum isWithSerdeAttribute = true;
    else
        enum isWithSerdeAttribute = false;
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

private size_t countAdapters(Attributes...)(Attributes attributes) pure @safe
{
    size_t result;
    static foreach (attribute; attributes)
        static if (isWithSerdeAttribute!(typeof(attribute)))
            ++result;
    return result;
}

enum fieldDefaultValueCount(T, size_t index) = countDefaultValues(
        __traits(getAttributes, FieldSymbol!(T, index)),
    );

enum fieldOmitPredicateCount(T, size_t index) = countOmitPredicates(
        __traits(getAttributes, FieldSymbol!(T, index)),
    );

enum fieldAdapterCount(T, size_t index) = countAdapters(
        __traits(getAttributes, FieldSymbol!(T, index)),
    );

template FindAdapter(Attributes...)
{
    static if (Attributes.length == 0)
        static assert(false, "serde field has no adapter");
    else static if (isWithSerdeAttribute!(typeof(Attributes[0])))
        alias FindAdapter = typeof(Attributes[0]).implementation;
    else
        alias FindAdapter = FindAdapter!(Attributes[1 .. $]);
}

template FieldAdapter(T, size_t index)
{
    alias FieldAdapter = FindAdapter!(
        __traits(getAttributes, FieldSymbol!(T, index)));
}

enum isAdapterRepresentation(T) = isString!T || is(Unqualified!T == bool) ||
    is(Unqualified!T == enum) || __traits(isIntegral, Unqualified!T) ||
    __traits(isFloating, Unqualified!T);

template isCaseOfAttribute(A)
{
    static if (is(A == CaseOf!Tag, Tag))
        enum isCaseOfAttribute = true;
    else
        enum isCaseOfAttribute = false;
}

private size_t countCases(Attributes...)(Attributes attributes) pure @safe
{
    size_t result;
    static foreach (attribute; attributes)
        static if (isCaseOfAttribute!(typeof(attribute)))
            ++result;
    return result;
}

enum unionCaseCount(T, size_t index) = countCases(
        __traits(getAttributes, UnionMemberSymbol!(T, index)),
    );

private size_t findMarkedField(T, A, size_t index = 0)() pure @safe
{
    static if (index == Unqualified!T.tupleof.length)
        return size_t.max;
    else static if (fieldHas!(T, index, A))
        return index;
    else
        return findMarkedField!(T, A, index + 1);
}

private size_t countMarkedFields(T, A, size_t index = 0)() pure @safe
{
    static if (index == Unqualified!T.tupleof.length)
        return 0;
    else
        return (fieldHas!(T, index, A) ? 1 : 0) +
            countMarkedFields!(T, A, index + 1);
}

enum discriminantIndex(T) = findMarkedField!(T, Discriminant);
enum payloadIndex(T) = findMarkedField!(T, Payload);

template DiscriminantType(T)
{
    alias DiscriminantType = FieldType!(T, discriminantIndex!T);
}

template PayloadType(T)
{
    alias PayloadType = FieldType!(T, payloadIndex!T);
}

TagLayout taggedUnionLayout(T)() pure @safe
{
    TagLayout result;
    static foreach (attribute; __traits(getAttributes, Unqualified!T))
        static if (is(typeof(attribute) == TaggedUnion))
            result = attribute.layout;
    return result;
}

bool unionCaseIsActive(T, size_t index, Tag)(Tag tag) pure @safe
{
    bool result;
    static foreach (attribute; __traits(getAttributes,
            UnionMemberSymbol!(T, index)))
        static if (isCaseOfAttribute!(typeof(attribute)))
            result = tag == attribute.value;
    return result;
}

void setUnionCaseTag(T, size_t index, Tag)(Tag* tag)
{
    static foreach (attribute; __traits(getAttributes,
            UnionMemberSymbol!(T, index)))
        static if (isCaseOfAttribute!(typeof(attribute)))
            *tag = attribute.value;
}

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
    static if (isString!U || isStringBuf!U || isOwnedString!U ||
        is(U == bool) || is(U == enum) ||
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
    else static if (isHashMap!U)
        return isSerdeHashMapKey!(HashMapKey!U) &&
            supportedValue!(HashMapValue!U);
    else static if (isStringHashMap!U)
        return supportedValue!(StringHashMapValue!U);
    else static if (isFixedArray!U)
        return supportedValue!(typeof(U.init[0]));
    else static if (isTaggedUnion!U)
    {
        alias P = PayloadType!U;
        bool result = supportedValue!(DiscriminantType!U);
        static foreach (index; 0 .. P.tupleof.length)
            result = result && supportedValue!(UnionMemberType!(P, index));
        return result;
    }
    else static if (isSerdeStruct!U)
    {
        bool result = true;
        static foreach (index; 0 .. U.tupleof.length)
            static if (!fieldHas!(U, index, Ignore))
                static if (fieldAdapterCount!(U, index) == 0)
                    result = result && supportedValue!(FieldType!(U, index));
        return result;
    }
    else
        return false;
}

enum isSupportedValue(T) = supportedValue!T;

package(xtb.serde) void validateValueSchema(T)()
{
    alias U = Unqualified!T;
    static if (isHashMap!U)
    {
        static assert(isSerdeHashMapKey!(HashMapKey!U),
            "serde HashMap keys must have type String");
        validateValueSchema!(HashMapValue!U)();
    }
    else static if (isStringHashMap!U)
        validateValueSchema!(StringHashMapValue!U)();
    else
    {
        static assert(isSupportedValue!U,
            "unsupported serde value type: " ~ U.stringof);
        static if (is(U == enum))
            validateEnumSchema!U();
        else static if (isOption!U)
            validateValueSchema!(OptionElement!U)();
        else static if (is(U == Pointee*, Pointee))
            validateValueSchema!Pointee();
        else static if (isDynamicArray!U)
            validateValueSchema!(typeof(U.init[0]))();
        else static if (isArray!U)
            validateValueSchema!(ArrayElement!U)();
        else static if (isFixedArray!U)
            validateValueSchema!(typeof(U.init[0]))();
        else static if (isSerdeStruct!U)
            validateSchema!U();
    }
}

void validateSchema(T)()
{
    alias U = Unqualified!T;
    static assert(isSerdeStruct!U,
        "serde document root must be a struct without a user-defined destructor");
    static assert(countAttribute!TaggedUnion(__traits(getAttributes, U)) <= 1,
        "a serde struct may have at most one @taggedUnion");
    static if (isTaggedUnion!U)
        validateTaggedUnionSchema!U();
    else
    {
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
}

void validateEnumSchema(T)()
{
    alias U = Unqualified!T;
    static assert(is(U == enum), "enum schema validation requires an enum");
    static assert(countAttribute!VariantCase(__traits(getAttributes, U)) <= 1,
        "a serde enum may have at most one @variantCase");
    static assert(enumCase!U != KeyCase.schema,
        "@variantCase(KeyCase.schema) is not a concrete casing policy");
    alias members = __traits(allMembers, U);
    static foreach (leftIndex, left; members)
    {
        static if (__traits(compiles, __traits(getMember, U, left)))
        {
            static assert(countAttribute!Rename(__traits(getAttributes,
                    EnumMemberSymbol!(U, left))) <= 1,
                "a serde enum member may have at most one @rename");
            static assert(enumMemberName!(U, left).length != 0,
                "serialized enum member names must not be empty");
            static foreach (attribute; __traits(getAttributes,
                    EnumMemberSymbol!(U, left)))
                static if (is(typeof(attribute) == AliasName))
                    static assert(attribute.value.length != 0,
                        "serialized enum aliases must not be empty");
            static foreach (rightIndex, right; members)
                static if (rightIndex > leftIndex &&
                    __traits(compiles, __traits(getMember, U, right)))
                    static assert(!enumMembersOverlap!(U, left, right),
                        "serialized enum names and aliases must be unique");
        }
    }
}

private bool enumMembersOverlap(T, string left, string right)() pure @safe
{
    enum leftCase = enumMemberName!(T, left) == left
        ? enumCase!T : KeyCase.preserve;
    if (enumMemberMatches!(T, right)(enumMemberName!(T, left), leftCase))
        return true;
    static foreach (attribute; __traits(getAttributes,
            EnumMemberSymbol!(T, left)))
        static if (is(typeof(attribute) == AliasName))
            if (enumMemberMatches!(T, right)(attribute.value, KeyCase.preserve))
                return true;
    return false;
}

private void validateTaggedUnionSchema(T)()
{
    alias U = Unqualified!T;
    static assert(countAttribute!TaggedUnion(__traits(getAttributes, U)) == 1,
        "a tagged union must have exactly one @taggedUnion");
    static assert(countMarkedFields!(U, Discriminant) == 1,
        "a tagged union must have exactly one @discriminant field");
    static assert(countMarkedFields!(U, Payload) == 1,
        "a tagged union must have exactly one @payload field");
    static assert(U.tupleof.length == 2,
        "a tagged union contains only its discriminant and payload fields");
    alias Tag = DiscriminantType!U;
    alias P = PayloadType!U;
    static assert(is(Unqualified!Tag == enum),
        "a tagged union discriminant must be an enum");
    static assert(isSerdeUnion!P,
        "a tagged union payload must be a union");
    validateEnumSchema!Tag();
    alias tagMembers = __traits(allMembers, Unqualified!Tag);
    static foreach (leftIndex, member; tagMembers)
    {
        static if (__traits(compiles,
                __traits(getMember, Unqualified!Tag, member)))
        {
            static assert(unionCaseForTagCount!P(
                    __traits(getMember, Unqualified!Tag, member)) == 1,
                "every discriminant enum value must map to exactly one union case");
            static foreach (rightIndex, other; tagMembers)
                static if (rightIndex > leftIndex && __traits(compiles,
                        __traits(getMember, Unqualified!Tag, other)))
                    static assert(__traits(getMember, Unqualified!Tag, member) !=
                            __traits(getMember, Unqualified!Tag, other),
                        "tagged union discriminant enum values must be unique");
        }
    }
    static foreach (index; 0 .. P.tupleof.length)
    {
        {
            alias C = UnionMemberType!(P, index);
            static assert(unionCaseCount!(P, index) == 1,
                "every tagged union payload member needs exactly one @caseOf");
            static foreach (attribute; __traits(getAttributes,
                    UnionMemberSymbol!(P, index)))
                static if (isCaseOfAttribute!(typeof(attribute)))
                    static assert(is(typeof(attribute.value) == Unqualified!Tag),
                        "@caseOf value must have the discriminant enum type");
            static assert(borrowedValue!C,
                "raw tagged unions currently require borrowed payload cases");
            validateValueSchema!C();
            static if (taggedUnionLayout!U == TagLayout.internal)
                static assert(isSerdeStruct!C && !isTaggedUnion!C,
                    "internally tagged union cases must be ordinary structs");
            static foreach (other; index + 1 .. P.tupleof.length)
                static assert(!unionCasesOverlap!(P, index, other, Tag),
                    "tagged union cases must use distinct discriminant values");
        }
    }
    static if (taggedUnionLayout!U == TagLayout.adjacent)
        static assert(!fieldsOverlap!(U, discriminantIndex!U,
                U, payloadIndex!U),
            "adjacent tagged union field names must be distinct");
    static if (taggedUnionLayout!U == TagLayout.internal)
        static foreach (index; 0 .. P.tupleof.length)
            {
            {
                alias C = UnionMemberType!(P, index);
                static if (isSerdeStruct!C)
                    static foreach (field; 0 .. serializedFieldCount!C)
                        static assert(!fieldOverlapsOrdinal!(U,
                                discriminantIndex!U, C)(field),
                            "internal tag name conflicts with a payload field");
            }
        }
}

private bool unionCasesOverlap(P, size_t left, size_t right, Tag)() pure @safe
{
    Tag leftTag;
    Tag rightTag;
    setUnionCaseTag!(P, left)(&leftTag);
    setUnionCaseTag!(P, right)(&rightTag);
    return leftTag == rightTag;
}

private size_t unionCaseForTagCount(P, Tag)(Tag tag) pure @safe
{
    size_t result;
    static foreach (index; 0 .. Unqualified!P.tupleof.length)
        if (unionCaseIsActive!(P, index)(tag))
            ++result;
    return result;
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
    else static if (isHashMap!U)
        return isSerdeHashMapKey!(HashMapKey!U) &&
            borrowedValue!(HashMapValue!U);
    else static if (isFixedArray!U)
        return borrowedValue!(typeof(U.init[0]));
    else static if (isTaggedUnion!U)
    {
        alias P = PayloadType!U;
        bool result = borrowedValue!(DiscriminantType!U);
        static foreach (index; 0 .. P.tupleof.length)
            result = result && borrowedValue!(UnionMemberType!(P, index));
        return result;
    }
    else static if (isSerdeStruct!U)
    {
        bool result = true;
        static foreach (index; 0 .. U.tupleof.length)
            static if (!fieldHas!(U, index, Ignore))
                static if (fieldAdapterCount!(U, index) == 0)
                    result = result && borrowedValue!(FieldType!(U, index));
        return result;
    }
    else
        return false;
}

private bool ownedValue(T)() pure @safe
{
    alias U = Unqualified!T;
    static if (isStringBuf!U || isOwnedString!U || is(U == bool) ||
        is(U == enum) ||
        __traits(isIntegral, U) || __traits(isFloating, U))
        return true;
    else static if (isOption!U)
        return ownedValue!(OptionElement!U);
    else static if (isOwnedArray!U)
        return ownedValue!(ArrayElement!U);
    else static if (isShallowArray!U)
        return ownedValue!(ArrayElement!U) &&
            !needsDeinit!(ArrayElement!U) &&
            !hasElaborateDestructor!(ArrayElement!U);
    else static if (isOwnedStringHashMap!U)
        return ownedValue!(StringHashMapValue!U);
    else static if (isStringHashMap!U)
        return ownedValue!(StringHashMapValue!U) &&
            !needsDeinit!(StringHashMapValue!U) &&
            !hasElaborateDestructor!(StringHashMapValue!U);
    else static if (isFixedArray!U)
        return ownedValue!(typeof(U.init[0]));
    else static if (isTaggedUnion!U)
        return false;
    else static if (isSerdeStruct!U)
    {
        bool result = true;
        static foreach (index; 0 .. U.tupleof.length)
            static if (!fieldHas!(U, index, Ignore))
                static if (fieldAdapterCount!(U, index) == 0)
                    result = result && ownedValue!(FieldType!(U, index));
        return result;
    }
    else
        return false;
}

package(xtb.serde) enum isOwnedSerdeValue(T) = ownedValue!T;

package(xtb.serde) void validateBorrowedValue(T)()
{
    validateValueSchema!T();
    static assert(borrowedValue!T,
        "Deserialized values use String, slices, pointers, and " ~
            "HashMap!(String, V); StringBuf, Array, and OwnedArray require direct decoding");
}

package(xtb.serde) void validateOwnedValue(T)()
{
    validateValueSchema!T();
    static assert(ownedValue!T,
        "directly decoded values use StringBuf, OwnedString, Array, OwnedArray, and " ~
            "StringHashMap; String, slices, raw pointers, and HashMap " ~
            "require Deserialized");
}

void validateBorrowedSchema(T)()
{
    validateSchema!T();
    static assert(borrowedValue!T,
        "Deserialized schemas use String, slices, pointers, and " ~
            "HashMap!(String, V); StringBuf, Array, and OwnedArray require direct decoding");
}

void validateOwnedSchema(T)()
{
    validateSchema!T();
    static assert(ownedValue!T,
        "directly decoded schemas use StringBuf, OwnedString, Array, OwnedArray, and " ~
            "StringHashMap; String, slices, raw pointers, and HashMap " ~
            "require Deserialized");
}

package(xtb.serde) void initializeOwnedValue(T)(
    Allocator* allocator,
    T* output,
)
{
    alias U = Unqualified!T;
    static if (isStringBuf!U)
        *cast(StringBuf*) output = StringBuf.create(allocator);
    else static if (isStringHashMap!U)
    {
        U created = U.create(allocator);
        moveEmplace(created, *cast(U*) output);
    }
    else static if (isOption!U)
        initializeOwnedValue(allocator, &(*output).storage());
    else static if (isArray!U)
    {
        U created = U.create(allocator);
        moveEmplace(created, *cast(U*) output);
    }
    else static if (isFixedArray!U)
        foreach (index; 0 .. output.length)
            initializeOwnedValue(allocator, &(*output)[index]);
    else static if (isSerdeStruct!U)
                {
                static foreach (index; 0 .. U.tupleof.length)
                    initializeOwnedValue(allocator, &output.tupleof[index]);
            }
}

package(xtb.serde) void deinitOwnedValue(T)(T* value)
{
    alias U = Unqualified!T;
    static if (isOption!U)
    {
        // Direct serde decoding initializes Option storage before the payload
        // has necessarily decoded far enough to become `Some`. Clean the
        // storage regardless of the logical tag so partial values cannot leak.
        deinitOwnedValue(&(*value).storage());
    }
    else static if (isStringBuf!U || isOwnedString!U ||
        isStringHashMap!U || isArray!U)
    {
        static if (needsDeinit!U)
        {
            deinitValue(*value);
            static if (hasElaborateDestructor!U)
            {
                U empty;
                moveEmplace(empty, *value);
            }
        }
    }
    else static if (isFixedArray!U)
    {
        size_t index = value.length;
        while (index != 0)
            deinitOwnedValue(&(*value)[--index]);
    }
    else static if (isSerdeStruct!U)
    {
        static if (needsDeinit!U)
            deinitValue(*value);
        else
            static foreach_reverse (index; 0 .. U.tupleof.length)
            deinitOwnedValue(&value.tupleof[index]);
        static if (hasElaborateDestructor!U)
        {
            U empty;
            moveEmplace(empty, *value);
        }
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
        fieldOmitPredicateCount!(T, index) +
        fieldAdapterCount!(T, index);

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
    static assert(fieldAdapterCount!(T, index) <= 1,
        "a serde field may have at most one @withSerde");
    static assert(fieldDefaultValueCount!(T, index) == 0 ||
            !hasElaborateDestructor!(
                Unqualified!F),
        "@defaultValue currently requires a field without an elaborate destructor");
    static assert(fieldDefaultValueCount!(T, index) == 0 || !flattened,
        "@defaultValue cannot be combined with @flatten");
    static assert(fieldOmitPredicateCount!(T, index) == 0 ||
            fieldAttributeCount!(T, index, OmitDefault) == 0,
        "@omitIf cannot be combined with @omitDefault");
    static assert(fieldAdapterCount!(T, index) == 0 || !flattened,
        "@withSerde cannot be combined with @flatten");
    static assert(ignored || fieldAdapterCount!(T, index) != 0 ||
            isSupportedValue!F,
        "unsupported serde field type: " ~ F.stringof);
    static if (fieldAdapterCount!(T, index) != 0)
    {
        alias Adapter = FieldAdapter!(T, index);
        static assert(__traits(hasMember, Adapter, "Representation"),
            "serde adapter must declare Representation");
        static if (__traits(hasMember, Adapter, "Representation"))
        {
            alias Representation = Adapter.Representation;
            static assert(isAdapterRepresentation!Representation,
                "serde adapter Representation must be a scalar or String");
            static if (is(Unqualified!Representation == enum))
                validateEnumSchema!Representation();
            static assert(__traits(compiles,
                    Adapter.encode(*cast(const(F)*) null,
                    cast(Representation*) null)),
                "serde adapter must define encode(const ref field, Representation*)");
            static assert(__traits(compiles,
                    Adapter.decode(*cast(const(Representation)*) null,
                    cast(Allocator*) null, cast(F*) null)),
                "serde adapter must define decode(const ref Representation, Allocator*, field*)");
            static if (__traits(compiles,
                    Adapter.encode(*cast(const(F)*) null,
                    cast(Representation*) null)))
                static assert(is(typeof(Adapter.encode(
                        *cast(const(F)*) null,
                        cast(Representation*) null)) == SerdeErrorKind),
                    "serde adapter encode must return SerdeErrorKind");
            static if (__traits(compiles,
                    Adapter.decode(*cast(const(Representation)*) null,
                    cast(Allocator*) null, cast(F*) null)))
                static assert(is(typeof(Adapter.decode(
                        *cast(const(Representation)*) null,
                        cast(Allocator*) null, cast(F*) null)) == SerdeErrorKind),
                    "serde adapter decode must return SerdeErrorKind");
        }
    }
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
    else static if (!ignored && fieldAdapterCount!(T, index) == 0)
        validateValueSchema!F();
}
