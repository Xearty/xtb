module examples.pretty_print_demo;

import xtb.ansi : AnsiColor, AnsiStyle;
import xtb.fmt.ansi : beginAnsi, endAnsi, styled;
import xtb.containers.array;
import xtb.flag_set : FlagSet;
import xtb.containers.hash_map;
import xtb.containers.hash_set;
import xtb.allocators.malloc : mallocAllocator;
import xtb.lifetime : tagged_by, tagged_case;
import xtb.option : Option;
import xtb.fmt.format : formatted;
import xtb.fmt.pretty_print : PrettyPrintColorScheme, PrettyPrintLayout,
    PrettyPrintOptions, pretty, writePretty;
import xtb.fmt.writer : Writer;
import xtb.fmt.print : writeln;
import xtb.string;

enum Permission : ubyte
{
    read,
    write,
    execute,
    administer = 7,
}

alias Permissions = FlagSet!Permission;

enum Health : ubyte
{
    unknown,
    healthy,
    degraded,
    offline,
}

struct Endpoint
{
    String host;
    ushort port;
}

struct Service
{
    String name;
    Option!Endpoint endpoint;
    Permissions permissions;
    int[4] recentExitCodes;
}

struct ScalarSamples
{
    bool enabled;
    Health health;
    int attempts;
    double load;
    char separator;
    dchar symbol;
    String message;
    Option!uint retryAfterSeconds;
}

struct EmptyMarker
{
}

enum TaggedValueKind : ubyte
{
    none,
    integer,
    endpoint,
    retry,
}

union TaggedValuePayload
{
    int integer;
    Endpoint endpoint;

    // The field name does not need to match the discriminator when an explicit
    // case mapping is clearer.
    @tagged_case(TaggedValueKind.retry)
    uint retryAfterSeconds;
}

struct TaggedValue
{
    String label;
    TaggedValueKind kind;

    @tagged_by("kind", TaggedValueKind.none)
    TaggedValuePayload payload;
}

union RawValue
{
    int integer;
    double floating;
}

struct Node
{
    String name;
    Node* next;
}

private extern (C) int demoCallback(int value) nothrow @nogc
{
    return value;
}

/// Writes one token using a style from the active pretty-print scheme. Custom
/// hooks can use the public ANSI API for syntax they emit themselves and call
/// `writePretty` for nested values.
private void writeDemoStyled(
    ref Writer writer,
    scope String value,
    AnsiStyle style,
    scope const ref PrettyPrintOptions options,
) nothrow @nogc
{
    const styled = options.colored && style.enabled;
    if (styled)
        beginAnsi(writer, style);
    writer.put(value);
    if (styled)
        endAnsi(writer, style);
}

/// A type can replace its structural debug representation without changing its
/// normal display representation. The hook receives the active pretty-print
/// options, so nested values retain the caller's colors and policies.
struct Credential
{
    String user;
    String secret;

    void prettyFormatTo(
        ref Writer writer,
        scope const ref PrettyPrintOptions options,
    ) const nothrow @nogc
    {
        writeDemoStyled(
            writer,
            "Credential",
            options.colorScheme.typeName,
            options,
        );
        writeDemoStyled(writer, "(", options.colorScheme.punctuation, options);
        writeDemoStyled(writer, "user", options.colorScheme.fieldName, options);
        writeDemoStyled(writer, ": ", options.colorScheme.punctuation, options);
        writePretty(writer, user, options);
        writeDemoStyled(writer, ", ", options.colorScheme.punctuation, options);
        writeDemoStyled(
            writer,
            "secret",
            options.colorScheme.fieldName,
            options,
        );
        writeDemoStyled(writer, ": ", options.colorScheme.punctuation, options);
        writeDemoStyled(
            writer,
            "<redacted>",
            options.colorScheme.unsupported,
            options,
        );
        writeDemoStyled(writer, ")", options.colorScheme.punctuation, options);
    }
}

/// `formatTo` remains the concise normal display representation. Calling
/// `.pretty` deliberately ignores it and shows the structural representation.
struct DisplayName
{
    String value;

    void formatTo(ref Writer writer) const nothrow @nogc
    {
        writer.put(value);
    }
}

/// Builds a vivid palette that styles punctuation as well as semantic values.
/// The module defaults intentionally leave punctuation unstyled; applications
/// can opt into a denser color treatment like this one.
private PrettyPrintColorScheme vividColorScheme()
{
    PrettyPrintColorScheme scheme = PrettyPrintColorScheme.defaults();
    scheme.typeName = AnsiStyle.foreground(AnsiColor.brightMagenta).bold;
    scheme.fieldName = AnsiStyle.foreground(AnsiColor.brightCyan);
    scheme.stringValue = AnsiStyle.foreground(AnsiColor.brightGreen);
    scheme.characterValue = AnsiStyle.foreground(AnsiColor.green);
    scheme.numberValue = AnsiStyle.foreground(AnsiColor.brightBlue);
    scheme.booleanValue = AnsiStyle.foreground(AnsiColor.yellow);
    scheme.constructorName = AnsiStyle.foreground(AnsiColor.brightYellow);
    scheme.enumValue = AnsiStyle.foreground(AnsiColor.brightGreen);
    scheme.nullValue = AnsiStyle.foreground(AnsiColor.brightBlack).italic;
    scheme.pointerValue = AnsiStyle.foreground(AnsiColor.brightMagenta);
    scheme.punctuation = AnsiStyle.foreground(AnsiColor.brightBlack);
    scheme.truncation = AnsiStyle.foreground(AnsiColor.brightYellow).italic;
    scheme.depthLimit = AnsiStyle.foreground(AnsiColor.brightRed).bold;
    scheme.unsupported = AnsiStyle.foreground(AnsiColor.brightRed).bold;
    return scheme;
}

/// Prints a visible section label. This styling is independent from the pretty
/// printer and only makes the showcase easier to scan in a terminal.
private void heading(String title)
{
    const style = AnsiStyle.foreground(AnsiColor.brightWhite)
        .withBackground(AnsiColor.blue)
        .bold;
    writeln("\n", styled(formatted!"  {}  "(title), style));
}

extern (C) int main()
{
    Service service = Service(
        "gateway",
        Option!Endpoint.some(Endpoint("127.0.0.1", 8443)),
        Permissions.of(Permission.read, Permission.write, Permission.execute),
        [0, 0, 1, 137],
    );

    PrettyPrintOptions vivid = PrettyPrintOptions.defaults().withColorScheme(
        vividColorScheme(),
    );

    heading("DEFAULTS, LVALUES, AND TEMPORARIES");

    // Default options use the built-in semantic palette and automatic layout.
    writeln("default palette: ", service.pretty);

    // The caller can provide a palette, but never has to provide one.
    writeln("vivid palette:   ", service.pretty(vivid));

    // Lvalues are borrowed without copying. Changes made before formatting are
    // observed by the wrapper.
    Endpoint liveEndpoint = Endpoint("localhost", 8080);
    auto borrowed = liveEndpoint.pretty(vivid);
    liveEndpoint.port = 8081;
    writeln("borrowed lvalue: ", borrowed);

    // Rvalues are moved into an owning wrapper, so temporary expressions are
    // safe to pass directly to `writeln` or interpolation.
    writeln("owned temporary: ", Endpoint("localhost", 9090).pretty(vivid));

    heading("LAYOUT POLICY");

    PrettyPrintOptions compact = vivid.withLayout(PrettyPrintLayout.compact);
    writeln("forced compact:  ", service.pretty(compact));

    // Expanded output uses four spaces here. `some(` is a same-line unary
    // wrapper, so its Endpoint fields gain one visual level—not two.
    PrettyPrintOptions expanded = vivid.withLayout(
        PrettyPrintLayout.expanded,
    );
    expanded.indentSize = 4;
    writeln("forced expanded:\n", service.pretty(expanded));

    // A narrow automatic width expands aggregates that do not fit. ANSI bytes
    // do not count toward this visible-width hint.
    PrettyPrintOptions narrow = vivid;
    narrow.softMaxWidth = 44;
    writeln("automatic width 44:\n", service.pretty(narrow));

    // Type names can be hidden while retaining all other semantic colors.
    PrettyPrintOptions structural = vivid;
    structural.showTypeNames = false;
    writeln("without type names: ", service.pretty(structural));

    // Color can be disabled independently from layout and type-name policy.
    PrettyPrintOptions plainExpanded = expanded.withoutColors();
    plainExpanded.showTypeNames = false;
    writeln("plain expanded:\n", service.pretty(plainExpanded));

    heading("TAGGED UNION LAYOUTS");

    // Tagged raw unions are printed through their containing aggregate. The
    // discriminator selects the one member that is safe to inspect.
    TaggedValue taggedEndpoint;
    taggedEndpoint.label = "upstream";
    taggedEndpoint.kind = TaggedValueKind.endpoint;
    taggedEndpoint.payload.endpoint = Endpoint("api.internal", 9443);

    writeln("automatic:       ", taggedEndpoint.pretty(vivid));
    writeln("forced compact:  ", taggedEndpoint.pretty(compact));
    writeln("forced expanded:\n", taggedEndpoint.pretty(expanded));

    // Automatic layout accounts for the active payload only. Tightening the
    // visible width expands both the containing struct and nested Endpoint.
    PrettyPrintOptions taggedNarrow = vivid;
    taggedNarrow.softMaxWidth = 36;
    writeln("automatic width 36:\n", taggedEndpoint.pretty(taggedNarrow));

    // The inactive discriminator prints an empty payload rather than reading
    // raw union storage.
    TaggedValue taggedInactive;
    taggedInactive.label = "idle";
    writeln("inactive:        ", taggedInactive.pretty(compact));

    // `@tagged_case` supports an intentionally different field/tag name while
    // retaining the same active-member behavior in every layout.
    TaggedValue taggedRetry;
    taggedRetry.label = "backoff";
    taggedRetry.kind = TaggedValueKind.retry;
    taggedRetry.payload.retryAfterSeconds = 15;
    writeln("mapped compact:  ", taggedRetry.pretty(compact));
    writeln("mapped expanded:\n", taggedRetry.pretty(expanded));

    heading("SCALARS, ENUMS, STRINGS, AND OPTION");

    ScalarSamples scalars = ScalarSamples(
        true,
        Health.degraded,
        3,
        0.625,
        ':',
        cast(dchar) 0x1f642,
        "ready\nserving",
        Option!uint.none,
    );
    writeln(scalars.pretty(vivid));

    // Invalid enum values retain their underlying number instead of guessing a
    // member name.
    Health invalidHealth = cast(Health) 99;
    writeln("invalid enum: ", invalidHealth.pretty(vivid));

    // Both Option states are explicit. A multiline aggregate payload is fused
    // with `some(` and closes at the Option's indentation level.
    Option!Endpoint missingEndpoint;
    writeln("none: ", missingEndpoint.pretty(vivid));
    writeln(
        "some expanded:\n",
        Option!Endpoint.some(Endpoint("10.0.0.8", 443)).pretty(expanded),
    );

    heading("BUILT-IN AND XTB COLLECTIONS");

    int[5] fixedValues = [1, 2, 3, 5, 8];
    writeln("static array: ", fixedValues.pretty(vivid));
    writeln("slice:        ", fixedValues[1 .. 4].pretty(vivid));

    Array!int dynamicValues = Array!int.create(mallocAllocator());
    dynamicValues.append(13);
    dynamicValues.append(21);
    dynamicValues.append(34);
    writeln("Array:        ", dynamicValues.pretty(vivid));

    HashMap!(String, int) statuses =
        HashMap!(String, int).create(mallocAllocator());
    if (!statuses.set("healthy", 2) || !statuses.set("degraded", 1))
    {
        statuses.deinit();
        dynamicValues.deinit();
        return 1;
    }
    writeln("HashMap:      ", statuses.pretty(vivid));

    HashSet!String regions = HashSet!String.create(mallocAllocator());
    if (!regions.add("eu-west") || !regions.add("us-east"))
    {
        regions.deinit();
        statuses.deinit();
        dynamicValues.deinit();
        return 1;
    }
    writeln("HashSet:      ", regions.pretty(vivid));
    writeln("FlagSet:      ", service.permissions.pretty(vivid));

    StringBuf message = StringBuf.fromString(
        mallocAllocator(),
        "owned\nStringBuf",
    );
    writeln("StringBuf:    ", message.pretty(vivid));

    heading("BOUNDS AND FAILURE-SAFE DIAGNOSTICS");

    // `maxItems` applies to struct fields and collection elements.
    PrettyPrintOptions limited = compact;
    limited.maxItems = 2;
    writeln("maxItems = 2: ", service.pretty(limited));

    // Pointer dereferencing is opt-in. Depth limiting keeps cyclic trusted
    // graphs bounded once dereferencing is enabled.
    Node node = Node("root", null);
    node.next = &node;
    PrettyPrintOptions bounded = compact;
    bounded.dereferencePointers = true;
    bounded.maxDepth = 1;
    writeln("bounded cycle: ", node.pretty(bounded));

    // The default pointer representation is an address and never dereferences.
    int responseCode = 200;
    int* responsePointer = &responseCode;
    writeln("pointer address: ", responsePointer.pretty(vivid));
    PrettyPrintOptions followed = vivid;
    followed.dereferencePointers = true;
    writeln("pointer value:   ", responsePointer.pretty(followed));
    int* nullPointer;
    writeln("null pointer:    ", nullPointer.pretty(vivid));

    // Function pointers and `void*` remain address-only even when pointer
    // dereferencing is enabled; there is no safe generic value to inspect.
    alias Callback = extern (C) int function(int) nothrow @nogc;
    Callback callback = &demoCallback;
    writeln("function pointer: ", callback.pretty(followed));
    void* opaquePointer = cast(void*) responsePointer;
    writeln("void pointer:     ", opaquePointer.pretty(followed));

    // Even for a tagged union, an invalid runtime discriminator does not make
    // the formatter guess which bytes are live. It emits a diagnostic marker
    // without touching the raw payload.
    TaggedValue invalidTagged = taggedEndpoint;
    invalidTagged.kind = cast(TaggedValueKind) 99;
    writeln("invalid tagged union: ", invalidTagged.pretty(compact));

    // A raw union has no active-member metadata, so the formatter refuses to
    // guess and emits a safe marker instead of reading arbitrary storage.
    RawValue raw;
    raw.integer = 42;
    writeln("raw union: ", raw.pretty(vivid));
    writeln("empty struct: ", EmptyMarker.init.pretty(vivid));

    heading("CUSTOMIZATION AND PRINT INTEGRATION");

    // A const-compatible `prettyFormatTo` hook can redact or reshape debug
    // output. Nested calls use `writePretty` to preserve the active options.
    Credential credential = Credential("martin", "not-for-logs");
    writeln("custom hook: ", credential.pretty(vivid));

    // Normal display and structural debug output intentionally stay separate.
    DisplayName displayName = DisplayName("gateway");
    writeln("normal display:  ", displayName);
    writeln("structural view: ", displayName.pretty(vivid));

    // Pretty wrappers work in interpolation sequences because `print.d` sees
    // their ordinary `formatTo(ref Writer)` extension hook.
    Endpoint interpolated = Endpoint("localhost", 7070);
    writeln(i"interpolated: $(interpolated.pretty(vivid))");

    message.deinit();
    regions.deinit();
    statuses.deinit();
    dynamicValues.deinit();
    return 0;
}
