module xtb.window.opengl;

nothrow @nogc:

import core.stdc.string : memcpy;
import xtb.memory : Allocator, deallocateArray, tryAllocateArray;
import xtb.types : String, i32, u8;
import xtb.window.error : WindowError, WindowErrorKind, WindowResult, WindowStatus;
import xtb.window.internal.create_options : BackendClientAPI, BackendGLContextCreationAPI,
    BackendGLProfile, BackendGLReleaseBehavior, BackendGLRobustness,
    BackendWindowCreateOptions;
import xtb.window.internal.glfw;
import xtb.window.internal.glfw_error : clear_glfw_error, glfw_call_error, glfw_call_status;
import xtb.window.system : WindowSystem;
import xtb.window.window : Window, WindowConfig;

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
/// The default requests desktop OpenGL 3.3 core. `share_context_with`, when non-null,
/// must belong to the same WindowSystem and use the same client and context
/// creation APIs. It is a non-owning handle and does not extend the lifetime of
/// the shared window.
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
WindowStatus make_context_current(Window* window) @system
{
    if (!window_has_opengl_context(window))
        return typeof(return).err(WindowError(WindowErrorKind.context_unavailable));

    clear_glfw_error();
    glfwMakeContextCurrent(window.backend_handle());
    return glfw_call_status(WindowErrorKind.context_operation_failed);
}

/// Detaches any OpenGL/OpenGL ES context from the calling thread.
WindowStatus clear_current_context() @system
{
    clear_glfw_error();
    glfwMakeContextCurrent(null);
    return glfw_call_status(WindowErrorKind.context_operation_failed);
}

/// Swaps `window`'s OpenGL front and back buffers.
///
/// XTB requires the context to be current on the calling thread even on
/// backends where GLFW itself does not require this, keeping behavior portable
/// to EGL.
WindowStatus swap_buffers(Window* window) @system
{
    if (!window_has_opengl_context(window))
        return typeof(return).err(WindowError(WindowErrorKind.context_unavailable));
    if (!window.context_is_current())
        return typeof(return).err(WindowError(WindowErrorKind.no_current_context));

    clear_glfw_error();
    glfwSwapBuffers(window.backend_handle());
    return glfw_call_status(WindowErrorKind.context_operation_failed);
}

/// Sets the swap interval for `window`'s current OpenGL context.
///
/// Zero disables synchronization; one requests normal vertical
/// synchronization. Negative values are backend-extension dependent and are
/// passed through to GLFW.
WindowStatus set_swap_interval(Window* window, i32 interval) @system
{
    if (!window_has_opengl_context(window))
        return typeof(return).err(WindowError(WindowErrorKind.context_unavailable));
    if (!window.context_is_current())
        return typeof(return).err(WindowError(WindowErrorKind.no_current_context));

    clear_glfw_error();
    glfwSwapInterval(interval);
    return glfw_call_status(WindowErrorKind.context_operation_failed);
}

/// Queries context attributes exposed by GLFW for `window`.
///
/// This is a window query and must be called from the main thread. Samples and
/// sRGB capability are creation requirements; query their actual values through
/// OpenGL.
WindowResult!OpenGLContextInfo opengl_context_info(const(Window)* window) @system
{
    if (!window_has_opengl_context(window))
        return typeof(return).err(WindowError(WindowErrorKind.context_unavailable));

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

    const error = glfw_call_error(WindowErrorKind.context_operation_failed);
    if (error.failed)
        return typeof(return).err(error);
    return typeof(return).ok(result);
}

/// Looks up an OpenGL/OpenGL ES procedure for `window`'s current context.
/// `name` must be non-empty ASCII without embedded NUL bytes.
WindowResult!OpenGLProc opengl_proc_address(Window* window, scope String name) @system
{
    if (!window_has_opengl_context(window))
        return typeof(return).err(WindowError(WindowErrorKind.context_unavailable));
    if (!window.context_is_current())
        return typeof(return).err(WindowError(WindowErrorKind.no_current_context));

    char[256] local_storage;
    char[] allocated_storage;
    const(char)* c_name;
    const name_error = prepare_api_name(
        window.backend_allocator,
        name,
        WindowErrorKind.invalid_proc_name,
        local_storage[],
        &allocated_storage,
        &c_name,
    );
    if (name_error.failed)
        return typeof(return).err(name_error);
    scope (exit)
        release_api_name(window.backend_allocator, allocated_storage);

    clear_glfw_error();
    const backend_proc = glfwGetProcAddress(c_name);
    const error = glfw_call_error(WindowErrorKind.context_operation_failed);
    if (error.failed)
        return typeof(return).err(error);
    if (backend_proc is null)
        return typeof(return).err(WindowError(WindowErrorKind.proc_unavailable));
    return typeof(return).ok(cast(OpenGLProc) backend_proc);
}

/// Checks a client/context API extension for `window`'s current context.
/// `name` must be non-empty ASCII without embedded NUL bytes.
WindowResult!bool opengl_extension_supported(Window* window, scope String name) @system
{
    if (!window_has_opengl_context(window))
        return typeof(return).err(WindowError(WindowErrorKind.context_unavailable));
    if (!window.context_is_current())
        return typeof(return).err(WindowError(WindowErrorKind.no_current_context));

    char[256] local_storage;
    char[] allocated_storage;
    const(char)* c_name;
    const name_error = prepare_api_name(
        window.backend_allocator,
        name,
        WindowErrorKind.invalid_extension_name,
        local_storage[],
        &allocated_storage,
        &c_name,
    );
    if (name_error.failed)
        return typeof(return).err(name_error);
    scope (exit)
        release_api_name(window.backend_allocator, allocated_storage);

    clear_glfw_error();
    const supported = glfwExtensionSupported(c_name);
    const error = glfw_call_error(WindowErrorKind.context_operation_failed);
    if (error.failed)
        return typeof(return).err(error);
    return typeof(return).ok(supported == GLFW_TRUE);
}

/// Creates a Window with an OpenGL/OpenGL ES context. The Window allocation
/// uses the WindowSystem allocator.
WindowResult!(Window*) create_opengl_window(
    WindowSystem* system,
    WindowConfig window_config = WindowConfig.init,
    OpenGLConfig opengl_config = OpenGLConfig.init,
) @system
{
    if (system is null)
        return typeof(return).err(WindowError(WindowErrorKind.initialization_failed));
    return create_opengl_window_impl(
        system,
        system.allocator_for_windows,
        window_config,
        opengl_config,
    );
}

/// Allocator-selecting counterpart to `create_opengl_window`.
WindowResult!(Window*) create_opengl_window(
    WindowSystem* system,
    Allocator* allocator,
    WindowConfig window_config,
    OpenGLConfig opengl_config = OpenGLConfig.init,
) @system
{
    if (system is null)
        return typeof(return).err(WindowError(WindowErrorKind.initialization_failed));
    if (allocator is null || *allocator is null)
        return typeof(return).err(WindowError(WindowErrorKind.allocation_failed));
    return create_opengl_window_impl(system, allocator, window_config, opengl_config);
}

private WindowResult!(Window*) create_opengl_window_impl(
    WindowSystem* system,
    Allocator* allocator,
    WindowConfig window_config,
    OpenGLConfig opengl_config,
) @system
{
    const config_error = validate_context_config(system, opengl_config);
    if (config_error.failed)
        return typeof(return).err(config_error);

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

    auto window_result = system.create_window_with_backend_options(
        allocator,
        window_config,
        backend_options,
    );
    if (window_result.isErr)
        return typeof(return).err(opengl_creation_error(window_result.takeError()));
    return window_result;
}

private WindowError opengl_creation_error(WindowError error) pure @safe
{
    if (error.kind != WindowErrorKind.window_creation_failed)
        return error;

    switch (error.backend_code)
    {
        case GLFW_INVALID_ENUM:
        case GLFW_INVALID_VALUE:
        case GLFW_NO_WINDOW_CONTEXT:
            error.kind = WindowErrorKind.invalid_context_config;
            break;
        case GLFW_API_UNAVAILABLE:
        case GLFW_VERSION_UNAVAILABLE:
        case GLFW_FORMAT_UNAVAILABLE:
            error.kind = WindowErrorKind.context_unavailable;
            break;
        case GLFW_OUT_OF_MEMORY:
            error.kind = WindowErrorKind.allocation_failed;
            break;
        default:
            break;
    }
    return error;
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

private WindowError validate_context_config(
    WindowSystem* system,
    OpenGLConfig config,
) pure @safe
{
    if (config.context_version.major <= 0 || config.context_version.minor < 0 ||
        config.framebuffer.samples < 0)
        return WindowError(WindowErrorKind.invalid_context_config);

    if (config.api == OpenGLAPI.opengl)
    {
        if (config.profile != OpenGLProfile.any &&
            !version_at_least(config.context_version, 3, 2))
            return WindowError(WindowErrorKind.invalid_context_config);
        if (config.forward_compatible && !version_at_least(config.context_version, 3, 0))
            return WindowError(WindowErrorKind.invalid_context_config);
    }

    if (config.share_context_with !is null)
    {
        if (!window_has_opengl_context(config.share_context_with) ||
            config.share_context_with.owner_system !is system ||
            config.share_context_with.backend_client_api != backend_client_api(config.api) ||
            config.share_context_with.backend_context_creation_api !=
            backend_context_creation_api(config.creation_api))
            return WindowError(WindowErrorKind.invalid_context_config);
    }

    return WindowError.init;
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

private WindowError prepare_api_name(
    Allocator* allocator,
    scope String name,
    WindowErrorKind invalid_kind,
    scope char[] local_storage,
    scope char[]* allocated_storage,
    scope const(char)** output,
) @system
{
    *allocated_storage = null;
    *output = null;

    if (name.length == 0 || name.length == size_t.max)
        return WindowError(invalid_kind);
    foreach (character; name)
        if (character == '\0' || cast(ubyte) character > 0x7f)
            return WindowError(invalid_kind);

    if (name.length < local_storage.length)
    {
        memcpy(local_storage.ptr, name.ptr, name.length);
        local_storage[name.length] = '\0';
        *output = local_storage.ptr;
        return WindowError.init;
    }

    if (allocator is null || *allocator is null)
        return WindowError(WindowErrorKind.allocation_failed);
    char[] storage = allocator.tryAllocateArray!char(name.length + 1);
    if (storage.ptr is null)
        return WindowError(WindowErrorKind.allocation_failed);
    memcpy(storage.ptr, name.ptr, name.length);
    storage[name.length] = '\0';
    *allocated_storage = storage;
    *output = storage.ptr;
    return WindowError.init;
}

private void release_api_name(Allocator* allocator, char[] storage) @system
{
    if (storage.ptr !is null)
        allocator.deallocateArray(storage);
}
