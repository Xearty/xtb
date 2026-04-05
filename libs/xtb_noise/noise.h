#ifndef _XTB_NOISE_H_
#define _XTB_NOISE_H_

#include <xtb_core/core.h>
#include <xtb_core/array.h>
#include <xtbm/xtbm.h>

namespace xtb
{

struct Noise1d
{
    Array<f32> values;

    static Noise1d create(i32 vertices_count);
    f32 sample(f32 input);
};

}

#endif // _XTB_NOISE_H_
