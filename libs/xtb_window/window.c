#include "window.h"

#include <GLFW/glfw3.h>

XTB_Key_State g_keyboard_key_states[XTB_KEY_LAST + 1];
XTB_Key_State g_mouse_button_states[GLFW_MOUSE_BUTTON_LAST + 1];
u32 g_prev_cursor_position[2];
u32 g_cursor_position[2];

void window_system_init(void)
{
    glfwInit();
}

void window_system_deinit(void)
{
    glfwTerminate();
}

static void glfw_key_callback(GLFWwindow *window, int key, int scancode, int action, int mods)
{
    if (key < 0) return;

    switch (action)
    {
        case GLFW_PRESS:
        {
            g_keyboard_key_states[key] = XTB_KEY_STATE_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            g_keyboard_key_states[key] = XTB_KEY_STATE_RELEASED;
        } break;
    }
}

static void glfw_cursor_callback(GLFWwindow *window, double xposd, double yposd)
{
    g_prev_cursor_position[0] = g_cursor_position[0];
    g_prev_cursor_position[1] = g_cursor_position[1];

    g_cursor_position[0] = (float)xposd;
    g_cursor_position[1] = (float)yposd;
}

static void glfw_mouse_button_callback(GLFWwindow *window, int button, int action, int mods)
{
    if (button < 0) return;

    switch (action)
    {
        case GLFW_PRESS:
        {
            g_mouse_button_states[button] = XTB_KEY_STATE_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            g_mouse_button_states[button] = XTB_KEY_STATE_RELEASED;
        } break;
    }
}

static void update_keyboard_key_states(void)
{
    for (int key = 0; key <= XTB_KEY_LAST; ++key)
    {
        if (g_keyboard_key_states[key] == XTB_KEY_STATE_PRESSED)
        {
            g_keyboard_key_states[key] = XTB_KEY_STATE_DOWN;
        }
        else if (g_keyboard_key_states[key] == XTB_KEY_STATE_RELEASED)
        {
            g_keyboard_key_states[key] = XTB_KEY_STATE_UP;
        }
    }
}

static void update_mouse_button_states(void)
{
    for (int button = 0; button <= XTB_MOUSE_BUTTON_LAST; ++button)
    {
        if (g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED)
        {
            g_mouse_button_states[button] = XTB_KEY_STATE_DOWN;
        }
        else if (g_mouse_button_states[button] == XTB_KEY_STATE_RELEASED)
        {
            g_mouse_button_states[button] = XTB_KEY_STATE_UP;
        }
    }
}

XTB_Window *window_create(XTB_Window_Config config)
{
    u32 window_width = config.width > 0 ? config.width : 800;
    u32 window_height = config.height > 0 ? config.height : 800;
    const char *title = config.title != NULL ? config.title : "XTB Window";

    if (config.flags & XTB_WIN_OPENGL_CONTEXT)
    {
        u32 major = config.opengl.major_version ? config.opengl.major_version : 3;
        u32 minor = config.opengl.minor_version ? config.opengl.minor_version : 3;

        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, major);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, minor);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    }

    glfwWindowHint(GLFW_SAMPLES, config.samples);

    GLFWwindow *window = glfwCreateWindow(window_width, window_height, title, NULL, NULL);
    glfwSetKeyCallback(window, glfw_key_callback);
    glfwSetCursorPosCallback(window, glfw_cursor_callback);
    glfwSetMouseButtonCallback(window, glfw_mouse_button_callback);

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
    update_keyboard_key_states();
    update_mouse_button_states();
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

XTB_Key_State window_key_get_state(u32 key)
{
    return g_keyboard_key_states[key];
}

bool window_key_is_pressed(u32 key)
{
    return g_keyboard_key_states[key] == XTB_KEY_STATE_PRESSED;
}

bool window_key_is_released(u32 key)
{
    return g_keyboard_key_states[key] == XTB_KEY_STATE_RELEASED;
}

bool window_key_is_down(u32 key)
{
    return g_keyboard_key_states[key] == XTB_KEY_STATE_DOWN
        || g_keyboard_key_states[key] == XTB_KEY_STATE_PRESSED;
}

bool window_key_is_up(u32 key)
{
    return g_keyboard_key_states[key] == XTB_KEY_STATE_UP
        || g_keyboard_key_states[key] == XTB_KEY_STATE_RELEASED;
}

XTB_Key_State window_mouse_button_get_state(u32 button)
{
    return g_mouse_button_states[button];
}

bool window_mouse_button_is_pressed(u32 button)
{
    return g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED;
}

bool window_mouse_button_is_released(u32 button)
{
    return g_mouse_button_states[button] == XTB_KEY_STATE_RELEASED;
}

bool window_mouse_button_is_down(u32 button)
{
    return g_mouse_button_states[button] == XTB_KEY_STATE_DOWN
        || g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED;
}

bool window_mouse_button_is_up(u32 button)
{
    return g_mouse_button_states[button] == XTB_KEY_STATE_UP
        || g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED;
}

void *window_get_proc_address(const char *name)
{
    return glfwGetProcAddress(name);
}

void window_get_cursor_position(float *x, float *y)
{
    *x = g_cursor_position[0];
    *y = g_cursor_position[1];
}

void window_get_previous_cursor_position(float *x, float *y)
{
    *x = g_prev_cursor_position[0];
    *y = g_prev_cursor_position[1];
}

void window_get_cursor_delta(float *x, float *y)
{
    *x = g_cursor_position[0] - g_prev_cursor_position[0];
    *y = g_cursor_position[1] - g_prev_cursor_position[1];
}

