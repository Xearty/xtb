module xtb.core.print;

nothrow @nogc:

public import xtb.core.writer;

import core.interpolation : InterpolationFooter, InterpolationHeader;
import core.stdc.stdio : FILE, fflush, fwrite, stderr, stdout;
import core.stdc.string : memcpy;
import xtb.core.lifetime : move, moveEmplace;
import xtb.core.memory : Allocator;
import xtb.core.panic : panic;
import xtb.core.string : StringBuf;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.types : String, u8;
import xtb.core.utf8 : isValidUtf8;

version (unittest) private template InterpolationTestSequence(Values...)
{
    alias InterpolationTestSequence = Values;
}

version (unittest) private void writeHeader(ref Writer writer, String name)
{
    writer.write("[", name, "] ");
}

struct BufferWriteResult
{
    bool ok;
    bool truncated;
    size_t written;
    size_t required;
}

private size_t fileSink(void* context, scope const(u8)[] bytes)
{
    FILE* file = cast(FILE*) context;
    if (file is null)
        return 0;
    return fwrite(bytes.ptr, 1, bytes.length, file);
}

/// Creates an immediate non-owning writer over a libc `FILE*`.
Writer fileWriter(FILE* file)
{
    return Writer.fromSink(&fileSink, cast(void*) file);
}

private struct FixedBufferState
{
    char[] destination;
    size_t written;
    size_t required;
    bool overflow;
}

private size_t fixedBufferSink(void* context, scope const(u8)[] bytes)
{
    FixedBufferState* state = cast(FixedBufferState*) context;
    if (state is null)
        return 0;

    if (bytes.length > size_t.max - state.required)
        state.overflow = true;
    else
        state.required += bytes.length;

    const capacity = state.destination.length == 0
        ? 0 : state.destination.length - 1;
    if (state.written < capacity)
    {
        const available = capacity - state.written;
        const amount = bytes.length < available ? bytes.length : available;
        if (amount != 0)
            memcpy(state.destination.ptr + state.written, bytes.ptr, amount);
        state.written += amount;
    }
    if (state.destination.length != 0)
        state.destination[state.written] = '\0';

    return bytes.length;
}

private void finishFixedBuffer(FixedBufferState* state)
@trusted
{
    version (XTB_Checked)
        require(state !is null, "fixed buffer state is null");
    while (state.written != 0 &&
        !isValidUtf8(cast(String) state.destination[0 .. state.written]))
        --state.written;
    if (state.destination.length != 0)
        state.destination[state.written] = '\0';
}

WriteResult write(Args...)(auto ref Args args)
{
    return writeFile(cast(FILE*) stdout, args);
}

WriteResult writeln(Args...)(auto ref Args args)
{
    return writelnFile(cast(FILE*) stdout, args);
}

WriteResult ewrite(Args...)(auto ref Args args)
{
    return writeFile(cast(FILE*) stderr, args);
}

WriteResult ewriteln(Args...)(auto ref Args args)
{
    return writelnFile(cast(FILE*) stderr, args);
}

WriteResult writeFile(Args...)(FILE* file, auto ref Args args)
{
    Writer writer = fileWriter(file);
    writer.write(args);
    return writer.result;
}

WriteResult writelnFile(Args...)(FILE* file, auto ref Args args)
{
    Writer writer = fileWriter(file);
    writer.writeln(args);
    return writer.result;
}

BufferWriteResult writeBuffer(Args...)(char[] destination, auto ref Args args)
{
    FixedBufferState state;
    state.destination = destination;
    if (destination.length != 0)
        destination[0] = '\0';

    Writer writer = Writer.fromSink(&fixedBufferSink, &state);
    writer.write(args);
    const result = writer.result;
    finishFixedBuffer(&state);
    return BufferWriteResult(
        result.ok && !state.overflow,
        state.overflow || state.required > state.written,
        state.written,
        state.required,
    );
}

BufferWriteResult formatBuffer(string pattern, Args...)(
    char[] destination,
    auto ref Args args,
)
{
    FixedBufferState state;
    state.destination = destination;
    if (destination.length != 0)
        destination[0] = '\0';

    Writer writer = Writer.fromSink(&fixedBufferSink, &state);
    writer.format!pattern(args);
    const result = writer.result;
    finishFixedBuffer(&state);
    return BufferWriteResult(
        result.ok && !state.overflow,
        state.overflow || state.required > state.written,
        state.written,
        state.required,
    );
}

BufferWriteResult formatBuffer(Sequence...)(
    char[] destination,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    FixedBufferState state;
    state.destination = destination;
    if (destination.length != 0)
        destination[0] = '\0';

    Writer writer = Writer.fromSink(&fixedBufferSink, &state);
    writer.format(header, sequence, footer);
    const result = writer.result;
    finishFixedBuffer(&state);
    return BufferWriteResult(
        result.ok && !state.overflow,
        state.overflow || state.required > state.written,
        state.written,
        state.required,
    );
}

bool tryFormatString(string pattern, Args...)(
    Allocator* allocator,
    StringBuf* output,
    auto ref Args args,
)
{
    version (XTB_Checked)
        require(output !is null, "StringBuf output pointer is null");
    output.deinit();

    StringBuf fresh = StringBuf.create(allocator);
    if (!fresh.tryFormat!pattern(args))
    {
        fresh.deinit();
        return false;
    }
    moveEmplace(fresh, *output);
    return true;
}

bool tryFormatString(Sequence...)(
    Allocator* allocator,
    StringBuf* output,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    version (XTB_Checked)
        require(output !is null, "StringBuf output pointer is null");
    output.deinit();

    StringBuf fresh = StringBuf.create(allocator);
    if (!fresh.tryFormat(header, sequence, footer))
    {
        fresh.deinit();
        return false;
    }
    moveEmplace(fresh, *output);
    return true;
}

StringBuf formatString(string pattern, Args...)(
    Allocator* allocator,
    auto ref Args args,
)
{
    StringBuf result;
    if (!tryFormatString!pattern(allocator, &result, args))
        panic("String formatting failed");
    return move(result);
}

StringBuf formatString(Sequence...)(
    Allocator* allocator,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    StringBuf result;
    if (!tryFormatString(allocator, &result, header, sequence, footer))
        panic("String formatting failed");
    return move(result);
}

WriteResult format(string pattern, Args...)(auto ref Args args)
{
    Writer writer = fileWriter(cast(FILE*) stdout);
    writer.format!pattern(args);
    return writer.result;
}

WriteResult format(Sequence...)(
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    Writer writer = fileWriter(cast(FILE*) stdout);
    writer.format(header, sequence, footer);
    return writer.result;
}

WriteResult formatln(string pattern, Args...)(auto ref Args args)
{
    Writer writer = fileWriter(cast(FILE*) stdout);
    writer.formatln!pattern(args);
    return writer.result;
}

WriteResult formatln(Sequence...)(
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    Writer writer = fileWriter(cast(FILE*) stdout);
    writer.formatln(header, sequence, footer);
    return writer.result;
}

bool flushStdout()
{
    return fflush(cast(FILE*) stdout) == 0;
}

bool flushStderr()
{
    return fflush(cast(FILE*) stderr) == 0;
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

    StringBuf buffer = StringBuf.create(mallocAllocator());
    int answer = 42;
    buffer.write("answer=", answer, ", hex=", hexadecimal(255));
    assert(buffer == "answer=42, hex=0xff");
    const uint constantInteger = 255;
    const double constantFloat = 1.25;
    buffer.clear();
    buffer.write(
        hexadecimal(constantInteger).upper,
        ", ",
        fixed(constantFloat, 2),
    );
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

    // StringBuf can be exposed as an immediate generic Writer. Bytes are visible
    // as soon as each writer call returns; there is no finish obligation.
    char[511] splitScalarPrefix;
    splitScalarPrefix[] = 'a';
    const String splitScalarPrefixString = splitScalarPrefix[];

    buffer.clear();
    Writer bufferWriter = buffer.writer();
    bufferWriter.put(splitScalarPrefixString);
    bufferWriter.put("🙂");
    assert(bufferWriter.result.ok);
    assert(bufferWriter.result.written == 515);
    assert(buffer.byteLength == 515);
    assert(buffer.view[0 .. 511] == splitScalarPrefixString);
    assert(buffer.view[511 .. $] == "🙂");

    buffer.clear();
    Writer headerWriter = buffer.writer();
    writeHeader(headerWriter, "HTTP");
    headerWriter.writeln("status=", 200);
    assert(headerWriter.ok);
    assert(buffer == "[HTTP] status=200\n");

    StringBuf fallibleSplitScalar;
    assert(tryFormatString!"{}{}"(
            mallocAllocator(),
            &fallibleSplitScalar,
            splitScalarPrefixString,
            "🙂",
    ));
    assert(fallibleSplitScalar.byteLength == 515);
    assert(fallibleSplitScalar.view[511 .. $] == "🙂");

    char[8] fixedBuffer;
    const result = fixedBuffer[].writeBuffer("abcdefghi");
    assert(result.ok);
    assert(result.truncated);
    assert(result.written == 7);
    assert(result.required == 9);
    assert(fixedBuffer[7] == '\0');

    char[4] truncatedScalar;
    const scalarResult = truncatedScalar[].writeBuffer("A🙂");
    assert(scalarResult.ok);
    assert(scalarResult.truncated);
    assert(scalarResult.written == 1);
    assert(scalarResult.required == 5);
    assert(truncatedScalar[0 .. 1] == "A");
    assert(truncatedScalar[1] == '\0');

    char[6] exactScalar;
    const exactScalarResult = exactScalar[].writeBuffer("A🙂");
    assert(exactScalarResult.ok);
    assert(!exactScalarResult.truncated);
    assert(exactScalarResult.written == 5);
    assert(exactScalarResult.required == 5);
    assert(exactScalar[0 .. 5] == "A🙂");

    StringBuf allocated = formatString!"{}:{}"(mallocAllocator(), "item", 9);
    assert(allocated == "item:9");
    buffer.clear();
    buffer.write("owned=", allocated);
    assert(buffer == "owned=item:9");

    struct StatefulValue
    {
    nothrow @nogc:

        size_t* calls;

        void formatTo(ref Writer writer)
        {
            ++*calls;
            writer.put("stateful");
        }
    }

    size_t calls;
    StatefulValue value = StatefulValue(&calls);
    StringBuf stateful = formatString!"{}"(
        mallocAllocator(),
        value,
    );
    assert(stateful == "stateful");
    assert(calls == 1);

    buffer.clear();
    buffer.write(i"answer=$(answer), hex=$(hexadecimal(answer))");
    assert(buffer == "answer=42, hex=0x2a");

    struct CountedExpression
    {
    nothrow @nogc:

        size_t* evaluations;

        int evaluate()
        {
            ++*evaluations;
            return 7;
        }
    }

    size_t evaluations;
    CountedExpression counted = CountedExpression(&evaluations);
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
    buffer.write(
        i"expanded=$(InterpolationTestSequence!(answer, answer))",
    );
    assert(buffer == "expanded=4242");

    buffer.clear();
    buffer.write(i"");
    assert(buffer.empty);

    char[12] interpolatedFixed;
    const interpolatedFixedResult = interpolatedFixed[].formatBuffer(
        i"value=$(answer)",
    );
    assert(interpolatedFixedResult.ok);
    assert(!interpolatedFixedResult.truncated);
    assert(interpolatedFixedResult.written == 8);
    assert(interpolatedFixedResult.required == 8);
    assert(interpolatedFixed[0 .. 8] == "value=42");
    assert(interpolatedFixed[8] == '\0');

    char[8] truncatedInterpolation;
    const truncatedInterpolationResult = truncatedInterpolation[].formatBuffer(
        i"value=$(answer)",
    );
    assert(truncatedInterpolationResult.ok);
    assert(truncatedInterpolationResult.truncated);
    assert(truncatedInterpolationResult.written == 7);
    assert(truncatedInterpolationResult.required == 8);
    assert(truncatedInterpolation[0 .. 7] == "value=4");
    assert(truncatedInterpolation[7] == '\0');

    StringBuf interpolated = formatString(
        mallocAllocator(),
        i"owned: $(answer), $(fixed(1.25, 2))",
    );
    assert(interpolated == "owned: 42, 1.25");

    StringBuf fallibleInterpolated;
    assert(tryFormatString(
            mallocAllocator(),
            &fallibleInterpolated,
            i"try: $(binary(5))",
    ));
    assert(fallibleInterpolated == "try: 0b101");

    AllocationRecord[4] transactionalRecords;
    InstrumentedAllocator transactionalAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        transactionalRecords[],
    );
    StringBuf transactional = StringBuf.withCapacity(
        transactionalAllocator.allocator,
        8,
    );
    transactional.write("keep");
    transactionalAllocator.failAfter(0);
    char[128] oversized;
    oversized[] = 'x';
    assert(!transactional.tryWrite("++", cast(String) oversized[]));
    assert(transactional == "keep");
    transactional.deinit();
    assert(transactionalAllocator.clean);

    AllocationRecord[4] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    failing.failAfter(0);
    StringBuf failedInterpolated;
    assert(!tryFormatString(
            failing.allocator,
            &failedInterpolated,
            i"allocation required: $(answer)",
    ));
    assert(failedInterpolated.empty);
    assert(failing.clean);

    failedInterpolated.deinit();
    fallibleInterpolated.deinit();
    interpolated.deinit();
    stateful.deinit();
    allocated.deinit();
    fallibleSplitScalar.deinit();
    buffer.deinit();
}
