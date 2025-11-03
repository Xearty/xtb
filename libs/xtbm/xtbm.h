#ifndef _XTBM_H_
#define _XTBM_H_

// TODO(xearty): These are defined in xtb_core now but are left here for now
#define xtb_min(A, B) ((A) < (B) ? (A) : (B))
#define xtb_max(A, B) ((A) > (B) ? (A) : (B))
#define xtb_clamp(VALUE, MIN_VALUE, MAX_VALUE)  \
    ((VALUE) < (MIN_VALUE) ? (MIN_VALUE)        \
     : (VALUE) > (MAX_VALUE) ? (MAX_VALUE)      \
     : (VALUE))

float xtb_lerp(float a, float b, float t);
float xtb_inv_lerp(float a, float b, float value);

#endif // _XTBM_H_
