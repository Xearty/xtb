module xtb.window.internal.c_string;

nothrow @nogc:

import core.stdc.string : memcpy;
import xtb.memory : Allocator, deallocateArray, tryAllocateArray;
import xtb.types : String;
import xtb.window.error : WindowError, WindowErrorKind;

version (XTB_Checked) import xtb.panic : require;

package(xtb.window) WindowError prepare_c_string(
    Allocator* allocator,
    scope String value,
    char[]* storage,
    const(char)** result,
) @system
{
    version (XTB_Checked)
    {
        require(allocator !is null && *allocator !is null, "C-string allocator is null");
        foreach (ch; value)
            require(ch != '\0', "C-string input contains an embedded NUL byte");
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
