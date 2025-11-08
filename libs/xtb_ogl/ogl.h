#ifndef _XTB_OGL_H_
#define _XTB_OGL_H_

#include <xtb_core/str.h>
#include <glad/glad.h>

typedef unsigned int ShaderProgram;
typedef unsigned int Shader;

Shader load_shader_from_file(const char *ns, XTB_String8 filepath, int shader_type);
Shader load_vertex_shader_from_file(const char *ns, XTB_String8 filepath);
Shader load_fragment_shader_from_file(const char *ns, XTB_String8 filepath);
ShaderProgram create_shader_program_from_descriptors(const char *ns, Shader vs_id, Shader fs_id);
ShaderProgram load_shader_program_from_files(const char *ns, XTB_String8 vertex_filepath, XTB_String8 fragment_filepath);

#endif // _XTB_OGL_H_
