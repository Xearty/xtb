#ifndef _XTB_STR_H_
#define _XTB_STR_H_

#include <xtb_core/contract.h>
#include <xtb_core/core.h>
#include <xtb_core/arena.h>
#include <xtb_core/allocator.h>
#include <xtb_core/array.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdarg.h>

#include <ostream>

namespace xtb
{

struct StringList;

struct String
{
    String() = default;
    explicit String(u8 *data, isize len) : m_data(data), m_len(len) {}

    template <isize N>
    constexpr String(const char (&lit)[N]) : m_data((u8*)lit), m_len(N - 1) {}

    static String from_cstr(const char *cstr)
    {
        return String((u8*)cstr, strlen(cstr));
    }

    u8 operator[](isize index)
    {
        Assert(index < m_len);
        return this->m_data[index];
    }

    u8* data() { return m_data; }
    const u8* data() const { return m_data; }
    isize len() { return m_len; }

    String copy(Allocator *allocator);
    String substr(isize begin_idx, isize len);

    isize find(String needle);
    isize find_last(String needle);

    isize find(u8 needle);
    isize find_last(u8 needle);

    bool contains(u8 needle);
    bool contains(String needle);

    String replace(String from, String to, Allocator* allocator);

    String concat(String other, Allocator* allocator);
    String escape(Allocator *allocator);

    String strip_extension();
    String basename();

    u8 front();
    u8 back();

    i32 compare(String other) const;
    bool equals(String other) const;
    bool operator==(String other) const { return this->equals(other); }

    String head(isize count);
    String tail(isize count);

    bool starts_with(String prefix);
    bool ends_with(String postfix);

    String trunc_left(isize count);
    String trunc_right(isize count);

    String trim_left();
    String trim_right();
    String trim();

    static String invalid();
    bool is_invalid();
    bool is_valid();

    bool is_empty() const;

    static String formatv(Allocator* allocator, const char *fmt, va_list args);
    static String format(Allocator *allocator, const char *fmt, ...);

    static String array_join(Allocator* allocator, String *array, isize count);
    static String array_join_sep(Allocator* allocator, String *array, isize count, String sep);

    // NOTE: Return types tells you how many bytes to skip
    using SplitPred = isize(String rest, void *data);

    StringList split_pred(SplitPred pred, void *data, Allocator* allocator);
    StringList split_tokens_pred(SplitPred pred, void *data, Allocator* allocator);
    StringList split_by_str(String sep, Allocator* allocator);
    StringList split_by_char(char sep, Allocator* allocator);
    StringList split_by_whitespace(Allocator* allocator);
    StringList split_by_lines(Allocator* allocator);

    // TODO: Maybe add source location
    String inspect();
    String inspect(isize idx, isize len);

private:
    u8* m_data;
    isize m_len;
};

std::ostream& operator<<(std::ostream& os, String string);

struct StringList
{
    struct Node
    {
        String string;
        struct Node *prev;
        struct Node *next;
    };

    Node *head;
    Node *tail;

    static StringList::Node* alloc_node(Allocator* allocator, String string);
    void push_back_explicit(StringList::Node *node);
    void push_back(String string, Allocator* allocator);
    String join(Allocator* allocator);
    String join_string_sep(String sep, Allocator* allocator);
    String join_char_sep(char sep, Allocator* allocator);
};

struct StringBuf : public Array<u8>
{
    using Array<u8>::Array;
    using Array<u8>::append;
    using Array<u8>::append_assume_capacity;

    explicit StringBuf(Allocator* allocator, String init_string)
        : StringBuf(allocator, init_string.data(), init_string.len()) {}

    static StringBuf init(Allocator* allocator)
    {
        return StringBuf(allocator);
    }

    static StringBuf init_with_capacity(Allocator* allocator, isize capacity)
    {
        return StringBuf(allocator, capacity);
    }

    static StringBuf from_pointer(Allocator* allocator, const u8* pointer, isize size)
    {
        return StringBuf(allocator, pointer, size);
    }

    static StringBuf from_string(Allocator* allocator, String init_string)
    {
        return StringBuf(allocator, init_string);
    }

    void append(String string)
    {
        this->append(string.data(), string.len());
    }

    void append_assume_capacity(String string)
    {
        this->append_assume_capacity(string.data(), string.len());
    }

    void prepend(String string)
    {
        // TODO: This can be optimized. If we need to grow anyway, we can insert the old content
        // in the correct place and avoid shifting afterwards
        this->ensure_capacity(m_size + string.len());
        MemoryMove(m_data + string.len(), m_data, m_size);
        MemoryCopy(m_data, string.data(), string.len());
        m_size += string.len();
    }

    String view()
    {
        return String(m_data, m_size);
    }

    void null_terminate()
    {
        if (m_size == 0 || m_data[m_size - 1] != '\0')
        {
            this->append('\0');
        }
    }

    String detach()
    {
        this->null_terminate();

        String string = String(m_data, m_size);
        this->clear();
        return string;
    }
};

inline std::ostream& operator<<(std::ostream& os, StringBuf buffer)
{
    for (isize i = 0; i < buffer.size(); ++i)
    {
        os << buffer[i];
    }

    return os;
}

}

#endif // _XTB_STR_H_
