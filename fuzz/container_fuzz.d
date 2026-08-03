module fuzz.container_fuzz;

nothrow @nogc:

import xtb.core.array : Array, clear, removeAt, tryAppend, tryInsert;
import xtb.core.hash_map : HashMap, HashSet, remove, set, tryAdd;
import xtb.core.memory : mallocAllocator;
import xtb.core.string : StringBuf, clear, tryAppend, tryEscape, tryInsert,
    tryPrepend;
import xtb.core.utf8 : floorCodePointBoundary;

extern (C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) @system
{
    if (data is null)
        return 0;

    Array!ubyte values = Array!ubyte.create(mallocAllocator());
    StringBuf text = StringBuf.create(mallocAllocator());
    HashMap!(ubyte, ubyte) map = HashMap!(ubyte, ubyte).create(
        mallocAllocator(),
    );
    HashSet!ubyte setValues = HashSet!ubyte.create(mallocAllocator());
    size_t cursor;
    while (cursor < size)
    {
        const operation = data[cursor++] % 12;
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
                text.tryAppend(cast(dchar) data[cursor - 1]);
                break;
            case 4:
                if (text.byteLength != 0)
                {
                    const candidate = data[cursor - 1] % text.byteLength;
                    const begin = text.view.floorCodePointBoundary(candidate);
                    text.tryPrepend(text.view[begin .. $]);
                }
                break;
            case 5:
                if (text.byteLength != 0)
                {
                    const beginCandidate = data[cursor - 1] % text.byteLength;
                    const begin = text.view.floorCodePointBoundary(beginCandidate);
                    const indexCandidate = (data[cursor - 1] / 2) %
                        (text.byteLength + 1);
                    const index = text.view.floorCodePointBoundary(indexCandidate);
                    text.tryInsert(index, text.view[begin .. $]);
                }
                break;
            case 6:
                if (text.byteLength != 0)
                {
                    const candidate = data[cursor - 1] % text.byteLength;
                    const begin = text.view.floorCodePointBoundary(candidate);
                    text.tryEscape(text.view[begin .. $]);
                }
                break;
            case 7:
                values.clear();
                text.clear();
                break;
            case 8:
                map.set(data[cursor - 1], cast(ubyte) cursor);
                break;
            case 9:
                map.remove(data[cursor - 1]);
                break;
            case 10:
                setValues.tryAdd(data[cursor - 1]);
                break;
            case 11:
                setValues.remove(data[cursor - 1]);
                break;
        }

        assert(values.length <= values.capacity);
        assert(text.byteLength <= text.byteCapacity);
        assert(map.length <= 256 && map.length <= map.capacity);
        assert(setValues.length <= 256 && setValues.length <= setValues.capacity);
        if (values.length > 4096)
            values.clear();
        if (text.byteLength > 4096)
            text.clear();
    }
    return 0;
}
