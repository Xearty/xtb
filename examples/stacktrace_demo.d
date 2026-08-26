module examples.stacktrace_demo;

import core.stdc.stdio : FILE, stdout;
import xtb.diagnostics.crash : CrashHandlerScope;
import xtb.diagnostics.demangle : SignatureDetail;
import xtb.fmt.writer : Writer;
import xtb.fmt.print : fileWriter;
import xtb.diagnostics.stacktrace : StackFrame, StackTrace, StackTraceContext,
    capture, writeStackTrace;
import xtb.diagnostics.stacktrace_style : StackTraceStyle, StackTraceTheme;
import xtb.string;

private enum AssetKind : ubyte
{
    texture,
    mesh,
}

private struct AssetRequest
{
    String path;
    int identifier;
}

private union AssetMetadata
{
    ulong packed;
    ubyte[8] bytes;
}

private struct RenderResult
{
    uint submittedPasses;
    AssetMetadata metadata;
}

private alias ErrorHook = extern (C) void function(int, const(char)*);
private alias SampleFilter = bool function(scope const(float)[]) pure nothrow @nogc;
private alias CompletionHook = void delegate(
    ref const(AssetRequest),
    const(RenderResult)*,
) nothrow @nogc;

private struct RenderBackend
{
    private struct Command
    {
        ushort opcode;
        const(void)* payload;
    }

    pragma(inline, false)
    int submit(
        ref StackTraceContext context,
        scope const(Command)[] commands,
        ref uint[String] resourceSlots,
        ErrorHook errorHook,
        CompletionHook completion,
        shared(const(void))* device,
    ) const nothrow @nogc
    {
        return inspectBackendState(
            context,
            commands,
            resourceSlots,
            errorHook,
            completion,
            device,
        );
    }
}

private extern (C) void reportError(int, const(char)*) nothrow @nogc
{
}

private bool finiteSamples(scope const(float)[] samples) pure nothrow @nogc
{
    foreach (sample; samples)
        if (sample != sample)
            return false;
    return true;
}

pragma(inline, false)
private int writeCapturedTrace(ref StackTraceContext context) nothrow @nogc
{
    StackFrame[96] frames;
    char[64 * 1024] text;
    StackTrace trace = context.capture(frames[], text[], 1);

    Writer writer = fileWriter(cast(FILE*) stdout);
    StackTraceStyle style = StackTraceStyle.fromTheme(StackTraceTheme.gruvbox);
    style.signatureDetail = SignatureDetail.overloadIdentityAndReturn;
    char[64 * 1024] signatureStorage;
    writer.writeStackTrace(&trace, signatureStorage[], &style);
    writer.put('\n');
    return writer.result.ok ? 0 : 1;
}

pragma(inline, false)
private int inspectBackendState(
    ref StackTraceContext context,
    scope const(RenderBackend.Command)[] commands,
    ref uint[String] resourceSlots,
    ErrorHook errorHook,
    CompletionHook completion,
    shared(const(void))* device,
) nothrow @nogc
{
    const result = writeCapturedTrace(context);
    return result + cast(int) commands.length - cast(int) commands.length +
        (errorHook is null ? 0 : 0) + (completion is null ? 0 : 0) +
        (device is null ? 0 : 0);
}

pragma(inline, false)
private int encodeCommands(
    AssetKind kind,
    size_t laneCount,
    alias filter,
)(
    ref StackTraceContext context,
    ref const(AssetRequest) request,
    scope const(float)[] samples,
    ref const(ubyte)[16] digest,
    ref uint[String] resourceSlots,
    ErrorHook errorHook,
    CompletionHook completion,
) nothrow @nogc
{
    const accepted = filter(samples);
    RenderBackend.Command[2] commands = [
        RenderBackend.Command(cast(ushort) kind, &request),
        RenderBackend.Command(cast(ushort) laneCount, &digest),
    ];
    RenderBackend backend;
    shared(const(void))* device;
    return backend.submit(
        context,
        commands[],
        resourceSlots,
        errorHook,
        completion,
        device,
    ) + (accepted ? 0 : 0);
}

pragma(inline, false)
private int qualifyAndEncode(
    AssetKind kind,
    size_t laneCount,
    alias filter,
)(
    ref StackTraceContext context,
    inout(AssetRequest)* request,
    scope const(float)[] samples,
    const(ubyte[16])* digest,
    ref uint[String] resourceSlots,
    immutable(ubyte)* formatTag,
    lazy int,
    out RenderResult preliminaryResult,
) nothrow @nogc
{
    ErrorHook errorHook = &reportError;
    CompletionHook completion;
    return encodeCommands!(kind, laneCount, filter)(
        context,
        *request,
        samples,
        *digest,
        resourceSlots,
        errorHook,
        completion,
    ) + (formatTag is null ? 0 : 0) +
        cast(int) preliminaryResult.submittedPasses;
}

pragma(inline, false)
private int dispatchAsset(Types...)(
    ref StackTraceContext context,
    ref const(AssetRequest) request,
    scope const(float)[] samples,
    ref const(ubyte)[16] digest,
    ref uint[String] resourceSlots,
    Types values,
) nothrow @nogc
{
    immutable ubyte formatTag = 7;
    RenderResult preliminaryResult;
    const ignored = values.length;
    return qualifyAndEncode!(AssetKind.mesh, 8, finiteSamples)(
        context,
        &request,
        samples,
        &digest,
        resourceSlots,
        &formatTag,
        request.identifier,
        preliminaryResult,
    ) + cast(int) ignored - cast(int) ignored;
}

pragma(inline, false)
private int selectAsset(
    ref StackTraceContext context,
    ref const(AssetRequest) request,
    scope const(float)[] samples,
) nothrow @nogc
{
    ubyte[16] digest;
    uint[String] resourceSlots;
    return dispatchAsset!(int, double, String)(
        context,
        request,
        samples,
        digest,
        resourceSlots,
        42,
        3.5,
        "mesh",
    );
}

pragma(inline, false)
private int loadScene(
    ref StackTraceContext context,
    String path,
    int identifier,
) nothrow @nogc
{
    float[4] samples = [0.25f, 0.5f, 0.75f, 1.0f];
    const AssetRequest request = AssetRequest(path, identifier);
    return selectAsset(context, request, samples[]);
}

pragma(inline, false)
private int runApplication(ref StackTraceContext context) nothrow @nogc
{
    return loadScene(context, "assets/scene.xtb", 42);
}

extern (C) int main(int argumentCount, char** arguments)
{
    const(char)* executable = argumentCount == 0 ? null : arguments[0];
    scope CrashHandlerScope crashHandlers = CrashHandlerScope.install(executable);
    StackTraceContext context = StackTraceContext.create(executable);
    return runApplication(context);
}
