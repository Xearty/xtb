#include <xtb_bmp/bmp.h>
#include <raylib.h>
#include <math.h>

BMP_Color
layer_filter_accent_color(BMP_Color color, int factor, BMP_Color filter_color)
{
    BMP_Color out_color = color;

    int threshold = 255 / factor;

    int average = (color.r + color.g + color.b) / 3;
    if (average < threshold)
    {
        int luminosity =  average * factor;
        float fluminosity = (float)luminosity / 255.f;

        out_color = bmp_color_create(filter_color.b * fluminosity,
                                    filter_color.g * fluminosity,
                                    filter_color.r * fluminosity,
                                    255);
    }

    return out_color;
}

float
map_range(float value,
          float from_min, float from_max,
          float to_min, float to_max)
{
    if (from_max == from_min)
    {
        return to_min;
    }
    else
    {
        return to_min + ((value - from_min) * (to_max - to_min)) / (from_max - from_min);
    }
}

struct Rainbow_State
{
    Vector3 times;
    Vector3 increments;
};

Rainbow_State create_rainbow_state(float min_increment, float max_increment)
{
    Rainbow_State state = {};

    float constant = 10000000;

    state.times.x = GetRandomValue(0, constant);
    state.times.y = GetRandomValue(0, constant);
    state.times.z = GetRandomValue(0, constant);

    state.increments.x = map_range(GetRandomValue(0, constant), 0.0f, constant, min_increment, max_increment);
    state.increments.y = map_range(GetRandomValue(0, constant), 0.0f, constant, min_increment, max_increment);
    state.increments.z = map_range(GetRandomValue(0, constant), 0.0f, constant, min_increment, max_increment);

    return state;
}

void update_rainbow_state(Rainbow_State *state)
{
    state->times.x += state->increments.x;
    state->times.y += state->increments.y;
    state->times.z += state->increments.z;
}

BMP_Color
layer_filter_rainbow(BMP_Color color, int factor, Rainbow_State state)
{
    BMP_Color out_color = color;

    int threshold = 255 / factor;

    int average = (color.r + color.g + color.b) / 3;
    if (average < threshold)
    {
        int luminosity =  average * factor;
        float fluminosity = (float)luminosity / 255.f;

        float sin_factor = 0.25f;
        float b = fabs(sin(state.times.x * sin_factor));
        float g = fabs(sin(state.times.y * sin_factor));
        float r = fabs(sin(state.times.z * sin_factor));

        float norm_b = map_range(b, 0.0f, 1.0f, 0.0f, 255.0f);
        float norm_g = map_range(g, 0.0f, 1.0f, 0.0f, 255.0f);
        float norm_r = map_range(r, 0.0f, 1.0f, 0.0f, 255.0f);

        out_color = bmp_color_create(norm_b * fluminosity,
                                            norm_g * fluminosity,
                                            norm_r * fluminosity,
                                            255);
    }

    return out_color;
}

BMP_Color
layer_filter_negative(BMP_Color color)
{
    BMP_Color out_color = bmp_color_create(255 - color.b,
                                           255 - color.g,
                                           255 - color.r,
                                           255);

    return out_color;
}
