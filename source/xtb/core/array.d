module xtb.core.array;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.lifetime : emplace;
import core.stdc.string : memmove;
import xtb.core.lifetime : deinitValue = deinit, move, moveEmplace, needsDeinit;
import xtb.core.memory : Allocator, deallocateArray, tryAllocateArray, tryReallocateArray;
import xtb.core.panic : panic;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.numeric : multiplyOverflows;
import xtb.core.released_storage : ReleasedStorage;

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
    private __gshared size_t trackedDeinits;
    private __gshared int[32] deinitOrder;

    private struct TrackedOwner
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

        void deinit()
        {
            if (!active)
                return;
            deinitOrder[trackedDeinits++] = value;
            active = false;
        }
    }

    private struct CopyableOwner
    {
    nothrow @nogc:

        int value;
        bool active;
        size_t* deinits;

        this(int value, size_t* deinits)
        {
            this.value = value;
            this.deinits = deinits;
            active = true;
        }

        void deinit()
        {
            if (!active)
                return;
            active = false;
            ++*deinits;
        }
    }

    private struct DestructorOnly
    {
        ~this()
        {
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
}

struct ArrayUnmanaged(T)
{
nothrow @nogc:

    alias Self = ArrayUnmanaged!T;

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
        version (XTB_Checked)
        {
            require(output !is null, "ArrayUnmanaged output pointer is null");
            require(output.data_ is null && output.length_ == 0 &&
                    output.capacity_ == 0,
                "ArrayUnmanaged output is not empty");
        }
        requireValidAllocator(allocator);
        ArrayUnmanaged temporary;
        if (capacity != 0 && !temporary.tryReserve(allocator, capacity))
            return false;
        moveEmplace(temporary, *output);
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
        version (XTB_Checked)
        {
            require(length <= capacity,
                "adopted ArrayUnmanaged length exceeds capacity");
            require((capacity == 0) == (data is null),
                "adopted ArrayUnmanaged storage does not match capacity");
        }
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
    /// Releases backing storage without finalizing logical elements.
    void deinit(Allocator* allocator)
    {
        if (capacity_ != 0)
            requireValidAllocator(allocator);
        if (capacity_ != 0)
            allocator.deallocateArray(data_[0 .. capacity_]);
    }

    /// Releases backing storage and leaves this unmanaged array reusable.
    void resetAndRelease(Allocator* allocator)
    {
        if (capacity_ != 0)
            requireValidAllocator(allocator);
        if (capacity_ != 0)
            allocator.deallocateArray(data_[0 .. capacity_]);
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
        version (XTB_Checked)
            require(index < length_, "Array index out of bounds");
        return data_[index];
    }

    ref const(T) opIndex(size_t index) const return @system
    {
        version (XTB_Checked)
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

    /// Attempts to append by moving from `*value` only after capacity succeeds.
    /// On failure `*value` and the array are unchanged.
    bool tryAppend(Allocator* allocator, scope T* value) @system
    {
        requireValidAllocator(allocator);
        version (XTB_Checked)
            require(value !is null, "Array append value pointer is null");
        if (length_ == size_t.max)
            return false;

        size_t sourceIndex;
        const aliases = logicalElementIndex(value, &sourceIndex);
        if (!tryReserve(allocator, length_ + 1))
            return false;
        T* source = aliases ? data_ + sourceIndex : value;
        constructMove(data_ + length_, *source);
        ++length_;
        return true;
    }

    void append(Allocator* allocator, T value)
    {
        if (!tryAppend(allocator, &value))
            panic("Array allocation failed");
    }

    void appendAssumeCapacity(T value)
    {
        version (XTB_Checked)
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
            version (XTB_Checked)
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
        scope T* value,
    ) @system
    {
        requireValidAllocator(allocator);
        version (XTB_Checked)
        {
            require(index <= length_, "Array insert index out of bounds");
            require(value !is null, "Array insert value pointer is null");
        }
        if (length_ == size_t.max)
            return false;

        size_t sourceIndex;
        const aliases = logicalElementIndex(value, &sourceIndex);
        if (!tryReserve(allocator, length_ + 1))
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
        T* source = aliases
            ? data_ + (sourceIndex >= index ? sourceIndex + 1 : sourceIndex) : value;
        constructMove(data_ + index, *source);
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
            version (XTB_Checked)
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
        if (!tryInsert(allocator, index, &value))
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
        version (XTB_Checked)
            require(length_ != 0, "cannot pop an empty Array");
        --length_;
        T result = void;
        static if (__traits(isPOD, T))
            result = data_[length_];
        else
            constructMove(&result, data_[length_]);
        return result;
    }

    /// Discards logical elements without finalizing them.
    void clear()
    {
        length_ = 0;
    }

    void removeAt(size_t index)
    {
        version (XTB_Checked)
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
            foreach (i; index .. length_ - 1)
                constructMove(data_ + i, data_[i + 1]);
        }
        --length_;
    }

    void removeRange(size_t index, size_t count)
    {
        version (XTB_Checked)
        {
            require(index <= length_, "Array range index out of bounds");
            require(count <= length_ - index,
                "Array range count out of bounds");
        }
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
    bool logicalElementIndex(scope const T* value, scope size_t* index) const @system
    {
        if (value is null || data_ is null || length_ == 0)
            return false;
        const address = cast(size_t) value;
        const begin = cast(size_t) data_;
        const end = begin + length_ * T.sizeof;
        if (address < begin || address >= end)
            return false;
        const byteOffset = address - begin;
        if (byteOffset % T.sizeof != 0)
            return false;
        *index = byteOffset / T.sizeof;
        return true;
    }

    bool trySetCapacity(Allocator* allocator, size_t capacity)
    {
        if (multiplyOverflows(capacity, T.sizeof))
            return false;

        static if (__traits(isPOD, T))
        {
            T[] replacement = allocator.tryReallocateArray(
                data_[0 .. capacity_],
                capacity,
            );
            if (capacity != 0 && replacement.ptr is null)
                return false;
            data_ = replacement.ptr;
        }
        else
        {
            T* replacement = allocator.tryAllocateArray!T(capacity).ptr;
            if (capacity != 0 && replacement is null)
                return false;
            foreach (i; 0 .. length_)
                constructMove(replacement + i, data_[i]);
            allocator.deallocateArray(data_[0 .. capacity_]);
            data_ = replacement;
        }
        capacity_ = capacity;
        return true;
    }
}

/// Managed shallow array.
///
/// `Array` owns only its backing allocation. Discard operations never finalize
/// logical elements; use `OwnedArray` when the container must own element
/// cleanup.
struct Array(T)
{
nothrow @nogc:

    alias Self = Array!T;
    alias Storage = ArrayUnmanaged!T;
    alias Released = ReleasedStorage!Storage;

private:
    Allocator* allocator_;
    Storage storage_;

    version (XTB_Checked)
    {
        invariant
        {
            require(&this !is null, "Array pointer is null");
        }
    }

public:
    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Creates an empty managed array bound to `allocator`.
    static Self create(Allocator* allocator) @safe
    {
        requireValidAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    /// Creates an empty managed array with at least `capacity` elements.
    static bool tryWithCapacity(
        Allocator* allocator,
        size_t capacity,
        scope Self* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "Array output pointer is null");
            require(output.allocator_ is null,
                "Array output is already initialized");
        }
        Storage storage;
        if (!Storage.tryWithCapacity(allocator, capacity, &storage))
            return false;
        output.allocator_ = allocator;
        moveEmplace(storage, output.storage_);
        return true;
    }

    /// Creates an empty managed array with at least `capacity` elements.
    static Self withCapacity(Allocator* allocator, size_t capacity) @trusted
    {
        Self result;
        if (!tryWithCapacity(allocator, capacity, &result))
            panic("Array allocation failed");
        return move(result);
    }

    /// Creates a managed array containing `length` default-initialized values.
    static Self withLength(Allocator* allocator, size_t length) @trusted
    {
        Storage storage = Storage.withLength(allocator, length);
        Self result;
        result.allocator_ = allocator;
        moveEmplace(storage, result.storage_);
        return move(result);
    }

    static if (__traits(isCopyable, T))
    {
        /// Copies `values` into a newly allocated managed array.
        static Self fromSlice(
            Allocator* allocator,
            scope const(T)[] values,
        ) @trusted
        {
            Storage storage = Storage.fromSlice(allocator, values);
            Self result;
            result.allocator_ = allocator;
            moveEmplace(storage, result.storage_);
            return move(result);
        }
    }

    /// Adopts storage previously returned by `release`.
    static Self adopt(scope Released* released) @trusted
    {
        version (XTB_Checked)
            require(released !is null, "released Array storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator_ = allocator;
        moveEmplace(storage, result.storage_);
        return move(result);
    }

    /// Releases all storage and unbinds the allocator. The zero state is valid.
    void deinit() @trusted
    {
        if (allocator_ is null)
            return;
        storage_.deinit(allocator_);
        allocator_ = null;
    }

    /// Releases allocated storage but keeps the allocator binding.
    void resetAndRelease() @trusted
    {
        storage_.resetAndRelease(allocator_);
    }

    /// Transfers allocator-bound storage out and leaves this array empty.
    Released release() @trusted
    {
        auto result = Released.fromOwnedParts(allocator_, &storage_);
        allocator_ = null;
        return move(result);
    }

    size_t length() const pure @safe
    {
        return storage_.length;
    }

    size_t capacity() const pure @safe
    {
        return storage_.capacity;
    }

    bool empty() const pure @safe
    {
        return storage_.empty;
    }

    T[] slice() return @system
    {
        return storage_.slice;
    }

    const(T)[] slice() const return @system
    {
        return storage_.slice;
    }

    bool tryReserve(size_t requested) @trusted
    {
        return storage_.tryReserve(allocator_, requested);
    }

    void reserve(size_t requested) @trusted
    {
        storage_.reserve(allocator_, requested);
    }

    bool tryResize(size_t requested) @trusted
    {
        return storage_.tryResize(allocator_, requested);
    }

    void resize(size_t requested) @trusted
    {
        storage_.resize(allocator_, requested);
    }

    bool tryAppend(scope T* value) @trusted
    {
        return storage_.tryAppend(allocator_, value);
    }

    void append(T value) @trusted
    {
        storage_.append(allocator_, move(value));
    }

    void appendAssumeCapacity(T value) @trusted
    {
        storage_.appendAssumeCapacity(move(value));
    }

    static if (__traits(isCopyable, T))
    {
        bool tryAppend(scope const(T)[] values) @trusted
        {
            return storage_.tryAppend(allocator_, values);
        }

        void append(scope const(T)[] values) @trusted
        {
            storage_.append(allocator_, values);
        }

        void appendAssumeCapacity(scope const(T)[] values) @trusted
        {
            storage_.appendAssumeCapacity(values);
        }
    }

    bool tryInsert(size_t index, scope T* value) @trusted
    {
        return storage_.tryInsert(allocator_, index, value);
    }

    void insert(size_t index, T value) @trusted
    {
        storage_.insert(allocator_, index, move(value));
    }

    static if (__traits(isCopyable, T))
    {
        bool tryInsert(size_t index, scope const(T)[] values) @trusted
        {
            return storage_.tryInsert(allocator_, index, values);
        }

        void insert(size_t index, scope const(T)[] values) @trusted
        {
            storage_.insert(allocator_, index, values);
        }
    }

    T pop() @trusted
    {
        return storage_.pop();
    }

    void clear() @trusted
    {
        storage_.clear();
    }

    void removeAt(size_t index) @trusted
    {
        storage_.removeAt(index);
    }

    void removeRange(size_t index, size_t count) @trusted
    {
        storage_.removeRange(index, count);
    }

    bool tryShrinkToFit() @trusted
    {
        return storage_.tryShrinkToFit(allocator_);
    }

    void shrinkToFit() @trusted
    {
        storage_.shrinkToFit(allocator_);
    }

    ref T opIndex(size_t index) return @system
    {
        return storage_[index];
    }

    ref const(T) opIndex(size_t index) const return @system
    {
        return storage_[index];
    }

    Allocator* allocator() return pure @safe
    {
        return allocator_;
    }

package(xtb):
    static Self adoptUnmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        requireValidAllocator(allocator);
        version (XTB_Checked)
            require(storage !is null, "ArrayUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        moveEmplace(*storage, result.storage_);
        return move(result);
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

private template supportsOwnedElementDeinit(T)
{
    static if (!needsDeinit!T)
        enum supportsOwnedElementDeinit = true;
    else
        enum supportsOwnedElementDeinit = __traits(compiles,
                deinitValue(*cast(T*) null));
}

/// Managed contiguous storage with ownership of logical element cleanup.
///
/// `OwnedArray` owns both its backing allocation and every live element. Any
/// operation that discards an element without returning it calls free `deinit`
/// when the element participates in the explicit lifetime protocol. Transfers
/// such as `pop` do not finalize the returned value.
struct OwnedArray(T)
{
nothrow @nogc:

    alias Self = OwnedArray!T;
    alias Storage = ArrayUnmanaged!T;

private:
    Allocator* allocator_;
    Storage storage_;

    version (XTB_Checked)
    {
        invariant
        {
            require(&this !is null, "OwnedArray pointer is null");
        }
    }

    void deinitRange(size_t index, size_t count) @trusted
    {
        static if (needsDeinit!T)
        {
            size_t end = index + count;
            while (end != index)
                deinitValue(storage_.slice[--end]);
        }
    }

public:
    static assert(!hasElaborateDestructor!T || needsDeinit!T,
        "OwnedArray cannot own lexical destructor-only element types");
    static assert(supportsOwnedElementDeinit!T,
        "OwnedArray element cleanup must support free deinit(value) without context");

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(Allocator* allocator) @safe
    {
        requireValidAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    static bool tryWithCapacity(
        Allocator* allocator,
        size_t capacity,
        scope Self* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "OwnedArray output pointer is null");
            require(output.allocator_ is null,
                "OwnedArray output is already initialized");
        }
        Storage storage;
        if (!Storage.tryWithCapacity(allocator, capacity, &storage))
            return false;
        output.allocator_ = allocator;
        moveEmplace(storage, output.storage_);
        return true;
    }

    static Self withCapacity(Allocator* allocator, size_t capacity) @trusted
    {
        Self result;
        if (!tryWithCapacity(allocator, capacity, &result))
            panic("OwnedArray allocation failed");
        return move(result);
    }

    static Self withLength(Allocator* allocator, size_t length) @trusted
    {
        Storage storage = Storage.withLength(allocator, length);
        Self result;
        result.allocator_ = allocator;
        moveEmplace(storage, result.storage_);
        return move(result);
    }

    static if (__traits(isCopyable, T))
    {
        static Self fromSlice(
            Allocator* allocator,
            scope const(T)[] values,
        ) @trusted
        {
            Storage storage = Storage.fromSlice(allocator, values);
            Self result;
            result.allocator_ = allocator;
            moveEmplace(storage, result.storage_);
            return move(result);
        }
    }

    /// Finalizes every live element and releases backing storage.
    void deinit() @trusted
    {
        if (allocator_ is null)
            return;
        deinitRange(0, storage_.length);
        storage_.deinit(allocator_);
        allocator_ = null;
    }

    /// Finalizes every element, releases storage, and keeps the allocator.
    void resetAndRelease() @trusted
    {
        deinitRange(0, storage_.length);
        storage_.resetAndRelease(allocator_);
    }

    size_t length() const pure @safe
    {
        return storage_.length;
    }

    size_t capacity() const pure @safe
    {
        return storage_.capacity;
    }

    bool empty() const pure @safe
    {
        return storage_.empty;
    }

    T[] slice() return @system
    {
        return storage_.slice;
    }

    const(T)[] slice() const return @system
    {
        return storage_.slice;
    }

    bool tryReserve(size_t requested) @trusted
    {
        return storage_.tryReserve(allocator_, requested);
    }

    void reserve(size_t requested) @trusted
    {
        storage_.reserve(allocator_, requested);
    }

    bool tryResize(size_t requested) @trusted
    {
        if (requested < storage_.length)
        {
            requireValidAllocator(allocator_);
            deinitRange(requested, storage_.length - requested);
        }
        return storage_.tryResize(allocator_, requested);
    }

    void resize(size_t requested) @trusted
    {
        if (!tryResize(requested))
            panic("OwnedArray allocation failed");
    }

    bool tryAppend(scope T* value) @trusted
    {
        return storage_.tryAppend(allocator_, value);
    }

    void append(T value) @trusted
    {
        storage_.append(allocator_, move(value));
    }

    void appendAssumeCapacity(T value) @trusted
    {
        storage_.appendAssumeCapacity(move(value));
    }

    static if (__traits(isCopyable, T))
    {
        bool tryAppend(scope const(T)[] values) @trusted
        {
            return storage_.tryAppend(allocator_, values);
        }

        void append(scope const(T)[] values) @trusted
        {
            storage_.append(allocator_, values);
        }

        void appendAssumeCapacity(scope const(T)[] values) @trusted
        {
            storage_.appendAssumeCapacity(values);
        }
    }

    bool tryInsert(size_t index, scope T* value) @trusted
    {
        return storage_.tryInsert(allocator_, index, value);
    }

    void insert(size_t index, T value) @trusted
    {
        storage_.insert(allocator_, index, move(value));
    }

    static if (__traits(isCopyable, T))
    {
        bool tryInsert(size_t index, scope const(T)[] values) @trusted
        {
            return storage_.tryInsert(allocator_, index, values);
        }

        void insert(size_t index, scope const(T)[] values) @trusted
        {
            storage_.insert(allocator_, index, values);
        }
    }

    T pop() @trusted
    {
        return storage_.pop();
    }

    void clear() @trusted
    {
        deinitRange(0, storage_.length);
        storage_.clear();
    }

    void removeAt(size_t index) @trusted
    {
        version (XTB_Checked)
            require(index < storage_.length, "OwnedArray index out of bounds");
        deinitRange(index, 1);
        storage_.removeAt(index);
    }

    void removeRange(size_t index, size_t count) @trusted
    {
        version (XTB_Checked)
        {
            require(index <= storage_.length,
                "OwnedArray range index out of bounds");
            require(count <= storage_.length - index,
                "OwnedArray range count out of bounds");
        }
        deinitRange(index, count);
        storage_.removeRange(index, count);
    }

    bool tryShrinkToFit() @trusted
    {
        return storage_.tryShrinkToFit(allocator_);
    }

    void shrinkToFit() @trusted
    {
        storage_.shrinkToFit(allocator_);
    }

    ref T opIndex(size_t index) return @system
    {
        return storage_[index];
    }

    ref const(T) opIndex(size_t index) const return @system
    {
        return storage_[index];
    }

    Allocator* allocator() return pure @safe
    {
        return allocator_;
    }
}

private void requireValidAllocator(Allocator* allocator) @trusted
{
    version (XTB_Checked)
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
    // Pointer-based move APIs promise that the source enters its normal
    // moved-from state. An explicit-deinit POD value may still own resources,
    // so a raw assignment would duplicate ownership and leave the source live.
    static if (__traits(isPOD, T) && !needsDeinit!T)
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

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

    static assert(ArrayUnmanaged!int.sizeof == 3 * size_t.sizeof);
    static assert(Array!int.sizeof ==
            ArrayUnmanaged!int.sizeof + (Allocator*).sizeof);
    static assert(OwnedArray!int.sizeof == Array!int.sizeof);
    static assert(!__traits(isCopyable, ArrayUnmanaged!int));
    static assert(!__traits(isCopyable, Array!int));
    static assert(!__traits(isCopyable, OwnedArray!int));
    static assert(!__traits(isCopyable, Array!int.Released));
    static assert(!__traits(compiles, () { Array!int left; Array!int right; left = move(right); }));
    static assert(!__traits(compiles, () {
            OwnedArray!int left;
            OwnedArray!int right;
            left = move(right);
        }));
    static assert(!__traits(compiles, () {
            Array!int.Released left;
            Array!int.Released right;
            left = move(right);
        }));
    static assert(!hasElaborateDestructor!(Array!int));
    static assert(!hasElaborateDestructor!(OwnedArray!int));
    static assert(!hasElaborateDestructor!(Array!int.Released));
    static assert(needsDeinit!(Array!int));
    static assert(needsDeinit!(OwnedArray!int));
    static assert(needsDeinit!(Array!int.Released));
    static assert(!__traits(compiles, () { OwnedArray!DestructorOnly value; }));
    static assert(!__traits(compiles, () { OwnedArray!(ArrayUnmanaged!int) value; }));
    static assert(!__traits(hasMember, OwnedArray!int, "release"));
    static assert(!__traits(hasMember, OwnedArray!int, "adopt"));

    Array!int zero;
    zero.deinit();
    zero.resetAndRelease();

    Array!int values = Array!int.withCapacity(mallocAllocator(), 1);
    values.append(1);
    int[3] more = [2, 3, 4];
    values.append(more[]);
    values.append(values.slice[1 .. 3]);
    assert(values.slice == [1, 2, 3, 4, 2, 3]);
    values.removeAt(1);
    assert(values.slice == [1, 3, 4, 2, 3]);
    assert(values.pop() == 3);
    values.insert(1, 9);
    assert(values.slice == [1, 9, 3, 4, 2]);
    values.removeRange(1, 2);
    assert(values.slice == [1, 4, 2]);
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
    selfInserted.deinit();

    AllocationRecord[8] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Array!int fallible = Array!int.withCapacity(tracked.allocator, 1);
    while (fallible.length < fallible.capacity)
        fallible.appendAssumeCapacity(42);
    int candidate = 7;
    const previousLength = fallible.length;
    tracked.failAfter(0);
    assert(!fallible.tryAppend(&candidate));
    assert(candidate == 7);
    assert(fallible.length == previousLength && fallible[0] == 42);
    tracked.allowAllocations();
    fallible.deinit();
    assert(tracked.clean && tracked.stats.invalidCalls == 0);
}

unittest
{
    import xtb.core.allocators.malloc : mallocAllocator;

    trackedDeinits = 0;
    deinitOrder[] = 0;

    // Array is shallow: discard paths do not deinitialize elements.
    Array!TrackedOwner shallow = Array!TrackedOwner.withCapacity(
        mallocAllocator(),
        4,
    );
    shallow.append(TrackedOwner(1));
    shallow.append(TrackedOwner(2));
    shallow.append(TrackedOwner(3));
    shallow.removeAt(1);
    assert(trackedDeinits == 0);
    shallow.resize(1);
    assert(trackedDeinits == 0);
    shallow.clear();
    assert(trackedDeinits == 0);
    shallow.deinit();
    assert(trackedDeinits == 0);

    // OwnedArray deep-cleans every discard path in reverse order where a range
    // is discarded.
    OwnedArray!TrackedOwner owned = OwnedArray!TrackedOwner.withCapacity(
        mallocAllocator(),
        4,
    );
    owned.append(TrackedOwner(10));
    owned.append(TrackedOwner(20));
    owned.append(TrackedOwner(30));
    owned.removeAt(1);
    assert(trackedDeinits == 1 && deinitOrder[0] == 20);
    owned.append(TrackedOwner(40));
    owned.append(TrackedOwner(50));
    owned.removeRange(1, 2);
    assert(trackedDeinits == 3);
    assert(deinitOrder[1] == 40);
    assert(deinitOrder[2] == 30);
    owned.append(TrackedOwner(60));
    owned.append(TrackedOwner(70));
    owned.resize(1);
    assert(trackedDeinits == 6);
    assert(deinitOrder[3] == 70);
    assert(deinitOrder[4] == 60);
    assert(deinitOrder[5] == 50);
    owned.clear();
    assert(trackedDeinits == 7 && deinitOrder[6] == 10);
    owned.deinit();
    assert(trackedDeinits == 7);
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

    AllocationRecord[32] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    // pop transfers ownership and therefore does not deinitialize the payload.
    OwnedArray!(Array!int) nested = OwnedArray!(Array!int).create(
        tracked.allocator,
    );
    Array!int first = Array!int.create(tracked.allocator);
    first.append(11);
    nested.append(move(first));
    Array!int second = Array!int.create(tracked.allocator);
    second.append(22);
    nested.append(move(second));
    assert(tracked.stats.outstandingAllocations == 3);

    Array!int transferred = nested.pop();
    assert(transferred[0] == 22);
    assert(tracked.stats.outstandingAllocations == 3);
    transferred.deinit();
    assert(tracked.stats.outstandingAllocations == 2);

    nested.clear();
    // Only the OwnedArray backing allocation remains after its child is
    // deep-cleaned.
    assert(tracked.stats.outstandingAllocations == 1);
    nested.deinit();
    assert(tracked.clean && tracked.stats.invalidCalls == 0);
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;
    import xtb.core.string : StringBuf;

    AllocationRecord[32] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    // Fallible pointer insertion preserves caller ownership on allocation
    // failure, including move-only explicit owners.
    Array!StringBuf values = Array!StringBuf.withCapacity(tracked.allocator, 1);
    StringBuf first = StringBuf.fromString(tracked.allocator, "first");
    values.append(move(first));
    while (values.length < values.capacity)
    {
        StringBuf filler = StringBuf.fromString(tracked.allocator, "filler");
        values.appendAssumeCapacity(move(filler));
    }
    StringBuf candidate = StringBuf.fromString(tracked.allocator, "candidate");
    const oldLength = values.length;
    tracked.failAfter(0);
    assert(!values.tryAppend(&candidate));
    assert(candidate.view == "candidate");
    assert(values.length == oldLength);
    tracked.allowAllocations();

    // Array is shallow, so explicitly finalize its elements before releasing
    // the backing allocation in this test.
    foreach_reverse (ref value; values.slice)
        deinitValue(value);
    values.clear();
    values.deinit();
    candidate.deinit();
    assert(tracked.clean && tracked.stats.invalidCalls == 0);
}

unittest
{
    import xtb.core.allocators.malloc : mallocAllocator;

    // tryAppend supports pointers into the array even when reserve relocates
    // storage. The original slot becomes the normal moved-from value.
    trackedDeinits = 0;
    deinitOrder[] = 0;
    OwnedArray!TrackedOwner values = OwnedArray!TrackedOwner.withCapacity(
        mallocAllocator(),
        1,
    );
    values.append(TrackedOwner(7));
    assert(values.tryAppend(&values[0]));
    assert(values.length == 2);
    assert(!values[0].active);
    assert(values[1].active && values[1].value == 7);
    assert(trackedDeinits == 0);
    values.deinit();
    assert(trackedDeinits == 1 && deinitOrder[0] == 7);

    // The same alias rule applies to fallible insertion. If the source lies at
    // or after the insertion point it follows the shift before being consumed.
    trackedDeinits = 0;
    OwnedArray!TrackedOwner inserted = OwnedArray!TrackedOwner.withCapacity(
        mallocAllocator(),
        2,
    );
    inserted.append(TrackedOwner(1));
    inserted.append(TrackedOwner(2));
    assert(inserted.tryInsert(0, &inserted[1]));
    assert(inserted.length == 3);
    assert(inserted[0].active && inserted[0].value == 2);
    assert(inserted[1].active && inserted[1].value == 1);
    assert(!inserted[2].active);
    inserted.deinit();
    assert(trackedDeinits == 2);
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

    size_t deinits;
    CopyableOwner[2] source = [
        CopyableOwner(7, &deinits),
        CopyableOwner(8, &deinits),
    ];
    OwnedArray!CopyableOwner values = OwnedArray!CopyableOwner.fromSlice(
        mallocAllocator(),
        source[],
    );
    values.append(source[]);
    values.shrinkToFit();
    values.append(values.slice[0 .. 2]);
    values.removeRange(1, 2);
    assert(deinits == 2);
    values.deinit();
    assert(deinits == 6);
    foreach_reverse (ref value; source)
        deinitValue(value);
    assert(deinits == 8);

    AllocationRecord[16] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    Array!int releasedSource = Array!int.fromSlice(
        tracked.allocator,
        [1, 2, 3],
    );
    Array!int.Released released = releasedSource.release();
    assert(releasedSource.allocator is null && releasedSource.empty);
    assert(released.allocator is tracked.allocator);
    appendReleasedValue(released.storage, released.allocator, 4);
    assert(released.storage.slice == [1, 2, 3, 4]);
    deinitValue(released);
    assert(tracked.clean && tracked.stats.invalidCalls == 0);
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

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

    Array!int managed = Array!int.create(managedAllocator.allocator);
    ArrayUnmanaged!int unmanaged;
    foreach (value; 0 .. 96)
    {
        int managedValue = value;
        int unmanagedValue = value;
        assert(managed.tryAppend(&managedValue));
        assert(unmanaged.tryAppend(unmanagedAllocator.allocator, &unmanagedValue));
    }

    int[4] inserted = [700, 701, 702, 703];
    assert(managed.tryInsert(17, inserted[]));
    assert(unmanaged.tryInsert(
            unmanagedAllocator.allocator,
            17,
            inserted[],
    ));
    managed.removeRange(9, 11);
    unmanaged.removeRange(9, 11);
    assert(managed.tryReserve(256));
    assert(unmanaged.tryReserve(unmanagedAllocator.allocator, 256));
    assert(managed.tryShrinkToFit());
    assert(unmanaged.tryShrinkToFit(unmanagedAllocator.allocator));

    assert(managed.slice == unmanaged.slice);
    assert(managed.length == unmanaged.length);
    assert(managed.capacity == unmanaged.capacity);
    assert(managedAllocator.stats == unmanagedAllocator.stats);

    managed.clear();
    unmanaged.clear();
    managed.deinit();
    unmanaged.deinit(unmanagedAllocator.allocator);
    assert(managedAllocator.stats == unmanagedAllocator.stats);
    assert(managedAllocator.clean && unmanagedAllocator.clean);
}
