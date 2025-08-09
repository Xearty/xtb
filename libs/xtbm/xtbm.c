float xtb_lerp(float a, float b, float t)
{
    return (1.0f - t) * a + t * b;
}

float xtb_inv_lerp(float a, float b, float value)
{
    return (value - a) / (b - a);
}

