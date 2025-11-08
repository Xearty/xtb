#include "window.h"

#include <GLFW/glfw3.h>

u32 g_key_states[XTB_KEY_LAST + 1];

void window_system_init(void)
{
    glfwInit();
}

void window_system_deinit(void)
{
    glfwTerminate();
}

enum
{
    XTB_KEY_STATE_UP = 0,
    XTB_KEY_STATE_DOWN = 1,
    XTB_KEY_STATE_RELEASED = 2,
    XTB_KEY_STATE_PRESSED = 3,
};

void glfw_key_callback(GLFWwindow *window, int key, int scancode, int action, int mods)
{
    if (key < 0) return;

    switch (action)
    {
        case GLFW_PRESS:
        {
            g_key_states[key] = XTB_KEY_STATE_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            g_key_states[key] = XTB_KEY_STATE_RELEASED;
        } break;
    }
}

static void update_key_states(void)
{
    for (int key = 0; key <= XTB_KEY_LAST; ++key)
    {
        if (g_key_states[key] == XTB_KEY_STATE_PRESSED)
        {
            g_key_states[key] = XTB_KEY_STATE_DOWN;
        }
        else if (g_key_states[key] == XTB_KEY_STATE_RELEASED)
        {
            g_key_states[key] = XTB_KEY_STATE_UP;
        }
    }
}

XTB_Window *window_create(XTB_Window_Config config)
{
    u32 window_width = config.width > 0 ? config.width : 800;
    u32 window_height = config.height > 0 ? config.height : 800;
    const char *title = config.title != NULL ? config.title : "XTB Window";

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);

    if (config.flags & XTB_WIN_OPENGL_CONTEXT)
    {
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    }

    glfwWindowHint(GLFW_SAMPLES, config.samples);

    GLFWwindow *window = glfwCreateWindow(window_width, window_height, title, NULL, NULL);
    glfwSetKeyCallback(window, glfw_key_callback);

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
    update_key_states();
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

bool window_key_is_pressed(u32 key)
{
    return g_key_states[key] == XTB_KEY_STATE_PRESSED;
}

bool window_key_is_released(u32 key)
{
    return g_key_states[key] == XTB_KEY_STATE_RELEASED;
}

bool window_key_is_down(u32 key)
{
    return g_key_states[key] == XTB_KEY_STATE_DOWN
        || g_key_states[key] == XTB_KEY_STATE_PRESSED;
}

bool window_key_is_up(u32 key)
{
    return g_key_states[key] == XTB_KEY_STATE_UP
        || g_key_states[key] == XTB_KEY_STATE_RELEASED;
}

void *window_get_proc_address(const char *name)
{
    return glfwGetProcAddress(name);
}
