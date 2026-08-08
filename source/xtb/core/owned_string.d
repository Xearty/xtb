module xtb.core.owned_string;

nothrow @nogc:

import core.lifetime : move;
import core.stdc.string : memmove;
import xtb.core.hash : hashValue;
import xtb.core.memory : Allocator, deallocateArray, tryAllocateArray;
import xtb.core.panic : panic;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.released_storage : ReleasedStorage;
import xtb.core.string : StringBuf, StringBufUnmanaged, asStringUnchecked;
import xtb.core.types : String, u8;

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
        version (XTB_Checked)
        {
            require(output !is null,
                "OwnedStringUnmanaged output pointer is null");
            require(output.value_.ptr is null && output.value_.length == 0,
                "OwnedStringUnmanaged output is not empty");
        }

        if (value.length == 0)
            return true;

        char* bytes = allocator.tryAllocateArray!char(value.length).ptr;
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
            allocator.deallocateArray(value_.ptr[0 .. value_.length]);
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
        import xtb.core.string : equal;

        return value_.equal(other);
    }

    bool opEquals(scope ref const OwnedStringUnmanaged other) const
    pure @safe
    {
        import xtb.core.string : equal;

        return value_.equal(other.value_);
    }

    size_t toHash() const pure @safe
    {
        return hashValue(value_);
    }

package(xtb):
    static OwnedStringUnmanaged adoptExact(String value) @system
    {
        version (XTB_Checked)
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
    alias Released = ReleasedStorage!Storage;

private:
    Allocator* allocator_;
    Storage storage_;

    version (XTB_Checked)
    {
        invariant
        {
            require(&this !is null, "OwnedString pointer is null");
        }
    }

public:
    @disable this(this);

    static Self create(Allocator* allocator) @trusted
    {
        requireValidOwnedStringAllocator(allocator);
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    static bool tryFromString(
        Allocator* allocator,
        scope String value,
        scope Self* output,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(output !is null, "OwnedString output pointer is null");
            require(output.allocator_ is null && output.storage_.empty,
                "OwnedString output is not empty");
        }
        Storage storage;
        if (!Storage.tryFromString(allocator, value, &storage))
            return false;
        output.allocator_ = allocator;
        output.storage_ = move(storage);
        return true;
    }

    static Self fromString(Allocator* allocator, scope String value) @trusted
    {
        Self result;
        if (!tryFromString(allocator, value, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    static bool tryFromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
        scope Self* output,
    ) @system
    {
        version (XTB_Checked)
        {
            require(output !is null, "OwnedString output pointer is null");
            require(output.allocator_ is null && output.storage_.empty,
                "OwnedString output is not empty");
        }
        Storage storage;
        if (!Storage.tryFromBytesUnchecked(allocator, bytes, &storage))
            return false;
        output.allocator_ = allocator;
        output.storage_ = move(storage);
        return true;
    }

    static Self fromBytesUnchecked(
        Allocator* allocator,
        scope const(u8)[] bytes,
    ) @system
    {
        Self result;
        if (!tryFromBytesUnchecked(allocator, bytes, &result))
            panic("OwnedString allocation failed");
        return move(result);
    }

    static bool tryFromStringBuf(
        Allocator* destination,
        scope StringBuf* source,
        scope Self* output,
    ) @trusted
    {
        requireValidOwnedStringAllocator(destination);
        version (XTB_Checked)
        {
            require(source !is null, "StringBuf source pointer is null");
            require(output !is null, "OwnedString output pointer is null");
            require(output.allocator_ is null && output.storage_.empty,
                "OwnedString output is not empty");
        }

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
                version (XTB_Checked)
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

    static Self adopt(scope Released* released) @trusted
    {
        version (XTB_Checked)
            require(released !is null,
                "released OwnedString storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(storage);
        return move(result);
    }

    ~this() @trusted
    {
        this.deinit();
    }

    void deinit() @trusted
    {
        if (allocator_ is null)
            return;
        storage_.deinit(allocator_);
        allocator_ = null;
    }

    void resetAndRelease() @trusted
    {
        storage_.resetAndRelease(allocator_);
    }

    Released release() @trusted
    {
        auto result = Released.fromOwnedParts(allocator_, &storage_);
        allocator_ = null;
        return move(result);
    }

    String view() const return pure @trusted
    {
        return storage_.view;
    }

    size_t byteLength() const pure @trusted
    {
        return storage_.byteLength;
    }

    bool empty() const pure @trusted
    {
        return storage_.empty;
    }

    bool equal(scope String other) const pure @trusted
    {
        return storage_ == other;
    }

    bool equal(scope ref const Self other) const pure @trusted
    {
        return storage_ == other.storage_;
    }

    bool tryClone(
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return Self.tryFromString(allocator, storage_.view, output);
    }

    Self clone(Allocator* allocator) const @trusted
    {
        return Self.fromString(allocator, storage_.view);
    }

    bool opEquals(scope String other) const pure @trusted
    {
        return storage_ == other;
    }

    bool opEquals(scope ref const Self other) const pure @trusted
    {
        return storage_ == other.storage_;
    }

    size_t toHash() const pure @trusted
    {
        return storage_.toHash();
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
        requireValidOwnedStringAllocator(allocator);
        version (XTB_Checked)
            require(storage !is null,
                "OwnedStringUnmanaged pointer is null");
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(*storage);
        return move(result);
    }
}

private void requireValidOwnedStringAllocator(Allocator* allocator) @trusted
{
    version (XTB_Checked)
        require(allocator !is null && *allocator !is null,
            "OwnedString requires a valid allocator");
}

static assert(OwnedStringUnmanaged.sizeof == String.sizeof);
static assert(OwnedString.sizeof == (Allocator*).sizeof + String.sizeof);
static assert(is(typeof((cast(OwnedString*) null).allocator()) == Allocator*));
static assert(!__traits(compiles,
        (cast(const(OwnedString)*) null).allocator()));

unittest
{
    import xtb.core.memory : InstrumentedAllocator, mallocAllocator;

    OwnedString empty = OwnedString.fromString(mallocAllocator(), "");
    assert(empty.empty);
    assert(empty.allocator is mallocAllocator());

    OwnedString text = OwnedString.fromString(mallocAllocator(), "hello");
    assert(text.view == "hello");
    assert(text.equal("hello"));
    assert(text.byteLength == 5);
    assert(text.toHash == hashValue("hello"));
    static assert(!__traits(isCopyable, OwnedString));
    static assert(!__traits(isCopyable, OwnedStringUnmanaged));

    OwnedString copy = text.clone(mallocAllocator());
    assert(copy == text);
    assert(copy.equal(text));
    assert(copy.view.ptr !is text.view.ptr);

    StringBuf exact = StringBuf.fromString(mallocAllocator(), "exact");
    const(char)* exactPointer;
    {
        exact.shrinkToFit();
        exactPointer = exact.view.ptr;
    }
    OwnedString adopted = OwnedString.fromStringBuf(
        mallocAllocator(),
        &exact,
    );
    {
        import xtb.core.string : empty;

        assert(exact.allocator is null && exact.empty);
    }
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
    assert(!OwnedString.tryFromStringBuf(failing.allocator, &source, &failed));
    {
        assert(source.view == "retained");
        source.deinit();
    }
    assert(failed.allocator is null && failed.empty);
    assert(failing.clean);
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
            allocator.allocator,
            "sixteen bytes!!!",
            &exact,
    ));
    assert(exact.byteLength == 16);
    assert(allocator.stats.outstandingAllocations == 1);
    assert(allocator.stats.outstandingBytes == 16);
    exact.deinit(allocator.allocator);
    assert(allocator.clean);

    const allocationCalls = allocator.stats.allocationCalls;
    OwnedString empty = OwnedString.fromString(allocator.allocator, "");
    assert(empty.empty);
    assert(empty.allocator is allocator.allocator);
    assert(allocator.stats.allocationCalls == allocationCalls);

    StringBuf spare = StringBuf.withCapacity(allocator.allocator, 64);
    {
        spare.append("small");
    }
    OwnedString compact = OwnedString.fromStringBuf(
        allocator.allocator,
        &spare,
    );
    assert(compact.view == "small");
    assert(compact.byteLength == 5);
    {
        import xtb.core.string : empty;

        assert(spare.allocator is null && spare.empty);
    }

    AllocationRecord[8] foreignRecords;
    InstrumentedAllocator foreign = InstrumentedAllocator.create(
        mallocAllocator(),
        foreignRecords[],
    );
    StringBuf foreignBuffer = StringBuf.fromString(
        foreign.allocator,
        "foreign",
    );
    const(char)* foreignPointer;
    {
        foreignPointer = foreignBuffer.view.ptr;
    }
    OwnedString normalized = OwnedString.fromStringBuf(
        allocator.allocator,
        &foreignBuffer,
    );
    assert(normalized.view == "foreign");
    assert(normalized.view.ptr !is foreignPointer);
    {
        import xtb.core.string : empty;

        assert(foreignBuffer.allocator is null && foreignBuffer.empty);
    }
    assert(foreign.clean);

    normalized.deinit();
    compact.deinit();
    empty.deinit();
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
    assert(foreign.stats.invalidCalls == 0);
}
