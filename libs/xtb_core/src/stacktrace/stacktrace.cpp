#include "xtb_ansi/escape_codes.h"
#include "xtb_core/thread_context.h"
#include <xtb_core/core.h>
#include <xtb_core/stacktrace.h>
#include <xtb_ansi/ansi.h>

#include <backtrace.h>

#include <cxxabi.h>

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <iostream>

#include <xtb_core/string.h>

#include "signature_parser.cpp"
#include "color_schemes.cpp"

namespace xtb::stacktrace
{
struct Backtrace
{
    struct backtrace_state *state;
    i64 missing_frames_count;
    ColorScheme colors = ColorScheme::get_default();
};

Backtrace g_backtrace;

void xtb_backtrace_error_callback(void *data, const char *msg, int errnum)
{
    Unused(data);
    Unused(errnum);

    ansi_print_bold_red(stderr, "BACKTRACE ERROR: %s", msg);
    fputs("\n", stderr);
}

static char* demangle(const char *symbol)
{
    int status = 0;
    char* demangled_saymbol = abi::__cxa_demangle(symbol, NULL, NULL, &status);
    return demangled_saymbol;
}

StringBuf format_colored_signature(Allocator* allocator, String signature, ColorScheme colors)
{
    using namespace sigparse;

    StringBuf result = StringBuf::init(allocator);

    ScratchScope scratch(allocator);
    Array<Token> tokens = tokenize(&scratch->allocator, signature);

    bool inside_parameter_list = false;

    for (const auto& token : tokens)
    {
        const char* ansi_color = colors.default_color;

        if (token.kind == TokenKind::LeftParen)
        {
            inside_parameter_list = true;
        }
        else if (token.kind == TokenKind::Identifier)
        {
            switch (token.ident_type)
            {
                case IdentType::Namespace: ansi_color = colors.namespace_color; break;
                case IdentType::Function:  ansi_color = colors.function_color;  break;
                case IdentType::Type:      ansi_color = colors.type_color;      break;
                case IdentType::None: break;
            }
        }
        else if (token.kind == TokenKind::Const || token.kind == TokenKind::Volatile)
        {
            result.append(' ');
            ansi_color = colors.keyword_color;
        }
        else if (token.kind == TokenKind::Pointer || token.kind == TokenKind::LVReference || token.kind == TokenKind::RVReference)
        {
            ansi_color = colors.pointer_ref_color;
        }
        else if (token.kind == TokenKind::Signed || token.kind == TokenKind::Unsigned)
        {
            ansi_color = colors.type_color;
        }

        result.append(String::from_cstr(ansi_color));
        result.append(token.source_string);
        result.append(String::from_cstr(COLOR_RESET));

        if (token.kind == TokenKind::Comma || token.kind == TokenKind::Signed || token.kind == TokenKind::Unsigned)
        {
            result.append(' ');
        }
        else if (token.kind == TokenKind::Pointer || token.kind == TokenKind::LVReference || token.kind == TokenKind::RVReference)
        {
            if (!inside_parameter_list)
            {
                result.append(' ');
            }
        }
    }

    return result;
}

String stacktrace_get_final_signature_string(Allocator* allocator, String signature)
{
    struct StringReplacement { String from, to; };
    StringReplacement replacements[] = {
        { "void* (**)(void*, long, void*, long, long)", "xtb::Allocator*" }
    };

    ScratchScope scratch;

    for (StringReplacement replacement : replacements)
    {
        signature = signature.replace(
            replacement.from,
            replacement.to,
            &scratch->allocator
        );
    }

    StringBuf formatted_signature = format_colored_signature(
        allocator,
        signature,
        g_backtrace.colors
    );

    return formatted_signature.detach();;
}

struct StackFrame
{
    String filename;
    String function;
    i32 line;
    uintptr_t pc;
};

struct CollectStackFramesContext
{
    Arena* arena;
    Array<StackFrame>* frames;
};

static int collect_stack_frames_callback(void* data,
                                 uintptr_t pc,
                                 const char* filename,
                                 int lineno,
                                 const char* function)
{
    CollectStackFramesContext* ctx = (CollectStackFramesContext*)data;

    // TODO: Improve the string API to handle these cases more easily
    String filename_str = "";
    String function_str = "";
    if (filename) filename_str = String::from_cstr(filename);
    if (function) function_str = String::from_cstr(function);

    StackFrame frame = {
        .filename = filename_str.copy(&ctx->arena->allocator),
        .function = function_str.copy(&ctx->arena->allocator),
        .line = lineno,
        .pc = pc,
    };

    ctx->frames->append(frame);

    if (function_str == "main")
    {
        return 1;
    }

    return 0;
}

static Array<StackFrame> collect_stack_frames(Arena* arena, i32 skip_frames_count = 2)
{
    Array<StackFrame> frames = Array<StackFrame>::init(&arena->allocator);

    CollectStackFramesContext context = {
        .arena = arena,
        .frames = &frames,
    };

    backtrace_full(g_backtrace.state,
                   skip_frames_count,
                   collect_stack_frames_callback,
                   xtb_backtrace_error_callback,
                   &context);

    return frames;
}

static void push_missing_frame()
{
    g_backtrace.missing_frames_count += 1;
}

static void print_missing_frames(i64 next_non_missing_depth)
{
    if (g_backtrace.missing_frames_count <= 0) return;

    if (g_backtrace.missing_frames_count == 1)
    {
        std::cerr
            << " "
            << g_backtrace.colors.decoration_color << "["
            << g_backtrace.colors.line_number_color << next_non_missing_depth - 1
            << g_backtrace.colors.decoration_color << "]"
            << COLOR_RESET << " "
            << g_backtrace.colors.missing_frames_color << "<frame omitted: no debug info>" << COLOR_RESET
            << std::endl << std::endl;;
    }
    else
    {
        std::cerr
            << " "
            << g_backtrace.colors.decoration_color << "["
            << g_backtrace.colors.line_number_color << next_non_missing_depth - g_backtrace.missing_frames_count
            << g_backtrace.colors.decoration_color << "…"
            << g_backtrace.colors.line_number_color << next_non_missing_depth - 1
            << g_backtrace.colors.decoration_color << "]"
            << COLOR_RESET << " "
            << g_backtrace.colors.missing_frames_color << "<frames omitted: no debug info>" << COLOR_RESET
            << std::endl << std::endl;;
    }

    g_backtrace.missing_frames_count = 0;
}

static void print_stack_frame(StackFrame* frame, isize depth)
{
    ScratchScope scratch;

    if (frame->filename.is_empty())
    {
        push_missing_frame();
    }
    else
    {
        print_missing_frames(depth);

        String function_display = frame->function;

        if (frame->function.is_empty())
        {
            function_display = "[No Symbol]";
        }
        else
        {
            char* demangled_symbol = demangle((char*)frame->function.data());
            if (demangled_symbol != NULL)
            {
                function_display = String::from_cstr(demangled_symbol).copy(&scratch->allocator);
            }
            free(demangled_symbol);
        }

        std::cerr
            << " " << g_backtrace.colors.decoration_color << "["
            << g_backtrace.colors.line_number_color << depth
            << g_backtrace.colors.decoration_color << "]" << COLOR_RESET << " "
            << stacktrace_get_final_signature_string(&scratch->allocator, function_display)
            << "\n     " << g_backtrace.colors.decoration_color << "↳" << COLOR_RESET << " "
            << g_backtrace.colors.filepath_color << frame->filename << COLOR_RESET
            << g_backtrace.colors.decoration_color << ":" << COLOR_RESET
            << g_backtrace.colors.line_number_color << frame->line << COLOR_RESET
            << std::endl;
    }
}

void print(int skip_frames_count)
{
    if (g_backtrace.state == NULL) return;

    ScratchScope scratch;
    Array<StackFrame> frames = collect_stack_frames(*scratch, skip_frames_count);

    for (isize depth = 0; depth < frames.size(); ++depth)
    {
        print_stack_frame(&frames[depth], depth);
    }

    print_missing_frames(frames.size());
}

void print_full()
{
    print(0);
}

void init(const char *exe_path)
{
    g_backtrace.state = backtrace_create_state(exe_path, 0, xtb_backtrace_error_callback, NULL);
}

void colorscheme_set(ColorScheme colors)
{
    if (colors.function_color != NULL) g_backtrace.colors.function_color = colors.function_color;
    if (colors.type_color != NULL) g_backtrace.colors.type_color = colors.type_color;
    if (colors.namespace_color != NULL) g_backtrace.colors.namespace_color = colors.namespace_color;
    if (colors.filepath_color != NULL) g_backtrace.colors.filepath_color = colors.filepath_color;
    if (colors.line_number_color != NULL) g_backtrace.colors.line_number_color = colors.line_number_color;
    if (colors.keyword_color != NULL) g_backtrace.colors.keyword_color = colors.keyword_color;
    if (colors.default_color != NULL) g_backtrace.colors.default_color = colors.default_color;
    if (colors.pointer_ref_color != NULL) g_backtrace.colors.pointer_ref_color = colors.pointer_ref_color;
    if (colors.decoration_color != NULL) g_backtrace.colors.decoration_color = colors.decoration_color;
    if (colors.missing_frames_color != NULL) g_backtrace.colors.missing_frames_color = colors.missing_frames_color;
}

void colorscheme_pick_preset(ColorSchemePreset preset)
{
    colorscheme_set(ColorScheme::get_preset(preset));
}

}
