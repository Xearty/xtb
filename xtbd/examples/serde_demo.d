module examples.serde_demo;

import core.lifetime : move;
import xtb.core.array : Array, append;
import xtb.core.memory : Allocator, mallocAllocator;
import xtb.core.option : Option, set;
import xtb.core.print : Writer, writeln;
import xtb.core.string : String, StringBuf, append, clear, equal;
import xtb.serde : Deserialized, KeyCase, SerdeError, SerdeErrorKind, TagLayout,
    aliasName, caseOf, discriminant, fieldCase, ignore, omitDefault, payload,
    readJson, readToml, rename, required, taggedUnion, variantCase, withSerde,
    writeJson, writeToml;

private enum Protocol
{
    http,
    https,
}

@fieldCase(KeyCase.snake)
private struct Endpoint
{
    @required StringBuf hostName;
    ushort port;
    Protocol protocol;
    Array!StringBuf labels;
}

@fieldCase(KeyCase.snake)
private struct ServiceConfig
{
    @rename("service") @required StringBuf serviceName;
    @aliasName("primary") Endpoint primaryEndpoint;
    Array!Endpoint replicaEndpoints;
    Array!StringBuf featureFlags;
    int[3] retryDelays;
    Option!StringBuf deploymentNote;
    Option!Endpoint fallbackEndpoint;
    @omitDefault bool tracingEnabled;
    @ignore uint runtimeRequests;
}

@fieldCase(KeyCase.snake)
private struct BorrowedReport
{
    @required String reportName;
    int[] samples;
}

@variantCase(KeyCase.snake)
private enum ChangeKind
{
    serviceStarted,
    @rename("stopped") @aliasName("service_stopped") serviceStopped,
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
    @caseOf(ChangeKind.serviceStarted) StartedChange started;
    @caseOf(ChangeKind.serviceStopped) StoppedChange stopped;
}

@taggedUnion(TagLayout.adjacent)
private struct ServiceChange
{
    @discriminant @rename("change_type") ChangeKind kind;
    @payload @rename("change") ChangePayload data;
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
    @withSerde!PercentageSerde Percentage readiness;
}

private size_t appendSink(void* context, scope String bytes) nothrow @nogc
{
    StringBuf* output = cast(StringBuf*) context;
    (*output).append(bytes);
    return bytes.length;
}

private bool writeFormats(scope const ref ServiceConfig config) nothrow @nogc
{
    StringBuf json = StringBuf.create(mallocAllocator());
    Writer jsonWriter = Writer.fromSink(&appendSink, &json);
    SerdeError error = writeJson(jsonWriter, config);
    if (!error.ok)
        return false;

    StringBuf toml = StringBuf.create(mallocAllocator());
    Writer tomlWriter = Writer.fromSink(&appendSink, &toml);
    error = writeToml(tomlWriter, config);
    if (!error.ok)
        return false;

    writeln("mutated JSON:\n", json.view);
    writeln("mutated TOML:\n", toml.view);

    ServiceConfig fromToml;
    error = readToml(toml.view, mallocAllocator(), &fromToml);
    if (!error.ok)
        return false;
    writeln("TOML round trip: ", fromToml.serviceName.view,
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

    writeln("parsed service: ", config.serviceName.view);
    writeln("primary: ", config.primaryEndpoint.hostName.view,
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
    config.deploymentNote.set(move(deploymentNote));

    StringBuf feature = StringBuf.fromString(allocator, "compression");
    config.featureFlags.append(move(feature));

    Endpoint replica;
    replica.hostName = StringBuf.fromString(allocator, "api-2.internal");
    replica.port = 9443;
    replica.protocol = Protocol.https;
    replica.labels = Array!StringBuf.create(allocator);
    StringBuf canary = StringBuf.fromString(allocator, "canary");
    replica.labels.append(move(canary));
    config.replicaEndpoints.append(move(replica));

    Endpoint fallback;
    fallback.hostName = StringBuf.fromString(allocator, "fallback.internal");
    fallback.port = 443;
    fallback.protocol = Protocol.https;
    fallback.labels = Array!StringBuf.create(allocator);
    config.fallbackEndpoint.set(move(fallback));

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
    Writer tomlWriter = Writer.fromSink(&appendSink, &toml);
    error = writeToml(tomlWriter, stopped);
    if (!error.ok)
        return false;
    writeln("tagged TOML:\n", toml.view);

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
