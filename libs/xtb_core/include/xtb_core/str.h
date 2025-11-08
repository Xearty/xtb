#ifndef _XTB_STR_H_
#define _XTB_STR_H_

#include <xtb_core/core.h>
#include <xtb_core/arena.h>
#include <xtb_core/allocator.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdarg.h>

XTB_C_LINKAGE_BEGIN

typedef struct XTB_String8
{
    char *str;
    size_t len;
} XTB_String8;

XTB_String8 xtb_str8(const char *str, size_t len);
#define xtb_str8_lit(cstring_literal) (XTB_String8){ (char *)cstring_literal, sizeof(cstring_literal) - 1 }
XTB_String8 xtb_str8_cstring(const char *cstring);
#define xtb_str8_cstring_copy(allocator, cstr) xtb_str8_copy((allocator), xtb_str8_cstring((cstr)))
XTB_String8 xtb_str8_copy(Allocator* allocator, XTB_String8 string);
#define xtb_str8_lit_copy(allocator, cstring_literal) xtb_str8_copy((allocator), xtb_str8_lit(cstring_literal))
XTB_String8 xtb_str8_push_copy(XTB_Arena *arena, XTB_String8 string);
void xtb_str8_free(Allocator* allocator, XTB_String8 str);
#define xtb_str8_empty xtb_str8_lit("")
#define xtb_str8_invalid xtb_str8(NULL, 0)
bool xtb_str8_is_invalid(XTB_String8 string);
bool xtb_str8_is_valid(XTB_String8 string);

char xtb_str8_front(XTB_String8 string);
char xtb_str8_back(XTB_String8 string);

int xtb_str8_compare(XTB_String8 f, XTB_String8 s);
bool xtb_str8_eq(XTB_String8 f, XTB_String8 s);
bool xtb_str8_eq_cstring(XTB_String8 f, const char *s);
#define xtb_str8_eq_lit(f, s) xtb_str8_eq((f), xtb_str8_lit(s))

bool xtb_str8_starts_with(XTB_String8 string, XTB_String8 prefix);
#define xtb_str8_starts_with_lit(string, prefix) xtb_str8_starts_with((string), xtb_str8_lit(prefix))
bool xtb_str8_ends_with(XTB_String8 string, XTB_String8 postfix);
#define xtb_str8_ends_with_lit(string, postfix) xtb_str8_ends_with((string), xtb_str8_lit(postfix))

XTB_String8 xtb_str8_head(XTB_String8 string, size_t count);
XTB_String8 xtb_str8_tail(XTB_String8 string, size_t count);

XTB_String8 xtb_str8_trunc_left(XTB_String8 string, size_t count);
XTB_String8 xtb_str8_trunc_right(XTB_String8 string, size_t count);

XTB_String8 xtb_str8_trim_left(XTB_String8 string);
XTB_String8 xtb_str8_trim_right(XTB_String8 string);
XTB_String8 xtb_str8_trim(XTB_String8 string);
#define xtb_str8_trim_copy(allocator, string) xtb_str8_copy((allocator), xtb_str8_trim(string))

XTB_String8 xtb_str8_substr(XTB_String8 string, size_t begin_idx, size_t len);
#define xtb_str8_substr_copy(allocator, string, begin_idx, len) \
    xtb_str8_copy((allocator), xtb_str8_substr((string), (begin_idx), (len)))

XTB_String8 xtb_str8_concat(Allocator* allocator, XTB_String8 f, XTB_String8 s);
#define xtb_str8_concat_lit(allocator, f, s) xtb_str8_concat((allocator), (f), xtb_str8_lit(s))

size_t xtb_str8_array_accumulate_length(XTB_String8 *array, size_t count);
XTB_String8 xtb_str8_array_join(Allocator* allocator, XTB_String8 *array, size_t count);
XTB_String8 xtb_str8_array_join_sep(Allocator* allocator, XTB_String8 *array, size_t count, XTB_String8 sep);

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

XTB_String8_List_Node *xtb_str8_list_alloc_node(Allocator* allocator, XTB_String8 string);
void xtb_str8_list_push_explicit(Allocator* allocator, XTB_String8_List *str_list, XTB_String8_List_Node *node);
void xtb_str8_list_push(Allocator* allocator, XTB_String8_List *str_list, XTB_String8 string);
size_t xtb_str8_list_length(XTB_String8_List str_list);
size_t xtb_str8_list_accumulate_length(XTB_String8_List str_list);
XTB_String8 xtb_str8_list_join(Allocator* allocator, XTB_String8_List str_list);
XTB_String8 xtb_str8_list_join_str_sep(Allocator* allocator, XTB_String8_List str_list, XTB_String8 sep);
XTB_String8 xtb_str8_list_join_char_sep(Allocator* allocator, XTB_String8_List str_list, char sep);

// NOTE: Return types tells you how many bytes to skip
typedef int(*XTB_String8_Split_Pred_Fn)(XTB_String8 rest, void *data);

XTB_String8_List xtb_str8_split_pred(Allocator* allocator, XTB_String8 str, XTB_String8_Split_Pred_Fn pred, void *data);
XTB_String8_List xtb_str8_split_tokens_pred(Allocator* allocator, XTB_String8 str, XTB_String8_Split_Pred_Fn pred, void *data);
XTB_String8_List xtb_str8_split_by_str(Allocator* allocator, XTB_String8 str, XTB_String8 sep);
XTB_String8_List xtb_str8_split_by_char(Allocator* allocator, XTB_String8 str, char sep);
XTB_String8_List xtb_str8_split_by_whitespace(Allocator* allocator, XTB_String8 str);
XTB_String8_List xtb_str8_split_by_lines(Allocator* allocator, XTB_String8 str);

XTB_String8 xtb_str8_formatv(Allocator* allocator, const char *fmt, va_list args);
XTB_String8 xtb_str8_format(Allocator* allocator, const char *fmt, ...);

#define xtb_str8_debug(s) fprintf(stderr, "%.*s\n", (int)(s).len, (s).str)

#define xtb_str8_assert_null_terminated(string) \
    XTB_ASSERT((string).str[(string).len] == '\0')

#ifdef XTB_STR_SHORTHANDS
typedef XTB_String8 String8;
typedef XTB_String8_List String8_List;
typedef XTB_String8_List_Node String8_List_Node;

#define str8                         xtb_str8
#define str8_cstring                 xtb_str8_cstring
#define str8_cstring_copy            xtb_str8_cstring_copy
#define str8_lit                     xtb_str8_lit
#define str8_copy                    xtb_str8_copy
#define str8_lit_copy                xtb_str8_lit_copy
#define str8_free                    xtb_str8_free
#define str8_empty                   xtb_str8_empty
#define str8_invalid                 xtb_str8_invalid
#define str8_is_invalid              xtb_str8_is_invalid
#define str8_is_valid                xtb_str8_is_valid
#define str8_front                   xtb_str8_front
#define str8_back                    xtb_str8_back
#define str8_compare                 xtb_str8_compare
#define str8_eq                      xtb_str8_eq
#define str8_eq_cstring              xtb_str8_eq_cstring
#define str8_eq_lit                  xtb_str8_eq_lit
#define str8_starts_with             xtb_str8_starts_with
#define str8_starts_with_lit         xtb_str8_starts_with_lit
#define str8_ends_with               xtb_str8_ends_with
#define str8_ends_with_lit           xtb_str8_ends_with_lit
#define str8_head                    xtb_str8_head
#define str8_tail                    xtb_str8_tail
#define str8_trunc_left              xtb_str8_trunc_left
#define str8_trunc_right             xtb_str8_trunc_right
#define str8_trim_left               xtb_str8_trim_left
#define str8_trim_right              xtb_str8_trim_right
#define str8_trim                    xtb_str8_trim
#define str8_trim_copy               xtb_str8_trim_copy
#define str8_substr                  xtb_str8_substr
#define str8_substr_copy             xtb_str8_substr_copy
#define str8_concat                  xtb_str8_concat
#define str8_concat_lit              xtb_str8_concat_lit
#define str8_array_accumulate_length xtb_str8_array_accumulate_length
#define str8_array_join              xtb_str8_array_join
#define str8_array_join_sep          xtb_str8_array_join_sep
#define str8_list_alloc_node         xtb_str8_list_alloc_node
#define str8_list_push_explicit      xtb_str8_list_push_explicit
#define str8_list_push               xtb_str8_list_push
#define str8_list_length             xtb_str8_list_length
#define str8_list_accumulate_length  xtb_str8_list_accumulate_length
#define str8_list_join               xtb_str8_list_join
#define str8_list_join_str_sep       xtb_str8_list_join_str_sep
#define str8_list_join_char_sep      xtb_str8_list_join_char_sep
#define str8_split_pred              xtb_str8_split_pred
#define str8_split_tokens_pred       xtb_str8_split_tokens_pred
#define str8_split_by_str            xtb_str8_split_by_str
#define str8_split_by_char           xtb_str8_split_by_char
#define str8_split_by_whitespace     xtb_str8_split_by_whitespace
#define str8_split_by_lines          xtb_str8_split_by_lines
#define str8_formatv                 xtb_str8_formatv
#define str8_format                  xtb_str8_format
#define str8_debug                   xtb_str8_debug
#define str8_assert_null_terminated  xtb_str8_assert_null_terminated
#endif

XTB_C_LINKAGE_END

#endif // _XTB_STR_H_
