#ifndef _XTB_STACKTRACE_H_
#define _XTB_STACKTRACE_H_

#include <xtb_core/context_cracking.h>

namespace xtb
{

namespace stacktrace
{

enum class ColorSchemePreset
{
    Solar,
    WarmAsh,
    Zenburn,
    Gruvbox,
    TokyoNight,
    Nord,
    Dracula,
    OneDark,
    Monokai,
    CatppuccinMocha,
    Everforest,
    Solarized,
    Firewatch,
    MutedEarth,
    HokusaiMist,
    HarborDusk,
    Experiment,
};

struct ColorScheme
{
    const char* function_color;
    const char* type_color;
    const char* namespace_color;
    const char* filepath_color;
    const char* line_number_color;
    const char* keyword_color;
    const char* default_color;
    const char* pointer_ref_color;
    const char* decoration_color;
    const char* missing_frames_color;

    static ColorScheme get_default();
    static ColorScheme get_preset(ColorSchemePreset preset);
};

void print(int skip_frames_count);
void print_full();

void init(const char *exe_path);

void colorscheme_set(ColorScheme colors);
void colorscheme_pick_preset(ColorSchemePreset preset);

}

}

#endif // _XTB_STACKTRACE_H_
