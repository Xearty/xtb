module xtb.log.internal.sgr;

nothrow @nogc:

import core.attribute;

import xtb.ansi;
import xtb.types;

package(xtb.log) enum SGRParseKind : u8
{
    unsupported,
    incomplete,
    complete,
}

@mustuse package(xtb.log) struct SGRParseResult
{
    SGRParseKind kind;
    usize length;
    bool full_reset;
}

package(xtb.log) enum max_supported_sgr_length = ANSISequence.capacity;

package(xtb.log) SGRParseResult parse_sgr_prefix(scope String bytes)
pure @safe
{
    if (bytes.length == 0 || bytes[0] != '\x1b') return SGRParseResult(SGRParseKind.unsupported);

    if (bytes.length == 1) return SGRParseResult(SGRParseKind.incomplete);

    if (bytes[1] != '[') return SGRParseResult(SGRParseKind.unsupported);

    const limit = bytes.length < max_supported_sgr_length
        ? bytes.length
        : max_supported_sgr_length;
    foreach (index; 2 .. limit)
    {
        const value = cast(u8) bytes[index];
        if (value >= 0x40 && value <= 0x7E)
        {
            if (value != 'm') return SGRParseResult(SGRParseKind.unsupported);

            bool full_reset = true;
            foreach (parameter; bytes[2 .. index])
            {
                if (parameter != '0' && parameter != ';')
                {
                    full_reset = false;
                    break;
                }
            }

            return SGRParseResult(
                SGRParseKind.complete,
                index + 1,
                full_reset,
            );
        }

        const is_digit = value >= '0' && value <= '9';
        if (is_digit || value == ';' || value == ':') continue;

        return SGRParseResult(SGRParseKind.unsupported);
    }

    return bytes.length < max_supported_sgr_length
        ? SGRParseResult(SGRParseKind.incomplete)
        : SGRParseResult(SGRParseKind.unsupported);
}

package(xtb.log) usize safe_sgr_prefix_length(scope String bytes)
pure @safe
{
    if (bytes.length == 0) return 0;

    const start = bytes.length > max_supported_sgr_length
        ? bytes.length - max_supported_sgr_length
        : 0;
    usize index = bytes.length;
    while (index != start)
    {
        --index;
        if (bytes[index] != '\x1b') continue;

        const SGRParseResult parsed = parse_sgr_prefix(bytes[index .. $]);
        return parsed.kind == SGRParseKind.incomplete ? index : bytes.length;
    }

    return bytes.length;
}
