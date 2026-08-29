module tests.window_glfw_smoke_tests;

nothrow @nogc:

import xtb.allocators.malloc : mallocAllocator;
import xtb.memory : Allocator;
import xtb.thread_context : ThreadContextScope;
import xtb.window;

extern (C) int main() @system
{
    ThreadContextScope thread_context = ThreadContextScope.acquire();
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

    version (linux)
    {
        if (!WindowSystem.platform_compiled_in(WindowPlatform.x11) ||
            !WindowSystem.platform_compiled_in(WindowPlatform.wayland))
            return 7;
    }

    WindowConfig window_config;
    window_config.width = 64;
    window_config.height = 64;
    window_config.title = "xtb.window GLFW smoke test";
    window_config.visible = false;

    auto window_result = system.create_window(window_config);
    if (window_result.isErr)
        return 3;
    Window* window = window_result.take();
    scope (exit)
        window.deinit();

    if (!window.valid)
        return 4;

    const size = window.size();
    if (size.width != window_config.width || size.height != window_config.height)
        return 5;

    const content_scale = window.content_scale();
    if (!(content_scale.x > 0) || !(content_scale.y > 0))
        return 8;

    if (system.poll_events().isErr)
        return 6;

    return 0;
}
