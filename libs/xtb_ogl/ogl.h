#ifndef _XTB_OGL_H_
#define _XTB_OGL_H_

#include <xtb_core/str.h>
#include <glad/glad.h>

C_LINKAGE_BEGIN

typedef unsigned int ShaderProgram;
typedef unsigned int Shader;

typedef void* (* XTBLoadProc)(const char *name);

bool ogl_load_gl(XTBLoadProc load_proc);

Shader load_shader_from_file(const char *ns, String filepath, int shader_type);
Shader load_vertex_shader_from_file(const char *ns, String filepath);
Shader load_fragment_shader_from_file(const char *ns, String filepath);
ShaderProgram create_shader_program_from_descriptors(const char *ns, Shader vs_id, Shader fs_id);
ShaderProgram load_shader_program_from_files(const char *ns, String vertex_filepath, String fragment_filepath);

Shader load_shader_from_memory(const char *ns, const char *src, int shader_type);
ShaderProgram load_shader_program_from_memory(const char *ns, const char *vertex_src, const char *fragment_src);

void toggle_wireframe(void);

C_LINKAGE_END

#endif // _XTB_OGL_H_
