module xtb.window.event;

nothrow @nogc:

import xtb.types : i32, u8;
import xtb.window.input : CursorPosition, Key, KeyAction, KeyModifier, MouseButton;

struct WindowPosition
{
    i32 x;
    i32 y;
}

struct WindowSize
{
    i32 width;
    i32 height;
}

struct ContentScale
{
    float x = 1;
    float y = 1;
}

struct BoolWindowEvent
{
    bool value;
}

struct KeyEvent
{
    Key key;
    i32 scan_code;
    KeyAction action;
    KeyModifier modifiers;
}

struct TextInputEvent
{
    dchar codepoint;
}

struct MouseButtonEvent
{
    MouseButton button;
    KeyAction action;
    KeyModifier modifiers;
}

struct CursorMovedEvent
{
    CursorPosition position;
    double delta_x;
    double delta_y;
}

struct ScrollEvent
{
    double x;
    double y;
}

enum WindowEventKind : u8
{
    key,
    text_input,
    mouse_button,
    cursor_moved,
    cursor_entered,
    cursor_left,
    scroll,
    moved,
    resized,
    close_requested,
    focus_changed,
    minimized_changed,
    maximized_changed,
    framebuffer_resized,
    content_scale_changed,
}

struct WindowEvent
{
    WindowEventKind kind;
    union
    {
        KeyEvent key_event;
        TextInputEvent text_input;
        MouseButtonEvent mouse_button_event;
        CursorMovedEvent cursor_moved;
        BoolWindowEvent state;
        ScrollEvent scroll;
        WindowPosition position;
        WindowSize size;
        ContentScale content_scale;
    }
}
