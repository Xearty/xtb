module examples.os_demo;

import xtb.core;
import xtb.os;

extern (C) int main(int argumentCount, char** arguments) nothrow @nogc
{
    ThreadContextScope context = ThreadContextScope.acquire();
    const input = argumentCount > 1 ? fromCString(arguments[1]) : ".";
    const root = Path.fromString(input);

    StringBuf canonical = StringBuf.create(mallocAllocator());
    OsError error = canonicalPath(root, canonical);
    if (error.failed)
    {
        formatln!"cannot resolve path: error={} native={}"(cast(uint) error.kind, error.nativeCode);
        return 1;
    }
    writeln("directory: ", canonical.view);

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
