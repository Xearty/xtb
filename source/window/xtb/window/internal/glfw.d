module xtb.window.internal.glfw;

nothrow @nogc:

// Minimal GLFW 3.4+ ABI used by xtb.window. Keeping this declaration surface
// local prevents GLFW constants and types from becoming part of XTB's API.

extern (C):

struct GLFWwindow;
struct GLFWmonitor;

alias GLFWglproc = extern (C) void function() nothrow @nogc;

struct GLFWvidmode
{
    int width;
    int height;
    int redBits;
    int greenBits;
    int blueBits;
    int refreshRate;
}

alias GLFWkeyfun = extern (C) void function(GLFWwindow*, int, int, int, int) nothrow @nogc;
alias GLFWcharfun = extern (C) void function(GLFWwindow*, uint) nothrow @nogc;
alias GLFWmousebuttonfun = extern (C) void function(GLFWwindow*, int, int, int) nothrow @nogc;
alias GLFWcursorposfun = extern (C) void function(GLFWwindow*, double, double) nothrow @nogc;
alias GLFWcursorenterfun = extern (C) void function(GLFWwindow*, int) nothrow @nogc;
alias GLFWscrollfun = extern (C) void function(GLFWwindow*, double, double) nothrow @nogc;
alias GLFWwindowposfun = extern (C) void function(GLFWwindow*, int, int) nothrow @nogc;
alias GLFWwindowsizefun = extern (C) void function(GLFWwindow*, int, int) nothrow @nogc;
alias GLFWwindowclosefun = extern (C) void function(GLFWwindow*) nothrow @nogc;
alias GLFWwindowrefreshfun = extern (C) void function(GLFWwindow*) nothrow @nogc;
alias GLFWwindowfocusfun = extern (C) void function(GLFWwindow*, int) nothrow @nogc;
alias GLFWwindowiconifyfun = extern (C) void function(GLFWwindow*, int) nothrow @nogc;
alias GLFWwindowmaximizefun = extern (C) void function(GLFWwindow*, int) nothrow @nogc;
alias GLFWframebuffersizefun = extern (C) void function(GLFWwindow*, int, int) nothrow @nogc;
alias GLFWwindowcontentscalefun = extern (C) void function(GLFWwindow*, float, float) nothrow @nogc;
alias GLFWmonitorfun = extern (C) void function(GLFWmonitor*, int) nothrow @nogc;

void glfwGetVersion(int*, int*, int*);
void glfwInitHint(int, int);
int glfwInit();
void glfwTerminate();
int glfwGetError(const(char)**);
int glfwPlatformSupported(int);
int glfwGetPlatform();
void glfwDefaultWindowHints();
void glfwWindowHint(int, int);
GLFWwindow* glfwCreateWindow(int, int, const(char)*, GLFWmonitor*, GLFWwindow*);
void glfwDestroyWindow(GLFWwindow*);
void glfwPollEvents();
void glfwMakeContextCurrent(GLFWwindow*);
GLFWwindow* glfwGetCurrentContext();
void glfwSwapBuffers(GLFWwindow*);
void glfwSwapInterval(int);
int glfwExtensionSupported(const(char)*);
GLFWglproc glfwGetProcAddress(const(char)*);
void glfwSetWindowUserPointer(GLFWwindow*, void*);
void* glfwGetWindowUserPointer(GLFWwindow*);
int glfwWindowShouldClose(GLFWwindow*);
void glfwSetWindowShouldClose(GLFWwindow*, int);
void glfwSetWindowTitle(GLFWwindow*, const(char)*);
void glfwGetWindowPos(GLFWwindow*, int*, int*);
void glfwSetWindowPos(GLFWwindow*, int, int);
void glfwGetWindowSize(GLFWwindow*, int*, int*);
void glfwSetWindowSize(GLFWwindow*, int, int);
void glfwGetFramebufferSize(GLFWwindow*, int*, int*);
int glfwGetWindowAttrib(GLFWwindow*, int);
GLFWmonitor* glfwGetWindowMonitor(GLFWwindow*);
void glfwSetWindowMonitor(GLFWwindow*, GLFWmonitor*, int, int, int, int, int);
GLFWmonitor* glfwGetPrimaryMonitor();
GLFWmonitor** glfwGetMonitors(int*);
const(char)* glfwGetMonitorName(GLFWmonitor*);
const(GLFWvidmode)* glfwGetVideoMode(GLFWmonitor*);
GLFWmonitorfun glfwSetMonitorCallback(GLFWmonitorfun);
void glfwGetCursorPos(GLFWwindow*, double*, double*);
int glfwGetInputMode(GLFWwindow*, int);
void glfwSetInputMode(GLFWwindow*, int, int);
GLFWkeyfun glfwSetKeyCallback(GLFWwindow*, GLFWkeyfun);
GLFWcharfun glfwSetCharCallback(GLFWwindow*, GLFWcharfun);
GLFWmousebuttonfun glfwSetMouseButtonCallback(GLFWwindow*, GLFWmousebuttonfun);
GLFWcursorposfun glfwSetCursorPosCallback(GLFWwindow*, GLFWcursorposfun);
GLFWcursorenterfun glfwSetCursorEnterCallback(GLFWwindow*, GLFWcursorenterfun);
GLFWscrollfun glfwSetScrollCallback(GLFWwindow*, GLFWscrollfun);
GLFWwindowposfun glfwSetWindowPosCallback(GLFWwindow*, GLFWwindowposfun);
GLFWwindowsizefun glfwSetWindowSizeCallback(GLFWwindow*, GLFWwindowsizefun);
GLFWwindowclosefun glfwSetWindowCloseCallback(GLFWwindow*, GLFWwindowclosefun);
GLFWwindowrefreshfun glfwSetWindowRefreshCallback(GLFWwindow*, GLFWwindowrefreshfun);
GLFWwindowfocusfun glfwSetWindowFocusCallback(GLFWwindow*, GLFWwindowfocusfun);
GLFWwindowiconifyfun glfwSetWindowIconifyCallback(GLFWwindow*, GLFWwindowiconifyfun);
GLFWwindowmaximizefun glfwSetWindowMaximizeCallback(GLFWwindow*, GLFWwindowmaximizefun);
GLFWframebuffersizefun glfwSetFramebufferSizeCallback(GLFWwindow*, GLFWframebuffersizefun);
GLFWwindowcontentscalefun glfwSetWindowContentScaleCallback(GLFWwindow*, GLFWwindowcontentscalefun);

version (Windows)
{
    void* glfwGetWin32Window(GLFWwindow*);
}
else version (OSX)
{
    void* glfwGetCocoaWindow(GLFWwindow*);
    void* glfwGetCocoaView(GLFWwindow*);
}
else version (linux)
{
    void* glfwGetX11Display();
    ulong glfwGetX11Window(GLFWwindow*);
    void* glfwGetWaylandDisplay();
    void* glfwGetWaylandWindow(GLFWwindow*);
}

// Generic values.
enum int GLFW_NO_ERROR = 0;
enum int GLFW_NOT_INITIALIZED = 0x00010001;
enum int GLFW_NO_CURRENT_CONTEXT = 0x00010002;
enum int GLFW_INVALID_ENUM = 0x00010003;
enum int GLFW_INVALID_VALUE = 0x00010004;
enum int GLFW_OUT_OF_MEMORY = 0x00010005;
enum int GLFW_API_UNAVAILABLE = 0x00010006;
enum int GLFW_VERSION_UNAVAILABLE = 0x00010007;
enum int GLFW_PLATFORM_ERROR = 0x00010008;
enum int GLFW_FORMAT_UNAVAILABLE = 0x00010009;
enum int GLFW_NO_WINDOW_CONTEXT = 0x0001000A;
enum int GLFW_FALSE = 0;
enum int GLFW_TRUE = 1;
enum int GLFW_RELEASE = 0;
enum int GLFW_PRESS = 1;
enum int GLFW_REPEAT = 2;
enum int GLFW_CONNECTED = 0x00040001;
enum int GLFW_DISCONNECTED = 0x00040002;
enum int GLFW_DONT_CARE = -1;

// Initialization hints and runtime platforms (GLFW 3.4+).
enum int GLFW_PLATFORM = 0x00050003;
enum int GLFW_ANY_PLATFORM = 0x00060000;
enum int GLFW_PLATFORM_WIN32 = 0x00060001;
enum int GLFW_PLATFORM_COCOA = 0x00060002;
enum int GLFW_PLATFORM_WAYLAND = 0x00060003;
enum int GLFW_PLATFORM_X11 = 0x00060004;
enum int GLFW_PLATFORM_NULL = 0x00060005;

// Window hints and attributes.
enum int GLFW_FOCUSED = 0x00020001;
enum int GLFW_ICONIFIED = 0x00020002;
enum int GLFW_RESIZABLE = 0x00020003;
enum int GLFW_VISIBLE = 0x00020004;
enum int GLFW_DECORATED = 0x00020005;
enum int GLFW_MAXIMIZED = 0x00020008;
enum int GLFW_HOVERED = 0x0002000B;
enum int GLFW_CLIENT_API = 0x00022001;
enum int GLFW_CONTEXT_VERSION_MAJOR = 0x00022002;
enum int GLFW_CONTEXT_VERSION_MINOR = 0x00022003;
enum int GLFW_CONTEXT_REVISION = 0x00022004;
enum int GLFW_CONTEXT_ROBUSTNESS = 0x00022005;
enum int GLFW_OPENGL_FORWARD_COMPAT = 0x00022006;
enum int GLFW_CONTEXT_DEBUG = 0x00022007;
enum int GLFW_OPENGL_DEBUG_CONTEXT = GLFW_CONTEXT_DEBUG;
enum int GLFW_OPENGL_PROFILE = 0x00022008;
enum int GLFW_CONTEXT_RELEASE_BEHAVIOR = 0x00022009;
enum int GLFW_CONTEXT_NO_ERROR = 0x0002200A;
enum int GLFW_CONTEXT_CREATION_API = 0x0002200B;
enum int GLFW_SAMPLES = 0x0002100D;
enum int GLFW_SRGB_CAPABLE = 0x0002100E;
enum int GLFW_DOUBLEBUFFER = 0x00021010;
enum int GLFW_NO_API = 0;
enum int GLFW_OPENGL_API = 0x00030001;
enum int GLFW_OPENGL_ES_API = 0x00030002;
enum int GLFW_OPENGL_ANY_PROFILE = 0;
enum int GLFW_OPENGL_CORE_PROFILE = 0x00032001;
enum int GLFW_OPENGL_COMPAT_PROFILE = 0x00032002;
enum int GLFW_NO_ROBUSTNESS = 0;
enum int GLFW_NO_RESET_NOTIFICATION = 0x00031001;
enum int GLFW_LOSE_CONTEXT_ON_RESET = 0x00031002;
enum int GLFW_ANY_RELEASE_BEHAVIOR = 0;
enum int GLFW_RELEASE_BEHAVIOR_FLUSH = 0x00035001;
enum int GLFW_RELEASE_BEHAVIOR_NONE = 0x00035002;
enum int GLFW_NATIVE_CONTEXT_API = 0x00036001;
enum int GLFW_EGL_CONTEXT_API = 0x00036002;
enum int GLFW_OSMESA_CONTEXT_API = 0x00036003;

// Input modes.
enum int GLFW_CURSOR = 0x00033001;
enum int GLFW_LOCK_KEY_MODS = 0x00033004;
enum int GLFW_CURSOR_NORMAL = 0x00034001;
enum int GLFW_CURSOR_HIDDEN = 0x00034002;
enum int GLFW_CURSOR_DISABLED = 0x00034003;

// Modifier masks.
enum int GLFW_MOD_SHIFT = 0x0001;
enum int GLFW_MOD_CONTROL = 0x0002;
enum int GLFW_MOD_ALT = 0x0004;
enum int GLFW_MOD_SUPER = 0x0008;
enum int GLFW_MOD_CAPS_LOCK = 0x0010;
enum int GLFW_MOD_NUM_LOCK = 0x0020;

// Printable keys.
enum int GLFW_KEY_UNKNOWN = -1;
enum int GLFW_KEY_SPACE = 32;
enum int GLFW_KEY_APOSTROPHE = 39;
enum int GLFW_KEY_COMMA = 44;
enum int GLFW_KEY_MINUS = 45;
enum int GLFW_KEY_PERIOD = 46;
enum int GLFW_KEY_SLASH = 47;
enum int GLFW_KEY_0 = 48;
enum int GLFW_KEY_1 = 49;
enum int GLFW_KEY_2 = 50;
enum int GLFW_KEY_3 = 51;
enum int GLFW_KEY_4 = 52;
enum int GLFW_KEY_5 = 53;
enum int GLFW_KEY_6 = 54;
enum int GLFW_KEY_7 = 55;
enum int GLFW_KEY_8 = 56;
enum int GLFW_KEY_9 = 57;
enum int GLFW_KEY_SEMICOLON = 59;
enum int GLFW_KEY_EQUAL = 61;
enum int GLFW_KEY_A = 65;
enum int GLFW_KEY_B = 66;
enum int GLFW_KEY_C = 67;
enum int GLFW_KEY_D = 68;
enum int GLFW_KEY_E = 69;
enum int GLFW_KEY_F = 70;
enum int GLFW_KEY_G = 71;
enum int GLFW_KEY_H = 72;
enum int GLFW_KEY_I = 73;
enum int GLFW_KEY_J = 74;
enum int GLFW_KEY_K = 75;
enum int GLFW_KEY_L = 76;
enum int GLFW_KEY_M = 77;
enum int GLFW_KEY_N = 78;
enum int GLFW_KEY_O = 79;
enum int GLFW_KEY_P = 80;
enum int GLFW_KEY_Q = 81;
enum int GLFW_KEY_R = 82;
enum int GLFW_KEY_S = 83;
enum int GLFW_KEY_T = 84;
enum int GLFW_KEY_U = 85;
enum int GLFW_KEY_V = 86;
enum int GLFW_KEY_W = 87;
enum int GLFW_KEY_X = 88;
enum int GLFW_KEY_Y = 89;
enum int GLFW_KEY_Z = 90;
enum int GLFW_KEY_LEFT_BRACKET = 91;
enum int GLFW_KEY_BACKSLASH = 92;
enum int GLFW_KEY_RIGHT_BRACKET = 93;
enum int GLFW_KEY_GRAVE_ACCENT = 96;
enum int GLFW_KEY_WORLD_1 = 161;
enum int GLFW_KEY_WORLD_2 = 162;

// Function and keypad keys.
enum int GLFW_KEY_ESCAPE = 256;
enum int GLFW_KEY_ENTER = 257;
enum int GLFW_KEY_TAB = 258;
enum int GLFW_KEY_BACKSPACE = 259;
enum int GLFW_KEY_INSERT = 260;
enum int GLFW_KEY_DELETE = 261;
enum int GLFW_KEY_RIGHT = 262;
enum int GLFW_KEY_LEFT = 263;
enum int GLFW_KEY_DOWN = 264;
enum int GLFW_KEY_UP = 265;
enum int GLFW_KEY_PAGE_UP = 266;
enum int GLFW_KEY_PAGE_DOWN = 267;
enum int GLFW_KEY_HOME = 268;
enum int GLFW_KEY_END = 269;
enum int GLFW_KEY_CAPS_LOCK = 280;
enum int GLFW_KEY_SCROLL_LOCK = 281;
enum int GLFW_KEY_NUM_LOCK = 282;
enum int GLFW_KEY_PRINT_SCREEN = 283;
enum int GLFW_KEY_PAUSE = 284;
enum int GLFW_KEY_F1 = 290;
enum int GLFW_KEY_F2 = 291;
enum int GLFW_KEY_F3 = 292;
enum int GLFW_KEY_F4 = 293;
enum int GLFW_KEY_F5 = 294;
enum int GLFW_KEY_F6 = 295;
enum int GLFW_KEY_F7 = 296;
enum int GLFW_KEY_F8 = 297;
enum int GLFW_KEY_F9 = 298;
enum int GLFW_KEY_F10 = 299;
enum int GLFW_KEY_F11 = 300;
enum int GLFW_KEY_F12 = 301;
enum int GLFW_KEY_F13 = 302;
enum int GLFW_KEY_F14 = 303;
enum int GLFW_KEY_F15 = 304;
enum int GLFW_KEY_F16 = 305;
enum int GLFW_KEY_F17 = 306;
enum int GLFW_KEY_F18 = 307;
enum int GLFW_KEY_F19 = 308;
enum int GLFW_KEY_F20 = 309;
enum int GLFW_KEY_F21 = 310;
enum int GLFW_KEY_F22 = 311;
enum int GLFW_KEY_F23 = 312;
enum int GLFW_KEY_F24 = 313;
enum int GLFW_KEY_F25 = 314;
enum int GLFW_KEY_KP_0 = 320;
enum int GLFW_KEY_KP_1 = 321;
enum int GLFW_KEY_KP_2 = 322;
enum int GLFW_KEY_KP_3 = 323;
enum int GLFW_KEY_KP_4 = 324;
enum int GLFW_KEY_KP_5 = 325;
enum int GLFW_KEY_KP_6 = 326;
enum int GLFW_KEY_KP_7 = 327;
enum int GLFW_KEY_KP_8 = 328;
enum int GLFW_KEY_KP_9 = 329;
enum int GLFW_KEY_KP_DECIMAL = 330;
enum int GLFW_KEY_KP_DIVIDE = 331;
enum int GLFW_KEY_KP_MULTIPLY = 332;
enum int GLFW_KEY_KP_SUBTRACT = 333;
enum int GLFW_KEY_KP_ADD = 334;
enum int GLFW_KEY_KP_ENTER = 335;
enum int GLFW_KEY_KP_EQUAL = 336;
enum int GLFW_KEY_LEFT_SHIFT = 340;
enum int GLFW_KEY_LEFT_CONTROL = 341;
enum int GLFW_KEY_LEFT_ALT = 342;
enum int GLFW_KEY_LEFT_SUPER = 343;
enum int GLFW_KEY_RIGHT_SHIFT = 344;
enum int GLFW_KEY_RIGHT_CONTROL = 345;
enum int GLFW_KEY_RIGHT_ALT = 346;
enum int GLFW_KEY_RIGHT_SUPER = 347;
enum int GLFW_KEY_MENU = 348;
