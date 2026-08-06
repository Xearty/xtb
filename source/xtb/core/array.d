module xtb.core.array;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.lifetime : emplace, move, moveEmplace;
import core.stdc.string : memmove;
import xtb.core.memory : Allocator, deallocate, tryAllocate, tryReallocate;
import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.panic : panic, require;
import xtb.core.numeric : multiplyOverflows;

/// Raw allocation detached from an unmanaged array.
///
/// This package-only token has no destructor. The caller assumes ownership of
/// every live element and must eventually adopt or explicitly destroy and
/// deallocate the storage with the originating allocator.
package(xtb) struct RawArrayStorage(T)
{
    T* data;
    size_t length;
    size_t capacity;
}

version (unittest)
{
    private __gshared size_t trackedDestructions;
    private __gshared int[16] destructionOrder;
    private __gshared int copyableLiveElements;

    private struct TrackedElement
    {
    nothrow @nogc:

        int value;
        bool active;

        @disable this(this);

        this(int value)
        {
            this.value = value;
            active = true;
        }

        ~this()
        {
            if (!active)
                return;
            destructionOrder[trackedDestructions++] = value;
            active = false;
        }
    }

    private void appendReleasedValue(
        ref ArrayUnmanaged!int storage,
        Allocator* allocator,
        int value,
    )
    {
        storage.append(allocator, value);
    }

    private struct CopyableElement
    {
    nothrow @nogc:

        int value;
        bool active;

        this(int value)
        {
            this.value = value;
            active = true;
            ++copyableLiveElements;
        }

        this(this)
        {
            if (active)
                ++copyableLiveElements;
        }

        ~this()
        {
            if (!active)
                return;
            active = false;
            --copyableLiveElements;
        }
    }
}

struct ArrayUnmanaged(T)
{
nothrow @nogc:

private:
    T* data_;
    size_t length_;
    size_t capacity_;

public:
    @disable this(this);

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t capacity,
        scope ArrayUnmanaged* output,
    )
    {
        require(output !is null, "ArrayUnmanaged output pointer is null");
        require(output.data_ is null && output.length_ == 0 &&
                output.capacity_ == 0,
            "ArrayUnmanaged output is not empty");
        requireValidAllocator(allocator);
        ArrayUnmanaged temporary;
        if (capacity != 0 && !temporary.tryReserve(allocator, capacity))
            return false;
        *output = move(temporary);
        return true;
    }

    static ArrayUnmanaged withCapacity(
        Allocator* allocator,
        size_t capacity,
    )
    {
        ArrayUnmanaged result;
        if (!tryWithCapacity(allocator, capacity, &result))
            panic("Array allocation failed");
        return result;
    }

    static ArrayUnmanaged withLength(
        Allocator* allocator,
        size_t length,
    )
    {
        ArrayUnmanaged result;
        result.resize(allocator, length);
        return result;
    }

    static if (__traits(isCopyable, T))
    {
        static ArrayUnmanaged fromSlice(
            Allocator* allocator,
            scope const(T)[] values,
        )
        {
            ArrayUnmanaged result = withCapacity(allocator, values.length);
            result.append(allocator, values);
            return result;
        }
    }

package(xtb):
    static ArrayUnmanaged adopt(
        T* data,
        size_t length,
        size_t capacity,
    ) @system
    {
        require(length <= capacity,
            "adopted ArrayUnmanaged length exceeds capacity");
        require((capacity == 0) == (data is null),
            "adopted ArrayUnmanaged storage does not match capacity");
        ArrayUnmanaged result;
        result.data_ = data;
        result.length_ = length;
        result.capacity_ = capacity;
        return result;
    }

    RawArrayStorage!T releaseRaw() @system
    {
        RawArrayStorage!T result = RawArrayStorage!T(
            data_,
            length_,
            capacity_,
        );
        data_ = null;
        length_ = 0;
        capacity_ = 0;
        return result;
    }

public:
    void deinit(Allocator* allocator)
    {
        if (capacity_ != 0)
            requireValidAllocator(allocator);
        destroyElements(data_, length_);
        if (capacity_ != 0)
            allocator.deallocate(data_, capacity_);
        this = ArrayUnmanaged.init;
    }

    void resetAndRelease(Allocator* allocator)
    {
        if (capacity_ != 0)
            requireValidAllocator(allocator);
        destroyElements(data_, length_);
        if (capacity_ != 0)
            allocator.deallocate(data_, capacity_);
        data_ = null;
        length_ = 0;
        capacity_ = 0;
    }

    size_t length() const pure @safe
    {
        return length_;
    }

    size_t capacity() const pure @safe
    {
        return capacity_;
    }

    bool empty() const pure @safe
    {
        return length_ == 0;
    }

    T[] slice() return pure @system
    {
        return data_[0 .. length_];
    }

    const(T)[] slice() const return pure @system
    {
        return data_[0 .. length_];
    }

    ref T opIndex(size_t index) return @system
    {
        require(index < length_, "Array index out of bounds");
        return data_[index];
    }

    ref const(T) opIndex(size_t index) const return @system
    {
        require(index < length_, "Array index out of bounds");
        return data_[index];
    }

    bool tryReserve(Allocator* allocator, size_t requested)
    {
        requireValidAllocator(allocator);
        if (requested <= capacity_)
            return true;

        size_t capacity = capacity_ == 0 ? 8 : capacity_;
        while (capacity < requested)
        {
            if (capacity > size_t.max / 2)
            {
                capacity = requested;
                break;
            }
            capacity *= 2;
        }
        return trySetCapacity(allocator, capacity);
    }

    void reserve(Allocator* allocator, size_t requested)
    {
        if (!tryReserve(allocator, requested))
            panic("Array allocation failed");
    }

    bool tryResize(Allocator* allocator, size_t requested)
    {
        requireValidAllocator(allocator);
        if (requested < length_)
        {
            destroyElements(data_ + requested, length_ - requested);
            length_ = requested;
            return true;
        }
        if (!tryReserve(allocator, requested))
            return false;
        while (length_ < requested)
        {
            constructInitial(data_ + length_);
            ++length_;
        }
        return true;
    }

    void resize(Allocator* allocator, size_t requested)
    {
        if (!tryResize(allocator, requested))
            panic("Array allocation failed");
    }

    bool tryAppend(Allocator* allocator, T value)
    {
        requireValidAllocator(allocator);
        if (length_ == size_t.max || !tryReserve(allocator, length_ + 1))
            return false;
        constructMove(data_ + length_, value);
        ++length_;
        return true;
    }

    void append(Allocator* allocator, T value)
    {
        if (!tryAppend(allocator, move(value)))
            panic("Array allocation failed");
    }

    void appendAssumeCapacity(T value)
    {
        require(length_ < capacity_, "Array capacity exceeded");
        constructMove(data_ + length_, value);
        ++length_;
    }

    static if (__traits(isCopyable, T))
    {
        bool tryAppend(
            Allocator* allocator,
            scope const(T)[] values,
        )
        {
            requireValidAllocator(allocator);
            if (values.length > size_t.max - length_)
                return false;

            bool aliasesArray;
            size_t sourceOffset;
            if (values.length != 0 && data_ !is null)
            {
                const sourceAddress = cast(size_t) values.ptr;
                const beginAddress = cast(size_t) data_;
                const endAddress = beginAddress + length_ * T.sizeof;
                aliasesArray = sourceAddress >= beginAddress &&
                    sourceAddress < endAddress;
                if (aliasesArray)
                {
                    const byteOffset = sourceAddress - beginAddress;
                    if (byteOffset % T.sizeof != 0 ||
                        values.length > length_ - byteOffset / T.sizeof)
                        return false;
                    sourceOffset = byteOffset / T.sizeof;
                }
            }

            const oldLength = length_;
            const newLength = oldLength + values.length;
            if (!tryReserve(allocator, newLength))
                return false;
            const(T)* source = aliasesArray ? data_ + sourceOffset : values.ptr;
            static if (__traits(isPOD, T))
            {
                if (values.length != 0)
                    memmove(data_ + length_, source,
                        values.length * T.sizeof);
                length_ = newLength;
            }
            else
            {
                while (length_ < newLength)
                {
                    constructCopy(data_ + length_,
                        source[length_ - oldLength]);
                    ++length_;
                }
            }
            return true;
        }

        void append(Allocator* allocator, scope const(T)[] values)
        {
            if (!tryAppend(allocator, values))
                panic("Array allocation failed");
        }

        void appendAssumeCapacity(scope const(T)[] values)
        {
            require(values.length <= capacity_ - length_,
                "Array capacity exceeded");
            static if (__traits(isPOD, T))
            {
                if (values.length != 0)
                    memmove(data_ + length_, values.ptr,
                        values.length * T.sizeof);
                length_ += values.length;
            }
            else
            {
                foreach (ref value; values)
                {
                    constructCopy(data_ + length_, value);
                    ++length_;
                }
            }
        }
    }

    bool tryInsert(
        Allocator* allocator,
        size_t index,
        T value,
    )
    {
        requireValidAllocator(allocator);
        require(index <= length_, "Array insert index out of bounds");
        if (length_ == size_t.max || !tryReserve(allocator, length_ + 1))
            return false;
        static if (__traits(isPOD, T))
        {
            const following = length_ - index;
            if (following != 0)
                memmove(data_ + index + 1, data_ + index,
                    following * T.sizeof);
        }
        else
        {
            size_t position = length_;
            while (position > index)
            {
                constructMove(data_ + position, data_[position - 1]);
                --position;
            }
        }
        constructMove(data_ + index, value);
        ++length_;
        return true;
    }

    static if (__traits(isCopyable, T))
    {
        bool tryInsert(
            Allocator* allocator,
            size_t index,
            scope const(T)[] values,
        )
        {
            requireValidAllocator(allocator);
            require(index <= length_, "Array insert index out of bounds");
            if (values.length > size_t.max - length_)
                return false;
            if (values.length == 0)
                return true;

            bool aliasesArray;
            size_t sourceOffset;
            if (data_ !is null)
            {
                const sourceAddress = cast(size_t) values.ptr;
                const beginAddress = cast(size_t) data_;
                const endAddress = beginAddress + length_ * T.sizeof;
                aliasesArray = sourceAddress >= beginAddress &&
                    sourceAddress < endAddress;
                if (aliasesArray)
                {
                    const byteOffset = sourceAddress - beginAddress;
                    if (byteOffset % T.sizeof != 0 ||
                        values.length > length_ - byteOffset / T.sizeof)
                        return false;
                    sourceOffset = byteOffset / T.sizeof;
                    static if (!__traits(isPOD, T))
                        return false;
                }
            }

            const oldLength = length_;
            const newLength = oldLength + values.length;
            if (!tryReserve(allocator, newLength))
                return false;
            static if (__traits(isPOD, T))
            {
                const following = oldLength - index;
                if (following != 0)
                    memmove(data_ + index + values.length,
                        data_ + index, following * T.sizeof);
                if (aliasesArray)
                {
                    const sourceEnd = sourceOffset + values.length;
                    const leftCount = sourceOffset < index
                        ? (sourceEnd < index ? sourceEnd : index) -
                            sourceOffset : 0;
                    const rightCount = values.length - leftCount;
                    if (leftCount != 0)
                        memmove(data_ + index, data_ + sourceOffset,
                            leftCount * T.sizeof);
                    if (rightCount != 0)
                    {
                        const rightSource = sourceOffset + leftCount +
                            values.length;
                        memmove(data_ + index + leftCount,
                            data_ + rightSource, rightCount * T.sizeof);
                    }
                }
                else
                    memmove(data_ + index, values.ptr,
                        values.length * T.sizeof);
            }
            else
            {
                size_t position = oldLength;
                while (position > index)
                {
                    --position;
                    constructMove(data_ + position + values.length,
                        data_[position]);
                }
                foreach (offset, ref value; values)
                    constructCopy(data_ + index + offset, value);
            }
            length_ = newLength;
            return true;
        }
    }

    void insert(Allocator* allocator, size_t index, T value)
    {
        if (!tryInsert(allocator, index, move(value)))
            panic("Array allocation failed");
    }

    static if (__traits(isCopyable, T))
    {
        void insert(
            Allocator* allocator,
            size_t index,
            scope const(T)[] values,
        )
        {
            if (!tryInsert(allocator, index, values))
                panic("Array allocation failed");
        }
    }

    T pop()
    {
        require(length_ != 0, "cannot pop an empty Array");
        --length_;
        T result = void;
        static if (__traits(isPOD, T))
            result = data_[length_];
        else
            constructMove(&result, data_[length_]);
        return result;
    }

    void clear()
    {
        destroyElements(data_, length_);
        length_ = 0;
    }

    void removeAt(size_t index)
    {
        require(index < length_, "Array index out of bounds");
        static if (__traits(isPOD, T))
        {
            const following = length_ - index - 1;
            if (following != 0)
                memmove(data_ + index, data_ + index + 1,
                    following * T.sizeof);
        }
        else
        {
            destroyElement(data_ + index);
            foreach (i; index .. length_ - 1)
                constructMove(data_ + i, data_[i + 1]);
        }
        --length_;
    }

    void removeRange(size_t index, size_t count)
    {
        require(index <= length_, "Array range index out of bounds");
        require(count <= length_ - index,
            "Array range count out of bounds");
        if (count == 0)
            return;
        static if (__traits(isPOD, T))
        {
            const following = length_ - index - count;
            if (following != 0)
                memmove(data_ + index, data_ + index + count,
                    following * T.sizeof);
        }
        else
        {
            destroyElements(data_ + index, count);
            foreach (i; index .. length_ - count)
                constructMove(data_ + i, data_[i + count]);
        }
        length_ -= count;
    }

    bool tryShrinkToFit(Allocator* allocator)
    {
        requireValidAllocator(allocator);
        if (length_ == capacity_)
            return true;
        if (length_ == 0)
        {
            resetAndRelease(allocator);
            return true;
        }
        return trySetCapacity(allocator, length_);
    }

    void shrinkToFit(Allocator* allocator)
    {
        if (!tryShrinkToFit(allocator))
            panic("Array allocation failed");
    }

private:
    bool trySetCapacity(Allocator* allocator, size_t capacity)
    {
        if (multiplyOverflows(capacity, T.sizeof))
            return false;

        static if (__traits(isPOD, T))
        {
            void* replacement = allocator.tryReallocate(
                capacity * T.sizeof,
                data_,
                capacity_ * T.sizeof,
                T.alignof,
            );
            if (capacity != 0 && replacement is null)
                return false;
            data_ = cast(T*) replacement;
        }
        else
        {
            T* replacement = allocator.tryAllocate!T(capacity);
            if (capacity != 0 && replacement is null)
                return false;
            foreach (i; 0 .. length_)
                constructMove(replacement + i, data_[i]);
            allocator.deallocate(data_, capacity_);
            data_ = replacement;
        }
        capacity_ = capacity;
        return true;
    }
}

struct Array(T)
{
nothrow @nogc:

    alias Self = Array!T;
    alias Storage = ArrayUnmanaged!T;

private:
    Allocator* allocator_;
    Storage storage_;

public:
    mixin ManagedContainerAdapter!(Self, Storage);

package(xtb):
    static Self adoptUnmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        requireValidAllocator(allocator);
        require(storage !is null, "ArrayUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(*storage);
        return result;
    }

    static Self adoptRaw(
        Allocator* allocator,
        T* data,
        size_t length,
        size_t capacity,
    ) @system
    {
        Storage storage = Storage.adopt(data, length, capacity);
        return adoptUnmanaged(allocator, &storage);
    }
}

private void requireValidAllocator(Allocator* allocator)
{
    require(allocator !is null && *allocator !is null,
        "Array requires a valid allocator");
}

private void constructInitial(T)(T* destination)
{
    static if (__traits(isPOD, T))
        *destination = T.init;
    else
        emplace(destination);
}

private void constructMove(T)(T* destination, ref T source)
{
    static if (__traits(isPOD, T))
        *destination = source;
    else
        moveEmplace(source, *destination);
}

private void constructCopy(T, U)(T* destination, ref U source)
{
    static if (__traits(isPOD, T))
        *destination = source;
    else
        emplace(destination, source);
}

private void destroyElement(T)(T* element)
{
    static if (hasElaborateDestructor!T)
        destroy!false(*element);
}

private void destroyElements(T)(T* data, size_t length)
{
    static if (hasElaborateDestructor!T)
    {
        while (length != 0)
            destroyElement(data + --length);
    }
}

unittest
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

    Array!int selfInserted = Array!int.fromSlice(
        mallocAllocator(),
        [1, 2, 3, 4, 5, 6, 7, 8],
    );
    selfInserted.insert(2, selfInserted.slice[1 .. 4]);
    assert(selfInserted.slice == [1, 2, 2, 3, 4, 3, 4, 5, 6, 7, 8]);

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

unittest
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

unittest
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

unittest
{
    import xtb.core.memory : AllocationRecord, Allocator,
        InstrumentedAllocator, mallocAllocator;

    static assert(ArrayUnmanaged!int.sizeof == 3 * size_t.sizeof);
    static assert(Array!int.sizeof ==
        ArrayUnmanaged!int.sizeof + (Allocator*).sizeof);
    static assert(!__traits(isCopyable, ArrayUnmanaged!int));
    static assert(!__traits(isCopyable, Array!int));
    static assert(!__traits(isCopyable, Array!int.Released));
    static assert(!__traits(compiles, () @safe {
        Array!int.Released released;
        ref ArrayUnmanaged!int storage = released.storage;
    }));
    static assert(__traits(compiles,
        (scope const Array!int.Released* released) @safe {
            const length = released.storage.length;
        }));
    static assert(!__traits(compiles, (ref Array!int.Released released) {
        released.allocator = mallocAllocator();
    }));
    static assert(!__traits(compiles, (ref Array!int managed) {
        ArrayUnmanaged!int storage = managed;
    }));

    ArrayUnmanaged!int zero;
    zero.deinit(null);
    zero.resetAndRelease(null);
    assert(zero.empty && zero.capacity == 0);

    AllocationRecord[16] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    {
        Array!int values = Array!int.withCapacity(tracked.handle, 2);
        values.append(10);
        values.append(20);

        Array!int.Released released = values.release();
        assert(values.allocator is null);
        assert(values.empty && values.capacity == 0);
        assert(released.allocator is tracked.handle);
        assert(released.storage.slice == [10, 20]);

        appendReleasedValue(
            released.storage,
            released.allocator,
            30,
        );
        assert(released.storage.slice == [10, 20, 30]);
    }
    assert(tracked.clean);

    {
        Array!int source = Array!int.fromSlice(
            tracked.handle,
            [1, 2, 3],
        );
        Array!int.Released released = source.release();
        Array!int adopted = Array!int.adopt(&released);

        assert(source.allocator is null && source.empty);
        assert(released.allocator is null);
        assert(released.storage.empty);
        assert(adopted.allocator is tracked.handle);
        assert(adopted.slice == [1, 2, 3]);
    }
    assert(tracked.clean);

    {
        Array!int source = Array!int.fromSlice(
            tracked.handle,
            [4, 5],
        );
        Array!int.Released released = source.release();

        Allocator* allocator;
        ArrayUnmanaged!int storage = released.extract(&allocator);
        assert(allocator is tracked.handle);
        assert(released.allocator is null);
        assert(released.storage.empty);

        storage.append(allocator, 6);
        assert(storage.slice == [4, 5, 6]);
        storage.deinit(allocator);
    }
    assert(tracked.clean);
}

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        mallocAllocator;

    AllocationRecord[64] managedRecords;
    AllocationRecord[64] unmanagedRecords;
    InstrumentedAllocator managedAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        managedRecords[],
    );
    InstrumentedAllocator unmanagedAllocator = InstrumentedAllocator.create(
        mallocAllocator(),
        unmanagedRecords[],
    );

    Array!int managed = Array!int.create(managedAllocator.handle);
    ArrayUnmanaged!int unmanaged;

    foreach (value; 0 .. 96)
    {
        assert(managed.tryAppend(value));
        assert(unmanaged.tryAppend(unmanagedAllocator.handle, value));
    }

    int[4] inserted = [700, 701, 702, 703];
    assert(managed.tryInsert(17, inserted[]));
    assert(unmanaged.tryInsert(
        unmanagedAllocator.handle,
        17,
        inserted[],
    ));
    managed.removeRange(9, 11);
    unmanaged.removeRange(9, 11);
    assert(managed.tryReserve(256));
    assert(unmanaged.tryReserve(unmanagedAllocator.handle, 256));
    assert(managed.tryShrinkToFit());
    assert(unmanaged.tryShrinkToFit(unmanagedAllocator.handle));

    assert(managed.slice == unmanaged.slice);
    assert(managed.length == unmanaged.length);
    assert(managed.capacity == unmanaged.capacity);
    assert(managedAllocator.stats == unmanagedAllocator.stats);

    const managedStatsBeforeClear = managedAllocator.stats;
    const unmanagedStatsBeforeClear = unmanagedAllocator.stats;
    managed.clear();
    unmanaged.clear();
    assert(managedAllocator.stats == managedStatsBeforeClear);
    assert(unmanagedAllocator.stats == unmanagedStatsBeforeClear);

    managed.deinit();
    unmanaged.deinit(unmanagedAllocator.handle);
    assert(managedAllocator.stats == unmanagedAllocator.stats);
    assert(managedAllocator.clean && unmanagedAllocator.clean);
}

unittest
{
    import xtb.core.memory : AllocationRecord, Allocator,
        InstrumentedAllocator, mallocAllocator;

    Array!int zero;
    Array!int.Released first = zero.release();
    assert(zero.allocator is null && zero.empty);
    assert(first.allocator is null && first.storage.empty);

    Array!int adopted = Array!int.adopt(&first);
    assert(first.allocator is null && first.storage.empty);
    assert(adopted.allocator is null && adopted.empty);

    Array!int.Released second = adopted.release();
    Allocator* allocator = cast(Allocator*) 1;
    ArrayUnmanaged!int storage = second.extract(&allocator);
    assert(allocator is null);
    assert(storage.empty && storage.capacity == 0);
    assert(second.allocator is null && second.storage.empty);
    storage.deinit(null);

    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    trackedDestructions = 0;
    destructionOrder[] = 0;
    {
        Array!TrackedElement values =
            Array!TrackedElement.create(tracked.handle);
        values.append(TrackedElement(91));
        auto released = values.release();
        assert(values.allocator is null && values.empty);
        assert(trackedDestructions == 0);
    }
    assert(trackedDestructions == 1);
    assert(destructionOrder[0] == 91);
    assert(tracked.clean && tracked.stats.invalidCalls == 0);
}
