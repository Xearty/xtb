module examples.cli_demo;

nothrow @nogc:

import xtb.cli;
import xtb.core.option : Option;
import xtb.core.print : writeln;
import xtb.core.types : String;

@(cliVersion("1.0.0"), cliAbout("Small typed command-line parser example"), cliSubcommandOptional)
struct RootArgs
{
    @(cliShortName('v'), cliShortAlias('V'), cliAliasName("verbosity"), cliCount, cliGlobal,
        cliHelp("Increase verbosity"))
    uint verbose;

    @(cliGlobal, cliAliasName("cwd"), cliValueName("DIR"),
        cliHelp("Change the working directory"))
    Option!String directory;

    alias Commands = CliCommands!(BuildArgs, TestArgs);
}

@(cliCommand("build"), cliAliasName("b"), cliAbout("Build the project"))
struct BuildArgs
{
    @(cliShortName('r'), cliAliasName("optimized"), cliHelp("Build with optimizations"))
    bool release;

    @(cliShortName('j'), cliAliasName("parallelism"), cliValueName("N"),
        cliHelp("Number of parallel jobs"))
    uint jobs = 1;
}

@(cliCommand("test"), cliAliasName("t"), cliAbout("Run the test suite"))
struct TestArgs
{
    @(cliShortName('f'), cliShortAlias('F'), cliValueName("FILTER"),
        cliHelp("Only run matching tests"))
    Option!String filter;
}

private int runBuild(ref RootArgs root, ref BuildArgs args)
{
    writeln("build: release=", args.release, ", jobs=", args.jobs,
        ", verbosity=", root.verbose);
    return 0;
}

private int runTests(ref RootArgs root, ref TestArgs args)
{
    if (args.filter.isSome)
        writeln("test: filter=", args.filter.value, ", verbosity=", root.verbose);
    else
        writeln("test: all, verbosity=", root.verbose);
    return 0;
}

extern (C) int main(int argc, char** argv)
{
    auto result = parseArgs!RootArgs(argc, argv);
    scope (exit)
        result.deinit();

    if (!result.hasInvocation)
        return handleCliResult(result);

    ref root = result.invocation;

    if (auto build = root.command!BuildArgs)
        return runBuild(root.args, build.args);

    if (auto test = root.command!TestArgs)
        return runTests(root.args, test.args);

    writeln("No command selected. Try --help.");
    return 0;
}
