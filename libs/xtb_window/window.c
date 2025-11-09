#include "window.h"

#include <xtb_core/allocator.h>
#include <GLFW/glfw3.h>
#include <string.h>

/****************************************************************
 * Global State (Internal)
****************************************************************/
struct XTB_Window
{
    GLFWwindow *handle;

    XTB_Key_State g_keyboard_key_states[XTB_KEY_LAST + 1];
    XTB_Key_State g_mouse_button_states[GLFW_MOUSE_BUTTON_LAST + 1];
    f32 g_prev_cursor_position[2];
    f32 g_cursor_position[2];
    f32 g_scroll_offset[2];
    XTB_Cursor_Focus_State g_cursor_focus_state;
    bool g_cursor_visible;
    bool g_cursor_captured;
    bool g_vsync_enabled;
};

/****************************************************************
 * GLFW Callbacks (Internal)
****************************************************************/
static void glfw_key_callback(GLFWwindow *glfw_window, int key, int scancode, int action, int mods)
{
    if (key < 0) return;

    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    switch (action)
    {
        case GLFW_PRESS:
        {
            window->g_keyboard_key_states[key] = XTB_KEY_STATE_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            window->g_keyboard_key_states[key] = XTB_KEY_STATE_RELEASED;
        } break;
    }
}

static void glfw_cursor_pos_callback(GLFWwindow *glfw_window, double xpos, double ypos)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    window->g_prev_cursor_position[0] = window->g_cursor_position[0];
    window->g_prev_cursor_position[1] = window->g_cursor_position[1];

    window->g_cursor_position[0] = (f32)xpos;
    window->g_cursor_position[1] = (f32)ypos;
}

static void glfw_mouse_button_callback(GLFWwindow *glfw_window, int button, int action, int mods)
{
    if (button < 0) return;

    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    switch (action)
    {
        case GLFW_PRESS:
        {
            window->g_mouse_button_states[button] = XTB_KEY_STATE_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            window->g_mouse_button_states[button] = XTB_KEY_STATE_RELEASED;
        } break;
    }
}

static void glfw_cursor_enter_callback(GLFWwindow *glfw_window, int entered)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    window->g_cursor_focus_state = entered
        ? XTB_CURSOR_FOCUS_JUST_ENTERED
        : XTB_CURSOR_FOCUS_JUST_LEFT;
}

static void glfw_scroll_callback(GLFWwindow *glfw_window, double xoffset, double yoffset)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    window->g_scroll_offset[0] = (f32)xoffset;
    window->g_scroll_offset[1] = (f32)yoffset;
}

/****************************************************************
 * State Update (Internal)
****************************************************************/
static void update_keyboard_key_states(XTB_Window *window)
{
    for (int key = 0; key <= XTB_KEY_LAST; ++key)
    {
        if (window->g_keyboard_key_states[key] == XTB_KEY_STATE_PRESSED)
        {
            window->g_keyboard_key_states[key] = XTB_KEY_STATE_DOWN;
        }
        else if (window->g_keyboard_key_states[key] == XTB_KEY_STATE_RELEASED)
        {
            window->g_keyboard_key_states[key] = XTB_KEY_STATE_UP;
        }
    }
}

static void update_mouse_button_states(XTB_Window *window)
{
    for (int button = 0; button <= XTB_MOUSE_BUTTON_LAST; ++button)
    {
        if (window->g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED)
        {
            window->g_mouse_button_states[button] = XTB_KEY_STATE_DOWN;
        }
        else if (window->g_mouse_button_states[button] == XTB_KEY_STATE_RELEASED)
        {
            window->g_mouse_button_states[button] = XTB_KEY_STATE_UP;
        }
    }
}

static void update_cursor_focus_state(XTB_Window *window)
{
    if (window->g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_ENTERED)
    {
        window->g_cursor_focus_state = XTB_CURSOR_FOCUS_INSIDE;
    }
    else if (window->g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_LEFT)
    {
        window->g_cursor_focus_state = XTB_CURSOR_FOCUS_OUTSIDE;
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

    GLFWwindow *glfw_window = glfwCreateWindow(window_width, window_height, title, NULL, NULL);

    if (glfw_window == NULL)
    {
        return NULL;
    }

    glfwSetKeyCallback(glfw_window, glfw_key_callback);
    glfwSetCursorPosCallback(glfw_window, glfw_cursor_pos_callback);
    glfwSetMouseButtonCallback(glfw_window, glfw_mouse_button_callback);
    glfwSetCursorEnterCallback(glfw_window, glfw_cursor_enter_callback);
    glfwSetScrollCallback(glfw_window, glfw_scroll_callback);

    XTB_Window *window = XTB_AllocateZero(allocator_get_heap(), XTB_Window);
    glfwSetWindowUserPointer(glfw_window, window);

    window->handle = glfw_window;
    window->g_cursor_visible = true;
    window->g_cursor_captured = false;
    window->g_vsync_enabled = true;

    return window;
}

void window_destroy(XTB_Window *window)
{
    glfwDestroyWindow(window->handle);
}

bool window_should_close(XTB_Window *window)
{
    return glfwWindowShouldClose(window->handle);
}

void window_poll_events(XTB_Window *window)
{
    // NOTE(xearty): Clear the scroll offset before
    // we poll so it only persists for a single frame
    window->g_scroll_offset[0] = window->g_scroll_offset[1] = 0.0f;

    window->g_prev_cursor_position[0] = window->g_cursor_position[0];
    window->g_prev_cursor_position[1] = window->g_cursor_position[1];

    update_keyboard_key_states(window);
    update_mouse_button_states(window);
    update_cursor_focus_state(window);

    glfwPollEvents();
}

void window_make_context_current(XTB_Window *window)
{
    glfwMakeContextCurrent(window->handle);
}

void window_swap_buffers(XTB_Window *window)
{
    glfwSwapBuffers(window->handle);
}

void window_request_close(XTB_Window *window)
{
    glfwSetWindowShouldClose(window->handle, GLFW_TRUE);
}

void window_set_title(XTB_Window *window, const char *title)
{
    glfwSetWindowTitle(window->handle, title);
}

void window_set_vsync(XTB_Window *window, bool enabled)
{
    window_make_context_current(window);
    glfwSwapInterval(enabled ? 1 : 0);
    window->g_vsync_enabled = enabled;
}

bool window_vsync_enabled(XTB_Window *window)
{
    return window->g_vsync_enabled;
}

/****************************************************************
 * Keyboard Input
****************************************************************/
XTB_Key_State window_key_get_state(XTB_Window *window, u32 key)
{
    return window->g_keyboard_key_states[key];
}

bool window_key_is_up(XTB_Window *window, u32 key)
{
    return window->g_keyboard_key_states[key] == XTB_KEY_STATE_UP
        || window->g_keyboard_key_states[key] == XTB_KEY_STATE_RELEASED;
}

bool window_key_is_down(XTB_Window *window, u32 key)
{
    return window->g_keyboard_key_states[key] == XTB_KEY_STATE_DOWN
        || window->g_keyboard_key_states[key] == XTB_KEY_STATE_PRESSED;
}

bool window_key_is_released(XTB_Window *window, u32 key)
{
    return window->g_keyboard_key_states[key] == XTB_KEY_STATE_RELEASED;
}

bool window_key_is_pressed(XTB_Window *window, u32 key)
{
    return window->g_keyboard_key_states[key] == XTB_KEY_STATE_PRESSED;
}

/****************************************************************
 * Mouse Input
****************************************************************/
XTB_Key_State window_mouse_button_get_state(XTB_Window *window, u32 button)
{
    return window->g_mouse_button_states[button];
}

bool window_mouse_button_is_up(XTB_Window *window, u32 button)
{
    return window->g_mouse_button_states[button] == XTB_KEY_STATE_UP
        || window->g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED;
}

bool window_mouse_button_is_down(XTB_Window *window, u32 button)
{
    return window->g_mouse_button_states[button] == XTB_KEY_STATE_DOWN
        || window->g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED;
}

bool window_mouse_button_is_released(XTB_Window *window, u32 button)
{
    return window->g_mouse_button_states[button] == XTB_KEY_STATE_RELEASED;
}

bool window_mouse_button_is_pressed(XTB_Window *window, u32 button)
{
    return window->g_mouse_button_states[button] == XTB_KEY_STATE_PRESSED;
}

void window_cursor_get_position(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->g_cursor_position[0];
    *y = window->g_cursor_position[1];
}

void window_cursor_get_previous_position(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->g_prev_cursor_position[0];
    *y = window->g_prev_cursor_position[1];
}

void window_cursor_get_delta(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->g_cursor_position[0] - window->g_prev_cursor_position[0];
    *y = window->g_cursor_position[1] - window->g_prev_cursor_position[1];
}

XTB_Cursor_Focus_State window_cursor_get_focus(XTB_Window *window)
{
    return window->g_cursor_focus_state;
}

bool window_cursor_is_inside_window(XTB_Window *window)
{
    return window->g_cursor_focus_state == XTB_CURSOR_FOCUS_INSIDE
        || window->g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_ENTERED;
}

bool window_cursor_is_outside_window(XTB_Window *window)
{
    return window->g_cursor_focus_state == XTB_CURSOR_FOCUS_OUTSIDE
        || window->g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_LEFT;
}

bool window_cursor_just_entered_window(XTB_Window *window)
{
    return window->g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_ENTERED;
}

bool window_cursor_just_left_window(XTB_Window *window)
{
    return window->g_cursor_focus_state == XTB_CURSOR_FOCUS_JUST_LEFT;
}

void window_scroll_get_delta(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->g_scroll_offset[0];
    *y = window->g_scroll_offset[1];
}

f32 window_scroll_delta_x(XTB_Window *window)
{
    return window->g_scroll_offset[0];
}

f32 window_scroll_delta_y(XTB_Window *window)
{
    return window->g_scroll_offset[1];
}

bool window_scroll_this_frame(XTB_Window *window)
{
    return window->g_scroll_offset[0] != 0.0f && window->g_scroll_offset[1] != 0.0f;
}

void window_cursor_show(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    window->g_cursor_visible = true;
}

void window_cursor_hide(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
    window->g_cursor_visible = false;
}

bool window_cursor_is_visible(XTB_Window *window)
{
    return window->g_cursor_visible;
}

void window_cursor_capture(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    window->g_cursor_captured = true;
}

void window_cursor_release(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    window->g_cursor_captured = false;
}

bool window_cursor_is_captured(XTB_Window *window)
{
    return window->g_cursor_captured;
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
