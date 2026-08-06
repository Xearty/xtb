module xtb.core.owned_string;

nothrow @nogc:

import core.lifetime : move;
import core.stdc.string : memmove;
import xtb.core.hash : hashValue;
import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator, deallocate, tryAllocate;
import xtb.core.panic : panic, require;
import xtb.core.string : String, StringBuf, StringBufUnmanaged,
    asStringUnchecked, equal;
import xtb.core.types : u8;

/// Immutable exact-sized UTF-8 allocation without an embedded allocator.
///
/// The zero state is valid. Nonempty values must be explicitly deinitialized
/// with the allocator that created or adopted their storage. Copying is
/// disabled because a shallow copy would duplicate ownership.
struct OwnedStringUnmanaged
{
nothrow @nogc:

private:
    String value_;

public:
    @disable this(this);

    static bool tryFromString(
        Allocator* allocator,
        scope String value,
        scope OwnedStringUnmanaged* output,
    ) @trusted
    {
        requireValidOwnedStringAllocator(allocator);
        require(output !is null,
            "OwnedStringUnmanaged output pointer is null");
        require(output.value_.ptr is null && output.value_.length == 0,
            "OwnedStringUnmanaged output is not empty");

        if (value.length == 0)
            return true;

        char* bytes = allocator.tryAllocate!char(value.length);
        if (bytes is null)
            return false;
        memmove(bytes, value.ptr, value.length);
        output.value_ = bytes[0 .. value.length];
        return true;
    }

    static OwnedStringUnmanaged fromString(
        Allocator* allocator,
        scope String value,
    ) @trusted
    {
        OwnedStringUnmanaged result;
        if (!tryFromString(allocator, value, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    /// Copies bytes whose UTF-8 validity the caller has already proved.
    static bool tryFromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        scope OwnedStringUnmanaged* output,
    ) @system
    {
        return tryFromString(allocator, bytes.asStringUnchecked, output);
    }

    /// Panicking counterpart to `tryFromBytesUnchecked`.
    static OwnedStringUnmanaged fromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    ) @system
    {
        OwnedStringUnmanaged result;
        if (!tryFromBytesUnchecked(allocator, bytes, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    void deinit(Allocator* allocator) @trusted
    {
        if (value_.length != 0)
        {
            requireValidOwnedStringAllocator(allocator);
            allocator.deallocate(cast(char*) value_.ptr, value_.length);
        }
        value_ = String.init;
    }

    void resetAndRelease(Allocator* allocator) @trusted
    {
        deinit(allocator);
    }

    String view() const return pure @safe
    {
        return value_;
    }

    size_t byteLength() const pure @safe
    {
        return value_.length;
    }

    bool empty() const pure @safe
    {
        return value_.length == 0;
    }

    bool opEquals(scope String other) const pure @safe
    {
        return value_.equal(other);
    }

    bool opEquals(scope ref const OwnedStringUnmanaged other) const
        pure @safe
    {
        return value_.equal(other.value_);
    }

    size_t toHash() const pure @safe
    {
        return hashValue(value_);
    }

package(xtb):
    static OwnedStringUnmanaged adoptExact(String value) @system
    {
        require((value.length == 0) == (value.ptr is null),
            "adopted OwnedString storage is not canonical");
        OwnedStringUnmanaged result;
        result.value_ = value;
        return move(result);
    }

    String releaseExact() @system
    {
        String result = value_;
        value_ = String.init;
        return result;
    }

    const(String)* viewPointer() const return @safe
    {
        return &value_;
    }
}

/// Standalone RAII wrapper around `OwnedStringUnmanaged`.
struct OwnedString
{
nothrow @nogc:

    alias Self = OwnedString;
    alias Storage = OwnedStringUnmanaged;

private:
    Allocator* allocator_;
    Storage storage_;

public:
    mixin ManagedContainerAdapter!(Self, Storage);

    static bool tryFromStringBuf(
        Allocator* destination,
        scope StringBuf* source,
        scope Self* output,
    ) @trusted
    {
        requireValidOwnedStringAllocator(destination);
        require(source !is null, "StringBuf source pointer is null");
        require(output !is null, "OwnedString output pointer is null");
        require(output.allocator_ is null && output.storage_.empty,
            "OwnedString output is not empty");

        if (source.empty)
        {
            source.deinit();
            Self result = Self.create(destination);
            *output = move(result);
            return true;
        }

        if (source.allocator is destination)
        {
            if (source.byteCapacity == source.byteLength ||
                source.tryShrinkToFit())
            {
                auto released = source.release();
                Allocator* releasedAllocator;
                StringBufUnmanaged raw = released.extract(
                    &releasedAllocator,
                );
                require(releasedAllocator is destination,
                    "StringBuf allocator changed during release");
                String exact = raw.releaseExactStorage();
                Storage storage = Storage.adoptExact(exact);
                Self result = adoptUnmanaged(destination, &storage);
                *output = move(result);
                return true;
            }
        }

        Self copied;
        if (!Self.tryFromString(destination, source.view, &copied))
            return false;
        source.deinit();
        *output = move(copied);
        return true;
    }

    static Self fromStringBuf(
        Allocator* destination,
        scope StringBuf* source,
    ) @trusted
    {
        Self result;
        if (!tryFromStringBuf(destination, source, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    bool tryClone(Allocator* allocator, scope Self* output) const @safe
    {
        return Self.tryFromString(allocator, view, output);
    }

    Self clone(Allocator* allocator) const @safe
    {
        return Self.fromString(allocator, view);
    }

package(xtb):
    static Self adoptUnmanaged(
        Allocator* allocator,
        scope Storage* storage,
    ) @system
    {
        requireValidOwnedStringAllocator(allocator);
        require(storage !is null,
            "OwnedStringUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(*storage);
        return move(result);
    }
}

private void requireValidOwnedStringAllocator(Allocator* allocator)
{
    require(allocator !is null && *allocator !is null,
        "OwnedString requires a valid allocator");
}

static assert(OwnedStringUnmanaged.sizeof == String.sizeof);
static assert(OwnedString.sizeof == (Allocator*).sizeof + String.sizeof);

unittest
{
    import xtb.core.memory : InstrumentedAllocator, mallocAllocator;

    OwnedString empty = OwnedString.fromString(mallocAllocator(), "");
    assert(empty.empty);
    assert(empty.allocator is mallocAllocator());

    OwnedString text = OwnedString.fromString(mallocAllocator(), "hello");
    assert(text.view == "hello");
    assert(text.byteLength == 5);
    assert(text.toHash == hashValue("hello"));
    static assert(!__traits(isCopyable, OwnedString));
    static assert(!__traits(isCopyable, OwnedStringUnmanaged));

    OwnedString copy = text.clone(mallocAllocator());
    assert(copy == text);
    assert(copy.view.ptr !is text.view.ptr);

    StringBuf exact = StringBuf.fromString(mallocAllocator(), "exact");
    exact.shrinkToFit();
    const exactPointer = exact.view.ptr;
    OwnedString adopted = OwnedString.fromStringBuf(
        mallocAllocator(),
        &exact,
    );
    assert(exact.allocator is null && exact.empty);
    assert(adopted.view.ptr is exactPointer);

    import xtb.core.memory : AllocationRecord;

    AllocationRecord[8] records;
    InstrumentedAllocator failing = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    StringBuf source = StringBuf.fromString(mallocAllocator(), "retained");
    failing.failAfter(0);
    OwnedString failed;
    assert(!OwnedString.tryFromStringBuf(failing.handle, &source, &failed));
    assert(source.view == "retained");
    assert(failed.allocator is null && failed.empty);
    assert(failing.clean);
    source.deinit();
}

unittest
{
    import xtb.core.memory : AllocationRecord, InstrumentedAllocator,
        mallocAllocator;

    AllocationRecord[16] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    OwnedStringUnmanaged exact;
    assert(OwnedStringUnmanaged.tryFromString(
        allocator.handle,
        "sixteen bytes!!!",
        &exact,
    ));
    assert(exact.byteLength == 16);
    assert(allocator.stats.outstandingAllocations == 1);
    assert(allocator.stats.outstandingBytes == 16);
    exact.deinit(allocator.handle);
    assert(allocator.clean);

    const allocationCalls = allocator.stats.allocationCalls;
    OwnedString empty = OwnedString.fromString(allocator.handle, "");
    assert(empty.empty);
    assert(empty.allocator is allocator.handle);
    assert(allocator.stats.allocationCalls == allocationCalls);

    StringBuf spare = StringBuf.withCapacity(allocator.handle, 64);
    spare.append("small");
    OwnedString compact = OwnedString.fromStringBuf(
        allocator.handle,
        &spare,
    );
    assert(compact.view == "small");
    assert(compact.byteLength == 5);
    assert(spare.allocator is null && spare.empty);

    AllocationRecord[8] foreignRecords;
    InstrumentedAllocator foreign = InstrumentedAllocator.create(
        mallocAllocator(),
        foreignRecords[],
    );
    StringBuf foreignBuffer = StringBuf.fromString(
        foreign.handle,
        "foreign",
    );
    const foreignPointer = foreignBuffer.view.ptr;
    OwnedString normalized = OwnedString.fromStringBuf(
        allocator.handle,
        &foreignBuffer,
    );
    assert(normalized.view == "foreign");
    assert(normalized.view.ptr !is foreignPointer);
    assert(foreignBuffer.allocator is null && foreignBuffer.empty);
    assert(foreign.clean);

    normalized.deinit();
    compact.deinit();
    empty.deinit();
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
    assert(foreign.stats.invalidCalls == 0);
}
