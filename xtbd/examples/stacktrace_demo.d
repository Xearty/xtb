module examples.stacktrace_demo;

import core.stdc.stdio : FILE, stdout;
import xtb.core.crash : CrashHandlerScope;
import xtb.core.print : Writer;
import xtb.core.stacktrace : StackFrame, StackTrace, StackTraceContext,
    capture, writeStackTrace;
import xtb.core.string : String;

private struct AssetRequest
{
    String path;
    int identifier;
}

private struct SceneLoader
{
    pragma(inline, false)
    int load(
        ref StackTraceContext context,
        const(AssetRequest)* request,
        scope const(int)[] samples,
    ) nothrow @nogc
    {
        return decodeAsset(context, request, samples);
    }
}

pragma(inline, false)
private int writeCapturedTrace(ref StackTraceContext context) nothrow @nogc
{
    StackFrame[64] frames;
    char[32 * 1024] text;
    StackTrace trace = context.capture(frames[], text[], 1);

    Writer writer = Writer.fromFile(cast(FILE*) stdout);
    writer.writeStackTrace(&trace);
    return writer.finish().ok ? 0 : 1;
}

pragma(inline, false)
private int submitRenderGraph(
    ref StackTraceContext context,
    uint passCount,
    const(void)* backendHandle,
) nothrow @nogc
{
    const result = writeCapturedTrace(context);
    return result + cast(int) passCount - cast(int) passCount +
        (backendHandle is null ? 0 : 0);
}

pragma(inline, false)
private int buildRenderGraph(
    ref StackTraceContext context,
    ref AssetRequest request,
    int* mutableCursor,
) nothrow @nogc
{
    const passCount = mutableCursor is null ? 0U : cast(uint) *mutableCursor;
    return submitRenderGraph(context, passCount, &request);
}

pragma(inline, false)
private int validatePixels(
    ref StackTraceContext context,
    ref AssetRequest request,
    scope const(int)[] samples,
) nothrow @nogc
{
    int cursor = samples.length == 0 ? 0 : samples[0];
    return buildRenderGraph(context, request, &cursor);
}

pragma(inline, false)
private int parseHeader(
    ref StackTraceContext context,
    const(AssetRequest)* source,
    scope const(int)[] samples,
) nothrow @nogc
{
    AssetRequest request = *source;
    return validatePixels(context, request, samples);
}

pragma(inline, false)
private int decodeAsset(
    ref StackTraceContext context,
    const(AssetRequest)* request,
    scope const(int)[] samples,
) nothrow @nogc
{
    return parseHeader(context, request, samples);
}

pragma(inline, false)
private int dispatchTyped(T)(
    ref StackTraceContext context,
    ref AssetRequest request,
    scope const(T)[] samples,
) nothrow @nogc
{
    SceneLoader loader;
    return loader.load(context, &request, samples);
}

pragma(inline, false)
private int loadScene(
    ref StackTraceContext context,
    String path,
    int identifier,
) nothrow @nogc
{
    int[4] samples = [3, 5, 8, 13];
    AssetRequest request = AssetRequest(path, identifier);
    return dispatchTyped!int(context, request, samples[]);
}

pragma(inline, false)
private int runApplication(ref StackTraceContext context) nothrow @nogc
{
    return loadScene(context, "assets/scene.xtb", 42);
}

extern(C) int main(int argumentCount, char** arguments)
{
    const(char)* executable = argumentCount == 0 ? null : arguments[0];
    scope CrashHandlerScope crashHandlers = CrashHandlerScope.install(executable);
    StackTraceContext context = StackTraceContext.create(executable);
    return runApplication(context);
}
