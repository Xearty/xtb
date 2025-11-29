#include "window.h"

#include <xtb_core/allocator.h>
#include <GLFW/glfw3.h>
#include <string.h>
#include <stdio.h>

namespace xtb
{

typedef struct WindowCallbacks
{
    KeyCallback key_callback;
    MouseButtonCallback mouse_button_callback;
    CursorPositionCallback cursor_position_callback;
    ScrollCallback scroll_callback;
    CursorEnterCallback cursor_enter_callback;

    WindowSizeCallback window_size_callback;
    FramebufferSizeCallback framebuffer_size_callback;
} WindowCallbacks;

/****************************************************************
 * Per Window State
****************************************************************/
struct Window
{
    GLFWwindow *handle;
    Allocator *allocator;

    WindowCallbacks callbacks;
    void *user_pointer;

    KeyState keyboard_state[KEY_LAST + 1];
    KeyState mouse_buttons[MOUSE_BUTTON_LAST + 1];

    f32 cursor_prev_x;
    f32 cursor_prev_y;

    f32 cursor_x;
    f32 cursor_y;

    f32 scroll_delta_x;
    f32 scroll_delta_y;

    CursorFocus cursor_focus;

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

    Window *window = (Window*)glfwGetWindowUserPointer(glfw_window);

    switch (action)
    {
        case GLFW_PRESS:
        {
            window->keyboard_state[key] = KEY_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            window->keyboard_state[key] = KEY_RELEASED;
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

    Window *window = (Window*)glfwGetWindowUserPointer(glfw_window);

    switch (action)
    {
        case GLFW_PRESS:
        {
            window->mouse_buttons[button] = KEY_PRESSED;
        } break;

        case GLFW_RELEASE:
        {
            window->mouse_buttons[button] = KEY_RELEASED;
        } break;
    }

    if (window->callbacks.mouse_button_callback)
    {
        window->callbacks.mouse_button_callback(window, button, action,  mods);
    }
}

static void glfw_cursor_pos_callback(GLFWwindow *glfw_window, double xpos, double ypos)
{
    Window *window = (Window*)glfwGetWindowUserPointer(glfw_window);

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
    Window *window = (Window*)glfwGetWindowUserPointer(glfw_window);

    window->scroll_delta_x = (f32)xoffset;
    window->scroll_delta_y = (f32)yoffset;

    if (window->callbacks.scroll_callback)
    {
        window->callbacks.scroll_callback(window, xoffset, yoffset);
    }
}

static void glfw_cursor_enter_callback(GLFWwindow *glfw_window, int entered)
{
    Window *window = (Window*)glfwGetWindowUserPointer(glfw_window);

    window->cursor_focus = entered
        ? CURSOR_ENTERED
        : CURSOR_LEFT;

    if (window->callbacks.cursor_enter_callback)
    {
        window->callbacks.cursor_enter_callback(window, entered);
    }
}

static void glfw_window_size_callback(GLFWwindow *glfw_window, int width, int height)
{
    // TODO(xearty): Maybe get the window size from this callback

    Window *window = (Window*)glfwGetWindowUserPointer(glfw_window);

    if (window->callbacks.window_size_callback)
    {
        window->callbacks.window_size_callback(window, width, height);
    }
}

static void glfw_framebuffer_size_callback(GLFWwindow *glfw_window, int width, int height)
{
    Window *window = (Window*)glfwGetWindowUserPointer(glfw_window);

    if (window->callbacks.framebuffer_size_callback)
    {
        window->callbacks.framebuffer_size_callback(window, width, height);
    }
}

/****************************************************************
 * State Update (Internal)
****************************************************************/
static void update_keyboard_key_states(Window *window)
{
    for (int key = 0; key <= KEY_LAST; ++key)
    {
        if (window->keyboard_state[key] == KEY_PRESSED)
        {
            window->keyboard_state[key] = (KeyState)KEY_DOWN;
        }
        else if (window->keyboard_state[key] == KEY_RELEASED)
        {
            window->keyboard_state[key] = (KeyState)KEY_UP;
        }
    }
}

static void update_mouse_button_states(Window *window)
{
    for (int button = 0; button <= MOUSE_BUTTON_LAST; ++button)
    {
        if (window->mouse_buttons[button] == KEY_PRESSED)
        {
            window->mouse_buttons[button] = (KeyState)KEY_DOWN;
        }
        else if (window->mouse_buttons[button] == KEY_RELEASED)
        {
            window->mouse_buttons[button] = (KeyState)KEY_UP;
        }
    }
}

static void update_cursor_focus_state(Window *window)
{
    if (window->cursor_focus == CURSOR_ENTERED)
    {
        window->cursor_focus = CURSOR_INSIDE;
    }
    else if (window->cursor_focus == CURSOR_LEFT)
    {
        window->cursor_focus = CURSOR_OUTSIDE;
    }
}

/****************************************************************
 * Window System
****************************************************************/
void window_system_init(void)
{
    glfwInit();
}

void window_system_shutdown(void)
{
    glfwTerminate();
}

/****************************************************************
 * Window Configuration
****************************************************************/
WindowConfig window_config_default(void)
{
    WindowConfig cfg = {};
    cfg.width = 800;
    cfg.height = 800;
    cfg.title = "XTB Window";

    cfg.backend = WINDOW_BACKEND_OPENGL;
    cfg.flags = WINDOW_VSYNC;
    cfg.samples = 1;

    cfg.opengl.version_major = 4;
    cfg.opengl.version_minor = 5;

    return cfg;
}

/****************************************************************
 * Window
****************************************************************/
Window *window_create(Allocator *allocator, WindowConfig cfg)
{
    if (cfg.backend == WINDOW_BACKEND_OPENGL)
    {
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, cfg.opengl.version_major);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, cfg.opengl.version_minor);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, true);
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

    Window *window = AllocateZero(allocator, Window);
    glfwSetWindowUserPointer(glfw_window, window);

    window->handle = glfw_window;
    window->allocator = allocator;

    int cursor_mode = glfwGetInputMode(window->handle, GLFW_CURSOR);
    window->cursor_visible = (cursor_mode == GLFW_CURSOR_NORMAL);
    window->cursor_captured = (cursor_mode == GLFW_CURSOR_NORMAL);

    window_vsync_set(window, !!(cfg.flags & WINDOW_VSYNC));

    if (cfg.flags & WINDOW_FULLSCREEN)
    {
        window_fullscreen_set(window, true);
    }

    return window;
}

Window *window_create_default(Allocator *allocator)
{
    return window_create(allocator, window_config_default());
}

void window_destroy(Window *window)
{
    glfwDestroyWindow(window->handle);
    Deallocate(window->allocator, window);
}

bool window_should_close(Window *window)
{
    return glfwWindowShouldClose(window->handle);
}

void window_poll_events(Window *window)
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

void window_make_context_current(Window *window)
{
    glfwMakeContextCurrent(window->handle);
}

void window_swap_buffers(Window *window)
{
    glfwSwapBuffers(window->handle);
}

void window_request_close(Window *window)
{
    glfwSetWindowShouldClose(window->handle, GLFW_TRUE);
}

void window_title_set(Window *window, const char *title)
{
    glfwSetWindowTitle(window->handle, title);
}

void window_title_show_fps(Window *window, const char *title, f32 dt, f32 secs_per_update)
{
    static f32 elapsed = 0;
    static i32 frames_count = 0;

    elapsed += dt;
    frames_count += 1;

    if (elapsed >= secs_per_update)
    {
        int fps = frames_count / elapsed;

        frames_count = 0;
        elapsed = 0;

        char format_buf[128];
        snprintf(format_buf, sizeof(format_buf), "%s | %d fps", title, fps);
        window_title_set(window, format_buf);
    }
}

/****************************************************************
 * Vsync
****************************************************************/
void window_vsync_set(Window *window, bool enabled)
{
    window_make_context_current(window);
    glfwSwapInterval(enabled ? 1 : 0);
    window->vsync_enabled = enabled;
}

bool window_vsync_enabled(Window *window)
{
    return window->vsync_enabled;
}

/****************************************************************
 * Fullscreen
****************************************************************/
void window_fullscreen_set(Window *window, bool fullscreen)
{
    window->is_fullscreen = fullscreen;

    if (fullscreen)
    {
        window_position_get(window, &window->fullscreen_restore.x, &window->fullscreen_restore.y);
        window_size_get(window, &window->fullscreen_restore.width, &window->fullscreen_restore.height);

        Monitor *monitor = monitor_primary_get();
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

void window_fullscreen_toggle(Window *window)
{
    window_fullscreen_set(window, !window->is_fullscreen);
}

bool window_is_fullscreen(Window *window)
{
    return window->is_fullscreen;
}

/****************************************************************
 * Window Geometry
****************************************************************/
void window_position_get(Window *window, i32 *x, i32 *y)
{
    glfwGetWindowPos(window->handle, x, y);
}

void window_size_get(Window *window, i32 *width, i32 *height)
{
    glfwGetWindowSize(window->handle, width, height);
}

/****************************************************************
 * Monitor
****************************************************************/
Monitor *monitor_primary_get(void)
{
    return (Monitor*)glfwGetPrimaryMonitor();
}

/****************************************************************
 * Window Callbacks
****************************************************************/
void window_set_key_callback(Window *window, KeyCallback callback)
{
    window->callbacks.key_callback = callback;
}

void window_set_mouse_button_callback(Window *window, MouseButtonCallback callback)
{
    window->callbacks.mouse_button_callback = callback;
}
void window_set_cursor_position_callback(Window *window, CursorPositionCallback callback)
{
    window->callbacks.cursor_position_callback = callback;
}
void window_set_scroll_callback(Window *window, ScrollCallback callback)
{
    window->callbacks.scroll_callback = callback;
}
void window_set_cursor_enter_callback(Window *window, CursorEnterCallback callback)
{
    window->callbacks.cursor_enter_callback = callback;
}

void window_set_window_size_callback(Window *window, WindowSizeCallback callback)
{
    window->callbacks.window_size_callback = callback;
}

void window_set_framebuffer_size_callback(Window *window, FramebufferSizeCallback callback)
{
    window->callbacks.framebuffer_size_callback = callback;
}

void window_user_pointer_set(Window *window, void *user_pointer)
{
    window->user_pointer = user_pointer;
}

void *window_user_pointer_get(Window *window)
{
    return window->user_pointer;
}

/****************************************************************
 * Keyboard Input
****************************************************************/
KeyState key_state_get(Window *window, u32 key)
{
    return window->keyboard_state[key];
}

bool key_is_up(Window *window, u32 key)
{
    return window->keyboard_state[key] == KEY_UP
        || window->keyboard_state[key] == KEY_RELEASED;
}

bool key_is_down(Window *window, u32 key)
{
    return window->keyboard_state[key] == KEY_DOWN
        || window->keyboard_state[key] == KEY_PRESSED;
}

bool key_is_released(Window *window, u32 key)
{
    return window->keyboard_state[key] == KEY_RELEASED;
}

bool key_is_pressed(Window *window, u32 key)
{
    return window->keyboard_state[key] == KEY_PRESSED;
}

/****************************************************************
 * Mouse Input
****************************************************************/
KeyState mouse_button_state_get(Window *window, u32 button)
{
    return window->mouse_buttons[button];
}

bool mouse_button_is_up(Window *window, u32 button)
{
    return window->mouse_buttons[button] == KEY_UP
        || window->mouse_buttons[button] == KEY_PRESSED;
}

bool mouse_button_is_down(Window *window, u32 button)
{
    return window->mouse_buttons[button] == KEY_DOWN
        || window->mouse_buttons[button] == KEY_PRESSED;
}

bool mouse_button_is_released(Window *window, u32 button)
{
    return window->mouse_buttons[button] == KEY_RELEASED;
}

bool mouse_button_is_pressed(Window *window, u32 button)
{
    return window->mouse_buttons[button] == KEY_PRESSED;
}

void cursor_pos_get(Window *window, f32 *x, f32 *y)
{
    *x = window->cursor_x;
    *y = window->cursor_y;
}

void cursor_pos_prev_get(Window *window, f32 *x, f32 *y)
{
    *x = window->cursor_prev_x;
    *y = window->cursor_prev_y;
}

void cursor_delta_get(Window *window, f32 *x, f32 *y)
{
    *x = window->cursor_x - window->cursor_prev_x;
    *y = window->cursor_y - window->cursor_prev_y;
}

CursorFocus cursor_focus_get(Window *window)
{
    return window->cursor_focus;
}

bool cursor_is_inside(Window *window)
{
    return window->cursor_focus == CURSOR_INSIDE
        || window->cursor_focus == CURSOR_ENTERED;
}

bool cursor_is_outside(Window *window)
{
    return window->cursor_focus == CURSOR_OUTSIDE
        || window->cursor_focus == CURSOR_LEFT;
}

bool cursor_entered(Window *window)
{
    return window->cursor_focus == CURSOR_ENTERED;
}

bool cursor_left(Window *window)
{
    return window->cursor_focus == CURSOR_LEFT;
}

void scroll_delta_get(Window *window, f32 *x, f32 *y)
{
    *x = window->scroll_delta_x;
    *y = window->scroll_delta_y;
}

f32 scroll_delta_x(Window *window)
{
    return window->scroll_delta_x;
}

f32 scroll_delta_y(Window *window)
{
    return window->scroll_delta_y;
}

bool scroll_happened(Window *window)
{
    return window->scroll_delta_x != 0.0f && window->scroll_delta_y != 0.0f;
}

void cursor_show(Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    window->cursor_visible = true;
}

void cursor_hide(Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
    window->cursor_visible = false;
}

bool cursor_is_visible(Window *window)
{
    return window->cursor_visible;
}

void cursor_capture(Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    window->cursor_captured = true;
}

void cursor_release(Window *window)
{
    glfwSetInputMode(window->handle, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    window->cursor_captured = false;
}

bool cursor_is_captured(Window *window)
{
    return window->cursor_captured;
}

/****************************************************************
 * Miscellaneous
****************************************************************/
void *proc_address_get(const char *name)
{
    return (void*)glfwGetProcAddress(name);
}

double time_get(void)
{
    return glfwGetTime();
}

}
