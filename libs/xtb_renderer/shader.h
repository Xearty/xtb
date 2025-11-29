#ifndef XTB_RENDERER_SHADER_H
#define XTB_RENDERER_SHADER_H

#include <xtb_core/core.h>
#include <xtb_ogl/ogl.h>

typedef struct ShaderProgram
{
    u32 id;

    i32 model_location;
    i32 view_location;
    i32 projection_location;

    i32 time_location;
} ShaderProgram;


static inline ShaderProgram create_shader_program(const char *ns, const char *vs, const char *fs)
{
    u32 id = load_shader_program_from_memory(ns, vs, fs);

    ShaderProgram result = {
        .id = id,
        .model_location = glGetUniformLocation(id, "model"),
        .view_location = glGetUniformLocation(id, "view"),
        .projection_location = glGetUniformLocation(id, "projection"),
        .time_location = glGetUniformLocation(id, "u_Time"),
    };

    return result;
}

#endif // XTB_RENDERER_SHADER_H
