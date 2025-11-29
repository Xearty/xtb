#include <xtb_core/stacktrace.h>
#include <xtb_core/contract.h>
#include <xtb_ansi/ansi.h>

namespace xtb::stacktrace
{

ColorScheme ColorScheme::get_default()
{
    return ColorScheme::get_preset(ColorSchemePreset::Solar);
}

ColorScheme ColorScheme::get_preset(ColorSchemePreset preset)
{
    switch (preset)
    {
        case ColorSchemePreset::Solar: return {
            .function_color       = ansi_color8_foreground(220),
            .type_color           = ansi_color8_foreground(110),
            .namespace_color      = ansi_color8_foreground(81),
            .filepath_color       = ansi_color8_foreground(244),
            .line_number_color    = ansi_color8_foreground(203),
            .keyword_color        = ansi_color8_foreground(152),
            .default_color        = ansi_color8_foreground(252),
            .pointer_ref_color    = ansi_color8_foreground(250),
            .decoration_color     = ansi_color8_foreground(250),
            .missing_frames_color = ansi_color8_foreground(8),
        };

        case ColorSchemePreset::Zenburn: return {
            .function_color       = ansi_color8_foreground(228),
            .type_color           = ansi_color8_foreground(187),
            .namespace_color      = ansi_color8_foreground(109),
            .filepath_color       = ansi_color8_foreground(240),
            .line_number_color    = ansi_color8_foreground(248),
            .keyword_color        = ansi_color8_foreground(223),
            .default_color        = ansi_color8_foreground(188),
            .pointer_ref_color    = ansi_color8_foreground(229),
            .decoration_color     = ansi_color8_foreground(239),
            .missing_frames_color = ansi_color8_foreground(237),
        };

        case ColorSchemePreset::Gruvbox: return {
            .function_color       = ansi_color8_foreground(142),
            .type_color           = ansi_color8_foreground(214),
            .namespace_color      = ansi_color8_foreground(109),
            .filepath_color       = ansi_color8_foreground(244),
            .line_number_color    = ansi_color8_foreground(243),
            .keyword_color        = ansi_color8_foreground(208),
            .default_color        = ansi_color8_foreground(223),
            .pointer_ref_color    = ansi_color8_foreground(223),
            .decoration_color     = ansi_color8_foreground(241),
            .missing_frames_color = ansi_color8_foreground(239),
        };

        case ColorSchemePreset::TokyoNight: return {
            .function_color       = ansi_color8_foreground(111),
            .type_color           = ansi_color8_foreground(179),
            .namespace_color      = ansi_color8_foreground(117),
            .filepath_color       = ansi_color8_foreground(60),
            .line_number_color    = ansi_color8_foreground(60),
            .keyword_color        = ansi_color8_foreground(141),
            .default_color        = ansi_color8_foreground(146),
            .pointer_ref_color    = ansi_color8_foreground(110),
            .decoration_color     = ansi_color8_foreground(239),
            .missing_frames_color = ansi_color8_foreground(238),
        };

        case ColorSchemePreset::WarmAsh: return {
            .function_color       = ansi_color8_foreground(220),
            .type_color           = ansi_color8_foreground(250),
            .namespace_color      = ansi_color8_foreground(245),
            .filepath_color       = ansi_color8_foreground(240),
            .line_number_color    = ansi_color8_foreground(203),
            .keyword_color        = ansi_color8_foreground(152),
            .default_color        = ansi_color8_foreground(252),
            .pointer_ref_color    = ansi_color8_foreground(247),
            .decoration_color     = ansi_color8_foreground(239),
            .missing_frames_color = ansi_color8_foreground(238),
        };

        case ColorSchemePreset::Nord: return {
            .function_color       = ansi_color8_foreground(110),
            .type_color           = ansi_color8_foreground(186),
            .namespace_color      = ansi_color8_foreground(109),
            .filepath_color       = ansi_color8_foreground(240),
            .line_number_color    = ansi_color8_foreground(239),
            .keyword_color        = ansi_color8_foreground(139),
            .default_color        = ansi_color8_foreground(255),
            .pointer_ref_color    = ansi_color8_foreground(252),
            .decoration_color     = ansi_color8_foreground(238),
            .missing_frames_color = ansi_color8_foreground(237),
        };

        case ColorSchemePreset::Dracula: return {
            .function_color       = ansi_color8_foreground(84),
            .type_color           = ansi_color8_foreground(228),
            .namespace_color      = ansi_color8_foreground(117),
            .filepath_color       = ansi_color8_foreground(61),
            .line_number_color    = ansi_color8_foreground(239),
            .keyword_color        = ansi_color8_foreground(212),
            .default_color        = ansi_color8_foreground(255),
            .pointer_ref_color    = ansi_color8_foreground(255),
            .decoration_color     = ansi_color8_foreground(238),
            .missing_frames_color = ansi_color8_foreground(237),
        };

        case ColorSchemePreset::OneDark: return {
            .function_color       = ansi_color8_foreground(75),
            .type_color           = ansi_color8_foreground(180),
            .namespace_color      = ansi_color8_foreground(73),
            .filepath_color       = ansi_color8_foreground(241),
            .line_number_color    = ansi_color8_foreground(240),
            .keyword_color        = ansi_color8_foreground(176),
            .default_color        = ansi_color8_foreground(249),
            .pointer_ref_color    = ansi_color8_foreground(249),
            .decoration_color     = ansi_color8_foreground(238),
            .missing_frames_color = ansi_color8_foreground(237),
        };

        case ColorSchemePreset::Monokai: return {
            .function_color       = ansi_color8_foreground(148),
            .type_color           = ansi_color8_foreground(179),
            .namespace_color      = ansi_color8_foreground(81),
            .filepath_color       = ansi_color8_foreground(242),
            .line_number_color    = ansi_color8_foreground(242),
            .keyword_color        = ansi_color8_foreground(197),
            .default_color        = ansi_color8_foreground(255),
            .pointer_ref_color    = ansi_color8_foreground(252),
            .decoration_color     = ansi_color8_foreground(240),
            .missing_frames_color = ansi_color8_foreground(238),
        };

        case ColorSchemePreset::CatppuccinMocha: return {
            .function_color       = ansi_color8_foreground(111),
            .type_color           = ansi_color8_foreground(216),
            .namespace_color      = ansi_color8_foreground(147),
            .filepath_color       = ansi_color8_foreground(243),
            .line_number_color    = ansi_color8_foreground(241),
            .keyword_color        = ansi_color8_foreground(211),
            .default_color        = ansi_color8_foreground(189),
            .pointer_ref_color    = ansi_color8_foreground(189),
            .decoration_color     = ansi_color8_foreground(238),
            .missing_frames_color = ansi_color8_foreground(237),
        };

        case ColorSchemePreset::Everforest: return {
            .function_color       = ansi_color8_foreground(144),
            .type_color           = ansi_color8_foreground(180),
            .namespace_color      = ansi_color8_foreground(109),
            .filepath_color       = ansi_color8_foreground(245),
            .line_number_color    = ansi_color8_foreground(240),
            .keyword_color        = ansi_color8_foreground(174),
            .default_color        = ansi_color8_foreground(187),
            .pointer_ref_color    = ansi_color8_foreground(187),
            .decoration_color     = ansi_color8_foreground(239),
            .missing_frames_color = ansi_color8_foreground(238),
        };

        case ColorSchemePreset::Solarized: return {
            .function_color       = ansi_color8_foreground(221),
            .type_color           = ansi_color8_foreground(116),
            .namespace_color      = ansi_color8_foreground(67),
            .filepath_color       = ansi_color8_foreground(241),
            .line_number_color    = ansi_color8_foreground(244),
            .keyword_color        = ansi_color8_foreground(208),
            .default_color        = ansi_color8_foreground(252),
            .pointer_ref_color    = ansi_color8_foreground(246),
            .decoration_color     = ansi_color8_foreground(239),
            .missing_frames_color = ansi_color8_foreground(237),
        };

        case ColorSchemePreset::Firewatch: return {
            .function_color       = ansi_color8_foreground(208),
            .type_color           = ansi_color8_foreground(179),
            .namespace_color      = ansi_color8_foreground(68),
            .filepath_color       = ansi_color8_foreground(241),
            .line_number_color    = ansi_color8_foreground(160),
            .keyword_color        = ansi_color8_foreground(202),
            .default_color        = ansi_color8_foreground(252),
            .pointer_ref_color    = ansi_color8_foreground(247),
            .decoration_color     = ansi_color8_foreground(239),
            .missing_frames_color = ansi_color8_foreground(237),
        };

        case ColorSchemePreset::MutedEarth: return {
            .function_color       = ansi_color8_foreground(143),
            .type_color           = ansi_color8_foreground(180),
            .namespace_color      = ansi_color8_foreground(108),
            .filepath_color       = ansi_color8_foreground(244),
            .line_number_color    = ansi_color8_foreground(242),
            .keyword_color        = ansi_color8_foreground(137),
            .default_color        = ansi_color8_foreground(252),
            .pointer_ref_color    = ansi_color8_foreground(247),
            .decoration_color     = ansi_color8_foreground(240),
            .missing_frames_color = ansi_color8_foreground(238),
        };

        case ColorSchemePreset::HokusaiMist: return {
            .function_color       = ansi_color8_foreground(110),
            .type_color           = ansi_color8_foreground(179),
            .namespace_color      = ansi_color8_foreground(109),
            .filepath_color       = ansi_color8_foreground(244),
            .line_number_color    = ansi_color8_foreground(240),
            .keyword_color        = ansi_color8_foreground(140),
            .default_color        = ansi_color8_foreground(187),
            .pointer_ref_color    = ansi_color8_foreground(187),
            .decoration_color     = ansi_color8_foreground(238),
            .missing_frames_color = ansi_color8_foreground(237),
        };

        case ColorSchemePreset::HarborDusk: return {
            .function_color       = ansi_color8_foreground(110),
            .type_color           = ansi_color8_foreground(180),
            .namespace_color      = ansi_color8_foreground(67),
            .filepath_color       = ansi_color8_foreground(242),
            .line_number_color    = ansi_color8_foreground(59),
            .keyword_color        = ansi_color8_foreground(215),
            .default_color        = ansi_color8_foreground(187),
            .pointer_ref_color    = ansi_color8_foreground(187),
            .decoration_color     = ansi_color8_foreground(240),
            .missing_frames_color = ansi_color8_foreground(238),
        };

        case ColorSchemePreset::Experiment: return {

        };
    }

    Unreachable;
}
}
