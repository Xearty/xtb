module xtb.cli.traits;

nothrow @nogc:

import xtb.cli.attributes;
import xtb.cli.value : CliValueError;
import xtb.core.array : Array;
import xtb.core.lifetime : hasDDestructor, needsFinalization;
import xtb.core.memory : Allocator;
import xtb.core.option : Option;
import xtb.core.print : Writer;
import xtb.core.types : String;

private alias AliasSeq(T...) = T;

template Unqualified(T)
{
    alias Unqualified = typeof(cast() T.init);
}

/// Compile-time list of direct child command argument types.
struct CliCommands(Children...)
{
    enum isCliCommands = true;
    alias Types = AliasSeq!Children;
}

private bool containsAttribute(A, Attributes...)(Attributes attributes)
pure @safe
{
    bool result;
    static foreach (attribute; attributes)
        static if (__traits(compiles, typeof(attribute)))
            static if (is(typeof(attribute) == A))
                result = true;
    return result;
}

private size_t countAttribute(A, Attributes...)(Attributes attributes)
pure @safe
{
    size_t result;
    static foreach (attribute; attributes)
        static if (__traits(compiles, typeof(attribute)))
            static if (is(typeof(attribute) == A))
                ++result;
    return result;
}

template RawFieldSymbol(T, size_t index)
{
    alias U = Unqualified!T;
    enum name = __traits(identifier, U.tupleof[index]);
    alias RawFieldSymbol = __traits(getMember, U, name);
}

template RawFieldType(T, size_t index)
{
    alias RawFieldType = typeof(Unqualified!T.tupleof[index]);
}

enum rawFieldHas(T, size_t index, A) = containsAttribute!A(
        __traits(getAttributes, RawFieldSymbol!(T, index)),
    );

enum rawFieldAttributeCount(T, size_t index, A) = countAttribute!A(
        __traits(getAttributes, RawFieldSymbol!(T, index)),
    );

private struct CliFieldPath(Indices...)
{
    alias indices = AliasSeq!Indices;
}

private template PrependFieldPath(size_t head, Path)
{
    template Impl(Indices...)
    {
        alias Impl = CliFieldPath!(head, Indices);
    }

    alias PrependFieldPath = Impl!(Path.indices);
}

private template PrependFieldPaths(size_t head, Paths...)
{
    static if (Paths.length == 0)
        alias PrependFieldPaths = AliasSeq!();
    else
        alias PrependFieldPaths = AliasSeq!(
            PrependFieldPath!(head, Paths[0]),
            PrependFieldPaths!(head, Paths[1 .. $]),
        );
}

private template CliFieldPathsFrom(T, size_t rawIndex)
{
    alias U = Unqualified!T;
    static if (rawIndex == U.tupleof.length)
        alias CliFieldPathsFrom = AliasSeq!();
    else static if (rawFieldHas!(U, rawIndex, CliFlatten))
    {
        alias Nested = Unqualified!(RawFieldType!(U, rawIndex));
        static if (is(Nested == struct))
            alias CliFieldPathsFrom = AliasSeq!(
                PrependFieldPaths!(rawIndex, CliFieldPaths!Nested),
                CliFieldPathsFrom!(U, rawIndex + 1),
            );
        else
            alias CliFieldPathsFrom = AliasSeq!(
                CliFieldPath!rawIndex,
                CliFieldPathsFrom!(U, rawIndex + 1),
            );
    }
    else
        alias CliFieldPathsFrom = AliasSeq!(
            CliFieldPath!rawIndex,
            CliFieldPathsFrom!(U, rawIndex + 1),
        );
}

template CliFieldPaths(T)
{
    alias CliFieldPaths = CliFieldPathsFrom!(Unqualified!T, 0);
}

enum cliFieldCount(T) = CliFieldPaths!(Unqualified!T).length;

private template FieldOwnerAtPath(T, size_t head, Rest...)
{
    alias U = Unqualified!T;
    static if (Rest.length == 0)
        alias FieldOwnerAtPath = U;
    else
        alias FieldOwnerAtPath = FieldOwnerAtPath!(
            Unqualified!(RawFieldType!(U, head)),
            Rest,
        );
}

private template fieldLeafIndexAtPath(size_t head, Rest...)
{
    static if (Rest.length == 0)
        enum size_t fieldLeafIndexAtPath = head;
    else
        enum size_t fieldLeafIndexAtPath = fieldLeafIndexAtPath!Rest;
}

template FieldPath(T, size_t index)
{
    alias FieldPath = CliFieldPaths!(Unqualified!T)[index];
}

template FieldOwner(T, size_t index)
{
    alias Path = FieldPath!(T, index);
    alias FieldOwner = FieldOwnerAtPath!(Unqualified!T, Path.indices);
}

template fieldLeafIndex(T, size_t index)
{
    alias Path = FieldPath!(T, index);
    enum size_t fieldLeafIndex = fieldLeafIndexAtPath!(Path.indices);
}

template FieldSymbol(T, size_t index)
{
    alias FieldSymbol = RawFieldSymbol!(FieldOwner!(T, index), fieldLeafIndex!(T, index));
}

template FieldType(T, size_t index)
{
    alias FieldType = RawFieldType!(FieldOwner!(T, index), fieldLeafIndex!(T, index));
}

enum fieldHas(T, size_t index, A) = containsAttribute!A(
        __traits(getAttributes, FieldSymbol!(T, index)),
    );

enum fieldAttributeCount(T, size_t index, A) = countAttribute!A(
        __traits(getAttributes, FieldSymbol!(T, index)),
    );

ref auto cliFieldRefAtDepth(Path, size_t depth, T)(ref T value) pure @system
{
    enum size_t fieldIndex = Path.indices[depth];
    static if (depth + 1 == Path.indices.length)
        return value.tupleof[fieldIndex];
    else
        return cliFieldRefAtDepth!(Path, depth + 1)(value.tupleof[fieldIndex]);
}

ref auto cliFieldRef(T, size_t index)(ref T value) pure @system
{
    alias Path = FieldPath!(T, index);
    return cliFieldRefAtDepth!(Path, 0)(value);
}

private size_t symbolAttributeCount(alias Symbol, A)() pure @safe
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

private A symbolAttribute(alias Symbol, A)() pure @safe
{
    static assert(symbolAttributeCount!(Symbol, A)() == 1,
        Symbol.stringof ~ " must have exactly one " ~ A.stringof ~ " attribute");
    static foreach (attribute; __traits(getAttributes, Symbol))
        static if (__traits(compiles, typeof(attribute)))
            static if (is(typeof(attribute) == A))
                return attribute;
    assert(false);
}

private A fieldAttribute(T, size_t index, A)() pure @safe
{
    alias Symbol = FieldSymbol!(T, index);
    static assert(fieldAttributeCount!(T, index, A) == 1,
        T.stringof ~ "." ~ __traits(identifier, Symbol) ~
            " must have exactly one " ~ A.stringof ~ " attribute");
    static foreach (attribute; __traits(getAttributes, Symbol))
        static if (__traits(compiles, typeof(attribute)))
            static if (is(typeof(attribute) == A))
                return attribute;
    assert(false);
}

private auto fieldAliasNamesStorage(T, size_t fieldIndex)() pure @safe
{
    String[fieldAttributeCount!(T, fieldIndex, CliAliasName)] result;
    size_t aliasIndex;
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, fieldIndex)))
        static if (__traits(compiles, typeof(attribute)))
            static if (is(typeof(attribute) == CliAliasName))
                result[aliasIndex++] = attribute.value;
    return result;
}

private auto fieldShortAliasesStorage(T, size_t fieldIndex)() pure @safe
{
    char[fieldAttributeCount!(T, fieldIndex, CliShortAlias)] result;
    size_t aliasIndex;
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, fieldIndex)))
        static if (__traits(compiles, typeof(attribute)))
            static if (is(typeof(attribute) == CliShortAlias))
                result[aliasIndex++] = attribute.value;
    return result;
}

private auto commandAliasNamesStorage(T)() pure @safe
{
    alias U = Unqualified!T;
    String[symbolAttributeCount!(U, CliAliasName)()] result;
    size_t aliasIndex;
    static foreach (attribute; __traits(getAttributes, U))
        static if (__traits(compiles, typeof(attribute)))
            static if (is(typeof(attribute) == CliAliasName))
                result[aliasIndex++] = attribute.value;
    return result;
}

private template isValueWithAttribute(alias attribute)
{
    static if (__traits(compiles, typeof(attribute).isCliValueWith))
        enum isValueWithAttribute = typeof(attribute).isCliValueWith;
    else
        enum isValueWithAttribute = false;
}

private template isPossibleValuesAttribute(alias attribute)
{
    static if (__traits(compiles, typeof(attribute).isCliPossibleValues))
        enum isPossibleValuesAttribute = typeof(attribute).isCliPossibleValues;
    else
        enum isPossibleValuesAttribute = false;
}

private size_t fieldPossibleValuesCount(T, size_t index)() pure @safe
{
    size_t result;
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        static if (isPossibleValuesAttribute!attribute)
            ++result;
    return result;
}

enum fieldHasPossibleValues(T, size_t index) =
    fieldPossibleValuesCount!(T, index)() != 0;

template FieldPossibleValues(T, size_t index)
{
    static assert(fieldPossibleValuesCount!(T, index)() == 1,
        T.stringof ~ "." ~ __traits(identifier, FieldSymbol!(T, index)) ~
            " must have exactly one @cliPossibleValues attribute");
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        static if (isPossibleValuesAttribute!attribute)
            alias FieldPossibleValues = typeof(attribute).values;
}

private size_t fieldValueWithCount(T, size_t index)() pure @safe
{
    size_t result;
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        static if (isValueWithAttribute!attribute)
            ++result;
    return result;
}

enum fieldHasValueWith(T, size_t index) = fieldValueWithCount!(T, index)() != 0;

template FieldValueRepresentation(T, size_t index)
{
    static assert(fieldValueWithCount!(T, index)() == 1,
        T.stringof ~ "." ~ __traits(identifier, FieldSymbol!(T, index)) ~
            " must have exactly one @cliValueWith attribute");
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        static if (isValueWithAttribute!attribute)
            alias FieldValueRepresentation = typeof(attribute).representation;
}

template FieldValueParser(T, size_t index)
{
    alias Representation = FieldValueRepresentation!(T, index);
    static assert(__traits(hasMember, Representation, "parse"),
        T.stringof ~ "." ~ __traits(identifier, FieldSymbol!(T, index)) ~
            " @cliValueWith representation must define static parse");
    alias FieldValueParser = __traits(getMember, Representation, "parse");
}

enum fieldHasDefault(T, size_t index) = fieldHas!(T, index, CliDefault);
enum fieldHasDefaultInput(T, size_t index) = fieldHas!(T, index, CliDefaultInput);
enum fieldHidesDefault(T, size_t index) = fieldHas!(T, index, CliHideDefault);

template fieldDefaultInput(T, size_t index)
{
    static assert(fieldAttributeCount!(T, index, CliDefaultInput) == 1,
        T.stringof ~ "." ~ __traits(identifier, FieldSymbol!(T, index)) ~
            " must have exactly one @cliDefaultInput attribute");
    enum String fieldDefaultInput = fieldAttribute!(T, index, CliDefaultInput)().value;
}

private template ParserOverloads(alias operation)
{
    static if (__traits(compiles,
            __traits(getOverloads, __traits(parent, operation), __traits(identifier, operation))))
        alias ParserOverloads = __traits(getOverloads,
            __traits(parent, operation), __traits(identifier, operation));
    else
        alias ParserOverloads = AliasSeq!operation;
}

private template ParserFunctionType(alias operation)
{
    static if (is(typeof(&operation) Function : Function*) && is(Function == function))
        alias ParserFunctionType = Function;
    else
        alias ParserFunctionType = void;
}

private template ParserParameters(alias operation)
{
    static if (is(ParserFunctionType!operation Parameters == function))
        alias ParserParameters = Parameters;
    else
        alias ParserParameters = AliasSeq!();
}

private template ParserReturnType(alias operation)
{
    static if (is(ParserFunctionType!operation Return == return))
        alias ParserReturnType = Return;
    else
        alias ParserReturnType = void;
}

private bool parserHasFunctionAttribute(alias operation, string wanted)() pure @safe
{
    static foreach (attribute; __traits(getFunctionAttributes, operation))
        if (attribute == wanted)
            return true;
    return false;
}

private bool parserParameterIsScope(alias operation, size_t index)() pure @safe
{
    static if (is(ParserFunctionType!operation == void))
        return false;
    else
    {
        static foreach (storageClass; __traits(getParameterStorageClasses, typeof(&operation), index))
            if (storageClass == "scope")
                return true;
        return false;
    }
}

private bool functionParameterIsRef(alias operation, size_t index)() pure @safe
{
    static if (is(ParserFunctionType!operation == void))
        return false;
    else
    {
        static foreach (storageClass; __traits(getParameterStorageClasses, typeof(&operation), index))
            if (storageClass == "ref")
                return true;
        return false;
    }
}

private enum cliFormatterIsValid(alias Formatter, T) = () {
    alias Value = Unqualified!T;
    alias Parameters = ParserParameters!Formatter;
    static if (!is(ParserReturnType!Formatter == void) ||
        !parserHasFunctionAttribute!(Formatter, "nothrow")() ||
        !parserHasFunctionAttribute!(Formatter, "@nogc")() ||
        Parameters.length != 2)
        return false;
    else
        return is(Parameters[0] == Writer) &&
            functionParameterIsRef!(Formatter, 0)() &&
            (is(Parameters[1] == const(Value)*) ||
                    is(Parameters[1] == const(Value*))) &&
            parserParameterIsScope!(Formatter, 1)();
}();

enum cliRepresentationHasFormatter(Representation, T) = () {
    static if (!__traits(hasMember, Representation, "format"))
        return false;
    else
    {
        alias Formatter = __traits(getMember, Representation, "format");
        return cliFormatterIsValid!(Formatter, T);
    }
}();

private enum parserHasCommonContract(alias Parser) =
    is(ParserReturnType!Parser == CliValueError) &&
    parserHasFunctionAttribute!(Parser, "nothrow")() &&
    parserHasFunctionAttribute!(Parser, "@nogc")() &&
    ParserParameters!Parser.length != 0 &&
    is(ParserParameters!Parser[0] == String) &&
    parserParameterIsScope!(Parser, 0)();

private enum cliParserCandidateWithoutAllocator(alias Parser, T) = () {
    alias Value = Unqualified!T;
    alias Parameters = ParserParameters!Parser;
    static if (!parserHasCommonContract!Parser || Parameters.length != 2)
        return false;
    else
        return is(Parameters[1] == Value*);
}();

private enum cliParserCandidateWithAllocator(alias Parser, T) = () {
    alias Value = Unqualified!T;
    alias Parameters = ParserParameters!Parser;
    static if (!parserHasCommonContract!Parser || Parameters.length != 3)
        return false;
    else
        return is(Parameters[1] == Allocator*) && is(Parameters[2] == Value*);
}();

private size_t cliParserWithoutAllocatorCount(alias Parser, T)() pure @safe
{
    size_t result;
    static foreach (Candidate; ParserOverloads!Parser)
        static if (cliParserCandidateWithoutAllocator!(Candidate, T))
            ++result;
    return result;
}

private size_t cliParserWithAllocatorCount(alias Parser, T)() pure @safe
{
    size_t result;
    static foreach (Candidate; ParserOverloads!Parser)
        static if (cliParserCandidateWithAllocator!(Candidate, T))
            ++result;
    return result;
}

enum cliParserMatchCount(alias Parser, T) = cliParserWithoutAllocatorCount!(Parser, T)() +
    cliParserWithAllocatorCount!(Parser, T)();

enum cliParserIsValid(alias Parser, T) = cliParserMatchCount!(Parser, T) != 0;

enum cliParserIsAmbiguous(alias Parser, T) = cliParserMatchCount!(Parser, T) > 1;

enum cliParserNeedsAllocator(alias Parser, T) =
    cliParserWithAllocatorCount!(Parser, T)() == 1 &&
    cliParserWithoutAllocatorCount!(Parser, T)() == 0;

private enum CliFieldParserTarget : ubyte
{
    invalid,
    field,
    element,
    ambiguous,
}

enum isOption(T) = is(Unqualified!T == Option!Element, Element);

template OptionElement(T)
{
    static if (is(Unqualified!T == Option!Element, Element))
        alias OptionElement = Element;
    else
        static assert(false, T.stringof ~ " is not an Option");
}

enum isArray(T) = is(Unqualified!T == Array!Element, Element);

template ArrayElement(T)
{
    static if (is(Unqualified!T == Array!Element, Element))
        alias ArrayElement = Element;
    else
        static assert(false, T.stringof ~ " is not an Array");
}

template CliValueType(T)
{
    static if (isOption!T)
        alias CliValueType = OptionElement!T;
    else static if (isArray!T)
        alias CliValueType = ArrayElement!T;
    else
        alias CliValueType = Unqualified!T;
}

private enum cliFieldParserTarget(T, size_t index) = () {
    static if (!fieldHasValueWith!(T, index))
        return CliFieldParserTarget.invalid;
    else
    {
        alias Field = Unqualified!(FieldType!(T, index));
        alias Value = CliValueType!Field;
        alias Parser = FieldValueParser!(T, index);
        enum parsesField = cliParserIsValid!(Parser, Field);
        enum fieldAmbiguous = cliParserIsAmbiguous!(Parser, Field);
        static if (isOption!Field || isArray!Field)
        {
            enum parsesElement = cliParserIsValid!(Parser, Value);
            enum elementAmbiguous = cliParserIsAmbiguous!(Parser, Value);
        }
        else
        {
            enum parsesElement = false;
            enum elementAmbiguous = false;
        }

        static if (fieldAmbiguous || elementAmbiguous ||
            (parsesField && parsesElement))
            return CliFieldParserTarget.ambiguous;
        else static if (parsesField)
            return CliFieldParserTarget.field;
        else static if (parsesElement)
            return CliFieldParserTarget.element;
        else
            return CliFieldParserTarget.invalid;
    }
}();

enum cliFieldParserParsesWholeField(T, size_t index) =
    cliFieldParserTarget!(T, index) == CliFieldParserTarget.field;

enum cliFieldParserParsesElement(T, size_t index) =
    cliFieldParserTarget!(T, index) == CliFieldParserTarget.element;

enum cliFieldIsRepeated(T, size_t index) = isArray!(FieldType!(T, index)) &&
    !cliFieldParserParsesWholeField!(T, index);

private bool cliFieldParserNeedsAllocator(T, size_t index)() pure @safe
{
    alias Field = Unqualified!(FieldType!(T, index));
    alias Value = CliValueType!Field;
    alias Parser = FieldValueParser!(T, index);
    static if (cliFieldParserParsesWholeField!(T, index))
        return cliParserNeedsAllocator!(Parser, Field);
    else static if (cliFieldParserParsesElement!(T, index))
        return cliParserNeedsAllocator!(Parser, Value);
    else
        return false;
}

enum isCliScalar(T) = is(Unqualified!T == String) ||
    is(Unqualified!T == bool) || __traits(isIntegral, Unqualified!T) ||
    is(Unqualified!T == enum);

enum isCliFieldType(T) = isCliScalar!(CliValueType!T) &&
    !(isOption!T && is(OptionElement!T == bool));

template CommandTypes(T)
{
    alias U = Unqualified!T;
    static if (__traits(hasMember, U, "Commands"))
    {
        alias Commands = __traits(getMember, U, "Commands");
        static assert(__traits(hasMember, Commands, "isCliCommands") &&
                Commands.isCliCommands,
            U.stringof ~ ".Commands must alias CliCommands!(...)");
        alias CommandTypes = Commands.Types;
    }
    else
        alias CommandTypes = AliasSeq!();
}

enum hasSubcommands(T) = CommandTypes!T.length != 0;

enum isDirectCommand(Parent, Child) = () {
    bool result;
    static foreach (Candidate; CommandTypes!Parent)
        static if (is(Unqualified!Candidate == Unqualified!Child))
            result = true;
    return result;
}();

enum directCommandIndex(Parent, Child) = () {
    size_t result = size_t.max;
    static foreach (index, Candidate; CommandTypes!Parent)
        static if (is(Unqualified!Candidate == Unqualified!Child))
            result = index;
    return result;
}();

private struct NameStorage(size_t capacity)
{
    char[capacity] data;
    size_t length;
}

private auto normalizedIdentifierStorage(string input)() pure @safe
{
    NameStorage!(input.length * 2 + 1) result;
    bool previousWasSeparator = true;
    foreach (index, codeUnit; input)
    {
        if (codeUnit == '_')
        {
            if (result.length != 0 && result.data[result.length - 1] != '-')
                result.data[result.length++] = '-';
            previousWasSeparator = true;
            continue;
        }
        if (codeUnit >= 'A' && codeUnit <= 'Z')
        {
            if (index != 0 && !previousWasSeparator && result.length != 0 &&
                result.data[result.length - 1] != '-')
                result.data[result.length++] = '-';
            result.data[result.length++] = cast(char)(codeUnit - 'A' + 'a');
            previousWasSeparator = false;
            continue;
        }
        result.data[result.length++] = codeUnit;
        previousWasSeparator = codeUnit == '-';
    }
    while (result.length != 0 && result.data[result.length - 1] == '-')
        --result.length;
    return result;
}

template normalizedIdentifier(string input)
{
    enum storage = normalizedIdentifierStorage!input();
    enum String normalizedIdentifier = storage.data[0 .. storage.length];
}

private auto upperValueNameStorage(string input)() pure @safe
{
    NameStorage!(input.length + 1) result;
    foreach (codeUnit; input)
    {
        if (codeUnit == '-')
            result.data[result.length++] = '_';
        else if (codeUnit >= 'a' && codeUnit <= 'z')
            result.data[result.length++] = cast(char)(codeUnit - 'a' + 'A');
        else
            result.data[result.length++] = codeUnit;
    }
    return result;
}

template upperValueName(string input)
{
    enum storage = upperValueNameStorage!input();
    enum String upperValueName = storage.data[0 .. storage.length];
}

template fieldLongName(T, size_t index)
{
    static assert(fieldAttributeCount!(T, index, CliLongName) <= 1,
        "CLI field has multiple @cliLongName attributes");
    static if (fieldHas!(T, index, CliLongName))
        enum String fieldLongName = fieldAttribute!(T, index, CliLongName)().value;
    else
        enum String fieldLongName = normalizedIdentifier!(
                __traits(identifier, FieldSymbol!(T, index)));
}

template fieldLongAliases(T, size_t index)
{
    enum String[] fieldLongAliases = fieldAliasNamesStorage!(T, index)();
}

private auto fieldAllLongNamesStorage(T, size_t index)() pure @safe
{
    String[1 + fieldLongAliases!(T, index).length] result;
    result[0] = fieldLongName!(T, index);
    static foreach (aliasIndex, aliasName; fieldLongAliases!(T, index))
        result[1 + aliasIndex] = aliasName;
    return result;
}

template fieldAllLongNames(T, size_t index)
{
    enum String[] fieldAllLongNames = fieldAllLongNamesStorage!(T, index)();
}

private auto negativeLongNameStorage(T, size_t index)() pure @safe
{
    enum canonical = fieldLongName!(T, index);
    NameStorage!(canonical.length + 3) result;
    result.data[0 .. 3] = "no-";
    result.length = 3;
    foreach (codeUnit; canonical)
        result.data[result.length++] = codeUnit;
    return result;
}

template fieldNegativeLongName(T, size_t index)
{
    static if (fieldHas!(T, index, CliNegatable))
    {
        enum storage = negativeLongNameStorage!(T, index)();
        enum String fieldNegativeLongName = storage.data[0 .. storage.length];
    }
    else
        enum String fieldNegativeLongName = "";
}

private auto fieldAllRecognizedLongNamesStorage(T, size_t index)() pure @safe
{
    enum negatable = fieldHas!(T, index, CliNegatable);
    String[fieldAllLongNames!(T, index).length + (negatable ? 1 : 0)] result;
    static foreach (nameIndex, name; fieldAllLongNames!(T, index))
        result[nameIndex] = name;
    static if (negatable)
        result[$ - 1] = fieldNegativeLongName!(T, index);
    return result;
}

template fieldAllRecognizedLongNames(T, size_t index)
{
    enum String[] fieldAllRecognizedLongNames =
        fieldAllRecognizedLongNamesStorage!(T, index)();
}

template fieldShortName(T, size_t index)
{
    static assert(fieldAttributeCount!(T, index, CliShortName) <= 1,
        "CLI field has multiple @cliShortName attributes");
    static if (fieldHas!(T, index, CliShortName))
        enum char fieldShortName = fieldAttribute!(T, index, CliShortName)().value;
    else
        enum char fieldShortName = '\0';
}

template fieldShortAliases(T, size_t index)
{
    enum char[] fieldShortAliases = fieldShortAliasesStorage!(T, index)();
}

private auto fieldAllShortNamesStorage(T, size_t index)() pure @safe
{
    enum hasCanonical = fieldShortName!(T, index) != '\0';
    char[(hasCanonical ? 1 : 0) + fieldShortAliases!(T, index).length] result;
    static if (hasCanonical)
        result[0] = fieldShortName!(T, index);
    static foreach (aliasIndex, aliasName; fieldShortAliases!(T, index))
        result[(hasCanonical ? 1 : 0) + aliasIndex] = aliasName;
    return result;
}

template fieldAllShortNames(T, size_t index)
{
    enum char[] fieldAllShortNames = fieldAllShortNamesStorage!(T, index)();
}

template fieldHelp(T, size_t index)
{
    static assert(fieldAttributeCount!(T, index, CliHelp) <= 1,
        "CLI field has multiple @cliHelp attributes");
    static if (fieldHas!(T, index, CliHelp))
        enum String fieldHelp = fieldAttribute!(T, index, CliHelp)().text;
    else
        enum String fieldHelp = "";
}

template fieldValueName(T, size_t index)
{
    static assert(fieldAttributeCount!(T, index, CliValueName) <= 1,
        "CLI field has multiple @cliValueName attributes");
    static if (fieldHas!(T, index, CliValueName))
        enum String fieldValueName = fieldAttribute!(T, index, CliValueName)().value;
    else
        enum String fieldValueName = upperValueName!(fieldLongName!(T, index));
}

private auto fieldExplicitPossibleValuesStorage(T, size_t index)() pure @safe
{
    alias Values = FieldPossibleValues!(T, index);
    String[Values.length] result;
    static foreach (valueIndex, value; Values)
    {
        static assert(is(typeof(value) : String),
            "@cliPossibleValues arguments must be strings");
        result[valueIndex] = value;
    }
    return result;
}

template fieldExplicitPossibleValues(T, size_t index)
{
    static if (fieldHasPossibleValues!(T, index))
        enum String[] fieldExplicitPossibleValues =
            fieldExplicitPossibleValuesStorage!(T, index)();
    else
        enum String[] fieldExplicitPossibleValues = [];
}

private auto enumCliNamesStorage(T)() pure @safe
{
    alias U = Unqualified!T;
    String[__traits(allMembers, U).length] result;
    static foreach (index, member; __traits(allMembers, U))
        result[index] = enumCliName!(U, member);
    return result;
}

template enumCliNames(T)
{
    alias U = Unqualified!T;
    static assert(is(U == enum), U.stringof ~ " must be an enum");
    enum String[] enumCliNames = enumCliNamesStorage!U();
}

private String enumCliNameForValue(T)(T value) pure @safe
{
    alias U = Unqualified!T;
    String result;
    static foreach (member; __traits(allMembers, U))
    {
        if (result.length == 0 && value == __traits(getMember, U, member))
            result = enumCliName!(U, member);
    }
    return result;
}

enum fieldIsRequired(T, size_t index) = () {
    alias Field = Unqualified!(FieldType!(T, index));

    static if (isOption!Field || isArray!Field ||
        fieldHasDefault!(T, index) || fieldHasDefaultInput!(T, index) ||
        fieldHas!(T, index, CliCount) || fieldHas!(T, index, CliRest) ||
        fieldHas!(T, index, CliTerminal))
        return false;
    else static if (is(Field == bool) &&
        !fieldHas!(T, index, CliNegatable) &&
        !fieldHas!(T, index, CliPositional))
        return false;
    else
        return true;
}();

private auto fieldDefaultValueStorage(T, size_t index)() pure @system
{
    Unqualified!T defaults = Unqualified!T.init;
    return cliFieldRef!(Unqualified!T, index)(defaults);
}

enum fieldDefaultValue(T, size_t index) = fieldDefaultValueStorage!(T, index)();

enum fieldHasHelpDefault(T, size_t index) =
    (fieldHasDefault!(T, index) || fieldHasDefaultInput!(T, index)) &&
    !fieldHidesDefault!(T, index) && !fieldHas!(T, index, CliHidden);

private enum normalWriterCanFormat(T) = __traits(compiles, {
        Writer writer;
        Unqualified!T value;
        writer.value(value);
    });

enum fieldSemanticDefaultCanFormat(T, size_t index) = () {
    alias Field = Unqualified!(FieldType!(T, index));
    static if (is(Field == enum) || isCliScalar!Field)
        return true;
    else static if (fieldHasValueWith!(T, index))
    {
        alias Representation = FieldValueRepresentation!(T, index);
        return cliRepresentationHasFormatter!(Representation, Field) ||
            normalWriterCanFormat!Field;
    }
    else
        return normalWriterCanFormat!Field;
}();

template fieldAutomaticEnumDefaultName(T, size_t index)
{
    alias Field = Unqualified!(FieldType!(T, index));
    static assert(is(Field == enum));
    enum String fieldAutomaticEnumDefaultName =
        enumCliNameForValue!Field(fieldDefaultValue!(T, index));
}

template fieldHelpPossibleValues(T, size_t index)
{
    alias Field = FieldType!(T, index);
    alias Value = CliValueType!Field;
    static if (fieldHasPossibleValues!(T, index))
        enum String[] fieldHelpPossibleValues = fieldExplicitPossibleValues!(T, index);
    else static if (!fieldHasValueWith!(T, index) && is(Unqualified!Value == enum))
        enum String[] fieldHelpPossibleValues = enumCliNames!(Unqualified!Value);
    else
        enum String[] fieldHelpPossibleValues = [];
}

template commandName(T)
{
    alias U = Unqualified!T;
    static assert(symbolAttributeCount!(U, CliCommand)() == 1,
        U.stringof ~ " used as a subcommand must have exactly one @cliCommand(...) attribute");
    enum String commandName = symbolAttribute!(U, CliCommand)().name;
}

template commandAliases(T)
{
    enum String[] commandAliases = commandAliasNamesStorage!T();
}

private auto commandAllNamesStorage(T)() pure @safe
{
    String[1 + commandAliases!T.length] result;
    result[0] = commandName!T;
    static foreach (aliasIndex, aliasName; commandAliases!T)
        result[1 + aliasIndex] = aliasName;
    return result;
}

template commandAllNames(T)
{
    enum String[] commandAllNames = commandAllNamesStorage!(T)();
}

template typeAbout(T)
{
    alias U = Unqualified!T;
    static assert(symbolAttributeCount!(U, CliAbout)() <= 1,
        U.stringof ~ " has multiple @cliAbout attributes");
    static if (symbolAttributeCount!(U, CliAbout)() == 1)
        enum String typeAbout = symbolAttribute!(U, CliAbout)().text;
    else
        enum String typeAbout = "";
}

template typeVersion(T)
{
    alias U = Unqualified!T;
    static assert(symbolAttributeCount!(U, CliVersion)() <= 1,
        U.stringof ~ " has multiple @cliVersion attributes");
    static if (symbolAttributeCount!(U, CliVersion)() == 1)
        enum String typeVersion = symbolAttribute!(U, CliVersion)().value;
    else
        enum String typeVersion = "";
}

/// Returns the application version metadata attached to a CLI root type.
enum String cliVersionOf(T) = typeVersion!T;

enum builtinHelpEnabled(T) = symbolAttributeCount!(Unqualified!T,
        CliNoBuiltinHelp)() == 0;

enum builtinVersionEnabled(T) = cliVersionOf!T.length != 0 &&
    symbolAttributeCount!(Unqualified!T, CliNoBuiltinVersion)() == 0;

private enum CliSubcommandPolicy : ubyte
{
    required,
    optional,
    help,
}

private enum subcommandPolicy(T) = () {
    alias U = Unqualified!T;
    static if (symbolAttributeCount!(U, CliSubcommandOptional)() != 0)
        return CliSubcommandPolicy.optional;
    else static if (symbolAttributeCount!(U, CliHelpOnNoSubcommand)() != 0)
        return CliSubcommandPolicy.help;
    else
        return CliSubcommandPolicy.required;
}();

enum subcommandIsOptional(T) = subcommandPolicy!T == CliSubcommandPolicy.optional;
enum helpOnMissingSubcommand(T) = subcommandPolicy!T == CliSubcommandPolicy.help;

private bool cliFieldNeedsAllocator(T, size_t index)() pure @safe
{
    static if (fieldHasValueWith!(T, index))
    {
        static if (cliFieldParserParsesWholeField!(T, index))
            return cliFieldParserNeedsAllocator!(T, index)();
        else static if (cliFieldIsRepeated!(T, index))
            return true;
        else
            return cliFieldParserNeedsAllocator!(T, index)();
    }
    else static if (cliFieldIsRepeated!(T, index))
        return true;
    else
        return false;
}

enum cliNeedsAllocator(T) = () {
    alias U = Unqualified!T;
    bool result;
    static foreach (index; 0 .. cliFieldCount!U)
        static if (cliFieldNeedsAllocator!(U, index)())
            result = true;
    static foreach (Child; CommandTypes!U)
        static if (cliNeedsAllocator!Child)
            result = true;
    return result;
}();

private bool fieldTakesValue(T, size_t index)() pure @safe
{
    alias Field = FieldType!(T, index);
    static if (fieldHas!(T, index, CliCount) || fieldHas!(T, index, CliNegatable))
        return false;
    else static if (!isOption!Field && !isArray!Field && is(Unqualified!Field == bool))
        return false;
    else
        return true;
}

enum cliFieldTakesValue(T, size_t index) = fieldTakesValue!(T, index)();

private String firstDuplicateString(scope const(String)[] values) pure @safe
{
    foreach (leftIndex, left; values)
        foreach (rightIndex; leftIndex + 1 .. values.length)
            if (left == values[rightIndex])
                return left;
    return null;
}

private char firstDuplicateChar(scope const(char)[] values) pure @safe
{
    foreach (leftIndex, left; values)
        foreach (rightIndex; leftIndex + 1 .. values.length)
            if (left == values[rightIndex])
                return left;
    return '\0';
}

private String firstOverlap(
    scope const(String)[] left,
    scope const(String)[] right,
) pure @safe
{
    foreach (leftValue; left)
        foreach (rightValue; right)
            if (leftValue == rightValue)
                return leftValue;
    return null;
}

private char firstOverlap(
    scope const(char)[] left,
    scope const(char)[] right,
) pure @safe
{
    foreach (leftValue; left)
        foreach (rightValue; right)
            if (leftValue == rightValue)
                return leftValue;
    return '\0';
}

private bool hasLongOptionDelimiter(scope String name) pure @safe
{
    foreach (codeUnit; name)
        if (codeUnit == '=')
            return true;
    return false;
}

private bool isCliAttribute(alias attribute)() pure @safe
{
    static if (isPossibleValuesAttribute!attribute || isValueWithAttribute!attribute)
        return true;
    else static if (__traits(compiles, typeof(attribute)))
    {
        alias A = typeof(attribute);
        return is(A == CliCommand) || is(A == CliAbout) || is(A == CliVersion) ||
            is(A == CliNoBuiltinHelp) || is(A == CliNoBuiltinVersion) ||
            is(A == CliHelp) || is(A == CliLongName) || is(A == CliAliasName) ||
            is(A == CliShortName) || is(A == CliShortAlias) || is(A == CliValueName) ||
            is(A == CliPositional) || is(A == CliFlatten) || is(A == CliDefault) ||
            is(A == CliDefaultInput) || is(A == CliHideDefault) || is(A == CliCount) ||
            is(A == CliGlobal) || is(A == CliRest) || is(A == CliHidden) ||
            is(A == CliNegatable) || is(A == CliTerminal) ||
            is(A == CliSubcommandOptional) || is(A == CliHelpOnNoSubcommand);
    }
    else
        return false;
}

private bool flattenFieldHasUnsupportedCliAttribute(T, size_t index)() pure @safe
{
    bool result;
    static foreach (attribute; __traits(getAttributes, RawFieldSymbol!(T, index)))
        static if (isCliAttribute!attribute())
            static if (!is(typeof(attribute) == CliFlatten))
                result = true;
    return result;
}

private bool flattenTypeHasCliAttribute(T)() pure @safe
{
    bool result;
    static foreach (attribute; __traits(getAttributes, Unqualified!T))
        static if (isCliAttribute!attribute())
            result = true;
    return result;
}

private bool validateFlattenFields(T)() pure @safe
{
    alias U = Unqualified!T;
    static foreach (index; 0 .. U.tupleof.length)
    {
        static assert(rawFieldAttributeCount!(U, index, CliFlatten) <= 1,
            U.stringof ~ "." ~ __traits(identifier, RawFieldSymbol!(U, index)) ~
                " has duplicate @cliFlatten attributes");
        static if (rawFieldHas!(U, index, CliFlatten))
        {
            alias Nested = Unqualified!(RawFieldType!(U, index));
            static assert(is(Nested == struct),
                U.stringof ~ "." ~ __traits(identifier, RawFieldSymbol!(U, index)) ~
                    " @cliFlatten requires a direct struct-valued field");
            static assert(!flattenFieldHasUnsupportedCliAttribute!(U, index)(),
                U.stringof ~ "." ~ __traits(identifier, RawFieldSymbol!(U, index)) ~
                    " @cliFlatten cannot be combined with other CLI field attributes");
            static if (is(Nested == struct))
                static assert(validateFlattenGroup!Nested());
        }
    }
    return true;
}

private bool validateFlattenGroup(T)() pure @safe
{
    alias U = Unqualified!T;
    static assert(is(U == struct), U.stringof ~ " flattened CLI group must be a struct");
    static assert(!hasSubcommands!U,
        U.stringof ~ " flattened CLI group cannot declare CliCommands");
    static assert(!flattenTypeHasCliAttribute!U(),
        U.stringof ~ " flattened CLI group cannot declare CLI type attributes");

    static assert(validateFlattenFields!U());
    return true;
}

private bool validateField(Root, T, size_t index)() pure @safe
{
    alias Field = FieldType!(T, index);
    alias Value = CliValueType!Field;
    enum sourceName = __traits(identifier, FieldSymbol!(T, index));

    static assert(fieldValueWithCount!(T, index)() <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliValueWith attributes");
    static if (fieldHasValueWith!(T, index))
    {
        alias Parser = FieldValueParser!(T, index);
        enum parserTarget = cliFieldParserTarget!(T, index);
        static assert(parserTarget != CliFieldParserTarget.ambiguous,
            T.stringof ~ "." ~ sourceName ~
                " @cliValueWith parser is ambiguous between the field and element types");
        static assert(parserTarget != CliFieldParserTarget.invalid,
            T.stringof ~ "." ~ sourceName ~
                " @cliValueWith parser must be nothrow @nogc and parse either " ~
                Field.stringof ~ " or its Option/Array element type using " ~
                "CliValueError(scope String, T*) or " ~
                "CliValueError(scope String, Allocator*, T*)");
        static assert(!fieldHas!(T, index, CliCount),
            T.stringof ~ "." ~ sourceName ~ " @cliValueWith cannot be combined with @cliCount");
        static if (cliFieldParserParsesWholeField!(T, index))
            alias ParsedValue = Unqualified!Field;
        else
            alias ParsedValue = Value;
        static assert(!hasDDestructor!ParsedValue,
            T.stringof ~ "." ~ sourceName ~
                " @cliValueWith value types with D destructor semantics are not supported");
        alias Representation = FieldValueRepresentation!(T, index);
        static if (__traits(hasMember, Representation, "format"))
            static assert(cliRepresentationHasFormatter!(Representation, ParsedValue),
                T.stringof ~ "." ~ sourceName ~
                    " @cliValueWith format must be " ~
                    "void format(ref Writer, scope const " ~ ParsedValue.stringof ~
                    "*) nothrow @nogc");
        static if (is(Unqualified!Field == bool) &&
            !fieldHas!(T, index, CliPositional) &&
            !fieldHas!(T, index, CliNegatable))
            static assert(false,
                T.stringof ~ "." ~ sourceName ~
                    " @cliValueWith cannot be used with a named bool presence flag");
        static if (isOption!Field && is(Unqualified!Value == bool) &&
            !fieldHas!(T, index, CliNegatable))
            static assert(false,
                T.stringof ~ "." ~ sourceName ~
                    " Option!bool CLI fields are not supported yet");
        static if (cliFieldParserParsesElement!(T, index) && isArray!Field &&
            is(Unqualified!Value == bool))
            static assert(false,
                T.stringof ~ "." ~ sourceName ~
                    " repeated Array!bool CLI fields are not supported");
    }
    else static if (!(fieldHas!(T, index, CliNegatable) && isOption!Field &&
            is(Unqualified!Value == bool)))
        static assert(isCliFieldType!Field,
            T.stringof ~ "." ~ sourceName ~ " has unsupported CLI field type " ~ Field.stringof);
    static assert(fieldAttributeCount!(T, index, CliPositional) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliPositional attributes");
    static assert(fieldAttributeCount!(T, index, CliDefault) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliDefault attributes");
    static assert(fieldAttributeCount!(T, index, CliDefaultInput) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliDefaultInput attributes");
    static assert(fieldAttributeCount!(T, index, CliHideDefault) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliHideDefault attributes");
    static assert(fieldAttributeCount!(T, index, CliCount) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliCount attributes");
    static assert(fieldAttributeCount!(T, index, CliGlobal) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliGlobal attributes");
    static assert(fieldAttributeCount!(T, index, CliRest) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliRest attributes");
    static assert(fieldAttributeCount!(T, index, CliHidden) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliHidden attributes");
    static assert(fieldAttributeCount!(T, index, CliNegatable) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliNegatable attributes");
    static assert(fieldAttributeCount!(T, index, CliTerminal) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliTerminal attributes");
    static assert(fieldPossibleValuesCount!(T, index)() <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @cliPossibleValues attributes");

    enum hasSemanticDefault = fieldHasDefault!(T, index);
    enum hasInputDefault = fieldHasDefaultInput!(T, index);
    enum hasAnyDefault = hasSemanticDefault || hasInputDefault;
    static assert(!(hasSemanticDefault && hasInputDefault),
        T.stringof ~ "." ~ sourceName ~
            " cannot combine @cliDefault with @cliDefaultInput");
    static if (fieldHidesDefault!(T, index))
        static assert(hasAnyDefault,
            T.stringof ~ "." ~ sourceName ~
                " @cliHideDefault requires @cliDefault or @cliDefaultInput");
    static if (hasAnyDefault)
    {
        static assert(!isOption!Field,
            T.stringof ~ "." ~ sourceName ~
                " defaults cannot be used with Option fields");
        static assert(!isArray!Field,
            T.stringof ~ "." ~ sourceName ~
                " defaults cannot be used with repeated Array fields");
        static assert(!fieldHas!(T, index, CliCount),
            T.stringof ~ "." ~ sourceName ~
                " defaults cannot be combined with @cliCount");
        static assert(!fieldHas!(T, index, CliTerminal),
            T.stringof ~ "." ~ sourceName ~
                " defaults cannot be combined with @cliTerminal");
        static if (is(Unqualified!Field == bool) &&
            !fieldHas!(T, index, CliNegatable) &&
            !fieldHas!(T, index, CliPositional))
            static assert(false,
                T.stringof ~ "." ~ sourceName ~
                    " defaults cannot be used with a bool presence flag");
    }
    static if (hasSemanticDefault && !fieldHidesDefault!(T, index) &&
        !fieldHas!(T, index, CliHidden))
        static assert(fieldSemanticDefaultCanFormat!(T, index),
            T.stringof ~ "." ~ sourceName ~
                " @cliDefault value cannot be formatted for help; " ~
                "provide a cliValueWith formatter or add @cliHideDefault");

    static if (fieldHasPossibleValues!(T, index))
    {
        enum possibleValues = fieldExplicitPossibleValues!(T, index);
        static assert(possibleValues.length != 0,
            T.stringof ~ "." ~ sourceName ~ " @cliPossibleValues cannot be empty");
        static foreach (value; possibleValues)
            static assert(value.length != 0,
                T.stringof ~ "." ~ sourceName ~
                    " @cliPossibleValues cannot contain an empty value");
        enum duplicatePossibleValue = firstDuplicateString(possibleValues);
        static assert(duplicatePossibleValue.length == 0,
            T.stringof ~ "." ~ sourceName ~ " has duplicate possible value '" ~
                duplicatePossibleValue ~ "'");
        static assert(cliFieldTakesValue!(T, index),
            T.stringof ~ "." ~ sourceName ~
                " @cliPossibleValues requires an argument that takes a value");
    }

    static if (!fieldHasValueWith!(T, index) && is(Unqualified!Value == enum))
    {
        enum duplicateEnumValueName = firstDuplicateString(enumCliNames!(Unqualified!Value));
        static assert(duplicateEnumValueName.length == 0,
            T.stringof ~ "." ~ sourceName ~ " enum " ~ Unqualified!Value.stringof ~
                " has duplicate CLI value name '" ~ duplicateEnumValueName ~ "'");
    }
    enum duplicateLongAlias = firstDuplicateString(fieldLongAliases!(T, index));
    static assert(duplicateLongAlias.length == 0,
        T.stringof ~ "." ~ sourceName ~ " has duplicate long option alias '--" ~
            duplicateLongAlias ~ "'");
    enum duplicateShortAlias = firstDuplicateChar(fieldShortAliases!(T, index));
    static assert(duplicateShortAlias == '\0',
        T.stringof ~ "." ~ sourceName ~ " has duplicate short option alias '-" ~
            duplicateShortAlias ~ "'");

    static if (fieldHas!(T, index, CliHidden))
        static assert(!fieldIsRequired!(T, index),
            T.stringof ~ "." ~ sourceName ~
                " @cliHidden cannot be used with a required argument");

    static if (fieldHas!(T, index, CliTerminal))
    {
        static assert(!fieldHas!(T, index, CliPositional),
            T.stringof ~ "." ~ sourceName ~ " @cliTerminal cannot be positional");
        static assert(!fieldHas!(T, index, CliCount),
            T.stringof ~ "." ~ sourceName ~ " @cliTerminal cannot be combined with @cliCount");
        static assert(!isArray!Field,
            T.stringof ~ "." ~ sourceName ~ " @cliTerminal cannot be used with Array fields");
    }

    static if (fieldHas!(T, index, CliNegatable))
    {
        enum isBool = is(Unqualified!Field == bool);
        enum isOptionalBool = isOption!Field && is(Unqualified!Value == bool);
        static assert(isBool || isOptionalBool,
            T.stringof ~ "." ~ sourceName ~
                " @cliNegatable requires bool or Option!bool");
        static assert(!fieldHas!(T, index, CliPositional),
            T.stringof ~ "." ~ sourceName ~ " @cliNegatable cannot be positional");
        static assert(!fieldHas!(T, index, CliCount),
            T.stringof ~ "." ~ sourceName ~
                " @cliNegatable cannot be combined with @cliCount");
        static assert(!fieldHasValueWith!(T, index),
            T.stringof ~ "." ~ sourceName ~
                " @cliNegatable cannot be combined with @cliValueWith");
    }

    static if (fieldHas!(T, index, CliCount))
    {
        static assert(__traits(isIntegral, Unqualified!Field) &&
                !is(Unqualified!Field == bool),
            T.stringof ~ "." ~ sourceName ~ " @cliCount requires an integral field");
        static assert(!fieldHas!(T, index, CliPositional),
            T.stringof ~ "." ~ sourceName ~ " @cliCount cannot be positional");
    }
    static if (fieldHas!(T, index, CliGlobal))
        static assert(!fieldHas!(T, index, CliPositional),
            T.stringof ~ "." ~ sourceName ~ " @cliGlobal cannot be positional");
    static if (fieldHas!(T, index, CliRest))
    {
        static assert(fieldHas!(T, index, CliPositional),
            T.stringof ~ "." ~ sourceName ~ " @cliRest requires @cliPositional");
        static assert(cliFieldIsRepeated!(T, index),
            T.stringof ~ "." ~ sourceName ~ " @cliRest requires a repeated Array!T field");
    }
    static if (fieldHas!(T, index, CliPositional))
    {
        static assert(fieldAttributeCount!(T, index, CliLongName) == 0 &&
                fieldLongAliases!(T, index)
                    .length == 0 &&
                    fieldShortName!(T, index) == '\0' &&
                fieldShortAliases!(T, index)
                    .length == 0,
                T.stringof ~ "." ~ sourceName ~ " positional fields cannot have option names");
        static if (cliFieldIsRepeated!(T, index))
            static assert(fieldHas!(T, index, CliRest),
                T.stringof ~ "." ~ sourceName ~
                    " repeated positional Array fields require @cliRest");
    }
    else
    {
        static foreach (name; fieldAllRecognizedLongNames!(T, index))
        {
            static assert(name.length != 0,
                T.stringof ~ "." ~ sourceName ~ " has an empty long option name");
            static assert(!hasLongOptionDelimiter(name),
                T.stringof ~ "." ~ sourceName ~ " has invalid long option name '--" ~ name ~
                    "': '=' is reserved for attached option values");
        }
        static if (builtinHelpEnabled!Root)
            static foreach (name; fieldAllRecognizedLongNames!(T, index))
                static assert(name != "help",
                    T.stringof ~ "." ~ sourceName ~ " conflicts with built-in --help");
        enum duplicateLongName = firstDuplicateString(
                fieldAllRecognizedLongNames!(T, index));
        static assert(duplicateLongName.length == 0,
            T.stringof ~ " has duplicate long option '--" ~ duplicateLongName ~ "'");
        static if (builtinHelpEnabled!Root)
            static foreach (shortName; fieldAllShortNames!(T, index))
                static assert(shortName != 'h',
                    T.stringof ~ "." ~ sourceName ~ " conflicts with built-in -h");
        enum duplicateShortName = firstDuplicateChar(fieldAllShortNames!(T, index));
        static assert(duplicateShortName == '\0',
            T.stringof ~ " has duplicate short option '-" ~ duplicateShortName ~ "'");
        static foreach (shortName; fieldAllShortNames!(T, index))
            static assert((shortName >= 'a' && shortName <= 'z') ||
                    (shortName >= 'A' && shortName <= 'Z') ||
                    (shortName >= '0' && shortName <= '9'),
                T.stringof ~ "." ~ sourceName ~ " has an invalid short option name");
    }
    static if (isArray!Field)
    {
        static if (cliFieldIsRepeated!(T, index))
            static assert(!is(Unqualified!Value == bool),
                T.stringof ~ "." ~ sourceName ~ " Array!bool CLI fields are not supported");
        static assert(!needsFinalization!Value,
            T.stringof ~ "." ~ sourceName ~
                " Array CLI fields require elements without cleanup obligations");
    }
    return true;
}

private bool validateOptionPair(T, size_t leftIndex, size_t rightIndex)()
pure @safe
{
    static if (!fieldHas!(T, leftIndex, CliPositional) &&
        !fieldHas!(T, rightIndex, CliPositional))
    {
        enum duplicateLongName = firstOverlap(
                fieldAllRecognizedLongNames!(T, leftIndex),
                fieldAllRecognizedLongNames!(T, rightIndex),
            );
        static assert(duplicateLongName.length == 0,
            T.stringof ~ " has duplicate long option '--" ~ duplicateLongName ~ "'");
        enum duplicateShortName = firstOverlap(
                fieldAllShortNames!(T, leftIndex),
                fieldAllShortNames!(T, rightIndex),
            );
        static assert(duplicateShortName == '\0',
            T.stringof ~ " has duplicate short option '-" ~ duplicateShortName ~ "'");
    }
    return true;
}

private bool validateOptionUniquenessAt(T, size_t leftIndex)() pure @safe
{
    static foreach (rightIndex; leftIndex + 1 .. cliFieldCount!T)
        static assert(validateOptionPair!(T, leftIndex, rightIndex)());
    return true;
}

private bool hasOptionalPositionalBefore(T, size_t index)() pure @safe
{
    bool result;
    static foreach (candidate; 0 .. index)
    {
        static if (fieldHas!(T, candidate, CliPositional))
            static if (!fieldIsRequired!(T, candidate))
                result = true;
    }
    return result;
}

private bool hasRestBefore(T, size_t index)() pure @safe
{
    bool result;
    static foreach (candidate; 0 .. index)
        static if (fieldHas!(T, candidate, CliPositional) &&
            fieldHas!(T, candidate, CliRest))
            result = true;
    return result;
}

private bool validateChildPair(T, size_t leftIndex, size_t rightIndex)() pure @safe
{
    alias Children = CommandTypes!T;
    alias Left = Unqualified!(Children[leftIndex]);
    alias Right = Unqualified!(Children[rightIndex]);
    enum duplicateName = firstOverlap(commandAllNames!Left, commandAllNames!Right);
    static assert(duplicateName.length == 0,
        T.stringof ~ " has duplicate subcommand name '" ~ duplicateName ~ "'");
    return true;
}

private bool validateChildAt(T, size_t leftIndex)() pure @safe
{
    alias Children = CommandTypes!T;
    alias Left = Children[leftIndex];
    alias LeftU = Unqualified!Left;
    static assert(is(LeftU == struct),
        T.stringof ~ " child command " ~ LeftU.stringof ~ " must be a struct");
    static foreach (name; commandAllNames!LeftU)
        static assert(name.length != 0,
            LeftU.stringof ~ " has an empty command name");
    enum duplicateCommandName = firstDuplicateString(commandAllNames!LeftU);
    static assert(duplicateCommandName.length == 0,
        LeftU.stringof ~ " has duplicate command name '" ~ duplicateCommandName ~ "'");
    static foreach (rightIndex; leftIndex + 1 .. Children.length)
        static assert(validateChildPair!(T, leftIndex, rightIndex)());
    return true;
}

private bool validatePositionalOrderingAt(T, size_t index)() pure @safe
{
    static if (fieldHas!(T, index, CliPositional))
    {
        static assert(!hasRestBefore!(T, index)(),
            T.stringof ~ " has a positional after its @cliRest field");
        static if (fieldIsRequired!(T, index))
            static assert(!hasOptionalPositionalBefore!(T, index)(),
                T.stringof ~ " has a required positional after an optional positional");
    }
    return true;
}

private bool validateGlobalAgainstField(
    Parent,
    size_t globalIndex,
    Child,
    size_t childIndex,
)() pure @safe
{
    static if (!fieldHas!(Unqualified!Child, childIndex, CliPositional))
    {
        enum duplicateLongName = firstOverlap(
                fieldAllRecognizedLongNames!(Parent, globalIndex),
                fieldAllRecognizedLongNames!(Unqualified!Child, childIndex),
            );
        static assert(duplicateLongName.length == 0,
            Unqualified!Child.stringof ~ " option '--" ~ duplicateLongName ~
                "' conflicts with inherited global option '--" ~ duplicateLongName ~ "'");
        enum duplicateShortName = firstOverlap(
                fieldAllShortNames!(Parent, globalIndex),
                fieldAllShortNames!(Unqualified!Child, childIndex),
            );
        static assert(duplicateShortName == '\0',
            Unqualified!Child.stringof ~ " option '-" ~ duplicateShortName ~
                "' conflicts with inherited global option '-" ~ duplicateShortName ~ "'");
    }
    return true;
}

private bool validateGlobalAgainstSubtree(Parent, size_t globalIndex, Child)()
pure @safe
{
    static foreach (index; 0 .. cliFieldCount!(Unqualified!Child))
        static assert(validateGlobalAgainstField!(
                Parent,
                globalIndex,
                Unqualified!Child,
                index,
        )());

    static foreach (Grandchild; CommandTypes!(Unqualified!Child))
        static assert(validateGlobalAgainstSubtree!(
                Parent,
                globalIndex,
                Unqualified!Grandchild,
        )());
    return true;
}

private bool validateGlobalCollisionsAt(T, size_t index)() pure @safe
{
    static if (fieldHas!(T, index, CliGlobal))
        static foreach (Child; CommandTypes!T)
            static assert(validateGlobalAgainstSubtree!(T, index, Unqualified!Child)());
    return true;
}

private bool validateRootVersionAt(T, size_t index)() pure @safe
{
    static if (builtinVersionEnabled!T && !fieldHas!(T, index, CliPositional))
    {
        enum versionCollision = firstOverlap(
                fieldAllRecognizedLongNames!(T, index),
                ["version"],
            );
        static assert(versionCollision.length == 0,
            T.stringof ~ " declares both built-in --version and option '--" ~
                versionCollision ~ "'");
    }
    return true;
}

private bool validateCommand(Root, T)() pure @safe
{
    alias U = Unqualified!T;
    static assert(is(U == struct), U.stringof ~ " CLI argument type must be a struct");
    static assert(__traits(compiles, () { U value; }),
        U.stringof ~ " CLI argument type must be default-constructible");
    static assert(validateFlattenFields!U());

    static if (is(U == Unqualified!Root))
    {
        static assert(symbolAttributeCount!(U, CliAliasName)() == 0,
            U.stringof ~ " root CLI command cannot declare @cliAliasName");
        static assert(symbolAttributeCount!(U, CliShortAlias)() == 0,
            U.stringof ~ " root CLI command cannot declare @cliShortAlias");
        static assert(symbolAttributeCount!(U, CliVersion)() <= 1,
            U.stringof ~ " has multiple @cliVersion attributes");
        static assert(symbolAttributeCount!(U, CliNoBuiltinHelp)() <= 1,
            U.stringof ~ " has duplicate @cliNoBuiltinHelp attributes");
        static assert(symbolAttributeCount!(U, CliNoBuiltinVersion)() <= 1,
            U.stringof ~ " has duplicate @cliNoBuiltinVersion attributes");
    }
    else
    {
        static assert(symbolAttributeCount!(U, CliCommand)() == 1,
            U.stringof ~ " used as a subcommand must have exactly one @cliCommand(...) attribute");
        static assert(symbolAttributeCount!(U, CliShortAlias)() == 0,
            U.stringof ~ " @cliShortAlias is only valid on named option fields");
        static assert(symbolAttributeCount!(U, CliVersion)() == 0,
            U.stringof ~ " @cliVersion is only valid on the root CLI argument type");
        static assert(symbolAttributeCount!(U, CliNoBuiltinHelp)() == 0,
            U.stringof ~ " @cliNoBuiltinHelp is only valid on the root CLI argument type");
        static assert(symbolAttributeCount!(U, CliNoBuiltinVersion)() == 0,
            U.stringof ~ " @cliNoBuiltinVersion is only valid on the root CLI argument type");
    }

    static assert(symbolAttributeCount!(U, CliSubcommandOptional)() <= 1,
        U.stringof ~ " has duplicate @cliSubcommandOptional attributes");
    static assert(symbolAttributeCount!(U, CliHelpOnNoSubcommand)() <= 1,
        U.stringof ~ " has duplicate @cliHelpOnNoSubcommand attributes");
    static assert(!(symbolAttributeCount!(U, CliSubcommandOptional)() != 0 &&
            symbolAttributeCount!(U, CliHelpOnNoSubcommand)() != 0),
        U.stringof ~ " cannot use both @cliSubcommandOptional and @cliHelpOnNoSubcommand");
    static if (!hasSubcommands!U)
    {
        static assert(symbolAttributeCount!(U, CliSubcommandOptional)() == 0,
            U.stringof ~ " @cliSubcommandOptional is only valid on commands with subcommands");
        static assert(symbolAttributeCount!(U, CliHelpOnNoSubcommand)() == 0,
            U.stringof ~ " @cliHelpOnNoSubcommand is only valid on commands with subcommands");
    }

    static foreach (index; 0 .. cliFieldCount!U)
        static assert(validateField!(Root, U, index)());

    static if (hasSubcommands!U)
    {
        static foreach (index; 0 .. cliFieldCount!U)
            static assert(!fieldHas!(U, index, CliPositional),
                U.stringof ~ " cannot declare positional arguments while it has subcommands");

        static foreach (leftIndex; 0 .. CommandTypes!U.length)
            static assert(validateChildAt!(U, leftIndex)());
    }

    static foreach (leftIndex; 0 .. cliFieldCount!U)
        static assert(validateOptionUniquenessAt!(U, leftIndex)());

    static foreach (index; 0 .. cliFieldCount!U)
        static assert(validatePositionalOrderingAt!(U, index)());

    static foreach (index; 0 .. cliFieldCount!U)
        static assert(validateGlobalCollisionsAt!(U, index)());

    static foreach (Child; CommandTypes!U)
        static assert(validateCommand!(Root, Unqualified!Child)());
    return true;
}

private bool validateCliSchema(T)() pure @safe
{
    alias U = Unqualified!T;
    static assert(validateCommand!(U, U)());
    static foreach (index; 0 .. cliFieldCount!U)
        static assert(validateRootVersionAt!(U, index)());
    return true;
}

template ValidateCliSchema(T)
{
    enum ValidateCliSchema = validateCliSchema!(Unqualified!T)();
}

template enumCliName(T, string member)
{
    enum String enumCliName = normalizedIdentifier!member;
}
