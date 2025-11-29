#include "xtb_core/allocator.h"
#include "xtb_core/thread_context.h"
#include <xtb_core/string.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/contract.h>

#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <iostream>

namespace xtb
{

String String::copy(Allocator *allocator)
{
    u8 *buf = AllocateBytes(allocator, m_len + 1);
    strncpy((char*)buf, (char *)m_data, m_len)[m_len] = '\0';
    return String(buf, m_len);
}

String String::substr(isize begin_idx, isize len)
{
    isize begin_idx_clamped = ClampTop(begin_idx, m_len);
    isize end_idx = ClampTop(begin_idx + len, m_len);
    isize actual_len = end_idx - begin_idx_clamped;
    return String(m_data + begin_idx_clamped, actual_len);
}

isize String::find(String needle)
{
    for (isize begin_idx = 0; begin_idx <= m_len - needle.len(); ++begin_idx)
    {
        std::cout << begin_idx << ": " << this->substr(begin_idx, needle.len()) << std::endl;
        std::cout << begin_idx << ": " << needle << std::endl;
        if (this->substr(begin_idx, needle.len()) == needle)
        {
            return begin_idx;
        }
    }
    return -1;
}

isize String::find_last(String needle)
{
    for (isize end_idx = m_len - 1; end_idx >= needle.len(); --end_idx)
    {
        isize begin_idx = end_idx - needle.len();
        if (this->substr(begin_idx, needle.len()) == needle)
        {
            return begin_idx;
        }
    }
    return -1;
}

isize String::find(u8 needle)
{
    for (i32 i = 0; i < m_len; ++i)
    {
        if (m_data[i] == needle) return i;
    }

    return -1;
}

isize String::find_last(u8 needle)
{
    for (i32 i = m_len - 1; i >= 0; --i)
    {
        if (m_data[i] == needle) return i;
    }

    return -1;
}

bool String::contains(u8 needle)
{
    return this->find(needle) != -1;
}

bool String::contains(String needle)
{
    return this->find(needle) != -1;
}

String String::replace(String from, String to, Allocator* allocator)
{
    ScratchScope scratch(allocator);
    StringList parts = this->split_by_str(from, &scratch->allocator);
    return parts.join_string_sep(to, allocator);
}

String String::concat(String other, Allocator* allocator)
{
    String strings[] = { *this, other };
    return String::array_join(allocator, strings, ArrLen(strings));
}

String String::escape(Allocator *allocator)
{
    char escape_characters[] = { 'a', 'b', 'e', 'f', 'n', 'r', 't', 'v', '\\', '\'', '\"', '?' };
    char hex_values[] = { 0x07, 0x08, 0x1b, 0x0c, 0x0a, 0x0d, 0x09, 0x0b, 0x5c, 0x27, 0x22, 0x3f };
    StaticAssert(ArrLen(escape_characters) == ArrLen(hex_values), "Array lengths must match");

    StringBuf buf = StringBuf::init_with_capacity(allocator, m_len + 1);

    for (i32 i = 0; i < m_len; ++i)
    {
        char ch = m_data[i];

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
            buf.append('\\');
            buf.append(escape_ch);
        }
        else
        {
            buf.append(ch);
        }
    }

    return buf.detach();
}

String String::strip_extension()
{
    i32 dot_pos = this->find_last('.');
    i32 ext_len = m_len - dot_pos;
    return this->trunc_right(ext_len);
}

String String::basename()
{
    i32 begin = this->find_last('/') + 1;
    i32 len = m_len - begin;
    return this->substr(begin, len);
}

u8 String::front()
{
    Assert(m_len > 0);
    return m_data[0];
}

u8 String::back()
{
    Assert(m_len > 0);
    return m_data[m_len - 1];
}

i32 String::compare(String other) const
{
    // Compare the common prefix
    isize min_len = Min(m_len, other.m_len);
    i32 r = 0;
    if (min_len > 0)
    {
        r = memcmp(m_data, other.m_data, (usize)min_len);
    }

    if (r < 0) return -1;
    if (r > 0) return 1;

    // Prefixes are equal, so shorter string is "less"
    if (m_len < other.m_len) return -1;
    if (m_len > other.m_len) return 1;
    return 0;
}

bool String::equals(String other) const
{
    if (m_len != other.m_len) return false;
    return this->compare(other) == 0;
}

String String::head(isize count)
{
    return this->substr(0, count);
}

String String::tail(isize count)
{
    int begin_idx = ClampBot(m_len - count, 0);
    return this->substr(begin_idx, count);
}

bool String::starts_with(String prefix)
{
    return this->head(prefix.m_len).equals(prefix);
}

bool String::ends_with(String postfix)
{
    return this->tail(postfix.m_len).equals(postfix);
}

String String::trunc_left(isize count)
{
    return this->substr(count, m_len - count);
}

String String::trunc_right(isize count)
{
    return this->substr(0, m_len - count);
}

String String::trim_left()
{
    int i;
    for (i = 0; i < m_len; ++i)
    {
        if (!isspace(m_data[i])) break;
    }
    return this->trunc_left(i);
}

String String::trim_right()
{
    isize i;
    for (i = m_len - 1; i >= 0; --i)
    {
        if (!isspace(m_data[i])) break;
    }
    isize count = m_len - 1 - i;
    return this->trunc_right(count);
}

String String::trim()
{
    return this->trim_left().trim_right();
}

String String::invalid()
{
    return String(NULL, 0);
}

bool String::is_invalid()
{
    return m_data == NULL;
}

bool String::is_valid()
{
    return !this->is_invalid();
}

bool String::is_empty() const
{
    return m_len == 0;
}

String String::formatv(Allocator* allocator, const char *fmt, va_list args)
{
    va_list args_copy;
    va_copy(args_copy, args);

    int len = vsnprintf(NULL, 0, fmt, args_copy);
    va_end(args_copy);

    if (len <= 0)
    {
        return String::invalid();
    }

    u8 *str_buf = AllocateBytes(allocator, len + 1);
    if (!str_buf)
    {
        return String::invalid();
    }

    vsnprintf((char*)str_buf, len + 1, fmt, args);

    return String(str_buf, len);
}

String String::format(Allocator *allocator, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    String result = String::formatv(allocator, fmt, args);
    va_end(args);
    return result;
}

static isize str_array_accumulate_length(String *array, isize count)
{
    isize len = 0;
    for (isize i = 0; i < count; ++i) len += array[i].len();
    return len;
}

String String::array_join(Allocator* allocator, String *array, isize count)
{
    isize len = str_array_accumulate_length(array, count);
    u8 *str_buf = AllocateBytes(allocator, len + 1);

    isize out_idx = 0;
    for (isize i = 0; i < count; ++i)
    {
        MemoryCopy(str_buf + out_idx, array[i].data(), array[i].len());
        out_idx += array[i].len();
    }

    str_buf[len] = 0;

    return String(str_buf, len);
}

String String::array_join_sep(Allocator* allocator, String *array, isize count, String sep)
{
    isize non_sep_len = str_array_accumulate_length(array, count);
    isize sep_count = count - 1;
    isize len = non_sep_len + (sep_count * sep.len());

    u8 *str_buf = AllocateBytes(allocator, len + 1);

    isize out_idx = 0;
    for (isize i = 0; i < count; ++i)
    {
        MemoryCopy(str_buf + out_idx, array[i].data(), array[i].len());
        out_idx += array[i].len();

        if (i != count - 1)
        {
            MemoryCopy(str_buf + out_idx, sep.data(), sep.len());
            out_idx += sep.len();
        }
    }

    return String(str_buf, len);
}

///////////////////////////////////////////////////////////////////////////////////////////////////

isize str_list_length(StringList str_list)
{
    isize len = 0;
    IterateList(&str_list) len += 1;
    return len;
}

isize str_list_accumulate_length(StringList str_list)
{
    isize len = 0;
    IterateList(&str_list) len += it->string.len();
    return len;
}

String
str_array_join_sep(Allocator* allocator,
                        String *array,
                        isize count,
                        String sep)
{
    isize non_sep_len = str_array_accumulate_length(array, count);
    isize sep_count = count - 1;
    isize len = non_sep_len + (sep_count * sep.len());

    u8 *str_buf = AllocateBytes(allocator, len + 1);

    isize out_idx = 0;
    for (isize i = 0; i < count; ++i)
    {
        MemoryCopy(str_buf + out_idx, array[i].data(), array[i].len());
        out_idx += array[i].len();

        if (i != count - 1)
        {
            MemoryCopy(str_buf + out_idx, sep.data(), sep.len());
            out_idx += sep.len();
        }
    }

    return String(str_buf, len);
}

StringList String::split_pred(String::SplitPred pred,
                              void *data,
                              Allocator* allocator)
{
    StringList result = {0};

    isize token_begin_idx = 0;
    isize i = 0;

    while (i < this->len())
    {
        String rest = this->trunc_left(i);
        int skip = pred(rest, data);

        if (skip > 0) // delimiter hit
        {
            isize tok_len = i - token_begin_idx;
            String token = this->substr(token_begin_idx, tok_len);
            result.push_back(token, allocator);

            i += skip;
            token_begin_idx = i;
        }
        else
        {
            i++;
        }
    }

    if (token_begin_idx <= this->len()) // just in case the predicate returns nonsense
    {
        isize tok_len = this->len() - token_begin_idx;
        String token = this->substr(token_begin_idx, tok_len);
        result.push_back(token, allocator);
    }

    return result;
}

StringList String::split_tokens_pred(String::SplitPred pred,
                                     void *data,
                                     Allocator* allocator)
{
    StringList result = {0};

    isize token_begin_idx = 0;
    isize i = 0;

    while (i < this->len())
    {
        String rest = this->trunc_left(i);
        int skip = pred(rest, data);

        if (skip > 0) // delimiter hit
        {
            isize tok_len = i - token_begin_idx;
            if (tok_len > 0)
            {
                String token = this->substr(token_begin_idx, tok_len);
                result.push_back(token, allocator);
            }

            i += skip;
            token_begin_idx = i;
        }
        else
        {
            i++;
        }
    }

    if (token_begin_idx <= this->len()) // just in case the predicate returns nonsense
    {
        isize tok_len = this->len() - token_begin_idx;
        if (tok_len > 0)
        {
            String token = this->substr(token_begin_idx, tok_len);
            result.push_back(token, allocator);
        }
    }

    return result;
}

static isize split_by_str_pred(String rest, void *data)
{
    String sep = *(String *)data;
    String rest_substr = rest.substr(0, sep.len());
    return rest_substr.equals(sep) ? sep.len() : 0;
}

StringList String::split_by_str(String sep, Allocator* allocator)
{
    return this->split_pred(split_by_str_pred, &sep, allocator);
}

static isize split_by_char_pred(String rest, void *data)
{
    return rest[0] == *(u8 *)data ? 1 : 0;
}

StringList String::split_by_char(char sep, Allocator* allocator)
{
    return this->split_pred(split_by_char_pred, &sep, allocator);
}

static isize split_by_whitespace_pred(String rest, void *data)
{
    int i = 0;
    for (i = 0; i < rest.len(); ++i)
    {
        if (!isspace(rest[i])) break;
    }
    return i;
}

StringList String::split_by_whitespace(Allocator* allocator)
{
    return this->split_tokens_pred(split_by_whitespace_pred, NULL, allocator);
}

StringList String::split_by_lines(Allocator* allocator)
{
    return this->split_by_char('\n', allocator);
}

String String::inspect()
{
    return this->inspect(0, this->m_len);
}

String String::inspect(isize idx, isize len)
{
    std::cout << this->substr(idx, len) << std::endl;
    return *this;
}

std::ostream& operator<<(std::ostream& os, String string)
{
    for (isize i = 0; i < string.len(); ++i)
    {
        os << string[i];
    }

    return os;
}

StringList::Node* StringList::alloc_node(Allocator* allocator, String string)
{
    StringList::Node *node = AllocateZero(allocator, StringList::Node);
    node->string = string;
    return node;
}

void StringList::push_back_explicit(StringList::Node *node)
{
    DLLPushBack(this->head, this->tail, node);
}

void StringList::push_back(String string, Allocator* allocator)
{
    StringList::Node *node = StringList::alloc_node(allocator, string);
    this->push_back_explicit(node);
}

String StringList::join(Allocator* allocator)
{
    return StringList::join_string_sep("", allocator);
}

String StringList::join_string_sep(String sep, Allocator* allocator)
{
    // TODO(xearty): Do these two in one pass
    isize non_sep_len = str_list_accumulate_length(*this);
    isize count = str_list_length(*this);
    isize sep_count = count - 1;
    isize len = non_sep_len + (sep_count * sep.len());

    StringBuf result = StringBuf::init_with_capacity(allocator, len + 1);

    IterateList(this)
    {
        result.append_assume_capacity(it->string);
        if (it != this->tail)
        {
            result.append_assume_capacity(sep);
        }
    }

    return result.detach();
}

String StringList::join_char_sep(char sep, Allocator* allocator)
{
    return this->join_string_sep(String((u8*)&sep, 1), allocator);
}

}
