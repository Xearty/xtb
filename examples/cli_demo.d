module examples.cli_demo;

nothrow @nogc:

import xtb.cli;
import xtb.core.option : Option;
import xtb.core.print : writeln;
import xtb.core.types : String;

@(cliVersion("1.0.0"), about("Small typed command-line parser example"), allowNoSubcommand)
struct RootArgs
{
    @(shortName('v'), count, global, help("Increase verbosity"))
    uint verbose;

    @(global, valueName("DIR"), help("Change the working directory"))
    Option!String directory;

    alias Commands = CliCommands!(BuildArgs, TestArgs);
}

@(command("build"), about("Build the project"))
struct BuildArgs
{
    @(shortName('r'), help("Build with optimizations"))
    bool release;

    @(shortName('j'), valueName("N"), help("Number of parallel jobs"))
    uint jobs = 1;
}

@(command("test"), about("Run the test suite"))
struct TestArgs
{
    @(shortName('f'), valueName("FILTER"), help("Only run matching tests"))
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
