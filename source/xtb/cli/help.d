module xtb.cli.help;

nothrow @nogc:

import core.stdc.stdio : stderr, stdout;
import xtb.cli.attributes;
import xtb.cli.internal.traits;
import xtb.cli.parser : CliError, CliErrorKind, CliOutcomeKind, CliParseResult, ParsedCommand, normalizeProgramName;
import xtb.cli.value : CliValueErrorKind;
import xtb.core.ansi : AnsiColor, AnsiStyle;
import xtb.core.fmt.ansi : AnsiWriter;
import xtb.core.fmt.buffered_writer : BufferedWriter;
import xtb.core.fmt.print : fileWriter;
import xtb.core.fmt.writer : Writer;
import xtb.core.types : String;

private enum cliHeadingStyle = AnsiStyle.init.bold;
private enum cliCanonicalStyle = AnsiStyle.foreground(AnsiColor.brightCyan).bold;
private enum cliSecondaryStyle = AnsiStyle.foreground(AnsiColor.cyan).dim;
private enum cliValueStyle = AnsiStyle.foreground(AnsiColor.brightYellow);
private enum cliDefaultStyle = AnsiStyle.foreground(AnsiColor.brightGreen);
private enum cliMetadataStyle = AnsiStyle.init.dim;
private enum cliErrorStyle = AnsiStyle.foreground(AnsiColor.brightRed).bold;

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
            writeSelectedHelp!T(styledOutput, result.programName, result.invocation);
            return 0;
        case CliOutcomeKind.version_:
            writeVersion!T(styledOutput, result.programName);
            return 0;
        case CliOutcomeKind.terminal:
            return 0;
        case CliOutcomeKind.error:
            writeError!T(styledError, result.mutableError, result.invocation);
            styledError.put('\n');
            writeSelectedUsage!T(styledError, result.programName, result.invocation);
            static if (builtinHelpEnabled!T)
            {
                styledError.put("\nTry '");
                writeProgramPath!T(styledError, result.programName, result.invocation);
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
