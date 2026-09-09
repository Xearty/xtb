module xtb.containers.array;

nothrow @nogc:

import core.attribute;
import core_lifetime = core.lifetime;
import core.stdc.string;

import xtb.containers.released_storage;
import xtb.lifetime;
import xtb.memory;
import xtb.numeric;
import xtb.panic;
import xtb.types;

private template supports_default_initialization(T)
{
    enum supports_default_initialization = __traits(compiles, ()
    {
        T value;
    });
}

/// Raw backing allocation detached from an unmanaged array.
///
/// This package-only token owns only the allocation, not logical element
/// cleanup. It is move-only and requires the originating allocator for
/// explicit deinitialization. Callers that transfer the storage onward must
/// consume the token exactly once. Its representation satisfies
/// `length <= capacity`, and `data is null` exactly when `capacity == 0`.
@mustuse package(xtb) struct RawArrayStorage(T)
{
    alias Self = RawArrayStorage!T;

    T* data;
    usize length;
    usize capacity;

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    package(xtb) static Self adopt(T* data, usize length, usize capacity) @system
    {
        require(length <= capacity, "adopted raw array length exceeds capacity");
        require(
            (capacity == 0) == (data is null),
            "adopted raw array storage does not match capacity",
        );
        Self result;
        result.data = data;
        result.length = length;
        result.capacity = capacity;
        return result;
    }

    /// Releases only the backing allocation; logical elements are not finalized.
    ///
    /// When `capacity` is nonzero, `allocator` must point to the allocator that
    /// owns `data`. A null allocator is accepted only when `capacity == 0`.
    void deinit(Allocator* allocator)
    {
        if (this.capacity == 0) return;

        require_valid_allocator(allocator);
        allocator.deallocate_array(this.data[0 .. this.capacity]);
    }
}

/// Growable backing-allocation owner without embedded allocator context.
///
/// Every operation that may allocate or release storage requires the allocator
/// explicitly. Copying and generated assignment are disabled; use XTB move
/// construction for transfer and explicitly deinitialize a live value with the
/// same allocator context that owns its backing allocation. The public
/// representation must satisfy `length <= capacity` and `data is null` exactly
/// when `capacity == 0`. Except when releasing an empty value, every allocator
/// argument must point to a valid allocator.
@mustuse struct ArrayUnmanaged(T)
{
    alias Self = ArrayUnmanaged!T;

    T* data;
    usize length;
    usize capacity;

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Attempts to create an empty array with at least `capacity` elements.
    ///
    /// `output` must point to `ArrayUnmanaged.init`. On allocation failure, it
    /// remains `ArrayUnmanaged.init`.
    static bool try_with_capacity(
        Allocator* allocator,
        usize capacity,
        scope ArrayUnmanaged* output,
    ) @system
    {
        require(output !is null, "ArrayUnmanaged output pointer is null");
        const output_is_inert = output is null
            || (output.data is null && output.length == 0 && output.capacity == 0);
        require(output_is_inert, "ArrayUnmanaged output is not inert");
        require_valid_allocator(allocator);
        ArrayUnmanaged temporary;
        if (capacity != 0 && !temporary.try_reserve(allocator, capacity)) return false;

        move_emplace(temporary, *output);
        return true;
    }

    static ArrayUnmanaged with_capacity(Allocator* allocator, usize capacity)
    {
        ArrayUnmanaged result;
        if (!ArrayUnmanaged.try_with_capacity(allocator, capacity, &result))
            panic("Array allocation failed");

        return result;
    }

    static if (supports_default_initialization!T)
    {
        static ArrayUnmanaged with_length(Allocator* allocator, usize length)
        {
            ArrayUnmanaged result;
            result.resize(allocator, length);
            return result;
        }
    }

    static if (__traits(isCopyable, T))
    {
        static ArrayUnmanaged from_slice(Allocator* allocator, scope const(T)[] values)
        {
            auto result = ArrayUnmanaged.with_capacity(allocator, values.length);
            result.append(allocator, values);
            return result;
        }
    }

    package(xtb) static ArrayUnmanaged adopt(T* data, usize length, usize capacity) @system
    {
        require(length <= capacity, "adopted ArrayUnmanaged length exceeds capacity");
        require(
            (capacity == 0) == (data is null),
            "adopted ArrayUnmanaged storage does not match capacity",
        );
        ArrayUnmanaged result;
        result.data = data;
        result.length = length;
        result.capacity = capacity;
        return result;
    }

    /// Transfers backing storage out and leaves this unmanaged array empty.
    package(xtb) RawArrayStorage!T release_raw() @system
    {
        auto result = RawArrayStorage!T.adopt(this.data, this.length, this.capacity);
        this.data = null;
        this.length = 0;
        this.capacity = 0;
        return result;
    }

    /// Releases backing storage without finalizing logical elements.
    ///
    /// A null `allocator` is accepted only when `capacity == 0`.
    void deinit(Allocator* allocator)
    {
        if (this.capacity == 0) return;

        require_valid_allocator(allocator);
        allocator.deallocate_array(this.data[0 .. this.capacity]);
    }

    /// Releases backing storage and leaves this unmanaged array reusable.
    ///
    /// A null `allocator` is accepted only when `capacity == 0`.
    void reset_and_release(Allocator* allocator)
    {
        if (this.capacity != 0)
        {
            require_valid_allocator(allocator);
            allocator.deallocate_array(this.data[0 .. this.capacity]);
        }

        this.data = null;
        this.length = 0;
        this.capacity = 0;
    }

    bool empty() const pure @safe
    {
        return this.length == 0;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.sequence(this);
    }

    /// Returns a slice borrowed from this array until backing storage is
    /// reallocated or released.
    inout(T)[] slice() inout return pure @system
    {
        return this.data[0 .. this.length];
    }

    /// Returns a reference borrowed from this array until backing storage is
    /// reallocated or released.
    ref inout(T) opIndex(usize index) inout return @system
    {
        require(index < this.length, "Array index out of bounds");
        return this.data[index];
    }

    bool try_reserve(Allocator* allocator, usize requested)
    {
        require_valid_allocator(allocator);
        if (requested <= this.capacity) return true;

        usize capacity = this.capacity == 0 ? 8 : this.capacity;
        while (capacity < requested)
        {
            if (capacity > usize.max / 2)
            {
                capacity = requested;
                break;
            }
            capacity *= 2;
        }
        return this.try_set_capacity(allocator, capacity);
    }

    void reserve(Allocator* allocator, usize requested)
    {
        if (!this.try_reserve(allocator, requested)) panic("Array allocation failed");
    }

    static if (supports_default_initialization!T)
    {
        bool try_resize(Allocator* allocator, usize requested)
        {
            require_valid_allocator(allocator);
            if (requested < this.length)
            {
                this.length = requested;
                return true;
            }
            if (!this.try_reserve(allocator, requested)) return false;

            while (this.length < requested)
            {
                construct_initial(this.data + this.length);
                ++this.length;
            }
            return true;
        }

        void resize(Allocator* allocator, usize requested)
        {
            if (!this.try_resize(allocator, requested)) panic("Array allocation failed");
        }
    }

    /// Attempts to append by moving from `*value` only after capacity succeeds.
    /// `value` must not be null. On failure `*value` and the array are unchanged.
    bool try_append(Allocator* allocator, scope T* value) @system
    {
        require_valid_allocator(allocator);
        require(value !is null, "Array append value pointer is null");
        if (this.length == usize.max) return false;

        usize source_index;
        const aliases = this.logical_element_index(value, source_index);
        if (!this.try_reserve(allocator, this.length + 1)) return false;

        T* source = aliases ? this.data + source_index : value;
        construct_move(this.data + this.length, *source);
        ++this.length;
        return true;
    }

    void append(Allocator* allocator, T value)
    {
        if (!this.try_append(allocator, &value)) panic("Array allocation failed");
    }

    void append_assume_capacity(T value)
    {
        require(this.length < this.capacity, "Array capacity exceeded");
        construct_move(this.data + this.length, value);
        ++this.length;
    }

    static if (__traits(isCopyable, T))
    {
        bool try_append(Allocator* allocator, scope const(T)[] values)
        {
            require_valid_allocator(allocator);
            if (values.length > usize.max - this.length) return false;

            bool aliases_array;
            usize source_offset;
            if (values.length != 0 && this.data !is null)
            {
                const source_address = cast(usize) values.ptr;
                const begin_address = cast(usize) this.data;
                const end_address = begin_address + this.length * T.sizeof;
                aliases_array = source_address >= begin_address
                    && source_address < end_address;
                if (aliases_array)
                {
                    const byte_offset = source_address - begin_address;
                    const invalid_offset = byte_offset % T.sizeof != 0;
                    const exceeds_array = values.length
                        > this.length - byte_offset / T.sizeof;
                    if (invalid_offset || exceeds_array) return false;
                    source_offset = byte_offset / T.sizeof;
                }
            }

            const old_length = this.length;
            const new_length = old_length + values.length;
            if (!this.try_reserve(allocator, new_length)) return false;

            const(T)* source = aliases_array ? this.data + source_offset : values.ptr;
            static if (__traits(isPOD, T))
            {
                if (values.length != 0)
                {
                    memmove(this.data + this.length, source, values.length * T.sizeof);
                }
                this.length = new_length;
            }
            else
            {
                while (this.length < new_length)
                {
                    construct_copy(
                        this.data + this.length,
                        source[this.length - old_length],
                    );
                    ++this.length;
                }
            }
            return true;
        }

        void append(Allocator* allocator, scope const(T)[] values)
        {
            if (!this.try_append(allocator, values)) panic("Array allocation failed");
        }

        void append_assume_capacity(scope const(T)[] values)
        {
            require(
                values.length <= this.capacity - this.length,
                "Array capacity exceeded",
            );
            static if (__traits(isPOD, T))
            {
                if (values.length != 0)
                {
                    memmove(this.data + this.length, values.ptr, values.length * T.sizeof);
                }
                this.length += values.length;
            }
            else
            {
                foreach (const ref value; values)
                {
                    construct_copy(this.data + this.length, value);
                    ++this.length;
                }
            }
        }
    }

    /// Attempts to insert by moving from `*value` only after capacity succeeds.
    /// `value` must not be null. On failure `*value` and the array are unchanged.
    bool try_insert(Allocator* allocator, usize index, scope T* value) @system
    {
        require_valid_allocator(allocator);
        require(index <= this.length, "Array insert index out of bounds");
        require(value !is null, "Array insert value pointer is null");
        if (this.length == usize.max) return false;

        usize source_index;
        const aliases = this.logical_element_index(value, source_index);
        if (!this.try_reserve(allocator, this.length + 1)) return false;

        static if (__traits(isPOD, T))
        {
            const following = this.length - index;
            if (following != 0)
            {
                memmove(this.data + index + 1, this.data + index, following * T.sizeof);
            }
        }
        else
        {
            usize position = this.length;
            while (position > index)
            {
                construct_move(this.data + position, this.data[position - 1]);
                --position;
            }
        }
        T* source = value;
        if (aliases)
        {
            const adjusted_source_index = source_index >= index ? source_index + 1 : source_index;
            source = this.data + adjusted_source_index;
        }
        construct_move(this.data + index, *source);
        ++this.length;
        return true;
    }

    static if (__traits(isCopyable, T))
    {
        bool try_insert(Allocator* allocator, usize index, scope const(T)[] values)
        {
            require_valid_allocator(allocator);
            require(index <= this.length, "Array insert index out of bounds");
            if (values.length > usize.max - this.length) return false;
            if (values.length == 0) return true;

            bool aliases_array;
            usize source_offset;
            if (this.data !is null)
            {
                const source_address = cast(usize) values.ptr;
                const begin_address = cast(usize) this.data;
                const end_address = begin_address + this.length * T.sizeof;
                aliases_array = source_address >= begin_address
                    && source_address < end_address;
                if (aliases_array)
                {
                    const byte_offset = source_address - begin_address;
                    const invalid_offset = byte_offset % T.sizeof != 0;
                    const exceeds_array = values.length
                        > this.length - byte_offset / T.sizeof;
                    if (invalid_offset || exceeds_array) return false;
                    source_offset = byte_offset / T.sizeof;
                    static if (!__traits(isPOD, T)) return false;
                }
            }

            const old_length = this.length;
            const new_length = old_length + values.length;
            if (!this.try_reserve(allocator, new_length)) return false;
            static if (__traits(isPOD, T))
            {
                const following = old_length - index;
                if (following != 0)
                {
                    memmove(
                        this.data + index + values.length,
                        this.data + index,
                        following * T.sizeof,
                    );
                }
                if (aliases_array)
                {
                    const source_end = source_offset + values.length;
                    const left_end = source_end < index ? source_end : index;
                    const left_count = source_offset < index
                        ? left_end - source_offset
                        : 0;
                    const right_count = values.length - left_count;
                    if (left_count != 0)
                    {
                        memmove(
                            this.data + index,
                            this.data + source_offset,
                            left_count * T.sizeof,
                        );
                    }
                    if (right_count != 0)
                    {
                        const right_source = source_offset + left_count
                            + values.length;
                        memmove(
                            this.data + index + left_count,
                            this.data + right_source,
                            right_count * T.sizeof,
                        );
                    }
                }
                else
                {
                    memmove(this.data + index, values.ptr, values.length * T.sizeof);
                }
            }
            else
            {
                usize position = old_length;
                while (position > index)
                {
                    --position;
                    construct_move(
                        this.data + position + values.length,
                        this.data[position],
                    );
                }
                foreach (offset, const ref value; values)
                    construct_copy(this.data + index + offset, value);
            }
            this.length = new_length;
            return true;
        }
    }

    void insert(Allocator* allocator, usize index, T value)
    {
        if (!this.try_insert(allocator, index, &value)) panic("Array allocation failed");
    }

    static if (__traits(isCopyable, T))
    {
        void insert(Allocator* allocator, usize index, scope const(T)[] values)
        {
            if (!this.try_insert(allocator, index, values)) panic("Array allocation failed");
        }
    }

    /// Removes and returns the last element by move.
    T pop()
    {
        require(this.length != 0, "cannot pop an empty Array");
        --this.length;
        T result = void;
        static if (__traits(isPOD, T))
        {
            result = this.data[this.length];
        }
        else
        {
            construct_move(&result, this.data[this.length]);
        }
        return result;
    }

    /// Discards logical elements without finalizing them.
    void clear()
    {
        this.length = 0;
    }

    void remove_at(usize index)
    {
        require(index < this.length, "Array index out of bounds");
        static if (__traits(isPOD, T))
        {
            const following = this.length - index - 1;
            if (following != 0)
            {
                memmove(this.data + index, this.data + index + 1, following * T.sizeof);
            }
        }
        else
        {
            for (usize i = index; i < this.length - 1; ++i)
                construct_move(this.data + i, this.data[i + 1]);
        }
        --this.length;
    }

    void remove_range(usize index, usize count)
    {
        require(index <= this.length, "Array range index out of bounds");
        require(count <= this.length - index, "Array range count out of bounds");
        if (count == 0) return;
        static if (__traits(isPOD, T))
        {
            const following = this.length - index - count;
            if (following != 0)
            {
                memmove(this.data + index, this.data + index + count, following * T.sizeof);
            }
        }
        else
        {
            for (usize i = index; i < this.length - count; ++i)
                construct_move(this.data + i, this.data[i + count]);
        }
        this.length -= count;
    }

    bool try_shrink_to_fit(Allocator* allocator)
    {
        require_valid_allocator(allocator);
        if (this.length == this.capacity) return true;
        if (this.length == 0)
        {
            this.reset_and_release(allocator);
            return true;
        }
        return this.try_set_capacity(allocator, this.length);
    }

    void shrink_to_fit(Allocator* allocator)
    {
        if (!this.try_shrink_to_fit(allocator)) panic("Array allocation failed");
    }

    private bool logical_element_index(scope const T* value, scope ref usize index) const @system
    {
        if (value is null || this.data is null || this.length == 0) return false;
        const address = cast(usize) value;
        const begin = cast(usize) this.data;
        const end = begin + this.length * T.sizeof;
        if (address < begin || address >= end) return false;
        const byte_offset = address - begin;
        if (byte_offset % T.sizeof != 0) return false;
        index = byte_offset / T.sizeof;
        return true;
    }

    private bool try_set_capacity(Allocator* allocator, usize capacity)
    {
        if (multiply_overflows(capacity, T.sizeof)) return false;

        static if (__traits(isPOD, T))
        {
            T[] replacement = allocator.try_reallocate_array(
                this.data[0 .. this.capacity],
                capacity,
            );
            if (capacity != 0 && replacement.ptr is null) return false;
            this.data = replacement.ptr;
        }
        else
        {
            T* replacement = allocator.try_allocate_array!T(capacity).ptr;
            if (capacity != 0 && replacement is null) return false;
            for (usize i; i < this.length; ++i)
                construct_move(replacement + i, this.data[i]);
            allocator.deallocate_array(this.data[0 .. this.capacity]);
            this.data = replacement;
        }
        this.capacity = capacity;
        return true;
    }
}

/// Managed shallow array.
///
/// `Array` owns only its backing allocation. Discard operations never finalize
/// logical elements; use `OwnedArray` when the container must own element
/// cleanup. Allocator arguments to constructors must point to a valid allocator.
@mustuse struct Array(T)
{
    alias Self = Array!T;
    alias Storage = ArrayUnmanaged!T;
    alias Released = ReleasedStorage!Storage;

    /// Allocator that owns `storage`; null only for an inert or released value.
    Allocator* allocator;
    /// Backing allocation owned through `allocator` while this value is live.
    Storage storage;

    invariant
    {
        require(&this !is null, "Array pointer is null");
    }

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    /// Creates an empty managed array bound to `allocator`.
    static Self create(Allocator* allocator) @safe
    {
        require_valid_allocator(allocator);
        Self result;
        result.allocator = allocator;
        return result;
    }

    /// Attempts to create an empty managed array with at least `capacity` elements.
    ///
    /// `output` must point to `Array.init`. On allocation failure, it remains
    /// `Array.init`.
    static bool try_with_capacity(Allocator* allocator, usize capacity, scope Self* output) @system
    {
        require(output !is null, "Array output pointer is null");
        const output_is_inert = output is null
            || (output.allocator is null
                && output.storage.data is null
                && output.storage.length == 0
                && output.storage.capacity == 0);
        require(output_is_inert, "Array output is not inert");
        Storage storage;
        if (!Storage.try_with_capacity(allocator, capacity, &storage)) return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    /// Creates an empty managed array with at least `capacity` elements.
    static Self with_capacity(Allocator* allocator, usize capacity) @trusted
    {
        Self result;
        if (!Self.try_with_capacity(allocator, capacity, &result))
            panic("Array allocation failed");

        return move(result);
    }

    static if (supports_default_initialization!T)
    {
        /// Creates a managed array containing `length` default-initialized values.
        static Self with_length(Allocator* allocator, usize length) @trusted
        {
            auto storage = Storage.with_length(allocator, length);
            Self result;
            result.allocator = allocator;
            move_emplace(storage, result.storage);
            return move(result);
        }
    }

    static if (__traits(isCopyable, T))
    {
        /// Copies `values` into a newly allocated managed array.
        static Self from_slice(Allocator* allocator, scope const(T)[] values) @trusted
        {
            auto storage = Storage.from_slice(allocator, values);
            Self result;
            result.allocator = allocator;
            move_emplace(storage, result.storage);
            return move(result);
        }
    }

    /// Adopts storage previously returned by `release`.
    ///
    /// `released` must be non-null and is consumed by this operation.
    static Self adopt(scope Released* released) @system
    {
        require(released !is null, "released Array storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator = allocator;
        move_emplace(storage, result.storage);
        return move(result);
    }

    /// Releases all storage and unbinds the allocator. The zero state is valid.
    void deinit() @trusted
    {
        if (this.allocator is null) return;
        this.storage.deinit(this.allocator);
        this.allocator = null;
    }

    /// Releases allocated storage but keeps the allocator binding.
    void reset_and_release() @trusted
    {
        this.storage.reset_and_release(this.allocator);
    }

    /// Transfers allocator-bound storage out and leaves this array empty.
    Released release() @trusted
    {
        auto result = Released.from_owned_parts(this.allocator, &this.storage);
        this.allocator = null;
        return move(result);
    }

    usize length() const pure @safe
    {
        return this.storage.length;
    }

    usize capacity() const pure @safe
    {
        return this.storage.capacity;
    }

    bool empty() const pure @safe
    {
        return this.storage.empty;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.sequence(this);
    }

    /// Returns a slice borrowed from this array until backing storage is
    /// reallocated or released.
    inout(T)[] slice() inout return @system
    {
        return this.storage.slice;
    }

    bool try_reserve(usize requested) @trusted
    {
        return this.storage.try_reserve(this.allocator, requested);
    }

    void reserve(usize requested) @trusted
    {
        this.storage.reserve(this.allocator, requested);
    }

    static if (supports_default_initialization!T)
    {
        bool try_resize(usize requested) @trusted
        {
            return this.storage.try_resize(this.allocator, requested);
        }

        void resize(usize requested) @trusted
        {
            this.storage.resize(this.allocator, requested);
        }
    }

    /// `value` must not be null. On failure `*value` and this array are unchanged.
    bool try_append(scope T* value) @system
    {
        return this.storage.try_append(this.allocator, value);
    }

    void append(T value) @trusted
    {
        this.storage.append(this.allocator, move(value));
    }

    void append_assume_capacity(T value) @trusted
    {
        this.storage.append_assume_capacity(move(value));
    }

    static if (__traits(isCopyable, T))
    {
        bool try_append(scope const(T)[] values) @trusted
        {
            return this.storage.try_append(this.allocator, values);
        }

        void append(scope const(T)[] values) @trusted
        {
            this.storage.append(this.allocator, values);
        }

        void append_assume_capacity(scope const(T)[] values) @trusted
        {
            this.storage.append_assume_capacity(values);
        }
    }

    /// `value` must not be null. On failure `*value` and this array are unchanged.
    bool try_insert(usize index, scope T* value) @system
    {
        return this.storage.try_insert(this.allocator, index, value);
    }

    void insert(usize index, T value) @trusted
    {
        this.storage.insert(this.allocator, index, move(value));
    }

    static if (__traits(isCopyable, T))
    {
        bool try_insert(usize index, scope const(T)[] values) @trusted
        {
            return this.storage.try_insert(this.allocator, index, values);
        }

        void insert(usize index, scope const(T)[] values) @trusted
        {
            this.storage.insert(this.allocator, index, values);
        }
    }

    /// Removes and returns the last element by move.
    T pop() @trusted
    {
        return this.storage.pop();
    }

    void clear() @trusted
    {
        this.storage.clear();
    }

    void remove_at(usize index) @trusted
    {
        this.storage.remove_at(index);
    }

    void remove_range(usize index, usize count) @trusted
    {
        this.storage.remove_range(index, count);
    }

    bool try_shrink_to_fit() @trusted
    {
        return this.storage.try_shrink_to_fit(this.allocator);
    }

    void shrink_to_fit() @trusted
    {
        this.storage.shrink_to_fit(this.allocator);
    }

    /// Returns a reference borrowed from this array until backing storage is
    /// reallocated or released.
    ref inout(T) opIndex(usize index) inout return @system
    {
        return this.storage[index];
    }

    /// Consumes `*storage` and binds it to `allocator`.
    package(xtb.containers) static Self adopt_unmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        require_valid_allocator(allocator);
        require(storage !is null, "ArrayUnmanaged pointer is null");
        Self result;
        result.allocator = allocator;
        move_emplace(*storage, result.storage);
        return move(result);
    }

    package(xtb.containers) static Self adopt_raw(
        Allocator* allocator,
        T* data,
        usize length,
        usize capacity,
    ) @system
    {
        auto storage = Storage.adopt(data, length, capacity);
        return Self.adopt_unmanaged(allocator, &storage);
    }
}

/// Managed contiguous storage with ownership of logical element cleanup.
///
/// `OwnedArray` owns both its backing allocation and every live element. Any
/// operation that discards an element without returning it finalizes that
/// element. Explicit-deinit values use free `deinit`; destructor-only values
/// use D destruction. Transfers such as `pop` do not finalize the returned
/// value. Allocator arguments to constructors must point to a valid allocator.
@mustuse struct OwnedArray(T)
{
    alias Self = OwnedArray!T;
    alias Storage = ArrayUnmanaged!T;

    /// Allocator that owns `storage`; null only while this value is inert.
    Allocator* allocator;
    /// Backing allocation and live elements owned through `allocator`.
    Storage storage;

    invariant
    {
        require(&this !is null, "OwnedArray pointer is null");
    }

    private void deinit_range(usize index, usize count) @trusted
    {
        static if (needs_finalization!T)
        {
            foreach_reverse (ref value; this.storage.slice[index .. index + count])
                finalize(value);
        }
    }

    static assert(
        can_finalize_without_context!T,
        "OwnedArray elements must support context-free finalization",
    );

    @disable this(this);
    @disable ref Self opAssign(Self source) return;

    static Self create(Allocator* allocator) @safe
    {
        require_valid_allocator(allocator);
        Self result;
        result.allocator = allocator;
        return result;
    }

    /// Attempts to create an empty owned array with at least `capacity` elements.
    ///
    /// `output` must point to `OwnedArray.init`. On allocation failure, it
    /// remains `OwnedArray.init`.
    static bool try_with_capacity(Allocator* allocator, usize capacity, scope Self* output) @system
    {
        require(output !is null, "OwnedArray output pointer is null");
        const output_is_inert = output is null
            || (output.allocator is null
                && output.storage.data is null
                && output.storage.length == 0
                && output.storage.capacity == 0);
        require(output_is_inert, "OwnedArray output is not inert");
        Storage storage;
        if (!Storage.try_with_capacity(allocator, capacity, &storage)) return false;
        output.allocator = allocator;
        move_emplace(storage, output.storage);
        return true;
    }

    static Self with_capacity(Allocator* allocator, usize capacity) @trusted
    {
        Self result;
        if (!Self.try_with_capacity(allocator, capacity, &result))
            panic("OwnedArray allocation failed");

        return move(result);
    }

    static if (supports_default_initialization!T)
    {
        static Self with_length(Allocator* allocator, usize length) @trusted
        {
            auto storage = Storage.with_length(allocator, length);
            Self result;
            result.allocator = allocator;
            move_emplace(storage, result.storage);
            return move(result);
        }
    }

    static if (__traits(isCopyable, T))
    {
        static Self from_slice(Allocator* allocator, scope const(T)[] values) @trusted
        {
            auto storage = Storage.from_slice(allocator, values);
            Self result;
            result.allocator = allocator;
            move_emplace(storage, result.storage);
            return move(result);
        }
    }

    /// Finalizes every live element and releases backing storage.
    void deinit() @trusted
    {
        if (this.allocator is null) return;
        this.deinit_range(0, this.storage.length);
        this.storage.deinit(this.allocator);
        this.allocator = null;
    }

    /// Finalizes every element, releases storage, and keeps the allocator.
    void reset_and_release() @trusted
    {
        this.deinit_range(0, this.storage.length);
        this.storage.reset_and_release(this.allocator);
    }

    usize length() const pure @safe
    {
        return this.storage.length;
    }

    usize capacity() const pure @safe
    {
        return this.storage.capacity;
    }

    bool empty() const pure @safe
    {
        return this.storage.empty;
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        pretty.sequence(this);
    }

    /// Returns a slice borrowed from this array until backing storage is
    /// reallocated or released.
    inout(T)[] slice() inout return @system
    {
        return this.storage.slice;
    }

    bool try_reserve(usize requested) @trusted
    {
        return this.storage.try_reserve(this.allocator, requested);
    }

    void reserve(usize requested) @trusted
    {
        this.storage.reserve(this.allocator, requested);
    }

    static if (supports_default_initialization!T)
    {
        bool try_resize(usize requested) @trusted
        {
            if (requested < this.storage.length)
            {
                require_valid_allocator(this.allocator);
                this.deinit_range(requested, this.storage.length - requested);
            }
            return this.storage.try_resize(this.allocator, requested);
        }

        void resize(usize requested) @trusted
        {
            if (!this.try_resize(requested)) panic("OwnedArray allocation failed");
        }
    }

    /// `value` must not be null. On failure `*value` and this array are unchanged.
    bool try_append(scope T* value) @system
    {
        return this.storage.try_append(this.allocator, value);
    }

    void append(T value) @trusted
    {
        this.storage.append(this.allocator, move(value));
    }

    void append_assume_capacity(T value) @trusted
    {
        this.storage.append_assume_capacity(move(value));
    }

    static if (__traits(isCopyable, T))
    {
        bool try_append(scope const(T)[] values) @trusted
        {
            return this.storage.try_append(this.allocator, values);
        }

        void append(scope const(T)[] values) @trusted
        {
            this.storage.append(this.allocator, values);
        }

        void append_assume_capacity(scope const(T)[] values) @trusted
        {
            this.storage.append_assume_capacity(values);
        }
    }

    /// `value` must not be null. On failure `*value` and this array are unchanged.
    bool try_insert(usize index, scope T* value) @system
    {
        return this.storage.try_insert(this.allocator, index, value);
    }

    void insert(usize index, T value) @trusted
    {
        this.storage.insert(this.allocator, index, move(value));
    }

    static if (__traits(isCopyable, T))
    {
        bool try_insert(usize index, scope const(T)[] values) @trusted
        {
            return this.storage.try_insert(this.allocator, index, values);
        }

        void insert(usize index, scope const(T)[] values) @trusted
        {
            this.storage.insert(this.allocator, index, values);
        }
    }

    /// Removes and transfers ownership of the last element.
    T pop() @trusted
    {
        return this.storage.pop();
    }

    void clear() @trusted
    {
        this.deinit_range(0, this.storage.length);
        this.storage.clear();
    }

    void remove_at(usize index) @trusted
    {
        require(index < this.storage.length, "OwnedArray index out of bounds");
        this.deinit_range(index, 1);
        this.storage.remove_at(index);
    }

    void remove_range(usize index, usize count) @trusted
    {
        require(index <= this.storage.length, "OwnedArray range index out of bounds");
        require(
            count <= this.storage.length - index,
            "OwnedArray range count out of bounds",
        );
        this.deinit_range(index, count);
        this.storage.remove_range(index, count);
    }

    bool try_shrink_to_fit() @trusted
    {
        return this.storage.try_shrink_to_fit(this.allocator);
    }

    void shrink_to_fit() @trusted
    {
        this.storage.shrink_to_fit(this.allocator);
    }

    /// Returns a reference borrowed from this array until backing storage is
    /// reallocated or released.
    ref inout(T) opIndex(usize index) inout return @system
    {
        return this.storage[index];
    }
}

private void require_valid_allocator(Allocator* allocator) @trusted
{
    require(allocator !is null && *allocator !is null, "Array requires a valid allocator");
}

private void construct_initial(T)(T* destination)
{
    static if (__traits(isPOD, T))
    {
        *destination = T.init;
    }
    else
    {
        core_lifetime.emplace(destination);
    }
}

private void construct_move(T)(T* destination, scope ref T source)
{
    // Pointer-based move APIs promise that the source enters its normal
    // moved-from state. An explicit-deinit POD value may still own resources,
    // so a raw assignment would duplicate ownership and leave the source live.
    static if (__traits(isPOD, T) && !needs_deinit!T)
    {
        *destination = source;
    }
    else
    {
        move_emplace(source, *destination);
    }
}

private void construct_copy(T, U)(T* destination, scope const ref U source)
{
    static if (__traits(isPOD, T))
    {
        *destination = source;
    }
    else
    {
        core_lifetime.emplace(destination, source);
    }
}

version (unittest)
{
    import core.internal.traits;

    import xtb.allocators.instrumented;
    import xtb.allocators.malloc;
    import xtb.string;

    private __gshared usize tracked_deinits;
    private __gshared i32[32] deinit_order;

    private struct TrackedOwner
    {
    nothrow @nogc:

        i32 value;
        bool active;

        @disable this(this);

        this(i32 value)
        {
            this.value = value;
            this.active = true;
        }

        void deinit()
        {
            if (!this.active) return;

            deinit_order[tracked_deinits++] = this.value;
            this.active = false;
        }
    }

    private struct CopyableOwner
    {
    nothrow @nogc:

        i32 value;
        bool active;
        usize* deinits;

        this(i32 value, usize* deinits)
        {
            this.value = value;
            this.deinits = deinits;
            this.active = true;
        }

        void deinit()
        {
            if (!this.active) return;

            this.active = false;
            ++*this.deinits;
        }
    }

    private struct DestructorOnly
    {
        usize* destructions;
        bool armed;

        @disable this(this);

        ~this() nothrow @nogc
        {
            if (this.armed)
            {
                ++*this.destructions;
                this.armed = false;
            }
        }
    }

    private void append_released_value(
        scope ref ArrayUnmanaged!i32 storage,
        Allocator* allocator,
        i32 value,
    )
    {
        storage.append(allocator, value);
    }
}

unittest
{
    static assert(ArrayUnmanaged!i32.sizeof == 3 * usize.sizeof);
    static assert(Array!i32.sizeof == ArrayUnmanaged!i32.sizeof + (Allocator*).sizeof);
    static assert(OwnedArray!i32.sizeof == Array!i32.sizeof);
    static assert(needs_deinit!(RawArrayStorage!i32));
    static assert(!__traits(isCopyable, RawArrayStorage!i32));
    static assert(!__traits(compiles, (ref RawArrayStorage!i32 value)
    {
        xtb.lifetime.deinit(value);
    }));
    static assert(__traits(compiles, (ref RawArrayStorage!i32 value, Allocator* allocator)
    {
        xtb.lifetime.deinit(value, allocator);
    }));
    static assert(!__traits(isCopyable, ArrayUnmanaged!i32));
    static assert(needs_deinit!(ArrayUnmanaged!i32));
    static assert(!__traits(compiles, (ref ArrayUnmanaged!i32 value)
    {
        xtb.lifetime.deinit(value);
    }));
    static assert(__traits(compiles, (ref ArrayUnmanaged!i32 value, Allocator* allocator)
    {
        xtb.lifetime.deinit(value, allocator);
    }));
    static assert(!__traits(compiles, ()
    {
        ArrayUnmanaged!i32 left;
        ArrayUnmanaged!i32 right;
        left = move(right);
    }));
    static assert(!__traits(isCopyable, Array!i32));
    static assert(!__traits(isCopyable, OwnedArray!i32));
    static assert(!__traits(isCopyable, Array!i32.Released));
    static assert(!__traits(compiles, ()
    {
        Array!i32 left;
        Array!i32 right;
        left = move(right);
    }));
    static assert(!__traits(compiles, ()
    {
        OwnedArray!i32 left;
        OwnedArray!i32 right;
        left = move(right);
    }));
    static assert(!__traits(compiles, ()
    {
        Array!i32.Released left;
        Array!i32.Released right;
        left = move(right);
    }));
    static assert(!hasElaborateDestructor!(Array!i32));
    static assert(!hasElaborateDestructor!(OwnedArray!i32));
    static assert(!hasElaborateDestructor!(Array!i32.Released));
    static assert(needs_deinit!(Array!i32));
    static assert(needs_deinit!(OwnedArray!i32));
    static assert(needs_deinit!(Array!i32.Released));
    static assert(can_finalize_without_context!DestructorOnly);
    static assert(__traits(compiles, ()
    {
        OwnedArray!DestructorOnly value;
    }));
    static assert(!__traits(compiles, ()
    {
        OwnedArray!(ArrayUnmanaged!i32) value;
    }));
    static assert(!__traits(hasMember, OwnedArray!i32, "release"));
    static assert(!__traits(hasMember, OwnedArray!i32, "adopt"));

    usize destructions;
    auto destructor_values = OwnedArray!DestructorOnly.create(malloc_allocator());
    auto discarded = DestructorOnly(&destructions, true);
    assert(destructor_values.try_append(&discarded));
    assert(!discarded.armed);
    destructor_values.remove_at(0);
    assert(destructions == 1);

    auto transferred_source = DestructorOnly(&destructions, true);
    assert(destructor_values.try_append(&transferred_source));
    DestructorOnly transferred_value = destructor_values.pop();
    assert(destructions == 1);
    finalize(transferred_value);
    assert(destructions == 2);
    destructor_values.deinit();

    AllocationRecord[8] raw_records;
    auto raw_allocator = InstrumentedAllocator.create(malloc_allocator(), raw_records[]);
    auto raw_source = ArrayUnmanaged!i32.from_slice(raw_allocator.allocator, [1, 2, 3]);
    RawArrayStorage!i32 raw = raw_source.release_raw();
    assert(raw_source.empty && raw_source.capacity == 0);
    RawArrayStorage!i32 moved_raw = move(raw);
    assert(raw.data is null && raw.length == 0 && raw.capacity == 0);
    assert(moved_raw.length == 3 && moved_raw.capacity >= 3);
    xtb.lifetime.deinit(moved_raw, raw_allocator.allocator);
    assert(raw_allocator.clean);

    Array!i32 zero;
    zero.deinit();
    zero.reset_and_release();

    auto values = Array!i32.with_capacity(malloc_allocator(), 1);
    values.append(1);
    i32[3] more = [2, 3, 4];
    values.append(more[]);
    values.append(values.slice[1 .. 3]);
    assert(values.slice == [1, 2, 3, 4, 2, 3]);
    values.remove_at(1);
    assert(values.slice == [1, 3, 4, 2, 3]);
    assert(values.pop() == 3);
    values.insert(1, 9);
    assert(values.slice == [1, 9, 3, 4, 2]);
    values.remove_range(1, 2);
    assert(values.slice == [1, 4, 2]);
    values.shrink_to_fit();
    assert(values.capacity == values.length);
    values.clear();
    assert(values.empty);
    values.reset_and_release();
    assert(values.capacity == 0);

    auto self_inserted = Array!i32.from_slice(malloc_allocator(), [1, 2, 3, 4, 5, 6, 7, 8]);
    self_inserted.insert(2, self_inserted.slice[1 .. 4]);
    assert(self_inserted.slice == [1, 2, 2, 3, 4, 3, 4, 5, 6, 7, 8]);
    self_inserted.deinit();

    AllocationRecord[8] records;
    auto tracked = InstrumentedAllocator.create(malloc_allocator(), records[]);
    auto fallible = Array!i32.with_capacity(tracked.allocator, 1);
    while (fallible.length < fallible.capacity)
        fallible.append_assume_capacity(42);

    i32 candidate = 7;
    const previous_length = fallible.length;
    tracked.fail_after(0);
    assert(!fallible.try_append(&candidate));
    assert(candidate == 7);
    assert(fallible.length == previous_length && fallible[0] == 42);
    tracked.allow_allocations();
    fallible.deinit();
    assert(tracked.clean && tracked.stats.invalid_calls == 0);
}

unittest
{
    tracked_deinits = 0;
    deinit_order[] = 0;

    // Array is shallow: discard paths do not deinitialize elements.
    auto shallow = Array!TrackedOwner.with_capacity(malloc_allocator(), 4);
    shallow.append(TrackedOwner(1));
    shallow.append(TrackedOwner(2));
    shallow.append(TrackedOwner(3));
    shallow.remove_at(1);
    assert(tracked_deinits == 0);
    shallow.resize(1);
    assert(tracked_deinits == 0);
    shallow.clear();
    assert(tracked_deinits == 0);
    shallow.deinit();
    assert(tracked_deinits == 0);

    // OwnedArray deep-cleans every discard path in reverse order where a range
    // is discarded.
    auto owned = OwnedArray!TrackedOwner.with_capacity(malloc_allocator(), 4);
    owned.append(TrackedOwner(10));
    owned.append(TrackedOwner(20));
    owned.append(TrackedOwner(30));
    owned.remove_at(1);
    assert(tracked_deinits == 1 && deinit_order[0] == 20);
    owned.append(TrackedOwner(40));
    owned.append(TrackedOwner(50));
    owned.remove_range(1, 2);
    assert(tracked_deinits == 3);
    assert(deinit_order[1] == 40);
    assert(deinit_order[2] == 30);
    owned.append(TrackedOwner(60));
    owned.append(TrackedOwner(70));
    owned.resize(1);
    assert(tracked_deinits == 6);
    assert(deinit_order[3] == 70);
    assert(deinit_order[4] == 60);
    assert(deinit_order[5] == 50);
    owned.clear();
    assert(tracked_deinits == 7 && deinit_order[6] == 10);
    owned.deinit();
    assert(tracked_deinits == 7);
}

unittest
{
    AllocationRecord[32] records;
    auto tracked = InstrumentedAllocator.create(malloc_allocator(), records[]);

    // pop transfers ownership and therefore does not deinitialize the payload.
    auto nested = OwnedArray!(Array!i32).create(tracked.allocator);
    auto first = Array!i32.create(tracked.allocator);
    first.append(11);
    nested.append(move(first));
    auto second = Array!i32.create(tracked.allocator);
    second.append(22);
    nested.append(move(second));
    assert(tracked.stats.outstanding_allocations == 3);

    Array!i32 transferred = nested.pop();
    assert(transferred[0] == 22);
    assert(tracked.stats.outstanding_allocations == 3);
    transferred.deinit();
    assert(tracked.stats.outstanding_allocations == 2);

    nested.clear();
    // Only the OwnedArray backing allocation remains after its child is
    // deep-cleaned.
    assert(tracked.stats.outstanding_allocations == 1);
    nested.deinit();
    assert(tracked.clean && tracked.stats.invalid_calls == 0);
}

unittest
{
    AllocationRecord[32] records;
    auto tracked = InstrumentedAllocator.create(malloc_allocator(), records[]);

    // Fallible pointer insertion preserves caller ownership on allocation
    // failure, including move-only explicit owners.
    auto values = Array!StringBuf.with_capacity(tracked.allocator, 1);
    auto first = StringBuf.from_string(tracked.allocator, "first");
    values.append(move(first));
    while (values.length < values.capacity)
    {
        auto filler = StringBuf.from_string(tracked.allocator, "filler");
        values.append_assume_capacity(move(filler));
    }
    auto candidate = StringBuf.from_string(tracked.allocator, "candidate");
    const old_length = values.length;
    tracked.fail_after(0);
    assert(!values.try_append(&candidate));
    assert(candidate.view == "candidate");
    assert(values.length == old_length);
    tracked.allow_allocations();

    // Array is shallow, so explicitly finalize its elements before releasing
    // the backing allocation in this test.
    foreach_reverse (ref value; values.slice)
        xtb.lifetime.deinit(value);

    values.clear();
    values.deinit();
    candidate.deinit();
    assert(tracked.clean && tracked.stats.invalid_calls == 0);
}

unittest
{
    // try_append supports pointers into the array even when reserve relocates
    // storage. The original slot becomes the normal moved-from value.
    tracked_deinits = 0;
    deinit_order[] = 0;
    auto values = OwnedArray!TrackedOwner.with_capacity(malloc_allocator(), 1);
    values.append(TrackedOwner(7));
    assert(values.try_append(&values[0]));
    assert(values.length == 2);
    assert(!values[0].active);
    assert(values[1].active && values[1].value == 7);
    assert(tracked_deinits == 0);
    values.deinit();
    assert(tracked_deinits == 1 && deinit_order[0] == 7);

    // The same alias rule applies to fallible insertion. If the source lies at
    // or after the insertion point it follows the shift before being consumed.
    tracked_deinits = 0;
    auto inserted = OwnedArray!TrackedOwner.with_capacity(malloc_allocator(), 2);
    inserted.append(TrackedOwner(1));
    inserted.append(TrackedOwner(2));
    assert(inserted.try_insert(0, &inserted[1]));
    assert(inserted.length == 3);
    assert(inserted[0].active && inserted[0].value == 2);
    assert(inserted[1].active && inserted[1].value == 1);
    assert(!inserted[2].active);
    inserted.deinit();
    assert(tracked_deinits == 2);
}

unittest
{
    usize deinits;
    CopyableOwner[2] source = [
        CopyableOwner(7, &deinits),
        CopyableOwner(8, &deinits),
    ];
    auto values = OwnedArray!CopyableOwner.from_slice(malloc_allocator(), source[]);
    values.append(source[]);
    values.shrink_to_fit();
    values.append(values.slice[0 .. 2]);
    values.remove_range(1, 2);
    assert(deinits == 2);
    values.deinit();
    assert(deinits == 6);
    foreach_reverse (ref value; source)
        xtb.lifetime.deinit(value);

    assert(deinits == 8);

    AllocationRecord[16] records;
    auto tracked = InstrumentedAllocator.create(malloc_allocator(), records[]);
    auto released_source = Array!i32.from_slice(tracked.allocator, [1, 2, 3]);
    Array!i32.Released released = released_source.release();
    assert(released_source.allocator is null && released_source.empty);
    assert(released.allocator is tracked.allocator);
    append_released_value(released.storage, released.allocator, 4);
    assert(released.storage.slice == [1, 2, 3, 4]);
    xtb.lifetime.deinit(released);
    assert(tracked.clean && tracked.stats.invalid_calls == 0);
}

unittest
{
    AllocationRecord[64] managed_records;
    AllocationRecord[64] unmanaged_records;
    auto managed_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        managed_records[],
    );
    auto unmanaged_allocator = InstrumentedAllocator.create(
        malloc_allocator(),
        unmanaged_records[],
    );

    auto managed = Array!i32.create(managed_allocator.allocator);
    ArrayUnmanaged!i32 unmanaged;
    foreach (value; 0 .. 96)
    {
        i32 managed_value = value;
        i32 unmanaged_value = value;
        assert(managed.try_append(&managed_value));
        assert(unmanaged.try_append(unmanaged_allocator.allocator, &unmanaged_value));
    }

    i32[4] inserted = [700, 701, 702, 703];
    assert(managed.try_insert(17, inserted[]));
    const unmanaged_inserted = unmanaged.try_insert(
        unmanaged_allocator.allocator,
        17,
        inserted[],
    );
    assert(unmanaged_inserted);
    managed.remove_range(9, 11);
    unmanaged.remove_range(9, 11);
    assert(managed.try_reserve(256));
    assert(unmanaged.try_reserve(unmanaged_allocator.allocator, 256));
    assert(managed.try_shrink_to_fit());
    assert(unmanaged.try_shrink_to_fit(unmanaged_allocator.allocator));

    assert(managed.slice == unmanaged.slice);
    assert(managed.length == unmanaged.length);
    assert(managed.capacity == unmanaged.capacity);
    assert(managed_allocator.stats == unmanaged_allocator.stats);

    managed.clear();
    unmanaged.clear();
    managed.deinit();
    unmanaged.deinit(unmanaged_allocator.allocator);
    assert(managed_allocator.stats == unmanaged_allocator.stats);
    assert(managed_allocator.clean && unmanaged_allocator.clean);
}
