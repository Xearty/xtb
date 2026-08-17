module xtb.core.pretty_print;

nothrow @nogc:

import xtb.core.ansi : AnsiColor, AnsiStyle, beginAnsi, endAnsi;
import xtb.core.lifetime : lifetimeDeinit = deinit,
    isTaggedPayloadField,
    move,
    needsDeinit,
    taggedBy,
    taggedCase,
    taggedPayloadDiscriminatorIndex,
    taggedPayloadMemberTag,
    taggedPayloadMetadata;

version (unittest)
{
    import xtb.core.array;
    import xtb.core.flag_set : FlagSet;
    import xtb.core.hash_map;
    import xtb.core.owned_string;
    import xtb.core.option : Option;
    import xtb.core.result : Result;
    import xtb.core.string;
    import xtb.core.string_hash_map;
    import xtb.core.string_hash_set;
}
import xtb.core.print : Writer;
import xtb.core.types : String;

/// Controls how aggregate values are laid out.
enum PrettyPrintLayout : ubyte
{
    /// Use a conservative allocation-free width estimate. Unknown-width values
    /// are printed expanded, so custom formatters are never called twice.
    automatic,

    /// Always print aggregates on one line.
    compact,

    /// Print non-empty aggregates across multiple lines.
    expanded,
}

/// ANSI styles used by the default pretty printer.
///
/// The default-initialized value is a complete, usable scheme. Replace
/// individual fields or pass a different scheme through `PrettyPrintOptions`.
struct PrettyPrintColorScheme
{
    AnsiStyle typeName = AnsiStyle.foreground(AnsiColor.brightMagenta);
    AnsiStyle fieldName = AnsiStyle.foreground(AnsiColor.brightCyan);
    AnsiStyle stringValue = AnsiStyle.foreground(AnsiColor.green);
    AnsiStyle characterValue = AnsiStyle.foreground(AnsiColor.green);
    AnsiStyle numberValue = AnsiStyle.foreground(AnsiColor.blue);
    AnsiStyle booleanValue = AnsiStyle.foreground(AnsiColor.yellow);
    AnsiStyle enumValue = AnsiStyle.foreground(AnsiColor.brightGreen);
    AnsiStyle nullValue = AnsiStyle.foreground(AnsiColor.brightBlack);
    AnsiStyle pointerValue = AnsiStyle.foreground(AnsiColor.magenta);
    AnsiStyle punctuation;
    AnsiStyle truncation = AnsiStyle.foreground(AnsiColor.brightBlack);
    AnsiStyle depthLimit = AnsiStyle.foreground(AnsiColor.brightRed);
    AnsiStyle unsupported = AnsiStyle.foreground(AnsiColor.brightRed);

    static PrettyPrintColorScheme defaults()
    pure nothrow @nogc @safe
    {
        return PrettyPrintColorScheme.init;
    }
}

/// Runtime policy for pretty printing.
///
/// `PrettyPrintOptions.init` is deliberately useful. Callers only need to pass
/// options when they want to change a policy or color. `softMaxWidth` counts
/// emitted UTF-8 bytes while ignoring ANSI sequences; it is a layout hint, not
/// a Unicode terminal-column measurement.
struct PrettyPrintOptions
{
    ushort indentSize = 2;
    ushort maxDepth = 8;
    uint maxItems = 32;
    uint softMaxWidth = 80;
    PrettyPrintLayout layout = PrettyPrintLayout.automatic;
    bool colored = true;
    bool showTypeNames = true;

    /// Pointers are shown as typed addresses by default. Enabling this follows
    /// the pointer and is useful for trusted object graphs, but may be unsafe
    /// for stale or otherwise invalid pointers.
    bool dereferencePointers;

    PrettyPrintColorScheme colorScheme;

    static PrettyPrintOptions defaults()
    pure nothrow @nogc @safe
    {
        return PrettyPrintOptions.init;
    }

    PrettyPrintOptions withColorScheme(PrettyPrintColorScheme scheme) const
    pure nothrow @nogc @safe
    {
        PrettyPrintOptions result = this;
        result.colorScheme = scheme;
        return result;
    }

    PrettyPrintOptions withoutColors() const
    pure nothrow @nogc @safe
    {
        PrettyPrintOptions result = this;
        result.colored = false;
        return result;
    }

    PrettyPrintOptions withLayout(PrettyPrintLayout requested) const
    pure nothrow @nogc @safe
    {
        PrettyPrintOptions result = this;
        result.layout = requested;
        return result;
    }
}

/// Borrowed formatting wrapper accepted by every `xtb.core.print` entry point.
///
/// The zero value is safe and prints `null`. A wrapper returned from the
/// lvalue overload of `pretty` borrows its source and must not outlive it.
/// The stored pointer is const-qualified because pretty printing is an
/// observation and must not mutate the inspected value.
struct PrettyValue(T)
{
    private const(T)* value_;
    PrettyPrintOptions options;

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writePrettyPointer!T(writer, value_, options);
    }
}

/// Owning formatting wrapper used when `pretty` receives an rvalue.
///
/// Keeping the temporary inside the wrapper makes expressions such as
/// `writeln(Point(1, 2).pretty)` valid without retaining a dangling pointer.
/// Copying follows `T`: a wrapper around a non-copyable value is non-copyable.
/// References contained inside `T` remain borrowed; the `return scope` rvalue
/// overload preserves those source lifetimes instead of pretending to deep-own
/// pointed-to storage.
struct OwnedPrettyValue(T)
{
    private T value_;
    PrettyPrintOptions options;

    static if (needsDeinit!T)
    {
        @disable this(this);
        @disable ref OwnedPrettyValue opAssign(OwnedPrettyValue source) return;

        ~this()
        {
            lifetimeDeinit(value_);
        }
    }

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writePrettyImpl(writer, value_, options, PrettyPrintContext.init);
    }
}

private void writePrettyPointer(T)(
    ref Writer writer,
    scope const(T)* value,
    scope const ref PrettyPrintOptions options,
)
{
    if (value is null)
    {
        writeStyledText(
            writer,
            "null",
            options.colorScheme.nullValue,
            options,
        );
        return;
    }
    writePrettyImpl(writer, *value, options, PrettyPrintContext.init);
}

/// Borrows an lvalue for `write`, `writeln`, `writeBuffer`, and the other
/// `xtb.core.print` APIs. This overload is preferred for lvalues and does not
/// copy the source value.
PrettyValue!T pretty(T)(
    return ref scope T value,
    PrettyPrintOptions options = PrettyPrintOptions.init,
)
@trusted
{
    // Taking and storing the address is the only system operation. The
    // `return ref scope` ties the returned wrapper to the address of `value`
    // at safe call sites; `scope` also prevents unrelated escapes inside this
    // boundary. The wrapper never mutates through the pointer.
    PrettyValue!T result;
    result.value_ = &value;
    result.options = options;
    return result;
}

/// Owns an rvalue for `write`, `writeln`, `writeBuffer`, and the other
/// `xtb.core.print` APIs. This overload is preferred for temporaries.
OwnedPrettyValue!T pretty(T)(
    return scope T value,
    PrettyPrintOptions options = PrettyPrintOptions.init,
)
@trusted
{
    // XTB `move` transfers the value into the returned wrapper and reconstructs
    // explicit-lifetime owners to `T.init`; no reference is fabricated here.
    return OwnedPrettyValue!T(move(value), options);
}

/// Writes a value directly without constructing a wrapper.
///
/// Prefer a const-compatible
/// `void prettyDescribe(Pretty)(scope ref Pretty)` member
/// that describes the value through `pretty.value`, `atom`, `constructor`,
/// `sequence`, `map`, `set`, or `flags`. The description is interpreted both
/// for rendering and width measurement, so it must be deterministic,
/// observational, and safe to invoke more than once.
///
/// `void prettyFormatTo(ref Writer, scope const ref PrettyPrintOptions)`
/// remains the low-level escape hatch for syntax that cannot use those
/// semantic forms. Its automatic width is unknown. A type must not define both
/// pretty hooks.
/// Ordinary `formatRepresentation` and `formatTo` are separate normal-display
/// customization points and are deliberately ignored here.
void writePretty(T)(
    ref Writer writer,
    auto ref T value,
    PrettyPrintOptions options = PrettyPrintOptions.init,
)
{
    writePrettyImpl(writer, value, options, PrettyPrintContext.init);
}

private template Unqualified(T)
{
    alias Unqualified = typeof(cast() T.init);
}

private enum isStringType(T) = is(Unqualified!T == String) ||
    is(Unqualified!T == char[]) || is(Unqualified!T == const(char)[]) ||
    is(Unqualified!T == immutable(char)[]);

private enum isCharacterType(T) = is(Unqualified!T == char) ||
    is(Unqualified!T == wchar) || is(Unqualified!T == dchar);

// `void` has no value to dereference. Keep this check independent of
// `Unqualified`, whose implementation intentionally operates on value types
// and therefore cannot be instantiated for `void` itself.
private enum isVoidPointee(T) = is(T == void) || is(T == const(void)) ||
    is(T == immutable(void));

// Keep pointer recognition in its own template scope. Binding a pointee alias
// directly in more than one `static if` condition inside the same function
// redeclares that alias for pointer instantiations.
private enum isPointerType(T) = is(Unqualified!T == Pointee*, Pointee);

/// Tracks semantic recursion separately from visual indentation. Constructor-
/// like wrappers such as `some(...)` and `&...` increase recursion depth but
/// do not add an indentation level when their child starts on the same line.
private struct PrettyPrintContext
{
    ushort recursionDepth;
    ushort indentationDepth;
}

private enum PrettyRole : ubyte
{
    nullValue,
}

private struct PrettyRender(Described)
{
    Writer* writer_;
    const(PrettyPrintOptions)* options_;
    PrettyPrintContext context_;

    enum nullRole = PrettyRole.nullValue;

    void value(Value)(auto ref Value semanticValue)
    {
        writePrettyImpl(*writer_, semanticValue, *options_, context_);
    }

    void atom(scope String name, PrettyRole role)
    {
        writeSemanticTypePrefix!Described(*writer_, *options_, '.');
        writeStyledText(
            *writer_,
            name,
            prettyRoleStyle(role, *options_),
            *options_,
        );
    }

    void constructor(scope String name)
    {
        writeSemanticTypePrefix!Described(*writer_, *options_, '.');
        writeStyledText(
            *writer_,
            name,
            options_.colorScheme.booleanValue,
            *options_,
        );
        writePunctuation(*writer_, "()", *options_);
    }

    void constructor(Value)(scope String name, auto ref Value payload)
    {
        writeSemanticTypePrefix!Described(*writer_, *options_, '.');
        writeStyledText(
            *writer_,
            name,
            options_.colorScheme.booleanValue,
            *options_,
        );
        writePunctuation(*writer_, '(', *options_);
        if (depthLimitReached(context_.recursionDepth, *options_))
            writeDepthLimit(*writer_, *options_);
        else
        {
            PrettyPrintContext childContext = descendWrapper(context_);
            writePrettyImpl(*writer_, payload, *options_, childContext);
        }
        writePunctuation(*writer_, ')', *options_);
    }

    void sequence(Source)(auto ref Source source)
    {
        validatePrettySequenceSource(source);
        writeSemanticSequence!Described(
            *writer_,
            source,
            *options_,
            context_,
        );
    }

    void map(Source)(auto ref Source source)
    {
        validatePrettyMapSource(source);
        writeHashMap!Described(*writer_, source, *options_, context_);
    }

    void set(Source)(auto ref Source source)
    {
        validatePrettySetSource(source);
        writeHashSet!Described(*writer_, source, *options_, context_);
    }

    void flags(Source)(auto ref Source source)
    {
        validatePrettyFlagsSource(source);
        writeFlagSet!Described(*writer_, source, *options_, context_);
    }
}

private struct PrettyMeasure(Described)
{
    const(PrettyPrintOptions)* options_;
    PrettyPrintContext context_;
    size_t budget_;
    WidthEstimate result_ = WidthEstimate(true, 0);

    enum nullRole = PrettyRole.nullValue;

    WidthEstimate result() const pure @safe
    {
        return result_;
    }

    void value(Value)(auto ref Value semanticValue)
    {
        append(estimateWidth(
                semanticValue,
                *options_,
                context_.recursionDepth,
                remainingBudget,
        ));
    }

    void atom(scope String name, PrettyRole)
    {
        size_t width = semanticTypePrefixWidth!Described(*options_);
        if (name.length > size_t.max - width)
        {
            result_ = unknownWidth();
            return;
        }
        width += name.length;
        append(knownWidth(width));
    }

    void constructor(scope String name)
    {
        size_t width = semanticTypePrefixWidth!Described(*options_);
        if (name.length > size_t.max - width ||
            2 > size_t.max - width - name.length)
        {
            result_ = unknownWidth();
            return;
        }
        width += name.length + 2;
        append(knownWidth(width));
    }

    void constructor(Value)(scope String name, auto ref Value payload)
    {
        size_t width = semanticTypePrefixWidth!Described(*options_);
        if (name.length > size_t.max - width ||
            1 > size_t.max - width - name.length)
        {
            result_ = unknownWidth();
            return;
        }
        width += name.length + 1;

        if (depthLimitReached(context_.recursionDepth, *options_))
        {
            if (4 > size_t.max - width)
            {
                result_ = unknownWidth();
                return;
            }
            width += 4;
            append(knownWidth(width));
            return;
        }

        const available = remainingBudget;
        const child = estimateWidth(
            payload,
            *options_,
            nextDepth(context_.recursionDepth),
            available > width ? available - width : 0,
        );
        if (!child.known || child.width > size_t.max - width)
        {
            result_ = unknownWidth();
            return;
        }
        width += child.width;
        if (width == size_t.max)
        {
            result_ = unknownWidth();
            return;
        }
        ++width;
        append(knownWidth(width));
    }

    void sequence(Source)(auto ref Source source)
    {
        validatePrettySequenceSource(source);
        append(estimateSemanticSequence!Described(
                source,
                *options_,
                context_.recursionDepth,
                remainingBudget,
        ));
    }

    void map(Source)(auto ref Source source)
    {
        validatePrettyMapSource(source);
        append(estimateHashMap!Described(
                source,
                *options_,
                context_.recursionDepth,
                remainingBudget,
        ));
    }

    void set(Source)(auto ref Source source)
    {
        validatePrettySetSource(source);
        append(estimateHashSet!Described(
                source,
                *options_,
                context_.recursionDepth,
                remainingBudget,
        ));
    }

    void flags(Source)(auto ref Source source)
    {
        validatePrettyFlagsSource(source);
        append(estimateFlagSet!Described(
                source,
                *options_,
                remainingBudget,
        ));
    }

private:
    size_t remainingBudget() const pure @safe
    {
        if (!result_.known || result_.width >= budget_)
            return 0;
        return budget_ - result_.width;
    }

    void append(WidthEstimate part) pure @safe
    {
        if (!result_.known || !part.known ||
            part.width > size_t.max - result_.width)
        {
            result_ = unknownWidth();
            return;
        }
        const total = result_.width + part.width;
        if (total > budget_)
        {
            result_ = unknownWidth();
            return;
        }
        result_ = knownWidth(total);
    }
}

private enum hasPrettyDescribe(T) =
    __traits(hasMember, Unqualified!T, "prettyDescribe");

private enum hasPrettyFormatToMember(T) =
    __traits(hasMember, Unqualified!T, "prettyFormatTo");

private void validatePrettySequenceSource(Source)(scope const ref Source source)
{
    static assert(__traits(compiles, source.length) &&
            __traits(compiles, source[0]),
        "pretty.sequence source must provide length and indexed access");
}

private void validatePrettyMapSource(Source)(scope const ref Source source)
{
    static assert(__traits(compiles, source.length) &&
            __traits(compiles, source.cursor()),
        "pretty.map source must provide length and cursor()");
    alias Cursor = typeof(source.cursor());
    static assert(__traits(compiles, Cursor.init.valid) &&
            __traits(compiles, *Cursor.init.key) &&
            __traits(compiles, *Cursor.init.value) &&
            __traits(compiles, { Cursor cursor; cursor.advance(); }),
        "pretty.map cursor must provide valid, key, value, and advance()");
}

private void validatePrettySetSource(Source)(scope const ref Source source)
{
    static assert(__traits(compiles, source.length) &&
            __traits(compiles, source.cursor()),
        "pretty.set source must provide length and cursor()");
    alias Cursor = typeof(source.cursor());
    static assert(__traits(compiles, Cursor.init.valid) &&
            __traits(compiles, *Cursor.init.value) &&
            __traits(compiles, { Cursor cursor; cursor.advance(); }),
        "pretty.set cursor must provide valid, value, and advance()");
}

private void validatePrettyFlagsSource(Source)(scope const ref Source source)
{
    alias U = Unqualified!Source;
    static assert(__traits(hasMember, U, "FlagType") &&
            __traits(compiles, source.enabledCount),
        "pretty.flags source must provide FlagType and enabledCount");
    static if (__traits(hasMember, U, "FlagType"))
    {
        alias Flag = U.FlagType;
        static foreach (name; __traits(allMembers, Flag))
        {
            {
                enum flag = __traits(getMember, Flag, name);
                static assert(__traits(compiles, source.contains(flag)),
                    "pretty.flags source must provide contains(FlagType)");
            }
        }
    }
}

private size_t semanticTypePrefixWidth(Described)(
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    return options.showTypeNames ? Described.stringof.length + 1 : 0;
}

private void writeSemanticTypePrefix(Described)(
    ref Writer writer,
    scope const ref PrettyPrintOptions options,
    char separator,
)
{
    if (!options.showTypeNames)
        return;
    writeTypeName!Described(writer, options);
    writePunctuation(writer, separator, options);
}

private AnsiStyle prettyRoleStyle(
    PrettyRole role,
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    final switch (role)
    {
        case PrettyRole.nullValue:
            return options.colorScheme.nullValue;
    }
}

private void writePrettyImpl(T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;

    static if (isPointerType!U)
    {
        if (value is null)
        {
            writeStyledText(
                writer,
                "null",
                options.colorScheme.nullValue,
                options,
            );
            return;
        }
    }

    static assert(!(hasPrettyDescribe!T && hasPrettyFormatToMember!T),
        U.stringof ~ " defines both prettyDescribe and prettyFormatTo");

    static if (hasPrettyDescribe!T)
    {
        PrettyRender!U pretty = PrettyRender!U(&writer, &options, context);
        alias DescribeReturn = typeof(value.prettyDescribe(pretty));
        static assert(is(DescribeReturn == void), U.stringof ~
                ".prettyDescribe(...) must return void");
        value.prettyDescribe(pretty);
    }
    else static if (hasPrettyFormatTo!T)
    {
        alias FormatReturn = typeof(value.prettyFormatTo(writer, options));
        static assert(is(FormatReturn == void), U.stringof ~
                ".prettyFormatTo(...) must return void");
        value.prettyFormatTo(writer, options);
    }
    else static if (is(U == typeof(null)))
    {
        writeStyledText(
            writer,
            "null",
            options.colorScheme.nullValue,
            options,
        );
    }
    else static if (isStringType!U)
    {
        writeString(writer, cast(String) value, options);
    }
    else static if (is(U == bool))
    {
        writeStyledText(
            writer,
            value ? "true" : "false",
            options.colorScheme.booleanValue,
            options,
        );
    }
    else static if (isCharacterType!U)
    {
        writeCharacter(writer, value, options);
    }
    else static if (is(U == enum))
    {
        writeEnum(writer, value, options);
    }
    else static if ((__traits(isIntegral, U) &&
            U.sizeof <= ulong.sizeof) || __traits(isFloating, U))
    {
        writeStyledValue(
            writer,
            value,
            options.colorScheme.numberValue,
            options,
        );
    }
    else static if (is(U == Element[], Element))
    {
        writeSlice(writer, value, options, context);
    }
    else static if (is(U == Element[N], Element, size_t N))
    {
        static if (is(Element == char) || is(Element == const(char)) ||
            is(Element == immutable(char)))
            writeString(writer, cast(String) value[], options);
        else
            writeIndexableSequence(writer, value, N, options, context);
    }
    else static if (is(U == Pointee*, Pointee))
    {
        writePointer!(T, Pointee)(writer, value, options, context);
    }
    else
    {
        writeDefaultAggregateOrUnsupported(writer, value, options, context);
    }
}

private enum hasPrettyFormatTo(T) = __traits(compiles,
{
        const(Unqualified!T)* value;
        Writer* writer;
        const(PrettyPrintOptions)* options;
        (*value).prettyFormatTo(*writer, *options);
    });

private void writeDefaultAggregateOrUnsupported(T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;
    static if (is(U == struct))
        writeStruct(writer, value, options, context);
    else static if (is(U == union))
        writeUnion(writer, value, options, context);
    else
        writeUnsupported!U(writer, options);
}

private void writeSemanticSequence(Display, T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (options.showTypeNames)
    {
        writeTypeName!Display(writer, options);
        writer.put(' ');
    }
    writeIndexableSequence(writer, value, value.length, options, context);
}

private void writeSlice(T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    writeIndexableSequence(writer, value, value.length, options, context);
}

private void writeIndexableSequence(T)(
    ref Writer writer,
    scope const ref T value,
    size_t length,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (length == 0)
    {
        writePunctuation(writer, "[]", options);
        return;
    }
    if (depthLimitReached(context.recursionDepth, options))
    {
        writeDepthLimit(writer, options);
        return;
    }

    const compact = chooseCompact(value, options, context);
    const shown = limitedItemCount(length, options.maxItems);
    const truncated = shown < length;
    PrettyPrintContext childContext = descendAggregate(context);

    writePunctuation(writer, '[', options);
    if (!compact)
        writer.put('\n');

    foreach (index; 0 .. shown)
    {
        if (compact)
        {
            if (index != 0)
                writePunctuation(writer, ", ", options);
        }
        else
            writeIndent(writer, childContext.indentationDepth, options);

        writePrettyImpl(writer, value[index], options, childContext);

        if (!compact)
        {
            if (index + 1 < shown || truncated)
                writePunctuation(writer, ',', options);
            writer.put('\n');
        }
    }

    if (truncated)
    {
        if (compact)
        {
            if (shown != 0)
                writePunctuation(writer, ", ", options);
        }
        else
            writeIndent(writer, childContext.indentationDepth, options);
        writeTruncation(writer, length - shown, options);
        if (!compact)
            writer.put('\n');
    }

    if (!compact)
        writeIndent(writer, context.indentationDepth, options);
    writePunctuation(writer, ']', options);
}

private void writeFlagSet(Display, T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;
    alias Flag = U.FlagType;

    if (options.showTypeNames)
    {
        writeTypeName!Display(writer, options);
        writer.put(' ');
    }

    const length = value.enabledCount;
    if (length == 0)
    {
        writePunctuation(writer, "{}", options);
        return;
    }

    const compact = chooseCompact(value, options, context);
    const shown = limitedItemCount(length, options.maxItems);
    const truncated = shown < length;
    PrettyPrintContext itemContext = descendIndentation(context);
    size_t written;

    writePunctuation(writer, '{', options);
    if (!compact)
        writer.put('\n');

    static foreach (name; __traits(allMembers, Flag))
    {
        {
            enum flag = __traits(getMember, Flag, name);
            if (value.contains(flag) && written < shown)
            {
                if (compact)
                {
                    if (written != 0)
                        writePunctuation(writer, ", ", options);
                }
                else
                    writeIndent(writer, itemContext.indentationDepth, options);

                writeStyledText(
                    writer,
                    name,
                    options.colorScheme.enumValue,
                    options,
                );

                ++written;
                if (!compact)
                {
                    if (written < shown || truncated)
                        writePunctuation(writer, ',', options);
                    writer.put('\n');
                }
            }
        }
    }

    if (truncated)
    {
        if (compact)
        {
            if (shown != 0)
                writePunctuation(writer, ", ", options);
        }
        else
            writeIndent(writer, itemContext.indentationDepth, options);
        writeTruncation(writer, length - shown, options);
        if (!compact)
            writer.put('\n');
    }

    if (!compact)
        writeIndent(writer, context.indentationDepth, options);
    writePunctuation(writer, '}', options);
}

private void writeHashMap(Display, T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (options.showTypeNames)
    {
        writeTypeName!Display(writer, options);
        writer.put(' ');
    }

    if (value.length == 0)
    {
        writePunctuation(writer, "{}", options);
        return;
    }
    if (depthLimitReached(context.recursionDepth, options))
    {
        writeDepthLimit(writer, options);
        return;
    }

    const compact = chooseCompact(value, options, context);
    const shown = limitedItemCount(value.length, options.maxItems);
    const truncated = shown < value.length;
    PrettyPrintContext childContext = descendAggregate(context);
    size_t index;
    auto cursor = value.cursor();

    writePunctuation(writer, '{', options);
    if (!compact)
        writer.put('\n');

    while (cursor.valid && index < shown)
    {
        if (compact)
        {
            if (index != 0)
                writePunctuation(writer, ", ", options);
        }
        else
            writeIndent(writer, childContext.indentationDepth, options);

        writePrettyImpl(writer, *cursor.key, options, childContext);
        writePunctuation(writer, ": ", options);
        writePrettyImpl(writer, *cursor.value, options, childContext);

        ++index;
        cursor.advance();
        if (!compact)
        {
            if (index < shown || truncated)
                writePunctuation(writer, ',', options);
            writer.put('\n');
        }
    }

    if (truncated)
    {
        if (compact)
        {
            if (shown != 0)
                writePunctuation(writer, ", ", options);
        }
        else
            writeIndent(writer, childContext.indentationDepth, options);
        writeTruncation(writer, value.length - shown, options);
        if (!compact)
            writer.put('\n');
    }

    if (!compact)
        writeIndent(writer, context.indentationDepth, options);
    writePunctuation(writer, '}', options);
}

private void writeHashSet(Display, T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (options.showTypeNames)
    {
        writeTypeName!Display(writer, options);
        writer.put(' ');
    }

    if (value.length == 0)
    {
        writePunctuation(writer, "{}", options);
        return;
    }
    if (depthLimitReached(context.recursionDepth, options))
    {
        writeDepthLimit(writer, options);
        return;
    }

    const compact = chooseCompact(value, options, context);
    const shown = limitedItemCount(value.length, options.maxItems);
    const truncated = shown < value.length;
    PrettyPrintContext childContext = descendAggregate(context);
    size_t index;
    auto cursor = value.cursor();

    writePunctuation(writer, '{', options);
    if (!compact)
        writer.put('\n');

    while (cursor.valid && index < shown)
    {
        if (compact)
        {
            if (index != 0)
                writePunctuation(writer, ", ", options);
        }
        else
            writeIndent(writer, childContext.indentationDepth, options);

        writePrettyImpl(writer, *cursor.value, options, childContext);

        ++index;
        cursor.advance();
        if (!compact)
        {
            if (index < shown || truncated)
                writePunctuation(writer, ',', options);
            writer.put('\n');
        }
    }

    if (truncated)
    {
        if (compact)
        {
            if (shown != 0)
                writePunctuation(writer, ", ", options);
        }
        else
            writeIndent(writer, childContext.indentationDepth, options);
        writeTruncation(writer, value.length - shown, options);
        if (!compact)
            writer.put('\n');
    }

    if (!compact)
        writeIndent(writer, context.indentationDepth, options);
    writePunctuation(writer, '}', options);
}

private template HasNamedStructField(T, size_t index)
{
    alias U = Unqualified!T;
    enum name = __traits(identifier, U.tupleof[index]);
    enum HasNamedStructField = name.length != 0 &&
        __traits(compiles, __traits(getMember, U, name));
}

private size_t countNamedFields(T)()
pure @safe
{
    size_t result;
    static foreach (index; 0 .. T.tupleof.length)
    {
        // A `static foreach` body shares its declaration scope across
        // iterations unless an explicit nested scope is introduced. Avoid a
        // per-iteration named enum here so structs with multiple fields do not
        // redeclare the same symbol.
        static if (HasNamedStructField!(T, index))
            ++result;
    }
    return result;
}

private void writeStruct(T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;
    enum fieldCount = countNamedFields!U();

    // Empty structs are terminal values. Printing them never descends further,
    // so a depth limit should not hide their complete representation.
    if (fieldCount == 0)
    {
        if (options.showTypeNames)
        {
            writeTypeName!U(writer, options);
            writer.put(' ');
        }
        writePunctuation(writer, "{}", options);
        return;
    }

    if (depthLimitReached(context.recursionDepth, options))
    {
        writeDepthLimit(writer, options);
        return;
    }

    if (options.showTypeNames)
    {
        writeTypeName!U(writer, options);
        writer.put(' ');
    }

    const shown = limitedItemCount(fieldCount, options.maxItems);
    const truncated = shown < fieldCount;
    const compact = chooseCompact(value, options, context);
    PrettyPrintContext childContext = descendAggregate(context);
    writePunctuation(writer, '{', options);
    if (!compact)
        writer.put('\n');

    size_t visitedFields;
    size_t writtenFields;
    static foreach (index; 0 .. U.tupleof.length)
    {
        {
            enum name = __traits(identifier, U.tupleof[index]);
            static if (HasNamedStructField!(U, index))
            {
                if (visitedFields < shown)
                {
                    if (compact)
                    {
                        if (writtenFields != 0)
                            writePunctuation(writer, ", ", options);
                    }
                    else
                        writeIndent(writer, childContext.indentationDepth, options);

                    writeStyledText(
                        writer,
                        name,
                        options.colorScheme.fieldName,
                        options,
                    );
                    writePunctuation(writer, ": ", options);
                    static if (isTaggedPayloadField!(U, index))
                        writeTaggedPayload!(U, index)(
                            writer,
                            value,
                            options,
                            childContext,
                        );
                    else
                        writePrettyImpl(
                            writer,
                            value.tupleof[index],
                            options,
                            childContext,
                        );

                    ++writtenFields;
                    if (!compact)
                    {
                        if (writtenFields < shown || truncated)
                            writePunctuation(writer, ',', options);
                        writer.put('\n');
                    }
                }
                ++visitedFields;
            }
        }
    }

    if (truncated)
    {
        if (compact)
        {
            if (writtenFields != 0)
                writePunctuation(writer, ", ", options);
        }
        else
            writeIndent(writer, childContext.indentationDepth, options);
        writeTruncation(writer, fieldCount - shown, options);
        if (!compact)
            writer.put('\n');
    }

    if (!compact)
        writeIndent(writer, context.indentationDepth, options);
    writePunctuation(writer, '}', options);
}

private void writeTaggedPayload(T, size_t payloadIndex)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;
    enum metadata = taggedPayloadMetadata!(U, payloadIndex)();
    alias Tag = Unqualified!(typeof(metadata.inactive));
    alias Payload = Unqualified!(typeof(U.tupleof[payloadIndex]));
    enum discriminatorIndex = taggedPayloadDiscriminatorIndex!(U, payloadIndex)();
    const active = value.tupleof[discriminatorIndex];

    if (active == metadata.inactive)
    {
        if (options.showTypeNames)
        {
            writeTypeName!Payload(writer, options);
            writer.put(' ');
        }
        writePunctuation(writer, "{}", options);
        return;
    }

    if (depthLimitReached(context.recursionDepth, options))
    {
        writeDepthLimit(writer, options);
        return;
    }

    if (options.showTypeNames)
    {
        writeTypeName!Payload(writer, options);
        writer.put(' ');
    }

    static foreach (memberIndex; 0 .. Payload.tupleof.length)
    {
        {
            enum mappedTag = taggedPayloadMemberTag!(
                    Payload,
                    memberIndex,
                    Tag,
                )();
            if (active == mappedTag)
            {
                if (options.maxItems == 0)
                {
                    writePunctuation(writer, '{', options);
                    writeTruncation(writer, 1, options);
                    writePunctuation(writer, '}', options);
                    return;
                }

                const compact = chooseTaggedPayloadCompact!(U, payloadIndex)(
                    value,
                    options,
                    context,
                );
                PrettyPrintContext childContext = descendAggregate(context);
                enum name = __traits(identifier, Payload.tupleof[memberIndex]);

                writePunctuation(writer, '{', options);
                if (!compact)
                {
                    writer.put('\n');
                    writeIndent(
                        writer,
                        childContext.indentationDepth,
                        options,
                    );
                }

                writeStyledText(
                    writer,
                    name,
                    options.colorScheme.fieldName,
                    options,
                );
                writePunctuation(writer, ": ", options);
                writePrettyImpl(
                    writer,
                    value.tupleof[payloadIndex].tupleof[memberIndex],
                    options,
                    childContext,
                );

                if (!compact)
                {
                    writer.put('\n');
                    writeIndent(writer, context.indentationDepth, options);
                }
                writePunctuation(writer, '}', options);
                return;
            }
        }
    }

    writeStyledText(
        writer,
        "<invalid tagged union discriminator>",
        options.colorScheme.unsupported,
        options,
    );
}

private bool chooseTaggedPayloadCompact(T, size_t payloadIndex)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    final switch (options.layout)
    {
        case PrettyPrintLayout.compact:
            return true;
        case PrettyPrintLayout.expanded:
            return false;
        case PrettyPrintLayout.automatic:
            break;
    }

    if (options.softMaxWidth == 0)
        return false;
    const indentation = cast(size_t) context.indentationDepth *
        options.indentSize;
    if (indentation >= options.softMaxWidth)
        return false;
    const available = cast(size_t) options.softMaxWidth - indentation;
    const estimate = estimateTaggedPayload!(T, payloadIndex)(
        value,
        options,
        context.recursionDepth,
        available,
    );
    return estimate.known && estimate.width <= available;
}

private void writeUnion(T)(
    ref Writer writer,
    scope const ref T,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext,
)
{
    alias U = Unqualified!T;
    if (options.showTypeNames)
    {
        writeTypeName!U(writer, options);
        writer.put(' ');
    }
    writeStyledText(
        writer,
        "<union: active member unknown>",
        options.colorScheme.unsupported,
        options,
    );
}

private void writePointer(T, Pointee)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (value is null)
    {
        writeStyledText(
            writer,
            "null",
            options.colorScheme.nullValue,
            options,
        );
        return;
    }

    // Borrowed values are observed through a transitive const view, so a
    // wrapped `void*` reaches this function as `const(void)*`.
    static if (!is(Pointee == function))
    {
        static if (!isVoidPointee!Pointee)
        {
            if (options.dereferencePointers)
            {
                writeStyledText(
                    writer,
                    "&",
                    options.colorScheme.pointerValue,
                    options,
                );
                if (depthLimitReached(context.recursionDepth, options))
                    writeDepthLimit(writer, options);
                else
                {
                    // Like `some(`, `&` is a same-line wrapper around one value.
                    PrettyPrintContext childContext = descendWrapper(context);
                    writePrettyImpl(writer, *value, options, childContext);
                }
                return;
            }
        }
    }

    if (options.showTypeNames)
    {
        writeTypeName!(Unqualified!T)(writer, options);
        writer.put(' ');
    }
    writeStyledText(
        writer,
        "@",
        options.colorScheme.pointerValue,
        options,
    );
    writeStyledValue(
        writer,
        cast(const(void)*) value,
        options.colorScheme.pointerValue,
        options,
    );
}

private void writeEnum(T)(
    ref Writer writer,
    T value,
    scope const ref PrettyPrintOptions options,
)
{
    alias U = Unqualified!T;
    String matchedName;
    static foreach (member; __traits(allMembers, U))
    {
        {
            static if (__traits(compiles, __traits(getMember, U, member)))
            {
                alias M = typeof(__traits(getMember, U, member));
                static if (is(Unqualified!M == U))
                {
                    if (matchedName.length == 0 &&
                        value == __traits(getMember, U, member))
                        matchedName = member;
                }
            }
        }
    }

    if (options.showTypeNames)
        writeTypeName!U(writer, options);

    if (matchedName.length != 0)
    {
        if (options.showTypeNames)
            writePunctuation(writer, '.', options);
        writeStyledText(
            writer,
            matchedName,
            options.colorScheme.enumValue,
            options,
        );
        return;
    }

    static if (U.sizeof <= ulong.sizeof)
    {
        if (options.showTypeNames)
            writePunctuation(writer, '(', options);
        static if (__traits(isUnsigned, U))
        {
            writeStyledValue(
                writer,
                cast(ulong) value,
                options.colorScheme.numberValue,
                options,
            );
        }
        else
        {
            writeStyledValue(
                writer,
                cast(long) value,
                options.colorScheme.numberValue,
                options,
            );
        }
        if (options.showTypeNames)
            writePunctuation(writer, ')', options);
    }
    else
    {
        if (options.showTypeNames)
            writer.put(' ');
        writeStyledText(
            writer,
            "<invalid enum value>",
            options.colorScheme.unsupported,
            options,
        );
    }
}

private void writeString(
    ref Writer writer,
    scope String value,
    scope const ref PrettyPrintOptions options,
)
{
    const style = options.colorScheme.stringValue;
    beginStyle(writer, style, options);
    writer.put('"');

    size_t runStart;
    foreach (index, character; value)
    {
        String escape;
        switch (character)
        {
            case '"':
                escape = "\\\"";
                break;
            case '\\':
                escape = "\\\\";
                break;
            case '\n':
                escape = "\\n";
                break;
            case '\r':
                escape = "\\r";
                break;
            case '\t':
                escape = "\\t";
                break;
            case '\0':
                escape = "\\0";
                break;
            default:
                if (cast(ubyte) character < 0x20 || character == 0x7f)
                {
                    if (runStart < index)
                        writer.put(value[runStart .. index]);
                    writeHexByte(writer, cast(ubyte) character);
                    runStart = index + 1;
                }
                continue;
        }

        if (runStart < index)
            writer.put(value[runStart .. index]);
        writer.put(escape);
        runStart = index + 1;
    }

    if (runStart < value.length)
        writer.put(value[runStart .. $]);
    writer.put('"');
    endStyle(writer, style, options);
}

private void writeCharacter(T)(
    ref Writer writer,
    T value,
    scope const ref PrettyPrintOptions options,
)
{
    const style = options.colorScheme.characterValue;
    beginStyle(writer, style, options);
    writer.put('\'');

    const codePoint = cast(dchar) value;
    switch (codePoint)
    {
        case '\'':
            writer.put("\\'");
            break;
        case '\\':
            writer.put("\\\\");
            break;
        case '\n':
            writer.put("\\n");
            break;
        case '\r':
            writer.put("\\r");
            break;
        case '\t':
            writer.put("\\t");
            break;
        case '\0':
            writer.put("\\0");
            break;
        default:
            static if (is(Unqualified!T == char))
            {
                if (cast(ubyte) value >= 0x80 ||
                    !isPrintableScalar(codePoint))
                    writeEscapedCodePoint(writer, cast(ubyte) value);
                else
                    writer.put(value);
            }
            else
            {
                if (!isPrintableScalar(codePoint))
                    writeEscapedCodePoint(writer, cast(uint) codePoint);
                else
                    writer.value(codePoint);
            }
            break;
    }

    writer.put('\'');
    endStyle(writer, style, options);
}

private bool isPrintableScalar(dchar value)
pure @safe
{
    const codePoint = cast(uint) value;
    return codePoint >= 0x20 && codePoint != 0x7f &&
        !(codePoint >= 0xd800 && codePoint <= 0xdfff) &&
        codePoint <= 0x10ffff;
}

private void writeEscapedCodePoint(ref Writer writer, uint value)
{
    if (value <= ubyte.max)
    {
        writer.put("\\x");
        writeHexDigits(writer, value, 2);
    }
    else if (value <= ushort.max)
    {
        writer.put("\\u");
        writeHexDigits(writer, value, 4);
    }
    else
    {
        writer.put("\\U");
        writeHexDigits(writer, value, 8);
    }
}

private void writeHexDigits(ref Writer writer, uint value, ubyte count)
{
    enum String digits = "0123456789abcdef";
    while (count != 0)
    {
        --count;
        const shift = cast(uint) count * 4;
        writer.put(digits[(value >> shift) & 0x0f]);
    }
}

private void writeHexByte(ref Writer writer, ubyte value)
{
    writer.put("\\x");
    writeHexDigits(writer, value, 2);
}

private void writeTruncation(
    ref Writer writer,
    size_t remaining,
    scope const ref PrettyPrintOptions options,
)
{
    const style = options.colorScheme.truncation;
    beginStyle(writer, style, options);
    writer.put("... (");
    writer.value(remaining);
    writer.put(" more)");
    endStyle(writer, style, options);
}

private void writeDepthLimit(
    ref Writer writer,
    scope const ref PrettyPrintOptions options,
)
{
    writeStyledText(
        writer,
        "...",
        options.colorScheme.depthLimit,
        options,
    );
}

private void writeUnsupported(T)(
    ref Writer writer,
    scope const ref PrettyPrintOptions options,
)
{
    if (options.showTypeNames)
    {
        writeTypeName!T(writer, options);
        writer.put(' ');
    }
    writeStyledText(
        writer,
        "<unsupported>",
        options.colorScheme.unsupported,
        options,
    );
}

private void writeTypeName(T)(
    ref Writer writer,
    scope const ref PrettyPrintOptions options,
)
{
    alias U = Unqualified!T;
    writeStyledText(
        writer,
        U.stringof,
        options.colorScheme.typeName,
        options,
    );
}

private void writePunctuation(
    ref Writer writer,
    char value,
    scope const ref PrettyPrintOptions options,
)
{
    writeStyledCharacter(
        writer,
        value,
        options.colorScheme.punctuation,
        options,
    );
}

private void writePunctuation(
    ref Writer writer,
    scope String value,
    scope const ref PrettyPrintOptions options,
)
{
    writeStyledText(
        writer,
        value,
        options.colorScheme.punctuation,
        options,
    );
}

private void writeStyledText(
    ref Writer writer,
    scope String value,
    AnsiStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    beginStyle(writer, style, options);
    writer.put(value);
    endStyle(writer, style, options);
}

private void writeStyledCharacter(
    ref Writer writer,
    char value,
    AnsiStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    beginStyle(writer, style, options);
    writer.put(value);
    endStyle(writer, style, options);
}

private void writeStyledValue(T)(
    ref Writer writer,
    T value,
    AnsiStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    beginStyle(writer, style, options);
    writer.value(value);
    endStyle(writer, style, options);
}

private void beginStyle(
    ref Writer writer,
    AnsiStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    if (options.colored && style.enabled)
        writer.beginAnsi(style);
}

private void endStyle(
    ref Writer writer,
    AnsiStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    if (options.colored && style.enabled)
        writer.endAnsi(style);
}

private void writeIndent(
    ref Writer writer,
    ushort depth,
    scope const ref PrettyPrintOptions options,
)
{
    const count = cast(size_t) depth * options.indentSize;
    writer.repeat(' ', count);
}

private bool depthLimitReached(
    ushort depth,
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    return depth == ushort.max || depth > options.maxDepth;
}

private ushort nextDepth(ushort depth)
pure @safe
{
    return depth == ushort.max ? ushort.max : cast(ushort)(depth + 1);
}

private PrettyPrintContext descendAggregate(PrettyPrintContext context)
pure @safe
{
    context.recursionDepth = nextDepth(context.recursionDepth);
    context.indentationDepth = nextDepth(context.indentationDepth);
    return context;
}

private PrettyPrintContext descendWrapper(PrettyPrintContext context)
pure @safe
{
    context.recursionDepth = nextDepth(context.recursionDepth);
    return context;
}

private PrettyPrintContext descendIndentation(PrettyPrintContext context)
pure @safe
{
    context.indentationDepth = nextDepth(context.indentationDepth);
    return context;
}

private size_t limitedItemCount(size_t length, uint maxItems)
pure @safe
{
    return length < maxItems ? length : maxItems;
}

private size_t decimalDigits(ulong value)
pure @safe
{
    size_t result = 1;
    while (value >= 10)
    {
        value /= 10;
        ++result;
    }
    return result;
}

private size_t integerWidth(T)(T value)
pure @safe
{
    static assert(__traits(isIntegral, T) && T.sizeof <= ulong.sizeof);
    static if (__traits(isUnsigned, T))
        return decimalDigits(cast(ulong) value);
    else
    {
        const signedValue = cast(long) value;
        const bits = cast(ulong) signedValue;
        const magnitude = signedValue < 0 ? 0UL - bits : bits;
        return decimalDigits(magnitude) + (signedValue < 0 ? 1 : 0);
    }
}

private size_t truncationWidth(size_t remaining)
pure @safe
{
    // "... (" + decimal digits + " more)"
    return 11 + decimalDigits(cast(ulong) remaining);
}

private bool chooseCompact(T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    final switch (options.layout)
    {
        case PrettyPrintLayout.compact:
            return true;
        case PrettyPrintLayout.expanded:
            return false;
        case PrettyPrintLayout.automatic:
            break;
    }

    if (options.softMaxWidth == 0)
        return false;
    const indentation = cast(size_t) context.indentationDepth *
        options.indentSize;
    if (indentation >= options.softMaxWidth)
        return false;
    const available = cast(size_t) options.softMaxWidth - indentation;
    const estimate = estimateWidth(
        value,
        options,
        context.recursionDepth,
        available,
    );
    return estimate.known && estimate.width <= available;
}

private struct WidthEstimate
{
    bool known;
    size_t width;
}

private WidthEstimate knownWidth(size_t width)
pure @safe
{
    return WidthEstimate(true, width);
}

private WidthEstimate unknownWidth()
pure @safe
{
    return WidthEstimate.init;
}

private bool addWidth(size_t* total, size_t addition, size_t budget)
pure @safe
{
    if (addition > size_t.max - *total)
        return false;
    *total += addition;
    return *total <= budget;
}

private WidthEstimate estimateWidth(T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    ushort depth,
    size_t budget,
)
{
    alias U = Unqualified!T;

    static assert(!(hasPrettyDescribe!T && hasPrettyFormatToMember!T),
        U.stringof ~ " defines both prettyDescribe and prettyFormatTo");

    static if (hasPrettyDescribe!T)
    {
        PrettyMeasure!U pretty = PrettyMeasure!U(
            &options,
            PrettyPrintContext(depth, 0),
            budget,
        );
        alias DescribeReturn = typeof(value.prettyDescribe(pretty));
        static assert(is(DescribeReturn == void), U.stringof ~
                ".prettyDescribe(...) must return void");
        value.prettyDescribe(pretty);
        return pretty.result;
    }
    else static if (hasPrettyFormatTo!T)
    {
        return unknownWidth();
    }
    else static if (is(U == typeof(null)))
        return knownWidth(4);
    else static if (isStringType!U)
        return estimateEscapedString(cast(String) value, budget);
    else static if (is(U == bool))
        return knownWidth(value ? 4 : 5);
    else static if (isCharacterType!U)
        return knownWidth(estimateCharacterWidth(value));
    else static if (is(U == enum))
        return estimateEnumWidth(value, options);
    else static if (__traits(isIntegral, U) && U.sizeof <= ulong.sizeof)
        return knownWidth(integerWidth(value));
    else static if (__traits(isFloating, U))
        return knownWidth(U.sizeof * 8 + 16);
    else static if (is(U == Element[], Element))
        return estimateIndexable(value, value.length, options, depth, budget);
    else static if (is(U == Element[N], Element, size_t N))
    {
        static if (is(Element == char) || is(Element == const(char)) ||
            is(Element == immutable(char)))
            return estimateEscapedString(cast(String) value[], budget);
        else
            return estimateIndexable(value, N, options, depth, budget);
    }
    else static if (is(U == Pointee*, Pointee))
    {
        if (value is null)
            return knownWidth(4);
        static if (is(Pointee == function))
        {
            return estimatePointerAddressWidth!U(options);
        }
        else static if (isVoidPointee!Pointee)
        {
            return estimatePointerAddressWidth!U(options);
        }
        else
        {
            if (!options.dereferencePointers)
                return estimatePointerAddressWidth!U(options);
            if (depthLimitReached(depth, options))
                return knownWidth(4);
            const child = estimateWidth(*value, options, nextDepth(depth), budget);
            return child.known && child.width < size_t.max
                ? knownWidth(child.width + 1) : unknownWidth();
        }
    }
    else
        return estimateDefaultAggregate(value, options, depth, budget);
}

private WidthEstimate estimatePointerAddressWidth(T)(
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    // `@` + the `0x` prefix + two hexadecimal digits per address byte.
    const typePrefix = options.showTypeNames ? T.stringof.length + 1 : 0;
    return knownWidth(typePrefix + 3 + size_t.sizeof * 2);
}

private WidthEstimate estimateDefaultAggregate(T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    ushort depth,
    size_t budget,
)
{
    alias U = Unqualified!T;
    static if (is(U == struct))
        return estimateStruct(value, options, depth, budget);
    else static if (is(U == union))
        return knownWidth((options.showTypeNames ? U.stringof.length + 1 : 0) + 30);
    else
        return unknownWidth();
}

private size_t estimateCharacterWidth(T)(T value)
pure @safe
{
    const codePoint = cast(dchar) value;
    if (codePoint == '\'' || codePoint == '\\' || codePoint == '\n' ||
        codePoint == '\r' || codePoint == '\t' || codePoint == '\0')
        return 4;

    static if (is(Unqualified!T == char))
    {
        if (cast(ubyte) value >= 0x80 || !isPrintableScalar(codePoint))
            return 6;
        return 3;
    }
    else
    {
        if (!isPrintableScalar(codePoint))
        {
            const numeric = cast(uint) codePoint;
            return numeric <= ubyte.max ? 6 : numeric <= ushort.max ? 8 : 12;
        }
        const numeric = cast(uint) codePoint;
        const encodedWidth = numeric <= 0x7f ? 1 : numeric <= 0x7ff ? 2 : numeric <= 0xffff ? 3 : 4;
        return encodedWidth + 2;
    }
}

private WidthEstimate estimateEnumWidth(T)(
    T value,
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    alias U = Unqualified!T;
    size_t memberWidth;
    static foreach (member; __traits(allMembers, U))
    {
        {
            static if (__traits(compiles, __traits(getMember, U, member)))
            {
                alias M = typeof(__traits(getMember, U, member));
                static if (is(Unqualified!M == U))
                {
                    if (memberWidth == 0 &&
                        value == __traits(getMember, U, member))
                        memberWidth = member.length;
                }
            }
        }
    }

    if (memberWidth != 0)
        return knownWidth((options.showTypeNames ? U.stringof.length + 1 : 0) +
                memberWidth);
    static if (U.sizeof <= ulong.sizeof)
    {
        const numericWidth = integerWidth(value);
        return knownWidth(
            numericWidth +
                (options.showTypeNames ? U.stringof.length + 2 : 0),
        );
    }
    else
        return knownWidth((options.showTypeNames ? U.stringof.length + 1 : 0) +
                "<invalid enum value>".length);
}

private WidthEstimate estimateEscapedString(scope String value, size_t budget)
pure @safe
{
    size_t total = 2;
    if (total > budget)
        return unknownWidth();
    foreach (character; value)
    {
        size_t addition = 1;
        if (character == '"' || character == '\\' || character == '\n' ||
            character == '\r' || character == '\t' || character == '\0')
            addition = 2;
        else if (cast(ubyte) character < 0x20 || character == 0x7f)
            addition = 4;
        if (!addWidth(&total, addition, budget))
            return unknownWidth();
    }
    return knownWidth(total);
}

private WidthEstimate estimateIndexable(T)(
    scope const ref T value,
    size_t length,
    scope const ref PrettyPrintOptions options,
    ushort depth,
    size_t budget,
)
{
    if (length == 0)
        return knownWidth(2);
    if (depthLimitReached(depth, options))
        return knownWidth(3);

    size_t total = 2;
    const shown = limitedItemCount(length, options.maxItems);
    foreach (index; 0 .. shown)
    {
        if (index != 0 && !addWidth(&total, 2, budget))
            return unknownWidth();
        const child = estimateWidth(
            value[index],
            options,
            nextDepth(depth),
            budget > total ? budget - total : 0,
        );
        if (!child.known || !addWidth(&total, child.width, budget))
            return unknownWidth();
    }
    if (shown < length)
    {
        if (shown != 0 && !addWidth(&total, 2, budget))
            return unknownWidth();
        if (!addWidth(&total, truncationWidth(length - shown), budget))
            return unknownWidth();
    }
    return knownWidth(total);
}

private WidthEstimate estimateSemanticSequence(Display, T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    ushort depth,
    size_t budget,
)
{
    size_t prefix = options.showTypeNames ? Display.stringof.length + 1 : 0;
    const child = estimateIndexable(
        value,
        value.length,
        options,
        depth,
        budget >= prefix ? budget - prefix : 0,
    );
    if (!child.known || !addWidth(&prefix, child.width, budget))
        return unknownWidth();
    return knownWidth(prefix);
}

private WidthEstimate estimateFlagSet(Display, T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    size_t budget,
)
{
    alias U = Unqualified!T;
    alias Flag = U.FlagType;

    size_t total = options.showTypeNames ? Display.stringof.length + 1 : 0;
    if (!addWidth(&total, 2, budget))
        return unknownWidth();

    const length = value.enabledCount;
    const shown = limitedItemCount(length, options.maxItems);
    size_t written;
    static foreach (name; __traits(allMembers, Flag))
    {
        {
            enum flag = __traits(getMember, Flag, name);
            if (value.contains(flag) && written < shown)
            {
                if (written != 0 && !addWidth(&total, 2, budget))
                    return unknownWidth();
                if (!addWidth(&total, name.length, budget))
                    return unknownWidth();
                ++written;
            }
        }
    }

    if (shown < length)
    {
        if (shown != 0 && !addWidth(&total, 2, budget))
            return unknownWidth();
        if (!addWidth(&total, truncationWidth(length - shown), budget))
            return unknownWidth();
    }
    return knownWidth(total);
}

private WidthEstimate estimateHashMap(Display, T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    ushort depth,
    size_t budget,
)
{
    size_t total = options.showTypeNames ? Display.stringof.length + 1 : 0;
    if (value.length == 0)
        return addWidth(&total, 2, budget) ? knownWidth(total) : unknownWidth();
    if (depthLimitReached(depth, options))
        return addWidth(&total, 3, budget) ? knownWidth(total) : unknownWidth();
    if (!addWidth(&total, 2, budget))
        return unknownWidth();

    const shown = limitedItemCount(value.length, options.maxItems);
    size_t index;
    auto cursor = value.cursor();
    while (cursor.valid && index < shown)
    {
        if (index != 0 && !addWidth(&total, 2, budget))
            return unknownWidth();
        const key = estimateWidth(
            *cursor.key,
            options,
            nextDepth(depth),
            budget > total ? budget - total : 0,
        );
        if (!key.known || !addWidth(&total, key.width, budget) ||
            !addWidth(&total, 2, budget))
            return unknownWidth();
        const mapped = estimateWidth(
            *cursor.value,
            options,
            nextDepth(depth),
            budget > total ? budget - total : 0,
        );
        if (!mapped.known || !addWidth(&total, mapped.width, budget))
            return unknownWidth();
        ++index;
        cursor.advance();
    }
    if (shown < value.length)
    {
        if (shown != 0 && !addWidth(&total, 2, budget))
            return unknownWidth();
        if (!addWidth(&total, truncationWidth(value.length - shown), budget))
            return unknownWidth();
    }
    return knownWidth(total);
}

private WidthEstimate estimateHashSet(Display, T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    ushort depth,
    size_t budget,
)
{
    size_t total = options.showTypeNames ? Display.stringof.length + 1 : 0;
    if (value.length == 0)
        return addWidth(&total, 2, budget) ? knownWidth(total) : unknownWidth();
    if (depthLimitReached(depth, options))
        return addWidth(&total, 3, budget) ? knownWidth(total) : unknownWidth();
    if (!addWidth(&total, 2, budget))
        return unknownWidth();

    const shown = limitedItemCount(value.length, options.maxItems);
    size_t index;
    auto cursor = value.cursor();
    while (cursor.valid && index < shown)
    {
        if (index != 0 && !addWidth(&total, 2, budget))
            return unknownWidth();
        const child = estimateWidth(
            *cursor.value,
            options,
            nextDepth(depth),
            budget > total ? budget - total : 0,
        );
        if (!child.known || !addWidth(&total, child.width, budget))
            return unknownWidth();
        ++index;
        cursor.advance();
    }
    if (shown < value.length)
    {
        if (shown != 0 && !addWidth(&total, 2, budget))
            return unknownWidth();
        if (!addWidth(&total, truncationWidth(value.length - shown), budget))
            return unknownWidth();
    }
    return knownWidth(total);
}

private WidthEstimate estimateTaggedPayload(T, size_t payloadIndex)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    ushort depth,
    size_t budget,
)
{
    alias U = Unqualified!T;
    enum metadata = taggedPayloadMetadata!(U, payloadIndex)();
    alias Tag = Unqualified!(typeof(metadata.inactive));
    alias Payload = Unqualified!(typeof(U.tupleof[payloadIndex]));
    enum discriminatorIndex = taggedPayloadDiscriminatorIndex!(U, payloadIndex)();
    const active = value.tupleof[discriminatorIndex];

    if (active == metadata.inactive)
    {
        size_t total = options.showTypeNames ? Payload.stringof.length + 1 : 0;
        return addWidth(&total, 2, budget) ? knownWidth(total) : unknownWidth();
    }
    if (depthLimitReached(depth, options))
        return knownWidth(3);

    size_t total = options.showTypeNames ? Payload.stringof.length + 1 : 0;
    if (options.maxItems == 0)
    {
        if (!addWidth(&total, 2, budget) ||
            !addWidth(&total, truncationWidth(1), budget))
            return unknownWidth();
        return knownWidth(total);
    }

    static foreach (memberIndex; 0 .. Payload.tupleof.length)
    {
        {
            enum mappedTag = taggedPayloadMemberTag!(
                    Payload,
                    memberIndex,
                    Tag,
                )();
            if (active == mappedTag)
            {
                enum name = __traits(identifier, Payload.tupleof[memberIndex]);
                if (!addWidth(&total, 2 + name.length + 2, budget))
                    return unknownWidth();
                const child = estimateWidth(
                    value.tupleof[payloadIndex].tupleof[memberIndex],
                    options,
                    nextDepth(depth),
                    budget > total ? budget - total : 0,
                );
                if (!child.known || !addWidth(&total, child.width, budget))
                    return unknownWidth();
                return knownWidth(total);
            }
        }
    }

    return addWidth(
        &total,
        "<invalid tagged union discriminator>".length,
        budget,
    ) ? knownWidth(total) : unknownWidth();
}

private WidthEstimate estimateStruct(T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    ushort depth,
    size_t budget,
)
{
    alias U = Unqualified!T;
    enum fieldCount = countNamedFields!U();
    if (fieldCount == 0)
    {
        size_t emptyWidth = options.showTypeNames ? U.stringof.length + 1 : 0;
        return addWidth(&emptyWidth, 2, budget)
            ? knownWidth(emptyWidth) : unknownWidth();
    }
    if (depthLimitReached(depth, options))
        return knownWidth(3);

    size_t total = options.showTypeNames ? U.stringof.length + 1 : 0;
    if (!addWidth(&total, 2, budget))
        return unknownWidth();

    const shown = limitedItemCount(fieldCount, options.maxItems);
    size_t visitedFields;
    size_t writtenFields;
    static foreach (index; 0 .. U.tupleof.length)
    {
        {
            enum name = __traits(identifier, U.tupleof[index]);
            static if (HasNamedStructField!(U, index))
            {
                if (visitedFields < shown)
                {
                    if (writtenFields != 0 && !addWidth(&total, 2, budget))
                        return unknownWidth();
                    if (!addWidth(&total, name.length, budget) ||
                        !addWidth(&total, 2, budget))
                        return unknownWidth();
                    static if (isTaggedPayloadField!(U, index))
                        const child = estimateTaggedPayload!(U, index)(
                            value,
                            options,
                            nextDepth(depth),
                            budget > total ? budget - total : 0,
                        );
                    else
                        const child = estimateWidth(
                            value.tupleof[index],
                            options,
                            nextDepth(depth),
                            budget > total ? budget - total : 0,
                        );
                    if (!child.known || !addWidth(&total, child.width, budget))
                        return unknownWidth();
                    ++writtenFields;
                }
                ++visitedFields;
            }
        }
    }

    if (shown < fieldCount)
    {
        if (writtenFields != 0 && !addWidth(&total, 2, budget))
            return unknownWidth();
        if (!addWidth(&total, truncationWidth(fieldCount - shown), budget))
            return unknownWidth();
    }
    return knownWidth(total);
}

version (unittest)
{
    private enum PrettyPrintTestPermission : ubyte
    {
        read,
        write,
        execute,
        administer = 7,
    }

    private enum PrettyPrintTestColor : ubyte
    {
        red = 1,
        blue = 2,
    }

    private enum PrettyPrintTestSigned : byte
    {
        zero,
    }

    private struct PrettyPrintTestEmpty
    {
    }

    private struct PrettyPrintTestRecord
    {
        int id;
        String name;
    }

    private struct PrettyPrintTestOuter
    {
        PrettyPrintTestRecord inner;
        int tail;
    }

    private struct PrettyPrintTestOptionalHolder
    {
        Option!PrettyPrintTestRecord item;
        int tail;
    }

    private struct PrettyPrintTestPointerHolder
    {
        PrettyPrintTestRecord* item;
        int tail;
    }

    private struct PrettyPrintTestStaticArrayHolder
    {
        int[4] values;
    }

    private struct PrettyPrintTestEmptyHolder
    {
        PrettyPrintTestEmpty empty;
    }

    private struct PrettyPrintTestNode
    {
        int value;
        PrettyPrintTestNode* next;
    }

    private struct PrettyPrintTestManyFields
    {
        int first;
        int second;
        int third;
    }

    private struct PrettyPrintTestEnumHolder
    {
        PrettyPrintTestSigned value;
    }

    private struct PrettyPrintTestMoveOnly
    {
        @disable this(this);
        int value;
    }

    private struct PrettyPrintTestBorrowedSlice
    {
        int[] values;
    }

    private __gshared size_t prettyPrintTestDestructions;

    private struct PrettyPrintTestTrackedOwner
    {
        @disable this(this);
        int value;
        bool ownsValue;

        ~this() nothrow @nogc
        {
            if (ownsValue)
                ++prettyPrintTestDestructions;
        }
    }

    // DIP1000 must preserve the relationship between a borrowed wrapper and
    // its source. Returning a wrapper around a local would otherwise leave a
    // dangling pointer. Keep this as a compile-time regression test rather
    // than a runtime use-after-scope test.
    static assert(!__traits(compiles,
    {
            PrettyValue!PrettyPrintTestRecord escapePrettyPrintBorrow() @safe
            {
                PrettyPrintTestRecord local;
                return pretty(local);
            }
        }));

    // `return scope` must not make pointer-free owned temporaries unusable from
    // safe code.
    static assert(__traits(compiles,
    {
            OwnedPrettyValue!PrettyPrintTestEnumHolder returnOwnedPrettyPrintValue() @safe
            {
                return PrettyPrintTestEnumHolder.init.pretty;
            }
        }));

    // Owning the outer temporary is not deep ownership. The returned wrapper
    // must retain the lifetime of slices and pointers stored inside that value.
    static assert(!__traits(compiles,
    {
            OwnedPrettyValue!PrettyPrintTestBorrowedSlice escapePrettyPrintContainedBorrow() @safe
            {
                int[1] local = [1];
                return PrettyPrintTestBorrowedSlice(local[]).pretty;
            }
        }));

    private struct PrettyPrintTestConflictingSemanticOverride
    {
        void prettyDescribe(Pretty)(scope ref Pretty pretty) const
        {
            pretty.atom("semantic", pretty.nullRole);
        }

        void prettyFormatTo(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) const nothrow @nogc
        {
            writer.put("raw");
        }
    }

    static assert(!__traits(compiles,
            (ref Writer writer, ref PrettyPrintTestConflictingSemanticOverride value) {
            writePretty(writer, value);
        }));

    private struct PrettyPrintTestNonVoidDescribe
    {
        int prettyDescribe(Pretty)(scope ref Pretty pretty) const
        {
            pretty.atom("invalid", pretty.nullRole);
            return 1;
        }
    }

    static assert(!__traits(compiles,
            (ref Writer writer, ref PrettyPrintTestNonVoidDescribe value) {
            writePretty(writer, value);
        }));

    private struct PrettyPrintTestNonVoidOverride
    {
        int prettyFormatTo(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) const nothrow @nogc
        {
            writer.put("invalid");
            return 1;
        }
    }

    static assert(!__traits(compiles,
            (ref Writer writer, ref PrettyPrintTestNonVoidOverride value) {
            writePretty(writer, value);
        }));

    private struct PrettyPrintTestOverride
    {
        int ignored;

        void prettyFormatTo(
            ref Writer writer,
            scope const ref PrettyPrintOptions options,
        ) const nothrow @nogc
        {
            writer.put(options.showTypeNames
                    ? "<pretty with options>" : "<pretty without types>");
        }
    }

    // Unit-test instrumentation only. A const pretty hook cannot mutate state
    // reachable through its value, so use separate module storage to verify
    // that automatic layout never executes a custom hook during measurement.
    private __gshared size_t prettyPrintTestHookCalls;

    private struct PrettyPrintTestCountedOverride
    {
        void prettyFormatTo(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) const nothrow @nogc
        {
            ++prettyPrintTestHookCalls;
            writer.put("<counted>");
        }
    }

    private struct PrettyPrintTestCountedHolder
    {
        PrettyPrintTestCountedOverride item;
        int tail;
    }

    private struct PrettyPrintTestMutableOnlyOverride
    {
        int value;

        void prettyFormatTo(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) nothrow @nogc
        {
            writer.put("<mutable pretty>");
        }
    }

    private struct PrettyPrintTestBothOverrides
    {
        int ignored;

        void prettyFormatTo(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) const nothrow @nogc
        {
            writer.put("<pretty wins>");
        }

        void formatTo(ref Writer writer) const nothrow @nogc
        {
            writer.put("<normal format>");
        }
    }

    private struct PrettyPrintTestFormatOverride
    {
        int ignored;

        void formatTo(ref Writer writer) const nothrow @nogc
        {
            writer.put("<format override>");
        }
    }

    private union PrettyPrintTestUnion
    {
        int integer;
        double floating;
    }

    private enum PrettyPrintTestTaggedKind : ubyte
    {
        none,
        integer,
        floating,
    }

    private union PrettyPrintTestTaggedPayload
    {
        int integer;

        @taggedCase(PrettyPrintTestTaggedKind.floating)
        int renamedFloating;
    }

    private struct PrettyPrintTestTaggedValue
    {
        PrettyPrintTestTaggedKind kind;

        @taggedBy("kind", PrettyPrintTestTaggedKind.none)
        PrettyPrintTestTaggedPayload payload;
    }

    private extern (C) int prettyPrintTestFunction(int value)
    nothrow @nogc
    {
        return value;
    }

    private PrettyPrintOptions plainOptions()
    pure nothrow @nogc @safe
    {
        return PrettyPrintOptions.init.withoutColors();
    }

    private PrettyPrintColorScheme disabledColorScheme()
    pure nothrow @nogc @safe
    {
        PrettyPrintColorScheme result = PrettyPrintColorScheme.init;
        result.typeName = AnsiStyle.init;
        result.fieldName = AnsiStyle.init;
        result.stringValue = AnsiStyle.init;
        result.characterValue = AnsiStyle.init;
        result.numberValue = AnsiStyle.init;
        result.booleanValue = AnsiStyle.init;
        result.enumValue = AnsiStyle.init;
        result.nullValue = AnsiStyle.init;
        result.pointerValue = AnsiStyle.init;
        result.punctuation = AnsiStyle.init;
        result.truncation = AnsiStyle.init;
        result.depthLimit = AnsiStyle.init;
        result.unsupported = AnsiStyle.init;
        return result;
    }

    private void expectPretty(T)(
        auto ref T value,
        scope String expected,
        PrettyPrintOptions options = PrettyPrintOptions.init.withoutColors(),
    ) nothrow @nogc
    {
        import xtb.core.print : writeBuffer;
        import xtb.core.string;

        char[4096] storage;
        const result = writeBuffer(storage[], pretty(value, options));
        assert(result.ok);
        assert(!result.truncated);
        assert(storage[0 .. result.written].equal(expected));
    }

    private void expectOwnedPretty(T)(
        T value,
        scope String expected,
        PrettyPrintOptions options = PrettyPrintOptions.init.withoutColors(),
    ) nothrow @nogc
    {
        import xtb.core.print : writeBuffer;
        import xtb.core.string;

        char[4096] storage;
        const result = writeBuffer(storage[], pretty(move(value), options));
        assert(result.ok);
        assert(!result.truncated);
        assert(storage[0 .. result.written].equal(expected));
    }

    private void expectWidthEstimateCovers(T)(
        auto ref T value,
        PrettyPrintOptions options = PrettyPrintOptions.init.withoutColors(),
    ) nothrow @nogc
    {
        import xtb.core.print : writeBuffer;

        options.colored = false;
        options.layout = PrettyPrintLayout.compact;

        char[4096] storage;
        const rendered = writeBuffer(storage[], pretty(value, options));
        assert(rendered.ok);
        assert(!rendered.truncated);

        const estimate = estimateWidth(value, options, 0, size_t.max);
        assert(estimate.known);
        // An overestimate only chooses the expanded layout conservatively. An
        // underestimate can exceed softMaxWidth after choosing compact output.
        assert(estimate.width >= rendered.written);
    }
}

unittest
{
    const defaults = PrettyPrintOptions.init;
    const namedDefaults = PrettyPrintOptions.defaults();
    assert(namedDefaults.indentSize == defaults.indentSize);
    assert(namedDefaults.maxDepth == defaults.maxDepth);
    assert(namedDefaults.maxItems == defaults.maxItems);
    assert(defaults.indentSize == 2);
    assert(defaults.maxDepth == 8);
    assert(defaults.maxItems == 32);
    assert(defaults.softMaxWidth == 80);
    assert(defaults.layout == PrettyPrintLayout.automatic);
    assert(defaults.colored);
    assert(defaults.showTypeNames);
    assert(!defaults.dereferencePointers);

    const defaultScheme = PrettyPrintColorScheme.defaults();
    assert(defaultScheme.typeName.enabled);
    assert(defaultScheme.fieldName.enabled);
    assert(defaultScheme.stringValue.enabled);
    assert(defaultScheme.characterValue.enabled);
    assert(defaultScheme.numberValue.enabled);
    assert(defaultScheme.booleanValue.enabled);
    assert(defaultScheme.enumValue.enabled);
    assert(defaultScheme.nullValue.enabled);
    assert(defaultScheme.pointerValue.enabled);
    assert(!defaultScheme.punctuation.enabled);
    assert(defaultScheme.truncation.enabled);
    assert(defaultScheme.depthLimit.enabled);
    assert(defaultScheme.unsupported.enabled);

    const plain = defaults.withoutColors();
    assert(!plain.colored);
    assert(defaults.colored);
    assert(defaults.withLayout(PrettyPrintLayout.expanded).layout ==
            PrettyPrintLayout.expanded);

    PrettyPrintColorScheme scheme = PrettyPrintColorScheme.init;
    scheme.numberValue = AnsiStyle.foreground(AnsiColor.brightRed);
    const changed = defaults.withColorScheme(scheme);
    assert(changed.maxDepth == defaults.maxDepth);
    assert(changed.colored == defaults.colored);
}

unittest
{
    PrettyPrintOptions plain = plainOptions();

    int number = 42;
    number.expectPretty("42", plain);
    number.expectWidthEstimateCovers(plain);

    bool yes = true;
    yes.expectPretty("true", plain);
    bool no;
    no.expectPretty("false", plain);

    typeof(null) nothing;
    nothing.expectPretty("null", plain);

    float decimal = 1.5f;
    decimal.expectPretty("1.5", plain);
    decimal.expectWidthEstimateCovers(plain);

    String text = "a\n\"b\\c\x01";
    text.expectPretty("\"a\\n\\\"b\\\\c\\x01\"", plain);
    text.expectWidthEstimateCovers(plain);

    import xtb.core.allocators.malloc : mallocAllocator;

    StringBuf buffer = StringBuf.fromString(mallocAllocator(), "owned\ntext");
    buffer.expectPretty("\"owned\\ntext\"", plain);
    buffer.expectWidthEstimateCovers(plain);
    buffer.deinit();

    StringBufUnmanaged unmanagedBuffer = StringBufUnmanaged.fromString(
        mallocAllocator(),
        "owned\ntext",
    );
    unmanagedBuffer.expectPretty("\"owned\\ntext\"", plain);
    unmanagedBuffer.expectWidthEstimateCovers(plain);
    unmanagedBuffer.deinit(mallocAllocator());

    OwnedString ownedString = OwnedString.fromString(
        mallocAllocator(),
        "owned\ntext",
    );
    ownedString.expectPretty("\"owned\\ntext\"", plain);
    ownedString.expectWidthEstimateCovers(plain);
    ownedString.deinit();

    OwnedStringUnmanaged unmanagedOwnedString =
        OwnedStringUnmanaged.fromString(mallocAllocator(), "owned\ntext");
    unmanagedOwnedString.expectPretty("\"owned\\ntext\"", plain);
    unmanagedOwnedString.expectWidthEstimateCovers(plain);
    unmanagedOwnedString.deinit(mallocAllocator());

    char quote = '\'';
    quote.expectPretty("'\\''", plain);
    char slash = '\\';
    slash.expectPretty("'\\\\'", plain);
    char control = cast(char) 0x1f;
    control.expectPretty("'\\x1f'", plain);
    char nonAsciiByte = cast(char) 0xe9;
    nonAsciiByte.expectPretty("'\\xe9'", plain);
    wchar surrogate = cast(wchar) 0xd800;
    surrogate.expectPretty("'\\ud800'", plain);
    dchar smile = cast(dchar) 0x1f642;
    smile.expectPretty("'🙂'", plain);
}

unittest
{
    PrettyPrintOptions plain = plainOptions();

    PrettyPrintTestColor color = PrettyPrintTestColor.red;
    color.expectPretty("PrettyPrintTestColor.red", plain);
    color.expectWidthEstimateCovers(plain);

    PrettyPrintOptions noTypes = plain;
    noTypes.showTypeNames = false;
    color.expectPretty("red", noTypes);

    PrettyPrintTestColor invalid = cast(PrettyPrintTestColor) 9;
    invalid.expectPretty("PrettyPrintTestColor(9)", plain);
    invalid.expectPretty("9", noTypes);

    PrettyPrintTestEnumHolder signed = PrettyPrintTestEnumHolder(
        cast(PrettyPrintTestSigned)-128,
    );
    PrettyPrintOptions narrow = noTypes;
    narrow.softMaxWidth = 12;
    signed.expectPretty("{\n  value: -128\n}", narrow);
}

unittest
{
    PrettyPrintOptions plain = plainOptions();
    PrettyPrintOptions noTypes = plain;
    noTypes.showTypeNames = false;

    Option!int present = Option!int.some(7);
    present.expectPretty("some(7)", noTypes);
    present.expectPretty("Option!int.some(7)", plain);
    present.expectWidthEstimateCovers(plain);

    Option!int absent;
    absent.expectPretty("none", noTypes);
    absent.expectPretty("Option!int.none", plain);

    Result!(int, int) resultOk = Result!(int, int).ok(7);
    resultOk.expectPretty("ok(7)", noTypes);
    resultOk.expectPretty("Result!(int, int).ok(7)", plain);
    resultOk.expectWidthEstimateCovers(plain);

    Result!(int, int) resultErr = Result!(int, int).err(9);
    resultErr.expectPretty("err(9)", noTypes);
    resultErr.expectPretty("Result!(int, int).err(9)", plain);

    Result!(void, int) resultVoid = Result!(void, int).ok();
    resultVoid.expectPretty("ok()", noTypes);
    resultVoid.expectPretty("Result!(void, int).ok()", plain);

    Option!PrettyPrintTestRecord nested =
        Option!PrettyPrintTestRecord.some(PrettyPrintTestRecord(1, "one"));

    // Unary wrappers increase semantic recursion without adding a second
    // visual indentation level. The payload aggregate therefore aligns with
    // the `some(` call rather than drifting one level to the right.
    PrettyPrintOptions expanded = noTypes.withLayout(
        PrettyPrintLayout.expanded,
    );
    expanded.indentSize = 4;
    nested.expectPretty(
        "some({\n" ~
            "    id: 1,\n" ~
            "    name: \"one\"\n" ~
            "})",
        expanded,
    );
    nested.expectWidthEstimateCovers(noTypes);

    PrettyPrintTestOptionalHolder holder = PrettyPrintTestOptionalHolder(
        nested,
        9,
    );
    holder.expectPretty(
        "{\n" ~
            "    item: some({\n" ~
            "        id: 1,\n" ~
            "        name: \"one\"\n" ~
            "    }),\n" ~
            "    tail: 9\n" ~
            "}",
        expanded,
    );

    PrettyPrintOptions shallow = noTypes.withLayout(PrettyPrintLayout.compact);
    shallow.maxDepth = 0;
    nested.expectPretty("some(...)", shallow);

    Option!PrettyPrintTestRecord[1] nestedArray = [nested];
    PrettyPrintOptions automatic = noTypes;
    automatic.maxDepth = 0;
    automatic.softMaxWidth = 10;
    nestedArray.expectPretty("[\n  some(...)\n]", automatic);
}

unittest
{
    PrettyPrintOptions plain = plainOptions();
    PrettyPrintOptions noTypes = plain;
    noTypes.showTypeNames = false;

    int[4] fixedValues = [1, 2, 3, 4];
    fixedValues.expectPretty("[1, 2, 3, 4]", noTypes);
    fixedValues.expectWidthEstimateCovers(noTypes);
    fixedValues[].expectPretty("[1, 2, 3, 4]", noTypes);

    PrettyPrintTestStaticArrayHolder holder =
        PrettyPrintTestStaticArrayHolder(fixedValues);
    holder.expectPretty("{values: [1, 2, 3, 4]}", noTypes);
    holder.expectWidthEstimateCovers(noTypes);

    char[3] fixedText = ['x', 't', 'b'];
    fixedText.expectPretty("\"xtb\"", noTypes);

    int[] empty;
    empty.expectPretty("[]", noTypes);

    PrettyPrintOptions limited = noTypes.withLayout(PrettyPrintLayout.compact);
    limited.maxItems = 2;
    fixedValues.expectPretty("[1, 2, ... (2 more)]", limited);
    limited.maxItems = 0;
    fixedValues.expectPretty("[... (4 more)]", limited);

    PrettyPrintOptions expanded = noTypes.withLayout(PrettyPrintLayout.expanded);
    fixedValues[0 .. 2].expectPretty("[\n  1,\n  2\n]", expanded);
    expanded.indentSize = 4;
    fixedValues[0 .. 2].expectPretty("[\n    1,\n    2\n]", expanded);

    PrettyPrintOptions automatic = noTypes;
    automatic.softMaxWidth = 5;
    fixedValues[0 .. 2].expectPretty("[\n  1,\n  2\n]", automatic);
    automatic.layout = PrettyPrintLayout.compact;
    fixedValues[0 .. 2].expectPretty("[1, 2]", automatic);
    automatic.layout = PrettyPrintLayout.automatic;
    automatic.softMaxWidth = 0;
    fixedValues[0 .. 1].expectPretty("[\n  1\n]", automatic);

    long[1] minimumInteger = [long.min];
    PrettyPrintOptions exactWidth = noTypes;
    exactWidth.softMaxWidth = 22;
    minimumInteger.expectPretty("[-9223372036854775808]", exactWidth);
    exactWidth.softMaxWidth = 21;
    minimumInteger.expectPretty(
        "[\n  -9223372036854775808\n]",
        exactWidth,
    );

    int[2][1] nestedValues = [[1, 2]];
    PrettyPrintOptions shallow = noTypes.withLayout(PrettyPrintLayout.compact);
    shallow.maxDepth = 0;
    nestedValues.expectPretty("[...]", shallow);
}

unittest
{
    PrettyPrintOptions plain = plainOptions();

    struct LocalRecord
    {
        int value;

        void touch()
        {
        }
    }

    LocalRecord localRecord;
    localRecord.value = 11;
    localRecord.expectPretty("LocalRecord {value: 11}", plain);
    localRecord.expectWidthEstimateCovers(plain);
    PrettyPrintOptions localLimited = plain.withLayout(PrettyPrintLayout.compact);
    localLimited.maxItems = 1;
    localRecord.expectPretty("LocalRecord {value: 11}", localLimited);

    PrettyPrintTestEmpty empty;
    empty.expectPretty("PrettyPrintTestEmpty {}", plain);

    PrettyPrintTestEmptyHolder emptyHolder;
    PrettyPrintOptions noDepth = plain.withLayout(PrettyPrintLayout.compact);
    noDepth.maxDepth = 0;
    emptyHolder.expectPretty(
        "PrettyPrintTestEmptyHolder {empty: PrettyPrintTestEmpty {}}",
        noDepth,
    );

    PrettyPrintTestRecord record = PrettyPrintTestRecord(7, "Ada");
    static assert(is(typeof(pretty(record)) ==
            PrettyValue!PrettyPrintTestRecord));
    static assert(is(typeof(pretty(PrettyPrintTestRecord.init)) ==
            OwnedPrettyValue!PrettyPrintTestRecord));

    record.expectPretty(
        "PrettyPrintTestRecord {id: 7, name: \"Ada\"}",
        plain,
    );
    record.expectWidthEstimateCovers(plain);

    const PrettyPrintTestRecord constRecord = record;
    constRecord.expectPretty(
        "PrettyPrintTestRecord {id: 7, name: \"Ada\"}",
        plain,
    );

    PrettyValue!PrettyPrintTestRecord emptyWrapper;
    emptyWrapper.options = plain;
    import xtb.core.print : writeBuffer;
    import xtb.core.string;

    char[32] emptyStorage;
    const emptyResult = writeBuffer(emptyStorage[], emptyWrapper);
    assert(emptyResult.ok);
    assert(emptyStorage[0 .. emptyResult.written].equal("null"));

    const PrettyValue!PrettyPrintTestRecord borrowedWrapper =
        pretty(record, plain);
    char[128] constWrapperStorage;
    const constWrapperResult = writeBuffer(
        constWrapperStorage[],
        borrowedWrapper,
    );
    assert(constWrapperResult.ok);
    assert(!constWrapperResult.truncated);
    assert(constWrapperStorage[0 .. constWrapperResult.written].equal(
            "PrettyPrintTestRecord {id: 7, name: \"Ada\"}",
    ));

    auto liveBorrow = record.pretty(plain);
    record.id = 8;
    char[128] liveBorrowStorage;
    const liveBorrowResult = writeBuffer(liveBorrowStorage[], liveBorrow);
    assert(liveBorrowResult.ok);
    assert(!liveBorrowResult.truncated);
    assert(liveBorrowStorage[0 .. liveBorrowResult.written].equal(
            "PrettyPrintTestRecord {id: 8, name: \"Ada\"}",
    ));
    record.id = 7;

    PrettyPrintTestRecord(8, "Grace").expectOwnedPretty(
        "PrettyPrintTestRecord {id: 8, name: \"Grace\"}",
        plain,
    );

    const OwnedPrettyValue!PrettyPrintTestEnumHolder constOwnedWrapper =
        pretty(PrettyPrintTestEnumHolder.init, plain);
    char[160] constOwnedStorage;
    const constOwnedResult = writeBuffer(
        constOwnedStorage[],
        constOwnedWrapper,
    );
    assert(constOwnedResult.ok);
    assert(!constOwnedResult.truncated);
    assert(constOwnedStorage[0 .. constOwnedResult.written].equal(
            "PrettyPrintTestEnumHolder {value: PrettyPrintTestSigned.zero}",
    ));

    PrettyPrintTestMoveOnly borrowedMoveOnly = PrettyPrintTestMoveOnly(4);
    borrowedMoveOnly.expectPretty(
        "PrettyPrintTestMoveOnly {value: 4}",
        plain,
    );
    PrettyPrintTestMoveOnly(5).expectOwnedPretty(
        "PrettyPrintTestMoveOnly {value: 5}",
        plain,
    );
    alias MoveWrapper = OwnedPrettyValue!PrettyPrintTestMoveOnly;
    static assert(!__traits(isCopyable, MoveWrapper));

    prettyPrintTestDestructions = 0;
    {
        PrettyPrintTestTrackedOwner tracked =
            PrettyPrintTestTrackedOwner(6, true);
        tracked.expectPretty(
            "PrettyPrintTestTrackedOwner {value: 6, ownsValue: true}",
            plain,
        );
        assert(prettyPrintTestDestructions == 0);
    }
    assert(prettyPrintTestDestructions == 1);

    prettyPrintTestDestructions = 0;
    PrettyPrintTestTrackedOwner(7, true).expectOwnedPretty(
        "PrettyPrintTestTrackedOwner {value: 7, ownsValue: true}",
        plain,
    );
    assert(prettyPrintTestDestructions == 1);

    {
        import xtb.core.allocators.instrumented : AllocationRecord,
            InstrumentedAllocator;
        import xtb.core.allocators.malloc : mallocAllocator;

        AllocationRecord[4] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(),
            records[],
        );
        {
            OwnedString owner = OwnedString.fromString(
                allocator.allocator,
                "owned pretty",
            );
            auto wrapper = pretty(move(owner), plain);
            assert(!allocator.clean());
        }
        assert(allocator.clean());
        assert(allocator.stats.invalidCalls == 0);
    }

    PrettyPrintTestRecord interpolatedRecord =
        PrettyPrintTestRecord(9, "Lin");
    char[192] interpolationStorage;
    const interpolationResult = writeBuffer(
        interpolationStorage[],
        i"record=$(interpolatedRecord.pretty(plain))",
    );
    assert(interpolationResult.ok);
    assert(!interpolationResult.truncated);
    assert(interpolationStorage[0 .. interpolationResult.written].equal(
            "record=PrettyPrintTestRecord {id: 9, name: \"Lin\"}",
    ));

    PrettyPrintOptions expanded = plain.withLayout(PrettyPrintLayout.expanded);
    record.expectPretty(
        "PrettyPrintTestRecord {\n  id: 7,\n  name: \"Ada\"\n}",
        expanded,
    );

    PrettyPrintTestOuter outer = PrettyPrintTestOuter(record, 3);
    PrettyPrintOptions shallow = plain.withLayout(PrettyPrintLayout.compact);
    shallow.maxDepth = 0;
    outer.expectPretty(
        "PrettyPrintTestOuter {inner: ..., tail: 3}",
        shallow,
    );

    PrettyPrintTestManyFields many = PrettyPrintTestManyFields(1, 2, 3);
    PrettyPrintOptions limited = plain.withLayout(PrettyPrintLayout.compact);
    limited.maxItems = 2;
    many.expectPretty(
        "PrettyPrintTestManyFields {first: 1, second: 2, ... (1 more)}",
        limited,
    );
    limited.maxItems = 0;
    many.expectPretty(
        "PrettyPrintTestManyFields {... (3 more)}",
        limited,
    );
}

unittest
{
    PrettyPrintOptions plain = plainOptions();

    PrettyPrintTestOverride withOptions = PrettyPrintTestOverride(1);
    withOptions.expectPretty("<pretty with options>", plain);
    PrettyPrintOptions noTypes = plain;
    noTypes.showTypeNames = false;
    withOptions.expectPretty("<pretty without types>", noTypes);

    import xtb.core.print : writeBuffer;
    import xtb.core.string;

    PrettyPrintTestBothOverrides both = PrettyPrintTestBothOverrides(1);
    both.expectPretty("<pretty wins>", plain);
    char[64] bothNormalStorage;
    const bothNormalResult = writeBuffer(bothNormalStorage[], both);
    assert(bothNormalResult.ok);
    assert(bothNormalStorage[0 .. bothNormalResult.written].equal(
            "<normal format>",
    ));

    // Normal display formatting and structural debug formatting are separate.
    // `formatTo` is ignored by `.pretty` unless the type also opts into the
    // const-compatible `prettyFormatTo` hook.
    PrettyPrintTestFormatOverride displayOnly = PrettyPrintTestFormatOverride(9);
    char[64] normalStorage;
    const normalResult = writeBuffer(normalStorage[], displayOnly);
    assert(normalResult.ok);
    assert(normalStorage[0 .. normalResult.written].equal("<format override>"));
    displayOnly.expectPretty(
        "PrettyPrintTestFormatOverride {ignored: 9}",
        plain,
    );

    prettyPrintTestHookCalls = 0;
    PrettyPrintTestCountedHolder counted = PrettyPrintTestCountedHolder(
        PrettyPrintTestCountedOverride.init,
        2,
    );
    counted.expectPretty(
        "PrettyPrintTestCountedHolder {\n" ~
            "  item: <counted>,\n" ~
            "  tail: 2\n" ~
            "}",
        plain,
    );
    assert(prettyPrintTestHookCalls == 1);

    // A mutable-only pretty hook is deliberately not called. Pretty printing
    // observes through a const view and cannot mutate the inspected value.
    PrettyPrintTestMutableOnlyOverride mutableOnly =
        PrettyPrintTestMutableOnlyOverride(4);
    mutableOnly.expectPretty(
        "PrettyPrintTestMutableOnlyOverride {value: 4}",
        plain,
    );
}

unittest
{
    PrettyPrintOptions noTypes = plainOptions();
    noTypes.showTypeNames = false;

    int number = 42;
    int* pointer = &number;
    PrettyPrintOptions dereferenced = noTypes;
    dereferenced.dereferencePointers = true;
    pointer.expectPretty("&42", dereferenced);
    pointer.expectWidthEstimateCovers(dereferenced);

    PrettyPrintTestRecord record = PrettyPrintTestRecord(3, "node");
    PrettyPrintTestPointerHolder holder = PrettyPrintTestPointerHolder(
        &record,
        8,
    );
    PrettyPrintOptions expanded = dereferenced.withLayout(
        PrettyPrintLayout.expanded,
    );
    expanded.indentSize = 4;
    holder.expectPretty(
        "{\n" ~
            "    item: &{\n" ~
            "        id: 3,\n" ~
            "        name: \"node\"\n" ~
            "    },\n" ~
            "    tail: 8\n" ~
            "}",
        expanded,
    );
    holder.expectWidthEstimateCovers(dereferenced);

    int* nullPointer;
    nullPointer.expectPretty("null", noTypes);

    import xtb.core.print : writeBuffer;
    import xtb.core.string;

    char[128] addressStorage;
    const addressResult = writeBuffer(addressStorage[], pointer.pretty(noTypes));
    assert(addressResult.ok);
    assert(addressResult.written > 3);
    assert(addressStorage[0 .. 3].equal("@0x"));

    alias TestFunctionPointer = extern (C) int function(int) nothrow @nogc;
    TestFunctionPointer functionPointer = &prettyPrintTestFunction;
    char[256] functionStorage;
    const functionResult = writeBuffer(
        functionStorage[],
        functionPointer.pretty(dereferenced),
    );
    assert(functionResult.ok);
    assert(functionResult.written > 3);
    assert(functionStorage[0 .. 3].equal("@0x"));

    TestFunctionPointer nullFunction;
    nullFunction.expectPretty("null", noTypes);

    void* opaque = cast(void*) pointer;
    char[128] opaqueStorage;
    const opaqueResult = writeBuffer(
        opaqueStorage[],
        opaque.pretty(dereferenced),
    );
    assert(opaqueResult.ok);
    assert(opaqueResult.written > 3);
    assert(opaqueStorage[0 .. 3].equal("@0x"));

    PrettyPrintTestNode node = PrettyPrintTestNode(1, null);
    node.next = &node;
    PrettyPrintOptions bounded = noTypes.withLayout(
        PrettyPrintLayout.compact,
    );
    bounded.showTypeNames = true;
    bounded.dereferencePointers = true;
    bounded.maxDepth = 1;
    node.expectPretty(
        "PrettyPrintTestNode {value: 1, next: &...}",
        bounded,
    );
}

unittest
{
    PrettyPrintOptions plain = plainOptions();
    PrettyPrintTestUnion value;
    value.integer = 7;
    value.expectPretty(
        "PrettyPrintTestUnion <union: active member unknown>",
        plain,
    );
    value.expectWidthEstimateCovers(plain);
}

unittest
{
    PrettyPrintOptions compact = plainOptions().withLayout(
        PrettyPrintLayout.compact,
    );
    PrettyPrintOptions expanded = plainOptions().withLayout(
        PrettyPrintLayout.expanded,
    );

    PrettyPrintTestTaggedValue value;
    value.kind = PrettyPrintTestTaggedKind.integer;
    value.payload.integer = 7;
    value.expectPretty(
        "PrettyPrintTestTaggedValue {kind: PrettyPrintTestTaggedKind.integer, "
            ~ "payload: PrettyPrintTestTaggedPayload {integer: 7}}",
        compact,
    );
    value.expectPretty(
        "PrettyPrintTestTaggedValue {
"
            ~ "  kind: PrettyPrintTestTaggedKind.integer,
"
            ~ "  payload: PrettyPrintTestTaggedPayload {
"
            ~ "    integer: 7
"
            ~ "  }
"
            ~ "}",
        expanded,
    );
    value.expectWidthEstimateCovers(compact);

    value.kind = PrettyPrintTestTaggedKind.floating;
    value.payload.renamedFloating = 9;
    value.expectPretty(
        "PrettyPrintTestTaggedValue {kind: PrettyPrintTestTaggedKind.floating, "
            ~ "payload: PrettyPrintTestTaggedPayload {renamedFloating: 9}}",
        compact,
    );
    value.expectWidthEstimateCovers(compact);

    value.kind = PrettyPrintTestTaggedKind.none;
    value.expectPretty(
        "PrettyPrintTestTaggedValue {kind: PrettyPrintTestTaggedKind.none, "
            ~ "payload: PrettyPrintTestTaggedPayload {}}",
        compact,
    );
    value.expectWidthEstimateCovers(compact);

    value.kind = cast(PrettyPrintTestTaggedKind) 99;
    value.expectPretty(
        "PrettyPrintTestTaggedValue {kind: PrettyPrintTestTaggedKind(99), "
            ~ "payload: PrettyPrintTestTaggedPayload "
            ~ "<invalid tagged union discriminator>}",
        compact,
    );
    value.expectWidthEstimateCovers(compact);
}

unittest
{
    import xtb.core.allocators.malloc : mallocAllocator;

    PrettyPrintOptions noTypes = plainOptions();
    noTypes.showTypeNames = false;

    Array!int values = Array!int.create(mallocAllocator());
    values.expectPretty("[]", noTypes);
    values.append(1);
    values.append(2);
    values.expectPretty("[1, 2]", noTypes);
    values.expectWidthEstimateCovers(noTypes);
    PrettyPrintOptions noneShown = noTypes.withLayout(PrettyPrintLayout.compact);
    noneShown.maxItems = 0;
    values.expectPretty("[... (2 more)]", noneShown);
    values.deinit();

    OwnedArray!int ownedValues = OwnedArray!int.create(mallocAllocator());
    ownedValues.append(3);
    ownedValues.append(4);
    ownedValues.expectPretty("[3, 4]", noTypes);
    ownedValues.expectWidthEstimateCovers(noTypes);
    ownedValues.deinit();

    HashMap!(String, int) map = HashMap!(String, int).create(mallocAllocator());
    map.expectPretty("{}", noTypes);
    assert(map.set("one", 1));
    map.expectPretty("{\"one\": 1}", noTypes);
    map.expectWidthEstimateCovers(noTypes);
    map.expectPretty("{... (1 more)}", noneShown);
    map.deinit();

    HashSet!int hashSet = HashSet!int.create(mallocAllocator());
    hashSet.expectPretty("{}", noTypes);
    assert(hashSet.add(7));
    hashSet.expectPretty("{7}", noTypes);
    hashSet.expectWidthEstimateCovers(noTypes);
    hashSet.expectPretty("{... (1 more)}", noneShown);
    hashSet.deinit();

    OwnedHashMap!(String, int) ownedMap =
        OwnedHashMap!(String, int).create(mallocAllocator());
    String ownedKey = "owned";
    int ownedValue = 9;
    assert(ownedMap.add(&ownedKey, &ownedValue));
    ownedMap.expectPretty("{\"owned\": 9}", noTypes);
    ownedMap.expectWidthEstimateCovers(noTypes);
    ownedMap.deinit();

    OwnedHashSet!int ownedSet = OwnedHashSet!int.create(mallocAllocator());
    int ownedElement = 11;
    assert(ownedSet.add(&ownedElement));
    ownedSet.expectPretty("{11}", noTypes);
    ownedSet.expectWidthEstimateCovers(noTypes);
    ownedSet.deinit();

    ArrayUnmanaged!int unmanagedValues;
    unmanagedValues.append(mallocAllocator(), 5);
    unmanagedValues.append(mallocAllocator(), 6);
    unmanagedValues.expectPretty("[5, 6]", noTypes);
    unmanagedValues.expectWidthEstimateCovers(noTypes);
    unmanagedValues.deinit(mallocAllocator());

    HashMapUnmanaged!(String, int) unmanagedMap;
    assert(unmanagedMap.set(mallocAllocator(), "unmanaged", 13));
    unmanagedMap.expectPretty("{\"unmanaged\": 13}", noTypes);
    unmanagedMap.expectWidthEstimateCovers(noTypes);
    unmanagedMap.deinit(mallocAllocator());

    HashSetUnmanaged!int unmanagedSet;
    assert(unmanagedSet.add(mallocAllocator(), 17));
    unmanagedSet.expectPretty("{17}", noTypes);
    unmanagedSet.expectWidthEstimateCovers(noTypes);
    unmanagedSet.deinit(mallocAllocator());

    StringHashMapUnmanaged!int unmanagedStringMap;
    assert(unmanagedStringMap.set(mallocAllocator(), "string", 19));
    unmanagedStringMap.expectPretty("{\"string\": 19}", noTypes);
    unmanagedStringMap.expectWidthEstimateCovers(noTypes);
    unmanagedStringMap.deinit(mallocAllocator());

    StringHashMap!int stringMap = StringHashMap!int.create(mallocAllocator());
    assert(stringMap.set("managed-string", 23));
    stringMap.expectPretty("{\"managed-string\": 23}", noTypes);
    stringMap.expectWidthEstimateCovers(noTypes);
    stringMap.deinit();

    OwnedStringHashMap!int ownedStringMap =
        OwnedStringHashMap!int.create(mallocAllocator());
    assert(ownedStringMap.set("owned-string", 29));
    ownedStringMap.expectPretty("{\"owned-string\": 29}", noTypes);
    ownedStringMap.expectWidthEstimateCovers(noTypes);
    ownedStringMap.deinit();

    StringHashSetUnmanaged unmanagedStringSet;
    assert(unmanagedStringSet.add(mallocAllocator(), "unmanaged-set"));
    unmanagedStringSet.expectPretty("{\"unmanaged-set\"}", noTypes);
    unmanagedStringSet.expectWidthEstimateCovers(noTypes);
    unmanagedStringSet.deinit(mallocAllocator());

    StringHashSet stringSet = StringHashSet.create(mallocAllocator());
    assert(stringSet.add("managed-set"));
    stringSet.expectPretty("{\"managed-set\"}", noTypes);
    stringSet.expectWidthEstimateCovers(noTypes);
    stringSet.deinit();
}

unittest
{
    PrettyPrintOptions noTypes = plainOptions();
    noTypes.showTypeNames = false;
    alias Permissions = FlagSet!PrettyPrintTestPermission;

    Permissions permissions = Permissions.of(
        PrettyPrintTestPermission.read,
        PrettyPrintTestPermission.execute,
        PrettyPrintTestPermission.administer,
    );
    permissions.expectPretty("{read, execute, administer}", noTypes);
    permissions.expectWidthEstimateCovers(noTypes);

    PrettyPrintOptions limited = noTypes.withLayout(PrettyPrintLayout.compact);
    limited.maxItems = 2;
    permissions.expectPretty("{read, execute, ... (1 more)}", limited);
    limited.maxItems = 0;
    permissions.expectPretty("{... (3 more)}", limited);
}

unittest
{
    import xtb.core.print : writeBuffer;
    import xtb.core.string;

    int number = 42;
    char[64] storage;
    const defaultResult = writeBuffer(storage[], number.pretty);
    assert(defaultResult.ok);
    assert(storage[0 .. defaultResult.written].equal("\x1b[34m42\x1b[0m"));

    PrettyPrintColorScheme scheme = PrettyPrintColorScheme.init;
    scheme.numberValue = AnsiStyle.foreground(AnsiColor.brightRed);
    PrettyPrintOptions custom = PrettyPrintOptions.init.withColorScheme(scheme);
    char[64] customStorage;
    const customResult = writeBuffer(customStorage[], number.pretty(custom));
    assert(customResult.ok);
    assert(customStorage[0 .. customResult.written].equal(
            "\x1b[91m42\x1b[0m",
    ));

    char[2] tiny;
    const truncated = writeBuffer(tiny[], number.pretty(custom.withoutColors()));
    assert(truncated.ok);
    assert(truncated.truncated);
    assert(truncated.written == 1);
    assert(truncated.required == 2);
}

unittest
{
    // Every configurable semantic style is exercised through public pretty
    // output. Keeping all unrelated styles disabled makes each expectation
    // prove exactly which category owns the emitted token.
    AnsiStyle red = AnsiStyle.foreground(AnsiColor.brightRed);
    PrettyPrintOptions base = PrettyPrintOptions.init.withLayout(
        PrettyPrintLayout.compact,
    );
    base.showTypeNames = false;
    base.colorScheme = disabledColorScheme();

    int number = 42;
    PrettyPrintOptions numberOptions = base;
    numberOptions.colorScheme.numberValue = red;
    number.expectPretty("\x1b[91m42\x1b[0m", numberOptions);

    bool boolean = true;
    PrettyPrintOptions booleanOptions = base;
    booleanOptions.colorScheme.booleanValue = red;
    boolean.expectPretty("\x1b[91mtrue\x1b[0m", booleanOptions);

    String text = "value";
    PrettyPrintOptions stringOptions = base;
    stringOptions.colorScheme.stringValue = red;
    text.expectPretty("\x1b[91m\"value\"\x1b[0m", stringOptions);

    char character = 'x';
    PrettyPrintOptions characterOptions = base;
    characterOptions.colorScheme.characterValue = red;
    character.expectPretty("\x1b[91m'x'\x1b[0m", characterOptions);

    PrettyPrintTestColor enumeration = PrettyPrintTestColor.red;
    PrettyPrintOptions enumOptions = base;
    enumOptions.colorScheme.enumValue = red;
    enumeration.expectPretty("\x1b[91mred\x1b[0m", enumOptions);

    typeof(null) nothing;
    PrettyPrintOptions nullOptions = base;
    nullOptions.colorScheme.nullValue = red;
    nothing.expectPretty("\x1b[91mnull\x1b[0m", nullOptions);

    PrettyPrintTestRecord record = PrettyPrintTestRecord(7, "Ada");
    PrettyPrintOptions typeOptions = base;
    typeOptions.showTypeNames = true;
    typeOptions.colorScheme.typeName = red;
    record.expectPretty(
        "\x1b[91mPrettyPrintTestRecord\x1b[0m {id: 7, name: \"Ada\"}",
        typeOptions,
    );

    PrettyPrintOptions fieldOptions = base;
    fieldOptions.colorScheme.fieldName = red;
    record.expectPretty(
        "{\x1b[91mid\x1b[0m: 7, " ~
            "\x1b[91mname\x1b[0m: \"Ada\"}",
        fieldOptions,
    );

    int[2] values = [1, 2];
    PrettyPrintOptions punctuationOptions = base;
    punctuationOptions.colorScheme.punctuation = red;
    values.expectPretty(
        "\x1b[91m[\x1b[0m1\x1b[91m, \x1b[0m2" ~
            "\x1b[91m]\x1b[0m",
        punctuationOptions,
    );

    PrettyPrintOptions truncationOptions = base;
    truncationOptions.maxItems = 1;
    truncationOptions.colorScheme.truncation = red;
    values.expectPretty(
        "[1, \x1b[91m... (1 more)\x1b[0m]",
        truncationOptions,
    );

    int[1][1] nested = [[1]];
    PrettyPrintOptions depthOptions = base;
    depthOptions.maxDepth = 0;
    depthOptions.colorScheme.depthLimit = red;
    nested.expectPretty("[\x1b[91m...\x1b[0m]", depthOptions);

    int* pointer = &number;
    PrettyPrintOptions pointerOptions = base;
    pointerOptions.dereferencePointers = true;
    pointerOptions.colorScheme.pointerValue = red;
    pointer.expectPretty("\x1b[91m&\x1b[0m42", pointerOptions);

    PrettyPrintTestUnion unionValue;
    unionValue.integer = 1;
    PrettyPrintOptions unsupportedOptions = base;
    unsupportedOptions.colorScheme.unsupported = red;
    unionValue.expectPretty(
        "\x1b[91m<union: active member unknown>\x1b[0m",
        unsupportedOptions,
    );

    // Turning colors off suppresses even an otherwise enabled custom style.
    number.expectPretty("42", numberOptions.withoutColors());
}
