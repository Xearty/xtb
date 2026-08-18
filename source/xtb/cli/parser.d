module xtb.cli.parser;

nothrow @nogc:

import core.lifetime : emplace;
import core.stdc.stdio : stderr, stdout;
import core.stdc.string : strlen;
import xtb.cli.attributes;
import xtb.cli.traits;
import xtb.core.array : Array;
import xtb.core.lifetime : deinitValue = deinit, moveAssign, needsDeinit;
import xtb.core.memory : Allocator;
import xtb.core.option : Option;
import xtb.core.print : Writer;
import xtb.core.string : baseName;
import xtb.core.types : String;
import xtb.core.utf8 : isValidUtf8;

enum CliErrorKind : ubyte
{
    none,
    invalidUtf8,
    unknownOption,
    unknownCommand,
    missingOptionValue,
    invalidValue,
    missingRequiredOption,
    missingPositional,
    missingCommand,
    duplicateOption,
    unexpectedArgument,
    allocationFailed,
}

struct CliError
{
    CliErrorKind kind;
    size_t argumentIndex;
    String token;
    String detail;
    size_t commandDepth = size_t.max;
    size_t fieldIndex = size_t.max;
}

private enum CliOutcomeKind : ubyte
{
    invocation,
    help,
    version_,
    error,
}

private enum OptionMatch : ubyte
{
    noMatch,
    matched,
    failed,
}

private template childStorageSize(T)
{
    enum size_t childStorageSize = () {
        size_t result = 1;
        static foreach (Child; CommandTypes!T)
            if (ParsedCommand!Child.sizeof > result)
                result = ParsedCommand!Child.sizeof;
        return result;
    }();
}

private template childStorageAlignment(T)
{
    enum size_t childStorageAlignment = () {
        size_t result = 1;
        static foreach (Child; CommandTypes!T)
            if (ParsedCommand!Child.alignof > result)
                result = ParsedCommand!Child.alignof;
        return result;
    }();
}

/// One parsed command level. `args` contains this command's arguments and
/// `command!Child` provides typed access to the one selected direct child.
struct ParsedCommand(T)
{
nothrow @nogc:

    T args;

private:
    size_t childTag_;
    align(childStorageAlignment!T) ubyte[childStorageSize!T] childStorage_;

public:
    @disable this(this);
    @disable ref ParsedCommand opAssign(ParsedCommand source) return;

    /// Returns the selected direct child, or null when another/no child is active.
    ParsedCommand!Child* command(Child)() return @system if (isDirectCommand!(T, Child))
    {
        enum size_t index = directCommandIndex!(T, Child);
        return childTag_ == index + 1 ? childPointer!Child() : null;
    }

    const(ParsedCommand!Child)* command(Child)() const return @system if (isDirectCommand!(T, Child))
    {
        enum size_t index = directCommandIndex!(T, Child);
        return childTag_ == index + 1 ? childPointer!Child() : null;
    }

    bool hasCommand() const pure @safe
    {
        return childTag_ != 0;
    }

    void deinit() @system
    {
        if (childTag_ != 0)
        {
            static foreach (index, Child; CommandTypes!T)
            {
                if (childTag_ == index + 1)
                    childPointer!Child().deinit();
            }
            childTag_ = 0;
        }

        static if (needsDeinit!T)
            deinitValue(args);
    }

package(xtb.cli):
    ParsedCommand!Child* activateCommand(Child)() return @system if (isDirectCommand!(T, Child))
    {
        enum size_t index = directCommandIndex!(T, Child);
        childTag_ = index + 1;
        auto result = childPointer!Child();
        emplace(result);
        return result;
    }

private:
    ParsedCommand!Child* childPointer(Child)() return @system if (isDirectCommand!(T, Child))
    {
        return cast(ParsedCommand!Child*) childStorage_.ptr;
    }

    const(ParsedCommand!Child)* childPointer(Child)() const return @system
            if (isDirectCommand!(T, Child))
    {
        return cast(const(ParsedCommand!Child)*) childStorage_.ptr;
    }
}

/// Result of CLI parsing. Normal applications only need `hasInvocation`,
/// `invocation`, `handleCliResult`, and `deinit`.
struct CliParseResult(T)
{
nothrow @nogc:

    static assert(ValidateCliSchema!T);

private:
    CliOutcomeKind outcome_;
    CliError error_;
    String programName_;
    ParsedCommand!T invocation_;

public:
    @disable this(this);
    @disable ref CliParseResult opAssign(CliParseResult source) return;

    bool hasInvocation() const pure @safe
    {
        return outcome_ == CliOutcomeKind.invocation;
    }

    bool failed() const pure @safe
    {
        return outcome_ == CliOutcomeKind.error;
    }

    ref ParsedCommand!T invocation() return @system
    {
        return invocation_;
    }

    ref const(ParsedCommand!T) invocation() const return @system
    {
        return invocation_;
    }

    const(CliError)* error() const return pure @safe
    {
        return failed ? &error_ : null;
    }

    void deinit() @system
    {
        invocation_.deinit();
    }

package(xtb.cli):
    ref CliOutcomeKind outcome() return pure @safe
    {
        return outcome_;
    }

    ref CliError mutableError() return pure @safe
    {
        return error_;
    }

    ref String programName() return pure @safe
    {
        return programName_;
    }
}

private struct ArgumentSource
{
nothrow @nogc:
    String[] values;
    int argc;
    char** argv;
    bool cStyle;

    size_t length() const pure @safe
    {
        return cStyle ? (argc > 0 ? cast(size_t) argc : 0) : values.length;
    }

    String at(size_t index) const @trusted
    {
        if (!cStyle)
            return values[index];
        if (argv is null)
            return null;
        const(char)* pointer = argv[index];
        if (pointer is null)
            return null;
        return cast(String) pointer[0 .. strlen(pointer)];
    }
}

private struct ParseState
{
nothrow @nogc:
    ArgumentSource source;
    size_t index;
    Allocator* allocator;
    CliOutcomeKind outcome = CliOutcomeKind.invocation;
    CliError error;

    bool atEnd() const pure @safe
    {
        return index >= source.length;
    }

    String current() const @trusted
    {
        return source.at(index);
    }

    void fail(
        CliErrorKind kind,
        String token,
        String detail = null,
        size_t commandDepth = size_t.max,
        size_t fieldIndex = size_t.max,
    ) @safe
    {
        if (outcome == CliOutcomeKind.error)
            return;
        outcome = CliOutcomeKind.error;
        error.kind = kind;
        error.argumentIndex = index;
        error.token = token;
        error.detail = detail;
        error.commandDepth = commandDepth;
        error.fieldIndex = fieldIndex;
    }
}

private struct ParseFrame(T)
{
nothrow @nogc:
    ParsedCommand!T* node;
    bool[T.tupleof.length]* seen;
}

/// Parses process-style argc/argv without copying argument text.
CliParseResult!T parseArgs(T)(int argc, char** argv) @trusted if (!cliNeedsAllocator!T)
{
    ArgumentSource source;
    source.argc = argc;
    source.argv = argv;
    source.cStyle = true;
    return parseSource!T(source, null);
}

/// Parses process-style argc/argv using `allocator` for repeated arguments.
CliParseResult!T parseArgs(T)(int argc, char** argv, Allocator* allocator) @trusted
{
    ArgumentSource source;
    source.argc = argc;
    source.argv = argv;
    source.cStyle = true;
    return parseSource!T(source, allocator);
}

/// Parses a borrowed argv-style slice including argv[0].
CliParseResult!T parseArgs(T)(scope String[] argv) @trusted if (!cliNeedsAllocator!T)
{
    ArgumentSource source;
    source.values = argv;
    return parseSource!T(source, null);
}

/// Parses a borrowed argv-style slice including argv[0].
CliParseResult!T parseArgs(T)(scope String[] argv, Allocator* allocator) @trusted
{
    ArgumentSource source;
    source.values = argv;
    return parseSource!T(source, allocator);
}

pragma(inline, true)
private String normalizeProgramName(String programPath) @safe
{
    if (!isValidUtf8(programPath))
        return "program";

    String programName = programPath.baseName;
    return programName.length == 0 ? "program" : programName;
}

pragma(inline, true)
private CliParseResult!T parseSource(T)(ArgumentSource source, Allocator* allocator)
@system
{
    static assert(ValidateCliSchema!T);

    CliParseResult!T result;
    String programName = source.length == 0 ? String.init : source.at(0);
    result.programName = normalizeProgramName(programName);

    ParseState state;
    state.source = source;
    state.index = source.length == 0 ? 0 : 1;
    state.allocator = allocator;

    parseCommand!(T, T)(state, result.invocation_);
    result.outcome = state.outcome;
    result.mutableError = state.error;
    return result;
}

pragma(inline, true)
private void parseCommand(Root, T, Ancestors...)(
    ref ParseState state,
    ref ParsedCommand!T node,
    Ancestors ancestors,
) @system
{
    bool[T.tupleof.length] seen;
    ParseFrame!T currentFrame = ParseFrame!T(&node, &seen);
    size_t positionalOrdinal;
    bool optionsEnded;

    while (!state.atEnd && state.outcome == CliOutcomeKind.invocation)
    {
        const token = state.current;
        if (!isValidUtf8(token))
        {
            state.fail(CliErrorKind.invalidUtf8, token);
            return;
        }

        if (!optionsEnded && token == "--")
        {
            ++state.index;
            optionsEnded = true;
            continue;
        }

        static if (builtinHelpEnabled!Root)
        {
            if (!optionsEnded && token == "--help")
            {
                ++state.index;
                state.outcome = CliOutcomeKind.help;
                return;
            }
        }

        static if (is(Unqualified!T == Unqualified!Root) &&
            builtinVersionEnabled!Root)
        {
            if (!optionsEnded && token == "--version")
            {
                ++state.index;
                state.outcome = CliOutcomeKind.version_;
                return;
            }
        }

        if (!optionsEnded && token.length > 2 && token[0] == '-' && token[1] == '-')
        {
            if (!parseLongOption!(T)(state, currentFrame, ancestors))
                return;
            continue;
        }

        if (!optionsEnded && token.length > 1 && token[0] == '-')
        {
            if (!parseShortOptions!(Root, T)(state, currentFrame, ancestors))
                return;
            continue;
        }

        static if (hasSubcommands!T)
        {
            bool matched;
            static foreach (Child; CommandTypes!T)
            {
                if (!matched && token == commandName!Child)
                {
                    matched = true;
                    ++state.index;
                    auto child = node.activateCommand!Child();
                    parseCommand!(Root, Child)(
                        state,
                        *child,
                        ancestors,
                        currentFrame,
                    );
                }
            }
            if (!matched)
                state.fail(CliErrorKind.unknownCommand, token);
            return;
        }
        else
        {
            if (!parseNextPositional!T(
                    state,
                    currentFrame,
                    positionalOrdinal,
                    Ancestors.length,
                ))
                return;
            ++state.index;
        }
    }

    if (state.outcome != CliOutcomeKind.invocation)
        return;

    static foreach (index; 0 .. T.tupleof.length)
    {
        {
            static if (fieldHas!(T, index, Positional))
            {
                alias Field = FieldType!(T, index);
                enum requiredPositional = fieldHas!(T, index, Required) ||
                    (!isOption!Field && !fieldHas!(T, index, Rest));
                static if (requiredPositional)
                {
                    if (!(*currentFrame.seen)[index])
                    {
                        state.fail(
                            CliErrorKind.missingPositional,
                            null,
                            null,
                            Ancestors.length,
                            index,
                        );
                        return;
                    }
                }
            }
            else static if (fieldHas!(T, index, Required))
            {
                if (!(*currentFrame.seen)[index])
                {
                    state.fail(
                        CliErrorKind.missingRequiredOption,
                        null,
                        null,
                        Ancestors.length,
                        index,
                    );
                    return;
                }
            }
        }
    }

    static if (hasSubcommands!T && !allowsNoSubcommand!T)
    {
        if (!node.hasCommand)
            state.fail(CliErrorKind.missingCommand, null);
    }
}

private bool parseLongOption(T, Ancestors...)(
    ref ParseState state,
    ref ParseFrame!T currentFrame,
    Ancestors ancestors,
) @system
{
    const token = state.current;
    size_t equals = token.length;
    foreach (index; 2 .. token.length)
    {
        if (token[index] == '=')
        {
            equals = index;
            break;
        }
    }
    const name = token[2 .. equals];
    const hasAttached = equals != token.length;
    const attached = hasAttached ? token[equals + 1 .. $] : null;

    auto match = tryLongOnFrame!T(
        state,
        currentFrame,
        name,
        attached,
        hasAttached,
        false,
    );
    if (match == OptionMatch.failed)
        return false;
    if (match == OptionMatch.matched)
    {
        ++state.index;
        return true;
    }

    match = tryLongOnAncestors(
        state,
        name,
        attached,
        hasAttached,
        ancestors,
    );
    if (match == OptionMatch.failed)
        return false;
    if (match == OptionMatch.matched)
    {
        ++state.index;
        return true;
    }

    state.fail(CliErrorKind.unknownOption, token);
    return false;
}

private OptionMatch tryLongOnAncestors(Ancestors...)(
    ref ParseState state,
    String name,
    String attached,
    bool hasAttached,
    Ancestors ancestors,
) @system
{
    OptionMatch result = OptionMatch.noMatch;
    static foreach (reverseIndex; 0 .. Ancestors.length)
    {
        if (result == OptionMatch.noMatch)
            result = tryLongOnFrame(
                state,
                ancestors[Ancestors.length - 1 - reverseIndex],
                name,
                attached,
                hasAttached,
                true,
            );
    }
    return result;
}

pragma(inline, true)
private OptionMatch tryLongOnFrame(T)(
    ref ParseState state,
    ref ParseFrame!T frame,
    String name,
    String attached,
    bool hasAttached,
    bool globalsOnly,
) @system
{
    static foreach (index; 0 .. T.tupleof.length)
    {
        static if (!fieldHas!(T, index, Positional))
        {
            {
                enum String longName = fieldLongName!(T, index);
                if ((!globalsOnly || fieldHas!(T, index, Global)) &&
                    name == longName)
                    return consumeNamedField!(T, index, false)(
                        state,
                        frame,
                        attached,
                        hasAttached,
                    );
            }
        }
    }
    return OptionMatch.noMatch;
}

private bool parseShortOptions(Root, T, Ancestors...)(
    ref ParseState state,
    ref ParseFrame!T currentFrame,
    Ancestors ancestors,
) @system
{
    const token = state.current;
    size_t offset = 1;
    while (offset < token.length)
    {
        const shortName = token[offset];
        static if (builtinHelpEnabled!Root)
        {
            if (shortName == 'h')
            {
                ++state.index;
                state.outcome = CliOutcomeKind.help;
                return false;
            }
        }

        auto match = tryShortOnFrame!T(
            state,
            currentFrame,
            shortName,
            token,
            offset,
            false,
        );
        if (match == OptionMatch.noMatch)
            match = tryShortOnAncestors(
                state,
                shortName,
                token,
                offset,
                ancestors,
            );
        if (match == OptionMatch.failed)
            return false;
        if (match == OptionMatch.noMatch)
        {
            state.fail(CliErrorKind.unknownOption, token);
            return false;
        }
        if (state.outcome != CliOutcomeKind.invocation)
            return false;
    }

    ++state.index;
    return true;
}

private OptionMatch tryShortOnAncestors(Ancestors...)(
    ref ParseState state,
    char shortName,
    String token,
    ref size_t offset,
    Ancestors ancestors,
) @system
{
    OptionMatch result = OptionMatch.noMatch;
    static foreach (reverseIndex; 0 .. Ancestors.length)
    {
        if (result == OptionMatch.noMatch)
            result = tryShortOnFrame(
                state,
                ancestors[Ancestors.length - 1 - reverseIndex],
                shortName,
                token,
                offset,
                true,
            );
    }
    return result;
}

pragma(inline, true)
private OptionMatch tryShortOnFrame(T)(
    ref ParseState state,
    ref ParseFrame!T frame,
    char shortName,
    String token,
    ref size_t offset,
    bool globalsOnly,
) @system
{
    static foreach (index; 0 .. T.tupleof.length)
    {
        static if (!fieldHas!(T, index, Positional) &&
            fieldShortName!(T, index) != '\0')
        {
            if ((!globalsOnly || fieldHas!(T, index, Global)) &&
                shortName == fieldShortName!(T, index))
            {
                ++offset;
                static if (cliFieldTakesValue!(T, index))
                {
                    String attached;
                    bool hasAttached;
                    if (offset < token.length)
                    {
                        hasAttached = true;
                        if (token[offset] == '=')
                            ++offset;
                        attached = token[offset .. $];
                        offset = token.length;
                    }
                    auto result = consumeNamedField!(T, index, true)(
                        state,
                        frame,
                        attached,
                        hasAttached,
                    );
                    return result;
                }
                else
                {
                    return consumeNamedField!(T, index, true)(
                        state,
                        frame,
                        null,
                        false,
                    );
                }
            }
        }
    }
    return OptionMatch.noMatch;
}

pragma(inline, true)
private OptionMatch consumeNamedField(T, size_t index, bool shortForm)(
    ref ParseState state,
    ref ParseFrame!T frame,
    String attached,
    bool hasAttached,
) @system
{
    const optionToken = state.current;
    alias Field = FieldType!(T, index);
    ref field = frame.node.args.tupleof[index];
    ref bool wasSeen = (*frame.seen)[index];

    static if (fieldHas!(T, index, Count))
    {
        if (hasAttached)
        {
            state.fail(CliErrorKind.invalidValue, state.current, optionToken);
            return OptionMatch.failed;
        }
        if (field == Field.max)
        {
            state.fail(CliErrorKind.invalidValue, state.current, optionToken);
            return OptionMatch.failed;
        }
        ++field;
        wasSeen = true;
        return OptionMatch.matched;
    }
    else static if (!isOption!Field && !isArray!Field &&
        is(Unqualified!Field == bool))
    {
        if (hasAttached)
        {
            state.fail(CliErrorKind.invalidValue, state.current, optionToken);
            return OptionMatch.failed;
        }
        if (wasSeen)
        {
            state.fail(CliErrorKind.duplicateOption, state.current, optionToken);
            return OptionMatch.failed;
        }
        field = true;
        wasSeen = true;
        return OptionMatch.matched;
    }
    else
    {
        static if (!isArray!Field)
        {
            if (wasSeen)
            {
                state.fail(CliErrorKind.duplicateOption, state.current, optionToken);
                return OptionMatch.failed;
            }
        }

        String value;
        if (hasAttached)
            value = attached;
        else
        {
            if (state.index + 1 >= state.source.length)
            {
                state.fail(CliErrorKind.missingOptionValue, state.current, optionToken);
                return OptionMatch.failed;
            }
            ++state.index;
            value = state.current;
            if (!isValidUtf8(value))
            {
                state.fail(CliErrorKind.invalidUtf8, value, optionToken);
                return OptionMatch.failed;
            }
        }

        if (!assignFieldValue!Field(state, field, value, optionToken))
            return OptionMatch.failed;
        wasSeen = true;
        return OptionMatch.matched;
    }
}

private bool parseNextPositional(T)(
    ref ParseState state,
    ref ParseFrame!T frame,
    ref size_t ordinal,
    size_t commandDepth,
) @system
{
    size_t currentOrdinal;
    bool matched;
    static foreach (index; 0 .. T.tupleof.length)
    {
        if (!tryParsePositionalAt!(T, index)(
                state,
                frame,
                currentOrdinal,
                ordinal,
                matched,
                commandDepth,
            ))
            return false;
    }
    if (!matched)
    {
        state.fail(CliErrorKind.unexpectedArgument, state.current);
        return false;
    }
    return true;
}

pragma(inline, true)
private bool tryParsePositionalAt(T, size_t index)(
    ref ParseState state,
    ref ParseFrame!T frame,
    ref size_t currentOrdinal,
    ref size_t ordinal,
    ref bool matched,
    size_t commandDepth,
) @system
{
    static if (fieldHas!(T, index, Positional))
    {
        if (!matched && currentOrdinal == ordinal)
        {
            alias Field = FieldType!(T, index);
            ref field = frame.node.args.tupleof[index];
            if (!assignFieldValue!Field(
                    state,
                    field,
                    state.current,
                    null,
                    commandDepth,
                    index,
                ))
                return false;
            (*frame.seen)[index] = true;
            matched = true;
            static if (!fieldHas!(T, index, Rest))
                ++ordinal;
        }
        ++currentOrdinal;
    }
    return true;
}

private bool assignFieldValue(Field)(
    ref ParseState state,
    ref Field field,
    String text,
    String detail,
    size_t commandDepth = size_t.max,
    size_t fieldIndex = size_t.max,
) @system
{
    static if (isOption!Field)
    {
        alias Value = OptionElement!Field;
        Value value;
        if (!parseScalar!Value(text, &value))
        {
            state.fail(CliErrorKind.invalidValue, text, detail, commandDepth, fieldIndex);
            return false;
        }
        field = Option!Value.some(value);
        return true;
    }
    else static if (isArray!Field)
    {
        alias Value = ArrayElement!Field;
        Value value;
        if (!parseScalar!Value(text, &value))
        {
            state.fail(CliErrorKind.invalidValue, text, detail, commandDepth, fieldIndex);
            return false;
        }
        if (field.allocator is null)
        {
            if (state.allocator is null)
            {
                state.fail(CliErrorKind.allocationFailed, text, detail, commandDepth, fieldIndex);
                return false;
            }
            Field created = Field.create(state.allocator);
            moveAssign(created, field);
        }
        if (!field.tryAppend(&value))
        {
            state.fail(CliErrorKind.allocationFailed, text, detail, commandDepth, fieldIndex);
            return false;
        }
        return true;
    }
    else
    {
        if (!parseScalar!Field(text, &field))
        {
            state.fail(CliErrorKind.invalidValue, text, detail, commandDepth, fieldIndex);
            return false;
        }
        return true;
    }
}

private bool parseScalar(T)(String text, T* output) @system
{
    alias U = Unqualified!T;
    static if (is(U == String))
    {
        *output = text;
        return true;
    }
    else static if (is(U == bool))
    {
        if (text == "true")
        {
            *output = true;
            return true;
        }
        if (text == "false")
        {
            *output = false;
            return true;
        }
        return false;
    }
    else static if (is(U == enum))
    {
        static foreach (member; __traits(allMembers, U))
        {
            static if (__traits(hasMember, U, member))
            {
                if (text == enumCliName!(U, member))
                {
                    *output = __traits(getMember, U, member);
                    return true;
                }
            }
        }
        return false;
    }
    else static if (__traits(isIntegral, U))
    {
        if (text.length == 0)
            return false;
        size_t cursor;
        bool negative;
        static if (U.min < 0)
        {
            if (text[0] == '-')
            {
                negative = true;
                cursor = 1;
            }
        }
        else
        {
            if (text[0] == '-')
                return false;
        }
        if (cursor == text.length)
            return false;

        ulong magnitude;
        foreach (codeUnit; text[cursor .. $])
        {
            if (codeUnit < '0' || codeUnit > '9')
                return false;
            const digit = cast(ulong)(codeUnit - '0');
            if (magnitude > (ulong.max - digit) / 10)
                return false;
            magnitude = magnitude * 10 + digit;
        }

        static if (U.min == 0)
        {
            if (magnitude > cast(ulong) U.max)
                return false;
            *output = cast(U) magnitude;
        }
        else
        {
            enum ulong negativeLimit = cast(ulong)(0UL - cast(ulong) U.min);
            if ((!negative && magnitude > cast(ulong) U.max) ||
                (negative && magnitude > negativeLimit))
                return false;
            if (negative)
                *output = magnitude == negativeLimit
                    ? U.min : cast(U)-cast(long) magnitude;
            else
                *output = cast(U) magnitude;
        }
        return true;
    }
    else
        static assert(false, U.stringof ~ " has no CLI scalar parser");
}

/// Writes generated help for the root command or a statically selected command path.
/// `Path` must list direct descendants starting at `Root`.
void writeHelp(Root, Path...)(ref Writer writer, String programPath) @system
{
    static assert(ValidateCliSchema!Root);
    alias Target = HelpPathTarget!(Root, Path);
    String programName = normalizeProgramName(programPath);

    writeHelpAbout!Target(writer);
    writeStaticUsage!(Root, Path)(writer, programName);
    writeHelpSections!(Root, Target)(writer);

    static if (hasVisibleGlobalsOnStaticPath!(Root, Path))
    {
        writer.put("\nGlobal options:\n");
        writeGlobalsOnStaticPath!(Root, Path)(writer);
    }
}

/// Writes the library-owned non-invocation response to caller-provided writers.
/// Returns the process exit code associated with the response.
int writeCliResult(T)(
    ref Writer output,
    ref Writer errorOutput,
    ref CliParseResult!T result,
) @system
{
    final switch (result.outcome)
    {
        case CliOutcomeKind.invocation:
            return 0;
        case CliOutcomeKind.help:
            writeSelectedHelp!T(output, result.programName, result.invocation_);
            return 0;
        case CliOutcomeKind.version_:
            writeVersion!T(output, result.programName);
            return 0;
        case CliOutcomeKind.error:
            writeError!T(errorOutput, result.error_, result.invocation_);
            errorOutput.put('\n');
            writeSelectedUsage!T(errorOutput, result.programName, result.invocation_);
            static if (builtinHelpEnabled!T)
            {
                errorOutput.put("\nTry '");
                writeProgramPath!T(errorOutput, result.programName, result.invocation_);
                errorOutput.put(" --help' for more information.\n");
            }
            return 2;
    }
}

/// Handles help, version, and diagnostics using stdout/stderr.
int handleCliResult(T)(ref CliParseResult!T result) @system
{
    Writer output = Writer.fromFile(cast(typeof(stdout)) stdout);
    Writer errorOutput = Writer.fromFile(cast(typeof(stderr)) stderr);
    const exitCode = writeCliResult(output, errorOutput, result);
    output.finish();
    errorOutput.finish();
    return exitCode;
}

private void writeSelectedHelp(T)(
    ref Writer writer,
    String programName,
    ref ParsedCommand!T root,
) @system
{
    writeSelectedHelpAt!(T, T)(writer, programName, root, root);
}

private void writeSelectedHelpAt(Root, T)(
    ref Writer writer,
    String programName,
    ref ParsedCommand!Root tree,
    ref ParsedCommand!T node,
) @system
{
    bool descended;
    static foreach (Child; CommandTypes!T)
    {
        if (!descended)
        {
            if (auto child = node.command!Child)
            {
                descended = true;
                writeSelectedHelpAt!(Root, Child)(writer, programName, tree, *child);
            }
        }
    }
    if (descended)
        return;

    writeHelpAbout!T(writer);
    writeSelectedUsage!Root(writer, programName, tree);
    writeHelpSections!(Root, T)(writer);

    if (hasGlobalsAlongActivePath!Root(tree))
    {
        writer.put("\nGlobal options:\n");
        writeGlobalsAlongActivePath!Root(writer, tree);
    }
}

private void writeHelpAbout(T)(ref Writer writer) @system
{
    enum aboutText = typeAbout!T;
    static if (aboutText.length != 0)
    {
        writer.put(aboutText);
        writer.put("\n\n");
    }
}

private void writeHelpSections(Root, T)(ref Writer writer) @system
{
    static if (hasSubcommands!T)
    {
        writer.put("\nCommands:\n");
        static foreach (Child; CommandTypes!T)
            writeCommandHelpLine!Child(writer);
    }
    else static if (hasVisiblePositionals!T)
    {
        writer.put("\nArguments:\n");
        writePositionals!T(writer);
    }

    static if (hasVisibleLocalOptions!T || builtinHelpEnabled!Root ||
        (is(Unqualified!T == Unqualified!Root) && builtinVersionEnabled!Root))
    {
        writer.put("\nOptions:\n");
        static if (hasVisibleLocalOptions!T)
            writeLocalOptions!T(writer);
        static if (builtinHelpEnabled!Root)
            writer.put("  -h, --help\tShow this help\n");
        static if (is(Unqualified!T == Unqualified!Root) &&
            builtinVersionEnabled!Root)
            writer.put("      --version\tShow the application version\n");
    }
}

private void writeCommandHelpLine(T)(ref Writer writer) @system
{
    writer.put("  ");
    writer.put(commandName!T);
    enum aboutText = typeAbout!T;
    static if (aboutText.length != 0)
    {
        writer.put("\t");
        writer.put(aboutText);
    }
    writer.put('\n');
}

private template HelpPathTarget(Parent, Path...)
{
    static if (Path.length == 0)
        alias HelpPathTarget = Parent;
    else
    {
        alias Child = Path[0];
        static assert(isDirectCommand!(Parent, Child),
            Child.stringof ~ " is not a direct CLI subcommand of " ~ Parent.stringof);
        alias HelpPathTarget = HelpPathTarget!(Child, Path[1 .. $]);
    }
}

private void writeStaticUsage(Root, Path...)(
    ref Writer writer,
    String programName,
) @system
{
    alias Target = HelpPathTarget!(Root, Path);

    writer.put("Usage: ");
    writer.put(programName);
    static foreach (CommandType; Path)
    {
        writer.put(' ');
        writer.put(commandName!CommandType);
    }
    writeUsageSuffixForType!(Target, hasInheritedGlobalsOnStaticPath!(Root, Path))(writer);
    writer.put('\n');
}

private template hasInheritedGlobalsOnStaticPath(Parent, Path...)
{
    static if (Path.length == 0)
        enum bool hasInheritedGlobalsOnStaticPath = false;
    else
        enum bool hasInheritedGlobalsOnStaticPath = hasAnyGlobalOptions!Parent ||
            hasInheritedGlobalsOnStaticPath!(Path[0], Path[1 .. $]);
}

private template hasVisibleGlobalsOnStaticPath(Parent, Path...)
{
    static if (Path.length == 0)
        enum bool hasVisibleGlobalsOnStaticPath = hasVisibleGlobalOptions!Parent;
    else
        enum bool hasVisibleGlobalsOnStaticPath = hasVisibleGlobalOptions!Parent ||
            hasVisibleGlobalsOnStaticPath!(Path[0], Path[1 .. $]);
}

private void writeGlobalsOnStaticPath(Parent, Path...)(ref Writer writer) @system
{
    writeVisibleGlobals!Parent(writer);
    static if (Path.length != 0)
        writeGlobalsOnStaticPath!(Path[0], Path[1 .. $])(writer);
}

private void writeSelectedUsage(T)(
    ref Writer writer,
    String programName,
    ref ParsedCommand!T root,
) @system
{
    writer.put("Usage: ");
    writeProgramPath!T(writer, programName, root);
    writeUsageSuffixForActive!(T, false)(writer, root);
    writer.put('\n');
}

private void writeProgramPath(T)(
    ref Writer writer,
    String programName,
    ref ParsedCommand!T node,
) @system
{
    writer.put(programName);
    writeChildPath!T(writer, node);
}

private void writeChildPath(T)(ref Writer writer, ref ParsedCommand!T node)
@system
{
    static foreach (Child; CommandTypes!T)
    {
        if (auto child = node.command!Child)
        {
            writer.put(' ');
            writer.put(commandName!Child);
            writeChildPath!Child(writer, *child);
            return;
        }
    }
}

private void writeUsageSuffixForActive(T, bool inheritedGlobals)(
    ref Writer writer,
    ref ParsedCommand!T node,
) @system
{
    static foreach (Child; CommandTypes!T)
    {
        if (auto child = node.command!Child)
        {
            writeUsageSuffixForActive!(
                Child,
                inheritedGlobals || hasAnyGlobalOptions!T,
            )(writer, *child);
            return;
        }
    }

    writeUsageSuffixForType!(T, inheritedGlobals)(writer);
}

private void writeUsageSuffixForType(T, bool inheritedGlobals)(ref Writer writer) @system
{
    static if (hasAnyNamedOptions!T || inheritedGlobals)
        writer.put(" [OPTIONS]");
    static if (hasSubcommands!T)
    {
        static if (allowsNoSubcommand!T)
            writer.put(" [COMMAND]");
        else
            writer.put(" <COMMAND>");
    }
    else
        writePositionalUsage!T(writer);
}

private void writePositionalUsage(T)(ref Writer writer) @system
{
    static foreach (index; 0 .. T.tupleof.length)
        writePositionalUsageAt!(T, index)(writer);
}

pragma(inline, true)
private void writePositionalUsageAt(T, size_t index)(ref Writer writer) @system
{
    static if (fieldHas!(T, index, Positional))
    {
        alias Field = FieldType!(T, index);
        writer.put(' ');
        static if (fieldHas!(T, index, Rest))
        {
            static if (fieldHas!(T, index, Required))
                writer.put('<');
            else
                writer.put('[');
            writer.put(fieldValueName!(T, index));
            writer.put("...");
            static if (fieldHas!(T, index, Required))
                writer.put('>');
            else
                writer.put(']');
        }
        else static if (isOption!Field && !fieldHas!(T, index, Required))
        {
            writer.put('[');
            writer.put(fieldValueName!(T, index));
            writer.put(']');
        }
        else
        {
            writer.put('<');
            writer.put(fieldValueName!(T, index));
            writer.put('>');
        }
    }
}

private enum hasVisiblePositionals(T) = () {
    bool result;
    static foreach (index; 0 .. T.tupleof.length)
        static if (fieldHas!(T, index, Positional) &&
            !fieldHas!(T, index, Hidden))
            result = true;
    return result;
}();

private enum hasAnyNamedOptions(T) = () {
    bool result;
    static foreach (index; 0 .. T.tupleof.length)
        static if (!fieldHas!(T, index, Positional))
            result = true;
    return result;
}();

private enum hasAnyGlobalOptions(T) = () {
    bool result;
    static foreach (index; 0 .. T.tupleof.length)
        static if (!fieldHas!(T, index, Positional) &&
            fieldHas!(T, index, Global))
            result = true;
    return result;
}();

private enum hasVisibleLocalOptions(T) = () {
    bool result;
    static foreach (index; 0 .. T.tupleof.length)
        static if (!fieldHas!(T, index, Positional) &&
            !fieldHas!(T, index, Global) &&
            !fieldHas!(T, index, Hidden))
            result = true;
    return result;
}();

private void writePositionals(T)(ref Writer writer) @system
{
    static foreach (index; 0 .. T.tupleof.length)
        writePositionalLine!(T, index)(writer);
}

pragma(inline, true)
private void writePositionalLine(T, size_t index)(ref Writer writer) @system
{
    static if (fieldHas!(T, index, Positional) &&
        !fieldHas!(T, index, Hidden))
    {
        writer.put("  ");
        writer.put(fieldValueName!(T, index));
        static if (fieldHas!(T, index, Rest))
            writer.put("...");
        enum helpText = fieldHelp!(T, index);
        static if (helpText.length != 0)
        {
            writer.put("\t");
            writer.put(helpText);
        }
        writer.put('\n');
    }
}

private void writeLocalOptions(T)(ref Writer writer) @system
{
    static foreach (index; 0 .. T.tupleof.length)
    {
        static if (!fieldHas!(T, index, Positional) &&
            !fieldHas!(T, index, Global) &&
            !fieldHas!(T, index, Hidden))
            writeOptionLine!(T, index)(writer);
    }
}

pragma(inline, true)
private void writeOptionLine(T, size_t index)(ref Writer writer) @system
{
    writer.put("  ");
    enum shortName = fieldShortName!(T, index);
    static if (shortName != '\0')
    {
        writer.put('-');
        writer.put(shortName);
        writer.put(", ");
    }
    else
        writer.put("    ");
    writer.put("--");
    writer.put(fieldLongName!(T, index));
    static if (cliFieldTakesValue!(T, index))
    {
        writer.put(" <");
        writer.put(fieldValueName!(T, index));
        writer.put('>');
    }
    static if (fieldHas!(T, index, Count))
        writer.put("...");
    enum helpText = fieldHelp!(T, index);
    static if (helpText.length != 0)
    {
        writer.put("\t");
        writer.put(helpText);
    }
    writer.put('\n');
}

private enum hasVisibleGlobalOptions(T) = () {
    bool result;
    static foreach (index; 0 .. T.tupleof.length)
        static if (!fieldHas!(T, index, Positional) &&
            fieldHas!(T, index, Global) &&
            !fieldHas!(T, index, Hidden))
            result = true;
    return result;
}();

private void writeVisibleGlobals(T)(ref Writer writer) @system
{
    static foreach (index; 0 .. T.tupleof.length)
        static if (!fieldHas!(T, index, Positional) &&
            fieldHas!(T, index, Global) &&
            !fieldHas!(T, index, Hidden))
            writeOptionLine!(T, index)(writer);
}

private bool hasGlobalsAlongActivePath(T)(ref ParsedCommand!T node) @system
{
    static if (hasVisibleGlobalOptions!T)
        return true;
    static foreach (Child; CommandTypes!T)
        if (auto child = node.command!Child)
            return hasGlobalsAlongActivePath!Child(*child);
    return false;
}

private void writeGlobalsAlongActivePath(T)(
    ref Writer writer,
    ref ParsedCommand!T node,
) @system
{
    writeVisibleGlobals!T(writer);
    static foreach (Child; CommandTypes!T)
    {
        if (auto child = node.command!Child)
        {
            writeGlobalsAlongActivePath!Child(writer, *child);
            return;
        }
    }
}

private void writeVersion(T)(ref Writer writer, String programName) @system
{
    writer.put(programName);
    writer.put(' ');
    writer.put(typeVersion!T);
    writer.put('\n');
}

private void writeErrorFieldName(T)(
    ref Writer writer,
    ref ParsedCommand!T node,
    size_t targetDepth,
    size_t fieldIndex,
    size_t currentDepth,
    bool valueName,
) @system
{
    if (targetDepth == currentDepth)
    {
        static foreach (index; 0 .. T.tupleof.length)
        {
            if (fieldIndex == index)
            {
                if (valueName)
                    writer.put(fieldValueName!(T, index));
                else
                    writer.put(fieldLongName!(T, index));
                return;
            }
        }
        return;
    }

    static foreach (Child; CommandTypes!T)
    {
        if (auto child = node.command!Child)
        {
            writeErrorFieldName!Child(
                writer,
                *child,
                targetDepth,
                fieldIndex,
                currentDepth + 1,
                valueName,
            );
            return;
        }
    }
}

private void writeError(T)(
    ref Writer writer,
    CliError error,
    ref ParsedCommand!T root,
) @system
{
    writer.put("error: ");
    final switch (error.kind)
    {
        case CliErrorKind.none:
            writer.put("unknown command-line error");
            break;
        case CliErrorKind.invalidUtf8:
            writer.put("argument contains invalid UTF-8");
            break;
        case CliErrorKind.unknownOption:
            writer.put("unknown option '");
            writer.put(error.token);
            writer.put("'");
            break;
        case CliErrorKind.unknownCommand:
            writer.put("unknown command '");
            writer.put(error.token);
            writer.put("'");
            break;
        case CliErrorKind.missingOptionValue:
            writer.put("missing value for ");
            writer.put(error.detail);
            break;
        case CliErrorKind.invalidValue:
            writer.put("invalid value '");
            writer.put(error.token);
            writer.put("' for ");
            if (error.fieldIndex != size_t.max)
                writeErrorFieldName!T(
                    writer,
                    root,
                    error.commandDepth,
                    error.fieldIndex,
                    0,
                    true,
                );
            else
                writer.put(error.detail);
            break;
        case CliErrorKind.missingRequiredOption:
            writer.put("required option '--");
            writeErrorFieldName!T(
                writer,
                root,
                error.commandDepth,
                error.fieldIndex,
                0,
                false,
            );
            writer.put("' was not provided");
            break;
        case CliErrorKind.missingPositional:
            writer.put("required argument <");
            writeErrorFieldName!T(
                writer,
                root,
                error.commandDepth,
                error.fieldIndex,
                0,
                true,
            );
            writer.put("> was not provided");
            break;
        case CliErrorKind.missingCommand:
            writer.put("a command is required");
            break;
        case CliErrorKind.duplicateOption:
            writer.put("option ");
            writer.put(error.detail);
            writer.put(" was provided more than once");
            break;
        case CliErrorKind.unexpectedArgument:
            writer.put("unexpected argument '");
            writer.put(error.token);
            writer.put("'");
            break;
        case CliErrorKind.allocationFailed:
            writer.put("allocation failed while parsing ");
            if (error.fieldIndex != size_t.max)
                writeErrorFieldName!T(
                    writer,
                    root,
                    error.commandDepth,
                    error.fieldIndex,
                    0,
                    true,
                );
            else
                writer.put(error.detail);
            break;
    }
}
