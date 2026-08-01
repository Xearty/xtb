module xtb.serde.ownership;

nothrow @nogc:

import xtb.core.memory : Allocator, deallocate, tryAllocate;
import xtb.core.panic : require;
import xtb.core.types : String;
import xtb.serde.traits : FieldType, Unqualified, fieldHas, isDynamicArray,
    isFixedArray, isSerdeStruct, isString;
import xtb.serde.attributes : Ignore;

struct Deserialized(T)
{
nothrow @nogc:

    private Allocator* allocator_;
    private T* value_;

    @disable this(this);

    ~this()
    {
        deinit();
    }

    bool empty() const pure @safe
    {
        return value_ is null;
    }

    ref T value() return @system
    {
        require(value_ !is null, "empty deserialized value");
        return *value_;
    }

    ref const(T) value() const return @system
    {
        require(value_ !is null, "empty deserialized value");
        return *value_;
    }

    T* pointer() return @system
    {
        return value_;
    }

    void deinit()
    {
        if (value_ !is null)
        {
            releaseDecoded(*value_, allocator_);
            allocator_.deallocate(value_);
        }
        allocator_ = null;
        value_ = null;
    }
}

package(xtb.serde) bool prepareDeserialized(T)(
    Allocator* allocator,
    Deserialized!T* output,
    T** value,
)
{
    require(allocator !is null && *allocator !is null,
        "serde requires a valid allocator");
    require(output !is null, "deserialized output pointer is null");
    require(value !is null, "deserialized value pointer is null");
    output.deinit();
    T* created = allocator.tryAllocate!T();
    if (created is null)
    {
        *value = null;
        return false;
    }
    *created = T.init;
    output.allocator_ = allocator;
    output.value_ = created;
    *value = created;
    return true;
}

package(xtb.serde) void abandonDeserialized(T)(Deserialized!T* output)
{
    require(output !is null, "deserialized output pointer is null");
    output.deinit();
}

package(xtb.serde) void releaseDecoded(T)(ref T value, Allocator* allocator)
{
    alias U = Unqualified!T;
    static if (isString!U)
    {
        if (value.ptr !is null)
            allocator.deallocate(cast(char*) value.ptr, value.length + 1);
        value = null;
    }
    else static if (is(U == Pointee*, Pointee))
    {
        if (value !is null)
        {
            releaseDecoded(*value, allocator);
            allocator.deallocate(value);
            value = null;
        }
    }
    else static if (isDynamicArray!U)
    {
        foreach (ref element; value)
            releaseDecoded(element, allocator);
        allocator.deallocate(value.ptr, value.length);
        value = null;
    }
    else static if (isFixedArray!U)
    {
        foreach (ref element; value)
            releaseDecoded(element, allocator);
        value = U.init;
    }
    else static if (isSerdeStruct!U)
    {
        static foreach (index; 0 .. U.tupleof.length)
            static if (!fieldHas!(U, index, Ignore))
                releaseDecoded(value.tupleof[index], allocator);
        value = U.init;
    }
    else
        value = U.init;
}
