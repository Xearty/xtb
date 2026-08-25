module xtb.log.internal.sgr;

nothrow @nogc:

import xtb.core.ansi : AnsiSequence;
import xtb.core.string : String;

package(xtb.log) enum SgrParseKind : ubyte
{
    unsupported,
    incomplete,
    complete,
}

package(xtb.log) struct SgrParseResult
{
    SgrParseKind kind;
    size_t length;
    bool fullReset;
}

package(xtb.log) enum maxSupportedSgrLength = AnsiSequence.capacity;

package(xtb.log) SgrParseResult parseSgrPrefix(scope String bytes)
pure @safe
{
    if (bytes.length == 0 || bytes[0] != '\x1b')
        return SgrParseResult(SgrParseKind.unsupported);
    if (bytes.length == 1)
        return SgrParseResult(SgrParseKind.incomplete);
    if (bytes[1] != '[')
        return SgrParseResult(SgrParseKind.unsupported);

    const limit = bytes.length < maxSupportedSgrLength
        ? bytes.length : maxSupportedSgrLength;
    foreach (index; 2 .. limit)
    {
        const value = cast(ubyte) bytes[index];
        if (value >= 0x40 && value <= 0x7e)
        {
            if (value != 'm')
                return SgrParseResult(SgrParseKind.unsupported);

            bool fullReset = true;
            foreach (parameter; bytes[2 .. index])
            {
                if (parameter != '0' && parameter != ';')
                {
                    fullReset = false;
                    break;
                }
            }
            return SgrParseResult(
                SgrParseKind.complete,
                index + 1,
                fullReset,
            );
        }

        const digit = value >= '0' && value <= '9';
        if (digit || value == ';' || value == ':')
            continue;
        return SgrParseResult(SgrParseKind.unsupported);
    }

    return bytes.length < maxSupportedSgrLength
        ? SgrParseResult(SgrParseKind.incomplete) : SgrParseResult(SgrParseKind.unsupported);
}

package(xtb.log) size_t safeSgrPrefixLength(scope String bytes)
pure @safe
{
    if (bytes.length == 0)
        return 0;

    const start = bytes.length > maxSupportedSgrLength
        ? bytes.length - maxSupportedSgrLength : 0;
    size_t index = bytes.length;
    while (index != start)
    {
        --index;
        if (bytes[index] != '\x1b')
            continue;

        const parsed = parseSgrPrefix(bytes[index .. $]);
        return parsed.kind == SgrParseKind.incomplete ? index : bytes.length;
    }
    return bytes.length;
}
