module xtb.diagnostics.crash;

nothrow @nogc:

import core.stdc.signal : sig_atomic_t;
import core.stdc.stdio : FILE, stderr;
import xtb.panic : PanicHook, panic, set_panic_handler;

version (XTB_Checked) import xtb.panic : require;
import xtb.fmt.writer : Writer;
import xtb.fmt.print : fileWriter;
import xtb.diagnostics.stacktrace : StackFrame, StackTrace, StackTraceContext,
    capture, writeStackTrace;
import xtb.diagnostics.stacktrace_style : ModuleDisplay, StackTraceStyle,
    StackTraceTheme, SignatureLayout;
import xtb.diagnostics.demangle : SignatureDetail;
import xtb.string;

version (linux)
    import CrashBackend = xtb.diagnostics.internal.linux.crash;
else
    import CrashBackend = xtb.diagnostics.internal.unsupported.crash;

enum SignalTraceMode
{
    faultAddressOnly,
    attemptStackUnwind,
}

struct CrashHandlerOptions
{
    StackTraceTheme theme = StackTraceTheme.gruvbox;
    SignalTraceMode signalTraceMode = SignalTraceMode.attemptStackUnwind;
    bool tracePanics = true;
    ModuleDisplay moduleDisplay = ModuleDisplay.omitted;
    SignatureDetail signatureDetail = SignatureDetail.overloadIdentity;
    SignatureLayout signatureLayout = SignatureLayout.multiline;
    size_t signatureColumns = 100;
}

struct CrashHandlerScope
{
nothrow @nogc:

    private bool active_;

    @disable this(this);

    ~this()
    {
        deinit();
    }

    static CrashHandlerScope install(
        const(char)* permanentExecutablePath = null,
        CrashHandlerOptions options = CrashHandlerOptions.init,
    )
    {
        version (XTB_Checked)
            require(!globalState.active, "crash handlers already installed");
        globalState.context = StackTraceContext.create(permanentExecutablePath);
        globalState.style = StackTraceStyle.fromTheme(options.theme);
        globalState.style.moduleDisplay = options.moduleDisplay;
        globalState.style.signatureDetail = options.signatureDetail;
        globalState.style.signatureLayout = options.signatureLayout;
        globalState.style.signatureColumns = options.signatureColumns;
        globalState.panicTraceWritten = 0;
        const signalsInstalled = CrashBackend.installCrashSignals(
            options.signalTraceMode == SignalTraceMode.attemptStackUnwind,
            &globalState.style.colors,
            &globalState.panicTraceWritten,
        );
        if (!signalsInstalled)
            panic("failed to install crash signal handler");
        if (options.tracePanics)
            globalState.previousPanic = set_panic_handler(&tracePanic);
        globalState.tracesPanics = options.tracePanics;
        globalState.active = true;

        CrashHandlerScope result;
        result.active_ = true;
        return result;
    }

    void deinit()
    {
        if (!active_)
            return;
        if (globalState.tracesPanics)
            cast(void) set_panic_handler(
                globalState.previousPanic.handler,
                globalState.previousPanic.context,
            );
        CrashBackend.restoreCrashSignals();
        globalState = GlobalCrashState.init;
        active_ = false;
    }
}

private struct GlobalCrashState
{
    StackTraceContext context;
    StackTraceStyle style;
    PanicHook previousPanic;
    bool tracesPanics;
    bool active;
    sig_atomic_t panicTraceWritten;
}

private __gshared GlobalCrashState globalState;

private void tracePanic(String message, void*)
{
    if (globalState.previousPanic.handler !is null)
        globalState.previousPanic.handler(
            message,
            globalState.previousPanic.context,
        );
    Writer writer = fileWriter(cast(FILE*) stderr);
    writer.put('\n');
    StackFrame[64] frames;
    char[16 * 1024] text;
    StackTrace trace = globalState.context.capture(frames[], text[], 2);
    char[32 * 1024] signatureStorage;
    writer.writeStackTrace(&trace, signatureStorage[], &globalState.style);
    writer.put('\n');
    globalState.panicTraceWritten = 1;
}
