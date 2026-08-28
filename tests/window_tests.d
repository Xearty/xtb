module tests.window_tests;

nothrow @nogc:

import xtb.allocators.malloc : mallocAllocator;
import xtb.memory : Allocator;
import xtb.window;

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

    auto generic_context_result = OpenGLContext.from_window(first);
    if (!generic_context_result.isErr ||
        generic_context_result.takeError().kind != WindowErrorKind.context_unavailable)
        return 25;

    const es_config = OpenGLContextConfig.opengl_es();
    if (es_config.api != OpenGLAPI.opengl_es ||
        es_config.context_version.major != 3 ||
        es_config.context_version.minor != 0 ||
        es_config.profile != OpenGLProfile.any)
        return 26;

    OpenGLContextConfig invalid_gl_config;
    invalid_gl_config.context_version = OpenGLVersion(3, 1);
    invalid_gl_config.profile = OpenGLProfile.core;
    auto invalid_gl_result = create_opengl_window(system, config, invalid_gl_config);
    if (!invalid_gl_result.isErr ||
        invalid_gl_result.takeError().kind != WindowErrorKind.invalid_context_config)
        return 27;

    auto null_allocator_gl_result = create_opengl_window(
        system,
        cast(Allocator*) null,
        config,
    );
    if (!null_allocator_gl_result.isErr ||
        null_allocator_gl_result.takeError()
            .kind != WindowErrorKind.allocation_failed)
        return 28;

    OpenGLContextConfig unavailable_gl_config;
    unavailable_gl_config.context_version = OpenGLVersion(99, 0);
    auto unavailable_gl_result = create_opengl_window(
        system,
        config,
        unavailable_gl_config,
    );
    if (!unavailable_gl_result.isErr ||
        unavailable_gl_result.takeError().kind != WindowErrorKind.context_unavailable)
        return 29;

    OpenGLContextConfig gl_config;
    gl_config.creation_api = OpenGLContextCreationAPI.os_mesa;
    gl_config.debug_context = true;
    gl_config.robustness = OpenGLRobustness.no_reset_notification;
    gl_config.release_behavior = OpenGLReleaseBehavior.flush;
    gl_config.framebuffer.samples = 4;
    gl_config.framebuffer.srgb_capable = true;

    auto gl_result = create_opengl_window(system, config, gl_config);
    if (gl_result.isErr)
    {
        // The Null platform is always present in GLFW 3.4+, but the host may
        // not provide the OSMesa runtime needed for a headless OpenGL context.
        // Static validation above still runs everywhere; exercise the live
        // context path whenever this optional runtime is available.
        if (gl_result.takeError().kind != WindowErrorKind.context_unavailable)
            return 30;
        return 0;
    }

    OpenGLContext gl = gl_result.take();
    Window* gl_window = gl.window;
    scope (exit)
        gl_window.deinit();

    if (!gl.valid || gl.api != OpenGLAPI.opengl || system.window_count != 2)
        return 31;
    if (gl.current)
        return 32;

    auto premature_swap = gl.swap_buffers();
    if (!premature_swap.isErr ||
        premature_swap.takeError().kind != WindowErrorKind.no_current_context)
        return 33;

    if (gl.make_current().isErr || !gl.current)
        return 34;
    if (OpenGLContext.current_context().window !is gl_window)
        return 35;
    if (gl.set_swap_interval(1).isErr)
        return 36;

    auto info_result = gl.info();
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
    auto invalid_proc = gl.proc_address(proc_with_nul[]);
    if (!invalid_proc.isErr || invalid_proc.takeError().kind != WindowErrorKind.invalid_proc_name)
        return 39;

    auto proc_result = gl.proc_address("glGetString");
    if (proc_result.isErr || proc_result.take() is null)
        return 40;

    auto extension_result = gl.extension_supported("GL_FAKE_extension");
    if (extension_result.isErr)
        return 41;
    const fake_extension_supported = extension_result.take();

    // The instrumented test backend exposes glFakeFunction. When present,
    // GL_FAKE_extension is reported only if all creation hints above reached
    // glfwCreateWindow unchanged. Real OpenGL implementations simply skip
    // this backend-specific assertion.
    const fake_backend = !gl.proc_address("glFakeFunction").isErr;
    if (fake_backend && !fake_extension_supported)
        return 42;
    if (!info.debug_context ||
        info.robustness != OpenGLRobustness.no_reset_notification ||
        info.release_behavior != OpenGLReleaseBehavior.flush ||
        !info.double_buffered)
        return 43;

    OpenGLContextConfig mismatched_share_config = gl_config;
    mismatched_share_config.creation_api = OpenGLContextCreationAPI.egl;
    mismatched_share_config.shared_context = gl;
    auto mismatched_share_result = create_opengl_window(
        system,
        config,
        mismatched_share_config,
    );
    if (!mismatched_share_result.isErr ||
        mismatched_share_result.takeError()
            .kind != WindowErrorKind.invalid_context_config)
        return 44;

    OpenGLContextConfig shared_config = gl_config;
    shared_config.shared_context = gl;
    auto shared_result = create_opengl_window(system, config, shared_config);
    if (shared_result.isErr)
        return 45;
    OpenGLContext shared_gl = shared_result.take();
    Window* shared_window = shared_gl.window;
    if (!shared_gl.valid || system.window_count != 3)
    {
        shared_window.deinit();
        return 46;
    }
    shared_window.deinit();
    if (system.window_count != 2)
        return 47;

    if (gl.swap_buffers().isErr)
        return 48;
    if (OpenGLContext.clear_current().isErr || gl.current ||
        OpenGLContext.current_context().valid)
        return 49;

    return 0;
}
