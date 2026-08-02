module tests.os_tests;

import xtb.os.directory;
import xtb.os.error;
import xtb.os.file;
import xtb.os.memory_map;
import xtb.os.path;
import xtb.os.pipe;
import xtb.os.process;
import xtb.os.time;
import xtb.core.array : Array, append;
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
            Command.exact(Path.fromString("/definitely/missing/xtbd-helper")),
            SpawnOptions.init,
            &child,
        );
        assert(error.failed && error.operation == ProcessOperation.spawn);
        assert(error.os.kind == OsErrorKind.notFound && child.empty);
    }
}

version (linux) private void runLinuxIntegration() nothrow @system @nogc
{
    import core.sys.posix.stdlib : mkdtemp;
    import xtb.os.environment : environmentVariable;

    ThreadContextScope context = ThreadContextScope.acquire();
    enum rootPattern = "/tmp/xtbd-os-XXXXXX";
    char[rootPattern.length + 1] rootStorage;
    rootStorage[0 .. rootPattern.length] = rootPattern;
    rootStorage[$ - 1] = '\0';
    const createdRoot = mkdtemp(rootStorage.ptr);
    assert(createdRoot !is null);
    const rootPath = Path.fromString(fromCString(createdRoot));
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
    static foreach (testFunction; __traits(getUnitTests, xtb.os.file))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.pipe))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.os.process))
        testFunction();
    version (linux)
        runLinuxIntegration();
    return 0;
}
