module xtb.threading.atomic;

nothrow @nogc:

import core.atomic;
import xtb.core.panic : panic;
import xtb.threading.internal.parking : park, parkingSupported, wakeAll, wakeOne;

/// C/C++-style memory ordering for XTB atomic operations.
///
/// `consume` is intentionally not part of the v1 model.
enum MemoryOrder : ubyte
{
    relaxed,
    acquire,
    release,
    acquireRelease,
    sequentiallyConsistent,
}

private template isTopLevelQualified(T)
{
    static if (is(T == const U, U))
        enum bool isTopLevelQualified = true;
    else static if (is(T == immutable U, U))
        enum bool isTopLevelQualified = true;
    else static if (is(T == shared U, U))
        enum bool isTopLevelQualified = true;
    else static if (is(T == inout U, U))
        enum bool isTopLevelQualified = true;
    else
        enum bool isTopLevelQualified = false;
}

private enum bool isAtomicWidthSupported(T) =
    T.sizeof == 1 || T.sizeof == 2 || T.sizeof == 4 || T.sizeof == 8;

private enum bool isAtomicEnum(T) = is(T == enum);
private enum bool isAtomicPointer(T) = is(T == U*, U);
private enum bool isAtomicIntegral(T) =
    __traits(isIntegral, T) && !isAtomicEnum!T;
private enum bool isAtomicFetchIntegral(T) =
    isAtomicIntegral!T && !is(T == bool);

private enum bool isAtomicTypeSupported(T) =
    !isTopLevelQualified!T &&
    isAtomicWidthSupported!T &&
    (isAtomicIntegral!T || isAtomicEnum!T || isAtomicPointer!T);

private enum bool isAtomicWaitSupported(T) =
    parkingSupported && T.sizeof == uint.sizeof;

private template CoreMemoryOrder(MemoryOrder order)
{
    static if (order == MemoryOrder.relaxed)
        enum CoreMemoryOrder = core.atomic.MemoryOrder.raw;
    else static if (order == MemoryOrder.acquire)
        enum CoreMemoryOrder = core.atomic.MemoryOrder.acq;
    else static if (order == MemoryOrder.release)
        enum CoreMemoryOrder = core.atomic.MemoryOrder.rel;
    else static if (order == MemoryOrder.acquireRelease)
        enum CoreMemoryOrder = core.atomic.MemoryOrder.acq_rel;
    else static if (order == MemoryOrder.sequentiallyConsistent)
        enum CoreMemoryOrder = core.atomic.MemoryOrder.seq;
    else
        static assert(false, "unsupported XTB MemoryOrder");
}

private bool validFailureOrder(MemoryOrder success, MemoryOrder failure) @safe
{
    if (failure == MemoryOrder.release ||
        failure == MemoryOrder.acquireRelease)
        return false;

    switch (success)
    {
        case MemoryOrder.relaxed:
            return failure == MemoryOrder.relaxed;
        case MemoryOrder.acquire:
            return failure == MemoryOrder.relaxed ||
                failure == MemoryOrder.acquire;
        case MemoryOrder.release:
            return failure == MemoryOrder.relaxed;
        case MemoryOrder.acquireRelease:
            return failure == MemoryOrder.relaxed ||
                failure == MemoryOrder.acquire;
        case MemoryOrder.sequentiallyConsistent:
            return failure == MemoryOrder.relaxed ||
                failure == MemoryOrder.acquire ||
                failure == MemoryOrder.sequentiallyConsistent;
        default:
            return false;
    }
}

private MemoryOrder failureOrderForRmw(MemoryOrder order)
{
    switch (order)
    {
        case MemoryOrder.relaxed:
            return MemoryOrder.relaxed;
        case MemoryOrder.acquire:
            return MemoryOrder.acquire;
        case MemoryOrder.release:
            return MemoryOrder.relaxed;
        case MemoryOrder.acquireRelease:
            return MemoryOrder.acquire;
        case MemoryOrder.sequentiallyConsistent:
            return MemoryOrder.sequentiallyConsistent;
        default:
            panic("invalid MemoryOrder value for atomic read-modify-write");
    }
}

/// An allocation-free atomic scalar value.
///
/// V1 supports unqualified 1/2/4/8-byte integral values (including character
/// types and `bool`), enums of those widths, and native pointers. Pointer
/// arithmetic fetch operations are intentionally absent. Arithmetic/bitwise
/// fetch operations are available only for non-`bool`, non-enum integral
/// values.
///
/// The wrapper is non-copyable. `Atomic.init` contains `T.init`; use
/// `Atomic!T(value)` for explicit non-default initialization. Ordinary
/// assignment between atomic wrappers is not an atomic operation and is
/// disabled by the non-copyable type.
///
/// LDC requires separate receiver overloads for `shared` and unshared wrapper
/// objects. Both surfaces operate on the same underlying atomic storage; the
/// qualifier casts needed to invoke compiler atomics are contained in trusted
/// methods and never expose a non-atomic access path.
struct Atomic(T)
{
nothrow @nogc:
    static assert(
        isAtomicTypeSupported!T,
        "Atomic!T v1 supports unqualified 1/2/4/8-byte integral, enum, or pointer types",
    );

    @disable this(this);

    /// Whether this atomic type can use the active backend's allocation-free
    /// blocking wait/notification path.
    ///
    /// V1 Linux parking uses a 32-bit futex wait word, so only atomic scalar
    /// types with the same storage width are waitable. Other supported atomic
    /// widths retain their non-blocking operations but do not expose
    /// `wait`/`notifyOne`/`notifyAll`.
    enum bool waitSupported = isAtomicWaitSupported!T;

    private T value_;

    /// Constructs an atomic value before publication to another thread.
    this(T value) @safe
    {
        value_ = value;
    }

    /// Atomically loads the current value.
    T load(
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) const @trusted
    {
        return loadAt(cast(T*)&value_, order);
    }

    /// Ditto, for a `shared Atomic!T` receiver.
    T load(
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) shared const @trusted
    {
        return loadAt(cast(T*)&value_, order);
    }

    static if (waitSupported)
    {
        /// Blocks while the atomic value compares equal to `oldValue`.
        ///
        /// Internal parking may return spuriously, so this method always
        /// re-checks the atomic value and returns only after observing a value
        /// different from `oldValue`. `release` and `acquireRelease` are not
        /// valid wait orders because the operation performs atomic loads.
        ///
        /// Once another thread may wait on this object, its address must remain
        /// stable until all such waiters have finished.
        void wait(
            T oldValue,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) const @trusted
        {
            waitAt(cast(T*)&value_, oldValue, order);
        }

        /// Ditto, for a `shared Atomic!T` receiver.
        void wait(
            T oldValue,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) shared const @trusted
        {
            waitAt(cast(T*)&value_, oldValue, order);
        }

        /// Wakes at most one thread blocked in `wait` on this atomic.
        ///
        /// Notification itself carries no publication ordering. Callers must
        /// publish protocol state with an atomic store/RMW before notifying.
        void notifyOne() const @trusted
        {
            wakeOne(waitAddress(cast(T*)&value_));
        }

        /// Ditto, for a `shared Atomic!T` receiver.
        void notifyOne() shared const @trusted
        {
            wakeOne(waitAddress(cast(T*)&value_));
        }

        /// Wakes all threads currently blocked in `wait` on this atomic.
        ///
        /// Notification itself carries no publication ordering. Callers must
        /// publish protocol state with an atomic store/RMW before notifying.
        void notifyAll() const @trusted
        {
            wakeAll(waitAddress(cast(T*)&value_));
        }

        /// Ditto, for a `shared Atomic!T` receiver.
        void notifyAll() shared const @trusted
        {
            wakeAll(waitAddress(cast(T*)&value_));
        }
    }

    /// Atomically stores a new value.
    void store(
        T value,
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) @trusted
    {
        storeAt(&value_, value, order);
    }

    /// Ditto, for a `shared Atomic!T` receiver.
    void store(
        T value,
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) shared @trusted
    {
        storeAt(cast(T*)&value_, value, order);
    }

    /// Atomically replaces the value and returns the previous value.
    T exchange(
        T value,
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) @trusted
    {
        return exchangeAt(&value_, value, order);
    }

    /// Ditto, for a `shared Atomic!T` receiver.
    T exchange(
        T value,
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) shared @trusted
    {
        return exchangeAt(cast(T*)&value_, value, order);
    }

    /// Weak compare/exchange with C/C++ expected-value semantics.
    bool compareExchangeWeak(
        ref T expected,
        T desired,
        MemoryOrder success = MemoryOrder.sequentiallyConsistent,
        MemoryOrder failure = MemoryOrder.sequentiallyConsistent,
    ) @trusted
    {
        return compareExchangeAt!true(
            &value_, expected, desired, success, failure,
        );
    }

    /// Ditto, for a `shared Atomic!T` receiver.
    bool compareExchangeWeak(
        ref T expected,
        T desired,
        MemoryOrder success = MemoryOrder.sequentiallyConsistent,
        MemoryOrder failure = MemoryOrder.sequentiallyConsistent,
    ) shared @trusted
    {
        return compareExchangeAt!true(
            cast(T*)&value_, expected, desired, success, failure,
        );
    }

    /// Strong compare/exchange with C/C++ expected-value semantics.
    bool compareExchangeStrong(
        ref T expected,
        T desired,
        MemoryOrder success = MemoryOrder.sequentiallyConsistent,
        MemoryOrder failure = MemoryOrder.sequentiallyConsistent,
    ) @trusted
    {
        return compareExchangeAt!false(
            &value_, expected, desired, success, failure,
        );
    }

    /// Ditto, for a `shared Atomic!T` receiver.
    bool compareExchangeStrong(
        ref T expected,
        T desired,
        MemoryOrder success = MemoryOrder.sequentiallyConsistent,
        MemoryOrder failure = MemoryOrder.sequentiallyConsistent,
    ) shared @trusted
    {
        return compareExchangeAt!false(
            cast(T*)&value_, expected, desired, success, failure,
        );
    }

    static if (isAtomicFetchIntegral!T)
    {
        /// Atomically adds `value` and returns the previous value.
        T fetchAdd(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) @trusted
        {
            return fetchAddAt(&value_, value, order);
        }

        /// Ditto, for a `shared Atomic!T` receiver.
        T fetchAdd(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) shared @trusted
        {
            return fetchAddAt(cast(T*)&value_, value, order);
        }

        /// Atomically subtracts `value` and returns the previous value.
        T fetchSub(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) @trusted
        {
            return fetchSubAt(&value_, value, order);
        }

        /// Ditto, for a `shared Atomic!T` receiver.
        T fetchSub(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) shared @trusted
        {
            return fetchSubAt(cast(T*)&value_, value, order);
        }

        /// Atomically applies bitwise AND and returns the previous value.
        T fetchAnd(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) @trusted
        {
            return fetchBitwiseAt!"&"(&value_, value, order);
        }

        /// Ditto, for a `shared Atomic!T` receiver.
        T fetchAnd(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) shared @trusted
        {
            return fetchBitwiseAt!"&"(cast(T*)&value_, value, order);
        }

        /// Atomically applies bitwise OR and returns the previous value.
        T fetchOr(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) @trusted
        {
            return fetchBitwiseAt!"|"(&value_, value, order);
        }

        /// Ditto, for a `shared Atomic!T` receiver.
        T fetchOr(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) shared @trusted
        {
            return fetchBitwiseAt!"|"(cast(T*)&value_, value, order);
        }

        /// Atomically applies bitwise XOR and returns the previous value.
        T fetchXor(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) @trusted
        {
            return fetchBitwiseAt!"^"(&value_, value, order);
        }

        /// Ditto, for a `shared Atomic!T` receiver.
        T fetchXor(
            T value,
            MemoryOrder order = MemoryOrder.sequentiallyConsistent,
        ) shared @trusted
        {
            return fetchBitwiseAt!"^"(cast(T*)&value_, value, order);
        }
    }

    private static T loadAt(T* address, MemoryOrder order) @trusted
    {
        switch (order)
        {
            case MemoryOrder.relaxed:
                return core.atomic.atomicLoad!(
                    CoreMemoryOrder!(MemoryOrder.relaxed),
                )(*address);
            case MemoryOrder.acquire:
                return core.atomic.atomicLoad!(
                    CoreMemoryOrder!(MemoryOrder.acquire),
                )(*address);
            case MemoryOrder.sequentiallyConsistent:
                return core.atomic.atomicLoad!(
                    CoreMemoryOrder!(MemoryOrder.sequentiallyConsistent),
                )(*address);
            case MemoryOrder.release:
            case MemoryOrder.acquireRelease:
                panic("invalid memory order for Atomic.load");
            default:
                panic("invalid MemoryOrder value for Atomic.load");
        }
    }

    static if (waitSupported)
    {
        private static void validateWaitOrder(MemoryOrder order)
        {
            switch (order)
            {
                case MemoryOrder.relaxed:
                case MemoryOrder.acquire:
                case MemoryOrder.sequentiallyConsistent:
                    return;
                case MemoryOrder.release:
                case MemoryOrder.acquireRelease:
                    panic("invalid memory order for Atomic.wait");
                default:
                    panic("invalid MemoryOrder value for Atomic.wait");
            }
        }

        private static uint waitBits(T value) @trusted
        {
            static assert(T.sizeof == uint.sizeof);
            static if (isAtomicPointer!T)
                return cast(uint) cast(size_t) value;
            else
                return cast(uint) value;
        }

        private static uint* waitAddress(T* address) @trusted
        {
            static assert(T.sizeof == uint.sizeof);
            static assert(T.alignof >= uint.alignof);
            return cast(uint*) address;
        }

        private static void waitAt(
            T* address,
            T oldValue,
            MemoryOrder order,
        ) @trusted
        {
            validateWaitOrder(order);
            const expectedBits = waitBits(oldValue);

            while (loadAt(address, order) == oldValue)
                cast(void) park(waitAddress(address), expectedBits);
        }
    }

    private static void storeAt(T* address, T value, MemoryOrder order) @trusted
    {
        switch (order)
        {
            case MemoryOrder.relaxed:
                core.atomic.atomicStore!(
                    CoreMemoryOrder!(MemoryOrder.relaxed),
                )(*address, value);
                return;
            case MemoryOrder.release:
                core.atomic.atomicStore!(
                    CoreMemoryOrder!(MemoryOrder.release),
                )(*address, value);
                return;
            case MemoryOrder.sequentiallyConsistent:
                core.atomic.atomicStore!(
                    CoreMemoryOrder!(MemoryOrder.sequentiallyConsistent),
                )(*address, value);
                return;
            case MemoryOrder.acquire:
            case MemoryOrder.acquireRelease:
                panic("invalid memory order for Atomic.store");
            default:
                panic("invalid MemoryOrder value for Atomic.store");
        }
    }

    private static T exchangeAt(T* address, T value, MemoryOrder order) @trusted
    {
        MemoryOrder failure = failureOrderForRmw(order);
        T expected = loadAt(address, failure);

        for (;;)
        {
            T previous = expected;
            if (compareExchangeAt!true(
                    address, expected, value, order, failure,
                ))
                return previous;
        }
    }

    private static bool compareExchangeAt(bool weak)(
        T* address,
        ref T expected,
        T desired,
        MemoryOrder success,
        MemoryOrder failure,
    ) @trusted
    {
        if (!validFailureOrder(success, failure))
            panic("invalid compare/exchange memory-order combination");

        switch (success)
        {
            case MemoryOrder.relaxed:
                return compareExchangeCore!(weak,
                    MemoryOrder.relaxed, MemoryOrder.relaxed,
                )(address, expected, desired);

            case MemoryOrder.acquire:
                if (failure == MemoryOrder.relaxed)
                    return compareExchangeCore!(
                        weak,
                        MemoryOrder.acquire, MemoryOrder.relaxed,
                    )(address, expected, desired);
                return compareExchangeCore!(weak,
                    MemoryOrder.acquire, MemoryOrder.acquire,
                )(address, expected, desired);

            case MemoryOrder.release:
                return compareExchangeCore!(weak,
                    MemoryOrder.release, MemoryOrder.relaxed,
                )(address, expected, desired);

            case MemoryOrder.acquireRelease:
                if (failure == MemoryOrder.relaxed)
                    return compareExchangeCore!(weak,
                        MemoryOrder.acquireRelease, MemoryOrder.relaxed,
                    )(address, expected, desired);
                return compareExchangeCore!(weak,
                    MemoryOrder.acquireRelease, MemoryOrder.acquire,
                )(address, expected, desired);

            case MemoryOrder.sequentiallyConsistent:
                if (failure == MemoryOrder.relaxed)
                    return compareExchangeCore!(weak,
                        MemoryOrder.sequentiallyConsistent, MemoryOrder.relaxed,
                    )(address, expected, desired);
                if (failure == MemoryOrder.acquire)
                    return compareExchangeCore!(weak,
                        MemoryOrder.sequentiallyConsistent, MemoryOrder.acquire,
                    )(address, expected, desired);
                return compareExchangeCore!(weak,
                    MemoryOrder.sequentiallyConsistent,
                    MemoryOrder.sequentiallyConsistent,
                )(address, expected, desired);

            default:
                panic("invalid MemoryOrder value for compare/exchange");
        }
    }

    private static bool compareExchangeCore(
        bool weak,
        MemoryOrder success,
        MemoryOrder failure,
    )(
        T* address,
        ref T expected,
        T desired,
    ) @trusted
    {
        static if (weak)
            return core.atomic.casWeak!(
                CoreMemoryOrder!success,
                CoreMemoryOrder!failure,
            )(address, &expected, desired);
        else
            return core.atomic.cas!(
                CoreMemoryOrder!success,
                CoreMemoryOrder!failure,
            )(address, &expected, desired);
    }

    static if (isAtomicFetchIntegral!T)
    {
        private static T fetchAddAt(
            T* address,
            T value,
            MemoryOrder order,
        ) @trusted
        {
            switch (order)
            {
                case MemoryOrder.relaxed:
                    return core.atomic.atomicFetchAdd!(
                        CoreMemoryOrder!(MemoryOrder.relaxed),
                    )(*address, cast(size_t) value);
                case MemoryOrder.acquire:
                    return core.atomic.atomicFetchAdd!(
                        CoreMemoryOrder!(MemoryOrder.acquire),
                    )(*address, cast(size_t) value);
                case MemoryOrder.release:
                    return core.atomic.atomicFetchAdd!(
                        CoreMemoryOrder!(MemoryOrder.release),
                    )(*address, cast(size_t) value);
                case MemoryOrder.acquireRelease:
                    return core.atomic.atomicFetchAdd!(
                        CoreMemoryOrder!(MemoryOrder.acquireRelease),
                    )(*address, cast(size_t) value);
                case MemoryOrder.sequentiallyConsistent:
                    return core.atomic.atomicFetchAdd!(
                        CoreMemoryOrder!(MemoryOrder.sequentiallyConsistent),
                    )(*address, cast(size_t) value);
                default:
                    panic("invalid MemoryOrder value for Atomic.fetchAdd");
            }
        }

        private static T fetchSubAt(
            T* address,
            T value,
            MemoryOrder order,
        ) @trusted
        {
            switch (order)
            {
                case MemoryOrder.relaxed:
                    return core.atomic.atomicFetchSub!(
                        CoreMemoryOrder!(MemoryOrder.relaxed),
                    )(*address, cast(size_t) value);
                case MemoryOrder.acquire:
                    return core.atomic.atomicFetchSub!(
                        CoreMemoryOrder!(MemoryOrder.acquire),
                    )(*address, cast(size_t) value);
                case MemoryOrder.release:
                    return core.atomic.atomicFetchSub!(
                        CoreMemoryOrder!(MemoryOrder.release),
                    )(*address, cast(size_t) value);
                case MemoryOrder.acquireRelease:
                    return core.atomic.atomicFetchSub!(
                        CoreMemoryOrder!(MemoryOrder.acquireRelease),
                    )(*address, cast(size_t) value);
                case MemoryOrder.sequentiallyConsistent:
                    return core.atomic.atomicFetchSub!(
                        CoreMemoryOrder!(MemoryOrder.sequentiallyConsistent),
                    )(*address, cast(size_t) value);
                default:
                    panic("invalid MemoryOrder value for Atomic.fetchSub");
            }
        }

        private static T fetchBitwiseAt(string operator)(
            T* address,
            T value,
            MemoryOrder order,
        ) @trusted
        {
            MemoryOrder failure = failureOrderForRmw(order);
            T expected = loadAt(address, failure);

            for (;;)
            {
                static if (operator == "&")
                    T desired = cast(T)(expected & value);
                else static if (operator == "|")
                    T desired = cast(T)(expected | value);
                else static if (operator == "^")
                    T desired = cast(T)(expected ^ value);
                else
                    static assert(false, "unsupported atomic bitwise operator");
                T previous = expected;
                if (compareExchangeAt!true(
                        address, expected, desired, order, failure,
                    ))
                    return previous;
            }
        }
    }
}

/// A minimal atomic boolean flag.
///
/// `AtomicFlag.init` is clear. `testAndSet` returns the previous flag value.
struct AtomicFlag
{
nothrow @nogc:
    @disable this(this);

    private Atomic!ubyte state_;

    bool testAndSet(
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) @safe
    {
        return state_.exchange(1, order) != 0;
    }

    bool testAndSet(
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) shared @safe
    {
        return state_.exchange(1, order) != 0;
    }

    void clear(
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) @safe
    {
        state_.store(0, order);
    }

    void clear(
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    ) shared @safe
    {
        state_.store(0, order);
    }
}

/// Issues a thread fence with the requested C/C++-style ordering.
void atomicThreadFence(MemoryOrder order) @trusted
{
    switch (order)
    {
        case MemoryOrder.relaxed:
            core.atomic.atomicFence!(
                CoreMemoryOrder!(MemoryOrder.relaxed),
            )();
            return;
        case MemoryOrder.acquire:
            core.atomic.atomicFence!(
                CoreMemoryOrder!(MemoryOrder.acquire),
            )();
            return;
        case MemoryOrder.release:
            core.atomic.atomicFence!(
                CoreMemoryOrder!(MemoryOrder.release),
            )();
            return;
        case MemoryOrder.acquireRelease:
            core.atomic.atomicFence!(
                CoreMemoryOrder!(MemoryOrder.acquireRelease),
            )();
            return;
        case MemoryOrder.sequentiallyConsistent:
            core.atomic.atomicFence!(
                CoreMemoryOrder!(MemoryOrder.sequentiallyConsistent),
            )();
            return;
        default:
            panic("invalid MemoryOrder value for atomicThreadFence");
    }
}

private enum AtomicTestEnum : uint
{
    zero,
    one,
    two,
}

static assert(__traits(compiles, Atomic!byte.init));
static assert(__traits(compiles, Atomic!ubyte.init));
static assert(__traits(compiles, Atomic!short.init));
static assert(__traits(compiles, Atomic!ushort.init));
static assert(__traits(compiles, Atomic!int.init));
static assert(__traits(compiles, Atomic!uint.init));
static assert(__traits(compiles, Atomic!long.init));
static assert(__traits(compiles, Atomic!ulong.init));
static assert(__traits(compiles, Atomic!bool.init));
static assert(__traits(compiles, Atomic!char.init));
static assert(__traits(compiles, Atomic!wchar.init));
static assert(__traits(compiles, Atomic!dchar.init));
static assert(__traits(compiles, Atomic!AtomicTestEnum.init));
static assert(__traits(compiles, Atomic!(int*).init));
static assert(!__traits(compiles, Atomic!float.init));
static assert(!__traits(compiles, Atomic!double.init));
static assert(!__traits(compiles, Atomic!(int[]).init));
static assert(!__traits(compiles, Atomic!(const int).init));
static assert(!__traits(compiles, Atomic!(immutable int).init));
static assert(!__traits(compiles, Atomic!(shared int).init));
static assert(Atomic!long.alignof >= long.alignof);
static assert(Atomic!(int*).alignof >= (int*).alignof);
static assert(Atomic!uint.waitSupported == parkingSupported);
static assert(Atomic!int.waitSupported == parkingSupported);
static assert(Atomic!dchar.waitSupported == parkingSupported);
static assert(Atomic!AtomicTestEnum.waitSupported == parkingSupported);
static assert(!Atomic!ushort.waitSupported);
static assert(!Atomic!ulong.waitSupported);
static if (parkingSupported)
{
    static assert(__traits(hasMember, Atomic!uint, "wait"));
    static assert(__traits(hasMember, Atomic!uint, "notifyOne"));
    static assert(__traits(hasMember, Atomic!uint, "notifyAll"));
    static assert(__traits(compiles, () @safe nothrow @nogc {
            shared Atomic!uint value;
            value.wait(0, MemoryOrder.acquire);
            value.notifyOne();
            value.notifyAll();
        }));
}
else
{
    static assert(!__traits(hasMember, Atomic!uint, "wait"));
    static assert(!__traits(hasMember, Atomic!uint, "notifyOne"));
    static assert(!__traits(hasMember, Atomic!uint, "notifyAll"));
}
static assert(!__traits(hasMember, Atomic!ushort, "wait"));
static assert(!__traits(hasMember, Atomic!ulong, "wait"));
static assert(__traits(hasMember, Atomic!int, "fetchAdd"));
static assert(!__traits(hasMember, Atomic!bool, "fetchAdd"));
static assert(!__traits(hasMember, Atomic!AtomicTestEnum, "fetchAdd"));
static assert(!__traits(hasMember, Atomic!(int*), "fetchAdd"));
static assert(!__traits(compiles, () { Atomic!int source; Atomic!int copy = source; }));
static assert(__traits(compiles, (shared Atomic!int* value) {
        value.store(1, MemoryOrder.release);
        return value.load(MemoryOrder.acquire);
    }));

unittest
{
    Atomic!int value;
    assert(value.load() == 0);

    auto initialized = Atomic!int(7);
    assert(initialized.load() == 7);

    initialized.store(9, MemoryOrder.relaxed);
    assert(initialized.load(MemoryOrder.relaxed) == 9);
    assert(initialized.exchange(10, MemoryOrder.relaxed) == 9);
    assert(initialized.exchange(11, MemoryOrder.release) == 10);
    assert(initialized.exchange(11, MemoryOrder.acquireRelease) == 11);
    assert(initialized.load() == 11);

    int expected = 11;
    assert(initialized.compareExchangeStrong(
            expected,
            13,
            MemoryOrder.acquireRelease,
            MemoryOrder.acquire,
    ));
    assert(expected == 11);
    assert(initialized.load() == 13);

    expected = 99;
    assert(!initialized.compareExchangeStrong(
            expected,
            17,
            MemoryOrder.release,
            MemoryOrder.relaxed,
    ));
    assert(expected == 13);
    assert(initialized.load() == 13);

    expected = 13;
    while (!initialized.compareExchangeWeak(
            expected,
            17,
            MemoryOrder.sequentiallyConsistent,
            MemoryOrder.acquire,
        ))
    {
        assert(expected == 13);
    }
    assert(initialized.load() == 17);

    assert(initialized.fetchAdd(5, MemoryOrder.relaxed) == 17);
    assert(initialized.load() == 22);
    assert(initialized.fetchSub(2, MemoryOrder.acquire) == 22);
    assert(initialized.load() == 20);
    assert(initialized.fetchOr(0b0011, MemoryOrder.release) == 20);
    assert(initialized.load() == 23);
    assert(initialized.fetchAnd(0b11110, MemoryOrder.acquireRelease) == 23);
    assert(initialized.load() == 22);
    assert(initialized.fetchXor(0b0110) == 22);
    assert(initialized.load() == 16);

    auto signedValue = Atomic!int(-4);
    assert(signedValue.fetchAdd(-3) == -4);
    assert(signedValue.load() == -7);
    assert(signedValue.fetchSub(-2) == -7);
    assert(signedValue.load() == -5);

    Atomic!AtomicTestEnum enumValue;
    assert(enumValue.load() == AtomicTestEnum.zero);
    enumValue.store(AtomicTestEnum.one, MemoryOrder.release);
    assert(enumValue.exchange(AtomicTestEnum.two, MemoryOrder.acquire) ==
            AtomicTestEnum.one);
    AtomicTestEnum enumExpected = AtomicTestEnum.two;
    assert(enumValue.compareExchangeStrong(
            enumExpected,
            AtomicTestEnum.one,
            MemoryOrder.acquire,
            MemoryOrder.acquire,
    ));

    int first = 1;
    int second = 2;
    Atomic!(int*) pointer;
    assert(pointer.load() is null);
    pointer.store(&first, MemoryOrder.release);
    assert(pointer.load(MemoryOrder.acquire) == &first);
    assert(pointer.exchange(&second) == &first);
    int* pointerExpected = &first;
    assert(!pointer.compareExchangeStrong(pointerExpected, &first));
    assert(pointerExpected == &second);

    shared Atomic!uint sharedValue;
    sharedValue.store(41, MemoryOrder.release);
    assert(sharedValue.load(MemoryOrder.acquire) == 41);
    assert(sharedValue.fetchAdd(1) == 41);
    assert(sharedValue.load() == 42);

    AtomicFlag flag;
    assert(!flag.testAndSet(MemoryOrder.acquire));
    assert(flag.testAndSet(MemoryOrder.relaxed));
    flag.clear(MemoryOrder.release);
    assert(!flag.testAndSet());

    shared AtomicFlag sharedFlag;
    assert(!sharedFlag.testAndSet());
    sharedFlag.clear();
    assert(!sharedFlag.testAndSet());

    atomicThreadFence(MemoryOrder.relaxed);
    atomicThreadFence(MemoryOrder.acquire);
    atomicThreadFence(MemoryOrder.release);
    atomicThreadFence(MemoryOrder.acquireRelease);
    atomicThreadFence(MemoryOrder.sequentiallyConsistent);
}

unittest
{
    auto value = Atomic!uint(7);

    uint expected = 99;
    assert(!value.compareExchangeStrong(
            expected, 8, MemoryOrder.relaxed, MemoryOrder.relaxed,
    ));
    assert(expected == 7);

    expected = 99;
    assert(!value.compareExchangeStrong(
            expected, 8, MemoryOrder.acquire, MemoryOrder.relaxed,
    ));
    expected = 99;
    assert(!value.compareExchangeStrong(
            expected, 8, MemoryOrder.acquire, MemoryOrder.acquire,
    ));
    expected = 99;
    assert(!value.compareExchangeStrong(
            expected, 8, MemoryOrder.release, MemoryOrder.relaxed,
    ));
    expected = 99;
    assert(!value.compareExchangeStrong(
            expected, 8, MemoryOrder.acquireRelease, MemoryOrder.relaxed,
    ));
    expected = 99;
    assert(!value.compareExchangeStrong(
            expected, 8, MemoryOrder.acquireRelease, MemoryOrder.acquire,
    ));
    expected = 99;
    assert(!value.compareExchangeStrong(
            expected,
            8,
            MemoryOrder.sequentiallyConsistent,
            MemoryOrder.relaxed,
    ));
    expected = 99;
    assert(!value.compareExchangeStrong(
            expected,
            8,
            MemoryOrder.sequentiallyConsistent,
            MemoryOrder.acquire,
    ));
    expected = 99;
    assert(!value.compareExchangeStrong(
            expected,
            8,
            MemoryOrder.sequentiallyConsistent,
            MemoryOrder.sequentiallyConsistent,
    ));
}
