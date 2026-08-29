module xtb.window.internal.glfw_input;

nothrow @nogc:

import xtb.window.input : Key, KeyAction, KeyModifier, MouseButton, MouseButtonAction;
import xtb.window.internal.glfw;

package(xtb.window) KeyAction key_action_from_glfw(int action) pure @safe
{
    switch (action)
    {
        case GLFW_PRESS:
            return KeyAction.pressed;
        case GLFW_REPEAT:
            return KeyAction.repeated;
        default:
            return KeyAction.released;
    }
}

package(xtb.window) MouseButtonAction mouse_button_action_from_glfw(int action) pure @safe
{
    return action == GLFW_PRESS ? MouseButtonAction.pressed : MouseButtonAction.released;
}

package(xtb.window) KeyModifier modifiers_from_glfw(int modifiers) pure @safe
{
    ubyte value;
    if ((modifiers & GLFW_MOD_SHIFT) != 0)
        value |= cast(ubyte) KeyModifier.shift;
    if ((modifiers & GLFW_MOD_CONTROL) != 0)
        value |= cast(ubyte) KeyModifier.control;
    if ((modifiers & GLFW_MOD_ALT) != 0)
        value |= cast(ubyte) KeyModifier.alt;
    if ((modifiers & GLFW_MOD_SUPER) != 0)
        value |= cast(ubyte) KeyModifier.super_;
    if ((modifiers & GLFW_MOD_CAPS_LOCK) != 0)
        value |= cast(ubyte) KeyModifier.caps_lock;
    if ((modifiers & GLFW_MOD_NUM_LOCK) != 0)
        value |= cast(ubyte) KeyModifier.num_lock;
    return cast(KeyModifier) value;
}

package(xtb.window) MouseButton mouse_button_from_glfw(int button) pure @safe
{
    switch (button)
    {
        case 0:
            return MouseButton.left;
        case 1:
            return MouseButton.right;
        case 2:
            return MouseButton.middle;
        case 3:
            return MouseButton.button4;
        case 4:
            return MouseButton.button5;
        case 5:
            return MouseButton.button6;
        case 6:
            return MouseButton.button7;
        case 7:
            return MouseButton.button8;
        default:
            return MouseButton.count;
    }
}

package(xtb.window) Key key_from_glfw(int key) pure @safe
{
    switch (key)
    {
        case GLFW_KEY_SPACE: return Key.space;
        case GLFW_KEY_APOSTROPHE: return Key.apostrophe;
        case GLFW_KEY_COMMA: return Key.comma;
        case GLFW_KEY_MINUS: return Key.minus;
        case GLFW_KEY_PERIOD: return Key.period;
        case GLFW_KEY_SLASH: return Key.slash;
        case GLFW_KEY_0: return Key.digit0;
        case GLFW_KEY_1: return Key.digit1;
        case GLFW_KEY_2: return Key.digit2;
        case GLFW_KEY_3: return Key.digit3;
        case GLFW_KEY_4: return Key.digit4;
        case GLFW_KEY_5: return Key.digit5;
        case GLFW_KEY_6: return Key.digit6;
        case GLFW_KEY_7: return Key.digit7;
        case GLFW_KEY_8: return Key.digit8;
        case GLFW_KEY_9: return Key.digit9;
        case GLFW_KEY_SEMICOLON: return Key.semicolon;
        case GLFW_KEY_EQUAL: return Key.equal;
        case GLFW_KEY_A: return Key.a;
        case GLFW_KEY_B: return Key.b;
        case GLFW_KEY_C: return Key.c;
        case GLFW_KEY_D: return Key.d;
        case GLFW_KEY_E: return Key.e;
        case GLFW_KEY_F: return Key.f;
        case GLFW_KEY_G: return Key.g;
        case GLFW_KEY_H: return Key.h;
        case GLFW_KEY_I: return Key.i;
        case GLFW_KEY_J: return Key.j;
        case GLFW_KEY_K: return Key.k;
        case GLFW_KEY_L: return Key.l;
        case GLFW_KEY_M: return Key.m;
        case GLFW_KEY_N: return Key.n;
        case GLFW_KEY_O: return Key.o;
        case GLFW_KEY_P: return Key.p;
        case GLFW_KEY_Q: return Key.q;
        case GLFW_KEY_R: return Key.r;
        case GLFW_KEY_S: return Key.s;
        case GLFW_KEY_T: return Key.t;
        case GLFW_KEY_U: return Key.u;
        case GLFW_KEY_V: return Key.v;
        case GLFW_KEY_W: return Key.w;
        case GLFW_KEY_X: return Key.x;
        case GLFW_KEY_Y: return Key.y;
        case GLFW_KEY_Z: return Key.z;
        case GLFW_KEY_LEFT_BRACKET: return Key.left_bracket;
        case GLFW_KEY_BACKSLASH: return Key.backslash;
        case GLFW_KEY_RIGHT_BRACKET: return Key.right_bracket;
        case GLFW_KEY_GRAVE_ACCENT: return Key.grave_accent;
        case GLFW_KEY_WORLD_1: return Key.world1;
        case GLFW_KEY_WORLD_2: return Key.world2;
        case GLFW_KEY_ESCAPE: return Key.escape;
        case GLFW_KEY_ENTER: return Key.enter;
        case GLFW_KEY_TAB: return Key.tab;
        case GLFW_KEY_BACKSPACE: return Key.backspace;
        case GLFW_KEY_INSERT: return Key.insert;
        case GLFW_KEY_DELETE: return Key.delete_key;
        case GLFW_KEY_RIGHT: return Key.right;
        case GLFW_KEY_LEFT: return Key.left;
        case GLFW_KEY_DOWN: return Key.down;
        case GLFW_KEY_UP: return Key.up;
        case GLFW_KEY_PAGE_UP: return Key.page_up;
        case GLFW_KEY_PAGE_DOWN: return Key.page_down;
        case GLFW_KEY_HOME: return Key.home;
        case GLFW_KEY_END: return Key.end;
        case GLFW_KEY_CAPS_LOCK: return Key.caps_lock;
        case GLFW_KEY_SCROLL_LOCK: return Key.scroll_lock;
        case GLFW_KEY_NUM_LOCK: return Key.num_lock;
        case GLFW_KEY_PRINT_SCREEN: return Key.print_screen;
        case GLFW_KEY_PAUSE: return Key.pause;
        case GLFW_KEY_F1: return Key.f1;
        case GLFW_KEY_F2: return Key.f2;
        case GLFW_KEY_F3: return Key.f3;
        case GLFW_KEY_F4: return Key.f4;
        case GLFW_KEY_F5: return Key.f5;
        case GLFW_KEY_F6: return Key.f6;
        case GLFW_KEY_F7: return Key.f7;
        case GLFW_KEY_F8: return Key.f8;
        case GLFW_KEY_F9: return Key.f9;
        case GLFW_KEY_F10: return Key.f10;
        case GLFW_KEY_F11: return Key.f11;
        case GLFW_KEY_F12: return Key.f12;
        case GLFW_KEY_F13: return Key.f13;
        case GLFW_KEY_F14: return Key.f14;
        case GLFW_KEY_F15: return Key.f15;
        case GLFW_KEY_F16: return Key.f16;
        case GLFW_KEY_F17: return Key.f17;
        case GLFW_KEY_F18: return Key.f18;
        case GLFW_KEY_F19: return Key.f19;
        case GLFW_KEY_F20: return Key.f20;
        case GLFW_KEY_F21: return Key.f21;
        case GLFW_KEY_F22: return Key.f22;
        case GLFW_KEY_F23: return Key.f23;
        case GLFW_KEY_F24: return Key.f24;
        case GLFW_KEY_F25: return Key.f25;
        case GLFW_KEY_KP_0: return Key.keypad0;
        case GLFW_KEY_KP_1: return Key.keypad1;
        case GLFW_KEY_KP_2: return Key.keypad2;
        case GLFW_KEY_KP_3: return Key.keypad3;
        case GLFW_KEY_KP_4: return Key.keypad4;
        case GLFW_KEY_KP_5: return Key.keypad5;
        case GLFW_KEY_KP_6: return Key.keypad6;
        case GLFW_KEY_KP_7: return Key.keypad7;
        case GLFW_KEY_KP_8: return Key.keypad8;
        case GLFW_KEY_KP_9: return Key.keypad9;
        case GLFW_KEY_KP_DECIMAL: return Key.keypad_decimal;
        case GLFW_KEY_KP_DIVIDE: return Key.keypad_divide;
        case GLFW_KEY_KP_MULTIPLY: return Key.keypad_multiply;
        case GLFW_KEY_KP_SUBTRACT: return Key.keypad_subtract;
        case GLFW_KEY_KP_ADD: return Key.keypad_add;
        case GLFW_KEY_KP_ENTER: return Key.keypad_enter;
        case GLFW_KEY_KP_EQUAL: return Key.keypad_equal;
        case GLFW_KEY_LEFT_SHIFT: return Key.left_shift;
        case GLFW_KEY_LEFT_CONTROL: return Key.left_control;
        case GLFW_KEY_LEFT_ALT: return Key.left_alt;
        case GLFW_KEY_LEFT_SUPER: return Key.left_super;
        case GLFW_KEY_RIGHT_SHIFT: return Key.right_shift;
        case GLFW_KEY_RIGHT_CONTROL: return Key.right_control;
        case GLFW_KEY_RIGHT_ALT: return Key.right_alt;
        case GLFW_KEY_RIGHT_SUPER: return Key.right_super;
        case GLFW_KEY_MENU: return Key.menu;
        default: return Key.unknown;
    }
}
