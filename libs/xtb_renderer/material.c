#include "material.h"

#include <xtb_core/thread_context.h>
#include <xtb_ogl/ogl.h>

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

void material_set_vec4(Material *mat, const char *name, vec4 val)
{
    i32 idx = material_find_param(mat->templ, name);
    Assert(idx >= 0);
    Assert(mat->templ->params.data[idx].kind == GL_FLOAT_VEC4);

    mat->values.data[idx].kind = GL_FLOAT_VEC4;
    mat->values.data[idx].as.vec4 = val;
}

void material_set_vec2(Material *mat, const char *name, vec2 val)
{
    i32 idx = material_find_param(mat->templ, name);
    Assert(idx >= 0);
    Assert(mat->templ->params.data[idx].kind == GL_FLOAT_VEC2);

    mat->values.data[idx].kind = GL_FLOAT_VEC2;
    mat->values.data[idx].as.vec2 = val;
}

void material_set_vec3(Material *mat, const char *name, vec3 val)
{
    i32 idx = material_find_param(mat->templ, name);
    Assert(idx >= 0);
    Assert(mat->templ->params.data[idx].kind == GL_FLOAT_VEC3);

    mat->values.data[idx].kind = GL_FLOAT_VEC3;
    mat->values.data[idx].as.vec3 = val;
}

void material_set_mat4(Material *mat, const char *name, mat4 val)
{
    i32 idx = material_find_param(mat->templ, name);
    Assert(idx >= 0);
    Assert(mat->templ->params.data[idx].kind == GL_FLOAT_MAT4);

    mat->values.data[idx].kind = GL_FLOAT_MAT4;
    mat->values.data[idx].as.mat4 = val;
}

Material material_instance_create(Allocator *allocator, MaterialTemplate *templ)
{
    Material mat = {};
    mat.templ = templ;
    array_init(&mat.values, allocator);
    array_resize(&mat.values, templ->params.count);

    return mat;
}

Material material_copy(Material *m)
{
    Material res = {};
    res.templ = m->templ;
    array_init(&res.values, allocator_get_static());
    array_append(&res.values, m->values.data, m->values.count);
    return res;
}

