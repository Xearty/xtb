module xtb.window.window;

nothrow @nogc:

import xtb.memory : Allocator, deallocate, tryAllocateInit;
import xtb.string : StringBuf;
import xtb.thread_context : ScratchScope;
import xtb.option : Option;
import xtb.types : String, i32;
import xtb.window.error : WindowError, WindowErrorKind, WindowResult;
import xtb.window.event : BoolWindowEvent, ContentScale, CursorMovedEvent, KeyEvent,
    MouseButtonEvent, ScrollEvent, TextInputEvent, WindowEvent, WindowEventKind,
    WindowPosition, WindowSize;
import xtb.window.input : CursorDelta, CursorMode, CursorPosition, Key, KeyState,
    MouseButton, MouseButtonState, ScrollDelta;
import xtb.window.internal.create_options : BackendClientAPI, BackendGLContextCreationAPI,
    BackendGLProfile, BackendGLReleaseBehavior, BackendGLRobustness,
    BackendWindowCreateOptions;
import xtb.window.internal.glfw;
import xtb.window.internal.glfw_error : clear_glfw_error, consume_glfw_error, glfw_call_error;
import xtb.window.internal.glfw_input : key_action_from_glfw, key_from_glfw,
    modifiers_from_glfw, mouse_button_from_glfw;
import xtb.window.monitor : Monitor;
import xtb.window.native : CocoaWindowHandle, NativeWindowHandle,
    NativeWindowPlatform, WaylandWindowHandle, Win32WindowHandle, X11WindowHandle;
import xtb.window.system : WindowSystem;

version (XTB_Checked) import xtb.panic : require;

private WindowError window_error(WindowErrorKind kind) pure @safe
{
    return WindowError(kind);
}

/// Native window creation parameters. Width and height must be positive. The
/// title must be valid UTF-8 without embedded NUL bytes.
struct WindowConfig
{
    i32 width = 1280;
    i32 height = 720;
    String title = "XTB Window";
    bool resizable = true;
    bool visible = true;
    bool decorated = true;
    bool focused = true;
    bool maximized = false;
    bool lock_key_modifiers = false;
}

alias WindowEventFn = void function(
    Window* window,
    scope const WindowEvent* event,
    void* context,
) nothrow @nogc;

struct WindowEventHandler
{
    WindowEventFn callback;
    void* context;
}

struct Window
{
nothrow @nogc:

    private GLFWwindow* handle_;
    private WindowSystem* system_;
    private Allocator* allocator_;
    private BackendClientAPI client_api_;
    private BackendGLContextCreationAPI context_creation_api_;
    private Window* previous_window_;
    private Window* next_window_;
    private WindowEventHandler event_handler_;
    private KeyState[cast(size_t) Key.count] key_states_;
    private MouseButtonState[cast(size_t) MouseButton.count] mouse_states_;
    private CursorPosition cursor_position_;
    private CursorDelta cursor_delta_;
    private ScrollDelta scroll_delta_;
    private bool cursor_inside_;
    private bool cursor_entered_;
    private bool cursor_left_;
    private WindowPosition fullscreen_restore_position_;
    private WindowSize fullscreen_restore_size_;
    private bool has_fullscreen_restore_position_;
    private bool has_fullscreen_restore_;

    @disable this(this);

    package(xtb.window) static WindowResult!(Window*) create(
        WindowSystem* system,
        Allocator* allocator,
        WindowConfig config,
        BackendWindowCreateOptions backend_options,
    ) @system
    {
        version (XTB_Checked)
        {
            require(system !is null, "WindowSystem is null");
            require(allocator !is null && *allocator !is null, "Window allocator is null");
            require(config.width > 0 && config.height > 0, "Window size must be positive");
        }

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf title = StringBuf.fromString(scratch.allocator, config.title);

        clear_glfw_error();
        glfwDefaultWindowHints();
        apply_backend_window_hints(backend_options);
        glfwWindowHint(GLFW_RESIZABLE, config.resizable ? GLFW_TRUE : GLFW_FALSE);
        glfwWindowHint(GLFW_VISIBLE, config.visible ? GLFW_TRUE : GLFW_FALSE);
        glfwWindowHint(GLFW_DECORATED, config.decorated ? GLFW_TRUE : GLFW_FALSE);
        glfwWindowHint(GLFW_FOCUSED, config.focused ? GLFW_TRUE : GLFW_FALSE);
        glfwWindowHint(GLFW_MAXIMIZED, config.maximized ? GLFW_TRUE : GLFW_FALSE);
        const hint_error = glfw_call_error(WindowErrorKind.window_creation_failed);
        if (hint_error.failed)
            return typeof(return).err(hint_error);

        clear_glfw_error();
        GLFWwindow* handle = glfwCreateWindow(
            config.width,
            config.height,
            title.checkedCString,
            null,
            backend_options.shared_context,
        );
        if (handle is null)
        {
            const error = glfw_call_error(WindowErrorKind.window_creation_failed);
            return typeof(return).err(error.failed
                    ? error : window_error(WindowErrorKind.window_creation_failed));
        }

        if (config.lock_key_modifiers)
        {
            clear_glfw_error();
            glfwSetInputMode(handle, GLFW_LOCK_KEY_MODS, GLFW_TRUE);
            const input_mode_error = glfw_call_error(WindowErrorKind.backend_operation_failed);
            if (input_mode_error.failed)
            {
                glfwDestroyWindow(handle);
                return typeof(return).err(input_mode_error);
            }
        }

        Window* window = allocator.tryAllocateInit!Window();
        if (window is null)
        {
            glfwDestroyWindow(handle);
            return typeof(return).err(window_error(WindowErrorKind.allocation_failed));
        }

        window.handle_ = handle;
        window.system_ = system;
        window.allocator_ = allocator;
        window.client_api_ = backend_options.client_api;
        window.context_creation_api_ = backend_options.context_creation_api;

        clear_glfw_error();
        glfwGetCursorPos(handle, &window.cursor_position_.x, &window.cursor_position_.y);
        auto state_error = glfw_call_error(WindowErrorKind.backend_operation_failed);
        if (!state_error.failed)
        {
            clear_glfw_error();
            window.cursor_inside_ = glfwGetWindowAttrib(handle, GLFW_HOVERED) == GLFW_TRUE;
            state_error = glfw_call_error(WindowErrorKind.backend_operation_failed);
        }
        if (state_error.failed)
        {
            glfwDestroyWindow(handle);
            allocator.deallocate(window);
            return typeof(return).err(state_error);
        }

        glfwSetWindowUserPointer(handle, window);
        install_callbacks(handle);
        system.link_window(window);
        return typeof(return).ok(window);
    }

    /// Destroys this window and releases the Window allocation. The pointer is
    /// invalid after this call. Window destruction is not permitted from an
    /// event callback.
    void deinit() @system
    {
        if (handle_ is null)
            return;

        version (XTB_Checked)
            require(system_ !is null, "live Window has no WindowSystem");

        WindowSystem* system = system_;
        Allocator* allocator = allocator_;
        GLFWwindow* handle = handle_;
        system.unlink_window(&this);
        glfwSetWindowUserPointer(handle, null);
        glfwDestroyWindow(handle);

        handle_ = null;
        system_ = null;
        allocator_ = null;
        client_api_ = BackendClientAPI.none;
        context_creation_api_ = BackendGLContextCreationAPI.native;
        allocator.deallocate(&this);
    }

    bool valid() const pure @safe
    {
        return handle_ !is null;
    }

    bool should_close() const @system
    {
        require_live();
        return glfwWindowShouldClose(backend_handle()) == GLFW_TRUE;
    }

    void set_should_close(bool value) @system
    {
        require_live();
        glfwSetWindowShouldClose(backend_handle(), value ? GLFW_TRUE : GLFW_FALSE);
    }

    void request_close() @system
    {
        set_should_close(true);
    }

    /// Changes the window title. `title` must be valid UTF-8 without embedded
    /// NUL bytes. Temporary native storage comes from the current thread's
    /// scratch arena, so a thread context must be installed.
    void set_title(scope String title) @system
    {
        require_live();

        ScratchScope scratch = ScratchScope.acquire();
        StringBuf native = StringBuf.fromString(scratch.allocator, title);
        glfwSetWindowTitle(backend_handle(), native.checkedCString);
    }

    /// Returns the global window position when the active platform exposes it.
    /// Platforms such as Wayland do not expose global window coordinates and
    /// return none.
    Option!WindowPosition position() const @system
    {
        require_live();
        WindowPosition result;
        clear_glfw_error();
        glfwGetWindowPos(backend_handle(), &result.x, &result.y);
        return consume_glfw_error() == GLFW_NO_ERROR
            ? Option!WindowPosition.some(result) : Option!WindowPosition.none();
    }

    /// Requests a global window position. Platforms that do not expose this
    /// operation may ignore the request.
    void set_position(WindowPosition value) @system
    {
        require_live();
        glfwSetWindowPos(backend_handle(), value.x, value.y);
    }

    WindowSize size() const @system
    {
        require_live();
        WindowSize result;
        glfwGetWindowSize(backend_handle(), &result.width, &result.height);
        return result;
    }

    /// Requests a positive client-area size.
    void set_size(WindowSize value) @system
    {
        require_live();
        version (XTB_Checked)
            require(value.width > 0 && value.height > 0, "Window size must be positive");
        glfwSetWindowSize(backend_handle(), value.width, value.height);
    }

    WindowSize framebuffer_size() const @system
    {
        require_live();
        WindowSize result;
        glfwGetFramebufferSize(backend_handle(), &result.width, &result.height);
        return result;
    }

    ContentScale content_scale() const @system
    {
        require_live();
        ContentScale result;

        clear_glfw_error();
        glfwGetWindowContentScale(backend_handle(), &result.x, &result.y);
        if (consume_glfw_error() != GLFW_NO_ERROR)
            return ContentScale.init;
        return result;
    }

    bool visible() const @system
    {
        require_live();
        return glfwGetWindowAttrib(backend_handle(), GLFW_VISIBLE) == GLFW_TRUE;
    }

    /// Requests that a hidden window become visible. Showing a windowed window
    /// may also give it input focus according to platform policy. GLFW ignores
    /// this command for fullscreen windows.
    void show() @system
    {
        require_live();
        glfwShowWindow(backend_handle());
    }

    /// Requests that a visible window become hidden. GLFW ignores this command
    /// for fullscreen windows.
    void hide() @system
    {
        require_live();
        glfwHideWindow(backend_handle());
    }

    bool focused() const @system
    {
        require_live();
        return glfwGetWindowAttrib(backend_handle(), GLFW_FOCUSED) == GLFW_TRUE;
    }

    bool minimized() const @system
    {
        require_live();
        return glfwGetWindowAttrib(backend_handle(), GLFW_ICONIFIED) == GLFW_TRUE;
    }

    bool maximized() const @system
    {
        require_live();
        return glfwGetWindowAttrib(backend_handle(), GLFW_MAXIMIZED) == GLFW_TRUE;
    }

    bool fullscreen() const @system
    {
        require_live();
        return glfwGetWindowMonitor(backend_handle()) !is null;
    }

    Monitor monitor() const @system
    {
        require_live();
        return Monitor.from_backend(glfwGetWindowMonitor(backend_handle()));
    }

    /// Requests fullscreen presentation. An invalid target selects the primary
    /// monitor when entering fullscreen and keeps the current monitor when
    /// already fullscreen. Missing monitors and unsupported platform features
    /// are treated as no-ops.
    void set_fullscreen(bool enabled, Monitor target = Monitor.init) @system
    {
        require_live();

        GLFWmonitor* current_monitor = glfwGetWindowMonitor(backend_handle());
        const currently_fullscreen = current_monitor !is null;

        if (enabled)
        {
            if (!target.valid)
            {
                if (currently_fullscreen)
                    return;

                target = system_.primary_monitor();
                if (!target.valid)
                    return;
            }

            if (currently_fullscreen && target.backend_handle() is current_monitor)
                return;

            auto mode_result = target.video_mode();
            if (mode_result.isErr)
                return;
            const mode = mode_result.take();

            WindowPosition restore_position;
            WindowSize restore_size;
            bool has_restore_position;
            if (!currently_fullscreen)
            {
                if (!query_fullscreen_restore_position(
                        &restore_position,
                        &has_restore_position))
                    return;
                if (!query_fullscreen_restore_size(&restore_size))
                    return;
            }

            clear_glfw_error();
            glfwSetWindowMonitor(
                backend_handle(),
                target.backend_handle(),
                0,
                0,
                mode.width,
                mode.height,
                mode.refresh_rate,
            );
            if (consume_glfw_error() != GLFW_NO_ERROR)
                return;

            if (!currently_fullscreen)
            {
                fullscreen_restore_position_ = restore_position;
                fullscreen_restore_size_ = restore_size;
                has_fullscreen_restore_position_ = has_restore_position;
                has_fullscreen_restore_ = true;
            }
            return;
        }

        if (!currently_fullscreen)
            return;

        version (XTB_Checked)
            require(has_fullscreen_restore_, "fullscreen restore state is unavailable");

        const restore_x = has_fullscreen_restore_position_
            ? fullscreen_restore_position_.x : 0;
        const restore_y = has_fullscreen_restore_position_
            ? fullscreen_restore_position_.y : 0;

        clear_glfw_error();
        glfwSetWindowMonitor(
            backend_handle(),
            null,
            restore_x,
            restore_y,
            fullscreen_restore_size_.width,
            fullscreen_restore_size_.height,
            GLFW_DONT_CARE,
        );
        if (consume_glfw_error() != GLFW_NO_ERROR)
            return;

        has_fullscreen_restore_position_ = false;
        has_fullscreen_restore_ = false;
    }

    void set_event_handler(WindowEventHandler handler) @system
    {
        event_handler_ = handler;
    }

    KeyState key_state(Key key) const pure @safe
    {
        const index = cast(size_t) key;
        return index < key_states_.length ? key_states_[index] : KeyState.init;
    }

    bool key_down(Key key) const pure @safe
    {
        return key_state(key).down;
    }

    bool key_pressed(Key key) const pure @safe
    {
        return key_state(key).pressed;
    }

    bool key_released(Key key) const pure @safe
    {
        return key_state(key).released;
    }

    bool key_repeated(Key key) const pure @safe
    {
        return key_state(key).repeated;
    }

    MouseButtonState mouse_button_state(MouseButton button) const pure @safe
    {
        const index = cast(size_t) button;
        return index < mouse_states_.length ? mouse_states_[index] : MouseButtonState.init;
    }

    bool mouse_button_down(MouseButton button) const pure @safe
    {
        return mouse_button_state(button).down;
    }

    bool mouse_button_pressed(MouseButton button) const pure @safe
    {
        return mouse_button_state(button).pressed;
    }

    bool mouse_button_released(MouseButton button) const pure @safe
    {
        return mouse_button_state(button).released;
    }

    CursorPosition cursor_position() const pure @safe
    {
        return cursor_position_;
    }

    CursorDelta cursor_delta() const pure @safe
    {
        return cursor_delta_;
    }

    ScrollDelta scroll_delta() const pure @safe
    {
        return scroll_delta_;
    }

    bool scrolled() const pure @safe
    {
        return scroll_delta_.x != 0 || scroll_delta_.y != 0;
    }

    bool cursor_inside() const pure @safe
    {
        return cursor_inside_;
    }

    bool cursor_entered() const pure @safe
    {
        return cursor_entered_;
    }

    bool cursor_left() const pure @safe
    {
        return cursor_left_;
    }

    CursorMode cursor_mode() const @system
    {
        require_live();
        switch (glfwGetInputMode(backend_handle(), GLFW_CURSOR))
        {
            case GLFW_CURSOR_HIDDEN:
                return CursorMode.hidden;
            case GLFW_CURSOR_DISABLED:
                return CursorMode.disabled;
            default:
                return CursorMode.normal;
        }
    }

    /// Requests the cursor mode. Platforms that cannot provide a requested
    /// mode may leave the current mode unchanged.
    void set_cursor_mode(CursorMode mode) @system
    {
        require_live();

        final switch (mode)
        {
            case CursorMode.normal:
                glfwSetInputMode(backend_handle(), GLFW_CURSOR, GLFW_CURSOR_NORMAL);
                break;
            case CursorMode.hidden:
                glfwSetInputMode(backend_handle(), GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
                break;
            case CursorMode.disabled:
                glfwSetInputMode(backend_handle(), GLFW_CURSOR, GLFW_CURSOR_DISABLED);
                break;
        }
    }

    /// Returns the native window handle for the selected window-system backend,
    /// or an invalid handle when the active backend has no corresponding native
    /// window handle. On Linux, linking xtb.window requires GLFW to be built
    /// with both the X11 and Wayland backends because XTB references both
    /// native-access APIs.
    NativeWindowHandle native_handle() const @system
    {
        require_live();

        const selected = glfwGetPlatform();
        version (Windows)
        {
            if (selected == GLFW_PLATFORM_WIN32)
            {
                void* native = glfwGetWin32Window(backend_handle());
                if (native is null)
                    return NativeWindowHandle.init;
                NativeWindowHandle result;
                result.platform = NativeWindowPlatform.win32;
                result.win32 = Win32WindowHandle(native);
                return result;
            }
        }
        else version (OSX)
        {
            if (selected == GLFW_PLATFORM_COCOA)
            {
                void* native_window = glfwGetCocoaWindow(backend_handle());
                void* native_view = glfwGetCocoaView(backend_handle());
                if (native_window is null || native_view is null)
                    return NativeWindowHandle.init;
                NativeWindowHandle result;
                result.platform = NativeWindowPlatform.cocoa;
                result.cocoa = CocoaWindowHandle(native_window, native_view);
                return result;
            }
        }
        else version (linux)
        {
            if (selected == GLFW_PLATFORM_X11)
            {
                const native = glfwGetX11Window(backend_handle());
                if (native == 0)
                    return NativeWindowHandle.init;
                NativeWindowHandle result;
                result.platform = NativeWindowPlatform.x11;
                result.x11 = X11WindowHandle(native);
                return result;
            }
            if (selected == GLFW_PLATFORM_WAYLAND)
            {
                void* native = glfwGetWaylandWindow(backend_handle());
                if (native is null)
                    return NativeWindowHandle.init;
                NativeWindowHandle result;
                result.platform = NativeWindowPlatform.wayland;
                result.wayland = WaylandWindowHandle(native);
                return result;
            }
        }

        return NativeWindowHandle.init;
    }

    package(xtb.window) void reset_poll_state() pure @safe
    {
        foreach (ref state; key_states_)
            state.reset_transitions();
        foreach (ref state; mouse_states_)
            state.reset_transitions();
        cursor_delta_ = CursorDelta.init;
        scroll_delta_ = ScrollDelta.init;
        cursor_entered_ = false;
        cursor_left_ = false;
    }

    package(xtb.window) Window* previous_window() return pure @safe
    {
        return previous_window_;
    }

    package(xtb.window) Window* next_window() return pure @safe
    {
        return next_window_;
    }

    package(xtb.window) void set_list_links(Window* previous, Window* next) pure @safe
    {
        previous_window_ = previous;
        next_window_ = next;
    }

    package(xtb.window) void set_previous_window(Window* previous) pure @safe
    {
        previous_window_ = previous;
    }

    package(xtb.window) void set_next_window(Window* next) pure @safe
    {
        next_window_ = next;
    }

    private bool query_fullscreen_restore_position(
        WindowPosition* result,
        bool* available,
    ) const @system
    {
        *available = false;
        clear_glfw_error();
        glfwGetWindowPos(backend_handle(), &result.x, &result.y);
        const error = consume_glfw_error();
        if (error == GLFW_NO_ERROR)
        {
            *available = true;
            return true;
        }
        return error == GLFW_FEATURE_UNAVAILABLE || error == GLFW_FEATURE_UNIMPLEMENTED;
    }

    private bool query_fullscreen_restore_size(WindowSize* result) const @system
    {
        clear_glfw_error();
        glfwGetWindowSize(backend_handle(), &result.width, &result.height);
        return consume_glfw_error() == GLFW_NO_ERROR;
    }

    package(xtb.window) GLFWwindow* backend_handle() const pure @system
    {
        return cast(GLFWwindow*) handle_;
    }

    package(xtb.window) BackendClientAPI backend_client_api() const pure @safe
    {
        return client_api_;
    }

    package(xtb.window) BackendGLContextCreationAPI backend_context_creation_api() const pure @safe
    {
        return context_creation_api_;
    }

    package(xtb.window) WindowSystem* owner_system() return pure @safe
    {
        return system_;
    }

    private void require_live() const @safe
    {
        version (XTB_Checked)
            require(handle_ !is null, "Window is not live");
    }

    private void dispatch(scope const WindowEvent* event) @system
    {
        if (event_handler_.callback !is null)
            event_handler_.callback(&this, event, event_handler_.context);
    }
}

private void apply_backend_window_hints(BackendWindowCreateOptions options) @system
{
    final switch (options.client_api)
    {
        case BackendClientAPI.none:
            glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
            break;
        case BackendClientAPI.opengl:
            glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API);
            break;
        case BackendClientAPI.opengl_es:
            glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
            break;
    }

    if (options.client_api == BackendClientAPI.none)
        return;

    if (options.context_version_major != 0)
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, options.context_version_major);
    if (options.context_version_minor != 0)
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, options.context_version_minor);

    final switch (options.profile)
    {
        case BackendGLProfile.any:
            glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_ANY_PROFILE);
            break;
        case BackendGLProfile.core:
            glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
            break;
        case BackendGLProfile.compatibility:
            glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_COMPAT_PROFILE);
            break;
    }

    final switch (options.context_creation_api)
    {
        case BackendGLContextCreationAPI.native:
            glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_NATIVE_CONTEXT_API);
            break;
        case BackendGLContextCreationAPI.egl:
            glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_EGL_CONTEXT_API);
            break;
        case BackendGLContextCreationAPI.os_mesa:
            glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_OSMESA_CONTEXT_API);
            break;
    }

    final switch (options.robustness)
    {
        case BackendGLRobustness.none:
            glfwWindowHint(GLFW_CONTEXT_ROBUSTNESS, GLFW_NO_ROBUSTNESS);
            break;
        case BackendGLRobustness.no_reset_notification:
            glfwWindowHint(GLFW_CONTEXT_ROBUSTNESS, GLFW_NO_RESET_NOTIFICATION);
            break;
        case BackendGLRobustness.lose_context_on_reset:
            glfwWindowHint(GLFW_CONTEXT_ROBUSTNESS, GLFW_LOSE_CONTEXT_ON_RESET);
            break;
    }

    final switch (options.release_behavior)
    {
        case BackendGLReleaseBehavior.any:
            glfwWindowHint(GLFW_CONTEXT_RELEASE_BEHAVIOR, GLFW_ANY_RELEASE_BEHAVIOR);
            break;
        case BackendGLReleaseBehavior.flush:
            glfwWindowHint(GLFW_CONTEXT_RELEASE_BEHAVIOR, GLFW_RELEASE_BEHAVIOR_FLUSH);
            break;
        case BackendGLReleaseBehavior.none:
            glfwWindowHint(GLFW_CONTEXT_RELEASE_BEHAVIOR, GLFW_RELEASE_BEHAVIOR_NONE);
            break;
    }

    glfwWindowHint(
        GLFW_OPENGL_FORWARD_COMPAT,
        options.forward_compatible ? GLFW_TRUE : GLFW_FALSE,
    );
    glfwWindowHint(
        GLFW_CONTEXT_DEBUG,
        options.debug_context ? GLFW_TRUE : GLFW_FALSE,
    );
    glfwWindowHint(
        GLFW_CONTEXT_NO_ERROR,
        options.no_error ? GLFW_TRUE : GLFW_FALSE,
    );
    glfwWindowHint(GLFW_SAMPLES, options.samples);
    glfwWindowHint(
        GLFW_SRGB_CAPABLE,
        options.srgb_capable ? GLFW_TRUE : GLFW_FALSE,
    );
    glfwWindowHint(
        GLFW_DOUBLEBUFFER,
        options.double_buffered ? GLFW_TRUE : GLFW_FALSE,
    );
}

private Window* window_from_backend(GLFWwindow* handle) @system
{
    return cast(Window*) glfwGetWindowUserPointer(handle);
}

private void install_callbacks(GLFWwindow* handle) @system
{
    glfwSetKeyCallback(handle, &on_key);
    glfwSetCharCallback(handle, &on_char);
    glfwSetMouseButtonCallback(handle, &on_mouse_button);
    glfwSetCursorPosCallback(handle, &on_cursor_position);
    glfwSetCursorEnterCallback(handle, &on_cursor_enter);
    glfwSetScrollCallback(handle, &on_scroll);
    glfwSetWindowPosCallback(handle, &on_window_position);
    glfwSetWindowSizeCallback(handle, &on_window_size);
    glfwSetWindowCloseCallback(handle, &on_window_close);
    glfwSetWindowRefreshCallback(handle, &on_window_refresh);
    glfwSetWindowFocusCallback(handle, &on_window_focus);
    glfwSetWindowIconifyCallback(handle, &on_window_iconify);
    glfwSetWindowMaximizeCallback(handle, &on_window_maximize);
    glfwSetFramebufferSizeCallback(handle, &on_framebuffer_size);
    glfwSetWindowContentScaleCallback(handle, &on_content_scale);
}

private extern (C) void on_key(
    GLFWwindow* handle,
    int backend_key,
    int scan_code,
    int backend_action,
    int backend_modifiers,
) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;

    const key = key_from_glfw(backend_key);
    const action = key_action_from_glfw(backend_action);
    if (key != Key.unknown)
        window.key_states_[cast(size_t) key].apply(action);

    WindowEvent event;
    event.kind = WindowEventKind.key;
    event.key_event = KeyEvent(
        key,
        scan_code,
        action,
        modifiers_from_glfw(backend_modifiers),
    );
    window.dispatch(&event);
}

private extern (C) void on_char(GLFWwindow* handle, uint codepoint) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;

    WindowEvent event;
    event.kind = WindowEventKind.text_input;
    event.text_input = TextInputEvent(cast(dchar) codepoint);
    window.dispatch(&event);
}

private extern (C) void on_mouse_button(
    GLFWwindow* handle,
    int backend_button,
    int backend_action,
    int backend_modifiers,
) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;

    const button = mouse_button_from_glfw(backend_button);
    if (button == MouseButton.count)
        return;
    const action = key_action_from_glfw(backend_action);
    window.mouse_states_[cast(size_t) button].apply(action);

    WindowEvent event;
    event.kind = WindowEventKind.mouse_button;
    event.mouse_button_event = MouseButtonEvent(
        button,
        action,
        modifiers_from_glfw(backend_modifiers),
    );
    window.dispatch(&event);
}

private extern (C) void on_cursor_position(
    GLFWwindow* handle,
    double x,
    double y,
) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;

    const delta_x = x - window.cursor_position_.x;
    const delta_y = y - window.cursor_position_.y;
    window.cursor_position_ = CursorPosition(x, y);
    window.cursor_delta_.x += delta_x;
    window.cursor_delta_.y += delta_y;

    WindowEvent event;
    event.kind = WindowEventKind.cursor_moved;
    event.cursor_moved = CursorMovedEvent(window.cursor_position_, delta_x, delta_y);
    window.dispatch(&event);
}

private extern (C) void on_cursor_enter(GLFWwindow* handle, int entered) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;

    window.cursor_inside_ = entered == GLFW_TRUE;
    window.cursor_entered_ = entered == GLFW_TRUE;
    window.cursor_left_ = entered != GLFW_TRUE;

    WindowEvent event;
    event.kind = entered == GLFW_TRUE
        ? WindowEventKind.cursor_entered
        : WindowEventKind.cursor_left;
    window.dispatch(&event);
}

private extern (C) void on_scroll(
    GLFWwindow* handle,
    double x,
    double y,
) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;

    window.scroll_delta_.x += x;
    window.scroll_delta_.y += y;

    WindowEvent event;
    event.kind = WindowEventKind.scroll;
    event.scroll = ScrollEvent(x, y);
    window.dispatch(&event);
}

private extern (C) void on_window_position(
    GLFWwindow* handle,
    int x,
    int y,
) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;
    WindowEvent event;
    event.kind = WindowEventKind.moved;
    event.position = WindowPosition(x, y);
    window.dispatch(&event);
}

private extern (C) void on_window_size(
    GLFWwindow* handle,
    int width,
    int height,
) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;
    WindowEvent event;
    event.kind = WindowEventKind.resized;
    event.size = WindowSize(width, height);
    window.dispatch(&event);
}

private extern (C) void on_window_close(GLFWwindow* handle) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;
    WindowEvent event;
    event.kind = WindowEventKind.close_requested;
    window.dispatch(&event);
}

private extern (C) void on_window_refresh(GLFWwindow* handle) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;
    WindowEvent event;
    event.kind = WindowEventKind.refresh_requested;
    window.dispatch(&event);
}

private extern (C) void on_window_focus(GLFWwindow* handle, int focused) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;
    WindowEvent event;
    event.kind = focused == GLFW_TRUE
        ? WindowEventKind.focus_gained
        : WindowEventKind.focus_lost;
    window.dispatch(&event);
}

private extern (C) void on_window_iconify(GLFWwindow* handle, int minimized) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;
    WindowEvent event;
    event.kind = WindowEventKind.minimized_changed;
    event.state = BoolWindowEvent(minimized == GLFW_TRUE);
    window.dispatch(&event);
}

private extern (C) void on_window_maximize(GLFWwindow* handle, int maximized) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;
    WindowEvent event;
    event.kind = WindowEventKind.maximized_changed;
    event.state = BoolWindowEvent(maximized == GLFW_TRUE);
    window.dispatch(&event);
}

private extern (C) void on_framebuffer_size(
    GLFWwindow* handle,
    int width,
    int height,
) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;
    WindowEvent event;
    event.kind = WindowEventKind.framebuffer_resized;
    event.size = WindowSize(width, height);
    window.dispatch(&event);
}

private extern (C) void on_content_scale(
    GLFWwindow* handle,
    float x,
    float y,
) nothrow @nogc @system
{
    Window* window = window_from_backend(handle);
    if (window is null)
        return;
    WindowEvent event;
    event.kind = WindowEventKind.content_scale_changed;
    event.content_scale = ContentScale(x, y);
    window.dispatch(&event);
}
