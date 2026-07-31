module tests.os_tests;

import xtb.os.directory;
import xtb.os.error;
import xtb.os.file;
import xtb.os.memory_map;
import xtb.os.path;
import xtb.os.time;
import xtb.core.array : Array;
import xtb.core.memory : mallocAllocator;
import xtb.core.print : formatTo;
import xtb.core.string : String, StringBuf, append;
import xtb.core.thread_context : ThreadContextScope;
import xtb.core.types : u64, u8;

version (linux) private void runLinuxIntegration() nothrow @system @nogc
{
    import core.sys.posix.unistd : getpid;
    import xtb.os.environment : environmentVariable;

    ThreadContextScope context = ThreadContextScope.acquire();
    StringBuf root = StringBuf.create(mallocAllocator());
    root.formatTo!"/tmp/xtbd-os-{}"(getpid());
    const rootPath = Path.fromString(root.view);
    OsError error = createDirectory(rootPath);
    assert(error.succeeded);

    StringBuf first = StringBuf.fromString(mallocAllocator(), root.view);
    first.append("/first.bin");
    const firstPath = Path.fromString(first.view);
    const u8[6] contents = [0, 1, 2, 3, 0, 255];
    assert(writeEntireFile(firstPath, contents[]).succeeded);

    FileMetadata information;
    assert(metadata(firstPath, true, &information).succeeded);
    assert(information.type == FileType.regular && information.size == contents.length);

    Array!u8 loaded = Array!u8.create(mallocAllocator());
    assert(readEntireFile(firstPath, loaded).succeeded);
    assert(loaded.slice == contents[]);

    MappedFile mapping;
    assert(mapReadOnly(firstPath, &mapping).succeeded);
    assert(mapping.bytes == contents[]);
    mapping.deinit();

    StringBuf second = StringBuf.fromString(mallocAllocator(), root.view);
    second.append("/second.bin");
    const secondPath = Path.fromString(second.view);
    assert(copyFile(firstPath, secondPath, loaded, true).succeeded);

    StringBuf renamed = StringBuf.fromString(mallocAllocator(), root.view);
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
    iterator.deinit();

    StringBuf cwd = StringBuf.create(mallocAllocator());
    assert(currentDirectory(cwd).succeeded && cwd.view.length != 0);
    StringBuf executable = StringBuf.create(mallocAllocator());
    assert(executablePath(executable).succeeded && executable.view.length != 0);
    String environmentPath;
    assert(environmentVariable("PATH", &environmentPath).succeeded);
    assert(environmentPath.length != 0);
    u64 before;
    u64 after;
    assert(monotonicNanoseconds(&before).succeeded);
    assert(sleepNanoseconds(1_000_000).succeeded);
    assert(monotonicNanoseconds(&after).succeeded && after >= before);
    assert(wallClockNanoseconds(&after).succeeded && after != 0);

    assert(removeFile(firstPath).succeeded);
    assert(removeFile(renamedPath).succeeded);
    assert(removeEmptyDirectory(rootPath).succeeded);
}

extern (C) int main()
{
    static foreach (testFunction; __traits(getUnitTests, xtb.os.path))
        testFunction();
    version (linux)
        runLinuxIntegration();
    return 0;
}
