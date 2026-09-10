module xtb.fmt.print;

nothrow @nogc:

public import xtb.fmt.writer;

import core.stdc.stdio;

import xtb.panic;
import xtb.types;

private usize file_sink(void* context, scope const(u8)[] bytes) @system
{
    FILE* file = cast(FILE*) context;
    if (file is null) return 0;

    return fwrite(bytes.ptr, 1, bytes.length, file);
}

/// Creates an immediate non-owning writer over a libc `FILE*`.
///
/// `file` must be non-null and remain open and valid until the returned writer
/// is no longer used.
Writer file_writer(FILE* file) @system
{
    require(file !is null, "file is null");
    return Writer.from_sink(&file_sink, cast(void*) file);
}

WriteResult write(Args...)(auto ref Args args)
{
    return write_file(cast(FILE*) stdout, args);
}

WriteResult writeln(Args...)(auto ref Args args)
{
    return writeln_file(cast(FILE*) stdout, args);
}

WriteResult ewrite(Args...)(auto ref Args args)
{
    return write_file(cast(FILE*) stderr, args);
}

WriteResult ewriteln(Args...)(auto ref Args args)
{
    return writeln_file(cast(FILE*) stderr, args);
}

/// Writes values synchronously to a non-null libc `FILE*`.
///
/// `file` must remain open and valid for the duration of the call.
WriteResult write_file(Args...)(FILE* file, auto ref Args args) @system
{
    auto writer = file_writer(file);
    writer.write(args);
    return writer.result;
}

/// Writes values and a newline synchronously to a non-null libc `FILE*`.
///
/// `file` must remain open and valid for the duration of the call.
WriteResult writeln_file(Args...)(FILE* file, auto ref Args args) @system
{
    auto writer = file_writer(file);
    writer.writeln(args);
    return writer.result;
}

bool flush_stdout()
{
    return fflush(cast(FILE*) stdout) == 0;
}

bool flush_stderr()
{
    return fflush(cast(FILE*) stderr) == 0;
}

version (unittest)
{
    import xtb.allocators.instrumented;
    import xtb.allocators.malloc;
    import xtb.fmt.fixed_buffer;
    import xtb.fmt.format;
    import xtb.string;
}

unittest
{
    FILE* file = tmpfile();
    assert(file !is null);
    scope (exit) assert(fclose(file) == 0);

    const WriteResult write_result = write_file(file, "value=", 42);
    const WriteResult line_result = writeln_file(file, "!");
    assert(write_result.ok);
    assert(write_result.written == 8);
    assert(line_result.ok);
    assert(line_result.written == 2);

    assert(fflush(file) == 0);
    rewind(file);
    char[10] output;
    const usize read = fread(output.ptr, 1, output.length, file);
    assert(read == output.length);
    assert(output[] == "value=42!\n");
}

unittest
{
    auto buffer = StringBuf.create(malloc_allocator());
    scope (exit) buffer.deinit();

    const i32 answer = 42;
    buffer.write("answer=", answer, ", hex=", hexadecimal(255));
    assert(buffer == "answer=42, hex=0xff");

    const u32 constant_integer = 255;
    const f64 constant_float = 1.25;
    buffer.clear();
    buffer.write(hexadecimal(constant_integer).upper, ", ", fixed(constant_float, 2));
    assert(buffer == "0XFF, 1.25");

    buffer.clear();
    buffer.format!"{} + {} = {}"(2, 3, 5);
    assert(buffer == "2 + 3 = 5");

    buffer.clear();
    buffer.writeln("line=", 1);
    buffer.writeln();
    assert(buffer == "line=1\n\n");

    buffer.clear();
    buffer.formatln!"{} + {} = {}"(2, 3, 5);
    buffer.formatln(i"answer=$(answer)");
    assert(buffer == "2 + 3 = 5\nanswer=42\n");
}

unittest
{
    auto buffer = StringBuf.create(malloc_allocator());
    scope (exit) buffer.deinit();

    // StringBuf exposes an immediate Writer. Each call reaches the destination
    // before returning, so no finish operation is required.
    char[511] split_scalar_prefix;
    split_scalar_prefix[] = 'a';
    const String split_scalar_prefix_string = split_scalar_prefix[];

    auto buffer_writer = buffer.writer();
    buffer_writer.put(split_scalar_prefix_string);
    buffer_writer.put("🙂");
    assert(buffer_writer.result.ok);
    assert(buffer_writer.result.written == 515);
    assert(buffer.byte_length == 515);
    assert(buffer.view[0 .. 511] == split_scalar_prefix_string);
    assert(buffer.view[511 .. $] == "🙂");

    buffer.clear();
    auto header_writer = buffer.writer();
    header_writer.write("[HTTP] ");
    header_writer.writeln("status=", 200);
    assert(header_writer.ok);
    assert(buffer == "[HTTP] status=200\n");
}

unittest
{
    char[8] fixed_buffer;
    const result = fixed_buffer[].write_buffer("abcdefghi");
    assert(result.ok);
    assert(result.truncated);
    assert(result.written == 7);
    assert(result.required == 9);
    assert(fixed_buffer[7] == '\0');

    char[4] truncated_scalar;
    const scalar_result = truncated_scalar[].write_buffer("A🙂");
    assert(scalar_result.ok);
    assert(scalar_result.truncated);
    assert(scalar_result.written == 1);
    assert(scalar_result.required == 5);
    assert(truncated_scalar[0 .. 1] == "A");
    assert(truncated_scalar[1] == '\0');

    char[6] exact_scalar;
    const exact_scalar_result = exact_scalar[].write_buffer("A🙂");
    assert(exact_scalar_result.ok);
    assert(!exact_scalar_result.truncated);
    assert(exact_scalar_result.written == 5);
    assert(exact_scalar_result.required == 5);
    assert(exact_scalar[0 .. 5] == "A🙂");
}

unittest
{
    const i32 answer = 42;

    char[12] interpolated_fixed;
    const interpolated_fixed_result = interpolated_fixed[].format_buffer(i"value=$(answer)");
    assert(interpolated_fixed_result.ok);
    assert(!interpolated_fixed_result.truncated);
    assert(interpolated_fixed_result.written == 8);
    assert(interpolated_fixed_result.required == 8);
    assert(interpolated_fixed[0 .. 8] == "value=42");
    assert(interpolated_fixed[8] == '\0');

    char[8] truncated_interpolation;
    const truncated_interpolation_result = truncated_interpolation[]
        .format_buffer(i"value=$(answer)");
    assert(truncated_interpolation_result.ok);
    assert(truncated_interpolation_result.truncated);
    assert(truncated_interpolation_result.written == 7);
    assert(truncated_interpolation_result.required == 8);
    assert(truncated_interpolation[0 .. 7] == "value=4");
    assert(truncated_interpolation[7] == '\0');
}

unittest
{
    template interpolation_test_sequence(values...)
    {
        alias interpolation_test_sequence = values;
    }

    struct StatefulValue
    {
    nothrow @nogc:

        usize* calls;

        void format_to(ref Writer writer)
        {
            ++*this.calls;
            writer.put("stateful");
        }
    }

    struct CountedExpression
    {
    nothrow @nogc:

        usize* evaluations;

        i32 evaluate()
        {
            ++*this.evaluations;
            return 7;
        }
    }

    auto buffer = StringBuf.create(malloc_allocator());
    scope (exit) buffer.deinit();

    const i32 answer = 42;
    usize calls;
    auto value = StatefulValue(&calls);
    StringBuf stateful = format_string!"{}"(malloc_allocator(), value);
    scope (exit) stateful.deinit();

    assert(stateful == "stateful");
    assert(calls == 1);

    buffer.write(i"answer=$(answer), hex=$(hexadecimal(answer))");
    assert(buffer == "answer=42, hex=0x2a");

    usize evaluations;
    auto counted = CountedExpression(&evaluations);
    buffer.clear();
    buffer.format(i"once=$(counted.evaluate()), custom=$(value)");
    assert(buffer == "once=7, custom=stateful");
    assert(evaluations == 1);
    assert(calls == 2);

    buffer.clear();
    buffer.write(i"outer [$(i"inner=$(answer)")] done");
    assert(buffer == "outer [inner=42] done");

    buffer.clear();
    buffer.write("prefix ", i"$(answer)", " suffix");
    assert(buffer == "prefix 42 suffix");

    buffer.clear();
    buffer.write(i"expanded=$(interpolation_test_sequence!(answer, answer))");
    assert(buffer == "expanded=4242");

    buffer.clear();
    buffer.write(i"");
    assert(buffer.empty);
}

unittest
{
    const i32 answer = 42;

    StringBuf allocated = format_string!"{}:{}"(malloc_allocator(), "item", 9);
    scope (exit) allocated.deinit();
    assert(allocated == "item:9");

    StringBuf interpolated = format_string(
        malloc_allocator(),
        i"owned: $(answer), $(fixed(1.25, 2))",
    );
    scope (exit) interpolated.deinit();
    assert(interpolated == "owned: 42, 1.25");
}

unittest
{
    StringBuf fallible_split_scalar;
    scope (exit) fallible_split_scalar.deinit();

    char[511] split_scalar_prefix;
    split_scalar_prefix[] = 'a';
    const String split_scalar_prefix_string = split_scalar_prefix[];
    assert(try_format_string!"{}{}"(
        malloc_allocator(),
        &fallible_split_scalar,
        split_scalar_prefix_string,
        "🙂",
    ));
    assert(fallible_split_scalar.byte_length == 515);
    assert(fallible_split_scalar.view[511 .. $] == "🙂");

    StringBuf fallible_interpolated;
    scope (exit) fallible_interpolated.deinit();
    assert(try_format_string(malloc_allocator(), &fallible_interpolated, i"try: $(binary(5))"));
    assert(fallible_interpolated == "try: 0b101");
}

unittest
{
    AllocationRecord[4] transactional_records;
    auto transactional_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        transactional_records[],
    );
    auto transactional = StringBuf.with_capacity(transactional_allocator.allocator, 8);

    transactional.write("keep");
    transactional_allocator.fail_after(0);
    char[128] oversized;
    oversized[] = 'x';
    assert(!transactional.try_write("++", cast(String) oversized[]));
    assert(transactional == "keep");

    transactional.deinit();
    assert(transactional_allocator.clean);
}

unittest
{
    const i32 answer = 42;
    AllocationRecord[4] records;
    auto failing = InstrumentedAllocator.create(malloc_allocator(), records[]);
    failing.fail_after(0);

    StringBuf failed_interpolated;
    scope (exit) failed_interpolated.deinit();
    assert(!try_format_string(
        failing.allocator,
        &failed_interpolated,
        i"allocation required: $(answer)",
    ));
    assert(failed_interpolated.empty);
    assert(failing.clean);
}
