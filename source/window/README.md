# xtb.window

`xtb.window` provides BetterC desktop window creation, event processing, input
state, monitor access, fullscreen transitions, cursor control, native
window-system handles, and an optional OpenGL/OpenGL ES integration layer.

The generic window API is deliberately graphics-API agnostic. `WindowConfig`
describes the native window only. `WindowSystem.create_window` creates a window
with no client graphics API, while graphics integrations supply their own
creation-time requirements without putting Vulkan, Direct3D, Metal, OpenGL,
swap-chain, sample-count, or vsync policy into `WindowConfig`.

The initial backend is GLFW 3.4 or newer. Applications using this subpackage
must link GLFW. On Linux a GLFW build with runtime X11/Wayland support is
recommended.

## Minimal use

```d
import xtb.allocators.malloc : mallocAllocator;
import xtb.window;

auto system_result = WindowSystem.create(mallocAllocator());
if (system_result.isErr)
    return 1;
WindowSystem* system = system_result.take();
scope (exit) system.deinit();

auto window_result = system.create_window(WindowConfig.init);
if (window_result.isErr)
    return 1;
Window* window = window_result.take();
scope (exit) window.deinit();

while (!window.should_close())
{
    if (system.poll_events().isErr)
        return 1;

    if (window.key_pressed(Key.escape))
        window.request_close();
}
```

`WindowSystem` and its window creation, destruction, and event processing are
main-thread operations. Exactly one live `WindowSystem` may own GLFW at a time;
a second `WindowSystem.create()` returns `WindowErrorKind.already_initialized`.
Every window must be destroyed before its system is deinitialized. A `Monitor`
is a borrowed backend handle and must be reacquired after monitor disconnection.

Platform-facing mutations and event polling return `WindowStatus`. A backend
failure is reported as `WindowErrorKind.backend_operation_failed` with the
original GLFW error code preserved in `backend_code`. Simple state queries keep
value-returning APIs; use events when backend-independent state tracking is
preferred.

## OpenGL

OpenGL support is an extension module in the same `xtb:window` library. Import
it explicitly when needed:

```d
import xtb.window;
import xtb.window.opengl;
```

OpenGL-specific creation requirements live in `OpenGLConfig`, not
`WindowConfig`:

```d
WindowConfig window_config;
window_config.width = 1280;
window_config.height = 720;
window_config.title = "OpenGL example";

OpenGLConfig gl_config;
gl_config.context_version = OpenGLVersion(4, 5);
gl_config.profile = OpenGLProfile.core;
gl_config.debug_context = true;
gl_config.framebuffer.samples = 4;
gl_config.framebuffer.srgb_capable = true;

auto window_result = system.create_opengl_window(window_config, gl_config);
if (window_result.isErr)
    return 1;

Window* window = window_result.take();
scope (exit) window.deinit();

if (window.make_context_current().isErr)
    return 1;
if (window.set_swap_interval(1).isErr)
    return 1;

while (!window.should_close())
{
    if (system.poll_events().isErr)
        return 1;

    // Render through your OpenGL bindings.

    if (window.swap_buffers().isErr)
        return 1;
}
```

The `Window*` remains the primary object for both ordinary window operations and
OpenGL integration. OpenGL functions are defined by `xtb.window.opengl` and use
D UFCS, so `window.swap_buffers()` does not make OpenGL part of the base
`Window` API. This also lets an application choose its renderer at runtime while
using the same `Window*` type after creation.

XTB does not provide OpenGL function declarations or a loader; use
`window.opengl_proc_address()` with the OpenGL binding/loader chosen by the
application. The default configuration requests desktop OpenGL 3.3 core. For
OpenGL ES, start from `OpenGLConfig.opengl_es()`, which requests OpenGL ES 3.0
and clears desktop-only profile requirements. Contexts may share objects by
setting `share_context_with` to another OpenGL window; both windows must belong
to the same `WindowSystem` and use the same client API and context creation API.

An OpenGL context may be current on only one thread at a time. After creation,
operations such as `make_context_current`, `swap_buffers`, `set_swap_interval`,
`opengl_proc_address`, and `opengl_extension_supported` may be used on the
render thread as long as the application synchronizes access and keeps window
lifecycle, `opengl_context_info`, and event processing on the main thread. The
context must be detached with `clear_current_context()` before its Window is
destroyed from another thread.

`OpenGLContextCreationAPI.os_mesa` is available for headless contexts when the
GLFW build and host provide OSMesa. The window test uses this path when
available, but does not require an OSMesa runtime.

## Other graphics APIs

Generic windows remain no-client-API windows. Future Vulkan integration can
create a presentation surface from the window-system/native-handle layer;
Direct3D and Metal integrations can likewise consume the Win32 and Cocoa native
handles without changing `WindowConfig`. The internal pre-creation seam also
supports graphics APIs, such as OpenGL, that must supply attributes before the
native window exists.
