module xtb.diagnostics.internal.linux.crash;

nothrow @nogc:

import core.stdc.signal : sig_atomic_t;
import xtb.ansi : AnsiColor, AnsiStyle, ansiResetSequence, ansiSequence;
import xtb.diagnostics.stacktrace_style : StackTraceColors;
import xtb.os.linux.execinfo : backtrace;
import xtb.os.posix.file : STDERR_FILENO, write;
import xtb.os.posix.process : _exit, getpid;
import xtb.os.posix.signal : SA_RESETHAND, SA_SIGINFO, SIGABRT, SIGBUS,
    SIGFPE, SIGILL, SIGSEGV, kill, sigaction, sigaction_t, sigemptyset,
    siginfo_t;
import xtb.os.posix.ucontext : ucontext_t;

version (X86_64)
    import xtb.os.posix.ucontext : REG_RIP;
else version (X86)
    import xtb.os.posix.ucontext : REG_EIP;
import xtb.string : String;

private enum int[] handledSignals = [
    SIGABRT,
    SIGBUS,
    SIGFPE,
    SIGILL,
    SIGSEGV,
];

private struct CrashSignalRuntime
{
    const(StackTraceColors)* colors;
    sig_atomic_t* panicTraceWritten;
    bool attemptStackUnwind;
}

private __gshared CrashSignalRuntime runtime;
private __gshared sigaction_t[handledSignals.length] previousSignals;

bool installCrashSignals(
    bool attemptStackUnwind,
    scope const StackTraceColors* colors,
    sig_atomic_t* panicTraceWritten,
)
{
    runtime.colors = colors;
    runtime.panicTraceWritten = panicTraceWritten;
    runtime.attemptStackUnwind = attemptStackUnwind;

    sigaction_t action;
    sigemptyset(&action.sa_mask);
    action.sa_sigaction = &handleSignal;
    action.sa_flags = SA_SIGINFO | SA_RESETHAND;
    foreach (index, signal; handledSignals)
    {
        const installed = sigaction(
            signal,
            &action,
            &previousSignals[index],
        ) == 0;
        if (!installed)
        {
            restoreInstalledSignals(index);
            runtime = CrashSignalRuntime.init;
            return false;
        }
    }

    // Force the platform unwinder's lazy setup outside signal context.
    void*[1] warmup;
    cast(void) backtrace(warmup.ptr, cast(int) warmup.length);
    return true;
}

void restoreCrashSignals()
{
    foreach (index, signal; handledSignals)
        cast(void) sigaction(signal, &previousSignals[index], null);
    runtime = CrashSignalRuntime.init;
}

private void restoreInstalledSignals(size_t count)
{
    static foreach (reverseIndex; 0 .. handledSignals.length)
    {
        if (count > handledSignals.length - reverseIndex - 1)
            cast(void) sigaction(
                handledSignals[handledSignals.length - reverseIndex - 1],
                &previousSignals[handledSignals.length - reverseIndex - 1],
                null,
            );
    }
}

private String signalName(int signal) pure @safe
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
@system
{
    if (rawContext is null)
        return 0;
    ucontext_t* context = cast(ucontext_t*) rawContext;
    version (X86_64)
        return cast(size_t) context.uc_mcontext.gregs[REG_RIP];
    else version (X86)
        return cast(size_t) context.uc_mcontext.gregs[REG_EIP];
    else version (AArch64)
        return cast(size_t) context.uc_mcontext.pc;
    else
        return 0;
}

private void rawWrite(String bytes) @system
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

private void rawHex(size_t value) @system
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

private void rawDecimal(size_t value) @system
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

private size_t decimalWidth(size_t value) pure @safe
{
    size_t width = 1;
    while (value >= 10)
    {
        value /= 10;
        ++width;
    }
    return width;
}

private void rawSpaces(size_t count) @system
{
    while (count != 0)
    {
        rawWrite(" ");
        --count;
    }
}

private void rawAnsi(AnsiColor color) @system
{
    const sequence = ansiSequence(AnsiStyle.foreground(color));
    rawWrite(sequence.view);
}

private void rawAnsiReset(AnsiColor color) @system
{
    if (color.enabled)
    {
        const sequence = ansiResetSequence();
        rawWrite(sequence.view);
    }
}

private void rawStyled(String text, AnsiColor color) @system
{
    rawAnsi(color);
    rawWrite(text);
    rawAnsiReset(color);
}

private extern (C) void handleSignal(
    int signal,
    siginfo_t*,
    void* rawContext,
)
{
    __gshared sig_atomic_t handling;
    if (handling != 0)
        _exit(128 + signal);
    handling = 1;

    const panicTraceWritten = runtime.panicTraceWritten is null
        ? 0 : *runtime.panicTraceWritten;
    if (signal == SIGABRT && panicTraceWritten != 0)
    {
        redeliverSignal(signal);
        return;
    }

    const colors = runtime.colors;
    if (colors is null)
    {
        redeliverSignal(signal);
        return;
    }

    rawWrite("\n");
    rawStyled("Fatal crash: ", colors.warning);
    rawStyled(signalName(signal), colors.warning);
    rawWrite("\n");
    rawStyled("Stack trace (signal context):", colors.decoration);
    rawWrite("\n");

    size_t faultPC = faultProgramCounter(rawContext);
    const attemptUnwind = runtime.attemptStackUnwind && panicTraceWritten == 0;
    void*[64] addresses;
    int addressCount;
    size_t frameCount;
    if (attemptUnwind)
    {
        addressCount = backtrace(addresses.ptr, cast(int) addresses.length);
        foreach (index; 2 .. addressCount)
        {
            const address = cast(size_t) addresses[index];
            if (faultPC == 0 || address != faultPC)
                ++frameCount;
        }
    }
    const labelWidth = frameCount == 0
        ? cast(size_t) 3 : 3 + decimalWidth(frameCount);

    if (faultPC != 0)
    {
        rawSpaces(labelWidth - 3);
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

    if (attemptUnwind)
    {
        size_t frameNumber = 1;
        foreach (index; 2 .. addressCount)
        {
            const address = cast(size_t) addresses[index];
            if (faultPC != 0 && address == faultPC)
                continue;
            rawSpaces(labelWidth - decimalWidth(frameNumber) - 3);
            rawStyled("[", colors.decoration);
            rawAnsi(colors.lineNumber);
            rawWrite("+");
            rawDecimal(frameNumber);
            rawAnsiReset(colors.lineNumber);
            rawStyled("] ", colors.decoration);
            rawAnsi(colors.address);
            rawWrite("pc=");
            rawHex(address);
            rawAnsiReset(colors.address);
            rawWrite("\n");
            ++frameNumber;
        }
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
    // it after SA_RESETHAND restored the default disposition, then return so
    // the kernel can perform normal signal termination and core-dump handling.
    redeliverSignal(signal);
}

private void redeliverSignal(int signal)
{
    if (kill(getpid(), signal) != 0)
        _exit(128 + signal);
}
