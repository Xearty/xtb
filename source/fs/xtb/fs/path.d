module xtb.fs.path;

nothrow @nogc:

import xtb.panic;
import xtb.string;
import xtb.types;

/// A borrowed native path.
///
/// `value` must not contain embedded NUL bytes.
struct Path
{
nothrow @nogc:

    /// Borrowed path bytes. Their storage must remain valid while this path is used.
    String value;

    static Path from_string(return scope String value) @trusted
    {
        // `return scope` preserves the lifetime of the borrowed value stored in result.
        Path result;
        if (!Path.try_from_string(value, &result)) panic("path contains an embedded NUL byte");
        return result;
    }

    /// Validates `value` and writes a borrowed path to `output`.
    ///
    /// `output` must not be null. The storage backing `value` must remain valid while
    /// `output.value` is used. On failure, `output` is left as `Path.init`.
    static bool try_from_string(String value, Path* output) @system
    {
        require(output !is null, "Path output pointer is null");
        *output = Path.init;
        if (value.contains_nul) return false;
        output.value = value;
        return true;
    }

    String view() const return scope pure @safe
    {
        return this.value;
    }

    bool empty() const pure @safe
    {
        return this.value.length == 0;
    }

    bool absolute() const pure @safe
    {
        return this.value.length != 0 && this.value[0] == '/';
    }

    Path file_name() const return scope pure @safe
    {
        usize end = this.value.length;
        while (end > 1 && this.value[end - 1] == '/')
            --end;
        usize begin = end;
        while (begin != 0 && this.value[begin - 1] != '/')
            --begin;
        return Path(this.value[begin .. end]);
    }

    Path parent() const return scope pure @safe
    {
        usize end = this.value.length;
        while (end > 1 && this.value[end - 1] == '/')
            --end;
        while (end != 0 && this.value[end - 1] != '/')
            --end;
        while (end > 1 && this.value[end - 1] == '/')
            --end;
        return Path(this.value[0 .. end]);
    }
}

bool try_append_component(ref StringBuf output, scope const Path component) @trusted
{
    String value = component.view;
    usize begin;
    while (begin < value.length && value[begin] == '/')
        ++begin;
    usize end = value.length;
    while (end > begin && value[end - 1] == '/')
        --end;
    if (begin == end) return true;

    const String current = output.view;
    const bool separator = current.length != 0 && current[$ - 1] != '/';
    const usize component_length = end - begin;
    if (component_length > usize.max - output.byte_length - separator) return false;

    bool aliases_output;
    usize source_offset;
    if (value.length != 0 && current.length != 0)
    {
        // Address comparison only detects whether reserve may invalidate `value`;
        // every subsequent slice remains bounds-checked.
        const usize source_address = cast(usize) value.ptr;
        const usize begin_address = cast(usize) current.ptr;
        const usize byte_offset = source_address - begin_address;
        aliases_output = source_address >= begin_address && byte_offset < current.length;
        if (aliases_output)
        {
            if (value.length > current.length - byte_offset) return false;
            source_offset = byte_offset;
        }
    }

    if (!output.try_reserve(output.byte_length + separator + component_length)) return false;
    if (aliases_output) value = output.view[source_offset .. source_offset + value.length];
    if (separator) output.append_assume_capacity('/');
    output.append_assume_capacity(value[begin .. end]);
    return true;
}

void append_component(ref StringBuf output, scope const Path component) @safe
{
    if (!try_append_component(output, component)) panic("path allocation failed");
}

unittest
{
    import xtb.allocators.malloc;

    Path path = Path.from_string("var");
    assert(path.view == "var" && !path.absolute);
    assert(Path.from_string("/tmp/file.txt/").file_name.view == "file.txt");
    assert(Path.from_string("/tmp/file.txt/").parent.view == "/tmp");
    StringBuf joined = StringBuf.from_string(malloc_allocator(), "/tmp/");
    append_component(joined, Path.from_string("/xtb/"));
    append_component(joined, Path.from_string("file"));
    assert(joined.view == "/tmp/xtb/file");

    StringBuf self_joined = StringBuf.from_string(malloc_allocator(), "root/abc");
    append_component(self_joined, Path.from_string(self_joined.view[5 .. $]));
    assert(self_joined.view == "root/abc/abc");

    Path rejected;
    assert(!Path.try_from_string("bad\0path", &rejected));

    self_joined.deinit();
    joined.deinit();
}
