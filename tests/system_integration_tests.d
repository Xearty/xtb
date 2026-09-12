module tests.system_integration_tests;

import xtb.fs.directory;
import xtb.os.error;
import xtb.process.environment;
import xtb.fs.file;
import xtb.fs.memory_map;
import xtb.fs.path;
import xtb.process.pipeline;
import xtb.os.pipe;
import xtb.process.process;
import xtb.process.io;
import xtb.duration : milliseconds;
import xtb.time : Instant, Timestamp, Timeout, sleep;
import core.internal.traits : hasElaborateDestructor;
import xtb.containers.array;
import xtb.allocators.arena : Arena, TempArena;
import xtb.lifetime : deinit, move, move_assign, needs_deinit;
import xtb.option : Option;
import xtb.result : Result;
import xtb.allocators.malloc : malloc_allocator;
import xtb.string;
import xtb.thread_context : ThreadContextScope, scratch_arena;
import xtb.thread : Thread;
import xtb.types : String, i64, u64, u8;

static assert(!hasElaborateDestructor!DirectoryIterator);
static assert(needs_deinit!DirectoryIterator);
static assert(!__traits(isCopyable, DirectoryIterator));
static assert(!__traits(compiles, () { DirectoryIterator left; DirectoryIterator right; left = right; }));
static assert(!hasElaborateDestructor!MappedFile);
static assert(needs_deinit!MappedFile);
static assert(!__traits(isCopyable, MappedFile));
static assert(!__traits(compiles, () { MappedFile left; MappedFile right; left = right; }));
static assert(!hasElaborateDestructor!PipeReader);
static assert(!hasElaborateDestructor!PipeWriter);
static assert(!hasElaborateDestructor!Pipe);
static assert(needs_deinit!PipeReader);
static assert(needs_deinit!PipeWriter);
static assert(needs_deinit!Pipe);
static assert(!__traits(isCopyable, PipeReader));
static assert(!__traits(isCopyable, PipeWriter));
static assert(!__traits(isCopyable, Pipe));
static assert(!__traits(compiles, () { PipeReader left; PipeReader right; left = right; }));
static assert(!__traits(compiles, () { PipeWriter left; PipeWriter right; left = right; }));
static assert(!__traits(compiles, () { Pipe left; Pipe right; left = right; }));
static assert(!hasElaborateDestructor!ChildProcess);
static assert(needs_deinit!ChildProcess);
static assert(!__traits(isCopyable, ChildProcess));
static assert(!__traits(compiles, () { ChildProcess left; ChildProcess right; left = right; }));
static assert(!hasElaborateDestructor!Pipeline);
static assert(needs_deinit!Pipeline);
static assert(!__traits(isCopyable, Pipeline));
static assert(!__traits(compiles, () { Pipeline left; Pipeline right; left = right; }));

static assert(!hasElaborateDestructor!File);
static assert(needs_deinit!File);
static assert(!__traits(isCopyable, File));
static assert(!__traits(compiles, () { File left; File right; left = right; }));
static assert(needs_deinit!(Option!File));
static assert(needs_deinit!(Result!(File, OsError)));
static assert(needs_deinit!(OwnedArray!File));

private struct FileOwnerComposition
{
    File file;
}

static assert(needs_deinit!FileOwnerComposition);

version (linux) private int closedPipeWriteWorker(PipeWriter* writer) nothrow @system @nogc
{
    u8[1] payload = [1];
    const result = writeSome(writer, payload[]);
    return result.error.succeeded && result.state == PipeWriteState.peerClosed
        ? 0 : 1;
}

version (linux) private size_t openDescriptorCount() nothrow @system @nogc
{
    DirectoryIterator iterator;
    assert(open_directory(Path.from_string("/proc/self/fd"), &iterator).succeeded);
    size_t result;
    DirectoryEntry entry;
    for (;;)
    {
        const nextResult = iterator.next(&entry);
        assert(nextResult.status != DirectoryStatus.failed);
        if (nextResult.status == DirectoryStatus.finished)
            break;
        ++result;
    }
    assert(iterator.close().succeeded);
    return result;
}

version (linux) private void assertNoChildProcesses() nothrow @system @nogc
{
    import core.stdc.errno : ECHILD, errno;
    import core.sys.posix.sys.wait : WNOHANG, waitpid;

    int status;
    errno = 0;
    assert(waitpid(-1, &status, WNOHANG) == -1 && errno == ECHILD);
}

version (linux) private bool countEntry(
    scope const Path, FileType, scope void* context) nothrow @system @nogc
{
    ++*cast(size_t*) context;
    return true;
}

version (linux) private void readPipeEntirely(
    PipeReader* reader,
    Array!u8* output,
) nothrow @system @nogc
{
    u8[256] buffer;
    for (;;)
    {
        const result = readSome(reader, buffer[]);
        assert(result.error.succeeded);
        if (result.state == PipeReadState.endOfFile)
            return;
        assert(result.state == PipeReadState.data);
        (*output).append(buffer[0 .. result.transferred]);
    }
}

version (linux) private void writePipeEntirely(
    PipeWriter* writer,
    scope const(u8)[] input,
) nothrow @system @nogc
{
    size_t written;
    while (written != input.length)
    {
        const result = writeSome(writer, input[written .. $]);
        assert(result.error.succeeded && result.state == PipeWriteState.data);
        written += result.transferred;
    }
}

version (linux) private void runProcessIntegration(
    String helperExecutable,
    String helperDirectory,
    Path temporaryDirectory,
) nothrow @system @nogc
{
    import core.stdc.signal : SIGTERM;
    import xtb.duration : milliseconds;

    SpawnOptions pipedOutput = SpawnOptions.init
        .withStdin(InputRoute.nullDevice())
        .withStdout(OutputRoute.piped())
        .withStderr(ErrorRoute.nullDevice());

    {
        String[4] arguments = ["argv", "hello world", "", "quote\"mark"];
        Command command = Command.exact(
            Path.from_string(helperExecutable),
            arguments[],
        );
        command.setArgumentZero("custom-zero");
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(command, pipedOutput, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(malloc_allocator());
        scope (exit)
            output.deinit();
        readPipeEntirely(child.stdoutPipe, &output);
        assert(output.slice.as_string_unchecked.equal(
                "custom-zero\0hello world\0\0quote\"mark\0",
        ));
    }

    {
        EnvironmentEntry[4] entries = [
            EnvironmentEntry("PATH", helperDirectory, EnvironmentAction.set),
            EnvironmentEntry("ONLY", "value", EnvironmentAction.set),
            EnvironmentEntry("EMPTY", "", EnvironmentAction.set),
            EnvironmentEntry("REMOVED", "", EnvironmentAction.remove),
        ];
        String[5] arguments = [
            "environment", "ONLY", "EMPTY", "REMOVED", "PATH",
        ];
        Command command = Command.search("process_test_helper", arguments[]);
        command.setEnvironment(Environment(EnvironmentMode.replace, entries[]));
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(command, pipedOutput, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(malloc_allocator());
        scope (exit)
            output.deinit();
        readPipeEntirely(child.stdoutPipe, &output);

        StringBuf expected = StringBuf.from_string(
            malloc_allocator(),
            "ONLY=value\0EMPTY=\0REMOVED\0PATH=",
        );
        expected.append(helperDirectory);
        expected.append('\0');
        assert(output.slice.as_string_unchecked.equal(expected.view));
        expected.deinit();
    }

    {
        String[1] arguments = ["cwd"];
        Command command = Command.exact(
            Path.from_string(helperExecutable),
            arguments[],
        );
        command.setWorkingDirectory(temporaryDirectory);
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(command, pipedOutput, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(malloc_allocator());
        scope (exit)
            output.deinit();
        readPipeEntirely(child.stdoutPipe, &output);
        assert(output.slice.as_string_unchecked.equal(temporaryDirectory.view));
    }

    {
        String[1] arguments = ["copy"];
        const options = SpawnOptions.init
            .withStdin(InputRoute.piped())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.nullDevice());
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), options, &child).succeeded);
        enum u8[7] input = [0, 1, 2, 255, 'x', '\n', 0];
        writePipeEntirely(child.stdinPipe, input[]);
        assert(close(child.stdinPipe).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(malloc_allocator());
        scope (exit)
            output.deinit();
        readPipeEntirely(child.stdoutPipe, &output);
        assert(output.slice == input[]);
    }

    {
        String[1] arguments = ["emit"];
        const options = pipedOutput.withStderr(ErrorRoute.mergeWithStdout());
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), options, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(malloc_allocator());
        scope (exit)
            output.deinit();
        readPipeEntirely(child.stdoutPipe, &output);
        assert(output.slice.as_string_unchecked.equal("out\0dataerror-data"));
    }

    {
        String[1] arguments = ["emit"];
        const options = pipedOutput.withStderr(ErrorRoute.piped());
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), options, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(malloc_allocator());
        scope (exit)
            output.deinit();
        Array!u8 errorOutput = Array!u8.create(malloc_allocator());
        scope (exit)
            errorOutput.deinit();
        readPipeEntirely(child.stdoutPipe, &output);
        readPipeEntirely(child.stderrPipe, &errorOutput);
        assert(output.slice.as_string_unchecked.equal("out\0data"));
        assert(errorOutput.slice.as_string_unchecked.equal("error-data"));
    }

    {
        Pipe external;
        PipeOptions pipeOptions;
        pipeOptions.readerMode = PipeMode.nonBlocking;
        assert(createPipe(pipeOptions, &external).succeeded);
        String[1] arguments = ["emit"];
        const options = pipedOutput
            .withStdout(OutputRoute.borrow(&external.writer));
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), options, &child).succeeded);
        assert(external.writer.valid);
        assert(close(&external.writer).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(malloc_allocator());
        scope (exit)
            output.deinit();
        readPipeEntirely(&external.reader, &output);
        assert(output.slice.as_string_unchecked.equal("out\0data"));
        external.deinit();
    }

    {
        String[2] arguments = ["exit", "23"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), SpawnOptions.init, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded);
        assert(status.exited && status.exitCode == 23 && !status.succeeded);
    }

    {
        StringBuf signalText = StringBuf.from_string(malloc_allocator(), "15");
        String[2] arguments = ["signal", signalText.view];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), SpawnOptions.init, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded);
        assert(status.signaled && status.terminationSignal == SIGTERM);
        signalText.deinit();
    }

    {
        String[2] arguments = ["sleep-ms", "100"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), SpawnOptions.init, &child).succeeded);
        assert(tryWait(&child).state == WaitState.running);
        assert(waitFor(&child, Timeout.immediate).state == WaitState.running);
        assert(waitFor(&child, Timeout.after(milliseconds(5))).state ==
                WaitState.running);
        const waited = waitFor(&child, Timeout.after(milliseconds(500)));
        assert(waited.error.succeeded && waited.state == WaitState.exited &&
                waited.status.succeeded);
    }

    {
        String[2] arguments = ["sleep-ms", "5000"];
        ChildProcess source;
        scope (exit)
            source.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), SpawnOptions.init, &source).succeeded);
        const processId = source.id;
        ChildProcess target;
        scope (exit)
            target.deinit();
        move_assign(source, target);
        assert(source.empty && target.ownsProcess && target.id.value ==
                processId.value);
        ExitStatus status;
        assert(killAndWait(&target, &status).succeeded && status.signaled);
    }

    {
        String[2] arguments = ["sleep-ms", "5000"];
        ChildProcess child;
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), SpawnOptions.init, &child).succeeded);
        const processId = cast(int) child.id.value;
        ExitStatus status;
        assert(killAndWait(&child, &status).succeeded);
        assert(status.signaled);
        child.deinit();

        import core.stdc.errno : ESRCH, errno;
        import core.sys.posix.signal : nativeKill = kill;

        assert(nativeKill(processId, 0) != 0 && errno == ESRCH);
    }

    {
        String[2] arguments = ["sleep-ms", "5000"];
        const options = SpawnOptions.init.withIsolation(
            ProcessIsolation.isolatedTree,
        );
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), options, &child).succeeded);
        ExitStatus status;
        assert(terminateAndWait(&child, &status).succeeded);
        assert(status.signaled && status.terminationSignal == SIGTERM);
    }

    {
        const baseline = openDescriptorCount();
        const options = SpawnOptions.init
            .withStdin(InputRoute.piped())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.piped());
        ChildProcess child;
        scope (exit)
            child.deinit();
        const error = spawn(
            Command.exact(Path.from_string("/definitely/missing/xtb-helper")),
            options,
            &child,
        );
        assert(error.failed && error.operation == ProcessOperation.spawn);
        assert(error.os.kind == OsErrorKind.notFound && child.empty);
        assert(openDescriptorCount() == baseline);
    }
}

version (linux) private void runCommunicateIntegration(
    String helperExecutable,
) nothrow @system @nogc
{
    import core.sys.posix.signal : SIGKILL, SIGTERM;
    import xtb.duration : milliseconds;

    const routes = SpawnOptions.init
        .withStdin(InputRoute.piped())
        .withStdout(OutputRoute.piped())
        .withStderr(ErrorRoute.piped());

    {
        const baseline = openDescriptorCount();
        String[1] arguments = ["copy"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), routes, &child).succeeded);
        enum u8[9] input = [0, 1, 2, 3, 255, 'x', '\n', 0, 9];
        u8[9] outputStorage;
        CaptureBuffer output = CaptureBuffer(outputStorage[]);
        const result = communicate(
            &child,
            input[],
            &output,
            null,
            CommunicateOptions.init,
        );
        assert(result.error.succeeded &&
                result.state == CommunicateState.completed);
        assert(result.inputWritten == input.length &&
                result.exitStatus.is_some && result.exitStatus.value.succeeded);
        assert(output.bytes == input[] && !output.truncated && child.empty);
        assert(openDescriptorCount() == baseline);
    }

    {
        enum floodBytes = 128 * 1024;
        enum inputBytes = 256 * 1024;
        Array!u8 input = Array!u8.create(malloc_allocator());
        scope (exit)
            input.deinit();
        input.resize(inputBytes);
        foreach (i, ref value; input.slice)
            value = cast(u8)(i % 251);
        Array!u8 outputStorage = Array!u8.create(malloc_allocator());
        scope (exit)
            outputStorage.deinit();
        outputStorage.resize(floodBytes + inputBytes);
        Array!u8 errorStorage = Array!u8.create(malloc_allocator());
        scope (exit)
            errorStorage.deinit();
        errorStorage.resize(floodBytes);
        CaptureBuffer output = CaptureBuffer(outputStorage.slice);
        CaptureBuffer errorOutput = CaptureBuffer(errorStorage.slice);

        String[1] arguments = ["flood-copy"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), routes, &child).succeeded);
        const result = communicate(
            &child,
            input.slice,
            &output,
            &errorOutput,
            CommunicateOptions.init,
        );
        assert(result.error.succeeded && result.exitStatus.value.succeeded);
        assert(result.inputWritten == inputBytes);
        assert(output.length == floodBytes + inputBytes && !output.truncated);
        assert(errorOutput.length == floodBytes && !errorOutput.truncated);
        foreach (value; output.bytes[0 .. floodBytes])
            assert(value == 'O');
        assert(output.bytes[floodBytes .. $] == input.slice);
        foreach (value; errorOutput.bytes)
            assert(value == 'E');
    }

    {
        String[1] arguments = ["emit"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), routes, &child).succeeded);
        u8[7] outputStorage;
        u8[9] errorStorage;
        CaptureBuffer output = CaptureBuffer(outputStorage[]);
        CaptureBuffer errorOutput = CaptureBuffer(errorStorage[]);
        const result = communicate(&child, null, &output, &errorOutput,
            CommunicateOptions.init);
        assert(result.error.succeeded && result.exitStatus.value.succeeded);
        assert(output.bytes.as_string_unchecked.equal("out\0dat") &&
                output.truncated);
        assert(errorOutput.bytes.as_string_unchecked.equal("error-dat") &&
                errorOutput.truncated);
    }

    {
        String[1] arguments = ["flood-copy"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), routes, &child).succeeded);
        const result = communicate(
            &child,
            null,
            null,
            null,
            CommunicateOptions.init,
        );
        assert(result.error.succeeded && result.exitStatus.value.succeeded);
    }

    {
        String[1] arguments = ["close-input"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), routes, &child).succeeded);
        u8[128 * 1024] input;
        u8[6] outputStorage;
        CaptureBuffer output = CaptureBuffer(outputStorage[]);
        const result = communicate(&child, input[], &output, null,
            CommunicateOptions.init);
        assert(result.error.succeeded && result.inputWritten <= input.length);
        assert(result.exitStatus.value.succeeded);
        assert(output.bytes.as_string_unchecked.equal("closed"));
    }

    {
        String[2] arguments = ["delayed-emit", "30"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), routes, &child).succeeded);
        u8[7] outputStorage;
        CaptureBuffer output = CaptureBuffer(outputStorage[]);
        const first = communicate(
            &child,
            null,
            &output,
            null,
            CommunicateOptions.init.withTimeout(milliseconds(0)),
        );
        assert(first.error.succeeded &&
                first.state == CommunicateState.timedOutRunning);
        assert(child.ownsProcess && output.length == 0);

        const second = communicate(
            &child,
            null,
            &output,
            null,
            CommunicateOptions.init,
        );
        assert(second.error.succeeded &&
                second.state == CommunicateState.completed);
        assert(second.exitStatus.value.succeeded);
        assert(output.bytes.as_string_unchecked.equal("delayed"));
    }

    {
        String[2] arguments = ["sleep-ms", "5000"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), routes, &child).succeeded);
        const options = CommunicateOptions.init
            .withTimeout(milliseconds(5))
            .withTimeoutAction(TimeoutAction.requestThenKill)
            .withTerminationGrace(milliseconds(100));
        const result = communicate(&child, null, null, null, options);
        assert(result.error.succeeded &&
                result.state == CommunicateState.timedOutTerminated);
        assert(result.exitStatus.is_some && result.exitStatus.value.signaled &&
                result.exitStatus.value.terminationSignal == SIGTERM);
        assert(child.empty);
    }

    {
        String[2] arguments = ["sleep-ms", "5000"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), routes, &child).succeeded);
        const options = CommunicateOptions.init
            .withTimeout(milliseconds(5))
            .withTimeoutAction(TimeoutAction.kill);
        const result = communicate(&child, null, null, null, options);
        assert(result.error.succeeded &&
                result.state == CommunicateState.timedOutTerminated);
        assert(result.exitStatus.value.signaled &&
                result.exitStatus.value.terminationSignal == SIGKILL);
        assert(child.empty);
    }

    {
        String[1] arguments = ["copy"];
        ChildProcess child;
        scope (exit)
            child.deinit();
        assert(spawn(Command.exact(Path.from_string(helperExecutable),
                arguments[]), routes, &child).succeeded);
        u8[8] sharedStorage;
        CaptureBuffer aliased = CaptureBuffer(sharedStorage[]);
        const result = communicate(
            &child,
            sharedStorage[],
            &aliased,
            null,
            CommunicateOptions.init,
        );
        assert(result.error.os.kind == OsErrorKind.invalidArgument);
        assert(child.ownsProcess);
        ExitStatus status;
        assert(killAndWait(&child, &status).succeeded);
    }
}

version (linux) private void runPipelineIntegration(
    String helperExecutable,
) nothrow @system @nogc
{
    import core.stdc.errno : ESRCH, errno;
    import core.sys.posix.signal : nativeKill = kill;
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;

    {
        String[1] copyArguments = ["copy"];
        Command[3] commands = [
            Command.exact(Path.from_string(helperExecutable), copyArguments[]),
            Command.exact(Path.from_string(helperExecutable), copyArguments[]),
            Command.exact(Path.from_string(helperExecutable), copyArguments[]),
        ];
        const options = PipelineOptions.init
            .withStdin(InputRoute.piped())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.piped())
            .withSuccessPolicy(PipelineSuccess.everyStage);
        Pipeline pipeline;
        scope (exit)
            pipeline.deinit();
        assert(spawnPipeline(
                commands[], options, malloc_allocator(), &pipeline).succeeded);
        assert(pipeline.length == 3 && pipeline.stdinPipe !is null &&
                pipeline.stdoutPipe !is null);
        enum u8[8] input = [0, 1, 2, 255, 'p', 'i', 'p', 'e'];
        writePipeEntirely(pipeline.stdinPipe, input[]);
        assert(close(pipeline.stdinPipe).succeeded);
        assert(waitPipeline(&pipeline).succeeded);
        Array!u8 output = Array!u8.create(malloc_allocator());
        scope (exit)
            output.deinit();
        readPipeEntirely(pipeline.stdoutPipe, &output);
        assert(output.slice == input[] && pipeline.completed &&
                pipeline.succeeded);
        foreach (index; 0 .. pipeline.length)
        {
            assert(pipeline.status(index).succeeded);
            Array!u8 errorOutput = Array!u8.create(malloc_allocator());
            scope (exit)
                errorOutput.deinit();
            readPipeEntirely(pipeline.stderrPipe(index), &errorOutput);
            assert(errorOutput.empty);
        }
    }

    {
        String[1] emitArguments = ["emit"];
        String[1] copyArguments = ["copy"];
        PipelineStage[2] stages = [
            PipelineStage(Command.exact(
                    Path.from_string(helperExecutable), emitArguments[],
            ))
                .withStderr(ErrorRoute.piped()),
            PipelineStage(Command.exact(
                    Path.from_string(helperExecutable), copyArguments[],
            )),
        ];
        const options = PipelineOptions.init
            .withStdin(InputRoute.nullDevice())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.nullDevice());
        Pipeline pipeline;
        scope (exit)
            pipeline.deinit();
        assert(spawnPipeline(
                stages[], options, malloc_allocator(), &pipeline).succeeded);
        assert(waitPipeline(&pipeline).succeeded && pipeline.succeeded);
        Array!u8 output = Array!u8.create(malloc_allocator());
        scope (exit)
            output.deinit();
        Array!u8 errorOutput = Array!u8.create(malloc_allocator());
        scope (exit)
            errorOutput.deinit();
        readPipeEntirely(pipeline.stdoutPipe, &output);
        readPipeEntirely(pipeline.stderrPipe(0), &errorOutput);
        assert(output.slice.as_string_unchecked.equal("out\0data"));
        assert(errorOutput.slice.as_string_unchecked.equal("error-data"));
        assert(pipeline.stderrPipe(1) is null);
    }

    {
        String[2] exitArguments = ["exit", "7"];
        String[1] copyArguments = ["copy"];
        Command[2] commands = [
            Command.exact(Path.from_string(helperExecutable), exitArguments[]),
            Command.exact(Path.from_string(helperExecutable), copyArguments[]),
        ];
        Pipeline pipeline;
        scope (exit)
            pipeline.deinit();
        assert(spawnPipeline(commands[], PipelineOptions.init,
                malloc_allocator(), &pipeline).succeeded);
        assert(waitPipeline(&pipeline).succeeded);
        assert(pipeline.status(0).exitCode == 7 &&
                pipeline.status(1).succeeded && pipeline.succeeded);

        PipelineOptions allStages;
        allStages.success = PipelineSuccess.everyStage;
        Pipeline strictPipeline;
        scope (exit)
            strictPipeline.deinit();
        assert(spawnPipeline(commands[], allStages, malloc_allocator(),
                &strictPipeline).succeeded);
        assert(waitPipeline(&strictPipeline).succeeded);
        assert(!strictPipeline.succeeded);
    }

    {
        String[2] sleepArguments = ["sleep-ms", "100"];
        Command[2] commands = [
            Command.exact(Path.from_string(helperExecutable), sleepArguments[]),
            Command.exact(Path.from_string(helperExecutable), sleepArguments[]),
        ];
        Pipeline pipeline;
        scope (exit)
            pipeline.deinit();
        assert(spawnPipeline(commands[], PipelineOptions.init,
                malloc_allocator(), &pipeline).succeeded);
        const observed = tryWaitPipeline(&pipeline);
        assert(observed.error.succeeded &&
                observed.state == PipelineWaitState.running &&
                observed.runningStages != 0);
        assert(waitPipeline(&pipeline).succeeded && pipeline.completed);
    }

    {
        String[2] sleepArguments = ["sleep-ms", "5000"];
        Command[2] commands = [
            Command.exact(Path.from_string(helperExecutable), sleepArguments[]),
            Command.exact(Path.from_string(helperExecutable), sleepArguments[]),
        ];
        Pipeline pipeline;
        assert(spawnPipeline(commands[], PipelineOptions.init,
                malloc_allocator(), &pipeline).succeeded);
        int[2] processIds = [
            cast(int) pipeline.stageId(0).value,
            cast(int) pipeline.stageId(1).value,
        ];
        assert(killPipelineAndWait(&pipeline).succeeded);
        assert(pipeline.completed);
        pipeline.deinit();
        foreach (processId; processIds)
            assert(nativeKill(processId, 0) != 0 && errno == ESRCH);
    }

    {
        const baseline = openDescriptorCount();
        String[1] copyArguments = ["copy"];
        Command[2] commands = [
            Command.exact(Path.from_string(helperExecutable), copyArguments[]),
            Command.exact(Path.from_string("/missing/xtb-pipeline-stage")),
        ];
        Pipeline pipeline;
        scope (exit)
            pipeline.deinit();
        const error = spawnPipeline(
            commands[],
            PipelineOptions.init,
            malloc_allocator(),
            &pipeline,
        );
        assert(error.failed &&
                error.operation == ProcessOperation.pipelineSpawn &&
                error.stageIndex == 1 && pipeline.empty);
        assert(openDescriptorCount() == baseline);
        assertNoChildProcesses();
    }

    {
        String[1] copyArguments = ["copy"];
        Command[1] commands = [Command.exact(
                Path.from_string(helperExecutable), copyArguments[],
            )];
        AllocationRecord[4] records;
        InstrumentedAllocator failing = InstrumentedAllocator.create(
            malloc_allocator(), records[],
        );
        failing.fail_after(0);
        Pipeline pipeline;
        scope (exit)
            pipeline.deinit();
        const error = spawnPipeline(
            commands[],
            PipelineOptions.init,
            failing.allocator,
            &pipeline,
        );
        assert(error.os.kind == OsErrorKind.resourceExhausted);
        assert(pipeline.empty && failing.clean);
    }
}

version (linux) private void runLinuxIntegration() nothrow @system @nogc
{
    import core.sys.posix.stdlib : mkdtemp;
    import xtb.process.environment : environmentVariable;

    ThreadContextScope context = ThreadContextScope.acquire();
    Pipe closedPipe;
    scope (exit)
        closedPipe.deinit();
    assert(createPipe(PipeOptions.init, &closedPipe).succeeded);
    assert(close(&closedPipe.reader).succeeded);
    auto closedPipeStarted = Thread.start!closedPipeWriteWorker(
        &closedPipe.writer,
    );
    assert(closedPipeStarted.is_ok);
    Thread closedPipeThread = closedPipeStarted.unwrap();
    assert(closedPipeThread.join() == 0);

    enum rootPattern = "/tmp/xtb-system-XXXXXX";
    char[rootPattern.length + 1] rootStorage;
    rootStorage[0 .. rootPattern.length] = rootPattern;
    rootStorage[$ - 1] = '\0';
    const createdRoot = mkdtemp(rootStorage.ptr);
    assert(createdRoot !is null);
    const checkedRoot = from_c_string(createdRoot);
    assert(checkedRoot.succeeded);
    const rootPath = Path.from_string(checkedRoot.value);
    OsError error;

    StringBuf first = StringBuf.from_string(malloc_allocator(), rootPath.view);
    first.append("/first.bin");
    const firstPath = Path.from_string(first.view);
    const u8[6] contents = [0, 1, 2, 3, 0, 255];
    const helperDescriptorCount = openDescriptorCount();
    assert(write_entire_file(firstPath, contents[]).succeeded);

    File explicitFile;
    assert(open(firstPath, OpenOptions.init, &explicitFile).succeeded);
    assert(explicitFile.valid);
    assert(explicitFile.close().succeeded && !explicitFile.valid);
    assert(explicitFile.close().succeeded);
    deinit(explicitFile);
    OpenOptions invalidOptions;
    invalidOptions.read = false;
    assert(open(firstPath, invalidOptions, &explicitFile).kind == OsErrorKind.invalidArgument);

    FileMetadata information;
    assert(metadata(firstPath, SymlinkMode.follow, &information).succeeded);
    assert(information.type == FileType.regular && information.size == contents.length);

    Array!u8 loaded = Array!u8.create(malloc_allocator());
    scope (exit)
        loaded.deinit();
    assert(read_entire_file(firstPath, &loaded).succeeded);
    assert(loaded.slice == contents[]);
    assert(openDescriptorCount() == helperDescriptorCount);

    {
        import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;

        const baseline = openDescriptorCount();
        AllocationRecord[2] records;
        InstrumentedAllocator failing = InstrumentedAllocator.create(
            malloc_allocator(), records[],
        );
        failing.fail_after(0);
        Array!u8 failedRead = Array!u8.create(failing.allocator);
        assert(read_entire_file(firstPath, &failedRead).kind == OsErrorKind.system);
        assert(openDescriptorCount() == baseline);
        deinit(failedRead);
        assert(failing.clean);
    }

    {
        const baseline = openDescriptorCount();
        File source;
        File target;
        assert(open(firstPath, OpenOptions.init, &source).succeeded);
        assert(open(firstPath, OpenOptions.init, &target).succeeded);
        assert(openDescriptorCount() == baseline + 2);
        move_assign(source, target);
        assert(!source.valid && target.valid);
        assert(openDescriptorCount() == baseline + 1);
        deinit(source);
        deinit(target);
        assert(openDescriptorCount() == baseline);
    }

    {
        const baseline = openDescriptorCount();
        File file;
        assert(open(firstPath, OpenOptions.init, &file).succeeded);
        Option!File optional = Option!File.some(move(file));
        assert(!file.valid && optional.value.valid);
        deinit(optional);
        assert(openDescriptorCount() == baseline);
    }

    {
        const baseline = openDescriptorCount();
        File file;
        assert(open(firstPath, OpenOptions.init, &file).succeeded);
        Result!(File, OsError) result = Result!(File, OsError).ok(move(file));
        assert(!file.valid && result.value.valid);
        deinit(result);
        assert(openDescriptorCount() == baseline);
    }

    {
        const baseline = openDescriptorCount();
        OwnedArray!File files = OwnedArray!File.create(malloc_allocator());
        File firstFile;
        File secondFile;
        assert(open(firstPath, OpenOptions.init, &firstFile).succeeded);
        assert(open(firstPath, OpenOptions.init, &secondFile).succeeded);
        files.append(move(firstFile));
        files.append(move(secondFile));
        assert(!firstFile.valid && !secondFile.valid);
        assert(openDescriptorCount() == baseline + 2);
        deinit(files);
        assert(openDescriptorCount() == baseline);
    }

    {
        const baseline = openDescriptorCount();
        FileOwnerComposition owner;
        assert(open(firstPath, OpenOptions.init, &owner.file).succeeded);
        deinit(owner);
        assert(openDescriptorCount() == baseline);
    }

    {
        const baseline = openDescriptorCount();
        DirectoryIterator source;
        DirectoryIterator target;
        assert(open_directory(rootPath, &source).succeeded);
        assert(open_directory(rootPath, &target).succeeded);
        assert(openDescriptorCount() == baseline + 2);
        move_assign(source, target);
        assert(!source.valid && target.valid);
        assert(openDescriptorCount() == baseline + 1);
        deinit(source);
        deinit(target);
        assert(openDescriptorCount() == baseline);
    }

    {
        const baseline = openDescriptorCount();
        Pipe source;
        Pipe target;
        assert(createPipe(PipeOptions.init, &source).succeeded);
        assert(createPipe(PipeOptions.init, &target).succeeded);
        assert(openDescriptorCount() == baseline + 4);
        move_assign(source, target);
        assert(!source.valid && target.valid);
        assert(openDescriptorCount() == baseline + 2);
        deinit(source);
        deinit(target);
        assert(openDescriptorCount() == baseline);
    }

    {
        MappedFile source;
        MappedFile target;
        assert(map_read_only(firstPath, &source).succeeded);
        assert(map_read_only(firstPath, &target).succeeded);
        move_assign(source, target);
        assert(source.empty);
        assert(target.bytes == contents[]);
        deinit(source);
        deinit(target);
    }

    MappedFile mapping;
    assert(map_read_only(firstPath, &mapping).succeeded);
    assert(mapping.bytes == contents[]);
    assert(mapping.unmap().succeeded);
    assert(mapping.unmap().succeeded);

    StringBuf second = StringBuf.from_string(malloc_allocator(), rootPath.view);
    second.append("/second.bin");
    const secondPath = Path.from_string(second.view);
    assert(copy_file(firstPath, secondPath, &loaded, CreateMode.create_new).succeeded);
    assert(copy_file(firstPath, secondPath, &loaded, CreateMode.create_new).kind ==
            OsErrorKind.alreadyExists);

    StringBuf renamed = StringBuf.from_string(malloc_allocator(), rootPath.view);
    renamed.append("/renamed.bin");
    const renamedPath = Path.from_string(renamed.view);
    assert(rename(secondPath, renamedPath).succeeded);

    DirectoryIterator iterator;
    assert(open_directory(rootPath, &iterator).succeeded);
    size_t entries;
    DirectoryEntry entry;
    for (;;)
    {
        const result = iterator.next(&entry);
        assert(result.status != DirectoryStatus.failed);
        if (result.status == DirectoryStatus.finished)
            break;
        assert(entry.name == "first.bin" || entry.name == "renamed.bin");
        ++entries;
    }
    assert(entries == 2);
    assert(iterator.close().succeeded);
    assert(iterator.close().succeeded);
    size_t walked;
    Arena walkArena = Arena.create(malloc_allocator(), 256);
    const walkDescriptorBaseline = openDescriptorCount();
    assert(walk_directory(rootPath, walkArena.allocator, &countEntry, &walked).succeeded);
    assert(walked == 2);
    assert(openDescriptorCount() == walkDescriptorBaseline);

    bool exists;
    assert(query_access(firstPath, Access.exists, &exists).succeeded && exists);
    assert(query_access(firstPath, Access.read, &exists).succeeded && exists);

    StringBuf cwd = StringBuf.create(malloc_allocator());
    assert(current_directory(&cwd).succeeded && cwd.view.length != 0);
    StringBuf canonical = StringBuf.create(malloc_allocator());
    assert(canonical_path(rootPath, &canonical).succeeded);
    assert(canonical.view.length != 0);
    StringBuf executable = StringBuf.create(malloc_allocator());
    assert(executable_path(&executable).succeeded && executable.view.length != 0);

    Array!u8 procStatus = Array!u8.create(malloc_allocator());
    scope (exit)
        procStatus.deinit();
    assert(read_entire_file(Path.from_string("/proc/self/status"), &procStatus).succeeded);
    assert(procStatus.length != 0);

    Arena* outputArena = scratch_arena();
    outputArena.set_rewind_poisoning(true);
    TempArena outputTemporary = outputArena.push();
    {
        StringBuf scratchCanonical = StringBuf.create(outputTemporary.allocator);
        assert(canonical_path(rootPath, &scratchCanonical).succeeded);
        assert(scratchCanonical.view.length != 0);
        assert(scratchCanonical.view[0] != cast(char) 0xDD);

        StringBuf scratchExecutable = StringBuf.create(outputTemporary.allocator);
        assert(executable_path(&scratchExecutable).succeeded);
        assert(scratchExecutable.view.length != 0);
        assert(scratchExecutable.view[0] != cast(char) 0xDD);
    }
    outputTemporary.pop();
    outputArena.set_rewind_poisoning(false);

    String environmentPath;
    assert(environmentVariable("PATH", &environmentPath).succeeded);
    assert(environmentPath.length != 0);
    const before = Instant.now();
    sleep(milliseconds(1));
    const after = Instant.now();
    assert(after >= before);
    assert(Timestamp.now().nanosecondsSinceUnixEpoch != 0);

    const helperDirectory = Path.from_string(executable.view).parent;
    StringBuf helperExecutable = StringBuf.from_string(
        malloc_allocator(),
        helperDirectory.view,
    );
    helperExecutable.append_component(Path.from_string("process_test_helper"));
    runProcessIntegration(
        helperExecutable.view,
        helperDirectory.view,
        rootPath,
    );
    runCommunicateIntegration(helperExecutable.view);
    runPipelineIntegration(helperExecutable.view);

    walkArena.deinit();

    assert(remove_file(firstPath).succeeded);
    assert(remove_file(renamedPath).succeeded);
    assert(remove_empty_directory(rootPath).succeeded);

    helperExecutable.deinit();
    executable.deinit();
    canonical.deinit();
    cwd.deinit();
    renamed.deinit();
    second.deinit();
    first.deinit();
}

extern (C) int main()
{
    version (linux)
        runLinuxIntegration();
    return 0;
}
