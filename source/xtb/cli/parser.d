module xtb.cli.parser;

nothrow @nogc:

import core.lifetime : emplace;
import core.stdc.stdio : stderr, stdout;
import core.stdc.string : strlen;
import xtb.cli.attributes;
import xtb.cli.traits;
import xtb.cli.value : CliValueError, CliValueErrorKind;
import xtb.core.ansi : AnsiColor, AnsiStyle, AnsiWriter;
import xtb.core.array : Array;
import xtb.core.lifetime : deinitValue = deinit, move, moveAssign, needsDeinit;
import xtb.core.memory : Allocator;
import xtb.core.option : Option;
import xtb.core.writer : BufferedWriter, Writer;
import xtb.core.print : fileWriter;
import xtb.core.string : baseName;
import xtb.core.types : String;
import xtb.core.utf8 : isValidUtf8;

private enum cliHeadingStyle = AnsiStyle.init.bold;
private enum cliCanonicalStyle = AnsiStyle.foreground(AnsiColor.brightCyan).bold;
private enum cliSecondaryStyle = AnsiStyle.foreground(AnsiColor.cyan).dim;
private enum cliValueStyle = AnsiStyle.foreground(AnsiColor.brightYellow);
private enum cliDefaultStyle = AnsiStyle.foreground(AnsiColor.brightGreen);
private enum cliMetadataStyle = AnsiStyle.init.dim;
private enum cliErrorStyle = AnsiStyle.foreground(AnsiColor.brightRed).bold;

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

private enum CliOutcomeKind : ubyte
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

/// Writes generated help for the root command or a statically selected command path.
/// `Path` must list direct descendants starting at `Root`.
/// ANSI styling is emitted only when `ansi` is true.
void writeHelp(Root, Path...)(
    ref Writer output,
    String programPath,
    bool ansi = false,
) @system
{
    static assert(ValidateCliSchema!Root);
    alias Target = HelpPathTarget!(Root, Path);
    String programName = normalizeProgramName(programPath);
    AnsiWriter writer = AnsiWriter.fromWriter(&output, ansi);

    writeHelpAbout!Target(writer);
    writeStaticUsage!(Root, Path)(writer, programName);
    writeHelpSections!(Root, Target)(writer);

    static if (hasVisibleGlobalsOnStaticPath!(true, Root, Path))
    {
        writer.put('\n');
        writer.styled("Required global options:", cliHeadingStyle);
        writer.put('\n');
        enum columnWidth = globalsOnStaticPathHelpColumnWidth!(true, Root, Path);
        bool firstGlobal = true;
        writeGlobalsOnStaticPath!(true, Root, Path)(writer, columnWidth, firstGlobal);
    }

    static if (hasVisibleGlobalsOnStaticPath!(false, Root, Path))
    {
        writer.put('\n');
        writer.styled("Optional global options:", cliHeadingStyle);
        writer.put('\n');
        enum columnWidth = globalsOnStaticPathHelpColumnWidth!(false, Root, Path);
        bool firstGlobal = true;
        writeGlobalsOnStaticPath!(false, Root, Path)(writer, columnWidth, firstGlobal);
    }
}

/// Writes the library-owned non-invocation response to caller-provided writers.
/// Returns the process exit code associated with the response.
int writeCliResult(T)(
    ref Writer output,
    ref Writer errorOutput,
    ref CliParseResult!T result,
    bool outputAnsi = false,
    bool errorAnsi = false,
) @system
{
    AnsiWriter styledOutput = AnsiWriter.fromWriter(&output, outputAnsi);
    AnsiWriter styledError = AnsiWriter.fromWriter(&errorOutput, errorAnsi);

    final switch (result.outcome)
    {
        case CliOutcomeKind.invocation:
            return 0;
        case CliOutcomeKind.help:
            writeSelectedHelp!T(styledOutput, result.programName, result.invocation_);
            return 0;
        case CliOutcomeKind.version_:
            writeVersion!T(styledOutput, result.programName);
            return 0;
        case CliOutcomeKind.terminal:
            return 0;
        case CliOutcomeKind.error:
            writeError!T(styledError, result.error_, result.invocation_);
            styledError.put('\n');
            writeSelectedUsage!T(styledError, result.programName, result.invocation_);
            static if (builtinHelpEnabled!T)
            {
                styledError.put("\nTry '");
                writeProgramPath!T(styledError, result.programName, result.invocation_);
                styledError.put(' ');
                styledError.styled("--help", cliCanonicalStyle);
                styledError.put("' for more information.\n");
            }
            return 2;
    }
}

/// Handles help, version, and diagnostics using stdout/stderr.
/// The application decides independently whether each descriptor should receive ANSI styling.
int handleCliResult(T)(
    ref CliParseResult!T result,
    bool outputAnsi = false,
    bool errorAnsi = false,
) @system
{
    Writer outputDestination = fileWriter(cast(typeof(stdout)) stdout);
    Writer errorDestination = fileWriter(cast(typeof(stderr)) stderr);

    // CLI help and diagnostics emit many small fragments, so coalesce them for
    // this stdout/stderr convenience path. Keep writeCliResult destination-neutral.
    char[1024] outputStorage;
    char[1024] errorStorage;
    BufferedWriter bufferedOutput = BufferedWriter.create(
        &outputDestination,
        outputStorage[],
    );
    BufferedWriter bufferedError = BufferedWriter.create(
        &errorDestination,
        errorStorage[],
    );
    Writer output = bufferedOutput.writer();
    Writer errorOutput = bufferedError.writer();

    const exitCode = writeCliResult(
        output,
        errorOutput,
        result,
        outputAnsi,
        errorAnsi,
    );
    cast(void) bufferedOutput.flush();
    cast(void) bufferedError.flush();
    return exitCode;
}

private void writeSelectedHelp(T)(
    ref AnsiWriter writer,
    String programName,
    ref ParsedCommand!T root,
) @system
{
    writeSelectedHelpAt!(T, T)(writer, programName, root, root);
}

private void writeSelectedHelpAt(Root, T)(
    ref AnsiWriter writer,
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

    if (hasGlobalsAlongActivePath!(Root, true)(tree))
    {
        writer.put('\n');
        writer.styled("Required global options:", cliHeadingStyle);
        writer.put('\n');
        const columnWidth = globalsAlongActivePathHelpColumnWidth!(Root, true)(tree);
        bool firstGlobal = true;
        writeGlobalsAlongActivePath!(Root, true)(writer, tree, columnWidth, firstGlobal);
    }

    if (hasGlobalsAlongActivePath!(Root, false)(tree))
    {
        writer.put('\n');
        writer.styled("Optional global options:", cliHeadingStyle);
        writer.put('\n');
        const columnWidth = globalsAlongActivePathHelpColumnWidth!(Root, false)(tree);
        bool firstGlobal = true;
        writeGlobalsAlongActivePath!(Root, false)(writer, tree, columnWidth, firstGlobal);
    }
}

private void writeHelpAbout(T)(ref AnsiWriter writer) @system
{
    enum aboutText = typeAbout!T;
    static if (aboutText.length != 0)
    {
        writer.put(aboutText);
        writer.put("\n\n");
    }
}

private void writeHelpSections(Root, T)(ref AnsiWriter writer) @system
{
    static if (hasVisiblePositionals!T)
    {
        writer.put('\n');
        writer.styled("Arguments:", cliHeadingStyle);
        writer.put('\n');
        writePositionals!T(writer, positionalHelpColumnWidth!T);
    }

    static if (hasSubcommands!T)
    {
        writer.put('\n');
        writer.styled("Commands:", cliHeadingStyle);
        writer.put('\n');
        enum commandColumnWidth = commandHelpColumnWidth!T;
        bool firstCommand = true;
        static foreach (Child; CommandTypes!T)
        {
            if (!firstCommand)
                writer.put('\n');
            writeCommandHelpLine!Child(writer, commandColumnWidth);
            firstCommand = false;
        }
    }

    static if (hasVisibleRequiredLocalOptions!T)
    {
        writer.put('\n');
        writer.styled("Required options:", cliHeadingStyle);
        writer.put('\n');
        enum requiredColumnWidth = visibleLocalOptionHelpColumnWidth!(T, true);
        writeLocalOptions!(T, true)(writer, requiredColumnWidth);
    }

    static if (hasVisibleOptionalLocalOptions!T || builtinHelpEnabled!Root ||
        (is(Unqualified!T == Unqualified!Root) && builtinVersionEnabled!Root))
    {
        writer.put('\n');
        writer.styled("Optional options:", cliHeadingStyle);
        writer.put('\n');
        enum optionColumnWidth = optionalLocalOptionHelpColumnWidth!(Root, T);
        static if (hasVisibleOptionalLocalOptions!T)
        {
            writeLocalOptions!(T, false)(writer, optionColumnWidth);
            static if (builtinHelpEnabled!Root ||
                (is(Unqualified!T == Unqualified!Root) && builtinVersionEnabled!Root))
                writer.put('\n');
        }
        static if (builtinHelpEnabled!Root)
            writeBuiltinOptionLine(writer, "-h, --help", "Show this help", optionColumnWidth);
        static if (is(Unqualified!T == Unqualified!Root) &&
            builtinVersionEnabled!Root)
            writeBuiltinOptionLine(
                writer,
                "    --version",
                "Show the application version",
                optionColumnWidth,
            );
    }
}

private enum commandHelpLabelWidth(T) = commandName!T.length;

private enum commandHelpColumnWidth(T) = () {
    size_t result;
    static foreach (Child; CommandTypes!T)
        if (commandHelpLabelWidth!Child > result)
            result = commandHelpLabelWidth!Child;
    return result;
}();

private void writeHelpGap(ref AnsiWriter writer, size_t labelWidth, size_t columnWidth) @system
{
    writer.repeat(' ', columnWidth - labelWidth + 2);
}

private void writeHelpMetadataIndent(ref AnsiWriter writer, size_t columnWidth) @system
{
    writer.repeat(' ', columnWidth + 4);
}

private void writeHelpDetailPrefix(
    ref AnsiWriter writer,
    size_t labelWidth,
    size_t columnWidth,
    ref bool firstDetail,
) @system
{
    if (firstDetail)
    {
        writeHelpGap(writer, labelWidth, columnWidth);
        firstDetail = false;
    }
    else
        writeHelpMetadataIndent(writer, columnWidth);
}

private void writeCommandHelpLine(T)(ref AnsiWriter writer, size_t columnWidth) @system
{
    writer.put("  ");
    writer.styled(commandName!T, cliCanonicalStyle);
    bool firstDetail = true;
    enum aboutText = typeAbout!T;
    static if (aboutText.length != 0)
    {
        writeHelpDetailPrefix(
            writer,
            commandHelpLabelWidth!T,
            columnWidth,
            firstDetail,
        );
        writer.put(aboutText);
        writer.put('\n');
    }

    static if (commandAliases!T.length != 0)
    {
        writeHelpDetailPrefix(
            writer,
            commandHelpLabelWidth!T,
            columnWidth,
            firstDetail,
        );
        writer.styled("aliases:", cliMetadataStyle);
        writer.put(' ');
        bool first = true;
        static foreach (name; commandAliases!T)
        {
            if (!first)
                writer.put(", ");
            writer.styled(name, cliSecondaryStyle);
            first = false;
        }
        writer.put('\n');
    }

    if (firstDetail)
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

private void writeRequiredNamedOptionUsageAt(T, size_t index, bool global)(
    ref AnsiWriter writer,
) @system
{
    static if (!fieldHas!(T, index, CliPositional) &&
        fieldHas!(T, index, CliGlobal) == global &&
        !fieldHas!(T, index, CliHidden) &&
        fieldIsRequired!(T, index))
    {
        writer.put(' ');
        static if (fieldHas!(T, index, CliNegatable))
        {
            writer.put('(');
            writer.styled("--", fieldLongName!(T, index), cliCanonicalStyle);
            writer.put('|');
            writer.styled("--", fieldNegativeLongName!(T, index), cliCanonicalStyle);
            writer.put(')');
        }
        else
        {
            writer.styled("--", fieldLongName!(T, index), cliCanonicalStyle);
            static if (cliFieldTakesValue!(T, index))
            {
                writer.put(' ');
                writer.styled('<', fieldValueName!(T, index), '>', cliValueStyle);
            }
        }
    }
}

private void writeRequiredLocalOptionUsage(T)(ref AnsiWriter writer) @system
{
    static foreach (index; 0 .. cliFieldCount!T)
        writeRequiredNamedOptionUsageAt!(T, index, false)(writer);
}

private void writeRequiredGlobalOptionUsage(T)(ref AnsiWriter writer) @system
{
    static foreach (index; 0 .. cliFieldCount!T)
        writeRequiredNamedOptionUsageAt!(T, index, true)(writer);
}

private void writeOptionalOptionsUsage(ref AnsiWriter writer) @system
{
    writer.put(' ');
    writer.styled("[OPTIONS]", cliValueStyle);
}

private void writeStaticLocalUsagePath(Current, Path...)(ref AnsiWriter writer) @system
{
    writeRequiredLocalOptionUsage!Current(writer);
    static if (Path.length != 0)
    {
        static if (hasVisibleOptionalLocalOptions!Current)
            writeOptionalOptionsUsage(writer);
        writePositionalUsage!Current(writer);
        alias Child = Path[0];
        writer.put(' ');
        writer.styled(commandName!Child, cliCanonicalStyle);
        writeStaticLocalUsagePath!(Child, Path[1 .. $])(writer);
    }
}

private void writeStaticUsage(Root, Path...)(
    ref AnsiWriter writer,
    String programName,
) @system
{
    alias Target = HelpPathTarget!(Root, Path);

    writer.styled("Usage:", cliHeadingStyle);
    writer.put(' ');
    writer.styled(programName, cliCanonicalStyle);
    writeStaticLocalUsagePath!(Root, Path)(writer);
    writeRequiredGlobalsOnStaticPathUsage!(Root, Path)(writer);
    static if (hasVisibleOptionalLocalOptions!Target ||
        hasVisibleGlobalsOnStaticPath!(false, Root, Path) ||
        builtinHelpEnabled!Root ||
        (Path.length == 0 && builtinVersionEnabled!Root))
        writeOptionalOptionsUsage(writer);
    writeCommandOrPositionalUsage!Target(writer);
    writer.put('\n');
}

private void writeRequiredGlobalsOnStaticPathUsage(Parent, Path...)(
    ref AnsiWriter writer,
) @system
{
    writeRequiredGlobalOptionUsage!Parent(writer);
    static if (Path.length != 0)
        writeRequiredGlobalsOnStaticPathUsage!(Path[0], Path[1 .. $])(writer);
}

private template hasVisibleGlobalsOnStaticPath(bool required, Parent, Path...)
{
    static if (Path.length == 0)
        enum bool hasVisibleGlobalsOnStaticPath = required
            ? hasVisibleRequiredGlobalOptions!Parent : hasVisibleOptionalGlobalOptions!Parent;
    else
        enum bool hasVisibleGlobalsOnStaticPath = (required
                    ? hasVisibleRequiredGlobalOptions!Parent : hasVisibleOptionalGlobalOptions!Parent) ||
            hasVisibleGlobalsOnStaticPath!(required, Path[0], Path[1 .. $]);
}

private template globalsOnStaticPathHelpColumnWidth(bool required, Parent, Path...)
{
    static if (Path.length == 0)
        enum size_t globalsOnStaticPathHelpColumnWidth =
            visibleGlobalOptionHelpColumnWidth!(Parent, required);
    else
    {
        enum childWidth = globalsOnStaticPathHelpColumnWidth!(
                required,
                Path[0],
                Path[1 .. $],
            );
        enum currentWidth = visibleGlobalOptionHelpColumnWidth!(Parent, required);
        enum size_t globalsOnStaticPathHelpColumnWidth = currentWidth > childWidth
            ? currentWidth : childWidth;
    }
}

private void writeGlobalsOnStaticPath(bool required, Parent, Path...)(
    ref AnsiWriter writer,
    size_t columnWidth,
    ref bool first,
) @system
{
    writeVisibleGlobals!(Parent, required)(writer, columnWidth, first);
    static if (Path.length != 0)
        writeGlobalsOnStaticPath!(required, Path[0], Path[1 .. $])(
            writer,
            columnWidth,
            first,
        );
}

private void writeSelectedUsage(T)(
    ref AnsiWriter writer,
    String programName,
    ref ParsedCommand!T root,
) @system
{
    writer.styled("Usage:", cliHeadingStyle);
    writer.put(' ');
    writer.styled(programName, cliCanonicalStyle);
    writeActiveUsagePath!(T, T)(writer, root, root);
    writer.put('\n');
}

private void writeActiveUsagePath(Root, T)(
    ref AnsiWriter writer,
    ref ParsedCommand!Root tree,
    ref ParsedCommand!T node,
) @system
{
    writeRequiredLocalOptionUsage!T(writer);
    static foreach (Child; CommandTypes!T)
    {
        if (auto child = node.command!Child)
        {
            static if (hasVisibleOptionalLocalOptions!T)
                writeOptionalOptionsUsage(writer);
            writePositionalUsage!T(writer);
            writer.put(' ');
            writer.styled(commandName!Child, cliCanonicalStyle);
            writeActiveUsagePath!(Root, Child)(writer, tree, *child);
            return;
        }
    }

    writeRequiredGlobalsAlongActivePathUsage!Root(writer, tree);
    if (hasGlobalsAlongActivePath!(Root, false)(tree) ||
        hasVisibleOptionalLocalOptions!T || builtinHelpEnabled!Root ||
        (is(Unqualified!T == Unqualified!Root) && builtinVersionEnabled!Root))
        writeOptionalOptionsUsage(writer);
    writeCommandOrPositionalUsage!T(writer);
}

private void writeRequiredGlobalsAlongActivePathUsage(T)(
    ref AnsiWriter writer,
    ref ParsedCommand!T node,
) @system
{
    writeRequiredGlobalOptionUsage!T(writer);
    static foreach (Child; CommandTypes!T)
    {
        if (auto child = node.command!Child)
        {
            writeRequiredGlobalsAlongActivePathUsage!Child(writer, *child);
            return;
        }
    }
}

private void writeProgramPath(T)(
    ref AnsiWriter writer,
    String programName,
    ref ParsedCommand!T node,
) @system
{
    writer.styled(programName, cliCanonicalStyle);
    writeChildPath!T(writer, node);
}

private void writeChildPath(T)(ref AnsiWriter writer, ref ParsedCommand!T node)
@system
{
    static foreach (Child; CommandTypes!T)
    {
        if (auto child = node.command!Child)
        {
            writer.put(' ');
            writer.styled(commandName!Child, cliCanonicalStyle);
            writeChildPath!Child(writer, *child);
            return;
        }
    }
}

private void writeCommandOrPositionalUsage(T)(ref AnsiWriter writer) @system
{
    static if (hasSubcommands!T)
    {
        writePositionalUsage!T(writer);
        writer.put(' ');
        static if (subcommandIsOptional!T)
            writer.styled("[COMMAND]", cliValueStyle);
        else
            writer.styled("<COMMAND>", cliValueStyle);
    }
    else
        writePositionalUsage!T(writer);
}

private void writePositionalUsage(T)(ref AnsiWriter writer) @system
{
    static foreach (index; 0 .. cliFieldCount!T)
        writePositionalUsageAt!(T, index)(writer);
}

pragma(inline, true)
private void writePositionalUsageAt(T, size_t index)(ref AnsiWriter writer) @system
{
    static if (fieldHas!(T, index, CliPositional) &&
        !fieldHas!(T, index, CliHidden))
    {
        writer.put(' ');
        static if (fieldHas!(T, index, CliRest))
            writer.styled('[', fieldValueName!(T, index), "...", ']', cliValueStyle);
        else static if (fieldIsRequired!(T, index))
            writer.styled('<', fieldValueName!(T, index), '>', cliValueStyle);
        else
            writer.styled('[', fieldValueName!(T, index), ']', cliValueStyle);
    }
}

private enum hasVisiblePositionals(T) = () {
    bool result;
    static foreach (index; 0 .. cliFieldCount!T)
        static if (fieldHas!(T, index, CliPositional) &&
            !fieldHas!(T, index, CliHidden))
            result = true;
    return result;
}();

private enum hasVisibleRequiredLocalOptions(T) = () {
    bool result;
    static foreach (index; 0 .. cliFieldCount!T)
        static if (!fieldHas!(T, index, CliPositional) &&
            !fieldHas!(T, index, CliGlobal) &&
            !fieldHas!(T, index, CliHidden) &&
            fieldIsRequired!(T, index))
            result = true;
    return result;
}();

private enum hasVisibleOptionalLocalOptions(T) = () {
    bool result;
    static foreach (index; 0 .. cliFieldCount!T)
        static if (!fieldHas!(T, index, CliPositional) &&
            !fieldHas!(T, index, CliGlobal) &&
            !fieldHas!(T, index, CliHidden) &&
            !fieldIsRequired!(T, index))
            result = true;
    return result;
}();

private enum positionalHelpLabelWidth(T, size_t index) = fieldValueName!(T, index).length +
    (
        fieldHas!(T, index, CliRest) ? 5 : 2);

private enum positionalHelpColumnWidth(T) = () {
    size_t result;
    static foreach (index; 0 .. cliFieldCount!T)
        static if (fieldHas!(T, index, CliPositional) &&
            !fieldHas!(T, index, CliHidden))
            if (positionalHelpLabelWidth!(T, index) > result)
                result = positionalHelpLabelWidth!(T, index);
    return result;
}();

private void writePositionals(T)(ref AnsiWriter writer, size_t columnWidth) @system
{
    bool first = true;
    static foreach (index; 0 .. cliFieldCount!T)
    {
        static if (fieldHas!(T, index, CliPositional) &&
            !fieldHas!(T, index, CliHidden))
        {
            if (!first)
                writer.put('\n');
            writePositionalLine!(T, index)(writer, columnWidth);
            first = false;
        }
    }
}

pragma(inline, true)
private void writePositionalLine(T, size_t index)(
    ref AnsiWriter writer,
    size_t columnWidth,
) @system
{
    static if (fieldHas!(T, index, CliPositional) &&
        !fieldHas!(T, index, CliHidden))
    {
        writer.put("  ");
        static if (fieldHas!(T, index, CliRest))
            writer.styled('[', fieldValueName!(T, index), "...", ']', cliValueStyle);
        else static if (fieldIsRequired!(T, index))
            writer.styled('<', fieldValueName!(T, index), '>', cliValueStyle);
        else
            writer.styled('[', fieldValueName!(T, index), ']', cliValueStyle);
        writeFieldHelpBlock!(T, index)(
            writer,
            positionalHelpLabelWidth!(T, index),
            columnWidth,
        );
    }
}

private enum optionHelpLabelWidth(T, size_t index) = () {
    size_t result;
    static if (fieldShortName!(T, index) != '\0')
        result += 2;
    static if (fieldShortName!(T, index) != '\0')
        result += 2;
    else
        result += 4;
    result += 2 + fieldLongName!(T, index).length;
    static if (cliFieldTakesValue!(T, index))
    {
        result += 3 + fieldValueName!(T, index).length;
    }
    return result;
}();

private enum visibleLocalOptionHelpColumnWidth(T, bool required) = () {
    size_t result;
    static foreach (index; 0 .. cliFieldCount!T)
        static if (!fieldHas!(T, index, CliPositional) &&
            !fieldHas!(T, index, CliGlobal) &&
            !fieldHas!(T, index, CliHidden) &&
            fieldIsRequired!(T, index) == required)
            if (optionHelpLabelWidth!(T, index) > result)
                result = optionHelpLabelWidth!(T, index);
    return result;
}();

private enum visibleGlobalOptionHelpColumnWidth(T, bool required) = () {
    size_t result;
    static foreach (index; 0 .. cliFieldCount!T)
        static if (!fieldHas!(T, index, CliPositional) &&
            fieldHas!(T, index, CliGlobal) &&
            !fieldHas!(T, index, CliHidden) &&
            fieldIsRequired!(T, index) == required)
            if (optionHelpLabelWidth!(T, index) > result)
                result = optionHelpLabelWidth!(T, index);
    return result;
}();

private enum optionalLocalOptionHelpColumnWidth(Root, T) = () {
    size_t result = visibleLocalOptionHelpColumnWidth!(T, false);
    static if (builtinHelpEnabled!Root)
        if ("-h, --help".length > result)
            result = "-h, --help".length;
    static if (is(Unqualified!T == Unqualified!Root) && builtinVersionEnabled!Root)
        if ("    --version".length > result)
            result = "    --version".length;
    return result;
}();

private void writeLocalOptions(T, bool required)(
    ref AnsiWriter writer,
    size_t columnWidth,
) @system
{
    bool first = true;
    static foreach (index; 0 .. cliFieldCount!T)
    {
        static if (!fieldHas!(T, index, CliPositional) &&
            !fieldHas!(T, index, CliGlobal) &&
            !fieldHas!(T, index, CliHidden) &&
            fieldIsRequired!(T, index) == required)
        {
            if (!first)
                writer.put('\n');
            writeOptionLine!(T, index)(writer, columnWidth);
            first = false;
        }
    }
}

pragma(inline, true)
private void writeOptionLine(T, size_t index)(
    ref AnsiWriter writer,
    size_t columnWidth,
) @system
{
    writer.put("  ");
    enum shortName = fieldShortName!(T, index);
    static if (shortName != '\0')
        writer.styled('-', shortName, ", ", "--", fieldLongName!(T, index), cliCanonicalStyle);
    else
    {
        writer.put("    ");
        writer.styled("--", fieldLongName!(T, index), cliCanonicalStyle);
    }
    static if (cliFieldTakesValue!(T, index))
    {
        writer.put(' ');
        writer.styled('<', fieldValueName!(T, index), '>', cliValueStyle);
    }
    writeFieldHelpBlock!(T, index)(
        writer,
        optionHelpLabelWidth!(T, index),
        columnWidth,
    );
}

private void writeBuiltinOptionLine(
    ref AnsiWriter writer,
    String label,
    String helpText,
    size_t columnWidth,
) @system
{
    writer.put("  ");
    writer.styled(label, cliCanonicalStyle);
    writeHelpGap(writer, label.length, columnWidth);
    writer.put(helpText);
    writer.put('\n');
}

private void writeFieldHelpBlock(T, size_t index)(
    ref AnsiWriter writer,
    size_t labelWidth,
    size_t columnWidth,
) @system
{
    enum helpText = fieldHelp!(T, index);
    enum possibleValues = fieldHelpPossibleValues!(T, index);
    enum hasDefault = fieldHasHelpDefault!(T, index);
    bool firstDetail = true;

    static if (helpText.length != 0)
    {
        writeHelpDetailPrefix(writer, labelWidth, columnWidth, firstDetail);
        writer.put(helpText);
        writer.put('\n');
    }

    static if (!fieldHas!(T, index, CliPositional) &&
        (fieldShortAliases!(T, index).length != 0 ||
            fieldLongAliases!(T, index).length != 0))
    {
        writeHelpDetailPrefix(writer, labelWidth, columnWidth, firstDetail);
        writer.styled("aliases:", cliMetadataStyle);
        writer.put(' ');
        bool firstAlias = true;
        static foreach (shortAlias; fieldShortAliases!(T, index))
        {
            if (!firstAlias)
                writer.put(", ");
            writer.styled('-', shortAlias, cliSecondaryStyle);
            firstAlias = false;
        }
        static foreach (longAlias; fieldLongAliases!(T, index))
        {
            if (!firstAlias)
                writer.put(", ");
            writer.styled("--", longAlias, cliSecondaryStyle);
            firstAlias = false;
        }
        writer.put('\n');
    }

    static if (!fieldHas!(T, index, CliPositional) &&
        fieldHas!(T, index, CliNegatable))
    {
        writeHelpDetailPrefix(writer, labelWidth, columnWidth, firstDetail);
        writer.styled("negatable:", cliMetadataStyle);
        writer.put(' ');
        writer.styled("--", fieldNegativeLongName!(T, index), cliSecondaryStyle);
        writer.put('\n');
    }

    static if (possibleValues.length != 0)
    {
        writeHelpDetailPrefix(writer, labelWidth, columnWidth, firstDetail);
        writer.styled("values:", cliMetadataStyle);
        writer.put(' ');
        bool firstValue = true;
        static foreach (value; possibleValues)
        {
            if (!firstValue)
                writer.put(", ");
            writer.styled(value, cliValueStyle);
            firstValue = false;
        }
        writer.put('\n');
    }

    static if (hasDefault)
    {
        writeHelpDetailPrefix(writer, labelWidth, columnWidth, firstDetail);
        writer.styled("default:", cliMetadataStyle);
        writer.put(' ');
        writeFieldHelpDefault!(T, index)(writer);
        writer.put('\n');
    }

    if (firstDetail)
        writer.put('\n');
}

private struct CliFormattedDefault(alias Representation, T)
{
nothrow @nogc:

    const(T)* value;

    void formatTo(ref Writer writer) const
    {
        Representation.format(writer, value);
    }
}

private void writeFieldHelpDefault(T, size_t index)(ref AnsiWriter writer) @system
{
    static assert(fieldHasHelpDefault!(T, index));
    static if (fieldHasDefaultInput!(T, index))
        writer.styled(fieldDefaultInput!(T, index), cliDefaultStyle);
    else
    {
        alias Field = Unqualified!(FieldType!(T, index));
        static assert(fieldHasDefault!(T, index));
        T defaults = T.init;
        ref value = cliFieldRef!(T, index)(defaults);
        static if (fieldHasValueWith!(T, index))
        {
            alias Representation = FieldValueRepresentation!(T, index);
            static if (cliRepresentationHasFormatter!(Representation, Field))
            {
                auto formatted = CliFormattedDefault!(Representation, Field)(&value);
                writer.styled(formatted, cliDefaultStyle);
            }
            else static if (is(Field == enum))
                writer.styled(fieldAutomaticEnumDefaultName!(T, index), cliDefaultStyle);
            else static if (is(Field == char) || is(Field == wchar) || is(Field == dchar))
                writer.styled(cast(uint) value, cliDefaultStyle);
            else
                writer.styled(value, cliDefaultStyle);
        }
        else static if (is(Field == enum))
            writer.styled(fieldAutomaticEnumDefaultName!(T, index), cliDefaultStyle);
        else static if (is(Field == char) || is(Field == wchar) || is(Field == dchar))
            writer.styled(cast(uint) value, cliDefaultStyle);
        else
            writer.styled(value, cliDefaultStyle);
    }
}

private enum hasVisibleRequiredGlobalOptions(T) = () {
    bool result;
    static foreach (index; 0 .. cliFieldCount!T)
        static if (!fieldHas!(T, index, CliPositional) &&
            fieldHas!(T, index, CliGlobal) &&
            !fieldHas!(T, index, CliHidden) &&
            fieldIsRequired!(T, index))
            result = true;
    return result;
}();

private enum hasVisibleOptionalGlobalOptions(T) = () {
    bool result;
    static foreach (index; 0 .. cliFieldCount!T)
        static if (!fieldHas!(T, index, CliPositional) &&
            fieldHas!(T, index, CliGlobal) &&
            !fieldHas!(T, index, CliHidden) &&
            !fieldIsRequired!(T, index))
            result = true;
    return result;
}();

private void writeVisibleGlobals(T, bool required)(
    ref AnsiWriter writer,
    size_t columnWidth,
    ref bool first,
) @system
{
    static foreach (index; 0 .. cliFieldCount!T)
        static if (!fieldHas!(T, index, CliPositional) &&
            fieldHas!(T, index, CliGlobal) &&
            !fieldHas!(T, index, CliHidden) &&
            fieldIsRequired!(T, index) == required)
            {
            if (!first)
                writer.put('\n');
            writeOptionLine!(T, index)(writer, columnWidth);
            first = false;
        }
}

private bool hasGlobalsAlongActivePath(T, bool required)(ref ParsedCommand!T node) @system
{
    static if (required ? hasVisibleRequiredGlobalOptions!T : hasVisibleOptionalGlobalOptions!T)
        return true;
    static foreach (Child; CommandTypes!T)
        if (auto child = node.command!Child)
            return hasGlobalsAlongActivePath!(Child, required)(*child);
    return false;
}

private size_t globalsAlongActivePathHelpColumnWidth(T, bool required)(
    ref ParsedCommand!T node,
) @system
{
    size_t result = visibleGlobalOptionHelpColumnWidth!(T, required);
    static foreach (Child; CommandTypes!T)
    {
        if (auto child = node.command!Child)
        {
            const childWidth = globalsAlongActivePathHelpColumnWidth!(Child, required)(*child);
            if (childWidth > result)
                result = childWidth;
            return result;
        }
    }
    return result;
}

private void writeGlobalsAlongActivePath(T, bool required)(
    ref AnsiWriter writer,
    ref ParsedCommand!T node,
    size_t columnWidth,
    ref bool first,
) @system
{
    writeVisibleGlobals!(T, required)(writer, columnWidth, first);
    static foreach (Child; CommandTypes!T)
    {
        if (auto child = node.command!Child)
        {
            writeGlobalsAlongActivePath!(Child, required)(writer, *child, columnWidth, first);
            return;
        }
    }
}

private void writeVersion(T)(ref AnsiWriter writer, String programName) @system
{
    writer.styled(programName, cliCanonicalStyle);
    writer.put(' ');
    writer.styled(typeVersion!T, cliDefaultStyle);
    writer.put('\n');
}

private void writeErrorFieldName(T)(
    ref AnsiWriter writer,
    ref ParsedCommand!T node,
    size_t targetDepth,
    size_t fieldIndex,
    size_t currentDepth,
    bool valueName,
) @system
{
    if (targetDepth == currentDepth)
    {
        static foreach (index; 0 .. cliFieldCount!T)
        {
            if (fieldIndex == index)
            {
                if (valueName)
                    writer.styled(fieldValueName!(T, index), cliValueStyle);
                else
                    writer.styled(fieldLongName!(T, index), cliCanonicalStyle);
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
    ref AnsiWriter writer,
    CliError error,
    ref ParsedCommand!T root,
) @system
{
    writer.styled("error:", cliErrorStyle);
    writer.put(' ');
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
            writer.styled(error.token, cliValueStyle);
            writer.put("'");
            break;
        case CliErrorKind.unknownCommand:
            writer.put("unknown command '");
            writer.styled(error.token, cliValueStyle);
            writer.put("'");
            break;
        case CliErrorKind.missingOptionValue:
            writer.put("missing value for ");
            writer.put(error.detail);
            break;
        case CliErrorKind.invalidValue:
            if (error.valueError.kind == CliValueErrorKind.outOfRange)
                writer.put("value '");
            else
                writer.put("invalid value '");
            writer.styled(error.token, cliValueStyle);
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
            if (error.valueError.kind == CliValueErrorKind.outOfRange)
                writer.put(" is out of range");
            if (error.valueError.message.length != 0)
            {
                writer.put(": ");
                writer.put(error.valueError.message);
            }
            break;
        case CliErrorKind.invalidDefault:
            writer.put("application default '");
            writer.styled(error.token, cliValueStyle);
            writer.put("' for ");
            writeErrorFieldName!T(
                writer,
                root,
                error.commandDepth,
                error.fieldIndex,
                0,
                true,
            );
            writer.put(" is invalid");
            if (error.valueError.kind == CliValueErrorKind.outOfRange)
                writer.put(" (out of range)");
            if (error.valueError.message.length != 0)
            {
                writer.put(": ");
                writer.put(error.valueError.message);
            }
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
            writer.styled(error.token, cliValueStyle);
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
            if (error.valueError.message.length != 0)
            {
                writer.put(": ");
                writer.put(error.valueError.message);
            }
            break;
    }
}
