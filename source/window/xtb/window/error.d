module xtb.window.error;

nothrow @nogc:

import xtb.result : Result;
import xtb.types : i32, u8;

enum WindowErrorKind : u8
{
    none,
    allocation_failed,
    unsupported_backend_version,
    platform_unavailable,
    initialization_failed,
    already_initialized,
    window_creation_failed,
    invalid_size,
    title_contains_nul,
    monitor_unavailable,
    native_handle_unavailable,
    invalid_context_config,
    context_unavailable,
    no_current_context,
    context_operation_failed,
    invalid_proc_name,
    proc_unavailable,
    invalid_extension_name,
}

struct WindowError
{
nothrow @nogc:

    WindowErrorKind kind;
    i32 backend_code;

    bool failed() const pure @safe
    {
        return kind != WindowErrorKind.none;
    }

    bool succeeded() const pure @safe
    {
        return kind == WindowErrorKind.none;
    }
}

alias WindowResult(T) = Result!(T, WindowError);
alias WindowStatus = WindowResult!void;
