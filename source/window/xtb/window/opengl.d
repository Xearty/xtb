module xtb.window.opengl;

nothrow @nogc:

import core.stdc.string : memcpy;
import xtb.memory : Allocator;
import xtb.types : String, i32, u8;
import xtb.window.error : WindowErrorKind, WindowResult;
import xtb.window.internal.create_options : BackendClientAPI, BackendGLContextCreationAPI,
    BackendGLProfile, BackendGLReleaseBehavior, BackendGLRobustness,
    BackendWindowCreateOptions;
import xtb.window.internal.glfw;
import xtb.window.internal.glfw_error : clear_glfw_error, glfw_call_error;
import xtb.window.system : WindowSystem;
import xtb.window.window : Window, WindowConfig;

version (XTB_Checked) import xtb.panic : require;

/// Client API provided by an OpenGL context window.
enum OpenGLAPI : u8
{
    opengl,
    opengl_es,
}

struct OpenGLVersion
{
    i32 major = 3;
    i32 minor = 3;
}

enum OpenGLProfile : u8
{
    any,
    core,
    compatibility,
}

/// API GLFW should use to create the OpenGL/OpenGL ES context.
///
/// `native` means WGL on Win32, GLX on X11, EGL on Wayland and NSGL on Cocoa.
/// `os_mesa` is primarily useful with a headless WindowSystem.
enum OpenGLContextCreationAPI : u8
{
    native,
    egl,
    os_mesa,
}

enum OpenGLRobustness : u8
{
    none,
    no_reset_notification,
    lose_context_on_reset,
}

enum OpenGLReleaseBehavior : u8
{
    any,
    flush,
    none,
}

struct OpenGLFramebufferConfig
{
    i32 samples;
    bool srgb_capable;
    bool double_buffered = true;
}

/// Requirements supplied before the native window and its context are created.
///
/// The default requests desktop OpenGL 3.3 core. Configuration consistency is
/// an API contract. `share_context_with`, when non-null, must be a live OpenGL
/// window owned by the same WindowSystem and must use the same client and
/// context creation APIs. It is a non-owning handle and does not extend the
/// lifetime of the shared window.
struct OpenGLConfig
{
    OpenGLAPI api = OpenGLAPI.opengl;
    OpenGLVersion context_version;
    OpenGLProfile profile = OpenGLProfile.core;
    OpenGLContextCreationAPI creation_api = OpenGLContextCreationAPI.native;
    OpenGLRobustness robustness = OpenGLRobustness.none;
    OpenGLReleaseBehavior release_behavior = OpenGLReleaseBehavior.any;
    bool forward_compatible;
    bool debug_context;
    bool no_error;
    OpenGLFramebufferConfig framebuffer;
    Window* share_context_with;

    /// Returns a configuration for OpenGL ES 3.0 with no desktop-GL profile.
    static OpenGLConfig opengl_es(
        OpenGLVersion requested = OpenGLVersion(3, 0),
    ) pure nothrow @nogc @safe
    {
        OpenGLConfig result;
        result.api = OpenGLAPI.opengl_es;
        result.context_version = requested;
        result.profile = OpenGLProfile.any;
        return result;
    }
}

/// Actual attributes of a created OpenGL or OpenGL ES context.
struct OpenGLContextInfo
{
    OpenGLAPI api;
    OpenGLVersion context_version;
    i32 revision;
    OpenGLProfile profile;
    OpenGLContextCreationAPI creation_api;
    OpenGLRobustness robustness;
    OpenGLReleaseBehavior release_behavior;
    bool forward_compatible;
    bool debug_context;
    bool no_error;
    bool double_buffered;
}

/// Generic OpenGL procedure pointer returned by the current context.
alias OpenGLProc = extern (C) void function() nothrow @nogc;

/// Returns whether `window` owns an OpenGL/OpenGL ES context.
bool has_opengl_context(const(Window)* window) pure @safe
{
    return window_has_opengl_context(window);
}

/// Returns whether `window`'s OpenGL/OpenGL ES context is current on this thread.
bool context_is_current(const(Window)* window) @system
{
    return window_has_opengl_context(window) &&
        glfwGetCurrentContext() is window.backend_handle();
}

/// Makes `window`'s OpenGL/OpenGL ES context current on this thread.
void make_context_current(Window* window) @system
{
    version (XTB_Checked)
        require(window_has_opengl_context(window), "Window has no OpenGL context");
    glfwMakeContextCurrent(window.backend_handle());
}

/// Detaches any OpenGL/OpenGL ES context from the calling thread.
void clear_current_context() @system
{
    glfwMakeContextCurrent(null);
}

/// Swaps `window`'s OpenGL front and back buffers.
///
/// XTB requires the context to be current on the calling thread even on
/// backends where GLFW itself does not require this, keeping behavior portable
/// to EGL.
void swap_buffers(Window* window) @system
{
    version (XTB_Checked)
    {
        require(window_has_opengl_context(window), "Window has no OpenGL context");
        require(window.context_is_current(), "OpenGL context is not current on this thread");
    }
    glfwSwapBuffers(window.backend_handle());
}

/// Sets the swap interval for `window`'s current OpenGL context.
///
/// Zero disables synchronization; one requests normal vertical
/// synchronization. Negative values are backend-extension dependent and are
/// passed through to GLFW.
void set_swap_interval(Window* window, i32 interval) @system
{
    version (XTB_Checked)
    {
        require(window_has_opengl_context(window), "Window has no OpenGL context");
        require(window.context_is_current(), "OpenGL context is not current on this thread");
    }
    glfwSwapInterval(interval);
}

/// Queries context attributes exposed by GLFW for `window`.
///
/// This is a window query and must be called from the main thread. Samples and
/// sRGB capability are creation requirements; query their actual values through
/// OpenGL.
WindowResult!OpenGLContextInfo opengl_context_info(const(Window)* window) @system
{
    version (XTB_Checked)
        require(window_has_opengl_context(window), "Window has no OpenGL context");

    clear_glfw_error();
    OpenGLContextInfo result;
    result.api = window_opengl_api(window);
    result.context_version.major = glfwGetWindowAttrib(window.backend_handle(), GLFW_CONTEXT_VERSION_MAJOR);
    result.context_version.minor = glfwGetWindowAttrib(window.backend_handle(), GLFW_CONTEXT_VERSION_MINOR);
    result.revision = glfwGetWindowAttrib(window.backend_handle(), GLFW_CONTEXT_REVISION);
    result.profile = opengl_profile(glfwGetWindowAttrib(
            window.backend_handle(),
            GLFW_OPENGL_PROFILE,
    ));
    result.creation_api = opengl_context_creation_api(
        glfwGetWindowAttrib(
            window.backend_handle(),
            GLFW_CONTEXT_CREATION_API,
    ));
    result.robustness = opengl_robustness(glfwGetWindowAttrib(
            window.backend_handle(),
            GLFW_CONTEXT_ROBUSTNESS,
    ));
    result.release_behavior = opengl_release_behavior(
        glfwGetWindowAttrib(
            window.backend_handle(),
            GLFW_CONTEXT_RELEASE_BEHAVIOR,
    ));
    result.forward_compatible = glfwGetWindowAttrib(
        window.backend_handle(),
        GLFW_OPENGL_FORWARD_COMPAT,
    ) == GLFW_TRUE;
    result.debug_context = glfwGetWindowAttrib(
        window.backend_handle(),
        GLFW_CONTEXT_DEBUG,
    ) == GLFW_TRUE;
    result.no_error = glfwGetWindowAttrib(
        window.backend_handle(),
        GLFW_CONTEXT_NO_ERROR,
    ) == GLFW_TRUE;
    result.double_buffered = glfwGetWindowAttrib(
        window.backend_handle(),
        GLFW_DOUBLEBUFFER,
    ) == GLFW_TRUE;

    const error = glfw_call_error(WindowErrorKind.backend_operation_failed);
    if (error.failed)
        return typeof(return).err(error);
    return typeof(return).ok(result);
}

/// Looks up an OpenGL/OpenGL ES procedure for `window`'s current context.
/// Returns null when the procedure is unavailable. `name` must be non-empty
/// ASCII without embedded NUL bytes and at most 255 bytes long.
OpenGLProc opengl_proc_address(Window* window, scope String name) @system
{
    version (XTB_Checked)
    {
        require(window_has_opengl_context(window), "Window has no OpenGL context");
        require(window.context_is_current(), "OpenGL context is not current on this thread");
    }

    char[256] local_storage;
    const(char)* c_name;
    prepare_api_name(name, local_storage[], &c_name);
    return cast(OpenGLProc) glfwGetProcAddress(c_name);
}

/// Checks a client/context API extension for `window`'s current context.
/// `name` must be non-empty ASCII without embedded NUL bytes and at most
/// 255 bytes long.
bool opengl_extension_supported(Window* window, scope String name) @system
{
    version (XTB_Checked)
    {
        require(window_has_opengl_context(window), "Window has no OpenGL context");
        require(window.context_is_current(), "OpenGL context is not current on this thread");
    }

    char[256] local_storage;
    const(char)* c_name;
    prepare_api_name(name, local_storage[], &c_name);
    return glfwExtensionSupported(c_name) == GLFW_TRUE;
}

/// Creates a Window with an OpenGL/OpenGL ES context. The Window allocation
/// uses the WindowSystem allocator. Requires an installed thread context for
/// temporary title conversion.
WindowResult!(Window*) create_opengl_window(
    WindowSystem* system,
    WindowConfig window_config = WindowConfig.init,
    OpenGLConfig opengl_config = OpenGLConfig.init,
) @system
{
    version (XTB_Checked)
        require(system !is null && system.initialized, "WindowSystem is not initialized");
    return create_opengl_window_impl(
        system,
        system.allocator_for_windows,
        window_config,
        opengl_config,
    );
}

/// Allocator-selecting counterpart to `create_opengl_window`. Requires an
/// installed thread context for temporary title conversion.
WindowResult!(Window*) create_opengl_window(
    WindowSystem* system,
    Allocator* allocator,
    WindowConfig window_config,
    OpenGLConfig opengl_config = OpenGLConfig.init,
) @system
{
    version (XTB_Checked)
    {
        require(system !is null && system.initialized, "WindowSystem is not initialized");
        require(allocator !is null && *allocator !is null, "Window allocator is null");
    }
    return create_opengl_window_impl(system, allocator, window_config, opengl_config);
}

private WindowResult!(Window*) create_opengl_window_impl(
    WindowSystem* system,
    Allocator* allocator,
    WindowConfig window_config,
    OpenGLConfig opengl_config,
) @system
{
    version (XTB_Checked)
        require_context_config(system, opengl_config);

    BackendWindowCreateOptions backend_options;
    backend_options.client_api = backend_client_api(opengl_config.api);
    backend_options.context_version_major = opengl_config.context_version.major;
    backend_options.context_version_minor = opengl_config.context_version.minor;
    backend_options.profile = backend_profile(opengl_config.profile);
    backend_options.context_creation_api = backend_context_creation_api(opengl_config.creation_api);
    backend_options.robustness = backend_robustness(opengl_config.robustness);
    backend_options.release_behavior = backend_release_behavior(opengl_config.release_behavior);
    backend_options.forward_compatible = opengl_config.forward_compatible;
    backend_options.debug_context = opengl_config.debug_context;
    backend_options.no_error = opengl_config.no_error;
    backend_options.samples = opengl_config.framebuffer.samples;
    backend_options.srgb_capable = opengl_config.framebuffer.srgb_capable;
    backend_options.double_buffered = opengl_config.framebuffer.double_buffered;
    if (opengl_config.share_context_with !is null)
        backend_options.shared_context = opengl_config.share_context_with.backend_handle();

    return system.create_window_with_backend_options(
        allocator,
        window_config,
        backend_options,
    );
}

private bool window_has_opengl_context(const(Window)* window) pure @safe
{
    if (window is null || !window.valid)
        return false;
    const client_api = window.backend_client_api;
    return client_api == BackendClientAPI.opengl ||
        client_api == BackendClientAPI.opengl_es;
}

private OpenGLAPI window_opengl_api(const(Window)* window) pure @safe
{
    return window.backend_client_api == BackendClientAPI.opengl_es
        ? OpenGLAPI.opengl_es : OpenGLAPI.opengl;
}

version (XTB_Checked) private void require_context_config(
    WindowSystem* system,
    OpenGLConfig config,
) @safe
{
    require(config.context_version.major > 0, "OpenGL major version must be positive");
    require(config.context_version.minor >= 0, "OpenGL minor version must not be negative");
    require(config.framebuffer.samples >= 0, "OpenGL sample count must not be negative");

    if (config.api == OpenGLAPI.opengl)
    {
        require(config.profile == OpenGLProfile.any ||
            version_at_least(config.context_version, 3, 2),
            "OpenGL profiles require OpenGL 3.2 or newer");
        require(!config.forward_compatible || version_at_least(config.context_version, 3, 0),
            "forward-compatible OpenGL requires OpenGL 3.0 or newer");
    }

    if (config.share_context_with !is null)
    {
        require(window_has_opengl_context(config.share_context_with),
            "shared Window has no OpenGL context");
        require(config.share_context_with.owner_system is system,
            "shared Window belongs to another WindowSystem");
        require(config.share_context_with.backend_client_api == backend_client_api(config.api),
            "shared Window uses another client API");
        require(config.share_context_with.backend_context_creation_api ==
            backend_context_creation_api(config.creation_api),
            "shared Window uses another context creation API");
    }
}

private bool version_at_least(OpenGLVersion value, i32 major, i32 minor) pure @safe
{
    return value.major > major || (value.major == major && value.minor >= minor);
}

private BackendClientAPI backend_client_api(OpenGLAPI api) pure @safe
{
    final switch (api)
    {
        case OpenGLAPI.opengl:
            return BackendClientAPI.opengl;
        case OpenGLAPI.opengl_es:
            return BackendClientAPI.opengl_es;
    }
}

private BackendGLProfile backend_profile(OpenGLProfile profile) pure @safe
{
    final switch (profile)
    {
        case OpenGLProfile.any:
            return BackendGLProfile.any;
        case OpenGLProfile.core:
            return BackendGLProfile.core;
        case OpenGLProfile.compatibility:
            return BackendGLProfile.compatibility;
    }
}

private BackendGLContextCreationAPI backend_context_creation_api(
    OpenGLContextCreationAPI api,
) pure @safe
{
    final switch (api)
    {
        case OpenGLContextCreationAPI.native:
            return BackendGLContextCreationAPI.native;
        case OpenGLContextCreationAPI.egl:
            return BackendGLContextCreationAPI.egl;
        case OpenGLContextCreationAPI.os_mesa:
            return BackendGLContextCreationAPI.os_mesa;
    }
}

private BackendGLRobustness backend_robustness(OpenGLRobustness robustness) pure @safe
{
    final switch (robustness)
    {
        case OpenGLRobustness.none:
            return BackendGLRobustness.none;
        case OpenGLRobustness.no_reset_notification:
            return BackendGLRobustness.no_reset_notification;
        case OpenGLRobustness.lose_context_on_reset:
            return BackendGLRobustness.lose_context_on_reset;
    }
}

private BackendGLReleaseBehavior backend_release_behavior(
    OpenGLReleaseBehavior behavior,
) pure @safe
{
    final switch (behavior)
    {
        case OpenGLReleaseBehavior.any:
            return BackendGLReleaseBehavior.any;
        case OpenGLReleaseBehavior.flush:
            return BackendGLReleaseBehavior.flush;
        case OpenGLReleaseBehavior.none:
            return BackendGLReleaseBehavior.none;
    }
}

private OpenGLProfile opengl_profile(i32 value) pure @safe
{
    switch (value)
    {
        case GLFW_OPENGL_CORE_PROFILE:
            return OpenGLProfile.core;
        case GLFW_OPENGL_COMPAT_PROFILE:
            return OpenGLProfile.compatibility;
        default:
            return OpenGLProfile.any;
    }
}

private OpenGLContextCreationAPI opengl_context_creation_api(i32 value) pure @safe
{
    switch (value)
    {
        case GLFW_EGL_CONTEXT_API:
            return OpenGLContextCreationAPI.egl;
        case GLFW_OSMESA_CONTEXT_API:
            return OpenGLContextCreationAPI.os_mesa;
        default:
            return OpenGLContextCreationAPI.native;
    }
}

private OpenGLRobustness opengl_robustness(i32 value) pure @safe
{
    switch (value)
    {
        case GLFW_NO_RESET_NOTIFICATION:
            return OpenGLRobustness.no_reset_notification;
        case GLFW_LOSE_CONTEXT_ON_RESET:
            return OpenGLRobustness.lose_context_on_reset;
        default:
            return OpenGLRobustness.none;
    }
}

private OpenGLReleaseBehavior opengl_release_behavior(i32 value) pure @safe
{
    switch (value)
    {
        case GLFW_RELEASE_BEHAVIOR_FLUSH:
            return OpenGLReleaseBehavior.flush;
        case GLFW_RELEASE_BEHAVIOR_NONE:
            return OpenGLReleaseBehavior.none;
        default:
            return OpenGLReleaseBehavior.any;
    }
}

private void prepare_api_name(
    scope String name,
    scope char[] storage,
    scope const(char)** output,
) @system
{
    version (XTB_Checked)
    {
        require(name.length != 0, "OpenGL name must not be empty");
        require(name.length < storage.length, "OpenGL name exceeds 255 bytes");
        foreach (character; name)
        {
            require(character != '\0', "OpenGL name contains an embedded NUL byte");
            require(cast(ubyte) character <= 0x7f, "OpenGL name must be ASCII");
        }
    }

    memcpy(storage.ptr, name.ptr, name.length);
    storage[name.length] = '\0';
    *output = storage.ptr;
}
