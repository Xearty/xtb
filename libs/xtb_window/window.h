#ifndef _XTB_WINDOW_H_
#define _XTB_WINDOW_H_

#include <xtb_core/core.h>

typedef struct XTB_Window XTB_Window;

typedef enum XTB_Window_Flags
{
    XTB_WIN_OPENGL_CONTEXT = 0b0001
} XTB_Window_Flags;

typedef struct XTB_Window_Config
{
    u32 width;
    u32 height;
    const char *title;
    u32 samples;
    XTB_Window_Flags flags;
} XTB_Window_Config;

void window_system_init(void);
void window_system_deinit(void);

XTB_Window *window_create(XTB_Window_Config config);
void window_destroy(XTB_Window *window);

bool window_should_close(XTB_Window *window);
void window_poll_events(XTB_Window *window);
void window_swap_buffers(XTB_Window *window);

void window_make_context_current(XTB_Window *window);

#endif // _XTB_WINDOW_H_
