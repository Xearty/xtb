module tests.window_tests;

nothrow @nogc:

import tests.support.fake_glfw : FakeGLFWOperation, fail_next_operation,
    fake_feature_unavailable, fake_platform_error, fake_version_unavailable,
    dispatch_cursor_enter_now, dispatch_cursor_position_now, dispatch_key_now,
    dispatch_mouse_button_now, dispatch_scroll_now,
    make_foreign_context_current, opengl_hints,
    queue_content_scale, queue_cursor_enter, queue_cursor_position, queue_focus,
    queue_close, queue_framebuffer_size, queue_key, queue_maximized, queue_minimized,
    queue_mouse_button, queue_monitor_connected, queue_monitor_disconnected,
    queue_refresh, queue_scroll, queue_text, queue_window_position, queue_window_size,
    seed_backend_error, set_backend_version, set_default_content_scale, swap_count,
    swap_interval;
import xtb.allocators.malloc : mallocAllocator;
import xtb.memory : Allocator;
import xtb.thread_context : ThreadContextScope;
import xtb.window;
import xtb.window.opengl;

private bool same_size(WindowSize left, WindowSize right) pure @safe
{
    return left.width == right.width && left.height == right.height;
}

private bool has_position(Window* window, WindowPosition expected) @system
{
    auto position = window.position();
    return position.isSome && position.value == expected;
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

private struct WindowSystemEventLog
{
    WindowSystemEventKind[4] kinds;
    bool[4] monitor_valid;
    size_t count;
}

private void record_system_event(
    WindowSystem*,
    scope const WindowSystemEvent* event,
    void* context,
) @system
{
    WindowSystemEventLog* log = cast(WindowSystemEventLog*) context;
    if (log is null || log.count >= log.kinds.length)
        return;
    log.kinds[log.count] = event.kind;
    log.monitor_valid[log.count] = event.monitor.valid;
    ++log.count;
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

private struct FullscreenNestedErrorLog
{
    bool injected;
}

private void inject_nested_fullscreen_error(
    Window* window,
    scope const WindowEvent* event,
    void* context,
) @system
{
    FullscreenNestedErrorLog* log = cast(FullscreenNestedErrorLog*) context;
    if (log is null || log.injected || event.kind != WindowEventKind.moved)
        return;

    log.injected = true;
    fail_next_operation(FakeGLFWOperation.set_window_position);
    // glfwSetWindowMonitor synchronously dispatched this callback. Make a
    // nested GLFW call fail so the outer transition has a foreign error in
    // GLFW's shared last-error slot when it eventually returns.
    window.set_position(WindowPosition(101, 103));
}

private struct ReentrantFullscreenExitLog
{
    bool exited;
}

private void exit_fullscreen_reentrantly(
    Window* window,
    scope const WindowEvent* event,
    void* context,
) @system
{
    ReentrantFullscreenExitLog* log = cast(ReentrantFullscreenExitLog*) context;
    if (log is null || log.exited || event.kind != WindowEventKind.moved)
        return;

    log.exited = true;
    // The move callback is synchronous inside the outer fullscreen entry. The
    // nested exit therefore proves that restore state was staged before GLFW
    // was allowed to call back into application code.
    window.set_fullscreen(false);
}

private bool expect_backend_version(
    Allocator* allocator,
    WindowSystemConfig config,
    int major,
    int minor,
    bool supported,
) @system
{
    set_backend_version(major, minor);
    auto result = WindowSystem.create(allocator, config);
    if (supported)
    {
        if (result.isErr)
            return false;
        result.take().deinit();
        return true;
    }

    return result.isErr &&
        result.takeError().kind == WindowErrorKind.unsupported_backend_version;
}

private bool runtime_backend_version_gate(
    Allocator* allocator,
    WindowSystemConfig config,
) @system
{
    scope (exit) set_backend_version(3, 4);

    return expect_backend_version(allocator, config, 3, 3, false) &&
        expect_backend_version(allocator, config, 3, 4, true) &&
        expect_backend_version(allocator, config, 3, 5, true) &&
        expect_backend_version(allocator, config, 4, 0, false) &&
        expect_backend_version(allocator, config, 2, 9, false);
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

private bool synchronous_transition_publication(
    WindowSystem* system,
    Window* first,
    WindowConfig config,
) @system
{
    auto second_result = system.create_window(config);
    if (second_result.isErr)
        return false;
    Window* second = second_result.take();
    scope (exit)
        second.deinit();

    if (system.window_count != 2)
        return false;

    const start = first.cursor_position;

    // Model callbacks delivered synchronously by GLFW between two polling
    // calls. Persistent state must change immediately, while transition
    // queries must continue exposing the previous published batch until the
    // next poll completes.
    if (!dispatch_key_now(first, Key.c, KeyAction.pressed) ||
        !dispatch_key_now(first, Key.c, KeyAction.released) ||
        !dispatch_mouse_button_now(first, MouseButton.middle, MouseButtonAction.pressed) ||
        !dispatch_cursor_position_now(first, start.x + 5, start.y + 4) ||
        !dispatch_scroll_now(
            first, 1, 2) ||
        !dispatch_cursor_enter_now(first, true) ||
        !dispatch_key_now(second, Key.e, KeyAction.pressed))
        return false;

    if (first.key_down(Key.c) || first.key_pressed(Key.c) ||
        first.key_released(Key.c) || first.key_repeated(Key.c) ||
        !first.mouse_button_down(MouseButton.middle) ||
        first.mouse_button_pressed(MouseButton.middle) ||
        first.mouse_button_released(
            MouseButton.middle) ||
        first.cursor_position != CursorPosition(start.x + 5, start.y + 4) ||
        first.cursor_delta != CursorDelta.init || first.scrolled ||
        !first.cursor_inside || first.cursor_entered || first.cursor_left ||
        !second.key_down(Key.e) || second.key_pressed(Key.e))
        return false;

    // Events dispatched by glfwPollEvents join the already-pending
    // between-poll callbacks in one publication batch.
    if (!queue_key(first, Key.c, KeyAction.repeated) ||
        !queue_mouse_button(first, MouseButton.middle, MouseButtonAction.released) ||
        !queue_cursor_position(first, start.x + 8, start.y + 10) ||
        !queue_scroll(first, -0.25, 0.5) ||
        !queue_cursor_enter(first, false) ||
        !queue_key(second, Key.e, KeyAction.released))
        return false;
    system.poll_events();

    const first_key = first.key_state(Key.c);
    const first_button = first.mouse_button_state(MouseButton.middle);
    const second_key = second.key_state(Key.e);
    if (!first_key.down || !first_key.pressed || !first_key.released ||
        !first_key.repeated || first_button.down || !first_button.pressed ||
        !first_button.released ||
        first.cursor_delta != CursorDelta(8, 10) ||
        first.scroll_delta != ScrollDelta(0.75, 2.5) || !first.scrolled ||
        first.cursor_inside || !first.cursor_entered || !first.cursor_left ||
        second_key.down || !second_key.pressed || !second_key.released)
        return false;

    // An empty poll replaces the published batch with an empty one without
    // disturbing persistent state.
    system.poll_events();
    if (!first.key_down(Key.c) || first.key_pressed(Key.c) ||
        first.key_released(Key.c) || first.key_repeated(Key.c) ||
        first.mouse_button_down(
            MouseButton.middle) ||
        first.mouse_button_pressed(MouseButton.middle) ||
        first.mouse_button_released(MouseButton.middle) ||
        first.cursor_delta != CursorDelta.init || first.scrolled ||
        first.cursor_entered || first.cursor_left || second.key_down(Key.e) ||
        second.key_pressed(Key.e) || second.key_released(Key.e))
        return false;

    // poll_events is a command: it publishes already-observed transitions
    // without attempting to attribute GLFW's ambient last-error slot to the
    // poll. A stale backend error must therefore have no effect on publication.
    if (!dispatch_key_now(first, Key.f, KeyAction.pressed))
        return false;
    seed_backend_error();
    system.poll_events();
    if (!first.key_down(Key.f) || !first.key_pressed(Key.f))
        return false;

    system.poll_events();
    if (!first.key_down(Key.f) || first.key_pressed(Key.f))
        return false;

    return true;
}

extern (C) int main() @system
{
    ThreadContextScope thread_context = ThreadContextScope.acquire();

    if (NativeWindowHandle.init.platform != NativeWindowPlatform.none ||
        NativeDisplayHandle.init.platform != NativeWindowPlatform.none)
        return 132;

    Allocator* allocator = mallocAllocator();

    WindowSystemConfig system_config;
    system_config.platform = WindowPlatform.headless;
    if (!runtime_backend_version_gate(allocator, system_config))
        return 147;
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

    Monitor primary = system.primary_monitor();
    if (!primary.valid || primary.name.length == 0)
        return 7;

    auto mode_result = primary.video_mode();
    if (mode_result.isErr)
        return 8;
    const mode = mode_result.take();
    if (mode.width != 1920 || mode.height != 1080 || mode.refresh_rate != 60)
        return 9;

    WindowSystemEventLog system_event_log;
    system.set_event_handler(WindowSystemEventHandler(&record_system_event, &system_event_log));
    if (!queue_monitor_disconnected(1))
        return 137;
    system.poll_events();
    if (system_event_log.count != 1 ||
        system_event_log.kinds[0] != WindowSystemEventKind.monitor_disconnected ||
        !system_event_log.monitor_valid[0] || system.monitor_count != 1)
        return 137;
    if (!queue_monitor_connected(1))
        return 138;
    system.poll_events();
    if (system_event_log.count != 2 ||
        system_event_log.kinds[1] != WindowSystemEventKind.monitor_connected ||
        !system_event_log.monitor_valid[1] || system.monitor_count != 2)
        return 138;
    if (!queue_monitor_disconnected(0) || !queue_monitor_disconnected(1))
        return 139;
    system.poll_events();
    if (system_event_log.count != 4 ||
        system_event_log.kinds[2] != WindowSystemEventKind.monitor_disconnected ||
        system_event_log.kinds[3] != WindowSystemEventKind.monitor_disconnected ||
        !system_event_log.monitor_valid[2] || !system_event_log.monitor_valid[3] ||
        system.monitor_count != 0 || system.primary_monitor().valid ||
        system.monitor(0).valid)
        return 139;

    system.set_event_handler(WindowSystemEventHandler.init);
    if (!queue_monitor_connected(0) || !queue_monitor_connected(1))
        return 140;
    system.poll_events();
    if (system.monitor_count != 2)
        return 140;
    primary = system.primary_monitor();
    if (!primary.valid)
        return 141;

    Monitor secondary = system.monitor(1);
    if (!secondary.valid || secondary.name == primary.name || system.monitor(2).valid)
        return 121;

    set_default_content_scale(1.5f, 1.25f);

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
    if (first.visible)
        return 146;
    if (first.fullscreen_monitor.valid)
        return 173;

    static assert(is(typeof(first.show()) == void));
    static assert(is(typeof(first.hide()) == void));
    static assert(is(typeof(first.minimize()) == void));
    static assert(is(typeof(first.maximize()) == void));
    static assert(is(typeof(first.restore()) == void));
    static assert(is(typeof(first.fullscreen_monitor()) == Monitor));

    first.show();
    if (!first.visible)
        return 147;
    first.show();
    if (!first.visible)
        return 148;

    first.hide();
    if (first.visible)
        return 149;
    first.hide();
    if (first.visible)
        return 150;

    fail_next_operation(FakeGLFWOperation.show_window);
    first.show();
    if (first.visible)
        return 151;
    first.show();
    if (!first.visible)
        return 152;

    fail_next_operation(FakeGLFWOperation.hide_window);
    first.hide();
    if (!first.visible)
        return 153;
    first.hide();
    if (first.visible)
        return 154;

    if (first.minimized || first.maximized)
        return 161;

    first.minimize();
    if (!first.minimized || first.maximized)
        return 162;

    fail_next_operation(FakeGLFWOperation.restore_window);
    first.restore();
    if (!first.minimized)
        return 163;

    first.restore();
    if (first.minimized || first.maximized)
        return 164;

    first.maximize();
    if (first.minimized || !first.maximized)
        return 165;

    fail_next_operation(FakeGLFWOperation.restore_window);
    first.restore();
    if (!first.maximized)
        return 166;

    first.restore();
    if (first.minimized || first.maximized)
        return 167;

    fail_next_operation(FakeGLFWOperation.iconify_window);
    first.minimize();
    if (first.minimized)
        return 168;

    fail_next_operation(FakeGLFWOperation.maximize_window);
    first.maximize();
    if (first.maximized)
        return 169;

    if (!same_size(first.size, WindowSize(320, 240)))
        return 13;
    if (!same_size(first.framebuffer_size, WindowSize(320, 240)))
        return 14;

    if (first.content_scale != ContentScale(1.5f, 1.25f))
        return 139;

    seed_backend_error();
    if (first.content_scale != ContentScale(1.5f, 1.25f))
        return 143;

    fail_next_operation(FakeGLFWOperation.get_window_content_scale);
    if (first.content_scale != ContentScale.init)
        return 144;
    if (first.content_scale != ContentScale(1.5f, 1.25f))
        return 145;

    static assert(is(typeof(first.set_size(WindowSize(640, 360))) == void));
    static assert(is(typeof(first.set_position(WindowPosition.init)) == void));
    static assert(is(typeof(first.set_fullscreen(false)) == void));
    static assert(is(typeof(first.set_cursor_mode(CursorMode.normal)) == void));
    static assert(is(typeof(system.poll_events()) == void));

    first.set_size(WindowSize(640, 360));
    if (!same_size(first.size, WindowSize(640, 360)))
        return 16;

    static assert(is(typeof(first.set_title("headless renamed")) == void));
    first.set_title("headless renamed");

    fail_next_operation(FakeGLFWOperation.set_window_title);
    first.set_title("backend failure");

    fail_next_operation(FakeGLFWOperation.set_window_position);
    first.set_position(WindowPosition(11, 13));
    if (!has_position(first, WindowPosition.init))
        return 103;

    fail_next_operation(
        FakeGLFWOperation.get_window_position,
        fake_feature_unavailable,
    );
    if (!first.position().isNone || !has_position(first, WindowPosition.init))
        return 102;

    fail_next_operation(FakeGLFWOperation.set_window_size);
    first.set_size(WindowSize(800, 600));
    if (!same_size(first.size, WindowSize(640, 360)))
        return 105;

    fail_next_operation(FakeGLFWOperation.set_input_mode);
    first.set_cursor_mode(CursorMode.hidden);
    if (first.cursor_mode != CursorMode.normal)
        return 107;

    seed_backend_error();
    first.set_cursor_mode(CursorMode.hidden);
    if (first.cursor_mode != CursorMode.hidden)
        return 108;
    first.set_cursor_mode(CursorMode.normal);

    const restore_position = WindowPosition(23, 29);
    first.set_position(restore_position);
    if (!has_position(first, restore_position))
        return 122;

    // A real restore-position query failure aborts the transition.
    fail_next_operation(FakeGLFWOperation.get_window_position);
    first.set_fullscreen(true, primary);
    if (first.fullscreen || !has_position(first, restore_position) ||
        !same_size(first.size, WindowSize(640, 360)))
        return 134;

    // A real restore-size query failure also leaves the window unchanged.
    fail_next_operation(FakeGLFWOperation.get_window_size);
    first.set_fullscreen(true, primary);
    if (first.fullscreen || !has_position(first, restore_position) ||
        !same_size(first.size, WindowSize(640, 360)))
        return 136;

    // An error produced by a nested GLFW call from a synchronous callback
    // must not be mistaken for failure of the outer fullscreen transition.
    // The follow-up exit also verifies that restore state was committed despite
    // the unrelated nested error.
    FullscreenNestedErrorLog nested_error_log;
    first.set_event_handler(WindowEventHandler(
            &inject_nested_fullscreen_error,
            &nested_error_log,
    ));
    first.set_fullscreen(true, primary);
    first.set_event_handler(WindowEventHandler.init);
    if (!nested_error_log.injected || !first.fullscreen ||
        first.fullscreen_monitor.name != primary.name)
        return 158;
    first.set_fullscreen(false);
    if (first.fullscreen || !has_position(first, restore_position) ||
        !same_size(first.size, WindowSize(640, 360)))
        return 159;

    // A callback caused by fullscreen entry may itself leave fullscreen before
    // the outer glfwSetWindowMonitor returns. The nested exit must see valid
    // restore state, and the outer call must reconcile bookkeeping with the
    // final backend mode instead of blindly committing its requested mode.
    ReentrantFullscreenExitLog reentrant_exit_log;
    first.set_event_handler(WindowEventHandler(
            &exit_fullscreen_reentrantly,
            &reentrant_exit_log,
    ));
    first.set_fullscreen(true, primary);
    first.set_event_handler(WindowEventHandler.init);
    if (!reentrant_exit_log.exited || first.fullscreen ||
        !has_position(first, restore_position) ||
        !same_size(first.size, WindowSize(640, 360)))
        return 160;

    // A backend transition failure is an unobservable command no-op.
    fail_next_operation(FakeGLFWOperation.set_window_monitor);
    first.set_fullscreen(true, primary);
    if (first.fullscreen)
        return 110;

    first.show();
    if (!first.visible)
        return 155;

    first.set_fullscreen(true, primary);
    if (!first.fullscreen || first.fullscreen_monitor.name != primary.name ||
        !same_size(first.size, WindowSize(1920, 1080)))
        return 116;

    first.maximize();
    if (first.maximized || first.fullscreen_monitor.name != primary.name)
        return 170;

    first.minimize();
    if (!first.minimized || !first.fullscreen ||
        first.fullscreen_monitor.name != primary.name)
        return 171;
    first.restore();
    if (first.minimized || !first.fullscreen ||
        first.fullscreen_monitor.name != primary.name)
        return 172;

    first.hide();
    if (!first.visible)
        return 156;
    first.show();
    if (!first.visible)
        return 157;

    fail_next_operation(FakeGLFWOperation.set_window_monitor);
    first.set_fullscreen(true, secondary);
    if (first.fullscreen_monitor.name != primary.name)
        return 124;

    first.set_fullscreen(true, secondary);
    if (first.fullscreen_monitor.name != secondary.name ||
        !same_size(first.size, WindowSize(2560, 1440)))
        return 125;

    first.set_fullscreen(true);
    if (first.fullscreen_monitor.name != secondary.name)
        return 126;

    fail_next_operation(FakeGLFWOperation.set_window_monitor);
    first.set_fullscreen(false);
    if (!first.fullscreen || first.fullscreen_monitor.name != secondary.name)
        return 118;

    first.set_fullscreen(false);
    if (first.fullscreen || !has_position(first, restore_position) ||
        !same_size(first.size, WindowSize(640, 360)))
        return 119;

    // Wayland-style lack of global positioning must not prevent fullscreen.
    fail_next_operation(
        FakeGLFWOperation.get_window_position,
        fake_feature_unavailable,
    );
    first.set_fullscreen(true, primary);
    if (!first.fullscreen || first.fullscreen_monitor.name != primary.name)
        return 133;
    first.set_fullscreen(false);
    if (first.fullscreen || !same_size(first.size, WindowSize(640, 360)))
        return 135;

    first.request_close();
    if (!first.should_close())
        return 19;
    first.set_should_close(false);
    if (first.should_close())
        return 127;

    CloseRequestLog close_log;
    first.set_event_handler(WindowEventHandler(&cancel_close_request, &close_log));
    if (!queue_close(first))
        return 128;
    system.poll_events();
    if (close_log.count != 1 || first.should_close())
        return 128;
    first.set_event_handler(WindowEventHandler.init);

    if (first.native_handle().valid || system.native_display_handle().valid)
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
            MouseButtonAction.pressed,
            enabled_lock_modifiers))
    {
        lock_window.deinit();
        return 132;
    }
    system.poll_events();
    if (lock_event_log.count != 2 ||
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

    const lock_modifiers = cast(KeyModifier)(
        cast(ubyte) KeyModifier.shift |
            cast(
                ubyte) KeyModifier.caps_lock |
            cast(ubyte) KeyModifier.num_lock);
    if (!queue_key(first, Key.a, KeyAction.pressed, lock_modifiers, 17) ||
        !queue_text(first, 'A') ||
        !queue_mouse_button(first, MouseButton.left, MouseButtonAction.pressed, KeyModifier.control) ||
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

    system.poll_events();
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
    if (first.content_scale != ContentScale(2, 2))
        return 140;
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
        event_log.events[2].mouse_button_event.action != MouseButtonAction.pressed ||
        event_log.events[2].mouse_button_event.modifiers != KeyModifier.control ||
        event_log.events[7].kind != WindowEventKind.cursor_entered ||
        event_log.events[8].kind != WindowEventKind.focus_lost ||
        event_log.events[12].kind != WindowEventKind.content_scale_changed ||
        event_log.events[12].content_scale != ContentScale(2, 2) ||
        event_log.events[14].kind != WindowEventKind.minimized_changed)
        return 31;

    if (!queue_key(first, Key.a, KeyAction.released) ||
        !queue_key(first, Key.b, KeyAction.pressed) ||
        !queue_key(first, Key.b, KeyAction.released) ||
        !queue_mouse_button(first, MouseButton.left, MouseButtonAction.released) ||
        !queue_mouse_button(first, MouseButton.right, MouseButtonAction.pressed) ||
        !queue_mouse_button(
            first, MouseButton.right, MouseButtonAction.released) ||
        !queue_cursor_enter(first, false) ||
        !queue_cursor_position(first, 15, 10) ||
        !queue_focus(first, true))
        return 32;

    system.poll_events();
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
        event_log.events[21].kind != WindowEventKind.cursor_left ||
        event_log.events[23].kind != WindowEventKind.focus_gained ||
        !first.focused)
        return 37;
    if (first.scrolled || first.scroll_delta.x != 0 || first.scroll_delta.y != 0)
        return 38;

    if (!queue_refresh(first))
        return 113;

    system.poll_events();
    if (event_log.count != 25 ||
        event_log.events[24].kind != WindowEventKind.refresh_requested)
        return 115;
    if (first.key_pressed(Key.b) || first.key_released(Key.b) ||
        first.mouse_button_pressed(MouseButton.right) ||
        first.mouse_button_released(
            MouseButton.right) ||
        first.cursor_delta.x != 0 || first.cursor_delta.y != 0 ||
        first.cursor_entered || first.cursor_left)
        return 39;

    first.set_event_handler(WindowEventHandler.init);
    if (!synchronous_transition_publication(system, first, config))
        return 158;
    if (system.window_count != 1)
        return 159;

    if (first.has_opengl_context())
        return 40;

    const es_config = OpenGLConfig.opengl_es();
    if (es_config.api != OpenGLAPI.opengl_es ||
        es_config.context_version.major != 3 ||
        es_config.context_version.minor != 0 ||
        es_config.profile != OpenGLProfile.any)
        return 42;

    OpenGLConfig unavailable_gl_config;
    unavailable_gl_config.context_version = OpenGLVersion(99, 0);
    auto unavailable_gl_result = system.create_opengl_window(
        config,
        unavailable_gl_config,
    );
    if (!unavailable_gl_result.isErr)
        return 45;
    const unavailable_gl_error = unavailable_gl_result.takeError();
    if (unavailable_gl_error.kind != WindowErrorKind.window_creation_failed ||
        unavailable_gl_error.backend_code != fake_version_unavailable)
        return 44;

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

    static assert(is(typeof(gl_window.make_context_current()) == void));
    static assert(is(typeof(clear_current_context()) == void));
    static assert(is(typeof(gl_window.swap_buffers()) == void));
    static assert(is(typeof(gl_window.set_swap_interval(1)) == void));
    static assert(is(typeof(gl_window.opengl_proc_address("glGetString")) == OpenGLProc));
    static assert(is(typeof(gl_window.opengl_extension_supported("GL_FAKE_extension")) == bool));

    gl_window.make_context_current();
    if (!gl_window.context_is_current())
        return 50;
    gl_window.set_swap_interval(1);
    if (swap_interval(gl_window) != 1)
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

    char[255] longest_api_name;
    longest_api_name[] = 'a';
    if (gl_window.opengl_proc_address(longest_api_name[]) !is null ||
        gl_window.opengl_extension_supported(longest_api_name[]))
        return 146;

    if (gl_window.opengl_proc_address("glGetString") is null)
        return 56;
    if (!gl_window.opengl_extension_supported("GL_FAKE_extension"))
        return 57;

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
    gl_window.swap_buffers();
    if (swap_count(gl_window) != swaps_before + 1)
        return 62;
    clear_current_context();
    if (gl_window.context_is_current())
        return 63;

    make_foreign_context_current();
    if (gl_window.context_is_current())
        return 64;

    gl_window.make_context_current();
    if (!gl_window.context_is_current())
        return 65;
    clear_current_context();

    return 0;
}
