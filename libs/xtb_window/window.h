#ifndef _XTB_WINDOW_H_
#define _XTB_WINDOW_H_

#include <xtb_core/core.h>
#include <xtb_core/allocator.h>

XTB_C_LINKAGE_BEGIN

/****************************************************************
 * Window System
****************************************************************/
void window_system_init(void);
void window_system_deinit(void);

/****************************************************************
 * Window Creation Config
****************************************************************/
typedef enum XTB_Window_Flags
{
    XTB_WINDOW_VSYNC      = 0b0001,
    XTB_WINDOW_FULLSCREEN = 0b0010,
} XTB_Window_Flags;

typedef enum XTB_Window_Backend
{
    XTB_WINDOW_BACKEND_OPENGL = 0,
} XTB_Window_Backend;

typedef struct XTB_Window_Config
{
    u32 width;
    u32 height;
    const char *title;

    XTB_Window_Backend backend;
    Flags32 flags;
    u32 samples;

    struct { u32 version_major; u32 version_minor; } opengl;
} XTB_Window_Config;

XTB_Window_Config window_config_default(void);

/****************************************************************
 * Window
****************************************************************/
typedef struct XTB_Window XTB_Window;

XTB_Window *window_create(Allocator *allocator, XTB_Window_Config cfg);
XTB_Window *window_create_default(Allocator *allocator);
void window_destroy(XTB_Window *window);

bool window_should_close(XTB_Window *window);
void window_poll_events(XTB_Window *window);

void window_make_context_current(XTB_Window *window);
void window_swap_buffers(XTB_Window *window);

void window_request_close(XTB_Window *window);
void window_set_title(XTB_Window *window, const char *title);

void window_set_vsync(XTB_Window *window, bool enabled);
bool window_vsync_enabled(XTB_Window *window);

void window_go_fullscreen(XTB_Window *window);
void window_go_windowed(XTB_Window *window);
void window_toggle_fullscreen(XTB_Window *window);
bool window_is_fullscreen(XTB_Window *window);

void window_get_position(XTB_Window *window, i32 *x, i32 *y);
void window_get_size(XTB_Window *window, i32 *width, i32 *height);

/****************************************************************
 * Monitor
****************************************************************/
typedef struct XTB_Monitor XTB_Monitor;

XTB_Monitor *window_get_primary_monitor(void);
XTB_Monitor *window_get_monitor(XTB_Window *window);

/****************************************************************
 * Window Callbacks
****************************************************************/
typedef void (*XTB_Window_Key_Callback)(XTB_Window *window, i32 key, i32 scancode, i32 action, i32 mods);
typedef void (*XTB_Window_Mouse_Button_Callback)(XTB_Window *window, i32 button, i32 action, i32 mods);
typedef void (*XTB_Window_Cursor_Position_Callback)(XTB_Window *window, f64 xpos, f64 ypos);
typedef void (*XTB_Window_Scroll_Callback)(XTB_Window *window, f64 xoffset, f64 yoffset);
typedef void (*XTB_Window_Cursor_Enter_Callback)(XTB_Window *window, i32 entered);

typedef void (*XTB_Window_Size_Callback)(XTB_Window *window, i32 width, i32 height);
typedef void (*XTB_Window_Framebuffer_Size_Callback)(XTB_Window *window, i32 width, i32 height);

void window_set_key_callback(XTB_Window *window, XTB_Window_Key_Callback callback);
void window_set_mouse_button_callback(XTB_Window *window, XTB_Window_Mouse_Button_Callback callback);
void window_set_cursor_position_callback(XTB_Window *window, XTB_Window_Cursor_Position_Callback callback);
void window_set_scroll_callback(XTB_Window *window, XTB_Window_Scroll_Callback callback);
void window_set_cursor_enter_callback(XTB_Window *window, XTB_Window_Cursor_Enter_Callback callback);
void window_set_window_size_callback(XTB_Window *window, XTB_Window_Size_Callback callback);
void window_set_framebuffer_size_callback(XTB_Window *window, XTB_Window_Framebuffer_Size_Callback callback);

void window_set_user_pointer(XTB_Window *window, void *user_pointer);
void *window_get_user_pointer(XTB_Window *window);

/****************************************************************
 * Keyboard Input
****************************************************************/
typedef enum XTB_Key_State
{
    XTB_KEY_STATE_UP = 0,
    XTB_KEY_STATE_DOWN,
    XTB_KEY_STATE_RELEASED,
    XTB_KEY_STATE_PRESSED,
} XTB_Key_State;

XTB_Key_State window_key_get_state(XTB_Window *window, u32 key);
bool window_key_is_up(XTB_Window *window, u32 key);
bool window_key_is_down(XTB_Window *window, u32 key);
bool window_key_is_released(XTB_Window *window, u32 key);
bool window_key_is_pressed(XTB_Window *window, u32 key);

/****************************************************************
 * Mouse Input
****************************************************************/
XTB_Key_State window_mouse_button_get_state(XTB_Window *window, u32 button);
bool window_mouse_button_is_up(XTB_Window *window, u32 button);
bool window_mouse_button_is_down(XTB_Window *window, u32 button);
bool window_mouse_button_is_released(XTB_Window *window, u32 button);
bool window_mouse_button_is_pressed(XTB_Window *window, u32 button);

void window_cursor_get_position(XTB_Window *window, f32 *x, f32 *y);
void window_cursor_get_previous_position(XTB_Window *window, f32 *x, f32 *y);
void window_cursor_get_delta(XTB_Window *window, f32 *x, f32 *y);

typedef enum XTB_Cursor_Focus_State {
    XTB_CURSOR_FOCUS_INSIDE = 0,
    XTB_CURSOR_FOCUS_OUTSIDE,
    XTB_CURSOR_FOCUS_JUST_ENTERED,
    XTB_CURSOR_FOCUS_JUST_LEFT
} XTB_Cursor_Focus_State;

XTB_Cursor_Focus_State window_cursor_get_focus(XTB_Window *window);
bool window_cursor_is_inside_window(XTB_Window *window);
bool window_cursor_is_outside_window(XTB_Window *window);
bool window_cursor_just_entered_window(XTB_Window *window);
bool window_cursor_just_left_window(XTB_Window *window);

void window_scroll_get_delta(XTB_Window *window, f32 *x, f32 *y);
f32 window_scroll_delta_x(XTB_Window *window);
f32 window_scroll_delta_y(XTB_Window *window);
bool window_scroll_this_frame(XTB_Window *window);

void window_cursor_show(XTB_Window *window);
void window_cursor_hide(XTB_Window *window);
bool window_cursor_is_visible(XTB_Window *window);

void window_cursor_capture(XTB_Window *window);
void window_cursor_release(XTB_Window *window);
bool window_cursor_is_captured(XTB_Window *window);

/****************************************************************
 * Miscellaneous
****************************************************************/
void *window_get_proc_address(const char *name);
double window_get_time(void);

/* Printable keys */
#define XTB_KEY_SPACE              32
#define XTB_KEY_APOSTROPHE         39  /* ' */
#define XTB_KEY_COMMA              44  /* , */
#define XTB_KEY_MINUS              45  /* - */
#define XTB_KEY_PERIOD             46  /* . */
#define XTB_KEY_SLASH              47  /* / */
#define XTB_KEY_0                  48
#define XTB_KEY_1                  49
#define XTB_KEY_2                  50
#define XTB_KEY_3                  51
#define XTB_KEY_4                  52
#define XTB_KEY_5                  53
#define XTB_KEY_6                  54
#define XTB_KEY_7                  55
#define XTB_KEY_8                  56
#define XTB_KEY_9                  57
#define XTB_KEY_SEMICOLON          59  /* ; */
#define XTB_KEY_EQUAL              61  /* = */
#define XTB_KEY_A                  65
#define XTB_KEY_B                  66
#define XTB_KEY_C                  67
#define XTB_KEY_D                  68
#define XTB_KEY_E                  69
#define XTB_KEY_F                  70
#define XTB_KEY_G                  71
#define XTB_KEY_H                  72
#define XTB_KEY_I                  73
#define XTB_KEY_J                  74
#define XTB_KEY_K                  75
#define XTB_KEY_L                  76
#define XTB_KEY_M                  77
#define XTB_KEY_N                  78
#define XTB_KEY_O                  79
#define XTB_KEY_P                  80
#define XTB_KEY_Q                  81
#define XTB_KEY_R                  82
#define XTB_KEY_S                  83
#define XTB_KEY_T                  84
#define XTB_KEY_U                  85
#define XTB_KEY_V                  86
#define XTB_KEY_W                  87
#define XTB_KEY_X                  88
#define XTB_KEY_Y                  89
#define XTB_KEY_Z                  90
#define XTB_KEY_LEFT_BRACKET       91  /* [ */
#define XTB_KEY_BACKSLASH          92  /* \ */
#define XTB_KEY_RIGHT_BRACKET      93  /* ] */
#define XTB_KEY_GRAVE_ACCENT       96  /* ` */
#define XTB_KEY_WORLD_1            161 /* non-US #1 */
#define XTB_KEY_WORLD_2            162 /* non-US #2 */

/* Function keys */
#define XTB_KEY_ESCAPE             256
#define XTB_KEY_ENTER              257
#define XTB_KEY_TAB                258
#define XTB_KEY_BACKSPACE          259
#define XTB_KEY_INSERT             260
#define XTB_KEY_DELETE             261
#define XTB_KEY_RIGHT              262
#define XTB_KEY_LEFT               263
#define XTB_KEY_DOWN               264
#define XTB_KEY_UP                 265
#define XTB_KEY_PAGE_UP            266
#define XTB_KEY_PAGE_DOWN          267
#define XTB_KEY_HOME               268
#define XTB_KEY_END                269
#define XTB_KEY_CAPS_LOCK          280
#define XTB_KEY_SCROLL_LOCK        281
#define XTB_KEY_NUM_LOCK           282
#define XTB_KEY_PRINT_SCREEN       283
#define XTB_KEY_PAUSE              284
#define XTB_KEY_F1                 290
#define XTB_KEY_F2                 291
#define XTB_KEY_F3                 292
#define XTB_KEY_F4                 293
#define XTB_KEY_F5                 294
#define XTB_KEY_F6                 295
#define XTB_KEY_F7                 296
#define XTB_KEY_F8                 297
#define XTB_KEY_F9                 298
#define XTB_KEY_F10                299
#define XTB_KEY_F11                300
#define XTB_KEY_F12                301
#define XTB_KEY_F13                302
#define XTB_KEY_F14                303
#define XTB_KEY_F15                304
#define XTB_KEY_F16                305
#define XTB_KEY_F17                306
#define XTB_KEY_F18                307
#define XTB_KEY_F19                308
#define XTB_KEY_F20                309
#define XTB_KEY_F21                310
#define XTB_KEY_F22                311
#define XTB_KEY_F23                312
#define XTB_KEY_F24                313
#define XTB_KEY_F25                314
#define XTB_KEY_KP_0               320
#define XTB_KEY_KP_1               321
#define XTB_KEY_KP_2               322
#define XTB_KEY_KP_3               323
#define XTB_KEY_KP_4               324
#define XTB_KEY_KP_5               325
#define XTB_KEY_KP_6               326
#define XTB_KEY_KP_7               327
#define XTB_KEY_KP_8               328
#define XTB_KEY_KP_9               329
#define XTB_KEY_KP_DECIMAL         330
#define XTB_KEY_KP_DIVIDE          331
#define XTB_KEY_KP_MULTIPLY        332
#define XTB_KEY_KP_SUBTRACT        333
#define XTB_KEY_KP_ADD             334
#define XTB_KEY_KP_ENTER           335
#define XTB_KEY_KP_EQUAL           336
#define XTB_KEY_LEFT_SHIFT         340
#define XTB_KEY_LEFT_CONTROL       341
#define XTB_KEY_LEFT_ALT           342
#define XTB_KEY_LEFT_SUPER         343
#define XTB_KEY_RIGHT_SHIFT        344
#define XTB_KEY_RIGHT_CONTROL      345
#define XTB_KEY_RIGHT_ALT          346
#define XTB_KEY_RIGHT_SUPER        347
#define XTB_KEY_MENU               348

#define XTB_KEY_LAST               XTB_KEY_MENU


#define XTB_MOUSE_BUTTON_1         0
#define XTB_MOUSE_BUTTON_2         1
#define XTB_MOUSE_BUTTON_3         2
#define XTB_MOUSE_BUTTON_4         3
#define XTB_MOUSE_BUTTON_5         4
#define XTB_MOUSE_BUTTON_6         5
#define XTB_MOUSE_BUTTON_7         6
#define XTB_MOUSE_BUTTON_8         7
#define XTB_MOUSE_BUTTON_LAST      XTB_MOUSE_BUTTON_8
#define XTB_MOUSE_BUTTON_LEFT      XTB_MOUSE_BUTTON_1
#define XTB_MOUSE_BUTTON_RIGHT     XTB_MOUSE_BUTTON_2
#define XTB_MOUSE_BUTTON_MIDDLE    XTB_MOUSE_BUTTON_3

XTB_C_LINKAGE_END

#endif // _XTB_WINDOW_H_
