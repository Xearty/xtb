# OpenGL

`import xtb.opengl;` provides BetterC desktop OpenGL declarations through 4.6
and a process-global runtime loader. It is intended for XTB's renderer and for
applications that want a ready binding; applications remain free to use a
different OpenGL binding with `xtb.window.opengl_proc_address`.

Create and make an OpenGL context current before loading functions:

```d
import xtb.opengl;
import xtb.window;
import xtb.window.opengl;

OpenGLConfig glConfig;
auto windowResult = system.create_opengl_window(WindowConfig.init, glConfig);
if (windowResult.isErr)
    return 1;
Window* window = windowResult.take();
scope (exit) window.deinit();

window.make_context_current();
if (loadOpenGL() < GLSupport.gl33)
    return 1;
scope (exit) unloadOpenGL();

glClearColor(0.05f, 0.05f, 0.05f, 1.0f);
glClear(GL_COLOR_BUFFER_BIT);
window.swap_buffers();
```

The declarations are configured through OpenGL 4.6, but `loadOpenGL()` loads
only versions supported by the current context. The initial renderer baseline
is OpenGL 3.3 core. `GL_ARB_debug_output`, `GL_ARB_indirect_parameters`, and
`GL_ARB_texture_filter_anisotropic` are also enabled when drivers advertise
them. Loading may allocate while collecting diagnostic information.

The loader supports XTB's ordinary WGL, GLX, CGL, and Wayland-EGL paths. It
does not load functions for an OSMesa context or an explicitly selected EGL
context in a non-Wayland session; `xtb.window` retains those context-creation
options for applications using another loader.

DUB supplies the binding's compile-time feature identifiers automatically.
Consumers compiling directly against a composed archive must pass `GL_46`,
`GL_ARB_debug_output`, `GL_ARB_indirect_parameters`, and
`GL_ARB_texture_filter_anisotropic` as D version identifiers as well.

The binding is based on vendored, unmodified BindBC-OpenGL and BindBC-Loader
sources. See [`vendor/UPSTREAM.md`](../../vendor/UPSTREAM.md) for versions and
licenses.
