#include "noise.h"
#include <stdlib.h>
#include <limits.h>

namespace xtb
{

Noise1d Noise1d::create(i32 vertices_count)
{
    Array<f32> values = Array<f32>::init_with_size(allocator_get_heap(), vertices_count);

    for (i32 i = 0; i < ArrLen(values); ++i)
    {
        values[i] = ((f32)rand() / INT_MAX) * 2.0f - 1.0f;
    }

    Noise1d noise;
    noise.values = values;
    return noise;
}

f32 Noise1d::sample(f32 input)
{
    f32 cell_size = 1.0f / this->values.size();
    i32 cell_idx = (i32)floorf(input / cell_size) % this->values.size(); // the left point idx
    i32 cell_start = cell_idx * cell_size;

    f32 displacement = (input - cell_start) / cell_size;

    f32 p1 = this->values[cell_idx] * displacement;
    f32 p2 = this->values[(cell_idx + 1) % this->values.size()] * displacement;

    return lerp(p1, p2, smoothstep(0.0f, 1.0f, displacement));
}

}

