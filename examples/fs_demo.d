module examples.fs_demo;

import xtb;
import xtb.fs;
import xtb.os.error : OsError;

extern (C) int main(int argumentCount, char** arguments) nothrow @nogc
{
    ThreadContextScope context = ThreadContextScope.acquire();
    String input = ".";
    if (argumentCount > 1)
    {
        const checked = fromCString(arguments[1]);
        if (checked.failed)
        {
            formatln!"path is not valid UTF-8 at byte {}"(
                checked.error.byteOffset,
            );
            return 1;
        }
        input = checked.value;
    }
    const root = Path.fromString(input);

    StringBuf canonical = StringBuf.create(mallocAllocator());
    scope (exit)
        canonical.deinit();
    OsError error = canonicalPath(root, canonical);
    if (error.failed)
    {
        formatln!"cannot resolve path: error={} native={}"(cast(uint) error.kind, error.nativeCode);
        return 1;
    }
    writeln("directory: ", canonical);

    DirectoryIterator iterator;
    error = openDirectory(root, &iterator);
    if (error.failed)
    {
        formatln!"cannot open directory: error={} native={}"(cast(uint) error.kind,
            error.nativeCode);
        return 1;
    }

    DirectoryEntry entry;
    for (;;)
    {
        const result = (&iterator).next(&entry);
        if (result.status == DirectoryStatus.finished)
            break;
        if (result.status == DirectoryStatus.failed)
        {
            formatln!"iteration failed: error={} native={}"(cast(uint) result.error.kind,
                result.error.nativeCode);
            return 1;
        }
        formatln!"type={} name={}"(cast(uint) entry.type, entry.name);
    }
    return 0;
}
