module examples.cli_demo;

nothrow @nogc:

import core.stdc.stdio : FILE, stderr, stdout;
import xtb.cli;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.array : Array;
import xtb.core.option : Option;
import xtb.core.print : writeln;
import xtb.core.string : equal;
import xtb.core.types : String;
import xtb.os.terminal : shouldUseAnsi;

enum Profile
{
    development,
    staging,
    production,
}

enum DiagnosticFormat
{
    human,
    compact,
    json,
}

enum BuildMode
{
    debug_,
    releaseSafe,
    releaseFast,
}

enum TestFormat
{
    pretty,
    terse,
    junit,
}

enum DependencyScope
{
    runtime,
    development,
    optional,
}

enum ListFormat
{
    table,
    tree,
    json,
}

private CliValueError parseCacheBudget(scope String input, uint* output)
{
    if (input.equal("auto"))
    {
        *output = 0;
        return CliValueError.init;
    }
    if (input.equal("64MiB"))
    {
        *output = 64;
        return CliValueError.init;
    }
    if (input.equal("256MiB"))
    {
        *output = 256;
        return CliValueError.init;
    }
    if (input.equal("1GiB"))
    {
        *output = 1024;
        return CliValueError.init;
    }
    return CliValueError.invalid("expected auto, 64MiB, 256MiB, or 1GiB");
}

private struct CacheBudgetCli
{
    alias parse = parseCacheBudget;
}

@(
    cliVersion("4.2.0"),
    cliAbout(
        "XTB Workspace Orchestrator\n"
        ~ "A deliberately feature-rich CLI showcase for typed parsing, nested commands,\n"
        ~ "aliases, defaults, custom values, terminal options, and ANSI help rendering."
),
cliSubcommandOptional,
)
struct RootArgs
{
    @(
        cliShortName('v'),
        cliShortAlias('V'),
        cliAliasName("verbosity"),
        cliCount,
        cliGlobal,
        cliHelp("Increase diagnostic verbosity"),
    )
    uint verbose;

    @(
        cliShortName('C'),
        cliAliasName("cwd"),
        cliAliasName("working-directory"),
        cliValueName(
            "DIR"),
        cliGlobal,
        cliHelp("Change the workspace directory before executing a command"),
    )
    Option!String directory;

    @(
        cliShortName('c'),
        cliAliasName("colour"),
        cliNegatable,
        cliDefault,
        cliGlobal,
        cliHelp("Enable styled application output and generated CLI responses"),
    )
    bool color = true;

    @(
        cliAliasName("environment"),
        cliDefault,
        cliGlobal,
        cliHelp("Select the deployment profile"),
    )
    Profile profile = Profile.development;

    @(
        cliLongName("diagnostic-format"),
        cliAliasName("diagnostics"),
        cliValueName("FORMAT"),
        cliDefault,
        cliGlobal,
        cliHelp("Choose how diagnostics are rendered"),
    )
    DiagnosticFormat diagnosticFormat = DiagnosticFormat.human;

    @(
        cliValueWith!CacheBudgetCli,
        cliPossibleValues!("auto", "64MiB", "256MiB", "1GiB"),
        cliDefaultInput("auto"),
        cliValueName("SIZE"),
        cliGlobal,
        cliHelp("Override the build-cache memory budget"),
    )
    uint cacheBudget;

    @(
        cliAliasName("schema"),
        cliTerminal,
        cliGlobal,
        cliHelp("Print a compact application schema summary and stop parsing"),
    )
    bool printSchema;

    @(
        cliHidden,
        cliGlobal,
    )
    bool internalTrace;

    alias Commands = CliCommands!(
        BuildArgs,
        TestArgs,
        RunArgs,
        DependencyArgs,
        PublishArgs,
    );
}

@(
    cliCommand("build"),
    cliAliasName("b"),
    cliAliasName("compile"),
    cliAbout("Compile the current workspace"),
)
struct BuildArgs
{
    @(
        cliShortName('r'),
        cliAliasName("optimized"),
        cliHelp("Build with optimization enabled"),
    )
    bool release;

    @(
        cliShortName('j'),
        cliAliasName("parallelism"),
        cliValueName("N"),
        cliDefault,
        cliHelp("Maximum number of parallel compiler jobs"),
    )
    uint jobs = 8;

    @(cliDefault, cliHelp("Select the compiler safety/optimization profile"))
    BuildMode mode = BuildMode.debug_;

    @(
        cliShortName('o'),
        cliAliasName("destination"),
        cliValueName("PATH"),
        cliHelp("Write build artifacts to this directory"),
    )
    String output;

    @(
        cliAliasName("incremental-build"),
        cliNegatable,
        cliDefault,
        cliHelp("Reuse valid artifacts from previous builds"),
    )
    bool incremental = true;

    @(
        cliShortName('D'),
        cliAliasName("define-value"),
        cliValueName("KEY=VALUE"),
        cliHelp("Define a compile-time value; may be supplied repeatedly"),
    )
    Array!String define;
}

@(
    cliCommand("test"),
    cliAliasName("t"),
    cliAliasName("check"),
    cliAbout("Run workspace tests"),
)
struct TestArgs
{
    @(
        cliPositional,
        cliValueName("FILTER"),
        cliHelp("Optional test-name filter"),
    )
    Option!String filter;

    @(
        cliShortName('f'),
        cliAliasName("reporter"),
        cliDefault,
        cliHelp("Select the test report format"),
    )
    TestFormat format = TestFormat.pretty;

    @(cliDefault, cliHelp("Retry each failed test up to N times"))
    uint retries = 2;

    @(
        cliAliasName("stop-on-failure"),
        cliHelp("Stop after the first failing test"),
    )
    bool failFast;

    @(
        cliNegatable,
        cliDefault,
        cliHelp("Collect source coverage information"),
    )
    bool coverage = true;
}

@(
    cliCommand("run"),
    cliAliasName("r"),
    cliAbout("Run a program with forwarded arguments"),
)
struct RunArgs
{
    @(
        cliShortName('E'),
        cliLongName("env"),
        cliAliasName("environment-variable"),
        cliValueName("KEY=VALUE"),
        cliHelp("Add an environment entry; may be supplied repeatedly"),
    )
    Array!String environment;

    @(
        cliLongName("child-directory"),
        cliAliasName("chdir"),
        cliValueName("DIR"),
        cliHelp("Set the child process working directory"),
    )
    Option!String childDirectory;

    @(
        cliPositional,
        cliValueName("PROGRAM"),
        cliHelp("Program to execute"),
    )
    String program;

    @(
        cliPositional,
        cliRest,
        cliValueName("ARG"),
        cliHelp("Arguments forwarded verbatim after the program name"),
    )
    Array!String arguments;
}

@(
    cliCommand("dependency"),
    cliAliasName("dep"),
    cliAliasName("deps"),
    cliAbout("Inspect and modify workspace dependencies"),
    cliSubcommandOptional,
)
struct DependencyArgs
{
    @(
        cliAliasName("registry-url"),
        cliValueName("URL"),
        cliHelp("Override the package registry for this operation"),
    )
    Option!String registry;

    alias Commands = CliCommands!(DependencyAddArgs, DependencyRemoveArgs, DependencyListArgs);
}

@(
    cliCommand("add"),
    cliAliasName("a"),
    cliAbout("Add a dependency to the workspace manifest"),
)
struct DependencyAddArgs
{
    @(
        cliPositional,
        cliValueName("PACKAGE"),
        cliHelp("Package name to add"),
    )
    String package_;

    @(
        cliAliasName("constraint"),
        cliValueName("VERSION"),
        cliHelp("Version or version constraint"),
    )
    Option!String version_;

    @(cliLongName("scope"), cliDefault, cliHelp("Dependency scope written to the manifest"))
    DependencyScope scope_ = DependencyScope.runtime;

    @(
        cliAliasName("pin"),
        cliHelp("Require the exact selected package version"),
    )
    bool exact;
}

@(
    cliCommand("remove"),
    cliAliasName("rm"),
    cliAliasName("delete"),
    cliAbout("Remove a dependency from the workspace manifest"),
)
struct DependencyRemoveArgs
{
    @(
        cliPositional,
        cliValueName("PACKAGE"),
        cliHelp("Package name to remove"),
    )
    String package_;

    @(
        cliNegatable,
        cliDefault,
        cliHelp("Remove dependencies that become unreachable"),
    )
    bool prune = true;
}

@(
    cliCommand("list"),
    cliAliasName("ls"),
    cliAbout("List resolved workspace dependencies"),
)
struct DependencyListArgs
{
    @(cliShortName('a'), cliHelp("Include transitive dependencies"))
    bool all;

    @(cliDefault, cliHelp("Select the dependency-list presentation"))
    ListFormat format = ListFormat.table;

    @(
        cliAliasName("development"),
        cliNegatable,
        cliDefault,
        cliHelp("Include development-only dependencies"),
    )
    bool dev = true;
}

@(
    cliCommand("publish"),
    cliAliasName("p"),
    cliAliasName("release"),
    cliAbout("Publish a built artifact to a package registry"),
)
struct PublishArgs
{
    @(
        cliPositional,
        cliValueName("ARTIFACT"),
        cliHelp("Artifact file to publish"),
    )
    String artifact;

    @(
        cliShortName('t'),
        cliAliasName("auth-token"),
        cliValueName("TOKEN"),
        cliHelp("Registry authentication token"),
    )
    String token;

    @(
        cliAliasName("registry-url"),
        cliValueName("URL"),
        cliHelp("Destination registry endpoint"),
    )
    Option!String registry;

    @(
        cliShortName('n'),
        cliAliasName("simulate"),
        cliHelp("Validate the release without uploading anything"),
    )
    bool dryRun;
}

private int runInvocation(ref ParsedCommand!RootArgs root)
{
    if (auto build = root.command!BuildArgs)
    {
        writeln("build: mode=", build.args.mode, ", jobs=", build.args.jobs,
            ", defines=", build.args.define.length);
        return 0;
    }
    if (auto test = root.command!TestArgs)
    {
        writeln("test: format=", test.args.format, ", retries=", test.args.retries);
        return 0;
    }
    if (auto run = root.command!RunArgs)
    {
        writeln("run: program=", run.args.program,
            ", forwarded=", run.args.arguments.length);
        return 0;
    }
    if (auto dependency = root.command!DependencyArgs)
    {
        if (auto add = dependency.command!DependencyAddArgs)
            writeln("dependency add: ", add.args.package_);
        else if (auto remove = dependency.command!DependencyRemoveArgs)
            writeln("dependency remove: ", remove.args.package_);
        else if (auto list = dependency.command!DependencyListArgs)
            writeln("dependency list: format=", list.args.format);
        else
            writeln("dependency: no operation selected");
        return 0;
    }
    if (auto publish = root.command!PublishArgs)
    {
        writeln("publish: artifact=", publish.args.artifact,
            ", dry-run=", publish.args.dryRun);
        return 0;
    }

    writeln("No command selected. Try --help.");
    return 0;
}

extern (C) int main(int argc, char** argv)
{
    auto result = parseArgs!RootArgs(argc, argv, mallocAllocator());
    scope (exit)
        result.deinit();

    // ANSI capability is application policy. stdout and stderr are resolved
    // independently, and shouldUseAnsi() also honors NO_COLOR and TERM=dumb.
    const colorEnabled = result.parsed.args.color;
    const outputAnsi = colorEnabled && shouldUseAnsi(cast(FILE*) stdout);
    const errorAnsi = colorEnabled && shouldUseAnsi(cast(FILE*) stderr);

    if (result.failed || result.hasBuiltinResponse)
        return handleCliResult(result, outputAnsi, errorAnsi);

    if (result.hasTerminal)
    {
        if (result.parsed.args.printSchema)
        {
            writeln("schema: build, test, run, dependency, publish");
            return 0;
        }
        return 0;
    }

    return runInvocation(result.invocation);
}
