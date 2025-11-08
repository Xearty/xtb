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

static XTB_String8 parse_string_literal(const char *input)
{
    const char *rest = input;

    if (rest[0] != '\"')
    {
        return xtb_str8_invalid;
    }
    rest += 1;

    const char *string_begin = rest;

    while (rest[0] != '\"') rest += 1;
    XTB_ASSERT(rest[0] == '\"');

    const char *string_end = rest;
    int string_len = string_end - string_begin;
    XTB_String8 substr = xtb_str8(string_begin, string_len);
    return xtb_str8_copy(allocator_get_heap(), substr);
}

static void indent(int indentation, int level, FILE *stream)
{
    int indent_spaces = level * indentation;
    for (int i = 0; i < indent_spaces; ++i) fprintf(stream, " ");
}

/****************************************************************
 * Value initializers (internal)
****************************************************************/
static XTB_JSON_Value* make_json_value(XTB_JSON_Type type)
{
    XTB_JSON_Value *value = calloc(1, sizeof(XTB_JSON_Value));
    value->type = type;
    return value;
}

static XTB_JSON_Value* make_json_null()
{
    return make_json_value(XTB_JSON_NULL);
}

static XTB_JSON_Value* make_json_bool(bool boolean_value)
{
    XTB_JSON_Value *value = make_json_value(XTB_JSON_BOOL);
    value->as.boolean = boolean_value;
    return value;
}

static XTB_JSON_Value *make_json_number(double number)
{
    XTB_JSON_Value *value = make_json_value(XTB_JSON_NUMBER);
    value->as.number = number;
    return value;
}

static XTB_JSON_Value *make_json_string(XTB_String8 string)
{
    XTB_JSON_Value *value = make_json_value(XTB_JSON_STRING);
    value->as.string = string;
    return value;
}

static XTB_JSON_Value* make_json_array(XTB_JSON_Array array)
{
    XTB_JSON_Value *value = make_json_value(XTB_JSON_ARRAY);
    value->as.array = array;
    return value;
}

static XTB_JSON_Value *make_object(XTB_JSON_Pair *first_pair)
{
    XTB_JSON_Value *value = make_json_value(XTB_JSON_OBJECT);
    value->as.object = first_pair;
    return value;
}

// steals the buffers
static XTB_JSON_Pair *make_pair(XTB_String8 key, XTB_JSON_Value *value)
{
    XTB_JSON_Pair *pair = (XTB_JSON_Pair*)calloc(1, sizeof(XTB_JSON_Pair));
    pair->key = key;
    pair->value = value;
    pair->next = NULL;
    return pair;
}

/****************************************************************
 * Value parsers (internal)
****************************************************************/
static const char *parse_value(const char *input, XTB_JSON_Value **out);

static const char* parse_null(const char *input, XTB_JSON_Value **out)
{
    input = skip_whitespace(input);

    if (strncmp(input, "null", 4) == 0)
    {
        input += 4;
        *out = make_json_null();
    }

    return input;
}

static const char* parse_boolean(const char *input, XTB_JSON_Value **out)
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

static const char* parse_number(const char *input, XTB_JSON_Value **out)
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

static const char *parse_string(const char *input, XTB_JSON_Value **out)
{
    const char *rest = input;
    rest = skip_whitespace(rest);

    XTB_String8 string = parse_string_literal(rest);
    if (xtb_str8_is_valid(string))
    {
        *out = make_json_string(string);
        return rest + string.len + 2; // 2 for the quotes
    }

    return input;
}

static const char *parse_array(const char *input, XTB_JSON_Value **out)
{
    input = skip_whitespace(input);

    const char *rest = input;

    if (rest[0] != '[')
    {
        return input;
    }

    rest += 1; // skip [

    XTB_JSON_Array array = make_array(allocator_get_heap());

    while (true)
    {
        rest = skip_whitespace(rest);
        if (rest[0] == ']') break;

        XTB_JSON_Value *value = NULL;
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
    XTB_ASSERT(rest[0] == ']');
    rest += 1; // skip ]
    *out = make_json_array(array);

    return rest;
}

static const char *parse_object(const char *input, XTB_JSON_Value **out)
{
    const char *rest = input;
    rest = skip_whitespace(rest);

    if (rest[0] != '{')
    {
        return input;
    }
    rest += 1; // skip {

    XTB_JSON_Pair *first_pair = NULL;
    XTB_JSON_Pair *last_pair = NULL;

    while (true)
    {
        rest = skip_whitespace(rest);
        if (rest[0] == '}') break;

        // key
        XTB_String8 key = parse_string_literal(rest);
        if (xtb_str8_is_invalid(key))
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
        XTB_JSON_Value *value = NULL;
        rest = parse_value(rest, &value);
        if (value != NULL)
        {
            XTB_JSON_Pair *pair = make_pair(key, value);
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
    XTB_ASSERT(rest[0] == '}');
    rest += 1; // skip the }
    *out = make_object(first_pair);

    return rest;
}

static const char *parse_value(const char *input, XTB_JSON_Value **out)
{
    XTB_JSON_Value *value = NULL;

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
XTB_JSON_Value *xtb_json_parse(const char *input)
{
    XTB_JSON_Value *value = NULL;
    input = parse_value(input, &value);
    return value;
}

XTB_JSON_Value *xtb_json_parse_file(XTB_String8 filepath)
{
    Allocator *heap_allocator = allocator_get_heap();

    XTB_String8 content = xtb_os_read_entire_file(heap_allocator, filepath);
    if (xtb_str8_is_invalid(content)) return NULL;

    XTB_JSON_Value *value = xtb_json_parse(content.str);
    xtb_str8_free(heap_allocator, content);

    return value;
}

/****************************************************************
 * Getters
****************************************************************/
XTB_JSON_Value *xtb_json_object_get_key(XTB_JSON_Value *value, const char *key)
{
    XTB_ASSERT(xtb_json_value_is_object(value));
    for (XTB_JSON_Pair *pair = value->as.object; pair != NULL; pair = pair->next)
    {
        if (xtb_str8_eq_cstring(pair->key, key))
        {
            return pair->value;
        }
    }

    return NULL;
}

// Length terminated version of `xtb_json_object_get_key`
XTB_JSON_Value *xtb_json_object_get_key_lt(XTB_JSON_Value *value, const char *key, int length)
{
    XTB_ASSERT(xtb_json_value_is_object(value));
    for (XTB_JSON_Pair *pair = value->as.object; pair != NULL; pair = pair->next)
    {
        if (xtb_str8_eq(pair->key, xtb_str8(key, length)))
        {
            return pair->value;
        }
    }

    return NULL;
}

XTB_JSON_Value *xtb_json_array_get_index(XTB_JSON_Value *value, size_t index)
{
    XTB_ASSERT(xtb_json_value_is_array(value));
    if (index < value->as.array.count)
    {
        return value->as.array.data[index];
    }
    else
    {
        return NULL;
    }
}

XTB_JSON_Value *xtb_json_object_get_key_chain(XTB_JSON_Value *value, const char *key)
{
    if (value == NULL) return NULL;
    return xtb_json_object_get_key(value, key);
}

// Length terminated version of `xtb_json_object_get_key_chain`
XTB_JSON_Value *xtb_json_object_get_key_lt_chain(XTB_JSON_Value *value, const char *key, int length)
{
    if (value == NULL) return NULL;
    return xtb_json_object_get_key_lt(value, key, length);
}

XTB_JSON_Value *xtb_json_array_get_index_chain(XTB_JSON_Value *value, size_t index)
{
    if (value == NULL) return NULL;
    return xtb_json_array_get_index(value, index);
}

XTB_JSON_Value *xtb_json_query(XTB_JSON_Value *value, const char *query)
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
            value = xtb_json_object_get_key_lt_chain(value, key_begin, key_len);
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
                    value = xtb_json_array_get_index_chain(value, index);
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
                        value = xtb_json_object_get_key_lt_chain(value, key_begin, key_len);
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

size_t xtb_json_array_get_length(const XTB_JSON_Value *value)
{
    XTB_ASSERT(xtb_json_value_is_array(value));
    return xtb_json_value_is_array(value) ? value->as.array.count : 0;
}

size_t xtb_json_object_get_num_keys(const XTB_JSON_Value *value)
{
    XTB_ASSERT(xtb_json_value_is_object(value));;
    if (!xtb_json_value_is_object(value)) return 0;

    size_t count = 0;
    for (XTB_JSON_Pair *pair = value->as.object; pair != NULL; pair = pair->next)
    {
        count++;
    }

    return count;
}

const char *xtb_json_get_type_string(const XTB_JSON_Value *value)
{
    switch (value->type)
    {
        case XTB_JSON_NULL: return "null";
        case XTB_JSON_BOOL: return "bool";
        case XTB_JSON_NUMBER: return "number";
        case XTB_JSON_STRING: return "string";
        case XTB_JSON_ARRAY: return "array";
        case XTB_JSON_OBJECT: return "object";
    }
}

/****************************************************************
 * Predicates
****************************************************************/
bool xtb_json_value_is_null(const XTB_JSON_Value *value)
{
    return value->type == XTB_JSON_NULL;
}

bool xtb_json_value_is_bool(const XTB_JSON_Value *value)
{
    return value->type == XTB_JSON_BOOL;
}

bool xtb_json_value_is_number(const XTB_JSON_Value *value)
{
    return value->type == XTB_JSON_NUMBER;
}

bool xtb_json_value_is_string(const XTB_JSON_Value *value)
{
    return value->type == XTB_JSON_STRING;
}

bool xtb_json_value_is_array(const XTB_JSON_Value *value)
{
    return value->type == XTB_JSON_ARRAY;
}

bool xtb_json_value_is_object(const XTB_JSON_Value *value)
{
    return value->type == XTB_JSON_OBJECT;
}

bool xtb_json_array_is_homogeneous(XTB_JSON_Value *value)
{
    XTB_ASSERT(xtb_json_value_is_array(value));
    if (!xtb_json_value_is_array(value)) return false;

    for (int i = 0; i < value->as.array.count - 1; ++i)
    {
        if (value->as.array.data[i]->type != value->as.array.data[i + 1]->type)
        {
            return false;
        }
    }

    return true;
}

bool xtb_json_array_is_homogeneous_type(XTB_JSON_Value *value, XTB_JSON_Type type)
{
    XTB_ASSERT(xtb_json_value_is_array(value));
    if (!xtb_json_value_is_array(value)) return false;
    return xtb_json_array_get_length(value) < 2
        || (xtb_json_array_get_index(value, 0)->type == type && xtb_json_array_is_homogeneous(value));
}

bool xtb_json_array_is_homogeneous_null(XTB_JSON_Value *value)
{
    return xtb_json_array_is_homogeneous_type(value, XTB_JSON_NULL);
}

bool xtb_json_array_is_homogeneous_bool(XTB_JSON_Value *value)
{
    return xtb_json_array_is_homogeneous_type(value, XTB_JSON_BOOL);
}

bool xtb_json_array_is_homogeneous_number(XTB_JSON_Value *value)
{
    return xtb_json_array_is_homogeneous_type(value, XTB_JSON_NUMBER);
}

bool xtb_json_array_is_homogeneous_string(XTB_JSON_Value *value)
{
    return xtb_json_array_is_homogeneous_type(value, XTB_JSON_STRING);
}

bool xtb_json_array_is_homogeneous_array(XTB_JSON_Value *value)
{
    return xtb_json_array_is_homogeneous_type(value, XTB_JSON_ARRAY);
}

bool xtb_json_array_is_homogeneous_object(XTB_JSON_Value *value)
{
    return xtb_json_array_is_homogeneous_type(value, XTB_JSON_OBJECT);
}

bool xtb_json_array_contains_array(const XTB_JSON_Value *value)
{
    XTB_ASSERT(xtb_json_value_is_array(value));
    if (!xtb_json_value_is_array(value)) return false;

    for (int i = 0; i < value->as.array.count; ++i)
    {
        if (xtb_json_value_is_array(value->as.array.data[i]))
        {
            return true;
        }
    }

    return false;
}

bool xtb_json_array_contains_object(const XTB_JSON_Value *value)
{
    XTB_ASSERT(xtb_json_value_is_array(value));
    if (!xtb_json_value_is_array(value)) return false;

    for (int i = 0; i < value->as.array.count; ++i)
    {
        if (xtb_json_value_is_object(value->as.array.data[i]))
        {
            return true;
        }
    }

    return false;
}

/****************************************************************
 * Pretty printing
****************************************************************/
void xtb_json_print_value(const XTB_JSON_Value *value, FILE *stream)
{
    switch (value->type)
    {
        case XTB_JSON_NULL:
        {
            fprintf(stream, "null");
        } break;

        case XTB_JSON_BOOL:
        {
            fprintf(stream, "%s", value->as.boolean ? "true" : "false");
        } break;

        case XTB_JSON_NUMBER:
        {
            fprintf(stream, "%lf", value->as.number);
        } break;

        case XTB_JSON_STRING:
        {
            fprintf(stream, "\"%s\"", value->as.string.str);
        } break;

        case XTB_JSON_ARRAY:
        {
            fprintf(stream, "[");
            for (int i = 0; i < value->as.array.count; ++i)
            {
                xtb_json_print_value(value->as.array.data[i], stream);
                if (i != value->as.array.count - 1)
                {
                    fprintf(stream, ", ");
                }
            }
            fprintf(stream, "]");
        } break;

        case XTB_JSON_OBJECT:
        {
            fprintf(stream, "{");
            for (XTB_JSON_Pair *pair = value->as.object; pair != NULL; pair = pair->next)
            {
                fprintf(stream, "\"%s\": ", pair->key.str);
                xtb_json_print_value(pair->value, stream);

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

static void pretty_print_value_recursive(const XTB_JSON_Value *value, int indent_spaces, int indent_level, FILE *stream)
{
    switch (value->type)
    {
        case XTB_JSON_NULL:
        {
            xtb_ansi_print_red(stream, "null");
        } break;

        case XTB_JSON_BOOL:
        {
            xtb_ansi_print_bright_yellow(stream, "%s", value->as.boolean ? "true" : "false");
        } break;

        case XTB_JSON_NUMBER:
        {
            xtb_ansi_print_bright_red(stream, "%lf", value->as.number);
        } break;

        case XTB_JSON_STRING:
        {
            xtb_ansi_print_bright_green(stream, "\"%s\"", value->as.string);
        } break;

        case XTB_JSON_ARRAY:
        {
            bool print_each_item_on_separate_line = xtb_json_array_get_length(value) >= 5
                || xtb_json_array_contains_array(value)
                || xtb_json_array_contains_object(value);

            if (print_each_item_on_separate_line)
            {
                fprintf(stream, "[");
                for (int i = 0; i < value->as.array.count; ++i)
                {
                    const XTB_JSON_Value *item = value->as.array.data[i];

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
                    const XTB_JSON_Value *item = value->as.array.data[i];

                    pretty_print_value_recursive(item, indent_spaces, indent_level + 1, stream);

                    if (i != value->as.array.count - 1)
                    {
                        fprintf(stream, ", ");
                    }
                }
                fprintf(stream, "]");
            }
        } break;

        case XTB_JSON_OBJECT:
        {
            fprintf(stream, "{");

            for (XTB_JSON_Pair *pair = value->as.object; pair != NULL; pair = pair->next)
            {
                fprintf(stream, "\n");
                indent(indent_spaces, indent_level + 1, stream);
                xtb_ansi_print_green(stream, "\"%s\"", pair->key);
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
            xtb_json_print_value(value, stream);
        } break;
    }
}

void xtb_json_pretty_print_value(const XTB_JSON_Value *value, int indent_spaces, FILE *stream)
{
    pretty_print_value_recursive(value, indent_spaces, 0, stream);
}

