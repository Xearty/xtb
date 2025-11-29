#ifndef XTB_SLICE_H
#define XTB_SLICE_H

#include <xtb_core/core.h>

namespace xtb
{

template <typename T>
struct Slice
{
    isize size() { return m_size; }
    const T* data() { return m_data; }
    const T& operator[](isize index) { return m_data[index]; }

    static Slice<T> from(T* data, isize size)
    {
        Slice<T> result;
        result.m_data = data;
        result.m_size = size;
        return result;
    }
protected:
    T* m_data;
    isize m_size;
};

template <typename T>
struct SliceMut : public Slice<T>
{
    using Slice<T>::m_data;
    using Slice<T>::m_size;

    T* data() { return m_data; }
    T& operator[](isize index) { return m_data[index]; }

    static SliceMut<T> from(T* data, isize size)
    {
        SliceMut<T> result;
        result.m_data = data;
        result.m_size = size;
        return result;
    }
};

}

#endif // XTB_SLICE_H
