#include "str.h"
#include "core.h"
#include "linked_list.h"

#include <string.h>

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
    size_t len = xtb_str8_list_accumulate_length(str_list);
    char *str_buf = XTB_AllocateBytes(allocator, len + 1);

    size_t out_idx = 0;
    XTB_IterateList(str_list, XTB_String8_List_Node, node,
    {
        XTB_MemoryCopy(str_buf + out_idx, node->string.str, node->string.len);
        out_idx += node->string.len;
    });
    str_buf[len] = '\0';

    return xtb_str8(str_buf, len);
}

XTB_String8 xtb_str8_list_join_sep(XTB_Allocator allocator, XTB_String8_List str_list, XTB_String8 sep)
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

XTB_String8 xtb_str8_substr_copy(XTB_Allocator allocator, XTB_String8 string, size_t begin_idx, size_t len)
{
    return xtb_str8_copy(allocator, xtb_str8_substr(string, begin_idx, len));
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
