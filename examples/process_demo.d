module examples.process_demo;

import xtb;
import xtb.os;

version (linux)
{

    private bool report(ProcessError error, String context) nothrow @nogc
    {
        if (error.succeeded)
            return true;
        formatln!"{} failed: operation={} stage={} error={} native={}"(
            context,
            cast(
                uint) error.operation,
            error.stageIndex,
            cast(uint) error.os.kind,
            error.os.nativeCode,
        );
        return false;
    }

    private void cleanupExampleChild(ChildProcess* child) nothrow @system @nogc
    {
        if (child.ownsProcess)
        {
            ExitStatus ignored;
            cast(void) killAndWait(child, &ignored);
        }
        if (!child.ownsProcess)
            child.deinit();
    }

    private void cleanupExamplePipeline(Pipeline* pipeline) nothrow @system @nogc
    {
        if (!pipeline.empty && !pipeline.completed)
            cast(void) killPipelineAndWait(pipeline);
        if (pipeline.empty || pipeline.completed)
            pipeline.deinit();
    }

    private bool printPipe(PipeReader* reader) nothrow @system @nogc
    {
        u8[256] storage;
        for (;;)
        {
            const result = readSome(reader, storage[]);
            if (result.error.failed)
            {
                formatln!"pipe read failed: error={} native={}"(
                    cast(uint) result.error.kind,
                    result.error.nativeCode,
                );
                return false;
            }
            if (result.state == PipeReadState.endOfFile)
                return true;
            if (result.state == PipeReadState.data)
            {
                const checked = storage[0 .. result.transferred].asString;
                if (checked.failed)
                    return false;
                write(checked.value);
            }
        }
    }

    private bool directSpawnExample() nothrow @system @nogc
    {
        writeln("\n-- direct spawn and explicit pipe ownership --");
        String[2] arguments = ["direct child: %s\n", "ready"];
        const command = Command.search("printf", arguments[]);
        const options = SpawnOptions.init
            .withStdin(InputRoute.nullDevice())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.mergeWithStdout());

        ChildProcess child;
        scope (exit)
            cleanupExampleChild(&child);
        if (!report(spawn(command, options, &child), "spawn"))
            return false;
        formatln!"spawned pid={}, stdout pipe={}"(
            child.id.value,
            child.hasStdoutPipe,
        );

        ExitStatus status;
        if (!report(wait(&child, &status), "wait") || !printPipe(child.stdoutPipe))
            return false;
        formatln!"normal exit={}, code={}, pipe remains readable until EOF"(
            status.exited,
            status.exitCode,
        );
        return true;
    }

    private bool communicateExample() nothrow @system @nogc
    {
        writeln("\n-- simultaneous stdin/stdout/stderr communication --");
        String[1] arguments = ["-"];
        const command = Command.search("cat", arguments[]);
        const routes = SpawnOptions.init
            .withStdin(InputRoute.piped())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.piped());
        ChildProcess child;
        scope (exit)
            cleanupExampleChild(&child);
        if (!report(spawn(command, routes, &child), "spawn cat"))
            return false;

        enum u8[12] input = [
            'b', 'i', 'n', 'a', 'r', 'y', ':', 0, 1, 2, '\n', 255,
        ];
        u8[32] outputStorage;
        u8[32] errorStorage;
        CaptureBuffer output = CaptureBuffer(outputStorage[]);
        CaptureBuffer errorOutput = CaptureBuffer(errorStorage[]);
        const result = communicate(
            &child,
            input[],
            &output,
            &errorOutput,
            CommunicateOptions.init,
        );
        if (!report(result.error, "communicate"))
            return false;
        formatln!"state={}, input written={}, binary stdout bytes={}, stderr bytes={}, exit success={}"(
            cast(uint) result.state,
            result.inputWritten,
            output.length,
            errorOutput.length,
            result.exitStatus.value.succeeded,
        );
        return output.bytes == input[];
    }

    private bool truncationExample() nothrow @system @nogc
    {
        writeln("\n-- bounded capture continues draining after truncation --");
        String[2] arguments = ["%s", "0123456789abcdef"];
        const routes = SpawnOptions.init
            .withStdin(InputRoute.nullDevice())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.nullDevice());
        ChildProcess child;
        scope (exit)
            cleanupExampleChild(&child);
        if (!report(spawn(Command.search("printf", arguments[]), routes, &child),
                "spawn truncation producer"))
            return false;

        u8[8] storage;
        CaptureBuffer capture = CaptureBuffer(storage[]);
        const result = communicate(
            &child,
            null,
            &capture,
            null,
            CommunicateOptions.init,
        );
        if (!report(result.error, "bounded communicate"))
            return false;
        const checked = capture.bytes.asString;
        if (checked.failed)
            return false;
        formatln!"captured='{}', length={}, truncated={}"(
            checked.value,
            capture.length,
            capture.truncated,
        );
        return capture.truncated;
    }

    private bool resumableTimeoutExample() nothrow @system @nogc
    {
        writeln("\n-- resumable timeout leaves ownership with the caller --");
        String[1] arguments = ["0.03"];
        ChildProcess child;
        scope (exit)
            cleanupExampleChild(&child);
        if (!report(spawn(Command.search("sleep", arguments[]), SpawnOptions.init,
                &child), "spawn resumable child"))
            return false;

        const first = communicate(
            &child,
            null,
            null,
            null,
            CommunicateOptions.init.withTimeout(milliseconds(0)),
        );
        if (!report(first.error, "immediate communicate"))
            return false;
        formatln!"first state={}, still owns process={}"(
            cast(uint) first.state,
            child.ownsProcess,
        );

        const resumed = communicate(
            &child,
            null,
            null,
            null,
            CommunicateOptions.init,
        );
        if (!report(resumed.error, "resumed communicate"))
            return false;
        formatln!"resumed state={}, exit success={}"(
            cast(uint) resumed.state,
            resumed.exitStatus.value.succeeded,
        );
        return resumed.state == CommunicateState.completed;
    }

    private bool terminatingTimeoutExample() nothrow @system @nogc
    {
        writeln("\n-- timeout policy can force cleanup and reap --");
        String[1] arguments = ["5"];
        ChildProcess child;
        scope (exit)
            cleanupExampleChild(&child);
        if (!report(spawn(Command.search("sleep", arguments[]), SpawnOptions.init,
                &child), "spawn timed child"))
            return false;
        const options = CommunicateOptions.init
            .withTimeout(milliseconds(5))
            .withTimeoutAction(TimeoutAction.kill);
        const result = communicate(&child, null, null, null, options);
        if (!report(result.error, "terminating communicate"))
            return false;
        formatln!"state={}, signaled={}, signal={}, owner empty={}"(
            cast(uint) result.state,
            result.exitStatus.value.signaled,
            result.exitStatus.value.terminationSignal,
            child.empty,
        );
        return result.state == CommunicateState.timedOutTerminated;
    }

    private bool borrowedPipelineExample() nothrow @system @nogc
    {
        writeln("\n-- borrowed stage slices and per-stage status --");
        String[4] producerArguments = [
            "%s\n%s\n%s\n", "pear", "apple", "pear",
        ];
        String[2] translateArguments = ["a-z", "A-Z"];
        String[1] uniqueArguments = ["-c"];
        Command[4] commands = [
            Command.search("printf", producerArguments[]),
            Command.search("sort"),
            Command.search("tr", translateArguments[]),
            Command.search("uniq", uniqueArguments[]),
        ];
        PipelineStage[4] stages = [
            PipelineStage(commands[0]),
            PipelineStage(commands[1]),
            PipelineStage(commands[2]),
            PipelineStage(commands[3]).withStderr(ErrorRoute.nullDevice()),
        ];
        const options = PipelineOptions.init
            .withStdin(InputRoute.nullDevice())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.inherited())
            .withSuccessPolicy(PipelineSuccess.everyStage)
            .withIsolation(ProcessIsolation.isolatedTree);

        Pipeline pipeline;
        scope (exit)
            cleanupExamplePipeline(&pipeline);
        if (!report(spawnPipeline(
                stages[], options, mallocAllocator(), &pipeline), "spawn pipeline"))
            return false;
        formatln!"stages={}, final stdout pipe={}"(
            pipeline.length,
            pipeline.stdoutPipe !is null,
        );
        if (!report(waitPipeline(&pipeline), "wait pipeline") ||
            !printPipe(pipeline.stdoutPipe))
            return false;
        foreach (index; 0 .. pipeline.length)
            formatln!"stage {} exit code={}"(index, pipeline.status(index).exitCode);
        formatln!"every-stage success={}"(pipeline.succeeded);
        return pipeline.succeeded;
    }
}

extern (C) int main() nothrow @nogc
{
    version (linux)
    {
        ThreadContextScope context = ThreadContextScope.acquire();
        return directSpawnExample() && communicateExample() &&
            truncationExample() && resumableTimeoutExample() &&
            terminatingTimeoutExample() && borrowedPipelineExample()
            ? 0 : 1;
    }
    else
    {
        writeln("the process backend is not implemented on this platform");
        return 0;
    }
}
