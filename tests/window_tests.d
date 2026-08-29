module tests.window_tests;

nothrow @nogc:

import tests.support.fake_glfw : FakeGLFWOperation, fail_next_operation,
    fake_platform_error, make_foreign_context_current, opengl_hints,
    queue_content_scale, queue_cursor_enter, queue_cursor_position, queue_focus,
    queue_close, queue_framebuffer_size, queue_key, queue_maximized, queue_minimized,
    queue_mouse_button, queue_scroll, queue_text, queue_window_position,
    queue_window_size, seed_backend_error, swap_count, swap_interval;
import xtb.allocators.malloc : mallocAllocator;
import xtb.memory : Allocator;
import xtb.window;
import xtb.window.opengl;

private bool same_size(WindowSize left, WindowSize right) pure @safe
{
    return left.width == right.width && left.height == right.height;
}

private struct EventLog
{
    WindowEvent[32] events;
    size_t count;
}

private void record_event(
    Window*,
    scope const WindowEvent* event,
    void* context,
) @system
{
    EventLog* log = cast(EventLog*) context;
    if (log is null || log.count >= log.events.length)
        return;
    log.events[log.count++] = *event;
}

private struct CloseRequestLog
{
    size_t count;
}

private void cancel_close_request(
    Window* window,
    scope const WindowEvent* event,
    void* context,
) @system
{
    if (event.kind != WindowEventKind.close_requested)
        return;

    CloseRequestLog* log = cast(CloseRequestLog*) context;
    if (log !is null)
        ++log.count;
    window.set_should_close(false);
}

private bool single_window_system_ownership(
    Allocator* allocator,
    WindowSystemConfig config,
) @system
{
    auto first_result = WindowSystem.create(allocator, config);
    if (first_result.isErr)
        return false;
    WindowSystem* first = first_result.take();

    auto second_result = WindowSystem.create(allocator, config);
    if (!second_result.isErr ||
        second_result.takeError().kind != WindowErrorKind.already_initialized)
    {
        first.deinit();
        return false;
    }

    first.deinit();

    auto replacement_result = WindowSystem.create(allocator, config);
    if (replacement_result.isErr)
        return false;
    WindowSystem* replacement = replacement_result.take();
    replacement.deinit();
    return true;
}

extern (C) int main() @system
{
    if (NativeWindowHandle.init.platform != NativeWindowPlatform.none ||
        NativeDisplayHandle.init.platform != NativeWindowPlatform.none)
        return 132;

    Allocator* allocator = mallocAllocator();

    WindowSystemConfig system_config;
    system_config.platform = WindowPlatform.headless;
    if (!single_window_system_ownership(allocator, system_config))
        return 1;

    auto system_result = WindowSystem.create(allocator, system_config);
    if (system_result.isErr)
        return 2;
    WindowSystem* system = system_result.take();
    scope (exit)
        system.deinit();

    if (!system.initialized || system.platform != WindowPlatform.headless)
        return 3;
    if (!WindowSystem.platform_compiled_in(WindowPlatform.headless))
        return 4;
    if (system.monitor_count != 2)
        return 5;

    auto primary_result = system.primary_monitor();
    if (primary_result.isErr)
        return 6;
    Monitor primary = primary_result.take();
    if (!primary.valid || primary.name.length == 0)
        return 7;

    auto mode_result = primary.video_mode();
    if (mode_result.isErr)
        return 8;
    const mode = mode_result.take();
    if (mode.width != 1920 || mode.height != 1080 || mode.refresh_rate != 60)
        return 9;

    auto secondary_result = system.monitor(1);
    if (secondary_result.isErr)
        return 120;
    Monitor secondary = secondary_result.take();
    if (!secondary.valid || secondary.name == primary.name)
        return 121;

    WindowConfig invalid_config;
    invalid_config.width = 0;
    auto invalid_result = system.create_window(invalid_config);
    if (!invalid_result.isErr || invalid_result.takeError().kind != WindowErrorKind.invalid_size)
        return 10;

    WindowConfig config;
    config.width = 320;
    config.height = 240;
    config.title = "xtb.window headless test";
    config.visible = false;

    auto first_result = system.create_window(config);
    if (first_result.isErr)
        return 11;
    Window* first = first_result.take();
    scope (exit)
        first.deinit();

    if (system.window_count != 1 || !first.valid)
        return 12;
    if (!same_size(first.size, WindowSize(320, 240)))
        return 13;
    if (!same_size(first.framebuffer_size, WindowSize(320, 240)))
        return 14;

    if (first.set_size(WindowSize(640, 360)).isErr)
        return 15;
    if (!same_size(first.size, WindowSize(640, 360)))
        return 16;

    if (first.set_title("headless renamed").isErr)
        return 17;
    const char[3] title_with_nul = ['x', '\0', 'y'];
    auto title_result = first.set_title(title_with_nul[]);
    if (!title_result.isErr || title_result.takeError().kind != WindowErrorKind.title_contains_nul)
        return 18;

    fail_next_operation(FakeGLFWOperation.set_window_title);
    auto failed_title = first.set_title("backend failure");
    if (!failed_title.isErr)
        return 100;
    const title_backend_error = failed_title.takeError();
    if (title_backend_error.kind != WindowErrorKind.backend_operation_failed ||
        title_backend_error.backend_code != fake_platform_error)
        return 101;

    fail_next_operation(FakeGLFWOperation.set_window_position);
    auto failed_position = first.set_position(WindowPosition(11, 13));
    if (!failed_position.isErr)
        return 102;
    const position_backend_error = failed_position.takeError();
    if (position_backend_error.kind != WindowErrorKind.backend_operation_failed ||
        position_backend_error.backend_code != fake_platform_error ||
        first.position != WindowPosition.init)
        return 103;

    fail_next_operation(FakeGLFWOperation.set_window_size);
    auto failed_size = first.set_size(WindowSize(800, 600));
    if (!failed_size.isErr)
        return 104;
    const size_backend_error = failed_size.takeError();
    if (size_backend_error.kind != WindowErrorKind.backend_operation_failed ||
        size_backend_error.backend_code != fake_platform_error ||
        !same_size(first.size, WindowSize(640, 360)))
        return 105;

    fail_next_operation(FakeGLFWOperation.set_input_mode);
    auto failed_cursor_mode = first.set_cursor_mode(CursorMode.hidden);
    if (!failed_cursor_mode.isErr)
        return 106;
    const cursor_backend_error = failed_cursor_mode.takeError();
    if (cursor_backend_error.kind != WindowErrorKind.backend_operation_failed ||
        cursor_backend_error.backend_code != fake_platform_error ||
        first.cursor_mode != CursorMode.normal)
        return 107;

    seed_backend_error();
    if (first.set_cursor_mode(CursorMode.hidden).isErr ||
        first.cursor_mode != CursorMode.hidden ||
        first.set_cursor_mode(CursorMode.normal).isErr)
        return 108;

    const restore_position = WindowPosition(23, 29);
    if (first.set_position(restore_position).isErr)
        return 122;

    fail_next_operation(FakeGLFWOperation.set_window_monitor);
    auto failed_fullscreen = first.set_fullscreen(true, primary);
    if (!failed_fullscreen.isErr)
        return 109;
    const fullscreen_backend_error = failed_fullscreen.takeError();
    if (fullscreen_backend_error.kind != WindowErrorKind.backend_operation_failed ||
        fullscreen_backend_error.backend_code != fake_platform_error ||
        first.fullscreen)
        return 110;

    if (first.set_fullscreen(true, primary).isErr || !first.fullscreen ||
        first.monitor.name != primary.name ||
        !same_size(first.size, WindowSize(1920, 1080)))
        return 116;

    fail_next_operation(FakeGLFWOperation.set_window_monitor);
    auto failed_monitor_switch = first.set_fullscreen(true, secondary);
    if (!failed_monitor_switch.isErr)
        return 123;
    const monitor_switch_error = failed_monitor_switch.takeError();
    if (monitor_switch_error.kind != WindowErrorKind.backend_operation_failed ||
        monitor_switch_error.backend_code != fake_platform_error ||
        first.monitor.name != primary.name)
        return 124;

    if (first.set_fullscreen(true, secondary).isErr ||
        first.monitor.name != secondary.name ||
        !same_size(first.size, WindowSize(2560, 1440)))
        return 125;

    if (first.set_fullscreen(true).isErr || first.monitor.name != secondary.name)
        return 126;

    fail_next_operation(FakeGLFWOperation.set_window_monitor);
    auto failed_windowed = first.set_fullscreen(false);
    if (!failed_windowed.isErr)
        return 117;
    const windowed_backend_error = failed_windowed.takeError();
    if (windowed_backend_error.kind != WindowErrorKind.backend_operation_failed ||
        windowed_backend_error.backend_code != fake_platform_error ||
        !first.fullscreen || first.monitor.name != secondary.name)
        return 118;
    if (first.set_fullscreen(false).isErr || first.fullscreen ||
        first.position != restore_position ||
        !same_size(first.size, WindowSize(640, 360)))
        return 119;

    first.request_close();
    if (!first.should_close())
        return 19;
    first.set_should_close(false);
    if (first.should_close())
        return 127;

    CloseRequestLog close_log;
    first.set_event_handler(WindowEventHandler(&cancel_close_request, &close_log));
    if (!queue_close(first) || system.poll_events().isErr ||
        close_log.count != 1 || first.should_close())
        return 128;
    first.set_event_handler(WindowEventHandler.init);

    if (!first.native_handle().isErr || !system.native_display_handle().isErr)
        return 20;

    auto second_result = system.create_window(config);
    if (second_result.isErr)
        return 21;
    Window* second = second_result.take();
    if (system.window_count != 2)
    {
        second.deinit();
        return 22;
    }
    second.deinit();
    if (system.window_count != 1)
        return 23;

    WindowConfig lock_config = config;
    lock_config.lock_key_modifiers = true;

    fail_next_operation(FakeGLFWOperation.set_input_mode);
    auto failed_lock_result = system.create_window(lock_config);
    if (!failed_lock_result.isErr)
        return 129;
    const lock_backend_error = failed_lock_result.takeError();
    if (lock_backend_error.kind != WindowErrorKind.backend_operation_failed ||
        lock_backend_error.backend_code != fake_platform_error ||
        system.window_count != 1)
        return 130;

    auto lock_result = system.create_window(lock_config);
    if (lock_result.isErr)
        return 131;
    Window* lock_window = lock_result.take();
    EventLog lock_event_log;
    lock_window.set_event_handler(WindowEventHandler(&record_event, &lock_event_log));
    const enabled_lock_modifiers = cast(KeyModifier)(
        cast(ubyte) KeyModifier.caps_lock |
        cast(ubyte) KeyModifier.num_lock);
    if (!queue_key(lock_window, Key.c, KeyAction.pressed, enabled_lock_modifiers) ||
        !queue_mouse_button(
            lock_window,
            MouseButton.left,
            KeyAction.pressed,
            enabled_lock_modifiers) ||
        system.poll_events().isErr ||
        lock_event_log.count != 2 ||
        lock_event_log.events[0].key_event.modifiers != enabled_lock_modifiers ||
        lock_event_log.events[1].mouse_button_event.modifiers != enabled_lock_modifiers)
    {
        lock_window.deinit();
        return 132;
    }
    lock_window.deinit();
    if (system.window_count != 1)
        return 133;

    EventLog event_log;
    first.set_event_handler(WindowEventHandler(&record_event, &event_log));

    fail_next_operation(FakeGLFWOperation.poll_events);
    auto failed_poll = system.poll_events();
    if (!failed_poll.isErr)
        return 114;
    const poll_backend_error = failed_poll.takeError();
    if (poll_backend_error.kind != WindowErrorKind.backend_operation_failed ||
        poll_backend_error.backend_code != fake_platform_error)
        return 115;

    const lock_modifiers = cast(KeyModifier)(
        cast(ubyte) KeyModifier.shift |
        cast(ubyte) KeyModifier.caps_lock |
        cast(ubyte) KeyModifier.num_lock);
    if (!queue_key(first, Key.a, KeyAction.pressed, lock_modifiers, 17) ||
        !queue_text(first, 'A') ||
        !queue_mouse_button(first, MouseButton.left, KeyAction.pressed, KeyModifier.control) ||
        !queue_cursor_position(first, 10, 5) ||
        !queue_cursor_position(first, 13, 9) ||
        !queue_scroll(first, 1, 0.5) ||
        !queue_scroll(first, -0.25, 2) ||
        !queue_cursor_enter(
            first, true) ||
        !queue_focus(first, false) ||
        !queue_window_position(first, 7, 9) ||
        !queue_window_size(first, 500, 400) ||
        !queue_framebuffer_size(first, 1000, 800) ||
        !queue_content_scale(first, 2, 2) ||
        !queue_maximized(first, true) ||
        !queue_minimized(first, true))
        return 24;

    if (system.poll_events().isErr)
        return 111;
    if (!first.key_down(Key.a) || !first.key_pressed(Key.a) ||
        first.key_released(Key.a) || first.key_repeated(Key.a))
        return 25;
    if (!first.mouse_button_down(MouseButton.left) ||
        !first.mouse_button_pressed(
            MouseButton.left) ||
        first.mouse_button_released(MouseButton.left))
        return 26;
    if (first.cursor_position.x != 13 || first.cursor_position.y != 9 ||
        first.cursor_delta.x != 13 || first.cursor_delta.y != 9)
        return 27;
    if (first.scroll_delta.x != 0.75 || first.scroll_delta.y != 2.5 || !first.scrolled)
        return 28;
    if (!first.cursor_inside || !first.cursor_entered || first.cursor_left)
        return 29;
    if (first.focused || !first.maximized || !first.minimized)
        return 30;
    if (event_log.count != 15 ||
        event_log.events[0].kind != WindowEventKind.key ||
        event_log.events[0].key_event.key != Key.a ||
        event_log.events[0].key_event.scan_code != 17 ||
        event_log.events[0].key_event.action != KeyAction.pressed ||
        event_log.events[0].key_event.modifiers != KeyModifier.shift ||
        event_log.events[1].kind != WindowEventKind.text_input ||
        event_log.events[1].text_input.codepoint != 'A' ||
        event_log.events[2].kind != WindowEventKind.mouse_button ||
        event_log.events[2].mouse_button_event.button != MouseButton.left ||
        event_log.events[2].mouse_button_event.modifiers != KeyModifier.control ||
        event_log.events[7].kind != WindowEventKind.cursor_entered ||
        event_log.events[14].kind != WindowEventKind.minimized_changed)
        return 31;

    if (!queue_key(first, Key.a, KeyAction.released) ||
        !queue_key(first, Key.b, KeyAction.pressed) ||
        !queue_key(first, Key.b, KeyAction.released) ||
        !queue_mouse_button(first, MouseButton.left, KeyAction.released) ||
        !queue_mouse_button(first, MouseButton.right, KeyAction.pressed) ||
        !queue_mouse_button(first, MouseButton.right, KeyAction.released) ||
        !queue_cursor_enter(first, false) ||
        !queue_cursor_position(first, 15, 10))
        return 32;

    if (system.poll_events().isErr)
        return 112;
    if (first.key_down(Key.a) || first.key_pressed(Key.a) || !first.key_released(Key.a))
        return 33;
    if (first.key_down(Key.b) || !first.key_pressed(Key.b) || !first.key_released(Key.b))
        return 34;
    if (first.mouse_button_down(MouseButton.left) ||
        first.mouse_button_pressed(MouseButton.left) ||
        !first.mouse_button_released(MouseButton.left))
        return 35;
    if (first.mouse_button_down(MouseButton.right) ||
        !first.mouse_button_pressed(
            MouseButton.right) ||
        !first.mouse_button_released(MouseButton.right))
        return 36;
    if (first.cursor_inside || first.cursor_entered || !first.cursor_left ||
        first.cursor_delta.x != 2 || first.cursor_delta.y != 1 ||
        event_log.events[21].kind != WindowEventKind.cursor_left)
        return 37;
    if (first.scrolled || first.scroll_delta.x != 0 || first.scroll_delta.y != 0)
        return 38;

    if (system.poll_events().isErr)
        return 113;
    if (first.key_pressed(Key.b) || first.key_released(Key.b) ||
        first.mouse_button_pressed(MouseButton.right) ||
        first.mouse_button_released(
            MouseButton.right) ||
        first.cursor_delta.x != 0 || first.cursor_delta.y != 0 ||
        first.cursor_entered || first.cursor_left)
        return 39;

    if (first.has_opengl_context())
        return 40;
    auto generic_context_result = first.make_context_current();
    if (!generic_context_result.isErr ||
        generic_context_result.takeError().kind != WindowErrorKind.context_unavailable)
        return 41;

    const es_config = OpenGLConfig.opengl_es();
    if (es_config.api != OpenGLAPI.opengl_es ||
        es_config.context_version.major != 3 ||
        es_config.context_version.minor != 0 ||
        es_config.profile != OpenGLProfile.any)
        return 42;

    OpenGLConfig invalid_gl_config;
    invalid_gl_config.context_version = OpenGLVersion(3, 1);
    invalid_gl_config.profile = OpenGLProfile.core;
    auto invalid_gl_result = system.create_opengl_window(config, invalid_gl_config);
    if (!invalid_gl_result.isErr ||
        invalid_gl_result.takeError().kind != WindowErrorKind.invalid_context_config)
        return 43;

    auto null_allocator_gl_result = system.create_opengl_window(
        cast(Allocator*) null,
        config,
    );
    if (!null_allocator_gl_result.isErr ||
        null_allocator_gl_result.takeError()
            .kind != WindowErrorKind.allocation_failed)
        return 44;

    OpenGLConfig unavailable_gl_config;
    unavailable_gl_config.context_version = OpenGLVersion(99, 0);
    auto unavailable_gl_result = system.create_opengl_window(
        config,
        unavailable_gl_config,
    );
    if (!unavailable_gl_result.isErr ||
        unavailable_gl_result.takeError().kind != WindowErrorKind.context_unavailable)
        return 45;

    OpenGLConfig gl_config;
    gl_config.creation_api = OpenGLContextCreationAPI.os_mesa;
    gl_config.debug_context = true;
    gl_config.robustness = OpenGLRobustness.no_reset_notification;
    gl_config.release_behavior = OpenGLReleaseBehavior.flush;
    gl_config.framebuffer.samples = 4;
    gl_config.framebuffer.srgb_capable = true;

    auto gl_result = system.create_opengl_window(config, gl_config);
    if (gl_result.isErr)
        return 46;

    Window* gl_window = gl_result.take();
    scope (exit)
        gl_window.deinit();

    if (!gl_window.has_opengl_context() || system.window_count != 2)
        return 47;
    if (gl_window.context_is_current())
        return 48;

    auto premature_swap = gl_window.swap_buffers();
    if (!premature_swap.isErr ||
        premature_swap.takeError().kind != WindowErrorKind.no_current_context)
        return 49;

    if (gl_window.make_context_current().isErr || !gl_window.context_is_current())
        return 50;
    if (gl_window.set_swap_interval(1).isErr || swap_interval(gl_window) != 1)
        return 51;

    auto info_result = gl_window.opengl_context_info();
    if (info_result.isErr)
        return 52;
    const info = info_result.take();
    if (info.api != OpenGLAPI.opengl ||
        info.context_version.major != gl_config.context_version.major ||
        info.context_version.minor != gl_config.context_version.minor ||
        info.creation_api != OpenGLContextCreationAPI.os_mesa ||
        info.profile != OpenGLProfile.core ||
        !info.debug_context ||
        info.robustness != OpenGLRobustness.no_reset_notification ||
        info.release_behavior != OpenGLReleaseBehavior.flush ||
        !info.double_buffered)
        return 53;

    const creation_hints = opengl_hints(gl_window);
    if (creation_hints.version_major != gl_config.context_version.major ||
        creation_hints.version_minor != gl_config.context_version.minor ||
        creation_hints.debug_context != gl_config.debug_context ||
        creation_hints.samples != gl_config.framebuffer.samples ||
        creation_hints.srgb_capable != gl_config.framebuffer.srgb_capable ||
        !creation_hints.double_buffered)
        return 54;

    const char[3] proc_with_nul = ['g', '\0', 'l'];
    auto invalid_proc = gl_window.opengl_proc_address(proc_with_nul[]);
    if (!invalid_proc.isErr || invalid_proc.takeError().kind != WindowErrorKind.invalid_proc_name)
        return 55;

    auto proc_result = gl_window.opengl_proc_address("glGetString");
    if (proc_result.isErr || proc_result.take() is null)
        return 56;

    auto extension_result = gl_window.opengl_extension_supported("GL_FAKE_extension");
    if (extension_result.isErr || !extension_result.take())
        return 57;

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
        return 58;

    OpenGLConfig shared_config = gl_config;
    shared_config.share_context_with = gl_window;
    auto shared_result = system.create_opengl_window(config, shared_config);
    if (shared_result.isErr)
        return 59;
    Window* shared_window = shared_result.take();
    if (!shared_window.has_opengl_context() || system.window_count != 3 ||
        opengl_hints(shared_window).shared_context_with !is gl_window)
    {
        shared_window.deinit();
        return 60;
    }
    shared_window.deinit();
    if (system.window_count != 2)
        return 61;

    const swaps_before = swap_count(gl_window);
    if (gl_window.swap_buffers().isErr || swap_count(gl_window) != swaps_before + 1)
        return 62;
    if (clear_current_context().isErr || gl_window.context_is_current())
        return 63;

    make_foreign_context_current();
    if (gl_window.context_is_current())
        return 64;

    if (gl_window.make_context_current().isErr || !gl_window.context_is_current())
        return 65;
    if (clear_current_context().isErr)
        return 66;

    return 0;
}
