#ifndef _XTB_STR_H_
#define _XTB_STR_H_

#include <xtb_core/core.h>
#include <xtb_core/arena.h>
#include <xtb_core/allocator.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdarg.h>

C_LINKAGE_BEGIN

typedef struct String
{
    char *str;
    size_t len;
} String;

String str_from(const char *str, usize len);
#define str(cstring_literal) (String){ (char *)cstring_literal, sizeof(cstring_literal) - 1 }
String cstr(const char *cstring);

#define cstr_copy(allocator, cstring) str_copy((allocator), cstr((cstring)))
String str_copy(Allocator* allocator, String string);
// #define str_lit_copy(allocator, cstring_literal) str_copy((allocator), str(cstring_literal))
String str_push_copy(Arena *arena, String string);
void str_free(Allocator* allocator, String str);
#define str_empty str("")
#define str_invalid str_from(NULL, 0)
bool str_is_invalid(String string);
bool str_is_valid(String string);

char str_front(String string);
char str_back(String string);

int str_compare(String f, String s);
bool str_eq(String f, String s);
bool str_eq_cstring(String f, const char *s);
#define str_eq_lit(f, s) str_eq((f), str(s))

bool str_starts_with(String string, String prefix);
#define str_starts_with_lit(string, prefix) str_starts_with((string), str(prefix))
bool str_ends_with(String string, String postfix);
#define str_ends_with_lit(string, postfix) str_ends_with((string), str(postfix))

String str_head(String string, size_t count);
String str_tail(String string, size_t count);

String str_trunc_left(String string, size_t count);
String str_trunc_right(String string, size_t count);

String str_trim_left(String string);
String str_trim_right(String string);
String str_trim(String string);
#define str_trim_copy(allocator, string) str_copy((allocator), str_trim(string))

String str_substr(String string, size_t begin_idx, size_t len);
#define str_substr_copy(allocator, string, begin_idx, len) \
    str_copy((allocator), str_substr((string), (begin_idx), (len)))

String str_concat(Allocator* allocator, String f, String s);
#define str_concat_lit(allocator, f, s) str_concat((allocator), (f), str(s))

size_t str_array_accumulate_length(String *array, size_t count);
String str_array_join(Allocator* allocator, String *array, size_t count);
String str_array_join_sep(Allocator* allocator, String *array, size_t count, String sep);

typedef struct StringListNode
{
    String string;
    struct StringListNode *prev;
    struct StringListNode *next;
} StringListNode;

typedef struct StringList
{
    StringListNode *head;
    StringListNode *tail;
} StringList;

StringListNode *str_list_alloc_node(Allocator* allocator, String string);
void str_list_push_explicit(Allocator* allocator, StringList *str_list, StringListNode *node);
void str_list_push(Allocator* allocator, StringList *str_list, String string);
size_t str_list_length(StringList str_list);
size_t str_list_accumulate_length(StringList str_list);
String str_list_join(Allocator* allocator, StringList str_list);
String str_list_join_str_sep(Allocator* allocator, StringList str_list, String sep);
String str_list_join_char_sep(Allocator* allocator, StringList str_list, char sep);

// NOTE: Return types tells you how many bytes to skip
typedef int(*StringSplitPredFn)(String rest, void *data);

StringList str_split_pred(Allocator* allocator, String str, StringSplitPredFn pred, void *data);
StringList str_split_tokens_pred(Allocator* allocator, String str, StringSplitPredFn pred, void *data);
StringList str_split_by_str(Allocator* allocator, String str, String sep);
StringList str_split_by_char(Allocator* allocator, String str, char sep);
StringList str_split_by_whitespace(Allocator* allocator, String str);
StringList str_split_by_lines(Allocator* allocator, String str);

String str_formatv(Allocator* allocator, const char *fmt, va_list args);
String str_format(Allocator* allocator, const char *fmt, ...);

#define str_debug(s) fprintf(stderr, "%.*s\n", (int)(s).len, (s).str)

#define str_assert_null_terminated(string) \
    ASSERT((string).str[(string).len] == '\0')

C_LINKAGE_END

#endif // _XTB_STR_H_
