#include "material.h"

#include <xtb_ogl/ogl.h>
#include <xtb_core/thread_context.h>

namespace xtb
{

static inline MaterialParamKind opengl_type_to_material_param_type(i32 gl_type)
{
    switch (gl_type)
    {
        case GL_FLOAT: return MATERIAL_PARAM_FLOAT;
        case GL_FLOAT_VEC2: return MATERIAL_PARAM_FLOAT_VEC2;
        case GL_FLOAT_VEC3: return MATERIAL_PARAM_FLOAT_VEC3;
        case GL_FLOAT_VEC4: return MATERIAL_PARAM_FLOAT_VEC4;
        case GL_FLOAT_MAT2: return MATERIAL_PARAM_FLOAT_MAT2;
        case GL_FLOAT_MAT3: return MATERIAL_PARAM_FLOAT_MAT3;
        case GL_FLOAT_MAT4: return MATERIAL_PARAM_FLOAT_MAT4;
    }

    return MATERIAL_PARAM_NONE;
}

Array<MaterialParamDesc> material_params_from_program(Allocator *allocator, ShaderProgramID program)
{
    auto params = Array<MaterialParamDesc>::init(allocator);

    GLint uniform_count = 0;
    glGetProgramiv(program, GL_ACTIVE_UNIFORMS, &uniform_count);

    if (uniform_count > 0)
    {
        params.reserve(uniform_count);

        GLint max_name_len = 0;
        glGetProgramiv(program, GL_ACTIVE_UNIFORM_MAX_LENGTH, &max_name_len);

        TempArena scratch = scratch_begin_conflict(allocator);

        u8 *uniform_name = AllocateBytes(&scratch.arena->allocator, max_name_len + 1);

        for (GLint uniform_index = 0; uniform_index < uniform_count; ++uniform_index)
        {
            GLsizei length = 0;
            GLsizei count = 0;
            GLenum type = GL_NONE;

            glGetActiveUniform(program, uniform_index, max_name_len, &length, &count, &type, (GLchar*)uniform_name);

            String param_name = String(uniform_name, length);

            if (uniform_is_material_param(param_name))
            {
                MaterialParamDesc param = {
                    .name = param_name.copy(allocator),
                    .kind = opengl_type_to_material_param_type(type),
                    .uniform_location = glGetUniformLocation(program, (GLchar*)uniform_name),
                    .array_size = count,
                };

                params.append(param);
            }
        }
        scratch_end(scratch);
    }

    return params;
}

void material_apply(Material *material)
{
    glUseProgram(material->templ->program.id);

    for (i32 i = 0; i < material->templ->params.size(); ++i)
    {
        const MaterialParamDesc *desc = &material->templ->params[i];
        const MaterialParamValue *value = &material->values[i];

        switch (desc->kind)
        {
            case MATERIAL_PARAM_FLOAT:
            {
                glUniform1f(desc->uniform_location, value->as.f32_);
            } break;

            case MATERIAL_PARAM_FLOAT_VEC2:
            {
                glUniform2fv(desc->uniform_location, 1, &value->as.vec2_.x);
            } break;

            case MATERIAL_PARAM_FLOAT_VEC3:
            {
                glUniform3fv(desc->uniform_location, 1, &value->as.vec3_.x);
            } break;

            case MATERIAL_PARAM_FLOAT_VEC4:
            {
                glUniform4fv(desc->uniform_location, 1, &value->as.vec4_.x);
            } break;

            case MATERIAL_PARAM_FLOAT_MAT2:
            {
                glUniformMatrix2fv(desc->uniform_location, 1, GL_FALSE, &value->as.mat2_.m00);
            } break;

            case MATERIAL_PARAM_FLOAT_MAT3:
            {
                glUniformMatrix3fv(desc->uniform_location, 1, GL_FALSE, &value->as.mat3_.m00);
            } break;

            case MATERIAL_PARAM_FLOAT_MAT4:
            {
                glUniformMatrix4fv(desc->uniform_location, 1, GL_FALSE, &value->as.mat4_.m00);
            } break;

            case MATERIAL_PARAM_NONE: break;
        }
    }
}

}
