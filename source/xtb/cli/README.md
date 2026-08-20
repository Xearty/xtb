# `xtb.cli`

`xtb.cli` is XTB's statically described command-line parser for `-betterC` D.
A struct describes a command, its fields describe arguments, and
`CliCommands!(...)` describes the statically known child-command tree.

The library is designed around the same constraints as the rest of XTB:

- `-betterC`;
- no GC and no exceptions;
- no runtime command registration or `TypeInfo`-based reflection;
- compile-time schema validation;
- borrowed `String` values where possible;
- explicit allocation only when storage is actually required;
- explicit cleanup through `CliParseResult.deinit`;
- typed command traversal after parsing;
- application-owned dispatch and terminal behavior.

The parser does not invoke command callbacks. It returns a typed parsed tree and
leaves normal application control flow explicit.

See [`ROADMAP.md`](ROADMAP.md) for proposed future work,
[`../../../design_spec/cli_requiredness_defaults.md`](../../../design_spec/cli_requiredness_defaults.md)
for the requiredness/default redesign, and
[`../../../design_spec/cli_flatten.md`](../../../design_spec/cli_flatten.md) for the
flattened argument-group design.

## Quick start

```d
module app;

nothrow @nogc:

import core.stdc.stdio : FILE, stderr, stdout;
import xtb.cli;
import xtb.core.option : Option;
import xtb.core.types : String;
import xtb.os.terminal : shouldUseAnsi;

@(cliVersion("1.0.0"), cliAbout("Small package tool"))
struct RootArgs
{
    @(cliShortName('v'), cliCount, cliGlobal, cliHelp("Increase verbosity"))
    uint verbose;

    @(cliNegatable, cliDefault, cliGlobal, cliHelp("Use colored output"))
    bool color = true;

    alias Commands = CliCommands!(BuildArgs, RemoveArgs);
}

@(cliCommand("build"), cliAliasName("b"), cliAbout("Build the package"))
struct BuildArgs
{
    @(cliShortName('j'), cliValueName("N"), cliDefault, cliHelp("Parallel jobs"))
    uint jobs = 4;

    @(cliShortName('o'), cliValueName("PATH"), cliHelp("Output directory"))
    String output; // required by default
}

@(cliCommand("remove"), cliAliasName("rm"), cliAbout("Remove a package"))
struct RemoveArgs
{
    @(cliPositional, cliValueName("PACKAGE"))
    String package_; // required positional

    @(cliValueName("REGISTRY"))
    Option!String registry; // optional; absence is preserved
}

extern (C) int main(int argc, char** argv)
{
    auto result = parseArgs!RootArgs(argc, argv);
    scope (exit) result.deinit();

    const outputAnsi = result.parsed.args.color && shouldUseAnsi(cast(FILE*) stdout);
    const errorAnsi = result.parsed.args.color && shouldUseAnsi(cast(FILE*) stderr);

    if (result.failed || result.hasBuiltinResponse)
        return handleCliResult(result, outputAnsi, errorAnsi);

    if (result.hasTerminal)
    {
        // Handle application-defined terminal behavior from result.parsed.
        return 0;
    }

    ref root = result.invocation;

    if (auto build = root.command!BuildArgs)
    {
        // root.args is RootArgs; build.args is BuildArgs.
        return 0;
    }

    if (auto remove = root.command!RemoveArgs)
    {
        String package_ = remove.args.package_;
        return 0;
    }

    return 0;
}
```

The intended result-handling flow is:

```d
if (result.failed || result.hasBuiltinResponse)
    return handleCliResult(result, outputAnsi, errorAnsi);

if (result.hasTerminal)
{
    // Application-owned terminal behavior.
}

ref root = result.invocation;
```

`result.parsed` is always the underlying parsed tree and may be partial for
terminal/error/built-in outcomes. `result.invocation` should only be used after
a normal invocation has been established.

## Command trees

Every child command is a struct with exactly one `@cliCommand(...)` attribute.
The root has no command name.

```d
struct RootArgs
{
    alias Commands = CliCommands!(BuildArgs, TestArgs);
}

@(cliCommand("build"), cliAbout("Build the project"))
struct BuildArgs
{
}

@(cliCommand("test"), cliAbout("Run tests"))
struct TestArgs
{
}
```

Commands may contain their own `CliCommands!(...)` lists.

```d
@cliCommand("dependency")
struct DependencyArgs
{
    alias Commands = CliCommands!(DependencyAddArgs, DependencyRemoveArgs);
}
```

Traversal is typed and only direct children are accepted:

```d
ref root = result.invocation;

if (auto dependency = root.command!DependencyArgs)
{
    if (auto add = dependency.command!DependencyAddArgs)
    {
        // add.args has type DependencyAddArgs.
    }
}
```

Exactly one child can be active at each command level.

## Flattened argument groups

`cliFlatten` lets a normal nested D struct contribute its fields directly to the
containing command's CLI namespace. Only the CLI schema is flattened; storage
remains nested.

```d
struct CompileOptions
{
    @(cliShortName('j'), cliDefault, cliHelp("Parallel jobs"))
    uint jobs = 8;

    Option!String compiler;
}

struct BuildArgs
{
    @cliFlatten
    CompileOptions compile;

    String output;
}
```

The CLI accepts the nested fields as ordinary `BuildArgs` options:

```text
tool build --output build/ --jobs 16 --compiler ldc2
```

while application code keeps the useful grouping:

```d
build.args.compile.jobs;
build.args.compile.compiler;
build.args.output;
```

Flattened groups may be nested recursively:

```d
struct LoggingOptions
{
    bool verbose;
}

struct CommonOptions
{
    @cliFlatten
    LoggingOptions logging;

    Option!String config;
}

struct Args
{
    @cliFlatten
    CommonOptions common;
}
```

The logical field order is the declaration order after expanding each flattened
field in place. This matters for positional arguments:

```d
struct Source
{
    @(cliPositional, cliValueName("SOURCE"))
    String source;
}

struct CopyArgs
{
    @(cliPositional, cliValueName("PREFIX"))
    String prefix;

    @cliFlatten
    Source input;

    @(cliPositional, cliValueName("DESTINATION"))
    String destination;
}
```

produces:

```text
Usage: tool <PREFIX> <SOURCE> <DESTINATION>
```

The nested fields retain all of their normal CLI semantics, including:

- requiredness and `Option!T`;
- `cliDefault`, `cliDefaultInput`, and `cliHideDefault`;
- aliases and short names;
- `cliGlobal`;
- `cliHidden` and `cliTerminal`;
- repeated/rest arguments;
- `cliNegatable` and `cliCount`;
- `cliValueWith` custom representations.

Collisions are checked in the resulting flat namespace, so a direct field and a
flattened field cannot claim the same option spelling.

The flatten target itself must be a direct struct-valued field:

```d
@cliFlatten
CommonOptions common; // valid
```

Pointers, `Option!Struct`, containers, and scalar fields are not flattenable.
The flatten field may not combine `cliFlatten` with other CLI field attributes;
put those attributes on the nested fields instead. A flattened group may contain
other flattened groups, but it may not declare `CliCommands` or carry CLI
type-level attributes. The group is an argument-composition value, not a hidden
command or policy scope.

No separate flatten-cycle detector is needed. Because flattening follows only
direct by-value struct fields, D's own finite-layout rules already reject the
recursive layouts that could form a cycle. Pointer/container recursion is not a
valid flatten target.

Flattening adds no runtime allocation or adapter object. XTB resolves each
logical argument to its nested field path at compile time and writes directly
into the existing nested `args` value.

## Requiredness and defaults

Requiredness is derived from the schema. There is no `cliRequired` attribute.

For ordinary value-taking scalar fields:

| Declaration | Meaning when omitted |
| --- | --- |
| `T value;` | parse error: required |
| `Option!T value;` | `none` |
| `@cliDefault T value;` | use the initialized D value |
| `@cliDefaultInput("text") T value;` | parse the declared text at runtime |

For example:

```d
String output; // required

Option!String compiler; // optional, absence survives

@cliDefault
uint jobs = 8; // optional semantic default

@cliDefaultInput("auto")
uint cacheBudget; // optional parser-derived default
```

The D implicit initializer is **not** itself a CLI default. A field such as:

```d
uint port;
```

is required, even though its initial D value is `0`.

`@cliDefault` is the explicit schema declaration that the initialized D value
should be accepted when the option is absent. This also makes `.init` defaults
unambiguous:

```d
@cliDefault
uint retries; // omitted -> 0
```

### `cliDefault`

`cliDefault` uses the semantic D value already present in the initialized
argument struct. Generated help normally formats that value:

```d
@(cliDefault, cliHelp("Parallel jobs"))
uint jobs = 8;
```

```text
--jobs <JOBS>  Parallel jobs
               default: 8
```

The default must have a CLI-facing representation. For custom values,
`cliValueWith` formatting is preferred; otherwise normal XTB `Writer`
formatting may be used.

If the default should intentionally not be visualized, use `cliHideDefault`:

```d
@(cliDefault, cliHideDefault)
InternalPolicy policy = ...;
```

This changes only generated help. The semantic default still exists.

### `cliDefaultInput`

`cliDefaultInput` declares a CLI spelling that is parsed through the normal
value parser when the argument is omitted:

```d
@(
    cliValueWith!CacheBudgetCli,
    cliDefaultInput("auto"),
)
uint cacheBudget;
```

The fallback text is validated **at runtime**, not by invoking application
parsers at compile time. Generated help displays the declared spelling directly:

```text
default: auto
```

A broken application-declared fallback produces `CliErrorKind.invalidDefault`.
Allocation failure remains an allocation failure.

`cliDefault` and `cliDefaultInput` are mutually exclusive. Defaults are also
invalid on `Option!T`, because `Option!T` promises that real absence can survive
a successful parse.

## Argument categories with intrinsic zero-occurrence semantics

Required-by-default applies to value-taking scalars. Some argument kinds
naturally have a zero-occurrence state and therefore remain omittable.

### Presence flags

```d
bool verbose;
```

```text
absent      -> false
--verbose   -> true
```

Named presence booleans do not accept `--verbose=true`.

### Count flags

```d
@(cliShortName('v'), cliCount)
uint verbose;
```

Zero occurrences produce zero; repeated occurrences increment the value.
Short clusters are supported, so `-vvv` counts three occurrences.

### Repeated values

```d
@(cliShortName('D'), cliValueName("NAME=VALUE"))
Array!String defines;
```

Repeated `Array!T` fields are zero-or-more and require an allocator when
storage must grow.

### Terminal arguments

`cliTerminal` is an optional trigger, even when its field takes a value:

```d
@(cliTerminal, cliValueName("SHELL"))
CompletionShell completions;
```

Omitting `--completions` does not make the command invalid. Supplying it parses
the value and then ends normal parsing with `result.hasTerminal == true`.

## Negatable booleans

`cliNegatable` gives a boolean explicit positive and negative long spellings.

A plain negatable `bool` is a required two-way choice:

```d
@cliNegatable
bool color;
```

```text
absent       -> error
--color      -> true
--no-color   -> false
```

A semantic default makes the choice optional:

```d
@(cliNegatable, cliDefault)
bool color = true;
```

An `Option!bool` preserves whether the user expressed a preference:

```d
@cliNegatable
Option!bool color;
```

```text
absent       -> none
--color      -> some(true)
--no-color   -> some(false)
```

Aliases and short names are positive-only. XTB does not synthesize negative
aliases such as `--no-colour` from `@cliAliasName("colour")`.

## Positionals and rest arguments

A positional is declared explicitly:

```d
@(cliPositional, cliValueName("PACKAGE"))
String package_;
```

Requiredness follows the same scalar model:

```d
@(cliPositional, cliValueName("INPUT"))
String input; // required

@(cliPositional, cliValueName("FILTER"))
Option!String filter; // optional
```

A repeated positional can consume the rest of argv:

```d
@(cliPositional, cliRest, cliValueName("ARG"))
Array!String arguments;
```

`--` ends option recognition and is useful before forwarded/rest arguments.

Commands with child commands may declare required fixed-count positionals.
Those positionals are consumed in declaration order before a bare token can
select a child command:

```d
struct RootArgs
{
    @(cliPositional, cliValueName("WORKSPACE"))
    String workspace;

    alias Commands = CliCommands!(BuildArgs, TestArgs);
}
```

```text
tool my-workspace build
tool my-workspace test
```

Optional, defaulted, repeated, and rest parent positionals are rejected because
they would make the positional/command boundary ambiguous. A token that happens
to equal a command name is still consumed as a parent positional until all
required parent positionals are satisfied. Thus `tool build` above means
`WORKSPACE="build"` followed by a missing-command error. Named and global
options may still appear around the parent positional prefix.

## Naming and aliases

Field identifiers are normalized to kebab-case:

```d
bool dryRun;            // --dry-run
uint worker_count;      // --worker-count
```

Canonical spelling can be overridden and aliases added:

```d
@(
    cliLongName("directory"),
    cliAliasName("cwd"),
    cliAliasName("working-directory"),
    cliShortName('C'),
)
Option!String directory;
```

This accepts `-C`, `--directory`, `--cwd`, and `--working-directory` as the
same logical field. Duplicate detection is logical rather than spelling-based.

Commands support aliases too:

```d
@(cliCommand("remove"), cliAliasName("rm"), cliAliasName("delete"))
struct RemoveArgs
{
}
```

Canonical names remain the names used for command identity, usage paths, and
primary help labels.

## Global arguments

`cliGlobal` makes a named field available while parsing descendant commands:

```d
@(cliShortName('v'), cliCount, cliGlobal)
uint verbose;
```

Inherited globals remain stored on the command level that declared them.
Collisions with descendant option spellings are rejected at compile time.

## Hidden arguments

`cliHidden` keeps an argument parseable but removes it from generated help,
including positional usage rendering.

```d
@(cliHidden, cliGlobal)
bool internalTrace;
```

Hidden arguments are useful for compatibility, diagnostics, or intentionally
undocumented internal switches.

A hidden argument must be omittable. This is rejected:

```d
@cliHidden
String secret; // invalid: required but undiscoverable
```

These are valid:

```d
@cliHidden
bool trace;

@cliHidden
Option!String internalMode;

@(cliHidden, cliDefault)
uint internalLimit = 32;
```

Because the entire field is hidden, a hidden semantic default does not require
a formatter merely for help visualization. `cliHideDefault` is therefore not
needed just because the whole argument uses `cliHidden`.

## Custom CLI values

`cliValueWith!Representation` groups a custom value's CLI parser and optional
formatter.

```d
struct DurationCli
{
    static CliValueError parse(
        scope String input,
        Duration* output,
    ) nothrow @nogc
    {
        // ...
    }

    static void format(
        ref Writer writer,
        scope const Duration* value,
    ) nothrow @nogc
    {
        // ...
    }
}

@cliValueWith!DurationCli
Duration timeout;
```

Accepted parse signatures are:

```d
CliValueError parse(scope String input, T* output) nothrow @nogc;

CliValueError parse(
    scope String input,
    Allocator* allocator,
    T* output,
) nothrow @nogc;
```

The allocator requirement is inferred from the signature and contributes to
`cliNeedsAllocator!Args`.

For `Option!T` and `Array!T`, the parser target determines whether the
representation applies to the element or the whole field. A parser targeting
`T*` parses the contained/repeated value; a parser targeting the full field
type parses the entire field from one argv value. Ambiguous representation
signatures are schema errors.

The optional formatter has the form:

```d
static void format(
    ref Writer writer,
    scope const T* value,
) nothrow @nogc;
```

It defines the canonical CLI-facing representation used when a semantic
`cliDefault` must be shown in help.

`CliValueError.message` is borrowed. If non-empty, its storage must remain valid
until the containing `CliParseResult` is deinitialized; string literals are the
simplest safe choice.

## Built-in help and version

The root may declare metadata:

```d
@(
    cliVersion("2.4.1"),
    cliAbout("Package manager"),
)
struct RootArgs
{
}
```

By default XTB owns:

```text
-h, --help
--version
```

Disable them independently with:

```d
@cliNoBuiltinHelp
struct RootArgs { }

@cliNoBuiltinVersion
struct RootArgs { }
```

Disabling a built-in also releases its spelling for application arguments.
`cliVersionOf!T` exposes version metadata independently of whether automatic
`--version` handling is enabled.

## Missing-subcommand policy

A command with children normally requires one child command.

Two alternate policies exist:

```d
@cliSubcommandOptional
struct RootArgs
{
    alias Commands = CliCommands!(...);
}
```

allows a normal invocation with no child.

```d
@cliHelpOnNoSubcommand
struct RootArgs
{
    alias Commands = CliCommands!(...);
}
```

returns generated help when argv ends without a child command, but only after
all required fields on the active command path have been satisfied. Missing
required options or positionals therefore produce their normal diagnostics
instead of being replaced by help. Explicit built-in or terminal outcomes still
short-circuit normal requiredness.

The two policies are mutually exclusive.

## Terminal arguments

`cliTerminal` lets the application define a successful parser outcome that
stops normal parsing after an argument is consumed:

```d
@(cliTerminal, cliValueName("SHELL"))
CompletionShell completions;
```

After successful consumption:

- `result.hasTerminal` is true;
- `result.hasInvocation` is false;
- `result.parsed` exposes the partial typed tree;
- remaining argv is ignored;
- later required/default/subcommand validation is skipped.

Errors that occur before the terminal argument still win. An invalid terminal
value remains an error.

Terminal arguments are named, non-repeating triggers. They cannot be
positional, `cliCount`, repeated arrays, or defaulted.

## Generated help

Public help rendering is available independently of the built-in `--help`
interception:

```d
writeHelp!RootArgs(writer, programPath);
writeHelp!(RootArgs, DependencyArgs, DependencyAddArgs)(writer, programPath);
```

The command path is compile-time validated. `programPath` is normalized to a
program basename internally.

Help is canonical-first. Requiredness is structural rather than buried in
metadata: required named options are written explicitly in the usage string and
listed under `Required options:`, while omittable named options are listed under
`Optional options:`. Required and optional globals are similarly split into
`Required global options:` and `Optional global options:`.

Aliases, negation, values, and defaults remain secondary metadata. When an
entry has no description, its first metadata item occupies the normal detail
column on the canonical-name line; remaining metadata continues below it.

Typical shape:

```text
Usage: tool build --output <PATH> [OPTIONS]

Required options:
  -o, --output <PATH>  Output path
                       aliases: --destination

Optional options:
  -j, --jobs <N>       Number of parallel jobs
                       aliases: --parallelism
                       default: 8

      --mode <MODE>    Build mode
                       values: debug, release-safe, release-fast
                       default: debug
```

The usage notation follows these rules:

- required named options are shown explicitly using their canonical long name;
- a required negatable boolean is shown as `(--color|--no-color)`;
- `[OPTIONS]` appears only when that usage scope accepts at least one visible
  optional named option; built-in `--help`/`--version` and visible optional globals
  count as optional options;
- parent-local `[OPTIONS]` appears before the child command because those options
  belong to the parent scope;
- required positionals use `<NAME>` in both usage and the `Arguments:` section;
- optional positionals use `[NAME]` in both places;
- rest positionals use `[NAME...]` in both places;
- positional arguments do not get a redundant `required` metadata line.

A nested command may therefore legitimately contain more than one `[OPTIONS]`
marker, for example:

```text
Usage: tool dependency [OPTIONS] add [OPTIONS] <PACKAGE>
```

The first marker belongs to `dependency`; the second belongs to `add` plus
visible globals/built-ins.

`cliPossibleValues!(...)` is help metadata only. It does not constrain custom
parsing.

## ANSI rendering

`xtb.cli` does not decide whether a terminal should receive ANSI escapes.
Rendering functions accept explicit booleans:

```d
writeHelp!Args(writer, programPath, ansi);

writeCliResult(
    output,
    errorOutput,
    result,
    outputAnsi,
    errorAnsi,
);

handleCliResult(result, outputAnsi, errorAnsi);
```

Application code can use `xtb.os.terminal.shouldUseAnsi` independently for
stdout and stderr:

```d
const outputAnsi = shouldUseAnsi(cast(FILE*) stdout);
const errorAnsi = shouldUseAnsi(cast(FILE*) stderr);
return handleCliResult(result, outputAnsi, errorAnsi);
```

This keeps environment/TTY policy outside `xtb.cli`. `shouldUseAnsi` already
handles terminal capability and `NO_COLOR` policy.

Built-in help/version are written to stdout. Parse diagnostics and error usage
are written to stderr.

## Allocation and lifetimes

Borrowed scalar strings normally refer directly to argv storage. The caller
must keep the argv/string input alive while using the parsed result.

Repeated arrays and allocator-aware custom representations may require an
`Allocator*`. The trait:

```d
enum needsAllocator = cliNeedsAllocator!Args;
```

is computed from the entire command tree.

When `cliNeedsAllocator!Args` is false:

```d
auto result = parseArgs!Args(argc, argv);
```

is available.

When allocation is required:

```d
auto result = parseArgs!Args(argc, argv, allocator);
```

must be used.

Always deinitialize the result:

```d
auto result = parseArgs!Args(...);
scope (exit) result.deinit();
```

The parsed command tree is non-copyable.

## Schema validation

The CLI schema is aggressively checked at compile time. Among other things,
XTB rejects:

- duplicate/conflicting option spellings;
- command alias collisions;
- collisions with enabled built-ins;
- inherited-global collisions;
- unsupported field types;
- malformed `cliValueWith` signatures;
- ambiguous whole-field/element parsers;
- defaults on `Option!T`, repeated/count/terminal/presence categories;
- both `cliDefault` and `cliDefaultInput` on one field;
- `cliHideDefault` without a default;
- required hidden arguments;
- invalid negatable combinations;
- invalid positional/rest ordering;
- command-policy attributes on leaf commands.

This is intentional: invalid CLI shapes should fail while compiling the schema,
not become runtime parser edge cases.

## Current limitations

Important current limitations are tracked in [`ROADMAP.md`](ROADMAP.md). The
most relevant today are:

- cross-argument relationships/groups are application validation;
- unknown-option/command diagnostics do not yet provide typo suggestions;
- shell completion scripts are not generated;
- help is aligned but does not yet perform terminal-width wrapping;
- dynamic/external subcommands are intentionally outside the planned scope.

## Examples and tests

The repository contains:

- `examples/cli_demo.d` — a feature-dense CLI including ANSI help;
- `examples/cli_nested_demo.d` — nested commands, repeated values, rest args;
- `tests/cli_tests.d` — parsing, schema, help, ANSI, allocation, cleanup, and
  cross-feature regression coverage.

Use:

```text
just targets
just run example cli -- --help
just run example cli-nested -- --help
```

Program arguments passed through `just run example` must follow the explicit
`--` separator.
