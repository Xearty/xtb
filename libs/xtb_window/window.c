#include "window.h"

#include <GLFW/glfw3.h>

void window_system_init(void)
{
    glfwInit();
}

void window_system_deinit(void)
{
    glfwTerminate();
}

XTB_Window *window_create(XTB_Window_Config config)
{
    u32 window_width = config.width > 0 ? config.width : 800;
    u32 window_height = config.height > 0 ? config.height : 800;
    const char *title = config.title != NULL ? config.title : "XTB Window";

    glfwInit();
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);

    if (config.flags & XTB_WIN_OPENGL_CONTEXT)
    {
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    }

    glfwWindowHint(GLFW_SAMPLES, config.samples);

    GLFWwindow *window = glfwCreateWindow(window_width, window_height, title, NULL, NULL);

    return (XTB_Window*)window;
}

void window_destroy(XTB_Window *window)
{
    glfwDestroyWindow((GLFWwindow*)window);
}

bool window_should_close(XTB_Window *window)
{
    return glfwWindowShouldClose((GLFWwindow*)window);
}

void window_poll_events(XTB_Window *window)
{
    glfwPollEvents();
}

void window_swap_buffers(XTB_Window *window)
{
    glfwSwapBuffers((GLFWwindow*)window);
}

void window_make_context_current(XTB_Window *window)
{
    glfwMakeContextCurrent((GLFWwindow*)window);
}
