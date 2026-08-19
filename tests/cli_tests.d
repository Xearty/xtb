module tests.cli_tests;

nothrow @nogc:

import xtb.cli;
import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.array : Array;
import xtb.core.lifetime : moveAssign;
import xtb.core.memory : Allocator;
import xtb.core.option : Option;
import xtb.core.print : Writer;
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
        assert(writer.finish().ok);

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
        assert(writer.finish().ok);
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
        assert(writer.finish().ok);
        assert(!contains(output.text, "internal"));
        assert(!contains(output.text, "default:"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!HiddenPositionalArgs(writer, "tool");
        assert(writer.finish().ok);
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
    {
        String[1] argv = ["/usr/local/bin/tool"];
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
        assert(outputWriter.finish().ok);
        assert(errorWriter.finish().ok);
        assert(errors.text.length == 0);
        assert(contains(output.text, "Choose a command"));
        assert(contains(output.text, "Usage: tool --config <CONFIG> <COMMAND>"));
        assert(contains(output.text, "group"));
        assert(!contains(output.text, "Show this help"));
    }

    {
        String[2] argv = ["tool", "group"];
        auto result = parseArgs!HelpOnMissingRootArgs(argv);
        scope (exit)
            result.deinit();

        assert(!result.hasInvocation);
        assert(!result.failed);
        assert(result.invocation.command!HelpOnMissingGroupArgs !is null);

        TextSink output;
        TextSink errors;
        Writer outputWriter = Writer.fromSink(&textSink, &output);
        Writer errorWriter = Writer.fromSink(&textSink, &errors);
        assert(writeCliResult(outputWriter, errorWriter, result) == 0);
        assert(outputWriter.finish().ok);
        assert(errorWriter.finish().ok);
        assert(errors.text.length == 0);
        assert(contains(output.text, "Choose a group command"));
        assert(contains(output.text, "Usage: tool --config <CONFIG> group <COMMAND>"));
        assert(contains(output.text, "run"));
        assert(!contains(output.text, "Show this help"));
    }

    {
        String[2] argv = ["tool", "wat"];
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
        assert(writer.finish().ok);

        assert(contains(output.text, "Usage: tool (--color|--no-color) [OPTIONS]"));
        assert(contains(output.text, "Required options:"));
        assert(contains(output.text, "--color"));
        assert(contains(output.text, "negatable: --no-color"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!NegatableArgs(writer, "tool");
        assert(writer.finish().ok);

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
        assert(writer.finish().ok);

        assert(contains(output.text, "Usage: tool --output <OUTPUT>"));
        assert(!contains(output.text, "[OPTIONS]"));
        assert(contains(output.text, "Required options:"));
        assert(!contains(output.text, "Optional options:"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(RequiredGlobalRootArgs, RequiredGlobalChildArgs)(writer, "tool");
        assert(writer.finish().ok);

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
        assert(writer.finish().ok);

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
        assert(builtinWriter.finish().ok);
        assert(errorWriter.finish().ok);
        assert(errors.text.length == 0);
        assert(output.text == builtinOutput.text);
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(CustomHelpRootArgs, CustomHelpChildArgs)(writer, "tool");
        assert(writer.finish().ok);

        assert(contains(output.text, "Usage: tool [OPTIONS] child [OPTIONS]"));
        assert(contains(output.text, "-h, --help"));
        assert(!contains(output.text, "Show this help"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(RootArgs, BuildArgs)(writer, "tool");
        assert(writer.finish().ok);

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
        assert(writer.finish().ok);

        assert(contains(output.text, "--jobs <JOBS>"));
        assert(contains(output.text, "aliases: --parallelism"));
        assert(contains(output.text, "values: auto"));
        assert(contains(output.text, "default: auto"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(AliasRootArgs)(writer, "tool");
        assert(writer.finish().ok);

        assert(contains(output.text, "remove"));
        assert(contains(output.text, "Remove an item"));
        assert(contains(output.text, "aliases: rm, del"));
        assert(contains(output.text, "list"));
        assert(contains(output.text, "aliases: ls"));
        assert(contains(output.text, "-v, --verbose"));
        assert(contains(output.text, "aliases: -V, -Q, --verbosity, --chatty"));
        assert(contains(output.text, "--color"));
        assert(contains(output.text, "aliases: --colour"));
    }

    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(AliasRootArgs, AliasRemoveArgs)(writer, "tool");
        assert(writer.finish().ok);

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
        assert(plainWriter.finish().ok);
        assert(!contains(plain.text, "\x1b["));

        TextSink styled;
        Writer styledWriter = Writer.fromSink(&textSink, &styled);
        writeHelp!OverrideBuiltInValueArgs(styledWriter, "tool", true);
        assert(styledWriter.finish().ok);
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
        assert(outputWriter.finish().ok);
        assert(errorWriter.finish().ok);
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
        assert(outputWriter.finish().ok);
        assert(errorWriter.finish().ok);
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
        assert(outputWriter.finish().ok);
        assert(errorWriter.finish().ok);
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
        outputWriter.finish();
        errorWriter.finish();
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
    outputWriter.finish();
    errorWriter.finish();

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
        outputWriter.finish();
        errorWriter.finish();
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
        outputWriter.finish();
        errorWriter.finish();
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
        assert(outputWriter.finish().ok);
        assert(errorWriter.finish().ok);
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
        assert(outputWriter.finish().ok);
        assert(errorWriter.finish().ok);
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
        assert(outputWriter.finish().ok);
        assert(errorWriter.finish().ok);
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
