#include "window.h"

#include <GLFW/glfw3.h>

/****************************************************************
 * Global State (Internal)
****************************************************************/
XTB_Key_State g_keyboard_key_states[XTB_KEY_LAST + 1];
XTB_Key_State g_mouse_button_states[GLFW_MOUSE_BUTTON_LAST + 1];
f32 g_prev_cursor_position[2];
f32 g_cursor_position[2];
f32 g_scroll_offset[2];
XTB_Cursor_Focus_State g_cursor_focus_state;
bool g_cursor_visible;
bool g_cursor_captured;

/****************************************************************
 * GLFW Callbacks (Internal)
****************************************************************/
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

static void glfw_cursor_pos_callback(GLFWwindow *window, double xpos, double ypos)
{
    g_prev_cursor_position[0] = g_cursor_position[0];
    g_prev_cursor_position[1] = g_cursor_position[1];

    g_cursor_position[0] = (f32)xpos;
    g_cursor_position[1] = (f32)ypos;
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

static void glfw_cursor_enter_callback(GLFWwindow *window, int entered)
{
    g_cursor_focus_state = entered
        ? XTB_CURSOR_FOCUS_JUST_ENTERED
        : XTB_CURSOR_FOCUS_JUST_LEFT;
}

static void glfw_scroll_callback(GLFWwindow *window, double xoffset, double yoffset)
{
    g_scroll_offset[0] = (f32)xoffset;
    g_scroll_offset[1] = (f32)yoffset;
}

/****************************************************************
 * State Update (Internal)
****************************************************************/
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

static void update_cursor_focus_state(void)
{
    if (g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_ENTERED)
    {
        g_cursor_focus_state = XTB_CURSOR_FOCUS_INSIDE;
    }
    else if (g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_LEFT)
    {
        g_cursor_focus_state = XTB_CURSOR_FOCUS_OUTSIDE;
    }
}

/****************************************************************
 * Window System
****************************************************************/
void window_system_init(void)
{
    glfwInit();
}

void window_system_deinit(void)
{
    glfwTerminate();
}

/****************************************************************
 * Window
****************************************************************/
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
    glfwSetCursorPosCallback(window, glfw_cursor_pos_callback);
    glfwSetMouseButtonCallback(window, glfw_mouse_button_callback);
    glfwSetCursorEnterCallback(window, glfw_cursor_enter_callback);
    glfwSetScrollCallback(window, glfw_scroll_callback);

    g_cursor_visible = true;

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
    // NOTE(xearty): Clear the scroll offset before
    // we poll so it only persists for a single frame
    g_scroll_offset[0] = g_scroll_offset[1] = 0.0f;

    update_keyboard_key_states();
    update_mouse_button_states();
    update_cursor_focus_state();
    glfwPollEvents();
}

void window_make_context_current(XTB_Window *window)
{
    glfwMakeContextCurrent((GLFWwindow*)window);
}

void window_swap_buffers(XTB_Window *window)
{
    glfwSwapBuffers((GLFWwindow*)window);
}

void window_request_close(XTB_Window *window)
{
    glfwSetWindowShouldClose((GLFWwindow*)window, GLFW_TRUE);
}

void window_set_title(XTB_Window *window, const char *title)
{
    glfwSetWindowTitle((GLFWwindow*)window, title);
}

/****************************************************************
 * Keyboard Input
****************************************************************/
XTB_Key_State window_key_get_state(u32 key)
{
    return g_keyboard_key_states[key];
}

bool window_key_is_up(u32 key)
{
    return g_keyboard_key_states[key] == XTB_KEY_STATE_UP
        || g_keyboard_key_states[key] == XTB_KEY_STATE_RELEASED;
}

bool window_key_is_down(u32 key)
{
    return g_keyboard_key_states[key] == XTB_KEY_STATE_DOWN
        || g_keyboard_key_states[key] == XTB_KEY_STATE_PRESSED;
}

bool window_key_is_released(u32 key)
{
    return g_keyboard_key_states[key] == XTB_KEY_STATE_RELEASED;
}

bool window_key_is_pressed(u32 key)
{
    return g_keyboard_key_states[key] == XTB_KEY_STATE_PRESSED;
}

/****************************************************************
 * Mouse Input
****************************************************************/
XTB_Key_State window_mouse_button_get_state(u32 button)
{
    return g_mouse_button_states[button];
}

bool window_mouse_button_is_up(u32 button)
{
    return g_mouse_button_states[button] == XTB_KEY_STATE_UP
        || g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED;
}

bool window_mouse_button_is_down(u32 button)
{
    return g_mouse_button_states[button] == XTB_KEY_STATE_DOWN
        || g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED;
}

bool window_mouse_button_is_released(u32 button)
{
    return g_mouse_button_states[button] == XTB_KEY_STATE_RELEASED;
}

bool window_mouse_button_is_pressed(u32 button)
{
    return g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED;
}

void window_cursor_get_position(f32 *x, f32 *y)
{
    *x = g_cursor_position[0];
    *y = g_cursor_position[1];
}

void window_cursor_get_previous_position(f32 *x, f32 *y)
{
    *x = g_prev_cursor_position[0];
    *y = g_prev_cursor_position[1];
}

void window_cursor_get_delta(f32 *x, f32 *y)
{
    *x = g_cursor_position[0] - g_prev_cursor_position[0];
    *y = g_cursor_position[1] - g_prev_cursor_position[1];
}

XTB_Cursor_Focus_State window_cursor_get_focus(void)
{
    return g_cursor_focus_state;
}

bool window_cursor_is_inside_window(void)
{
    return g_cursor_focus_state == XTB_CURSOR_FOCUS_INSIDE
        || g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_ENTERED;
}

bool window_cursor_is_outside_window(void)
{
    return g_cursor_focus_state == XTB_CURSOR_FOCUS_OUTSIDE
        || g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_LEFT;
}

bool window_cursor_just_entered_window(void)
{
    return g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_ENTERED;
}

bool window_cursor_just_left_window(void)
{
    return g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_LEFT;
}

void window_scroll_get_delta(f32 *x, f32 *y)
{
    *x = g_scroll_offset[0];
    *y = g_scroll_offset[1];
}

f32 window_scroll_delta_x(void)
{
    return g_scroll_offset[0];
}

f32 window_scroll_delta_y(void)
{
    return g_scroll_offset[1];
}

bool window_scroll_this_frame(void)
{
    return g_scroll_offset[0] != 0.0f && g_scroll_offset[1] != 0.0f;
}

void window_cursor_show(XTB_Window *window)
{
    glfwSetInputMode((GLFWwindow*)window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    g_cursor_visible = true;
}

void window_cursor_hide(XTB_Window *window)
{
    glfwSetInputMode((GLFWwindow*)window, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
    g_cursor_visible = false;
}

bool window_cursor_is_visible(const XTB_Window *window)
{
    return g_cursor_visible;
}

void window_cursor_capture(XTB_Window *window)
{
    glfwSetInputMode((GLFWwindow*)window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    g_cursor_captured = true;
}

void window_cursor_release(XTB_Window *window)
{
    glfwSetInputMode((GLFWwindow*)window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    g_cursor_captured = false;
}

bool window_cursor_is_captured(const XTB_Window *window)
{
    return g_cursor_captured;
}

/****************************************************************
 * Miscellaneous
****************************************************************/
void *window_get_proc_address(const char *name)
{
    return glfwGetProcAddress(name);
}

double window_get_time(void)
{
    return glfwGetTime();
}
