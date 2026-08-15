module xtb.core.owned_string;

nothrow @nogc:

import core.stdc.string : memmove;
import xtb.core.array : RawArrayStorage;
import xtb.core.allocators.arena : Arena;
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

    /// D's transitive const turns `Allocator*` into `const(Allocator)*` in a
    /// const method even though invoking the allocator does not mutate this
    /// `OwnedString`. Constructors only accept mutable allocator slots, so the
    /// original allocator remains mutable when the string is viewed as const.
    Allocator* allocatorForAllocation() const @trusted
    {
        return cast(Allocator*) allocator_;
    }

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

    /// Copies this value into storage owned by `arena`.
    bool tryCopy(Arena* arena, scope String* output) const @trusted
    {
        return storage_.view.tryCopy(arena, output);
    }

    /// Panicking arena-owned counterpart to `tryCopy`.
    String copy(Arena* arena) const @trusted
    {
        return storage_.view.copy(arena);
    }

    /// Clones this value with its current allocator.
    bool tryClone(scope Self* output) const @trusted
    {
        return Self.tryFromString(allocatorForAllocation, storage_.view, output);
    }

    /// Clones this value with an explicit allocator.
    bool tryClone(
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return Self.tryFromString(allocator, storage_.view, output);
    }

    /// Panicking clone using this value's current allocator.
    Self clone() const @trusted
    {
        return Self.fromString(allocatorForAllocation, storage_.view);
    }

    /// Panicking clone using an explicit allocator.
    Self clone(Allocator* allocator) const @trusted
    {
        return Self.fromString(allocator, storage_.view);
    }

    /// Concatenates into a new owner using this value's allocator.
    bool tryConcat(String right, scope Self* output) const @trusted
    {
        return storage_.view.tryConcat(right, allocatorForAllocation, output);
    }

    /// Concatenates into a new owner using an explicit allocator.
    bool tryConcat(
        String right,
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return storage_.view.tryConcat(right, allocator, output);
    }

    /// Concatenates into storage owned by `arena`.
    bool tryConcat(
        String right,
        Arena* arena,
        scope String* output,
    ) const @trusted
    {
        return storage_.view.tryConcat(right, arena, output);
    }

    /// Panicking concatenation using this value's allocator.
    Self concat(String right) const @trusted
    {
        return storage_.view.concat(right, allocatorForAllocation);
    }

    /// Panicking concatenation using an explicit allocator.
    Self concat(String right, Allocator* allocator) const @trusted
    {
        return storage_.view.concat(right, allocator);
    }

    /// Panicking concatenation into storage owned by `arena`.
    String concat(String right, Arena* arena) const @trusted
    {
        return storage_.view.concat(right, arena);
    }

    /// Replaces matches into a new owner using this value's allocator.
    bool tryReplace(
        String from,
        String to,
        scope Self* output,
    ) const @trusted
    {
        return storage_.view.tryReplace(from, to, allocatorForAllocation, output);
    }

    /// Replaces matches into a new owner using an explicit allocator.
    bool tryReplace(
        String from,
        String to,
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return storage_.view.tryReplace(from, to, allocator, output);
    }

    /// Replaces matches into storage owned by `arena`.
    bool tryReplace(
        String from,
        String to,
        Arena* arena,
        scope String* output,
    ) const @trusted
    {
        return storage_.view.tryReplace(from, to, arena, output);
    }

    /// Panicking replacement using this value's allocator.
    Self replace(String from, String to) const @trusted
    {
        return storage_.view.replace(from, to, allocatorForAllocation);
    }

    /// Panicking replacement using an explicit allocator.
    Self replace(
        String from,
        String to,
        Allocator* allocator,
    ) const @trusted
    {
        return storage_.view.replace(from, to, allocator);
    }

    /// Panicking replacement into storage owned by `arena`.
    String replace(String from, String to, Arena* arena) const @trusted
    {
        return storage_.view.replace(from, to, arena);
    }

    /// Escapes into a new owner using this value's allocator.
    bool tryEscape(scope Self* output) const @trusted
    {
        return storage_.view.tryEscape(allocatorForAllocation, output);
    }

    /// Escapes into a new owner using an explicit allocator.
    bool tryEscape(
        Allocator* allocator,
        scope Self* output,
    ) const @trusted
    {
        return storage_.view.tryEscape(allocator, output);
    }

    /// Escapes into storage owned by `arena`.
    bool tryEscape(Arena* arena, scope String* output) const @trusted
    {
        return storage_.view.tryEscape(arena, output);
    }

    /// Panicking escape using this value's allocator.
    Self escape() const @trusted
    {
        return storage_.view.escape(allocatorForAllocation);
    }

    /// Panicking escape using an explicit allocator.
    Self escape(Allocator* allocator) const @trusted
    {
        return storage_.view.escape(allocator);
    }

    /// Panicking escape into storage owned by `arena`.
    String escape(Arena* arena) const @trusted
    {
        return storage_.view.escape(arena);
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

/// Consumes `source` into an immutable exact-sized owner using the buffer's
/// current allocator. On allocation failure `source` is unchanged.
bool tryIntoOwnedString(
    scope ref StringBuf source,
    scope OwnedString* output,
) @trusted
{
    return tryIntoOwnedString(source, source.allocator, output);
}

/// Consumes `source` into an immutable exact-sized owner using `destination`.
/// On allocation failure `source` is unchanged.
bool tryIntoOwnedString(
    scope ref StringBuf source,
    Allocator* destination,
    scope OwnedString* output,
) @trusted
{
    return tryConsumeStringBuf(destination, &source, output);
}

/// Panicking counterpart to `tryIntoOwnedString` using the buffer's allocator.
OwnedString intoOwnedString(scope ref StringBuf source) @trusted
{
    return intoOwnedString(source, source.allocator);
}

/// Panicking counterpart to `tryIntoOwnedString` using `destination`.
OwnedString intoOwnedString(
    scope ref StringBuf source,
    Allocator* destination,
) @trusted
{
    OwnedString result;
    if (!tryConsumeStringBuf(destination, &source, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

private bool tryConsumeStringBuf(
    Allocator* destination,
    scope StringBuf* source,
    scope OwnedString* output,
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
        OwnedString result = OwnedString.create(destination);
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
            OwnedStringUnmanaged storage =
                OwnedStringUnmanaged.adoptExact(&exact);
            OwnedString result =
                OwnedString.adoptUnmanaged(destination, &storage);
            moveEmplace(result, *output);
            return true;
        }
    }

    OwnedString copied;
    if (!OwnedString.tryFromString(destination, source.view, &copied))
        return false;
    source.resetAndRelease();
    source.deinit();
    moveEmplace(copied, *output);
    return true;
}

/// Copies borrowed text into exact-sized independently owned storage.
bool tryCopy(
    String value,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryCopyImpl(value, allocator, output);
}

/// Copies borrowed text into storage owned by `arena`.
bool tryCopy(
    String value,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryCopyImpl(value, arena, output);
}

/// Panicking independently owned counterpart to `tryCopy`.
OwnedString copy(String value, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!value.tryCopy(allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `tryCopy`.
String copy(String value, Arena* arena) @trusted
{
    String result;
    if (!value.tryCopy(arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Concatenates into exact-sized independently owned storage.
bool tryConcat(
    String left,
    String right,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryConcatImpl(left, right, allocator, output);
}

/// Concatenates into storage owned by `arena`.
bool tryConcat(
    String left,
    String right,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryConcatImpl(left, right, arena, output);
}

/// Panicking independently owned counterpart to `tryConcat`.
OwnedString concat(String left, String right, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!left.tryConcat(right, allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `tryConcat`.
String concat(String left, String right, Arena* arena) @trusted
{
    String result;
    if (!left.tryConcat(right, arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Replaces every non-overlapping `from` occurrence in independently owned output.
bool tryReplace(
    String value,
    String from,
    String to,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryReplaceImpl(value, from, to, allocator, output);
}

/// Replaces every non-overlapping `from` occurrence in arena-owned output.
bool tryReplace(
    String value,
    String from,
    String to,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryReplaceImpl(value, from, to, arena, output);
}

/// Panicking independently owned counterpart to `tryReplace`.
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

/// Panicking arena-owned counterpart to `tryReplace`.
String replace(
    String value,
    String from,
    String to,
    Arena* arena,
) @trusted
{
    String result;
    if (!value.tryReplace(from, to, arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Joins borrowed strings into exact-sized independently owned storage.
bool tryJoin(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryJoinImpl(values, separator, allocator, output);
}

/// Joins borrowed strings into storage owned by `arena`.
bool tryJoin(
    scope const(String)[] values,
    String separator,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryJoinImpl(values, separator, arena, output);
}

/// Panicking independently owned counterpart to `tryJoin`.
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

/// Panicking arena-owned counterpart to `tryJoin`.
String join(
    scope const(String)[] values,
    String separator,
    Arena* arena,
) @trusted
{
    String result;
    if (!tryJoin(values, separator, arena, &result))
        panic("arena string allocation failed");
    return result;
}

/// Escapes conventional C-style special characters into independently owned text.
bool tryEscape(
    String value,
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    return tryEscapeImpl(value, allocator, output);
}

/// Escapes conventional C-style special characters into arena-owned text.
bool tryEscape(
    String value,
    Arena* arena,
    scope String* output,
) @trusted
{
    return tryEscapeImpl(value, arena, output);
}

/// Panicking independently owned counterpart to `tryEscape`.
OwnedString escape(String value, Allocator* allocator) @trusted
{
    OwnedString result;
    if (!value.tryEscape(allocator, &result))
        panic("OwnedString allocation failed");
    return move(result);
}

/// Panicking arena-owned counterpart to `tryEscape`.
String escape(String value, Arena* arena) @trusted
{
    String result;
    if (!value.tryEscape(arena, &result))
        panic("arena string allocation failed");
    return result;
}

private bool tryCopyImpl(Context, Output)(
    String value,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
    char[] allocation;
    if (!tryPrepareStringTransform(context, value.length, &allocation))
        return false;
    if (value.length != 0)
        memmove(allocation.ptr, value.ptr, value.length);
    commitStringTransform(context, allocation, output);
    return true;
}

private bool tryConcatImpl(Context, Output)(
    String left,
    String right,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
    if (right.length > size_t.max - left.length)
        return false;
    const length = left.length + right.length;

    char[] allocation;
    if (!tryPrepareStringTransform(context, length, &allocation))
        return false;
    if (left.length != 0)
        memmove(allocation.ptr, left.ptr, left.length);
    if (right.length != 0)
        memmove(allocation.ptr + left.length, right.ptr, right.length);
    commitStringTransform(context, allocation, output);
    return true;
}

private bool tryReplaceImpl(Context, Output)(
    String value,
    String from,
    String to,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
    if (from.length == 0)
        return tryCopyImpl(value, context, output);

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

    char[] allocation;
    if (!tryPrepareStringTransform(context, length, &allocation))
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
    commitStringTransform(context, allocation, output);
    return true;
}

private bool tryJoinImpl(Context, Output)(
    scope const(String)[] values,
    String separator,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
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

    char[] allocation;
    if (!tryPrepareStringTransform(context, length, &allocation))
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
    commitStringTransform(context, allocation, output);
    return true;
}

private bool tryEscapeImpl(Context, Output)(
    String value,
    Context context,
    scope Output* output,
) @trusted
{
    requireStringTransformOutput(context, output);
    size_t escapedCount;
    foreach (character; value)
        if (escapedCharacter(character) != '\0')
            ++escapedCount;
    if (escapedCount > size_t.max - value.length)
        return false;
    const length = value.length + escapedCount;

    char[] allocation;
    if (!tryPrepareStringTransform(context, length, &allocation))
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
    commitStringTransform(context, allocation, output);
    return true;
}

private void requireStringTransformOutput(
    Allocator* allocator,
    scope OwnedString* output,
) @trusted
{
    requireEmptyOwnedStringOutput(allocator, output);
}

private void requireStringTransformOutput(
    Arena* arena,
    scope String* output,
) @trusted
{
    version (XTB_Checked)
    {
        require(arena !is null, "string transform requires a valid arena");
        require(output !is null, "String output pointer is null");
    }
}

private bool tryPrepareStringTransform(
    Allocator* allocator,
    size_t length,
    scope char[]* allocation,
) @trusted
{
    if (length == 0)
        return true;
    *allocation = allocator.tryAllocateArray!char(length);
    return allocation.ptr !is null;
}

private bool tryPrepareStringTransform(
    Arena* arena,
    size_t length,
    scope char[]* allocation,
) @trusted
{
    if (length == 0)
        return true;
    *allocation = arena.tryAllocateArray!char(length);
    return allocation.ptr !is null;
}

private void commitStringTransform(
    Allocator* allocator,
    char[] allocation,
    scope OwnedString* output,
) @system
{
    if (allocation.length == 0)
    {
        OwnedString result = OwnedString.create(allocator);
        moveEmplace(result, *output);
        return;
    }
    adoptExactOwnedString(allocator, allocation, output);
}

private void commitStringTransform(
    Arena*,
    char[] allocation,
    scope String* output,
) @trusted
{
    *output = allocation;
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
    OwnedString adopted = exact.intoOwnedString();
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
    assert(!source.tryIntoOwnedString(failing.allocator, &failed));
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
    OwnedString compact = spare.intoOwnedString();
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
    OwnedString normalized =
        foreignBuffer.intoOwnedString(allocator.allocator);
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
