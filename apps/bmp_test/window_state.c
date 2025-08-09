typedef struct WindowState WindowState;
struct WindowState
{
    Vector2 screen_size;
    Vector2 virtual_size;

    Vector2 screen_mouse_position;
    Vector2 virtual_mouse_position;

    float scale;
};

WindowState
create_window_state(Vector2 screen_size, Vector2 virtual_size)
{
    WindowState state = {};
    state.screen_size = screen_size;
    state.virtual_size = virtual_size;
    state.scale = 1.0f / xtb_min(screen_size.x / virtual_size.x,
                                 screen_size.y / virtual_size.y);
    return state;
}

void
update_mouse_position(WindowState *state)
{
    state->screen_mouse_position = GetMousePosition();
    state->virtual_mouse_position.x = state->screen_mouse_position.x * state->scale;
    state->virtual_mouse_position.y = state->screen_mouse_position.y * state->scale;

    state->virtual_mouse_position.x = xtb_clamp(state->virtual_mouse_position.x,
                                                0,
                                                state->screen_size.x);
    state->virtual_mouse_position.y = xtb_clamp(state->virtual_mouse_position.y,
                                                0,
                                                state->screen_size.y);
}

WindowState window_state;
