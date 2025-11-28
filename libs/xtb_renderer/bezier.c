#include "renderer.h"

#include "types.h"
#include <xtb_core/thread_context.h>

static Vec2Array compute_bezier_points(Allocator *allocator, vec2 *points, size_t count, i32 samples)
{
    Assert(samples > 1);
    Assert(count > 0);

    TempArena scratch = scratch_begin_conflict(allocator);

    Vec2Array polypoints = make_array(allocator);
    array_reserve(&polypoints, samples);

    Vec2Array intermediate = make_array(&scratch.arena->allocator);

    for (i32 sample_iter = 0; sample_iter < samples; ++sample_iter)
    {
        f32 t = unlerp(0, samples - 1, sample_iter);

        i32 icount = count;
        array_assign(&intermediate, points, count);

        while (icount > 1)
        {
            for (i32 i = 0; i < icount - 1; ++i)
            {
                intermediate.data[i] = lerp2(intermediate.data[i], intermediate.data[i + 1], t);
            }

            icount -= 1;
        }

        array_push(&polypoints, intermediate.data[0]);
    }

    scratch_end(scratch);
    return polypoints;
}

static Vec2Array compute_bezier_spline_points(Allocator *allocator, vec2 *points, i32 count, i32 bezier_deg, i32 samples)
{
    Vec2Array polypoints = make_array(allocator);

    for (i32 i = 0; i < count - bezier_deg; i += bezier_deg)
    {
        Vec2Array curr_polypoints = compute_bezier_points(allocator, points + i, bezier_deg + 1, samples);

        if (i != 0)
        {
            array_append(&polypoints, curr_polypoints.data + 1, curr_polypoints.count - 1);
        }
        else
        {
            array_append(&polypoints, curr_polypoints.data, curr_polypoints.count);
        }
    }

    return polypoints;
}

void render_bezier_spline_custom(Renderer *renderer, vec2 *points, i32 count, i32 bezier_deg, i32 samples, f32 thickness, vec4 color, bool looped)
{
    TempArena scratch = scratch_begin_no_conflicts();
    Vec2Array polypoints = compute_bezier_spline_points(&scratch.arena->allocator, points, count, bezier_deg, samples);
    render_polyline_custom(renderer, polypoints.data, polypoints.count, thickness, color, looped);
    scratch_end(scratch);
}

