module xtb.diagnostics.crash;

import core.stdc.signal : SIGABRT, SIGFPE, SIGILL, SIGSEGV, sig_atomic_t;
import core.stdc.stdio : FILE, stderr;
import xtb.core.panic : PanicHook, panic, setPanicHandler;
import xtb.core.print : Writer;
import xtb.diagnostics.stacktrace : StackFrame, StackTrace, StackTraceContext,
    capture, writeStackTrace;
import xtb.diagnostics.stacktrace_style : AnsiColor, ModuleDisplay, StackTraceStyle,
    StackTraceTheme, SignatureLayout;
import xtb.diagnostics.demangle : SignatureDetail;
import xtb.core.string : String;

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
    private bool active_;

    @disable this(this);

    ~this() nothrow @nogc
    {
        deinit();
    }

    static CrashHandlerScope install(
        const(char)* permanentExecutablePath = null,
        CrashHandlerOptions options = CrashHandlerOptions.init,
    ) nothrow @nogc
    {
        requireInstall(!globalState.active, "crash handlers already installed");
        globalState.context = StackTraceContext.create(permanentExecutablePath);
        globalState.style = StackTraceStyle.fromTheme(options.theme);
        globalState.style.moduleDisplay = options.moduleDisplay;
        globalState.style.signatureDetail = options.signatureDetail;
        globalState.style.signatureLayout = options.signatureLayout;
        globalState.style.signatureColumns = options.signatureColumns;
        globalState.signalTraceMode = options.signalTraceMode;
        globalState.panicTraceWritten = 0;
        version (linux)
            installSignals();
        if (options.tracePanics)
            globalState.previousPanic = setPanicHandler(&tracePanic);
        globalState.tracesPanics = options.tracePanics;
        globalState.active = true;

        CrashHandlerScope result;
        result.active_ = true;
        return result;
    }

    void deinit() nothrow @nogc
    {
        if (!active_)
            return;
        if (globalState.tracesPanics)
            setPanicHandler(
                globalState.previousPanic.handler,
                globalState.previousPanic.context,
            );
        version (linux)
            restoreSignals();
        globalState = GlobalCrashState.init;
        active_ = false;
    }
}

private struct GlobalCrashState
{
    StackTraceContext context;
    StackTraceStyle style;
    PanicHook previousPanic;
    SignalTraceMode signalTraceMode;
    bool tracesPanics;
    bool active;
    sig_atomic_t panicTraceWritten;
    version (linux) sigaction_t[handledSignals.length] previousSignals;
}

private __gshared GlobalCrashState globalState;

private void requireInstall(bool condition, String message) nothrow @nogc
{
    if (!condition)
        panic(message);
}

private void tracePanic(String message, void*) nothrow @nogc
{
    if (globalState.previousPanic.handler !is null)
        globalState.previousPanic.handler(
            message,
            globalState.previousPanic.context,
        );
    Writer writer = Writer.fromFile(cast(FILE*) stderr);
    writer.put('\n');
    StackFrame[64] frames;
    char[16 * 1024] text;
    StackTrace trace = globalState.context.capture(frames[], text[], 3);
    char[32 * 1024] signatureStorage;
    writer.writeStackTrace(&trace, signatureStorage[], &globalState.style);
    cast(void) writer.finish();
    globalState.panicTraceWritten = 1;
}

version (linux)
{
    import core.sys.linux.execinfo : backtrace;
    import core.sys.posix.signal : SA_RESETHAND, SA_SIGINFO, SIGBUS,
        kill, sigaction, sigaction_t, sigemptyset, siginfo_t;
    import core.sys.posix.unistd : STDERR_FILENO, _exit, getpid, write;
    import core.sys.posix.ucontext : ucontext_t;

    private enum int[] handledSignals = [
        SIGABRT,
        SIGBUS,
        SIGFPE,
        SIGILL,
        SIGSEGV,
    ];

    private void installSignals() nothrow @nogc
    {
        sigaction_t action;
        sigemptyset(&action.sa_mask);
        action.sa_sigaction = &handleSignal;
        action.sa_flags = SA_SIGINFO | SA_RESETHAND;
        foreach (index, signal; handledSignals)
        {
            const installed = sigaction(
                signal,
                &action,
                &globalState.previousSignals[index],
            ) == 0;
            if (!installed)
                restoreInstalledSignals(index);
            requireInstall(installed, "failed to install crash signal handler");
        }

        // Force the platform unwinder's lazy setup outside signal context.
        void*[1] warmup;
        cast(void) backtrace(warmup.ptr, cast(int) warmup.length);
    }

    private void restoreInstalledSignals(size_t count) nothrow @nogc
    {
        static foreach (reverseIndex; 0 .. handledSignals.length)
        {
            if (count > handledSignals.length - reverseIndex - 1)
                cast(void) sigaction(
                    handledSignals[handledSignals.length - reverseIndex - 1],
                    &globalState.previousSignals[
                    handledSignals.length - reverseIndex - 1
            ],
                    null,
                );
        }
    }

    private void restoreSignals() nothrow @nogc
    {
        foreach (index, signal; handledSignals)
            cast(void) sigaction(signal, &globalState.previousSignals[index], null);
    }

    private String signalName(int signal) pure nothrow @safe @nogc
    {
        switch (signal)
        {
            case SIGABRT:
                return "SIGABRT";
            case SIGBUS:
                return "SIGBUS";
            case SIGFPE:
                return "SIGFPE";
            case SIGILL:
                return "SIGILL";
            case SIGSEGV:
                return "SIGSEGV";
            default:
                return "unknown signal";
        }
    }

    private size_t faultProgramCounter(void* rawContext)
    nothrow @system @nogc
    {
        if (rawContext is null)
            return 0;
        ucontext_t* context = cast(ucontext_t*) rawContext;
        version (X86_64)
        {
            import core.sys.posix.ucontext : REG_RIP;

            return cast(size_t) context.uc_mcontext.gregs[REG_RIP];
        }
        else version (X86)
        {
            import core.sys.posix.ucontext : REG_EIP;

            return cast(size_t) context.uc_mcontext.gregs[REG_EIP];
        }
        else version (AArch64)
            return cast(size_t) context.uc_mcontext.pc;
        else
            return 0;
    }

    private void rawWrite(String bytes) nothrow @system @nogc
    {
        size_t offset;
        while (offset < bytes.length)
        {
            const result = write(
                STDERR_FILENO,
                bytes.ptr + offset,
                bytes.length - offset,
            );
            if (result <= 0)
                return;
            offset += cast(size_t) result;
        }
    }

    private void rawHex(size_t value) nothrow @system @nogc
    {
        static immutable digits = "0123456789abcdef";
        char[2 + size_t.sizeof * 2] buffer;
        buffer[0] = '0';
        buffer[1] = 'x';
        foreach (index; 0 .. size_t.sizeof * 2)
        {
            const shift = (size_t.sizeof * 2 - index - 1) * 4;
            buffer[index + 2] = digits[(value >> shift) & 0xf];
        }
        rawWrite(buffer[]);
    }

    private void rawDecimal(size_t value) nothrow @system @nogc
    {
        char[32] buffer;
        size_t begin = buffer.length;
        do
        {
            buffer[--begin] = cast(char)('0' + value % 10);
            value /= 10;
        }
        while (value != 0);
        rawWrite(buffer[begin .. $]);
    }

    private void rawAnsi(AnsiColor color) nothrow @system @nogc
    {
        if (!color.enabled)
            return;
        rawWrite("\x1b[38;5;");
        rawDecimal(color.index);
        rawWrite("m");
    }

    private void rawAnsiReset(AnsiColor color) nothrow @system @nogc
    {
        if (color.enabled)
            rawWrite("\x1b[0m");
    }

    private void rawStyled(String text, AnsiColor color) nothrow @system @nogc
    {
        rawAnsi(color);
        rawWrite(text);
        rawAnsiReset(color);
    }

    private extern (C) void handleSignal(
        int signal,
        siginfo_t*,
        void* rawContext,
    ) nothrow @nogc
    {
        __gshared sig_atomic_t handling;
        if (handling != 0)
            _exit(128 + signal);
        handling = 1;

        const colors = &globalState.style.colors;
        rawWrite("\n");
        rawStyled("Fatal crash: ", colors.warning);
        rawStyled(signalName(signal), colors.warning);
        rawWrite("\n");
        rawStyled("Stack trace (signal context):", colors.decoration);
        rawWrite("\n");

        size_t faultPC = faultProgramCounter(rawContext);
        if (faultPC != 0)
        {
            rawStyled("[", colors.decoration);
            rawStyled("0", colors.lineNumber);
            rawStyled("] ", colors.decoration);
            rawAnsi(colors.address);
            rawWrite("pc=");
            rawHex(faultPC);
            rawAnsiReset(colors.address);
            rawWrite("  ");
            rawStyled("<faulting instruction>", colors.warning);
            rawWrite("\n");
        }

        if (globalState.signalTraceMode == SignalTraceMode.attemptStackUnwind &&
            globalState.panicTraceWritten == 0)
        {
            void*[64] addresses;
            const count = backtrace(addresses.ptr, cast(int) addresses.length);
            foreach (index; 2 .. count)
            {
                rawWrite("  ");
                rawStyled("[", colors.decoration);
                rawAnsi(colors.lineNumber);
                rawWrite("+");
                rawDecimal(cast(size_t) index - 1);
                rawAnsiReset(colors.lineNumber);
                rawStyled("] ", colors.decoration);
                rawAnsi(colors.address);
                rawWrite("pc=");
                rawHex(cast(size_t) addresses[index]);
                rawAnsiReset(colors.address);
                rawWrite("\n");
            }
        }
        else if (globalState.panicTraceWritten != 0)
        {
            rawStyled("<rich panic trace printed above>", colors.decoration);
            rawWrite("\n");
        }
        else
        {
            rawStyled(
                "<fault-address-only mode: stack unwinding disabled>",
                colors.decoration,
            );
            rawWrite("\n");
        }

        // The current signal remains blocked until this handler returns. Queue
        // it after SA_RESETHAND restored the default disposition, then return
        // so the kernel can perform normal signal termination (and core-dump
        // handling). Use _exit only if re-delivery itself fails.
        if (kill(getpid(), signal) != 0)
            _exit(128 + signal);
    }
}
else
{
    private enum int[] handledSignals = [];
}
