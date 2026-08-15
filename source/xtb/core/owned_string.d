module xtb.core.owned_string;

nothrow @nogc:

import core.stdc.string : memmove;
import xtb.core.array : RawArrayStorage;
import xtb.core.hash : hashValue;
import xtb.core.lifetime : move, moveEmplace;
import xtb.core.memory : Allocator, deallocateArray, tryAllocateArray;
import xtb.core.panic : panic;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.released_storage : ReleasedStorage;
import xtb.core.string : StringBuf, StringBufUnmanaged, asStringUnchecked,
    escapedCharacter, find, notFound;
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
    @disable ref OwnedStringUnmanaged opAssign(OwnedStringUnmanaged source) return;

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
    static OwnedStringUnmanaged adoptExact(
        scope RawArrayStorage!char* storage,
    ) @system
    {
        version (XTB_Checked)
        {
            require(storage !is null,
                "raw OwnedString storage pointer is null");
            require(storage.length == storage.capacity,
                "adopted OwnedString storage is not exact-sized");
            require((storage.length == 0) == (storage.data is null),
                "adopted OwnedString storage is not canonical");
        }
        OwnedStringUnmanaged result;
        result.value_ = storage.data[0 .. storage.length];
        storage.data = null;
        storage.length = 0;
        storage.capacity = 0;
        return move(result);
    }

    const(String)* viewPointer() const return @safe
    {
        return &value_;
    }
}

/// Standalone explicit-lifetime wrapper around `OwnedStringUnmanaged`.
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
    @disable ref Self opAssign(Self source) return;

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
        moveEmplace(storage, output.storage_);
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
        moveEmplace(storage, output.storage_);
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
            source.resetAndRelease();
            source.deinit();
            Self result = Self.create(destination);
            moveEmplace(result, *output);
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
                RawArrayStorage!char exact = raw.releaseExactStorage();
                Storage storage = Storage.adoptExact(&exact);
                Self result = adoptUnmanaged(destination, &storage);
                moveEmplace(result, *output);
                return true;
            }
        }

        Self copied;
        if (!Self.tryFromString(destination, source.view, &copied))
            return false;
        source.resetAndRelease();
        source.deinit();
        moveEmplace(copied, *output);
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
        moveEmplace(storage, result.storage_);
        return move(result);
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
        moveEmplace(*storage, result.storage_);
        return move(result);
    }
}

/// Copies a borrowed string into exact-sized immutable owned storage.
bool tryCopy(
    String value,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return OwnedString.tryFromString(allocator, value, output);
}

/// Panicking counterpart to `tryCopy`.
OwnedString copy(String value, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!value.tryCopy(allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Concatenates two borrowed strings into exact-sized immutable owned storage.
bool tryConcat(
    String left,
    String right,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    requireEmptyOwnedStringOutput(allocator, output);
    if (right.length > size_t.max - left.length)
        return false;
    const length = left.length + right.length;
    if (length == 0)
    {
        OwnedString result = OwnedString.create(allocator);
        moveEmplace(result, *output);
        return true;
    }

    char[] allocation = allocator.tryAllocateArray!char(length);
    if (allocation.ptr is null)
        return false;
    if (left.length != 0)
        memmove(allocation.ptr, left.ptr, left.length);
    if (right.length != 0)
        memmove(allocation.ptr + left.length, right.ptr, right.length);
    adoptExactOwnedString(allocator, allocation, output);
    return true;
}

/// Panicking counterpart to `tryConcat`.
OwnedString concat(String left, String right, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!left.tryConcat(right, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Replaces every non-overlapping `from` occurrence with `to` in owned output.
bool tryReplace(
    String value,
    String from,
    String to,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    requireEmptyOwnedStringOutput(allocator, output);
    if (from.length == 0)
        return value.tryCopy(allocator, output);

    size_t count;
    size_t position;
    while (position <= value.length)
    {
        const found = value[position .. $].find(from);
        if (found == notFound)
            break;
        ++count;
        position += found + from.length;
    }

    size_t length = value.length;
    if (to.length >= from.length)
    {
        const growth = to.length - from.length;
        if (growth != 0 && count > (size_t.max - length) / growth)
            return false;
        length += count * growth;
    }
    else
        length -= count * (from.length - to.length);

    if (length == 0)
    {
        OwnedString result = OwnedString.create(allocator);
        moveEmplace(result, *output);
        return true;
    }

    char[] allocation = allocator.tryAllocateArray!char(length);
    if (allocation.ptr is null)
        return false;
    size_t sourceOffset;
    size_t destinationOffset;
    while (sourceOffset < value.length)
    {
        const found = value[sourceOffset .. $].find(from);
        if (found == notFound)
        {
            const remainder = value.length - sourceOffset;
            if (remainder != 0)
                memmove(
                    allocation.ptr + destinationOffset,
                    value.ptr + sourceOffset,
                    remainder,
                );
            destinationOffset += remainder;
            break;
        }
        if (found != 0)
            memmove(
                allocation.ptr + destinationOffset,
                value.ptr + sourceOffset,
                found,
            );
        destinationOffset += found;
        if (to.length != 0)
            memmove(
                allocation.ptr + destinationOffset,
                to.ptr,
                to.length,
            );
        destinationOffset += to.length;
        sourceOffset += found + from.length;
    }
    adoptExactOwnedString(allocator, allocation, output);
    return true;
}

/// Panicking counterpart to `tryReplace`.
OwnedString replace(
    String value,
    String from,
    String to,
    Allocator* allocator,
) @trusted
{
    OwnedString result;
    if (!value.tryReplace(from, to, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Joins borrowed strings into exact-sized immutable owned storage.
bool tryJoin(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    requireEmptyOwnedStringOutput(allocator, output);
    size_t length;
    foreach (value; values)
    {
        if (value.length > size_t.max - length)
            return false;
        length += value.length;
    }
    if (values.length > 1)
    {
        const count = values.length - 1;
        if (separator.length != 0 &&
            count > (size_t.max - length) / separator.length)
            return false;
        length += count * separator.length;
    }

    if (length == 0)
    {
        OwnedString result = OwnedString.create(allocator);
        moveEmplace(result, *output);
        return true;
    }

    char[] allocation = allocator.tryAllocateArray!char(length);
    if (allocation.ptr is null)
        return false;
    size_t offset;
    foreach (index, value; values)
    {
        if (index != 0 && separator.length != 0)
        {
            memmove(allocation.ptr + offset, separator.ptr, separator.length);
            offset += separator.length;
        }
        if (value.length != 0)
        {
            memmove(allocation.ptr + offset, value.ptr, value.length);
            offset += value.length;
        }
    }
    adoptExactOwnedString(allocator, allocation, output);
    return true;
}

/// Panicking counterpart to `tryJoin`.
OwnedString join(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
) @trusted
{
    OwnedString result;
    if (!tryJoin(values, separator, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Escapes conventional C-style special characters into immutable owned text.
bool tryEscape(
    String value,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    requireEmptyOwnedStringOutput(allocator, output);
    size_t escapedCount;
    foreach (character; value)
        if (escapedCharacter(character) != '\0')
            ++escapedCount;
    if (escapedCount > size_t.max - value.length)
        return false;
    const length = value.length + escapedCount;
    if (length == 0)
    {
        OwnedString result = OwnedString.create(allocator);
        moveEmplace(result, *output);
        return true;
    }

    char[] allocation = allocator.tryAllocateArray!char(length);
    if (allocation.ptr is null)
        return false;
    size_t offset;
    foreach (character; value)
    {
        const escaped = escapedCharacter(character);
        if (escaped != '\0')
        {
            allocation[offset++] = '\\';
            allocation[offset++] = escaped;
        }
        else
            allocation[offset++] = character;
    }
    adoptExactOwnedString(allocator, allocation, output);
    return true;
}

/// Panicking counterpart to `tryEscape`.
OwnedString escape(String value, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!value.tryEscape(allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

private void requireEmptyOwnedStringOutput(
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    requireValidOwnedStringAllocator(allocator);
    version (XTB_Checked)
    {
        require(output !is null, "OwnedString output pointer is null");
        require(output.allocator_ is null && output.storage_.empty,
            "OwnedString output is not empty");
    }
}

private void adoptExactOwnedString(
    Allocator* allocator,
    char[] allocation,
    scope OwnedString* output,
) @system
{
    RawArrayStorage!char raw = RawArrayStorage!char.adopt(
        allocation.ptr,
        allocation.length,
        allocation.length,
    );
    OwnedStringUnmanaged storage = OwnedStringUnmanaged.adoptExact(&raw);
    OwnedString result = OwnedString.adoptUnmanaged(allocator, &storage);
    moveEmplace(result, *output);
}

private void requireValidOwnedStringAllocator(Allocator* allocator) @trusted
{
    version (XTB_Checked)
        require(allocator !is null && *allocator !is null,
            "OwnedString requires a valid allocator");
}

static assert(OwnedStringUnmanaged.sizeof == String.sizeof);
static assert(OwnedString.sizeof == (Allocator*).sizeof + String.sizeof);
static assert(__traits(compiles, (scope OwnedString* value) @safe {
        Allocator* allocator = value.allocator;
    }));
static assert(!__traits(compiles, (scope const OwnedString* value) @safe {
        Allocator* allocator = value.allocator;
    }));

unittest
{
    import core.internal.traits : hasElaborateDestructor;
    import xtb.core.lifetime : needsDeinit;
    import xtb.core.allocators.instrumented : InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

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
    static assert(!hasElaborateDestructor!OwnedString);
    static assert(!hasElaborateDestructor!OwnedStringUnmanaged);
    static assert(needsDeinit!OwnedString);
    static assert(!__traits(compiles, (ref OwnedString left,
            ref OwnedString right) { left = move(right); }));
    static assert(!__traits(compiles, (ref OwnedStringUnmanaged left,
            ref OwnedStringUnmanaged right) { left = move(right); }));
    static assert(!__traits(compiles,
            OwnedStringUnmanaged.adoptExact(cast(String) "borrowed")));

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

    StringBufUnmanaged unmanaged = StringBufUnmanaged.fromString(
        mallocAllocator(),
        "unmanaged exact",
    );
    unmanaged.shrinkToFit(mallocAllocator());
    RawArrayStorage!char raw = unmanaged.releaseExactStorage();
    OwnedStringUnmanaged exactUnmanaged =
        OwnedStringUnmanaged.adoptExact(&raw);
    assert(raw.data is null && raw.length == 0 && raw.capacity == 0);
    assert(exactUnmanaged.view == "unmanaged exact");
    exactUnmanaged.deinit(mallocAllocator());

    import xtb.core.allocators.instrumented : AllocationRecord;

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

    failed.deinit();
    adopted.deinit();
    copy.deinit();
    text.deinit();
    empty.deinit();
}

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

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

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

    static assert(is(typeof("copy".copy(mallocAllocator())) == OwnedString));
    static assert(is(typeof("a".concat("b", mallocAllocator())) == OwnedString));
    static assert(is(typeof("a".replace("a", "b", mallocAllocator())) == OwnedString));
    static assert(is(typeof("a".escape(mallocAllocator())) == OwnedString));
    static assert(!is(typeof("copy".tryCopy(
            mallocAllocator(),
            cast(String*) null,
            ))));

    AllocationRecord[32] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );

    OwnedString copied = "copy".copy(allocator.allocator);
    assert(copied == "copy");
    assert(allocator.stats.outstandingBytes == copied.byteLength);
    copied.deinit();
    assert(allocator.clean);

    OwnedString concatenated = "left".concat("right", allocator.allocator);
    assert(concatenated == "leftright");
    assert(allocator.stats.outstandingBytes == concatenated.byteLength);
    concatenated.deinit();
    assert(allocator.clean);

    OwnedString replaced = "one two one".replace(
        "one",
        "1",
        allocator.allocator,
    );
    assert(replaced == "1 two 1");
    assert(allocator.stats.outstandingBytes == replaced.byteLength);
    replaced.deinit();
    assert(allocator.clean);

    String[3] parts = ["a", "b", "c"];
    OwnedString joined = parts[].join("/", allocator.allocator);
    assert(joined == "a/b/c");
    assert(allocator.stats.outstandingBytes == joined.byteLength);
    joined.deinit();
    assert(allocator.clean);

    OwnedString escaped = "a\n\t\\b".escape(allocator.allocator);
    assert(escaped == "a\\n\\t\\\\b");
    assert(allocator.stats.outstandingBytes == escaped.byteLength);
    escaped.deinit();
    assert(allocator.clean);

    const allocationCalls = allocator.stats.allocationCalls;
    OwnedString empty = "".concat("", allocator.allocator);
    assert(empty.empty && empty.allocator is allocator.allocator);
    assert(allocator.stats.allocationCalls == allocationCalls);
    empty.deinit();

    allocator.failAfter(0);
    OwnedString failedCopy;
    OwnedString failedConcat;
    OwnedString failedReplace;
    OwnedString failedJoin;
    OwnedString failedEscape;
    assert(!"copy".tryCopy(allocator.allocator, &failedCopy));
    assert(!"a".tryConcat("b", allocator.allocator, &failedConcat));
    assert(!"a".tryReplace("a", "b", allocator.allocator, &failedReplace));
    assert(!parts[].tryJoin("/", allocator.allocator, &failedJoin));
    assert(!"\n".tryEscape(allocator.allocator, &failedEscape));
    assert(failedCopy.allocator is null && failedCopy.empty);
    assert(failedConcat.allocator is null && failedConcat.empty);
    assert(failedReplace.allocator is null && failedReplace.empty);
    assert(failedJoin.allocator is null && failedJoin.empty);
    assert(failedEscape.allocator is null && failedEscape.empty);
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
}
