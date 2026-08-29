module tests.support.fake_glfw;

nothrow @nogc:

import core.stdc.string : strcmp;
import xtb.window : Key, KeyAction, KeyModifier, MouseButton, Window;
import G = xtb.window.internal.glfw;

enum FakeGLFWOperation : ubyte
{
    none,
    poll_events,
    set_window_title,
    get_window_position,
    set_window_position,
    get_window_size,
    set_window_size,
    get_window_content_scale,
    set_window_monitor,
    set_input_mode,
}

enum int fake_platform_error = G.GLFW_PLATFORM_ERROR;
enum int fake_feature_unavailable = G.GLFW_FEATURE_UNAVAILABLE;
enum int fake_version_unavailable = G.GLFW_VERSION_UNAVAILABLE;

struct FakeOpenGLHints
{
    int client_api;
    int version_major;
    int version_minor;
    int profile;
    int creation_api;
    int robustness;
    int release_behavior;
    bool forward_compatible;
    bool debug_context;
    bool no_error;
    int samples;
    bool srgb_capable;
    bool double_buffered;
    Window* shared_context_with;
}

private struct Hints
{
    int client_api = G.GLFW_OPENGL_API;
    int version_major = 1;
    int version_minor;
    int profile = G.GLFW_OPENGL_ANY_PROFILE;
    int creation_api = G.GLFW_NATIVE_CONTEXT_API;
    int robustness = G.GLFW_NO_ROBUSTNESS;
    int release_behavior = G.GLFW_ANY_RELEASE_BEHAVIOR;
    int forward_compatible;
    int debug_context;
    int no_error;
    int samples;
    int srgb_capable;
    int double_buffered = G.GLFW_TRUE;
    int visible = G.GLFW_TRUE;
    int resizable = G.GLFW_TRUE;
    int decorated = G.GLFW_TRUE;
    int focused = G.GLFW_TRUE;
    int maximized;
}

private struct FakeMonitor
{
    const(char)* name;
    G.GLFWvidmode mode;
    bool connected = true;
}

private struct FakeWindow
{
    bool alive;
    int width;
    int height;
    int x;
    int y;
    int should_close;
    void* user;
    double cursor_x = 0;
    double cursor_y = 0;
    int cursor_mode = G.GLFW_CURSOR_NORMAL;
    bool lock_key_modifiers;
    bool focused = true;
    bool minimized;
    bool maximized;
    float content_scale_x = 1;
    float content_scale_y = 1;
    Hints hints;
    G.GLFWmonitor* monitor;
    G.GLFWwindow* shared_context;
    size_t swap_count;
    int swap_interval;

    G.GLFWkeyfun key_callback;
    G.GLFWcharfun char_callback;
    G.GLFWmousebuttonfun mouse_button_callback;
    G.GLFWcursorposfun cursor_position_callback;
    G.GLFWcursorenterfun cursor_enter_callback;
    G.GLFWscrollfun scroll_callback;
    G.GLFWwindowposfun window_position_callback;
    G.GLFWwindowsizefun window_size_callback;
    G.GLFWwindowclosefun window_close_callback;
    G.GLFWwindowrefreshfun window_refresh_callback;
    G.GLFWwindowfocusfun window_focus_callback;
    G.GLFWwindowiconifyfun window_iconify_callback;
    G.GLFWwindowmaximizefun window_maximize_callback;
    G.GLFWframebuffersizefun framebuffer_size_callback;
    G.GLFWwindowcontentscalefun content_scale_callback;
}

private enum FakeEventKind : ubyte
{
    key,
    text,
    mouse_button,
    cursor_position,
    cursor_enter,
    scroll,
    window_position,
    window_size,
    close,
    refresh,
    focus,
    minimize,
    maximize,
    framebuffer_size,
    content_scale,
    monitor,
}

private struct FakeEvent
{
    FakeEventKind kind;
    FakeWindow* window;
    int a;
    int b;
    int c;
    int d;
    double x;
    double y;
    uint codepoint;
    FakeMonitor* monitor;
}

private enum size_t max_windows = 32;
private enum size_t max_events = 256;

private Hints hints;
private FakeWindow[max_windows] windows;
private size_t next_window;
private FakeEvent[max_events] events;
private size_t event_count;
private G.GLFWwindow* current_context;
private int last_error;
private FakeGLFWOperation failing_operation;
private int failing_error;
private float default_content_scale_x = 1;
private float default_content_scale_y = 1;
private int selected_platform = G.GLFW_PLATFORM_NULL;
private bool initialized;
private FakeWindow foreign_context;
private G.GLFWmonitorfun monitor_callback;

private FakeMonitor[2] fake_monitors = [
    FakeMonitor("Fake Monitor 1".ptr, G.GLFWvidmode(1920, 1080, 8, 8, 8, 60), true),
    FakeMonitor("Fake Monitor 2".ptr, G.GLFWvidmode(2560, 1440, 8, 8, 8, 144), true),
];
private G.GLFWmonitor*[2] monitor_handles;

private FakeWindow* fake(G.GLFWwindow* window) @system
{
    return cast(FakeWindow*) window;
}

private G.GLFWwindow* backend(FakeWindow* window) @system
{
    return cast(G.GLFWwindow*) window;
}

private FakeMonitor* fake_monitor(G.GLFWmonitor* monitor) @system
{
    return cast(FakeMonitor*) monitor;
}

private FakeWindow* find_window(Window* window) @system
{
    if (window is null)
        return null;
    foreach (ref candidate; windows)
    {
        if (candidate.alive && candidate.user is window)
            return &candidate;
    }
    return null;
}

private bool push_event(FakeEvent event) @system
{
    if (event_count >= events.length)
        return false;
    if (event.kind == FakeEventKind.monitor)
    {
        if (event.monitor is null)
            return false;
    }
    else if (event.window is null)
        return false;
    events[event_count++] = event;
    return true;
}

private int backend_key(Key key) pure @safe
{
    if (key >= Key.digit0 && key <= Key.digit9)
        return G.GLFW_KEY_0 + cast(int) key - cast(int) Key.digit0;
    if (key >= Key.a && key <= Key.z)
        return G.GLFW_KEY_A + cast(int) key - cast(int) Key.a;
    if (key >= Key.f1 && key <= Key.f25)
        return G.GLFW_KEY_F1 + cast(int) key - cast(int) Key.f1;
    if (key >= Key.keypad0 && key <= Key.keypad9)
        return G.GLFW_KEY_KP_0 + cast(int) key - cast(int) Key.keypad0;

    switch (key)
    {
        case Key.space:
            return G.GLFW_KEY_SPACE;
        case Key.apostrophe:
            return G.GLFW_KEY_APOSTROPHE;
        case Key.comma:
            return G.GLFW_KEY_COMMA;
        case Key.minus:
            return G.GLFW_KEY_MINUS;
        case Key.period:
            return G.GLFW_KEY_PERIOD;
        case Key.slash:
            return G.GLFW_KEY_SLASH;
        case Key.semicolon:
            return G.GLFW_KEY_SEMICOLON;
        case Key.equal:
            return G.GLFW_KEY_EQUAL;
        case Key.left_bracket:
            return G.GLFW_KEY_LEFT_BRACKET;
        case Key.backslash:
            return G.GLFW_KEY_BACKSLASH;
        case Key.right_bracket:
            return G.GLFW_KEY_RIGHT_BRACKET;
        case Key.grave_accent:
            return G.GLFW_KEY_GRAVE_ACCENT;
        case Key.world1:
            return G.GLFW_KEY_WORLD_1;
        case Key.world2:
            return G.GLFW_KEY_WORLD_2;
        case Key.escape:
            return G.GLFW_KEY_ESCAPE;
        case Key.enter:
            return G.GLFW_KEY_ENTER;
        case Key.tab:
            return G.GLFW_KEY_TAB;
        case Key.backspace:
            return G.GLFW_KEY_BACKSPACE;
        case Key.insert:
            return G.GLFW_KEY_INSERT;
        case Key.delete_key:
            return G.GLFW_KEY_DELETE;
        case Key.right:
            return G.GLFW_KEY_RIGHT;
        case Key.left:
            return G.GLFW_KEY_LEFT;
        case Key.down:
            return G.GLFW_KEY_DOWN;
        case Key.up:
            return G.GLFW_KEY_UP;
        case Key.page_up:
            return G.GLFW_KEY_PAGE_UP;
        case Key.page_down:
            return G.GLFW_KEY_PAGE_DOWN;
        case Key.home:
            return G.GLFW_KEY_HOME;
        case Key.end:
            return G.GLFW_KEY_END;
        case Key.caps_lock:
            return G.GLFW_KEY_CAPS_LOCK;
        case Key.scroll_lock:
            return G.GLFW_KEY_SCROLL_LOCK;
        case Key.num_lock:
            return G.GLFW_KEY_NUM_LOCK;
        case Key.print_screen:
            return G.GLFW_KEY_PRINT_SCREEN;
        case Key.pause:
            return G.GLFW_KEY_PAUSE;
        case Key.keypad_decimal:
            return G.GLFW_KEY_KP_DECIMAL;
        case Key.keypad_divide:
            return G.GLFW_KEY_KP_DIVIDE;
        case Key.keypad_multiply:
            return G.GLFW_KEY_KP_MULTIPLY;
        case Key.keypad_subtract:
            return G.GLFW_KEY_KP_SUBTRACT;
        case Key.keypad_add:
            return G.GLFW_KEY_KP_ADD;
        case Key.keypad_enter:
            return G.GLFW_KEY_KP_ENTER;
        case Key.keypad_equal:
            return G.GLFW_KEY_KP_EQUAL;
        case Key.left_shift:
            return G.GLFW_KEY_LEFT_SHIFT;
        case Key.left_control:
            return G.GLFW_KEY_LEFT_CONTROL;
        case Key.left_alt:
            return G.GLFW_KEY_LEFT_ALT;
        case Key.left_super:
            return G.GLFW_KEY_LEFT_SUPER;
        case Key.right_shift:
            return G.GLFW_KEY_RIGHT_SHIFT;
        case Key.right_control:
            return G.GLFW_KEY_RIGHT_CONTROL;
        case Key.right_alt:
            return G.GLFW_KEY_RIGHT_ALT;
        case Key.right_super:
            return G.GLFW_KEY_RIGHT_SUPER;
        case Key.menu:
            return G.GLFW_KEY_MENU;
        default:
            return G.GLFW_KEY_UNKNOWN;
    }
}

bool queue_key(
    Window* window,
    Key key,
    KeyAction action,
    KeyModifier modifiers = KeyModifier.none,
    int scan_code = 0,
) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(
            FakeEventKind.key,
            target,
            backend_key(key),
            scan_code,
            cast(int) action,
            cast(int) modifiers,
    ));
}

bool queue_text(Window* window, dchar codepoint) @system
{
    FakeWindow* target = find_window(window);
    FakeEvent event;
    event.kind = FakeEventKind.text;
    event.window = target;
    event.codepoint = cast(uint) codepoint;
    return push_event(event);
}

bool queue_mouse_button(
    Window* window,
    MouseButton button,
    KeyAction action,
    KeyModifier modifiers = KeyModifier.none,
) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(
            FakeEventKind.mouse_button,
            target,
            cast(int) button,
            cast(int) action,
            cast(int) modifiers,
    ));
}

bool queue_cursor_position(Window* window, double x, double y) @system
{
    FakeWindow* target = find_window(window);
    FakeEvent event;
    event.kind = FakeEventKind.cursor_position;
    event.window = target;
    event.x = x;
    event.y = y;
    return push_event(event);
}

bool queue_cursor_enter(Window* window, bool entered) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(
            FakeEventKind.cursor_enter,
            target,
            entered ? G.GLFW_TRUE : G.GLFW_FALSE,
    ));
}

bool queue_scroll(Window* window, double x, double y) @system
{
    FakeWindow* target = find_window(window);
    FakeEvent event;
    event.kind = FakeEventKind.scroll;
    event.window = target;
    event.x = x;
    event.y = y;
    return push_event(event);
}

bool queue_window_position(Window* window, int x, int y) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(FakeEventKind.window_position, target, x, y));
}

bool queue_window_size(Window* window, int width, int height) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(FakeEventKind.window_size, target, width, height));
}

bool queue_close(Window* window) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(FakeEventKind.close, target));
}

bool queue_refresh(Window* window) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(FakeEventKind.refresh, target));
}

bool queue_focus(Window* window, bool focused) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(
            FakeEventKind.focus,
            target,
            focused ? G.GLFW_TRUE : G.GLFW_FALSE,
    ));
}

bool queue_minimized(Window* window, bool minimized) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(
            FakeEventKind.minimize,
            target,
            minimized ? G.GLFW_TRUE : G.GLFW_FALSE,
    ));
}

bool queue_maximized(Window* window, bool maximized) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(
            FakeEventKind.maximize,
            target,
            maximized ? G.GLFW_TRUE : G.GLFW_FALSE,
    ));
}

bool queue_framebuffer_size(Window* window, int width, int height) @system
{
    FakeWindow* target = find_window(window);
    return push_event(FakeEvent(FakeEventKind.framebuffer_size, target, width, height));
}

void set_default_content_scale(float x, float y) @system
{
    default_content_scale_x = x;
    default_content_scale_y = y;
}

bool queue_content_scale(Window* window, float x, float y) @system
{
    FakeWindow* target = find_window(window);
    FakeEvent event;
    event.kind = FakeEventKind.content_scale;
    event.window = target;
    event.x = x;
    event.y = y;
    return push_event(event);
}

bool queue_monitor_connected(size_t index) @system
{
    if (index >= fake_monitors.length)
        return false;
    FakeEvent event;
    event.kind = FakeEventKind.monitor;
    event.monitor = &fake_monitors[index];
    event.a = G.GLFW_CONNECTED;
    return push_event(event);
}

bool queue_monitor_disconnected(size_t index) @system
{
    if (index >= fake_monitors.length)
        return false;
    FakeEvent event;
    event.kind = FakeEventKind.monitor;
    event.monitor = &fake_monitors[index];
    event.a = G.GLFW_DISCONNECTED;
    return push_event(event);
}

FakeOpenGLHints opengl_hints(Window* window) @system
{
    FakeOpenGLHints result;
    FakeWindow* value = find_window(window);
    if (value is null)
        return result;

    result.client_api = value.hints.client_api;
    result.version_major = value.hints.version_major;
    result.version_minor = value.hints.version_minor;
    result.profile = value.hints.profile;
    result.creation_api = value.hints.creation_api;
    result.robustness = value.hints.robustness;
    result.release_behavior = value.hints.release_behavior;
    result.forward_compatible = value.hints.forward_compatible == G.GLFW_TRUE;
    result.debug_context = value.hints.debug_context == G.GLFW_TRUE;
    result.no_error = value.hints.no_error == G.GLFW_TRUE;
    result.samples = value.hints.samples;
    result.srgb_capable = value.hints.srgb_capable == G.GLFW_TRUE;
    result.double_buffered = value.hints.double_buffered == G.GLFW_TRUE;
    result.shared_context_with = value.shared_context is null
        ? null : cast(Window*) fake(value.shared_context).user;
    return result;
}

size_t swap_count(Window* window) @system
{
    FakeWindow* value = find_window(window);
    return value is null ? 0 : value.swap_count;
}

int swap_interval(Window* window) @system
{
    FakeWindow* value = find_window(window);
    return value is null ? 0 : value.swap_interval;
}

void fail_next_operation(
    FakeGLFWOperation operation,
    int error = fake_platform_error,
) @system
{
    failing_operation = operation;
    failing_error = error;
}

void seed_backend_error(int error = fake_platform_error) @system
{
    last_error = error;
}

void make_foreign_context_current() @system
{
    foreign_context = FakeWindow.init;
    foreign_context.alive = true;
    foreign_context.hints.client_api = G.GLFW_OPENGL_API;
    foreign_context.user = cast(void*) 1;
    current_context = backend(&foreign_context);
}

private bool fail_operation(FakeGLFWOperation operation) @system
{
    if (failing_operation != operation)
        return false;
    last_error = failing_error;
    failing_operation = FakeGLFWOperation.none;
    failing_error = G.GLFW_NO_ERROR;
    return true;
}

private extern (C) void fake_proc() nothrow @nogc
{
}

private void reset_backend_state() @system
{
    hints = Hints.init;
    foreach (ref window; windows)
        window = FakeWindow.init;
    next_window = 0;
    event_count = 0;
    current_context = null;
    last_error = G.GLFW_NO_ERROR;
    failing_operation = FakeGLFWOperation.none;
    failing_error = G.GLFW_NO_ERROR;
    default_content_scale_x = 1;
    default_content_scale_y = 1;
    foreign_context = FakeWindow.init;
    monitor_callback = null;
    foreach (ref monitor; fake_monitors)
        monitor.connected = true;
    monitor_handles[0] = cast(G.GLFWmonitor*)&fake_monitors[0];
    monitor_handles[1] = cast(G.GLFWmonitor*)&fake_monitors[1];
}

extern (C) void glfwGetVersion(int* major, int* minor, int* revision)
{
    *major = 3;
    *minor = 4;
    *revision = 0;
}

extern (C) void glfwInitHint(int hint, int value)
{
    if (hint == G.GLFW_PLATFORM)
        selected_platform = value == G.GLFW_ANY_PLATFORM ? G.GLFW_PLATFORM_NULL : value;
}

extern (C) int glfwInit()
{
    reset_backend_state();
    initialized = true;
    return G.GLFW_TRUE;
}

extern (C) void glfwTerminate()
{
    initialized = false;
    current_context = null;
    event_count = 0;
    foreach (ref window; windows)
        window.alive = false;
}

extern (C) int glfwGetError(const(char)** description)
{
    if (description !is null)
        *description = null;
    const result = last_error;
    last_error = G.GLFW_NO_ERROR;
    return result;
}

extern (C) int glfwPlatformSupported(int platform)
{
    return platform == G.GLFW_PLATFORM_NULL ? G.GLFW_TRUE : G.GLFW_FALSE;
}

extern (C) int glfwGetPlatform()
{
    return selected_platform;
}

extern (C) void glfwDefaultWindowHints()
{
    hints = Hints.init;
}

extern (C) void glfwWindowHint(int hint, int value)
{
    switch (hint)
    {
        case G.GLFW_CLIENT_API:
            hints.client_api = value;
            break;
        case G.GLFW_CONTEXT_VERSION_MAJOR:
            hints.version_major = value;
            break;
        case G.GLFW_CONTEXT_VERSION_MINOR:
            hints.version_minor = value;
            break;
        case G.GLFW_OPENGL_PROFILE:
            hints.profile = value;
            break;
        case G.GLFW_CONTEXT_CREATION_API:
            hints.creation_api = value;
            break;
        case G.GLFW_CONTEXT_ROBUSTNESS:
            hints.robustness = value;
            break;
        case G.GLFW_CONTEXT_RELEASE_BEHAVIOR:
            hints.release_behavior = value;
            break;
        case G.GLFW_OPENGL_FORWARD_COMPAT:
            hints.forward_compatible = value;
            break;
        case G.GLFW_CONTEXT_DEBUG:
            hints.debug_context = value;
            break;
        case G.GLFW_CONTEXT_NO_ERROR:
            hints.no_error = value;
            break;
        case G.GLFW_SAMPLES:
            hints.samples = value;
            break;
        case G.GLFW_SRGB_CAPABLE:
            hints.srgb_capable = value;
            break;
        case G.GLFW_DOUBLEBUFFER:
            hints.double_buffered = value;
            break;
        case G.GLFW_VISIBLE:
            hints.visible = value;
            break;
        case G.GLFW_RESIZABLE:
            hints.resizable = value;
            break;
        case G.GLFW_DECORATED:
            hints.decorated = value;
            break;
        case G.GLFW_FOCUSED:
            hints.focused = value;
            break;
        case G.GLFW_MAXIMIZED:
            hints.maximized = value;
            break;
        default:
            break;
    }
}

extern (C) G.GLFWwindow* glfwCreateWindow(
    int width,
    int height,
    const(char)*,
    G.GLFWmonitor* monitor,
    G.GLFWwindow* shared_context,
)
{
    if (!initialized)
    {
        last_error = G.GLFW_NOT_INITIALIZED;
        return null;
    }
    if (hints.version_major >= 99)
    {
        last_error = G.GLFW_VERSION_UNAVAILABLE;
        return null;
    }
    if (next_window >= windows.length)
    {
        last_error = G.GLFW_OUT_OF_MEMORY;
        return null;
    }

    FakeWindow* window = &windows[next_window++];
    *window = FakeWindow.init;
    window.alive = true;
    window.width = width;
    window.height = height;
    window.focused = hints.focused == G.GLFW_TRUE;
    window.maximized = hints.maximized == G.GLFW_TRUE;
    window.content_scale_x = default_content_scale_x;
    window.content_scale_y = default_content_scale_y;
    window.hints = hints;
    window.monitor = monitor;
    window.shared_context = shared_context;
    return backend(window);
}

extern (C) void glfwDestroyWindow(G.GLFWwindow* window)
{
    if (window is null)
        return;
    FakeWindow* value = fake(window);
    value.alive = false;
    value.user = null;
    if (current_context is window)
        current_context = null;
}

extern (C) void glfwPollEvents()
{
    if (fail_operation(FakeGLFWOperation.poll_events))
        return;

    size_t index;
    while (index < event_count)
    {
        FakeEvent event = events[index++];
        if (event.kind == FakeEventKind.monitor)
        {
            if (event.monitor is null)
                continue;
            event.monitor.connected = event.a == G.GLFW_CONNECTED;
            if (monitor_callback !is null)
                monitor_callback(cast(G.GLFWmonitor*) event.monitor, event.a);
            continue;
        }

        FakeWindow* window = event.window;
        if (window is null || !window.alive)
            continue;
        G.GLFWwindow* handle = backend(window);

        final switch (event.kind)
        {
            case FakeEventKind.key:
                if (window.key_callback !is null)
                {
                    int modifiers = event.d;
                    if (!window.lock_key_modifiers)
                        modifiers &= ~(G.GLFW_MOD_CAPS_LOCK | G.GLFW_MOD_NUM_LOCK);
                    window.key_callback(handle, event.a, event.b, event.c, modifiers);
                }
                break;
            case FakeEventKind.text:
                if (window.char_callback !is null)
                    window.char_callback(handle, event.codepoint);
                break;
            case FakeEventKind.mouse_button:
                if (window.mouse_button_callback !is null)
                {
                    int modifiers = event.c;
                    if (!window.lock_key_modifiers)
                        modifiers &= ~(G.GLFW_MOD_CAPS_LOCK | G.GLFW_MOD_NUM_LOCK);
                    window.mouse_button_callback(handle, event.a, event.b, modifiers);
                }
                break;
            case FakeEventKind.cursor_position:
                window.cursor_x = event.x;
                window.cursor_y = event.y;
                if (window.cursor_position_callback !is null)
                    window.cursor_position_callback(handle, event.x, event.y);
                break;
            case FakeEventKind.cursor_enter:
                if (
                    window.cursor_enter_callback !is null)
                    window.cursor_enter_callback(handle, event.a);
                break;
            case FakeEventKind.scroll:
                if (window.scroll_callback !is null)
                    window.scroll_callback(handle, event.x, event.y);
                break;
            case FakeEventKind.window_position:
                window.x = event.a;
                window.y = event.b;
                if (window.window_position_callback !is null)
                    window.window_position_callback(handle, event.a, event.b);
                break;
            case FakeEventKind.window_size:
                window.width = event.a;
                window.height = event.b;
                if (window.window_size_callback !is null)
                    window.window_size_callback(handle, event.a, event.b);
                break;
            case FakeEventKind.close:
                window.should_close = G.GLFW_TRUE;
                if (window.window_close_callback !is null)
                    window.window_close_callback(handle);
                break;
            case FakeEventKind.refresh:
                if (window.window_refresh_callback !is null)
                    window.window_refresh_callback(handle);
                break;
            case FakeEventKind.focus:
                window.focused = event.a == G.GLFW_TRUE;
                if (window.window_focus_callback !is null)
                    window.window_focus_callback(handle, event.a);
                break;
            case FakeEventKind.minimize:
                window.minimized = event.a == G.GLFW_TRUE;
                if (window.window_iconify_callback !is null)
                    window.window_iconify_callback(handle, event.a);
                break;
            case FakeEventKind.maximize:
                window.maximized = event.a == G.GLFW_TRUE;
                if (window.window_maximize_callback !is null)
                    window.window_maximize_callback(handle, event.a);
                break;
            case FakeEventKind.framebuffer_size:
                if (
                    window.framebuffer_size_callback !is null)
                    window.framebuffer_size_callback(handle, event.a, event.b);
                break;
            case FakeEventKind.content_scale:
                window.content_scale_x = cast(float) event.x;
                window.content_scale_y = cast(float) event.y;
                if (window.content_scale_callback !is null)
                    window.content_scale_callback(handle, cast(float) event.x, cast(float) event.y);
                break;
            case FakeEventKind.monitor:
                break;
        }
    }
    event_count = 0;
}

extern (C) void glfwMakeContextCurrent(G.GLFWwindow* window)
{
    if (window !is null && fake(window).hints.client_api == G.GLFW_NO_API)
    {
        last_error = G.GLFW_NO_WINDOW_CONTEXT;
        return;
    }
    current_context = window;
}

extern (C) G.GLFWwindow* glfwGetCurrentContext()
{
    return current_context;
}

extern (C) void glfwSwapBuffers(G.GLFWwindow* window)
{
    if (window is null || current_context !is window)
    {
        last_error = G.GLFW_NO_CURRENT_CONTEXT;
        return;
    }
    ++fake(window).swap_count;
}

extern (C) void glfwSwapInterval(int interval)
{
    if (current_context is null)
    {
        last_error = G.GLFW_NO_CURRENT_CONTEXT;
        return;
    }
    fake(current_context).swap_interval = interval;
}

extern (C) int glfwExtensionSupported(const(char)* extension)
{
    if (current_context is null)
    {
        last_error = G.GLFW_NO_CURRENT_CONTEXT;
        return G.GLFW_FALSE;
    }
    return extension !is null && strcmp(extension, "GL_FAKE_extension".ptr) == 0
        ? G.GLFW_TRUE : G.GLFW_FALSE;
}

extern (C) G.GLFWglproc glfwGetProcAddress(const(char)* name)
{
    if (current_context is null)
    {
        last_error = G.GLFW_NO_CURRENT_CONTEXT;
        return null;
    }
    if (name is null)
        return null;
    if (strcmp(name, "glGetString".ptr) == 0 || strcmp(name, "glFakeFunction".ptr) == 0)
        return &fake_proc;
    return null;
}

extern (C) void glfwSetWindowUserPointer(G.GLFWwindow* window, void* pointer)
{
    fake(window).user = pointer;
}

extern (C) void* glfwGetWindowUserPointer(G.GLFWwindow* window)
{
    return fake(window).user;
}

extern (C) int glfwWindowShouldClose(G.GLFWwindow* window)
{
    return fake(window).should_close;
}

extern (C) void glfwSetWindowShouldClose(G.GLFWwindow* window, int value)
{
    fake(window).should_close = value;
}

extern (C) void glfwSetWindowTitle(G.GLFWwindow*, const(char)*)
{
    cast(void) fail_operation(FakeGLFWOperation.set_window_title);
}

extern (C) void glfwGetWindowPos(G.GLFWwindow* window, int* x, int* y)
{
    if (fail_operation(FakeGLFWOperation.get_window_position))
        return;
    *x = fake(window).x;
    *y = fake(window).y;
}

extern (C) void glfwSetWindowPos(G.GLFWwindow* window, int x, int y)
{
    if (fail_operation(FakeGLFWOperation.set_window_position))
        return;
    FakeWindow* value = fake(window);
    value.x = x;
    value.y = y;
    if (value.window_position_callback !is null)
        value.window_position_callback(window, x, y);
}

extern (C) void glfwGetWindowSize(G.GLFWwindow* window, int* width, int* height)
{
    if (fail_operation(FakeGLFWOperation.get_window_size))
        return;
    *width = fake(window).width;
    *height = fake(window).height;
}

extern (C) void glfwSetWindowSize(G.GLFWwindow* window, int width, int height)
{
    if (fail_operation(FakeGLFWOperation.set_window_size))
        return;
    FakeWindow* value = fake(window);
    value.width = width;
    value.height = height;
    if (value.window_size_callback !is null)
        value.window_size_callback(window, width, height);
    if (value.framebuffer_size_callback !is null)
        value.framebuffer_size_callback(window, width, height);
}

extern (C) void glfwGetFramebufferSize(G.GLFWwindow* window, int* width, int* height)
{
    *width = fake(window).width;
    *height = fake(window).height;
}

extern (C) void glfwGetWindowContentScale(G.GLFWwindow* window, float* x, float* y)
{
    if (x !is null)
        *x = 0;
    if (y !is null)
        *y = 0;
    if (fail_operation(FakeGLFWOperation.get_window_content_scale))
        return;

    if (x !is null)
        *x = fake(window).content_scale_x;
    if (y !is null)
        *y = fake(window).content_scale_y;
}

extern (C) int glfwGetWindowAttrib(G.GLFWwindow* window, int attrib)
{
    FakeWindow* value = fake(window);
    switch (attrib)
    {
        case G.GLFW_HOVERED:
            return G.GLFW_FALSE;
        case G.GLFW_FOCUSED:
            return value.focused ? G.GLFW_TRUE : G.GLFW_FALSE;
        case G.GLFW_ICONIFIED:
            return value.minimized ? G.GLFW_TRUE : G.GLFW_FALSE;
        case G.GLFW_MAXIMIZED:
            return value.maximized ? G.GLFW_TRUE : G.GLFW_FALSE;
        case G.GLFW_CLIENT_API:
            return value.hints.client_api;
        case G.GLFW_CONTEXT_VERSION_MAJOR:
            return value.hints.version_major;
        case G.GLFW_CONTEXT_VERSION_MINOR:
            return value.hints.version_minor;
        case G.GLFW_CONTEXT_REVISION:
            return 0;
        case G.GLFW_OPENGL_PROFILE:
            return value.hints.profile;
        case G.GLFW_CONTEXT_CREATION_API:
            return value.hints.creation_api;
        case G.GLFW_CONTEXT_ROBUSTNESS:
            return value.hints.robustness;
        case G.GLFW_CONTEXT_RELEASE_BEHAVIOR:
            return value.hints.release_behavior;
        case G.GLFW_OPENGL_FORWARD_COMPAT:
            return value.hints.forward_compatible;
        case G.GLFW_CONTEXT_DEBUG:
            return value.hints.debug_context;
        case G.GLFW_CONTEXT_NO_ERROR:
            return value.hints.no_error;
        case G.GLFW_DOUBLEBUFFER:
            return value.hints.double_buffered;
        default:
            return G.GLFW_FALSE;
    }
}

extern (C) G.GLFWmonitor* glfwGetWindowMonitor(G.GLFWwindow* window)
{
    return fake(window).monitor;
}

extern (C) void glfwSetWindowMonitor(
    G.GLFWwindow* window,
    G.GLFWmonitor* monitor,
    int x,
    int y,
    int width,
    int height,
    int,
)
{
    if (fail_operation(FakeGLFWOperation.set_window_monitor))
        return;
    FakeWindow* value = fake(window);
    value.monitor = monitor;
    value.x = x;
    value.y = y;
    value.width = width;
    value.height = height;
    if (value.window_position_callback !is null)
        value.window_position_callback(window, x, y);
    if (value.window_size_callback !is null)
        value.window_size_callback(window, width, height);
    if (value.framebuffer_size_callback !is null)
        value.framebuffer_size_callback(window, width, height);
}

extern (C) G.GLFWmonitor* glfwGetPrimaryMonitor()
{
    foreach (ref monitor; fake_monitors)
    {
        if (monitor.connected)
            return cast(G.GLFWmonitor*) &monitor;
    }
    return null;
}

extern (C) G.GLFWmonitor** glfwGetMonitors(int* count)
{
    size_t connected_count;
    foreach (ref monitor; fake_monitors)
    {
        if (monitor.connected)
            monitor_handles[connected_count++] = cast(G.GLFWmonitor*) &monitor;
    }
    *count = cast(int) connected_count;
    return connected_count == 0 ? null : monitor_handles.ptr;
}

extern (C) G.GLFWmonitorfun glfwSetMonitorCallback(G.GLFWmonitorfun callback)
{
    const previous = monitor_callback;
    monitor_callback = callback;
    return previous;
}

extern (C) const(char)* glfwGetMonitorName(G.GLFWmonitor* monitor)
{
    return fake_monitor(monitor).name;
}

extern (C) const(G.GLFWvidmode)* glfwGetVideoMode(G.GLFWmonitor* monitor)
{
    return &fake_monitor(monitor).mode;
}

extern (C) void glfwGetCursorPos(G.GLFWwindow* window, double* x, double* y)
{
    *x = fake(window).cursor_x;
    *y = fake(window).cursor_y;
}

extern (C) int glfwGetInputMode(G.GLFWwindow* window, int mode)
{
    FakeWindow* value = fake(window);
    if (mode == G.GLFW_CURSOR)
        return value.cursor_mode;
    if (mode == G.GLFW_LOCK_KEY_MODS)
        return value.lock_key_modifiers ? G.GLFW_TRUE : G.GLFW_FALSE;
    return G.GLFW_FALSE;
}

extern (C) void glfwSetInputMode(G.GLFWwindow* window, int mode, int value)
{
    if (fail_operation(FakeGLFWOperation.set_input_mode))
        return;
    FakeWindow* target = fake(window);
    if (mode == G.GLFW_CURSOR)
        target.cursor_mode = value;
    else if (mode == G.GLFW_LOCK_KEY_MODS)
        target.lock_key_modifiers = value == G.GLFW_TRUE;
}

extern (C) G.GLFWkeyfun glfwSetKeyCallback(G.GLFWwindow* window, G.GLFWkeyfun callback)
{
    auto previous = fake(window).key_callback;
    fake(window).key_callback = callback;
    return previous;
}

extern (C) G.GLFWcharfun glfwSetCharCallback(G.GLFWwindow* window, G.GLFWcharfun callback)
{
    auto previous = fake(window).char_callback;
    fake(window).char_callback = callback;
    return previous;
}

extern (C) G.GLFWmousebuttonfun glfwSetMouseButtonCallback(G.GLFWwindow* window, G.GLFWmousebuttonfun callback)
{
    auto previous = fake(window).mouse_button_callback;
    fake(window).mouse_button_callback = callback;
    return previous;
}

extern (C) G.GLFWcursorposfun glfwSetCursorPosCallback(G.GLFWwindow* window, G.GLFWcursorposfun callback)
{
    auto previous = fake(window).cursor_position_callback;
    fake(window).cursor_position_callback = callback;
    return previous;
}

extern (C) G.GLFWcursorenterfun glfwSetCursorEnterCallback(G.GLFWwindow* window, G.GLFWcursorenterfun callback)
{
    auto previous = fake(window).cursor_enter_callback;
    fake(window).cursor_enter_callback = callback;
    return previous;
}

extern (C) G.GLFWscrollfun glfwSetScrollCallback(G.GLFWwindow* window, G.GLFWscrollfun callback)
{
    auto previous = fake(window).scroll_callback;
    fake(window).scroll_callback = callback;
    return previous;
}

extern (C) G.GLFWwindowposfun glfwSetWindowPosCallback(G.GLFWwindow* window, G.GLFWwindowposfun callback)
{
    auto previous = fake(window).window_position_callback;
    fake(window).window_position_callback = callback;
    return previous;
}

extern (C) G.GLFWwindowsizefun glfwSetWindowSizeCallback(G.GLFWwindow* window, G.GLFWwindowsizefun callback)
{
    auto previous = fake(window).window_size_callback;
    fake(window).window_size_callback = callback;
    return previous;
}

extern (C) G.GLFWwindowclosefun glfwSetWindowCloseCallback(G.GLFWwindow* window, G.GLFWwindowclosefun callback)
{
    auto previous = fake(window).window_close_callback;
    fake(window).window_close_callback = callback;
    return previous;
}

extern (C) G.GLFWwindowrefreshfun glfwSetWindowRefreshCallback(
    G.GLFWwindow* window,
    G.GLFWwindowrefreshfun callback,
)
{
    FakeWindow* target = fake(window);
    G.GLFWwindowrefreshfun previous = target.window_refresh_callback;
    target.window_refresh_callback = callback;
    return previous;
}

extern (C) G.GLFWwindowfocusfun glfwSetWindowFocusCallback(G.GLFWwindow* window, G.GLFWwindowfocusfun callback)
{
    auto previous = fake(window).window_focus_callback;
    fake(window).window_focus_callback = callback;
    return previous;
}

extern (C) G.GLFWwindowiconifyfun glfwSetWindowIconifyCallback(G.GLFWwindow* window, G
        .GLFWwindowiconifyfun callback)
{
    auto previous = fake(window).window_iconify_callback;
    fake(window).window_iconify_callback = callback;
    return previous;
}

extern (C) G.GLFWwindowmaximizefun glfwSetWindowMaximizeCallback(G.GLFWwindow* window, G
        .GLFWwindowmaximizefun callback)
{
    auto previous = fake(window).window_maximize_callback;
    fake(window).window_maximize_callback = callback;
    return previous;
}

extern (C) G.GLFWframebuffersizefun glfwSetFramebufferSizeCallback(G.GLFWwindow* window, G
        .GLFWframebuffersizefun callback)
{
    auto previous = fake(window).framebuffer_size_callback;
    fake(window).framebuffer_size_callback = callback;
    return previous;
}

extern (C) G.GLFWwindowcontentscalefun glfwSetWindowContentScaleCallback(G.GLFWwindow* window, G
        .GLFWwindowcontentscalefun callback)
{
    auto previous = fake(window).content_scale_callback;
    fake(window).content_scale_callback = callback;
    return previous;
}

version (Windows)
{
    extern (C) void* glfwGetWin32Window(G.GLFWwindow*)
    {
        return null;
    }
}
else version (OSX)
{
    extern (C) void* glfwGetCocoaWindow(G.GLFWwindow*)
    {
        return null;
    }

    extern (C) void* glfwGetCocoaView(G.GLFWwindow*)
    {
        return null;
    }
}
else version (linux)
{
    extern (C) void* glfwGetX11Display()
    {
        return null;
    }

    extern (C) ulong glfwGetX11Window(G.GLFWwindow*)
    {
        return 0;
    }

    extern (C) void* glfwGetWaylandDisplay()
    {
        return null;
    }

    extern (C) void* glfwGetWaylandWindow(G.GLFWwindow*)
    {
        return null;
    }
}
