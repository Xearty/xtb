module xtb.cli.attributes;

nothrow @nogc:

/// Declares the command-line name of a subcommand argument type.
struct CliCommand
{
    string name;
}

/// Short description shown in generated help.
struct CliAbout
{
    string text;
}

/// Application version attached to the root argument type.
struct CliVersion
{
    string value;
}

/// Disables generated -h/--help handling for the entire command tree.
struct CliNoBuiltinHelp
{
}

/// Disables generated root --version handling while retaining version metadata.
struct CliNoBuiltinVersion
{
}

/// Description shown next to an argument in generated help.
struct CliHelp
{
    string text;
}

/// Overrides the inferred long option name.
struct CliLongName
{
    string value;
}

/// Adds an alternate long option name or subcommand name.
struct CliAliasName
{
    string value;
}

/// Adds an explicit one-code-unit short option name.
struct CliShortName
{
    char value;
}

/// Adds an alternate one-code-unit short option name.
struct CliShortAlias
{
    char value;
}

/// Overrides the generated value placeholder used by help text.
struct CliValueName
{
    string value;
}

/// Declares possible value spellings shown in generated help.
///
/// This is help metadata only; parsing remains authoritative.
struct CliPossibleValues(Values...)
{
    enum isCliPossibleValues = true;
    enum values = Values;
}

/// Creates a `CliPossibleValues` attribute.
template cliPossibleValues(Values...)
{
    enum cliPossibleValues = CliPossibleValues!Values();
}

struct CliPositional
{
}

/// Uses the field's initialized D value when the argument is omitted.
struct CliDefault
{
}

/// Parses this command-line spelling at runtime when the argument is omitted.
struct CliDefaultInput
{
    string value;
}

/// Suppresses default-value metadata in generated help.
struct CliHideDefault
{
}

struct CliCount
{
}

struct CliGlobal
{
}

struct CliRest
{
}

/// Omits this argument from generated help while leaving it fully parseable.
///
/// Hidden arguments must be omittable; a required argument may not be hidden
/// because generated help would provide no way to discover it.
struct CliHidden
{
}

/// Gives a named boolean option explicit positive and negative long forms.
///
/// `--name` selects true and `--no-name` selects false. Short names and
/// aliases remain positive-only spellings.
struct CliNegatable
{
}

/// Stops normal parsing after this named, non-repeating argument is successfully consumed.
struct CliTerminal
{
}

/// Selects an application-defined CLI value representation for this field.
///
/// The representation must expose a static `parse` operation returning
/// `CliValueError` and accepting either `(scope String, T*)` or
/// `(scope String, Allocator*, T*)`. For `Option!T` and `Array!T`, a parser
/// targeting `T*` parses the contained/repeated element. A parser targeting
/// the full field type parses the whole field from one command-line value.
///
/// The representation may additionally expose
/// `void format(ref Writer, scope const T*) nothrow @nogc` to provide the
/// canonical CLI spelling used for semantic default values.
struct CliValueWith(alias Representation)
{
    enum isCliValueWith = true;
    alias representation = Representation;
}

/// Creates a `CliValueWith` attribute for `Representation`.
template cliValueWith(alias Representation)
{
    enum cliValueWith = CliValueWith!Representation();
}

/// Allows a command with child commands to execute without selecting one.
struct CliSubcommandOptional
{
}

/// Shows generated help when a command with child commands reaches the end of argv without selecting one.
struct CliHelpOnNoSubcommand
{
}

CliCommand cliCommand(string name) pure @safe
{
    return CliCommand(name);
}

CliAbout cliAbout(string text) pure @safe
{
    return CliAbout(text);
}

CliVersion cliVersion(string value) pure @safe
{
    return CliVersion(value);
}

CliHelp cliHelp(string text) pure @safe
{
    return CliHelp(text);
}

CliLongName cliLongName(string value) pure @safe
{
    return CliLongName(value);
}

CliAliasName cliAliasName(string value) pure @safe
{
    return CliAliasName(value);
}

CliShortName cliShortName(char value) pure @safe
{
    return CliShortName(value);
}

CliShortAlias cliShortAlias(char value) pure @safe
{
    return CliShortAlias(value);
}

CliValueName cliValueName(string value) pure @safe
{
    return CliValueName(value);
}

CliDefaultInput cliDefaultInput(string value) pure @safe
{
    return CliDefaultInput(value);
}

enum cliPositional = CliPositional();
enum cliDefault = CliDefault();
enum cliHideDefault = CliHideDefault();
enum cliCount = CliCount();
enum cliGlobal = CliGlobal();
enum cliRest = CliRest();
enum cliHidden = CliHidden();
enum cliNegatable = CliNegatable();
enum cliTerminal = CliTerminal();
enum cliSubcommandOptional = CliSubcommandOptional();
enum cliHelpOnNoSubcommand = CliHelpOnNoSubcommand();
enum cliNoBuiltinHelp = CliNoBuiltinHelp();
enum cliNoBuiltinVersion = CliNoBuiltinVersion();
