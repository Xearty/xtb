# XTB CLI Flattened Argument Groups

## Status

**Implemented design.**

This document defines the implemented `cliFlatten` feature for `xtb.cli`.

The goal is to allow applications to compose reusable groups of CLI arguments as ordinary nested D structs while presenting those fields as part of the containing command's flat CLI namespace.

The design intentionally keeps storage nested and only flattens the **CLI schema**.

## 1. Motivation

Larger command-line applications often have groups of arguments that are shared between commands or that belong together conceptually.

Without flattening, the application has several unattractive options:

1. Duplicate the fields in every command.
2. Use D mixins/templates to physically inject fields into multiple structs.
3. Introduce artificial CLI hierarchy that does not match the actual command syntax.
4. Move unrelated arguments into the root/global namespace merely to reuse them.

For example:

```d
struct BuildArgs
{
    @(cliShortName('j'), cliDefault)
    uint jobs = 8;

    Option!String compiler;

    bool warnings;

    String output;
}

struct CheckArgs
{
    @(cliShortName('j'), cliDefault)
    uint jobs = 8;

    Option!String compiler;

    bool warnings;

    bool all;
}
```

With `cliFlatten`, the common fields can remain a reusable D value:

```d
struct CompileOptions
{
    @(cliShortName('j'), cliDefault)
    uint jobs = 8;

    Option!String compiler;

    bool warnings;
}

struct BuildArgs
{
    @cliFlatten
    CompileOptions compile;

    String output;
}

struct CheckArgs
{
    @cliFlatten
    CompileOptions compile;

    bool all;
}
```

The CLI namespace behaves as if the fields of `CompileOptions` were declared directly in each command.

Application storage remains structured:

```d
build.compile.jobs;
build.compile.compiler;
build.output;
```

The central design principle is:

> `cliFlatten` flattens the CLI schema, not the D object layout.

## 2. Proposed attribute

The proposed attribute is:

```d
@cliFlatten
NestedStruct field;
```

Example:

```d
struct CommonOptions
{
    bool verbose;

    Option!String config;

    @(cliDefault, cliValueName("N"))
    uint jobs = 8;
}

struct Args
{
    @cliFlatten
    CommonOptions common;

    String output;
}
```

Conceptually, the CLI schema is equivalent to declaring the nested fields directly in `Args`, but parsed values remain stored under `args.common`.

## 3. Flattening is schema-only

`cliFlatten` must not change the actual D field structure.

Given:

```d
struct NetworkOptions
{
    Option!String proxy;

    @cliDefault
    uint timeout = 30;
}

struct FetchArgs
{
    @cliFlatten
    NetworkOptions network;

    String url;
}
```

the application accesses:

```d
args.network.proxy;
args.network.timeout;
args.url;
```

It does **not** gain synthetic members such as `args.proxy` or `args.timeout`.

This keeps normal D semantics intact and avoids generated/mixin-based storage tricks.

## 4. Flattened fields preserve their semantics

Flattening should not reinterpret nested field declarations.

Example:

```d
struct Common
{
    String config;

    Option!String output;

    @cliDefault
    uint jobs = 8;

    bool verbose;

    @cliNegatable
    bool color;
}
```

When flattened, the meanings remain:

- `config`: required scalar.
- `output`: optional; absence preserved.
- `jobs`: optional; semantic default `8`.
- `verbose`: optional presence flag.
- `color`: required explicit `--color` / `--no-color` choice.

All existing rules for requiredness, defaults, aliases, globals, hidden/terminal arguments, custom values, count flags, repeated arguments, and positionals continue to apply exactly as if the field were declared directly in the containing command.

## 5. Named options

The most common use case is reusable named-option groups.

```d
struct CompileOptions
{
    @(cliShortName('j'), cliDefault)
    uint jobs = 8;

    Option!String compiler;

    bool warnings;
}

struct BuildArgs
{
    @cliFlatten
    CompileOptions compile;

    String output;
}
```

Possible help:

```text
Usage: tool build --output <OUTPUT> [OPTIONS]

Required options:
      --output <OUTPUT>  Output directory

Optional options:
  -j, --jobs <JOBS>      Maximum parallel compiler jobs
                         default: 8
      --compiler <VALUE> Compiler executable
      --warnings         Enable compiler warnings
  -h, --help             Show this help
```

There should be no visible indication that these options came from a nested struct.

## 6. Positionals

Flattening should support positional fields too.

```d
struct InputArguments
{
    @(cliPositional, cliValueName("INPUT"))
    String input;
}

struct ConvertArgs
{
    @cliFlatten
    InputArguments source;

    @(cliPositional, cliValueName("OUTPUT"))
    String output;
}
```

CLI:

```text
tool convert input.txt output.txt
```

Help:

```text
Usage: tool convert <INPUT> <OUTPUT>

Arguments:
  <INPUT>   Input file
  <OUTPUT>  Output file
```

The flattened struct's fields conceptually occupy the declaration position of the `@cliFlatten` field.

## 7. Declaration ordering

A flattened field is expanded **in place**.

Given:

```d
struct Group
{
    @cliPositional
    String second;

    bool verbose;
}

struct Args
{
    @cliPositional
    String first;

    @cliFlatten
    Group group;

    @cliPositional
    String third;
}
```

the logical schema order is:

```text
first
group.second
group.verbose
third
```

For named arguments, declaration order mainly affects deterministic help output.

For positionals, it determines parse order.

## 8. Recursive flattening

Nested flattening should be supported.

```d
struct OutputOptions
{
    Option!String output;
}

struct CompileOptions
{
    @cliFlatten
    OutputOptions output;

    @cliDefault
    uint jobs = 8;
}

struct BuildArgs
{
    @cliFlatten
    CompileOptions compile;

    bool release;
}
```

The resulting CLI namespace contains:

```text
--output
--jobs
--release
```

while application storage remains nested.

## 9. Recursive-cycle handling

The implementation deliberately does **not add explicit `cliFlatten` cycle detection**.

This is deliberate.

`cliFlatten` should only accept direct, by-value struct fields:

```d
@cliFlatten
CommonOptions common;
```

D already rejects infinitely recursive by-value layouts. A direct recursive struct or mutual by-value recursion cannot form a valid finite object layout.

Therefore an actual flatten cycle cannot exist among valid direct struct-valued fields.

The compiler already enforces the stronger underlying invariant:

> A by-value struct layout must be finite.

Adding independent CLI-specific visited-type/cycle-detection machinery would duplicate language-level validation without providing useful extra safety.

### 9.1 Pointer/reference cycles do not change this

Recursive structures using pointers are valid D:

```d
struct Node
{
    Node* next;
}
```

but pointer fields are not valid flatten targets:

```d
@cliFlatten
Node* next; // schema error
```

The same applies to:

```d
Option!Group
Group*
Array!Group
```

Only a direct struct value may be flattened.

Therefore pointer/container cycles never enter the flatten traversal.

### 9.2 Defensive recursion limits

No explicit semantic cycle detection is proposed.

If implementation templates ever need an instantiation-depth guard due to a compiler limitation, that should be treated as an implementation robustness detail rather than part of the public semantics.

## 10. Valid flatten targets

The initial rule should be simple:

> `cliFlatten` may only be applied to a direct struct-valued field.

Valid:

```d
struct Common
{
    bool verbose;
}

struct Args
{
    @cliFlatten
    Common common;
}
```

Invalid:

```d
@cliFlatten
Common* common;
```

```d
@cliFlatten
Option!Common common;
```

```d
@cliFlatten
Array!Common common;
```

```d
@cliFlatten
uint value;
```

## 11. Subcommands inside flattened structs

The implementation prohibits subcommands inside flattened structs.

```d
struct Common
{
    alias Commands = CliCommands!(FooArgs, BarArgs);
}

struct RootArgs
{
    @cliFlatten
    Common common;
}
```

This raises unnecessary questions around parsed command storage, typed traversal, help paths, and command-level policies.

The rule should be:

> A flattened struct may contain arguments and other flattened argument groups, but it may not declare `CliCommands`.

Subcommands remain part of the explicit command tree.

## 12. CLI type-level attributes

A flattened struct is an argument-composition value, not a hidden command or a
separate CLI schema scope. The flattened type itself therefore may not carry CLI
type-level attributes.

This includes command-level concepts such as `cliCommand`, `cliAbout`,
`cliVersion`, `cliSubcommandOptional`, `cliHelpOnNoSubcommand`,
`cliNoBuiltinHelp`, and `cliNoBuiltinVersion`, as well as field-oriented CLI
attributes incorrectly attached to the type. CLI attributes belong on the nested
fields that become logical arguments. Non-CLI type attributes from other
subsystems remain unaffected.

## 13. Attributes on the flatten field itself

The implementation keeps `cliFlatten` exclusive.

Preferred:

```d
@cliFlatten
CommonOptions common;
```

Do not initially allow propagation semantics such as:

```d
@(cliFlatten, cliGlobal)
CommonOptions common;
```

or:

```d
@(cliFlatten, cliHidden)
CommonOptions common;
```

Those would introduce attribute inheritance rules and override questions.

The initial rule should be:

> `cliFlatten` changes only schema nesting. All argument semantics are declared on the nested fields themselves.

The validator should reject unrelated CLI field attributes combined with `cliFlatten`.

## 14. Global arguments

Globals declared inside a flattened group should work normally.

```d
struct CommonGlobals
{
    @(cliGlobal, cliShortName('v'))
    bool verbose;

    @(cliGlobal, cliNegatable, cliDefault)
    bool color = true;
}

struct RootArgs
{
    @cliFlatten
    CommonGlobals common;

    alias Commands = CliCommands!(BuildArgs, TestArgs);
}
```

They are still root global arguments because their effective schema location is the root command.

## 15. Collision validation

All namespace/collision validation must happen **after conceptual flattening**.

```d
struct Common
{
    bool verbose;
}

struct Args
{
    @cliFlatten
    Common common;

    bool verbose;
}
```

must fail exactly as though both fields were declared directly.

This includes canonical long names, aliases, short names, generated negatable spellings, inherited globals, built-ins, and positional-layout restrictions.

Flattening must not create a separate namespace.

## 16. Requiredness and defaults

Flattened fields participate in the current requiredness/default design unchanged.

```d
struct Shared
{
    String toolchain;

    Option!String cacheDirectory;

    @cliDefault
    uint jobs = 8;

    @cliDefaultInput("auto")
    CacheBudget cacheBudget;
}
```

Flattening yields the same required/optional behavior and help sections as equivalent direct fields.

`cliFlatten` itself has no requiredness semantics.

## 17. Hidden arguments

A hidden field inside a flattened group behaves exactly like a direct hidden field.

```d
struct InternalOptions
{
    @cliHidden
    bool traceParser;
}
```

All current `cliHidden` validity rules still apply, including rejecting hidden required arguments.

## 18. Terminal arguments

Terminal arguments inside flattened groups should retain their existing semantics.

```d
struct DiagnosticsOptions
{
    @cliTerminal
    bool printSchema;
}
```

Flattening introduces no special terminal behavior.

## 19. Custom value representations

`cliValueWith` should compose naturally with flattening.

```d
struct TimeoutOptions
{
    @(
        cliValueWith!DurationCli,
        cliDefault,
    )
    Duration timeout = Duration.seconds(30);
}
```

The parser and help renderer treat it like a directly declared custom CLI value.

## 20. Runtime cost and lifetime behavior

Flattening should add no independent runtime allocation cost.

The nested struct already exists inside the parsed command struct. The parser simply writes to nested field storage.

No temporary flattened object, adapter container, or runtime name-to-path map should be created.

The flatten path should be compile-time information.

## 21. Internal field paths

Implementation traits will need to identify nested storage paths.

A direct field can be represented conceptually as:

```text
field index 3
```

A recursively flattened field may need:

```text
field 2 -> field 1 -> field 4
```

The internal schema representation should therefore support a compile-time field path instead of assuming every argument is one direct member access away from its command struct.

The exact representation is an implementation detail.

## 22. Parser implementation direction

A clean implementation should separate:

1. discovering logical CLI fields;
2. resolving each logical field's nested storage location.

Compile-time traversal can produce descriptors containing:

- owning command type;
- nested field path;
- effective field type;
- field UDAs;
- logical declaration order.

The existing parser/help/schema validation should then operate over that flattened descriptor sequence.

This is preferable to creating synthetic copied fields or special-case parser branches.

## 23. Help implementation direction

Help should use the same flattened logical-field sequence as parsing.

A flattened argument should be indistinguishable from a direct one for:

- required/optional section selection;
- aliases;
- defaults;
- possible values;
- ANSI styling;
- usage rendering;
- hidden filtering;
- global filtering.

`cliFlatten` should not create a visible group heading.

## 24. Future help grouping is separate

Flattening suggests a future feature such as:

```d
@(cliFlatten, cliHelpGroup("Compilation"))
CompileOptions compile;
```

but help grouping should **not** be part of the initial flatten implementation.

Schema flattening answers:

> Where does this field live in the CLI namespace?

Help grouping answers:

> How should this field be visually organized?

Those are separate concerns and should remain separately designed.

## 25. Interaction with other XTB metadata

`cliFlatten` is CLI-specific.

It must not imply flattening in Serde or any other subsystem.

If the same field should be flattened in multiple systems, each subsystem should declare that independently with its own namespaced attribute.

## 26. Invalid schemas

The implementation rejects:

- non-struct flatten targets;
- pointer targets;
- `Option!Struct` targets;
- container targets;
- flatten targets that declare subcommands;
- unsupported extra CLI attributes on the flatten field;
- namespace collisions after flattening.

No separate flatten-cycle schema error is needed because valid direct by-value structs cannot form such a cycle.

## 27. Examples

### 27.1 Reused compilation options

```d
struct CompileOptions
{
    @(cliShortName('j'), cliDefault)
    uint jobs = 8;

    Option!String compiler;

    bool warnings;
}

struct BuildArgs
{
    @cliFlatten
    CompileOptions compile;

    String output;
}

struct CheckArgs
{
    @cliFlatten
    CompileOptions compile;

    bool all;
}
```

Usage:

```text
tool build --output build/
tool build --output build/ -j 16
tool check --compiler clang
```

Application:

```d
build.compile.jobs;
build.compile.compiler;
build.output;

check.compile.jobs;
check.all;
```

### 27.2 Root global group

```d
struct GlobalOptions
{
    @(cliGlobal, cliShortName('v'))
    bool verbose;

    @(cliGlobal, cliNegatable, cliDefault)
    bool color = true;
}

struct RootArgs
{
    @cliFlatten
    GlobalOptions global;

    alias Commands = CliCommands!(BuildArgs, TestArgs);
}
```

### 27.3 Flattened positionals

```d
struct SourceArguments
{
    @(cliPositional, cliValueName("SOURCE"))
    String source;
}

struct CopyArgs
{
    @cliFlatten
    SourceArguments source;

    @(cliPositional, cliValueName("DESTINATION"))
    String destination;
}
```

Help:

```text
Usage: tool copy <SOURCE> <DESTINATION>

Arguments:
  <SOURCE>
  <DESTINATION>
```

### 27.4 Recursive flattening

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

struct BuildArgs
{
    @cliFlatten
    CommonOptions common;

    String output;
}
```

Storage remains nested:

```d
args.common.logging.verbose;
args.common.config;
args.output;
```

while the CLI namespace is flat.

## 28. Testing strategy

The feature should include focused tests for:

1. basic named-option flattening;
2. nested storage writes;
3. reuse of one flattened type in multiple commands;
4. recursive flattening;
5. declaration/help ordering;
6. required flattened scalars;
7. `Option!T`;
8. `cliDefault`;
9. `cliDefaultInput`;
10. `cliHideDefault`;
11. presence booleans;
12. required negatable booleans;
13. repeated arrays;
14. positional flattening/order;
15. rest positional interaction;
16. globals;
17. hidden fields;
18. terminal fields;
19. `cliValueWith`;
20. aliases and short aliases;
21. direct-vs-flattened collisions;
22. collisions between two flattened groups;
23. generated negatable-name collisions;
24. invalid target kinds;
25. subcommands inside flatten targets;
26. invalid extra attributes;
27. help output;
28. usage output;
29. ANSI/plain equivalence;
30. deinitialization/allocation behavior for allocator-backed nested fields.

No dedicated flatten-cycle test is necessary unless a valid-D type graph is found that can produce an actual by-value flatten cycle.

## 29. Documentation expectations

The CLI README should explain `cliFlatten` primarily as a composition feature:

```d
struct CommonOptions
{
    bool verbose;

    @cliDefault
    uint jobs = 8;
}

struct BuildArgs
{
    @cliFlatten
    CommonOptions common;
}
```

with the concise rule:

> `cliFlatten` splices the nested struct's fields into the containing CLI schema while preserving the nested D storage layout.

The roadmap should track help grouping separately.

## 30. Recommended initial scope

The implementation supports:

- direct struct-valued flatten targets;
- named options;
- positionals;
- repeated/rest fields;
- globals;
- hidden and terminal fields;
- required/default semantics;
- aliases;
- custom `cliValueWith` representations;
- recursive nested flattening;
- normal help/usage;
- collision/schema validation.

It intentionally does **not** support:

- flattening pointers;
- flattening `Option!Struct`;
- flattening containers of structs;
- subcommands inside flattened groups;
- propagating attributes from the flatten field;
- help groups;
- name prefixes such as `--compile-jobs`;
- runtime/dynamic flattening;
- special cycle-detection machinery.

## 31. Summary

The proposed API is:

```d
struct CommonOptions
{
    @(cliShortName('j'), cliDefault)
    uint jobs = 8;

    Option!String compiler;
}

struct BuildArgs
{
    @cliFlatten
    CommonOptions common;

    String output;
}
```

CLI:

```text
tool build --output build/ --jobs 16
```

Storage:

```d
args.common.jobs == 16;
args.output == "build/";
```

The nested struct disappears only from the **CLI schema**, not from the D object model.

Recursive flattening is allowed through nested direct struct values.

Explicit flatten-cycle detection is intentionally omitted because D already rejects recursive by-value struct layouts, while indirect pointer/container recursion is not eligible for `cliFlatten`.

The feature therefore provides reusable argument composition without mixins, synthetic storage, runtime adapters, or a second hierarchy in the CLI model.
