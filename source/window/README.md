# xtb.window

`xtb.window` provides BetterC desktop window creation, event processing, input
state, monitor access, fullscreen transitions, cursor control, native
window-system handles, and an optional OpenGL/OpenGL ES context layer.

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
    system.poll_events();

    if (window.key_pressed(Key.escape))
        window.request_close();
}
```

`WindowSystem` and its window creation, destruction, and event processing are
main-thread operations. Every window must be destroyed before its system is
deinitialized. A `Monitor` is a borrowed backend handle and must be reacquired
after monitor disconnection.

## OpenGL

OpenGL-specific creation requirements live in `OpenGLContextConfig`, not
`WindowConfig`:

```d
WindowConfig window_config;
window_config.width = 1280;
window_config.height = 720;
window_config.title = "OpenGL example";

OpenGLContextConfig gl_config;
gl_config.context_version = OpenGLVersion(4, 5);
gl_config.profile = OpenGLProfile.core;
gl_config.debug_context = true;
gl_config.framebuffer.samples = 4;
gl_config.framebuffer.srgb_capable = true;

auto context_result = create_opengl_window(
    system,
    window_config,
    gl_config,
);
if (context_result.isErr)
    return 1;

OpenGLContext context = context_result.take();
Window* window = context.window;
scope (exit) window.deinit();

if (context.make_current().isErr)
    return 1;
if (context.set_swap_interval(1).isErr)
    return 1;

while (!window.should_close())
{
    system.poll_events();

    // Render through your OpenGL bindings.

    if (context.swap_buffers().isErr)
        return 1;
}
```

`OpenGLContext` is a non-owning typed handle. Destroying its `Window` destroys
the context. Like other borrowed XTB pointers/views, a context handle must not
be accessed afterward; `context.valid` is not a lifetime check for stale
handles. XTB does not provide OpenGL function declarations or a loader; use
`context.proc_address` with the OpenGL binding/loader chosen by the application.

The default context configuration requests desktop OpenGL 3.3 core. For OpenGL
ES, start from `OpenGLContextConfig.opengl_es()`, which requests OpenGL ES 3.0
and clears desktop-only profile requirements. Contexts may share objects by
setting `shared_context`; both contexts must belong to the same `WindowSystem`
and use the same client API and context creation API.

A context may be current on only one thread at a time. After creation, context
operations such as `make_current`, `swap_buffers`, `set_swap_interval`,
`proc_address`, and `extension_supported` may be used on the render thread as
long as the application synchronizes window/context access and keeps window
lifecycle, `context.info`, and event processing on the main thread. A context
must be detached from any render thread before its Window is destroyed.

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
