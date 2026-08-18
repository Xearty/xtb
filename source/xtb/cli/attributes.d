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

/// Allows a command with child commands to execute without selecting one.
struct AllowNoSubcommand
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
enum allowNoSubcommand = AllowNoSubcommand();
