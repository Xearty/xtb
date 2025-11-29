#include "renderer.h"

static void setup_polyline_render_data(Renderer *renderer, PolylineRenderData *out_data)
{
    PolylineRenderData *rdata = &renderer->polyline_render_data;

    glGenVertexArrays(1, &rdata->vao);
    glBindVertexArray(rdata->vao);

    glGenBuffers(1, &rdata->per_vertex_vbo);
    glGenBuffers(1, &rdata->instanced_vbo);
    glGenBuffers(1, &rdata->instanced_ebo);

    i32 per_vertex_stride = sizeof(PolylinePerVertexData);
    glBindBuffer(GL_ARRAY_BUFFER, rdata->per_vertex_vbo);

    glVertexAttribPointer(0, 1, GL_FLOAT, GL_FALSE, per_vertex_stride, (void *)offsetof(PolylinePerVertexData, t));
    glEnableVertexAttribArray(0);

    glVertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, per_vertex_stride, (void *)offsetof(PolylinePerVertexData, side));
    glEnableVertexAttribArray(1);

    PolylinePerVertexData per_vertex_data[] = {
        {0.0f, 1.0f},
        {1.0f, 1.0f},
        {1.0f, -1.0f},
        {0.0f, -1.0f}};

    glBufferData(GL_ARRAY_BUFFER, sizeof(per_vertex_data), per_vertex_data, GL_STATIC_DRAW);

    u32 indices[] = {
        0, 1, 2, //
        2, 3, 0  //
    };

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, rdata->instanced_ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);

    i32 instanced_stride = sizeof(PolylineInstanceData);
    glBindBuffer(GL_ARRAY_BUFFER, rdata->instanced_vbo);
    glBufferData(GL_ARRAY_BUFFER, POLYLINE_INSTANCED_MAX_LINES * instanced_stride, NULL, GL_DYNAMIC_DRAW);

    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, instanced_stride, (void *)offsetof(PolylineInstanceData, prev));
    glEnableVertexAttribArray(2);
    glVertexAttribDivisor(2, 1);

    glVertexAttribPointer(3, 2, GL_FLOAT, GL_FALSE, instanced_stride, (void *)offsetof(PolylineInstanceData, current_start));
    glEnableVertexAttribArray(3);
    glVertexAttribDivisor(3, 1);

    glVertexAttribPointer(4, 2, GL_FLOAT, GL_FALSE, instanced_stride, (void *)offsetof(PolylineInstanceData, current_end));
    glEnableVertexAttribArray(4);
    glVertexAttribDivisor(4, 1);

    glVertexAttribPointer(5, 2, GL_FLOAT, GL_FALSE, instanced_stride, (void *)offsetof(PolylineInstanceData, next));
    glEnableVertexAttribArray(5);
    glVertexAttribDivisor(5, 1);

    glBindVertexArray(0);
}

void render_polyline_custom(Renderer *renderer, vec2 *points, i32 count, f32 thickness, vec4 color, bool looped)
{
    const PolylineRenderData *rdata = &renderer->polyline_render_data;

    ShaderProgramID program = renderer->shaders.polyline;
    glUseProgram(program);
    glUniform1f(glGetUniformLocation(program, "uThickness"), thickness);
    glUniformMatrix4fv(glGetUniformLocation(program, "uProjection"), 1, GL_FALSE, &renderer->camera2d.projection.m00);
    glUniform4f(glGetUniformLocation(program, "color"), color.r, color.g, color.b, color.a);

    glBindVertexArray(rdata->vao);

    for (i32 batch_start = 0; batch_start < count - 1; batch_start += POLYLINE_INSTANCED_MAX_LINES)
    {
        PolylineInstanceData instanced_data[POLYLINE_INSTANCED_MAX_LINES] = {};

        i32 batch_end = Min(batch_start + POLYLINE_INSTANCED_MAX_LINES, count - 1);

        for (i32 i = batch_start; i < batch_end; ++i)
        {
            PolylineInstanceData *inst_data = &instanced_data[i - batch_start];

            if (looped)
            {
                inst_data->prev = points[repeati32(i - 1, count - 1)];
                inst_data->current_start = points[i];
                inst_data->current_end = points[repeati32(i + 1, count - 1)];
                inst_data->next = points[repeati32(i + 2, count - 1)];
            }
            else
            {
                inst_data->prev = points[Max(0, i - 1)];
                inst_data->current_start = points[i];
                inst_data->current_end = points[i + 1];
                inst_data->next = points[Min(i + 2, count - 1)];
            }
        }

        i32 instances_in_batch = batch_end - batch_start;

        glBindBuffer(GL_ARRAY_BUFFER, rdata->instanced_vbo);
        glBufferSubData(GL_ARRAY_BUFFER, 0, instances_in_batch * sizeof(PolylineInstanceData), instanced_data);

        glDrawElementsInstanced(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0, instances_in_batch);
    }

    glBindVertexArray(0);
}

