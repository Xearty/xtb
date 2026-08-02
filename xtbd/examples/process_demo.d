module examples.process_demo;

import xtb.core;
import xtb.os;

extern (C) int main() nothrow @nogc
{
    version (linux)
    {
        ThreadContextScope context = ThreadContextScope.acquire();
        String[2] arguments = ["process library: %s\n", "ready"];
        const command = Command.search("printf", arguments[]);
        const options = SpawnOptions.init
            .withStdin(InputRoute.nullDevice())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.mergeWithStdout());

        ChildProcess child;
        const spawnError = spawn(command, options, &child);
        if (spawnError.failed)
        {
            formatln!"spawn failed: operation={} error={} native={}"(
                cast(
                    uint) spawnError.operation,
                cast(uint) spawnError.os.kind,
                spawnError.os.nativeCode,
            );
            return 1;
        }

        ExitStatus status;
        const waitError = wait(&child, &status);
        if (waitError.failed)
        {
            formatln!"wait failed: error={} native={}"(
                cast(uint) waitError.os.kind,
                waitError.os.nativeCode,
            );
            return 1;
        }

        u8[256] storage;
        for (;;)
        {
            const result = readSome(child.stdoutPipe, storage[]);
            if (result.error.failed)
            {
                formatln!"read failed: error={} native={}"(
                    cast(uint) result.error.kind,
                    result.error.nativeCode,
                );
                return 1;
            }
            if (result.state == PipeReadState.endOfFile)
                break;
            if (result.state == PipeReadState.data)
                write(storage[0 .. result.transferred].asStringUnchecked);
        }

        if (!status.succeeded)
        {
            if (status.exited)
                formatln!"child exited with code {}"(status.exitCode);
            else
                formatln!"child was terminated by signal {}"(
                    status.terminationSignal,
                );
            return 1;
        }
        return 0;
    }
    else
    {
        writeln("the process backend is not implemented on this platform");
        return 0;
    }
}
