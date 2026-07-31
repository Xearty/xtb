module xtb.os.path;

import xtb.core.panic : panic, require;
import xtb.core.string : String, StringBuf, containsNul, tryAppend;

/// A borrowed native path without embedded NUL bytes.
struct Path
{
    private String value_;

    static Path fromString(String value) nothrow @nogc
    {
        Path result;
        if (!tryFromString(value, &result))
            panic("path contains an embedded NUL byte");
        return result;
    }

    static bool tryFromString(String value, Path* output) nothrow @system @nogc
    {
        require(output !is null, "Path output pointer is null");
        if (value.containsNul)
            return false;
        output.value_ = value;
        return true;
    }

    String view() const return scope pure nothrow @safe @nogc
    {
        return value_;
    }

    bool empty() const pure nothrow @safe @nogc
    {
        return value_.length == 0;
    }

    bool absolute() const pure nothrow @safe @nogc
    {
        return value_.length != 0 && value_[0] == '/';
    }

    Path fileName() const pure nothrow @safe @nogc
    {
        size_t end = value_.length;
        while (end > 1 && value_[end - 1] == '/')
            --end;
        size_t begin = end;
        while (begin != 0 && value_[begin - 1] != '/')
            --begin;
        return Path(value_[begin .. end]);
    }

    Path parent() const pure nothrow @safe @nogc
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

bool tryAppendComponent(ref StringBuf output, Path component) nothrow @nogc
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
    if (current.length != 0 && current[$ - 1] != '/' && !output.tryAppend('/'))
        return false;
    return output.tryAppend(value[begin .. end]);
}

void appendComponent(ref StringBuf output, Path component) nothrow @nogc
{
    if (!output.tryAppendComponent(component))
        panic("path allocation failed");
}

nothrow @nogc unittest
{
    import xtb.core.memory : mallocAllocator;

    Path path = Path.fromString("var");
    assert(path.view == "var" && !path.absolute);
    assert(Path.fromString("/tmp/file.txt/").fileName.view == "file.txt");
    assert(Path.fromString("/tmp/file.txt/").parent.view == "/tmp");
    StringBuf joined = StringBuf.fromString(mallocAllocator(), "/tmp/");
    joined.appendComponent(Path.fromString("/xtbd/"));
    joined.appendComponent(Path.fromString("file"));
    assert(joined.view == "/tmp/xtbd/file");
    Path rejected;
    assert(!Path.tryFromString("bad\0path", &rejected));
}
