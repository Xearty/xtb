#include <xtb_core/str.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/contract.h>

// TODO(xearty): str_buffer should probably go in str.h
#include <xtb_core/str_buffer.h>

#include <string.h>
#include <stdio.h>
#include <ctype.h>

String str_from(u8 *str, usize len)
{
    return (String){ (u8*)str, len };
}

String cstr(const char *cstring)
{
    return str_from((u8*)cstring, strlen(cstring));
}

String str_copy(Allocator* allocator, String string)
{
    u8 *buf = AllocateBytes(allocator, string.len + 1);
    strncpy((char*)buf, (char *)string.str, string.len)[string.len] = '\0';
    return str_from(buf, string.len);
}

String str_push_copy(Arena *arena, String string)
{
    return str_copy(&arena->allocator, string);
}

void str_free(Allocator* allocator, String str)
{
    Deallocate(allocator, str.str);
}

bool str_is_invalid(String string)
{
    return string.str == NULL;
}

bool str_is_valid(String string)
{
    return !str_is_invalid(string);
}

i32 str_find_char(String haystack, char needle)
{
    for (i32 i = 0; i < haystack.len; ++i)
    {
        if (haystack.str[i] == needle) return i;
    }

    return -1;
}

i32 str_find_char_last(String haystack, char needle)
{
    for (i32 i = haystack.len - 1; i >= 0; --i)
    {
        if (haystack.str[i] == needle) return i;
    }

    return -1;
}

String str_escape(Allocator *allocator, String string)
{
    char escape_characters[] = { 'a', 'b', 'e', 'f', 'n', 'r', 't', 'v', '\\', '\'', '\"', '?' };
    char hex_values[] = { 0x07, 0x08, 0x1b, 0x0c, 0x0a, 0x0d, 0x09, 0x0b, 0x5c, 0x27, 0x22, 0x3f };
    StaticAssert(ArrLen(escape_characters) == ArrLen(hex_values), str_escape_arrays_match);

    StringBuffer buf = str_buffer_new(allocator, string.len + 1);

    for (i32 i = 0; i < string.len; ++i)
    {
        char ch = string.str[i];

        bool should_escape = false;
        u8 escape_ch = '\0';

        for (i32 j = 0; j < ArrLen(hex_values); ++j)
        {
            if (ch == hex_values[j])
            {
                escape_ch = escape_characters[j];
                should_escape = true;
                break;
            }
        }

        if (should_escape)
        {
            str_buffer_push_back_char(&buf, '\\');
            str_buffer_push_back_char(&buf, escape_ch);
        }
        else
        {
            str_buffer_push_back_char(&buf, ch);
        }
    }

    return str_buffer_detach(&buf);
}

String path_strip_extension(String path)
{
    i32 dot_pos = str_find_char_last(path, '.');
    i32 ext_len = path.len - dot_pos;
    return str_trunc_right(path, ext_len);
}

String path_basename(String path)
{
    i32 begin = str_find_char_last(path, '/') + 1;
    i32 len = path.len - begin;
    return str_substr(path, begin, len);
}

char str_front(String string)
{
    return string.str[0];
}

char str_back(String string)
{
    return string.str[string.len - 1];
}

int str_compare(String f, String s)
{
    return strncmp((char*)f.str, (char*)s.str, Max(f.len, s.len));
}

bool str_eq(String f, String s)
{
    if (f.len != s.len) return false;
    return str_compare(f, s) == 0;
}

bool str_eq_cstring(String f, const char *s)
{
    return str_eq(f, cstr(s));
}

String str_head(String string, size_t count)
{
    return str_substr(string, 0, count);
}

String str_tail(String string, size_t count)
{
    int begin_idx = ClampBot((int)string.len - (int)count, 0);
    return str_substr(string, begin_idx, count);
}

bool str_starts_with(String string, String prefix)
{
    return str_eq(str_head(string, prefix.len), prefix);
}

bool str_ends_with(String string, String postfix)
{
    return str_eq(str_tail(string, postfix.len), postfix);
}

String str_trunc_left(String string, size_t count)
{
    return str_substr(string, count, string.len - count);
}

String str_trunc_right(String string, size_t count)
{
    return str_substr(string, 0, string.len - count);
}

String str_trim_left(String string)
{
    int i;
    for (i = 0; i < string.len; ++i)
    {
        if (!isspace(string.str[i])) break;
    }
    return str_trunc_left(string, i);
}

String str_trim_right(String string)
{
    int i;
    for (i = string.len - 1; i >= 0; --i)
    {
        if (!isspace(string.str[i])) break;
    }
    int count = (int)string.len - 1 - i;
    return str_trunc_right(string, count);
}

String str_trim(String string)
{
    return str_trim_left(str_trim_right(string));
}

size_t str_list_length(StringList str_list)
{
    size_t len = 0;
    IterateList(str_list, StringListNode, node) len += 1;
    return len;
}

size_t str_list_accumulate_length(StringList str_list)
{
    size_t len = 0;
    IterateList(str_list, StringListNode, node) len += node->string.len;
    return len;
}

String str_list_join(Allocator* allocator, StringList str_list)
{
    return str_list_join_str_sep(allocator, str_list, str_empty);
}

String str_list_join_str_sep(Allocator* allocator, StringList str_list, String sep)
{
    // TODO(xearty): Do these two in one pass
    size_t non_sep_len = str_list_accumulate_length(str_list);
    size_t count = str_list_length(str_list);
    size_t sep_count = count - 1;
    size_t len = non_sep_len + (sep_count * sep.len);

    u8 *str_buf = AllocateBytes(allocator, len + 1);

    size_t out_idx = 0;
    IterateList(str_list, StringListNode, node)
    {
        MemoryCopy(str_buf + out_idx, node->string.str, node->string.len);
        out_idx += node->string.len;

        if (node != str_list.tail)
        {
            MemoryCopy(str_buf + out_idx, sep.str, sep.len);
            out_idx += sep.len;
        }
    }

    return str_from(str_buf, len);
}

String str_list_join_char_sep(Allocator* allocator, StringList str_list, char sep)
{
    return str_list_join_str_sep(allocator, str_list, str_from((u8*)&sep, 1));
}

size_t str_array_accumulate_length(String *array, size_t count)
{
    size_t len = 0;
    for (size_t i = 0; i < count; ++i) len += array[i].len;
    return len;
}

String str_array_join(Allocator* allocator, String *array, size_t count)
{
    size_t len = str_array_accumulate_length(array, count);
    u8 *str_buf = AllocateBytes(allocator, len + 1);

    size_t out_idx = 0;
    for (size_t i = 0; i < count; ++i)
    {
        MemoryCopy(str_buf + out_idx, array[i].str, array[i].len);
        out_idx += array[i].len;
    }

    str_buf[len] = 0;

    return str_from(str_buf, len);
}

String
str_array_join_sep(Allocator* allocator,
                        String *array,
                        size_t count,
                        String sep)
{
    size_t non_sep_len = str_array_accumulate_length(array, count);
    size_t sep_count = count - 1;
    size_t len = non_sep_len + (sep_count * sep.len);

    u8 *str_buf = AllocateBytes(allocator, len + 1);

    size_t out_idx = 0;
    for (size_t i = 0; i < count; ++i)
    {
        MemoryCopy(str_buf + out_idx, array[i].str, array[i].len);
        out_idx += array[i].len;

        if (i != count - 1)
        {
            MemoryCopy(str_buf + out_idx, sep.str, sep.len);
            out_idx += sep.len;
        }
    }

    return str_from(str_buf, len);
}

String str_substr(String string, size_t begin_idx, size_t len)
{
    size_t begin_idx_clamped = ClampTop(begin_idx, string.len);
    size_t end_idx = ClampTop(begin_idx + len, string.len);
    size_t actual_len = end_idx - begin_idx_clamped;
    return str_from(string.str + begin_idx_clamped, actual_len);
}

String str_concat(Allocator* allocator, String f, String s)
{
    String strings[] = { f, s };
    return str_array_join(allocator, strings, ArrLen(strings));
}

StringListNode* str_list_alloc_node(Allocator* allocator, String string)
{
    StringListNode *node = AllocateZero(allocator, StringListNode);
    node->string = string;
    return node;
}

void str_list_push_explicit(Allocator* allocator, StringList *str_list, StringListNode *node)
{
    DLLPushBack(str_list->head, str_list->tail, node);
}

void str_list_push(Allocator* allocator, StringList *str_list, String string)
{
    StringListNode *node = str_list_alloc_node(allocator, string);
    str_list_push_explicit(allocator, str_list, node);
}

StringList
str_split_pred(Allocator* allocator,
                         String str,
                         StringSplitPredFn pred,
                         void *data)
{
    StringList result = {0};

    size_t token_begin_idx = 0;
    size_t i = 0;

    while (i < str.len)
    {
        String rest = str_trunc_left(str, i);
        int skip = pred(rest, data);

        if (skip > 0) // delimiter hit
        {
            size_t tok_len = i - token_begin_idx;
            String token = str_substr(str, token_begin_idx, tok_len);
            str_list_push(allocator, &result, token);

            i += skip;
            token_begin_idx = i;
        }
        else
        {
            i++;
        }
    }

    if (token_begin_idx <= str.len) // just in case the predicate returns nonsense
    {
        size_t tok_len = str.len - token_begin_idx;
        String token = str_substr(str, token_begin_idx, tok_len);
        str_list_push(allocator, &result, token);
    }

    return result;
}

StringList
str_split_tokens_pred(Allocator* allocator,
                                String str,
                                StringSplitPredFn pred,
                                void *data)
{
    StringList result = {0};

    size_t token_begin_idx = 0;
    size_t i = 0;

    while (i < str.len)
    {
        String rest = str_trunc_left(str, i);
        int skip = pred(rest, data);

        if (skip > 0) // delimiter hit
        {
            size_t tok_len = i - token_begin_idx;
            if (tok_len > 0)
            {
                String token = str_substr(str, token_begin_idx, tok_len);
                str_list_push(allocator, &result, token);
            }

            i += skip;
            token_begin_idx = i;
        }
        else
        {
            i++;
        }
    }

    if (token_begin_idx <= str.len) // just in case the predicate returns nonsense
    {
        size_t tok_len = str.len - token_begin_idx;
        if (tok_len > 0)
        {
            String token = str_substr(str, token_begin_idx, tok_len);
            str_list_push(allocator, &result, token);
        }
    }

    return result;
}

static int split_by_str_pred(String rest, void *data)
{
    String sep = *(String *)data;
    String rest_substr = str_substr(rest, 0, sep.len);
    return str_eq(rest_substr, sep) ? sep.len : 0;
}

StringList str_split_by_str(Allocator* allocator, String str, String sep)
{
    return str_split_pred(allocator, str, split_by_str_pred, &sep);
}

static int split_by_char_pred(String rest, void *data)
{
    return str_front(rest) == *(char *)data ? 1 : 0;
}

StringList str_split_by_char(Allocator* allocator, String str, char sep)
{
    return str_split_pred(allocator, str, split_by_char_pred, &sep);
}

static int split_by_whitespace_pred(String rest, void *data)
{
    int i = 0;
    for (i = 0; i < rest.len; ++i)
    {
        if (!isspace(rest.str[i])) break;
    }
    return i;
}

StringList str_split_by_whitespace(Allocator* allocator, String str)
{
    return str_split_tokens_pred(allocator, str, split_by_whitespace_pred, NULL);
}

StringList str_split_by_lines(Allocator* allocator, String str)
{
    return str_split_by_char(allocator, str, '\n');
}

String str_formatv(Allocator* allocator, const char *fmt, va_list args)
{
    va_list args_copy;
    va_copy(args_copy, args);

    int len = vsnprintf(NULL, 0, fmt, args_copy);
    va_end(args_copy);

    if (len <= 0)
    {
        return str_invalid;
    }

    u8 *str_buf = AllocateBytes(allocator, len + 1);
    if (!str_buf)
    {
        return str_invalid;
    }

    vsnprintf((char*)str_buf, len + 1, fmt, args);

    return str_from(str_buf, len);
}

String str_format(Allocator* allocator, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    String result = str_formatv(allocator, fmt, args);
    va_end(args);
    return result;
}

