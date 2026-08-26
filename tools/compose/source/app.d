module app;

import compose : ComposeOptions, compose;
import std.getopt : getopt;
import std.stdio : stderr, writeln;

int main(string[] args)
{
    ComposeOptions options;
    try
    {
        getopt(args,
            "mode", &options.mode,
            "output", &options.outputDirectory,
        );
        options.features = args[1 .. $];
        const library = compose(options, ".");
        writeln(library);
        return 0;
    }
    catch (Exception error)
    {
        stderr.writeln("xtb compose: ", error.msg);
        return 1;
    }
}
