module xtb.cli.attributes;

nothrow @nogc:

/// Declares the command-line name of a subcommand argument type.
struct Command
{
    string name;
}

/// Short description shown in generated help.
struct About
{
    string text;
}

/// Application version attached to the root argument type.
struct CliVersion
{
    string value;
}

/// Disables generated -h/--help handling for the entire command tree.
struct NoBuiltinHelp
{
}

/// Disables generated root --version handling while retaining version metadata.
struct NoBuiltinVersion
{
}

/// Description shown next to an argument in generated help.
struct Help
{
    string text;
}

/// Overrides the inferred long option name.
struct LongName
{
    string value;
}

/// Adds an explicit one-code-unit short option name.
struct ShortName
{
    char value;
}

/// Overrides the generated value placeholder used by help text.
struct ValueName
{
    string value;
}

struct Positional
{
}

struct Required
{
}

struct Count
{
}

struct Global
{
}

struct Rest
{
}

struct Hidden
{
}

/// Stops normal parsing after this named, non-repeating argument is successfully consumed.
struct Terminal
{
}

/// Selects an application-defined parser for this field.
///
/// The parser must return `CliValueError` and accept either `(scope String, T*)`
/// or `(scope String, Allocator*, T*)`. For `Option!T` and `Array!T`, a parser
/// targeting `T*` parses the contained/repeated element. A parser targeting the
/// full field type parses the whole field from one command-line value. Exactly
/// one compatible parser target/signature must exist.
struct ParseWith(alias Parser)
{
    enum isCliParseWith = true;
    alias parser = Parser;
}

/// Creates a `ParseWith` attribute for `Parser`.
template parseWith(alias Parser)
{
    enum parseWith = ParseWith!Parser();
}

/// Allows a command with child commands to execute without selecting one.
struct SubcommandOptional
{
}

/// Shows generated help when a command with child commands reaches the end of argv without selecting one.
struct HelpOnNoSubcommand
{
}

Command command(string name) pure @safe
{
    return Command(name);
}

About about(string text) pure @safe
{
    return About(text);
}

CliVersion cliVersion(string value) pure @safe
{
    return CliVersion(value);
}

Help help(string text) pure @safe
{
    return Help(text);
}

LongName longName(string value) pure @safe
{
    return LongName(value);
}

ShortName shortName(char value) pure @safe
{
    return ShortName(value);
}

ValueName valueName(string value) pure @safe
{
    return ValueName(value);
}

enum positional = Positional();
enum required = Required();
enum count = Count();
enum global = Global();
enum rest = Rest();
enum hidden = Hidden();
enum terminal = Terminal();
enum subcommandOptional = SubcommandOptional();
enum helpOnNoSubcommand = HelpOnNoSubcommand();
enum noBuiltinHelp = NoBuiltinHelp();
enum noBuiltinVersion = NoBuiltinVersion();
