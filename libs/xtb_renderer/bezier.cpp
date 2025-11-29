#include "renderer.h"

#include "types.h"
#include <xtb_core/thread_context.h>

namespace xtb
{

static Array<vec2> compute_bezier_points(Allocator *allocator, vec2 *points, size_t count, i32 samples)
{
    Assert(samples > 1);
    Assert(count > 0);

    TempArena scratch = scratch_begin_conflict(allocator);

    auto polypoints = Array<vec2>::init_with_capacity(allocator, samples);

    auto intermediate = Array<vec2>::init_with_size(&scratch.arena->allocator, count);

    for (i32 sample_iter = 0; sample_iter < samples; ++sample_iter)
    {
        f32 t = unlerp(0, samples - 1, sample_iter);

        i32 icount = count;
        for (isize idx = 0; idx < (isize)count; ++idx)
        {
            intermediate[idx] = points[idx];
        }

        while (icount > 1)
        {
            for (i32 i = 0; i < icount - 1; ++i)
            {
                intermediate[i] = lerp2(intermediate[i], intermediate[i + 1], t);
            }

            icount -= 1;
        }

        polypoints.append(intermediate[0]);
    }

    scratch_end(scratch);
    return polypoints;
}

static Array<vec2> compute_bezier_spline_points(Allocator *allocator, vec2 *points, i32 count, i32 bezier_deg, i32 samples)
{
    auto polypoints = Array<vec2>::init(allocator);

    for (i32 i = 0; i < count - bezier_deg; i += bezier_deg)
    {
        Array<vec2> curr_polypoints = compute_bezier_points(allocator, points + i, bezier_deg + 1, samples);

        if (i != 0)
        {
            // array_append(&polypoints, curr_polypoints.data() + 1, curr_polypoints.size() - 1);
            for (isize j = 1; j < curr_polypoints.size(); ++j)
            {
                polypoints.append(curr_polypoints[j]);
            }
        }
        else
        {
            // array_append(&polypoints, curr_polypoints.data(), curr_polypoints.size());
            for (isize j = 0; j < curr_polypoints.size(); ++j)
            {
                polypoints.append(curr_polypoints[j]);
            }
        }
    }

    return polypoints;
}

void render_bezier_spline_custom(Renderer *renderer, vec2 *points, i32 count, i32 bezier_deg, i32 samples, f32 thickness, vec4 color, bool looped)
{
    TempArena scratch = scratch_begin_no_conflicts();
    Array<vec2> polypoints = compute_bezier_spline_points(&scratch.arena->allocator, points, count, bezier_deg, samples);
    render_polyline_custom(renderer, polypoints.data(), polypoints.size(), thickness, color, looped);
    scratch_end(scratch);
}

}
