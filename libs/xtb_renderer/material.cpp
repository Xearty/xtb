#include "material.h"

#include <xtb_core/thread_context.h>
#include <xtb_ogl/ogl.h>

#include "opengl_material.cpp"
#include "xtb_core/allocator.h"

namespace xtb
{

namespace
{

void material_set_defaults(Material *mat)
{
    Array<MaterialParamDesc>& params = mat->templ->params;

    for (i32 i = 0; i < params.size(); ++i)
    {
        switch (params[i].kind)
        {
            case MaterialParamKind::Float: mat->set_float_by_index(i, 0.0f); break;

            case MaterialParamKind::Vec2: mat->set_vec2_by_index(i, v2s(0.0f)); break;
            case MaterialParamKind::Vec3: mat->set_vec3_by_index(i, v3s(0.0f)); break;
            case MaterialParamKind::Vec4: mat->set_vec4_by_index(i, v4s(0.0f)); break;

            case MaterialParamKind::Mat2: mat->set_mat2_by_index(i, I2()); break;
            case MaterialParamKind::Mat3: mat->set_mat3_by_index(i, I3()); break;
            case MaterialParamKind::Mat4: mat->set_mat4_by_index(i, I4()); break;

            case MaterialParamKind::None: break;
        }
    }
}

}

i32 MaterialTemplate::find_param(const char *name) const
{
    for (i32 i = 0; i < this->params.size(); ++i)
    {
        const MaterialParamDesc *desc = &this->params[i];
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
void Material::set_float_by_index(i32 index, f32 val)
{
    Assert(index >= 0);
    Assert(this->templ->params[index].kind == MaterialParamKind::Float);

    this->values[index].kind = MaterialParamKind::Float;
    this->values[index].as.f32_ = val;
}

void Material::set_vec2_by_index(i32 index, vec2 val)
{
    Assert(index >= 0);
    Assert(this->templ->params[index].kind == MaterialParamKind::Vec2);

    this->values[index].kind = MaterialParamKind::Vec2;
    this->values[index].as.vec2_ = val;
}

void Material::set_vec3_by_index(i32 index, vec3 val)
{
    Assert(index >= 0);
    Assert(this->templ->params[index].kind == MaterialParamKind::Vec3);

    this->values[index].kind = MaterialParamKind::Vec3;
    this->values[index].as.vec3_ = val;
}

void Material::set_vec4_by_index(i32 index, vec4 val)
{
    Assert(index >= 0);
    Assert(this->templ->params[index].kind == MaterialParamKind::Vec4);

    this->values[index].kind = MaterialParamKind::Vec4;
    this->values[index].as.vec4_ = val;
}

void Material::set_mat2_by_index(i32 index, mat2 val)
{
    Assert(index >= 0);
    Assert(this->templ->params[index].kind == MaterialParamKind::Mat2);

    this->values[index].kind = MaterialParamKind::Mat2;
    this->values[index].as.mat2_ = val;
}

void Material::set_mat3_by_index(i32 index, mat3 val)
{
    Assert(index >= 0);
    Assert(this->templ->params[index].kind == MaterialParamKind::Mat3);

    this->values[index].kind = MaterialParamKind::Mat3;
    this->values[index].as.mat3_ = val;
}

void Material::set_mat4_by_index(i32 index, mat4 val)
{
    Assert(index >= 0);
    Assert(this->templ->params[index].kind == MaterialParamKind::Mat4);

    this->values[index].kind = MaterialParamKind::Mat4;
    this->values[index].as.mat4_ = val;
}

/****************************************************************
 * String Setters
****************************************************************/
void Material::set_float(const char *name, f32 val)
{
    i32 index = this->templ->find_param(name);
    this->set_float_by_index(index, val);
}

void Material::set_vec2(const char *name, vec2 val)
{
    i32 index = this->templ->find_param(name);
    this->set_vec2_by_index(index, val);
}

void Material::set_vec4(const char *name, vec4 val)
{
    i32 index = this->templ->find_param(name);
    this->set_vec4_by_index(index, val);
}

void Material::set_vec3(const char *name, vec3 val)
{
    i32 index = this->templ->find_param(name);
    this->set_vec3_by_index(index, val);
}

void Material::set_mat2(const char *name, mat2 val)
{
    i32 index = this->templ->find_param(name);
    this->set_mat2_by_index(index, val);
}

void Material::set_mat3(const char *name, mat3 val)
{
    i32 index = this->templ->find_param(name);
    this->set_mat3_by_index(index, val);
}

void Material::set_mat4(const char *name, mat4 val)
{
    i32 index = this->templ->find_param(name);
    this->set_mat4_by_index(index, val);
}
/****************************************************************
 * Constructors
****************************************************************/
MaterialTemplate MaterialTemplate::init(Allocator *allocator, ShaderProgram program)
{
    MaterialTemplate templ = {};
    templ.program = program;
    templ.params = material_params_from_program(allocator, program.id);;
    return templ;
}

Material Material::create_from_template(Allocator* allocator, MaterialTemplate* templ)
{
    Material mat = {};
    mat.templ = templ;
    mat.values = Array<MaterialParamValue>::init(allocator); // TODO: Make init_with_size
    mat.values.resize(templ->params.size());
    material_set_defaults(&mat);
    return mat;
}

Material Material::copy(Allocator* allocator) const
{
    Material res = {};
    res.templ = this->templ;
    res.values = Array<MaterialParamValue>::init(allocator);
    for (isize i = 0; i < this->values.size(); ++i)
    {
        res.values.append(this->values[i]);
    }
    // array_init(&res.values, allocator);
    // array_append(&res.values, m->values.data, m->values.count);
    return res;
}

}
