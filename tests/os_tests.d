module tests.os_tests;

import xtb.os.directory;
import xtb.os.error;
import xtb.os.environment;
import xtb.os.file;
import xtb.os.memory_map;
import xtb.os.path;
import xtb.os.pipeline;
import xtb.os.pipe;
import xtb.os.process;
import xtb.os.process_io;
import xtb.os.time;
import xtb.os.terminal;
import xtb.core.array : Array, append, resize;
import xtb.core.arena : Arena, TempArena, pop, push;
import xtb.core.memory : mallocAllocator;
import xtb.core.string : String, StringBuf, append, asStringUnchecked, equal,
    fromCString;
import xtb.core.thread_context : ThreadContextScope, scratchArena;
import xtb.core.types : i64, u64, u8;

version (linux) private bool countEntry(Path, FileType, void* context) nothrow @system @nogc
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
    import xtb.core.duration : milliseconds;

    SpawnOptions pipedOutput = SpawnOptions.init
        .withStdin(InputRoute.nullDevice())
        .withStdout(OutputRoute.piped())
        .withStderr(ErrorRoute.nullDevice());

    {
        String[4] arguments = ["argv", "hello world", "", "quote\"mark"];
        Command command = Command.exact(
            Path.fromString(helperExecutable),
            arguments[],
        );
        command.setArgumentZero("custom-zero");
        ChildProcess child;
        assert(spawn(command, pipedOutput, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(mallocAllocator());
        readPipeEntirely(child.stdoutPipe, &output);
        assert(output.slice.asStringUnchecked.equal(
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
        assert(spawn(command, pipedOutput, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(mallocAllocator());
        readPipeEntirely(child.stdoutPipe, &output);

        StringBuf expected = StringBuf.fromString(
            mallocAllocator(),
            "ONLY=value\0EMPTY=\0REMOVED\0PATH=",
        );
        expected.append(helperDirectory);
        expected.append('\0');
        assert(output.slice.asStringUnchecked.equal(expected.view));
    }

    {
        String[1] arguments = ["cwd"];
        Command command = Command.exact(
            Path.fromString(helperExecutable),
            arguments[],
        );
        command.setWorkingDirectory(temporaryDirectory);
        ChildProcess child;
        assert(spawn(command, pipedOutput, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(mallocAllocator());
        readPipeEntirely(child.stdoutPipe, &output);
        assert(output.slice.asStringUnchecked.equal(temporaryDirectory.view));
    }

    {
        String[1] arguments = ["copy"];
        const options = SpawnOptions.init
            .withStdin(InputRoute.piped())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.nullDevice());
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), options, &child).succeeded);
        enum u8[7] input = [0, 1, 2, 255, 'x', '\n', 0];
        writePipeEntirely(child.stdinPipe, input[]);
        assert(close(child.stdinPipe).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(mallocAllocator());
        readPipeEntirely(child.stdoutPipe, &output);
        assert(output.slice == input[]);
    }

    {
        String[1] arguments = ["emit"];
        const options = pipedOutput.withStderr(ErrorRoute.mergeWithStdout());
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), options, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(mallocAllocator());
        readPipeEntirely(child.stdoutPipe, &output);
        assert(output.slice.asStringUnchecked.equal("out\0dataerror-data"));
    }

    {
        String[1] arguments = ["emit"];
        const options = pipedOutput.withStderr(ErrorRoute.piped());
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), options, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(mallocAllocator());
        Array!u8 errorOutput = Array!u8.create(mallocAllocator());
        readPipeEntirely(child.stdoutPipe, &output);
        readPipeEntirely(child.stderrPipe, &errorOutput);
        assert(output.slice.asStringUnchecked.equal("out\0data"));
        assert(errorOutput.slice.asStringUnchecked.equal("error-data"));
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
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), options, &child).succeeded);
        assert(external.writer.valid);
        assert(close(&external.writer).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded && status.succeeded);
        Array!u8 output = Array!u8.create(mallocAllocator());
        readPipeEntirely(&external.reader, &output);
        assert(output.slice.asStringUnchecked.equal("out\0data"));
    }

    {
        String[2] arguments = ["exit", "23"];
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), SpawnOptions.init, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded);
        assert(status.exited && status.exitCode == 23 && !status.succeeded);
    }

    {
        StringBuf signalText = StringBuf.fromString(mallocAllocator(), "15");
        String[2] arguments = ["signal", signalText.view];
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), SpawnOptions.init, &child).succeeded);
        ExitStatus status;
        assert(wait(&child, &status).succeeded);
        assert(status.signaled && status.terminationSignal == SIGTERM);
    }

    {
        String[2] arguments = ["sleep-ms", "100"];
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
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
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), SpawnOptions.init, &child).succeeded);
        const processId = cast(int) child.id.value;
        child.deinit();
        assert(child.empty);

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
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), options, &child).succeeded);
        ExitStatus status;
        assert(terminateAndWait(&child, &status).succeeded);
        assert(status.signaled && status.terminationSignal == SIGTERM);
    }

    {
        ChildProcess child;
        const error = spawn(
            Command.exact(Path.fromString("/definitely/missing/xtb-helper")),
            SpawnOptions.init,
            &child,
        );
        assert(error.failed && error.operation == ProcessOperation.spawn);
        assert(error.os.kind == OsErrorKind.notFound && child.empty);
    }
}

version (linux) private void runCommunicateIntegration(
    String helperExecutable,
) nothrow @system @nogc
{
    import core.sys.posix.signal : SIGKILL, SIGTERM;
    import xtb.core.duration : milliseconds;

    const routes = SpawnOptions.init
        .withStdin(InputRoute.piped())
        .withStdout(OutputRoute.piped())
        .withStderr(ErrorRoute.piped());

    {
        String[1] arguments = ["copy"];
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
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
                result.exitStatus.isSome && result.exitStatus.value.succeeded);
        assert(output.bytes == input[] && !output.truncated && child.empty);
    }

    {
        enum floodBytes = 128 * 1024;
        enum inputBytes = 256 * 1024;
        Array!u8 input = Array!u8.create(mallocAllocator());
        input.resize(inputBytes);
        foreach (i, ref value; input.slice)
            value = cast(u8)(i % 251);
        Array!u8 outputStorage = Array!u8.create(mallocAllocator());
        outputStorage.resize(floodBytes + inputBytes);
        Array!u8 errorStorage = Array!u8.create(mallocAllocator());
        errorStorage.resize(floodBytes);
        CaptureBuffer output = CaptureBuffer(outputStorage.slice);
        CaptureBuffer errorOutput = CaptureBuffer(errorStorage.slice);

        String[1] arguments = ["flood-copy"];
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
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
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), routes, &child).succeeded);
        u8[7] outputStorage;
        u8[9] errorStorage;
        CaptureBuffer output = CaptureBuffer(outputStorage[]);
        CaptureBuffer errorOutput = CaptureBuffer(errorStorage[]);
        const result = communicate(&child, null, &output, &errorOutput,
            CommunicateOptions.init);
        assert(result.error.succeeded && result.exitStatus.value.succeeded);
        assert(output.bytes.asStringUnchecked.equal("out\0dat") &&
                output.truncated);
        assert(errorOutput.bytes.asStringUnchecked.equal("error-dat") &&
                errorOutput.truncated);
    }

    {
        String[1] arguments = ["flood-copy"];
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
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
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), routes, &child).succeeded);
        u8[128 * 1024] input;
        u8[6] outputStorage;
        CaptureBuffer output = CaptureBuffer(outputStorage[]);
        const result = communicate(&child, input[], &output, null,
            CommunicateOptions.init);
        assert(result.error.succeeded && result.inputWritten <= input.length);
        assert(result.exitStatus.value.succeeded);
        assert(output.bytes.asStringUnchecked.equal("closed"));
    }

    {
        String[2] arguments = ["delayed-emit", "30"];
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
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
        assert(output.bytes.asStringUnchecked.equal("delayed"));
    }

    {
        String[2] arguments = ["sleep-ms", "5000"];
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
                arguments[]), routes, &child).succeeded);
        const options = CommunicateOptions.init
            .withTimeout(milliseconds(5))
            .withTimeoutAction(TimeoutAction.requestThenKill)
            .withTerminationGrace(milliseconds(100));
        const result = communicate(&child, null, null, null, options);
        assert(result.error.succeeded &&
                result.state == CommunicateState.timedOutTerminated);
        assert(result.exitStatus.isSome && result.exitStatus.value.signaled &&
                result.exitStatus.value.terminationSignal == SIGTERM);
        assert(child.empty);
    }

    {
        String[2] arguments = ["sleep-ms", "5000"];
        ChildProcess child;
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
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
        assert(spawn(Command.exact(Path.fromString(helperExecutable),
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
        child.deinit();
    }
}

version (linux) private void runPipelineIntegration(
    String helperExecutable,
) nothrow @system @nogc
{
    import core.stdc.errno : ESRCH, errno;
    import core.sys.posix.signal : nativeKill = kill;
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator;

    {
        String[1] copyArguments = ["copy"];
        Command[3] commands = [
            Command.exact(Path.fromString(helperExecutable), copyArguments[]),
            Command.exact(Path.fromString(helperExecutable), copyArguments[]),
            Command.exact(Path.fromString(helperExecutable), copyArguments[]),
        ];
        const options = PipelineOptions.init
            .withStdin(InputRoute.piped())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.piped())
            .withSuccessPolicy(PipelineSuccess.everyStage);
        Pipeline pipeline;
        assert(spawnPipeline(
                commands[], options, mallocAllocator(), &pipeline).succeeded);
        assert(pipeline.length == 3 && pipeline.stdinPipe !is null &&
                pipeline.stdoutPipe !is null);
        enum u8[8] input = [0, 1, 2, 255, 'p', 'i', 'p', 'e'];
        writePipeEntirely(pipeline.stdinPipe, input[]);
        assert(close(pipeline.stdinPipe).succeeded);
        assert(waitPipeline(&pipeline).succeeded);
        Array!u8 output = Array!u8.create(mallocAllocator());
        readPipeEntirely(pipeline.stdoutPipe, &output);
        assert(output.slice == input[] && pipeline.completed &&
                pipeline.succeeded);
        foreach (index; 0 .. pipeline.length)
        {
            assert(pipeline.status(index).succeeded);
            Array!u8 errorOutput = Array!u8.create(mallocAllocator());
            readPipeEntirely(pipeline.stderrPipe(index), &errorOutput);
            assert(errorOutput.empty);
        }
    }

    {
        String[1] emitArguments = ["emit"];
        String[1] copyArguments = ["copy"];
        PipelineStage[2] stages = [
            PipelineStage(Command.exact(
                    Path.fromString(helperExecutable), emitArguments[],
            ))
                .withStderr(ErrorRoute.piped()),
            PipelineStage(Command.exact(
                    Path.fromString(helperExecutable), copyArguments[],
            )),
        ];
        const options = PipelineOptions.init
            .withStdin(InputRoute.nullDevice())
            .withStdout(OutputRoute.piped())
            .withStderr(ErrorRoute.nullDevice());
        Pipeline pipeline;
        assert(spawnPipeline(
                stages[], options, mallocAllocator(), &pipeline).succeeded);
        assert(waitPipeline(&pipeline).succeeded && pipeline.succeeded);
        Array!u8 output = Array!u8.create(mallocAllocator());
        Array!u8 errorOutput = Array!u8.create(mallocAllocator());
        readPipeEntirely(pipeline.stdoutPipe, &output);
        readPipeEntirely(pipeline.stderrPipe(0), &errorOutput);
        assert(output.slice.asStringUnchecked.equal("out\0data"));
        assert(errorOutput.slice.asStringUnchecked.equal("error-data"));
        assert(pipeline.stderrPipe(1) is null);
    }

    {
        String[2] exitArguments = ["exit", "7"];
        String[1] copyArguments = ["copy"];
        Command[2] commands = [
            Command.exact(Path.fromString(helperExecutable), exitArguments[]),
            Command.exact(Path.fromString(helperExecutable), copyArguments[]),
        ];
        Pipeline pipeline;
        assert(spawnPipeline(commands[], PipelineOptions.init,
                mallocAllocator(), &pipeline).succeeded);
        assert(waitPipeline(&pipeline).succeeded);
        assert(pipeline.status(0).exitCode == 7 &&
                pipeline.status(1).succeeded && pipeline.succeeded);

        PipelineOptions allStages;
        allStages.success = PipelineSuccess.everyStage;
        Pipeline strictPipeline;
        assert(spawnPipeline(commands[], allStages, mallocAllocator(),
                &strictPipeline).succeeded);
        assert(waitPipeline(&strictPipeline).succeeded);
        assert(!strictPipeline.succeeded);
    }

    {
        String[2] sleepArguments = ["sleep-ms", "100"];
        Command[2] commands = [
            Command.exact(Path.fromString(helperExecutable), sleepArguments[]),
            Command.exact(Path.fromString(helperExecutable), sleepArguments[]),
        ];
        Pipeline pipeline;
        assert(spawnPipeline(commands[], PipelineOptions.init,
                mallocAllocator(), &pipeline).succeeded);
        const observed = tryWaitPipeline(&pipeline);
        assert(observed.error.succeeded &&
                observed.state == PipelineWaitState.running &&
                observed.runningStages != 0);
        assert(waitPipeline(&pipeline).succeeded && pipeline.completed);
    }

    {
        String[2] sleepArguments = ["sleep-ms", "5000"];
        Command[2] commands = [
            Command.exact(Path.fromString(helperExecutable), sleepArguments[]),
            Command.exact(Path.fromString(helperExecutable), sleepArguments[]),
        ];
        Pipeline pipeline;
        assert(spawnPipeline(commands[], PipelineOptions.init,
                mallocAllocator(), &pipeline).succeeded);
        int[2] processIds = [
            cast(int) pipeline.stageId(0).value,
            cast(int) pipeline.stageId(1).value,
        ];
        pipeline.deinit();
        assert(pipeline.empty);
        foreach (processId; processIds)
            assert(nativeKill(processId, 0) != 0 && errno == ESRCH);
    }

    {
        String[1] copyArguments = ["copy"];
        Command[2] commands = [
            Command.exact(Path.fromString(helperExecutable), copyArguments[]),
            Command.exact(Path.fromString("/missing/xtb-pipeline-stage")),
        ];
        Pipeline pipeline;
        const error = spawnPipeline(
            commands[],
            PipelineOptions.init,
            mallocAllocator(),
            &pipeline,
        );
        assert(error.failed &&
                error.operation == ProcessOperation.pipelineSpawn &&
                error.stageIndex == 1 && pipeline.empty);
    }

    {
        String[1] copyArguments = ["copy"];
        Command[1] commands = [Command.exact(
                Path.fromString(helperExecutable), copyArguments[],
            )];
        AllocationRecord[4] records;
        InstrumentedAllocator failing = InstrumentedAllocator.create(
            mallocAllocator(), records[],
        );
        failing.failAfter(0);
        Pipeline pipeline;
        const error = spawnPipeline(
            commands[],
            PipelineOptions.init,
            failing.handle,
            &pipeline,
        );
        assert(error.os.kind == OsErrorKind.resourceExhausted);
        assert(pipeline.empty && failing.clean);
    }
}

version (linux) private void runLinuxIntegration() nothrow @system @nogc
{
    import core.sys.posix.stdlib : mkdtemp;
    import xtb.os.environment : environmentVariable;

    ThreadContextScope context = ThreadContextScope.acquire();
    enum rootPattern = "/tmp/xtb-os-XXXXXX";
    char[rootPattern.length + 1] rootStorage;
    rootStorage[0 .. rootPattern.length] = rootPattern;
    rootStorage[$ - 1] = '\0';
    const createdRoot = mkdtemp(rootStorage.ptr);
    assert(createdRoot !is null);
    const checkedRoot = fromCString(createdRoot);
    assert(checkedRoot.succeeded);
    const rootPath = Path.fromString(checkedRoot.value);
    OsError error;

    StringBuf first = StringBuf.fromString(mallocAllocator(), rootPath.view);
    first.append("/first.bin");
    const firstPath = Path.fromString(first.view);
    const u8[6] contents = [0, 1, 2, 3, 0, 255];
    assert(writeEntireFile(firstPath, contents[]).succeeded);

    File explicitFile;
    assert(open(firstPath, OpenOptions.init, &explicitFile).succeeded);
    assert(explicitFile.valid);
    assert(close(&explicitFile).succeeded && !explicitFile.valid);
    assert(close(&explicitFile).succeeded);
    OpenOptions invalidOptions;
    invalidOptions.read = false;
    assert(open(firstPath, invalidOptions, &explicitFile).kind == OsErrorKind.invalidArgument);

    FileMetadata information;
    assert(metadata(firstPath, SymlinkMode.follow, &information).succeeded);
    assert(information.type == FileType.regular && information.size == contents.length);

    Array!u8 loaded = Array!u8.create(mallocAllocator());
    assert(readEntireFile(firstPath, loaded).succeeded);
    assert(loaded.slice == contents[]);

    MappedFile mapping;
    assert(mapReadOnly(firstPath, &mapping).succeeded);
    assert(mapping.bytes == contents[]);
    assert(unmap(&mapping).succeeded);
    assert(unmap(&mapping).succeeded);

    StringBuf second = StringBuf.fromString(mallocAllocator(), rootPath.view);
    second.append("/second.bin");
    const secondPath = Path.fromString(second.view);
    assert(copyFile(firstPath, secondPath, loaded, CreateMode.createNew).succeeded);
    assert(copyFile(firstPath, secondPath, loaded, CreateMode.createNew).kind ==
            OsErrorKind.alreadyExists);

    StringBuf renamed = StringBuf.fromString(mallocAllocator(), rootPath.view);
    renamed.append("/renamed.bin");
    const renamedPath = Path.fromString(renamed.view);
    assert(rename(secondPath, renamedPath).succeeded);

    DirectoryIterator iterator;
    assert(openDirectory(rootPath, &iterator).succeeded);
    size_t entries;
    DirectoryEntry entry;
    for (;;)
    {
        const result = (&iterator).next(&entry);
        assert(result.status != DirectoryStatus.failed);
        if (result.status == DirectoryStatus.finished)
            break;
        assert(entry.name == "first.bin" || entry.name == "renamed.bin");
        ++entries;
    }
    assert(entries == 2);
    assert(close(&iterator).succeeded);
    assert(close(&iterator).succeeded);
    size_t walked;
    Arena walkArena = Arena.create(mallocAllocator(), 256);
    assert(walkDirectory(rootPath, walkArena.allocatorHandle, &countEntry, &walked).succeeded);
    assert(walked == 2);

    bool exists;
    assert(queryAccess(firstPath, Access.exists, &exists).succeeded && exists);
    assert(queryAccess(firstPath, Access.read, &exists).succeeded && exists);

    StringBuf cwd = StringBuf.create(mallocAllocator());
    assert(currentDirectory(cwd).succeeded && cwd.view.length != 0);
    StringBuf canonical = StringBuf.create(mallocAllocator());
    assert(canonicalPath(rootPath, canonical).succeeded);
    assert(canonical.view.length != 0);
    StringBuf executable = StringBuf.create(mallocAllocator());
    assert(executablePath(executable).succeeded && executable.view.length != 0);

    Array!u8 procStatus = Array!u8.create(mallocAllocator());
    assert(readEntireFile(Path.fromString("/proc/self/status"), procStatus).succeeded);
    assert(procStatus.length != 0);

    Arena* outputArena = scratchArena();
    outputArena.setRewindPoisoning(true);
    TempArena outputTemporary = outputArena.push();
    {
        StringBuf scratchCanonical = StringBuf.create(outputTemporary.allocator);
        assert(canonicalPath(rootPath, scratchCanonical).succeeded);
        assert(scratchCanonical.view.length != 0);
        assert(scratchCanonical.view[0] != cast(char) 0xDD);

        StringBuf scratchExecutable = StringBuf.create(outputTemporary.allocator);
        assert(executablePath(scratchExecutable).succeeded);
        assert(scratchExecutable.view.length != 0);
        assert(scratchExecutable.view[0] != cast(char) 0xDD);
    }
    outputTemporary.pop();
    outputArena.setRewindPoisoning(false);

    String environmentPath;
    assert(environmentVariable("PATH", &environmentPath).succeeded);
    assert(environmentPath.length != 0);
    u64 before;
    u64 after;
    assert(monotonicNanoseconds(&before).succeeded);
    assert(sleepNanoseconds(1_000_000).succeeded);
    assert(monotonicNanoseconds(&after).succeeded && after >= before);
    i64 wallTime;
    assert(wallClockNanoseconds(&wallTime).succeeded && wallTime != 0);

    StringBuf helperDirectory = StringBuf.fromString(
        mallocAllocator(),
        cwd.view,
    );
    helperDirectory.append("/build");
    StringBuf helperExecutable = StringBuf.fromString(
        mallocAllocator(),
        helperDirectory.view,
    );
    helperExecutable.append("/process_test_helper");
    runProcessIntegration(
        helperExecutable.view,
        helperDirectory.view,
        rootPath,
    );
    runCommunicateIntegration(helperExecutable.view);
    runPipelineIntegration(helperExecutable.view);

    assert(removeFile(firstPath).succeeded);
    assert(removeFile(renamedPath).succeeded);
    assert(removeEmptyDirectory(rootPath).succeeded);
}

extern (C) int main()
{
    static foreach (testFunction; __traits(getUnitTests, xtb.os.path))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.error))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.environment))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.file))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.pipe))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.pipeline))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.process))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.process_io))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.terminal))
        testFunction();
    version (linux)
        runLinuxIntegration();
    return 0;
}
