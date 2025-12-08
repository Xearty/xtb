#ifndef _XTB_ARRAY_H_
#define _XTB_ARRAY_H_

#include <xtb_core/core.h>
#include <xtb_core/allocator.h>
#include <xtb_core/contract.h>
#include <xtb_core/slice.h>
#include <iterator>

#include <initializer_list>
#include <algorithm>
#include <stdio.h>
#include <utility>

namespace xtb
{

template <typename It>
struct EnumerateIterator
{
    using Ref = decltype(*std::declval<It>());
    using Pair = std::pair<const isize, Ref>;

    isize index;
    It iterator;

    explicit EnumerateIterator(isize index, It iterator) : index(index), iterator(iterator) {}

    bool operator!=(const EnumerateIterator<It>& other) const
    {
        return this->iterator != other.iterator;
    }

    void operator++()
    {
        ++this->index;
        ++this->iterator;
    }

    Pair operator*() const
    {
        return Pair { this->index, *this->iterator };
    }
};

template <typename R>
struct EnumerateRange
{
    R range;

    auto begin()
    {
        using It = decltype(std::begin(this->range));
        return EnumerateIterator<It>(0, std::begin(this->range));
    }

    auto end()
    {
        using It = decltype(std::end(this->range));
        return EnumerateIterator<It>(0, std::end(this->range));
    }
};

template <typename R>
auto enumerate(R& range)
{
    return EnumerateRange<R&>{ range };
}

template <typename R>
auto enumerate(const R& range)
{
    return EnumerateRange<const R&>{ range };
}

// TODO: Make an OwningArray Array variant that calls destructors
template <typename T>
struct Array
{
    Array() = default;

    explicit Array(Allocator *allocator, isize capacity = 0)
        : m_allocator(allocator)
    {
        this->ensure_capacity(capacity);
    }

    explicit Array(Allocator *allocator, const T *pointer, isize size)
        : Array(allocator, size)
    {
        for (isize i = 0; i < size; ++i)
        {
            this->append_assume_capacity(pointer[i]);
        }
    }

    static Array<T> init(Allocator *allocator)
    {
        return Array(allocator);
    }

    static Array<T> init_with_capacity(Allocator *allocator, isize capacity)
    {
        return Array(allocator, capacity);
    }

    static Array<T> from_pointer(Allocator *allocator, T *pointer, isize size)
    {
        return Array(allocator, pointer, size);
    }

    Array(std::initializer_list<T> ilist) : m_allocator(allocator_get_heap())
    {
        this->ensure_capacity(ilist.size());
        std::copy(ilist.begin(), ilist.end(), m_data);
        m_size = ilist.size();
    }

    static Array<T> init_with_size(Allocator *allocator, isize size)
    {
        auto result = Array::init(allocator);
        result.resize(size);
        return result;
    }

    void deinit()
    {
        deallocate(m_allocator, m_data);
    }

    void reserve(isize capacity)
    {
        this->ensure_capacity(capacity);
    }

    void resize(isize size)
    {
        this->reserve(size);
        for (isize i = m_size; i < size; ++i)
        {
            m_data[i] = T{};
        }
        m_size = size;
    }

    void append(const T& item)
    {
        this->ensure_capacity(m_size + 1);
        this->append_assume_capacity(item);
    }

    void append(const T* pointer, isize size)
    {
        this->ensure_capacity(m_size + size);
        this->append_assume_capacity(pointer, size);
    }

    void append(std::initializer_list<T> ilist)
    {
        this->ensure_capacity(m_size + ilist.size());
        this->append_assume_capacity(ilist);
    }

    void append_assume_capacity(const T& item)
    {
        Assert(m_size + 1 <= m_capacity);
        m_data[m_size++] = item;
    }

    void append_assume_capacity(const T* pointer, isize size)
    {
        Assert(m_size + size <= m_capacity);
        for (isize i = 0; i < size; ++i)
        {
            this->append_assume_capacity(pointer[i]);
        }
    }

    void append_assume_capacity(std::initializer_list<T> ilist)
    {
        Assert(m_size + (isize)ilist.size() <= m_capacity);
        for (const T& item : ilist)
        {
            m_data[m_size++] = item;
        }
    }

    isize size() const { return m_size; }
    isize capacity() const { return m_capacity; };
    T* data() const { return m_data; }

    void clear()
    {
        deallocate(m_allocator, m_data);
        m_data = NULL;
        m_size = 0;
        m_capacity = 0;
    }

    T& operator[](isize index)
    {
        Assert(index < m_size);
        return m_data[index];
    }

    const T& operator[](isize index) const
    {
        Assert(index < m_size);
        return m_data[index];
    }

    void destroy_items()
    {
        if constexpr (!std::is_trivially_destructible_v<T>)
        {
            for (isize i = 0; i < m_size; ++i)
            {
                m_data[i].~T();
            }
        }
    }

    const T* begin() const { return m_data; }
    const T* end() const { return m_data + m_size; }

    const T* cbegin() const { return m_data; }
    const T* cend() const { return m_data + m_size; }

    auto enumerate() { return xtb::enumerate(*this); }

    [[nodiscard]] Slice<T>       to_slice()       noexcept { return Slice<T>(m_data, m_size); }
    [[nodiscard]] Slice<const T> to_slice() const noexcept { return Slice<const T>(m_data, m_size); }

protected:
    void ensure_capacity(isize needed)
    {
        if (m_capacity >= needed) return;

        isize new_capacity = GrowGeometric(m_capacity, needed);

        m_data = reallocate<T>(m_allocator, (void*)m_data, m_capacity, new_capacity);
        Assert(m_data != NULL);

        m_capacity = new_capacity;
    }

protected:
    Allocator* m_allocator = NULL;
    T* m_data = NULL;
    isize m_size = 0;
    isize m_capacity = 0;
};

template <typename T>
[[nodiscard]] constexpr Slice<T> slice(const Array<T>& array) noexcept
{
    return Slice<T>(array.data(), array.size());
}

}

#endif // _XTB_ARRAY_H_
