module xtb.core.array;

import core.internal.traits : hasElaborateDestructor;
import core.lifetime : emplace, move, moveEmplace;
import core.stdc.string : memmove;
import xtb.core.memory : Allocator, deallocate, tryAllocate, tryReallocate;
import xtb.core.panic : panic, require;
import xtb.core.types : multiplyOverflows;

version (unittest)
{
    private __gshared size_t trackedDestructions;
    private __gshared int[16] destructionOrder;
    private __gshared int copyableLiveElements;

    private struct TrackedElement
    {
        int value;
        bool active;

        @disable this(this);

        this(int value) nothrow @nogc
        {
            this.value = value;
            active = true;
        }

        ~this() nothrow @nogc
        {
            if (!active)
                return;
            destructionOrder[trackedDestructions++] = value;
            active = false;
        }
    }

    private struct CopyableElement
    {
        int value;
        bool active;

        this(int value) nothrow @nogc
        {
            this.value = value;
            active = true;
            ++copyableLiveElements;
        }

        this(this) nothrow @nogc
        {
            if (active)
                ++copyableLiveElements;
        }

        ~this() nothrow @nogc
        {
            if (!active)
                return;
            active = false;
            --copyableLiveElements;
        }
    }
}

struct Array(T)
{
    private Allocator* allocator_;
    private T* data_;
    private size_t length_;
    private size_t capacity_;

    @disable this(this);

    static Array create(Allocator* allocator) nothrow @nogc
    {
        require(allocator !is null, "Array requires an allocator");
        Array result;
        result.allocator_ = allocator;
        return result;
    }

    static Array withCapacity(Allocator* allocator, size_t capacity)
        nothrow @nogc
    {
        Array result = create(allocator);
        if (capacity != 0 && !result.tryReserve(capacity))
            panic("Array allocation failed");
        return result;
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t capacity,
        Array* output,
    ) nothrow @nogc
    {
        require(output !is null, "Array output pointer is null");
        *output = create(allocator);
        return (*output).tryReserve(capacity);
    }

    static Array withLength(Allocator* allocator, size_t length)
        nothrow @nogc
    {
        Array result = create(allocator);
        result.resize(length);
        return result;
    }

    static Array fromSlice(U = T)(Allocator* allocator, scope const(T)[] values)
        nothrow @nogc
        if (is(U == T) && __traits(isCopyable, T))
    {
        Array result = withCapacity(allocator, values.length);
        result.append(values);
        return result;
    }

    ~this() nothrow @nogc
    {
        deinit();
    }

    void deinit() nothrow @nogc
    {
        destroyElements(data_, length_);
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

private void constructInitial(T)(T* destination) nothrow @nogc
{
    static if (__traits(isPOD, T))
        *destination = T.init;
    else
        emplace(destination);
}

private void constructMove(T)(T* destination, ref T source) nothrow @nogc
{
    static if (__traits(isPOD, T))
        *destination = source;
    else
        moveEmplace(source, *destination);
}

private void constructCopy(T, U)(T* destination, ref U source) nothrow @nogc
{
    static if (__traits(isPOD, T))
        *destination = source;
    else
        emplace(destination, source);
}

private void destroyElement(T)(T* element) nothrow @nogc
{
    static if (hasElaborateDestructor!T)
        destroy!false(*element);
}

private void destroyElements(T)(T* data, size_t length) nothrow @nogc
{
    static if (hasElaborateDestructor!T)
    {
        while (length != 0)
            destroyElement(data + --length);
    }
}

private bool trySetCapacity(T)(ref Array!T array, size_t capacity)
    nothrow @nogc
{
    if (multiplyOverflows(capacity, T.sizeof))
        return false;

    static if (__traits(isPOD, T))
    {
        void* replacement = array.allocator_.tryReallocate(
            capacity * T.sizeof,
            array.data_,
            array.capacity_ * T.sizeof,
            T.alignof,
        );
        if (capacity != 0 && replacement is null)
            return false;
        array.data_ = cast(T*) replacement;
    }
    else
    {
        T* replacement = array.allocator_.tryAllocate!T(capacity);
        if (capacity != 0 && replacement is null)
            return false;
        foreach (i; 0 .. array.length_)
            constructMove(replacement + i, array.data_[i]);
        array.allocator_.deallocate(array.data_, array.capacity_);
        array.data_ = replacement;
    }
    array.capacity_ = capacity;
    return true;
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

    return array.trySetCapacity(capacity);
}

void reserve(T)(ref Array!T array, size_t requested) nothrow @nogc
{
    if (!array.tryReserve(requested))
        panic("Array allocation failed");
}

bool tryResize(T)(ref Array!T array, size_t requested) nothrow @nogc
{
    if (requested < array.length_)
    {
        destroyElements(array.data_ + requested, array.length_ - requested);
        array.length_ = requested;
        return true;
    }
    if (!array.tryReserve(requested))
        return false;
    while (array.length_ < requested)
    {
        constructInitial(array.data_ + array.length_);
        ++array.length_;
    }
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
    constructMove(array.data_ + array.length_, value);
    ++array.length_;
    return true;
}

void append(T)(ref Array!T array, T value) nothrow @nogc
{
    if (!array.tryAppend(move(value)))
        panic("Array allocation failed");
}

void appendAssumeCapacity(T)(ref Array!T array, T value) nothrow @nogc
{
    require(array.length_ < array.capacity_, "Array capacity exceeded");
    constructMove(array.data_ + array.length_, value);
    ++array.length_;
}

bool tryAppend(T)(ref Array!T array, scope const(T)[] values) nothrow @nogc
    if (__traits(isCopyable, T))
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

    const oldLength = array.length_;
    const newLength = oldLength + values.length;
    if (!array.tryReserve(newLength))
        return false;
    const(T)* source = aliasesArray ? array.data_ + sourceOffset : values.ptr;
    static if (__traits(isPOD, T))
    {
        if (values.length != 0)
            memmove(array.data_ + array.length_, source, values.length * T.sizeof);
        array.length_ = newLength;
    }
    else
    {
        while (array.length_ < newLength)
        {
            constructCopy(array.data_ + array.length_, source[array.length_ - oldLength]);
            ++array.length_;
        }
    }
    return true;
}

void append(T)(ref Array!T array, scope const(T)[] values) nothrow @nogc
    if (__traits(isCopyable, T))
{
    if (!array.tryAppend(values))
        panic("Array allocation failed");
}

void appendAssumeCapacity(T)(
    ref Array!T array,
    scope const(T)[] values,
) nothrow @nogc
    if (__traits(isCopyable, T))
{
    require(values.length <= array.capacity_ - array.length_,
        "Array capacity exceeded");
    static if (__traits(isPOD, T))
    {
        if (values.length != 0)
            memmove(array.data_ + array.length_, values.ptr, values.length * T.sizeof);
        array.length_ += values.length;
    }
    else
    {
        foreach (ref value; values)
        {
            constructCopy(array.data_ + array.length_, value);
            ++array.length_;
        }
    }
}

bool tryInsert(T)(ref Array!T array, size_t index, T value) nothrow @nogc
{
    require(index <= array.length_, "Array insert index out of bounds");
    if (array.length_ == size_t.max || !array.tryReserve(array.length_ + 1))
        return false;
    static if (__traits(isPOD, T))
    {
        const following = array.length_ - index;
        if (following != 0)
            memmove(array.data_ + index + 1, array.data_ + index, following * T.sizeof);
    }
    else
    {
        size_t position = array.length_;
        while (position > index)
        {
            constructMove(array.data_ + position, array.data_[position - 1]);
            --position;
        }
    }
    constructMove(array.data_ + index, value);
    ++array.length_;
    return true;
}

bool tryInsert(T)(
    ref Array!T array,
    size_t index,
    scope const(T)[] values,
) nothrow @nogc
    if (__traits(isCopyable, T))
{
    require(index <= array.length_, "Array insert index out of bounds");
    if (values.length > size_t.max - array.length_)
        return false;
    if (values.length == 0)
        return true;

    bool aliasesArray;
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
            return false;
        }
    }

    const oldLength = array.length_;
    const newLength = oldLength + values.length;
    if (!array.tryReserve(newLength))
        return false;
    static if (__traits(isPOD, T))
    {
        const following = oldLength - index;
        if (following != 0)
            memmove(array.data_ + index + values.length,
                array.data_ + index, following * T.sizeof);
        if (values.length != 0)
            memmove(array.data_ + index, values.ptr, values.length * T.sizeof);
    }
    else
    {
        size_t position = oldLength;
        while (position > index)
        {
            --position;
            constructMove(array.data_ + position + values.length, array.data_[position]);
        }
        foreach (offset, ref value; values)
            constructCopy(array.data_ + index + offset, value);
    }
    array.length_ = newLength;
    return true;
}

void insert(T)(ref Array!T array, size_t index, T value) nothrow @nogc
{
    if (!array.tryInsert(index, move(value)))
        panic("Array allocation failed");
}

void insert(T)(ref Array!T array, size_t index, scope const(T)[] values)
    nothrow @nogc
    if (__traits(isCopyable, T))
{
    if (!array.tryInsert(index, values))
        panic("Array allocation failed");
}

T pop(T)(ref Array!T array) nothrow @nogc
{
    require(array.length_ != 0, "cannot pop an empty Array");
    --array.length_;
    T result = void;
    static if (__traits(isPOD, T))
        result = array.data_[array.length_];
    else
        constructMove(&result, array.data_[array.length_]);
    return result;
}

void clear(T)(ref Array!T array) nothrow @nogc
{
    destroyElements(array.data_, array.length_);
    array.length_ = 0;
}

void removeAt(T)(ref Array!T array, size_t index) nothrow @nogc
{
    require(index < array.length_, "Array index out of bounds");
    static if (__traits(isPOD, T))
    {
        const following = array.length_ - index - 1;
        if (following != 0)
            memmove(array.data_ + index, array.data_ + index + 1, following * T.sizeof);
    }
    else
    {
        destroyElement(array.data_ + index);
        foreach (i; index .. array.length_ - 1)
            constructMove(array.data_ + i, array.data_[i + 1]);
    }
    --array.length_;
}

void removeRange(T)(ref Array!T array, size_t index, size_t count)
    nothrow @nogc
{
    require(index <= array.length_, "Array range index out of bounds");
    require(count <= array.length_ - index, "Array range count out of bounds");
    if (count == 0)
        return;
    static if (__traits(isPOD, T))
    {
        const following = array.length_ - index - count;
        if (following != 0)
            memmove(array.data_ + index, array.data_ + index + count, following * T.sizeof);
    }
    else
    {
        destroyElements(array.data_ + index, count);
        foreach (i; index .. array.length_ - count)
            constructMove(array.data_ + i, array.data_[i + count]);
    }
    array.length_ -= count;
}

bool tryShrinkToFit(T)(ref Array!T array) nothrow @nogc
{
    if (array.length_ == array.capacity_)
        return true;
    if (array.length_ == 0)
    {
        array.resetAndRelease();
        return true;
    }
    return array.trySetCapacity(array.length_);
}

void shrinkToFit(T)(ref Array!T array) nothrow @nogc
{
    if (!array.tryShrinkToFit())
        panic("Array allocation failed");
}

void resetAndRelease(T)(ref Array!T array) nothrow @nogc
{
    destroyElements(array.data_, array.length_);
    array.allocator_.deallocate(array.data_, array.capacity_);
    array.data_ = null;
    array.length_ = 0;
    array.capacity_ = 0;
}

nothrow @nogc unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator, mallocAllocator;

    Array!int zero;
    zero.deinit();
    zero.resetAndRelease();

    Array!int values = Array!int.withCapacity(mallocAllocator(), 1);
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
    values.insert(1, 9);
    assert(values[1] == 9);
    values.removeRange(1, 2);
    assert(values.length == 3);
    values.shrinkToFit();
    assert(values.capacity == values.length);
    values.clear();
    assert(values.empty);
    values.resetAndRelease();
    assert(values.capacity == 0);

    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Array!int fallible = Array!int.withCapacity(tracked.handle, 1);
    while (fallible.length < fallible.capacity)
        fallible.appendAssumeCapacity(42);
    const previousLength = fallible.length;
    tracked.failAfter(0);
    assert(!fallible.tryAppend(7));
    assert(fallible.length == previousLength && fallible[0] == 42);
    fallible.deinit();
    assert(tracked.clean);
}

nothrow @nogc unittest
{
    import xtb.core.memory : mallocAllocator;

    trackedDestructions = 0;
    destructionOrder[] = 0;

    Array!TrackedElement values = Array!TrackedElement.withCapacity(
        mallocAllocator(),
        1,
    );
    values.append(TrackedElement(1));
    values.append(TrackedElement(3));
    values.insert(1, TrackedElement(2));
    assert(values.length == 3);
    assert(values[0].value == 1);
    assert(values[1].value == 2);
    assert(values[2].value == 3);
    assert(trackedDestructions == 0);

    values.removeAt(1);
    assert(values.length == 2);
    assert(values[1].value == 3);
    assert(trackedDestructions == 1);
    assert(destructionOrder[0] == 2);

    {
        TrackedElement value = values.pop();
        assert(value.value == 3);
        assert(trackedDestructions == 1);
    }
    assert(trackedDestructions == 2);
    assert(destructionOrder[1] == 3);

    values.append(TrackedElement(4));
    values.append(TrackedElement(5));
    values.clear();
    assert(trackedDestructions == 5);
    assert(destructionOrder[2] == 5);
    assert(destructionOrder[3] == 4);
    assert(destructionOrder[4] == 1);

    values.append(TrackedElement(6));
    values.resetAndRelease();
    assert(trackedDestructions == 6);
    assert(destructionOrder[5] == 6);
    values.deinit();
    assert(trackedDestructions == 6);
}

nothrow @nogc unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator, mallocAllocator;

    copyableLiveElements = 0;
    {
        CopyableElement[2] source = [CopyableElement(7), CopyableElement(8)];
        assert(copyableLiveElements == 2);
        Array!CopyableElement values = Array!CopyableElement.fromSlice(
            mallocAllocator(),
            source[],
        );
        assert(copyableLiveElements == 4);
        values.append(source[]);
        assert(copyableLiveElements == 6);
        values.shrinkToFit();
        values.append(values.slice[0 .. 2]);
        assert(copyableLiveElements == 8);
        values.removeRange(1, 2);
        assert(copyableLiveElements == 6);
        values.shrinkToFit();
        assert(copyableLiveElements == 6);
    }
    assert(copyableLiveElements == 0);

    AllocationRecord[16] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Array!(Array!int) arrays = Array!(Array!int).create(tracked.handle);
    Array!int child = Array!int.create(tracked.handle);
    child.append(42);
    arrays.append(move(child));
    assert(arrays.length == 1);
    assert(arrays[0][0] == 42);
    arrays.clear();
    assert(arrays.empty);
    arrays.resetAndRelease();
    assert(tracked.clean);
}
