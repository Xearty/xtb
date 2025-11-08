#include "ogl.h"

#include <glad/glad.h>
#include <stdio.h>
#include <stdlib.h>

#include <xtb_os/os.h>
#include <xtb_core/thread_context.h>

#include "glad/src/glad.c"

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

Shader load_shader_from_file(const char *ns, XTB_String8 filepath, int shader_type)
{
    XTB_Temp_Arena scratch = xtb_scratch_begin_no_conflicts();
    XTB_String8 shader_content = xtb_os_read_entire_file(&scratch.arena->allocator, filepath);

    XTB_ASSERT(xtb_str8_is_valid(shader_content));

    Shader id = glCreateShader(shader_type);
    glShaderSource(id, 1, (const char * const *)&shader_content.str, NULL);

    xtb_scratch_end(scratch);

    glCompileShader(id);
    log_shader_compile_errors(ns, id);

    return id;
}

Shader load_vertex_shader_from_file(const char *ns, XTB_String8 filepath)
{
    return load_shader_from_file(ns, filepath, GL_VERTEX_SHADER);
}

Shader load_fragment_shader_from_file(const char *ns, XTB_String8 filepath)
{
    return load_shader_from_file(ns, filepath, GL_FRAGMENT_SHADER);
}

ShaderProgram create_shader_program_from_descriptors(const char *ns, Shader vs_id, Shader fs_id)
{
    ShaderProgram id = glCreateProgram();
    glAttachShader(id, vs_id);
    glAttachShader(id, fs_id);
    glLinkProgram(id);
    log_shader_program_link_errors(ns, id);

    return id;
}

ShaderProgram load_shader_program_from_files(const char *ns, XTB_String8 vertex_filepath, XTB_String8 fragment_filepath)
{
    char shader_ns[512];

    snprintf(shader_ns, 512, "%s_vertex_shader", ns);
    Shader vertex_shader = load_vertex_shader_from_file(shader_ns, vertex_filepath);

    snprintf(shader_ns, 512, "%s_fragment_shader", ns);
    Shader fragment_shader = load_fragment_shader_from_file(shader_ns, fragment_filepath);

    ShaderProgram id = create_shader_program_from_descriptors(ns, vertex_shader, fragment_shader);

    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);

    return id;
}

