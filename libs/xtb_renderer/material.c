#include "material.h"

#include <xtb_core/thread_context.h>
#include <xtb_ogl/ogl.h>

static void material_set_defaults(Material *mat)
{
    MaterialParamDescArray *params = &mat->templ->params;
    MaterialParamValueArray *values = &mat->values;

    for (i32 i = 0; i < params->count; ++i)
    {
        MaterialParamDesc *param = &params->data[i];
        MaterialParamValue *value = &values->data[i];

        switch (param->kind)
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
    for (i32 i = 0; i < t->params.count; ++i)
    {
        MaterialParamDesc *desc = &t->params.data[i];
        if (str_eq_cstring(desc->name, name))
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
    Assert(mat->templ->params.data[index].kind == MATERIAL_PARAM_FLOAT_VEC2);

    mat->values.data[index].kind = MATERIAL_PARAM_FLOAT;
    mat->values.data[index].as.f32 = val;
}

void material_set_vec2_by_index(Material *mat, i32 index, vec2 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params.data[index].kind == MATERIAL_PARAM_FLOAT_VEC2);

    mat->values.data[index].kind = MATERIAL_PARAM_FLOAT_VEC2;
    mat->values.data[index].as.vec2 = val;
}

void material_set_vec3_by_index(Material *mat, i32 index, vec3 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params.data[index].kind == MATERIAL_PARAM_FLOAT_VEC3);

    mat->values.data[index].kind = MATERIAL_PARAM_FLOAT_VEC3;
    mat->values.data[index].as.vec3 = val;
}

void material_set_vec4_by_index(Material *mat, i32 index, vec4 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params.data[index].kind == MATERIAL_PARAM_FLOAT_VEC4);

    mat->values.data[index].kind = MATERIAL_PARAM_FLOAT_VEC4;
    mat->values.data[index].as.vec4 = val;
}

void material_set_mat2_by_index(Material *mat, i32 index, mat2 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params.data[index].kind == MATERIAL_PARAM_FLOAT_MAT2);

    mat->values.data[index].kind = MATERIAL_PARAM_FLOAT_MAT2;
    mat->values.data[index].as.mat2 = val;
}

void material_set_mat3_by_index(Material *mat, i32 index, mat3 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params.data[index].kind == MATERIAL_PARAM_FLOAT_MAT3);

    mat->values.data[index].kind = MATERIAL_PARAM_FLOAT_MAT3;
    mat->values.data[index].as.mat3 = val;
}

void material_set_mat4_by_index(Material *mat, i32 index, mat4 val)
{
    Assert(index >= 0);
    Assert(mat->templ->params.data[index].kind == MATERIAL_PARAM_FLOAT_MAT4);

    mat->values.data[index].kind = MATERIAL_PARAM_FLOAT_MAT4;
    mat->values.data[index].as.mat4 = val;
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
Material material_instance_create(Allocator *allocator, MaterialTemplate *templ)
{
    Material mat = {};
    mat.templ = templ;
    array_init(&mat.values, allocator);
    array_resize(&mat.values, templ->params.count);
    material_set_defaults(&mat);
    return mat;
}

Material material_copy(Allocator *allocator, Material *m)
{
    Material res = {};
    res.templ = m->templ;
    array_init(&res.values, allocator);
    array_append(&res.values, m->values.data, m->values.count);
    return res;
}

