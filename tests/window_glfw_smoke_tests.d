module tests.window_glfw_smoke_tests;

nothrow @nogc:

import xtb.allocators.malloc : mallocAllocator;
import xtb.memory : Allocator;
import xtb.window;

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

    if (system.poll_events().isErr)
        return 6;

    return 0;
}
