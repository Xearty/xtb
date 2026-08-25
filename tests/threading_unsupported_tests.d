module tests.threading_unsupported_tests;

import core.stdc.stdlib : free, malloc;
import xtb.core.memory : Allocator;
import xtb.sync;
import xtb.thread;
import barrierModule = xtb.sync.barrier;
import condVarModule = xtb.sync.cond_var;
import generationWaitModule = xtb.sync.internal.generation_wait;
import latchModule = xtb.sync.latch;
import lockGuardModule = xtb.sync.lock_guard;
import mutexModule = xtb.sync.mutex;
import onceModule = xtb.sync.once;
import onceCellModule = xtb.sync.once_cell;
import parkingModule = xtb.sync.internal.parking;
import rwLockModule = xtb.sync.rw_lock;
import semaphoreModule = xtb.sync.semaphore;
import spawnModule = xtb.thread.spawn;
import startLatchModule = xtb.thread.internal.start_latch;
import threadScopeModule = xtb.thread.thread_scope;
import waitGroupModule = xtb.sync.wait_group;

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

private void scopedWorker(int* value) nothrow @nogc
{
    *value = 42;
}

private struct UnsupportedScopeContext
{
    bool sawUnsupported;
    int value;
}

private void unsupportedScopeBody(
    scope ref ThreadScope scope_,
    scope UnsupportedScopeContext* context,
) nothrow @nogc
{
    auto started = scope_.spawn!scopedWorker(&context.value);
    if (started.isErr)
    {
        const error = started.unwrapError();
        context.sawUnsupported =
            error.kind == SpawnErrorKind.threadStartFailed &&
            error.threadStartError.kind == ThreadStartErrorKind.unsupported;
    }
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
    static foreach (testFunction; __traits(getUnitTests, barrierModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, lockGuardModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, mutexModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, condVarModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, semaphoreModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, spawnModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, latchModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, onceModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, onceCellModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, parkingModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, rwLockModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, generationWaitModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, startLatchModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, threadScopeModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, waitGroupModule))
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

    TrackingAllocator spawnTracker = TrackingAllocator.create();
    auto spawnStarted = spawn!typedWorker(spawnTracker.allocator, 42);
    if (!spawnStarted.isErr)
        return 15;
    const spawnError = spawnStarted.unwrapError();
    if (spawnError.kind != SpawnErrorKind.threadStartFailed ||
        spawnError.threadStartError.kind != ThreadStartErrorKind.unsupported)
        return 16;
    if (spawnTracker.allocations != 1 || spawnTracker.deallocations != 1)
        return 17;

    TrackingAllocator scopeTracker = TrackingAllocator.create();
    UnsupportedScopeContext scopeContext;
    threadScope!unsupportedScopeBody(scopeTracker.allocator, &scopeContext);
    if (!scopeContext.sawUnsupported || scopeContext.value != 0 ||
        scopeTracker.allocations != 1 || scopeTracker.deallocations != 1)
        return 18;

    TrackingAllocator inlineScopeTracker = TrackingAllocator.create();
    bool inlineUnsupported;
    int inlineValue;
    threadScope(
        inlineScopeTracker.allocator,
        (scope ref ThreadScope scope_) nothrow @nogc {
        auto started = scope_.spawn!scopedWorker(&inlineValue);
        if (started.isErr)
        {
            const error = started.unwrapError();
            inlineUnsupported =
                error.kind == SpawnErrorKind.threadStartFailed &&
                error.threadStartError.kind ==
                ThreadStartErrorKind.unsupported;
        }
    },
    );
    if (!inlineUnsupported || inlineValue != 0 ||
        inlineScopeTracker.allocations != 1 ||
        inlineScopeTracker.deallocations != 1)
        return 19;

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
