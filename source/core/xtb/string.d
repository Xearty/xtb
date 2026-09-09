module xtb.string;

nothrow @nogc:

import core.attribute;
import core.interpolation;
import core.stdc.string;

import xtb.allocators.arena;
import xtb.containers.array;
import xtb.containers.released_storage;
import xtb.fmt.writer;
import xtb.hash;
import xtb.lifetime;
import xtb.memory;
import xtb.panic;
import xtb.types;
import xtb.utf8;

enum not_found = usize.max;

alias SplitPredicate = usize function(String rest, void* context) nothrow @nogc;

private template UnqualifiedStringInput(T)
{
    alias UnqualifiedStringInput = typeof(cast() T.init);
}

private enum is_owned_string_input(T) =
    is(UnqualifiedStringInput!T == OwnedString);

private enum is_string_buf_input(T) = is(T : String) || is_owned_string_input!T;

private enum is_string_buf_argument(alias value) =
    is_string_buf_input!(typeof(value)) &&
    (!is_owned_string_input!(typeof(value)) || __traits(isRef, value));

private String string_buf_input(T)(return scope auto ref T value)
pure @trusted
if (is_string_buf_input!T)
{
    static if (is_owned_string_input!T)
    {
        static assert(__traits(isRef, value),
            "temporary OwnedString input would lose its cleanup obligation");
        return value.view;
    }
    else
        return value;
}

/// Borrows bytes already proven to be valid UTF-8.
String as_string_unchecked(return scope const(u8)[] bytes)
pure @system
{
    return cast(String) bytes;
}

Utf8StringResult from_c_string(const(char)* value) @system
{
    require(value !is null, "null C string");
    const candidate = value[0 .. strlen(value)];
    const error = validate_utf8(candidate);
    return error.failed
        ? Utf8StringResult(String.init, error) : Utf8StringResult(candidate, Utf8Error.init);
}

String from_c_string_unchecked(const(char)* value) @system
{
    require(value !is null, "null C string");
    return value[0 .. strlen(value)];
}

usize byte_length(String value) pure @safe
{
    return value.length;
}

const(u8)[] bytes(return scope String value) pure @trusted
{
    return cast(const(u8)[]) value;
}

bool empty(String value) pure @safe
{
    return value.length == 0;
}

char front_code_unit(String value) @safe
{
    require(value.length != 0, "front_code_unit of empty String");
    return value[0];
}

char back_code_unit(String value) @safe
{
    require(value.length != 0, "back_code_unit of empty String");
    return value[value.length - 1];
}

bool equal(String left, String right) pure @trusted
{
    if (left.length != right.length)
        return false;
    return left.length == 0 || memcmp(left.ptr, right.ptr, left.length) == 0;
}

i32 compare(String left, String right) pure @trusted
{
    const common = left.length < right.length ? left.length : right.length;
    if (common != 0)
    {
        const comparison = memcmp(left.ptr, right.ptr, common);
        if (comparison < 0)
            return -1;
        if (comparison > 0)
            return 1;
    }
    return left.length < right.length ? -1 : left.length > right.length ? 1 : 0;
}

String slice_bytes(
    return scope String value,
    usize begin_byte_offset,
    usize end_byte_offset,
)
@safe
{
    require(begin_byte_offset <= end_byte_offset,
        "String byte slice begin exceeds end");
    require(end_byte_offset <= value.length,
        "String byte slice end out of bounds");
    require(value.is_code_point_boundary(begin_byte_offset),
        "String byte slice begins inside UTF-8 code point");
    require(value.is_code_point_boundary(end_byte_offset),
        "String byte slice ends inside UTF-8 code point");
    return value[begin_byte_offset .. end_byte_offset];
}

String prefix_bytes(return scope String value, usize end_byte_offset)
@safe
{
    return value.slice_bytes(0, end_byte_offset);
}

String suffix_bytes(return scope String value, usize begin_byte_offset)
@safe
{
    return value.slice_bytes(begin_byte_offset, value.length);
}

usize find(String value, String needle) pure @trusted
{
    if (needle.length == 0)
        return 0;
    if (needle.length > value.length)
        return not_found;

    foreach (i; 0 .. value.length - needle.length + 1)
    {

        if (memcmp(value.ptr + i, needle.ptr, needle.length) == 0)
            return i;
    }
    return not_found;
}

usize find_code_unit(String value, char code_unit) pure @safe
{
    foreach (byte_offset, candidate; value)
    {
        if (candidate == code_unit)
            return byte_offset;
    }
    return not_found;
}

usize find_last(String value, String needle) pure @trusted
{
    if (needle.length == 0)
        return value.length;
    if (needle.length > value.length)
        return not_found;

    usize index = value.length - needle.length + 1;
    while (index != 0)
    {
        --index;

        if (memcmp(value.ptr + index, needle.ptr, needle.length) == 0)
            return index;
    }
    return not_found;
}

usize find_last_code_unit(String value, char code_unit) pure @safe
{
    usize byte_offset = value.length;
    while (byte_offset != 0)
    {
        --byte_offset;
        if (value[byte_offset] == code_unit)
            return byte_offset;
    }
    return not_found;
}

usize find_code_point(String value, dchar code_point) @safe
{
    const encoded = encode_utf8(code_point);
    const code_units = encoded.bytes;
    return value.find(code_units[0 .. encoded.byte_length]);
}

usize find_last_code_point(String value, dchar code_point) @safe
{
    const encoded = encode_utf8(code_point);
    const code_units = encoded.bytes;
    return value.find_last(code_units[0 .. encoded.byte_length]);
}

String base_name(String value) pure @safe
{
    const slash = value.find_last_code_unit('/');
    const backslash = value.find_last_code_unit('\\');
    usize separator = slash;
    if (separator == not_found ||
        (backslash != not_found && backslash > separator))
        separator = backslash;
    return separator == not_found ? value : value[separator + 1 .. $];
}

String strip_extension(String value) pure @safe
{
    const extension = value.find_last_code_unit('.');
    const base_offset = value.length - value.base_name.length;
    return extension == not_found || extension <= base_offset
        ? value : value[0 .. extension];
}

bool contains(String value, String needle) pure @safe
{
    return value.find(needle) != not_found;
}

bool contains_code_unit(String value, char code_unit) pure @safe
{
    return value.find_code_unit(code_unit) != not_found;
}

bool contains_code_point(String value, dchar code_point) @safe
{
    return value.find_code_point(code_point) != not_found;
}

bool contains_nul(String value) pure @safe
{
    return value.contains_code_unit('\0');
}

bool starts_with(String value, String prefix) pure @trusted
{
    return prefix.length <= value.length && value[0 .. prefix.length].equal(prefix);
}

bool ends_with(String value, String suffix) pure @trusted
{
    return suffix.length <= value.length &&
        value[value.length - suffix.length .. $].equal(suffix);
}

private bool is_ascii_whitespace(char value) pure @safe
{
    return value == ' ' || value == '\t' || value == '\n' ||
        value == '\r' || value == '\f' || value == '\v';
}

String trim_ascii_start(return scope String value) pure @safe
{
    usize begin;
    while (begin < value.length && is_ascii_whitespace(value[begin]))
        ++begin;
    return value[begin .. $];
}

String trim_ascii_end(return scope String value) pure @safe
{
    usize end = value.length;
    while (end != 0 && is_ascii_whitespace(value[end - 1]))
        --end;
    return value[0 .. end];
}

String trim_ascii(return scope String value) pure @safe
{
    return value.trim_ascii_start().trim_ascii_end();
}

private char escaped_character(char value) pure @safe
{
    switch (value)
    {
        case '\a':
            return 'a';
        case '\b':
            return 'b';
        case '\x1b':
            return 'e';
        case '\f':
            return 'f';
        case '\n':
            return 'n';
        case '\r':
            return 'r';
        case '\t':
            return 't';
        case '\v':
            return 'v';
        case '\\':
            return '\\';
        case '\'':
            return '\'';
        case '"':
            return '"';
        case '?':
            return '?';
        default:
            return '\0';
    }
}

bool try_split_when(
    String value,
    SplitPredicate predicate,
    void* context,
    bool discard_empty,
    Allocator* allocator,
    Array!String* output,
)
{
    require(predicate !is null, "split predicate is null");
    require(output !is null, "split output is null");
    Array!String created = Array!String.create(allocator);
    move_emplace(created, *output);

    usize token_begin;
    usize index;
    while (index < value.length)
    {
        const skip = predicate(value[index .. $], context);
        require(skip <= value.length - index, "split predicate skipped past input");
        if (skip == 0)
        {
            index = value.ceil_code_point_boundary(index + 1);
            continue;
        }
        require(value.is_code_point_boundary(index + skip),
            "split predicate ended inside UTF-8 code point");

        String token = value[token_begin .. index];

        if ((!discard_empty || token.length != 0) &&
            !output.try_append(&token))
        {
            output.deinit();
            return false;
        }
        index += skip;
        token_begin = index;
    }

    String token = value[token_begin .. $];

    if ((!discard_empty || token.length != 0) &&
        !output.try_append(&token))
    {
        output.deinit();
        return false;
    }
    return true;
}

Array!String split_when(
    String value,
    SplitPredicate predicate,
    void* context,
    bool discard_empty,
    Allocator* allocator,
)
{
    Array!String result;
    if (!value.try_split_when(predicate, context, discard_empty, allocator, &result))
        panic("String split allocation failed");
    return result;
}

private usize string_separator(String rest, void* context)
{
    String separator = *cast(String*) context;
    return rest.starts_with(separator) ? separator.length : 0;
}

private usize character_separator(String rest, void* context)
{
    return rest.length != 0 && rest[0] == *cast(char*) context ? 1 : 0;
}

private bool is_ascii_whitespace_public(char value) pure @safe
{
    return is_ascii_whitespace(value);
}

private usize whitespace_separator(String rest, void*)
{
    usize count;
    while (count < rest.length && is_ascii_whitespace_public(rest[count]))
        ++count;
    return count;
}

Array!String split(String value, String separator, Allocator* allocator)
{
    require(separator.length != 0, "String separator must not be empty");
    return value.split_when(&string_separator, &separator, false, allocator);
}

Array!String split(String value, char separator, Allocator* allocator)
{
    require(cast(u8) separator <= 0x7f,
        "non-ASCII split separator; use String");
    return value.split_when(&character_separator, &separator, false, allocator);
}

Array!String split_whitespace(String value, Allocator* allocator)
{
    return value.split_when(&whitespace_separator, null, true, allocator);
}

Array!String split_lines(String value, Allocator* allocator)
{
    return value.split('\n', allocator);
}

private bool strings_overlap(scope String left, scope String right) pure @trusted
{
    if (left.length == 0 || right.length == 0)
        return false;

    const left_begin = cast(usize) left.ptr;
    const left_end = left_begin + left.length;
    const right_begin = cast(usize) right.ptr;
    const right_end = right_begin + right.length;
    return left_begin < right_end && right_begin < left_end;
}

/// Growable UTF-8 backing storage without embedded allocator context.
///
/// The value owns its allocation but every allocating or releasing operation
/// requires the originating allocator explicitly. Copying and generated
/// assignment are disabled.
@mustuse struct StringBufUnmanaged
{
nothrow @nogc:

    ArrayUnmanaged!char bytes;

    @disable this(this);
    @disable ref StringBufUnmanaged opAssign(StringBufUnmanaged source) return;

    static bool try_with_capacity(
        Allocator* allocator,
        usize byte_capacity,
        scope StringBufUnmanaged* output,
    )
    {
        require(output !is null,
            "StringBufUnmanaged output pointer is null");
        require(output.bytes.capacity == 0,
            "StringBufUnmanaged output is not empty");
        StringBufUnmanaged temporary;
        if (!temporary.bytes.try_reserve(allocator, byte_capacity))
            return false;
        move_emplace(temporary, *output);
        return true;
    }

    static StringBufUnmanaged with_capacity(
        Allocator* allocator,
        usize byte_capacity,
    )
    {
        StringBufUnmanaged result;
        if (!StringBufUnmanaged.try_with_capacity(allocator, byte_capacity, &result))
            panic("StringBuf allocation failed");
        return result;
    }

    static bool try_from_string(Value)(
        Allocator* allocator,
        scope auto ref Value value,
        scope StringBufUnmanaged* output,
    )
    if (is_string_buf_argument!value)
    {
        require(output !is null,
            "StringBufUnmanaged output pointer is null");
        require(output.bytes.capacity == 0,
            "StringBufUnmanaged output is not empty");
        StringBufUnmanaged temporary;
        if (!temporary.try_append(allocator, value))
            return false;
        move_emplace(temporary, *output);
        return true;
    }

    static StringBufUnmanaged from_string(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    )
    if (is_string_buf_argument!value)
    {
        StringBufUnmanaged result;
        if (!StringBufUnmanaged.try_from_string(allocator, value, &result))
            panic("StringBuf allocation failed");
        return result;
    }

    /// Copies bytes whose UTF-8 validity the caller has already proved.
    static StringBufUnmanaged from_bytes_unchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    ) @system
    {
        StringBufUnmanaged result;
        if (!StringBufUnmanaged.try_from_bytes_unchecked(allocator, bytes, &result))
            panic("StringBuf allocation failed");
        return result;
    }

    /// Fallible counterpart to `from_bytes_unchecked`.
    static bool try_from_bytes_unchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        scope StringBufUnmanaged* output,
    ) @system
    {
        require(output !is null,
            "StringBufUnmanaged output pointer is null");
        require(output.bytes.capacity == 0,
            "StringBufUnmanaged output is not empty");
        StringBufUnmanaged temporary;
        if (!temporary.bytes.try_append(
                allocator,
                bytes.as_string_unchecked,
            ))
            return false;
        move_emplace(temporary, *output);
        return true;
    }

    private static StringBufUnmanaged adopt(
        char* data,
        usize length,
        usize capacity,
    ) @system
    {
        StringBufUnmanaged result;
        auto bytes = ArrayUnmanaged!char.adopt(data, length, capacity);
        move_emplace(bytes, result.bytes);
        return result;
    }

    /// Detaches storage whose allocation size is exactly the logical length.
    /// The returned token owns the allocation but carries no allocator.
    package(xtb) RawArrayStorage!char release_exact_storage() @system
    {
        require(this.byte_capacity == this.byte_length,
            "StringBuf storage is not exact-sized");
        return this.bytes.release_raw();
    }

    void deinit(Allocator* allocator)
    {
        this.bytes.deinit(allocator);
    }

    void reset_and_release(Allocator* allocator)
    {
        this.bytes.reset_and_release(allocator);
    }

    usize byte_length() const pure @safe
    {
        return this.bytes.length;
    }

    usize byte_capacity() const pure @safe
    {
        return this.bytes.capacity;
    }

    bool empty() const pure @safe
    {
        return this.bytes.empty;
    }

    String view() const return pure @trusted
    {
        return this.bytes.slice;
    }

    String format_representation() const return pure @trusted
    {
        return this.view;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.value(this.view);
    }

    bool opEquals(Other)(scope auto ref Other other) const pure @trusted
    if (is_string_buf_argument!other)
    {
        return this.view.equal(string_buf_input(other));
    }

    bool opEquals(scope ref const StringBufUnmanaged other) const pure @trusted
    {
        return this.view.equal(other.view);
    }

    usize toHash() const pure @trusted
    {
        return hash_value(this.view);
    }

    void reserve(Allocator* allocator, usize byte_capacity)
    {
        this.bytes.reserve(allocator, byte_capacity);
    }

    bool try_reserve(Allocator* allocator, usize byte_capacity)
    {
        return this.bytes.try_reserve(allocator, byte_capacity);
    }

    bool try_shrink_to_fit(Allocator* allocator)
    {
        return this.bytes.try_shrink_to_fit(allocator);
    }

    void shrink_to_fit(Allocator* allocator)
    {
        this.bytes.shrink_to_fit(allocator);
    }

    void append(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    )
    if (is_string_buf_argument!value)
    {
        this.bytes.append(allocator, string_buf_input(value));
    }

    bool try_append(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    )
    if (is_string_buf_argument!value)
    {
        return this.bytes.try_append(allocator, string_buf_input(value));
    }

    void append(Allocator* allocator, char value)
    {
        require(cast(u8) value <= 0x7f,
            "non-ASCII char appended to StringBuf; use dchar");
        this.bytes.append(allocator, value);
    }

    bool try_append(Allocator* allocator, char value)
    {
        require(cast(u8) value <= 0x7f,
            "non-ASCII char appended to StringBuf; use dchar");
        return this.bytes.try_append(allocator, &value);
    }

    void append(Allocator* allocator, dchar value)
    {
        if (!this.try_append(allocator, value))
            panic("StringBuf allocation failed");
    }

    bool try_append(Allocator* allocator, dchar value)
    {
        const encoded = encode_utf8(value);
        const code_units = encoded.bytes;
        return this.bytes.try_append(
            allocator,
            code_units[0 .. encoded.byte_length],
        );
    }

    void append_assume_capacity(Value)(scope auto ref Value value)
    if (is_string_buf_argument!value)
    {
        this.bytes.append_assume_capacity(string_buf_input(value));
    }

    void append_assume_capacity(char value)
    {
        require(cast(u8) value <= 0x7f,
            "non-ASCII char appended to StringBuf; use dchar");
        this.bytes.append_assume_capacity(value);
    }

    void append_assume_capacity(dchar value)
    {
        const encoded = encode_utf8(value);
        const code_units = encoded.bytes;
        this.bytes.append_assume_capacity(code_units[0 .. encoded.byte_length]);
    }

    bool try_insert(Value)(
        Allocator* allocator,
        usize byte_offset,
        scope auto ref Value value,
    )
    if (is_string_buf_argument!value)
    {
        require(byte_offset <= this.byte_length,
            "StringBuf insertion byte offset out of bounds");
        require(this.view.is_code_point_boundary(byte_offset),
            "StringBuf insertion byte offset is inside UTF-8 code point");
        return this.bytes.try_insert(
            allocator,
            byte_offset,
            string_buf_input(value),
        );
    }

    void insert(Value)(
        Allocator* allocator,
        usize byte_offset,
        scope auto ref Value value,
    )
    if (is_string_buf_argument!value)
    {
        if (!this.try_insert(allocator, byte_offset, value))
            panic("StringBuf allocation failed");
    }

    bool try_prepend(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    )
    if (is_string_buf_argument!value)
    {
        return this.try_insert(allocator, 0, value);
    }

    void prepend(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    )
    if (is_string_buf_argument!value)
    {
        this.insert(allocator, 0, value);
    }

    void truncate_bytes(usize new_byte_length)
    {
        require(new_byte_length <= this.byte_length,
            "StringBuf truncation byte length out of bounds");
        require(this.view.is_code_point_boundary(new_byte_length),
            "StringBuf truncation splits UTF-8 code point");
        this.bytes.remove_range(new_byte_length, this.byte_length - new_byte_length);
    }

    void clear()
    {
        this.bytes.clear();
    }

    bool try_append_escaped(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    )
    if (is_string_buf_argument!value)
    {
        String input = string_buf_input(value);
        bool aliases_buffer;
        usize source_offset;
        if (input.length != 0 && this.byte_length != 0)
        {
            const source_address = cast(usize) input.ptr;
            const begin_address = cast(usize) this.view.ptr;
            const byte_offset = source_address - begin_address;
            aliases_buffer = source_address >= begin_address &&
                byte_offset < this.byte_length;
            if (aliases_buffer)
            {
                if (input.length > this.byte_length - byte_offset)
                    return false;
                source_offset = byte_offset;
            }
        }

        usize escaped_count;
        foreach (character; input)

            if (escaped_character(character) != '\0')
                ++escaped_count;
        if (escaped_count > usize.max - input.length ||
            input.length + escaped_count > usize.max - this.byte_length)
            return false;
        const required = this.byte_length + input.length + escaped_count;
        if (!this.try_reserve(allocator, required))
            return false;
        if (aliases_buffer)
            input = this.view[source_offset .. source_offset + input.length];
        foreach (character; input)
        {
            const escaped = escaped_character(character);
            if (escaped != '\0')
            {
                this.append_assume_capacity('\\');
                this.append_assume_capacity(escaped);
            }
            else
                this.bytes.append_assume_capacity(character);
        }
        return true;
    }

    void append_escaped(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    )
    if (is_string_buf_argument!value)
    {
        if (!this.try_append_escaped(allocator, value))
            panic("StringBuf allocation failed");
    }

    /// Replaces every non-overlapping match in this buffer.
    ///
    /// Aliased `from` and `to` views are snapshotted before any mutation. On
    /// allocation failure the buffer remains unchanged.
    bool try_replace_in_place(From, To)(
        Allocator* allocator,
        scope auto ref From from_value,
        scope auto ref To to_value,
    )
    if (is_string_buf_argument!from_value &&
        is_string_buf_argument!to_value)
    {
        String from = string_buf_input(from_value);
        String to = string_buf_input(to_value);
        if (from.length == 0)
            return true;

        StringBufUnmanaged from_snapshot;
        scope (exit)
            from_snapshot.deinit(allocator);
        if (strings_overlap(this.view, from))
        {
            if (!StringBufUnmanaged.try_from_string(
                    allocator,
                    from,
                    &from_snapshot,
                ))
                return false;
            from = from_snapshot.view;
        }

        StringBufUnmanaged to_snapshot;
        scope (exit)
            to_snapshot.deinit(allocator);
        if (strings_overlap(this.view, to))
        {
            if (!StringBufUnmanaged.try_from_string(
                    allocator,
                    to,
                    &to_snapshot,
                ))
                return false;
            to = to_snapshot.view;
        }

        String original = this.view;
        usize count;
        usize position;
        while (position <= original.length)
        {
            const found = original[position .. $].find(from);
            if (found == not_found)
                break;
            ++count;
            position += found + from.length;
        }
        if (count == 0)
            return true;

        usize new_length = original.length;
        if (to.length >= from.length)
        {
            const growth = to.length - from.length;

            if (growth != 0 && count > (usize.max - new_length) / growth)
                return false;
            new_length += count * growth;
        }
        else
            new_length -= count * (from.length - to.length);
        if (!this.try_reserve(allocator, new_length))
            return false;

        const old_length = original.length;
        if (new_length <= old_length)
        {
            usize read_offset;
            usize write_offset;
            while (read_offset < old_length)
            {
                const found = this.view[read_offset .. old_length].find(from);
                if (found == not_found)
                {
                    const remaining = old_length - read_offset;
                    if (remaining != 0)
                        memmove(this.bytes.slice.ptr + write_offset,
                            this.bytes.slice.ptr + read_offset, remaining);
                    write_offset += remaining;
                    break;
                }
                if (found != 0)
                    memmove(this.bytes.slice.ptr + write_offset,
                        this.bytes.slice.ptr + read_offset, found);
                write_offset += found;
                if (to.length != 0)
                    memmove(this.bytes.slice.ptr + write_offset,
                        to.ptr, to.length);
                write_offset += to.length;
                read_offset += found + from.length;
            }
            this.bytes.remove_range(new_length, old_length - new_length);
            return true;
        }

        this.bytes.resize(allocator, new_length);
        usize read_end = old_length;
        usize write_end = new_length;
        while (read_end != 0)
        {
            const found = this.view[0 .. read_end].find_last(from);
            if (found == not_found)
            {
                if (read_end != 0)
                    memmove(this.bytes.slice.ptr + write_end - read_end,
                        this.bytes.slice.ptr, read_end);
                break;
            }
            const tail_begin = found + from.length;
            const tail_length = read_end - tail_begin;
            write_end -= tail_length;
            if (tail_length != 0)
                memmove(this.bytes.slice.ptr + write_end,
                    this.bytes.slice.ptr + tail_begin, tail_length);
            write_end -= to.length;
            if (to.length != 0)
                memmove(this.bytes.slice.ptr + write_end, to.ptr, to.length);
            read_end = found;
        }
        return true;
    }

    void replace_in_place(From, To)(
        Allocator* allocator,
        scope auto ref From from,
        scope auto ref To to,
    )
    if (is_string_buf_argument!from && is_string_buf_argument!to)
    {
        if (!this.try_replace_in_place(allocator, from, to))
            panic("StringBuf allocation failed");
    }

    /// Escapes this buffer in place.
    ///
    /// The operation reserves all required capacity before changing the
    /// logical contents, so allocation failure leaves the buffer unchanged.
    bool try_escape_in_place(Allocator* allocator)
    {
        const old_length = this.byte_length;
        usize escaped_count;
        foreach (character; this.view)

            if (escaped_character(character) != '\0')
                ++escaped_count;
        if (escaped_count == 0)
            return true;
        if (escaped_count > usize.max - old_length)
            return false;
        const new_length = old_length + escaped_count;
        if (!this.try_reserve(allocator, new_length))
            return false;

        this.bytes.resize(allocator, new_length);
        usize read_offset = old_length;
        usize write_offset = new_length;
        while (read_offset != 0)
        {
            const character = this.bytes[--read_offset];
            const escaped = escaped_character(character);
            if (escaped != '\0')
            {
                this.bytes[--write_offset] = escaped;
                this.bytes[--write_offset] = '\\';
            }
            else
                this.bytes[--write_offset] = character;
        }
        return true;
    }

    void escape_in_place(Allocator* allocator)
    {
        if (!this.try_escape_in_place(allocator))
            panic("StringBuf allocation failed");
    }

    /// Ensures a trailing NUL exists outside the logical string contents.
    ///
    /// The returned pointer remains valid only until this buffer is mutated or
    /// destroyed. Embedded NUL bytes are permitted; use `checked_c_string` when
    /// the target C API must receive the complete logical string.
    bool try_c_string(
        Allocator* allocator,
        scope const(char)** output,
    ) @system
    {
        require(output !is null, "C string output pointer is null");
        const old_length = this.byte_length;
        if (old_length == usize.max ||
            !this.bytes.try_resize(allocator, old_length + 1))
            return false;

        this.bytes[old_length] = '\0';
        const(char)* result = this.bytes.slice.ptr;
        this.bytes.remove_range(old_length, 1);
        *output = result;
        return true;
    }

    /// Panicking counterpart to `try_c_string`.
    const(char)* c_string(Allocator* allocator) return @system
    {
        const(char)* result;
        if (!this.try_c_string(allocator, &result))
            panic("StringBuf allocation failed");
        return result;
    }

    /// Returns a C string after rejecting embedded NUL bytes.
    const(char)* checked_c_string(Allocator* allocator) return @system
    {
        require(!this.view.contains_nul, "String contains embedded NUL");
        return this.c_string(allocator);
    }
}

@mustuse struct StringBuf
{
nothrow @nogc:

    alias Self = StringBuf;
    alias Storage = StringBufUnmanaged;
    alias Released = ReleasedStorage!Storage;

    Allocator* allocator;
    Storage storage;

    invariant
    {
        require(&this !is null, "StringBuf pointer is null");
    }

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(Allocator* allocator) @trusted
    {
        require_valid_string_buf_allocator(allocator);
        Self result;
        result.allocator = allocator;
        return result;
    }

    static bool try_with_capacity(
        Allocator* allocator,
        usize byte_capacity,
        scope Self* output,
    ) @trusted
    {
        require(output !is null, "StringBuf output pointer is null");
        require(output.allocator is null,
            "StringBuf output is already initialized");
        Storage storage;
        if (!Storage.try_with_capacity(allocator, byte_capacity, &storage))
            return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static Self with_capacity(
        Allocator* allocator,
        usize byte_capacity,
    ) @trusted
    {
        Self result;
        if (!Self.try_with_capacity(allocator, byte_capacity, &result))
            panic("StringBuf allocation failed");
        return move(result);
    }

    static bool try_from_string(Value)(
        Allocator* allocator,
        scope auto ref Value value,
        scope Self* output,
    ) @trusted
    if (is_string_buf_argument!value)
    {
        require(output !is null, "StringBuf output pointer is null");
        require(output.allocator is null,
            "StringBuf output is already initialized");
        Storage storage;
        if (!Storage.try_from_string(
                allocator,
                string_buf_input(value),
                &storage,
            ))
            return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static Self from_string(Value)(
        Allocator* allocator,
        scope auto ref Value value,
    ) @trusted
    if (is_string_buf_argument!value)
    {
        Self result;
        if (!Self.try_from_string(allocator, value, &result))
            panic("StringBuf allocation failed");
        return move(result);
    }

    static bool try_from_bytes_unchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        scope Self* output,
    ) @system
    {
        require(output !is null, "StringBuf output pointer is null");
        require(output.allocator is null,
            "StringBuf output is already initialized");
        Storage storage;
        if (!Storage.try_from_bytes_unchecked(allocator, bytes, &storage))
            return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static Self from_bytes_unchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    ) @system
    {
        Self result;
        if (!Self.try_from_bytes_unchecked(allocator, bytes, &result))
            panic("StringBuf allocation failed");
        return move(result);
    }

    static Self adopt(scope Released* released) @trusted
    {
        require(released !is null,
            "released StringBuf storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator = allocator;
        move_emplace(storage, result.storage);
        return move(result);
    }

    /// Releases all storage and unbinds the allocator. The zero state is valid.
    void deinit() @trusted
    {
        if (this.allocator is null)
            return;
        this.storage.deinit(this.allocator);
        this.allocator = null;
    }

    /// Releases allocated storage but keeps the allocator binding.
    void reset_and_release() @trusted
    {
        this.storage.reset_and_release(this.allocator);
    }

    /// Transfers allocator-bound storage out and leaves this buffer empty.
    Released release() @trusted
    {
        auto result = Released.from_owned_parts(this.allocator, &this.storage);
        this.allocator = null;
        return move(result);
    }

    usize byte_length() const pure @trusted
    {
        return this.storage.byte_length;
    }

    usize byte_capacity() const pure @trusted
    {
        return this.storage.byte_capacity;
    }

    bool empty() const pure @trusted
    {
        return this.storage.empty;
    }

    String view() const return pure @trusted
    {
        return this.storage.view;
    }

    String format_representation() const return pure @trusted
    {
        return this.view;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.value(this.view);
    }

    bool equal(Other)(scope auto ref Other other) const pure @trusted
    if (is_string_buf_argument!other)
    {
        return this.storage == string_buf_input(other);
    }

    bool equal(scope ref const Self other) const pure @trusted
    {
        return this.storage == other.storage;
    }

    void reserve(usize byte_capacity) @trusted
    {
        this.storage.reserve(this.allocator, byte_capacity);
    }

    bool try_reserve(usize byte_capacity) @trusted
    {
        return this.storage.try_reserve(this.allocator, byte_capacity);
    }

    bool try_shrink_to_fit() @trusted
    {
        return this.storage.try_shrink_to_fit(this.allocator);
    }

    void shrink_to_fit() @trusted
    {
        this.storage.shrink_to_fit(this.allocator);
    }

    void append(Value)(scope auto ref Value value) @trusted
    if (is_string_buf_argument!value)
    {
        this.storage.append(this.allocator, string_buf_input(value));
    }

    bool try_append(Value)(scope auto ref Value value) @trusted
    if (is_string_buf_argument!value)
    {
        return this.storage.try_append(this.allocator, string_buf_input(value));
    }

    void append(char value) @trusted
    {
        this.storage.append(this.allocator, value);
    }

    bool try_append(char value) @trusted
    {
        return this.storage.try_append(this.allocator, value);
    }

    void append(dchar value) @trusted
    {
        this.storage.append(this.allocator, value);
    }

    bool try_append(dchar value) @trusted
    {
        return this.storage.try_append(this.allocator, value);
    }

    /// Returns an immediate fallible `Writer` view over this buffer.
    ///
    /// The writer borrows this buffer and must not outlive it or be used after
    /// the buffer is moved or destroyed. Allocation failure becomes sticky
    /// writer failure; no explicit flush or finalization is required.
    Writer writer() return @trusted
    {
        return Writer.from_sink(&string_buf_writer_sink, &this);
    }

    /// Writes ordinary XTB printable values transactionally.
    ///
    /// On failure the visible contents are restored to their original length.
    /// Capacity growth and formatter side effects are not rolled back.
    bool try_write(Args...)(auto ref Args args) @trusted
    {
        const checkpoint = this.byte_length;
        Writer output = this.writer();
        output.write(args);
        if (output.ok)
            return true;
        this.truncate_bytes(checkpoint);
        return false;
    }

    /// Panicking counterpart to `try_write`.
    void write(Args...)(auto ref Args args) @trusted
    {
        if (!this.try_write(args))
            panic("StringBuf write failed");
    }

    /// Writes ordinary values followed by one newline transactionally.
    bool try_writeln(Args...)(auto ref Args args) @trusted
    {
        const checkpoint = this.byte_length;
        Writer output = this.writer();
        output.writeln(args);
        if (output.ok)
            return true;
        this.truncate_bytes(checkpoint);
        return false;
    }

    /// Panicking counterpart to `try_writeln`.
    void writeln(Args...)(auto ref Args args) @trusted
    {
        if (!this.try_writeln(args))
            panic("StringBuf write failed");
    }

    /// Applies compile-time `{}` formatting transactionally.
    bool try_format(string pattern, Args...)(auto ref Args args) @trusted
    {
        const checkpoint = this.byte_length;
        Writer output = this.writer();
        output.format!pattern(args);
        if (output.ok)
            return true;
        this.truncate_bytes(checkpoint);
        return false;
    }

    /// Panicking counterpart to `try_format`.
    void format(string pattern, Args...)(auto ref Args args) @trusted
    {
        if (!this.try_format!pattern(args))
            panic("StringBuf formatting failed");
    }

    /// Applies compile-time `{}` formatting and appends one newline transactionally.
    bool try_formatln(string pattern, Args...)(auto ref Args args) @trusted
    {
        const checkpoint = this.byte_length;
        Writer output = this.writer();
        output.formatln!pattern(args);
        if (output.ok)
            return true;
        this.truncate_bytes(checkpoint);
        return false;
    }

    /// Panicking counterpart to `try_formatln`.
    void formatln(string pattern, Args...)(auto ref Args args) @trusted
    {
        if (!this.try_formatln!pattern(args))
            panic("StringBuf formatting failed");
    }

    /// Writes a D interpolated string transactionally.
    bool try_format(Sequence...)(
        InterpolationHeader header,
        auto ref Sequence sequence,
        InterpolationFooter footer,
    ) @trusted
    {
        const checkpoint = this.byte_length;
        Writer output = this.writer();
        output.format(header, sequence, footer);
        if (output.ok)
            return true;
        this.truncate_bytes(checkpoint);
        return false;
    }

    /// Panicking counterpart for interpolated-string formatting.
    void format(Sequence...)(
        InterpolationHeader header,
        auto ref Sequence sequence,
        InterpolationFooter footer,
    ) @trusted
    {
        if (!this.try_format(header, sequence, footer))
            panic("StringBuf formatting failed");
    }

    /// Writes a D interpolated string followed by one newline transactionally.
    bool try_formatln(Sequence...)(
        InterpolationHeader header,
        auto ref Sequence sequence,
        InterpolationFooter footer,
    ) @trusted
    {
        const checkpoint = this.byte_length;
        Writer output = this.writer();
        output.formatln(header, sequence, footer);
        if (output.ok)
            return true;
        this.truncate_bytes(checkpoint);
        return false;
    }

    /// Panicking counterpart for interpolated-string formatting with a newline.
    void formatln(Sequence...)(
        InterpolationHeader header,
        auto ref Sequence sequence,
        InterpolationFooter footer,
    ) @trusted
    {
        if (!this.try_formatln(header, sequence, footer))
            panic("StringBuf formatting failed");
    }

    void append_assume_capacity(Value)(scope auto ref Value value) @trusted
    if (is_string_buf_argument!value)
    {
        this.storage.append_assume_capacity(string_buf_input(value));
    }

    void append_assume_capacity(char value) @trusted
    {
        this.storage.append_assume_capacity(value);
    }

    void append_assume_capacity(dchar value) @trusted
    {
        this.storage.append_assume_capacity(value);
    }

    bool try_insert(Value)(
        usize byte_offset,
        scope auto ref Value value,
    ) @trusted
    if (is_string_buf_argument!value)
    {
        return this.storage.try_insert(
            this.allocator,
            byte_offset,
            string_buf_input(value),
        );
    }

    void insert(Value)(
        usize byte_offset,
        scope auto ref Value value,
    ) @trusted
    if (is_string_buf_argument!value)
    {
        this.storage.insert(this.allocator, byte_offset, string_buf_input(value));
    }

    bool try_prepend(Value)(scope auto ref Value value) @trusted
    if (is_string_buf_argument!value)
    {
        return this.storage.try_prepend(this.allocator, string_buf_input(value));
    }

    void prepend(Value)(scope auto ref Value value) @trusted
    if (is_string_buf_argument!value)
    {
        this.storage.prepend(this.allocator, string_buf_input(value));
    }

    void truncate_bytes(usize new_byte_length) @trusted
    {
        this.storage.truncate_bytes(new_byte_length);
    }

    void clear() @trusted
    {
        this.storage.clear();
    }

    bool try_append_escaped(Value)(scope auto ref Value value) @trusted
    if (is_string_buf_argument!value)
    {
        return this.storage.try_append_escaped(
            this.allocator,
            string_buf_input(value),
        );
    }

    void append_escaped(Value)(scope auto ref Value value) @trusted
    if (is_string_buf_argument!value)
    {
        this.storage.append_escaped(this.allocator, string_buf_input(value));
    }

    /// Copies this buffer into a new exact-sized owner allocated by `allocator`.
    bool try_copy(
        Allocator* allocator,
        scope OwnedString* output,
    ) const @trusted
    {
        return this.storage.view.try_copy(allocator, output);
    }

    /// Copies this buffer into arena-owned storage.
    bool try_copy(Arena* arena, scope String* output) const @trusted
    {
        return this.storage.view.try_copy(arena, output);
    }

    /// Panicking independently owned counterpart to `try_copy`.
    OwnedString copy(Allocator* allocator) const @trusted
    {
        return this.storage.view.copy(allocator);
    }

    /// Panicking arena-owned counterpart to `try_copy`.
    String copy(Arena* arena) const @trusted
    {
        return this.storage.view.copy(arena);
    }

    bool try_replace_in_place(From, To)(
        scope auto ref From from,
        scope auto ref To to,
    ) @trusted
    if (is_string_buf_argument!from && is_string_buf_argument!to)
    {
        return this.storage.try_replace_in_place(
            this.allocator,
            string_buf_input(from),
            string_buf_input(to),
        );
    }

    void replace_in_place(From, To)(
        scope auto ref From from,
        scope auto ref To to,
    ) @trusted
    if (is_string_buf_argument!from && is_string_buf_argument!to)
    {
        this.storage.replace_in_place(
            this.allocator,
            string_buf_input(from),
            string_buf_input(to),
        );
    }

    /// Replaces every non-overlapping `from` occurrence in a new exact-sized
    /// owner allocated by `allocator`.
    bool try_replace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
        Allocator* allocator,
        scope OwnedString* output,
    ) const @trusted
    if (is_string_buf_argument!from && is_string_buf_argument!to)
    {
        return this.storage.view.try_replace(
            string_buf_input(from),
            string_buf_input(to),
            allocator,
            output,
        );
    }

    /// Replaces every non-overlapping `from` occurrence in arena-owned output.
    bool try_replace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
        Arena* arena,
        scope String* output,
    ) const @trusted
    if (is_string_buf_argument!from && is_string_buf_argument!to)
    {
        return this.storage.view.try_replace(
            string_buf_input(from),
            string_buf_input(to),
            arena,
            output,
        );
    }

    /// Panicking independently owned counterpart to `try_replace`.
    OwnedString replace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
        Allocator* allocator,
    ) const @trusted
    if (is_string_buf_argument!from && is_string_buf_argument!to)
    {
        return this.storage.view.replace(
            string_buf_input(from),
            string_buf_input(to),
            allocator,
        );
    }

    /// Panicking arena-owned counterpart to `try_replace`.
    String replace(From, To)(
        scope auto ref From from,
        scope auto ref To to,
        Arena* arena,
    ) const @trusted
    if (is_string_buf_argument!from && is_string_buf_argument!to)
    {
        return this.storage.view.replace(
            string_buf_input(from),
            string_buf_input(to),
            arena,
        );
    }

    bool try_escape_in_place() @trusted
    {
        return this.storage.try_escape_in_place(this.allocator);
    }

    void escape_in_place() @trusted
    {
        this.storage.escape_in_place(this.allocator);
    }

    bool try_c_string(scope const(char)** output) @system
    {
        return this.storage.try_c_string(this.allocator, output);
    }

    const(char)* c_string() return @system
    {
        return this.storage.c_string(this.allocator);
    }

    const(char)* checked_c_string() return @system
    {
        return this.storage.checked_c_string(this.allocator);
    }

    /// Returns the first UTF-8 code unit. The buffer must not be empty.
    char front_code_unit() const @trusted
    {
        return this.storage.view.front_code_unit();
    }

    /// Returns the last UTF-8 code unit. The buffer must not be empty.
    char back_code_unit() const @trusted
    {
        return this.storage.view.back_code_unit();
    }

    i32 compare(Other)(scope auto ref Other other) const pure @trusted
    if (is_string_buf_argument!other)
    {
        return this.storage.view.compare(string_buf_input(other));
    }

    String slice_bytes(usize begin_byte_offset, usize end_byte_offset) const return @trusted
    {
        return this.storage.view.slice_bytes(begin_byte_offset, end_byte_offset);
    }

    String prefix_bytes(usize end_byte_offset) const return @trusted
    {
        return this.storage.view.prefix_bytes(end_byte_offset);
    }

    String suffix_bytes(usize begin_byte_offset) const return @trusted
    {
        return this.storage.view.suffix_bytes(begin_byte_offset);
    }

    usize find(Needle)(scope auto ref Needle needle) const pure @trusted
    if (is_string_buf_argument!needle)
    {
        return this.storage.view.find(string_buf_input(needle));
    }

    usize find_last(Needle)(scope auto ref Needle needle) const pure @trusted
    if (is_string_buf_argument!needle)
    {
        return this.storage.view.find_last(string_buf_input(needle));
    }

    usize find_code_unit(char code_unit) const pure @trusted
    {
        return this.storage.view.find_code_unit(code_unit);
    }

    usize find_last_code_unit(char code_unit) const pure @trusted
    {
        return this.storage.view.find_last_code_unit(code_unit);
    }

    usize find_code_point(dchar code_point) const @trusted
    {
        return this.storage.view.find_code_point(code_point);
    }

    usize find_last_code_point(dchar code_point) const @trusted
    {
        return this.storage.view.find_last_code_point(code_point);
    }

    bool contains(Needle)(scope auto ref Needle needle) const pure @trusted
    if (is_string_buf_argument!needle)
    {
        return this.storage.view.contains(string_buf_input(needle));
    }

    bool contains_code_unit(char code_unit) const pure @trusted
    {
        return this.storage.view.contains_code_unit(code_unit);
    }

    bool contains_code_point(dchar code_point) const @trusted
    {
        return this.storage.view.contains_code_point(code_point);
    }

    bool contains_nul() const pure @trusted
    {
        return this.storage.view.contains_nul();
    }

    bool starts_with(Prefix)(scope auto ref Prefix prefix) const pure @trusted
    if (is_string_buf_argument!prefix)
    {
        return this.storage.view.starts_with(string_buf_input(prefix));
    }

    bool ends_with(Suffix)(scope auto ref Suffix suffix) const pure @trusted
    if (is_string_buf_argument!suffix)
    {
        return this.storage.view.ends_with(string_buf_input(suffix));
    }

    String base_name() const return pure @trusted
    {
        return this.storage.view.base_name();
    }

    String strip_extension() const return pure @trusted
    {
        return this.storage.view.strip_extension();
    }

    String trim_ascii_start() const return pure @trusted
    {
        return this.storage.view.trim_ascii_start();
    }

    String trim_ascii_end() const return pure @trusted
    {
        return this.storage.view.trim_ascii_end();
    }

    String trim_ascii() const return pure @trusted
    {
        return this.storage.view.trim_ascii();
    }

    /// Replaces the complete contents while retaining reusable capacity.
    ///
    /// `value` may be a view into this buffer; self-assignment and subview
    /// assignment are handled without allocation.
    bool try_assign(Value)(scope auto ref Value value) @trusted
    if (is_string_buf_argument!value)
    {
        const input = string_buf_input(value);
        const current = this.storage.view;
        bool aliases;
        usize source_offset;
        if (input.length != 0 && current.length != 0)
        {
            const source_address = cast(usize) input.ptr;
            const begin_address = cast(usize) current.ptr;
            if (source_address >= begin_address)
            {
                source_offset = source_address - begin_address;
                aliases = source_offset <= current.length &&
                    input.length <= current.length - source_offset;
            }
        }

        if (aliases)
        {
            if (input.length != 0 && source_offset != 0)
                memmove(this.storage.bytes.slice.ptr, input.ptr, input.length);
            if (input.length < current.length)
                this.storage.bytes.remove_range(
                    input.length,
                    current.length - input.length,
                );
            return true;
        }

        if (!this.storage.try_reserve(this.allocator, input.length))
            return false;
        this.storage.clear();
        this.storage.append_assume_capacity(input);
        return true;
    }

    void assign(Value)(scope auto ref Value value) @trusted
    if (is_string_buf_argument!value)
    {
        if (!this.try_assign(value))
            panic("StringBuf allocation failed");
    }

    /// Removes `prefix` when present and reports whether the buffer changed.
    bool remove_prefix(Prefix)(scope auto ref Prefix prefix) @trusted
    if (is_string_buf_argument!prefix)
    {
        const input = string_buf_input(prefix);
        if (!this.storage.view.starts_with(input))
            return false;
        if (input.length != 0)
            this.storage.bytes.remove_range(0, input.length);
        return true;
    }

    /// Removes `suffix` when present and reports whether the buffer changed.
    bool remove_suffix(Suffix)(scope auto ref Suffix suffix) @trusted
    if (is_string_buf_argument!suffix)
    {
        const input = string_buf_input(suffix);
        if (!this.storage.view.ends_with(input))
            return false;
        if (input.length != 0)
            this.storage.truncate_bytes(this.storage.byte_length - input.length);
        return true;
    }

    /// Removes leading ASCII whitespace in place.
    void trim_ascii_start_in_place() @trusted
    {
        const trimmed = this.storage.view.trim_ascii_start();
        const removed = this.storage.byte_length - trimmed.length;
        if (removed != 0)
            this.storage.bytes.remove_range(0, removed);
    }

    /// Removes trailing ASCII whitespace in place.
    void trim_ascii_end_in_place() @trusted
    {
        const trimmed = this.storage.view.trim_ascii_end();
        this.storage.truncate_bytes(trimmed.length);
    }

    /// Removes leading and trailing ASCII whitespace in place.
    void trim_ascii_in_place() @trusted
    {
        const original = this.storage.view;
        const trimmed = original.trim_ascii();
        const begin = trimmed.length == 0
            ? original.length : cast(usize) trimmed.ptr - cast(usize) original.ptr;
        if (begin != 0)
            this.storage.bytes.remove_range(0, begin);
        this.storage.truncate_bytes(trimmed.length);
    }

    Array!String split(Separator)(
        scope auto ref Separator separator,
        Allocator* allocator,
    ) const @trusted
    if (is_string_buf_argument!separator)
    {
        return this.storage.view.split(string_buf_input(separator), allocator);
    }

    Array!String split(char separator, Allocator* allocator) const @trusted
    {
        return this.storage.view.split(separator, allocator);
    }

    Array!String split_whitespace(Allocator* allocator) const @trusted
    {
        return this.storage.view.split_whitespace(allocator);
    }

    Array!String split_lines(Allocator* allocator) const @trusted
    {
        return this.storage.view.split_lines(allocator);
    }

    bool opEquals(Other)(scope auto ref Other other) const pure @trusted
    if (is_string_buf_argument!other)
    {
        return this.storage == string_buf_input(other);
    }

    bool opEquals(scope ref const Self other) const pure @trusted
    {
        return this.storage == other.storage;
    }

    usize toHash() const pure @trusted
    {
        return this.storage.toHash();
    }

    package(xtb) static Self adopt_unmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        require_valid_string_buf_allocator(allocator);
        require(storage !is null,
            "StringBufUnmanaged pointer is null");
        Self result;
        result.allocator = allocator;
        move_emplace(*storage, result.storage);
        return move(result);
    }

    package(xtb) static Self adopt_raw(
        Allocator* allocator,
        char* data,
        usize length,
        usize capacity,
    ) @system
    {
        Storage storage = Storage.adopt(data, length, capacity);
        return Self.adopt_unmanaged(allocator, &storage);
    }
}

private void require_valid_string_buf_allocator(Allocator* allocator) @trusted
{
    require(allocator !is null && *allocator !is null,
        "StringBuf requires a valid allocator");
}

private usize string_buf_writer_sink(
    void* context,
    scope const(u8)[] bytes,
)
@trusted
{
    StringBuf* buffer = cast(StringBuf*) context;
    if (buffer is null || buffer.allocator is null)
        return 0;
    return buffer.try_append(cast(String) bytes) ? bytes.length : 0;
}

///
/// The zero state is valid. Nonempty values must be explicitly deinitialized
/// with the allocator that created or adopted their storage. Copying is
/// disabled because a shallow copy would duplicate ownership.
@mustuse struct OwnedStringUnmanaged
{
nothrow @nogc:

    String value;

    @disable this(this);
    @disable ref OwnedStringUnmanaged opAssign(OwnedStringUnmanaged source) return;

    static bool try_from_string(
        Allocator* allocator,
        scope String value,
        scope OwnedStringUnmanaged* output,
    ) @trusted
    {
        require_valid_owned_string_allocator(allocator);
        require(output !is null,
            "OwnedStringUnmanaged output pointer is null");
        require(output.value.ptr is null && output.value.length == 0,
            "OwnedStringUnmanaged output is not empty");

        if (value.length == 0)
            return true;

        char* bytes = allocator.try_allocate_array!char(value.length).ptr;
        if (bytes is null)
            return false;
        memmove(bytes, value.ptr, value.length);
        output.value = bytes[0 .. value.length];
        return true;
    }

    static OwnedStringUnmanaged from_string(
        Allocator* allocator,
        scope String value,
    ) @trusted
    {
        OwnedStringUnmanaged result;
        if (!OwnedStringUnmanaged.try_from_string(allocator, value, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    /// Copies bytes whose UTF-8 validity the caller has already proved.
    static bool try_from_bytes_unchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        scope OwnedStringUnmanaged* output,
    ) @system
    {
        return OwnedStringUnmanaged.try_from_string(allocator, bytes.as_string_unchecked, output);
    }

    /// Panicking counterpart to `try_from_bytes_unchecked`.
    static OwnedStringUnmanaged from_bytes_unchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    ) @system
    {
        OwnedStringUnmanaged result;
        if (!OwnedStringUnmanaged.try_from_bytes_unchecked(allocator, bytes, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    void deinit(Allocator* allocator) @trusted
    {
        if (this.value.length != 0)
        {
            require_valid_owned_string_allocator(allocator);
            allocator.deallocate_array(this.value.ptr[0 .. this.value.length]);
        }
        this.value = String.init;
    }

    void reset_and_release(Allocator* allocator) @trusted
    {
        this.deinit(allocator);
    }

    String view() const return pure @safe
    {
        return this.value;
    }

    String format_representation() const return pure @safe
    {
        return this.view;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.value(this.view);
    }

    usize byte_length() const pure @safe
    {
        return this.value.length;
    }

    bool empty() const pure @safe
    {
        return this.value.length == 0;
    }

    bool opEquals(scope String other) const pure @safe
    {
        return this.value.equal(other);
    }

    bool opEquals(scope ref const OwnedStringUnmanaged other) const
    pure @safe
    {
        return this.value.equal(other.value);
    }

    usize toHash() const pure @safe
    {
        return hash_value(this.value);
    }

    package(xtb) static OwnedStringUnmanaged adopt_exact(
        scope RawArrayStorage!char* storage,
    ) @system
    {
        require(storage !is null,
            "raw OwnedString storage pointer is null");
        require(storage.length == storage.capacity,
            "adopted OwnedString storage is not exact-sized");
        require((storage.length == 0) == (storage.data is null),
            "adopted OwnedString storage is not canonical");
        OwnedStringUnmanaged result;
        result.value = storage.data[0 .. storage.length];
        storage.data = null;
        storage.length = 0;
        storage.capacity = 0;
        return move(result);
    }

    package(xtb) const(String)* view_pointer() const return @safe
    {
        return &this.value;
    }
}

/// Standalone explicit-lifetime wrapper around `OwnedStringUnmanaged`.
@mustuse struct OwnedString
{
nothrow @nogc:

    alias Self = OwnedString;
    alias Storage = OwnedStringUnmanaged;
    alias Released = ReleasedStorage!Storage;

    Allocator* allocator;
    Storage storage;

    invariant
    {
        require(&this !is null, "OwnedString pointer is null");
    }

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(Allocator* allocator) @trusted
    {
        require_valid_owned_string_allocator(allocator);
        Self result;
        result.allocator = allocator;
        return result;
    }

    static bool try_from_string(
        Allocator* allocator,
        scope String value,
        scope Self* output,
    ) @trusted
    {
        require(output !is null, "OwnedString output pointer is null");
        require(output.allocator is null && output.storage.empty,
            "OwnedString output is not empty");
        Storage storage;
        if (!Storage.try_from_string(allocator, value, &storage))
            return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static Self from_string(Allocator* allocator, scope String value) @trusted
    {
        Self result;
        if (!Self.try_from_string(allocator, value, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    static bool try_from_bytes_unchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        scope Self* output,
    ) @system
    {
        require(output !is null, "OwnedString output pointer is null");
        require(output.allocator is null && output.storage.empty,
            "OwnedString output is not empty");
        Storage storage;
        if (!Storage.try_from_bytes_unchecked(allocator, bytes, &storage))
            return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static Self from_bytes_unchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    ) @system
    {
        Self result;
        if (!Self.try_from_bytes_unchecked(allocator, bytes, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    static Self adopt(scope Released* released) @trusted
    {
        require(released !is null,
            "released OwnedString storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator = allocator;
        move_emplace(storage, result.storage);
        return move(result);
    }

    void deinit() @trusted
    {
        if (this.allocator is null)
            return;
        this.storage.deinit(this.allocator);
        this.allocator = null;
    }

    void reset_and_release() @trusted
    {
        this.storage.reset_and_release(this.allocator);
    }

    Released release() @trusted
    {
        auto result = Released.from_owned_parts(this.allocator, &this.storage);
        this.allocator = null;
        return move(result);
    }

    String view() const return pure @trusted
    {
        return this.storage.view;
    }

    String format_representation() const return pure @trusted
    {
        return this.view;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.value(this.view);
    }

    usize byte_length() const pure @trusted
    {
        return this.storage.byte_length;
    }

    bool empty() const pure @trusted
    {
        return this.storage.empty;
    }

    bool equal(scope String other) const pure @trusted
    {
        return this.storage == other;
    }

    bool equal(scope ref const Self other) const pure @trusted
    {
        return this.storage == other.storage;
    }

    /// Copies this value into storage owned by `arena`.
    bool try_copy(Arena* arena, scope String* output) const @trusted
    {
        return this.storage.view.try_copy(arena, output);
    }

    /// Panicking arena-owned counterpart to `try_copy`.
    String copy(Arena* arena) const @trusted
    {
        return this.storage.view.copy(arena);
    }

    /// Clones this value with an explicit allocator.
    bool try_clone(
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return Self.try_from_string(allocator, this.storage.view, output);
    }

    /// Panicking clone using an explicit allocator.
    Self clone(Allocator* allocator) const @trusted
    {
        return Self.from_string(allocator, this.storage.view);
    }

    /// Concatenates into a new owner using an explicit allocator.
    bool try_concat(
        String right,
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return this.storage.view.try_concat(right, allocator, output);
    }

    /// Concatenates into storage owned by `arena`.
    bool try_concat(
        String right,
        Arena* arena,
        scope String* output,
    ) const @trusted
    {
        return this.storage.view.try_concat(right, arena, output);
    }

    /// Panicking concatenation using an explicit allocator.
    Self concat(String right, Allocator* allocator) const @trusted
    {
        return this.storage.view.concat(right, allocator);
    }

    /// Panicking concatenation into storage owned by `arena`.
    String concat(String right, Arena* arena) const @trusted
    {
        return this.storage.view.concat(right, arena);
    }

    /// Replaces matches into a new owner using an explicit allocator.
    bool try_replace(
        String from,
        String to,
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return this.storage.view.try_replace(from, to, allocator, output);
    }

    /// Replaces matches into storage owned by `arena`.
    bool try_replace(
        String from,
        String to,
        Arena* arena,
        scope String* output,
    ) const @trusted
    {
        return this.storage.view.try_replace(from, to, arena, output);
    }

    /// Panicking replacement using an explicit allocator.
    Self replace(
        String from,
        String to,
        Allocator* allocator,
    ) const @trusted
    {
        return this.storage.view.replace(from, to, allocator);
    }

    /// Panicking replacement into storage owned by `arena`.
    String replace(String from, String to, Arena* arena) const @trusted
    {
        return this.storage.view.replace(from, to, arena);
    }

    /// Escapes into a new owner using an explicit allocator.
    bool try_escape(
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return this.storage.view.try_escape(allocator, output);
    }

    /// Escapes into storage owned by `arena`.
    bool try_escape(Arena* arena, scope String* output) const @trusted
    {
        return this.storage.view.try_escape(arena, output);
    }

    /// Panicking escape using an explicit allocator.
    Self escape(Allocator* allocator) const @trusted
    {
        return this.storage.view.escape(allocator);
    }

    /// Panicking escape into storage owned by `arena`.
    String escape(Arena* arena) const @trusted
    {
        return this.storage.view.escape(arena);
    }

    bool opEquals(scope String other) const pure @trusted
    {
        return this.storage == other;
    }

    bool opEquals(scope ref const Self other) const pure @trusted
    {
        return this.storage == other.storage;
    }

    usize toHash() const pure @trusted
    {
        return this.storage.toHash();
    }

    package(xtb) static Self adopt_unmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        require_valid_owned_string_allocator(allocator);
        require(storage !is null,
            "OwnedStringUnmanaged pointer is null");
        Self result;
        result.allocator = allocator;
        move_emplace(*storage, result.storage);
        return move(result);
    }
}

/// Copies borrowed text into exact-sized independently owned storage.
bool try_copy(
    String value,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return try_copy_impl(value, allocator, output);
}

/// Copies borrowed text into storage owned by `arena`.
bool try_copy(
    String value,
    Arena* arena,
    scope String* output,
) @trusted
{
    return try_copy_impl(value, arena, output);
}

/// Panicking independently owned counterpart to `try_copy`.
OwnedString copy(String value, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!value.try_copy(allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `try_copy`.
String copy(String value, Arena* arena) @trusted
{
    String result;
    if (!value.try_copy(arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Concatenates into exact-sized independently owned storage.
bool try_concat(
    String left,
    String right,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return try_concat_impl(left, right, allocator, output);
}

/// Concatenates into storage owned by `arena`.
bool try_concat(
    String left,
    String right,
    Arena* arena,
    scope String* output,
) @trusted
{
    return try_concat_impl(left, right, arena, output);
}

/// Panicking independently owned counterpart to `try_concat`.
OwnedString concat(String left, String right, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!left.try_concat(right, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `try_concat`.
String concat(String left, String right, Arena* arena) @trusted
{
    String result;
    if (!left.try_concat(right, arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Replaces every non-overlapping `from` occurrence in independently owned output.
bool try_replace(
    String value,
    String from,
    String to,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return try_replace_impl(value, from, to, allocator, output);
}

/// Replaces every non-overlapping `from` occurrence in arena-owned output.
bool try_replace(
    String value,
    String from,
    String to,
    Arena* arena,
    scope String* output,
) @trusted
{
    return try_replace_impl(value, from, to, arena, output);
}

/// Panicking independently owned counterpart to `try_replace`.
OwnedString replace(
    String value,
    String from,
    String to,
    Allocator* allocator,
) @trusted
{
    OwnedString result;
    if (!value.try_replace(from, to, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `try_replace`.
String replace(
    String value,
    String from,
    String to,
    Arena* arena,
) @trusted
{
    String result;
    if (!value.try_replace(from, to, arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Joins borrowed strings into exact-sized independently owned storage.
bool try_join(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return try_join_impl(values, separator, allocator, output);
}

/// Joins borrowed strings into storage owned by `arena`.
bool try_join(
    scope const(String)[] values,
    String separator,
    Arena* arena,
    scope String* output,
) @trusted
{
    return try_join_impl(values, separator, arena, output);
}

/// Panicking independently owned counterpart to `try_join`.
OwnedString join(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
) @trusted
{
    OwnedString result;
    if (!try_join(values, separator, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `try_join`.
String join(
    scope const(String)[] values,
    String separator,
    Arena* arena,
) @trusted
{
    String result;
    if (!try_join(values, separator, arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Escapes conventional C-style special characters into independently owned text.
bool try_escape(
    String value,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return try_escape_impl(value, allocator, output);
}

/// Escapes conventional C-style special characters into arena-owned text.
bool try_escape(
    String value,
    Arena* arena,
    scope String* output,
) @trusted
{
    return try_escape_impl(value, arena, output);
}

/// Panicking independently owned counterpart to `try_escape`.
OwnedString escape(String value, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!value.try_escape(allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `try_escape`.
String escape(String value, Arena* arena) @trusted
{
    String result;
    if (!value.try_escape(arena, &result))
        panic("arena string allocation failed");
    return result;
}

private bool try_copy_impl(Context, Output)(
    String value,
    Context context,
    scope Output* output,
) @trusted
{
    require_string_transform_output(context, output);
    char[] allocation;
    if (!try_prepare_string_transform(context, value.length, &allocation))
        return false;
    if (value.length != 0)
        memmove(allocation.ptr, value.ptr, value.length);
    commit_string_transform(context, allocation, output);
    return true;
}

private bool try_concat_impl(Context, Output)(
    String left,
    String right,
    Context context,
    scope Output* output,
) @trusted
{
    require_string_transform_output(context, output);
    if (right.length > usize.max - left.length)
        return false;
    const length = left.length + right.length;

    char[] allocation;
    if (!try_prepare_string_transform(context, length, &allocation))
        return false;
    if (left.length != 0)
        memmove(allocation.ptr, left.ptr, left.length);
    if (right.length != 0)
        memmove(allocation.ptr + left.length, right.ptr, right.length);
    commit_string_transform(context, allocation, output);
    return true;
}

private bool try_replace_impl(Context, Output)(
    String value,
    String from,
    String to,
    Context context,
    scope Output* output,
) @trusted
{
    require_string_transform_output(context, output);
    if (from.length == 0)
        return try_copy_impl(value, context, output);

    usize count;
    usize position;
    while (position <= value.length)
    {
        const found = value[position .. $].find(from);
        if (found == not_found)
            break;
        ++count;
        position += found + from.length;
    }

    usize length = value.length;
    if (to.length >= from.length)
    {
        const growth = to.length - from.length;

        if (growth != 0 && count > (usize.max - length) / growth)
            return false;
        length += count * growth;
    }
    else
        length -= count * (from.length - to.length);

    char[] allocation;
    if (!try_prepare_string_transform(context, length, &allocation))
        return false;
    usize source_offset;
    usize destination_offset;
    while (source_offset < value.length)
    {
        const found = value[source_offset .. $].find(from);
        if (found == not_found)
        {
            const remainder = value.length - source_offset;
            if (remainder != 0)
                memmove(
                    allocation.ptr + destination_offset,
                    value.ptr + source_offset,
                    remainder,
                );
            destination_offset += remainder;
            break;
        }
        if (found != 0)
            memmove(
                allocation.ptr + destination_offset,
                value.ptr + source_offset,
                found,
            );
        destination_offset += found;
        if (to.length != 0)
            memmove(
                allocation.ptr + destination_offset,
                to.ptr,
                to.length,
            );
        destination_offset += to.length;
        source_offset += found + from.length;
    }
    commit_string_transform(context, allocation, output);
    return true;
}

private bool try_join_impl(Context, Output)(
    scope const(String)[] values,
    String separator,
    Context context,
    scope Output* output,
) @trusted
{
    require_string_transform_output(context, output);
    usize length;
    foreach (value; values)
    {
        if (value.length > usize.max - length)
            return false;
        length += value.length;
    }
    if (values.length > 1)
    {
        const count = values.length - 1;
        if (separator.length != 0 &&
            count > (usize.max - length) / separator.length)
            return false;
        length += count * separator.length;
    }

    char[] allocation;
    if (!try_prepare_string_transform(context, length, &allocation))
        return false;
    usize offset;
    foreach (index, value; values)
    {
        if (index != 0 && separator.length != 0)
        {
            memmove(allocation.ptr + offset, separator.ptr, separator.length);
            offset += separator.length;
        }
        if (value.length != 0)
        {
            memmove(allocation.ptr + offset, value.ptr, value.length);
            offset += value.length;
        }
    }
    commit_string_transform(context, allocation, output);
    return true;
}

private bool try_escape_impl(Context, Output)(
    String value,
    Context context,
    scope Output* output,
) @trusted
{
    require_string_transform_output(context, output);
    usize escaped_count;
    foreach (character; value)

        if (escaped_character(character) != '\0')
            ++escaped_count;
    if (escaped_count > usize.max - value.length)
        return false;
    const length = value.length + escaped_count;

    char[] allocation;
    if (!try_prepare_string_transform(context, length, &allocation))
        return false;
    usize offset;
    foreach (character; value)
    {
        const escaped = escaped_character(character);
        if (escaped != '\0')
        {
            allocation[offset++] = '\\';
            allocation[offset++] = escaped;
        }
        else
            allocation[offset++] = character;
    }
    commit_string_transform(context, allocation, output);
    return true;
}

private void require_string_transform_output(
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    require_empty_owned_string_output(allocator, output);
}

private void require_string_transform_output(
    Arena* arena,
    scope String* output,
) @trusted
{
    require(arena !is null, "string transform requires a valid arena");
    require(output !is null, "String output pointer is null");
}

private bool try_prepare_string_transform(
    Allocator* allocator,
    usize length,
    scope char[]* allocation,
) @trusted
{
    if (length == 0)
        return true;
    *allocation = allocator.try_allocate_array!char(length);
    return allocation.ptr !is null;
}

private bool try_prepare_string_transform(
    Arena* arena,
    usize length,
    scope char[]* allocation,
) @trusted
{
    if (length == 0)
        return true;
    *allocation = arena.try_allocate_array!char(length);
    return allocation.ptr !is null;
}

private void commit_string_transform(
    Allocator* allocator,
    char[] allocation,
    scope OwnedString* output,
) @system
{
    if (allocation.length == 0)
    {
        OwnedString result = OwnedString.create(allocator);
        move_emplace(result, *output);
        return;
    }
    adopt_exact_owned_string(allocator, allocation, output);
}

private void commit_string_transform(
    Arena*,
    char[] allocation,
    scope String* output,
) @trusted
{
    *output = allocation;
}

private void require_empty_owned_string_output(
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    require_valid_owned_string_allocator(allocator);
    require(output !is null, "OwnedString output pointer is null");
    require(output.allocator is null && output.storage.empty,
        "OwnedString output is not empty");
}

private void adopt_exact_owned_string(
    Allocator* allocator,
    char[] allocation,
    scope OwnedString* output,
) @system
{
    RawArrayStorage!char raw = RawArrayStorage!char.adopt(
        allocation.ptr,
        allocation.length,
        allocation.length,
    );
    OwnedStringUnmanaged storage = OwnedStringUnmanaged.adopt_exact(&raw);
    OwnedString result = OwnedString.adopt_unmanaged(allocator, &storage);
    move_emplace(result, *output);
}

private void require_valid_owned_string_allocator(Allocator* allocator) @trusted
{
    require(allocator !is null && *allocator !is null,
        "OwnedString requires a valid allocator");
}

static assert(OwnedStringUnmanaged.sizeof == String.sizeof);
static assert(OwnedString.sizeof == (Allocator*).sizeof + String.sizeof);
static assert(__traits(compiles, (scope OwnedString* value) @safe {
        Allocator* allocator = value.allocator;
    }));
static assert(!__traits(compiles, (scope const OwnedString* value) @safe {
        Allocator* allocator = value.allocator;
    }));

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : malloc_allocator;

    String text = "  hello world  ";
    assert(text.trim_ascii().equal("hello world"));
    assert(text.find("world") == 8);
    assert(text.starts_with("  he"));
    assert(text.ends_with("  "));
    assert("a/b/file.tar".base_name.equal("file.tar"));
    assert("a/b/file.tar".strip_extension.equal("a/b/file"));
    assert("a/b/.gitignore".strip_extension.equal("a/b/.gitignore"));
    assert("a/b/.config.json".strip_extension.equal("a/b/.config"));
    assert("one two one".find_last("one") == 8);
    assert("hello".front_code_unit == 'h' && "hello".back_code_unit == 'o');
    assert("".empty);

    const c_result = from_c_string("native".ptr);
    assert(c_result.succeeded && c_result.value.equal("native"));

    u8[5] encoded = ['a', 0xc3, 0xa9, 0, 'z'];
    String unchecked = encoded[].as_string_unchecked;
    assert(unchecked.ptr is cast(const(char)*) encoded.ptr);
    assert(unchecked.byte_length == encoded.length);
    assert(unchecked.find_code_point(0xe9) == 1 && unchecked[3] == '\0');

    StringBuf copied_bytes = StringBuf.from_bytes_unchecked(
        malloc_allocator(),
        encoded[],
    );
    encoded[0] = 'b';
    assert(unchecked[0] == 'b');
    assert(copied_bytes.view[0] == 'a');
    assert(copied_bytes.view.find_code_point(0xe9) == 1);
    assert(copied_bytes.view[3] == '\0');

    StringBuf empty_bytes = StringBuf.from_bytes_unchecked(
        malloc_allocator(),
        null,
    );
    assert(empty_bytes.empty);

    Array!String tokens = "a::b::".split("::", malloc_allocator());
    assert(tokens.length == 3);
    assert(tokens[0].equal("a") && tokens[1].equal("b") && tokens[2].empty);
    Array!String words = "  alpha\t beta  ".split_whitespace(malloc_allocator());
    assert(words.length == 2);
    assert(words[0].equal("alpha") && words[1].equal("beta"));
    words.deinit();
    tokens.deinit();

    StringBuf buffer = StringBuf.from_string(malloc_allocator(), "hello");
    assert(buffer == "hello");
    assert(buffer.equal("hello"));
    assert("hello" == buffer);
    assert(buffer != "other");

    char[5] mutable_text = "hello";
    assert(buffer == mutable_text[]);
    assert(mutable_text[] == buffer);

    StringBuf same = StringBuf.from_string(malloc_allocator(), "hello");
    StringBuf different = StringBuf.from_string(malloc_allocator(), "Hello");
    assert(buffer == same && same == buffer);
    assert(buffer.equal(same));
    assert(buffer != different && different != buffer);
    assert(buffer.toHash == same.toHash);

    StringBuf empty_buffer = StringBuf.create(malloc_allocator());
    String empty_string;
    assert(empty_buffer == empty_string);
    assert(empty_string == empty_buffer);

    buffer.append(',');
    buffer.append(" world");
    buffer.append(cast(dchar) 0x1f642);
    assert(buffer.view.ends_with("🙂"));
    buffer.truncate_bytes(buffer.byte_length - "🙂".length);
    buffer.prepend("say: ");
    assert(buffer == "say: hello, world");
    buffer.replace_in_place("world", "BetterC library");
    assert(buffer == "say: hello, BetterC library");
    buffer.replace_in_place("BetterC library", "D");
    assert(buffer == "say: hello, D");
    buffer.append_escaped("\n");
    assert(buffer.view.ends_with("\\n"));
    buffer.append_escaped(" café🙂");
    assert(buffer.view.ends_with(" café🙂"));
    const original_length = buffer.byte_length;
    const(char)* terminated;
    assert(buffer.try_c_string(&terminated));
    assert(buffer.byte_length == original_length);
    assert(buffer.view == "say: hello, D\\n café🙂");
    assert(terminated[buffer.byte_length] == '\0');
    assert(buffer.checked_c_string[buffer.byte_length] == '\0');

    buffer.append('!');
    terminated = buffer.c_string;
    assert(buffer.view.ends_with("!"));
    assert(terminated[buffer.byte_length] == '\0');

    StringBuf unicode = StringBuf.from_string(malloc_allocator(), "Aé🙂");
    assert(unicode.byte_length == 7);
    assert(unicode.byte_capacity >= unicode.byte_length);
    unicode.insert(3, "界");
    assert(unicode == "Aé界🙂");
    unicode.truncate_bytes(6);
    assert(unicode == "Aé界");

    StringBuf scalar_widths = StringBuf.with_capacity(malloc_allocator(), 1);
    scalar_widths.append(cast(dchar) 0x7f);
    scalar_widths.append(cast(dchar) 0x80);
    scalar_widths.append(cast(dchar) 0x800);
    scalar_widths.append(cast(dchar) 0x10000);
    assert(scalar_widths.view == "\x7f\u0080\u0800\U00010000");

    StringBuf self_prepend = StringBuf.from_string(
        malloc_allocator(),
        "abcdefgh",
    );
    self_prepend.prepend(self_prepend.view);
    assert(self_prepend == "abcdefghabcdefgh");

    StringBuf self_escape = StringBuf.from_string(
        malloc_allocator(),
        "a\nbcdefg",
    );
    self_escape.append_escaped(self_escape.view);
    assert(self_escape == "a\nbcdefga\\nbcdefg");

    AllocationRecord[4] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        malloc_allocator(), records[],
    );
    failing.fail_after(0);
    StringBuf failed_bytes;
    assert(!StringBuf.try_from_bytes_unchecked(
            failing.allocator,
            encoded[],
            &failed_bytes,
    ));
    assert(failed_bytes.empty);

    StringBuf failed_scalar = StringBuf.create(failing.allocator);
    assert(!failed_scalar.try_append(cast(dchar) 0x1f642));
    assert(failed_scalar.empty && failing.clean);

    const(char)* sentinel = cast(const(char)*) 1;
    const(char)* unchanged = sentinel;
    assert(!failed_scalar.try_c_string(&unchanged));
    assert(unchanged is sentinel);
    assert(failed_scalar.empty && failing.clean);

    StringBuf empty_c_string = StringBuf.create(malloc_allocator());
    const(char)* empty_pointer;
    assert(empty_c_string.try_c_string(&empty_pointer));
    assert(empty_pointer !is null && empty_pointer[0] == '\0');
    assert(empty_c_string.empty);

    empty_c_string.deinit();
    failed_scalar.deinit();
    failed_bytes.deinit();
    self_escape.deinit();
    self_prepend.deinit();
    scalar_widths.deinit();
    unicode.deinit();
    empty_buffer.deinit();
    different.deinit();
    same.deinit();
    buffer.deinit();
    empty_bytes.deinit();
    copied_bytes.deinit();
}

unittest
{
    import core.internal.traits : hasElaborateDestructor;
    import xtb.memory : Allocator;
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : malloc_allocator;
    import xtb.lifetime : deinit, needs_deinit;

    static assert(StringBufUnmanaged.sizeof == ArrayUnmanaged!char.sizeof);
    static assert(StringBuf.sizeof ==
            StringBufUnmanaged.sizeof + (Allocator*).sizeof);
    static assert(!__traits(isCopyable, StringBufUnmanaged));
    static assert(!__traits(isCopyable, StringBuf));
    static assert(!__traits(isCopyable, StringBuf.Released));
    static assert(!hasElaborateDestructor!StringBufUnmanaged);
    static assert(!hasElaborateDestructor!StringBuf);
    static assert(needs_deinit!StringBuf);
    static assert(!__traits(compiles, (ref StringBufUnmanaged left,
            ref StringBufUnmanaged right) { left = move(right); }));
    static assert(!__traits(compiles, (ref StringBuf left,
            ref StringBuf right) { left = move(right); }));
    static assert(__traits(compiles, (scope StringBuf* value) @safe {
            Allocator* allocator = value.allocator;
        }));
    static assert(!__traits(compiles, (scope const StringBuf* value) @safe {
            Allocator* allocator = value.allocator;
        }));
    static assert(__traits(compiles, () @safe {
            StringBuf.Released released;
            ref StringBufUnmanaged storage = released.storage;
        }));
    static assert(!__traits(compiles, (scope StringBuf* value) { value.try_replace("a", "b"); }));
    static assert(!__traits(compiles, (scope StringBufUnmanaged* value,
            Allocator* allocator) { value.try_replace(allocator, "a", "b"); }));
    static assert(!__traits(compiles, (scope StringBuf* value) { value.try_escape("x"); }));
    static assert(!__traits(compiles, (scope StringBufUnmanaged* value,
            Allocator* allocator) { value.try_escape(allocator, "x"); }));

    StringBufUnmanaged zero;
    zero.deinit(null);
    zero.reset_and_release(null);
    assert(zero.empty && zero.byte_capacity == 0);

    AllocationRecord[16] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        malloc_allocator(),
        records[],
    );

    {
        StringBuf buffer = StringBuf.from_string(tracked.allocator, "alpha");
        StringBuf.Released released = buffer.release();
        assert(buffer.allocator is null && buffer.empty);
        assert(released.allocator is tracked.allocator);
        assert(released.storage.view == "alpha");

        released.storage.append(released.allocator, " beta");
        assert(released.storage.view == "alpha beta");
        deinit(released);
    }
    assert(tracked.clean);

    {
        StringBuf source = StringBuf.from_string(tracked.allocator, "adopted");
        StringBuf.Released released = source.release();
        StringBuf adopted = StringBuf.adopt(&released);

        assert(source.allocator is null && source.empty);
        assert(released.allocator is null && released.storage.empty);
        assert(adopted.allocator is tracked.allocator);
        assert(adopted.view == "adopted");
        adopted.deinit();
    }
    assert(tracked.clean);

    {
        StringBuf source = StringBuf.from_string(tracked.allocator, "raw");
        StringBuf.Released released = source.release();
        Allocator* allocator;
        StringBufUnmanaged storage = released.extract(&allocator);

        assert(allocator is tracked.allocator);
        assert(released.allocator is null && released.storage.empty);
        storage.append(allocator, " storage");
        assert(storage.view == "raw storage");
        storage.deinit(allocator);
    }
    assert(tracked.clean);
}

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : malloc_allocator;

    AllocationRecord[32] managed_records;
    AllocationRecord[32] unmanaged_records;
    InstrumentedAllocator managed_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        managed_records[],
    );
    InstrumentedAllocator unmanaged_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        unmanaged_records[],
    );

    StringBuf managed = StringBuf.create(managed_allocator.allocator);
    StringBufUnmanaged unmanaged;

    assert(managed.try_append("alpha"));
    assert(unmanaged.try_append(unmanaged_allocator.allocator, "alpha"));
    assert(managed.try_append(cast(dchar) 0x1f642));
    assert(unmanaged.try_append(
            unmanaged_allocator.allocator,
            cast(dchar) 0x1f642,
    ));
    assert(managed.try_insert(5, " beta"));
    assert(unmanaged.try_insert(
            unmanaged_allocator.allocator,
            5,
            " beta",
    ));
    assert(managed.try_replace_in_place("alpha", "A"));
    assert(unmanaged.try_replace_in_place(
            unmanaged_allocator.allocator,
            "alpha",
            "A",
    ));
    assert(managed.try_reserve(128));
    assert(unmanaged.try_reserve(unmanaged_allocator.allocator, 128));

    assert(managed.view == unmanaged.view);
    assert(managed.byte_length == unmanaged.byte_length);
    assert(managed.byte_capacity == unmanaged.byte_capacity);
    assert(managed_allocator.stats == unmanaged_allocator.stats);

    const managed_stats_before_clear = managed_allocator.stats;
    const unmanaged_stats_before_clear = unmanaged_allocator.stats;
    managed.clear();
    unmanaged.clear();
    assert(managed_allocator.stats == managed_stats_before_clear);
    assert(unmanaged_allocator.stats == unmanaged_stats_before_clear);

    managed.deinit();
    unmanaged.deinit(unmanaged_allocator.allocator);
    assert(managed_allocator.stats == unmanaged_allocator.stats);
    assert(managed_allocator.clean && unmanaged_allocator.clean);
}

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : malloc_allocator;

    StringBuf text = StringBuf.from_string(
        malloc_allocator(),
        "  alpha/beta/🙂  ",
    );
    StringBuf* pointer = &text;

    assert(pointer.starts_with("  alpha"));
    assert(pointer.ends_with("🙂  "));
    assert(pointer.contains("beta"));
    assert(pointer.contains_code_point(cast(dchar) 0x1f642));
    assert(pointer.find("alpha") == 2);
    assert(pointer.find_last_code_unit('/') == 12);
    assert(pointer.slice_bytes(2, 7) == "alpha");
    assert(pointer.base_name == "🙂  ");
    assert(pointer.strip_extension == pointer.view);
    assert(pointer.trim_ascii_start == "alpha/beta/🙂  ");
    assert(pointer.trim_ascii_end == "  alpha/beta/🙂");
    assert(pointer.trim_ascii == "alpha/beta/🙂");

    pointer.trim_ascii_in_place();
    assert(text == "alpha/beta/🙂");
    assert(pointer.remove_prefix("alpha/"));
    assert(pointer.remove_suffix("/🙂"));
    assert(text == "beta");
    assert(!pointer.remove_prefix("missing"));

    pointer.assign("prefix-value-suffix");
    String middle = pointer.slice_bytes(7, 12);
    pointer.assign(middle);
    assert(text == "value");
    pointer.assign(pointer.view);
    assert(text == "value");

    pointer.assign("a,b,c");
    Array!String parts = pointer.split(',', malloc_allocator());
    assert(parts.length == 3);
    assert(parts[0] == "a" && parts[1] == "b" && parts[2] == "c");
    parts.deinit();

    pointer.assign("\t  words  \n");
    pointer.trim_ascii_start_in_place();
    assert(text == "words  \n");
    pointer.trim_ascii_end_in_place();
    assert(text == "words");

    AllocationRecord[8] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        malloc_allocator(),
        records[],
    );
    StringBuf retained = StringBuf.from_string(failing.allocator, "small");
    failing.fail_after(0);
    assert(!retained.try_assign(
            "this replacement is intentionally larger than the current capacity",
    ));
    assert(retained == "small");
    retained.deinit();
    assert(failing.clean);
    text.deinit();
}
unittest
{
    import core.internal.traits : hasElaborateDestructor;
    import xtb.lifetime : needs_deinit;
    import xtb.allocators.instrumented : InstrumentedAllocator;
    import xtb.allocators.malloc : malloc_allocator;

    OwnedString empty = OwnedString.from_string(malloc_allocator(), "");
    assert(empty.empty);
    assert(empty.allocator is malloc_allocator());

    OwnedString text = OwnedString.from_string(malloc_allocator(), "hello");
    assert(text.view == "hello");
    assert(text.equal("hello"));
    assert(text.byte_length == 5);
    assert(text.toHash == hash_value("hello"));
    static assert(!__traits(isCopyable, OwnedString));
    static assert(!__traits(isCopyable, OwnedStringUnmanaged));
    static assert(!hasElaborateDestructor!OwnedString);
    static assert(!hasElaborateDestructor!OwnedStringUnmanaged);
    static assert(needs_deinit!OwnedString);
    static assert(!__traits(compiles, (ref OwnedString left,
            ref OwnedString right) { left = move(right); }));
    static assert(!__traits(compiles, (ref OwnedStringUnmanaged left,
            ref OwnedStringUnmanaged right) { left = move(right); }));
    static assert(!__traits(compiles,
            OwnedStringUnmanaged.adopt_exact(cast(String) "borrowed")));

    OwnedString copy = text.clone(malloc_allocator());
    assert(copy == text);
    assert(copy.equal(text));
    assert(copy.view.ptr !is text.view.ptr);

    StringBuf exact = StringBuf.from_string(malloc_allocator(), "exact");
    const(char)* exact_pointer;
    {
        exact.shrink_to_fit();
        exact_pointer = exact.view.ptr;
    }
    OwnedString buffer_copy = exact.copy(malloc_allocator());
    assert(buffer_copy.view == exact.view);
    assert(buffer_copy.view.ptr !is exact_pointer);
    assert(exact.view.ptr is exact_pointer);

    StringBufUnmanaged unmanaged = StringBufUnmanaged.from_string(
        malloc_allocator(),
        "unmanaged exact",
    );
    unmanaged.shrink_to_fit(malloc_allocator());
    RawArrayStorage!char raw = unmanaged.release_exact_storage();
    OwnedStringUnmanaged exact_unmanaged =
        OwnedStringUnmanaged.adopt_exact(&raw);
    assert(raw.data is null && raw.length == 0 && raw.capacity == 0);
    assert(exact_unmanaged.view == "unmanaged exact");
    exact_unmanaged.deinit(malloc_allocator());

    import xtb.allocators.instrumented : AllocationRecord;

    AllocationRecord[8] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        malloc_allocator(),
        records[],
    );
    StringBuf source = StringBuf.from_string(malloc_allocator(), "retained");
    failing.fail_after(0);
    OwnedString failed;
    assert(!source.try_copy(failing.allocator, &failed));
    {
        assert(source.view == "retained");
        source.deinit();
    }
    assert(failed.allocator is null && failed.empty);
    assert(failing.clean);

    failed.deinit();
    buffer_copy.deinit();
    exact.deinit();
    copy.deinit();
    text.deinit();
    empty.deinit();
}

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : malloc_allocator;

    AllocationRecord[16] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        records[],
    );

    OwnedStringUnmanaged exact;
    assert(OwnedStringUnmanaged.try_from_string(
            allocator.allocator,
            "sixteen bytes!!!",
            &exact,
    ));
    assert(exact.byte_length == 16);
    assert(allocator.stats.outstanding_allocations == 1);
    assert(allocator.stats.outstanding_bytes == 16);
    exact.deinit(allocator.allocator);
    assert(allocator.clean);

    const allocation_calls = allocator.stats.allocation_calls;
    OwnedString empty = OwnedString.from_string(allocator.allocator, "");
    assert(empty.empty);
    assert(empty.allocator is allocator.allocator);
    assert(allocator.stats.allocation_calls == allocation_calls);

    StringBuf spare = StringBuf.with_capacity(allocator.allocator, 64);
    {
        spare.append("small");
    }
    OwnedString compact = spare.copy(allocator.allocator);
    assert(compact.view == "small");
    assert(compact.byte_length == 5);
    assert(compact.view.ptr !is spare.view.ptr);
    assert(spare.view == "small");

    AllocationRecord[8] foreign_records;
    InstrumentedAllocator foreign = InstrumentedAllocator.create(
        malloc_allocator(),
        foreign_records[],
    );
    StringBuf foreign_buffer = StringBuf.from_string(
        foreign.allocator,
        "foreign",
    );
    const(char)* foreign_pointer;
    {
        foreign_pointer = foreign_buffer.view.ptr;
    }
    OwnedString normalized = foreign_buffer.copy(allocator.allocator);
    assert(normalized.view == "foreign");
    assert(normalized.view.ptr !is foreign_pointer);
    assert(foreign_buffer.view == "foreign");
    foreign_buffer.deinit();
    assert(foreign.clean);

    normalized.deinit();
    compact.deinit();
    spare.deinit();
    empty.deinit();
    assert(allocator.clean);
    assert(allocator.stats.invalid_calls == 0);
    assert(foreign.stats.invalid_calls == 0);
}

unittest
{
    import xtb.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.allocators.malloc : malloc_allocator;

    static assert(is(typeof("copy".copy(malloc_allocator())) == OwnedString));
    static assert(is(typeof("a".concat("b", malloc_allocator())) == OwnedString));
    static assert(is(typeof("a".replace("a", "b", malloc_allocator())) == OwnedString));
    static assert(is(typeof("a".escape(malloc_allocator())) == OwnedString));
    static assert(!is(typeof("copy".try_copy(
            malloc_allocator(),
            cast(String*) null,
            ))));

    AllocationRecord[32] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        records[],
    );

    OwnedString copied = "copy".copy(allocator.allocator);
    assert(copied == "copy");
    assert(allocator.stats.outstanding_bytes == copied.byte_length);
    copied.deinit();
    assert(allocator.clean);

    OwnedString concatenated = "left".concat("right", allocator.allocator);
    assert(concatenated == "leftright");
    assert(allocator.stats.outstanding_bytes == concatenated.byte_length);
    concatenated.deinit();
    assert(allocator.clean);

    OwnedString replaced = "one two one".replace(
        "one",
        "1",
        allocator.allocator,
    );
    assert(replaced == "1 two 1");
    assert(allocator.stats.outstanding_bytes == replaced.byte_length);
    replaced.deinit();
    assert(allocator.clean);

    String[3] parts = ["a", "b", "c"];
    OwnedString joined = parts[].join("/", allocator.allocator);
    assert(joined == "a/b/c");
    assert(allocator.stats.outstanding_bytes == joined.byte_length);
    joined.deinit();
    assert(allocator.clean);

    OwnedString escaped = "a\n\t\\b".escape(allocator.allocator);
    assert(escaped == "a\\n\\t\\\\b");
    assert(allocator.stats.outstanding_bytes == escaped.byte_length);
    escaped.deinit();
    assert(allocator.clean);

    const allocation_calls = allocator.stats.allocation_calls;
    OwnedString empty = "".concat("", allocator.allocator);
    assert(empty.empty && empty.allocator is allocator.allocator);
    assert(allocator.stats.allocation_calls == allocation_calls);
    empty.deinit();

    allocator.fail_after(0);
    OwnedString failed_copy;
    OwnedString failed_concat;
    OwnedString failed_replace;
    OwnedString failed_join;
    OwnedString failed_escape;
    assert(!"copy".try_copy(allocator.allocator, &failed_copy));
    assert(!"a".try_concat("b", allocator.allocator, &failed_concat));
    assert(!"a".try_replace("a", "b", allocator.allocator, &failed_replace));
    assert(!parts[].try_join("/", allocator.allocator, &failed_join));
    assert(!"\n".try_escape(allocator.allocator, &failed_escape));
    assert(failed_copy.allocator is null && failed_copy.empty);
    assert(failed_concat.allocator is null && failed_concat.empty);
    assert(failed_replace.allocator is null && failed_replace.empty);
    assert(failed_join.allocator is null && failed_join.empty);
    assert(failed_escape.allocator is null && failed_escape.empty);
    assert(allocator.clean);
    assert(allocator.stats.invalid_calls == 0);
}
