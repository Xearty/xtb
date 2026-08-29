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
    backend_operation_failed,
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
