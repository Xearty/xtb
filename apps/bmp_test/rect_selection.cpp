#include <xtb_core/core.h>
#include <raylib.h>
#include <string.h>
#include <stdlib.h>

typedef struct Rect Rect;
struct Rect {
    int x;
    int y;
    int width;
    int height;
};

typedef struct RectangleSelections RectangleSelections;
struct RectangleSelections {
    // Rects buffer
    Rect *rects;
    int rects_sz;
    int rects_cap;

    // Visual rect
    int is_creating_rect;
    int init_visual_rect_x, init_visual_rect_y;
    int cursor_visual_rect_x, cursor_visual_rect_y;
};

static Rect
create_rect_from_visual_selection(const RectangleSelections *selections)
{
    int left = Min(selections->init_visual_rect_x, selections->cursor_visual_rect_x);
    int right = Max(selections->init_visual_rect_x, selections->cursor_visual_rect_x);
    int top = Min(selections->init_visual_rect_y, selections->cursor_visual_rect_y);
    int bottom = Max(selections->init_visual_rect_y, selections->cursor_visual_rect_y);

    int width = right - left;
    int height = bottom - top;

    return (Rect){ left, top, width, height };
}


static void
push_selection_rect(RectangleSelections *selections, Rect selection)
{
    if (selections->rects_sz == selections->rects_cap)
    {
        if (selections->rects_cap == 0)
        {
            selections->rects_cap = 8;
        }
        else
        {
            selections->rects_cap <<= 1;
        }

        void *new_buf = malloc(selections->rects_cap * sizeof(Rect));
        memcpy(new_buf, selections->rects, selections->rects_sz * sizeof(Rect));
        free(selections->rects);
        selections->rects = (Rect*)new_buf;
    }

    selections->rects[selections->rects_sz++] = selection;
}

static void
update_rect_selections(RectangleSelections *selections)
{
    if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
    {
        selections->is_creating_rect = true;
        Vector2 mouse_pos = window_state.virtual_mouse_position;
        selections->init_visual_rect_x = mouse_pos.x;
        selections->init_visual_rect_y = mouse_pos.y;
    }
    if(IsMouseButtonDown(MOUSE_BUTTON_LEFT))
    {
        if (selections->is_creating_rect)
        {
            Vector2 mouse_pos = window_state.virtual_mouse_position;
            selections->cursor_visual_rect_x = mouse_pos.x;
            selections->cursor_visual_rect_y = mouse_pos.y;
        }
    }
    if (IsMouseButtonReleased(MOUSE_BUTTON_LEFT))
    {
        selections->is_creating_rect = false;
        Rect visual_rect = create_rect_from_visual_selection(selections);
        push_selection_rect(selections, visual_rect);
    }
}

static void
render_selection_visual_rect(const RectangleSelections* selections)
{
    if (selections->is_creating_rect)
    {
        Rect visual_rect = create_rect_from_visual_selection(selections);
        DrawRectangleLines(visual_rect.x,
                           visual_rect.y,
                           visual_rect.width,
                           visual_rect.height,
                           MAGENTA);
    }
}

static int
is_inside_selection(const RectangleSelections *selections, int x, int y)
{

    for (int rect_idx = 0; rect_idx < selections->rects_sz; rect_idx++)
    {
        Rect rect = selections->rects[rect_idx];
        int inner_x = x - rect.x;
        int inner_y = y - rect.y;

        if (inner_x >= 0 && inner_x < rect.width)
        {
            if (inner_y >= 0 && inner_y < rect.height)
            {
                return 1;
            }
        }
    }
    return 0;
}
