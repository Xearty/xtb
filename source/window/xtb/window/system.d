module xtb.window.system;

nothrow @nogc:

import xtb.types : u8;
import xtb.window.error : WindowError, WindowErrorKind, WindowResult;
import xtb.window.event : WindowSystemEvent, WindowSystemEventKind;
import xtb.window.internal.create_options : BackendWindowCreateOptions;
import xtb.window.internal.glfw;
import xtb.window.internal.glfw_error : clear_glfw_error, consume_glfw_error, glfw_call_error;
import xtb.window.monitor : Monitor;
import xtb.window.native : NativeDisplayHandle, NativeWindowPlatform,
    WaylandDisplayHandle, Win32DisplayHandle, X11DisplayHandle;
import xtb.window.window : Window, WindowConfig;
import xtb.memory : Allocator, deallocate, tryAllocateInit;

version (XTB_Checked) import xtb.panic : require;

version (Windows)
{
    extern (Windows) void* GetModuleHandleW(const(wchar)* module_name) nothrow @nogc;
}

enum WindowPlatform : u8
{
    automatic,
    win32,
    cocoa,
    wayland,
    x11,
    headless,
}

struct WindowSystemConfig
{
    WindowPlatform platform = WindowPlatform.automatic;
}

private int glfw_platform(WindowPlatform platform) pure @safe
{
    final switch (platform)
    {
        case WindowPlatform.automatic:
            return GLFW_ANY_PLATFORM;
        case WindowPlatform.win32:
            return GLFW_PLATFORM_WIN32;
        case WindowPlatform.cocoa:
            return GLFW_PLATFORM_COCOA;
        case WindowPlatform.wayland:
            return GLFW_PLATFORM_WAYLAND;
        case WindowPlatform.x11:
            return GLFW_PLATFORM_X11;
        case WindowPlatform.headless:
            return GLFW_PLATFORM_NULL;
    }
}

private WindowPlatform window_platform(int platform) pure @safe
{
    switch (platform)
    {
        case GLFW_PLATFORM_WIN32:
            return WindowPlatform.win32;
        case GLFW_PLATFORM_COCOA:
            return WindowPlatform.cocoa;
        case GLFW_PLATFORM_WAYLAND:
            return WindowPlatform.wayland;
        case GLFW_PLATFORM_X11:
            return WindowPlatform.x11;
        case GLFW_PLATFORM_NULL:
            return WindowPlatform.headless;
        default:
            return WindowPlatform.automatic;
    }
}

alias WindowSystemEventFn = void function(
    WindowSystem* system,
    scope const WindowSystemEvent* event,
    void* context,
) nothrow @nogc;

struct WindowSystemEventHandler
{
    WindowSystemEventFn callback;
    void* context;
}

// GLFW has a process-global lifecycle, so this is also the single active XTB
// owner used to route process-level GLFW callbacks.
private __gshared WindowSystem* active_window_system;

struct WindowSystem
{
nothrow @nogc:

    private Allocator* allocator_;
    private bool initialized_;
    private Window* first_window_;
    private size_t window_count_;
    private WindowSystemEventHandler event_handler_;

    @disable this(this);

    /// Initializes the process GLFW window system. XTB exclusively owns the
    /// process-global GLFW lifecycle while a WindowSystem is alive: GLFW must
    /// not already be initialized by application code or another library, and
    /// external code must not initialize, terminate, or replace process-global
    /// GLFW callbacks until `deinit`. Only one XTB WindowSystem may own this
    /// lifecycle at a time. `allocator` must be non-null. The returned pointer
    /// is stable until `deinit` and is allocated from `allocator`.
    static WindowResult!(WindowSystem*) create(
        Allocator* allocator,
        WindowSystemConfig config = WindowSystemConfig.init,
    ) @system
    {
        version (XTB_Checked)
            require(allocator !is null && *allocator !is null, "WindowSystem allocator is null");
        if (active_window_system !is null)
            return typeof(return).err(WindowError(WindowErrorKind.already_initialized));

        int major;
        int minor;
        int revision;
        glfwGetVersion(&major, &minor, &revision);
        // XTB declares the GLFW 3.x ABI directly. Do not assume a future major
        // version is ABI-compatible merely because its number is newer; support
        // for another major must be an explicit XTB compatibility update.
        if (major != 3 || minor < 4)
            return typeof(return).err(WindowError(
                    WindowErrorKind.unsupported_backend_version,
            ));

        const requested = glfw_platform(config.platform);
        clear_glfw_error();
        if (config.platform != WindowPlatform.automatic &&
            glfwPlatformSupported(requested) != GLFW_TRUE)
        {
            return typeof(return).err(WindowError(
                    WindowErrorKind.platform_unavailable,
                    consume_glfw_error(),
            ));
        }

        clear_glfw_error();
        glfwInitHint(GLFW_PLATFORM, requested);
        const init_hint_error = glfw_call_error(WindowErrorKind.initialization_failed);
        if (init_hint_error.failed)
            return typeof(return).err(init_hint_error);

        clear_glfw_error();
        if (glfwInit() != GLFW_TRUE)
            return typeof(return).err(WindowError(
                    WindowErrorKind.initialization_failed,
                    consume_glfw_error(),
            ));

        WindowSystem* result = allocator.tryAllocateInit!WindowSystem();
        if (result is null)
        {
            glfwTerminate();
            return typeof(return).err(WindowError(WindowErrorKind.allocation_failed));
        }
        result.allocator_ = allocator;
        result.initialized_ = true;

        clear_glfw_error();
        glfwSetMonitorCallback(&glfw_monitor_callback);
        const callback_error = glfw_call_error(WindowErrorKind.initialization_failed);
        if (callback_error.failed)
        {
            result.initialized_ = false;
            allocator.deallocate(result);
            glfwTerminate();
            return typeof(return).err(callback_error);
        }

        active_window_system = result;
        return typeof(return).ok(result);
    }

    /// Terminates XTB's process-global GLFW lifecycle. Every window created by
    /// this system must already have been deinitialized. Must not be called
    /// while XTB is dispatching a window-system or window event callback. This
    /// calls `glfwTerminate`, so external GLFW resources must not coexist with
    /// a live WindowSystem.
    void deinit()
    {
        if (!initialized_)
            return;

        version (XTB_Checked)
            require(first_window_ is null,
                "WindowSystem deinit requires all windows to be destroyed");

        Allocator* allocator = allocator_;
        glfwSetMonitorCallback(null);
        active_window_system = null;
        glfwTerminate();
        allocator_ = null;
        initialized_ = false;
        window_count_ = 0;
        event_handler_ = WindowSystemEventHandler.init;
        allocator.deallocate(&this);
    }

    bool initialized() const pure @safe
    {
        return initialized_;
    }

    WindowPlatform platform() const @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");
        return window_platform(glfwGetPlatform());
    }

    /// Returns whether the linked GLFW binary was compiled with support for
    /// `platform`. This does not imply that the platform is usable in the
    /// current environment. `automatic` is not a concrete platform.
    static bool platform_compiled_in(WindowPlatform platform) @system
    {
        version (XTB_Checked)
            require(platform != WindowPlatform.automatic,
                "automatic is not a concrete window platform");
        return glfwPlatformSupported(glfw_platform(platform)) == GLFW_TRUE;
    }

    size_t window_count() const pure @safe
    {
        return window_count_;
    }

    /// Sets the handler for process-level window-system events such as monitor
    /// connection changes. The handler runs synchronously during backend event
    /// processing. Ordinary window commands may be called from the handler, but
    /// it must not call `poll_events` or `deinit` on the WindowSystem.
    void set_event_handler(WindowSystemEventHandler handler) @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");
        event_handler_ = handler;
    }

    /// Creates a native window. Requires an installed thread context for
    /// temporary title conversion.
    WindowResult!(Window*) create_window(
        WindowConfig config = WindowConfig.init,
    ) @system
    {
        return create_window(allocator_, config);
    }

    /// Allocator-selecting counterpart to `create_window`. Requires an
    /// installed thread context for temporary title conversion.
    WindowResult!(Window*) create_window(
        Allocator* allocator,
        WindowConfig config = WindowConfig.init,
    ) @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");
        return create_window_with_backend_options(
            allocator,
            config,
            BackendWindowCreateOptions.init,
        );
    }

    package(xtb.window) WindowResult!(Window*) create_window_with_backend_options(
        Allocator* allocator,
        WindowConfig config,
        BackendWindowCreateOptions backend_options,
    ) @system
    {
        version (XTB_Checked)
        {
            require(initialized_, "WindowSystem is not initialized");
            require(allocator !is null && *allocator !is null, "Window allocator is null");
        }
        return Window.create(&this, allocator, config, backend_options);
    }

    /// Dispatches pending backend events, then publishes one transition batch
    /// per window. A batch includes callbacks delivered since the previous
    /// completed poll, including synchronous callbacks caused by other GLFW
    /// calls between polls. Event handlers run synchronously inside this call.
    /// Must not be called from a window-system or window event callback.
    void poll_events() @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");

        // Do not bracket glfwPollEvents with glfwGetError. GLFW may invoke an
        // application callback before glfwPollEvents returns, and that callback
        // may make another GLFW call on this thread. GLFW exposes only one
        // thread-local last-error slot, with no provenance, so reading it here
        // could incorrectly attribute the nested call's error to the poll. Event
        // processing is a command anyway; callers have no useful per-poll
        // recovery path for a backend error.
        glfwPollEvents();

        // Do not clear transitions before glfwPollEvents. GLFW callbacks are
        // not confined to event-polling calls, so pending transitions may
        // already contain valid events delivered between the previous poll and
        // this one. Publishing after dispatch preserves those events and folds
        // callbacks from this poll into the same observable batch.
        for (Window* window = first_window_; window !is null; window = window.next_window())
            window.publish_input_transitions();
    }

    /// Returns the current primary monitor, or an invalid Monitor if no monitor
    /// is currently connected.
    Monitor primary_monitor() const @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");
        return Monitor.from_backend(glfwGetPrimaryMonitor());
    }

    size_t monitor_count() const @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");

        int count;
        cast(void) glfwGetMonitors(&count);
        return count > 0 ? cast(size_t) count : 0;
    }

    /// Returns the connected monitor at `index`, or an invalid Monitor if the
    /// index no longer exists. Monitor enumeration may change as devices are
    /// connected and disconnected.
    Monitor monitor(size_t index) const @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");

        int count;
        GLFWmonitor** monitors = glfwGetMonitors(&count);
        if (monitors is null || index >= cast(size_t) count)
            return Monitor.init;
        return Monitor.from_backend(monitors[index]);
    }

    /// Returns the native display for the selected window-system backend, or
    /// an invalid handle when the active backend has no corresponding native
    /// display. On Linux, linking xtb.window requires GLFW to be built with
    /// both the X11 and Wayland backends because XTB references both
    /// native-access APIs.
    NativeDisplayHandle native_display_handle() const @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");

        const selected = glfwGetPlatform();
        version (Windows)
        {
            if (selected == GLFW_PLATFORM_WIN32)
            {
                NativeDisplayHandle result;
                result.platform = NativeWindowPlatform.win32;
                result.win32 = Win32DisplayHandle(GetModuleHandleW(null));
                return result;
            }
        }
        else version (linux)
        {
            if (selected == GLFW_PLATFORM_X11)
            {
                void* display = glfwGetX11Display();
                if (display is null)
                    return NativeDisplayHandle.init;
                NativeDisplayHandle result;
                result.platform = NativeWindowPlatform.x11;
                result.x11 = X11DisplayHandle(display);
                return result;
            }
            if (selected == GLFW_PLATFORM_WAYLAND)
            {
                void* display = glfwGetWaylandDisplay();
                if (display is null)
                    return NativeDisplayHandle.init;
                NativeDisplayHandle result;
                result.platform = NativeWindowPlatform.wayland;
                result.wayland = WaylandDisplayHandle(display);
                return result;
            }
        }

        return NativeDisplayHandle.init;
    }

    package(xtb.window) void dispatch_event(scope const WindowSystemEvent* event) @system
    {
        if (event_handler_.callback !is null)
            event_handler_.callback(&this, event, event_handler_.context);
    }

    package(xtb.window) Allocator* allocator_for_windows() return pure @safe
    {
        return allocator_;
    }

    package(xtb.window) void link_window(Window* window) @system
    {
        window.set_list_links(null, first_window_);
        if (first_window_ !is null)
            first_window_.set_previous_window(window);
        first_window_ = window;
        ++window_count_;
    }

    package(xtb.window) void unlink_window(Window* window) @system
    {
        Window* previous = window.previous_window();
        Window* next = window.next_window();
        if (previous !is null)
            previous.set_next_window(next);
        else
            first_window_ = next;
        if (next !is null)
            next.set_previous_window(previous);
        window.set_list_links(null, null);
        if (window_count_ != 0)
            --window_count_;
    }
}

private extern (C) void glfw_monitor_callback(GLFWmonitor* monitor, int backend_event)
{
    WindowSystem* system = active_window_system;
    if (system is null || monitor is null)
        return;

    WindowSystemEvent event;
    switch (backend_event)
    {
        case GLFW_CONNECTED:
            event.kind = WindowSystemEventKind.monitor_connected;
            break;
        case GLFW_DISCONNECTED:
            event.kind = WindowSystemEventKind.monitor_disconnected;
            break;
        default:
            return;
    }
    event.monitor = Monitor.from_backend(monitor);
    system.dispatch_event(&event);
}
