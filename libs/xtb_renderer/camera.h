#ifndef _XTB_CAMERA_H_
#define _XTB_CAMERA_H_

#include <xtbm/xtbm.h>

typedef struct Basis
{
    vec3 right;
    vec3 up;
    vec3 back;
} Basis;

typedef struct Camera
{
    f32 yaw, pitch;

    vec3 position;
    Basis basis;

    mat4 projection;
    mat4 view;
} Camera;

/****************************************************************
 * Initialization
****************************************************************/
void camera_init(Camera *camera);

/****************************************************************
 * Movement/Rotation
****************************************************************/
void camera_set_position(Camera *camera, vec3 position);
void camera_move(Camera *c, vec3 delta);
void camera_move_local(Camera *c, vec3 delta_local);

void camera_look_at(Camera *c, vec3 point);
void camera_rotate_delta(Camera *camera, f32 dx, f32 dy);

/****************************************************************
 * Projection
****************************************************************/
void camera_set_projection(Camera *camera, mat4 projection);

/****************************************************************
 * View
****************************************************************/
void camera_recalc_view_matrix(Camera *c);

#endif // _XTB_CAMERA_H_
