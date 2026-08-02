module tests.os_tests;

import xtb.os.directory;
import xtb.os.error;
import xtb.os.file;
import xtb.os.memory_map;
import xtb.os.path;
import xtb.os.pipe;
import xtb.os.time;
import xtb.core.array : Array;
import xtb.core.arena : Arena, TempArena, pop, push;
import xtb.core.memory : mallocAllocator;
import xtb.core.string : String, StringBuf, append, fromCString;
import xtb.core.thread_context : ThreadContextScope, scratchArena;
import xtb.core.types : i64, u64, u8;

version (linux) private bool countEntry(Path, FileType, void* context) nothrow @system @nogc
{
    ++*cast(size_t*) context;
    return true;
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
    version (linux)
        runLinuxIntegration();
    return 0;
}
