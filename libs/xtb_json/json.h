#ifndef _XTB_JSON_H_
#define _XTB_JSON_H_

#include <xtb_da/da.h>
#include <xtb_core/str.h>
#include <stdbool.h>
#include <stdio.h>

typedef enum
{
    XTB_JSON_NULL,
    XTB_JSON_BOOL,
    XTB_JSON_NUMBER,
    XTB_JSON_STRING,
    XTB_JSON_ARRAY,
    XTB_JSON_OBJECT
} XTB_JSON_Type;

typedef struct XTB_JSON_Value XTB_JSON_Value;

XTB_DA_DEFINE_TYPE(XTB_JSON_Array, XTB_JSON_Value*);

typedef struct XTB_JSON_Pair
{
    XTB_String8 key;
    XTB_JSON_Value *value;
    struct XTB_JSON_Pair *next;
} XTB_JSON_Pair;

struct XTB_JSON_Value
{
    XTB_JSON_Type type;
    union {
        double number;
        bool boolean;
        XTB_String8 string;
        XTB_JSON_Array array;
        XTB_JSON_Pair* object; // TODO: think if this should be pointer
    } as;
};

/****************************************************************
 * Parsing API
****************************************************************/
XTB_JSON_Value *xtb_json_parse(const char *input);
XTB_JSON_Value *xtb_json_parse_file(XTB_String8 filepath);

/****************************************************************
 * Getters
****************************************************************/
XTB_JSON_Value *xtb_json_object_get_key(XTB_JSON_Value *value, const char *key);
XTB_JSON_Value *xtb_json_array_get_index(XTB_JSON_Value *value, size_t index);
XTB_JSON_Value *xtb_json_object_get_key_chain(XTB_JSON_Value *value, const char *key);
XTB_JSON_Value *xtb_json_array_get_index_chain(XTB_JSON_Value *value, size_t index);
XTB_JSON_Value *xtb_json_object_get_key_lt(XTB_JSON_Value *value, const char *key, int length);
XTB_JSON_Value *xtb_json_object_get_key_lt_chain(XTB_JSON_Value *value, const char *key, int length);

// Query json objects and arrays with basic jq syntax
XTB_JSON_Value *xtb_json_query(XTB_JSON_Value *value, const char *query);

size_t xtb_json_array_get_length(const XTB_JSON_Value *value);
size_t xtb_json_object_get_num_keys(const XTB_JSON_Value *value);

const char *xtb_json_get_type_string(const XTB_JSON_Value *value);

/****************************************************************
 * Predicates
****************************************************************/
bool xtb_json_value_is_null(const XTB_JSON_Value *value);
bool xtb_json_value_is_bool(const XTB_JSON_Value *value);
bool xtb_json_value_is_number(const XTB_JSON_Value *value);
bool xtb_json_value_is_string(const XTB_JSON_Value *value);
bool xtb_json_value_is_array(const XTB_JSON_Value *value);
bool xtb_json_value_is_object(const XTB_JSON_Value *value);

bool xtb_json_array_is_homogeneous(XTB_JSON_Value *value);
bool xtb_json_array_is_homogeneous_type(XTB_JSON_Value *value, XTB_JSON_Type type);
bool xtb_json_array_is_homogeneous_null(XTB_JSON_Value *value);
bool xtb_json_array_is_homogeneous_bool(XTB_JSON_Value *value);
bool xtb_json_array_is_homogeneous_number(XTB_JSON_Value *value);
bool xtb_json_array_is_homogeneous_string(XTB_JSON_Value *value);
bool xtb_json_array_is_homogeneous_array(XTB_JSON_Value *value);
bool xtb_json_array_is_homogeneous_object(XTB_JSON_Value *value);

bool xtb_json_array_contains_array(const XTB_JSON_Value *value);
bool xtb_json_array_contains_object(const XTB_JSON_Value *value);

/****************************************************************
 * Pretty printing
****************************************************************/
void xtb_json_print_value(const XTB_JSON_Value *value, FILE *stream);
void xtb_json_pretty_print_value(const XTB_JSON_Value *value, int indent, FILE *stream);

#endif // _XTB_JSON_H_
