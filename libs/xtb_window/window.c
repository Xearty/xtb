#include "window.h"

#include <xtb_core/allocator.h>
#include <GLFW/glfw3.h>
#include <string.h>

/****************************************************************
 * Per Window State
****************************************************************/
struct XTB_Window
{
    GLFWwindow *handle;

    XTB_Key_State keyboard_state[XTB_KEY_LAST + 1];
    XTB_Key_State mouse_buttons[GLFW_MOUSE_BUTTON_LAST + 1];

    f32 cursor_prev_x;
    f32 cursor_prev_y;

    f32 cursor_x;
    f32 cursor_y;

    f32 scroll_delta_x;
    f32 scroll_delta_y;

    XTB_Cursor_Focus_State cursor_focus;

    bool cursor_visible;
    bool cursor_captured;
    bool vsync_enabled;
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
            window->keyboard_state[key] = XTB_KEY_STATE_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            window->keyboard_state[key] = XTB_KEY_STATE_RELEASED;
        } break;
    }
}

static void glfw_cursor_pos_callback(GLFWwindow *glfw_window, double xpos, double ypos)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    window->cursor_prev_x = window->cursor_x;
    window->cursor_prev_y = window->cursor_y;

    window->cursor_x = (f32)xpos;
    window->cursor_y = (f32)ypos;
}

static void glfw_mouse_button_callback(GLFWwindow *glfw_window, int button, int action, int mods)
{
    if (button < 0) return;

    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    switch (action)
    {
        case GLFW_PRESS:
        {
            window->mouse_buttons[button] = XTB_KEY_STATE_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            window->mouse_buttons[button] = XTB_KEY_STATE_RELEASED;
        } break;
    }
}

static void glfw_cursor_enter_callback(GLFWwindow *glfw_window, int entered)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    window->cursor_focus = entered
        ? XTB_CURSOR_FOCUS_JUST_ENTERED
        : XTB_CURSOR_FOCUS_JUST_LEFT;
}

static void glfw_scroll_callback(GLFWwindow *glfw_window, double xoffset, double yoffset)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    window->scroll_delta_x = (f32)xoffset;
    window->scroll_delta_y = (f32)yoffset;
}

/****************************************************************
 * State Update (Internal)
****************************************************************/
static void update_keyboard_key_states(XTB_Window *window)
{
    for (int key = 0; key <= XTB_KEY_LAST; ++key)
    {
        if (window->keyboard_state[key] == XTB_KEY_STATE_PRESSED)
        {
            window->keyboard_state[key] = XTB_KEY_STATE_DOWN;
        }
        else if (window->keyboard_state[key] == XTB_KEY_STATE_RELEASED)
        {
            window->keyboard_state[key] = XTB_KEY_STATE_UP;
        }
    }
}

static void update_mouse_button_states(XTB_Window *window)
{
    for (int button = 0; button <= XTB_MOUSE_BUTTON_LAST; ++button)
    {
        if (window->mouse_buttons[button] == XTB_KEY_STATE_PRESSED)
        {
            window->mouse_buttons[button] = XTB_KEY_STATE_DOWN;
        }
        else if (window->mouse_buttons[button] == XTB_KEY_STATE_RELEASED)
        {
            window->mouse_buttons[button] = XTB_KEY_STATE_UP;
        }
    }
}

static void update_cursor_focus_state(XTB_Window *window)
{
    if (window->cursor_focus == XTB_CURSOR_FOCUS_JUST_ENTERED)
    {
        window->cursor_focus = XTB_CURSOR_FOCUS_INSIDE;
    }
    else if (window->cursor_focus == XTB_CURSOR_FOCUS_JUST_LEFT)
    {
        window->cursor_focus = XTB_CURSOR_FOCUS_OUTSIDE;
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

    if (config.flags & XTB_WINDOW_OPENGL_CONTEXT)
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

    int cursor_mode = glfwGetInputMode(window->handle, GLFW_CURSOR);
    window->cursor_visible = (cursor_mode == GLFW_CURSOR_NORMAL);
    window->cursor_captured = (cursor_mode == GLFW_CURSOR_NORMAL);

    window_set_vsync(window, !!(config.flags & XTB_WINDOW_VSYNC));

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
    window->scroll_delta_x = window->scroll_delta_y = 0.0f;

    window->cursor_prev_x = window->cursor_x;
    window->cursor_prev_y = window->cursor_y;

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
    window->vsync_enabled = enabled;
}

bool window_vsync_enabled(XTB_Window *window)
{
    return window->vsync_enabled;
}

/****************************************************************
 * Keyboard Input
****************************************************************/
XTB_Key_State window_key_get_state(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key];
}

bool window_key_is_up(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key] == XTB_KEY_STATE_UP
        || window->keyboard_state[key] == XTB_KEY_STATE_RELEASED;
}

bool window_key_is_down(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key] == XTB_KEY_STATE_DOWN
        || window->keyboard_state[key] == XTB_KEY_STATE_PRESSED;
}

bool window_key_is_released(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key] == XTB_KEY_STATE_RELEASED;
}

bool window_key_is_pressed(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key] == XTB_KEY_STATE_PRESSED;
}

/****************************************************************
 * Mouse Input
****************************************************************/
XTB_Key_State window_mouse_button_get_state(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button];
}

bool window_mouse_button_is_up(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button] == XTB_KEY_STATE_UP
        || window->mouse_buttons[button] == XTB_KEY_STATE_PRESSED;
}

bool window_mouse_button_is_down(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button] == XTB_KEY_STATE_DOWN
        || window->mouse_buttons[button] == XTB_KEY_STATE_PRESSED;
}

bool window_mouse_button_is_released(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button] == XTB_KEY_STATE_RELEASED;
}

bool window_mouse_button_is_pressed(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button] == XTB_KEY_STATE_PRESSED;
}

void window_cursor_get_position(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->cursor_x;
    *y = window->cursor_y;
}

void window_cursor_get_previous_position(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->cursor_prev_x;
    *y = window->cursor_prev_y;
}

void window_cursor_get_delta(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->cursor_x - window->cursor_prev_x;
    *y = window->cursor_y - window->cursor_prev_y;
}

XTB_Cursor_Focus_State window_cursor_get_focus(XTB_Window *window)
{
    return window->cursor_focus;
}

bool window_cursor_is_inside_window(XTB_Window *window)
{
    return window->cursor_focus == XTB_CURSOR_FOCUS_INSIDE
        || window->cursor_focus == XTB_CURSOR_FOCUS_JUST_ENTERED;
}

bool window_cursor_is_outside_window(XTB_Window *window)
{
    return window->cursor_focus == XTB_CURSOR_FOCUS_OUTSIDE
        || window->cursor_focus == XTB_CURSOR_FOCUS_JUST_LEFT;
}

bool window_cursor_just_entered_window(XTB_Window *window)
{
    return window->cursor_focus == XTB_CURSOR_FOCUS_JUST_ENTERED;
}

bool window_cursor_just_left_window(XTB_Window *window)
{
    return window->cursor_focus == XTB_CURSOR_FOCUS_JUST_LEFT;
}

void window_scroll_get_delta(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->scroll_delta_x;
    *y = window->scroll_delta_y;
}

f32 window_scroll_delta_x(XTB_Window *window)
{
    return window->scroll_delta_x;
}

f32 window_scroll_delta_y(XTB_Window *window)
{
    return window->scroll_delta_y;
}

bool window_scroll_this_frame(XTB_Window *window)
{
    return window->scroll_delta_x != 0.0f && window->scroll_delta_y != 0.0f;
}

void window_cursor_show(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    window->cursor_visible = true;
}

void window_cursor_hide(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
    window->cursor_visible = false;
}

bool window_cursor_is_visible(XTB_Window *window)
{
    return window->cursor_visible;
}

void window_cursor_capture(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    window->cursor_captured = true;
}

void window_cursor_release(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    window->cursor_captured = false;
}

bool window_cursor_is_captured(XTB_Window *window)
{
    return window->cursor_captured;
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
