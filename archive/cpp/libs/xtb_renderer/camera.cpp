#include "camera.h"

#include <xtb_core/core.h>
#include <string.h>

namespace xtb
{

static void camera_recalc_basis(Camera *c)
{
    c->pitch = clamp(c->pitch, -89.0f, 89.0f);
    c->yaw = repeat(c->yaw, 360.0f);

    vec3 world_up = v3(0.0f, 1.0f, 0.0f);

    c->basis.back = neg3(norm3(v3_euler(c->yaw, c->pitch)));
    c->basis.right = norm3(cross(world_up, c->basis.back));
    c->basis.up = norm3(cross(c->basis.back, c->basis.right));
}

/****************************************************************
 * Initialization
****************************************************************/
void camera_init(Camera *camera)
{
    MemoryZeroStruct(camera);
    camera->view = I4();
    camera->projection = I4();
}

/****************************************************************
 * Movement/Rotation
****************************************************************/
void camera_set_position(Camera *camera, vec3 position)
{
    camera->position = position;
}

void camera_move(Camera *c, vec3 delta)
{
    c->position = add3(c->position, delta);
}

void camera_move_local(Camera *c, vec3 delta_local)
{
    vec3 delta =
        add3(
            add3(mul3s(c->basis.back, delta_local.z),
                 mul3s(c->basis.right, delta_local.x)),
            mul3s(c->basis.up, delta_local.y)
        );

    camera_move(c, delta);
}

void camera_look_at(Camera *c, vec3 point)
{
    vec3 direction = norm3(sub3(point, c->position));

    c->yaw = rad2deg(atan2f(direction.x, -direction.z));
    c->pitch = rad2deg(asinf(direction.y));
    camera_recalc_basis(c);
}

void camera_rotate_delta(Camera *camera, f32 dx, f32 dy)
{
    camera->yaw += dx;
    camera->pitch += dy;
    camera_recalc_basis(camera);
}

/****************************************************************
 * Projection
****************************************************************/
void camera_set_projection(Camera *camera, mat4 projection)
{
    camera->projection = projection;
}

/****************************************************************
 * View
****************************************************************/
void camera_recalc_view_matrix(Camera *c)
{
    vec3 world_up = v3(0.0f, 1.0f, 0.0f);
    vec3 target = sub3(c->position, c->basis.back);
    c->view = look_at(c->position, target, world_up);
}

}
