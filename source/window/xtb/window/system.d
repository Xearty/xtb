module xtb.window.system;

nothrow @nogc:

import xtb.types : u8;
import xtb.window.error : WindowError, WindowErrorKind, WindowResult, WindowStatus;
import xtb.window.internal.create_options : BackendWindowCreateOptions;
import xtb.window.internal.glfw;
import xtb.window.internal.glfw_error : clear_glfw_error, consume_glfw_error, glfw_call_error, glfw_call_status;
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

// GLFW has a process-global lifecycle, so only one owning WindowSystem may be
// alive at a time.
private __gshared bool window_system_active;

struct WindowSystem
{
nothrow @nogc:

    private Allocator* allocator_;
    private bool initialized_;
    private bool polling_events_;
    private Window* first_window_;
    private size_t window_count_;

    @disable this(this);

    /// Initializes the process GLFW window system. Only one XTB WindowSystem
    /// may own the GLFW lifecycle at a time. The returned pointer is stable
    /// until `deinit` and is allocated from `allocator`.
    static WindowResult!(WindowSystem*) create(
        Allocator* allocator,
        WindowSystemConfig config = WindowSystemConfig.init,
    ) @system
    {
        if (allocator is null || *allocator is null)
            return typeof(return).err(WindowError(WindowErrorKind.allocation_failed));
        if (window_system_active)
            return typeof(return).err(WindowError(WindowErrorKind.already_initialized));

        int major;
        int minor;
        int revision;
        glfwGetVersion(&major, &minor, &revision);
        if (major < 3 || (major == 3 && minor < 4))
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
        window_system_active = true;
        return typeof(return).ok(result);
    }

    /// Terminates the window system. Every window created by this system must
    /// already have been deinitialized.
    void deinit()
    {
        if (!initialized_)
            return;

        version (XTB_Checked)
            require(first_window_ is null,
                "WindowSystem deinit requires all windows to be destroyed");
        if (first_window_ !is null)
            return;

        Allocator* allocator = allocator_;
        glfwTerminate();
        window_system_active = false;
        allocator_ = null;
        initialized_ = false;
        polling_events_ = false;
        window_count_ = 0;
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
        if (!initialized_)
            return WindowPlatform.automatic;
        return window_platform(glfwGetPlatform());
    }

    static bool platform_supported(WindowPlatform platform) @system
    {
        if (platform == WindowPlatform.automatic)
            return true;
        return glfwPlatformSupported(glfw_platform(platform)) == GLFW_TRUE;
    }

    size_t window_count() const pure @safe
    {
        return window_count_;
    }

    WindowResult!(Window*) create_window(
        WindowConfig config = WindowConfig.init,
    ) @system
    {
        return create_window(allocator_, config);
    }

    WindowResult!(Window*) create_window(
        Allocator* allocator,
        WindowConfig config = WindowConfig.init,
    ) @system
    {
        version (XTB_Checked)
        {
            require(initialized_, "WindowSystem is not initialized");
            require(!polling_events_, "cannot create a window while dispatching events");
        }
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
            require(!polling_events_, "cannot create a window while dispatching events");
        }
        if (!initialized_)
            return typeof(return).err(WindowError(WindowErrorKind.initialization_failed));
        return Window.create(&this, allocator, config, backend_options);
    }

    /// Clears per-poll transition state for every window and then dispatches
    /// all pending backend events. Event handlers run synchronously inside this
    /// call.
    WindowStatus poll_events() @system
    {
        version (XTB_Checked)
        {
            require(initialized_, "WindowSystem is not initialized");
            require(!polling_events_, "WindowSystem event polling is not reentrant");
        }
        if (!initialized_)
            return typeof(return).err(WindowError(WindowErrorKind.initialization_failed));
        if (polling_events_)
            return typeof(return).ok();

        for (Window* window = first_window_; window !is null; window = window.next_window())
            window.reset_poll_state();

        polling_events_ = true;
        scope (exit)
            polling_events_ = false;
        clear_glfw_error();
        glfwPollEvents();
        return glfw_call_status(WindowErrorKind.backend_operation_failed);
    }

    WindowResult!Monitor primary_monitor() const @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");
        if (!initialized_)
            return typeof(return).err(WindowError(WindowErrorKind.initialization_failed));

        clear_glfw_error();
        GLFWmonitor* monitor = glfwGetPrimaryMonitor();
        if (monitor is null)
            return typeof(return).err(WindowError(
                    WindowErrorKind.monitor_unavailable,
                    consume_glfw_error(),
            ));
        return typeof(return).ok(Monitor.from_backend(monitor));
    }

    size_t monitor_count() const @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");
        if (!initialized_)
            return 0;

        int count;
        cast(void) glfwGetMonitors(&count);
        return count > 0 ? cast(size_t) count : 0;
    }

    WindowResult!Monitor monitor(size_t index) const @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");
        if (!initialized_)
            return typeof(return).err(WindowError(WindowErrorKind.initialization_failed));

        int count;
        GLFWmonitor** monitors = glfwGetMonitors(&count);
        if (monitors is null || index >= cast(size_t) count)
            return typeof(return).err(WindowError(WindowErrorKind.monitor_unavailable));
        return typeof(return).ok(Monitor.from_backend(monitors[index]));
    }

    WindowResult!NativeDisplayHandle native_display_handle() const @system
    {
        version (XTB_Checked)
            require(initialized_, "WindowSystem is not initialized");
        if (!initialized_)
            return typeof(return).err(WindowError(WindowErrorKind.initialization_failed));

        const selected = glfwGetPlatform();
        version (Windows)
        {
            if (selected == GLFW_PLATFORM_WIN32)
            {
                NativeDisplayHandle result;
                result.platform = NativeWindowPlatform.win32;
                result.win32 = Win32DisplayHandle(GetModuleHandleW(null));
                return typeof(return).ok(result);
            }
        }
        else version (linux)
        {
            if (selected == GLFW_PLATFORM_X11)
            {
                clear_glfw_error();
                void* display = glfwGetX11Display();
                if (display is null)
                    return typeof(return).err(WindowError(
                            WindowErrorKind.native_handle_unavailable,
                            consume_glfw_error(),
                    ));
                NativeDisplayHandle result;
                result.platform = NativeWindowPlatform.x11;
                result.x11 = X11DisplayHandle(display);
                return typeof(return).ok(result);
            }
            if (selected == GLFW_PLATFORM_WAYLAND)
            {
                clear_glfw_error();
                void* display = glfwGetWaylandDisplay();
                if (display is null)
                    return typeof(return).err(WindowError(
                            WindowErrorKind.native_handle_unavailable,
                            consume_glfw_error(),
                    ));
                NativeDisplayHandle result;
                result.platform = NativeWindowPlatform.wayland;
                result.wayland = WaylandDisplayHandle(display);
                return typeof(return).ok(result);
            }
        }

        return typeof(return).err(WindowError(WindowErrorKind.native_handle_unavailable));
    }

    package(xtb.window) Allocator* allocator_for_windows() return pure @safe
    {
        return allocator_;
    }

    package(xtb.window) bool polling_events() const pure @safe
    {
        return polling_events_;
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
