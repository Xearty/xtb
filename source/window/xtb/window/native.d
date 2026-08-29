module xtb.window.native;

nothrow @nogc:

import xtb.types : u8;

enum NativeWindowPlatform : u8
{
    none,
    win32,
    cocoa,
    wayland,
    x11,
}

struct Win32DisplayHandle
{
    void* instance;
}

struct X11DisplayHandle
{
    void* display;
}

struct WaylandDisplayHandle
{
    void* display;
}

struct Win32WindowHandle
{
    void* window;
}

struct CocoaWindowHandle
{
    void* window;
    void* view;
}

struct X11WindowHandle
{
    ulong window;
}

struct WaylandWindowHandle
{
    void* surface;
}

struct NativeDisplayHandle
{
    NativeWindowPlatform platform = NativeWindowPlatform.none;
    union
    {
        Win32DisplayHandle win32;
        X11DisplayHandle x11;
        WaylandDisplayHandle wayland;
    }
}

struct NativeWindowHandle
{
    NativeWindowPlatform platform = NativeWindowPlatform.none;
    union
    {
        Win32WindowHandle win32;
        CocoaWindowHandle cocoa;
        X11WindowHandle x11;
        WaylandWindowHandle wayland;
    }
}
