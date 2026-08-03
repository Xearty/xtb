#ifndef _XTB_JSON_H_
#define _XTB_JSON_H_

#include <xtb_core/string.h>
#include <xtb_core/array.h>
#include <stdbool.h>
#include <stdio.h>

namespace xtb
{

enum JsonType
{
    JSON_NULL,
    JSON_BOOL,
    JSON_NUMBER,
    JSON_STRING,
    JSON_ARRAY,
    JSON_OBJECT
};

struct JsonValue;

using JsonArray = Array<JsonValue*>;

struct JsonPair
{
    String key;
    JsonValue *value;
    struct JsonPair *next;
};

struct JsonValue
{
    JsonType type;
    union {
        double number;
        bool boolean;
        String string;
        JsonArray array;
        JsonPair* object; // TODO: think if this should be pointer
    } as;
};

/****************************************************************
 * Parsing API
****************************************************************/
JsonValue *json_parse(const char *input);
JsonValue *json_parse_file(String filepath);

/****************************************************************
 * Getters
****************************************************************/
JsonValue *json_object_get_key(JsonValue *value, const char *key);
JsonValue *json_array_get_index(JsonValue *value, size_t index);
JsonValue *json_object_get_key_chain(JsonValue *value, const char *key);
JsonValue *json_array_get_index_chain(JsonValue *value, size_t index);
JsonValue *json_object_get_key_lt(JsonValue *value, const char *key, int length);
JsonValue *json_object_get_key_lt_chain(JsonValue *value, const char *key, int length);

// Query json objects and arrays with basic jq syntax
JsonValue *json_query(JsonValue *value, const char *query);

size_t json_array_get_length(const JsonValue *value);
size_t json_object_get_num_keys(const JsonValue *value);

const char *json_get_type_string(const JsonValue *value);

/****************************************************************
 * Predicates
****************************************************************/
bool json_value_is_null(const JsonValue *value);
bool json_value_is_bool(const JsonValue *value);
bool json_value_is_number(const JsonValue *value);
bool json_value_is_string(const JsonValue *value);
bool json_value_is_array(const JsonValue *value);
bool json_value_is_object(const JsonValue *value);

bool json_array_is_homogeneous(JsonValue *value);
bool json_array_is_homogeneous_type(JsonValue *value, JsonType type);
bool json_array_is_homogeneous_null(JsonValue *value);
bool json_array_is_homogeneous_bool(JsonValue *value);
bool json_array_is_homogeneous_number(JsonValue *value);
bool json_array_is_homogeneous_string(JsonValue *value);
bool json_array_is_homogeneous_array(JsonValue *value);
bool json_array_is_homogeneous_object(JsonValue *value);

bool json_array_contains_array(const JsonValue *value);
bool json_array_contains_object(const JsonValue *value);

/****************************************************************
 * Pretty printing
****************************************************************/
void json_print_value(const JsonValue *value, FILE *stream);
void json_pretty_print_value(const JsonValue *value, int indent, FILE *stream);

}

#endif // _XTB_JSON_H_
