# CLI guide

A command is a struct; fields describe its arguments and `CliCommands` describes
its child commands.

```d
@(cliVersion("1.0.0"), cliAbout("Package tool"))
struct Args
{
    @(cliShortName('v'), cliCount, cliGlobal)
    uint verbose;

    alias Commands = CliCommands!BuildArgs;
}

@cliCommand("build")
struct BuildArgs
{
    @(cliShortName('j'), cliDefault)
    uint jobs = 4;

    String output; // required by default
}
```

## Parse-result lifecycle

Keep the parse result alive while using anything reached through it:

```d
auto result = parseArgs!Args(argc, argv);
scope(exit) result.deinit();

if (result.failed || result.hasBuiltinResponse)
    return handleCliResult(result);

if (result.hasTerminal)
    return 0;

ref root = result.invocation;
if (auto build = root.command!BuildArgs)
{
    auto jobs = build.args.jobs;
}
```

`CliParseResult` has one outcome:

| State | Access |
|---|---|
| `failed` | inspect `error()` or pass to `handleCliResult` |
| `hasBuiltinResponse` | pass to `handleCliResult` |
| `hasTerminal` | use `parsed()` if the terminal option needs the partially parsed tree |
| `hasInvocation` | use the complete `invocation` tree |

A `cliTerminal` option stops normal parsing successfully, so `parsed()` may be
partial. Do not treat it as a complete invocation.

`ParsedCommand!T.args` is the typed payload for that command level;
`command!Child` traverses the one selected direct child.

## Ownership

Parsing `String` fields borrows the original argument text; `parseArgs` does not
copy `argv`. Keep the input storage valid while those strings are used.

Repeated `Array!T` fields and allocator-aware custom value parsers require the
allocator overload of `parseArgs`:

```d
auto result = parseArgs!Args(argc, argv, mallocAllocator());
scope(exit) result.deinit();
```

The result owns allocations/resources stored in its parsed tree and `deinit()`
recursively cleans fields that participate in XTB's deinit protocol. References
into the tree must not outlive the result.

A custom `CliValueError.message` is borrowed and must remain valid until the
parse result is deinitialized; string literals are appropriate for static error
messages.

## Common attributes

| Attribute | Meaning |
|---|---|
| `cliCommand` | command name |
| `cliPositional` | positional argument |
| `cliShortName`, `cliAliasName` | aliases |
| `cliHelp`, `cliAbout`, `cliValueName` | descriptive text |
| `cliDefault` | field initializer is the default |
| `cliCount` | repeated flag increments a counter |
| `cliNegatable` | positive/negative boolean forms |
| `cliGlobal` | argument is visible to descendants |
| `cliFlatten` | expose fields of a nested struct in the current CLI namespace |
| `cliRest` | consume remaining positional values |
| `cliHidden` | hide an argument from generated output |
| `cliTerminal` | stop normal parsing successfully |

Plain scalar fields are required unless their argument kind has natural
zero-occurrence semantics or a default is supplied. Use `Option!T` when the
application needs to distinguish absence from a value.

`cliFlatten` changes only the CLI schema; storage remains nested in the D struct.

For complete examples, see
[`cli_demo.d`](../../../examples/cli_demo.d) and
[`cli_nested_demo.d`](../../../examples/cli_nested_demo.d).
