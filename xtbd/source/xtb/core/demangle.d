module xtb.core.demangle;

import xtb.core.string : String, equal;

private enum maxRecursion = 64;

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

private struct FunctionAttributes
{
    bool pure_;
    bool nothrow_;
    bool ref_;
    bool property;
    bool nogc;
    bool return_;
    bool scope_;
    bool trusted;
    bool safe;
    bool live;
}

private struct Demangler
{
    String input;
    size_t offset;
    size_t recursion;
    size_t lastTemplateName;
    bool hasLastTemplateName;
    DemangleWriter output;

    bool consume(char value) pure nothrow @system @nogc
    {
        if (offset == input.length || input[offset] != value)
            return false;
        ++offset;
        return true;
    }

    bool startsWith(String value) pure nothrow @system @nogc
    {
        return value.length <= input.length - offset &&
            input[offset .. offset + value.length].equal(value);
    }

    bool qualifiedName() nothrow @system @nogc
    {
        bool found;
        while (symbolNameStart())
        {
            if (found && repeatedTemplateFunctionName())
            {
                size_t ignored;
                if (!backReferenceTarget(&ignored))
                    return false;
                continue;
            }
            if (found)
                output.put('.');
            if (!symbolName())
                return false;
            found = true;
        }
        return found && !output.failed;
    }

    bool symbolNameStart() pure nothrow @system @nogc
    {
        if (offset >= input.length)
            return false;
        if (digit(input[offset]) || input[offset] == '0')
            return true;
        if (startsWith("__T") || startsWith("__U"))
            return true;
        return input[offset] == 'Q' && backReferenceTargetsIdentifier();
    }

    bool symbolName() nothrow @system @nogc
    {
        if (startsWith("__T") || startsWith("__U"))
            return templateName();
        if (offset < input.length && input[offset] == 'Q')
            return identifierBackReference();
        if (consume('0'))
        {
            output.put("<anonymous>");
            return true;
        }
        return lengthName();
    }

    bool lengthName() nothrow @system @nogc
    {
        size_t length;
        if (!number(&length) || length == 0 || length > input.length - offset)
            return false;
        output.put(input[offset .. offset + length]);
        offset += length;
        return !output.failed;
    }

    bool templateName() nothrow @system @nogc
    {
        offset += 3;
        lastTemplateName = offset;
        hasLastTemplateName = true;
        if (!lengthName())
            return false;
        output.put("!(");
        bool first = true;
        while (offset < input.length && input[offset] != 'Z')
        {
            if (!first)
                output.put(", ");
            if (!templateArgument())
                return false;
            first = false;
        }
        if (!consume('Z'))
            return false;
        output.put(')');
        return !output.failed;
    }

    bool repeatedTemplateFunctionName() pure nothrow @system @nogc
    {
        if (!hasLastTemplateName || offset >= input.length || input[offset] != 'Q')
            return false;
        const savedOffset = offset;
        size_t target;
        if (!backReferenceTarget(&target))
        {
            offset = savedOffset;
            return false;
        }
        const followsWithFunction = offset < input.length &&
            (callConvention(input[offset]) || input[offset] == 'M');
        offset = savedOffset;
        return target == lastTemplateName && followsWithFunction;
    }

    bool templateArgument() nothrow @system @nogc
    {
        if (consume('H'))
            output.put("specialized ");
        if (consume('T'))
            return type();
        if (consume('V'))
        {
            char[1024] ignoredType;
            DemangleWriter savedOutput = output;
            output = DemangleWriter(ignoredType[]);
            const validType = type();
            output = savedOutput;
            if (!validType)
                return false;
            return value();
        }
        if (consume('S'))
            return startsWith("_D") ? mangledName() : qualifiedName();
        if (consume('X'))
        {
            size_t length;
            if (!number(&length) || length > input.length - offset)
                return false;
            output.put(input[offset .. offset + length]);
            offset += length;
            return true;
        }
        return false;
    }

    bool value() nothrow @system @nogc
    {
        if (consume('n'))
        {
            output.put("null");
            return true;
        }
        if (consume('i'))
            return copyNumber(false);
        if (consume('N'))
            return copyNumber(true);
        if (offset < input.length &&
            (input[offset] == 'a' || input[offset] == 'w' || input[offset] == 'd'))
            return stringValue();
        if (consume('A') || consume('S'))
        {
            size_t count;
            if (!number(&count))
                return false;
            output.put('[');
            foreach (index; 0 .. count)
            {
                if (index != 0)
                    output.put(", ");
                if (!value())
                    return false;
            }
            output.put(']');
            return true;
        }
        if (consume('f'))
        {
            output.put('&');
            return mangledName();
        }
        if (consume('e'))
            return floatingValue();
        if (consume('c'))
        {
            if (!floatingValue())
                return false;
            output.put(" + ");
            if (!consume('c'))
                return false;
            return floatingValue();
        }
        return false;
    }

    bool stringValue() nothrow @system @nogc
    {
        const widthCode = input[offset++];
        size_t characters;
        if (!number(&characters) || !consume('_'))
            return false;
        const codeUnits = widthCode == 'a' ? 1U : widthCode == 'w' ? 2U : 4U;
        if (characters > size_t.max / codeUnits / 2)
            return false;
        const hexLength = characters * codeUnits * 2;
        if (hexLength > input.length - offset)
            return false;
        output.put('"');
        output.put(input[offset .. offset + hexLength]);
        output.put('"');
        offset += hexLength;
        return !output.failed;
    }

    bool floatingValue() nothrow @system @nogc
    {
        const start = offset;
        while (offset < input.length &&
            (hexDigit(input[offset]) || input[offset] == 'N' ||
                input[offset] == 'I' || input[offset] == 'P'))
            ++offset;
        if (offset == start)
            return false;
        output.put(input[start .. offset]);
        return !output.failed;
    }

    bool copyNumber(bool negative) nothrow @system @nogc
    {
        const start = offset;
        size_t ignored;
        if (!number(&ignored))
            return false;
        if (negative)
            output.put('-');
        output.put(input[start .. offset]);
        return !output.failed;
    }

    bool number(size_t* result) pure nothrow @system @nogc
    {
        if (result is null || offset == input.length || !digit(input[offset]))
            return false;
        size_t numberValue;
        while (offset < input.length && digit(input[offset]))
        {
            const next = cast(size_t) (input[offset] - '0');
            if (numberValue > (size_t.max - next) / 10)
                return false;
            numberValue = numberValue * 10 + next;
            ++offset;
        }
        *result = numberValue;
        return true;
    }

    bool backReferenceTarget(size_t* target) pure nothrow @system @nogc
    {
        if (target is null || offset >= input.length || input[offset] != 'Q')
            return false;
        const referencePosition = offset++;
        size_t distance;
        bool finished;
        while (offset < input.length)
        {
            const character = input[offset++];
            size_t digitValue;
            if (character >= 'A' && character <= 'Z')
                digitValue = cast(size_t) (character - 'A');
            else if (character >= 'a' && character <= 'z')
            {
                digitValue = cast(size_t) (character - 'a');
                finished = true;
            }
            else
                return false;
            if (distance > (size_t.max - digitValue) / 26)
                return false;
            distance = distance * 26 + digitValue;
            if (finished)
                break;
        }
        if (!finished || distance == 0 || distance > referencePosition)
            return false;
        *target = referencePosition - distance;
        return *target < input.length;
    }

    bool backReferenceTargetsIdentifier() pure nothrow @system @nogc
    {
        const savedOffset = offset;
        size_t target;
        const valid = backReferenceTarget(&target);
        offset = savedOffset;
        return valid && digit(input[target]);
    }

    bool identifierBackReference() nothrow @system @nogc
    {
        const referenceOffset = offset;
        size_t target;
        if (!backReferenceTarget(&target) || !digit(input[target]))
            return false;
        const afterReference = offset;
        if (++recursion > maxRecursion)
            return false;
        offset = target;
        const result = lengthName();
        --recursion;
        offset = afterReference;
        return result && referenceOffset != target;
    }

    bool typeBackReference() nothrow @system @nogc
    {
        size_t target;
        if (!backReferenceTarget(&target) || digit(input[target]))
            return false;
        const afterReference = offset;
        if (++recursion > maxRecursion)
            return false;
        offset = target;
        const result = type();
        --recursion;
        offset = afterReference;
        return result;
    }

    bool functionType(bool hasReturn = true, String callable = null)
        nothrow @system @nogc
    {
        String memberQualifier;
        if (offset < input.length && input[offset] == 'M')
        {
            ++offset;
            if (consume('x')) memberQualifier = " const";
            else if (consume('y')) memberQualifier = " immutable";
            else if (consume('O'))
            {
                if (consume('x')) memberQualifier = " shared const";
                else if (startsWith("Ng"))
                {
                    offset += 2;
                    memberQualifier = " shared inout";
                }
                else memberQualifier = " shared";
            }
            else if (startsWith("Ng"))
            {
                offset += 2;
                memberQualifier = " inout";
            }
        }
        if (offset >= input.length || !callConvention(input[offset]))
            return false;
        const convention = input[offset++];
        FunctionAttributes attributes;
        if (!functionAttributes(&attributes))
            return false;

        if (callable.length != 0)
            output.put(callable);
        output.put('(');
        bool first = true;
        char close;
        while (offset < input.length)
        {
            if (input[offset] == 'X' || input[offset] == 'Y' || input[offset] == 'Z')
            {
                close = input[offset++];
                break;
            }
            if (!first)
                output.put(", ");
            if (!parameter())
                return false;
            first = false;
        }
        if (close == '\0')
            return false;
        if (close != 'Z')
        {
            if (!first)
                output.put(", ");
            output.put(close == 'X' ? "..." : "TypeInfo[]...");
        }
        output.put(')');
        output.put(memberQualifier);
        if (hasReturn)
        {
            output.put(" -> ");
            if (!type())
                return false;
        }
        writeFunctionSuffix(attributes, convention);
        return !output.failed;
    }

    bool functionAttributes(FunctionAttributes* attributes)
        pure nothrow @system @nogc
    {
        while (offset + 1 < input.length && input[offset] == 'N')
        {
            const code = input[offset + 1];
            switch (code)
            {
                case 'a': attributes.pure_ = true; break;
                case 'b': attributes.nothrow_ = true; break;
                case 'c': attributes.ref_ = true; break;
                case 'd': attributes.property = true; break;
                case 'e': attributes.trusted = true; break;
                case 'f': attributes.safe = true; break;
                case 'i': attributes.nogc = true; break;
                case 'j': attributes.return_ = true; break;
                case 'l': attributes.scope_ = true; break;
                case 'm': attributes.live = true; break;
                default: return true;
            }
            offset += 2;
        }
        return true;
    }

    void writeFunctionSuffix(FunctionAttributes attributes, char convention)
        nothrow @system @nogc
    {
        if (attributes.pure_) output.put(" pure");
        if (attributes.nothrow_) output.put(" nothrow");
        if (attributes.ref_) output.put(" ref");
        if (attributes.property) output.put(" @property");
        if (attributes.nogc) output.put(" @nogc");
        if (attributes.return_) output.put(" return");
        if (attributes.scope_) output.put(" scope");
        if (attributes.trusted) output.put(" @trusted");
        if (attributes.safe) output.put(" @safe");
        if (attributes.live) output.put(" @live");
        switch (convention)
        {
            case 'U': output.put(" extern(C)"); break;
            case 'W': output.put(" extern(Windows)"); break;
            case 'R': output.put(" extern(C++)"); break;
            case 'Y': output.put(" extern(Objective-C)"); break;
            default: break;
        }
    }

    bool parameter() nothrow @system @nogc
    {
        if (consume('M'))
            output.put("scope ");
        else if (startsWith("Nk"))
        {
            offset += 2;
            output.put("return ");
        }
        if (consume('I')) output.put("in ");
        else if (consume('J')) output.put("out ");
        else if (consume('K')) output.put("ref ");
        else if (consume('L')) output.put("lazy ");
        return type();
    }

    bool type() nothrow @system @nogc
    {
        if (offset >= input.length)
            return false;
        if (input[offset] == 'Q')
            return typeBackReference();
        if (startsWith("Ng"))
        {
            offset += 2;
            return wrapped("inout(", ")");
        }
        if (consume('O'))
        {
            if (consume('x')) return wrapped("shared const(", ")");
            if (startsWith("Ng"))
            {
                offset += 2;
                return wrapped("shared inout(", ")");
            }
            return wrapped("shared(", ")");
        }
        if (consume('x')) return wrapped("const(", ")");
        if (consume('y')) return wrapped("immutable(", ")");
        if (startsWith("Nn"))
        {
            offset += 2;
            output.put("noreturn");
            return true;
        }
        if (startsWith("Nh"))
        {
            offset += 2;
            return wrapped("__vector(", ")");
        }
        if (startsWith("zi"))
        {
            offset += 2;
            output.put("cent");
            return true;
        }
        if (startsWith("zk"))
        {
            offset += 2;
            output.put("ucent");
            return true;
        }

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
            case 'o': output.put("ifloat"); return true;
            case 'p': output.put("idouble"); return true;
            case 'j': output.put("ireal"); return true;
            case 'q': output.put("cfloat"); return true;
            case 'r': output.put("cdouble"); return true;
            case 'c': output.put("creal"); return true;
            case 'n': output.put("typeof(null)"); return true;
            case 'P':
                if (offset < input.length &&
                    (callConvention(input[offset]) || input[offset] == 'M'))
                    return type();
                return postfix("*");
            case 'A': return postfix("[]");
            case 'G': return staticArray();
            case 'H': return associativeArray();
            case 'I':
            case 'S':
            case 'C':
            case 'E':
            case 'T': return qualifiedName();
            case 'D':
                skipTypeModifiers();
                return functionType(true, "delegate");
            case 'B': return tupleType();
            case 'F':
            case 'U':
            case 'W':
            case 'R':
            case 'Y':
                --offset;
                return functionType(true, "function");
            default: return false;
        }
    }

    bool postfix(String suffix) nothrow @system @nogc
    {
        if (!type())
            return false;
        output.put(suffix);
        return !output.failed;
    }

    bool staticArray() nothrow @system @nogc
    {
        const numberStart = offset;
        size_t length;
        if (!number(&length))
            return false;
        const numberEnd = offset;
        if (!type())
            return false;
        output.put('[');
        output.put(input[numberStart .. numberEnd]);
        output.put(']');
        return !output.failed;
    }

    bool associativeArray() nothrow @system @nogc
    {
        char[1024] keyStorage;
        DemangleWriter savedOutput = output;
        output = DemangleWriter(keyStorage[]);
        if (!type())
        {
            output = savedOutput;
            return false;
        }
        const key = keyStorage[0 .. output.written];
        output = savedOutput;
        if (!type())
            return false;
        output.put('[');
        output.put(key);
        output.put(']');
        return !output.failed;
    }

    bool tupleType() nothrow @system @nogc
    {
        output.put("Tuple!(");
        bool first = true;
        while (offset < input.length && input[offset] != 'Z')
        {
            if (!first)
                output.put(", ");
            if (!parameter())
                return false;
            first = false;
        }
        if (!consume('Z'))
            return false;
        output.put(')');
        return !output.failed;
    }

    bool wrapped(String prefix, String suffix) nothrow @system @nogc
    {
        output.put(prefix);
        if (!type())
            return false;
        output.put(suffix);
        return !output.failed;
    }

    void skipTypeModifiers() pure nothrow @system @nogc
    {
        bool progress = true;
        while (progress)
        {
            progress = false;
            if (offset < input.length &&
                (input[offset] == 'x' || input[offset] == 'y' || input[offset] == 'O'))
            {
                ++offset;
                progress = true;
            }
            else if (offset + 1 < input.length && input[offset] == 'N' &&
                input[offset + 1] == 'g')
            {
                offset += 2;
                progress = true;
            }
        }
    }

    bool mangledName() nothrow @system @nogc
    {
        if (!startsWith("_D"))
            return false;
        offset += 2;
        if (!qualifiedName())
            return false;
        if (consume('Z'))
            return true;
        if (offset < input.length &&
            (callConvention(input[offset]) || input[offset] == 'M'))
            return functionType();
        return type();
    }
}

private bool digit(char value) pure nothrow @safe @nogc
{
    return value >= '0' && value <= '9';
}

private bool hexDigit(char value) pure nothrow @safe @nogc
{
    return digit(value) || (value >= 'A' && value <= 'F');
}

private bool callConvention(char value) pure nothrow @safe @nogc
{
    return value == 'F' || value == 'U' || value == 'W' ||
        value == 'R' || value == 'Y';
}

version (unittest)
private int generatedSignature(
    ref const(int)[],
    int[String],
    int delegate(float),
    int function(long),
    int[4],
    shared const(int)*,
) pure nothrow @nogc
{
    return 0;
}

version (unittest)
private int generatedTemplate(int value, T)(T input) pure nothrow @nogc
{
    return value + cast(int) input;
}

version (unittest)
private bool generatedAliasTarget(scope const(float)[]) pure nothrow @nogc
{
    return true;
}

version (unittest)
private int generatedAliasTemplate(alias target)() pure nothrow @nogc
{
    return target(null) ? 1 : 0;
}

version (unittest)
private bool containsEllipsis(String value) pure nothrow @safe @nogc
{
    if (value.length < 3)
        return false;
    foreach (index; 0 .. value.length - 2)
        if (value[index .. index + 3] == "...")
            return true;
    return false;
}

version (unittest)
private bool containsText(String value, String needle) pure nothrow @system @nogc
{
    if (needle.length > value.length)
        return false;
    foreach (offset; 0 .. value.length - needle.length + 1)
        if (value[offset .. offset + needle.length].equal(needle))
            return true;
    return false;
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
    if (demangler.offset < mangled.length)
    {
        if (mangled[demangler.offset] == 'Z')
            ++demangler.offset;
        else if (callConvention(mangled[demangler.offset]) ||
            mangled[demangler.offset] == 'M')
        {
            if (!demangler.functionType())
                return false;
        }
        else if (!demangler.type())
            return false;
    }
    if (demangler.offset != mangled.length || demangler.output.failed)
        return false;
    *result = storage[0 .. demangler.output.written];
    return true;
}

nothrow @nogc unittest
{
    char[2048] storage;
    String result;
    assert(tryDemangleD(
        "_D8examples15stacktrace_demo9loadSceneFNbNiKS3xtb4core" ~
            "10stacktrace17StackTraceContextAxaZi",
        storage[],
        &result,
    ));
    assert(result.equal(
        "examples.stacktrace_demo.loadScene(ref xtb.core.stacktrace." ~
            "StackTraceContext, const(char)[]) -> int nothrow @nogc",
    ));

    assert(tryDemangleD(
        "_D8examples15stacktrace_demo16buildRenderGraphFNbNiKS3xtb4core" ~
            "10stacktrace17StackTraceContextKSQDpQDj12AssetRequestPiZi",
        storage[],
        &result,
    ));
    assert(result.equal(
        "examples.stacktrace_demo.buildRenderGraph(ref xtb.core.stacktrace." ~
            "StackTraceContext, ref examples.stacktrace_demo.AssetRequest, " ~
            "int*) -> int nothrow @nogc",
    ));

    assert(tryDemangleD(
        "_D8examples15stacktrace_demo__T13dispatchTypedTiZQsFNbNiK" ~
            "S3xtb4core10stacktrace17StackTraceContextKSQDuQDo12AssetRequestMAxiZi",
        storage[],
        &result,
    ));
    assert(result.equal(
        "examples.stacktrace_demo.dispatchTyped!(int)(ref " ~
            "xtb.core.stacktrace.StackTraceContext, ref examples.stacktrace_demo." ~
            "AssetRequest, scope const(int)[]) -> int nothrow @nogc",
    ));

    assert(!tryDemangleD("_D999broken", storage[], &result));
    assert(result.equal("_D999broken"));
    assert(!tryDemangleD("not_a_d_symbol", storage[], &result));
    assert(result.equal("not_a_d_symbol"));

    char[0] empty;
    assert(!tryDemangleD("_D4mainFZi", empty[], &result));

    assert(tryDemangleD(generatedSignature.mangleof, storage[], &result));
    assert(!result.containsEllipsis);
    assert(result.length > "generatedSignature".length);
    assert(result.containsText("function(long) -> int"));
    assert(!result.containsText("function(long) -> int*"));

    alias generatedInstantiation = generatedTemplate!(7, long);
    assert(tryDemangleD(generatedInstantiation.mangleof, storage[], &result));
    assert(!result.containsEllipsis);
    assert(result.containsText("generatedTemplate!(7, long)"));

    alias generatedAliasInstantiation = generatedAliasTemplate!generatedAliasTarget;
    assert(tryDemangleD(generatedAliasInstantiation.mangleof, storage[], &result));
    assert(result.containsText("generatedAliasTarget("));
}
