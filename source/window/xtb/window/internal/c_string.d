module xtb.window.internal.c_string;

nothrow @nogc:

import core.stdc.string : memcpy;
import xtb.memory : Allocator, deallocateArray, tryAllocateArray;
import xtb.types : String;
import xtb.window.error : WindowError, WindowErrorKind;

package(xtb.window) WindowError prepare_c_string(
    Allocator* allocator,
    scope String value,
    char[]* storage,
    const(char)** result,
) @system
{
    if (allocator is null || *allocator is null)
        return WindowError(WindowErrorKind.allocation_failed);

    foreach (ch; value)
    {
        if (ch == '\0')
            return WindowError(WindowErrorKind.title_contains_nul);
    }

    char[] buffer = allocator.tryAllocateArray!char(value.length + 1);
    if (buffer.ptr is null)
        return WindowError(WindowErrorKind.allocation_failed);
    if (value.length != 0)
        memcpy(buffer.ptr, value.ptr, value.length);
    buffer[value.length] = '\0';
    *storage = buffer;
    *result = buffer.ptr;
    return WindowError.init;
}

package(xtb.window) void release_c_string(Allocator* allocator, char[] storage) @system
{
    if (storage.ptr !is null)
        allocator.deallocateArray(storage);
}
