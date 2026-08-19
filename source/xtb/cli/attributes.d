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

struct CliPositional
{
}

struct CliRequired
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

/// Selects an application-defined parser for this field.
///
/// The parser must return `CliValueError` and accept either `(scope String, T*)`
/// or `(scope String, Allocator*, T*)`. For `Option!T` and `Array!T`, a parser
/// targeting `T*` parses the contained/repeated element. A parser targeting the
/// full field type parses the whole field from one command-line value. Exactly
/// one compatible parser target/signature must exist.
struct CliParseWith(alias Parser)
{
    enum isCliParseWith = true;
    alias parser = Parser;
}

/// Creates a `CliParseWith` attribute for `Parser`.
template cliParseWith(alias Parser)
{
    enum cliParseWith = CliParseWith!Parser();
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

enum cliPositional = CliPositional();
enum cliRequired = CliRequired();
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
