#ifndef _XTB_STR_H_
#define _XTB_STR_H_

#include "allocator.h"
#include <stddef.h>
#include <stdbool.h>

typedef struct XTB_String8
{
    char *str;
    size_t len;
} XTB_String8;

XTB_String8 xtb_str8(const char *str, size_t len);
XTB_String8 xtb_str8_cstring(const char *cstring);
XTB_String8 xtb_str8_copy(XTB_Allocator allocator, XTB_String8 string);
void xtb_str8_free(XTB_Allocator allocator, XTB_String8 str);
bool xtb_str8_is_invalid(XTB_String8 string);
bool xtb_str8_is_valid(XTB_String8 string);

char xtb_str8_front(XTB_String8 string);
char xtb_str8_back(XTB_String8 string);

int xtb_str8_compare(XTB_String8 f, XTB_String8 s);
bool xtb_str8_eq(XTB_String8 f, XTB_String8 s);
bool xtb_str8_eq_cstring(XTB_String8 f, const char *s);
#define xtb_str8_eq_lit(f, s) xtb_str8_eq((f), xtb_str8_lit(s))

XTB_String8 xtb_str8_trunc_left(XTB_String8 string, size_t count);
XTB_String8 xtb_str8_trunc_right(XTB_String8 string, size_t count);

XTB_String8 xtb_str8_trim_left(XTB_String8 string);
XTB_String8 xtb_str8_trim_right(XTB_String8 string);
XTB_String8 xtb_str8_trim(XTB_String8 string);
#define xtb_str8_trim_copy(allocator, string) xtb_str8_copy((allocator), xtb_str8_trim(string))

XTB_String8 xtb_str8_substr(XTB_String8 string, size_t begin_idx, size_t len);
#define xtb_str8_substr_copy(allocator, string, begin_idx, len) \
    xtb_str8_copy((allocator), xtb_str8_substr((string), (begin_idx), (len)))

size_t xtb_str8_array_accumulate_length(XTB_String8 *array, size_t count);
XTB_String8 xtb_str8_array_join(XTB_Allocator allocator, XTB_String8 *array, size_t count);
XTB_String8 xtb_str8_array_join_sep(XTB_Allocator allocator, XTB_String8 *array, size_t count, XTB_String8 sep);

#define xtb_str8_lit(cstring_literal) \
    (XTB_String8){ cstring_literal, sizeof(cstring_literal) - 1 }

#define xtb_str8_empty xtb_str8_lit("")

#define xtb_str8_lit_copy(allocator, cstring_literal) xtb_str8_copy((allocator), xtb_str8_lit(cstring_literal))

#define xtb_str8_invalid xtb_str8(NULL, 0)

typedef struct XTB_String8_List_Node
{
    XTB_String8 string;
    struct XTB_String8_List_Node *prev;
    struct XTB_String8_List_Node *next;
} XTB_String8_List_Node;

typedef struct XTB_String8_List
{
    XTB_String8_List_Node *head;
    XTB_String8_List_Node *tail;
} XTB_String8_List;

XTB_String8_List_Node *xtb_str8_list_alloc_node(XTB_Allocator allocator, XTB_String8 string);
void xtb_str8_list_push(XTB_Allocator allocator, XTB_String8_List *str_list, XTB_String8 string);
size_t xtb_str8_list_length(XTB_String8_List str_list);
size_t xtb_str8_list_accumulate_length(XTB_String8_List str_list);
XTB_String8 xtb_str8_list_join(XTB_Allocator allocator, XTB_String8_List str_list);
XTB_String8 xtb_str8_list_join_sep(XTB_Allocator allocator, XTB_String8_List str_list, XTB_String8 sep);

#endif // _XTB_STR_H_
