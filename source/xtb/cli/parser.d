module xtb.cli.parser;

nothrow @nogc:

import core.lifetime : emplace;
import core.stdc.string : strlen;
import xtb.cli.attributes;
import xtb.cli.internal.traits;
import xtb.cli.value : CliValueError, CliValueErrorKind;
import xtb.core.containers.array : Array;
import xtb.core.lifetime : deinitValue = deinit, move, moveAssign, needsDeinit;
import xtb.core.memory : Allocator;
import xtb.core.option : Option;
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
    invalidDefault,
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
    CliValueError valueError;
    size_t commandDepth = size_t.max;
    size_t fieldIndex = size_t.max;
}

package(xtb.cli) enum CliOutcomeKind : ubyte
{
    invocation,
    help,
    version_,
    terminal,
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

/// Result of CLI parsing. Built-in responses are library-owned, while custom
/// terminal outcomes expose the partially parsed tree through `parsed`.
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

    bool hasBuiltinResponse() const pure @safe
    {
        return outcome_ == CliOutcomeKind.help || outcome_ == CliOutcomeKind.version_;
    }

    bool hasTerminal() const pure @safe
    {
        return outcome_ == CliOutcomeKind.terminal;
    }

    bool failed() const pure @safe
    {
        return outcome_ == CliOutcomeKind.error;
    }

    /// Returns the parsed tree for a custom terminal outcome. It may be partial.
    ref ParsedCommand!T parsed() return @system
    {
        return invocation_;
    }

    ref const(ParsedCommand!T) parsed() const return @system
    {
        return invocation_;
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
        CliValueError valueError = CliValueError.init,
    ) @safe
    {
        if (outcome == CliOutcomeKind.error)
            return;
        outcome = CliOutcomeKind.error;
        error.kind = kind;
        error.argumentIndex = index;
        error.token = token;
        error.detail = detail;
        error.valueError = valueError;
        error.commandDepth = commandDepth;
        error.fieldIndex = fieldIndex;
    }
}

private struct ParseFrame(T)
{
nothrow @nogc:
    ParsedCommand!T* node;
    bool[cliFieldCount!T]* seen;
}

private bool requiredFieldsSatisfied(T)(ParseFrame!T frame)
{
    static foreach (index; 0 .. cliFieldCount!T)
    {
        static if (fieldIsRequired!(T, index))
        {
            if (!(*frame.seen)[index])
                return false;
        }
    }
    return true;
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
package(xtb.cli) String normalizeProgramName(String programPath) @safe
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
    bool[cliFieldCount!T] seen;
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
            if (positionalOrdinal < positionalFieldCount!T)
            {
                if (!parseNextPositional!T(
                        state,
                        currentFrame,
                        positionalOrdinal,
                        Ancestors.length,
                    ))
                    return;
                ++state.index;
                continue;
            }

            bool matched;
            static foreach (Child; CommandTypes!T)
            {
                static foreach (childName; commandAllNames!Child)
                {
                    if (!matched && token == childName)
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
            }
            if (!matched)
            {
                state.fail(CliErrorKind.unknownCommand, token);
                return;
            }
            break;
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

    static foreach (index; 0 .. cliFieldCount!T)
    {
        static if (fieldHasDefaultInput!(T, index))
        {
            if (!(*currentFrame.seen)[index])
            {
                ref field = cliFieldRef!(T, index)(currentFrame.node.args);
                if (!assignFieldValue!(T, index)(
                        state,
                        field,
                        fieldDefaultInput!(T, index),
                        null,
                        Ancestors.length,
                        index,
                        CliErrorKind.invalidDefault,
                    ))
                    return;
            }
        }
    }

    static foreach (index; 0 .. cliFieldCount!T)
    {
        static if (fieldIsRequired!(T, index))
        {
            if (!(*currentFrame.seen)[index])
            {
                static if (fieldHas!(T, index, CliPositional))
                    state.fail(
                        CliErrorKind.missingPositional,
                        null,
                        null,
                        Ancestors.length,
                        index,
                    );
                else
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

    static if (hasSubcommands!T && helpOnMissingSubcommand!T)
    {
        if (!node.hasCommand)
        {
            bool ancestorsComplete = true;
            static foreach (index; 0 .. Ancestors.length)
            {
                if (!requiredFieldsSatisfied(ancestors[index]))
                    ancestorsComplete = false;
            }

            if (ancestorsComplete)
            {
                state.outcome = CliOutcomeKind.help;
                return;
            }
        }
    }

    static if (hasSubcommands!T && !subcommandIsOptional!T &&
        !helpOnMissingSubcommand!T)
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
    static foreach (index; 0 .. cliFieldCount!T)
    {
        static if (!fieldHas!(T, index, CliPositional))
        {
            static foreach (longName; fieldAllLongNames!(T, index))
            {
                if ((!globalsOnly || fieldHas!(T, index, CliGlobal)) &&
                    name == longName)
                    return consumeNamedField!(T, index, false)(
                        state,
                        frame,
                        attached,
                        hasAttached,
                    );
            }
            static if (fieldHas!(T, index, CliNegatable))
            {
                if ((!globalsOnly || fieldHas!(T, index, CliGlobal)) &&
                    name == fieldNegativeLongName!(T, index))
                    return consumeNamedField!(T, index, false, true)(
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
    static foreach (index; 0 .. cliFieldCount!T)
    {
        static if (!fieldHas!(T, index, CliPositional) &&
            fieldAllShortNames!(T, index).length != 0)
        {
            static foreach (candidateShortName; fieldAllShortNames!(T, index))
            {
                if ((!globalsOnly || fieldHas!(T, index, CliGlobal)) &&
                    shortName == candidateShortName)
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
    }
    return OptionMatch.noMatch;
}

pragma(inline, true)
private OptionMatch consumeNamedField(
    T,
    size_t index,
    bool shortForm,
    bool negated = false,
)(
    ref ParseState state,
    ref ParseFrame!T frame,
    String attached,
    bool hasAttached,
) @system
{
    const optionToken = state.current;
    alias Field = FieldType!(T, index);
    ref field = cliFieldRef!(T, index)(frame.node.args);
    ref bool wasSeen = (*frame.seen)[index];

    static if (fieldHas!(T, index, CliNegatable))
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
        static if (isOption!Field)
            field = Option!bool.some(!negated);
        else
            field = !negated;
    }
    else static if (fieldHas!(T, index, CliCount))
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
    }
    else
    {
        static if (!cliFieldIsRepeated!(T, index))
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

        if (!assignFieldValue!(T, index)(state, field, value, optionToken))
            return OptionMatch.failed;
    }

    wasSeen = true;
    static if (fieldHas!(T, index, CliTerminal))
        state.outcome = CliOutcomeKind.terminal;
    return OptionMatch.matched;
}

private enum positionalFieldCount(T) = () {
    size_t result;
    static foreach (index; 0 .. cliFieldCount!T)
        static if (fieldHas!(T, index, CliPositional))
            ++result;
    return result;
}();

private bool parseNextPositional(T)(
    ref ParseState state,
    ref ParseFrame!T frame,
    ref size_t ordinal,
    size_t commandDepth,
) @system
{
    size_t currentOrdinal;
    bool matched;
    static foreach (index; 0 .. cliFieldCount!T)
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
    static if (fieldHas!(T, index, CliPositional))
    {
        if (!matched && currentOrdinal == ordinal)
        {
            alias Field = FieldType!(T, index);
            ref field = cliFieldRef!(T, index)(frame.node.args);
            if (!assignFieldValue!(T, index)(
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
            static if (!fieldHas!(T, index, CliRest))
                ++ordinal;
        }
        ++currentOrdinal;
    }
    return true;
}

private bool parseFieldValue(T, size_t index, Value)(
    ref ParseState state,
    String text,
    Value* output,
    String detail,
    size_t commandDepth,
    size_t fieldIndex,
    CliErrorKind invalidKind = CliErrorKind.invalidValue,
) @system
{
    CliValueError valueError;
    static if (fieldHasValueWith!(T, index))
    {
        alias Parser = FieldValueParser!(T, index);
        static if (cliParserNeedsAllocator!(Parser, Value))
        {
            if (state.allocator is null)
            {
                state.fail(
                    CliErrorKind.allocationFailed,
                    text,
                    detail,
                    commandDepth,
                    fieldIndex,
                );
                return false;
            }
            valueError = Parser(text, state.allocator, output);
        }
        else
            valueError = Parser(text, output);
    }
    else
    {
        if (!parseScalar!Value(text, output))
            valueError = CliValueError.invalid();
    }

    if (valueError.failed)
    {
        const errorKind = valueError.kind == CliValueErrorKind.allocationFailed
            ? CliErrorKind.allocationFailed : invalidKind;
        state.fail(
            errorKind,
            text,
            detail,
            commandDepth,
            fieldIndex,
            valueError,
        );
        return false;
    }
    return true;
}

private bool assignFieldValue(T, size_t index)(
    ref ParseState state,
    ref FieldType!(T, index) field,
    String text,
    String detail,
    size_t commandDepth = size_t.max,
    size_t fieldIndex = size_t.max,
    CliErrorKind invalidKind = CliErrorKind.invalidValue,
) @system
{
    alias Field = FieldType!(T, index);
    static if (fieldHasValueWith!(T, index) && cliFieldParserParsesWholeField!(T, index))
    {
        return parseFieldValue!(T, index, Field)(
            state,
            text,
            &field,
            detail,
            commandDepth,
            fieldIndex,
            invalidKind,
        );
    }
    else static if (isOption!Field)
    {
        alias Value = OptionElement!Field;
        Value value;
        static if (needsDeinit!Value)
            scope (exit)
                deinitValue(value);
        if (!parseFieldValue!(T, index, Value)(
                state,
                text,
                &value,
                detail,
                commandDepth,
                fieldIndex,
                invalidKind,
            ))
            return false;
        field = Option!Value.some(move(value));
        return true;
    }
    else static if (isArray!Field)
    {
        alias Value = ArrayElement!Field;
        Value value;
        static if (needsDeinit!Value)
            scope (exit)
                deinitValue(value);
        if (!parseFieldValue!(T, index, Value)(
                state,
                text,
                &value,
                detail,
                commandDepth,
                fieldIndex,
                invalidKind,
            ))
            return false;
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
        return parseFieldValue!(T, index, Field)(
            state,
            text,
            &field,
            detail,
            commandDepth,
            fieldIndex,
            invalidKind,
        );
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
