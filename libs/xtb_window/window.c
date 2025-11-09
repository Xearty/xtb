#include "window.h"

#include <xtb_core/allocator.h>
#include <GLFW/glfw3.h>
#include <string.h>

typedef struct XTB_WindowCallbacks
{
    XTB_KeyCallback key_callback;
    XTB_MouseButtonCallback mouse_button_callback;
    XTB_CursorPositionCallback cursor_position_callback;
    XTB_ScrollCallback scroll_callback;
    XTB_CursorEnterCallback cursor_enter_callback;

    XTB_WindowSizeCallback window_size_callback;
    XTB_FramebufferSizeCallback framebuffer_size_callback;
} XTB_WindowCallbacks;

/****************************************************************
 * Per Window State
****************************************************************/
struct XTB_Window
{
    GLFWwindow *handle;
    Allocator *allocator;

    XTB_WindowCallbacks callbacks;
    void *user_pointer;

    XTB_KeyState keyboard_state[XTB_KEY_LAST + 1];
    XTB_KeyState mouse_buttons[XTB_MOUSE_BUTTON_LAST + 1];

    f32 cursor_prev_x;
    f32 cursor_prev_y;

    f32 cursor_x;
    f32 cursor_y;

    f32 scroll_delta_x;
    f32 scroll_delta_y;

    XTB_CursorFocus cursor_focus;

    struct { i32 x, y, width, height; } fullscreen_restore;

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
            window->keyboard_state[key] = XTB_KEY_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            window->keyboard_state[key] = XTB_KEY_RELEASED;
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
            window->mouse_buttons[button] = XTB_KEY_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            window->mouse_buttons[button] = XTB_KEY_RELEASED;
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
        ? XTB_CURSOR_ENTERED
        : XTB_CURSOR_LEFT;

    if (window->callbacks.cursor_enter_callback)
    {
        window->callbacks.cursor_enter_callback(window, entered);
    }
}

static void glfw_window_size_callback(GLFWwindow *glfw_window, int width, int height)
{
    // TODO(xearty): Maybe get the window size from this callback

    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    if (window->callbacks.window_size_callback)
    {
        window->callbacks.window_size_callback(window, width, height);
    }
}

static void glfw_framebuffer_size_callback(GLFWwindow *glfw_window, int width, int height)
{
    XTB_Window *window = glfwGetWindowUserPointer(glfw_window);

    if (window->callbacks.framebuffer_size_callback)
    {
        window->callbacks.framebuffer_size_callback(window, width, height);
    }
}

/****************************************************************
 * State Update (Internal)
****************************************************************/
static void update_keyboard_key_states(XTB_Window *window)
{
    for (int key = 0; key <= XTB_KEY_LAST; ++key)
    {
        if (window->keyboard_state[key] == XTB_KEY_PRESSED)
        {
            window->keyboard_state[key] = XTB_KEY_DOWN;
        }
        else if (window->keyboard_state[key] == XTB_KEY_RELEASED)
        {
            window->keyboard_state[key] = XTB_KEY_UP;
        }
    }
}

static void update_mouse_button_states(XTB_Window *window)
{
    for (int button = 0; button <= XTB_MOUSE_BUTTON_LAST; ++button)
    {
        if (window->mouse_buttons[button] == XTB_KEY_PRESSED)
        {
            window->mouse_buttons[button] = XTB_KEY_DOWN;
        }
        else if (window->mouse_buttons[button] == XTB_KEY_RELEASED)
        {
            window->mouse_buttons[button] = XTB_KEY_UP;
        }
    }
}

static void update_cursor_focus_state(XTB_Window *window)
{
    if (window->cursor_focus == XTB_CURSOR_ENTERED)
    {
        window->cursor_focus = XTB_CURSOR_INSIDE;
    }
    else if (window->cursor_focus == XTB_CURSOR_LEFT)
    {
        window->cursor_focus = XTB_CURSOR_OUTSIDE;
    }
}

/****************************************************************
 * Window System
****************************************************************/
void xtb_window_system_init(void)
{
    glfwInit();
}

void xtb_window_system_shutdown(void)
{
    glfwTerminate();
}

/****************************************************************
 * Window Configuration
****************************************************************/
XTB_WindowConfig xtb_window_config_default(void)
{
    XTB_WindowConfig cfg = {};
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
XTB_Window *xtb_window_create(Allocator *allocator, XTB_WindowConfig cfg)
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

    // Input Callbacks
    glfwSetKeyCallback(glfw_window, glfw_key_callback);
    glfwSetMouseButtonCallback(glfw_window, glfw_mouse_button_callback);
    glfwSetCursorPosCallback(glfw_window, glfw_cursor_pos_callback);
    glfwSetScrollCallback(glfw_window, glfw_scroll_callback);
    glfwSetCursorEnterCallback(glfw_window, glfw_cursor_enter_callback);

    // Window State Callbacks
    glfwSetWindowSizeCallback(glfw_window, glfw_window_size_callback);
    glfwSetFramebufferSizeCallback(glfw_window, glfw_framebuffer_size_callback);

    XTB_Window *window = XTB_AllocateZero(allocator, XTB_Window);
    glfwSetWindowUserPointer(glfw_window, window);

    window->handle = glfw_window;
    window->allocator = allocator;

    int cursor_mode = glfwGetInputMode(window->handle, GLFW_CURSOR);
    window->cursor_visible = (cursor_mode == GLFW_CURSOR_NORMAL);
    window->cursor_captured = (cursor_mode == GLFW_CURSOR_NORMAL);

    xtb_window_vsync_set(window, !!(cfg.flags & XTB_WINDOW_VSYNC));

    if (cfg.flags & XTB_WINDOW_FULLSCREEN)
    {
        xtb_window_fullscreen_set(window, true);
    }

    return window;
}

XTB_Window *xtb_window_create_default(Allocator *allocator)
{
    return xtb_window_create(allocator, xtb_window_config_default());
}

void xtb_window_destroy(XTB_Window *window)
{
    glfwDestroyWindow(window->handle);
    XTB_Deallocate(window->allocator, window);
}

bool xtb_window_should_close(XTB_Window *window)
{
    return glfwWindowShouldClose(window->handle);
}

void xtb_window_poll_events(XTB_Window *window)
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

void xtb_window_make_context_current(XTB_Window *window)
{
    glfwMakeContextCurrent(window->handle);
}

void xtb_window_swap_buffers(XTB_Window *window)
{
    glfwSwapBuffers(window->handle);
}

void xtb_window_request_close(XTB_Window *window)
{
    glfwSetWindowShouldClose(window->handle, GLFW_TRUE);
}

void xtb_window_title_set(XTB_Window *window, const char *title)
{
    glfwSetWindowTitle(window->handle, title);
}

/****************************************************************
 * Vsync
****************************************************************/
void xtb_window_vsync_set(XTB_Window *window, bool enabled)
{
    xtb_window_make_context_current(window);
    glfwSwapInterval(enabled ? 1 : 0);
    window->vsync_enabled = enabled;
}

bool xtb_window_vsync_enabled(XTB_Window *window)
{
    return window->vsync_enabled;
}

/****************************************************************
 * Fullscreen
****************************************************************/
void xtb_window_fullscreen_set(XTB_Window *window, bool fullscreen)
{
    window->is_fullscreen = fullscreen;

    if (fullscreen)
    {
        xtb_window_position_get(window, &window->fullscreen_restore.x, &window->fullscreen_restore.y);
        xtb_window_size_get(window, &window->fullscreen_restore.width, &window->fullscreen_restore.height);

        XTB_Monitor *monitor = xtb_monitor_primary_get();
        const GLFWvidmode *mode = glfwGetVideoMode((GLFWmonitor*)monitor);
        glfwSetWindowMonitor(window->handle, (GLFWmonitor*)monitor, 0, 0, mode->width, mode->height, mode->refreshRate);
    }
    else
    {
        glfwSetWindowMonitor(window->handle, NULL,
                window->fullscreen_restore.x, window->fullscreen_restore.y,
                window->fullscreen_restore.width, window->fullscreen_restore.height,
                0);
    }
}

void xtb_window_fullscreen_toggle(XTB_Window *window)
{
    xtb_window_fullscreen_set(window, !window->is_fullscreen);
}

bool xtb_window_is_fullscreen(XTB_Window *window)
{
    return window->is_fullscreen;
}

/****************************************************************
 * Window Geometry
****************************************************************/
void xtb_window_position_get(XTB_Window *window, i32 *x, i32 *y)
{
    glfwGetWindowPos(window->handle, x, y);
}

void xtb_window_size_get(XTB_Window *window, i32 *width, i32 *height)
{
    glfwGetWindowSize(window->handle, width, height);
}

/****************************************************************
 * Monitor
****************************************************************/
XTB_Monitor *xtb_monitor_primary_get(void)
{
    return (XTB_Monitor*)glfwGetPrimaryMonitor();
}

/****************************************************************
 * Window Callbacks
****************************************************************/
void xtb_window_set_key_callback(XTB_Window *window, XTB_KeyCallback callback)
{
    window->callbacks.key_callback = callback;
}

void xtb_window_set_mouse_button_callback(XTB_Window *window, XTB_MouseButtonCallback callback)
{
    window->callbacks.mouse_button_callback = callback;
}
void xtb_window_set_cursor_position_callback(XTB_Window *window, XTB_CursorPositionCallback callback)
{
    window->callbacks.cursor_position_callback = callback;
}
void xtb_window_set_scroll_callback(XTB_Window *window, XTB_ScrollCallback callback)
{
    window->callbacks.scroll_callback = callback;
}
void xtb_window_set_cursor_enter_callback(XTB_Window *window, XTB_CursorEnterCallback callback)
{
    window->callbacks.cursor_enter_callback = callback;
}

void xtb_window_set_window_size_callback(XTB_Window *window, XTB_WindowSizeCallback callback)
{
    window->callbacks.window_size_callback = callback;
}

void xtb_window_set_framebuffer_size_callback(XTB_Window *window, XTB_FramebufferSizeCallback callback)
{
    window->callbacks.framebuffer_size_callback = callback;
}

void xtb_window_user_pointer_set(XTB_Window *window, void *user_pointer)
{
    window->user_pointer = user_pointer;
}

void *xtb_window_user_pointer_get(XTB_Window *window)
{
    return window->user_pointer;
}

/****************************************************************
 * Keyboard Input
****************************************************************/
XTB_KeyState xtb_key_state_get(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key];
}

bool xtb_key_is_up(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key] == XTB_KEY_UP
        || window->keyboard_state[key] == XTB_KEY_RELEASED;
}

bool xtb_key_is_down(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key] == XTB_KEY_DOWN
        || window->keyboard_state[key] == XTB_KEY_PRESSED;
}

bool xtb_key_is_released(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key] == XTB_KEY_RELEASED;
}

bool xtb_key_is_pressed(XTB_Window *window, u32 key)
{
    return window->keyboard_state[key] == XTB_KEY_PRESSED;
}

/****************************************************************
 * Mouse Input
****************************************************************/
XTB_KeyState xtb_mouse_button_state_get(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button];
}

bool xtb_mouse_button_is_up(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button] == XTB_KEY_UP
        || window->mouse_buttons[button] == XTB_KEY_PRESSED;
}

bool xtb_mouse_button_is_down(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button] == XTB_KEY_DOWN
        || window->mouse_buttons[button] == XTB_KEY_PRESSED;
}

bool xtb_mouse_button_is_released(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button] == XTB_KEY_RELEASED;
}

bool xtb_mouse_button_is_pressed(XTB_Window *window, u32 button)
{
    return window->mouse_buttons[button] == XTB_KEY_PRESSED;
}

void xtb_cursor_pos_get(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->cursor_x;
    *y = window->cursor_y;
}

void xtb_cursor_pos_prev_get(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->cursor_prev_x;
    *y = window->cursor_prev_y;
}

void xtb_cursor_delta_get(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->cursor_x - window->cursor_prev_x;
    *y = window->cursor_y - window->cursor_prev_y;
}

XTB_CursorFocus xtb_cursor_focus_get(XTB_Window *window)
{
    return window->cursor_focus;
}

bool xtb_cursor_is_inside(XTB_Window *window)
{
    return window->cursor_focus == XTB_CURSOR_INSIDE
        || window->cursor_focus == XTB_CURSOR_ENTERED;
}

bool xtb_cursor_is_outside(XTB_Window *window)
{
    return window->cursor_focus == XTB_CURSOR_OUTSIDE
        || window->cursor_focus == XTB_CURSOR_LEFT;
}

bool xtb_cursor_entered(XTB_Window *window)
{
    return window->cursor_focus == XTB_CURSOR_ENTERED;
}

bool xtb_cursor_left(XTB_Window *window)
{
    return window->cursor_focus == XTB_CURSOR_LEFT;
}

void xtb_scroll_delta_get(XTB_Window *window, f32 *x, f32 *y)
{
    *x = window->scroll_delta_x;
    *y = window->scroll_delta_y;
}

f32 xtb_scroll_delta_x(XTB_Window *window)
{
    return window->scroll_delta_x;
}

f32 xtb_scroll_delta_y(XTB_Window *window)
{
    return window->scroll_delta_y;
}

bool xtb_scroll_happened(XTB_Window *window)
{
    return window->scroll_delta_x != 0.0f && window->scroll_delta_y != 0.0f;
}

void xtb_cursor_show(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    window->cursor_visible = true;
}

void xtb_cursor_hide(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
    window->cursor_visible = false;
}

bool xtb_cursor_is_visible(XTB_Window *window)
{
    return window->cursor_visible;
}

void xtb_cursor_capture(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    window->cursor_captured = true;
}

void xtb_cursor_release(XTB_Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    window->cursor_captured = false;
}

bool xtb_cursor_is_captured(XTB_Window *window)
{
    return window->cursor_captured;
}

/****************************************************************
 * Miscellaneous
****************************************************************/
void *xtb_proc_address_get(const char *name)
{
    return glfwGetProcAddress(name);
}

double xtb_time_get(void)
{
    return glfwGetTime();
}
