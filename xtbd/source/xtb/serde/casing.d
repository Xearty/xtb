module xtb.serde.casing;

nothrow @nogc:

import xtb.core.print : Writer;
import xtb.core.types : String;
import xtb.serde.attributes : KeyCase;

private bool isLower(char value) pure @safe
{
    return value >= 'a' && value <= 'z';
}

private bool isUpper(char value) pure @safe
{
    return value >= 'A' && value <= 'Z';
}

private bool isDigit(char value) pure @safe
{
    return value >= '0' && value <= '9';
}

private bool isSeparator(char value) pure @safe
{
    return value == '_' || value == '-' || value == ' ';
}

private char lowerAscii(char value) pure @safe
{
    return isUpper(value) ? cast(char)(value + ('a' - 'A')) : value;
}

private char upperAscii(char value) pure @safe
{
    return isLower(value) ? cast(char)(value - ('a' - 'A')) : value;
}

private bool wordBoundary(String value, size_t index) pure @safe
{
    if (index == 0 || isSeparator(value[index]))
        return index != 0;
    const current = value[index];
    const previous = value[index - 1];
    if (isSeparator(previous))
        return true;
    if (isUpper(current) && (isLower(previous) || isDigit(previous)))
        return true;
    return isUpper(current) && isUpper(previous) && index + 1 < value.length &&
        isLower(value[index + 1]);
}

private char separatorFor(KeyCase casing) pure @safe
{
    return casing == KeyCase.kebab ? '-' : '_';
}

private struct CaseCursor
{
nothrow @nogc:

    String source;
    KeyCase casing;
    size_t index;
    bool emitted;
    bool pendingSeparator;
    bool boundaryEmitted;

    bool next(scope char* output) scope pure @trusted
    {
        while (index < source.length)
        {
            const at = index++;
            const value = source[at];
            if (isSeparator(value))
            {
                if (emitted)
                    pendingSeparator = true;
                continue;
            }

            const boundary = wordBoundary(source, at) && !boundaryEmitted;
            if ((casing == KeyCase.snake || casing == KeyCase.screamingSnake ||
                    casing == KeyCase.kebab) && emitted && (boundary || pendingSeparator))
            {
                pendingSeparator = false;
                boundaryEmitted = true;
                --index;
                *output = separatorFor(casing);
                return true;
            }

            pendingSeparator = false;
            boundaryEmitted = false;
            char converted = value;
            final switch (casing)
            {
                case KeyCase.schema:
                case KeyCase.preserve:
                    break;
                case KeyCase.camel:
                    converted = lowerAscii(value);
                    if (emitted && boundary)
                        converted = upperAscii(value);
                    break;
                case KeyCase.pascal:
                    converted = lowerAscii(value);
                    if (boundary || !emitted)
                        converted = upperAscii(value);
                    break;
                case KeyCase.snake:
                case KeyCase.kebab:
                    converted = lowerAscii(value);
                    break;
                case KeyCase.screamingSnake:
                    converted = upperAscii(value);
                    break;
            }
            emitted = true;
            *output = converted;
            return true;
        }
        return false;
    }
}

void writeCased(ref Writer writer, scope String value, KeyCase casing)
{
    CaseCursor cursor = CaseCursor(value, casing == KeyCase.schema
            ? KeyCase.preserve : casing);
    char character;
    while (cursor.next(&character))
        writer.put(character);
}

bool matchesCased(scope String candidate, scope String source, KeyCase casing)
pure @safe
{
    CaseCursor cursor = CaseCursor(source, casing == KeyCase.schema
            ? KeyCase.preserve : casing);
    size_t index;
    char character;
    while (cursor.next(&character))
    {
        if (index == candidate.length || candidate[index] != character)
            return false;
        ++index;
    }
    return index == candidate.length;
}

bool casedNamesEqual(
    scope String left,
    KeyCase leftCase,
    scope String right,
    KeyCase rightCase,
) pure @safe
{
    CaseCursor leftCursor = CaseCursor(left, leftCase == KeyCase.schema
            ? KeyCase.preserve : leftCase);
    CaseCursor rightCursor = CaseCursor(right, rightCase == KeyCase.schema
            ? KeyCase.preserve : rightCase);
    char leftCharacter;
    char rightCharacter;
    for (;;)
    {
        const hasLeft = leftCursor.next(&leftCharacter);
        const hasRight = rightCursor.next(&rightCharacter);
        if (hasLeft != hasRight)
            return false;
        if (!hasLeft)
            return true;
        if (leftCharacter != rightCharacter)
            return false;
    }
}

unittest
{
    assert(matchesCased("http_server_id", "HTTPServerID", KeyCase.snake));
    assert(matchesCased("HTTP_SERVER_ID", "HTTPServerID", KeyCase.screamingSnake));
    assert(matchesCased("http-server-id", "HTTPServerID", KeyCase.kebab));
    assert(matchesCased("httpServerId", "HTTP_server-ID", KeyCase.camel));
    assert(matchesCased("HttpServerId", "http_server_id", KeyCase.pascal));
}
