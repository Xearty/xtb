module xtb.window.internal.glfw_error;

nothrow @nogc:

import xtb.types : i32;
import xtb.window.error : WindowError, WindowErrorKind, WindowStatus;
import xtb.window.internal.glfw : GLFW_NO_ERROR, glfwGetError;

package(xtb.window) void clear_glfw_error() @system
{
    const(char)* description;
    cast(void) glfwGetError(&description);
}

package(xtb.window) i32 consume_glfw_error() @system
{
    const(char)* description;
    return glfwGetError(&description);
}

package(xtb.window) WindowError glfw_call_error(WindowErrorKind kind) @system
{
    const code = consume_glfw_error();
    return code == GLFW_NO_ERROR ? WindowError.init : WindowError(kind, code);
}

package(xtb.window) WindowStatus glfw_call_status(WindowErrorKind kind) @system
{
    const error = glfw_call_error(kind);
    return error.failed ? typeof(return).err(error) : typeof(return).ok();
}
