module tests.window_tests;

nothrow @nogc:

import xtb.allocators.malloc : mallocAllocator;
import xtb.memory : Allocator;
import xtb.window;
import xtb.window.opengl;
import xtb.window.internal.glfw : GLFW_CLIENT_API, GLFW_FALSE, GLFW_OPENGL_API,
    GLFW_OSMESA_CONTEXT_API, GLFW_CONTEXT_CREATION_API, GLFW_VISIBLE, GLFWwindow,
    glfwCreateWindow, glfwDefaultWindowHints, glfwDestroyWindow, glfwGetCurrentContext,
    glfwMakeContextCurrent, glfwSetWindowUserPointer, glfwWindowHint;

private bool same_size(WindowSize left, WindowSize right) pure @safe
{
    return left.width == right.width && left.height == right.height;
}

extern (C) int main() @system
{
    Allocator* allocator = mallocAllocator();

    WindowSystemConfig system_config;
    system_config.platform = WindowPlatform.headless;
    auto system_result = WindowSystem.create(allocator, system_config);
    if (system_result.isErr)
        return 1;
    WindowSystem* system = system_result.take();
    scope (exit)
        system.deinit();

    if (!system.initialized || system.platform != WindowPlatform.headless)
        return 2;
    if (!WindowSystem.platform_supported(WindowPlatform.headless))
        return 3;
    if (system.monitor_count == 0)
        return 4;

    auto primary_result = system.primary_monitor();
    if (primary_result.isErr)
        return 5;
    Monitor primary = primary_result.take();
    if (!primary.valid || primary.name.length == 0)
        return 6;

    auto mode_result = primary.video_mode();
    if (mode_result.isErr)
        return 7;
    const mode = mode_result.take();
    if (mode.width <= 0 || mode.height <= 0 || mode.refresh_rate <= 0)
        return 8;

    WindowConfig invalid_config;
    invalid_config.width = 0;
    auto invalid_result = system.create_window(invalid_config);
    if (!invalid_result.isErr || invalid_result.takeError().kind != WindowErrorKind.invalid_size)
        return 9;

    WindowConfig config;
    config.width = 320;
    config.height = 240;
    config.title = "xtb.window headless test";
    config.visible = false;

    auto first_result = system.create_window(config);
    if (first_result.isErr)
        return 10;
    Window* first = first_result.take();
    scope (exit)
        first.deinit();

    if (system.window_count != 1 || !first.valid)
        return 11;
    if (!same_size(first.size, WindowSize(320, 240)))
        return 12;
    if (!same_size(first.framebuffer_size, WindowSize(320, 240)))
        return 13;

    if (first.set_size(WindowSize(640, 360)).isErr)
        return 14;
    if (!same_size(first.size, WindowSize(640, 360)))
        return 15;

    if (first.set_title("headless renamed").isErr)
        return 16;
    const char[3] title_with_nul = ['x', '\0', 'y'];
    auto title_result = first.set_title(title_with_nul[]);
    if (!title_result.isErr || title_result.takeError().kind != WindowErrorKind.title_contains_nul)
        return 17;

    first.request_close();
    if (!first.should_close())
        return 18;

    if (!first.native_handle().isErr || !system.native_display_handle().isErr)
        return 19;

    auto second_result = system.create_window(config);
    if (second_result.isErr)
        return 20;
    Window* second = second_result.take();
    if (system.window_count != 2)
    {
        second.deinit();
        return 21;
    }
    second.deinit();
    if (system.window_count != 1)
        return 22;

    system.poll_events();
    if (first.cursor_delta.x != 0 || first.cursor_delta.y != 0)
        return 23;
    if (first.scroll_delta.x != 0 || first.scroll_delta.y != 0)
        return 24;

    if (first.has_opengl_context())
        return 25;
    auto generic_context_result = first.make_context_current();
    if (!generic_context_result.isErr ||
        generic_context_result.takeError().kind != WindowErrorKind.context_unavailable)
        return 26;

    const es_config = OpenGLConfig.opengl_es();
    if (es_config.api != OpenGLAPI.opengl_es ||
        es_config.context_version.major != 3 ||
        es_config.context_version.minor != 0 ||
        es_config.profile != OpenGLProfile.any)
        return 27;

    OpenGLConfig invalid_gl_config;
    invalid_gl_config.context_version = OpenGLVersion(3, 1);
    invalid_gl_config.profile = OpenGLProfile.core;
    auto invalid_gl_result = system.create_opengl_window(config, invalid_gl_config);
    if (!invalid_gl_result.isErr ||
        invalid_gl_result.takeError().kind != WindowErrorKind.invalid_context_config)
        return 28;

    auto null_allocator_gl_result = system.create_opengl_window(
        cast(Allocator*) null,
        config,
    );
    if (!null_allocator_gl_result.isErr ||
        null_allocator_gl_result.takeError()
            .kind != WindowErrorKind.allocation_failed)
        return 29;

    OpenGLConfig unavailable_gl_config;
    unavailable_gl_config.context_version = OpenGLVersion(99, 0);
    auto unavailable_gl_result = system.create_opengl_window(
        config,
        unavailable_gl_config,
    );
    if (!unavailable_gl_result.isErr ||
        unavailable_gl_result.takeError().kind != WindowErrorKind.context_unavailable)
        return 30;

    OpenGLConfig gl_config;
    gl_config.creation_api = OpenGLContextCreationAPI.os_mesa;
    gl_config.debug_context = true;
    gl_config.robustness = OpenGLRobustness.no_reset_notification;
    gl_config.release_behavior = OpenGLReleaseBehavior.flush;
    gl_config.framebuffer.samples = 4;
    gl_config.framebuffer.srgb_capable = true;

    auto gl_result = system.create_opengl_window(config, gl_config);
    if (gl_result.isErr)
    {
        // The Null platform is always present in GLFW 3.4+, but the host may
        // not provide the OSMesa runtime needed for a headless OpenGL context.
        // Static validation above still runs everywhere; exercise the live
        // context path whenever this optional runtime is available.
        if (gl_result.takeError().kind != WindowErrorKind.context_unavailable)
            return 31;
        return 0;
    }

    Window* gl_window = gl_result.take();
    scope (exit)
        gl_window.deinit();

    if (!gl_window.has_opengl_context() || system.window_count != 2)
        return 32;
    if (gl_window.context_is_current())
        return 33;

    auto premature_swap = gl_window.swap_buffers();
    if (!premature_swap.isErr ||
        premature_swap.takeError().kind != WindowErrorKind.no_current_context)
        return 34;

    if (gl_window.make_context_current().isErr || !gl_window.context_is_current())
        return 35;
    if (gl_window.set_swap_interval(1).isErr)
        return 36;

    auto info_result = gl_window.opengl_context_info();
    if (info_result.isErr)
        return 37;
    const info = info_result.take();
    const version_too_old =
        info.context_version.major < gl_config.context_version.major ||
        (info.context_version.major == gl_config.context_version.major &&
                info.context_version.minor < gl_config.context_version.minor);
    if (info.api != OpenGLAPI.opengl || version_too_old ||
        info.creation_api != OpenGLContextCreationAPI.os_mesa ||
        info.profile != OpenGLProfile.core)
        return 38;

    const char[3] proc_with_nul = ['g', '\0', 'l'];
    auto invalid_proc = gl_window.opengl_proc_address(proc_with_nul[]);
    if (!invalid_proc.isErr || invalid_proc.takeError().kind != WindowErrorKind.invalid_proc_name)
        return 39;

    auto proc_result = gl_window.opengl_proc_address("glGetString");
    if (proc_result.isErr || proc_result.take() is null)
        return 40;

    auto extension_result = gl_window.opengl_extension_supported("GL_FAKE_extension");
    if (extension_result.isErr)
        return 41;
    const fake_extension_supported = extension_result.take();

    // The instrumented test backend exposes glFakeFunction. When present,
    // GL_FAKE_extension is reported only if all creation hints above reached
    // glfwCreateWindow unchanged. Real OpenGL implementations simply skip
    // this backend-specific assertion.
    const fake_backend = !gl_window.opengl_proc_address("glFakeFunction").isErr;
    if (fake_backend && !fake_extension_supported)
        return 42;
    if (!info.debug_context ||
        info.robustness != OpenGLRobustness.no_reset_notification ||
        info.release_behavior != OpenGLReleaseBehavior.flush ||
        !info.double_buffered)
        return 43;

    OpenGLConfig mismatched_share_config = gl_config;
    mismatched_share_config.creation_api = OpenGLContextCreationAPI.egl;
    mismatched_share_config.share_context_with = gl_window;
    auto mismatched_share_result = system.create_opengl_window(
        config,
        mismatched_share_config,
    );
    if (!mismatched_share_result.isErr ||
        mismatched_share_result.takeError()
            .kind != WindowErrorKind.invalid_context_config)
        return 44;

    OpenGLConfig shared_config = gl_config;
    shared_config.share_context_with = gl_window;
    auto shared_result = system.create_opengl_window(config, shared_config);
    if (shared_result.isErr)
        return 45;
    Window* shared_window = shared_result.take();
    if (!shared_window.has_opengl_context() || system.window_count != 3)
    {
        shared_window.deinit();
        return 46;
    }
    shared_window.deinit();
    if (system.window_count != 2)
        return 47;

    if (gl_window.swap_buffers().isErr)
        return 48;
    if (clear_current_context().isErr || gl_window.context_is_current())
        return 49;

    glfwDefaultWindowHints();
    glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
    glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API);
    glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_OSMESA_CONTEXT_API);
    GLFWwindow* foreign_window = glfwCreateWindow(16, 16, "foreign context".ptr, null, null);
    if (foreign_window is null)
        return 50;
    scope (exit)
        glfwDestroyWindow(foreign_window);

    glfwSetWindowUserPointer(foreign_window, cast(void*) 1);
    glfwMakeContextCurrent(foreign_window);
    if (glfwGetCurrentContext() !is foreign_window)
        return 51;
    if (gl_window.context_is_current())
        return 52;

    if (gl_window.make_context_current().isErr || !gl_window.context_is_current())
        return 53;
    if (clear_current_context().isErr)
        return 54;

    return 0;
}
