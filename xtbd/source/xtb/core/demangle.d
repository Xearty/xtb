module xtb.core.demangle;

import xtb.core.string : String, equal;

private struct DemangleWriter
{
    char[] storage;
    size_t written;
    bool failed;

    void put(char value) nothrow @system @nogc
    {
        if (written == storage.length)
        {
            failed = true;
            return;
        }
        storage[written++] = value;
    }

    void put(String value) nothrow @system @nogc
    {
        if (value.length > storage.length - written)
        {
            failed = true;
            return;
        }
        foreach (character; value)
            storage[written++] = character;
    }
}

private struct Demangler
{
    String input;
    size_t offset;
    DemangleWriter output;

    bool consume(char value) pure nothrow @system @nogc
    {
        if (offset == input.length || input[offset] != value)
            return false;
        ++offset;
        return true;
    }

    bool qualifiedName() nothrow @system @nogc
    {
        bool found;
        while (offset < input.length && digit(input[offset]))
        {
            size_t length;
            if (!number(&length) || length == 0 || length > input.length - offset)
                return false;
            if (found)
                output.put('.');
            output.put(input[offset .. offset + length]);
            offset += length;
            found = true;
        }
        if (found && offset + 3 <= input.length &&
            input[offset .. offset + 3].equal("__T"))
        {
            output.put('.');
            if (!templateName())
                return false;
        }
        return found && !output.failed;
    }

    bool templateName() nothrow @system @nogc
    {
        offset += 3;
        size_t length;
        if (!number(&length) || length == 0 || length > input.length - offset)
            return false;
        output.put(input[offset .. offset + length]);
        offset += length;
        output.put("!(...)");

        size_t nesting = 1;
        while (offset < input.length && nesting != 0)
        {
            if (input[offset] == 'Z')
                --nesting;
            else if (offset + 3 <= input.length &&
                input[offset .. offset + 3].equal("__T"))
                ++nesting;
            ++offset;
        }
        if (nesting != 0)
            return false;
        if (offset < input.length && input[offset] == 'Q')
        {
            ++offset;
            while (offset < input.length && input[offset] != 'F' &&
                input[offset] != 'M')
                ++offset;
        }
        return !output.failed;
    }

    bool number(size_t* result) pure nothrow @system @nogc
    {
        if (result is null || offset == input.length || !digit(input[offset]))
            return false;
        size_t value;
        while (offset < input.length && digit(input[offset]))
        {
            const next = cast(size_t) (input[offset] - '0');
            if (value > (size_t.max - next) / 10)
                return false;
            value = value * 10 + next;
            ++offset;
        }
        *result = value;
        return true;
    }

    bool functionType() nothrow @system @nogc
    {
        // Member functions carry `M` immediately before their function type.
        if (offset < input.length && input[offset] == 'M')
            ++offset;
        if (!consume('F'))
            return offset == input.length;
        output.put('(');
        bool first = true;
        while (offset < input.length && input[offset] != 'Z')
        {
            skipFunctionAttribute();
            if (offset < input.length && input[offset] == 'Z')
                break;
            if (!first)
                output.put(", ");
            if (!parameter())
                return false;
            first = false;
        }
        if (!consume('Z'))
            return false;
        output.put(')');
        if (offset < input.length)
        {
            output.put(" -> ");
            if (!type())
                return false;
        }
        return offset == input.length && !output.failed;
    }

    void skipFunctionAttribute() pure nothrow @system @nogc
    {
        while (offset + 1 < input.length && input[offset] == 'N')
            offset += 2;
    }

    bool parameter() nothrow @system @nogc
    {
        if (offset == input.length)
            return false;
        switch (input[offset])
        {
            case 'J': output.put("out "); ++offset; break;
            case 'K': output.put("ref "); ++offset; break;
            case 'L': output.put("lazy "); ++offset; break;
            case 'M': output.put("scope "); ++offset; break;
            default: break;
        }
        return type();
    }

    bool type() nothrow @system @nogc
    {
        if (offset == input.length)
            return false;
        const code = input[offset++];
        switch (code)
        {
            case 'v': output.put("void"); return true;
            case 'b': output.put("bool"); return true;
            case 'g': output.put("byte"); return true;
            case 'h': output.put("ubyte"); return true;
            case 's': output.put("short"); return true;
            case 't': output.put("ushort"); return true;
            case 'i': output.put("int"); return true;
            case 'k': output.put("uint"); return true;
            case 'l': output.put("long"); return true;
            case 'm': output.put("ulong"); return true;
            case 'a': output.put("char"); return true;
            case 'u': output.put("wchar"); return true;
            case 'w': output.put("dchar"); return true;
            case 'f': output.put("float"); return true;
            case 'd': output.put("double"); return true;
            case 'e': output.put("real"); return true;
            case 'P':
                if (!type()) return false;
                output.put('*');
                return true;
            case 'A':
                if (!type()) return false;
                output.put("[]");
                return true;
            case 'x': return wrapped("const(", ")");
            case 'y': return wrapped("immutable(", ")");
            case 'O': return wrapped("shared(", ")");
            case 'S':
            case 'C':
            case 'E':
            case 'T':
                return qualifiedName();
            default:
                return false;
        }
    }

    bool wrapped(String prefix, String suffix) nothrow @system @nogc
    {
        output.put(prefix);
        if (!type())
            return false;
        output.put(suffix);
        return !output.failed;
    }
}

private bool digit(char value) pure nothrow @safe @nogc
{
    return value >= '0' && value <= '9';
}

bool tryDemangleD(
    String mangled,
    return scope char[] storage,
    return scope String* result,
) nothrow @system @nogc
{
    if (result is null)
        return false;
    *result = mangled;
    if (mangled.equal("_Dmain"))
    {
        if (storage.length < 4)
            return false;
        storage[0 .. 4] = "main";
        *result = storage[0 .. 4];
        return true;
    }
    if (mangled.length < 3 || !mangled[0 .. 2].equal("_D"))
        return false;

    Demangler demangler;
    demangler.input = mangled;
    demangler.offset = 2;
    demangler.output.storage = storage;
    if (!demangler.qualifiedName())
        return false;
    const nameLength = demangler.output.written;
    if (!demangler.functionType())
    {
        demangler.output.written = nameLength;
        demangler.output.failed = false;
        demangler.output.put("(...)");
        if (demangler.output.failed)
            return false;
    }
    *result = storage[0 .. demangler.output.written];
    return true;
}

nothrow @nogc unittest
{
    char[512] storage;
    String result;
    assert(tryDemangleD(
        "_D8examples15stacktrace_demo9loadSceneFNbNiKS3xtb4core10stacktrace17StackTraceContextZi",
        storage[],
        &result,
    ));
    assert(result.equal(
        "examples.stacktrace_demo.loadScene(ref xtb.core.stacktrace.StackTraceContext) -> int",
    ));
    assert(!tryDemangleD("_D999broken", storage[], &result));
    assert(result.equal("_D999broken"));
    assert(!tryDemangleD("not_a_d_symbol", storage[], &result));
    assert(result.equal("not_a_d_symbol"));

    char[0] empty;
    assert(!tryDemangleD("_D4mainFZi", empty[], &result));

    assert(tryDemangleD(
        "_D8examples15stacktrace_demo16buildRenderGraphFNbNiKS3xtb4core10stacktrace17StackTraceContextKSQDpQDj12AssetRequestPiZi",
        storage[],
        &result,
    ));
    assert(result.equal("examples.stacktrace_demo.buildRenderGraph(...)"));
}
