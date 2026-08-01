module fuzz.container_fuzz;

nothrow @nogc:

import xtb.core.array : Array, clear, removeAt, tryAppend, tryInsert;
import xtb.core.memory : mallocAllocator;
import xtb.core.string : StringBuf, clear, tryAppend, tryEscape, tryInsert,
    tryPrepend;

extern (C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) @system
{
    if (data is null)
        return 0;

    Array!ubyte values = Array!ubyte.create(mallocAllocator());
    StringBuf text = StringBuf.create(mallocAllocator());
    size_t cursor;
    while (cursor < size)
    {
        const operation = data[cursor++] % 8;
        final switch (operation)
        {
            case 0:
                values.tryAppend(data[cursor - 1]);
                break;
            case 1:
                if (values.length != 0)
                {
                    const index = data[cursor - 1] % values.length;
                    values.removeAt(index);
                }
                break;
            case 2:
                if (values.length != 0)
                {
                    const begin = data[cursor - 1] % values.length;
                    const count = values.length - begin;
                    const index = (data[cursor - 1] / 2) % (values.length + 1);
                    values.tryInsert(index, values.slice[begin .. begin + count]);
                }
                break;
            case 3:
                text.tryAppend(cast(char) data[cursor - 1]);
                break;
            case 4:
                if (text.length != 0)
                {
                    const begin = data[cursor - 1] % text.length;
                    text.tryPrepend(text.view[begin .. $]);
                }
                break;
            case 5:
                if (text.length != 0)
                {
                    const begin = data[cursor - 1] % text.length;
                    const index = (data[cursor - 1] / 2) % (text.length + 1);
                    text.tryInsert(index, text.view[begin .. $]);
                }
                break;
            case 6:
                if (text.length != 0)
                {
                    const begin = data[cursor - 1] % text.length;
                    text.tryEscape(text.view[begin .. $]);
                }
                break;
            case 7:
                values.clear();
                text.clear();
                break;
        }

        assert(values.length <= values.capacity);
        assert(text.length <= text.capacity);
        if (values.length > 4096)
            values.clear();
        if (text.length > 4096)
            text.clear();
    }
    return 0;
}
