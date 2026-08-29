module xtb.window.monitor;

nothrow @nogc:

import core.stdc.string : strlen;
import xtb.types : String, i32;
import xtb.window.error : WindowError, WindowErrorKind, WindowResult;
import xtb.window.internal.glfw;
import xtb.window.internal.glfw_error : clear_glfw_error, glfw_call_error;

version (XTB_Checked) import xtb.panic : require;

struct VideoMode
{
    i32 width;
    i32 height;
    i32 red_bits;
    i32 green_bits;
    i32 blue_bits;
    i32 refresh_rate;
}

struct Monitor
{
nothrow @nogc:

    private GLFWmonitor* handle_;

    bool valid() const pure @safe
    {
        return handle_ !is null;
    }

    /// Returns a borrowed UTF-8 view owned by GLFW. The returned string is
    /// valid only while this monitor remains connected and the owning
    /// WindowSystem remains alive. Copy it if it must outlive that interval.
    String name() const @system
    {
        version (XTB_Checked)
            require(handle_ !is null, "Monitor is not valid");
        const(char)* value = glfwGetMonitorName(backend_handle());
        if (value is null)
            return null;
        return value[0 .. strlen(value)];
    }

    WindowResult!VideoMode video_mode() const @system
    {
        version (XTB_Checked)
            require(handle_ !is null, "Monitor is not valid");
        clear_glfw_error();
        const GLFWvidmode* mode = glfwGetVideoMode(backend_handle());
        if (mode is null)
        {
            const error = glfw_call_error(WindowErrorKind.backend_operation_failed);
            return typeof(return).err(error.failed
                    ? error : WindowError(WindowErrorKind.backend_operation_failed));
        }
        return typeof(return).ok(VideoMode(
                mode.width,
                mode.height,
                mode.redBits,
                mode.greenBits,
                mode.blueBits,
                mode.refreshRate,
        ));
    }

    package(xtb.window) static Monitor from_backend(GLFWmonitor* handle) pure @system
    {
        Monitor result;
        result.handle_ = handle;
        return result;
    }

    package(xtb.window) GLFWmonitor* backend_handle() const pure @system
    {
        return cast(GLFWmonitor*) handle_;
    }
}
