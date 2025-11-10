#ifndef _XTB_WINDOW_H_
#define _XTB_WINDOW_H_

#include <xtb_core/core.h>
#include <xtb_core/allocator.h>

C_LINKAGE_BEGIN

/****************************************************************
 * Window System
****************************************************************/
void window_system_init(void);
void window_system_shutdown(void);

/****************************************************************
 * Window Configuration
****************************************************************/
typedef enum WindowFlags
{
    WINDOW_VSYNC      = 0b0001,
    WINDOW_FULLSCREEN = 0b0010,
} WindowFlags;

typedef enum WindowBackend
{
    WINDOW_BACKEND_OPENGL = 0,
} WindowBackend;

typedef struct WindowConfig
{
    u32 width;
    u32 height;
    const char *title;

    WindowBackend backend;
    Flags32 flags;
    u32 samples;

    struct { u32 version_major; u32 version_minor; } opengl;
} WindowConfig;

WindowConfig window_config_default(void);

/****************************************************************
 * Window
****************************************************************/
typedef struct Window Window;

Window* window_create(Allocator *allocator, WindowConfig cfg);
Window* window_create_default(Allocator *allocator);
void    window_destroy(Window *window);

bool window_should_close(Window *window);
void window_request_close(Window *window);

void window_poll_events(Window *window);

void window_make_context_current(Window *window);
void window_swap_buffers(Window *window);

void window_title_set(Window *window, const char *title);

/****************************************************************
 * Vsync
****************************************************************/
void window_vsync_set(Window *window, bool enabled);
bool window_vsync_enabled(Window *window);

/****************************************************************
 * Fullscreen
****************************************************************/
void window_fullscreen_set(Window *window, bool fullscreen);
void window_fullscreen_toggle(Window *window);
bool window_is_fullscreen(Window *window);

/****************************************************************
 * Window Geometry
****************************************************************/
void window_position_get(Window *window, i32 *x, i32 *y);
void window_size_get(Window *window, i32 *width, i32 *height);

/****************************************************************
 * Monitor
****************************************************************/
typedef struct Monitor Monitor;

Monitor* monitor_primary_get(void);
Monitor* window_monitor_get(Window *window);

/****************************************************************
 * Callbacks
****************************************************************/
typedef void (*KeyCallback)(Window *window, i32 key, i32 scancode, i32 action, i32 mods);
typedef void (*MouseButtonCallback)(Window *window, i32 button, i32 action, i32 mods);
typedef void (*CursorPositionCallback)(Window *window, f64 xpos, f64 ypos);
typedef void (*ScrollCallback)(Window *window, f64 xoffset, f64 yoffset);
typedef void (*CursorEnterCallback)(Window *window, i32 entered);
typedef void (*WindowSizeCallback)(Window *window, i32 width, i32 height);
typedef void (*FramebufferSizeCallback)(Window *window, i32 width, i32 height);

void window_set_key_callback(Window *window, KeyCallback callback);
void window_set_mouse_button_callback(Window *window, MouseButtonCallback callback);
void window_set_cursor_position_callback(Window *window, CursorPositionCallback callback);
void window_set_scroll_callback(Window *window, ScrollCallback callback);
void window_set_cursor_enter_callback(Window *window, CursorEnterCallback callback);
void window_set_window_size_callback(Window *window, WindowSizeCallback callback);
void window_set_framebuffer_size_callback(Window *window, FramebufferSizeCallback callback);

void  window_user_pointer_set(Window *window, void *user_pointer);
void* window_user_pointer_get(Window *window);

/****************************************************************
 * Keyboard Input
****************************************************************/
typedef enum KeyState
{
    KEY_UP = 0,
    KEY_DOWN,
    KEY_RELEASED,
    KEY_PRESSED,
} KeyState;

KeyState key_state_get(Window *window, u32 key);
bool     key_is_down(Window *window, u32 key);
bool     key_is_up(Window *window, u32 key);
bool     key_is_pressed(Window *window, u32 key);
bool     key_is_released(Window *window, u32 key);

/****************************************************************
 * Mouse Input
****************************************************************/
KeyState mouse_button_state_get(Window *window, u32 button);
bool     mouse_button_is_down(Window *window, u32 button);
bool     mouse_button_is_up(Window *window, u32 button);
bool     mouse_button_is_pressed(Window *window, u32 button);
bool     mouse_button_is_released(Window *window, u32 button);

void cursor_pos_get(Window *window, f32 *x, f32 *y);
void cursor_pos_prev_get(Window *window, f32 *x, f32 *y);
void cursor_delta_get(Window *window, f32 *x, f32 *y);

typedef enum CursorFocus {
    CURSOR_INSIDE = 0,
    CURSOR_OUTSIDE,
    CURSOR_ENTERED,
    CURSOR_LEFT
} CursorFocus;

CursorFocus cursor_focus_get(Window *window);
bool        cursor_is_inside(Window *window);
bool        cursor_is_outside(Window *window);
bool        cursor_entered(Window *window);
bool        cursor_left(Window *window);

void scroll_delta_get(Window *window, f32 *x, f32 *y);
f32  scroll_delta_x(Window *window);
f32  scroll_delta_y(Window *window);
bool scroll_happened(Window *window);

void cursor_show(Window *window);
void cursor_hide(Window *window);
bool cursor_is_visible(Window *window);

void cursor_capture(Window *window);
void cursor_release(Window *window);
bool cursor_is_captured(Window *window);

/****************************************************************
 * Miscellaneous
****************************************************************/
void*  proc_address_get(const char *name);
double time_get(void);

/* Printable keys */
#define KEY_SPACE              32
#define KEY_APOSTROPHE         39  /* ' */
#define KEY_COMMA              44  /* , */
#define KEY_MINUS              45  /* - */
#define KEY_PERIOD             46  /* . */
#define KEY_SLASH              47  /* / */
#define KEY_0                  48
#define KEY_1                  49
#define KEY_2                  50
#define KEY_3                  51
#define KEY_4                  52
#define KEY_5                  53
#define KEY_6                  54
#define KEY_7                  55
#define KEY_8                  56
#define KEY_9                  57
#define KEY_SEMICOLON          59  /* ; */
#define KEY_EQUAL              61  /* = */
#define KEY_A                  65
#define KEY_B                  66
#define KEY_C                  67
#define KEY_D                  68
#define KEY_E                  69
#define KEY_F                  70
#define KEY_G                  71
#define KEY_H                  72
#define KEY_I                  73
#define KEY_J                  74
#define KEY_K                  75
#define KEY_L                  76
#define KEY_M                  77
#define KEY_N                  78
#define KEY_O                  79
#define KEY_P                  80
#define KEY_Q                  81
#define KEY_R                  82
#define KEY_S                  83
#define KEY_T                  84
#define KEY_U                  85
#define KEY_V                  86
#define KEY_W                  87
#define KEY_X                  88
#define KEY_Y                  89
#define KEY_Z                  90
#define KEY_LEFT_BRACKET       91  /* [ */
#define KEY_BACKSLASH          92  /* \ */
#define KEY_RIGHT_BRACKET      93  /* ] */
#define KEY_GRAVE_ACCENT       96  /* ` */
#define KEY_WORLD_1            161 /* non-US #1 */
#define KEY_WORLD_2            162 /* non-US #2 */

/* Function keys */
#define KEY_ESCAPE             256
#define KEY_ENTER              257
#define KEY_TAB                258
#define KEY_BACKSPACE          259
#define KEY_INSERT             260
#define KEY_DELETE             261
#define KEY_RIGHT              262
#define KEY_LEFT               263
#define KEY_DOWN               264
#define KEY_UP                 265
#define KEY_PAGE_UP            266
#define KEY_PAGE_DOWN          267
#define KEY_HOME               268
#define KEY_END                269
#define KEY_CAPS_LOCK          280
#define KEY_SCROLL_LOCK        281
#define KEY_NUM_LOCK           282
#define KEY_PRINT_SCREEN       283
#define KEY_PAUSE              284
#define KEY_F1                 290
#define KEY_F2                 291
#define KEY_F3                 292
#define KEY_F4                 293
#define KEY_F5                 294
#define KEY_F6                 295
#define KEY_F7                 296
#define KEY_F8                 297
#define KEY_F9                 298
#define KEY_F10                299
#define KEY_F11                300
#define KEY_F12                301
#define KEY_F13                302
#define KEY_F14                303
#define KEY_F15                304
#define KEY_F16                305
#define KEY_F17                306
#define KEY_F18                307
#define KEY_F19                308
#define KEY_F20                309
#define KEY_F21                310
#define KEY_F22                311
#define KEY_F23                312
#define KEY_F24                313
#define KEY_F25                314
#define KEY_KP_0               320
#define KEY_KP_1               321
#define KEY_KP_2               322
#define KEY_KP_3               323
#define KEY_KP_4               324
#define KEY_KP_5               325
#define KEY_KP_6               326
#define KEY_KP_7               327
#define KEY_KP_8               328
#define KEY_KP_9               329
#define KEY_KP_DECIMAL         330
#define KEY_KP_DIVIDE          331
#define KEY_KP_MULTIPLY        332
#define KEY_KP_SUBTRACT        333
#define KEY_KP_ADD             334
#define KEY_KP_ENTER           335
#define KEY_KP_EQUAL           336
#define KEY_LEFT_SHIFT         340
#define KEY_LEFT_CONTROL       341
#define KEY_LEFT_ALT           342
#define KEY_LEFT_SUPER         343
#define KEY_RIGHT_SHIFT        344
#define KEY_RIGHT_CONTROL      345
#define KEY_RIGHT_ALT          346
#define KEY_RIGHT_SUPER        347
#define KEY_MENU               348
#define KEY_LAST               KEY_MENU

#define MOUSE_BUTTON_1         0
#define MOUSE_BUTTON_2         1
#define MOUSE_BUTTON_3         2
#define MOUSE_BUTTON_4         3
#define MOUSE_BUTTON_5         4
#define MOUSE_BUTTON_6         5
#define MOUSE_BUTTON_7         6
#define MOUSE_BUTTON_8         7
#define MOUSE_BUTTON_LAST      MOUSE_BUTTON_8
#define MOUSE_BUTTON_LEFT      MOUSE_BUTTON_1
#define MOUSE_BUTTON_RIGHT     MOUSE_BUTTON_2
#define MOUSE_BUTTON_MIDDLE    MOUSE_BUTTON_3

C_LINKAGE_END

#endif // _XTB_WINDOW_H_
