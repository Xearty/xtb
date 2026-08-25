module tests.cli_tests;

nothrow @nogc:

import xtb.cli;
import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.containers.array : Array;
import xtb.core.lifetime : moveAssign;
import xtb.core.memory : Allocator;
import xtb.core.option : Option;
import xtb.core.fmt.writer : Writer;
import xtb.core.types : String;

enum BuildMode
{
    debug_,
    releaseSafe,
    releaseFast,
}

@(cliVersion("2.4.1"), cliAbout("CLI test application"), cliSubcommandOptional)
struct RootArgs
{
    @(cliShortName('v'), cliCount, cliGlobal, cliHelp("Increase verbosity"))
    uint verbose;

    @(cliShortName('C'), cliGlobal, cliValueName("DIR"), cliHelp("Change directory"))
    Option!String directory;

    alias Commands = CliCommands!(BuildArgs, DependencyArgs);
}

@(cliCommand("build"), cliAbout("Build the project"))
struct BuildArgs
{
    @(cliShortName('r'), cliHelp("Build with optimizations"))
    bool release;

    @(cliShortName('j'), cliValueName("N"), cliHelp("Parallel jobs"), cliDefault)
    uint jobs = 1;

    @(cliHelp("Build mode"), cliDefault)
    BuildMode mode = BuildMode.debug_;

    @(cliValueName("PATH"), cliHelp("Output path"))
    String output;
}

@(cliCommand("dependency"), cliAbout("Manage dependencies"), cliSubcommandOptional)
struct DependencyArgs
{
    @(cliValueName("URL"), cliHelp("Registry URL"))
    Option!String registry;

    alias Commands = CliCommands!(DependencyAddArgs, DependencyListArgs);
}

@(cliCommand("add"), cliAbout("Add a dependency"))
struct DependencyAddArgs
{
    @(cliPositional, cliValueName("PACKAGE"))
    String package_;

    @(cliValueName("VERSION"), cliHelp("Dependency version"))
    Option!String version_;
}

@(cliCommand("list"), cliAbout("List dependencies"))
struct DependencyListArgs
{
    @(cliShortName('a'))
    bool all;
}

struct ParentPositionalRootArgs
{
    @(cliPositional, cliValueName("WORKSPACE"), cliHelp("Workspace to operate on"))
    String workspace;

    @(cliShortName('v'), cliCount, cliGlobal)
    uint verbose;

    alias Commands = CliCommands!(ParentPositionalBuildArgs, ParentPositionalTestArgs);
}

@(cliCommand("build"), cliAliasName("b"))
struct ParentPositionalBuildArgs
{
    @(cliPositional, cliValueName("TARGET"))
    String target;

    String output;
}

@cliCommand("test")
struct ParentPositionalTestArgs
{
    bool all;
}

struct ParentPositionalTerminalRootArgs
{
    @(cliPositional, cliValueName("WORKSPACE"))
    String workspace;

    @cliTerminal
    bool done;

    alias Commands = CliCommands!(ParentPositionalTerminalChildArgs);
}

@cliCommand("run")
struct ParentPositionalTerminalChildArgs
{
}

@(cliHelpOnNoSubcommand, cliAbout("Choose a workspace command"))
struct ParentPositionalHelpRootArgs
{
    String config;

    @(cliPositional, cliValueName("WORKSPACE"))
    String workspace;

    alias Commands = CliCommands!(ParentPositionalHelpChildArgs);
}

@cliCommand("run")
struct ParentPositionalHelpChildArgs
{
}

@cliSubcommandOptional
struct OptionalParentPositionalRootArgs
{
    @(cliPositional, cliValueName("WORKSPACE"))
    String workspace;

    alias Commands = CliCommands!(OptionalParentPositionalChildArgs);
}

@cliCommand("run")
struct OptionalParentPositionalChildArgs
{
}

struct ParentPositionalGroup
{
    @(cliPositional, cliValueName("ORG"))
    String organization;

    @(cliPositional, cliValueName("PROJECT"))
    String project;
}

struct FlattenedParentPositionalRootArgs
{
    @cliFlatten
    ParentPositionalGroup context;

    @(cliShortName('v'), cliCount, cliGlobal)
    uint verbose;

    alias Commands = CliCommands!(FlattenedParentPositionalChildArgs);
}

@cliCommand("show")
struct FlattenedParentPositionalChildArgs
{
}

struct NestedParentPositionalRootArgs
{
    @(cliPositional, cliValueName("ORG"))
    String organization;

    alias Commands = CliCommands!(NestedParentPositionalGroupArgs);
}

@cliCommand("project")
struct NestedParentPositionalGroupArgs
{
    @(cliPositional, cliValueName("PROJECT"))
    String project;

    @(cliGlobal, cliShortName('q'))
    bool quiet;

    alias Commands = CliCommands!(NestedParentPositionalLeafArgs);
}

@cliCommand("build")
struct NestedParentPositionalLeafArgs
{
    bool release;
}

struct InvalidDefaultParentPositionalArgs
{
    @(cliPositional, cliDefault)
    uint workspace = 1;

    alias Commands = CliCommands!(InvalidParentPositionalChildArgs);
}

struct InvalidDefaultInputParentPositionalArgs
{
    @(cliPositional, cliDefaultInput("workspace"))
    String workspace;

    alias Commands = CliCommands!(InvalidParentPositionalChildArgs);
}

struct InvalidOptionalParentPositionalArgs
{
    @cliPositional
    Option!String workspace;

    alias Commands = CliCommands!(InvalidParentPositionalChildArgs);
}

struct InvalidRepeatedParentPositionalArgs
{
    @cliPositional
    Array!String workspace;

    alias Commands = CliCommands!(InvalidParentPositionalChildArgs);
}

struct InvalidRestParentPositionalArgs
{
    @(cliPositional, cliRest)
    Array!String workspace;

    alias Commands = CliCommands!(InvalidParentPositionalChildArgs);
}

@cliCommand("child")
struct InvalidParentPositionalChildArgs
{
}

struct RequiredCommandRoot
{
    alias Commands = CliCommands!(RequiredCommandChild);
}

@cliCommand("child")
struct RequiredCommandChild
{
}

@(cliNoBuiltinHelp, cliHelpOnNoSubcommand, cliAbout("Choose a command"))
struct HelpOnMissingRootArgs
{
    String config;

    alias Commands = CliCommands!(HelpOnMissingGroupArgs);
}

@(cliCommand("group"), cliHelpOnNoSubcommand, cliAbout("Choose a group command"))
struct HelpOnMissingGroupArgs
{
    String profile;

    alias Commands = CliCommands!(HelpOnMissingLeafArgs);
}

@cliCommand("run")
struct HelpOnMissingLeafArgs
{
}

@cliSubcommandOptional
struct InvalidOptionalLeafArgs
{
}

@cliHelpOnNoSubcommand
struct InvalidHelpLeafArgs
{
}

@(cliSubcommandOptional, cliHelpOnNoSubcommand)
struct InvalidCombinedPolicyArgs
{
    alias Commands = CliCommands!(InvalidCombinedPolicyChildArgs);
}

@cliCommand("child")
struct InvalidCombinedPolicyChildArgs
{
}

@(cliSubcommandOptional, cliVersion("1.0"))
struct AllocRootArgs
{
    @(cliShortName('v'), cliCount, cliGlobal)
    uint verbose;

    alias Commands = CliCommands!(RunArgs);
}

@cliCommand("run")
struct RunArgs
{
    @(cliShortName('D'), cliValueName("VALUE"))
    Array!String defines;

    @(cliPositional, cliValueName("PROGRAM"))
    String program;

    @(cliPositional, cliRest, cliValueName("ARG"))
    Array!String arguments;
}

@(cliNoBuiltinHelp, cliSubcommandOptional)
struct CustomHelpRootArgs
{
    @(cliShortName('h'))
    bool help;

    alias Commands = CliCommands!(CustomHelpChildArgs);
}

@cliCommand("child")
struct CustomHelpChildArgs
{
    @(cliShortName('h'))
    bool help;
}

@cliNoBuiltinHelp
struct NoBuiltinHelpRootArgs
{
}

@cliNoBuiltinHelp
struct RequiredOnlyHelpArgs
{
    @(cliValueName("OUTPUT"), cliHelp("Output path"))
    String output;
}

@(cliNoBuiltinVersion, cliVersion("9.3.0"))
struct CustomVersionRootArgs
{
    @cliLongName("version")
    Option!String version_;
}

@cliNoBuiltinVersion
struct NoVersionMetadataRootArgs
{
}

enum CompletionShell
{
    bash,
    fish,
}

@cliNoBuiltinHelp
struct TerminalRootArgs
{
    @(cliShortName('v'), cliCount, cliGlobal)
    uint verbose;

    @(cliShortName('h'), cliGlobal, cliTerminal)
    bool help;

    alias Commands = CliCommands!(TerminalBuildArgs);
}

@cliCommand("build")
struct TerminalBuildArgs
{
    String output;

    @(cliTerminal, cliValueName("SHELL"))
    CompletionShell completions;
}

struct TerminalAllocArgs
{
    Array!String item;

    @cliTerminal
    bool done;
}

struct InvalidTerminalPositionalArgs
{
    @(cliPositional, cliTerminal)
    String value;
}

struct InvalidTerminalCountArgs
{
    @(cliCount, cliTerminal)
    uint verbose;
}

struct InvalidTerminalArrayArgs
{
    @cliTerminal
    Array!String values;
}

struct InvalidDuplicateTerminalArgs
{
    @(cliTerminal, cliTerminal)
    bool quit;
}

@cliAliasName("tool")
struct InvalidRootAliasArgs
{
}

struct AliasRootArgs
{
    @(cliShortName('v'), cliShortAlias('V'), cliShortAlias('Q'), cliAliasName("verbosity"),
        cliAliasName("chatty"), cliCount, cliGlobal)
    uint verbose;

    @cliAliasName("colour")
    bool color;

    alias Commands = CliCommands!(AliasRemoveArgs, AliasListArgs);
}

@(cliCommand("remove"), cliAliasName("rm"), cliAliasName("del"), cliAbout("Remove an item"))
struct AliasRemoveArgs
{
    @(cliShortName('f'), cliShortAlias('F'), cliShortAlias('E'), cliAliasName("delete"),
        cliAliasName("erase"))
    bool force;

    @cliAliasName("destination")
    String target;
}

@(cliCommand("list"), cliAliasName("ls"))
struct AliasListArgs
{
}

struct InvalidDuplicateLongAliasArgs
{
    @(cliAliasName("same"), cliAliasName("same"))
    bool value;
}

struct InvalidDuplicateShortAliasArgs
{
    @(cliShortAlias('x'), cliShortAlias('x'))
    bool value;
}

struct InvalidLongNameDelimiterArgs
{
    @cliLongName("foo=bar")
    bool value;
}

struct InvalidLongAliasDelimiterArgs
{
    @cliAliasName("foo=bar")
    bool value;
}

struct InvalidLongAliasCollisionArgs
{
    @(cliAliasName("same"))
    bool first;

    @(cliAliasName("same"))
    bool second;
}

struct InvalidShortAliasCollisionArgs
{
    @(cliShortAlias('x'))
    bool first;

    @(cliShortAlias('x'))
    bool second;
}

struct InvalidAliasGlobalCollisionRootArgs
{
    @(cliGlobal, cliAliasName("config"))
    bool verbose;

    alias Commands = CliCommands!(InvalidAliasGlobalCollisionChildArgs);
}

@cliCommand("child")
struct InvalidAliasGlobalCollisionChildArgs
{
    bool config;
}

struct InvalidPositionalAliasArgs
{
    @(cliPositional, cliAliasName("value"))
    String value;
}

struct InvalidPositionalShortAliasArgs
{
    @(cliPositional, cliShortAlias('v'))
    String value;
}

struct InvalidBuiltinHelpAliasArgs
{
    @cliAliasName("help")
    bool other;
}

struct InvalidBuiltinHelpShortAliasArgs
{
    @cliShortAlias('h')
    bool other;
}

@(cliVersion("1.0"))
struct InvalidBuiltinVersionAliasArgs
{
    @cliAliasName("version")
    bool other;
}

struct InvalidCommandAliasCollisionRootArgs
{
    alias Commands = CliCommands!(InvalidCommandAliasFirstArgs,
        InvalidCommandAliasSecondArgs);
}

@(cliCommand("remove"), cliAliasName("rm"))
struct InvalidCommandAliasFirstArgs
{
}

@(cliCommand("rename"), cliAliasName("rm"))
struct InvalidCommandAliasSecondArgs
{
}

struct InvalidDuplicateCommandAliasRootArgs
{
    alias Commands = CliCommands!(InvalidDuplicateCommandAliasArgs);
}

@(cliCommand("child"), cliAliasName("c"), cliAliasName("c"))
struct InvalidDuplicateCommandAliasArgs
{
}

struct InvalidCommandShortAliasRootArgs
{
    alias Commands = CliCommands!(InvalidCommandShortAliasArgs);
}

@(cliCommand("child"), cliShortAlias('c'))
struct InvalidCommandShortAliasArgs
{
}

@cliNoBuiltinHelp
struct DisabledBuiltinHelpAliasArgs
{
    @(cliAliasName("help"), cliShortAlias('h'))
    bool custom;
}

@(cliNoBuiltinVersion, cliVersion("1.0"))
struct DisabledBuiltinVersionAliasArgs
{
    @cliAliasName("version")
    bool custom;
}

struct NegatableArgs
{
    @(cliNegatable, cliDefault, cliShortName('c'), cliAliasName("colour"),
        cliHelp("Use colored output"))
    bool color;

    @(cliNegatable, cliDefault)
    bool feature = true;

    @cliNegatable
    Option!bool cache;
}

struct RequiredGlobalRootArgs
{
    @(cliGlobal, cliValueName("WORKSPACE"), cliHelp("Workspace root"))
    String workspace;

    alias Commands = CliCommands!(RequiredGlobalChildArgs);
}

@cliCommand("child")
struct RequiredGlobalChildArgs
{
}

struct NegatableGlobalRootArgs
{
    @(cliNegatable, cliGlobal, cliDefault)
    bool color = true;

    alias Commands = CliCommands!(NegatableGlobalChildArgs);
}

@cliCommand("child")
struct NegatableGlobalChildArgs
{
}

struct NegatableTerminalArgs
{
    String output;

    @(cliNegatable, cliTerminal)
    Option!bool diagnostics;
}

struct RequiredNegatableArgs
{
    @cliNegatable
    bool color;
}

struct InvalidPlainOptionalBoolArgs
{
    Option!bool color;
}

struct InvalidNegatableTypeArgs
{
    @cliNegatable
    uint jobs;
}

struct InvalidNegatablePositionalArgs
{
    @(cliNegatable, cliPositional)
    bool color;
}

struct InvalidDuplicateNegatableArgs
{
    @(cliNegatable, cliNegatable)
    bool color;
}

struct InvalidNegatableAliasCollisionArgs
{
    @(cliNegatable, cliAliasName("no-color"))
    bool color;
}

struct InvalidNegatableFieldCollisionArgs
{
    @cliNegatable
    bool color;

    bool noColor;
}

struct InvalidNegatableGlobalCollisionRootArgs
{
    @(cliNegatable, cliGlobal)
    bool color;

    alias Commands = CliCommands!(InvalidNegatableGlobalCollisionChildArgs);
}

@cliCommand("child")
struct InvalidNegatableGlobalCollisionChildArgs
{
    bool noColor;
}

private struct TestCliValue(alias Parser)
{
    alias parse = Parser;
}

struct Port
{
    ushort value;
}

CliValueError parsePort(scope String input, Port* output) nothrow @nogc
{
    if (input == "80")
    {
        output.value = 80;
        return CliValueError.init;
    }
    if (input == "443")
    {
        output.value = 443;
        return CliValueError.init;
    }
    if (input == "70000")
        return CliValueError.outOfRange("port must be between 0 and 65535");
    if (input == "silent")
        return CliValueError.invalid();
    return CliValueError.invalid("expected a numeric port");
}

struct CustomParentPositionalRootArgs
{
    @(cliPositional, cliValueName("PORT"), cliValueWith!(TestCliValue!parsePort))
    Port port;

    alias Commands = CliCommands!(CustomParentPositionalChildArgs);
}

@cliCommand("serve")
struct CustomParentPositionalChildArgs
{
}

CliValueError parseAutomaticJobs(scope String input, uint* output) nothrow @nogc
{
    if (input != "auto")
        return CliValueError.invalid("expected 'auto'");
    *output = 8;
    return CliValueError.init;
}

struct CustomValueArgs
{
    @(cliValueWith!(TestCliValue!parsePort))
    Port port;

    @(cliValueWith!(TestCliValue!parsePort))
    Option!Port optionalPort;

    @(cliValueWith!(TestCliValue!parsePort))
    Array!Port repeatedPort;
}

struct CustomValueNoAllocArgs
{
    @(cliValueWith!(TestCliValue!parsePort))
    Port port;
}

private int hexNibble(char codeUnit) pure @safe
{
    if (codeUnit >= '0' && codeUnit <= '9')
        return codeUnit - '0';
    if (codeUnit >= 'a' && codeUnit <= 'f')
        return codeUnit - 'a' + 10;
    if (codeUnit >= 'A' && codeUnit <= 'F')
        return codeUnit - 'A' + 10;
    return -1;
}

CliValueError parseHexBytes(
    scope String input,
    Allocator* allocator,
    Array!ubyte* output,
) nothrow @nogc
{
    if (input.length % 2 != 0)
        return CliValueError.invalid("expected an even number of hexadecimal digits");

    Array!ubyte decoded = Array!ubyte.create(allocator);
    scope (exit)
        decoded.deinit();
    foreach (offset; 0 .. input.length / 2)
    {
        const high = hexNibble(input[offset * 2]);
        const low = hexNibble(input[offset * 2 + 1]);
        if (high < 0 || low < 0)
            return CliValueError.invalid("expected hexadecimal digits");
        ubyte value = cast(ubyte)((high << 4) | low);
        if (!decoded.tryAppend(&value))
            return CliValueError.allocationFailed("could not store decoded bytes");
    }

    moveAssign(decoded, *output);
    return CliValueError.init;
}

CliValueError parseEmptyBytes(
    scope String input,
    Array!ubyte* output,
) nothrow @nogc
{
    cast(void) output;
    if (input != "empty")
        return CliValueError.invalid("expected 'empty'");
    return CliValueError.init;
}

struct WholeArrayCustomValueArgs
{
    @(cliValueWith!(TestCliValue!parseHexBytes))
    Array!ubyte bytes;
}

struct WholeArrayNoAllocArgs
{
    @(cliValueWith!(TestCliValue!parseEmptyBytes))
    Array!ubyte bytes;
}

CliValueError parseOptionalPort(
    scope String input,
    Option!Port* output,
) nothrow @nogc
{
    if (input == "none")
    {
        *output = Option!Port.none;
        return CliValueError.init;
    }

    Port port;
    const error = parsePort(input, &port);
    if (error.failed)
        return error;
    *output = Option!Port.some(port);
    return CliValueError.init;
}

struct WholeOptionCustomValueArgs
{
    @(cliValueWith!(TestCliValue!parseOptionalPort))
    Option!Port port;
}

struct WholeArrayPositionalArgs
{
    @(cliPositional, cliValueWith!(TestCliValue!parseHexBytes))
    Array!ubyte bytes;
}

struct InvalidWholeArrayRestArgs
{
    @(cliPositional, cliRest, cliValueWith!(TestCliValue!parseHexBytes))
    Array!ubyte bytes;
}

CliValueError parseAmbiguousBytes(
    scope String input,
    ubyte* output,
) nothrow @nogc
{
    cast(void) input;
    cast(void) output;
    return CliValueError.init;
}

CliValueError parseAmbiguousBytes(
    scope String input,
    Allocator* allocator,
    Array!ubyte* output,
) nothrow @nogc
{
    cast(void) input;
    cast(void) allocator;
    cast(void) output;
    return CliValueError.init;
}

struct InvalidAmbiguousCustomParserArgs
{
    @(cliValueWith!(TestCliValue!parseAmbiguousBytes))
    Array!ubyte bytes;
}

struct CustomPositionalValueArgs
{
    @(cliPositional, cliValueWith!(TestCliValue!parsePort))
    Port port;
}

struct OverrideBuiltInValueArgs
{
    @(
        cliAliasName("parallelism"),
        cliValueWith!(TestCliValue!parseAutomaticJobs),
        cliPossibleValues!("auto"),
        cliDefaultInput("auto"),
    )
    uint jobs;
}

struct OwnedParsedValue
{
    Array!String values;
}

CliValueError parseOwnedValue(
    scope String input,
    Allocator* allocator,
    OwnedParsedValue* output,
) nothrow @nogc
{
    Array!String values = Array!String.create(allocator);
    moveAssign(values, output.values);
    String value = input;
    if (!output.values.tryAppend(&value))
        return CliValueError.allocationFailed("could not store parsed value");
    return CliValueError.init;
}

struct AllocatorCustomValueArgs
{
    @(cliValueWith!(TestCliValue!parseOwnedValue))
    Option!OwnedParsedValue value;
}

struct InvalidOwningArrayCustomValueArgs
{
    @(cliValueWith!(TestCliValue!parseOwnedValue))
    Array!OwnedParsedValue value;
}

CliValueError parseBool(scope String input, bool* output) nothrow @nogc
{
    *output = input == "yes";
    return CliValueError.init;
}

CliValueError parsePortWithoutScope(String input, Port* output) nothrow @nogc
{
    return parsePort(input, output);
}

bool parsePortWrongReturn(scope String input, Port* output) nothrow @nogc
{
    cast(void) input;
    cast(void) output;
    return false;
}

struct DestructorParsedValue
{
    ~this()
    {
    }
}

CliValueError parseDestructorValue(
    scope String input,
    DestructorParsedValue* output,
) nothrow @nogc
{
    cast(void) input;
    cast(void) output;
    return CliValueError.init;
}

struct InvalidCustomDestructorArgs
{
    @(cliValueWith!(TestCliValue!parseDestructorValue))
    DestructorParsedValue value;
}

struct InvalidCustomBoolArgs
{
    @(cliValueWith!(TestCliValue!parseBool))
    bool flag;
}

struct InvalidNegatableValueWithArgs
{
    @(cliNegatable, cliValueWith!(TestCliValue!parseBool))
    bool flag;
}

struct InvalidCustomParserScopeArgs
{
    @(cliValueWith!(TestCliValue!parsePortWithoutScope))
    Port port;
}

struct InvalidCustomParserReturnArgs
{
    @(cliValueWith!(TestCliValue!parsePortWrongReturn))
    Port port;
}

struct InvalidDuplicateValueWithArgs
{
    @(cliValueWith!(TestCliValue!parsePort), cliValueWith!(TestCliValue!parsePort))
    Port port;
}

struct InvalidCountValueWithArgs
{
    @(cliCount, cliValueWith!(TestCliValue!parseAutomaticJobs))
    uint jobs;
}

struct InvalidEmptyPossibleValuesArgs
{
    @(cliPossibleValues!())
    String mode;
}

struct InvalidDuplicatePossibleValuesArgs
{
    @(cliPossibleValues!("fast", "fast"))
    String mode;
}

struct InvalidPossibleValuesFlagArgs
{
    @(cliPossibleValues!("true", "false"))
    bool flag;
}

struct InvalidDuplicatePossibleValuesAttributesArgs
{
    @(cliPossibleValues!("fast"), cliPossibleValues!("slow"))
    String mode;
}

enum InvalidNormalizedEnumNames
{
    fastMode,
    fast_mode,
}

struct InvalidNormalizedEnumNamesArgs
{
    InvalidNormalizedEnumNames mode;
}

struct InvalidChildVersionRootArgs
{
    alias Commands = CliCommands!(InvalidChildVersionArgs);
}

@(cliCommand("child"), cliVersion("1.0"))
struct InvalidChildVersionArgs
{
}

struct InvalidChildHelpPolicyRootArgs
{
    alias Commands = CliCommands!(InvalidChildHelpPolicyArgs);
}

@(cliCommand("child"), cliNoBuiltinHelp)
struct InvalidChildHelpPolicyArgs
{
}

struct InvalidChildVersionPolicyRootArgs
{
    alias Commands = CliCommands!(InvalidChildVersionPolicyArgs);
}

@(cliCommand("child"), cliNoBuiltinVersion)
struct InvalidChildVersionPolicyArgs
{
}

struct DurationValue
{
    uint seconds;
}

struct DurationValueCli
{
    static CliValueError parse(scope String input, DurationValue* output) nothrow @nogc
    {
        if (input == "30s")
        {
            output.seconds = 30;
            return CliValueError.init;
        }
        if (input == "60s")
        {
            output.seconds = 60;
            return CliValueError.init;
        }
        return CliValueError.invalid("expected 30s or 60s");
    }

    static void format(ref Writer writer, scope const DurationValue* value) nothrow @nogc
    {
        writer.value(value.seconds);
        writer.put('s');
    }
}

struct GenericFormattedValue
{
    uint value;

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writer.put('v');
        writer.value(value);
    }
}

struct GenericFormattedValueCli
{
    static CliValueError parse(scope String input, GenericFormattedValue* output) nothrow @nogc
    {
        if (input != "v10")
            return CliValueError.invalid("expected v10");
        output.value = 10;
        return CliValueError.init;
    }
}

struct ParserOnlyValue
{
    uint value;
}

struct ParserOnlyValueCli
{
    static CliValueError parse(scope String input, ParserOnlyValue* output) nothrow @nogc
    {
        if (input != "seven")
            return CliValueError.invalid("expected seven");
        output.value = 7;
        return CliValueError.init;
    }
}

struct RequirednessDefaultArgs
{
    uint required;
    Option!uint optional;

    @cliDefault
    uint zero;

    @cliDefault
    uint jobs = 8;

    @(cliValueWith!DurationValueCli, cliDefault)
    DurationValue timeout = DurationValue(30);

    @(cliValueWith!GenericFormattedValueCli, cliDefault)
    GenericFormattedValue generic = GenericFormattedValue(9);

    @(cliValueWith!(TestCliValue!parsePort), cliDefaultInput("443"))
    Port port;

    @(cliValueWith!ParserOnlyValueCli, cliDefault, cliHideDefault)
    ParserOnlyValue hidden = ParserOnlyValue(7);
}

struct HiddenInputDefaultArgs
{
    @(cliValueWith!(TestCliValue!parsePort), cliDefaultInput("80"), cliHideDefault)
    Port port;
}

struct HiddenSemanticDefaultArgs
{
    @(cliValueWith!ParserOnlyValueCli, cliDefault, cliHidden)
    ParserOnlyValue internal = ParserOnlyValue(7);
}

struct HiddenPositionalArgs
{
    @(cliPositional, cliHidden)
    Option!String internal;
}

struct InvalidHiddenRequiredArgs
{
    @cliHidden
    String secret;
}

struct BrokenRuntimeDefaultArgs
{
    @(cliValueWith!(TestCliValue!parsePort), cliDefaultInput("broken"))
    Port port;
}

struct InvalidOptionSemanticDefaultArgs
{
    @cliDefault
    Option!uint value;
}

struct InvalidOptionInputDefaultArgs
{
    @cliDefaultInput("8")
    Option!uint value;
}

struct InvalidTwoDefaultsArgs
{
    @(cliDefault, cliDefaultInput("8"))
    uint value;
}

struct InvalidHideDefaultArgs
{
    @cliHideDefault
    uint value;
}

struct InvalidUnformattableDefaultArgs
{
    @(cliValueWith!ParserOnlyValueCli, cliDefault)
    ParserOnlyValue value = ParserOnlyValue(7);
}

struct InvalidFormatterValueCli
{
    alias parse = ParserOnlyValueCli.parse;

    static String format(scope const ParserOnlyValue* value) nothrow @nogc
    {
        cast(void) value;
        return "seven";
    }
}

struct InvalidFormatterArgs
{
    @cliValueWith!InvalidFormatterValueCli ParserOnlyValue value;
}

struct ParentFinalizeRootArgs
{
    String config;

    @(cliValueWith!(TestCliValue!parsePort), cliDefaultInput("443"))
    Port port;

    alias Commands = CliCommands!(ParentFinalizeChildArgs);
}

@cliCommand("child")
struct ParentFinalizeChildArgs
{
}

static assert(!cliNeedsAllocator!RootArgs);
static assert(cliNeedsAllocator!AllocRootArgs);
static assert(!__traits(compiles, parseArgs!AllocRootArgs(cast(String[]) null)));
static assert(cliVersionOf!RootArgs == "2.4.1");
static assert(cliVersionOf!CustomVersionRootArgs == "9.3.0");
static assert(cliVersionOf!NoVersionMetadataRootArgs.length == 0);
static assert(!__traits(compiles,
        parseArgs!InvalidChildVersionRootArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidChildHelpPolicyRootArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidChildVersionPolicyRootArgs(cast(String[]) null)));
static assert(!__traits(compiles, parseArgs!InvalidOptionalLeafArgs(cast(String[]) null)));
static assert(!__traits(compiles, parseArgs!InvalidHelpLeafArgs(cast(String[]) null)));
static assert(!__traits(compiles, parseArgs!InvalidCombinedPolicyArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidTerminalPositionalArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidTerminalCountArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidTerminalArrayArgs(cast(String[]) null, mallocAllocator())));
static assert(!__traits(compiles,
        parseArgs!InvalidDuplicateTerminalArgs(cast(String[]) null)));
static assert(!__traits(compiles, parseArgs!InvalidRootAliasArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidDuplicateLongAliasArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidDuplicateShortAliasArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidLongNameDelimiterArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidLongAliasDelimiterArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidLongAliasCollisionArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidShortAliasCollisionArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidAliasGlobalCollisionRootArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidPositionalAliasArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidPositionalShortAliasArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidBuiltinHelpAliasArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidBuiltinHelpShortAliasArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidBuiltinVersionAliasArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidCommandAliasCollisionRootArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidDuplicateCommandAliasRootArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidCommandShortAliasRootArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidPlainOptionalBoolArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidNegatableTypeArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidNegatablePositionalArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidDuplicateNegatableArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidNegatableAliasCollisionArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidNegatableFieldCollisionArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidNegatableGlobalCollisionRootArgs(cast(String[]) null)));
static assert(cliNeedsAllocator!TerminalAllocArgs);
static assert(!cliNeedsAllocator!CustomValueNoAllocArgs);
static assert(cliNeedsAllocator!CustomValueArgs);
static assert(cliNeedsAllocator!AllocatorCustomValueArgs);
static assert(cliNeedsAllocator!WholeArrayCustomValueArgs);
static assert(!cliNeedsAllocator!WholeArrayNoAllocArgs);
static assert(!cliNeedsAllocator!WholeOptionCustomValueArgs);
static assert(!__traits(compiles,
        parseArgs!WholeArrayCustomValueArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidWholeArrayRestArgs(cast(String[]) null, mallocAllocator())));
static assert(!__traits(compiles,
        parseArgs!InvalidAmbiguousCustomParserArgs(cast(String[]) null, mallocAllocator())));
static assert(!__traits(compiles,
        parseArgs!InvalidOwningArrayCustomValueArgs(cast(String[]) null, mallocAllocator())));
static assert(!__traits(compiles,
        parseArgs!AllocatorCustomValueArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidCustomBoolArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidNegatableValueWithArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidCustomDestructorArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidCustomParserScopeArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidCustomParserReturnArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidDuplicateValueWithArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidCountValueWithArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidEmptyPossibleValuesArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidDuplicatePossibleValuesArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidPossibleValuesFlagArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidDuplicatePossibleValuesAttributesArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidNormalizedEnumNamesArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidOptionSemanticDefaultArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidOptionInputDefaultArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidTwoDefaultsArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidHideDefaultArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidHiddenRequiredArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidUnformattableDefaultArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFormatterArgs(cast(String[]) null)));
static assert(__traits(compiles,
        parseArgs!RequirednessDefaultArgs(cast(String[]) null)));

struct FlattenLeafOptions
{
    @(cliShortName('v'), cliAliasName("chatty"), cliHelp("Enable verbose output"))
    bool verbose;

    @(cliDefault, cliHelp("Parallel jobs"))
    uint jobs = 4;

    @(cliValueWith!DurationValueCli, cliDefault, cliHelp("Timeout"))
    DurationValue timeout = DurationValue(30);

    @(cliValueWith!ParserOnlyValueCli, cliDefault, cliHideDefault)
    ParserOnlyValue hiddenDefault = ParserOnlyValue(7);

    @(cliNegatable, cliHelp("Override color preference"))
    Option!bool color;

    @(
        cliValueWith!(TestCliValue!parsePort),
        cliDefaultInput("443"),
        cliHelp("Service port"),
    )
    Port port;

    @cliHidden
    bool internalTrace;
}

struct FlattenCommonOptions
{
    @cliFlatten
    FlattenLeafOptions leaf;

    @(cliValueName("PATH"), cliHelp("Optional config path"))
    Option!String config;

    @(cliValueName("TOOLCHAIN"), cliHelp("Required toolchain"))
    String toolchain;
}

struct FlattenArgs
{
    @cliFlatten
    FlattenCommonOptions common;

    @(cliValueName("OUTPUT"), cliHelp("Required output path"))
    String output;
}

struct FlattenPositionalGroup
{
    @(cliPositional, cliValueName("SOURCE"), cliHelp("Source value"))
    String source;
}

struct FlattenPositionalArgs
{
    @(cliPositional, cliValueName("PREFIX"), cliHelp("Prefix value"))
    String prefix;

    @cliFlatten
    FlattenPositionalGroup values;

    @(cliPositional, cliValueName("DESTINATION"), cliHelp("Destination value"))
    String destination;
}

struct FlattenGlobalOptions
{
    @(cliGlobal, cliShortName('v'), cliHelp("Verbose output"))
    bool verbose;

    @(cliGlobal, cliDefault, cliHelp("Global worker count"))
    uint workers = 2;
}

@cliSubcommandOptional
struct FlattenGlobalRootArgs
{
    @cliFlatten
    FlattenGlobalOptions global;

    alias Commands = CliCommands!(FlattenGlobalChildArgs);
}

@cliCommand("child")
struct FlattenGlobalChildArgs
{
    Option!String name;
}

struct FlattenTerminalGroup
{
    @(cliTerminal, cliValueName("TOPIC"))
    Option!String explain;
}

struct FlattenTerminalArgs
{
    @cliFlatten
    FlattenTerminalGroup terminal;

    String required;
}

struct FlattenRequiredChoiceGroup
{
    @cliNegatable
    bool color;
}

struct FlattenRequiredChoiceArgs
{
    @cliFlatten
    FlattenRequiredChoiceGroup choice;
}

struct FlattenRestGroup
{
    @(cliPositional, cliValueName("PROGRAM"))
    String program;

    @(cliPositional, cliRest, cliValueName("ARG"))
    Array!String arguments;
}

struct FlattenRestArgs
{
    @cliFlatten
    FlattenRestGroup run;
}

struct FlattenOverrideDefaultGroup
{
    @cliDefault
    uint jobs = 4;
}

struct FlattenOverrideDefaultArgs
{
    @cliFlatten
    FlattenOverrideDefaultGroup common = FlattenOverrideDefaultGroup(9);
}

struct FlattenAllocGroup
{
    @(cliShortName('D'), cliValueName("VALUE"))
    Array!String defines;
}

struct FlattenAllocArgs
{
    @cliFlatten
    FlattenAllocGroup compile;
}

struct FlattenCollisionGroup
{
    bool verbose;
}

struct InvalidFlattenCollisionArgs
{
    @cliFlatten
    FlattenCollisionGroup common;

    bool verbose;
}

struct InvalidFlattenTwoGroupsArgs
{
    @cliFlatten
    FlattenCollisionGroup first;

    @cliFlatten
    FlattenCollisionGroup second;
}

struct InvalidFlattenScalarArgs
{
    @cliFlatten
    uint value;
}

struct InvalidFlattenPointerArgs
{
    @cliFlatten
    FlattenCollisionGroup* common;
}

struct InvalidFlattenOptionArgs
{
    @cliFlatten
    Option!FlattenCollisionGroup common;
}

struct InvalidFlattenArrayArgs
{
    @cliFlatten
    Array!FlattenCollisionGroup common;
}

struct InvalidFlattenAttributeArgs
{
    @(cliFlatten, cliGlobal)
    FlattenCollisionGroup common;
}

@cliAbout("not a command")
struct InvalidFlattenCommandMetadataGroup
{
    bool verbose;
}

struct InvalidFlattenCommandMetadataArgs
{
    @cliFlatten
    InvalidFlattenCommandMetadataGroup common;
}

struct InvalidFlattenCommandGroup
{
    alias Commands = CliCommands!(InvalidFlattenCommandChild);
}

@cliCommand("child")
struct InvalidFlattenCommandChild
{
}

struct InvalidFlattenCommandArgs
{
    @cliFlatten
    InvalidFlattenCommandGroup common;
}

static assert(__traits(compiles,
        parseArgs!FlattenArgs(cast(String[]) null)));
static assert(__traits(compiles,
        parseArgs!FlattenPositionalArgs(cast(String[]) null)));
static assert(__traits(compiles,
        parseArgs!FlattenGlobalRootArgs(cast(String[]) null)));
static assert(__traits(compiles,
        parseArgs!FlattenTerminalArgs(cast(String[]) null)));
static assert(__traits(compiles,
        parseArgs!FlattenRequiredChoiceArgs(cast(String[]) null)));
static assert(__traits(compiles,
        parseArgs!FlattenOverrideDefaultArgs(cast(String[]) null)));
static assert(cliNeedsAllocator!FlattenRestArgs);
static assert(cliNeedsAllocator!FlattenAllocArgs);
static assert(!__traits(compiles,
        parseArgs!FlattenAllocArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFlattenCollisionArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFlattenTwoGroupsArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFlattenScalarArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFlattenPointerArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFlattenOptionArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFlattenArrayArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFlattenAttributeArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFlattenCommandMetadataArgs(cast(String[]) null)));
static assert(!__traits(compiles,
        parseArgs!InvalidFlattenCommandArgs(cast(String[]) null)));

private struct TextSink
{
    char[8192] storage;
    size_t length;

    String text() const return nothrow @nogc pure @safe
    {
        return storage[0 .. length];
    }
}

private size_t textSink(void* context, scope const(ubyte)[] bytes) @system
{
    TextSink* sink = cast(TextSink*) context;
    if (sink is null || bytes.length > sink.storage.length - sink.length)
        return 0;
    foreach (codeUnit; bytes)
        sink.storage[sink.length++] = cast(char) codeUnit;
    return bytes.length;
}

private bool contains(String haystack, String needle) pure @safe
{
    if (needle.length > haystack.length)
        return false;
    foreach (offset; 0 .. haystack.length - needle.length + 1)
        if (haystack[offset .. offset + needle.length] == needle)
            return true;
    return false;
}

private void testFlattenedArguments()
{
    {
        String[5] argv = ["tool", "--toolchain", "ldc2", "--output", "build"];
        auto result = parseArgs!FlattenArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(!result.invocation.args.common.leaf.verbose);
        assert(result.invocation.args.common.leaf.jobs == 4);
        assert(result.invocation.args.common.leaf.timeout.seconds == 30);
        assert(result.invocation.args.common.leaf.hiddenDefault.value == 7);
        assert(result.invocation.args.common.leaf.color.isNone);
        assert(result.invocation.args.common.leaf.port.value == 443);
        assert(!result.invocation.args.common.leaf.internalTrace);
        assert(result.invocation.args.common.config.isNone);
        assert(result.invocation.args.common.toolchain == "ldc2");
        assert(result.invocation.args.output == "build");
    }

    {
        String[14] argv = [
            "tool",
            "--toolchain",
            "ldc2",
            "--chatty",
            "--jobs",
            "9",
            "--no-color",
            "--port",
            "80",
            "--config",
            "xtb.conf",
            "--internal-trace",
            "--output",
            "build",
        ];
        auto result = parseArgs!FlattenArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.common.leaf.verbose);
        assert(result.invocation.args.common.leaf.jobs == 9);
        assert(result.invocation.args.common.leaf.color.isSome);
        assert(!result.invocation.args.common.leaf.color.value);
        assert(result.invocation.args.common.leaf.port.value == 80);
        assert(result.invocation.args.common.leaf.internalTrace);
        assert(result.invocation.args.common.config.isSome);
        assert(result.invocation.args.common.config.value == "xtb.conf");
        assert(result.invocation.args.common.toolchain == "ldc2");
        assert(result.invocation.args.output == "build");
    }

    {
        String[3] argv = ["tool", "--output", "build"];
        auto result = parseArgs!FlattenArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 2);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(contains(errors.text, "required option '--toolchain' was not provided"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!FlattenArgs(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text,
                "Usage: tool --toolchain <TOOLCHAIN> --output <OUTPUT> [OPTIONS]"));
        assert(contains(output.text, "Required options:"));
        assert(contains(output.text, "--toolchain <TOOLCHAIN>"));
        assert(contains(output.text, "--output <OUTPUT>"));
        assert(contains(output.text, "Optional options:"));
        assert(contains(output.text, "--verbose"));
        assert(contains(output.text, "aliases: --chatty"));
        assert(contains(output.text, "default: 4"));
        assert(contains(output.text, "default: 30s"));
        assert(contains(output.text, "default: 443"));
        assert(!contains(output.text, "default: 7"));
        assert(contains(output.text, "--config <PATH>"));
        assert(!contains(output.text, "internal-trace"));
        assert(!contains(output.text, "FlattenLeafOptions"));
        assert(!contains(output.text, "FlattenCommonOptions"));
    }

    {
        String[4] argv = ["tool", "prefix", "source", "destination"];
        auto result = parseArgs!FlattenPositionalArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.prefix == "prefix");
        assert(result.invocation.args.values.source == "source");
        assert(result.invocation.args.destination == "destination");

        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!FlattenPositionalArgs(writer, "tool");
        assert(writer.result.ok);
        assert(contains(output.text, "Usage: tool [OPTIONS] <PREFIX> <SOURCE> <DESTINATION>"));
    }

    {
        String[5] argv = ["tool", "child", "--verbose", "--name", "value"];
        auto result = parseArgs!FlattenGlobalRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.global.verbose);
        assert(result.invocation.args.global.workers == 2);
        auto child = result.invocation.command!FlattenGlobalChildArgs;
        assert(child !is null);
        assert(child.args.name.isSome);
        assert(child.args.name.value == "value");

        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(FlattenGlobalRootArgs, FlattenGlobalChildArgs)(writer, "tool");
        assert(writer.result.ok);
        assert(contains(output.text, "Optional global options:"));
        assert(contains(output.text, "--verbose"));
        assert(contains(output.text, "--workers <WORKERS>"));
        assert(contains(output.text, "default: 2"));
    }

    {
        String[3] argv = ["tool", "--explain", "schema"];
        auto result = parseArgs!FlattenTerminalArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasTerminal);
        assert(result.parsed.args.terminal.explain.isSome);
        assert(result.parsed.args.terminal.explain.value == "schema");
    }

    {
        String[1] argv = ["tool"];
        auto result = parseArgs!FlattenRequiredChoiceArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);
    }

    {
        String[2] argv = ["tool", "--no-color"];
        auto result = parseArgs!FlattenRequiredChoiceArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(!result.invocation.args.choice.color);

        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!FlattenRequiredChoiceArgs(writer, "tool");
        assert(writer.result.ok);
        assert(contains(output.text, "Usage: tool (--color|--no-color) [OPTIONS]"));
        assert(contains(output.text, "Required options:"));
    }

    {
        String[1] argv = ["tool"];
        auto result = parseArgs!FlattenOverrideDefaultArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.common.jobs == 9);

        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!FlattenOverrideDefaultArgs(writer, "tool");
        assert(writer.result.ok);
        assert(contains(output.text, "default: 9"));
    }

    {
        AllocationRecord[8] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );
        String[5] argv = ["tool", "app", "--", "-x", "value"];
        auto result = parseArgs!FlattenRestArgs(argv, allocator.allocator);
        assert(result.hasInvocation);
        assert(result.invocation.args.run.program == "app");
        assert(result.invocation.args.run.arguments.length == 2);
        assert(result.invocation.args.run.arguments[0] == "-x");
        assert(result.invocation.args.run.arguments[1] == "value");
        result.deinit();
        assert(allocator.clean);
    }

    {
        AllocationRecord[8] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );
        String[5] argv = ["tool", "-Da", "-Db", "-Dc", "-Dd"];
        auto result = parseArgs!FlattenAllocArgs(argv, allocator.allocator);
        assert(result.hasInvocation);
        assert(result.invocation.args.compile.defines.length == 4);
        assert(result.invocation.args.compile.defines[0] == "a");
        assert(result.invocation.args.compile.defines[3] == "d");
        result.deinit();
        assert(allocator.clean);
    }
}

private void testRequirednessAndDefaults()
{
    {
        String[1] argv = ["tool"];
        auto result = parseArgs!RequirednessDefaultArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);
    }

    {
        String[3] argv = ["tool", "--required", "5"];
        auto result = parseArgs!RequirednessDefaultArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.required == 5);
        assert(result.invocation.args.optional.isNone);
        assert(result.invocation.args.zero == 0);
        assert(result.invocation.args.jobs == 8);
        assert(result.invocation.args.timeout.seconds == 30);
        assert(result.invocation.args.generic.value == 9);
        assert(result.invocation.args.port.value == 443);
        assert(result.invocation.args.hidden.value == 7);
    }

    {
        String[11] argv = [
            "tool",
            "--required",
            "5",
            "--optional",
            "0",
            "--zero",
            "2",
            "--timeout",
            "60s",
            "--port",
            "80",
        ];
        auto result = parseArgs!RequirednessDefaultArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.optional.isSome);
        assert(result.invocation.args.optional.value == 0);
        assert(result.invocation.args.zero == 2);
        assert(result.invocation.args.timeout.seconds == 60);
        assert(result.invocation.args.port.value == 80);
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!RequirednessDefaultArgs(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text, "Usage: tool --required <REQUIRED> [OPTIONS]"));
        assert(contains(output.text, "Required options:"));
        assert(contains(output.text, "--required <REQUIRED>"));
        assert(contains(output.text, "Optional options:"));
        assert(contains(output.text, "--optional <OPTIONAL>"));
        assert(contains(output.text, "default: 0"));
        assert(contains(output.text, "default: 8"));
        assert(contains(output.text, "default: 30s"));
        assert(contains(output.text, "default: v9"));
        assert(contains(output.text, "default: 443"));
        assert(contains(output.text, "--hidden <HIDDEN>"));
        assert(!contains(output.text, "default: 7"));
        assert(!contains(output.text, "default: seven"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!HiddenInputDefaultArgs(writer, "tool");
        assert(writer.result.ok);
        assert(contains(output.text, "--port <PORT>"));
        assert(!contains(output.text, "default:"));
    }

    {
        String[1] argv = ["tool"];
        auto result = parseArgs!HiddenSemanticDefaultArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.internal.value == 7);

        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!HiddenSemanticDefaultArgs(writer, "tool");
        assert(writer.result.ok);
        assert(!contains(output.text, "internal"));
        assert(!contains(output.text, "default:"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!HiddenPositionalArgs(writer, "tool");
        assert(writer.result.ok);
        assert(!contains(output.text, "INTERNAL"));
    }

    {
        String[1] argv = ["tool"];
        auto result = parseArgs!BrokenRuntimeDefaultArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.invalidDefault);
        assert(result.error.token == "broken");
        assert(result.error.valueError.kind == CliValueErrorKind.invalid);
    }

    {
        String[2] argv = ["tool", "--help"];
        auto result = parseArgs!BrokenRuntimeDefaultArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasBuiltinResponse);
        assert(!result.failed);
    }

    {
        String[3] argv = ["tool", "--port", "80"];
        auto result = parseArgs!BrokenRuntimeDefaultArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.port.value == 80);
    }

    {
        String[2] argv = ["tool", "child"];
        auto result = parseArgs!ParentFinalizeRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);
    }

    {
        String[4] argv = ["tool", "--config", "project.toml", "child"];
        auto result = parseArgs!ParentFinalizeRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.config == "project.toml");
        assert(result.invocation.args.port.value == 443);
        assert(result.invocation.command!ParentFinalizeChildArgs !is null);
    }
}

private void testExplicitTypedTraversal()
{
    String[8] argv = [
        "tool",
        "-vv",
        "build",
        "-rj8",
        "--mode=release-safe",
        "--output",
        "build/app",
        "-v",
    ];
    auto result = parseArgs!RootArgs(argv);
    scope (exit)
        result.deinit();

    assert(result.hasInvocation);
    ref root = result.invocation;
    assert(root.args.verbose == 3);
    assert(root.args.directory.isNone);

    auto build = root.command!BuildArgs;
    assert(build !is null);
    assert(root.command!DependencyArgs is null);
    assert(build.args.release);
    assert(build.args.jobs == 8);
    assert(build.args.mode == BuildMode.releaseSafe);
    assert(build.args.output == "build/app");
}

private void testNestedCommandsAndChildVersionOption()
{
    String[8] argv = [
        "tool",
        "dependency",
        "--registry=https://registry.test",
        "add",
        "pkg",
        "--version",
        "2.0",
        "-v",
    ];
    auto result = parseArgs!RootArgs(argv);
    scope (exit)
        result.deinit();

    assert(result.hasInvocation);
    ref root = result.invocation;
    assert(root.args.verbose == 1);

    auto dependency = root.command!DependencyArgs;
    assert(dependency !is null);
    assert(dependency.args.registry.isSome);
    assert(dependency.args.registry.value == "https://registry.test");

    auto add = dependency.command!DependencyAddArgs;
    assert(add !is null);
    assert(add.args.package_ == "pkg");
    assert(add.args.version_.isSome);
    assert(add.args.version_.value == "2.0");
}

private void testDefaultsAndOptionalCommand()
{
    String[2] argv = ["tool", "dependency"];
    auto result = parseArgs!RootArgs(argv);
    scope (exit)
        result.deinit();

    assert(result.hasInvocation);
    auto dependency = result.invocation.command!DependencyArgs;
    assert(dependency !is null);
    assert(!dependency.hasCommand);
    assert(dependency.args.registry.isNone);
}

private void testRequiredAndDuplicateErrors()
{
    {
        String[2] argv = ["tool", "build"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();
        assert(!result.hasInvocation);
        assert(result.failed);
        assert(result.error !is null);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);
        assert(result.error.fieldIndex == 3);
    }

    {
        String[8] argv = [
            "tool",
            "build",
            "--output",
            "a",
            "--jobs",
            "2",
            "--jobs",
            "3",
        ];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.duplicateOption);
    }

    {
        String[3] argv = ["tool", "dependency", "add"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingPositional);
        assert(result.error.fieldIndex == 0);
    }
}

private void testRequiredCommand()
{
    String[1] argv = ["tool"];
    auto result = parseArgs!RequiredCommandRoot(argv);
    scope (exit)
        result.deinit();
    assert(result.failed);
    assert(result.error.kind == CliErrorKind.missingCommand);
}

private void testHelpOnMissingSubcommand()
{
    // Missing required fields are more specific than the no-subcommand help
    // policy. The policy only activates once the current command is otherwise
    // complete.
    {
        String[1] argv = ["/usr/local/bin/tool"];
        auto result = parseArgs!HelpOnMissingRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);
        assert(result.error.fieldIndex == 0);
    }

    {
        String[3] argv = ["tool", "--config", "config.toml"];
        auto result = parseArgs!HelpOnMissingRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(!result.hasInvocation);
        assert(!result.failed);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 0);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(errors.text.length == 0);
        assert(contains(output.text, "Choose a command"));
        assert(contains(output.text, "Usage: tool --config <CONFIG> <COMMAND>"));
        assert(contains(output.text, "group"));
        assert(!contains(output.text, "Show this help"));
    }

    // Required fields on the command carrying @cliHelpOnNoSubcommand also
    // take precedence over generated help.
    {
        String[4] argv = ["tool", "--config", "config.toml", "group"];
        auto result = parseArgs!HelpOnMissingRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);
        assert(result.error.commandDepth == 1);
        assert(result.error.fieldIndex == 0);
    }

    // A descendant help policy must not hide missing required fields on an
    // ancestor command. Let normal recursive validation report the ancestor.
    {
        String[4] argv = ["tool", "group", "--profile", "dev"];
        auto result = parseArgs!HelpOnMissingRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);
        assert(result.error.commandDepth == 0);
        assert(result.error.fieldIndex == 0);
    }

    {
        String[6] argv = [
            "tool", "--config", "config.toml", "group", "--profile", "dev",
        ];
        auto result = parseArgs!HelpOnMissingRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(!result.hasInvocation);
        assert(!result.failed);
        assert(result.parsed.command!HelpOnMissingGroupArgs !is null);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 0);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(errors.text.length == 0);
        assert(contains(output.text, "Choose a group command"));
        assert(contains(output.text,
                "Usage: tool --config <CONFIG> group --profile <PROFILE> <COMMAND>"));
        assert(contains(output.text, "run"));
        assert(!contains(output.text, "Show this help"));
    }

    {
        String[4] argv = ["tool", "--config", "config.toml", "wat"];
        auto result = parseArgs!HelpOnMissingRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.unknownCommand);
    }
}

private void testUnknownAndInvalidValues()
{
    {
        String[2] argv = ["tool", "unknown"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.unknownCommand);
        assert(result.error.token == "unknown");
    }

    {
        String[5] argv = ["tool", "build", "--output=x", "--mode", "wat"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.invalidValue);
        assert(result.error.token == "wat");
    }

    {
        String[5] argv = ["tool", "build", "--output=x", "--jobs", "999999999999999999999"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.invalidValue);
    }
}

private void testAliases()
{
    {
        String[6] argv = [
            "tool",
            "--verbosity",
            "--colour",
            "rm",
            "-F",
            "--destination=item",
        ];
        auto result = parseArgs!AliasRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        ref root = result.invocation;
        assert(root.args.verbose == 1);
        assert(root.args.color);

        auto remove = root.command!AliasRemoveArgs;
        assert(remove !is null);
        assert(remove.args.force);
        assert(remove.args.target == "item");
    }

    {
        String[3] argv = ["tool", "-Q", "ls"];
        auto result = parseArgs!AliasRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.verbose == 1);
        assert(result.invocation.command!AliasListArgs !is null);
    }

    {
        String[4] argv = ["tool", "del", "--erase", "--target=item"];
        auto result = parseArgs!AliasRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        auto remove = result.invocation.command!AliasRemoveArgs;
        assert(remove !is null);
        assert(remove.args.force);
        assert(remove.args.target == "item");
    }

    {
        String[4] argv = ["tool", "--colour", "--color", "ls"];
        auto result = parseArgs!AliasRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.duplicateOption);
    }

    {
        String[3] argv = ["tool", "--chatty", "ls"];
        auto result = parseArgs!AliasRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.verbose == 1);
    }

    {
        String[2] argv = ["tool", "--help"];
        auto result = parseArgs!DisabledBuiltinHelpAliasArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.custom);
    }

    {
        String[2] argv = ["tool", "-h"];
        auto result = parseArgs!DisabledBuiltinHelpAliasArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.custom);
    }

    {
        String[2] argv = ["tool", "--version"];
        auto result = parseArgs!DisabledBuiltinVersionAliasArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.custom);
    }
}

private void testNegatableBooleans()
{
    {
        String[1] argv = ["tool"];
        auto result = parseArgs!NegatableArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(!result.invocation.args.color);
        assert(result.invocation.args.feature);
        assert(result.invocation.args.cache.isNone);
    }

    {
        String[4] argv = ["tool", "--colour", "--no-feature", "--cache"];
        auto result = parseArgs!NegatableArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.color);
        assert(!result.invocation.args.feature);
        assert(result.invocation.args.cache.isSome);
        assert(result.invocation.args.cache.value);
    }

    {
        String[3] argv = ["tool", "-c", "--no-cache"];
        auto result = parseArgs!NegatableArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.color);
        assert(result.invocation.args.cache.isSome);
        assert(!result.invocation.args.cache.value);
    }

    {
        String[3] argv = ["tool", "--color", "--no-color"];
        auto result = parseArgs!NegatableArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.duplicateOption);
    }

    {
        String[2] argv = ["tool", "--color=true"];
        auto result = parseArgs!NegatableArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.invalidValue);
    }

    {
        String[2] argv = ["tool", "--no-colour"];
        auto result = parseArgs!NegatableArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.unknownOption);
    }

    {
        String[3] argv = ["tool", "child", "--no-color"];
        auto result = parseArgs!NegatableGlobalRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(!result.invocation.args.color);
        assert(result.invocation.command!NegatableGlobalChildArgs !is null);
    }

    {
        String[3] argv = ["tool", "--no-diagnostics", "ignored"];
        auto result = parseArgs!NegatableTerminalArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasTerminal);
        assert(result.parsed.args.output.length == 0);
        assert(result.parsed.args.diagnostics.isSome);
        assert(!result.parsed.args.diagnostics.value);
    }

    {
        String[1] argv = ["tool"];
        auto result = parseArgs!RequiredNegatableArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);
    }

    {
        String[2] argv = ["tool", "--no-color"];
        auto result = parseArgs!RequiredNegatableArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(!result.invocation.args.color);
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!RequiredNegatableArgs(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text, "Usage: tool (--color|--no-color) [OPTIONS]"));
        assert(contains(output.text, "Required options:"));
        assert(contains(output.text, "--color"));
        assert(contains(output.text, "negatable: --no-color"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!NegatableArgs(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text, "-c, --color"));
        assert(contains(output.text, "Use colored output"));
        assert(contains(output.text, "aliases: --colour"));
        assert(contains(output.text, "negatable: --no-color"));
        assert(contains(output.text, "default: false"));
        assert(contains(output.text, "--feature"));
        assert(contains(output.text, "negatable: --no-feature"));
        assert(contains(output.text, "default: true"));
        assert(contains(output.text, "--cache"));
        assert(contains(output.text, "negatable: --no-cache"));
        assert(!contains(output.text, "--no-colour"));
        assert(!contains(output.text, "<CACHE>"));
    }
}

private void testPublicGeneratedHelp()
{
    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!RequiredOnlyHelpArgs(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text, "Usage: tool --output <OUTPUT>"));
        assert(!contains(output.text, "[OPTIONS]"));
        assert(contains(output.text, "Required options:"));
        assert(!contains(output.text, "Optional options:"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(RequiredGlobalRootArgs, RequiredGlobalChildArgs)(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text,
                "Usage: tool child --workspace <WORKSPACE> [OPTIONS]"));
        assert(contains(output.text, "Required global options:"));
        assert(contains(output.text, "--workspace <WORKSPACE>"));
        assert(!contains(output.text, "Optional global options:"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(RootArgs, DependencyArgs, DependencyAddArgs)(
            writer,
            "/usr/local/bin/tool",
        );
        assert(writer.result.ok);

        assert(contains(output.text, "Add a dependency"));
        assert(contains(output.text, "Usage: tool dependency [OPTIONS] add [OPTIONS] <PACKAGE>"));
        assert(!contains(output.text, "/usr/local/bin/tool"));
        assert(contains(output.text, "  <PACKAGE>"));
        assert(!contains(output.text, "required
"));
        assert(contains(output.text, "--version <VERSION>"));
        assert(contains(output.text, "Optional global options:"));
        assert(contains(output.text, "--verbose"));
        assert(!contains(output.text, "Show the application version"));

        String[4] argv = ["tool", "dependency", "add", "--help"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();
        TextSink builtinOutput;
        TextSink errors;
        Writer builtinWriter = Writer.fromSink(&textSink, &builtinOutput);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(builtinWriter, errorWriter, result) == 0);
        assert(builtinWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(errors.text.length == 0);
        assert(output.text == builtinOutput.text);
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(CustomHelpRootArgs, CustomHelpChildArgs)(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text, "Usage: tool [OPTIONS] child [OPTIONS]"));
        assert(contains(output.text, "-h, --help"));
        assert(!contains(output.text, "Show this help"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(RootArgs, BuildArgs)(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text, "Usage: tool build --output <PATH> [OPTIONS]"));
        assert(contains(output.text, "Required options:"));
        assert(contains(output.text, "Optional options:"));
        assert(contains(output.text, "--jobs <N>"));
        assert(contains(output.text, "Parallel jobs"));
        assert(contains(output.text, "default: 1"));
        assert(contains(output.text, "--mode <MODE>"));
        assert(contains(output.text, "Build mode"));
        assert(contains(output.text, "values: debug, release-safe, release-fast"));
        assert(contains(output.text, "default: debug"));
        assert(contains(output.text, "--output <PATH>"));
        assert(contains(output.text, "Output path"));
        assert(!contains(output.text, "\t"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!OverrideBuiltInValueArgs(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text, "--jobs <JOBS>"));
        assert(contains(output.text, "aliases: --parallelism"));
        assert(contains(output.text, "values: auto"));
        assert(contains(output.text, "default: auto"));
        assert(contains(
                output.text,
                "      --jobs <JOBS>  aliases: --parallelism\n" ~
                "                     values: auto\n" ~
                "                     default: auto\n",
        ));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(AliasRootArgs)(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text, "remove"));
        assert(contains(output.text, "Remove an item"));
        assert(contains(output.text, "aliases: rm, del"));
        assert(contains(output.text, "list"));
        assert(contains(output.text, "aliases: ls"));
        assert(contains(output.text, "-v, --verbose"));
        assert(contains(output.text, "aliases: -V, -Q, --verbosity, --chatty"));
        assert(contains(output.text, "--color"));
        assert(contains(output.text, "aliases: --colour"));
        assert(contains(
                output.text,
                "  remove  Remove an item\n" ~
                "          aliases: rm, del\n\n" ~
                "  list    aliases: ls\n",
        ));
        assert(contains(
                output.text,
                "  -v, --verbose  aliases: -V, -Q, --verbosity, --chatty\n",
        ));
        assert(contains(output.text, "      --color  aliases: --colour\n"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(AliasRootArgs, AliasRemoveArgs)(writer, "tool");
        assert(writer.result.ok);

        assert(contains(output.text, "Usage: tool [OPTIONS] remove --target <TARGET> [OPTIONS]"));
        assert(contains(output.text, "-f, --force"));
        assert(contains(output.text, "aliases: -F, -E, --delete, --erase"));
        assert(contains(output.text, "Required options:"));
        assert(contains(output.text, "--target <TARGET>"));
        assert(contains(output.text, "aliases: --destination"));
    }
}

private void testAnsiRendering()
{
    {
        TextSink plain;
        Writer plainWriter = Writer.fromSink(&textSink, &plain);
        writeHelp!OverrideBuiltInValueArgs(plainWriter, "tool");
        assert(plainWriter.result.ok);
        assert(!contains(plain.text, "\x1b["));

        TextSink styled;
        Writer styledWriter = Writer.fromSink(&textSink, &styled);
        writeHelp!OverrideBuiltInValueArgs(styledWriter, "tool", true);
        assert(styledWriter.result.ok);
        assert(contains(styled.text, "\x1b[1mUsage:\x1b[0m"));
        assert(contains(styled.text, "\x1b[2maliases:\x1b[0m"));
        assert(contains(styled.text, "\x1b[93mauto\x1b[0m"));
    }

    {
        String[2] argv = ["tool", "--help"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result, true, false) == 0);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(contains(output.text, "\x1b["));
        assert(errors.text.length == 0);
    }

    {
        String[2] argv = ["tool", "wat"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result, false, true) == 2);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(output.text.length == 0);
        assert(contains(errors.text, "\x1b[1;91merror:\x1b[0m"));
        assert(contains(errors.text, "\x1b[93mwat\x1b[0m"));
    }
}

private void testGeneratedHelpAndVersion()
{
    {
        String[4] argv = ["/tmp/tool", "dependency", "add", "--help"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();
        assert(!result.hasInvocation);
        assert(!result.failed);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 0);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(errors.text.length == 0);
        assert(contains(output.text, "Add a dependency"));
        assert(contains(output.text, "Usage: tool dependency [OPTIONS] add [OPTIONS] <PACKAGE>"));
        assert(contains(output.text, "--version <VERSION>"));
        assert(contains(output.text, "Optional global options:"));
        assert(contains(output.text, "--verbose"));
        assert(!contains(output.text, "Show the application version"));
    }

    {
        String[2] argv = ["tool", "--version"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();
        assert(!result.hasInvocation);
        assert(!result.failed);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 0);
        assert(output.text == "tool 2.4.1\n");
        assert(errors.text.length == 0);
    }
}

private void testGeneratedErrorResponse()
{
    String[2] argv = ["tool", "wat"];
    auto result = parseArgs!RootArgs(argv);
    scope (exit)
        result.deinit();

    TextSink output;
    TextSink errors;
    Writer outputWriter = Writer.fromSink(&textSink, &output);
    Writer errorWriter = Writer.fromSink(&textSink, &errors);
    assert(writeCliResult(outputWriter, errorWriter, result) == 2);

    assert(output.text.length == 0);
    assert(contains(errors.text, "error: unknown command 'wat'"));
    assert(contains(errors.text, "Usage: tool [OPTIONS] [COMMAND]"));
    assert(contains(errors.text, "Try 'tool --help'"));
}

private void testDisabledBuiltinHelp()
{
    {
        String[2] argv = ["tool", "--help"];
        auto result = parseArgs!CustomHelpRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.help);
    }

    {
        String[2] argv = ["tool", "-h"];
        auto result = parseArgs!CustomHelpRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.help);
    }

    {
        String[3] argv = ["tool", "child", "--help"];
        auto result = parseArgs!CustomHelpRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        auto child = result.invocation.command!CustomHelpChildArgs;
        assert(child !is null);
        assert(child.args.help);
    }

    {
        String[3] argv = ["tool", "child", "-h"];
        auto result = parseArgs!CustomHelpRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        auto child = result.invocation.command!CustomHelpChildArgs;
        assert(child !is null);
        assert(child.args.help);
    }

    {
        String[2] argv = ["tool", "--wat"];
        auto result = parseArgs!NoBuiltinHelpRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 2);
        assert(!contains(errors.text, "--help"));
    }
}

private void testDisabledBuiltinVersion()
{
    {
        String[3] argv = ["tool", "--version", "custom"];
        auto result = parseArgs!CustomVersionRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        assert(result.invocation.args.version_.isSome);
        assert(result.invocation.args.version_.value == "custom");
    }

    {
        String[2] argv = ["tool", "--version"];
        auto result = parseArgs!CustomVersionRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingOptionValue);
    }

    {
        String[2] argv = ["tool", "--help"];
        auto result = parseArgs!CustomVersionRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(!result.hasInvocation);
        assert(!result.failed);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 0);
        assert(contains(output.text, "--version <VERSION>"));
        assert(!contains(output.text, "Show the application version"));
    }

    {
        String[1] argv = ["tool"];
        auto result = parseArgs!NoVersionMetadataRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
    }
}

private void testCustomValueParsers()
{
    AllocationRecord[32] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    {
        String[7] argv = [
            "tool",
            "--port",
            "80",
            "--optional-port=443",
            "--repeated-port",
            "80",
            "--repeated-port=443",
        ];
        auto result = parseArgs!CustomValueArgs(argv, allocator.allocator);
        assert(result.hasInvocation);
        assert(result.invocation.args.port.value == 80);
        assert(result.invocation.args.optionalPort.isSome);
        assert(result.invocation.args.optionalPort.value.value == 443);
        assert(result.invocation.args.repeatedPort.length == 2);
        assert(result.invocation.args.repeatedPort[0].value == 80);
        assert(result.invocation.args.repeatedPort[1].value == 443);
        result.deinit();
        assert(allocator.clean);
    }

    {
        String[3] argv = ["tool", "--bytes", "deadBEEF"];
        auto result = parseArgs!WholeArrayCustomValueArgs(argv, allocator.allocator);
        assert(result.hasInvocation);
        assert(result.invocation.args.bytes.length == 4);
        assert(result.invocation.args.bytes[0] == 0xde);
        assert(result.invocation.args.bytes[1] == 0xad);
        assert(result.invocation.args.bytes[2] == 0xbe);
        assert(result.invocation.args.bytes[3] == 0xef);
        result.deinit();
        assert(allocator.clean);
    }

    {
        String[3] argv = ["tool", "--port", "none"];
        auto result = parseArgs!WholeOptionCustomValueArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.port.isNone);
    }

    {
        String[3] argv = ["tool", "--port", "443"];
        auto result = parseArgs!WholeOptionCustomValueArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.port.isSome);
        assert(result.invocation.args.port.value.value == 443);
    }

    {
        String[2] argv = ["tool", "c001"];
        auto result = parseArgs!WholeArrayPositionalArgs(argv, allocator.allocator);
        assert(result.hasInvocation);
        assert(result.invocation.args.bytes.length == 2);
        assert(result.invocation.args.bytes[0] == 0xc0);
        assert(result.invocation.args.bytes[1] == 0x01);
        result.deinit();
        assert(allocator.clean);
    }

    {
        String[3] argv = ["tool", "--bytes", "empty"];
        auto result = parseArgs!WholeArrayNoAllocArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.bytes.length == 0);
    }

    {
        String[5] argv = ["tool", "--bytes", "deadbeef", "--bytes", "00"];
        auto result = parseArgs!WholeArrayCustomValueArgs(argv, allocator.allocator);
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.duplicateOption);
        result.deinit();
        assert(allocator.clean);
    }

    {
        String[3] argv = ["tool", "--jobs", "auto"];
        auto result = parseArgs!OverrideBuiltInValueArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.jobs == 8);
    }

    {
        String[2] argv = ["tool", "443"];
        auto result = parseArgs!CustomPositionalValueArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.port.value == 443);
    }
}

private void testCustomValueParserErrors()
{
    {
        String[3] argv = ["tool", "--port", "wat"];
        auto result = parseArgs!CustomValueNoAllocArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.invalidValue);
        assert(result.error.valueError.kind == CliValueErrorKind.invalid);
        assert(result.error.valueError.message == "expected a numeric port");

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 2);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(contains(errors.text,
                "invalid value 'wat' for --port: expected a numeric port"));
    }

    {
        String[3] argv = ["tool", "--port", "70000"];
        auto result = parseArgs!CustomValueNoAllocArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.valueError.kind == CliValueErrorKind.outOfRange);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 2);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(contains(errors.text,
                "value '70000' for --port is out of range: port must be between 0 and 65535"));
    }

    {
        String[3] argv = ["tool", "--port", "silent"];
        auto result = parseArgs!CustomValueNoAllocArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 2);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(contains(errors.text, "invalid value 'silent' for --port"));
        assert(!contains(errors.text, "--port:"));
    }

    {
        AllocationRecord[16] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );
        String[3] argv = ["tool", "--bytes", "00gg"];
        auto result = parseArgs!WholeArrayCustomValueArgs(argv, allocator.allocator);
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.invalidValue);
        assert(result.error.valueError.message == "expected hexadecimal digits");
        result.deinit();
        assert(allocator.clean);
    }

    {
        AllocationRecord[16] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );
        allocator.failAfter(0);
        String[3] argv = ["tool", "--bytes", "00"];
        auto result = parseArgs!WholeArrayCustomValueArgs(argv, allocator.allocator);
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.allocationFailed);
        assert(result.error.valueError.kind == CliValueErrorKind.allocationFailed);
        result.deinit();
        assert(allocator.clean);
    }
}

private void testAllocatorCustomValueParserCleanup()
{
    AllocationRecord[32] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    {
        String[3] argv = ["tool", "--value", "owned"];
        auto result = parseArgs!AllocatorCustomValueArgs(argv, allocator.allocator);
        assert(result.hasInvocation);
        assert(result.invocation.args.value.isSome);
        assert(result.invocation.args.value.value.values.length == 1);
        assert(result.invocation.args.value.value.values[0] == "owned");
        result.deinit();
        assert(allocator.clean);
    }

    allocator.failAfter(0);
    {
        String[3] argv = ["tool", "--value", "owned"];
        auto result = parseArgs!AllocatorCustomValueArgs(argv, allocator.allocator);
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.allocationFailed);
        assert(result.error.valueError.kind == CliValueErrorKind.allocationFailed);
        assert(result.error.valueError.message == "could not store parsed value");
        result.deinit();
        assert(allocator.clean);
    }
}

private void testTerminalArguments()
{
    {
        String[5] argv = ["tool", "build", "--help", "--wat", "ignored"];
        auto result = parseArgs!TerminalRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasTerminal);
        assert(!result.hasInvocation);
        assert(!result.hasBuiltinResponse);
        assert(!result.failed);
        ref root = result.parsed;
        assert(root.args.help);
        auto build = root.command!TerminalBuildArgs;
        assert(build !is null);
        assert(build.args.output.length == 0);
    }

    {
        String[5] argv = ["tool", "build", "--completions", "fish", "--wat"];
        auto result = parseArgs!TerminalRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasTerminal);
        auto build = result.parsed.command!TerminalBuildArgs;
        assert(build !is null);
        assert(build.args.completions == CompletionShell.fish);
        assert(build.args.output.length == 0);
    }

    {
        String[4] argv = ["tool", "build", "--output", "app"];
        auto result = parseArgs!TerminalRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasInvocation);
        auto build = result.invocation.command!TerminalBuildArgs;
        assert(build !is null);
        assert(build.args.output == "app");
        assert(build.args.completions == CompletionShell.init);
    }

    {
        String[4] argv = ["tool", "build", "--completions", "wat"];
        auto result = parseArgs!TerminalRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(!result.hasTerminal);
        assert(result.error.kind == CliErrorKind.invalidValue);
        assert(result.error.token == "wat");
    }

    {
        String[3] argv = ["tool", "--wat", "--help"];
        auto result = parseArgs!TerminalRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.failed);
        assert(!result.hasTerminal);
        assert(result.error.kind == CliErrorKind.unknownOption);
    }

    {
        String[3] argv = ["tool", "-vhv", "build"];
        auto result = parseArgs!TerminalRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasTerminal);
        assert(result.parsed.args.verbose == 1);
        assert(result.parsed.args.help);
        assert(!result.parsed.hasCommand);
    }

    {
        String[2] argv = ["tool", "--help"];
        auto result = parseArgs!RootArgs(argv);
        scope (exit)
            result.deinit();

        assert(result.hasBuiltinResponse);
        assert(!result.hasTerminal);
        assert(!result.hasInvocation);
        assert(!result.failed);
    }
}

private void testParentPositionalsBeforeSubcommands()
{
    static assert(__traits(compiles, parseArgs!ParentPositionalRootArgs(cast(String[]) null)));
    static assert(__traits(compiles, parseArgs!FlattenedParentPositionalRootArgs(cast(String[]) null)));
    static assert(!__traits(compiles,
            parseArgs!InvalidOptionalParentPositionalArgs(cast(String[]) null)));
    static assert(!__traits(compiles,
            parseArgs!InvalidRepeatedParentPositionalArgs(cast(String[]) null)));
    static assert(!__traits(compiles,
            parseArgs!InvalidRestParentPositionalArgs(cast(String[]) null)));
    static assert(!__traits(compiles,
            parseArgs!InvalidDefaultParentPositionalArgs(cast(String[]) null)));
    static assert(!__traits(compiles,
            parseArgs!InvalidDefaultInputParentPositionalArgs(cast(String[]) null)));

    // The parent prefix is required before command matching begins.
    {
        String[1] argv = ["tool"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingPositional);
        assert(result.error.fieldIndex == 0);
    }

    {
        String[6] argv = ["tool", "workspace", "build", "target", "--output", "out"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.workspace == "workspace");
        auto build = result.invocation.command!ParentPositionalBuildArgs;
        assert(build !is null);
        assert(build.args.target == "target");
        assert(build.args.output == "out");
    }

    // Command aliases become eligible at the same boundary as canonical names.
    {
        String[6] argv = ["tool", "workspace", "b", "target", "--output", "out"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.workspace == "workspace");
        assert(result.invocation.command!ParentPositionalBuildArgs !is null);
    }

    // Options remain parseable before and within the required positional prefix.
    {
        String[6] argv = ["tool", "-vv", "workspace", "build", "target", "--output"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingOptionValue);
        assert(result.parsed.args.workspace == "workspace");
        assert(result.parsed.args.verbose == 2);
    }

    {
        String[4] argv = ["tool", "workspace", "-v", "test"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.workspace == "workspace");
        assert(result.invocation.args.verbose == 1);
        assert(result.invocation.command!ParentPositionalTestArgs !is null);
    }

    {
        String[5] argv = ["tool", "acme", "-vv", "rocket", "show"];
        auto result = parseArgs!FlattenedParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.context.organization == "acme");
        assert(result.invocation.args.context.project == "rocket");
        assert(result.invocation.args.verbose == 2);
        assert(result.invocation.command!FlattenedParentPositionalChildArgs !is null);
    }

    // A token matching a command name or alias is still a positional until the
    // complete fixed prefix has been consumed.
    {
        String[2] argv = ["tool", "build"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.parsed.args.workspace == "build");
        assert(result.error.kind == CliErrorKind.missingCommand);
    }

    {
        String[4] argv = ["tool", "show", "rocket", "show"];
        auto result = parseArgs!FlattenedParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.context.organization == "show");
        assert(result.invocation.args.context.project == "rocket");
        assert(result.invocation.command!FlattenedParentPositionalChildArgs !is null);
    }

    {
        String[2] argv = ["tool", "acme"];
        auto result = parseArgs!FlattenedParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingPositional);
        assert(result.parsed.args.context.organization == "acme");
    }

    // `--` preserves the existing command semantics while allowing a leading
    // dash in a parent positional.
    {
        String[4] argv = ["tool", "--", "-workspace", "test"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.workspace == "-workspace");
        assert(result.invocation.command!ParentPositionalTestArgs !is null);
    }

    {
        String[4] argv = ["tool", "workspace", "--", "test"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.workspace == "workspace");
        assert(result.invocation.command!ParentPositionalTestArgs !is null);
    }

    // Once the prefix is complete, an unmatched bare token is a command error.
    {
        String[3] argv = ["tool", "workspace", "wat"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.unknownCommand);
        assert(result.error.token == "wat");
    }

    // Child requiredness is checked only after the parent prefix and command
    // have been consumed.
    {
        String[3] argv = ["tool", "workspace", "build"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingPositional);
        assert(result.error.commandDepth == 1);
    }

    {
        String[4] argv = ["tool", "workspace", "build", "target"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingRequiredOption);
        assert(result.error.commandDepth == 1);
    }

    // Nested commands independently apply their own fixed parent prefix.
    {
        String[6] argv = ["tool", "acme", "project", "rocket", "-q", "build"];
        auto result = parseArgs!NestedParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.organization == "acme");
        auto group = result.invocation.command!NestedParentPositionalGroupArgs;
        assert(group !is null);
        assert(group.args.project == "rocket");
        assert(group.args.quiet);
        assert(group.command!NestedParentPositionalLeafArgs !is null);
    }

    {
        String[4] argv = ["tool", "acme", "project", "build"];
        auto result = parseArgs!NestedParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        auto group = result.parsed.command!NestedParentPositionalGroupArgs;
        assert(group !is null);
        assert(group.args.project == "build");
        assert(result.error.kind == CliErrorKind.missingCommand);
    }

    // Custom one-token value representations work in the fixed prefix.
    {
        String[3] argv = ["tool", "443", "serve"];
        auto result = parseArgs!CustomParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.port.value == 443);
        assert(result.invocation.command!CustomParentPositionalChildArgs !is null);
    }

    {
        String[3] argv = ["tool", "bad", "serve"];
        auto result = parseArgs!CustomParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.invalidValue);
        assert(result.error.token == "bad");
    }

    // Flattened positionals participate in the same declaration-order prefix.
    {
        String[4] argv = ["tool", "acme", "rocket", "show"];
        auto result = parseArgs!FlattenedParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.context.organization == "acme");
        assert(result.invocation.args.context.project == "rocket");
        assert(result.invocation.command!FlattenedParentPositionalChildArgs !is null);
    }

    // Explicit built-in and terminal outcomes still short-circuit ordinary
    // requiredness, including an incomplete parent positional prefix.
    {
        String[2] argv = ["tool", "--help"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasBuiltinResponse);
        assert(!result.failed);
    }

    {
        String[3] argv = ["tool", "workspace", "--help"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasBuiltinResponse);
        assert(result.parsed.args.workspace == "workspace");
    }

    {
        String[2] argv = ["tool", "--done"];
        auto result = parseArgs!ParentPositionalTerminalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasTerminal);
        assert(result.parsed.args.done);
        assert(result.parsed.args.workspace.length == 0);
    }

    {
        String[3] argv = ["tool", "workspace", "--done"];
        auto result = parseArgs!ParentPositionalTerminalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasTerminal);
        assert(result.parsed.args.done);
        assert(result.parsed.args.workspace == "workspace");
    }

    // Missing-subcommand policies do not weaken the required parent prefix.
    {
        String[3] argv = ["tool", "--config", "config.toml"];
        auto result = parseArgs!ParentPositionalHelpRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingPositional);
    }

    {
        String[4] argv = ["tool", "--config", "config.toml", "workspace"];
        auto result = parseArgs!ParentPositionalHelpRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(!result.failed);
        assert(!result.hasInvocation);
        assert(result.parsed.args.config == "config.toml");
        assert(result.parsed.args.workspace == "workspace");
    }

    {
        String[1] argv = ["tool"];
        auto result = parseArgs!OptionalParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingPositional);
    }

    {
        String[2] argv = ["tool", "workspace"];
        auto result = parseArgs!OptionalParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.hasInvocation);
        assert(result.invocation.args.workspace == "workspace");
        assert(!result.invocation.hasCommand);
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!ParentPositionalRootArgs(writer, "tool");
        assert(writer.result.ok);
        assert(contains(output.text, "Usage: tool [OPTIONS] <WORKSPACE> <COMMAND>"));
        assert(contains(output.text, "Arguments:"));
        assert(contains(output.text, "<WORKSPACE>"));
        assert(contains(output.text, "Workspace to operate on"));
        assert(contains(output.text, "Commands:"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(ParentPositionalRootArgs, ParentPositionalBuildArgs)(writer, "tool");
        assert(writer.result.ok);
        assert(contains(output.text,
                "Usage: tool <WORKSPACE> build --output <OUTPUT> [OPTIONS] <TARGET>"));
    }

    {
        String[2] argv = ["tool", "workspace"];
        auto result = parseArgs!ParentPositionalRootArgs(argv);
        scope (exit)
            result.deinit();
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.missingCommand);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) != 0);
        assert(outputWriter.result.ok);
        assert(errorWriter.result.ok);
        assert(contains(errors.text, "Usage: tool [OPTIONS] <WORKSPACE> <COMMAND>"));
    }
}

private void testTerminalCleanup()
{
    AllocationRecord[16] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    String[7] argv = [
        "tool",
        "--item",
        "first",
        "--done",
        "--item",
        "second",
        "ignored",
    ];
    auto result = parseArgs!TerminalAllocArgs(argv, allocator.allocator);
    assert(result.hasTerminal);
    assert(result.parsed.args.done);
    assert(result.parsed.args.item.length == 1);
    assert(result.parsed.args.item[0] == "first");
    result.deinit();
    assert(allocator.clean);
}

private void testRepeatedAndRestArgumentsCleanUp()
{
    AllocationRecord[16] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    {
        String[8] argv = [
            "tool",
            "run",
            "-Da",
            "-Db",
            "app",
            "--",
            "-x",
            "value",
        ];
        auto result = parseArgs!AllocRootArgs(argv, allocator.allocator);
        assert(result.hasInvocation);
        auto run = result.invocation.command!RunArgs;
        assert(run !is null);
        assert(run.args.defines.length == 2);
        assert(run.args.defines[0] == "a");
        assert(run.args.defines[1] == "b");
        assert(run.args.program == "app");
        assert(run.args.arguments.length == 2);
        assert(run.args.arguments[0] == "-x");
        assert(run.args.arguments[1] == "value");
        result.deinit();
        assert(allocator.clean);
    }

    {
        String[5] argv = ["tool", "run", "-Da", "app", "--unknown"];
        auto result = parseArgs!AllocRootArgs(argv, allocator.allocator);
        assert(result.failed);
        assert(result.error.kind == CliErrorKind.unknownOption);
        result.deinit();
        assert(allocator.clean);
    }
}

private void testAllocationFailureCleansUp()
{
    AllocationRecord[8] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    allocator.failAfter(0);

    String[4] argv = ["tool", "run", "-Da", "app"];
    auto result = parseArgs!AllocRootArgs(argv, allocator.allocator);
    assert(result.failed);
    assert(result.error.kind == CliErrorKind.allocationFailed);
    result.deinit();
    assert(allocator.clean);
}

extern (C) int main()
{
    testFlattenedArguments();
    testParentPositionalsBeforeSubcommands();
    testRequirednessAndDefaults();
    testExplicitTypedTraversal();
    testNestedCommandsAndChildVersionOption();
    testDefaultsAndOptionalCommand();
    testRequiredAndDuplicateErrors();
    testRequiredCommand();
    testHelpOnMissingSubcommand();
    testUnknownAndInvalidValues();
    testAliases();
    testNegatableBooleans();
    testPublicGeneratedHelp();
    testAnsiRendering();
    testGeneratedHelpAndVersion();
    testGeneratedErrorResponse();
    testDisabledBuiltinHelp();
    testDisabledBuiltinVersion();
    testCustomValueParsers();
    testCustomValueParserErrors();
    testAllocatorCustomValueParserCleanup();
    testTerminalArguments();
    testTerminalCleanup();
    testRepeatedAndRestArgumentsCleanUp();
    testAllocationFailureCleansUp();
    return 0;
}
