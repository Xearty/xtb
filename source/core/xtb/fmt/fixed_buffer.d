module xtb.fmt.fixed_buffer;

nothrow @nogc:

import core.interpolation : InterpolationFooter, InterpolationHeader;
import core.stdc.string : memcpy;
import xtb.fmt.writer : Writer;
import xtb.types : String, u8;
import xtb.utf8 : is_valid_utf8;

version (XTB_Checked) import xtb.panic : require;

struct BufferWriteResult
{
    bool ok;
    bool truncated;
    size_t written;
    size_t required;
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
        !is_valid_utf8(cast(String) state.destination[0 .. state.written]))
        --state.written;
    if (state.destination.length != 0)
        state.destination[state.written] = '\0';
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
