module xtb.fmt.fixed_buffer;

nothrow @nogc:

import core.attribute;
import core.interpolation;
import core.stdc.string;

import xtb.fmt.writer;
import xtb.panic;
import xtb.types;
import xtb.utf8;

/// Outcome of writing formatted text into a fixed caller-owned buffer.
@mustuse struct BufferWriteResult
{
    bool ok;
    bool truncated;
    usize written;
    usize required;
}

private struct FixedBufferState
{
    char[] destination;
    usize written;
    usize required;
    bool overflow;
}

private usize fixed_buffer_sink(void* context, scope const(u8)[] bytes) @system
{
    auto state = cast(FixedBufferState*) context;
    if (state is null) return 0;

    if (bytes.length > usize.max - state.required)
        state.overflow = true;
    else
        state.required += bytes.length;

    const capacity = state.destination.length == 0 ? 0 : state.destination.length - 1;
    if (state.written < capacity)
    {
        const available = capacity - state.written;
        const amount = bytes.length < available ? bytes.length : available;
        if (amount != 0)
            cast(void) memcpy(state.destination.ptr + state.written, bytes.ptr, amount);
        state.written += amount;
    }
    if (state.destination.length != 0) state.destination[state.written] = '\0';

    return bytes.length;
}

private void finish_fixed_buffer(FixedBufferState* state) @safe
{
    require(state !is null, "fixed buffer state is null");
    while (
        state.written != 0
        && !is_valid_utf8(state.destination[0 .. state.written])
    )
    {
        --state.written;
    }
    if (state.destination.length != 0) state.destination[state.written] = '\0';
}

BufferWriteResult write_buffer(Args...)(char[] destination, auto ref Args args)
{
    auto state = FixedBufferState(destination: destination);
    if (destination.length != 0) destination[0] = '\0';

    auto writer = Writer.from_sink(&fixed_buffer_sink, &state);
    writer.write(args);
    const result = writer.result;
    finish_fixed_buffer(&state);
    return BufferWriteResult(
        result.ok && !state.overflow,
        state.overflow || state.required > state.written,
        state.written,
        state.required,
    );
}

BufferWriteResult format_buffer(String pattern, Args...)(
    char[] destination,
    auto ref Args args,
)
{
    auto state = FixedBufferState(destination: destination);
    if (destination.length != 0) destination[0] = '\0';

    auto writer = Writer.from_sink(&fixed_buffer_sink, &state);
    writer.format!pattern(args);
    const result = writer.result;
    finish_fixed_buffer(&state);
    return BufferWriteResult(
        result.ok && !state.overflow,
        state.overflow || state.required > state.written,
        state.written,
        state.required,
    );
}

BufferWriteResult format_buffer(Sequence...)(
    char[] destination,
    InterpolationHeader header,
    auto ref Sequence sequence,
    InterpolationFooter footer,
)
{
    auto state = FixedBufferState(destination: destination);
    if (destination.length != 0) destination[0] = '\0';

    auto writer = Writer.from_sink(&fixed_buffer_sink, &state);
    writer.format(header, sequence, footer);
    const result = writer.result;
    finish_fixed_buffer(&state);
    return BufferWriteResult(
        result.ok && !state.overflow,
        state.overflow || state.required > state.written,
        state.written,
        state.required,
    );
}
