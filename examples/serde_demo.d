module examples.serde_demo;

import xtb.containers.array;
import xtb.memory : Allocator;
import xtb.lifetime : deinitValue = deinit, move, move_emplace;
import xtb.allocators.malloc : mallocAllocator;
import xtb.option : Option, some;
import xtb.fmt.writer : Writer;
import xtb.fmt.print : writeln;
import xtb.string;
import xtb.types : u8;
import xtb.serde : Deserialized, KeyCase, SerdeError, SerdeErrorKind, TagLayout,
    serdeAliasName, serdeCaseOf, serdeDiscriminant, serdeFieldCase, serdeIgnore, serdeOmitDefault, serdePayload,
    readJson, readToml, serdeRename, serdeRequired, serdeTaggedUnion, serdeVariantCase, serdeWith,
    writeJson, writeToml;

private enum Protocol
{
    http,
    https,
}

@serdeFieldCase(KeyCase.snake)
private struct Endpoint
{
    @serdeRequired StringBuf hostName;
    ushort port;
    Protocol protocol;
    OwnedArray!StringBuf labels;

    void deinit() nothrow @nogc
    {
        deinitValue(labels);
        deinitValue(hostName);
    }
}

@serdeFieldCase(KeyCase.snake)
private struct ServiceConfig
{
    @serdeRename("service") @serdeRequired StringBuf serviceName;
    @serdeAliasName("primary") Endpoint primaryEndpoint;
    OwnedArray!Endpoint replicaEndpoints;
    OwnedArray!StringBuf featureFlags;
    int[3] retryDelays;
    Option!StringBuf deploymentNote;
    Option!Endpoint fallbackEndpoint;
    @serdeOmitDefault bool tracingEnabled;
    @serdeIgnore uint runtimeRequests;

    void deinit() nothrow @nogc
    {
        deinitValue(fallbackEndpoint);
        deinitValue(deploymentNote);
        deinitValue(featureFlags);
        deinitValue(replicaEndpoints);
        deinitValue(primaryEndpoint);
        deinitValue(serviceName);
    }
}

@serdeFieldCase(KeyCase.snake)
private struct BorrowedReport
{
    @serdeRequired String reportName;
    int[] samples;
}

@serdeVariantCase(KeyCase.snake)
private enum ChangeKind
{
    serviceStarted,
    @serdeRename("stopped") @serdeAliasName("service_stopped") serviceStopped,
}

private struct StartedChange
{
    String service;
    ushort port;
}

private struct StoppedChange
{
    String service;
    int exitCode;
}

private union ChangePayload
{
    @serdeCaseOf(ChangeKind.serviceStarted) StartedChange started;
    @serdeCaseOf(ChangeKind.serviceStopped) StoppedChange stopped;
}

@serdeTaggedUnion(TagLayout.adjacent)
private struct ServiceChange
{
    @serdeDiscriminant @serdeRename("change_type") ChangeKind kind;
    @serdePayload @serdeRename("change") ChangePayload data;
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

private struct Health
{
    @serdeWith!PercentageSerde Percentage readiness;
}

private size_t appendSink(void* context, scope const(u8)[] bytes) nothrow @nogc
{
    StringBuf* output = cast(StringBuf*) context;
    (*output).append(bytes.asStringUnchecked);
    return bytes.length;
}

private bool writeFormats(scope const ref ServiceConfig config) nothrow @nogc
{
    StringBuf json = StringBuf.create(mallocAllocator());
    scope (exit)
        json.deinit();
    Writer jsonWriter = Writer.fromSink(&appendSink, &json);
    SerdeError error = writeJson(jsonWriter, config);
    if (!error.ok)
        return false;

    StringBuf toml = StringBuf.create(mallocAllocator());
    scope (exit)
        toml.deinit();
    Writer tomlWriter = Writer.fromSink(&appendSink, &toml);
    error = writeToml(tomlWriter, config);
    if (!error.ok)
        return false;

    writeln("mutated JSON:\n", json);
    writeln("mutated TOML:\n", toml);

    ServiceConfig fromToml;
    scope (exit)
        fromToml.deinit();
    error = readToml(toml.view, mallocAllocator(), &fromToml);
    if (!error.ok)
        return false;
    writeln("TOML round trip: ", fromToml.serviceName,
        ", replicas=", fromToml.replicaEndpoints.length,
        ", flags=", fromToml.featureFlags.length);
    return true;
}

private bool demonstrateOwningDecode() nothrow @nogc
{
    enum source =
        "{\n" ~
        "  \"service\": \"gateway\",\n" ~
        "  \"primary\": {\n" ~
        "    \"host_name\": \"api.internal\",\n" ~
        "    \"port\": 8443,\n" ~
        "    \"protocol\": \"https\",\n" ~
        "    \"labels\": [\"stable\", \"regional\"]\n" ~
        "  },\n" ~
        "  \"replica_endpoints\": [\n" ~
        "    {\"host_name\": \"api-1.internal\", \"port\": 8443, " ~
        "\"protocol\": \"https\", \"labels\": [\"backup\"]}\n" ~
        "  ],\n" ~
        "  \"feature_flags\": [\"audit\", \"metrics\"],\n" ~
        "  \"retry_delays\": [1, 5, 30],\n" ~
        "  \"deployment_note\": null,\n" ~
        "  \"tracing_enabled\": true\n" ~
        "}";

    Allocator* allocator = mallocAllocator();
    ServiceConfig config;
    SerdeError error = readJson(source, allocator, &config);
    if (!error.ok)
    {
        writeln("JSON decode failed at ", error.line, ":", error.column);
        return false;
    }
    scope (exit)
        config.deinit();

    writeln("parsed service: ", config.serviceName);
    writeln("primary: ", config.primaryEndpoint.hostName,
        ":", config.primaryEndpoint.port);

    config.serviceName.clear();
    config.serviceName.append("edge-gateway");
    config.primaryEndpoint.hostName.append(".test");
    config.retryDelays[2] = 60;
    config.tracingEnabled = false;
    ++config.runtimeRequests;

    writeln("optional deployment note present: ",
        config.deploymentNote.isSome);
    StringBuf deploymentNote = StringBuf.fromString(allocator,
        "promote after health checks");
    config.deploymentNote = some(move(deploymentNote));

    StringBuf feature = StringBuf.fromString(allocator, "compression");
    config.featureFlags.append(move(feature));

    Endpoint replica;
    StringBuf replicaHostName = StringBuf.fromString(allocator, "api-2.internal");
    move_emplace(replicaHostName, replica.hostName);
    replica.port = 9443;
    replica.protocol = Protocol.https;
    OwnedArray!StringBuf replicaLabels = OwnedArray!StringBuf.create(allocator);
    move_emplace(replicaLabels, replica.labels);
    StringBuf canary = StringBuf.fromString(allocator, "canary");
    replica.labels.append(move(canary));
    config.replicaEndpoints.append(move(replica));

    Endpoint fallback;
    StringBuf fallbackHostName = StringBuf.fromString(allocator, "fallback.internal");
    move_emplace(fallbackHostName, fallback.hostName);
    fallback.port = 443;
    fallback.protocol = Protocol.https;
    OwnedArray!StringBuf fallbackLabels = OwnedArray!StringBuf.create(allocator);
    move_emplace(fallbackLabels, fallback.labels);
    Option!Endpoint fallbackOption = some(move(fallback));
    move_emplace(fallbackOption, config.fallbackEndpoint);

    if (!writeFormats(config))
        return false;

    error = readJson(
        "{\"service\":\"must not replace the current value\"," ~
            "\"primary_endpoint\":17}",
        allocator,
        &config,
    );
    if (error.ok || config.serviceName != "edge-gateway")
        return false;
    writeln("failed replacement preserved the parsed value at ",
        error.line, ":", error.column);
    return true;
}

private bool demonstrateDocumentOwnedDecode() nothrow @nogc
{
    Deserialized!BorrowedReport report;
    scope (exit)
        report.deinit();
    SerdeError error = readJson(
        "{\"report_name\":\"latency\",\"samples\":[12,9,15,11]}",
        mallocAllocator(),
        &report,
    );
    if (!error.ok)
        return false;

    report.value.samples[1] = 10;
    writeln("document-owned report: ", report.value.reportName,
        ", corrected sample=", report.value.samples[1]);
    return true;
}

private bool demonstrateTaggedUnionAndAdapter() nothrow @nogc
{
    Deserialized!ServiceChange change;
    scope (exit)
        change.deinit();
    SerdeError error = readJson(
        "{\"change\":{\"service\":\"gateway\",\"port\":8443}," ~
            "\"change_type\":\"service_started\"}",
        mallocAllocator(), &change);
    if (!error.ok)
        return false;
    writeln("tagged change: ", change.value.data.started.service,
        ":", change.value.data.started.port);

    ServiceChange stopped;
    stopped.kind = ChangeKind.serviceStopped;
    stopped.data.stopped = StoppedChange("worker", 17);
    StringBuf toml = StringBuf.create(mallocAllocator());
    scope (exit)
        toml.deinit();
    Writer tomlWriter = Writer.fromSink(&appendSink, &toml);
    error = writeToml(tomlWriter, stopped);
    if (!error.ok)
        return false;
    writeln("tagged TOML:\n", toml);

    Health health;
    error = readJson("{\"readiness\":98}", mallocAllocator(), &health);
    if (!error.ok)
        return false;
    writeln("adapted readiness: ", health.readiness.value, "%");
    return true;
}

extern (C) int main()
{
    if (!demonstrateOwningDecode())
        return 1;
    if (!demonstrateDocumentOwnedDecode())
        return 1;
    if (!demonstrateTaggedUnionAndAdapter())
        return 1;
    return 0;
}
