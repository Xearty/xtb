#include "json.h"
#include <xtb_core/allocator.h>
#include <xtb_core/contract.h>

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <xtb_os/os.h>
#include <xtb_ansi/ansi.h>
#include <xtb_core/core.h>
#include <xtb_core/linked_list.h>

/****************************************************************
 * Utilities (internal)
****************************************************************/
static bool is_whitespace(char sym)
{
    return (sym == ' ' || sym == '\t' || sym == '\n' || sym == '\r');
}

static const char* skip_whitespace(const char *input)
{
    while (is_whitespace(*input))
    {
        input += 1;
    }

    return input;
}

static bool is_digit(char ch)
{
    return (ch >= '0' && ch <= '9');
}

static String parse_string_literal(const char *input)
{
    const char *rest = input;

    if (rest[0] != '\"')
    {
        return str_invalid;
    }
    rest += 1;

    const char *string_begin = rest;

    while (rest[0] != '\"') rest += 1;
    ASSERT(rest[0] == '\"');

    const char *string_end = rest;
    int string_len = string_end - string_begin;
    String substr = str_from(string_begin, string_len);
    return str_copy(allocator_get_heap(), substr);
}

static void indent(int indentation, int level, FILE *stream)
{
    int indent_spaces = level * indentation;
    for (int i = 0; i < indent_spaces; ++i) fprintf(stream, " ");
}

/****************************************************************
 * Value initializers (internal)
****************************************************************/
static JsonValue* make_json_value(JsonType type)
{
    JsonValue *value = calloc(1, sizeof(JsonValue));
    value->type = type;
    return value;
}

static JsonValue* make_json_null()
{
    return make_json_value(JSON_NULL);
}

static JsonValue* make_json_bool(bool boolean_value)
{
    JsonValue *value = make_json_value(JSON_BOOL);
    value->as.boolean = boolean_value;
    return value;
}

static JsonValue *make_json_number(double number)
{
    JsonValue *value = make_json_value(JSON_NUMBER);
    value->as.number = number;
    return value;
}

static JsonValue *make_json_string(String string)
{
    JsonValue *value = make_json_value(JSON_STRING);
    value->as.string = string;
    return value;
}

static JsonValue* make_json_array(JsonArray array)
{
    JsonValue *value = make_json_value(JSON_ARRAY);
    value->as.array = array;
    return value;
}

static JsonValue *make_object(JsonPair *first_pair)
{
    JsonValue *value = make_json_value(JSON_OBJECT);
    value->as.object = first_pair;
    return value;
}

// steals the buffers
static JsonPair *make_pair(String key, JsonValue *value)
{
    JsonPair *pair = (JsonPair*)calloc(1, sizeof(JsonPair));
    pair->key = key;
    pair->value = value;
    pair->next = NULL;
    return pair;
}

/****************************************************************
 * Value parsers (internal)
****************************************************************/
static const char *parse_value(const char *input, JsonValue **out);

static const char* parse_null(const char *input, JsonValue **out)
{
    input = skip_whitespace(input);

    if (strncmp(input, "null", 4) == 0)
    {
        input += 4;
        *out = make_json_null();
    }

    return input;
}

static const char* parse_boolean(const char *input, JsonValue **out)
{
    input = skip_whitespace(input);

    if (strncmp(input, "true", 4) == 0)
    {
        input += 4;
        *out = make_json_bool(true);
    }
    else if (strncmp(input, "false", 5) == 0)
    {
        input += 5;
        *out = make_json_bool(false);
    }

    return input;
}

static const char* parse_number(const char *input, JsonValue **out)
{
    input = skip_whitespace(input);

    char *end;
    double number = strtod(input, &end);
    if (end != input)
    {
        *out = make_json_number(number);
        input = end;
    }

    return input;
}

static const char *parse_string(const char *input, JsonValue **out)
{
    const char *rest = input;
    rest = skip_whitespace(rest);

    String string = parse_string_literal(rest);
    if (str_is_valid(string))
    {
        *out = make_json_string(string);
        return rest + string.len + 2; // 2 for the quotes
    }

    return input;
}

static const char *parse_array(const char *input, JsonValue **out)
{
    input = skip_whitespace(input);

    const char *rest = input;

    if (rest[0] != '[')
    {
        return input;
    }

    rest += 1; // skip [

    JsonArray array = make_array(allocator_get_heap());

    while (true)
    {
        rest = skip_whitespace(rest);
        if (rest[0] == ']') break;

        JsonValue *value = NULL;
        const char *end_of_value = parse_value(rest, &value);

        if (value == NULL)
        {
            array_deinit(&array);
            return input;
        }
        else
        {
            array_push(&array, value);
            rest = end_of_value;
            rest = skip_whitespace(rest);
            if (rest[0] == ',')
            {
                rest += 1; // skip ,

                // There must not be a comma before ]
                rest = skip_whitespace(rest);
                if (rest[0] == ']')
                {
                    return NULL;
                }
            }
            else
            {
                // There must be a comma if this item is not the last one
                rest = skip_whitespace(rest);
                if (rest[0] != ']')
                {
                    return NULL;
                }
            }
        }

        rest = skip_whitespace(rest);
    }

    // We parsed the array successfully and the next character is ]
    ASSERT(rest[0] == ']');
    rest += 1; // skip ]
    *out = make_json_array(array);

    return rest;
}

static const char *parse_object(const char *input, JsonValue **out)
{
    const char *rest = input;
    rest = skip_whitespace(rest);

    if (rest[0] != '{')
    {
        return input;
    }
    rest += 1; // skip {

    JsonPair *first_pair = NULL;
    JsonPair *last_pair = NULL;

    while (true)
    {
        rest = skip_whitespace(rest);
        if (rest[0] == '}') break;

        // key
        String key = parse_string_literal(rest);
        if (str_is_invalid(key))
        {
            printf("ERROR while parsing object: key is not a string\n");
            return input;
        }
        rest += key.len + 2; // 2 for the quotes

        // in-between
        rest = skip_whitespace(rest);
        if (rest[0] != ':')
        {
            printf("ERROR while parsing object: missing colon\n");
            return input;
        }
        rest += 1; // skip :
        rest = skip_whitespace(rest);

        // value
        JsonValue *value = NULL;
        rest = parse_value(rest, &value);
        if (value != NULL)
        {
            JsonPair *pair = make_pair(key, value);
            SLLQueuePush(first_pair, last_pair, pair);
        }

        rest = skip_whitespace(rest);
        if (rest[0] == ',')
        {
            rest += 1; // skip ,

            // There must not be a comma before }
            rest = skip_whitespace(rest);
            if (rest[0] == '}')
            {
                return NULL;
            }
        }
        else
        {
            // There must be a comma if this pair is not the last one
            rest = skip_whitespace(rest);
            if (rest[0] != '}')
            {
                return NULL;
            }
        }
    }

    // We parsed the object successfully and the next character is }
    ASSERT(rest[0] == '}');
    rest += 1; // skip the }
    *out = make_object(first_pair);

    return rest;
}

static const char *parse_value(const char *input, JsonValue **out)
{
    JsonValue *value = NULL;

    const char *rest = input;

    rest = parse_null(input, &value);
    if (value != NULL)
    {
        *out = value;
        return rest;
    }

    rest = parse_boolean(input, &value);
    if (value != NULL)
    {
        *out = value;
        return rest;
    }

    rest = parse_number(input, &value);
    if (value != NULL)
    {
        *out = value;
        return rest;
    }

    rest = parse_string(input, &value);
    if (value != NULL)
    {
        *out = value;
        return rest;
    }

    rest = parse_array(input, &value);
    if (value != NULL)
    {
        *out = value;
        return rest;
    }

    rest = parse_object(input, &value);
    if (value != NULL)
    {
        *out = value;
        return rest;
    }

    return input;
}

/****************************************************************
 * Parsing API
****************************************************************/
JsonValue *json_parse(const char *input)
{
    JsonValue *value = NULL;
    input = parse_value(input, &value);
    return value;
}

JsonValue *json_parse_file(String filepath)
{
    Allocator *heap_allocator = allocator_get_heap();

    String content = os_read_entire_file(heap_allocator, filepath);
    if (str_is_invalid(content)) return NULL;

    JsonValue *value = json_parse(content.str);
    str_free(heap_allocator, content);

    return value;
}

/****************************************************************
 * Getters
****************************************************************/
JsonValue *json_object_get_key(JsonValue *value, const char *key)
{
    ASSERT(json_value_is_object(value));
    for (JsonPair *pair = value->as.object; pair != NULL; pair = pair->next)
    {
        if (str_eq_cstring(pair->key, key))
        {
            return pair->value;
        }
    }

    return NULL;
}

// Length terminated version of `json_object_get_key`
JsonValue *json_object_get_key_lt(JsonValue *value, const char *key, int length)
{
    ASSERT(json_value_is_object(value));
    for (JsonPair *pair = value->as.object; pair != NULL; pair = pair->next)
    {
        if (str_eq(pair->key, str_from(key, length)))
        {
            return pair->value;
        }
    }

    return NULL;
}

JsonValue *json_array_get_index(JsonValue *value, size_t index)
{
    ASSERT(json_value_is_array(value));
    if (index < value->as.array.count)
    {
        return value->as.array.data[index];
    }
    else
    {
        return NULL;
    }
}

JsonValue *json_object_get_key_chain(JsonValue *value, const char *key)
{
    if (value == NULL) return NULL;
    return json_object_get_key(value, key);
}

// Length terminated version of `json_object_get_key_chain`
JsonValue *json_object_get_key_lt_chain(JsonValue *value, const char *key, int length)
{
    if (value == NULL) return NULL;
    return json_object_get_key_lt(value, key, length);
}

JsonValue *json_array_get_index_chain(JsonValue *value, size_t index)
{
    if (value == NULL) return NULL;
    return json_array_get_index(value, index);
}

JsonValue *json_query(JsonValue *value, const char *query)
{
    while (true)
    {
        query = skip_whitespace(query);

        if (query[0] == '.')
        {
            query++; // skip .

            const char *key_begin = query;

            while (query[0] != '.' && query[0] != '[' && query[0] != '\0' && !is_whitespace(query[0]))
            {
                query++;
            }

            int key_len = query - key_begin;
            value = json_object_get_key_lt_chain(value, key_begin, key_len);
        }
        else if (query[0] == '[')
        {
            query++; // skip [

            const char *key_begin = query;

            if (is_digit(query[0]))
            {
                // array index
                char *end;
                size_t index = strtol(query, &end, 10);
                query = end;

                if (query[0] == ']')
                {
                    value = json_array_get_index_chain(value, index);
                    query++; // skip ]
                }
                else
                {
                    return NULL;
                }
            }
            else if (query[0] == '\"')
            {
                // object key
                query++; // skip "

                const char *key_begin = query;

                while (query[0] != '\"' && query[0] != '\0')
                {
                    query++;
                }

                if (query[0] == '\"')
                {
                    int key_len = query - key_begin;
                    query++; // skip "

                    if (query[0] == ']')
                    {
                        value = json_object_get_key_lt_chain(value, key_begin, key_len);
                        query++; // skip ]
                    }
                    else
                    {
                        return NULL;
                    }
                }
                else
                {
                    return NULL;
                }
            }
        }
        else if (query[0] == '\0')
        {
            break;
        }
        else
        {
            return NULL;
        }
    }

    return value;
}

size_t json_array_get_length(const JsonValue *value)
{
    ASSERT(json_value_is_array(value));
    return json_value_is_array(value) ? value->as.array.count : 0;
}

size_t json_object_get_num_keys(const JsonValue *value)
{
    ASSERT(json_value_is_object(value));;
    if (!json_value_is_object(value)) return 0;

    size_t count = 0;
    for (JsonPair *pair = value->as.object; pair != NULL; pair = pair->next)
    {
        count++;
    }

    return count;
}

const char *json_get_type_string(const JsonValue *value)
{
    switch (value->type)
    {
        case JSON_NULL: return "null";
        case JSON_BOOL: return "bool";
        case JSON_NUMBER: return "number";
        case JSON_STRING: return "string";
        case JSON_ARRAY: return "array";
        case JSON_OBJECT: return "object";
    }
}

/****************************************************************
 * Predicates
****************************************************************/
bool json_value_is_null(const JsonValue *value)
{
    return value->type == JSON_NULL;
}

bool json_value_is_bool(const JsonValue *value)
{
    return value->type == JSON_BOOL;
}

bool json_value_is_number(const JsonValue *value)
{
    return value->type == JSON_NUMBER;
}

bool json_value_is_string(const JsonValue *value)
{
    return value->type == JSON_STRING;
}

bool json_value_is_array(const JsonValue *value)
{
    return value->type == JSON_ARRAY;
}

bool json_value_is_object(const JsonValue *value)
{
    return value->type == JSON_OBJECT;
}

bool json_array_is_homogeneous(JsonValue *value)
{
    ASSERT(json_value_is_array(value));
    if (!json_value_is_array(value)) return false;

    for (int i = 0; i < value->as.array.count - 1; ++i)
    {
        if (value->as.array.data[i]->type != value->as.array.data[i + 1]->type)
        {
            return false;
        }
    }

    return true;
}

bool json_array_is_homogeneous_type(JsonValue *value, JsonType type)
{
    ASSERT(json_value_is_array(value));
    if (!json_value_is_array(value)) return false;
    return json_array_get_length(value) < 2
        || (json_array_get_index(value, 0)->type == type && json_array_is_homogeneous(value));
}

bool json_array_is_homogeneous_null(JsonValue *value)
{
    return json_array_is_homogeneous_type(value, JSON_NULL);
}

bool json_array_is_homogeneous_bool(JsonValue *value)
{
    return json_array_is_homogeneous_type(value, JSON_BOOL);
}

bool json_array_is_homogeneous_number(JsonValue *value)
{
    return json_array_is_homogeneous_type(value, JSON_NUMBER);
}

bool json_array_is_homogeneous_string(JsonValue *value)
{
    return json_array_is_homogeneous_type(value, JSON_STRING);
}

bool json_array_is_homogeneous_array(JsonValue *value)
{
    return json_array_is_homogeneous_type(value, JSON_ARRAY);
}

bool json_array_is_homogeneous_object(JsonValue *value)
{
    return json_array_is_homogeneous_type(value, JSON_OBJECT);
}

bool json_array_contains_array(const JsonValue *value)
{
    ASSERT(json_value_is_array(value));
    if (!json_value_is_array(value)) return false;

    for (int i = 0; i < value->as.array.count; ++i)
    {
        if (json_value_is_array(value->as.array.data[i]))
        {
            return true;
        }
    }

    return false;
}

bool json_array_contains_object(const JsonValue *value)
{
    ASSERT(json_value_is_array(value));
    if (!json_value_is_array(value)) return false;

    for (int i = 0; i < value->as.array.count; ++i)
    {
        if (json_value_is_object(value->as.array.data[i]))
        {
            return true;
        }
    }

    return false;
}

/****************************************************************
 * Pretty printing
****************************************************************/
void json_print_value(const JsonValue *value, FILE *stream)
{
    switch (value->type)
    {
        case JSON_NULL:
        {
            fprintf(stream, "null");
        } break;

        case JSON_BOOL:
        {
            fprintf(stream, "%s", value->as.boolean ? "true" : "false");
        } break;

        case JSON_NUMBER:
        {
            fprintf(stream, "%lf", value->as.number);
        } break;

        case JSON_STRING:
        {
            fprintf(stream, "\"%s\"", value->as.string.str);
        } break;

        case JSON_ARRAY:
        {
            fprintf(stream, "[");
            for (int i = 0; i < value->as.array.count; ++i)
            {
                json_print_value(value->as.array.data[i], stream);
                if (i != value->as.array.count - 1)
                {
                    fprintf(stream, ", ");
                }
            }
            fprintf(stream, "]");
        } break;

        case JSON_OBJECT:
        {
            fprintf(stream, "{");
            for (JsonPair *pair = value->as.object; pair != NULL; pair = pair->next)
            {
                fprintf(stream, "\"%s\": ", pair->key.str);
                json_print_value(pair->value, stream);

                if (pair->next != NULL)
                {
                    fprintf(stream, ", ");
                }
            }
            fprintf(stream, "}");
        } break;

        default:
        {
           fprintf(stream, "UNKNOWN");
        } break;
    }
}

static void pretty_print_value_recursive(const JsonValue *value, int indent_spaces, int indent_level, FILE *stream)
{
    switch (value->type)
    {
        case JSON_NULL:
        {
            ansi_print_red(stream, "null");
        } break;

        case JSON_BOOL:
        {
            ansi_print_bright_yellow(stream, "%s", value->as.boolean ? "true" : "false");
        } break;

        case JSON_NUMBER:
        {
            ansi_print_bright_red(stream, "%lf", value->as.number);
        } break;

        case JSON_STRING:
        {
            ansi_print_bright_green(stream, "\"%s\"", value->as.string);
        } break;

        case JSON_ARRAY:
        {
            bool print_each_item_on_separate_line = json_array_get_length(value) >= 5
                || json_array_contains_array(value)
                || json_array_contains_object(value);

            if (print_each_item_on_separate_line)
            {
                fprintf(stream, "[");
                for (int i = 0; i < value->as.array.count; ++i)
                {
                    const JsonValue *item = value->as.array.data[i];

                    fprintf(stream, "\n");
                    indent(indent_spaces, indent_level + 1, stream);
                    pretty_print_value_recursive(item, indent_spaces, indent_level + 1, stream);

                    if (i != value->as.array.count - 1)
                    {
                        fprintf(stream, ",");
                    }
                    else
                    {
                        fprintf(stream, "\n");
                        indent(indent_spaces, indent_level, stream);
                    }
                }
                fprintf(stream, "]");
            }
            else
            {
                fprintf(stream, "[");
                for (int i = 0; i < value->as.array.count; ++i)
                {
                    const JsonValue *item = value->as.array.data[i];

                    pretty_print_value_recursive(item, indent_spaces, indent_level + 1, stream);

                    if (i != value->as.array.count - 1)
                    {
                        fprintf(stream, ", ");
                    }
                }
                fprintf(stream, "]");
            }
        } break;

        case JSON_OBJECT:
        {
            fprintf(stream, "{");

            for (JsonPair *pair = value->as.object; pair != NULL; pair = pair->next)
            {
                fprintf(stream, "\n");
                indent(indent_spaces, indent_level + 1, stream);
                ansi_print_green(stream, "\"%s\"", pair->key);
                fprintf(stream, ": ");
                pretty_print_value_recursive(pair->value, indent_spaces, indent_level + 1, stream);

                if (pair->next != NULL)
                {
                    fprintf(stream, ",");
                }
                else
                {
                    fprintf(stream, "\n");
                    indent(indent_spaces, indent_level, stream);
                }
            }
            fprintf(stream, "}");
        } break;

        default:
        {
            json_print_value(value, stream);
        } break;
    }
}

void json_pretty_print_value(const JsonValue *value, int indent_spaces, FILE *stream)
{
    pretty_print_value_recursive(value, indent_spaces, 0, stream);
}

