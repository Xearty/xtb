#include "material.h"

#include <xtb_ogl/ogl.h>
#include <xtb_core/thread_context.h>

MaterialParamDescArray material_params_from_program(Allocator *allocator, ShaderProgram program)
{
    MaterialParamDescArray params = make_array(allocator);;

    GLint uniform_count = 0;
    glGetProgramiv(program, GL_ACTIVE_UNIFORMS, &uniform_count);

    if (uniform_count > 0)
    {
        array_reserve(&params, uniform_count);

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

            MaterialParamDesc param = {};
            param.name = str_copy(allocator, str_from(uniform_name, length));
            param.kind = type;
            param.uniform_location = glGetUniformLocation(program, (GLchar*)uniform_name);
            param.array_size = count;

            array_push(&params, param);
        }

        scratch_end(scratch);
    }

    return params;
}

static void material_apply(Material *material)
{
    glUseProgram(material->templ->program);

    for (i32 i = 0; i < material->templ->params.count; ++i)
    {
        const MaterialParamDesc *desc = &material->templ->params.data[i];
        const MaterialParamValue *value = &material->values.data[i];

        switch (desc->kind)
        {
            case GL_FLOAT:
            {
                glUniform1f(desc->uniform_location, value->as.f32);
            } break;

            case GL_FLOAT_VEC2:
            {
                glUniform2fv(desc->uniform_location, 1, &value->as.vec2.x);
            } break;

            case GL_FLOAT_VEC3:
            {
                glUniform3fv(desc->uniform_location, 1, &value->as.vec3.x);
            } break;

            case GL_FLOAT_VEC4:
            {
                glUniform4fv(desc->uniform_location, 1, &value->as.vec4.x);
            } break;

            case GL_FLOAT_MAT2:
            {
                glUniformMatrix2fv(desc->uniform_location, 1, GL_FALSE, &value->as.mat2.m00);
            } break;

            case GL_FLOAT_MAT3:
            {
                glUniformMatrix3fv(desc->uniform_location, 1, GL_FALSE, &value->as.mat3.m00);
            } break;

            case GL_FLOAT_MAT4:
            {
                glUniformMatrix4fv(desc->uniform_location, 1, GL_FALSE, &value->as.mat4.m00);
            } break;
        }
    }
}
