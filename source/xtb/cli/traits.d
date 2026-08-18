module xtb.cli.traits;

nothrow @nogc:

import xtb.cli.attributes;
import xtb.cli.value : CliValueError;
import xtb.core.array : Array;
import xtb.core.lifetime : hasDDestructor, needsFinalization;
import xtb.core.memory : Allocator;
import xtb.core.option : Option;
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

template FieldSymbol(T, size_t index)
{
    alias U = Unqualified!T;
    enum name = __traits(identifier, U.tupleof[index]);
    alias FieldSymbol = __traits(getMember, U, name);
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

private template isParseWithAttribute(alias attribute)
{
    static if (__traits(compiles, typeof(attribute).isCliParseWith))
        enum isParseWithAttribute = typeof(attribute).isCliParseWith;
    else
        enum isParseWithAttribute = false;
}

private size_t fieldParseWithCount(T, size_t index)() pure @safe
{
    size_t result;
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        static if (isParseWithAttribute!attribute)
            ++result;
    return result;
}

enum fieldHasParseWith(T, size_t index) = fieldParseWithCount!(T, index)() != 0;

template FieldValueParser(T, size_t index)
{
    static assert(fieldParseWithCount!(T, index)() == 1,
        T.stringof ~ "." ~ __traits(identifier, FieldSymbol!(T, index)) ~
            " must have exactly one @parseWith attribute");
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        static if (isParseWithAttribute!attribute)
            alias FieldValueParser = typeof(attribute).parser;
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
    static if (!fieldHasParseWith!(T, index))
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
    static assert(fieldAttributeCount!(T, index, LongName) <= 1,
        "CLI field has multiple @longName attributes");
    static if (fieldHas!(T, index, LongName))
        enum String fieldLongName = fieldAttribute!(T, index, LongName)().value;
    else
        enum String fieldLongName = normalizedIdentifier!(
                __traits(identifier, FieldSymbol!(T, index)));
}

template fieldShortName(T, size_t index)
{
    static assert(fieldAttributeCount!(T, index, ShortName) <= 1,
        "CLI field has multiple @shortName attributes");
    static if (fieldHas!(T, index, ShortName))
        enum char fieldShortName = fieldAttribute!(T, index, ShortName)().value;
    else
        enum char fieldShortName = '\0';
}

template fieldHelp(T, size_t index)
{
    static assert(fieldAttributeCount!(T, index, Help) <= 1,
        "CLI field has multiple @help attributes");
    static if (fieldHas!(T, index, Help))
        enum String fieldHelp = fieldAttribute!(T, index, Help)().text;
    else
        enum String fieldHelp = "";
}

template fieldValueName(T, size_t index)
{
    static assert(fieldAttributeCount!(T, index, ValueName) <= 1,
        "CLI field has multiple @valueName attributes");
    static if (fieldHas!(T, index, ValueName))
        enum String fieldValueName = fieldAttribute!(T, index, ValueName)().value;
    else
        enum String fieldValueName = upperValueName!(fieldLongName!(T, index));
}

template commandName(T)
{
    alias U = Unqualified!T;
    static assert(symbolAttributeCount!(U, Command)() == 1,
        U.stringof ~ " used as a subcommand must have exactly one @command(...) attribute");
    enum String commandName = symbolAttribute!(U, Command)().name;
}

template typeAbout(T)
{
    alias U = Unqualified!T;
    static assert(symbolAttributeCount!(U, About)() <= 1,
        U.stringof ~ " has multiple @about attributes");
    static if (symbolAttributeCount!(U, About)() == 1)
        enum String typeAbout = symbolAttribute!(U, About)().text;
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
        NoBuiltinHelp)() == 0;

enum builtinVersionEnabled(T) = cliVersionOf!T.length != 0 &&
    symbolAttributeCount!(Unqualified!T, NoBuiltinVersion)() == 0;

private enum CliSubcommandPolicy : ubyte
{
    required,
    optional,
    help,
}

private enum subcommandPolicy(T) = () {
    alias U = Unqualified!T;
    static if (symbolAttributeCount!(U, SubcommandOptional)() != 0)
        return CliSubcommandPolicy.optional;
    else static if (symbolAttributeCount!(U, HelpOnNoSubcommand)() != 0)
        return CliSubcommandPolicy.help;
    else
        return CliSubcommandPolicy.required;
}();

enum subcommandIsOptional(T) = subcommandPolicy!T == CliSubcommandPolicy.optional;
enum helpOnMissingSubcommand(T) = subcommandPolicy!T == CliSubcommandPolicy.help;

private bool cliFieldNeedsAllocator(T, size_t index)() pure @safe
{
    static if (fieldHasParseWith!(T, index))
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
    static foreach (index; 0 .. U.tupleof.length)
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
    static if (fieldHas!(T, index, Count))
        return false;
    else static if (!isOption!Field && !isArray!Field && is(Unqualified!Field == bool))
        return false;
    else
        return true;
}

enum cliFieldTakesValue(T, size_t index) = fieldTakesValue!(T, index)();

private bool validateField(Root, T, size_t index)() pure @safe
{
    alias Field = FieldType!(T, index);
    alias Value = CliValueType!Field;
    enum sourceName = __traits(identifier, FieldSymbol!(T, index));

    static assert(fieldParseWithCount!(T, index)() <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @parseWith attributes");
    static if (fieldHasParseWith!(T, index))
    {
        alias Parser = FieldValueParser!(T, index);
        enum parserTarget = cliFieldParserTarget!(T, index);
        static assert(parserTarget != CliFieldParserTarget.ambiguous,
            T.stringof ~ "." ~ sourceName ~
                " @parseWith parser is ambiguous between the field and element types");
        static assert(parserTarget != CliFieldParserTarget.invalid,
            T.stringof ~ "." ~ sourceName ~
                " @parseWith parser must be nothrow @nogc and parse either " ~
                Field.stringof ~ " or its Option/Array element type using " ~
                "CliValueError(scope String, T*) or " ~
                "CliValueError(scope String, Allocator*, T*)");
        static assert(!fieldHas!(T, index, Count),
            T.stringof ~ "." ~ sourceName ~ " @parseWith cannot be combined with @count");
        static if (cliFieldParserParsesWholeField!(T, index))
            alias ParsedValue = Unqualified!Field;
        else
            alias ParsedValue = Value;
        static assert(!hasDDestructor!ParsedValue,
            T.stringof ~ "." ~ sourceName ~
                " @parseWith value types with D destructor semantics are not supported");
        static if (is(Unqualified!Field == bool) && !fieldHas!(T, index, Positional))
            static assert(false,
                T.stringof ~ "." ~ sourceName ~
                    " @parseWith cannot be used with a named bool presence flag");
        static if (isOption!Field && is(Unqualified!Value == bool))
            static assert(false,
                T.stringof ~ "." ~ sourceName ~
                    " Option!bool CLI fields are not supported yet");
        static if (cliFieldParserParsesElement!(T, index) && isArray!Field &&
            is(Unqualified!Value == bool))
            static assert(false,
                T.stringof ~ "." ~ sourceName ~
                    " repeated Array!bool CLI fields are not supported");
    }
    else
        static assert(isCliFieldType!Field,
            T.stringof ~ "." ~ sourceName ~ " has unsupported CLI field type " ~ Field.stringof);
    static assert(fieldAttributeCount!(T, index, Positional) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @positional attributes");
    static assert(fieldAttributeCount!(T, index, Required) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @required attributes");
    static assert(fieldAttributeCount!(T, index, Count) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @count attributes");
    static assert(fieldAttributeCount!(T, index, Global) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @global attributes");
    static assert(fieldAttributeCount!(T, index, Rest) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @rest attributes");
    static assert(fieldAttributeCount!(T, index, Hidden) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @hidden attributes");
    static assert(fieldAttributeCount!(T, index, Terminal) <= 1,
        T.stringof ~ "." ~ sourceName ~ " has duplicate @terminal attributes");

    static if (fieldHas!(T, index, Terminal))
    {
        static assert(!fieldHas!(T, index, Positional),
            T.stringof ~ "." ~ sourceName ~ " @terminal cannot be positional");
        static assert(!fieldHas!(T, index, Count),
            T.stringof ~ "." ~ sourceName ~ " @terminal cannot be combined with @count");
        static assert(!isArray!Field,
            T.stringof ~ "." ~ sourceName ~ " @terminal cannot be used with Array fields");
    }

    static if (fieldHas!(T, index, Count))
    {
        static assert(__traits(isIntegral, Unqualified!Field) &&
                !is(Unqualified!Field == bool),
            T.stringof ~ "." ~ sourceName ~ " @count requires an integral field");
        static assert(!fieldHas!(T, index, Positional),
            T.stringof ~ "." ~ sourceName ~ " @count cannot be positional");
    }
    static if (fieldHas!(T, index, Global))
        static assert(!fieldHas!(T, index, Positional),
            T.stringof ~ "." ~ sourceName ~ " @global cannot be positional");
    static if (fieldHas!(T, index, Rest))
    {
        static assert(fieldHas!(T, index, Positional),
            T.stringof ~ "." ~ sourceName ~ " @rest requires @positional");
        static assert(cliFieldIsRepeated!(T, index),
            T.stringof ~ "." ~ sourceName ~ " @rest requires a repeated Array!T field");
    }
    static if (fieldHas!(T, index, Positional))
    {
        static assert(fieldShortName!(T, index) == '\0' &&
                !fieldHas!(T, index, LongName),
            T.stringof ~ "." ~ sourceName ~ " positional fields cannot have option names");
        static if (cliFieldIsRepeated!(T, index))
            static assert(fieldHas!(T, index, Rest),
                T.stringof ~ "." ~ sourceName ~
                    " repeated positional Array fields require @rest");
    }
    else
    {
        enum longName = fieldLongName!(T, index);
        static assert(longName.length != 0,
            T.stringof ~ "." ~ sourceName ~ " has an empty long option name");
        static if (builtinHelpEnabled!Root)
            static assert(longName != "help",
                T.stringof ~ "." ~ sourceName ~ " conflicts with built-in --help");
        enum shortName = fieldShortName!(T, index);
        static if (builtinHelpEnabled!Root)
            static assert(shortName != 'h',
                T.stringof ~ "." ~ sourceName ~ " conflicts with built-in -h");
        static assert(shortName == '\0' ||
                ((shortName >= 'a' && shortName <= 'z') ||
                    (shortName >= 'A' && shortName <= 'Z') ||
                    (shortName >= '0' && shortName <= '9')),
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
    static if (!fieldHas!(T, leftIndex, Positional) &&
        !fieldHas!(T, rightIndex, Positional))
    {
        enum leftLong = fieldLongName!(T, leftIndex);
        enum rightLong = fieldLongName!(T, rightIndex);
        enum leftShort = fieldShortName!(T, leftIndex);
        enum rightShort = fieldShortName!(T, rightIndex);
        static assert(leftLong != rightLong,
            T.stringof ~ " has duplicate long option '--" ~ leftLong ~ "'");
        static if (leftShort != '\0' && rightShort != '\0')
            static assert(leftShort != rightShort,
                T.stringof ~ " has duplicate short option names");
    }
    return true;
}

private bool validateOptionUniquenessAt(T, size_t leftIndex)() pure @safe
{
    static foreach (rightIndex; leftIndex + 1 .. T.tupleof.length)
        static assert(validateOptionPair!(T, leftIndex, rightIndex)());
    return true;
}

private bool hasOptionalPositionalBefore(T, size_t index)() pure @safe
{
    bool result;
    static foreach (candidate; 0 .. index)
    {
        static if (fieldHas!(T, candidate, Positional))
        {
            alias Field = FieldType!(T, candidate);
            static if (isOption!Field && !fieldHas!(T, candidate, Required))
                result = true;
        }
    }
    return result;
}

private bool hasRestBefore(T, size_t index)() pure @safe
{
    bool result;
    static foreach (candidate; 0 .. index)
        static if (fieldHas!(T, candidate, Positional) &&
            fieldHas!(T, candidate, Rest))
            result = true;
    return result;
}

private bool validateChildAt(T, size_t leftIndex)() pure @safe
{
    alias Children = CommandTypes!T;
    alias Left = Children[leftIndex];
    alias LeftU = Unqualified!Left;
    static assert(is(LeftU == struct),
        T.stringof ~ " child command " ~ LeftU.stringof ~ " must be a struct");
    enum leftName = commandName!LeftU;
    static assert(leftName.length != 0,
        LeftU.stringof ~ " has an empty command name");
    static foreach (rightIndex; leftIndex + 1 .. Children.length)
        static assert(leftName != commandName!(Unqualified!(Children[rightIndex])),
            T.stringof ~ " has duplicate subcommand name '" ~ leftName ~ "'");
    return true;
}

private bool validatePositionalOrderingAt(T, size_t index)() pure @safe
{
    static if (fieldHas!(T, index, Positional))
    {
        alias Field = FieldType!(T, index);
        static assert(!hasRestBefore!(T, index)(),
            T.stringof ~ " has a positional after its @rest field");
        static if (!isOption!Field && !fieldHas!(T, index, Rest))
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
    static if (!fieldHas!(Unqualified!Child, childIndex, Positional))
    {
        enum parentLong = fieldLongName!(Parent, globalIndex);
        enum parentShort = fieldShortName!(Parent, globalIndex);
        enum childLong = fieldLongName!(Unqualified!Child, childIndex);
        enum childShort = fieldShortName!(Unqualified!Child, childIndex);

        static assert(parentLong != childLong,
            Unqualified!Child.stringof ~ " option '--" ~ childLong ~
                "' conflicts with inherited global option '--" ~ parentLong ~ "'");
        static if (parentShort != '\0' && childShort != '\0')
            static assert(parentShort != childShort,
                Unqualified!Child.stringof ~
                    " has a short option that conflicts with an inherited global option");
    }
    return true;
}

private bool validateGlobalAgainstSubtree(Parent, size_t globalIndex, Child)()
pure @safe
{
    static foreach (index; 0 .. Unqualified!Child.tupleof.length)
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
    static if (fieldHas!(T, index, Global))
        static foreach (Child; CommandTypes!T)
            static assert(validateGlobalAgainstSubtree!(T, index, Unqualified!Child)());
    return true;
}

private bool validateRootVersionAt(T, size_t index)() pure @safe
{
    static if (builtinVersionEnabled!T && !fieldHas!(T, index, Positional))
        static assert(fieldLongName!(T, index) != "version",
            T.stringof ~ " declares both built-in --version and a --version option");
    return true;
}

private bool validateCommand(Root, T)() pure @safe
{
    alias U = Unqualified!T;
    static assert(is(U == struct), U.stringof ~ " CLI argument type must be a struct");
    static assert(__traits(compiles, () { U value; }),
        U.stringof ~ " CLI argument type must be default-constructible");

    static if (is(U == Unqualified!Root))
    {
        static assert(symbolAttributeCount!(U, CliVersion)() <= 1,
            U.stringof ~ " has multiple @cliVersion attributes");
        static assert(symbolAttributeCount!(U, NoBuiltinHelp)() <= 1,
            U.stringof ~ " has duplicate @noBuiltinHelp attributes");
        static assert(symbolAttributeCount!(U, NoBuiltinVersion)() <= 1,
            U.stringof ~ " has duplicate @noBuiltinVersion attributes");
    }
    else
    {
        static assert(symbolAttributeCount!(U, CliVersion)() == 0,
            U.stringof ~ " @cliVersion is only valid on the root CLI argument type");
        static assert(symbolAttributeCount!(U, NoBuiltinHelp)() == 0,
            U.stringof ~ " @noBuiltinHelp is only valid on the root CLI argument type");
        static assert(symbolAttributeCount!(U, NoBuiltinVersion)() == 0,
            U.stringof ~ " @noBuiltinVersion is only valid on the root CLI argument type");
    }

    static assert(symbolAttributeCount!(U, SubcommandOptional)() <= 1,
        U.stringof ~ " has duplicate @subcommandOptional attributes");
    static assert(symbolAttributeCount!(U, HelpOnNoSubcommand)() <= 1,
        U.stringof ~ " has duplicate @helpOnNoSubcommand attributes");
    static assert(!(symbolAttributeCount!(U, SubcommandOptional)() != 0 &&
            symbolAttributeCount!(U, HelpOnNoSubcommand)() != 0),
        U.stringof ~ " cannot use both @subcommandOptional and @helpOnNoSubcommand");
    static if (!hasSubcommands!U)
    {
        static assert(symbolAttributeCount!(U, SubcommandOptional)() == 0,
            U.stringof ~ " @subcommandOptional is only valid on commands with subcommands");
        static assert(symbolAttributeCount!(U, HelpOnNoSubcommand)() == 0,
            U.stringof ~ " @helpOnNoSubcommand is only valid on commands with subcommands");
    }

    static foreach (index; 0 .. U.tupleof.length)
        static assert(validateField!(Root, U, index)());

    static if (hasSubcommands!U)
    {
        static foreach (index; 0 .. U.tupleof.length)
            static assert(!fieldHas!(U, index, Positional),
                U.stringof ~ " cannot declare positional arguments while it has subcommands");

        static foreach (leftIndex; 0 .. CommandTypes!U.length)
            static assert(validateChildAt!(U, leftIndex)());
    }

    static foreach (leftIndex; 0 .. U.tupleof.length)
        static assert(validateOptionUniquenessAt!(U, leftIndex)());

    static foreach (index; 0 .. U.tupleof.length)
        static assert(validatePositionalOrderingAt!(U, index)());

    static foreach (index; 0 .. U.tupleof.length)
        static assert(validateGlobalCollisionsAt!(U, index)());

    static foreach (Child; CommandTypes!U)
        static assert(validateCommand!(Root, Unqualified!Child)());
    return true;
}

private bool validateCliSchema(T)() pure @safe
{
    alias U = Unqualified!T;
    static assert(validateCommand!(U, U)());
    static foreach (index; 0 .. U.tupleof.length)
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
