#include "ogl.h"

#include <glad/glad.h>
#include <stdio.h>
#include <stdlib.h>

#include <xtb_os/os.h>
#include <xtb_core/thread_context.h>
#include <xtb_core/contract.h>

#include "glad/src/glad.c"

bool ogl_load_gl(XTBLoadProc load_proc)
{
    return gladLoadGLLoader(load_proc) != 0;
}

void log_shader_compile_errors(const char *ns, unsigned int id)
{
    int success;
    glGetShaderiv(id, GL_COMPILE_STATUS, &success);

    if (!success)
    {
        char info_log[512];
        glGetShaderInfoLog(id, 512, NULL, info_log);
        fprintf(stderr, "ERROR:::%s::compilation_failed: %s\n", ns, info_log);
    }
}

void log_shader_program_link_errors(const char *ns, unsigned int id)
{
    int success;
    glGetProgramiv(id, GL_LINK_STATUS, &success);

    if (!success)
    {
        char info_log[512];
        glGetProgramInfoLog(id, 512, NULL, info_log);
        fprintf(stderr, "ERROR:::%s::linking_failed: %s\n", ns, info_log);
    }
}

Shader load_shader_from_memory(const char *ns, const char *src, int shader_type)
{
    Shader id = glCreateShader(shader_type);
    glShaderSource(id, 1, (const char * const *)&src, NULL);
    glCompileShader(id);
    log_shader_compile_errors(ns, id);

    return id;
}

Shader load_shader_from_file(const char *ns, String filepath, int shader_type)
{
    TempArena scratch = scratch_begin_no_conflicts();
    String shader_content = os_read_entire_file(&scratch.arena->allocator, filepath);
    Assert(str_is_valid(shader_content));

    Shader id = load_shader_from_memory(ns, (char *)shader_content.str, shader_type);
    scratch_end(scratch);

    return id;
}

Shader load_vertex_shader_from_file(const char *ns, String filepath)
{
    return load_shader_from_file(ns, filepath, GL_VERTEX_SHADER);
}

Shader load_fragment_shader_from_file(const char *ns, String filepath)
{
    return load_shader_from_file(ns, filepath, GL_FRAGMENT_SHADER);
}

ShaderProgramID create_shader_program_from_descriptors(const char *ns, Shader vs_id, Shader fs_id)
{
    ShaderProgramID id = glCreateProgram();
    glAttachShader(id, vs_id);
    glAttachShader(id, fs_id);
    glLinkProgram(id);
    log_shader_program_link_errors(ns, id);

    return id;
}

ShaderProgramID load_shader_program_from_files(const char *ns, String vertex_filepath, String fragment_filepath)
{
    TempArena scratch = scratch_begin_no_conflicts();

    String vertex_src = os_read_entire_file(&scratch.arena->allocator, vertex_filepath);
    Assert(str_is_valid(vertex_src));

    String fragment_src = os_read_entire_file(&scratch.arena->allocator, fragment_filepath);
    Assert(str_is_valid(fragment_src));

    ShaderProgramID program = load_shader_program_from_memory(ns, (char*)vertex_src.str, (char*)fragment_src.str);

    scratch_end(scratch);
    return program;
}

ShaderProgramID load_shader_program_from_memory(const char *ns, const char *vertex_src, const char *fragment_src)
{
    char shader_ns[512];

    snprintf(shader_ns, 512, "%s_vertex_shader", ns);
    Shader vertex_shader = load_shader_from_memory(shader_ns, vertex_src, GL_VERTEX_SHADER);

    snprintf(shader_ns, 512, "%s_fragment_shader", ns);
    Shader fragment_shader = load_shader_from_memory(shader_ns, fragment_src, GL_FRAGMENT_SHADER);

    ShaderProgramID id = create_shader_program_from_descriptors(ns, vertex_shader, fragment_shader);

    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);

    return id;
}

void toggle_wireframe(void)
{
    GLint polygonMode[2];
    glGetIntegerv(GL_POLYGON_MODE, polygonMode);
    if (polygonMode[1] == GL_LINE)
    {
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    }
    else
    {
        glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    }
}

