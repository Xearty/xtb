#include "material.h"

#include <xtb_core/thread_context.h>
#include <xtb_ogl/ogl.h>

#include "opengl_material.cpp"

namespace xtb
{

static void material_set_defaults(Material *mat)
{
    Array<MaterialParamDesc>& params = mat->templ->params;

    for (i32 i = 0; i < params.size(); ++i)
    {
        switch (params[i].kind)
        {
            case MATERIAL_PARAM_FLOAT: material_set_float_by_index(mat, i, 0.0f); break;

            case MATERIAL_PARAM_FLOAT_VEC2: material_set_vec2_by_index(mat, i, v2s(0.0f)); break;
            case MATERIAL_PARAM_FLOAT_VEC3: material_set_vec3_by_index(mat, i, v3s(0.0f)); break;
            case MATERIAL_PARAM_FLOAT_VEC4: material_set_vec4_by_index(mat, i, v4s(0.0f)); break;

            case MATERIAL_PARAM_FLOAT_MAT2: material_set_mat2_by_index(mat, i, I2()); break;
            case MATERIAL_PARAM_FLOAT_MAT3: material_set_mat3_by_index(mat, i, I3()); break;
            case MATERIAL_PARAM_FLOAT_MAT4: material_set_mat4_by_index(mat, i, I4()); break;

            case MATERIAL_PARAM_NONE: break;
        }
    }
}

i32 material_find_param(const MaterialTemplate *t, const char *name)
{
    for (i32 i = 0; i < t->params.size(); ++i)
    {
        const MaterialParamDesc *desc = &t->params[i];
        if (desc->name == String::from_cstr(name))
        {
            return i;
        }
    }

    return -1;
}

/****************************************************************
 * Index Setters
****************************************************************/
void material_set_float_by_index(Material *mat, i32 index, f32 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params[index].kind == MATERIAL_PARAM_FLOAT_VEC2);

    mat->values[index].kind = MATERIAL_PARAM_FLOAT;
    mat->values[index].as.f32_ = val;
}

void material_set_vec2_by_index(Material *mat, i32 index, vec2 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params[index].kind == MATERIAL_PARAM_FLOAT_VEC2);

    mat->values[index].kind = MATERIAL_PARAM_FLOAT_VEC2;
    mat->values[index].as.vec2_ = val;
}

void material_set_vec3_by_index(Material *mat, i32 index, vec3 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params[index].kind == MATERIAL_PARAM_FLOAT_VEC3);

    mat->values[index].kind = MATERIAL_PARAM_FLOAT_VEC3;
    mat->values[index].as.vec3_ = val;
}

void material_set_vec4_by_index(Material *mat, i32 index, vec4 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params[index].kind == MATERIAL_PARAM_FLOAT_VEC4);

    mat->values[index].kind = MATERIAL_PARAM_FLOAT_VEC4;
    mat->values[index].as.vec4_ = val;
}

void material_set_mat2_by_index(Material *mat, i32 index, mat2 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params[index].kind == MATERIAL_PARAM_FLOAT_MAT2);

    mat->values[index].kind = MATERIAL_PARAM_FLOAT_MAT2;
    mat->values[index].as.mat2_ = val;
}

void material_set_mat3_by_index(Material *mat, i32 index, mat3 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params[index].kind == MATERIAL_PARAM_FLOAT_MAT3);

    mat->values[index].kind = MATERIAL_PARAM_FLOAT_MAT3;
    mat->values[index].as.mat3_ = val;
}

void material_set_mat4_by_index(Material *mat, i32 index, mat4 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params[index].kind == MATERIAL_PARAM_FLOAT_MAT4);

    mat->values[index].kind = MATERIAL_PARAM_FLOAT_MAT4;
    mat->values[index].as.mat4_ = val;
}

/****************************************************************
 * String Setters
****************************************************************/
void material_set_float(Material *mat, const char *name, f32 val)
{
    i32 index = material_find_param(mat->templ, name);
    material_set_float_by_index(mat, index, val);
}

void material_set_vec2(Material *mat, const char *name, vec2 val)
{
    i32 index = material_find_param(mat->templ, name);
    material_set_vec2_by_index(mat, index, val);
}

void material_set_vec4(Material *mat, const char *name, vec4 val)
{
    i32 index = material_find_param(mat->templ, name);
    material_set_vec4_by_index(mat, index, val);
}

void material_set_vec3(Material *mat, const char *name, vec3 val)
{
    i32 index = material_find_param(mat->templ, name);
    material_set_vec3_by_index(mat, index, val);
}

void material_set_mat2(Material *mat, const char *name, mat2 val)
{
    i32 index = material_find_param(mat->templ, name);
    material_set_mat2_by_index(mat, index, val);
}

void material_set_mat3(Material *mat, const char *name, mat3 val)
{
    i32 index = material_find_param(mat->templ, name);
    material_set_mat3_by_index(mat, index, val);
}

void material_set_mat4(Material *mat, const char *name, mat4 val)
{
    i32 index = material_find_param(mat->templ, name);
    material_set_mat4_by_index(mat, index, val);
}
/****************************************************************
 * Constructors
****************************************************************/
void material_template_init(Allocator *allocator, ShaderProgram program, MaterialTemplate *templ)
{
    templ->program = program;
    templ->params = material_params_from_program(allocator, program.id);;
}

Material material_instance_create(Allocator *allocator, MaterialTemplate *templ)
{
    Material mat = {};
    mat.templ = templ;
    mat.values = Array<MaterialParamValue>::init(allocator); // TODO: Make init_with_size
    mat.values.resize(templ->params.size());
    material_set_defaults(&mat);
    return mat;
}

Material material_copy(Allocator *allocator, Material *m)
{
    Material res = {};
    res.templ = m->templ;
    res.values = Array<MaterialParamValue>::init(allocator);
    for (isize i = 0; i < m->values.size(); ++i)
    {
        res.values.append(m->values[i]);
    }
    // array_init(&res.values, allocator);
    // array_append(&res.values, m->values.data, m->values.count);
    return res;
}

}
