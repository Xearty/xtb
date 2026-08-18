module tests.cli_tests;

nothrow @nogc:

import xtb.cli;
import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.array : Array;
import xtb.core.option : Option;
import xtb.core.print : Writer;
import xtb.core.types : String;

enum BuildMode
{
    debug_,
    releaseSafe,
    releaseFast,
}

@(cliVersion("2.4.1"), about("CLI test application"), subcommandOptional)
struct RootArgs
{
    @(shortName('v'), count, global, help("Increase verbosity"))
    uint verbose;

    @(shortName('C'), global, valueName("DIR"), help("Change directory"))
    Option!String directory;

    alias Commands = CliCommands!(BuildArgs, DependencyArgs);
}

@(command("build"), about("Build the project"))
struct BuildArgs
{
    @(shortName('r'), help("Build with optimizations"))
    bool release;

    @(shortName('j'), valueName("N"), help("Parallel jobs"))
    uint jobs = 1;

    @(help("Build mode"))
    BuildMode mode = BuildMode.debug_;

    @(required, valueName("PATH"), help("Output path"))
    Option!String output;
}

@(command("dependency"), about("Manage dependencies"), subcommandOptional)
struct DependencyArgs
{
    @(valueName("URL"), help("Registry URL"))
    Option!String registry;

    alias Commands = CliCommands!(DependencyAddArgs, DependencyListArgs);
}

@(command("add"), about("Add a dependency"))
struct DependencyAddArgs
{
    @(positional, valueName("PACKAGE"))
    String package_;

    @(valueName("VERSION"), help("Dependency version"))
    Option!String version_;
}

@(command("list"), about("List dependencies"))
struct DependencyListArgs
{
    @(shortName('a'))
    bool all;
}

struct RequiredCommandRoot
{
    alias Commands = CliCommands!(RequiredCommandChild);
}

@command("child")
struct RequiredCommandChild
{
}

@(noBuiltinHelp, helpOnNoSubcommand, about("Choose a command"))
struct HelpOnMissingRootArgs
{
    @required
    Option!String config;

    alias Commands = CliCommands!(HelpOnMissingGroupArgs);
}

@(command("group"), helpOnNoSubcommand, about("Choose a group command"))
struct HelpOnMissingGroupArgs
{
    alias Commands = CliCommands!(HelpOnMissingLeafArgs);
}

@command("run")
struct HelpOnMissingLeafArgs
{
}

@subcommandOptional
struct InvalidOptionalLeafArgs
{
}

@helpOnNoSubcommand
struct InvalidHelpLeafArgs
{
}

@(subcommandOptional, helpOnNoSubcommand)
struct InvalidCombinedPolicyArgs
{
    alias Commands = CliCommands!(InvalidCombinedPolicyChildArgs);
}

@command("child")
struct InvalidCombinedPolicyChildArgs
{
}

@(subcommandOptional, cliVersion("1.0"))
struct AllocRootArgs
{
    @(shortName('v'), count, global)
    uint verbose;

    alias Commands = CliCommands!(RunArgs);
}

@command("run")
struct RunArgs
{
    @(shortName('D'), valueName("VALUE"))
    Array!String defines;

    @(positional, valueName("PROGRAM"))
    String program;

    @(positional, rest, valueName("ARG"))
    Array!String arguments;
}

@(noBuiltinHelp, subcommandOptional)
struct CustomHelpRootArgs
{
    @(shortName('h'))
    bool help;

    alias Commands = CliCommands!(CustomHelpChildArgs);
}

@command("child")
struct CustomHelpChildArgs
{
    @(shortName('h'))
    bool help;
}

@noBuiltinHelp
struct NoBuiltinHelpRootArgs
{
}

@(noBuiltinVersion, cliVersion("9.3.0"))
struct CustomVersionRootArgs
{
    @longName("version")
    Option!String version_;
}

@noBuiltinVersion
struct NoVersionMetadataRootArgs
{
}

enum CompletionShell
{
    bash,
    fish,
}

@noBuiltinHelp
struct TerminalRootArgs
{
    @(shortName('v'), count, global)
    uint verbose;

    @(shortName('h'), global, terminal)
    bool help;

    alias Commands = CliCommands!(TerminalBuildArgs);
}

@command("build")
struct TerminalBuildArgs
{
    @required
    Option!String output;

    @(terminal, valueName("SHELL"))
    CompletionShell completions;
}

struct TerminalAllocArgs
{
    Array!String item;

    @terminal
    bool done;
}

struct InvalidTerminalPositionalArgs
{
    @(positional, terminal)
    String value;
}

struct InvalidTerminalCountArgs
{
    @(count, terminal)
    uint verbose;
}

struct InvalidTerminalArrayArgs
{
    @terminal
    Array!String values;
}

struct InvalidDuplicateTerminalArgs
{
    @(terminal, terminal)
    bool quit;
}

struct InvalidChildVersionRootArgs
{
    alias Commands = CliCommands!(InvalidChildVersionArgs);
}

@(command("child"), cliVersion("1.0"))
struct InvalidChildVersionArgs
{
}

struct InvalidChildHelpPolicyRootArgs
{
    alias Commands = CliCommands!(InvalidChildHelpPolicyArgs);
}

@(command("child"), noBuiltinHelp)
struct InvalidChildHelpPolicyArgs
{
}

struct InvalidChildVersionPolicyRootArgs
{
    alias Commands = CliCommands!(InvalidChildVersionPolicyArgs);
}

@(command("child"), noBuiltinVersion)
struct InvalidChildVersionPolicyArgs
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
static assert(cliNeedsAllocator!TerminalAllocArgs);

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
    assert(build.args.output.isSome);
    assert(build.args.output.value == "build/app");
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
        assert(contains(output.text, "Usage: tool [OPTIONS] <COMMAND>"));
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
        assert(contains(output.text, "Usage: tool group <COMMAND>"));
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

private void testPublicGeneratedHelp()
{
    {
        TextSink output;
        Writer writer = Writer.fromSink(&textSink, &output);
        writeHelp!(RootArgs, DependencyArgs, DependencyAddArgs)(
            writer,
            "/usr/local/bin/tool",
        );
        assert(writer.finish().ok);

        assert(contains(output.text, "Add a dependency"));
        assert(contains(output.text, "Usage: tool dependency add [OPTIONS] <PACKAGE>"));
        assert(!contains(output.text, "/usr/local/bin/tool"));
        assert(contains(output.text, "--version <VERSION>"));
        assert(contains(output.text, "Global options:"));
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

        assert(contains(output.text, "Usage: tool child [OPTIONS]"));
        assert(contains(output.text, "-h, --help"));
        assert(!contains(output.text, "Show this help"));
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
        assert(contains(output.text, "Usage: tool dependency add [OPTIONS] <PACKAGE>"));
        assert(contains(output.text, "--version <VERSION>"));
        assert(contains(output.text, "Global options:"));
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
        assert(build.args.output.isNone);
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
        assert(build.args.output.isNone);
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
    testExplicitTypedTraversal();
    testNestedCommandsAndChildVersionOption();
    testDefaultsAndOptionalCommand();
    testRequiredAndDuplicateErrors();
    testRequiredCommand();
    testHelpOnMissingSubcommand();
    testUnknownAndInvalidValues();
    testPublicGeneratedHelp();
    testGeneratedHelpAndVersion();
    testGeneratedErrorResponse();
    testDisabledBuiltinHelp();
    testDisabledBuiltinVersion();
    testTerminalArguments();
    testTerminalCleanup();
    testRepeatedAndRestArgumentsCleanUp();
    testAllocationFailureCleansUp();
    return 0;
}
