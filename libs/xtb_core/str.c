#include "str.h"
#include "core.h"
#include "linked_list.h"

#include <string.h>
#include <stdio.h>
#include <ctype.h>

XTB_String8 xtb_str8(const char *str, size_t len)
{
    return (XTB_String8){ (char*)str, len };
}

XTB_String8 xtb_str8_cstring(const char *cstring)
{
    size_t len = strlen(cstring);
    return xtb_str8(cstring, len);
}

XTB_String8 xtb_str8_copy(XTB_Allocator allocator, XTB_String8 string)
{
    char *buf = XTB_AllocateArray(allocator, char, string.len + 1);
    strncpy(buf, string.str, string.len)[string.len] = '\0';
    return xtb_str8(buf, string.len);
}

void xtb_str8_free(XTB_Allocator allocator, XTB_String8 str)
{
    XTB_Deallocate(allocator, str.str);
}

bool xtb_str8_is_invalid(XTB_String8 string)
{
    return string.str == NULL;
}

bool xtb_str8_is_valid(XTB_String8 string)
{
    return !xtb_str8_is_invalid(string);
}

char xtb_str8_front(XTB_String8 string)
{
    return string.str[0];
}

char xtb_str8_back(XTB_String8 string)
{
    return string.str[string.len - 1];
}

int xtb_str8_compare(XTB_String8 f, XTB_String8 s)
{
    return strncmp(f.str, s.str, XTB_Max(f.len, s.len));
}

bool xtb_str8_eq(XTB_String8 f, XTB_String8 s)
{
    if (f.len != s.len) return false;
    return xtb_str8_compare(f, s) == 0;
}

bool xtb_str8_eq_cstring(XTB_String8 f, const char *s)
{
    return xtb_str8_eq(f, xtb_str8_cstring(s));
}

XTB_String8 xtb_str8_trunc_left(XTB_String8 string, size_t count)
{
    return xtb_str8_substr(string, count, string.len - count);
}

XTB_String8 xtb_str8_trunc_right(XTB_String8 string, size_t count)
{
    return xtb_str8_substr(string, 0, string.len - count);
}

XTB_String8 xtb_str8_trim_left(XTB_String8 string)
{
    int i;
    for (i = 0; i < string.len; ++i)
    {
        if (!isspace(string.str[i])) break;
    }
    return xtb_str8_trunc_left(string, i);
}

XTB_String8 xtb_str8_trim_right(XTB_String8 string)
{
    int i;
    for (i = string.len - 1; i >= 0; --i)
    {
        if (!isspace(string.str[i])) break;
    }
    int count = (int)string.len - 1 - i;
    return xtb_str8_trunc_right(string, count);
}

XTB_String8 xtb_str8_trim(XTB_String8 string)
{
    return xtb_str8_trim_left(xtb_str8_trim_right(string));
}

size_t xtb_str8_list_length(XTB_String8_List str_list)
{
    size_t len = 0;
    XTB_IterateList(str_list, XTB_String8_List_Node, node, len += 1);
    return len;
}

size_t xtb_str8_list_accumulate_length(XTB_String8_List str_list)
{
    size_t len = 0;
    XTB_IterateList(str_list, XTB_String8_List_Node, node, len += node->string.len);
    return len;
}

XTB_String8 xtb_str8_list_join(XTB_Allocator allocator, XTB_String8_List str_list)
{
    return xtb_str8_list_join_str_sep(allocator, str_list, xtb_str8_empty);
}

XTB_String8 xtb_str8_list_join_str_sep(XTB_Allocator allocator, XTB_String8_List str_list, XTB_String8 sep)
{
    // TODO(xearty): Do these two in one pass
    size_t non_sep_len = xtb_str8_list_accumulate_length(str_list);
    size_t count = xtb_str8_list_length(str_list);
    size_t sep_count = count - 1;
    size_t len = non_sep_len + (sep_count * sep.len);

    char *str_buf = XTB_AllocateBytes(allocator, len + 1);

    size_t out_idx = 0;
    XTB_IterateList(str_list, XTB_String8_List_Node, node,
    {
        XTB_MemoryCopy(str_buf + out_idx, node->string.str, node->string.len);
        out_idx += node->string.len;

        if (node != str_list.tail)
        {
            XTB_MemoryCopy(str_buf + out_idx, sep.str, sep.len);
            out_idx += sep.len;
        }
    });

    return xtb_str8(str_buf, len);
}

XTB_String8 xtb_str8_list_join_char_sep(XTB_Allocator allocator, XTB_String8_List str_list, char sep)
{
    return xtb_str8_list_join_str_sep(allocator, str_list, xtb_str8(&sep, 1));
}

size_t xtb_str8_array_accumulate_length(XTB_String8 *array, size_t count)
{
    size_t len = 0;
    for (size_t i = 0; i < count; ++i) len += array[i].len;
    return len;
}

XTB_String8 xtb_str8_array_join(XTB_Allocator allocator, XTB_String8 *array, size_t count)
{
    size_t len = xtb_str8_array_accumulate_length(array, count);
    char *str_buf = XTB_AllocateBytes(allocator, len + 1);

    size_t out_idx = 0;
    for (size_t i = 0; i < count; ++i)
    {
        XTB_MemoryCopy(str_buf + out_idx, array[i].str, array[i].len);
        out_idx += array[i].len;
    }

    return xtb_str8(str_buf, len);
}

XTB_String8
xtb_str8_array_join_sep(XTB_Allocator allocator,
                        XTB_String8 *array,
                        size_t count,
                        XTB_String8 sep)
{
    size_t non_sep_len = xtb_str8_array_accumulate_length(array, count);
    size_t sep_count = count - 1;
    size_t len = non_sep_len + (sep_count * sep.len);

    char *str_buf = XTB_AllocateBytes(allocator, len + 1);

    size_t out_idx = 0;
    for (size_t i = 0; i < count; ++i)
    {
        XTB_MemoryCopy(str_buf + out_idx, array[i].str, array[i].len);
        out_idx += array[i].len;

        if (i != count - 1)
        {
            XTB_MemoryCopy(str_buf + out_idx, sep.str, sep.len);
            out_idx += sep.len;
        }
    }

    return xtb_str8(str_buf, len);
}

XTB_String8 xtb_str8_substr(XTB_String8 string, size_t begin_idx, size_t len)
{
    size_t begin_idx_clamped = XTB_ClampTop(begin_idx, string.len);
    size_t end_idx = XTB_ClampTop(begin_idx + len, string.len);
    size_t actual_len = end_idx - begin_idx_clamped;
    return xtb_str8(string.str + begin_idx_clamped, actual_len);
}

XTB_String8_List_Node* xtb_str8_list_alloc_node(XTB_Allocator allocator, XTB_String8 string)
{
    XTB_String8_List_Node *node = XTB_AllocateZero(allocator, XTB_String8_List_Node);
    node->string = string;
    return node;
}

void xtb_str8_list_push(XTB_Allocator allocator, XTB_String8_List *str_list, XTB_String8 string)
{
    XTB_String8_List_Node *node = xtb_str8_list_alloc_node(allocator, string);
    DLLPushBack(str_list->head, str_list->tail, node);
}

XTB_String8_List
xtb_str8_list_split_pred(XTB_Allocator allocator,
                         XTB_String8 str,
                         XTB_String8_Split_Pred_Fn pred,
                         void *data)
{
    XTB_String8_List result = {0};

    int token_begin_idx = 0;

    for (int i = 0; i < str.len;)
    {
        XTB_String8 rest = xtb_str8_substr(str, i, str.len);

        int skip = pred(rest, data);
        if (skip != 0 || i == str.len - 1)
        {
            if (i == str.len - 1) i += 1; // We've reached the end, increment to meet
                                          // the loop condition and get the correct length

            size_t tok_len = i - token_begin_idx;
            if (tok_len > 0)
            {
                XTB_String8 token = xtb_str8_substr(str, token_begin_idx, tok_len);
                xtb_str8_list_push(allocator, &result, token);
            }
            token_begin_idx = i + skip;
            i += skip;
        }
        else
        {
            i += 1;
        }
    }

    return result;
}

static int split_by_str_pred(XTB_String8 rest, void *data)
{
    XTB_String8 sep = *(XTB_String8 *)data;
    XTB_String8 rest_substr = xtb_str8_substr(rest, 0, sep.len);
    return xtb_str8_eq(rest_substr, sep) ? sep.len : 0;
}

XTB_String8_List xtb_str8_list_split_by_str(XTB_Allocator allocator, XTB_String8 str, XTB_String8 sep)
{
    return xtb_str8_list_split_pred(allocator, str, split_by_str_pred, &sep);
}

static int split_by_char_pred(XTB_String8 rest, void *data)
{
    return xtb_str8_front(rest) == *(char *)data ? 1 : 0;
}

XTB_String8_List xtb_str8_list_split_by_char(XTB_Allocator allocator, XTB_String8 str, char sep)
{
    return xtb_str8_list_split_pred(allocator, str, split_by_char_pred, &sep);
}

static int split_by_whitespace_pred(XTB_String8 rest, void *data)
{
    int i = 0;
    for (i = 0; i < rest.len; ++i)
    {
        if (!isspace(rest.str[i])) break;
    }
    return i;
}

XTB_String8_List xtb_str8_list_split_by_whitespace(XTB_Allocator allocator, XTB_String8 str)
{
    return xtb_str8_list_split_pred(allocator, str, split_by_whitespace_pred, NULL);
}

XTB_String8 xtb_str8_formatv(XTB_Allocator allocator, const char *fmt, va_list args)
{
    va_list args_copy;
    va_copy(args_copy, args);

    int len = vsnprintf(NULL, 0, fmt, args_copy);
    va_end(args_copy);

    if (len <= 0)
    {
        return xtb_str8_invalid;
    }

    char *str_buf = XTB_AllocateBytes(allocator, len + 1);
    if (!str_buf)
    {
        return xtb_str8_invalid;
    }

    vsnprintf(str_buf, len + 1, fmt, args);

    return xtb_str8(str_buf, len);
}

XTB_String8 xtb_str8_format(XTB_Allocator allocator, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    XTB_String8 result = xtb_str8_formatv(allocator, fmt, args);
    va_end(args);
    return result;
}

