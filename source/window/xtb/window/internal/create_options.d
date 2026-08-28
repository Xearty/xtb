module xtb.window.internal.create_options;

nothrow @nogc:

import xtb.types : i32, u8;
import xtb.window.internal.glfw : GLFWwindow;

/// Internal window-creation settings used by graphics integration modules.
/// Generic xtb.window windows always use `none`. OpenGL/OpenGL ES integration
/// supplies context requirements before the native window is created, while
/// Vulkan, Direct3D, Metal, and similar APIs continue to use a no-API window
/// and create their presentation objects separately.
package(xtb.window) enum BackendClientAPI : u8
{
    none,
    opengl,
    opengl_es,
}

package(xtb.window) enum BackendGLProfile : u8
{
    any,
    core,
    compatibility,
}

package(xtb.window) enum BackendGLContextCreationAPI : u8
{
    native,
    egl,
    os_mesa,
}

package(xtb.window) enum BackendGLRobustness : u8
{
    none,
    no_reset_notification,
    lose_context_on_reset,
}

package(xtb.window) enum BackendGLReleaseBehavior : u8
{
    any,
    flush,
    none,
}

package(xtb.window) struct BackendWindowCreateOptions
{
    BackendClientAPI client_api = BackendClientAPI.none;
    i32 context_version_major;
    i32 context_version_minor;
    BackendGLProfile profile = BackendGLProfile.any;
    BackendGLContextCreationAPI context_creation_api = BackendGLContextCreationAPI.native;
    BackendGLRobustness robustness = BackendGLRobustness.none;
    BackendGLReleaseBehavior release_behavior = BackendGLReleaseBehavior.any;
    bool forward_compatible;
    bool debug_context;
    bool no_error;
    i32 samples;
    bool srgb_capable;
    bool double_buffered = true;
    GLFWwindow* shared_context;
}
