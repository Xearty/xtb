module xtb.fmt.pretty_print;

nothrow @nogc:

import xtb.ansi;
import xtb.fmt.ansi;
import xtb.fmt.writer;
import xtb.lifetime;
import xtb.types;

/// Controls how aggregate values are laid out.
enum PrettyPrintLayout : u8
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
nothrow @nogc:

    ANSIStyle type_name = ANSIStyle.foreground(ANSIColor.bright_magenta);
    ANSIStyle field_name = ANSIStyle.foreground(ANSIColor.bright_cyan);
    ANSIStyle string_value = ANSIStyle.foreground(ANSIColor.green);
    ANSIStyle character_value = ANSIStyle.foreground(ANSIColor.green);
    ANSIStyle number_value = ANSIStyle.foreground(ANSIColor.blue);
    ANSIStyle boolean_value = ANSIStyle.foreground(ANSIColor.yellow);
    ANSIStyle constructor_name = ANSIStyle.foreground(ANSIColor.bright_yellow);
    ANSIStyle enum_value = ANSIStyle.foreground(ANSIColor.bright_green);
    ANSIStyle null_value = ANSIStyle.foreground(ANSIColor.bright_black);
    ANSIStyle pointer_value = ANSIStyle.foreground(ANSIColor.magenta);
    ANSIStyle punctuation;
    ANSIStyle truncation = ANSIStyle.foreground(ANSIColor.bright_black);
    ANSIStyle depth_limit = ANSIStyle.foreground(ANSIColor.bright_red);
    ANSIStyle unsupported = ANSIStyle.foreground(ANSIColor.bright_red);

    static PrettyPrintColorScheme defaults() pure @safe
    {
        return PrettyPrintColorScheme.init;
    }
}

/// Runtime policy for pretty printing.
///
/// `PrettyPrintOptions.init` is deliberately useful. Callers only need to pass
/// options when they want to change a policy or color. `soft_max_width` counts
/// emitted UTF-8 bytes while ignoring ANSI sequences; it is a layout hint, not
/// a Unicode terminal-column measurement.
struct PrettyPrintOptions
{
nothrow @nogc:

    u16 indent_size = 2;
    u16 max_depth = 8;
    u32 max_items = 32;
    u32 soft_max_width = 80;
    PrettyPrintLayout layout = PrettyPrintLayout.automatic;
    bool colored = true;
    bool show_type_names = true;

    /// Pointers are shown as typed addresses by default. Enabling this follows
    /// the pointer and is useful for trusted object graphs, but may be unsafe
    /// for stale or otherwise invalid pointers.
    bool dereference_pointers;

    PrettyPrintColorScheme color_scheme;

    static PrettyPrintOptions defaults() pure @safe
    {
        return PrettyPrintOptions.init;
    }

    PrettyPrintOptions with_color_scheme(PrettyPrintColorScheme scheme) const pure @safe
    {
        PrettyPrintOptions result = this;
        result.color_scheme = scheme;
        return result;
    }

    PrettyPrintOptions without_colors() const pure @safe
    {
        PrettyPrintOptions result = this;
        result.colored = false;
        return result;
    }

    PrettyPrintOptions with_layout(PrettyPrintLayout requested) const pure @safe
    {
        PrettyPrintOptions result = this;
        result.layout = requested;
        return result;
    }
}

/// Borrowed formatting wrapper accepted by every `xtb.fmt.print` entry point.
///
/// The zero value is safe and prints `null`. A wrapper returned from the
/// lvalue overload of `pretty` borrows its source and must not outlive it.
/// The stored pointer is const-qualified because pretty printing is an
/// observation and must not mutate the inspected value.
struct PrettyValue(T)
{
nothrow @nogc:

    const(T)* value;
    PrettyPrintOptions options;

    void format_to(ref Writer writer) const
    {
        write_pretty_pointer!T(writer, this.value, this.options);
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
nothrow @nogc:

    T value;
    PrettyPrintOptions options;

    static if (needs_deinit!T)
    {
        @disable this(this);
        @disable ref OwnedPrettyValue opAssign(OwnedPrettyValue source) return;

        ~this()
        {
            deinit(this.value);
        }
    }

    void format_to(ref Writer writer) const
    {
        write_pretty_impl(writer, this.value, this.options, PrettyPrintContext.init);
    }
}

private void write_pretty_pointer(T)(
    ref Writer writer,
    scope const(T)* value,
    scope const ref PrettyPrintOptions options,
)
{
    if (value is null)
    {
        write_styled_text(
            writer,
            "null",
            options.color_scheme.null_value,
            options,
        );
        return;
    }

    write_pretty_impl(writer, *value, options, PrettyPrintContext.init);
}

/// Borrows an lvalue for `write`, `writeln`, `write_buffer`, and the other
/// `xtb.fmt.print` APIs. This overload is preferred for lvalues and does not
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
    result.value = &value;
    result.options = options;
    return result;
}

/// Owns an rvalue for `write`, `writeln`, `write_buffer`, and the other
/// `xtb.fmt.print` APIs. This overload is preferred for temporaries.
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
/// `void pretty_describe(Pretty)(scope ref Pretty)` member
/// that describes the value through `pretty.value`, `atom`, `constructor`,
/// `sequence`, `map`, `set`, or `flags`. The description is interpreted both
/// for rendering and width measurement, so it must be deterministic,
/// observational, and safe to invoke more than once.
///
/// `void pretty_format_to(ref Writer, scope const ref PrettyPrintOptions)`
/// remains the low-level escape hatch for syntax that cannot use those
/// semantic forms. Its automatic width is unknown. A type must not define both
/// pretty hooks.
/// Ordinary `format_representation` and `format_to` are separate normal-display
/// customization points and are deliberately ignored here.
void write_pretty(T)(
    ref Writer writer,
    auto ref T value,
    PrettyPrintOptions options = PrettyPrintOptions.init,
)
{
    write_pretty_impl(writer, value, options, PrettyPrintContext.init);
}

private template Unqualified(T)
{
    alias Unqualified = typeof(cast() T.init);
}

private enum is_string_type(T) = is(Unqualified!T == String)
    || is(Unqualified!T == char[])
    || is(Unqualified!T == const(char)[])
    || is(Unqualified!T == immutable(char)[]);

private enum is_character_type(T) = is(Unqualified!T == char)
    || is(Unqualified!T == wchar)
    || is(Unqualified!T == dchar);

// `void` has no value to dereference. Keep this check independent of
// `Unqualified`, whose implementation intentionally operates on value types
// and therefore cannot be instantiated for `void` itself.
private enum is_void_pointee(T) = is(T == void)
    || is(T == const(void))
    || is(T == immutable(void));

// Keep pointer recognition in its own template scope. Binding a pointee alias
// directly in more than one `static if` condition inside the same function
// redeclares that alias for pointer instantiations.
private enum is_pointer_type(T) = is(Unqualified!T == Pointee*, Pointee);

/// Tracks semantic recursion separately from visual indentation. Constructor-
/// like wrappers such as `some(...)` and `&...` increase recursion depth but
/// do not add an indentation level when their child starts on the same line.
private struct PrettyPrintContext
{
    u16 recursion_depth;
    u16 indentation_depth;
}

private enum PrettyRole : u8
{
    null_value,
}

private struct PrettyRender(Described)
{
nothrow @nogc:

    Writer* writer;
    const(PrettyPrintOptions)* options;
    PrettyPrintContext context;

    enum null_role = PrettyRole.null_value;

    void value(Value)(auto ref Value semantic_value)
    {
        write_pretty_impl(*this.writer, semantic_value, *this.options, this.context);
    }

    void atom(scope String name, PrettyRole role)
    {
        write_semantic_type_prefix!Described(*this.writer, *this.options, '.');
        write_styled_text(
            *this.writer,
            name,
            pretty_role_style(role, *this.options),
            *this.options,
        );
    }

    void constructor(scope String name)
    {
        write_semantic_type_prefix!Described(*this.writer, *this.options, '.');
        write_styled_text(
            *this.writer,
            name,
            this.options.color_scheme.constructor_name,
            *this.options,
        );
        write_punctuation(*this.writer, "()", *this.options);
    }

    void constructor(Value)(scope String name, auto ref Value payload)
    {
        write_semantic_type_prefix!Described(*this.writer, *this.options, '.');
        write_styled_text(
            *this.writer,
            name,
            this.options.color_scheme.constructor_name,
            *this.options,
        );
        write_punctuation(*this.writer, '(', *this.options);
        if (depth_limit_reached(this.context.recursion_depth, *this.options))
        {
            write_depth_limit(*this.writer, *this.options);
        }
        else
        {
            PrettyPrintContext child_context = descend_wrapper(this.context);
            write_pretty_impl(*this.writer, payload, *this.options, child_context);
        }
        write_punctuation(*this.writer, ')', *this.options);
    }

    void sequence(Source)(auto ref Source source)
    {
        validate_pretty_sequence_source(source);
        write_semantic_sequence!Described(
            *this.writer,
            source,
            *this.options,
            this.context,
        );
    }

    void map(Source)(auto ref Source source)
    {
        validate_pretty_map_source(source);
        write_hash_map!Described(*this.writer, source, *this.options, this.context);
    }

    void set(Source)(auto ref Source source)
    {
        validate_pretty_set_source(source);
        write_hash_set!Described(*this.writer, source, *this.options, this.context);
    }

    void flags(Source)(auto ref Source source)
    {
        validate_pretty_flags_source(source);
        write_flag_set!Described(*this.writer, source, *this.options, this.context);
    }
}

private struct PrettyMeasure(Described)
{
nothrow @nogc:

    const(PrettyPrintOptions)* options;
    PrettyPrintContext context;
    usize budget;
    WidthEstimate result_value = WidthEstimate(true, 0);

    enum null_role = PrettyRole.null_value;

    WidthEstimate result() const pure @safe
    {
        return this.result_value;
    }

    void value(Value)(auto ref Value semantic_value)
    {
        this.append(estimate_width(
            semantic_value,
            *this.options,
            this.context.recursion_depth,
            this.remaining_budget,
        ));
    }

    void atom(scope String name, PrettyRole)
    {
        usize width = semantic_type_prefix_width!Described(*this.options);
        if (name.length > usize.max - width)
        {
            this.result_value = unknown_width();
            return;
        }
        width += name.length;
        this.append(known_width(width));
    }

    void constructor(scope String name)
    {
        usize width = semantic_type_prefix_width!Described(*this.options);
        if (name.length > usize.max - width
            || 2 > usize.max - width - name.length)
        {
            this.result_value = unknown_width();
            return;
        }
        width += name.length + 2;
        this.append(known_width(width));
    }

    void constructor(Value)(scope String name, auto ref Value payload)
    {
        usize width = semantic_type_prefix_width!Described(*this.options);
        if (name.length > usize.max - width
            || 1 > usize.max - width - name.length)
        {
            this.result_value = unknown_width();
            return;
        }
        width += name.length + 1;

        if (depth_limit_reached(this.context.recursion_depth, *this.options))
        {
            if (4 > usize.max - width)
            {
                this.result_value = unknown_width();
                return;
            }
            width += 4;
            this.append(known_width(width));
            return;
        }

        const available = this.remaining_budget;
        const child = estimate_width(
            payload,
            *this.options,
            next_depth(this.context.recursion_depth),
            available > width ? available - width : 0,
        );
        if (!child.known || child.width > usize.max - width)
        {
            this.result_value = unknown_width();
            return;
        }
        width += child.width;
        if (width == usize.max)
        {
            this.result_value = unknown_width();
            return;
        }
        ++width;
        this.append(known_width(width));
    }

    void sequence(Source)(auto ref Source source)
    {
        validate_pretty_sequence_source(source);
        this.append(estimate_semantic_sequence!Described(
            source,
            *this.options,
            this.context.recursion_depth,
            this.remaining_budget,
        ));
    }

    void map(Source)(auto ref Source source)
    {
        validate_pretty_map_source(source);
        this.append(estimate_hash_map!Described(
            source,
            *this.options,
            this.context.recursion_depth,
            this.remaining_budget,
        ));
    }

    void set(Source)(auto ref Source source)
    {
        validate_pretty_set_source(source);
        this.append(estimate_hash_set!Described(
            source,
            *this.options,
            this.context.recursion_depth,
            this.remaining_budget,
        ));
    }

    void flags(Source)(auto ref Source source)
    {
        validate_pretty_flags_source(source);
        this.append(estimate_flag_set!Described(
            source,
            *this.options,
            this.remaining_budget,
        ));
    }

    private usize remaining_budget() const pure @safe
    {
        if (!this.result_value.known || this.result_value.width >= this.budget) return 0;
        return this.budget - this.result_value.width;
    }

    private void append(WidthEstimate part) pure @safe
    {
        if (!this.result_value.known
            || !part.known
            || part.width > usize.max - this.result_value.width)
        {
            this.result_value = unknown_width();
            return;
        }
        const total = this.result_value.width + part.width;
        if (total > this.budget)
        {
            this.result_value = unknown_width();
            return;
        }
        this.result_value = known_width(total);
    }
}

private enum has_pretty_describe(T) = __traits(hasMember, Unqualified!T, "pretty_describe");

private enum has_pretty_format_to_member(T) =
    __traits(hasMember, Unqualified!T, "pretty_format_to");

private void validate_pretty_sequence_source(Source)(scope const ref Source source)
{
    enum has_indexed_access = __traits(compiles, source.length)
        && __traits(compiles, source[0]);
    static assert(
        has_indexed_access,
        "pretty.sequence source must provide length and indexed access",
    );
}

private void validate_pretty_map_source(Source)(scope const ref Source source)
{
    enum has_map_source = __traits(compiles, source.length)
        && __traits(compiles, source.cursor());
    static assert(has_map_source, "pretty.map source must provide length and cursor()");

    enum has_map_cursor = __traits(compiles,
    {
        auto cursor = source.cursor();
        const valid = cursor.valid;
        const key = *cursor.key;
        const value = *cursor.value;
        cursor.advance();
    });
    static assert(
        has_map_cursor,
        "pretty.map cursor must provide valid, key, value, and advance()",
    );
}

private void validate_pretty_set_source(Source)(scope const ref Source source)
{
    enum has_set_source = __traits(compiles, source.length)
        && __traits(compiles, source.cursor());
    static assert(has_set_source, "pretty.set source must provide length and cursor()");

    enum has_set_cursor = __traits(compiles,
    {
        auto cursor = source.cursor();
        const valid = cursor.valid;
        const value = *cursor.value;
        cursor.advance();
    });
    static assert(has_set_cursor, "pretty.set cursor must provide valid, value, and advance()");
}

private void validate_pretty_flags_source(Source)(scope const ref Source source)
{
    alias U = Unqualified!Source;
    enum has_flag_source = __traits(hasMember, U, "FlagType")
        && __traits(compiles, source.enabled_count);
    static assert(has_flag_source, "pretty.flags source must provide FlagType and enabled_count");

    static if (__traits(hasMember, U, "FlagType"))
    {
        alias Flag = U.FlagType;
        static foreach (name; __traits(allMembers, Flag))
        {{
            enum flag = __traits(getMember, Flag, name);
            static assert(
                __traits(compiles, source.contains(flag)),
                "pretty.flags source must provide contains(FlagType)",
            );
        }}
    }
}

private usize semantic_type_prefix_width(Described)(
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    return options.show_type_names ? Described.stringof.length + 1 : 0;
}

private void write_semantic_type_prefix(Described)(
    ref Writer writer,
    scope const ref PrettyPrintOptions options,
    char separator,
)
{
    if (!options.show_type_names) return;
    write_type_name!Described(writer, options);
    write_punctuation(writer, separator, options);
}

private ANSIStyle pretty_role_style(
    PrettyRole role,
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    final switch (role)
    {
    case PrettyRole.null_value:
        return options.color_scheme.null_value;
    }
}

private void write_pretty_impl(T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;

    static if (is_pointer_type!U)
    {
        if (value is null)
        {
            write_styled_text(
                writer,
                "null",
                options.color_scheme.null_value,
                options,
            );
            return;
        }
    }

    enum has_conflicting_hooks = has_pretty_describe!T && has_pretty_format_to_member!T;
    static assert(
        !has_conflicting_hooks,
        U.stringof ~ " defines both pretty_describe and pretty_format_to",
    );

    static if (has_pretty_describe!T)
    {
        PrettyRender!U pretty = PrettyRender!U(&writer, &options, context);
        alias DescribeReturn = typeof(value.pretty_describe(pretty));
        static assert(
            is(DescribeReturn == void),
            U.stringof ~ ".pretty_describe(...) must return void",
        );
        value.pretty_describe(pretty);
    }
    else static if (has_pretty_format_to!T)
    {
        alias FormatReturn = typeof(value.pretty_format_to(writer, options));
        static assert(
            is(FormatReturn == void),
            U.stringof ~ ".pretty_format_to(...) must return void",
        );
        value.pretty_format_to(writer, options);
    }
    else static if (is(U == typeof(null)))
    {
        write_styled_text(
            writer,
            "null",
            options.color_scheme.null_value,
            options,
        );
    }
    else static if (is_string_type!U)
    {
        write_string(writer, cast(String) value, options);
    }
    else static if (is(U == bool))
    {
        write_styled_text(
            writer,
            value ? "true" : "false",
            options.color_scheme.boolean_value,
            options,
        );
    }
    else static if (is_character_type!U)
    {
        write_character(writer, value, options);
    }
    else static if (is(U == enum))
    {
        write_enum(writer, value, options);
    }
    else static if (
        (__traits(isIntegral, U) && U.sizeof <= u64.sizeof)
        || __traits(isFloating, U)
    )
    {
        write_styled_value(
            writer,
            value,
            options.color_scheme.number_value,
            options,
        );
    }
    else static if (is(U == Element[], Element))
    {
        write_slice(writer, value, options, context);
    }
    else static if (is(U == Element[N], Element, usize N))
    {
        static if (
            is(Element == char)
            || is(Element == const(char))
            || is(Element == immutable(char))
        )
        {
            write_string(writer, cast(String) value[], options);
        }
        else
        {
            write_indexable_sequence(writer, value, N, options, context);
        }
    }
    else static if (is(U == Pointee*, Pointee))
    {
        write_pointer!(T, Pointee)(writer, value, options, context);
    }
    else
    {
        write_default_aggregate_or_unsupported(writer, value, options, context);
    }
}

private enum has_pretty_format_to(T) = __traits(compiles,
{
    const(Unqualified!T)* value;
    Writer* writer;
    const(PrettyPrintOptions)* options;
    (*value).pretty_format_to(*writer, *options);
});

private void write_default_aggregate_or_unsupported(T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;
    static if (is(U == struct))
    {
        write_struct(writer, value, options, context);
    }
    else static if (is(U == union))
    {
        write_union(writer, value, options, context);
    }
    else
    {
        write_unsupported!U(writer, options);
    }
}

private void write_semantic_sequence(Display, T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (options.show_type_names)
    {
        write_type_name!Display(writer, options);
        writer.put(' ');
    }
    write_indexable_sequence(writer, value, value.length, options, context);
}

private void write_slice(T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    write_indexable_sequence(writer, value, value.length, options, context);
}

private void write_indexable_sequence(T)(
    ref Writer writer,
    scope const ref T value,
    usize length,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (length == 0)
    {
        write_punctuation(writer, "[]", options);
        return;
    }
    if (depth_limit_reached(context.recursion_depth, options))
    {
        write_depth_limit(writer, options);
        return;
    }

    const compact = choose_compact(value, options, context);
    const shown = limited_item_count(length, options.max_items);
    const truncated = shown < length;
    PrettyPrintContext child_context = descend_aggregate(context);

    write_punctuation(writer, '[', options);
    if (!compact) writer.put('\n');

    foreach (index; 0 .. shown)
    {
        if (compact)
        {
            if (index != 0) write_punctuation(writer, ", ", options);
        }
        else
        {
            write_indent(writer, child_context.indentation_depth, options);
        }

        write_pretty_impl(writer, value[index], options, child_context);

        if (!compact)
        {
            if (index + 1 < shown || truncated) write_punctuation(writer, ',', options);
            writer.put('\n');
        }
    }

    if (truncated)
    {
        if (compact)
        {
            if (shown != 0) write_punctuation(writer, ", ", options);
        }
        else
        {
            write_indent(writer, child_context.indentation_depth, options);
        }
        write_truncation(writer, length - shown, options);
        if (!compact) writer.put('\n');
    }

    if (!compact) write_indent(writer, context.indentation_depth, options);
    write_punctuation(writer, ']', options);
}

private void write_flag_set(Display, T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;
    alias Flag = U.FlagType;

    if (options.show_type_names)
    {
        write_type_name!Display(writer, options);
        writer.put(' ');
    }

    const length = value.enabled_count;
    if (length == 0)
    {
        write_punctuation(writer, "{}", options);
        return;
    }

    const compact = choose_compact(value, options, context);
    const shown = limited_item_count(length, options.max_items);
    const truncated = shown < length;
    PrettyPrintContext item_context = descend_indentation(context);
    usize written;

    write_punctuation(writer, '{', options);
    if (!compact) writer.put('\n');

    static foreach (name; __traits(allMembers, Flag))
    {{
        enum flag = __traits(getMember, Flag, name);
        if (value.contains(flag) && written < shown)
        {
            if (compact)
            {
                if (written != 0) write_punctuation(writer, ", ", options);
            }
            else
            {
                write_indent(writer, item_context.indentation_depth, options);
            }

            write_styled_text(
                writer,
                name,
                options.color_scheme.enum_value,
                options,
            );

            ++written;
            if (!compact)
            {
                if (written < shown || truncated) write_punctuation(writer, ',', options);
                writer.put('\n');
            }
        }
    }}

    if (truncated)
    {
        if (compact)
        {
            if (shown != 0) write_punctuation(writer, ", ", options);
        }
        else
        {
            write_indent(writer, item_context.indentation_depth, options);
        }
        write_truncation(writer, length - shown, options);
        if (!compact) writer.put('\n');
    }

    if (!compact) write_indent(writer, context.indentation_depth, options);
    write_punctuation(writer, '}', options);
}

private void write_hash_map(Display, T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (options.show_type_names)
    {
        write_type_name!Display(writer, options);
        writer.put(' ');
    }

    if (value.length == 0)
    {
        write_punctuation(writer, "{}", options);
        return;
    }
    if (depth_limit_reached(context.recursion_depth, options))
    {
        write_depth_limit(writer, options);
        return;
    }

    const compact = choose_compact(value, options, context);
    const shown = limited_item_count(value.length, options.max_items);
    const truncated = shown < value.length;
    PrettyPrintContext child_context = descend_aggregate(context);
    usize index;
    auto cursor = value.cursor();

    write_punctuation(writer, '{', options);
    if (!compact) writer.put('\n');

    while (cursor.valid && index < shown)
    {
        if (compact)
        {
            if (index != 0) write_punctuation(writer, ", ", options);
        }
        else
        {
            write_indent(writer, child_context.indentation_depth, options);
        }

        write_pretty_impl(writer, *cursor.key, options, child_context);
        write_punctuation(writer, ": ", options);
        write_pretty_impl(writer, *cursor.value, options, child_context);

        ++index;
        cursor.advance();
        if (!compact)
        {
            if (index < shown || truncated) write_punctuation(writer, ',', options);
            writer.put('\n');
        }
    }

    if (truncated)
    {
        if (compact)
        {
            if (shown != 0) write_punctuation(writer, ", ", options);
        }
        else
        {
            write_indent(writer, child_context.indentation_depth, options);
        }
        write_truncation(writer, value.length - shown, options);
        if (!compact) writer.put('\n');
    }

    if (!compact) write_indent(writer, context.indentation_depth, options);
    write_punctuation(writer, '}', options);
}

private void write_hash_set(Display, T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (options.show_type_names)
    {
        write_type_name!Display(writer, options);
        writer.put(' ');
    }

    if (value.length == 0)
    {
        write_punctuation(writer, "{}", options);
        return;
    }
    if (depth_limit_reached(context.recursion_depth, options))
    {
        write_depth_limit(writer, options);
        return;
    }

    const compact = choose_compact(value, options, context);
    const shown = limited_item_count(value.length, options.max_items);
    const truncated = shown < value.length;
    PrettyPrintContext child_context = descend_aggregate(context);
    usize index;
    auto cursor = value.cursor();

    write_punctuation(writer, '{', options);
    if (!compact) writer.put('\n');

    while (cursor.valid && index < shown)
    {
        if (compact)
        {
            if (index != 0) write_punctuation(writer, ", ", options);
        }
        else
        {
            write_indent(writer, child_context.indentation_depth, options);
        }

        write_pretty_impl(writer, *cursor.value, options, child_context);

        ++index;
        cursor.advance();
        if (!compact)
        {
            if (index < shown || truncated) write_punctuation(writer, ',', options);
            writer.put('\n');
        }
    }

    if (truncated)
    {
        if (compact)
        {
            if (shown != 0) write_punctuation(writer, ", ", options);
        }
        else
        {
            write_indent(writer, child_context.indentation_depth, options);
        }
        write_truncation(writer, value.length - shown, options);
        if (!compact) writer.put('\n');
    }

    if (!compact) write_indent(writer, context.indentation_depth, options);
    write_punctuation(writer, '}', options);
}

private template has_named_struct_field(T, usize index)
{
    alias U = Unqualified!T;
    enum name = __traits(identifier, U.tupleof[index]);
    enum has_named_struct_field = name.length != 0
        && __traits(compiles, __traits(getMember, U, name));
}

private usize count_named_fields(T)() pure @safe
{
    usize result;
    static foreach (index; 0 .. T.tupleof.length)
    {
        // A `static foreach` body shares its declaration scope across
        // iterations unless an explicit nested scope is introduced. Avoid a
        // per-iteration named enum here so structs with multiple fields do not
        // redeclare the same symbol.
        static if (has_named_struct_field!(T, index))
            ++result;
    }
    return result;
}

private void write_struct(T)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;
    enum field_count = count_named_fields!U();

    // Empty structs are terminal values. Printing them never descends further,
    // so a depth limit should not hide their complete representation.
    if (field_count == 0)
    {
        if (options.show_type_names)
        {
            write_type_name!U(writer, options);
            writer.put(' ');
        }
        write_punctuation(writer, "{}", options);
        return;
    }

    if (depth_limit_reached(context.recursion_depth, options))
    {
        write_depth_limit(writer, options);
        return;
    }

    if (options.show_type_names)
    {
        write_type_name!U(writer, options);
        writer.put(' ');
    }

    const shown = limited_item_count(field_count, options.max_items);
    const truncated = shown < field_count;
    const compact = choose_compact(value, options, context);
    PrettyPrintContext child_context = descend_aggregate(context);
    write_punctuation(writer, '{', options);
    if (!compact) writer.put('\n');

    usize visited_fields;
    usize written_fields;
    static foreach (index; 0 .. U.tupleof.length)
    {{
        enum name = __traits(identifier, U.tupleof[index]);
        static if (has_named_struct_field!(U, index))
        {
            if (visited_fields < shown)
            {
                if (compact)
                {
                    if (written_fields != 0) write_punctuation(writer, ", ", options);
                }
                else
                {
                    write_indent(writer, child_context.indentation_depth, options);
                }

                write_styled_text(
                    writer,
                    name,
                    options.color_scheme.field_name,
                    options,
                );
                write_punctuation(writer, ": ", options);
                static if (is_tagged_payload_field!(U, index))
                {
                    write_tagged_payload!(U, index)(
                        writer,
                        value,
                        options,
                        child_context,
                    );
                }
                else
                {
                    write_pretty_impl(
                        writer,
                        value.tupleof[index],
                        options,
                        child_context,
                    );
                }

                ++written_fields;
                if (!compact)
                {
                    if (written_fields < shown || truncated)
                    {
                        write_punctuation(writer, ',', options);
                    }
                    writer.put('\n');
                }
            }
            ++visited_fields;
        }
    }}

    if (truncated)
    {
        if (compact)
        {
            if (written_fields != 0) write_punctuation(writer, ", ", options);
        }
        else
        {
            write_indent(writer, child_context.indentation_depth, options);
        }
        write_truncation(writer, field_count - shown, options);
        if (!compact) writer.put('\n');
    }

    if (!compact) write_indent(writer, context.indentation_depth, options);
    write_punctuation(writer, '}', options);
}

private void write_tagged_payload(T, usize payload_index)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    alias U = Unqualified!T;
    enum metadata = tagged_payload_metadata!(U, payload_index)();
    alias Tag = Unqualified!(typeof(metadata.inactive));
    alias Payload = Unqualified!(typeof(U.tupleof[payload_index]));
    enum discriminator_index = tagged_payload_discriminator_index!(U, payload_index)();
    const active = value.tupleof[discriminator_index];

    if (active == metadata.inactive)
    {
        if (options.show_type_names)
        {
            write_type_name!Payload(writer, options);
            writer.put(' ');
        }
        write_punctuation(writer, "{}", options);
        return;
    }

    if (depth_limit_reached(context.recursion_depth, options))
    {
        write_depth_limit(writer, options);
        return;
    }

    if (options.show_type_names)
    {
        write_type_name!Payload(writer, options);
        writer.put(' ');
    }

    static foreach (member_index; 0 .. Payload.tupleof.length)
    {{
        enum mapped_tag = tagged_payload_member_tag!(
            Payload,
            member_index,
            Tag,
        )();
        if (active == mapped_tag)
        {
            if (options.max_items == 0)
            {
                write_punctuation(writer, '{', options);
                write_truncation(writer, 1, options);
                write_punctuation(writer, '}', options);
                return;
            }

            const compact = choose_tagged_payload_compact!(U, payload_index)(
                value,
                options,
                context,
            );
            PrettyPrintContext child_context = descend_aggregate(context);
            enum name = __traits(identifier, Payload.tupleof[member_index]);

            write_punctuation(writer, '{', options);
            if (!compact)
            {
                writer.put('\n');
                write_indent(
                    writer,
                    child_context.indentation_depth,
                    options,
                );
            }

            write_styled_text(
                writer,
                name,
                options.color_scheme.field_name,
                options,
            );
            write_punctuation(writer, ": ", options);
            write_pretty_impl(
                writer,
                value.tupleof[payload_index].tupleof[member_index],
                options,
                child_context,
            );

            if (!compact)
            {
                writer.put('\n');
                write_indent(writer, context.indentation_depth, options);
            }
            write_punctuation(writer, '}', options);
            return;
        }
    }}

    write_styled_text(
        writer,
        "<invalid tagged union discriminator>",
        options.color_scheme.unsupported,
        options,
    );
}

private bool choose_tagged_payload_compact(T, usize payload_index)(
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

    if (options.soft_max_width == 0) return false;
    const indentation = cast(usize) context.indentation_depth * options.indent_size;
    if (indentation >= options.soft_max_width) return false;
    const available = cast(usize) options.soft_max_width - indentation;
    const estimate = estimate_tagged_payload!(T, payload_index)(
        value,
        options,
        context.recursion_depth,
        available,
    );
    return estimate.known && estimate.width <= available;
}

private void write_union(T)(
    ref Writer writer,
    scope const ref T,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext,
)
{
    alias U = Unqualified!T;
    if (options.show_type_names)
    {
        write_type_name!U(writer, options);
        writer.put(' ');
    }
    write_styled_text(
        writer,
        "<union: active member unknown>",
        options.color_scheme.unsupported,
        options,
    );
}

private void write_pointer(T, Pointee)(
    ref Writer writer,
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    PrettyPrintContext context,
)
{
    if (value is null)
    {
        write_styled_text(
            writer,
            "null",
            options.color_scheme.null_value,
            options,
        );
        return;
    }

    // Borrowed values are observed through a transitive const view, so a
    // wrapped `void*` reaches this function as `const(void)*`.
    static if (!is(Pointee == function))
    {
        static if (!is_void_pointee!Pointee)
        {
            if (options.dereference_pointers)
            {
                write_styled_text(
                    writer,
                    "&",
                    options.color_scheme.pointer_value,
                    options,
                );
                if (depth_limit_reached(context.recursion_depth, options))
                {
                    write_depth_limit(writer, options);
                }
                else
                {
                    // Like `some(`, `&` is a same-line wrapper around one value.
                    PrettyPrintContext child_context = descend_wrapper(context);
                    write_pretty_impl(writer, *value, options, child_context);
                }
                return;
            }
        }
    }

    if (options.show_type_names)
    {
        write_type_name!(Unqualified!T)(writer, options);
        writer.put(' ');
    }
    write_styled_text(
        writer,
        "@",
        options.color_scheme.pointer_value,
        options,
    );
    write_styled_value(
        writer,
        cast(const(void)*) value,
        options.color_scheme.pointer_value,
        options,
    );
}

private void write_enum(T)(
    ref Writer writer,
    T value,
    scope const ref PrettyPrintOptions options,
)
{
    alias U = Unqualified!T;
    String matched_name;
    static foreach (member; __traits(allMembers, U))
    {{
        static if (__traits(compiles, __traits(getMember, U, member)))
        {
            alias M = typeof(__traits(getMember, U, member));
            static if (is(Unqualified!M == U))
            {
                if (matched_name.length == 0
                    && value == __traits(getMember, U, member))
                {
                    matched_name = member;
                }
            }
        }
    }}

    if (options.show_type_names) write_type_name!U(writer, options);

    if (matched_name.length != 0)
    {
        if (options.show_type_names) write_punctuation(writer, '.', options);
        write_styled_text(
            writer,
            matched_name,
            options.color_scheme.enum_value,
            options,
        );
        return;
    }

    static if (U.sizeof <= u64.sizeof)
    {
        if (options.show_type_names) write_punctuation(writer, '(', options);
        static if (__traits(isUnsigned, U))
        {
            write_styled_value(
                writer,
                cast(u64) value,
                options.color_scheme.number_value,
                options,
            );
        }
        else
        {
            write_styled_value(
                writer,
                cast(i64) value,
                options.color_scheme.number_value,
                options,
            );
        }
        if (options.show_type_names) write_punctuation(writer, ')', options);
    }
    else
    {
        if (options.show_type_names) writer.put(' ');
        write_styled_text(
            writer,
            "<invalid enum value>",
            options.color_scheme.unsupported,
            options,
        );
    }
}

private void write_string(
    ref Writer writer,
    scope String value,
    scope const ref PrettyPrintOptions options,
)
{
    const style = options.color_scheme.string_value;
    begin_style(writer, style, options);
    writer.put('"');

    usize run_start;
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
            if (cast(u8) character < 0x20 || character == 0x7F)
            {
                if (run_start < index) writer.put(value[run_start .. index]);
                write_hex_byte(writer, cast(u8) character);
                run_start = index + 1;
            }
            continue;
        }

        if (run_start < index) writer.put(value[run_start .. index]);
        writer.put(escape);
        run_start = index + 1;
    }

    if (run_start < value.length) writer.put(value[run_start .. $]);
    writer.put('"');
    end_style(writer, style, options);
}

private void write_character(T)(
    ref Writer writer,
    T value,
    scope const ref PrettyPrintOptions options,
)
{
    const style = options.color_scheme.character_value;
    begin_style(writer, style, options);
    writer.put('\'');

    const code_point = cast(dchar) value;
    switch (code_point)
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
            if (cast(u8) value >= 0x80 || !is_printable_scalar(code_point))
            {
                write_escaped_code_point(writer, cast(u8) value);
            }
            else
            {
                writer.put(value);
            }
        }
        else
        {
            if (!is_printable_scalar(code_point))
            {
                write_escaped_code_point(writer, cast(u32) code_point);
            }
            else
            {
                writer.value(code_point);
            }
        }
        break;
    }

    writer.put('\'');
    end_style(writer, style, options);
}

private bool is_printable_scalar(dchar value) pure @safe
{
    const code_point = cast(u32) value;
    return code_point >= 0x20
        && code_point != 0x7F
        && !(code_point >= 0xD800 && code_point <= 0xDFFF)
        && code_point <= 0x10FFFF;
}

private void write_escaped_code_point(ref Writer writer, u32 value)
{
    if (value <= u8.max)
    {
        writer.put("\\x");
        write_hex_digits(writer, value, 2);
    }
    else if (value <= u16.max)
    {
        writer.put("\\u");
        write_hex_digits(writer, value, 4);
    }
    else
    {
        writer.put("\\U");
        write_hex_digits(writer, value, 8);
    }
}

private void write_hex_digits(ref Writer writer, u32 value, u8 count)
{
    enum String digits = "0123456789abcdef";
    while (count != 0)
    {
        --count;
        const shift = cast(u32) count * 4;
        writer.put(digits[(value >> shift) & 0x0F]);
    }
}

private void write_hex_byte(ref Writer writer, u8 value)
{
    writer.put("\\x");
    write_hex_digits(writer, value, 2);
}

private void write_truncation(
    ref Writer writer,
    usize remaining,
    scope const ref PrettyPrintOptions options,
)
{
    const style = options.color_scheme.truncation;
    begin_style(writer, style, options);
    writer.put("... (");
    writer.value(remaining);
    writer.put(" more)");
    end_style(writer, style, options);
}

private void write_depth_limit(
    ref Writer writer,
    scope const ref PrettyPrintOptions options,
)
{
    write_styled_text(
        writer,
        "...",
        options.color_scheme.depth_limit,
        options,
    );
}

private void write_unsupported(T)(
    ref Writer writer,
    scope const ref PrettyPrintOptions options,
)
{
    if (options.show_type_names)
    {
        write_type_name!T(writer, options);
        writer.put(' ');
    }
    write_styled_text(
        writer,
        "<unsupported>",
        options.color_scheme.unsupported,
        options,
    );
}

private void write_type_name(T)(
    ref Writer writer,
    scope const ref PrettyPrintOptions options,
)
{
    alias U = Unqualified!T;
    write_styled_text(
        writer,
        U.stringof,
        options.color_scheme.type_name,
        options,
    );
}

private void write_punctuation(
    ref Writer writer,
    char value,
    scope const ref PrettyPrintOptions options,
)
{
    write_styled_character(
        writer,
        value,
        options.color_scheme.punctuation,
        options,
    );
}

private void write_punctuation(
    ref Writer writer,
    scope String value,
    scope const ref PrettyPrintOptions options,
)
{
    write_styled_text(
        writer,
        value,
        options.color_scheme.punctuation,
        options,
    );
}

private void write_styled_text(
    ref Writer writer,
    scope String value,
    ANSIStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    begin_style(writer, style, options);
    writer.put(value);
    end_style(writer, style, options);
}

private void write_styled_character(
    ref Writer writer,
    char value,
    ANSIStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    begin_style(writer, style, options);
    writer.put(value);
    end_style(writer, style, options);
}

private void write_styled_value(T)(
    ref Writer writer,
    T value,
    ANSIStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    begin_style(writer, style, options);
    writer.value(value);
    end_style(writer, style, options);
}

private void begin_style(
    ref Writer writer,
    ANSIStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    if (options.colored && style.enabled) writer.begin_ansi(style);
}

private void end_style(
    ref Writer writer,
    ANSIStyle style,
    scope const ref PrettyPrintOptions options,
)
{
    if (options.colored && style.enabled) writer.end_ansi(style);
}

private void write_indent(
    ref Writer writer,
    u16 depth,
    scope const ref PrettyPrintOptions options,
)
{
    const count = cast(usize) depth * options.indent_size;
    writer.repeat(' ', count);
}

private bool depth_limit_reached(
    u16 depth,
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    return depth == u16.max || depth > options.max_depth;
}

private u16 next_depth(u16 depth) pure @safe
{
    return depth == u16.max ? u16.max : cast(u16)(depth + 1);
}

private PrettyPrintContext descend_aggregate(PrettyPrintContext context) pure @safe
{
    context.recursion_depth = next_depth(context.recursion_depth);
    context.indentation_depth = next_depth(context.indentation_depth);
    return context;
}

private PrettyPrintContext descend_wrapper(PrettyPrintContext context) pure @safe
{
    context.recursion_depth = next_depth(context.recursion_depth);
    return context;
}

private PrettyPrintContext descend_indentation(PrettyPrintContext context) pure @safe
{
    context.indentation_depth = next_depth(context.indentation_depth);
    return context;
}

private usize limited_item_count(usize length, u32 max_items) pure @safe
{
    return length < max_items ? length : max_items;
}

private usize decimal_digits(u64 value) pure @safe
{
    usize result = 1;
    while (value >= 10)
    {
        value /= 10;
        ++result;
    }
    return result;
}

private usize integer_width(T)(T value) pure @safe
{
    static assert(__traits(isIntegral, T) && T.sizeof <= u64.sizeof);
    static if (__traits(isUnsigned, T))
    {
        return decimal_digits(cast(u64) value);
    }
    else
    {
        const signed_value = cast(i64) value;
        const bits = cast(u64) signed_value;
        const magnitude = signed_value < 0 ? 0UL - bits : bits;
        return decimal_digits(magnitude) + (signed_value < 0 ? 1 : 0);
    }
}

private usize truncation_width(usize remaining) pure @safe
{
    // "... (" + decimal digits + " more)"
    return 11 + decimal_digits(cast(u64) remaining);
}

private bool choose_compact(T)(
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

    if (options.soft_max_width == 0) return false;
    const indentation = cast(usize) context.indentation_depth * options.indent_size;
    if (indentation >= options.soft_max_width) return false;
    const available = cast(usize) options.soft_max_width - indentation;
    const estimate = estimate_width(
        value,
        options,
        context.recursion_depth,
        available,
    );
    return estimate.known && estimate.width <= available;
}

private struct WidthEstimate
{
    bool known;
    usize width;
}

private WidthEstimate known_width(usize width) pure @safe
{
    return WidthEstimate(true, width);
}

private WidthEstimate unknown_width() pure @safe
{
    return WidthEstimate.init;
}

private bool add_width(usize* total, usize addition, usize budget) pure @safe
{
    if (addition > usize.max - *total) return false;
    *total += addition;
    return *total <= budget;
}

private WidthEstimate estimate_width(T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    u16 depth,
    usize budget,
)
{
    alias U = Unqualified!T;

    enum has_conflicting_hooks = has_pretty_describe!T && has_pretty_format_to_member!T;
    static assert(
        !has_conflicting_hooks,
        U.stringof ~ " defines both pretty_describe and pretty_format_to",
    );

    static if (has_pretty_describe!T)
    {
        PrettyMeasure!U pretty = PrettyMeasure!U(
            &options,
            PrettyPrintContext(depth, 0),
            budget,
        );
        alias DescribeReturn = typeof(value.pretty_describe(pretty));
        static assert(
            is(DescribeReturn == void),
            U.stringof ~ ".pretty_describe(...) must return void",
        );
        value.pretty_describe(pretty);
        return pretty.result;
    }
    else static if (has_pretty_format_to!T)
    {
        return unknown_width();
    }
    else static if (is(U == typeof(null)))
    {
        return known_width(4);
    }
    else static if (is_string_type!U)
    {
        return estimate_escaped_string(cast(String) value, budget);
    }
    else static if (is(U == bool))
    {
        return known_width(value ? 4 : 5);
    }
    else static if (is_character_type!U)
    {
        return known_width(estimate_character_width(value));
    }
    else static if (is(U == enum))
    {
        return estimate_enum_width(value, options);
    }
    else static if (__traits(isIntegral, U) && U.sizeof <= u64.sizeof)
    {
        return known_width(integer_width(value));
    }
    else static if (__traits(isFloating, U))
    {
        return known_width(U.sizeof * 8 + 16);
    }
    else static if (is(U == Element[], Element))
    {
        return estimate_indexable(value, value.length, options, depth, budget);
    }
    else static if (is(U == Element[N], Element, usize N))
    {
        static if (
            is(Element == char)
            || is(Element == const(char))
            || is(Element == immutable(char))
        )
        {
            return estimate_escaped_string(cast(String) value[], budget);
        }
        else
        {
            return estimate_indexable(value, N, options, depth, budget);
        }
    }
    else static if (is(U == Pointee*, Pointee))
    {
        if (value is null) return known_width(4);

        static if (is(Pointee == function))
        {
            return estimate_pointer_address_width!U(options);
        }
        else static if (is_void_pointee!Pointee)
        {
            return estimate_pointer_address_width!U(options);
        }
        else
        {
            if (!options.dereference_pointers)
                return estimate_pointer_address_width!U(options);

            if (depth_limit_reached(depth, options)) return known_width(4);

            const child = estimate_width(*value, options, next_depth(depth), budget);
            return child.known && child.width < usize.max
                ? known_width(child.width + 1)
                : unknown_width();
        }
    }
    else
    {
        return estimate_default_aggregate(value, options, depth, budget);
    }
}

private WidthEstimate estimate_pointer_address_width(T)(
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    // `@` + the `0x` prefix + two hexadecimal digits per address byte.
    const type_prefix = options.show_type_names ? T.stringof.length + 1 : 0;
    return known_width(type_prefix + 3 + usize.sizeof * 2);
}

private WidthEstimate estimate_default_aggregate(T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    u16 depth,
    usize budget,
)
{
    alias U = Unqualified!T;
    static if (is(U == struct))
    {
        return estimate_struct(value, options, depth, budget);
    }
    else static if (is(U == union))
    {
        return known_width((options.show_type_names ? U.stringof.length + 1 : 0) + 30);
    }
    else
    {
        return unknown_width();
    }
}

private usize estimate_character_width(T)(T value) pure @safe
{
    const code_point = cast(dchar) value;
    const escaped = code_point == '\''
        || code_point == '\\'
        || code_point == '\n'
        || code_point == '\r'
        || code_point == '\t'
        || code_point == '\0';
    if (escaped) return 4;

    static if (is(Unqualified!T == char))
    {
        if (cast(u8) value >= 0x80 || !is_printable_scalar(code_point)) return 6;
        return 3;
    }
    else
    {
        if (!is_printable_scalar(code_point))
        {
            const numeric = cast(u32) code_point;
            if (numeric <= u8.max) return 6;
            if (numeric <= u16.max) return 8;
            return 12;
        }

        const numeric = cast(u32) code_point;
        if (numeric <= 0x7F) return 3;
        if (numeric <= 0x7FF) return 4;
        if (numeric <= 0xFFFF) return 5;
        return 6;
    }
}

private WidthEstimate estimate_enum_width(T)(
    T value,
    scope const ref PrettyPrintOptions options,
)
pure @safe
{
    alias U = Unqualified!T;
    usize member_width;
    static foreach (member; __traits(allMembers, U))
    {{
        static if (__traits(compiles, __traits(getMember, U, member)))
        {
            alias M = typeof(__traits(getMember, U, member));
            static if (is(Unqualified!M == U))
            {
                if (member_width == 0
                    && value == __traits(getMember, U, member))
                {
                    member_width = member.length;
                }
            }
        }
    }}

    const type_prefix = options.show_type_names ? U.stringof.length + 1 : 0;
    if (member_width != 0) return known_width(type_prefix + member_width);

    static if (U.sizeof <= u64.sizeof)
    {
        const numeric_prefix = options.show_type_names ? U.stringof.length + 2 : 0;
        return known_width(numeric_prefix + integer_width(value));
    }
    else
    {
        return known_width(type_prefix + "<invalid enum value>".length);
    }
}

private WidthEstimate estimate_escaped_string(scope String value, usize budget) pure @safe
{
    usize total = 2;
    if (total > budget) return unknown_width();
    foreach (character; value)
    {
        usize addition = 1;
        const escaped = character == '"'
            || character == '\\'
            || character == '\n'
            || character == '\r'
            || character == '\t'
            || character == '\0';
        if (escaped)
        {
            addition = 2;
        }
        else if (cast(u8) character < 0x20 || character == 0x7F)
        {
            addition = 4;
        }
        if (!add_width(&total, addition, budget)) return unknown_width();
    }
    return known_width(total);
}

private WidthEstimate estimate_indexable(T)(
    scope const ref T value,
    usize length,
    scope const ref PrettyPrintOptions options,
    u16 depth,
    usize budget,
)
{
    if (length == 0) return known_width(2);
    if (depth_limit_reached(depth, options)) return known_width(3);

    usize total = 2;
    const shown = limited_item_count(length, options.max_items);
    foreach (index; 0 .. shown)
    {
        if (index != 0 && !add_width(&total, 2, budget)) return unknown_width();
        const child = estimate_width(
            value[index],
            options,
            next_depth(depth),
            budget > total ? budget - total : 0,
        );
        if (!child.known || !add_width(&total, child.width, budget)) return unknown_width();
    }
    if (shown < length)
    {
        if (shown != 0 && !add_width(&total, 2, budget)) return unknown_width();
        if (!add_width(&total, truncation_width(length - shown), budget)) return unknown_width();
    }
    return known_width(total);
}

private WidthEstimate estimate_semantic_sequence(Display, T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    u16 depth,
    usize budget,
)
{
    usize prefix = options.show_type_names ? Display.stringof.length + 1 : 0;
    const child = estimate_indexable(
        value,
        value.length,
        options,
        depth,
        budget >= prefix ? budget - prefix : 0,
    );
    if (!child.known || !add_width(&prefix, child.width, budget)) return unknown_width();
    return known_width(prefix);
}

private WidthEstimate estimate_flag_set(Display, T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    usize budget,
)
{
    alias U = Unqualified!T;
    alias Flag = U.FlagType;

    usize total = options.show_type_names ? Display.stringof.length + 1 : 0;
    if (!add_width(&total, 2, budget)) return unknown_width();

    const length = value.enabled_count;
    const shown = limited_item_count(length, options.max_items);
    usize written;
    static foreach (name; __traits(allMembers, Flag))
    {{
        enum flag = __traits(getMember, Flag, name);
        if (value.contains(flag) && written < shown)
        {
            if (written != 0 && !add_width(&total, 2, budget)) return unknown_width();
            if (!add_width(&total, name.length, budget)) return unknown_width();
            ++written;
        }
    }}

    if (shown < length)
    {
        if (shown != 0 && !add_width(&total, 2, budget)) return unknown_width();
        if (!add_width(&total, truncation_width(length - shown), budget)) return unknown_width();
    }
    return known_width(total);
}

private WidthEstimate estimate_hash_map(Display, T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    u16 depth,
    usize budget,
)
{
    usize total = options.show_type_names ? Display.stringof.length + 1 : 0;
    if (value.length == 0)
    {
        return add_width(&total, 2, budget) ? known_width(total) : unknown_width();
    }
    if (depth_limit_reached(depth, options))
    {
        return add_width(&total, 3, budget) ? known_width(total) : unknown_width();
    }

    if (!add_width(&total, 2, budget)) return unknown_width();

    const shown = limited_item_count(value.length, options.max_items);
    usize index;
    auto cursor = value.cursor();
    while (cursor.valid && index < shown)
    {
        if (index != 0 && !add_width(&total, 2, budget)) return unknown_width();
        const key = estimate_width(
            *cursor.key,
            options,
            next_depth(depth),
            budget > total ? budget - total : 0,
        );
        if (!key.known
            || !add_width(&total, key.width, budget)
            || !add_width(&total, 2, budget))
        {
            return unknown_width();
        }
        const mapped = estimate_width(
            *cursor.value,
            options,
            next_depth(depth),
            budget > total ? budget - total : 0,
        );
        if (!mapped.known || !add_width(&total, mapped.width, budget)) return unknown_width();
        ++index;
        cursor.advance();
    }
    if (shown < value.length)
    {
        if (shown != 0 && !add_width(&total, 2, budget)) return unknown_width();
        if (!add_width(&total, truncation_width(value.length - shown), budget))
            return unknown_width();
    }
    return known_width(total);
}

private WidthEstimate estimate_hash_set(Display, T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    u16 depth,
    usize budget,
)
{
    usize total = options.show_type_names ? Display.stringof.length + 1 : 0;
    if (value.length == 0)
    {
        return add_width(&total, 2, budget) ? known_width(total) : unknown_width();
    }
    if (depth_limit_reached(depth, options))
    {
        return add_width(&total, 3, budget) ? known_width(total) : unknown_width();
    }

    if (!add_width(&total, 2, budget)) return unknown_width();

    const shown = limited_item_count(value.length, options.max_items);
    usize index;
    auto cursor = value.cursor();
    while (cursor.valid && index < shown)
    {
        if (index != 0 && !add_width(&total, 2, budget)) return unknown_width();
        const child = estimate_width(
            *cursor.value,
            options,
            next_depth(depth),
            budget > total ? budget - total : 0,
        );
        if (!child.known || !add_width(&total, child.width, budget)) return unknown_width();
        ++index;
        cursor.advance();
    }
    if (shown < value.length)
    {
        if (shown != 0 && !add_width(&total, 2, budget)) return unknown_width();
        if (!add_width(&total, truncation_width(value.length - shown), budget))
            return unknown_width();
    }
    return known_width(total);
}

private WidthEstimate estimate_tagged_payload(T, usize payload_index)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    u16 depth,
    usize budget,
)
{
    alias U = Unqualified!T;
    enum metadata = tagged_payload_metadata!(U, payload_index)();
    alias Tag = Unqualified!(typeof(metadata.inactive));
    alias Payload = Unqualified!(typeof(U.tupleof[payload_index]));
    enum discriminator_index = tagged_payload_discriminator_index!(U, payload_index)();
    const active = value.tupleof[discriminator_index];

    if (active == metadata.inactive)
    {
        usize total = options.show_type_names ? Payload.stringof.length + 1 : 0;
        return add_width(&total, 2, budget) ? known_width(total) : unknown_width();
    }
    if (depth_limit_reached(depth, options)) return known_width(3);

    usize total = options.show_type_names ? Payload.stringof.length + 1 : 0;
    if (options.max_items == 0)
    {
        if (!add_width(&total, 2, budget)
            || !add_width(&total, truncation_width(1), budget))
        {
            return unknown_width();
        }

        return known_width(total);
    }

    static foreach (member_index; 0 .. Payload.tupleof.length)
    {{
        enum mapped_tag = tagged_payload_member_tag!(
            Payload,
            member_index,
            Tag,
        )();
        if (active == mapped_tag)
        {
            enum name = __traits(identifier, Payload.tupleof[member_index]);
            if (!add_width(&total, 2 + name.length + 2, budget)) return unknown_width();
            const child = estimate_width(
                value.tupleof[payload_index].tupleof[member_index],
                options,
                next_depth(depth),
                budget > total ? budget - total : 0,
            );
            if (!child.known || !add_width(&total, child.width, budget)) return unknown_width();
            return known_width(total);
        }
    }}

    return add_width(
        &total,
        "<invalid tagged union discriminator>".length,
        budget,
    )
        ? known_width(total)
        : unknown_width();
}

private WidthEstimate estimate_struct(T)(
    scope const ref T value,
    scope const ref PrettyPrintOptions options,
    u16 depth,
    usize budget,
)
{
    alias U = Unqualified!T;
    enum field_count = count_named_fields!U();
    if (field_count == 0)
    {
        usize empty_width = options.show_type_names ? U.stringof.length + 1 : 0;
        return add_width(&empty_width, 2, budget)
            ? known_width(empty_width)
            : unknown_width();
    }
    if (depth_limit_reached(depth, options)) return known_width(3);

    usize total = options.show_type_names ? U.stringof.length + 1 : 0;
    if (!add_width(&total, 2, budget)) return unknown_width();

    const shown = limited_item_count(field_count, options.max_items);
    usize visited_fields;
    usize written_fields;
    static foreach (index; 0 .. U.tupleof.length)
    {{
        enum name = __traits(identifier, U.tupleof[index]);
        static if (has_named_struct_field!(U, index))
        {
            if (visited_fields < shown)
            {
                if (written_fields != 0 && !add_width(&total, 2, budget))
                {
                    return unknown_width();
                }
                if (!add_width(&total, name.length, budget)
                    || !add_width(&total, 2, budget))
                {
                    return unknown_width();
                }

                static if (is_tagged_payload_field!(U, index))
                {
                    const child = estimate_tagged_payload!(U, index)(
                        value,
                        options,
                        next_depth(depth),
                        budget > total ? budget - total : 0,
                    );
                }
                else
                {
                    const child = estimate_width(
                        value.tupleof[index],
                        options,
                        next_depth(depth),
                        budget > total ? budget - total : 0,
                    );
                }
                if (!child.known || !add_width(&total, child.width, budget))
                {
                    return unknown_width();
                }
                ++written_fields;
            }
            ++visited_fields;
        }
    }}

    if (shown < field_count)
    {
        if (written_fields != 0 && !add_width(&total, 2, budget)) return unknown_width();
        if (!add_width(&total, truncation_width(field_count - shown), budget))
            return unknown_width();
    }
    return known_width(total);
}

version (unittest)
{
    import xtb.allocators.instrumented;
    import xtb.allocators.malloc;
    import xtb.containers.array;
    import xtb.containers.hash_map;
    import xtb.containers.hash_set;
    import xtb.containers.string_hash_map;
    import xtb.containers.string_hash_set;
    import xtb.flag_set;
    import xtb.fmt.fixed_buffer;
    import xtb.option;
    import xtb.result;
    import xtb.string;

    private enum PrettyPrintTestPermission : u8
    {
        read,
        write,
        execute,
        administer = 7,
    }

    private enum PrettyPrintTestColor : u8
    {
        red = 1,
        blue = 2,
    }

    private enum PrettyPrintTestSigned : i8
    {
        zero,
    }

    private struct PrettyPrintTestEmpty
    {
    }

    private struct PrettyPrintTestRecord
    {
        i32 id;
        String name;
    }

    private struct PrettyPrintTestMapCursor
    {
    nothrow @nogc:

        i32 current_key;
        i32 current_value;
        bool is_valid;

        @disable this();

        this(i32 key, i32 value) pure @safe
        {
            this.current_key = key;
            this.current_value = value;
            this.is_valid = true;
        }

        bool valid() const pure @safe
        {
            return this.is_valid;
        }

        const(i32)* key() const return pure @safe
        {
            return &this.current_key;
        }

        const(i32)* value() const return pure @safe
        {
            return &this.current_value;
        }

        void advance()
        {
            this.is_valid = false;
        }
    }

    private struct PrettyPrintTestMapSource
    {
    nothrow @nogc:

        i32 key;
        i32 value;

        usize length() const pure @safe
        {
            return 1;
        }

        PrettyPrintTestMapCursor cursor() const return @safe
        {
            return PrettyPrintTestMapCursor(this.key, this.value);
        }

        void pretty_describe(Pretty)(scope ref Pretty pretty) const
        {
            pretty.map(this);
        }
    }

    private struct PrettyPrintTestSetCursor
    {
    nothrow @nogc:

        i32 current_value;
        bool is_valid;

        @disable this();

        this(i32 value) pure @safe
        {
            this.current_value = value;
            this.is_valid = true;
        }

        bool valid() const pure @safe
        {
            return this.is_valid;
        }

        const(i32)* value() const return pure @safe
        {
            return &this.current_value;
        }

        void advance()
        {
            this.is_valid = false;
        }
    }

    private struct PrettyPrintTestSetSource
    {
    nothrow @nogc:

        i32 value;

        usize length() const pure @safe
        {
            return 1;
        }

        PrettyPrintTestSetCursor cursor() const return @safe
        {
            return PrettyPrintTestSetCursor(this.value);
        }

        void pretty_describe(Pretty)(scope ref Pretty pretty) const
        {
            pretty.set(this);
        }
    }

    private struct PrettyPrintTestOuter
    {
        PrettyPrintTestRecord inner;
        i32 tail;
    }

    private struct PrettyPrintTestOptionalHolder
    {
        Option!PrettyPrintTestRecord item;
        i32 tail;
    }

    private struct PrettyPrintTestPointerHolder
    {
        PrettyPrintTestRecord* item;
        i32 tail;
    }

    private struct PrettyPrintTestStaticArrayHolder
    {
        i32[4] values;
    }

    private struct PrettyPrintTestEmptyHolder
    {
        PrettyPrintTestEmpty empty;
    }

    private struct PrettyPrintTestNode
    {
        i32 value;
        PrettyPrintTestNode* next;
    }

    private struct PrettyPrintTestManyFields
    {
        i32 first;
        i32 second;
        i32 third;
    }

    private struct PrettyPrintTestEnumHolder
    {
        PrettyPrintTestSigned value;
    }

    private struct PrettyPrintTestMoveOnly
    {
        i32 value;

        @disable this(this);
    }

    private struct PrettyPrintTestBorrowedSlice
    {
        i32[] values;
    }

    private __gshared usize pretty_print_test_destructions;

    private struct PrettyPrintTestTrackedOwner
    {
    nothrow @nogc:

        i32 value;
        bool owns_value;

        @disable this(this);

        ~this()
        {
            if (this.owns_value) ++pretty_print_test_destructions;
        }
    }

    // DIP1000 must preserve the relationship between a borrowed wrapper and
    // its source. Returning a wrapper around a local would otherwise leave a
    // dangling pointer. Keep this as a compile-time regression test rather
    // than a runtime use-after-scope test.
    private enum can_escape_pretty_print_borrow = __traits(compiles,
    {
        PrettyValue!PrettyPrintTestRecord escape_pretty_print_borrow() @safe
        {
            PrettyPrintTestRecord local;
            return pretty(local);
        }
    });
    static assert(!can_escape_pretty_print_borrow);

    // `return scope` must not make pointer-free owned temporaries unusable from
    // safe code.
    private enum can_return_owned_pretty_print_value = __traits(compiles,
    {
        OwnedPrettyValue!PrettyPrintTestEnumHolder return_owned_pretty_print_value() @safe
        {
            return PrettyPrintTestEnumHolder.init.pretty;
        }
    });
    static assert(can_return_owned_pretty_print_value);

    // Owning the outer temporary is not deep ownership. The returned wrapper
    // must retain the lifetime of slices and pointers stored inside that value.
    private enum can_escape_pretty_print_contained_borrow = __traits(compiles,
    {
        OwnedPrettyValue!PrettyPrintTestBorrowedSlice escape_pretty_print_contained_borrow() @safe
        {
            i32[1] local = [1];
            return PrettyPrintTestBorrowedSlice(local[]).pretty;
        }
    });
    static assert(!can_escape_pretty_print_contained_borrow);

    private struct PrettyPrintTestConflictingSemanticOverride
    {
    nothrow @nogc:

        void pretty_describe(Pretty)(scope ref Pretty pretty) const
        {
            pretty.atom("semantic", pretty.null_role);
        }

        void pretty_format_to(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) const
        {
            writer.put("raw");
        }
    }

    private enum can_write_conflicting_semantic_override = __traits(compiles,
    {
        Writer writer;
        PrettyPrintTestConflictingSemanticOverride value;
        write_pretty(writer, value);
    });
    static assert(!can_write_conflicting_semantic_override);

    private struct PrettyPrintTestNonVoidDescribe
    {
    nothrow @nogc:

        i32 pretty_describe(Pretty)(scope ref Pretty pretty) const
        {
            pretty.atom("invalid", pretty.null_role);
            return 1;
        }
    }

    private enum can_write_non_void_describe = __traits(compiles,
    {
        Writer writer;
        PrettyPrintTestNonVoidDescribe value;
        write_pretty(writer, value);
    });
    static assert(!can_write_non_void_describe);

    private struct PrettyPrintTestNonVoidOverride
    {
    nothrow @nogc:

        i32 pretty_format_to(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) const
        {
            writer.put("invalid");
            return 1;
        }
    }

    private enum can_write_non_void_override = __traits(compiles,
    {
        Writer writer;
        PrettyPrintTestNonVoidOverride value;
        write_pretty(writer, value);
    });
    static assert(!can_write_non_void_override);

    private struct PrettyPrintTestOverride
    {
    nothrow @nogc:

        i32 ignored;

        void pretty_format_to(
            ref Writer writer,
            scope const ref PrettyPrintOptions options,
        ) const
        {
            const text = options.show_type_names
                ? "<pretty with options>"
                : "<pretty without types>";
            writer.put(text);
        }
    }

    // Unit-test instrumentation only. A const pretty hook cannot mutate state
    // reachable through its value, so use separate module storage to verify
    // that automatic layout never executes a custom hook during measurement.
    private __gshared usize pretty_print_test_hook_calls;

    private struct PrettyPrintTestCountedOverride
    {
    nothrow @nogc:

        void pretty_format_to(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) const
        {
            ++pretty_print_test_hook_calls;
            writer.put("<counted>");
        }
    }

    private struct PrettyPrintTestCountedHolder
    {
        PrettyPrintTestCountedOverride item;
        i32 tail;
    }

    private struct PrettyPrintTestMutableOnlyOverride
    {
    nothrow @nogc:

        i32 value;

        void pretty_format_to(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        )
        {
            writer.put("<mutable pretty>");
        }
    }

    private struct PrettyPrintTestBothOverrides
    {
    nothrow @nogc:

        i32 ignored;

        void pretty_format_to(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) const
        {
            writer.put("<pretty wins>");
        }

        void format_to(ref Writer writer) const
        {
            writer.put("<normal format>");
        }
    }

    private struct PrettyPrintTestFormatOverride
    {
    nothrow @nogc:

        i32 ignored;

        void format_to(ref Writer writer) const
        {
            writer.put("<format override>");
        }
    }

    private union PrettyPrintTestUnion
    {
        i32 integer;
        f64 floating;
    }

    private enum PrettyPrintTestTaggedKind : u8
    {
        none,
        integer,
        floating,
    }

    private union PrettyPrintTestTaggedPayload
    {
        i32 integer;

        @tagged_case(PrettyPrintTestTaggedKind.floating)
        i32 renamed_floating;
    }

    private struct PrettyPrintTestTaggedValue
    {
        PrettyPrintTestTaggedKind kind;

        @tagged_by("kind", PrettyPrintTestTaggedKind.none)
        PrettyPrintTestTaggedPayload payload;
    }

    private extern (C) i32 pretty_print_test_function(i32 value) nothrow @nogc
    {
        return value;
    }

    private PrettyPrintOptions plain_options() pure nothrow @nogc @safe
    {
        return PrettyPrintOptions.init.without_colors();
    }

    private PrettyPrintColorScheme disabled_color_scheme() pure nothrow @nogc @safe
    {
        PrettyPrintColorScheme result = PrettyPrintColorScheme.init;
        result.type_name = ANSIStyle.init;
        result.field_name = ANSIStyle.init;
        result.string_value = ANSIStyle.init;
        result.character_value = ANSIStyle.init;
        result.number_value = ANSIStyle.init;
        result.boolean_value = ANSIStyle.init;
        result.constructor_name = ANSIStyle.init;
        result.enum_value = ANSIStyle.init;
        result.null_value = ANSIStyle.init;
        result.pointer_value = ANSIStyle.init;
        result.punctuation = ANSIStyle.init;
        result.truncation = ANSIStyle.init;
        result.depth_limit = ANSIStyle.init;
        result.unsupported = ANSIStyle.init;
        return result;
    }

    private void expect_pretty(T)(
        auto ref T value,
        scope String expected,
        PrettyPrintOptions options = PrettyPrintOptions.init.without_colors(),
    ) nothrow @nogc
    {
        char[4096] storage;
        const result = write_buffer(storage[], pretty(value, options));
        assert(result.ok);
        assert(!result.truncated);
        assert(storage[0 .. result.written].equal(expected));
    }

    private void expect_owned_pretty(T)(
        T value,
        scope String expected,
        PrettyPrintOptions options = PrettyPrintOptions.init.without_colors(),
    ) nothrow @nogc
    {
        char[4096] storage;
        const result = write_buffer(storage[], pretty(move(value), options));
        assert(result.ok);
        assert(!result.truncated);
        assert(storage[0 .. result.written].equal(expected));
    }

    private void expect_width_estimate_covers(T)(
        auto ref T value,
        PrettyPrintOptions options = PrettyPrintOptions.init.without_colors(),
    ) nothrow @nogc
    {

        options.colored = false;
        options.layout = PrettyPrintLayout.compact;

        char[4096] storage;
        const rendered = write_buffer(storage[], pretty(value, options));
        assert(rendered.ok);
        assert(!rendered.truncated);

        const estimate = estimate_width(value, options, 0, usize.max);
        assert(estimate.known);
        // An overestimate only chooses the expanded layout conservatively. An
        // underestimate can exceed soft_max_width after choosing compact output.
        assert(estimate.width >= rendered.written);
    }
}

unittest
{
    const defaults = PrettyPrintOptions.init;
    const named_defaults = PrettyPrintOptions.defaults();
    assert(named_defaults.indent_size == defaults.indent_size);
    assert(named_defaults.max_depth == defaults.max_depth);
    assert(named_defaults.max_items == defaults.max_items);
    assert(defaults.indent_size == 2);
    assert(defaults.max_depth == 8);
    assert(defaults.max_items == 32);
    assert(defaults.soft_max_width == 80);
    assert(defaults.layout == PrettyPrintLayout.automatic);
    assert(defaults.colored);
    assert(defaults.show_type_names);
    assert(!defaults.dereference_pointers);

    const default_scheme = PrettyPrintColorScheme.defaults();
    assert(default_scheme.type_name.enabled);
    assert(default_scheme.field_name.enabled);
    assert(default_scheme.string_value.enabled);
    assert(default_scheme.character_value.enabled);
    assert(default_scheme.number_value.enabled);
    assert(default_scheme.boolean_value.enabled);
    assert(default_scheme.constructor_name.enabled);
    assert(default_scheme.boolean_value.foreground_color == ANSIColor.yellow);
    assert(
        default_scheme.constructor_name.foreground_color == ANSIColor.bright_yellow,
    );
    assert(default_scheme.enum_value.enabled);
    assert(default_scheme.null_value.enabled);
    assert(default_scheme.pointer_value.enabled);
    assert(!default_scheme.punctuation.enabled);
    assert(default_scheme.truncation.enabled);
    assert(default_scheme.depth_limit.enabled);
    assert(default_scheme.unsupported.enabled);

    const plain = defaults.without_colors();
    assert(!plain.colored);
    assert(defaults.colored);
    assert(
        defaults.with_layout(PrettyPrintLayout.expanded).layout == PrettyPrintLayout.expanded,
    );

    PrettyPrintColorScheme scheme = PrettyPrintColorScheme.init;
    scheme.number_value = ANSIStyle.foreground(ANSIColor.bright_red);
    const changed = defaults.with_color_scheme(scheme);
    assert(changed.max_depth == defaults.max_depth);
    assert(changed.colored == defaults.colored);
}

unittest
{
    PrettyPrintOptions plain = plain_options();

    i32 number = 42;
    number.expect_pretty("42", plain);
    number.expect_width_estimate_covers(plain);

    bool yes = true;
    yes.expect_pretty("true", plain);
    bool no;
    no.expect_pretty("false", plain);

    typeof(null) nothing;
    nothing.expect_pretty("null", plain);

    f32 decimal = 1.5f;
    decimal.expect_pretty("1.5", plain);
    decimal.expect_width_estimate_covers(plain);

    String text = "a\n\"b\\c\x01";
    text.expect_pretty("\"a\\n\\\"b\\\\c\\x01\"", plain);
    text.expect_width_estimate_covers(plain);

    StringBuf buffer = StringBuf.from_string(malloc_allocator(), "owned\ntext");
    buffer.expect_pretty("\"owned\\ntext\"", plain);
    buffer.expect_width_estimate_covers(plain);
    buffer.deinit();

    StringBufUnmanaged unmanaged_buffer = StringBufUnmanaged.from_string(
        malloc_allocator(),
        "owned\ntext",
    );
    unmanaged_buffer.expect_pretty("\"owned\\ntext\"", plain);
    unmanaged_buffer.expect_width_estimate_covers(plain);
    unmanaged_buffer.deinit(malloc_allocator());

    OwnedString owned_string = OwnedString.from_string(
        malloc_allocator(),
        "owned\ntext",
    );
    owned_string.expect_pretty("\"owned\\ntext\"", plain);
    owned_string.expect_width_estimate_covers(plain);
    owned_string.deinit();

    OwnedStringUnmanaged unmanaged_owned_string =
        OwnedStringUnmanaged.from_string(malloc_allocator(), "owned\ntext");
    unmanaged_owned_string.expect_pretty("\"owned\\ntext\"", plain);
    unmanaged_owned_string.expect_width_estimate_covers(plain);
    unmanaged_owned_string.deinit(malloc_allocator());

    char quote = '\'';
    quote.expect_pretty("'\\''", plain);
    char slash = '\\';
    slash.expect_pretty("'\\\\'", plain);
    char control = cast(char) 0x1F;
    control.expect_pretty("'\\x1f'", plain);
    char non_ascii_byte = cast(char) 0xE9;
    non_ascii_byte.expect_pretty("'\\xe9'", plain);
    wchar surrogate = cast(wchar) 0xD800;
    surrogate.expect_pretty("'\\ud800'", plain);
    dchar smile = cast(dchar) 0x1F642;
    smile.expect_pretty("'🙂'", plain);
}

unittest
{
    PrettyPrintOptions plain = plain_options();

    PrettyPrintTestColor color = PrettyPrintTestColor.red;
    color.expect_pretty("PrettyPrintTestColor.red", plain);
    color.expect_width_estimate_covers(plain);

    PrettyPrintOptions no_types = plain;
    no_types.show_type_names = false;
    color.expect_pretty("red", no_types);

    PrettyPrintTestColor invalid = cast(PrettyPrintTestColor) 9;
    invalid.expect_pretty("PrettyPrintTestColor(9)", plain);
    invalid.expect_pretty("9", no_types);

    PrettyPrintTestEnumHolder signed = PrettyPrintTestEnumHolder(
        cast(PrettyPrintTestSigned)-128,
    );
    PrettyPrintOptions narrow = no_types;
    narrow.soft_max_width = 12;
    signed.expect_pretty("{\n  value: -128\n}", narrow);
}

unittest
{
    PrettyPrintOptions plain = plain_options();
    PrettyPrintOptions no_types = plain;
    no_types.show_type_names = false;

    Option!i32 present = Option!i32.some(7);
    present.expect_pretty("some(7)", no_types);
    present.expect_pretty("Option!int.some(7)", plain);
    present.expect_width_estimate_covers(plain);

    Option!i32 absent;
    absent.expect_pretty("none", no_types);
    absent.expect_pretty("Option!int.none", plain);

    Result!(i32, i32) result_ok = Result!(i32, i32).ok(7);
    result_ok.expect_pretty("ok(7)", no_types);
    result_ok.expect_pretty("Result!(int, int).ok(7)", plain);
    result_ok.expect_width_estimate_covers(plain);

    Result!(i32, i32) result_err = Result!(i32, i32).err(9);
    result_err.expect_pretty("err(9)", no_types);
    result_err.expect_pretty("Result!(int, int).err(9)", plain);

    Result!(void, i32) result_void = Result!(void, i32).ok();
    result_void.expect_pretty("ok()", no_types);
    result_void.expect_pretty("Result!(void, int).ok()", plain);

    Option!PrettyPrintTestRecord nested =
        Option!PrettyPrintTestRecord.some(PrettyPrintTestRecord(1, "one"));

    // Unary wrappers increase semantic recursion without adding a second
    // visual indentation level. The payload aggregate therefore aligns with
    // the `some(` call rather than drifting one level to the right.
    PrettyPrintOptions expanded = no_types.with_layout(
        PrettyPrintLayout.expanded,
    );
    expanded.indent_size = 4;
    nested.expect_pretty(
        "some({\n" ~
            "    id: 1,\n" ~
            "    name: \"one\"\n" ~
            "})",
        expanded,
    );
    nested.expect_width_estimate_covers(no_types);

    PrettyPrintTestOptionalHolder holder = PrettyPrintTestOptionalHolder(
        nested,
        9,
    );
    holder.expect_pretty(
        "{\n" ~
            "    item: some({\n" ~
            "        id: 1,\n" ~
            "        name: \"one\"\n" ~
            "    }),\n" ~
            "    tail: 9\n" ~
            "}",
        expanded,
    );

    PrettyPrintOptions shallow = no_types.with_layout(PrettyPrintLayout.compact);
    shallow.max_depth = 0;
    nested.expect_pretty("some(...)", shallow);

    Option!PrettyPrintTestRecord[1] nested_array = [nested];
    PrettyPrintOptions automatic = no_types;
    automatic.max_depth = 0;
    automatic.soft_max_width = 10;
    nested_array.expect_pretty("[\n  some(...)\n]", automatic);
}

unittest
{
    PrettyPrintOptions plain = plain_options();
    PrettyPrintOptions no_types = plain;
    no_types.show_type_names = false;

    i32[4] fixed_values = [1, 2, 3, 4];
    fixed_values.expect_pretty("[1, 2, 3, 4]", no_types);
    fixed_values.expect_width_estimate_covers(no_types);
    fixed_values[].expect_pretty("[1, 2, 3, 4]", no_types);

    PrettyPrintTestStaticArrayHolder holder =
        PrettyPrintTestStaticArrayHolder(fixed_values);
    holder.expect_pretty("{values: [1, 2, 3, 4]}", no_types);
    holder.expect_width_estimate_covers(no_types);

    char[3] fixed_text = ['x', 't', 'b'];
    fixed_text.expect_pretty("\"xtb\"", no_types);

    i32[] empty;
    empty.expect_pretty("[]", no_types);

    PrettyPrintOptions limited = no_types.with_layout(PrettyPrintLayout.compact);
    limited.max_items = 2;
    fixed_values.expect_pretty("[1, 2, ... (2 more)]", limited);
    limited.max_items = 0;
    fixed_values.expect_pretty("[... (4 more)]", limited);

    PrettyPrintOptions expanded = no_types.with_layout(PrettyPrintLayout.expanded);
    fixed_values[0 .. 2].expect_pretty("[\n  1,\n  2\n]", expanded);
    expanded.indent_size = 4;
    fixed_values[0 .. 2].expect_pretty("[\n    1,\n    2\n]", expanded);

    PrettyPrintOptions automatic = no_types;
    automatic.soft_max_width = 5;
    fixed_values[0 .. 2].expect_pretty("[\n  1,\n  2\n]", automatic);
    automatic.layout = PrettyPrintLayout.compact;
    fixed_values[0 .. 2].expect_pretty("[1, 2]", automatic);
    automatic.layout = PrettyPrintLayout.automatic;
    automatic.soft_max_width = 0;
    fixed_values[0 .. 1].expect_pretty("[\n  1\n]", automatic);

    i64[1] minimum_integer = [i64.min];
    PrettyPrintOptions exact_width = no_types;
    exact_width.soft_max_width = 22;
    minimum_integer.expect_pretty("[-9223372036854775808]", exact_width);
    exact_width.soft_max_width = 21;
    minimum_integer.expect_pretty(
        "[\n  -9223372036854775808\n]",
        exact_width,
    );

    i32[2][1] nested_values = [[1, 2]];
    PrettyPrintOptions shallow = no_types.with_layout(PrettyPrintLayout.compact);
    shallow.max_depth = 0;
    nested_values.expect_pretty("[...]", shallow);
}

unittest
{
    PrettyPrintOptions plain = plain_options();

    struct LocalRecord
    {
        i32 value;

        void touch()
        {
        }
    }

    LocalRecord local_record;
    local_record.value = 11;
    local_record.expect_pretty("LocalRecord {value: 11}", plain);
    local_record.expect_width_estimate_covers(plain);
    PrettyPrintOptions local_limited = plain.with_layout(PrettyPrintLayout.compact);
    local_limited.max_items = 1;
    local_record.expect_pretty("LocalRecord {value: 11}", local_limited);

    PrettyPrintTestEmpty empty;
    empty.expect_pretty("PrettyPrintTestEmpty {}", plain);

    PrettyPrintTestEmptyHolder empty_holder;
    PrettyPrintOptions no_depth = plain.with_layout(PrettyPrintLayout.compact);
    no_depth.max_depth = 0;
    empty_holder.expect_pretty(
        "PrettyPrintTestEmptyHolder {empty: PrettyPrintTestEmpty {}}",
        no_depth,
    );

    PrettyPrintTestRecord record = PrettyPrintTestRecord(7, "Ada");
    static assert(
        is(typeof(pretty(record)) == PrettyValue!PrettyPrintTestRecord),
    );
    static assert(
        is(typeof(pretty(PrettyPrintTestRecord.init)) == OwnedPrettyValue!PrettyPrintTestRecord),
    );

    record.expect_pretty(
        "PrettyPrintTestRecord {id: 7, name: \"Ada\"}",
        plain,
    );
    record.expect_width_estimate_covers(plain);

    const PrettyPrintTestRecord const_record = record;
    const_record.expect_pretty(
        "PrettyPrintTestRecord {id: 7, name: \"Ada\"}",
        plain,
    );

    PrettyValue!PrettyPrintTestRecord empty_wrapper;
    empty_wrapper.options = plain;

    char[32] empty_storage;
    const empty_result = write_buffer(empty_storage[], empty_wrapper);
    assert(empty_result.ok);
    assert(empty_storage[0 .. empty_result.written].equal("null"));

    const PrettyValue!PrettyPrintTestRecord borrowed_wrapper =
        pretty(record, plain);
    char[128] const_wrapper_storage;
    const const_wrapper_result = write_buffer(
        const_wrapper_storage[],
        borrowed_wrapper,
    );
    assert(const_wrapper_result.ok);
    assert(!const_wrapper_result.truncated);
    assert(const_wrapper_storage[0 .. const_wrapper_result.written].equal(
            "PrettyPrintTestRecord {id: 7, name: \"Ada\"}",
    ));

    auto live_borrow = record.pretty(plain);
    record.id = 8;
    char[128] live_borrow_storage;
    const live_borrow_result = write_buffer(live_borrow_storage[], live_borrow);
    assert(live_borrow_result.ok);
    assert(!live_borrow_result.truncated);
    assert(live_borrow_storage[0 .. live_borrow_result.written].equal(
            "PrettyPrintTestRecord {id: 8, name: \"Ada\"}",
    ));
    record.id = 7;

    PrettyPrintTestRecord(8, "Grace").expect_owned_pretty(
        "PrettyPrintTestRecord {id: 8, name: \"Grace\"}",
        plain,
    );

    const OwnedPrettyValue!PrettyPrintTestEnumHolder const_owned_wrapper =
        pretty(PrettyPrintTestEnumHolder.init, plain);
    char[160] const_owned_storage;
    const const_owned_result = write_buffer(
        const_owned_storage[],
        const_owned_wrapper,
    );
    assert(const_owned_result.ok);
    assert(!const_owned_result.truncated);
    assert(const_owned_storage[0 .. const_owned_result.written].equal(
            "PrettyPrintTestEnumHolder {value: PrettyPrintTestSigned.zero}",
    ));

    PrettyPrintTestMoveOnly borrowed_move_only = PrettyPrintTestMoveOnly(4);
    borrowed_move_only.expect_pretty(
        "PrettyPrintTestMoveOnly {value: 4}",
        plain,
    );
    PrettyPrintTestMoveOnly(5).expect_owned_pretty(
        "PrettyPrintTestMoveOnly {value: 5}",
        plain,
    );
    alias MoveWrapper = OwnedPrettyValue!PrettyPrintTestMoveOnly;
    static assert(!__traits(isCopyable, MoveWrapper));

    pretty_print_test_destructions = 0;
    {
        PrettyPrintTestTrackedOwner tracked =
            PrettyPrintTestTrackedOwner(6, true);
        tracked.expect_pretty(
            "PrettyPrintTestTrackedOwner {value: 6, owns_value: true}",
            plain,
        );
        assert(pretty_print_test_destructions == 0);
    }
    assert(pretty_print_test_destructions == 1);

    pretty_print_test_destructions = 0;
    PrettyPrintTestTrackedOwner(7, true).expect_owned_pretty(
        "PrettyPrintTestTrackedOwner {value: 7, owns_value: true}",
        plain,
    );
    assert(pretty_print_test_destructions == 1);

    {

        AllocationRecord[4] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            malloc_allocator(),
            records[],
        );
        {
            OwnedString owner = OwnedString.from_string(
                allocator.allocator,
                "owned pretty",
            );
            auto wrapper = pretty(move(owner), plain);
            assert(!allocator.clean());
        }
        assert(allocator.clean());
        assert(allocator.stats.invalid_calls == 0);
    }

    PrettyPrintTestRecord interpolated_record =
        PrettyPrintTestRecord(9, "Lin");
    char[192] interpolation_storage;
    const interpolation_result = write_buffer(
        interpolation_storage[],
        i"record=$(interpolated_record.pretty(plain))",
    );
    assert(interpolation_result.ok);
    assert(!interpolation_result.truncated);
    assert(interpolation_storage[0 .. interpolation_result.written].equal(
            "record=PrettyPrintTestRecord {id: 9, name: \"Lin\"}",
    ));

    PrettyPrintOptions expanded = plain.with_layout(PrettyPrintLayout.expanded);
    record.expect_pretty(
        "PrettyPrintTestRecord {\n  id: 7,\n  name: \"Ada\"\n}",
        expanded,
    );

    PrettyPrintTestOuter outer = PrettyPrintTestOuter(record, 3);
    PrettyPrintOptions shallow = plain.with_layout(PrettyPrintLayout.compact);
    shallow.max_depth = 0;
    outer.expect_pretty(
        "PrettyPrintTestOuter {inner: ..., tail: 3}",
        shallow,
    );

    PrettyPrintTestManyFields many = PrettyPrintTestManyFields(1, 2, 3);
    PrettyPrintOptions limited = plain.with_layout(PrettyPrintLayout.compact);
    limited.max_items = 2;
    many.expect_pretty(
        "PrettyPrintTestManyFields {first: 1, second: 2, ... (1 more)}",
        limited,
    );
    limited.max_items = 0;
    many.expect_pretty(
        "PrettyPrintTestManyFields {... (3 more)}",
        limited,
    );
}

unittest
{
    PrettyPrintOptions plain = plain_options();

    PrettyPrintTestOverride with_options = PrettyPrintTestOverride(1);
    with_options.expect_pretty("<pretty with options>", plain);
    PrettyPrintOptions no_types = plain;
    no_types.show_type_names = false;
    with_options.expect_pretty("<pretty without types>", no_types);

    PrettyPrintTestBothOverrides both = PrettyPrintTestBothOverrides(1);
    both.expect_pretty("<pretty wins>", plain);
    char[64] both_normal_storage;
    const both_normal_result = write_buffer(both_normal_storage[], both);
    assert(both_normal_result.ok);
    assert(both_normal_storage[0 .. both_normal_result.written].equal(
            "<normal format>",
    ));

    // Normal display formatting and structural debug formatting are separate.
    // `format_to` is ignored by `.pretty` unless the type also opts into the
    // const-compatible `pretty_format_to` hook.
    PrettyPrintTestFormatOverride display_only = PrettyPrintTestFormatOverride(9);
    char[64] normal_storage;
    const normal_result = write_buffer(normal_storage[], display_only);
    assert(normal_result.ok);
    assert(normal_storage[0 .. normal_result.written].equal("<format override>"));
    display_only.expect_pretty(
        "PrettyPrintTestFormatOverride {ignored: 9}",
        plain,
    );

    pretty_print_test_hook_calls = 0;
    PrettyPrintTestCountedHolder counted = PrettyPrintTestCountedHolder(
        PrettyPrintTestCountedOverride.init,
        2,
    );
    counted.expect_pretty(
        "PrettyPrintTestCountedHolder {\n" ~
            "  item: <counted>,\n" ~
            "  tail: 2\n" ~
            "}",
        plain,
    );
    assert(pretty_print_test_hook_calls == 1);

    // A mutable-only pretty hook is deliberately not called. Pretty printing
    // observes through a const view and cannot mutate the inspected value.
    PrettyPrintTestMutableOnlyOverride mutable_only =
        PrettyPrintTestMutableOnlyOverride(4);
    mutable_only.expect_pretty(
        "PrettyPrintTestMutableOnlyOverride {value: 4}",
        plain,
    );
}

unittest
{
    PrettyPrintOptions no_types = plain_options();
    no_types.show_type_names = false;

    i32 number = 42;
    i32* pointer = &number;
    PrettyPrintOptions dereferenced = no_types;
    dereferenced.dereference_pointers = true;
    pointer.expect_pretty("&42", dereferenced);
    pointer.expect_width_estimate_covers(dereferenced);

    PrettyPrintTestRecord record = PrettyPrintTestRecord(3, "node");
    PrettyPrintTestPointerHolder holder = PrettyPrintTestPointerHolder(
        &record,
        8,
    );
    PrettyPrintOptions expanded = dereferenced.with_layout(
        PrettyPrintLayout.expanded,
    );
    expanded.indent_size = 4;
    holder.expect_pretty(
        "{\n" ~
            "    item: &{\n" ~
            "        id: 3,\n" ~
            "        name: \"node\"\n" ~
            "    },\n" ~
            "    tail: 8\n" ~
            "}",
        expanded,
    );
    holder.expect_width_estimate_covers(dereferenced);

    i32* null_pointer;
    null_pointer.expect_pretty("null", no_types);

    char[128] address_storage;
    const address_result = write_buffer(address_storage[], pointer.pretty(no_types));
    assert(address_result.ok);
    assert(address_result.written > 3);
    assert(address_storage[0 .. 3].equal("@0x"));

    alias TestFunctionPointer = extern (C) i32 function(i32) nothrow @nogc;
    TestFunctionPointer function_pointer = &pretty_print_test_function;
    char[256] function_storage;
    const function_result = write_buffer(
        function_storage[],
        function_pointer.pretty(dereferenced),
    );
    assert(function_result.ok);
    assert(function_result.written > 3);
    assert(function_storage[0 .. 3].equal("@0x"));

    TestFunctionPointer null_function;
    null_function.expect_pretty("null", no_types);

    void* opaque = cast(void*) pointer;
    char[128] opaque_storage;
    const opaque_result = write_buffer(
        opaque_storage[],
        opaque.pretty(dereferenced),
    );
    assert(opaque_result.ok);
    assert(opaque_result.written > 3);
    assert(opaque_storage[0 .. 3].equal("@0x"));

    PrettyPrintTestNode node = PrettyPrintTestNode(1, null);
    node.next = &node;
    PrettyPrintOptions bounded = no_types.with_layout(
        PrettyPrintLayout.compact,
    );
    bounded.show_type_names = true;
    bounded.dereference_pointers = true;
    bounded.max_depth = 1;
    node.expect_pretty(
        "PrettyPrintTestNode {value: 1, next: &...}",
        bounded,
    );
}

unittest
{
    PrettyPrintOptions plain = plain_options();
    PrettyPrintTestUnion value;
    value.integer = 7;
    value.expect_pretty(
        "PrettyPrintTestUnion <union: active member unknown>",
        plain,
    );
    value.expect_width_estimate_covers(plain);
}

unittest
{
    PrettyPrintOptions compact = plain_options().with_layout(
        PrettyPrintLayout.compact,
    );
    PrettyPrintOptions expanded = plain_options().with_layout(
        PrettyPrintLayout.expanded,
    );

    PrettyPrintTestTaggedValue value;
    value.kind = PrettyPrintTestTaggedKind.integer;
    value.payload.integer = 7;
    value.expect_pretty(
        "PrettyPrintTestTaggedValue {kind: PrettyPrintTestTaggedKind.integer, "
            ~ "payload: PrettyPrintTestTaggedPayload {integer: 7}}",
        compact,
    );
    value.expect_pretty(
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
    value.expect_width_estimate_covers(compact);

    value.kind = PrettyPrintTestTaggedKind.floating;
    value.payload.renamed_floating = 9;
    value.expect_pretty(
        "PrettyPrintTestTaggedValue {kind: PrettyPrintTestTaggedKind.floating, "
            ~ "payload: PrettyPrintTestTaggedPayload {renamed_floating: 9}}",
        compact,
    );
    value.expect_width_estimate_covers(compact);

    value.kind = PrettyPrintTestTaggedKind.none;
    value.expect_pretty(
        "PrettyPrintTestTaggedValue {kind: PrettyPrintTestTaggedKind.none, "
            ~ "payload: PrettyPrintTestTaggedPayload {}}",
        compact,
    );
    value.expect_width_estimate_covers(compact);

    value.kind = cast(PrettyPrintTestTaggedKind) 99;
    value.expect_pretty(
        "PrettyPrintTestTaggedValue {kind: PrettyPrintTestTaggedKind(99), "
            ~ "payload: PrettyPrintTestTaggedPayload "
            ~ "<invalid tagged union discriminator>}",
        compact,
    );
    value.expect_width_estimate_covers(compact);
}

unittest
{

    PrettyPrintOptions no_types = plain_options();
    no_types.show_type_names = false;

    PrettyPrintTestMapSource custom_map = PrettyPrintTestMapSource(1, 2);
    custom_map.expect_pretty("{1: 2}", no_types);
    custom_map.expect_width_estimate_covers(no_types);

    PrettyPrintTestSetSource custom_set = PrettyPrintTestSetSource(3);
    custom_set.expect_pretty("{3}", no_types);
    custom_set.expect_width_estimate_covers(no_types);

    Array!i32 values = Array!i32.create(malloc_allocator());
    values.expect_pretty("[]", no_types);
    values.append(1);
    values.append(2);
    values.expect_pretty("[1, 2]", no_types);
    values.expect_width_estimate_covers(no_types);
    PrettyPrintOptions none_shown = no_types.with_layout(PrettyPrintLayout.compact);
    none_shown.max_items = 0;
    values.expect_pretty("[... (2 more)]", none_shown);
    values.deinit();

    OwnedArray!i32 owned_values = OwnedArray!i32.create(malloc_allocator());
    owned_values.append(3);
    owned_values.append(4);
    owned_values.expect_pretty("[3, 4]", no_types);
    owned_values.expect_width_estimate_covers(no_types);
    owned_values.deinit();

    HashMap!(String, i32) map = HashMap!(String, i32).create(malloc_allocator());
    map.expect_pretty("{}", no_types);
    assert(map.set("one", 1));
    map.expect_pretty("{\"one\": 1}", no_types);
    map.expect_width_estimate_covers(no_types);
    map.expect_pretty("{... (1 more)}", none_shown);
    map.deinit();

    HashSet!i32 hash_set = HashSet!i32.create(malloc_allocator());
    hash_set.expect_pretty("{}", no_types);
    assert(hash_set.add(7));
    hash_set.expect_pretty("{7}", no_types);
    hash_set.expect_width_estimate_covers(no_types);
    hash_set.expect_pretty("{... (1 more)}", none_shown);
    hash_set.deinit();

    OwnedHashMap!(String, i32) owned_map =
        OwnedHashMap!(String, i32).create(malloc_allocator());
    String owned_key = "owned";
    i32 owned_value = 9;
    assert(owned_map.add(&owned_key, &owned_value));
    owned_map.expect_pretty("{\"owned\": 9}", no_types);
    owned_map.expect_width_estimate_covers(no_types);
    owned_map.deinit();

    OwnedHashSet!i32 owned_set = OwnedHashSet!i32.create(malloc_allocator());
    i32 owned_element = 11;
    assert(owned_set.add(&owned_element));
    owned_set.expect_pretty("{11}", no_types);
    owned_set.expect_width_estimate_covers(no_types);
    owned_set.deinit();

    ArrayUnmanaged!i32 unmanaged_values;
    unmanaged_values.append(malloc_allocator(), 5);
    unmanaged_values.append(malloc_allocator(), 6);
    unmanaged_values.expect_pretty("[5, 6]", no_types);
    unmanaged_values.expect_width_estimate_covers(no_types);
    unmanaged_values.deinit(malloc_allocator());

    HashMapUnmanaged!(String, i32) unmanaged_map;
    assert(unmanaged_map.set(malloc_allocator(), "unmanaged", 13));
    unmanaged_map.expect_pretty("{\"unmanaged\": 13}", no_types);
    unmanaged_map.expect_width_estimate_covers(no_types);
    unmanaged_map.deinit(malloc_allocator());

    HashSetUnmanaged!i32 unmanaged_set;
    assert(unmanaged_set.add(malloc_allocator(), 17));
    unmanaged_set.expect_pretty("{17}", no_types);
    unmanaged_set.expect_width_estimate_covers(no_types);
    unmanaged_set.deinit(malloc_allocator());

    StringHashMapUnmanaged!i32 unmanaged_string_map;
    assert(unmanaged_string_map.set(malloc_allocator(), "string", 19));
    unmanaged_string_map.expect_pretty("{\"string\": 19}", no_types);
    unmanaged_string_map.expect_width_estimate_covers(no_types);
    unmanaged_string_map.deinit(malloc_allocator());

    StringHashMap!i32 string_map = StringHashMap!i32.create(malloc_allocator());
    assert(string_map.set("managed-string", 23));
    string_map.expect_pretty("{\"managed-string\": 23}", no_types);
    string_map.expect_width_estimate_covers(no_types);
    string_map.deinit();

    OwnedStringHashMap!i32 owned_string_map =
        OwnedStringHashMap!i32.create(malloc_allocator());
    assert(owned_string_map.set("owned-string", 29));
    owned_string_map.expect_pretty("{\"owned-string\": 29}", no_types);
    owned_string_map.expect_width_estimate_covers(no_types);
    owned_string_map.deinit();

    StringHashSetUnmanaged unmanaged_string_set;
    assert(unmanaged_string_set.add(malloc_allocator(), "unmanaged-set"));
    unmanaged_string_set.expect_pretty("{\"unmanaged-set\"}", no_types);
    unmanaged_string_set.expect_width_estimate_covers(no_types);
    unmanaged_string_set.deinit(malloc_allocator());

    StringHashSet string_set = StringHashSet.create(malloc_allocator());
    assert(string_set.add("managed-set"));
    string_set.expect_pretty("{\"managed-set\"}", no_types);
    string_set.expect_width_estimate_covers(no_types);
    string_set.deinit();
}

unittest
{
    PrettyPrintOptions no_types = plain_options();
    no_types.show_type_names = false;
    alias Permissions = FlagSet!PrettyPrintTestPermission;

    Permissions permissions = Permissions.of(
        PrettyPrintTestPermission.read,
        PrettyPrintTestPermission.execute,
        PrettyPrintTestPermission.administer,
    );
    permissions.expect_pretty("{read, execute, administer}", no_types);
    permissions.expect_width_estimate_covers(no_types);

    PrettyPrintOptions limited = no_types.with_layout(PrettyPrintLayout.compact);
    limited.max_items = 2;
    permissions.expect_pretty("{read, execute, ... (1 more)}", limited);
    limited.max_items = 0;
    permissions.expect_pretty("{... (3 more)}", limited);
}

unittest
{

    i32 number = 42;
    char[64] storage;
    const default_result = write_buffer(storage[], number.pretty);
    assert(default_result.ok);
    assert(storage[0 .. default_result.written].equal("\x1b[34m42\x1b[0m"));

    PrettyPrintColorScheme scheme = PrettyPrintColorScheme.init;
    scheme.number_value = ANSIStyle.foreground(ANSIColor.bright_red);
    PrettyPrintOptions custom = PrettyPrintOptions.init.with_color_scheme(scheme);
    char[64] custom_storage;
    const custom_result = write_buffer(custom_storage[], number.pretty(custom));
    assert(custom_result.ok);
    assert(custom_storage[0 .. custom_result.written].equal(
            "\x1b[91m42\x1b[0m",
    ));

    char[2] tiny;
    const truncated = write_buffer(tiny[], number.pretty(custom.without_colors()));
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
    ANSIStyle red = ANSIStyle.foreground(ANSIColor.bright_red);
    PrettyPrintOptions base = PrettyPrintOptions.init.with_layout(
        PrettyPrintLayout.compact,
    );
    base.show_type_names = false;
    base.color_scheme = disabled_color_scheme();

    i32 number = 42;
    PrettyPrintOptions number_options = base;
    number_options.color_scheme.number_value = red;
    number.expect_pretty("\x1b[91m42\x1b[0m", number_options);

    bool boolean = true;
    PrettyPrintOptions boolean_options = base;
    boolean_options.color_scheme.boolean_value = red;
    boolean.expect_pretty("\x1b[91mtrue\x1b[0m", boolean_options);

    Option!i32 present = Option!i32.some(7);
    present.expect_pretty("some(7)", boolean_options);

    PrettyPrintOptions constructor_options = base;
    constructor_options.color_scheme.constructor_name = red;
    present.expect_pretty("\x1b[91msome\x1b[0m(7)", constructor_options);
    boolean.expect_pretty("true", constructor_options);

    String text = "value";
    PrettyPrintOptions string_options = base;
    string_options.color_scheme.string_value = red;
    text.expect_pretty("\x1b[91m\"value\"\x1b[0m", string_options);

    char character = 'x';
    PrettyPrintOptions character_options = base;
    character_options.color_scheme.character_value = red;
    character.expect_pretty("\x1b[91m'x'\x1b[0m", character_options);

    PrettyPrintTestColor enumeration = PrettyPrintTestColor.red;
    PrettyPrintOptions enum_options = base;
    enum_options.color_scheme.enum_value = red;
    enumeration.expect_pretty("\x1b[91mred\x1b[0m", enum_options);

    typeof(null) nothing;
    PrettyPrintOptions null_options = base;
    null_options.color_scheme.null_value = red;
    nothing.expect_pretty("\x1b[91mnull\x1b[0m", null_options);

    PrettyPrintTestRecord record = PrettyPrintTestRecord(7, "Ada");
    PrettyPrintOptions type_options = base;
    type_options.show_type_names = true;
    type_options.color_scheme.type_name = red;
    record.expect_pretty(
        "\x1b[91mPrettyPrintTestRecord\x1b[0m {id: 7, name: \"Ada\"}",
        type_options,
    );

    PrettyPrintOptions field_options = base;
    field_options.color_scheme.field_name = red;
    record.expect_pretty(
        "{\x1b[91mid\x1b[0m: 7, " ~
            "\x1b[91mname\x1b[0m: \"Ada\"}",
        field_options,
    );

    i32[2] values = [1, 2];
    PrettyPrintOptions punctuation_options = base;
    punctuation_options.color_scheme.punctuation = red;
    values.expect_pretty(
        "\x1b[91m[\x1b[0m1\x1b[91m, \x1b[0m2" ~
            "\x1b[91m]\x1b[0m",
        punctuation_options,
    );

    PrettyPrintOptions truncation_options = base;
    truncation_options.max_items = 1;
    truncation_options.color_scheme.truncation = red;
    values.expect_pretty(
        "[1, \x1b[91m... (1 more)\x1b[0m]",
        truncation_options,
    );

    i32[1][1] nested = [[1]];
    PrettyPrintOptions depth_options = base;
    depth_options.max_depth = 0;
    depth_options.color_scheme.depth_limit = red;
    nested.expect_pretty("[\x1b[91m...\x1b[0m]", depth_options);

    i32* pointer = &number;
    PrettyPrintOptions pointer_options = base;
    pointer_options.dereference_pointers = true;
    pointer_options.color_scheme.pointer_value = red;
    pointer.expect_pretty("\x1b[91m&\x1b[0m42", pointer_options);

    PrettyPrintTestUnion union_value;
    union_value.integer = 1;
    PrettyPrintOptions unsupported_options = base;
    unsupported_options.color_scheme.unsupported = red;
    union_value.expect_pretty(
        "\x1b[91m<union: active member unknown>\x1b[0m",
        unsupported_options,
    );

    // Turning colors off suppresses even an otherwise enabled custom style.
    number.expect_pretty("42", number_options.without_colors());
}
