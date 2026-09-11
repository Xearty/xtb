module xtb.diagnostics.crash;

nothrow @nogc:

import core.attribute;
import core.stdc.signal;
import core.stdc.stdio;

import xtb.diagnostics.demangle;
import xtb.diagnostics.stacktrace;
import xtb.diagnostics.stacktrace_style;
import xtb.fmt.print;
import xtb.fmt.writer;
import xtb.panic;
import xtb.string;
import xtb.types;

version (linux)
{
    import crash_backend = xtb.diagnostics.internal.linux.crash;
}
else
{
    import crash_backend = xtb.diagnostics.internal.unsupported.crash;
}

enum SignalTraceMode
{
    fault_address_only,
    attempt_stack_unwind,
}

struct CrashHandlerOptions
{
    StackTraceTheme theme = StackTraceTheme.gruvbox;
    SignalTraceMode signal_trace_mode = SignalTraceMode.attempt_stack_unwind;
    bool trace_panics = true;
    ModuleDisplay module_display = ModuleDisplay.omitted;
    SignatureDetail signature_detail = SignatureDetail.overload_identity;
    SignatureLayout signature_layout = SignatureLayout.multiline;
    usize signature_columns = 100;
}

/// Owns the process-wide crash-handler installation.
/// Installation and cleanup must occur while application worker threads are stopped.
@mustuse struct CrashHandlerScope
{
nothrow @nogc:

    /// Tracks whether this scope owns the installed crash-handler state.
    /// Changing it manually breaks cleanup ownership.
    bool active;

    @disable this(this);

    ~this()
    {
        this.deinit();
    }

    /// Installs process-wide crash handlers until the returned scope is deinitialized.
    ///
    /// `permanent_executable_path` may be null. When non-null, it must point to
    /// a null-terminated string whose storage remains valid until the returned
    /// scope is deinitialized.
    static CrashHandlerScope install(
        const(char)* permanent_executable_path = null,
        CrashHandlerOptions options = CrashHandlerOptions.init,
    ) @system
    {
        require(!global_state.active, "crash handlers already installed");
        global_state.context = StackTraceContext.create(permanent_executable_path);
        global_state.style = StackTraceStyle.from_theme(options.theme);
        global_state.style.module_display = options.module_display;
        global_state.style.signature_detail = options.signature_detail;
        global_state.style.signature_layout = options.signature_layout;
        global_state.style.signature_columns = options.signature_columns;
        global_state.panic_trace_written = 0;
        const signals_installed = crash_backend.install_crash_signals(
            options.signal_trace_mode == SignalTraceMode.attempt_stack_unwind,
            &global_state.style.colors,
            &global_state.panic_trace_written,
        );
        if (!signals_installed) panic("failed to install crash signal handler");
        if (options.trace_panics) global_state.previous_panic = set_panic_handler(&trace_panic);

        global_state.traces_panics = options.trace_panics;
        global_state.active = true;

        CrashHandlerScope result;
        result.active = true;
        return result;
    }

    void deinit() @system
    {
        if (!this.active) return;

        if (global_state.traces_panics)
        {
            cast(void) set_panic_handler(
                global_state.previous_panic.handler,
                global_state.previous_panic.context,
            );
        }

        crash_backend.restore_crash_signals();
        global_state = GlobalCrashState.init;
        this.active = false;
    }
}

private struct GlobalCrashState
{
    StackTraceContext context;
    StackTraceStyle style;
    PanicHook previous_panic;
    bool traces_panics;
    bool active;
    sig_atomic_t panic_trace_written;
}

private __gshared GlobalCrashState global_state;

private void trace_panic(String message, void*)
{
    if (global_state.previous_panic.handler !is null)
        global_state.previous_panic.handler(message, global_state.previous_panic.context);

    Writer writer = file_writer(cast(FILE*) stderr);
    writer.put('\n');
    StackFrame[64] frames;
    char[16 * 1024] text;
    StackTrace trace = global_state.context.capture(frames[], text[], 2);
    char[32 * 1024] signature_storage;
    writer.write_stack_trace(&trace, signature_storage[], &global_state.style);
    writer.put('\n');
    global_state.panic_trace_written = 1;
}
