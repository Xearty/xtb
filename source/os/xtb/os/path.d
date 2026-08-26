module xtb.os.path;

nothrow @nogc:

import xtb.panic : panic;

version (XTB_Checked) import xtb.panic : require;
import xtb.string;

/// A borrowed native path without embedded NUL bytes.
struct Path
{
nothrow @nogc:

    private String value_;

    static Path fromString(String value)
    {
        Path result;
        if (!tryFromString(value, &result))
            panic("path contains an embedded NUL byte");
        return result;
    }

    static bool tryFromString(String value, Path* output) @system
    {
        version (XTB_Checked)
            require(output !is null, "Path output pointer is null");
        *output = Path.init;
        if (value.containsNul)
            return false;
        output.value_ = value;
        return true;
    }

    String view() const return scope pure @safe
    {
        return value_;
    }

    bool empty() const pure @safe
    {
        return value_.length == 0;
    }

    bool absolute() const pure @safe
    {
        return value_.length != 0 && value_[0] == '/';
    }

    Path fileName() const pure @safe
    {
        size_t end = value_.length;
        while (end > 1 && value_[end - 1] == '/')
            --end;
        size_t begin = end;
        while (begin != 0 && value_[begin - 1] != '/')
            --begin;
        return Path(value_[begin .. end]);
    }

    Path parent() const pure @safe
    {
        size_t end = value_.length;
        while (end > 1 && value_[end - 1] == '/')
            --end;
        while (end != 0 && value_[end - 1] != '/')
            --end;
        while (end > 1 && value_[end - 1] == '/')
            --end;
        return Path(value_[0 .. end]);
    }
}

bool tryAppendComponent(ref StringBuf output, Path component)
{
    String value = component.view;
    size_t begin;
    while (begin < value.length && value[begin] == '/')
        ++begin;
    size_t end = value.length;
    while (end > begin && value[end - 1] == '/')
        --end;
    if (begin == end)
        return true;

    const current = output.view;
    const separator = current.length != 0 && current[$ - 1] != '/';
    const componentLength = end - begin;
    if (componentLength > size_t.max - output.byteLength - separator)
        return false;

    bool aliasesOutput;
    size_t sourceOffset;
    if (value.length != 0 && current.length != 0)
    {
        const sourceAddress = cast(size_t) value.ptr;
        const beginAddress = cast(size_t) current.ptr;
        const byteOffset = sourceAddress - beginAddress;
        aliasesOutput = sourceAddress >= beginAddress && byteOffset < current.length;
        if (aliasesOutput)
        {
            if (value.length > current.length - byteOffset)
                return false;
            sourceOffset = byteOffset;
        }
    }

    if (!output.tryReserve(output.byteLength + separator + componentLength))
        return false;
    if (aliasesOutput)
        value = output.view[sourceOffset .. sourceOffset + value.length];
    if (separator)
        output.appendAssumeCapacity('/');
    output.appendAssumeCapacity(value[begin .. end]);
    return true;
}

void appendComponent(ref StringBuf output, Path component)
{
    if (!output.tryAppendComponent(component))
        panic("path allocation failed");
}

unittest
{
    import xtb.allocators.malloc : mallocAllocator;

    Path path = Path.fromString("var");
    assert(path.view == "var" && !path.absolute);
    assert(Path.fromString("/tmp/file.txt/").fileName.view == "file.txt");
    assert(Path.fromString("/tmp/file.txt/").parent.view == "/tmp");
    StringBuf joined = StringBuf.fromString(mallocAllocator(), "/tmp/");
    joined.appendComponent(Path.fromString("/xtb/"));
    joined.appendComponent(Path.fromString("file"));
    assert(joined.view == "/tmp/xtb/file");

    StringBuf selfJoined = StringBuf.fromString(mallocAllocator(), "root/abc");
    selfJoined.appendComponent(Path.fromString(selfJoined.view[5 .. $]));
    assert(selfJoined.view == "root/abc/abc");

    Path rejected;
    assert(!Path.tryFromString("bad\0path", &rejected));

    selfJoined.deinit();
    joined.deinit();
}
