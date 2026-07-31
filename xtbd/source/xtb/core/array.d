module xtb.core.array;

import core.stdc.string : memmove;
import xtb.core.memory : Allocator, deallocate, tryReallocate;
import xtb.core.panic : panic, require;
import xtb.core.types : multiplyOverflows;

struct Array(T)
{
    static assert(__traits(isPOD, T), "Array currently requires a POD element type");

    private Allocator* allocator_;
    private T* data_;
    private size_t length_;
    private size_t capacity_;

    @disable this(this);

    static Array init(Allocator* allocator, size_t initialCapacity = 0)
        nothrow @nogc
    {
        require(allocator !is null, "Array requires an allocator");
        Array result;
        result.allocator_ = allocator;
        if (initialCapacity != 0 && !result.tryReserve(initialCapacity))
            panic("Array allocation failed");
        return result;
    }

    ~this() nothrow @nogc
    {
        deinit();
    }

    void deinit() nothrow @nogc
    {
        if (data_ !is null)
            allocator_.deallocate(data_, capacity_);
        allocator_ = null;
        data_ = null;
        length_ = 0;
        capacity_ = 0;
    }

    size_t length() const pure nothrow @safe @nogc
    {
        return length_;
    }

    size_t capacity() const pure nothrow @safe @nogc
    {
        return capacity_;
    }

    bool empty() const pure nothrow @safe @nogc
    {
        return length_ == 0;
    }

    Allocator* allocator() return nothrow @nogc
    {
        return allocator_;
    }

    T[] slice() return nothrow @system @nogc
    {
        return data_[0 .. length_];
    }

    const(T)[] slice() const return nothrow @system @nogc
    {
        return data_[0 .. length_];
    }

    ref T opIndex(size_t index) return nothrow @system @nogc
    {
        require(index < length_, "Array index out of bounds");
        return data_[index];
    }

    ref const(T) opIndex(size_t index) const return nothrow @system @nogc
    {
        require(index < length_, "Array index out of bounds");
        return data_[index];
    }
}

bool tryReserve(T)(ref Array!T array, size_t requested) nothrow @nogc
{
    if (requested <= array.capacity_)
        return true;

    size_t capacity = array.capacity_ == 0 ? 8 : array.capacity_;
    while (capacity < requested)
    {
        if (capacity > size_t.max / 2)
        {
            capacity = requested;
            break;
        }
        capacity *= 2;
    }

    if (multiplyOverflows(capacity, T.sizeof))
        return false;

    void* replacement = array.allocator_.tryReallocate(
        capacity * T.sizeof,
        array.data_,
        array.capacity_ * T.sizeof,
        T.alignof,
    );
    if (replacement is null)
        return false;

    array.data_ = cast(T*) replacement;
    array.capacity_ = capacity;
    return true;
}

void reserve(T)(ref Array!T array, size_t requested) nothrow @nogc
{
    if (!array.tryReserve(requested))
        panic("Array allocation failed");
}

bool tryResize(T)(ref Array!T array, size_t requested) nothrow @nogc
{
    if (!array.tryReserve(requested))
        return false;

    if (requested > array.length_)
    {
        foreach (i; array.length_ .. requested)
            array.data_[i] = T.init;
    }
    array.length_ = requested;
    return true;
}

void resize(T)(ref Array!T array, size_t requested) nothrow @nogc
{
    if (!array.tryResize(requested))
        panic("Array allocation failed");
}

bool tryAppend(T)(ref Array!T array, T value) nothrow @nogc
{
    if (array.length_ == size_t.max || !array.tryReserve(array.length_ + 1))
        return false;
    array.data_[array.length_++] = value;
    return true;
}

void append(T)(ref Array!T array, T value) nothrow @nogc
{
    if (!array.tryAppend(value))
        panic("Array allocation failed");
}

bool tryAppend(T)(ref Array!T array, scope const(T)[] values) nothrow @nogc
{
    if (values.length > size_t.max - array.length_)
        return false;

    bool aliasesArray;
    size_t sourceOffset;
    if (values.length != 0 && array.data_ !is null)
    {
        const sourceAddress = cast(size_t) values.ptr;
        const beginAddress = cast(size_t) array.data_;
        const endAddress = beginAddress + array.length_ * T.sizeof;
        aliasesArray = sourceAddress >= beginAddress && sourceAddress < endAddress;
        if (aliasesArray)
        {
            const byteOffset = sourceAddress - beginAddress;
            if (byteOffset % T.sizeof != 0 ||
                values.length > array.length_ - byteOffset / T.sizeof)
                return false;
            sourceOffset = byteOffset / T.sizeof;
        }
    }

    const newLength = array.length_ + values.length;
    if (!array.tryReserve(newLength))
        return false;
    const(T)* source = aliasesArray ? array.data_ + sourceOffset : values.ptr;
    if (values.length != 0)
        memmove(array.data_ + array.length_, source, values.length * T.sizeof);
    array.length_ = newLength;
    return true;
}

void append(T)(ref Array!T array, scope const(T)[] values) nothrow @nogc
{
    if (!array.tryAppend(values))
        panic("Array allocation failed");
}

T pop(T)(ref Array!T array) nothrow @nogc
{
    require(array.length_ != 0, "cannot pop an empty Array");
    T result = array.data_[--array.length_];
    array.data_[array.length_] = T.init;
    return result;
}

void clear(T)(ref Array!T array) nothrow @nogc
{
    foreach (i; 0 .. array.length_)
        array.data_[i] = T.init;
    array.length_ = 0;
}

void removeAt(T)(ref Array!T array, size_t index) nothrow @nogc
{
    require(index < array.length_, "Array index out of bounds");
    const following = array.length_ - index - 1;
    if (following != 0)
        memmove(array.data_ + index, array.data_ + index + 1, following * T.sizeof);
    --array.length_;
    array.data_[array.length_] = T.init;
}

nothrow @nogc unittest
{
    import xtb.core.memory : mallocAllocator;

    Array!int values = Array!int.init(mallocAllocator(), 1);
    values.append(1);
    int[3] more = [2, 3, 4];
    values.append(more[]);
    values.append(values.slice[1 .. 3]);
    assert(values.length == 6);
    assert(values[2] == 3);
    values.removeAt(1);
    assert(values.slice.length == 5);
    assert(values[1] == 3);
    assert(values.pop() == 3);
    values.clear();
    assert(values.empty);
}
