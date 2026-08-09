module tests.threading_unsupported_tests;

import core.stdc.stdlib : free, malloc;
import xtb.core.memory : Allocator;
import xtb.threading;
import condVarModule = xtb.threading.cond_var;
import mutexModule = xtb.threading.mutex;
import parkingModule = xtb.threading.internal.parking;
import semaphoreModule = xtb.threading.semaphore;
import startLatchModule = xtb.threading.internal.start_latch;

static assert(!Atomic!uint.waitSupported);
static assert(!__traits(hasMember, Atomic!uint, "wait"));
static assert(!__traits(hasMember, Atomic!uint, "notifyOne"));
static assert(!__traits(hasMember, Atomic!uint, "notifyAll"));

private int worker(void* context) nothrow @nogc
{
    return 0;
}

private int typedWorker(int value) nothrow @nogc
{
    return value;
}

private struct TrackingAllocator
{
    private Allocator allocator_;
    size_t allocations;
    size_t deallocations;

    static TrackingAllocator create() nothrow @nogc
    {
        TrackingAllocator result;
        result.allocator_ = &trackingAllocatorProcedure;
        return result;
    }

    Allocator* allocator() return nothrow @nogc
    {
        return &allocator_;
    }
}

static assert(TrackingAllocator.allocator_.offsetof == 0);

private extern (C) void* trackingAllocatorProcedure(
    void* opaque,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) nothrow @nogc
{
    TrackingAllocator* tracker = cast(TrackingAllocator*) opaque;
    if (newSize == 0)
    {
        ++tracker.deallocations;
        free(oldPointer);
        return null;
    }
    if (oldPointer !is null || oldSize != 0 || alignment > 16)
        return null;
    ++tracker.allocations;
    return malloc(newSize);
}

extern (C) int main() nothrow @nogc
{
    static foreach (testFunction; __traits(getUnitTests, mutexModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, condVarModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, semaphoreModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, parkingModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, startLatchModule))
        testFunction();

    auto started = Thread.startRaw(&worker);
    if (!started.isErr)
        return 1;
    if (started.unwrapError().kind != ThreadStartErrorKind.unsupported)
        return 2;

    auto typedZeroAllocStarted = Thread.start!typedWorker(42);
    if (!typedZeroAllocStarted.isErr)
        return 13;
    if (typedZeroAllocStarted.unwrapError().kind !=
        ThreadStartErrorKind.unsupported)
        return 14;

    TrackingAllocator rawTracker = TrackingAllocator.create();
    auto rawAllocStarted = Thread.startRawAlloc(rawTracker.allocator, &worker);
    if (!rawAllocStarted.isErr)
        return 7;
    const rawAllocError = rawAllocStarted.unwrapError();
    if (rawAllocError.kind != ThreadStartAllocErrorKind.threadStartFailed ||
        rawAllocError.threadStartError.kind != ThreadStartErrorKind.unsupported)
        return 8;
    if (rawTracker.allocations != 1 || rawTracker.deallocations != 1)
        return 9;

    TrackingAllocator typedTracker = TrackingAllocator.create();
    auto typedStarted = Thread.startAlloc!typedWorker(typedTracker.allocator, 42);
    if (!typedStarted.isErr)
        return 10;
    const typedError = typedStarted.unwrapError();
    if (typedError.kind != ThreadStartAllocErrorKind.threadStartFailed ||
        typedError.threadStartError.kind != ThreadStartErrorKind.unsupported)
        return 11;
    if (typedTracker.allocations != 1 || typedTracker.deallocations != 1)
        return 12;

    auto named = setCurrentThreadName("unsupported");
    if (!named.isErr)
        return 3;
    if (named.unwrapError().kind != ThreadNameErrorKind.unsupported)
        return 4;

    if (currentThreadId() != ThreadId.init)
        return 5;
    if (hardwareConcurrency() != 0)
        return 6;

    cpuRelax();
    yieldThread();
    return 0;
}
