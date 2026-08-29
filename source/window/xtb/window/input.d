module xtb.window.input;

nothrow @nogc:

import xtb.types : u8;

enum Key : ubyte
{
    unknown,
    space,
    apostrophe,
    comma,
    minus,
    period,
    slash,
    digit0,
    digit1,
    digit2,
    digit3,
    digit4,
    digit5,
    digit6,
    digit7,
    digit8,
    digit9,
    semicolon,
    equal,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    left_bracket,
    backslash,
    right_bracket,
    grave_accent,
    world1,
    world2,
    escape,
    enter,
    tab,
    backspace,
    insert,
    delete_key,
    right,
    left,
    down,
    up,
    page_up,
    page_down,
    home,
    end,
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    f25,
    keypad0,
    keypad1,
    keypad2,
    keypad3,
    keypad4,
    keypad5,
    keypad6,
    keypad7,
    keypad8,
    keypad9,
    keypad_decimal,
    keypad_divide,
    keypad_multiply,
    keypad_subtract,
    keypad_add,
    keypad_enter,
    keypad_equal,
    left_shift,
    left_control,
    left_alt,
    left_super,
    right_shift,
    right_control,
    right_alt,
    right_super,
    menu,
    count,
}

enum KeyAction : u8
{
    released,
    pressed,
    repeated,
}

enum KeyModifier : u8
{
    none = 0,
    shift = 1 << 0,
    control = 1 << 1,
    alt = 1 << 2,
    super_ = 1 << 3,
    caps_lock = 1 << 4,
    num_lock = 1 << 5,
}

struct KeyState
{
nothrow @nogc:

    bool down;
    bool pressed;
    bool released;
    bool repeated;
}

enum MouseButton : u8
{
    left,
    right,
    middle,
    button4,
    button5,
    button6,
    button7,
    button8,
    count,
}

enum MouseButtonAction : u8
{
    released,
    pressed,
}

struct MouseButtonState
{
nothrow @nogc:

    bool down;
    bool pressed;
    bool released;
}

enum CursorMode : u8
{
    normal,
    hidden,
    disabled,
}

struct CursorPosition
{
    double x = 0;
    double y = 0;
}

struct CursorDelta
{
    double x = 0;
    double y = 0;
}

struct ScrollDelta
{
    double x = 0;
    double y = 0;
}
