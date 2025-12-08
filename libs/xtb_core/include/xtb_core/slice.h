#ifndef XTB_SLICE_H
#define XTB_SLICE_H

#include <xtb_core/core.h>
#include <xtb_core/contract.h>

namespace xtb
{

template <typename T>
struct Slice
{
    using value_type     = T;
    using iterator       = T*;
    using const_iterator = const T*;

    Slice() = default;
    Slice(T* data, isize size) : m_data(data), m_size(size) {}

    [[nodiscard]] isize size() const noexcept { return m_size; }
    [[nodiscard]] bool is_empty() const noexcept { return m_size == 0; }

    [[nodiscard]] T* data() noexcept { return m_data; }
    [[nodiscard]] const T* data() const noexcept { return m_data; }

    [[nodiscard]] T& operator[](isize index) noexcept
    {
        Assert(index >= 0 && index < m_size);
        return m_data[index];
    }

    [[nodiscard]] const T& operator[](isize index) const noexcept
    {
        Assert(index >= 0 && index < m_size);
        return m_data[index];
    }

    operator Slice<const T>() const noexcept { return Slice<const T>(m_data, m_size); }

    iterator begin() noexcept { return m_data; }
    iterator end()   noexcept { return m_data + m_size; }

    const_iterator begin() const noexcept { return m_data; }
    const_iterator end()   const noexcept { return m_data + m_size; }
    const_iterator cbegin() const noexcept { return m_data; }
    const_iterator cend()   const noexcept { return m_data + m_size; }

    // TODO
    [[nodiscard]] Slice subslice(isize offset, isize count) const noexcept
    {
        Assert(offset >= 0 && offset <= m_size);
        Assert(count >= 0 && count <= m_size);
        Assert(offset + count <= m_size);

        return Slice(offset, count);
    }

    [[nodiscard]] Slice subslice(isize offset) const noexcept
    {
        return subslice(offset, m_size);
    }

    [[nodiscard]] Slice drop(isize n) const noexcept
    {
        n = Clamp(n, 0, m_size);
        return Slice(m_data + n, m_size - n);
    }

    [[nodiscard]] Slice take(isize n) const noexcept
    {
        n = Clamp(n, 0, m_size);
        return Slice(m_data, n);
    }

    [[nodiscard]] Slice drop_last(isize n) const noexcept
    {
        n = Clamp(n, 0, m_size);
        return Slice(m_data, m_size - n);
    }

    [[nodiscard]] Slice take_last(isize n) const noexcept
    {
        n = Clamp(n, 0, m_size);
        return Slice(m_data + (m_size - n), n);
    }

    [[nodiscard]] Slice slice_range(isize from, isize to) const noexcept
    {
        Assert(from >= 0 && to >= from && to <= m_size);
        return Slice(m_data + from, to - from);
    }

    [[nodiscard]] T& front() noexcept
    {
        Assert(m_size > 0);
        return m_data[0];
    }

    [[nodiscard]] const T& front() const noexcept
    {
        Assert(m_size > 0);
        return m_data[0];
    }

    [[nodiscard]] T& back() noexcept
    {
        Assert(m_size > 0);
        return m_data[m_size - 1];
    }

    [[nodiscard]] const T& back() const noexcept
    {
        Assert(m_size > 0);
        return m_data[m_size - 1];
    }

private:
    T*    m_data = NULL;
    isize m_size = 0;
};

template <typename T, isize N>
[[nodiscard]] constexpr Slice<T> slice(T (&arr)[N]) noexcept
{
    return Slice<T>(arr, N);
}

template <typename T>
[[nodiscard]] constexpr Slice<T> slice(Slice<T> s) noexcept
{
    // surprisingly handy
    return s;
}

}

#endif // XTB_SLICE_H
