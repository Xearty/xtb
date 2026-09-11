module xtb.diagnostics.internal.linux.crash;

nothrow @nogc:

import core.stdc.signal : sig_atomic_t;

import xtb.ansi;
import xtb.diagnostics.stacktrace_style;
import xtb.os.linux.execinfo;
import xtb.os.posix.file;
import xtb.os.posix.process;
import xtb.os.posix.signal;
import xtb.os.posix.ucontext;
import xtb.types;

private enum i32[] handled_signals = [
    SIGABRT,
    SIGBUS,
    SIGFPE,
    SIGILL,
    SIGSEGV,
];

private struct CrashSignalRuntime
{
    const(StackTraceColors)* colors;
    sig_atomic_t* panic_trace_written;
    bool attempt_stack_unwind;
}

private __gshared CrashSignalRuntime runtime;
private __gshared sigaction_t[handled_signals.length] previous_signals;

/// Installs the crash-signal handlers.
///
/// `colors` and `panic_trace_written` may be null. Non-null pointers must remain
/// valid until `restore_crash_signals` is called.
bool install_crash_signals(
    bool attempt_stack_unwind,
    const(StackTraceColors)* colors,
    sig_atomic_t* panic_trace_written,
) @system
{
    runtime.colors = colors;
    runtime.panic_trace_written = panic_trace_written;
    runtime.attempt_stack_unwind = attempt_stack_unwind;

    sigaction_t action;
    sigemptyset(&action.sa_mask);
    action.sa_sigaction = &handle_signal;
    action.sa_flags = SA_SIGINFO | SA_RESETHAND;
    foreach (index, signal; handled_signals)
    {
        const installed = sigaction(signal, &action, &previous_signals[index]) == 0;
        if (!installed)
        {
            restore_installed_signals(index);
            runtime = CrashSignalRuntime.init;
            return false;
        }
    }

    // Force the platform unwinder's lazy setup outside signal context.
    void*[1] warmup;
    cast(void) backtrace(warmup.ptr, cast(i32) warmup.length);
    return true;
}

void restore_crash_signals()
{
    foreach (index, signal; handled_signals)
        cast(void) sigaction(signal, &previous_signals[index], null);

    runtime = CrashSignalRuntime.init;
}

private void restore_installed_signals(usize count)
{
    foreach_reverse (index; 0 .. count)
        cast(void) sigaction(handled_signals[index], &previous_signals[index], null);
}

private String signal_name(i32 signal) pure @safe
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

private usize fault_program_counter(void* raw_context) @system
{
    if (raw_context is null) return 0;

    ucontext_t* context = cast(ucontext_t*) raw_context;
    version (X86_64)
    {
        return cast(usize) context.uc_mcontext.gregs[REG_RIP];
    }
    else version (X86)
    {
        return cast(usize) context.uc_mcontext.gregs[REG_EIP];
    }
    else version (AArch64)
    {
        return cast(usize) context.uc_mcontext.pc;
    }
    else
    {
        return 0;
    }
}

private void raw_write(String bytes) @system
{
    usize offset;
    while (offset < bytes.length)
    {
        const result = write(STDERR_FILENO, bytes.ptr + offset, bytes.length - offset);
        if (result <= 0) return;

        offset += cast(usize) result;
    }
}

private void raw_hex(usize value) @system
{
    enum digits = "0123456789abcdef";
    char[2 + usize.sizeof * 2] buffer;
    buffer[0] = '0';
    buffer[1] = 'x';
    foreach (index; 0 .. usize.sizeof * 2)
    {
        const shift = (usize.sizeof * 2 - index - 1) * 4;
        buffer[index + 2] = digits[(value >> shift) & 0xF];
    }
    raw_write(buffer[]);
}

private void raw_decimal(usize value) @system
{
    char[32] buffer;
    usize begin = buffer.length;
    do
    {
        buffer[--begin] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    raw_write(buffer[begin .. $]);
}

private usize decimal_width(usize value) pure @safe
{
    usize width = 1;
    while (value >= 10)
    {
        value /= 10;
        ++width;
    }
    return width;
}

private void raw_spaces(usize count) @system
{
    while (count != 0)
    {
        raw_write(" ");
        --count;
    }
}

private void raw_ansi(ANSIColor color) @system
{
    const sequence = ansi_sequence(ANSIStyle.foreground(color));
    raw_write(sequence.view);
}

private void raw_ansi_reset(ANSIColor color) @system
{
    if (color.enabled)
    {
        const sequence = ansi_reset_sequence();
        raw_write(sequence.view);
    }
}

private void raw_styled(String text, ANSIColor color) @system
{
    raw_ansi(color);
    raw_write(text);
    raw_ansi_reset(color);
}

private extern (C) void handle_signal(int signal, siginfo_t*, void* raw_context)
{
    __gshared sig_atomic_t handling;
    if (handling != 0) _exit(128 + signal);

    handling = 1;

    const panic_trace_written = runtime.panic_trace_written is null
        ? 0
        : *runtime.panic_trace_written;
    if (signal == SIGABRT && panic_trace_written != 0)
    {
        redeliver_signal(signal);
        return;
    }

    const colors = runtime.colors;
    if (colors is null)
    {
        redeliver_signal(signal);
        return;
    }

    raw_write("\n");
    raw_styled("Fatal crash: ", colors.warning);
    raw_styled(signal_name(signal), colors.warning);
    raw_write("\n");
    raw_styled("Stack trace (signal context):", colors.decoration);
    raw_write("\n");

    const usize fault_pc = fault_program_counter(raw_context);
    const attempt_unwind = runtime.attempt_stack_unwind && panic_trace_written == 0;
    void*[64] addresses;
    i32 address_count;
    usize frame_count;
    if (attempt_unwind)
    {
        address_count = backtrace(addresses.ptr, cast(i32) addresses.length);
        foreach (index; 2 .. address_count)
        {
            const address = cast(usize) addresses[index];
            if (fault_pc == 0 || address != fault_pc) ++frame_count;
        }
    }
    const label_width = frame_count == 0 ? cast(usize) 3 : 3 + decimal_width(frame_count);

    if (fault_pc != 0)
    {
        raw_spaces(label_width - 3);
        raw_styled("[", colors.decoration);
        raw_styled("0", colors.line_number);
        raw_styled("] ", colors.decoration);
        raw_ansi(colors.address);
        raw_write("pc=");
        raw_hex(fault_pc);
        raw_ansi_reset(colors.address);
        raw_write("  ");
        raw_styled("<faulting instruction>", colors.warning);
        raw_write("\n");
    }

    if (attempt_unwind)
    {
        usize frame_number = 1;
        foreach (index; 2 .. address_count)
        {
            const address = cast(usize) addresses[index];
            if (fault_pc != 0 && address == fault_pc) continue;

            raw_spaces(label_width - decimal_width(frame_number) - 3);
            raw_styled("[", colors.decoration);
            raw_ansi(colors.line_number);
            raw_write("+");
            raw_decimal(frame_number);
            raw_ansi_reset(colors.line_number);
            raw_styled("] ", colors.decoration);
            raw_ansi(colors.address);
            raw_write("pc=");
            raw_hex(address);
            raw_ansi_reset(colors.address);
            raw_write("\n");
            ++frame_number;
        }
    }
    else
    {
        raw_styled("<fault-address-only mode: stack unwinding disabled>", colors.decoration);
        raw_write("\n");
    }

    // The current signal remains blocked until this handler returns. Queue
    // it after SA_RESETHAND restored the default disposition, then return so
    // the kernel can perform normal signal termination and core-dump handling.
    redeliver_signal(signal);
}

private void redeliver_signal(i32 signal)
{
    if (kill(getpid(), signal) != 0) _exit(128 + signal);
}
