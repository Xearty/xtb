module tests.serde_tests;

import tests.serde_backend_contract : runSerdeBackendContracts;
import xtb.core.array;
import xtb.core.hash_map;
import xtb.core.lifetime : deinitValue = deinit, move, moveEmplace;
import xtb.core.memory : Allocator;
import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.option : Option, some;
import xtb.core.print : Writer;
import xtb.core.string;
import xtb.core.string_hash_map;
import xtb.core.string_hash_set : StringHashSet;
import xtb.core.types : u8;
import xtb.serde.attributes;
import xtb.serde.casing;
import xtb.serde.error;
import xtb.serde.json;
import xtb.serde.ownership;
import xtb.serde.toml;
import xtb.serde.traits;

private size_t bufferSink(void* context, scope const(u8)[] bytes) nothrow @nogc
{
    StringBuf* output = cast(StringBuf*) context;
    (*output).append(bytes.asStringUnchecked);
    return bytes.length;
}

private size_t failingSink(void*, scope const(u8)[]) nothrow @nogc
{
    return 0;
}

private enum Mode
{
    quiet,
    verbose,
}

@serdeVariantCase(KeyCase.snake)
private enum DeploymentMode
{
    blueGreen,
    @serdeRename("rolling-update") @serdeAliasName("rolling") rollingUpdate,
}

bool omitSeven(scope const ref int value) nothrow @nogc pure @safe
{
    return value == 7;
}

private struct PolicyDocument
{
    DeploymentMode mode;
    @serdeDefaultValue(7) @serdeOmitIf!omitSeven int retryLimit;
}

private struct Percentage
{
    ubyte value;
}

struct PercentageSerde
{
    alias Representation = uint;

    static SerdeErrorKind encode(
        scope const ref Percentage value,
        uint* output,
    ) nothrow @nogc
    {
        *output = value.value;
        return SerdeErrorKind.none;
    }

    static SerdeErrorKind decode(
        scope const ref uint value,
        Allocator*,
        Percentage* output,
    ) nothrow @nogc
    {
        if (value > 100)
            return SerdeErrorKind.numberOutOfRange;
        output.value = cast(ubyte) value;
        return SerdeErrorKind.none;
    }
}

private struct AdapterDocument
{
    @serdeWith!PercentageSerde Percentage percentage;
}

static assert(fieldAdapterCount!(AdapterDocument, 0) == 1);

private struct SwitchState
{
    bool enabled;
}

struct SwitchStateSerde
{
    alias Representation = String;

    static SerdeErrorKind encode(
        scope const ref SwitchState value,
        String* output,
    ) nothrow @nogc
    {
        *output = value.enabled ? "enabled" : "disabled";
        return SerdeErrorKind.none;
    }

    static SerdeErrorKind decode(
        scope const ref String value,
        Allocator*,
        SwitchState* output,
    ) nothrow @nogc
    {
        if (value.equal("enabled"))
            output.enabled = true;
        else if (value.equal("disabled"))
            output.enabled = false;
        else
            return SerdeErrorKind.typeMismatch;
        return SerdeErrorKind.none;
    }
}

private struct StringAdapterDocument
{
    @serdeWith!SwitchStateSerde SwitchState state;
}

private struct ExplicitNestedDefault
{
    @serdeDefaultValue(11) int value;
}

private struct NestedDefaultsDocument
{
    ExplicitNestedDefault* pointer;
    ExplicitNestedDefault[] items;
}

@serdeVariantCase(KeyCase.snake)
private enum EventKind
{
    recordCreated,
    @serdeRename("removed") @serdeAliasName("record_deleted") recordDeleted,
}

private struct CreatedEvent
{
    int id;
    String displayName;
}

private struct DeletedEvent
{
    int id;
    bool permanent;
}

private union EventPayload
{
    @serdeCaseOf(EventKind.recordCreated) CreatedEvent created;
    @serdeCaseOf(EventKind.recordDeleted) DeletedEvent deleted;
}

@serdeTaggedUnion(TagLayout.external)
private struct ExternalEvent
{
    @serdeDiscriminant EventKind kind;
    @serdePayload EventPayload data;
}

@serdeTaggedUnion(TagLayout.internal)
private struct InternalEvent
{
    @serdeDiscriminant @serdeRename("event_type") EventKind kind;
    @serdePayload EventPayload data;
}

@serdeTaggedUnion(TagLayout.adjacent)
private struct AdjacentEvent
{
    @serdeDiscriminant @serdeRename("event_type") EventKind kind;
    @serdePayload @serdeRename("event_data") EventPayload data;
}

private struct ExternalEnvelope
{
    ExternalEvent event;
}

private struct InternalEnvelope
{
    InternalEvent event;
}

private struct AdjacentEnvelope
{
    AdjacentEvent event;
}

private enum ScalarKind
{
    integer,
}

private union ScalarPayload
{
    @serdeCaseOf(ScalarKind.integer) int integer;
}

@serdeTaggedUnion(TagLayout.internal)
private struct InvalidInternalUnion
{
    @serdeDiscriminant ScalarKind kind;
    @serdePayload ScalarPayload data;
}

private union IncompletePayload
{
    @serdeCaseOf(EventKind.recordCreated) CreatedEvent created;
}

@serdeTaggedUnion(TagLayout.adjacent)
private struct IncompleteUnion
{
    @serdeDiscriminant EventKind kind;
    @serdePayload IncompletePayload data;
}

struct InvalidSerdeAdapter
{
    alias Representation = uint;

    static bool encode(scope const ref Percentage, uint*)
    {
        return true;
    }

    static bool decode(scope const ref uint, Allocator*, Percentage*)
    {
        return true;
    }
}

private struct InvalidAdapterDocument
{
    @serdeWith!InvalidSerdeAdapter Percentage percentage;
}

@serdeFieldCase(KeyCase.snake)
private struct Identity
{
    @serdeRequired String displayName;
    uint userID;
}

private struct Settings
{
    @serdeRename("api-version") int apiVersion;
    @serdeAliasName("enabled") bool active;
    @serdeIgnore int transientValue;
    @serdeOmitDefault uint retries;
    @serdeFlatten Identity identity;
    Mode mode;
    int[] ports;
    int[2] pair;
}

private struct OptionalChild
{
    String label;
    int value;
}

private struct OptionalDocument
{
    OptionalChild* child;
}

@serdeFieldCase(KeyCase.snake)
private struct OptionalValues
{
    Option!String title;
    Option!int priority;
    Option!OptionalChild child;
    @serdeRequired Option!bool explicitToggle;
}

private struct CasingDocument
{
    uint httpServerID;
    @serdeRename("fixed-key") uint explicitName;
}

private struct Database
{
    @serdeRequired String hostName;
    ushort port;
}

private struct Server
{
    String name;
    bool enabled;
}

@serdeFieldCase(KeyCase.snake)
private struct TomlDocument
{
    @serdeRequired String applicationName;
    Database database;
    Server[] servers;
    double ratio;
}

private struct DefaultsDocument
{
    @serdeOmitDefault int retryCount = 3;
    bool enabled;
}

@serdeFieldCase(KeyCase.snake)
private struct ConflictingNames
{
    int fieldName;
    int field_name;
}

private struct NestedConflictingNames
{
    ConflictingNames nested;
}

private struct NestedConflictingNamesArray
{
    ConflictingNames[] nested;
}

private struct NestedConflictingNamesMap
{
    HashMap!(String, ConflictingNames) nested;
}

@serdeFieldCase(KeyCase.snake)
private struct TopLevelBorrowedItem
{
    @serdeRequired String displayName;
    int value;
}

@serdeFieldCase(KeyCase.snake)
private struct TopLevelOwnedItem
{
    @serdeRequired StringBuf displayName;
    int value;

    void deinit() nothrow @nogc
    {
        deinitValue(displayName);
    }
}

private enum ConflictingAdapterRepresentation
{
    @serdeRename("same") first,
    @serdeRename("same") second,
}

private struct ConflictingRepresentationAdapter
{
    alias Representation = ConflictingAdapterRepresentation;

    static SerdeErrorKind encode(
        scope const ref int value,
        Representation* output,
    ) nothrow @nogc
    {
        *output = value == 0 ? Representation.first : Representation.second;
        return SerdeErrorKind.none;
    }

    static SerdeErrorKind decode(
        scope const ref Representation value,
        Allocator*,
        int* output,
    ) nothrow @nogc
    {
        *output = value == Representation.first ? 0 : 1;
        return SerdeErrorKind.none;
    }
}

private struct InvalidAdapterRepresentationDocument
{
    @serdeWith!ConflictingRepresentationAdapter int value;
}

private struct HashMapDocument
{
    HashMap!(String, int) values;
}

private struct OwnedStringMapDocument
{
    OwnedStringHashMap!OwnedString values;
}

alias OwnedStringArrayMap = OwnedStringHashMap!(OwnedArray!int);

private struct HashMapContainers
{
    HashMap!(String, int)[] values;
    HashMap!(String, int)* pointer;
}

static assert(!isSerdeStruct!(HashSet!int));
static assert(!isSerdeStruct!(OwnedHashSet!int));
static assert(!isSerdeStruct!StringHashSet);

private struct StaticInitializer
{
    String text = "static storage";
}

align(64) private struct AlignedDocument
{
    int value;
}

@serdeFieldCase(KeyCase.snake)
private struct OwnedEndpoint
{
    @serdeRequired StringBuf hostName;
    ushort port;
    OwnedArray!StringBuf labels;

    void deinit() nothrow @nogc
    {
        deinitValue(labels);
        deinitValue(hostName);
    }
}

@serdeFieldCase(KeyCase.snake)
private struct OwnedDocument
{
    @serdeRequired StringBuf applicationName;
    OwnedEndpoint primaryEndpoint;
    OwnedArray!OwnedEndpoint replicaEndpoints;
    OwnedArray!StringBuf featureFlags;
    @serdeOmitDefault StringBuf description;
    @serdeOmitDefault OwnedArray!StringBuf experiments;
    int[3] retryDelays;
    @serdeOmitDefault bool tracingEnabled;

    void deinit() nothrow @nogc
    {
        deinitValue(experiments);
        deinitValue(description);
        deinitValue(featureFlags);
        deinitValue(replicaEndpoints);
        deinitValue(primaryEndpoint);
        deinitValue(applicationName);
    }
}

@serdeFieldCase(KeyCase.snake)
private struct OwnedOptionalValues
{
    Option!StringBuf title;
    Option!OwnedEndpoint endpoint;
    Option!uint revision;
    @serdeRequired Option!bool explicitToggle;
}

private void deinitOwnedOptionalValues(ref OwnedOptionalValues value) nothrow @nogc
{
    // Option is migrated to explicit lifetime semantics in a later step. Until
    // then, explicitly release the OwnedArray nested in its Endpoint payload
    // before Option.reset invokes the payload's current D destruction path.
    if (value.endpoint.isSome)
        value.endpoint.value.labels.deinit();
    value.endpoint.reset();
    value.title.reset();
    value.revision.reset();
    value.explicitToggle.reset();
}

private struct UnmanagedContainerFields
{
    ArrayUnmanaged!int array;
    StringBufUnmanaged string;
    HashMapUnmanaged!(String, int) map;
    HashSetUnmanaged!String set;
}

static assert(!__traits(compiles, validateSchema!(ArrayUnmanaged!int)()));
static assert(!__traits(compiles, validateSchema!StringBufUnmanaged()));
static assert(!__traits(compiles,
        validateSchema!(HashMapUnmanaged!(String, int))()));
static assert(!__traits(compiles,
        validateSchema!(HashSetUnmanaged!String)()));
static assert(!__traits(compiles, validateSchema!UnmanagedContainerFields()));
static assert(!__traits(compiles,
        (ref Writer writer, ref ArrayUnmanaged!int values) {
        writeJson(writer, values);
        writeToml(writer, values);
    }));

static assert(!__traits(compiles, validateSchema!ConflictingNames()));
static assert(!__traits(compiles, validateSchema!NestedConflictingNames()));
static assert(!__traits(compiles,
        validateSchema!NestedConflictingNamesArray()));
static assert(!__traits(compiles,
        validateSchema!NestedConflictingNamesMap()));
static assert(!__traits(compiles,
        validateSchema!InvalidAdapterRepresentationDocument()));
static assert(__traits(compiles, validateSchema!HashMapDocument()));
static assert(__traits(compiles, validateBorrowedSchema!HashMapDocument()));
static assert(__traits(compiles, validateBorrowedSchema!HashMapContainers()));
static assert(!__traits(compiles, validateOwnedSchema!HashMapDocument()));
static assert(__traits(compiles,
        (ref Writer writer, ref HashMap!(String, int) values) {
        writeJson(writer, values);
        writeToml(writer, values);
    }));
static assert(!__traits(compiles,
        (ref Writer writer, ref HashMap!(int, int) values) { writeJson(writer, values); }));
static assert(__traits(compiles, (ref Writer writer, ref int[3] values) { writeJson(writer, values); }));
static assert(__traits(compiles,
        (Allocator* allocator, Deserialized!(int[])* output) { readJson("[]", allocator, output); }));
static assert(__traits(compiles,
        (Allocator* allocator, Deserialized!(HashMap!(String, int))* output) {
        readJson("{}", allocator, output);
        readToml("", allocator, output);
    }));
static assert(!__traits(compiles,
        (Allocator* allocator, HashMap!(String, int)* output) { readJson("{}", allocator, output); }));
static assert(!__traits(compiles, (ref Writer writer, ref int[3] values) {
        writeToml(writer, values);
    }));
static assert(__traits(compiles, validateSchema!StaticInitializer()));
static assert(__traits(compiles, validateOwnedSchema!OwnedDocument()));
static assert(__traits(compiles, validateOwnedSchema!OwnedOptionalValues()));
static assert(__traits(compiles, validateBorrowedSchema!OptionalValues()));
static assert(__traits(compiles, validateBorrowedSchema!ExternalEvent()));
static assert(__traits(compiles, validateBorrowedSchema!InternalEvent()));
static assert(__traits(compiles, validateBorrowedSchema!AdjacentEvent()));
static assert(!__traits(compiles, validateOwnedSchema!AdjacentEvent()));
static assert(!__traits(compiles,
        validateBorrowedSchema!InvalidInternalUnion()));
static assert(!__traits(compiles, validateBorrowedSchema!IncompleteUnion()));
static assert(!__traits(compiles, validateSchema!InvalidAdapterDocument()));
static assert(!__traits(compiles, validateBorrowedSchema!OwnedDocument()));
static assert(!__traits(compiles, validateOwnedSchema!Settings()));
static assert(!__traits(compiles, (ref Deserialized!Settings value) {
        Deserialized!Settings copy = value;
    }));

private void testSharedPolicies() nothrow @nogc
{
    PolicyDocument value;
    value.mode = DeploymentMode.rollingUpdate;
    value.retryLimit = 7;

    StringBuf json = StringBuf.create(mallocAllocator());
    Writer jsonWriter = Writer.fromSink(&bufferSink, &json);
    SerdeError error = writeJson(jsonWriter, value);
    assert(error.ok);
    assert(json == "{\"mode\":\"rolling-update\"}");

    Deserialized!PolicyDocument fromJson;
    scope (exit)
        fromJson.deinit();
    error = readJson("{\"mode\":\"rolling\"}", mallocAllocator(),
        &fromJson);
    assert(error.ok);
    assert(fromJson.value.mode == DeploymentMode.rollingUpdate);
    assert(fromJson.value.retryLimit == 7);

    StringBuf toml = StringBuf.create(mallocAllocator());
    Writer tomlWriter = Writer.fromSink(&bufferSink, &toml);
    error = writeToml(tomlWriter, value);
    assert(error.ok);
    assert(toml == "mode = \"rolling-update\"");

    Deserialized!PolicyDocument fromToml;
    scope (exit)
        fromToml.deinit();
    error = readToml("mode = \"blue_green\"", mallocAllocator(),
        &fromToml);
    assert(error.ok);
    assert(fromToml.value.mode == DeploymentMode.blueGreen);
    assert(fromToml.value.retryLimit == 7);

    AdapterDocument adapted = AdapterDocument(Percentage(75));
    json.clear();
    jsonWriter = Writer.fromSink(&bufferSink, &json);
    error = writeJson(jsonWriter, adapted);
    assert(error.ok);
    assert(json == "{\"percentage\":75}");
    AdapterDocument ownedJson;
    error = readJson(json.view, mallocAllocator(), &ownedJson);
    assert(error.ok);
    assert(ownedJson.percentage.value == 75);

    toml.clear();
    tomlWriter = Writer.fromSink(&bufferSink, &toml);
    error = writeToml(tomlWriter, adapted);
    assert(error.ok);
    assert(toml == "percentage = 75");
    AdapterDocument ownedToml;
    error = readToml(toml.view, mallocAllocator(), &ownedToml);
    assert(error.ok);
    assert(ownedToml.percentage.value == 75);

    error = readJson("{\"percentage\":101}", mallocAllocator(), &ownedJson);
    assert(error.kind == SerdeErrorKind.numberOutOfRange);
    error = readToml("percentage = 101", mallocAllocator(), &ownedToml);
    assert(error.kind == SerdeErrorKind.numberOutOfRange);

    AllocationRecord[16] adapterRecords;
    InstrumentedAllocator adapterAllocator = InstrumentedAllocator.create(
        mallocAllocator(), adapterRecords[]);
    {
        StringAdapterDocument stringAdapted;
        error = readJson("{\"state\":\"en\\u0061bled\"}",
            adapterAllocator.allocator, &stringAdapted);
        assert(error.ok);
        assert(stringAdapted.state.enabled);
        error = readToml("state = \"disabled\"", adapterAllocator.allocator,
            &stringAdapted);
        assert(error.ok);
        assert(!stringAdapted.state.enabled);
    }
    assert(adapterAllocator.clean);
    assert(adapterAllocator.stats.invalidCalls == 0);

    Deserialized!NestedDefaultsDocument jsonDefaults;
    scope (exit)
        jsonDefaults.deinit();
    error = readJson("{\"pointer\":{},\"items\":[{}]}",
        mallocAllocator(), &jsonDefaults);
    assert(error.ok);
    assert(jsonDefaults.value.pointer.value == 11);
    assert(jsonDefaults.value.items[0].value == 11);

    Deserialized!NestedDefaultsDocument tomlDefaults;
    scope (exit)
        tomlDefaults.deinit();
    error = readToml("pointer = {}\nitems = [{}]\n",
        mallocAllocator(), &tomlDefaults);
    assert(error.ok);
    assert(tomlDefaults.value.pointer.value == 11);
    assert(tomlDefaults.value.items[0].value == 11);
    toml.deinit();
    json.deinit();
}

private void testJsonTaggedUnions() nothrow @nogc
{
    ExternalEvent external;
    external.kind = EventKind.recordCreated;
    external.data.created = CreatedEvent(17, "new record");
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = writeJson(writer, external);
    assert(error.ok);
    assert(encoded ==
            "{\"record_created\":{\"id\":17,\"displayName\":\"new record\"}}");

    Deserialized!ExternalEvent decodedExternal;
    scope (exit)
        decodedExternal.deinit();
    error = readJson(encoded.view, mallocAllocator(), &decodedExternal);
    assert(error.ok);
    assert(decodedExternal.value.kind == EventKind.recordCreated);
    assert(decodedExternal.value.data.created.id == 17);
    assert(decodedExternal.value.data.created.displayName.equal("new record"));

    InternalEvent internal;
    internal.kind = EventKind.recordDeleted;
    internal.data.deleted = DeletedEvent(9, true);
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, internal);
    assert(error.ok);
    assert(encoded ==
            "{\"event_type\":\"removed\",\"id\":9,\"permanent\":true}");

    Deserialized!InternalEvent decodedInternal;
    scope (exit)
        decodedInternal.deinit();
    error = readJson(
        "{\"permanent\":true,\"id\":9,\"event_type\":\"record_deleted\"}",
        mallocAllocator(), &decodedInternal);
    assert(error.ok);
    assert(decodedInternal.value.kind == EventKind.recordDeleted);
    assert(decodedInternal.value.data.deleted.id == 9);
    assert(decodedInternal.value.data.deleted.permanent);

    AdjacentEvent adjacent;
    adjacent.kind = EventKind.recordCreated;
    adjacent.data.created = CreatedEvent(23, "adjacent");
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, adjacent);
    assert(error.ok);
    assert(encoded ==
            "{\"event_type\":\"record_created\",\"event_data\":{" ~
            "\"id\":23,\"displayName\":\"adjacent\"}}");

    Deserialized!AdjacentEvent decodedAdjacent;
    scope (exit)
        decodedAdjacent.deinit();
    error = readJson(
        "{\"event_data\":{\"id\":23,\"displayName\":\"adjacent\"}," ~
            "\"event_type\":\"record_created\"}",
        mallocAllocator(), &decodedAdjacent);
    assert(error.ok);
    assert(decodedAdjacent.value.kind == EventKind.recordCreated);
    assert(decodedAdjacent.value.data.created.id == 23);

    error = readJson(
        "{\"event_type\":\"missing\",\"event_data\":{}}",
        mallocAllocator(), &decodedAdjacent);
    assert(error.kind == SerdeErrorKind.unknownVariant);
    assert(decodedAdjacent.empty);
    encoded.deinit();
}

private void testTomlTaggedUnions() nothrow @nogc
{
    ExternalEnvelope external;
    external.event.kind = EventKind.recordCreated;
    external.event.data.created = CreatedEvent(17, "new record");
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = writeToml(writer, external);
    assert(error.ok);
    assert(encoded ==
            "event = { \"record_created\" = { id = 17, " ~
            "displayName = \"new record\" } }");

    Deserialized!ExternalEnvelope decodedExternal;
    scope (exit)
        decodedExternal.deinit();
    error = readToml(encoded.view, mallocAllocator(), &decodedExternal);
    assert(error.ok);
    assert(decodedExternal.value.event.kind == EventKind.recordCreated);
    assert(decodedExternal.value.event.data.created.id == 17);

    InternalEnvelope internal;
    internal.event.kind = EventKind.recordDeleted;
    internal.event.data.deleted = DeletedEvent(9, true);
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, internal);
    assert(error.ok);
    assert(encoded ==
            "event = { event_type = \"removed\", id = 9, permanent = true }");

    Deserialized!InternalEnvelope decodedInternal;
    scope (exit)
        decodedInternal.deinit();
    error = readToml(
        "event = { permanent = true, id = 9, " ~
            "event_type = \"record_deleted\" }",
        mallocAllocator(), &decodedInternal);
    assert(error.ok);
    assert(decodedInternal.value.event.kind == EventKind.recordDeleted);
    assert(decodedInternal.value.event.data.deleted.permanent);

    AdjacentEnvelope adjacent;
    adjacent.event.kind = EventKind.recordCreated;
    adjacent.event.data.created = CreatedEvent(23, "adjacent");
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, adjacent);
    assert(error.ok);
    assert(encoded ==
            "event = { event_type = \"record_created\", event_data = { " ~
            "id = 23, displayName = \"adjacent\" } }");

    Deserialized!AdjacentEnvelope decodedAdjacent;
    scope (exit)
        decodedAdjacent.deinit();
    error = readToml(
        "event = { event_data = { id = 23, displayName = \"adjacent\" }, " ~
            "event_type = \"record_created\" }",
        mallocAllocator(), &decodedAdjacent);
    assert(error.ok);
    assert(decodedAdjacent.value.event.kind == EventKind.recordCreated);
    assert(decodedAdjacent.value.event.data.created.id == 23);

    error = readToml(
        "event = { event_type = \"missing\", event_data = {} }",
        mallocAllocator(), &decodedAdjacent);
    assert(error.kind == SerdeErrorKind.unknownVariant);
    assert(decodedAdjacent.empty);

    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, adjacent.event);
    assert(error.ok);
    assert(encoded ==
            "event_type = \"record_created\"\n" ~
            "event_data = { id = 23, displayName = \"adjacent\" }");
    Deserialized!AdjacentEvent rootAdjacent;
    scope (exit)
        rootAdjacent.deinit();
    error = readToml(
        "event_data = { id = 23, displayName = \"adjacent\" }\n" ~
            "event_type = \"record_created\"\n",
        mallocAllocator(), &rootAdjacent);
    assert(error.ok);
    assert(rootAdjacent.value.data.created.id == 23);

    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, external.event);
    assert(error.ok);
    Deserialized!ExternalEvent rootExternal;
    scope (exit)
        rootExternal.deinit();
    error = readToml(encoded.view, mallocAllocator(), &rootExternal);
    assert(error.ok);
    assert(rootExternal.value.data.created.id == 17);

    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, internal.event);
    assert(error.ok);
    Deserialized!InternalEvent rootInternal;
    scope (exit)
        rootInternal.deinit();
    error = readToml(encoded.view, mallocAllocator(), &rootInternal);
    assert(error.ok);
    assert(rootInternal.value.data.deleted.id == 9);
    encoded.deinit();
}

private void testJsonRoundTrip() nothrow @nogc
{
    int[3] ports = [80, 443, 8080];
    Settings settings;
    settings.apiVersion = 3;
    settings.active = true;
    settings.identity.displayName = "Ada \"L\"";
    settings.identity.userID = 42;
    settings.mode = Mode.verbose;
    settings.ports = ports[];
    settings.pair = [7, 9];

    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    JsonWriteOptions writeOptions;
    writeOptions.pretty = true;
    SerdeError error = writeJson(writer, settings, writeOptions);
    assert(error.ok);
    assert(encoded ==
            "{\n" ~
            "  \"api-version\": 3,\n" ~
            "  \"active\": true,\n" ~
            "  \"display_name\": \"Ada \\\"L\\\"\",\n" ~
            "  \"user_id\": 42,\n" ~
            "  \"mode\": \"verbose\",\n" ~
            "  \"ports\": [\n" ~
            "    80,\n" ~
            "    443,\n" ~
            "    8080\n" ~
            "  ],\n" ~
            "  \"pair\": [\n" ~
            "    7,\n" ~
            "    9\n" ~
            "  ]\n" ~
            "}");

    Deserialized!Settings decoded;
    scope (exit)
        decoded.deinit();
    error = readJson(encoded.view, mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.apiVersion == 3);
    assert(decoded.value.active);
    assert(decoded.value.identity.displayName.equal("Ada \"L\""));
    assert(decoded.value.identity.userID == 42);
    assert(decoded.value.mode == Mode.verbose);
    assert(decoded.value.ports.length == 3);
    assert(decoded.value.ports[2] == 8080);
    assert(decoded.value.pair == [7, 9]);
    encoded.deinit();
}

private void testJsonPolicies() nothrow @nogc
{
    Deserialized!Settings decoded;
    scope (exit)
        decoded.deinit();
    SerdeError error = readJson(
        "{\"api-version\":1,\"enabled\":true,\"display_name\":\"x\"," ~
            "\"user_id\":1,\"mode\":\"quiet\",\"ports\":[],\"pair\":[1,2]}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.ok);
    assert(decoded.value.active);

    error = readJson(
        "{\"api-version\":1,\"display_name\":\"x\",\"display_name\":\"y\"}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.kind == SerdeErrorKind.duplicateField);
    assert(decoded.empty);

    error = readJson("{\"api-version\":1}", mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.missingRequiredField);

    error = readJson(
        "{\"api-version\":1,\"display_name\":\"x\",\"mystery\":1}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.kind == SerdeErrorKind.unknownField);

    JsonReadOptions options;
    options.limits.ignoreUnknownFields = true;
    error = readJson(
        "{\"api-version\":1,\"display_name\":\"x\",\"unknown\":[1,{\"x\":2}]}",
        mallocAllocator(),
        &decoded,
        options,
    );
    assert(error.ok);
    assert(decoded.value.identity.displayName.equal("x"));
}

private void testJsonUnicodeAndNumbers() nothrow @nogc
{
    OptionalDocument document;
    Deserialized!OptionalDocument decoded;
    scope (exit)
        decoded.deinit();
    SerdeError error = readJson(
        "{\"child\":{\"label\":\"A\\u00df\\u6771\\ud834\\udd1e\",\"value\":-2147483648}}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.ok);
    assert(decoded.value.child !is null);
    assert(decoded.value.child.label.equal("Aß東𝄞"));
    assert(decoded.value.child.value == int.min);

    error = readJson("{\"child\":{\"label\":\"\\ud800\"}}",
        mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.invalidEscape);
    assert(decoded.empty);

    error = readJson("{\"child\":{\"label\":\"x\",\"value\":2147483648}}",
        mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.numberOutOfRange);

    error = readJson("{\"child\":null}", mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.child is null);

    enum invalidPrefix = "{\"child\":{\"label\":\"";
    enum invalidSuffix = "\"}}";
    char[invalidPrefix.length + 1 + invalidSuffix.length] invalidJson;
    invalidJson[0 .. invalidPrefix.length] = invalidPrefix;
    invalidJson[invalidPrefix.length] = cast(char) 0xff;
    invalidJson[invalidPrefix.length + 1 .. $] = invalidSuffix;
    error = readJson(invalidJson[], mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.invalidUtf8);
    assert(error.offset == invalidPrefix.length);
    document.child = null;
}

private void testJsonCasingAndOutputFailure() nothrow @nogc
{
    CasingDocument value = CasingDocument(7, 9);
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    JsonWriteOptions options;
    options.keyCase = KeyCase.snake;
    SerdeError error = writeJson(writer, value, options);
    assert(error.ok);
    assert(encoded == "{\"http_server_id\":7,\"fixed-key\":9}");

    Deserialized!CasingDocument decoded;
    scope (exit)
        decoded.deinit();
    JsonReadOptions readOptions;
    readOptions.keyCase = KeyCase.snake;
    error = readJson(encoded.view, mallocAllocator(), &decoded, readOptions);
    assert(error.ok);
    assert(decoded.value.httpServerID == 7);

    Writer failed = Writer.fromSink(&failingSink, null);
    error = writeJson(failed, value, options);
    assert(error.kind == SerdeErrorKind.outputFailure);

    DefaultsDocument defaults;
    StringBuf omitted = StringBuf.create(mallocAllocator());
    Writer omittedWriter = Writer.fromSink(&bufferSink, &omitted);
    error = writeJson(omittedWriter, defaults);
    assert(error.ok);
    assert(omitted == "{\"enabled\":false}");
    defaults.retryCount = 0;
    omitted.clear();
    omittedWriter = Writer.fromSink(&bufferSink, &omitted);
    error = writeJson(omittedWriter, defaults);
    assert(error.ok);
    assert(omitted == "{\"retryCount\":0,\"enabled\":false}");
    omitted.deinit();
    encoded.deinit();
}

private void testJsonAllocationFailures() nothrow @nogc
{
    enum input = "{\"child\":{\"label\":\"allocated\",\"value\":7}}";
    bool reachedSuccess;
    foreach (allowed; 0 .. 8)
    {
        AllocationRecord[16] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Deserialized!OptionalDocument decoded;
        SerdeError error = readJson(input, allocator.allocator, &decoded);
        if (error.ok)
        {
            assert(decoded.value.child.label.equal("allocated"));
            decoded.deinit();
            reachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(decoded.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);

    AllocationRecord[8] defaultRecords;
    InstrumentedAllocator defaultAllocator = InstrumentedAllocator.create(
        mallocAllocator(), defaultRecords[]);
    Deserialized!StaticInitializer initialized;
    SerdeError error = readJson("{}", defaultAllocator.allocator, &initialized);
    assert(error.ok);
    assert(initialized.value.text.equal("static storage"));
    initialized.deinit();
    assert(defaultAllocator.clean);
    assert(defaultAllocator.stats.invalidCalls == 0);

    Deserialized!AlignedDocument aligned;
    error = readJson("{\"value\":7}", defaultAllocator.allocator, &aligned);
    assert(error.ok);
    assert((cast(size_t) aligned.pointer & 63) == 0);
    aligned.deinit();
    assert(defaultAllocator.clean);
}

private void testJsonOptions() nothrow @nogc
{
    Deserialized!OptionalValues decoded;
    scope (exit)
        decoded.deinit();
    SerdeError error = readJson(
        "{\"title\":\"deploy\",\"priority\":null," ~
            "\"child\":{\"label\":\"worker\",\"value\":7}," ~
            "\"explicit_toggle\":false}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.ok);
    assert(decoded.value.title.isSome);
    assert(decoded.value.title.value.equal("deploy"));
    assert(decoded.value.priority.isNone);
    assert(decoded.value.child.isSome);
    assert(decoded.value.child.value.label.equal("worker"));
    assert(decoded.value.child.value.value == 7);
    assert(decoded.value.explicitToggle.isSome);
    assert(!decoded.value.explicitToggle.value);

    // A required option requires the key, not a non-null JSON value.
    error = readJson("{\"explicit_toggle\":null}", mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.explicitToggle.isNone);
    error = readJson("{}", mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.missingRequiredField);

    OptionalValues value;
    value.title = Option!String.some("release");
    value.priority = some(4);
    value.explicitToggle = some(true);
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, value);
    assert(error.ok);
    assert(encoded ==
            "{\"title\":\"release\",\"priority\":4,\"child\":null," ~
            "\"explicit_toggle\":true}");
    encoded.deinit();
}

private void testTomlRoundTrip() nothrow @nogc
{
    Server[2] servers = [
        Server("primary", true),
        Server("backup", false),
    ];
    TomlDocument document;
    document.applicationName = "demo";
    document.database = Database("db.local", 5432);
    document.servers = servers[];
    document.ratio = 0.125;

    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = writeToml(writer, document);
    assert(error.ok);
    assert(encoded ==
            "application_name = \"demo\"\n" ~
            "database = { hostName = \"db.local\", port = 5432 }\n" ~
            "servers = [{ name = \"primary\", enabled = true }, " ~
            "{ name = \"backup\", enabled = false }]\n" ~
            "ratio = 0.125");

    Deserialized!TomlDocument decoded;
    scope (exit)
        decoded.deinit();
    error = readToml(encoded.view, mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.applicationName.equal("demo"));
    assert(decoded.value.database.hostName.equal("db.local"));
    assert(decoded.value.database.port == 5432);
    assert(decoded.value.servers.length == 2);
    assert(decoded.value.servers[1].name.equal("backup"));
    assert(!decoded.value.servers[1].enabled);
    assert(decoded.value.ratio == 0.125);

    enum invalidPrefix = "application_name = \"";
    char[invalidPrefix.length + 2] invalidToml;
    invalidToml[0 .. invalidPrefix.length] = invalidPrefix;
    invalidToml[invalidPrefix.length] = cast(char) 0xff;
    invalidToml[$ - 1] = '"';
    error = readToml(invalidToml[], mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.invalidUtf8);
    assert(error.offset == invalidPrefix.length);
    encoded.deinit();
}

private void testTomlTablesAndSyntax() nothrow @nogc
{
    enum input =
        "# application settings\n" ~
        "application_name = 'table demo'\n" ~
        "servers = [ { name = \"one\", enabled = true }, ]\n" ~
        "ratio = +1_2.5e-1\n" ~
        "\n" ~
        "[database]\n" ~
        "hostName = \"localhost\\u002einternal\"\n" ~
        "port = 0x1538 # 5432\n";
    Deserialized!TomlDocument decoded;
    scope (exit)
        decoded.deinit();
    SerdeError error = readToml(input, mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.applicationName.equal("table demo"));
    assert(decoded.value.database.hostName.equal("localhost.internal"));
    assert(decoded.value.database.port == 5432);
    assert(decoded.value.servers.length == 1);
    assert(decoded.value.ratio == 1.25);

    error = readToml(
        "application_name = \"x\"\napplication_name = \"y\"\n",
        mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.duplicateField);

    error = readToml("ratio = 2026-08-01\n", mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.unsupportedValue);

    error = readToml("[[database]]\nhost_name = \"x\"\n",
        mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.unsupportedValue);

    Deserialized!OptionalDocument optional;
    scope (exit)
        optional.deinit();
    error = readToml("[child]\nlabel = \"nested\"\nvalue = 17\n",
        mallocAllocator(), &optional);
    assert(error.ok);
    assert(optional.value.child !is null);
    assert(optional.value.child.label.equal("nested"));
    assert(optional.value.child.value == 17);
}

private void testTomlAllocationFailures() nothrow @nogc
{
    enum input =
        "application_name = \"allocated\"\n" ~
        "database = { hostName = \"host\", port = 1 }\n" ~
        "servers = [{ name = \"server\", enabled = true }]\n" ~
        "ratio = 1.0\n";
    bool reachedSuccess;
    foreach (allowed; 0 .. 16)
    {
        AllocationRecord[32] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Deserialized!TomlDocument decoded;
        SerdeError error = readToml(input, allocator.allocator, &decoded);
        if (error.ok)
        {
            decoded.deinit();
            reachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(decoded.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);
}

private void testTomlOptions() nothrow @nogc
{
    enum input =
        "title = \"deploy\"\n" ~
        "explicit_toggle = false\n" ~
        "\n" ~
        "[child]\n" ~
        "label = \"worker\"\n" ~
        "value = 7\n";
    Deserialized!OptionalValues decoded;
    scope (exit)
        decoded.deinit();
    SerdeError error = readToml(input, mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.title.isSome);
    assert(decoded.value.title.value.equal("deploy"));
    assert(decoded.value.priority.isNone);
    assert(decoded.value.child.isSome);
    assert(decoded.value.child.value.label.equal("worker"));
    assert(decoded.value.child.value.value == 7);
    assert(decoded.value.explicitToggle.isSome);
    assert(!decoded.value.explicitToggle.value);

    OptionalValues value;
    value.priority = some(4);
    value.explicitToggle = some(true);
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, value);
    assert(error.ok);
    assert(encoded == "priority = 4\nexplicit_toggle = true");

    error = readToml("priority = 1\n", mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.missingRequiredField);
    encoded.deinit();
}

private void testOwnedOptionsAndFailures() nothrow @nogc
{
    enum jsonInput =
        "{\"title\":null,\"endpoint\":{\"host_name\":\"api.internal\"," ~
        "\"port\":8443,\"labels\":[\"tls\"]},\"revision\":3," ~
        "\"explicit_toggle\":true}";
    enum tomlInput =
        "title = \"scheduler\"\n" ~
        "explicit_toggle = true\n" ~
        "\n" ~
        "[endpoint]\n" ~
        "host_name = \"jobs.internal\"\n" ~
        "port = 7000\n" ~
        "labels = [\"stable\"]\n";

    AllocationRecord[128] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(), records[]);
    {
        OwnedOptionalValues value;
        SerdeError error = readJson(jsonInput, allocator.allocator, &value);
        assert(error.ok);
        assert(value.title.isNone);
        assert(value.endpoint.isSome);
        assert(value.endpoint.value.hostName == "api.internal");
        assert(value.endpoint.value.labels[0] == "tls");
        assert(value.revision.value == 3);

        StringBuf title = StringBuf.fromString(allocator.allocator, "release");
        value.title = some(move(title));
        value.endpoint.value.hostName.append(".test");

        StringBuf encoded = StringBuf.create(allocator.allocator);
        Writer writer = Writer.fromSink(&bufferSink, &encoded);
        error = writeJson(writer, value);
        assert(error.ok);
        assert(encoded ==
                "{\"title\":\"release\",\"endpoint\":{" ~
                "\"host_name\":\"api.internal.test\",\"port\":8443," ~
                "\"labels\":[\"tls\"]},\"revision\":3," ~
                "\"explicit_toggle\":true}");

        error = readToml(tomlInput, allocator.allocator, &value);
        assert(error.ok);
        assert(value.title.value == "scheduler");
        assert(value.endpoint.isSome);
        assert(value.endpoint.value.hostName == "jobs.internal");
        assert(value.endpoint.value.labels[0] == "stable");
        assert(value.revision.isNone);
        encoded.deinit();
        deinitOwnedOptionalValues(value);
    }
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);

    bool reachedSuccess;
    foreach (allowed; 0 .. 24)
    {
        AllocationRecord[128] failureRecords;
        InstrumentedAllocator failureAllocator = InstrumentedAllocator.create(
            mallocAllocator(), failureRecords[]);
        failureAllocator.failAfter(allowed);
        {
            OwnedOptionalValues value;
            SerdeError error = readJson(jsonInput, failureAllocator.allocator, &value);
            if (error.ok)
            {
                deinitOwnedOptionalValues(value);
                reachedSuccess = true;
            }
            else
                assert(error.kind == SerdeErrorKind.allocationFailure);
        }
        assert(failureAllocator.clean);
        assert(failureAllocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);
}

private void testOwnedJsonRoundTripAndMutation() nothrow @nogc
{
    enum input =
        "{\"application_name\":\"control plane\"," ~
        "\"primary_endpoint\":{\"host_name\":\"api.internal\"," ~
        "\"port\":8443,\"labels\":[\"primary\",\"tls\"]}," ~
        "\"replica_endpoints\":[" ~
        "{\"host_name\":\"api-1.internal\",\"port\":8443,\"labels\":[]}," ~
        "{\"host_name\":\"api-2.internal\",\"port\":9443," ~
        "\"labels\":[\"canary\"]}]," ~
        "\"feature_flags\":[\"audit\",\"metrics\"]," ~
        "\"retry_delays\":[1,5,30],\"tracing_enabled\":true}";

    OwnedDocument document;
    SerdeError error = readJson(input, mallocAllocator(), &document);
    assert(error.ok);
    assert(document.applicationName == "control plane");
    assert(document.primaryEndpoint.hostName == "api.internal");
    assert(document.primaryEndpoint.labels.length == 2);
    assert(document.replicaEndpoints.length == 2);
    assert(document.replicaEndpoints[1].hostName == "api-2.internal");
    assert(document.featureFlags[0] == "audit");

    document.applicationName.clear();
    document.applicationName.append("edge plane");
    document.primaryEndpoint.hostName.append(".test");
    document.featureFlags[1].clear();
    document.featureFlags[1].append("telemetry");
    StringBuf addedFlag = StringBuf.fromString(mallocAllocator(), "compression");
    document.featureFlags.append(move(addedFlag));
    document.retryDelays[2] = 60;
    document.tracingEnabled = false;

    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, document);
    assert(error.ok);
    assert(encoded ==
            "{\"application_name\":\"edge plane\"," ~
            "\"primary_endpoint\":{\"host_name\":\"api.internal.test\"," ~
            "\"port\":8443,\"labels\":[\"primary\",\"tls\"]}," ~
            "\"replica_endpoints\":[" ~
            "{\"host_name\":\"api-1.internal\",\"port\":8443,\"labels\":[]}," ~
            "{\"host_name\":\"api-2.internal\",\"port\":9443," ~
            "\"labels\":[\"canary\"]}]," ~
            "\"feature_flags\":[\"audit\",\"telemetry\",\"compression\"]," ~
            "\"retry_delays\":[1,5,60]}");
    encoded.deinit();
    deinitValue(document);
}

private void testOwnedTomlRoundTripAndReplacement() nothrow @nogc
{
    enum first =
        "application_name = \"scheduler\"\n" ~
        "primary_endpoint = { host_name = \"jobs.internal\", port = 7000, " ~
        "labels = [\"stable\"] }\n" ~
        "replica_endpoints = [{ host_name = \"jobs-1.internal\", " ~
        "port = 7001, labels = [\"backup\"] }]\n" ~
        "feature_flags = [\"fair_queue\"]\n" ~
        "retry_delays = [2, 10, 45]\n";
    enum replacement =
        "application_name = \"worker\"\n" ~
        "primary_endpoint = { host_name = \"worker.internal\", port = 9000, " ~
        "labels = [] }\n" ~
        "replica_endpoints = []\n" ~
        "feature_flags = [\"batch\", \"priority\"]\n" ~
        "retry_delays = [1, 3, 9]\n" ~
        "tracing_enabled = true\n";

    OwnedDocument document;
    SerdeError error = readToml(first, mallocAllocator(), &document);
    assert(error.ok);
    assert(document.applicationName == "scheduler");
    assert(document.replicaEndpoints.length == 1);

    error = readToml(replacement, mallocAllocator(), &document);
    assert(error.ok);
    assert(document.applicationName == "worker");
    assert(document.primaryEndpoint.hostName == "worker.internal");
    assert(document.replicaEndpoints.empty);
    assert(document.featureFlags.length == 2);
    assert(document.tracingEnabled);

    document.featureFlags[0].append("-v2");
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, document);
    assert(error.ok);
    assert(encoded ==
            "application_name = \"worker\"\n" ~
            "primary_endpoint = { host_name = \"worker.internal\", port = 9000, " ~
            "labels = [] }\n" ~
            "replica_endpoints = []\n" ~
            "feature_flags = [\"batch-v2\", \"priority\"]\n" ~
            "retry_delays = [1, 3, 9]\n" ~
            "tracing_enabled = true");
    encoded.deinit();
    deinitValue(document);
}

private void testOwnedDecodeIsTransactional() nothrow @nogc
{
    AllocationRecord[128] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(), records[]);
    OwnedDocument document;
    StringBuf preserved = StringBuf.fromString(allocator.allocator, "preserved");
    moveEmplace(preserved, document.applicationName);

    SerdeError error = readJson(
        "{\"application_name\":\"replacement\"," ~
            "\"primary_endpoint\":{\"host_name\":\"partial\"}," ~
            "\"replica_endpoints\":[{\"host_name\":7}]}",
        allocator.allocator,
        &document,
    );
    assert(error.kind == SerdeErrorKind.typeMismatch);
    assert(document.applicationName == "preserved");

    error = readToml(
        "application_name = \"replacement\"\n" ~
            "primary_endpoint = { host_name = \"partial\" }\n" ~
            "replica_endpoints = [7]\n",
        allocator.allocator,
        &document,
    );
    assert(error.kind == SerdeErrorKind.typeMismatch);
    assert(document.applicationName == "preserved");

    error = readJson(
        "{\"application_name\":\"replacement succeeded\"}",
        allocator.allocator,
        &document,
    );
    assert(error.ok);
    assert(document.applicationName == "replacement succeeded");
    assert(document.primaryEndpoint.hostName.allocator is allocator.allocator);
    assert(document.featureFlags.allocator is allocator.allocator);
    assert(document.description.allocator is allocator.allocator);
    assert(document.experiments.allocator is allocator.allocator);
    document.primaryEndpoint.hostName.append("initialized after decode");
    StringBuf lateFlag = StringBuf.fromString(allocator.allocator, "late");
    document.featureFlags.append(move(lateFlag));
    assert(document.primaryEndpoint.hostName ==
            "initialized after decode");
    assert(document.featureFlags[0] == "late");
    deinitValue(document);
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
}

private void testOwnedAllocationFailures() nothrow @nogc
{
    enum input =
        "{\"application_name\":\"owned\"," ~
        "\"primary_endpoint\":{\"host_name\":\"primary\",\"labels\":[\"a\"]}," ~
        "\"replica_endpoints\":[{\"host_name\":\"replica\"," ~
        "\"labels\":[\"b\"]}],\"feature_flags\":[\"one\",\"two\"]," ~
        "\"retry_delays\":[1,2,3]}";
    bool reachedSuccess;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        {
            OwnedDocument document;
            SerdeError error = readJson(input, allocator.allocator, &document);
            if (error.ok)
            {
                assert(document.applicationName == "owned");
                deinitValue(document);
                reachedSuccess = true;
            }
            else
                assert(error.kind == SerdeErrorKind.allocationFailure);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);

    enum tomlInput =
        "application_name = \"owned\"\n" ~
        "primary_endpoint = { host_name = \"primary\", labels = [\"a\"] }\n" ~
        "replica_endpoints = [{ host_name = \"replica\", labels = [\"b\"] }]\n" ~
        "feature_flags = [\"one\", \"two\"]\n" ~
        "retry_delays = [1, 2, 3]\n";
    reachedSuccess = false;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        {
            OwnedDocument document;
            SerdeError error = readToml(tomlInput, allocator.allocator, &document);
            if (error.ok)
            {
                assert(document.applicationName == "owned");
                deinitValue(document);
                reachedSuccess = true;
            }
            else
                assert(error.kind == SerdeErrorKind.allocationFailure);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);
}

private void testJsonTopLevelValues() nothrow @nogc
{
    int[3] fixedValues = [1, 2, 3];
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = writeJson(writer, fixedValues);
    assert(error.ok);
    assert(encoded == "[1,2,3]");

    int[] borrowedValues = fixedValues[];
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, borrowedValues);
    assert(error.ok);
    assert(encoded == "[1,2,3]");

    Deserialized!(TopLevelBorrowedItem[]) borrowedItems;
    error = readJson(
        "[{\"display_name\":\"alpha\",\"value\":1}," ~
            "{\"display_name\":\"beta\",\"value\":2}]",
        mallocAllocator(),
        &borrowedItems,
    );
    assert(error.ok);
    assert(borrowedItems.value.length == 2);
    assert(borrowedItems.value[0].displayName.equal("alpha"));
    assert(borrowedItems.value[1].value == 2);
    borrowedItems.deinit();

    Deserialized!(int[]) emptyValues;
    error = readJson("[]", mallocAllocator(), &emptyValues);
    assert(error.ok);
    assert(emptyValues.value.length == 0);
    emptyValues.deinit();

    JsonReadOptions limitedOptions;
    limitedOptions.limits.maxCollectionLength = 1;
    Deserialized!(int[]) limitedValues;
    scope (exit)
        limitedValues.deinit();
    error = readJson("[1,2]", mallocAllocator(), &limitedValues,
        limitedOptions);
    assert(error.kind == SerdeErrorKind.collectionLimit);
    assert(limitedValues.empty);

    int scalar;
    error = readJson("42", mallocAllocator(), &scalar);
    assert(error.ok);
    assert(scalar == 42);

    StringBuf text = StringBuf.create(mallocAllocator());
    error = readJson("\"root text\"", mallocAllocator(), &text);
    assert(error.ok);
    assert(text == "root text");

    int[3] decodedFixed = [9, 9, 9];
    error = readJson("[4,5,6]", mallocAllocator(), &decodedFixed);
    assert(error.ok);
    assert(decodedFixed == [4, 5, 6]);
    error = readJson("[7,8]", mallocAllocator(), &decodedFixed);
    assert(error.kind == SerdeErrorKind.typeMismatch);
    assert(decodedFixed == [4, 5, 6]);

    OwnedArray!TopLevelOwnedItem ownedItems;
    error = readJson(
        "[{\"display_name\":\"owned\",\"value\":7}]",
        mallocAllocator(),
        &ownedItems,
    );
    assert(error.ok);
    assert(ownedItems.length == 1);
    assert(ownedItems[0].displayName == "owned");
    assert(ownedItems[0].value == 7);
    error = readJson(
        "[{\"display_name\":8,\"value\":9}]",
        mallocAllocator(),
        &ownedItems,
    );
    assert(error.kind == SerdeErrorKind.typeMismatch);
    assert(ownedItems.length == 1);
    assert(ownedItems[0].displayName == "owned");
    assert(ownedItems[0].value == 7);

    bool reachedSuccess;
    foreach (allowed; 0 .. 12)
    {
        AllocationRecord[48] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Deserialized!(int[]) allocatedValues;
        error = readJson("[1,2,3]", allocator.allocator, &allocatedValues);
        if (error.ok)
        {
            assert(allocatedValues.value.length == 3);
            allocatedValues.deinit();
            reachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(allocatedValues.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);

    ownedItems.deinit();
    text.deinit();
    encoded.deinit();
}

private void testJsonHashMaps() nothrow @nogc
{
    HashMap!(String, int) source = HashMap!(String, int).create(
        mallocAllocator());
    assert(source.tryAdd("one", 1) == AddStatus.inserted);
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = writeJson(writer, source);
    assert(error.ok);
    assert(encoded == "{\"one\":1}");

    HashMap!(String, int) emptySource = HashMap!(String, int).create(
        mallocAllocator());
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, emptySource);
    assert(error.ok);
    assert(encoded == "{}");

    Deserialized!(HashMap!(String, int)) decoded;
    error = readJson("{}", mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.empty);
    decoded.deinit();

    error = readJson("{\"one\":1,\"two\":2,\"a\\tb\":3}",
        mallocAllocator(), &decoded);
    assert(error.ok);
    const one = decoded.value.find("one");
    const two = decoded.value.find("two");
    const escaped = decoded.value.find("a\tb");
    assert(one !is null && *one == 1);
    assert(two !is null && *two == 2);
    assert(escaped !is null && *escaped == 3);
    decoded.deinit();

    error = readJson("{\"same\":1,\"same\":2}", mallocAllocator(),
        &decoded);
    assert(error.kind == SerdeErrorKind.duplicateField);
    assert(decoded.empty);
    error = readJson("{\"same\":1,\"s\\u0061me\":2}",
        mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.duplicateField);
    assert(decoded.empty);

    JsonReadOptions limited;
    limited.limits.maxCollectionLength = 1;
    error = readJson("{\"one\":1,\"two\":2}", mallocAllocator(),
        &decoded, limited);
    assert(error.kind == SerdeErrorKind.collectionLimit);
    assert(decoded.empty);

    alias NestedMap = HashMap!(String, HashMap!(String, int));
    Deserialized!NestedMap nested;
    error = readJson("{\"outer\":{\"inner\":7}}", mallocAllocator(),
        &nested);
    assert(error.ok);
    const innerMap = nested.value.find("outer");
    assert(innerMap !is null);
    const innerValue = (*innerMap).find("inner");
    assert(innerValue !is null && *innerValue == 7);
    nested.deinit();

    Deserialized!(HashMap!(String, TopLevelBorrowedItem)) itemMap;
    error = readJson(
        "{\"item\":{\"display_name\":\"mapped\",\"value\":9}}",
        mallocAllocator(), &itemMap);
    assert(error.ok);
    const item = itemMap.value.find("item");
    assert(item !is null);
    assert(item.displayName.equal("mapped"));
    assert(item.value == 9);
    itemMap.deinit();

    Deserialized!HashMapContainers containers;
    error = readJson(
        "{\"values\":[{\"first\":1},{\"second\":2}]," ~
            "\"pointer\":{\"third\":3}}",
        mallocAllocator(), &containers);
    assert(error.ok);
    assert(containers.value.values.length == 2);
    const first = containers.value.values[0].find("first");
    const second = containers.value.values[1].find("second");
    const third = (*containers.value.pointer).find("third");
    assert(first !is null && *first == 1);
    assert(second !is null && *second == 2);
    assert(third !is null && *third == 3);
    containers.deinit();

    bool reachedContainerSuccess;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Deserialized!HashMapContainers allocatedContainers;
        error = readJson(
            "{\"values\":[{\"first\":1},{\"second\":2}]," ~
                "\"pointer\":{\"third\":3}}",
            allocator.allocator, &allocatedContainers);
        if (error.ok)
        {
            allocatedContainers.deinit();
            reachedContainerSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(allocatedContainers.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedContainerSuccess)
            break;
    }
    assert(reachedContainerSuccess);

    bool reachedSuccess;
    foreach (allowed; 0 .. 16)
    {
        AllocationRecord[64] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Deserialized!(HashMap!(String, int)) allocated;
        error = readJson("{\"one\":1,\"two\":2}", allocator.allocator,
            &allocated);
        if (error.ok)
        {
            allocated.deinit();
            reachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(allocated.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);

    emptySource.deinit();
    source.deinit();
    encoded.deinit();
}

private void testTomlHashMaps() nothrow @nogc
{
    HashMap!(String, int) source = HashMap!(String, int).create(
        mallocAllocator());
    assert(source.tryAdd("one", 1) == AddStatus.inserted);
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = writeToml(writer, source);
    assert(error.ok);
    assert(encoded == "one = 1");

    HashMap!(String, int) emptySource = HashMap!(String, int).create(
        mallocAllocator());
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, emptySource);
    assert(error.ok);
    assert(encoded.empty);

    Deserialized!(HashMap!(String, int)) decoded;
    error = readToml("", mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.empty);
    decoded.deinit();

    error = readToml("one = 1\n\"a.b\" = 2\n", mallocAllocator(),
        &decoded);
    assert(error.ok);
    const one = decoded.value.find("one");
    const dotted = decoded.value.find("a.b");
    assert(one !is null && *one == 1);
    assert(dotted !is null && *dotted == 2);
    decoded.deinit();

    error = readToml("same = 1\nsame = 2\n", mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.duplicateField);
    assert(decoded.empty);
    error = readToml("same = 1\n\"same\" = 2\n", mallocAllocator(),
        &decoded);
    assert(error.kind == SerdeErrorKind.duplicateField);
    assert(decoded.empty);

    TomlReadOptions limited;
    limited.limits.maxCollectionLength = 1;
    error = readToml("one = 1\ntwo = 2\n", mallocAllocator(), &decoded,
        limited);
    assert(error.kind == SerdeErrorKind.collectionLimit);
    assert(decoded.empty);
    error = readToml("[section]\nvalue = 1\n", mallocAllocator(),
        &decoded);
    assert(error.kind == SerdeErrorKind.unsupportedValue);
    assert(decoded.empty);

    HashMapDocument document;
    auto documentValues = HashMap!(String, int).create(mallocAllocator());
    moveEmplace(documentValues, document.values);
    assert(document.values.tryAdd("one", 1) == AddStatus.inserted);
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, document);
    assert(error.ok);
    assert(encoded == "values = { one = 1 }");

    Deserialized!HashMapDocument decodedDocument;
    error = readToml("values = { one = 1, \"a.b\" = 2 }",
        mallocAllocator(), &decodedDocument);
    assert(error.ok);
    const nestedOne = decodedDocument.value.values.find("one");
    const nestedDotted = decodedDocument.value.values.find("a.b");
    assert(nestedOne !is null && *nestedOne == 1);
    assert(nestedDotted !is null && *nestedDotted == 2);
    decodedDocument.deinit();

    Deserialized!(HashMap!(String, TopLevelBorrowedItem)) itemMap;
    error = readToml(
        "item = { display_name = \"mapped\", value = 9 }\n",
        mallocAllocator(), &itemMap);
    assert(error.ok);
    const item = itemMap.value.find("item");
    assert(item !is null);
    assert(item.displayName.equal("mapped"));
    assert(item.value == 9);
    itemMap.deinit();

    Deserialized!HashMapContainers containers;
    error = readToml(
        "values = [{ first = 1 }, { second = 2 }]\n" ~
            "pointer = { third = 3 }\n",
        mallocAllocator(), &containers);
    assert(error.ok);
    assert(containers.value.values.length == 2);
    const first = containers.value.values[0].find("first");
    const second = containers.value.values[1].find("second");
    const third = (*containers.value.pointer).find("third");
    assert(first !is null && *first == 1);
    assert(second !is null && *second == 2);
    assert(third !is null && *third == 3);
    containers.deinit();

    bool reachedContainerSuccess;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Deserialized!HashMapContainers allocatedContainers;
        error = readToml(
            "values = [{ first = 1 }, { second = 2 }]\n" ~
                "pointer = { third = 3 }\n",
            allocator.allocator, &allocatedContainers);
        if (error.ok)
        {
            allocatedContainers.deinit();
            reachedContainerSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(allocatedContainers.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedContainerSuccess)
            break;
    }
    assert(reachedContainerSuccess);

    bool reachedSuccess;
    foreach (allowed; 0 .. 16)
    {
        AllocationRecord[64] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Deserialized!(HashMap!(String, int)) allocated;
        error = readToml("one = 1\ntwo = 2\n", allocator.allocator,
            &allocated);
        if (error.ok)
        {
            allocated.deinit();
            reachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(allocated.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);

    document.values.deinit();
    emptySource.deinit();
    source.deinit();
    encoded.deinit();
}

private void testOwnedStringsAndStringHashMaps() nothrow @nogc
{
    static assert(is(StringViewHashMap!int == HashMap!(String, int)));

    OwnedString text;
    SerdeError error = readJson(
        "\"owned \\u03bb\"",
        mallocAllocator(),
        &text,
    );
    assert(error.ok);
    assert(text.view == "owned λ");

    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, text);
    assert(error.ok);
    assert(encoded == "\"owned λ\"");

    StringHashMap!int jsonMap;
    error = readJson(
        "{\"alpha\":1,\"a\\u0062\":2,\"\":3,\"λ\":4}",
        mallocAllocator(),
        &jsonMap,
    );
    assert(error.ok);
    const alpha = jsonMap.find("alpha");
    const ab = jsonMap.find("ab");
    const empty = jsonMap.find("");
    const lambda = jsonMap.find("λ");
    assert(alpha !is null && *alpha == 1);
    assert(ab !is null && *ab == 2);
    assert(empty !is null && *empty == 3);
    assert(lambda !is null && *lambda == 4);

    error = readJson(
        "{\"same\":1,\"s\\u0061me\":2}",
        mallocAllocator(),
        &jsonMap,
    );
    assert(error.kind == SerdeErrorKind.duplicateField);
    assert(jsonMap.length == 4);
    assert(jsonMap.find("alpha") !is null);

    StringHashMap!int singleJson = StringHashMap!int.create(
        mallocAllocator());
    assert(singleJson.add("one", 1));
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, singleJson);
    assert(error.ok);
    assert(encoded == "{\"one\":1}");

    StringHashMap!int tomlMap;
    error = readToml(
        "alpha = 1\n\"a.b\" = 2\n\"\" = 3\n\"λ\" = 4\n",
        mallocAllocator(),
        &tomlMap,
    );
    assert(error.ok);
    const tomlAlpha = tomlMap.find("alpha");
    const dotted = tomlMap.find("a.b");
    const tomlEmpty = tomlMap.find("");
    const tomlLambda = tomlMap.find("λ");
    assert(tomlAlpha !is null && *tomlAlpha == 1);
    assert(dotted !is null && *dotted == 2);
    assert(tomlEmpty !is null && *tomlEmpty == 3);
    assert(tomlLambda !is null && *tomlLambda == 4);

    error = readToml(
        "same = 1\n\"same\" = 2\n",
        mallocAllocator(),
        &tomlMap,
    );
    assert(error.kind == SerdeErrorKind.duplicateField);
    assert(tomlMap.length == 4);
    assert(tomlMap.find("a.b") !is null);

    StringHashMap!int singleToml = StringHashMap!int.create(
        mallocAllocator());
    assert(singleToml.add("one", 1));
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, singleToml);
    assert(error.ok);
    assert(encoded == "one = 1");

    OwnedStringMapDocument nestedJson;
    error = readJson(
        "{\"values\":{\"name\":\"value\"}}",
        mallocAllocator(),
        &nestedJson,
    );
    assert(error.ok);
    const nestedJsonValue = nestedJson.values.find("name");
    assert(nestedJsonValue !is null);
    assert(nestedJsonValue.view == "value");

    OwnedStringMapDocument nestedToml;
    error = readToml(
        "values = { name = \"value\" }\n",
        mallocAllocator(),
        &nestedToml,
    );
    assert(error.ok);
    const nestedTomlValue = nestedToml.values.find("name");
    assert(nestedTomlValue !is null);
    assert(nestedTomlValue.view == "value");

    bool jsonReachedSuccess;
    foreach (allowed; 0 .. 24)
    {
        AllocationRecord[96] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        StringHashMap!int allocated;
        error = readJson(
            "{\"one\":1,\"two\":2}",
            allocator.allocator,
            &allocated,
        );
        if (error.ok)
        {
            assert(allocated.length == 2);
            allocated.deinit();
            jsonReachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (jsonReachedSuccess)
            break;
    }
    assert(jsonReachedSuccess);

    bool tomlReachedSuccess;
    foreach (allowed; 0 .. 24)
    {
        AllocationRecord[96] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        StringHashMap!int allocated;
        error = readToml(
            "one = 1\ntwo = 2\n",
            allocator.allocator,
            &allocated,
        );
        if (error.ok)
        {
            assert(allocated.length == 2);
            allocated.deinit();
            tomlReachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (tomlReachedSuccess)
            break;
    }
    assert(tomlReachedSuccess);

    // Direct owned decoding must also clean a decoded value that could not be
    // inserted because the key was duplicated. The map only owns values after
    // successful insertion; retained locals remain the decoder's responsibility.
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        OwnedStringArrayMap allocated;
        error = readJson(
            "{\"same\":[1,2],\"same\":[3,4]}",
            allocator.allocator,
            &allocated,
        );
        assert(error.kind == SerdeErrorKind.duplicateField);
        assert(allocated.empty);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
    }

    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        OwnedStringArrayMap allocated;
        error = readToml(
            "same = [1, 2]\nsame = [3, 4]\n",
            allocator.allocator,
            &allocated,
        );
        assert(error.kind == SerdeErrorKind.duplicateField);
        assert(allocated.empty);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
    }

    bool ownedJsonReachedSuccess;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        OwnedStringArrayMap allocated;
        error = readJson(
            "{\"one\":[1,2,3],\"two\":[4,5,6]}",
            allocator.allocator,
            &allocated,
        );
        if (error.ok)
        {
            assert(allocated.length == 2);
            allocated.deinit();
            ownedJsonReachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(allocated.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (ownedJsonReachedSuccess)
            break;
    }
    assert(ownedJsonReachedSuccess);

    bool ownedTomlReachedSuccess;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        OwnedStringArrayMap allocated;
        error = readToml(
            "one = [1, 2, 3]\ntwo = [4, 5, 6]\n",
            allocator.allocator,
            &allocated,
        );
        if (error.ok)
        {
            assert(allocated.length == 2);
            allocated.deinit();
            ownedTomlReachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(allocated.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (ownedTomlReachedSuccess)
            break;
    }
    assert(ownedTomlReachedSuccess);

    nestedToml.values.deinit();
    nestedJson.values.deinit();
    singleToml.deinit();
    tomlMap.deinit();
    singleJson.deinit();
    jsonMap.deinit();
    encoded.deinit();
    text.deinit();
}

private alias DeepOwnedSerde = OwnedArray!(
    OwnedStringHashMap!(Option!(OwnedArray!OwnedString)),
);
private alias PartialOptionArray = OwnedArray!(Option!(OwnedArray!OwnedString));
private alias OwnedStringArrayHashMap = OwnedHashMap!(OwnedString, OwnedArray!int);

private struct PartialOwnedConfig
{
    OwnedString name;
    OwnedArray!OwnedString paths;
    Option!OwnedString description;
}

private struct TomlDeepOwnedDocument
{
    DeepOwnedSerde values;
}

private struct TomlOwnedStringOptionDocument
{
    Option!OwnedString value;
}

private struct OwnedHashMapDocument
{
    OwnedStringArrayHashMap values;
}

static assert(__traits(compiles, validateOwnedSchema!PartialOwnedConfig()));
static assert(__traits(compiles, validateOwnedSchema!TomlDeepOwnedDocument()));
static assert(__traits(compiles, validateOwnedSchema!OwnedHashMapDocument()));
static assert(!__traits(compiles, validateOwnedValue!(OwnedHashMap!(String, int))()));
static assert(!__traits(compiles, validateBorrowedValue!(HashMap!(OwnedString, int))()));
static assert(__traits(compiles,
        (Allocator* allocator, OwnedStringArrayHashMap* output) {
        readJson("{}", allocator, output);
        readToml("", allocator, output);
    }));
static assert(__traits(compiles,
        (ref Writer writer, ref OwnedStringArrayHashMap value) {
        writeJson(writer, value);
        writeToml(writer, value);
    }));

private void testSerdePartialOwnedConstruction() nothrow @nogc
{
    enum jsonInput =
        "{\"name\":\"config\",\"paths\":[\"one\",\"two\"]," ~
        "\"description\":\"details\"}";
    enum tomlInput =
        "name = \"config\"\n" ~
        "paths = [\"one\", \"two\"]\n" ~
        "description = \"details\"\n";

    bool jsonReachedSuccess;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        PartialOwnedConfig value;
        SerdeError error = readJson(jsonInput, allocator.allocator, &value);
        if (error.ok)
        {
            assert(value.name.view == "config");
            assert(value.paths.length == 2);
            assert(value.description.isSome);
            assert(value.description.value.view == "details");
            deinitValue(value);
            jsonReachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (jsonReachedSuccess)
            break;
    }
    assert(jsonReachedSuccess);

    bool tomlReachedSuccess;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        PartialOwnedConfig value;
        SerdeError error = readToml(tomlInput, allocator.allocator, &value);
        if (error.ok)
        {
            assert(value.name.view == "config");
            assert(value.paths.length == 2);
            assert(value.description.isSome);
            assert(value.description.value.view == "details");
            deinitValue(value);
            tomlReachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (tomlReachedSuccess)
            break;
    }
    assert(tomlReachedSuccess);
}

private void testSerdeOwnedStringOptionFailures() nothrow @nogc
{
    bool reachedSuccess;
    foreach (allowed; 0 .. 16)
    {
        AllocationRecord[64] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Option!OwnedString value;
        SerdeError error = readJson("\"payload\"", allocator.allocator, &value);
        if (error.ok)
        {
            assert(value.isSome);
            assert(value.value.view == "payload");
            value.deinit();
            reachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);

    foreach (input; ["null", "\"payload\""])
    {
        AllocationRecord[32] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        Option!OwnedString value;
        SerdeError error = readJson(input, allocator.allocator, &value);
        assert(error.ok);
        if (input[0] == 'n')
            assert(value.isNone);
        else
        {
            assert(value.isSome);
            assert(value.value.view == "payload");
        }
        value.deinit();
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
    }

    bool tomlReachedSuccess;
    foreach (allowed; 0 .. 16)
    {
        AllocationRecord[64] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        TomlOwnedStringOptionDocument value;
        SerdeError error = readToml(
            "value = \"payload\"\n",
            allocator.allocator,
            &value,
        );
        if (error.ok)
        {
            assert(value.value.isSome);
            assert(value.value.value.view == "payload");
            deinitValue(value);
            tomlReachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (tomlReachedSuccess)
            break;
    }
    assert(tomlReachedSuccess);
}

private void testSerdeOwnedMapFailureInjection() nothrow @nogc
{
    enum stringMapJson =
        "{\"one\":\"1\",\"two\":\"2\",\"three\":\"3\"," ~
        "\"four\":\"4\",\"five\":\"5\",\"six\":\"6\"," ~
        "\"seven\":\"7\",\"eight\":\"8\",\"nine\":\"9\"," ~
        "\"ten\":\"10\",\"eleven\":\"11\",\"twelve\":\"12\"}";
    enum stringMapToml =
        "one = \"1\"\ntwo = \"2\"\nthree = \"3\"\nfour = \"4\"\n" ~
        "five = \"5\"\nsix = \"6\"\nseven = \"7\"\neight = \"8\"\n" ~
        "nine = \"9\"\nten = \"10\"\neleven = \"11\"\ntwelve = \"12\"\n";

    bool jsonReachedSuccess;
    foreach (allowed; 0 .. 96)
    {
        AllocationRecord[512] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        OwnedStringHashMap!OwnedString value;
        SerdeError error = readJson(stringMapJson, allocator.allocator, &value);
        if (error.ok)
        {
            assert(value.length == 12);
            value.deinit();
            jsonReachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (jsonReachedSuccess)
            break;
    }
    assert(jsonReachedSuccess);

    bool tomlReachedSuccess;
    foreach (allowed; 0 .. 96)
    {
        AllocationRecord[512] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        OwnedStringHashMap!OwnedString value;
        SerdeError error = readToml(stringMapToml, allocator.allocator, &value);
        if (error.ok)
        {
            assert(value.length == 12);
            value.deinit();
            tomlReachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (tomlReachedSuccess)
            break;
    }
    assert(tomlReachedSuccess);

    foreach (json; [true, false])
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        OwnedStringHashMap!OwnedString value;
        SerdeError error = json
            ? readJson(
                "{\"same\":\"first\",\"same\":\"second\"}",
                allocator.allocator,
                &value,
            ) : readToml(
                "same = \"first\"\nsame = \"second\"\n",
                allocator.allocator,
                &value,
            );
        assert(error.kind == SerdeErrorKind.duplicateField);
        assert(value.empty);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
    }
}

private void testSerdeOwnedHashMap() nothrow @nogc
{
    enum jsonInput =
        "{\"one\":[1,2,3],\"two\":[4,5],\"three\":[6]," ~
        "\"four\":[7,8],\"five\":[9],\"six\":[10,11]," ~
        "\"seven\":[12],\"eight\":[13],\"nine\":[14],\"ten\":[15]}";
    enum tomlInput =
        "one = [1, 2, 3]\ntwo = [4, 5]\nthree = [6]\n" ~
        "four = [7, 8]\nfive = [9]\nsix = [10, 11]\n" ~
        "seven = [12]\neight = [13]\nnine = [14]\nten = [15]\n";

    bool jsonReachedSuccess;
    foreach (allowed; 0 .. 96)
    {
        AllocationRecord[512] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        OwnedStringArrayHashMap value;
        SerdeError error = readJson(jsonInput, allocator.allocator, &value);
        if (error.ok)
        {
            assert(value.length == 10);
            auto items = value.pointerItems();
            while (!items.empty)
            {
                assert(!items.front.key.empty);
                assert(!items.front.value.empty);
                items.popFront();
            }
            value.deinit();
            jsonReachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(value.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (jsonReachedSuccess)
            break;
    }
    assert(jsonReachedSuccess);

    bool tomlReachedSuccess;
    foreach (allowed; 0 .. 96)
    {
        AllocationRecord[512] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        OwnedStringArrayHashMap value;
        SerdeError error = readToml(tomlInput, allocator.allocator, &value);
        if (error.ok)
        {
            assert(value.length == 10);
            value.deinit();
            tomlReachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(value.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (tomlReachedSuccess)
            break;
    }
    assert(tomlReachedSuccess);

    foreach (json; [true, false])
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        OwnedStringArrayHashMap value;
        SerdeError error = json
            ? readJson(
                "{\"same\":[1],\"same\":[2]}",
                allocator.allocator,
                &value,
            ) : readToml(
                "same = [1]\nsame = [2]\n",
                allocator.allocator,
                &value,
            );
        assert(error.kind == SerdeErrorKind.duplicateField);
        assert(value.empty);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
    }

    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        OwnedStringArrayHashMap preserved = OwnedStringArrayHashMap.create(
            allocator.allocator);
        OwnedString key = OwnedString.fromString(allocator.allocator, "preserved");
        OwnedArray!int value = OwnedArray!int.fromSlice(
            allocator.allocator,
            [42],
        );
        assert(preserved.tryAdd(&key, &value) == AddStatus.inserted);
        allocator.failAfter(0);
        SerdeError error = readJson(
            "{\"replacement\":[1,2,3]}",
            allocator.allocator,
            &preserved,
        );
        assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(preserved.length == 1);
        preserved.deinit();
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
    }

    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        OwnedHashMapDocument document;
        SerdeError error = readToml(
            "values = { alpha = [1, 2], beta = [3] }\n",
            allocator.allocator,
            &document,
        );
        assert(error.ok);
        assert(document.values.length == 2);
        StringBuf encoded = StringBuf.create(allocator.allocator);
        Writer writer = Writer.fromSink(&bufferSink, &encoded);
        error = writeToml(writer, document);
        assert(error.ok);
        encoded.deinit();
        deinitValue(document);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
    }

    AllocationRecord[128] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(), records[]);
    OwnedStringArrayHashMap roundTrip;
    SerdeError error = readJson(
        "{\"alpha\":[1,2],\"beta\":[3]}",
        allocator.allocator,
        &roundTrip,
    );
    assert(error.ok);
    StringBuf encoded = StringBuf.create(allocator.allocator);
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, roundTrip);
    assert(error.ok);
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, roundTrip);
    assert(error.ok);
    encoded.deinit();
    roundTrip.deinit();
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
}

private void testSerdeDeepOwnedFailureInjection() nothrow @nogc
{
    enum jsonInput =
        "[{\"first\":[\"a\",\"b\"],\"none\":null}," ~
        "{\"second\":[\"c\",\"d\"]}]";
    bool reachedSuccess;
    foreach (allowed; 0 .. 128)
    {
        AllocationRecord[512] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        DeepOwnedSerde value;
        SerdeError error = readJson(jsonInput, allocator.allocator, &value);
        if (error.ok)
        {
            assert(value.length == 2);
            value.deinit();
            reachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);

    // This shape puts an owner-bearing Option directly inside an OwnedArray,
    // rather than behind a map insertion temporary.
    reachedSuccess = false;
    foreach (allowed; 0 .. 64)
    {
        AllocationRecord[256] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        PartialOptionArray value;
        SerdeError error = readJson(
            "[[\"a\",\"b\"],[\"c\",\"d\"]]",
            allocator.allocator,
            &value,
        );
        if (error.ok)
        {
            value.deinit();
            reachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);

    enum tomlInput =
        "values = [{ first = [\"a\", \"b\"] }, " ~
        "{ second = [\"c\", \"d\"] }]\n";
    reachedSuccess = false;
    foreach (allowed; 0 .. 128)
    {
        AllocationRecord[512] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        TomlDeepOwnedDocument value;
        SerdeError error = readToml(tomlInput, allocator.allocator, &value);
        if (error.ok)
        {
            assert(value.values.length == 2);
            deinitValue(value);
            reachedSuccess = true;
        }
        else
            assert(error.kind == SerdeErrorKind.allocationFailure);
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);
}

extern (C) int main()
{
    runSerdeBackendContracts();
    testSharedPolicies();
    testJsonTaggedUnions();
    testTomlTaggedUnions();
    testJsonRoundTrip();
    testJsonTopLevelValues();
    testJsonHashMaps();
    testJsonPolicies();
    testJsonUnicodeAndNumbers();
    testJsonCasingAndOutputFailure();
    testJsonAllocationFailures();
    testJsonOptions();
    testTomlRoundTrip();
    testTomlHashMaps();
    testTomlTablesAndSyntax();
    testTomlAllocationFailures();
    testTomlOptions();
    testOwnedJsonRoundTripAndMutation();
    testOwnedTomlRoundTripAndReplacement();
    testOwnedDecodeIsTransactional();
    testOwnedAllocationFailures();
    testOwnedOptionsAndFailures();
    testOwnedStringsAndStringHashMaps();
    testSerdePartialOwnedConstruction();
    testSerdeOwnedStringOptionFailures();
    testSerdeOwnedMapFailureInjection();
    testSerdeOwnedHashMap();
    testSerdeDeepOwnedFailureInjection();
    return 0;
}
