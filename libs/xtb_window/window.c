#include "window.h"

#include <xtb_core/allocator.h>
#include <xtb_core/contract.h>
#include <GLFW/glfw3.h>
#include <string.h>

typedef struct XTB_Window_Callbacks
{
    XTB_Window_Key_Callback key_callback;
    XTB_Window_Mouse_Button_Callback mouse_button_callback;
    XTB_Window_Cursor_Position_Callback cursor_position_callback;
    XTB_Window_Scroll_Callback scroll_callback;
    XTB_Window_Cursor_Enter_Callback cursor_enter_callback;
} XTB_Window_Callbacks;

/****************************************************************
 * Per Window State
****************************************************************/
struct XTB_Window
{
    GLFWwindow *handle;
    Allocator *allocator;

    XTB_Window_Callbacks callbacks;
    void *user_pointer;

    XTB_Monitor *monitor;
    i32 fullscreen_stored_x;
    i32 fullscreen_stored_y;
    i32 fullscreen_stored_width;
    i32 fullscreen_stored_height;

    XTB_Key_State keyboard_state[XTB_KEY_LAST + 1];
    XTB_Key_State mouse_buttons[XTB_MOUSE_BUTTON_LAST + 1];

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
    bool is_fullscreen;
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

    if (window->callbacks.key_callback)
    {
        window->callbacks.key_callback(window, key, scancode, action, mods);
    }
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

    if (window->callbacks.mouse_button_callback)
    {
        window->callbacks.mouse_button_callback(window, button, action,  mods);
    }
}

static void glfw_cursor_pos_callback(GLFWwindow *glfw_window, double xpos, double ypos)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    window->cursor_prev_x = window->cursor_x;
    window->cursor_prev_y = window->cursor_y;

    window->cursor_x = (f32)xpos;
    window->cursor_y = (f32)ypos;

    if (window->callbacks.cursor_position_callback)
    {
        window->callbacks.cursor_position_callback(window, xpos, ypos);
    }
}

static void glfw_scroll_callback(GLFWwindow *glfw_window, double xoffset, double yoffset)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    window->scroll_delta_x = (f32)xoffset;
    window->scroll_delta_y = (f32)yoffset;

    if (window->callbacks.scroll_callback)
    {
        window->callbacks.scroll_callback(window, xoffset, yoffset);
    }
}

static void glfw_cursor_enter_callback(GLFWwindow *glfw_window, int entered)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    window->cursor_focus = entered
        ? XTB_CURSOR_FOCUS_JUST_ENTERED
        : XTB_CURSOR_FOCUS_JUST_LEFT;

    if (window->callbacks.cursor_enter_callback)
    {
        window->callbacks.cursor_enter_callback(window, entered);
    }
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
 * Window Creation Config
****************************************************************/
XTB_Window_Config window_config_default(void)
{
    XTB_Window_Config cfg = {};
    cfg.width = 800;
    cfg.height = 800;
    cfg.title = "XTB Window";

    cfg.backend = XTB_WINDOW_BACKEND_OPENGL;
    cfg.flags = XTB_WINDOW_VSYNC;
    cfg.samples = 1;

    cfg.opengl.version_major = 3;
    cfg.opengl.version_minor = 3;

    return cfg;
}

/****************************************************************
 * Window
****************************************************************/
XTB_Window *window_create(Allocator *allocator, XTB_Window_Config cfg)
{
    if (cfg.backend == XTB_WINDOW_BACKEND_OPENGL)
    {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, cfg.opengl.version_major);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, cfg.opengl.version_minor);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    }

    glfwWindowHint(GLFW_SAMPLES, cfg.samples);

    GLFWwindow *glfw_window = glfwCreateWindow(cfg.width, cfg.height, cfg.title, NULL, NULL);

    if (glfw_window == NULL)
    {
        return NULL;
    }

    glfwSetKeyCallback(glfw_window, glfw_key_callback);
    glfwSetMouseButtonCallback(glfw_window, glfw_mouse_button_callback);
    glfwSetCursorPosCallback(glfw_window, glfw_cursor_pos_callback);
    glfwSetScrollCallback(glfw_window, glfw_scroll_callback);
    glfwSetCursorEnterCallback(glfw_window, glfw_cursor_enter_callback);

    XTB_Window *window = XTB_AllocateZero(allocator, XTB_Window);
    glfwSetWindowUserPointer(glfw_window, window);

    window->handle = glfw_window;
    window->allocator = allocator;

    int cursor_mode = glfwGetInputMode(window->handle, GLFW_CURSOR);
    window->cursor_visible = (cursor_mode == GLFW_CURSOR_NORMAL);
    window->cursor_captured = (cursor_mode == GLFW_CURSOR_NORMAL);

    window_set_vsync(window, !!(cfg.flags & XTB_WINDOW_VSYNC));

    window->monitor = cfg.fullscreen.monitor;

    if (cfg.flags & XTB_WINDOW_FULLSCREEN)
    {
        window_go_fullscreen(window);
    }

    return window;
}

XTB_Window *window_create_default(Allocator *allocator)
{
    return window_create(allocator, window_config_default());
}

void window_destroy(XTB_Window *window)
{
    glfwDestroyWindow(window->handle);
    XTB_Deallocate(window->allocator, window);
}

bool window_should_close(XTB_Window *window)
{
    return glfwWindowShouldClose(window->handle);
}

void window_poll_events(XTB_Window *window)
{
    // NOTE(xearty): Clear the scroll offset before
    // we poll so it only persists for a single frame
    window->scroll_delta_x = 0.0f;
    window->scroll_delta_y = 0.0f;

    // NOTE(xearty): Clear the mouse position delta
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

void window_go_fullscreen(XTB_Window *window)
{
    XTB_ASSERT(window->monitor != NULL);

    window->is_fullscreen = true;

    window_get_position(window, &window->fullscreen_stored_y, &window->fullscreen_stored_y);
    window_get_size(window, &window->fullscreen_stored_width, &window->fullscreen_stored_height);

    const GLFWvidmode *mode = glfwGetVideoMode((GLFWmonitor*)window->monitor);
    glfwSetWindowMonitor(window->handle, (GLFWmonitor*)window->monitor, 0, 0, mode->width, mode->height, mode->refreshRate);
}

void window_go_windowed(XTB_Window *window)
{
    window->is_fullscreen = false;

    glfwSetWindowMonitor(window->handle,
                         NULL,
                         window->fullscreen_stored_x,
                         window->fullscreen_stored_y,
                         window->fullscreen_stored_width,
                         window->fullscreen_stored_height,
                         0);
}

void window_toggle_fullscreen(XTB_Window *window)
{
    if (window->is_fullscreen)
    {
        window_go_windowed(window);
    }
    else
    {
        window_go_fullscreen(window);
    }
}

bool window_is_fullscreen(XTB_Window *window)
{
    return window->is_fullscreen;
}

void window_get_position(XTB_Window *window, i32 *x, i32 *y)
{
    glfwGetWindowPos(window->handle, x, y);
}

void window_get_size(XTB_Window *window, i32 *width, i32 *height)
{
    glfwGetWindowSize(window->handle, width, height);
}

/****************************************************************
 * Monitor
****************************************************************/
XTB_Monitor *window_get_primary_monitor(void)
{
    return (XTB_Monitor*)glfwGetPrimaryMonitor();
}

/****************************************************************
 * Window Callbacks
****************************************************************/
void window_set_key_callback(XTB_Window *window, XTB_Window_Key_Callback callback)
{
    window->callbacks.key_callback = callback;
}

void window_set_mouse_button_callback(XTB_Window *window, XTB_Window_Mouse_Button_Callback callback)
{
    window->callbacks.mouse_button_callback = callback;
}
void window_set_cursor_position_callback(XTB_Window *window, XTB_Window_Cursor_Position_Callback callback)
{
    window->callbacks.cursor_position_callback = callback;
}
void window_set_scroll_callback(XTB_Window *window, XTB_Window_Scroll_Callback callback)
{
    window->callbacks.scroll_callback = callback;
}
void window_set_cursor_enter_callback(XTB_Window *window, XTB_Window_Cursor_Enter_Callback callback)
{
    window->callbacks.cursor_enter_callback = callback;
}

void window_set_user_pointer(XTB_Window *window, void *user_pointer)
{
    window->user_pointer = user_pointer;
}

void *window_get_user_pointer(XTB_Window *window)
{
    return window->user_pointer;
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
