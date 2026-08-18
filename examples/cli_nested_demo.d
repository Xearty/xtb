module examples.cli_nested_demo;

nothrow @nogc:

import xtb.cli;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.array : Array;
import xtb.core.option : Option;
import xtb.core.print : writeln;
import xtb.core.types : String;

@(cliVersion("1.0.0"), cliAbout("Nested subcommand and repeated-argument example"), cliSubcommandOptional)
struct RootArgs
{
    @(cliShortName('v'), cliCount, cliGlobal, cliHelp("Increase verbosity"))
    uint verbose;

    alias Commands = CliCommands!(RunArgs, DependencyArgs);
}

@(cliCommand("run"), cliAbout("Run a program"))
struct RunArgs
{
    @(cliShortName('D'), cliValueName("NAME=VALUE"), cliHelp("Define a value; may be repeated"))
    Array!String defines;

    @(cliPositional, cliValueName("PROGRAM"))
    String program;

    @(cliPositional, cliRest, cliValueName("ARG"))
    Array!String arguments;
}

@(cliCommand("dependency"), cliAbout("Manage dependencies"))
struct DependencyArgs
{
    @(cliValueName("URL"), cliHelp("Registry used by dependency commands"))
    Option!String registry;

    alias Commands = CliCommands!(DependencyAddArgs, DependencyRemoveArgs, DependencyListArgs);
}

@(cliCommand("add"), cliAbout("Add a dependency"))
struct DependencyAddArgs
{
    @(cliPositional, cliValueName("PACKAGE"))
    String package_;

    @(cliValueName("VERSION"), cliHelp("Requested package version"))
    Option!String version_;
}

@(cliCommand("remove"), cliAbout("Remove a dependency"))
struct DependencyRemoveArgs
{
    @(cliPositional, cliValueName("PACKAGE"))
    String package_;
}

@(cliCommand("list"), cliAbout("List dependencies"))
struct DependencyListArgs
{
    @(cliShortName('a'), cliHelp("Include transitive dependencies"))
    bool all;
}

private int runProgram(ref RootArgs root, ref RunArgs args)
{
    writeln("run: ", args.program, ", definitions=", args.defines.length,
        ", arguments=", args.arguments.length, ", verbosity=", root.verbose);
    return 0;
}

private int addDependency(
    ref RootArgs root,
    ref DependencyArgs dependency,
    ref DependencyAddArgs args,
)
{
    writeln("add dependency: ", args.package_, ", verbosity=", root.verbose);
    if (dependency.registry.isSome)
        writeln("registry: ", dependency.registry.value);
    if (args.version_.isSome)
        writeln("version: ", args.version_.value);
    return 0;
}

extern (C) int main(int argc, char** argv)
{
    auto result = parseArgs!RootArgs(argc, argv, mallocAllocator());
    scope (exit)
        result.deinit();

    if (!result.hasInvocation)
        return handleCliResult(result);

    ref root = result.invocation;

    if (auto run = root.command!RunArgs)
        return runProgram(root.args, run.args);

    if (auto dependency = root.command!DependencyArgs)
    {
        if (auto add = dependency.command!DependencyAddArgs)
            return addDependency(root.args, dependency.args, add.args);

        if (auto remove = dependency.command!DependencyRemoveArgs)
        {
            writeln("remove dependency: ", remove.args.package_);
            return 0;
        }

        if (auto list = dependency.command!DependencyListArgs)
        {
            writeln("list dependencies: all=", list.args.all);
            return 0;
        }
    }

    writeln("No command selected. Try --help.");
    return 0;
}
