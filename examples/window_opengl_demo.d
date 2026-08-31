module examples.window_opengl_demo;

import xtb.allocators.malloc : mallocAllocator;
import xtb.fmt : formatln;
import xtb.opengl;
import xtb.thread_context : ThreadContextScope;
import xtb.types : String;
import xtb.window;
import xtb.window.opengl;

private enum vertexShaderSource = `#version 330 core
out vec3 vertexColor;

const vec2 positions[3] = vec2[3](
    vec2( 0.0,  0.6),
    vec2(-0.6, -0.6),
    vec2( 0.6, -0.6)
);

const vec3 colors[3] = vec3[3](
    vec3(1.0, 0.2, 0.2),
    vec3(0.2, 1.0, 0.2),
    vec3(0.2, 0.4, 1.0)
);

void main()
{
    gl_Position = vec4(positions[gl_VertexID], 0.0, 1.0);
    vertexColor = colors[gl_VertexID];
}
`;

private enum fragmentShaderSource = `#version 330 core
in vec3 vertexColor;
out vec4 fragmentColor;

void main()
{
    fragmentColor = vec4(vertexColor, 1.0);
}
`;

private GLuint compileShader(GLenum kind, scope String source) nothrow @nogc
{
    GLuint shader = glCreateShader(kind);
    const(GLchar)* sourcePointer = source.ptr;
    const sourceLength = cast(GLint) source.length;
    glShaderSource(shader, 1, &sourcePointer, &sourceLength);
    glCompileShader(shader);

    GLint compiled;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled == 0)
    {
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

private GLuint createTriangleProgram() nothrow @nogc
{
    GLuint vertexShader = compileShader(GL_VERTEX_SHADER, vertexShaderSource);
    if (vertexShader == 0)
        return 0;

    GLuint fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentShaderSource);
    if (fragmentShader == 0)
    {
        glDeleteShader(vertexShader);
        return 0;
    }

    GLuint program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);

    GLint linked;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (linked == 0)
    {
        glDeleteProgram(program);
        return 0;
    }
    return program;
}

extern (C) int main() nothrow @nogc
{
    ThreadContextScope threadContext = ThreadContextScope.acquire();

    auto systemResult = WindowSystem.create(mallocAllocator());
    if (systemResult.isErr)
    {
        const error = systemResult.error;
        formatln!"Window system creation failed: kind={}, backend={}"(
            cast(uint) error.kind,
            error.backend_code,
        );
        return 1;
    }
    WindowSystem* system = systemResult.take();
    scope (exit) system.deinit();

    WindowConfig windowConfig = WindowConfig(
        width: 800,
        height: 600,
        title: "XTB OpenGL",
    );

    auto windowResult = system.create_opengl_window(windowConfig);
    if (windowResult.isErr)
    {
        const error = windowResult.error;
        formatln!"OpenGL window creation failed: kind={}, backend={}"(
            cast(uint) error.kind,
            error.backend_code,
        );
        return 1;
    }
    Window* window = windowResult.take();
    scope (exit) window.deinit();

    window.make_context_current();
    window.set_swap_interval(1);

    const support = loadOpenGL();
    scope (exit) unloadOpenGL();
    if (support < GLSupport.gl33)
    {
        formatln!"OpenGL loading failed: status={}"(cast(int) support);
        return 1;
    }

    GLuint program = createTriangleProgram();
    if (program == 0)
    {
        formatln!"Failed to create the triangle shader program"();
        return 1;
    }
    scope (exit) glDeleteProgram(program);

    GLuint vertexArray;
    glGenVertexArrays(1, &vertexArray);
    scope (exit) glDeleteVertexArrays(1, &vertexArray);

    glUseProgram(program);
    glBindVertexArray(vertexArray);

    while (!window.should_close())
    {
        system.poll_events();
        if (window.key_pressed(Key.escape))
            window.request_close();

        const framebufferSize = window.framebuffer_size();
        glViewport(0, 0, framebufferSize.width, framebufferSize.height);
        glClearColor(0.08f, 0.12f, 0.18f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        window.swap_buffers();
    }

    return 0;
}
