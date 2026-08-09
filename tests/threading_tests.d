module tests.threading_tests;

import core.lifetime : move;
import core.stdc.stdlib : free, malloc;
import xtb.core.memory : Allocator;
import xtb.core.allocators.malloc : mallocAllocator;
import xtb.core.panic : panic;
import xtb.core.result : Result, ResultReturns;
import xtb.threading;
import atomicModule = xtb.threading.atomic;
import barrierModule = xtb.threading.barrier;
import condVarModule = xtb.threading.cond_var;
import countdownModule = xtb.threading.internal.countdown;
import generationWaitModule = xtb.threading.internal.generation_wait;
import latchModule = xtb.threading.latch;
import lockGuardModule = xtb.threading.lock_guard;
import mutexModule = xtb.threading.mutex;
import onceModule = xtb.threading.once;
import onceCellModule = xtb.threading.once_cell;
import parkingModule = xtb.threading.internal.parking;
import rwLockModule = xtb.threading.rw_lock;
import semaphoreModule = xtb.threading.semaphore;
import spawnModule = xtb.threading.spawn;
import startLatchModule = xtb.threading.internal.start_latch;
import spinWaitModule = xtb.threading.spin_wait;
import threadScopeModule = xtb.threading.thread_scope;
import waitGroupModule = xtb.threading.wait_group;

version (linux) import linuxBackendModule = xtb.threading.internal.thread_linux;

version (linux) import core.sys.linux.sched : cpu_set_t, sched_getaffinity;

version (Posix)
{
    import core.stdc.signal : SIGABRT;
    import core.sys.posix.pthread : pthread_attr_destroy,
        pthread_attr_getstacksize,
        pthread_attr_t,
        pthread_create,
        pthread_join,
        pthread_self,
        pthread_t;
    import core.sys.posix.sys.wait : waitpid;
    import core.sys.posix.unistd : _exit, fork;
}

version (linux) private extern (C) pragma(mangle, "pthread_getattr_np")
int nativePthreadGetAttr(pthread_t thread, pthread_attr_t* attributes) nothrow @nogc;

version (linux) private extern (C) pragma(mangle, "pthread_getname_np")
int nativePthreadGetName(pthread_t thread, char* name, size_t length) nothrow @nogc;

version (Posix) private struct IncrementContext
{
    Atomic!uint* counter;
    uint iterations;
}

version (Posix) private extern (C) void* incrementWorker(void* opaque)
nothrow @nogc
{
    IncrementContext* context = cast(IncrementContext*) opaque;
    foreach (_; 0 .. context.iterations)
        context.counter.fetchAdd(1, MemoryOrder.relaxed);
    return null;
}

version (Posix) private bool stressFetchAdd() nothrow @nogc
{
    enum workerCount = 8;
    enum iterations = 100_000;

    Atomic!uint counter;
    IncrementContext context = IncrementContext(&counter, iterations);
    pthread_t[workerCount] workers;

    foreach (ref worker; workers)
        if (pthread_create(&worker, null, &incrementWorker, &context) != 0)
            return false;

    foreach (worker; workers)
        if (pthread_join(worker, null) != 0)
            return false;

    return counter.load() == workerCount * iterations;
}

version (Posix) private struct PublicationContext
{
    Atomic!uint ready;
    int payload;
    int observed;
}

version (Posix) private extern (C) void* publicationWriter(void* opaque)
nothrow @nogc
{
    PublicationContext* context = cast(PublicationContext*) opaque;
    context.payload = 0x5a5a_1234;
    context.ready.store(1, MemoryOrder.release);
    return null;
}

version (Posix) private extern (C) void* publicationReader(void* opaque)
nothrow @nogc
{
    PublicationContext* context = cast(PublicationContext*) opaque;
    while (context.ready.load(MemoryOrder.acquire) == 0)
    {
    }
    context.observed = context.payload;
    return null;
}

version (Posix) private bool releaseAcquirePublishes() nothrow @nogc
{
    PublicationContext context;
    pthread_t writer;
    pthread_t reader;

    if (pthread_create(&reader, null, &publicationReader, &context) != 0)
        return false;
    if (pthread_create(&writer, null, &publicationWriter, &context) != 0)
        return false;
    if (pthread_join(writer, null) != 0)
        return false;
    if (pthread_join(reader, null) != 0)
        return false;

    return context.observed == 0x5a5a_1234;
}

version (linux) private bool waitForAtomicAtLeast(
    Atomic!uint* value,
    uint target,
) nothrow @nogc
{
    foreach (_; 0 .. 1_000_000)
    {
        if (value.load(MemoryOrder.acquire) >= target)
            return true;
        yieldThread();
    }
    return false;
}

version (linux) private struct AtomicWaitPublicationContext
{
    Atomic!uint state;
    Atomic!uint entered;
    Atomic!uint completed;
    int payload;
    int observed;
}

version (linux) private extern (C) void* atomicWaitPublicationWorker(
    void* opaque,
) nothrow @nogc
{
    AtomicWaitPublicationContext* context =
        cast(AtomicWaitPublicationContext*) opaque;
    context.entered.store(1, MemoryOrder.release);
    context.state.wait(0, MemoryOrder.acquire);
    context.observed = context.payload;
    context.completed.store(1, MemoryOrder.release);
    return null;
}

version (linux) private bool atomicWaitPublishesAndRechecks() nothrow @nogc
{
    AtomicWaitPublicationContext context;
    pthread_t worker;
    if (pthread_create(
            &worker,
            null,
            &atomicWaitPublicationWorker,
            &context,
        ) != 0)
        return false;

    if (!waitForAtomicAtLeast(&context.entered, 1))
    {
        context.state.store(1, MemoryOrder.release);
        context.state.notifyAll();
        cast(void) pthread_join(worker, null);
        return false;
    }

    // Notifications without a value change may wake the futex internally, but
    // Atomic.wait must re-check and remain blocked while the value is still 0.
    foreach (_; 0 .. 256)
    {
        context.state.notifyOne();
        yieldThread();
    }
    if (context.completed.load(MemoryOrder.acquire) != 0)
    {
        context.state.store(1, MemoryOrder.release);
        context.state.notifyAll();
        cast(void) pthread_join(worker, null);
        return false;
    }

    context.payload = 0x3a4b_5c6d;
    context.state.store(1, MemoryOrder.release);
    context.state.notifyOne();
    if (pthread_join(worker, null) != 0)
        return false;
    return context.completed.load(MemoryOrder.acquire) == 1 &&
        context.observed == context.payload;
}

version (linux) private struct AtomicWaitGenerationContext
{
    Atomic!uint generation;
    Atomic!uint completedGeneration;
    Atomic!uint failed;
    uint rounds;
}

version (linux) private extern (C) void* atomicWaitGenerationWorker(
    void* opaque,
) nothrow @nogc
{
    AtomicWaitGenerationContext* context =
        cast(AtomicWaitGenerationContext*) opaque;
    foreach (round; 0 .. context.rounds)
    {
        context.generation.wait(round, MemoryOrder.acquire);
        if (context.generation.load(MemoryOrder.relaxed) != round + 1)
        {
            context.failed.store(1, MemoryOrder.release);
            return null;
        }
        context.completedGeneration.store(round + 1, MemoryOrder.release);
    }
    return null;
}

version (linux) private bool atomicWaitWakeBeforeParkStress() nothrow @nogc
{
    enum rounds = 2_048;
    AtomicWaitGenerationContext context;
    context.rounds = rounds;

    pthread_t worker;
    if (pthread_create(
            &worker,
            null,
            &atomicWaitGenerationWorker,
            &context,
        ) != 0)
        return false;

    bool succeeded = true;
    foreach (generation; 1 .. rounds + 1)
    {
        context.generation.store(generation, MemoryOrder.release);
        context.generation.notifyOne();
        if (!waitForAtomicAtLeast(&context.completedGeneration, generation))
        {
            succeeded = false;
            break;
        }
    }

    if (!succeeded)
    {
        context.generation.store(uint.max, MemoryOrder.release);
        context.generation.notifyAll();
    }

    if (pthread_join(worker, null) != 0)
        return false;
    return succeeded && context.failed.load(MemoryOrder.acquire) == 0 &&
        context.completedGeneration.load(MemoryOrder.acquire) == rounds;
}

version (linux) private struct AtomicWaitAllContext
{
    Atomic!uint state;
    Atomic!uint ready;
    Atomic!uint completed;
}

version (linux) private extern (C) void* atomicWaitAllWorker(
    void* opaque,
) nothrow @nogc
{
    AtomicWaitAllContext* context = cast(AtomicWaitAllContext*) opaque;
    context.ready.fetchAdd(1, MemoryOrder.release);
    context.state.wait(0, MemoryOrder.acquire);
    context.completed.fetchAdd(1, MemoryOrder.release);
    return null;
}

version (linux) private bool atomicNotifyAllReleasesWaiters() nothrow @nogc
{
    enum workerCount = 8;
    AtomicWaitAllContext context;
    pthread_t[workerCount] workers;
    uint started;

    foreach (ref worker; workers)
    {
        if (pthread_create(&worker, null, &atomicWaitAllWorker, &context) != 0)
            break;
        ++started;
    }

    if (started != workerCount ||
        !waitForAtomicAtLeast(&context.ready, workerCount))
    {
        context.state.store(1, MemoryOrder.release);
        context.state.notifyAll();
        foreach (index; 0 .. started)
            cast(void) pthread_join(workers[index], null);
        return false;
    }

    context.state.store(1, MemoryOrder.release);
    context.state.notifyAll();

    bool joined = true;
    foreach (worker; workers)
        if (pthread_join(worker, null) != 0)
            joined = false;
    return joined &&
        context.completed.load(MemoryOrder.acquire) == workerCount;
}

version (linux) private bool atomicWaitImmediateOrders() nothrow @nogc
{
    Atomic!uint value = Atomic!uint(1);
    value.wait(0, MemoryOrder.relaxed);
    value.wait(0, MemoryOrder.acquire);
    value.wait(0, MemoryOrder.sequentiallyConsistent);
    return value.load(MemoryOrder.relaxed) == 1;
}

version (linux) private struct SignedAtomicWaitContext
{
    Atomic!int state;
    Atomic!uint entered;
    Atomic!uint completed;
}

version (linux) private extern (C) void* signedAtomicWaitWorker(
    void* opaque,
) nothrow @nogc
{
    SignedAtomicWaitContext* context = cast(SignedAtomicWaitContext*) opaque;
    context.entered.store(1, MemoryOrder.release);
    context.state.wait(-1, MemoryOrder.acquire);
    context.completed.store(1, MemoryOrder.release);
    return null;
}

version (linux) private bool signedAtomicWaitUsesValueBits() nothrow @nogc
{
    SignedAtomicWaitContext context;
    context.state.store(-1, MemoryOrder.relaxed);

    pthread_t worker;
    if (pthread_create(&worker, null, &signedAtomicWaitWorker, &context) != 0)
        return false;
    if (!waitForAtomicAtLeast(&context.entered, 1))
    {
        context.state.store(-2, MemoryOrder.release);
        context.state.notifyAll();
        cast(void) pthread_join(worker, null);
        return false;
    }

    context.state.store(-2, MemoryOrder.release);
    context.state.notifyOne();
    if (pthread_join(worker, null) != 0)
        return false;
    return context.completed.load(MemoryOrder.acquire) == 1;
}

version (linux) private int nullContextRawWorker(void* context) nothrow @nogc
{
    return context is null ? 17 : -1;
}

version (linux) private int safeSurfaceWorker(void*) nothrow @nogc
{
    return 0;
}

version (linux) private void safeThreadSurface(ref Thread thread) nothrow @nogc @safe
{
    cast(void) thread.joinable();
    cast(void) thread.id();
    cast(void) thread.setName("xtb-safe");
    cast(void) currentThreadId();
    yieldThread();
    cast(void) hardwareConcurrency();
    cast(void) setCurrentThreadName("xtb-safe");
}

version (linux) private int safeJoin(ref Thread thread) nothrow @nogc @safe
{
    return thread.join();
}

version (linux) private void safeDetach(ref Thread thread) nothrow @nogc @safe
{
    thread.detach();
}

version (linux) private int safeJoinHandle(ref JoinHandle!int handle)
nothrow @nogc @safe
{
    cast(void) handle.joinable();
    return handle.join();
}

version (linux) private void safeVoidJoinHandle(ref JoinHandle!void handle)
nothrow @nogc @safe
{
    cast(void) handle.joinable();
    handle.join();
}

version (linux) static assert(!__traits(compiles, () nothrow @nogc @safe {
        Thread.startRaw(&safeSurfaceWorker);
    }));

version (linux) private int statusRawWorker(void* context) nothrow @nogc
{
    return *cast(int*) context;
}

version (linux) private int mutateRawContext(void* context) nothrow @nogc
{
    int* value = cast(int*) context;
    *value += 5;
    return -13;
}

version (linux) private struct StartTrackingAllocator
{
    private Allocator allocator_;
    Atomic!uint allocationCalls;
    Atomic!uint deallocationCalls;
    bool failAllocation;
    ThreadId allocationThread;
    ThreadId deallocationThread;

    static StartTrackingAllocator create(bool failAllocation = false)
    nothrow @nogc
    {
        StartTrackingAllocator result;
        result.allocator_ = &startTrackingAllocatorProcedure;
        result.failAllocation = failAllocation;
        return result;
    }

    Allocator* allocator() return nothrow @nogc
    {
        return &allocator_;
    }
}

version (linux) static assert(StartTrackingAllocator.allocator_.offsetof == 0);

version (linux) private extern (C) void* startTrackingAllocatorProcedure(
    void* opaque,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) nothrow @nogc
{
    StartTrackingAllocator* tracker = cast(StartTrackingAllocator*) opaque;
    if (newSize == 0)
    {
        tracker.deallocationThread = currentThreadId();
        tracker.deallocationCalls.fetchAdd(1, MemoryOrder.release);
        free(oldPointer);
        return null;
    }

    tracker.allocationThread = currentThreadId();
    tracker.allocationCalls.fetchAdd(1, MemoryOrder.relaxed);
    if (tracker.failAllocation || oldPointer !is null || oldSize != 0 ||
        alignment > 16)
        return null;
    return malloc(newSize);
}

version (linux) private struct AllocReleaseContext
{
    StartTrackingAllocator* tracker;
    Atomic!uint workerEntered;
}

version (linux) private int allocatedRawWorker(void* opaque) nothrow @nogc
{
    AllocReleaseContext* context = cast(AllocReleaseContext*) opaque;
    const released = context.tracker.deallocationCalls.load(MemoryOrder.acquire);
    const releasedHere = context.tracker.deallocationThread == currentThreadId();
    context.workerEntered.store(1, MemoryOrder.release);
    return released == 1 && releasedHere ? 37 : -37;
}

version (linux) private int allocatedTypedWorker(
    StartTrackingAllocator* tracker,
    int left,
    int right,
) nothrow @nogc
{
    const released = tracker.deallocationCalls.load(MemoryOrder.acquire);
    const releasedHere = tracker.deallocationThread == currentThreadId();
    return released == 1 && releasedHere ? left + right : -1;
}

version (linux) private void allocatedVoidWorker(Atomic!uint* entered)
nothrow @nogc
{
    entered.store(1, MemoryOrder.release);
}

version (linux) private int zeroArgTypedWorker() nothrow @nogc
{
    return 31;
}

version (linux) private int constValueWorker(const int value) nothrow @nogc
{
    return value;
}

version (linux) private int sliceValueWorker(const(int)[] values) nothrow @nogc
{
    int total;
    foreach (value; values)
        total += value;
    return total;
}

version (linux) align(64) private struct OverAlignedCapture
{
    int value;
}

version (linux) private int overAlignedWorker(OverAlignedCapture capture)
nothrow @nogc
{
    return capture.value;
}

version (linux) private struct MoveOnlyCapture
{
    Atomic!uint* destructions;
    int value;

    @disable this(this);

    ~this() nothrow @nogc
    {
        if (destructions !is null)
            destructions.fetchAdd(1, MemoryOrder.relaxed);
    }
}

version (linux) private int moveOnlyWorker(MoveOnlyCapture capture)
nothrow @nogc
{
    return capture.value;
}

version (linux) private struct ConversionSource
{
    ThreadId* convertedOn;
    int value;
}

version (linux) private struct ConvertedCapture
{
    int value;

    this(ConversionSource source) nothrow @nogc
    {
        *source.convertedOn = currentThreadId();
        value = source.value;
    }
}

version (linux) private int convertedCaptureWorker(
    ConvertedCapture capture,
    ThreadId* workerThread,
) nothrow @nogc
{
    *workerThread = currentThreadId();
    return capture.value;
}

version (linux) private void refTypedWorker(ref int) nothrow @nogc
{
}

version (linux) private void outTypedWorker(out int) nothrow @nogc
{
}

version (linux) private void lazyTypedWorker(lazy int) nothrow @nogc
{
}

version (linux) private void inTypedWorker(in int) nothrow @nogc
{
}

version (linux) private int sharedTypedWorker(shared int value) nothrow @nogc
{
    return value;
}

version (linux) private long wrongReturnTypedWorker(int value) nothrow @nogc
{
    return value;
}

version (linux) private ref int refReturnTypedWorker() nothrow @nogc
{
    static int value;
    return value;
}

version (linux) private int missingNothrowTypedWorker(int value) @nogc
{
    return value;
}

version (linux) private int missingNogcTypedWorker(int value) nothrow
{
    return value;
}

version (linux) private struct MemberTypedWorker
{
    int run(int value) nothrow @nogc
    {
        return value;
    }
}

version (linux) private struct StaticMemberTypedWorker
{
    static int run(int value) nothrow @nogc
    {
        return value;
    }
}

version (linux) private void nestedTypedWorkerCompileCheck() nothrow @nogc @system
{
    int captured;
    int nested(int value) nothrow @nogc
    {
        return value + captured;
    }

    static assert(!__traits(compiles, Thread.start!nested(1)));
    static assert(!__traits(compiles,
            Thread.startAlloc!nested(mallocAllocator(), 1)));
}

version (linux) static assert(!__traits(compiles, Thread.start!refTypedWorker(1)));
version (linux) static assert(!__traits(compiles, Thread.start!outTypedWorker(1)));
version (linux) static assert(!__traits(compiles, Thread.start!lazyTypedWorker(1)));
version (linux) static assert(!__traits(compiles, Thread.start!inTypedWorker(1)));
version (linux) static assert(!__traits(compiles, Thread.start!sharedTypedWorker(1)));
version (linux) static assert(!__traits(compiles, Thread.start!wrongReturnTypedWorker(1)));
version (linux) static assert(!__traits(compiles, Thread.start!refReturnTypedWorker()));
version (linux) static assert(!__traits(compiles, Thread.start!missingNothrowTypedWorker(1)));
version (linux) static assert(!__traits(compiles, Thread.start!missingNogcTypedWorker(1)));
version (linux) static assert(!__traits(compiles, Thread.start!(MemberTypedWorker.run)(1)));
version (linux) static assert(__traits(compiles, Thread.start!(StaticMemberTypedWorker.run)(1)));
version (linux) static assert(!__traits(compiles, Thread.start!constValueWorker()));
version (linux) static assert(!__traits(compiles, Thread.start!constValueWorker(1, 2)));
version (linux) static assert(__traits(compiles,
        Thread.startWith!constValueWorker(ThreadStartOptions.init, 1)));

version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!refTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!outTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!lazyTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!inTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!sharedTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!wrongReturnTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!refReturnTypedWorker(mallocAllocator())));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!missingNothrowTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!missingNogcTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!(MemberTypedWorker.run)(mallocAllocator(), 1)));
version (linux) static assert(__traits(compiles,
        Thread.startAlloc!(StaticMemberTypedWorker.run)(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!constValueWorker(mallocAllocator())));
version (linux) static assert(!__traits(compiles,
        Thread.startAlloc!constValueWorker(mallocAllocator(), 1, 2)));

version (linux) static assert(!__traits(compiles,
        spawn!refTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        spawn!outTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        spawn!lazyTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        spawn!inTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        spawn!sharedTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        spawn!refReturnTypedWorker(mallocAllocator())));
version (linux) static assert(!__traits(compiles,
        spawn!missingNothrowTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        spawn!missingNogcTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        spawn!(MemberTypedWorker.run)(mallocAllocator(), 1)));
version (linux) static assert(__traits(compiles,
        spawn!(StaticMemberTypedWorker.run)(mallocAllocator(), 1)));
version (linux) static assert(__traits(compiles,
        spawn!wrongReturnTypedWorker(mallocAllocator(), 1)));
version (linux) static assert(!__traits(compiles,
        spawn!constValueWorker(mallocAllocator())));
version (linux) static assert(!__traits(compiles,
        spawn!constValueWorker(mallocAllocator(), 1, 2)));
version (linux) static assert(!__traits(hasMember, JoinHandle!int, "detach"));

version (linux) private struct StaticScopedWorker
{
    static void run(int) nothrow @nogc
    {
    }
}

version (linux) private void validThreadScopeCompileBody(
    scope ref ThreadScope,
    scope int*,
) nothrow @nogc
{
}

version (linux) private void missingScopeBody(
    ref ThreadScope,
    scope int*,
) nothrow @nogc
{
}

version (linux) private int returningThreadScopeBody(
    scope ref ThreadScope,
    scope int*,
) nothrow @nogc
{
    return 0;
}

version (linux) private ThreadScope* escapedThreadScope;

version (linux) private void threadScopeCompileChecks() nothrow @nogc @system
{
    ThreadScope scope_;
    int value;

    static assert(__traits(compiles,
            scope_.spawn!refTypedWorker(value)));
    static assert(!__traits(compiles,
            scope_.spawn!refTypedWorker(1)));
    static assert(!__traits(compiles,
            scope_.spawn!outTypedWorker(value)));
    static assert(!__traits(compiles,
            scope_.spawn!lazyTypedWorker(value)));
    static assert(!__traits(compiles,
            scope_.spawn!inTypedWorker(value)));
    static assert(!__traits(compiles,
            scope_.spawn!wrongReturnTypedWorker(value)));
    static assert(!__traits(compiles,
            scope_.spawn!missingNothrowTypedWorker(value)));
    static assert(!__traits(compiles,
            scope_.spawn!missingNogcTypedWorker(value)));
    static assert(__traits(compiles,
            scope_.spawn!(StaticScopedWorker.run)(value)));
    static assert(!__traits(hasMember, ThreadScope, "join"));
    static assert(!__traits(hasMember, ThreadScope, "detach"));

    static assert(__traits(compiles,
            threadScope!validThreadScopeCompileBody(mallocAllocator(), &value)));
    static assert(!__traits(compiles,
            threadScope!missingScopeBody(mallocAllocator(), &value)));
    static assert(!__traits(compiles,
            threadScope!returningThreadScopeBody(mallocAllocator(), &value)));
    static assert(!__traits(compiles, () { ThreadScope source; ThreadScope copy = source; }));
    static assert(!__traits(compiles,
            (scope ref ThreadScope borrowed) nothrow @nogc @safe { escapedThreadScope = &borrowed; }));

    int captured;
    void nestedWorker() nothrow @nogc
    {
        ++captured;
    }

    static assert(!__traits(compiles, scope_.spawn!nestedWorker()));
}

version (linux) private bool typedStartWorks() nothrow @nogc
{
    auto zeroStarted = Thread.start!zeroArgTypedWorker();
    if (!zeroStarted.isOk)
        return false;
    Thread zeroThread = zeroStarted.unwrap();
    if (zeroThread.join() != 31)
        return false;

    auto constStarted = Thread.start!constValueWorker(73);
    if (!constStarted.isOk)
        return false;
    Thread constThread = constStarted.unwrap();
    if (constThread.join() != 73)
        return false;

    Atomic!uint entered;
    auto voidStarted = Thread.start!allocatedVoidWorker(&entered);
    if (!voidStarted.isOk)
        return false;
    Thread voidThread = voidStarted.unwrap();
    if (voidThread.join() != 0 || entered.load(MemoryOrder.acquire) != 1)
        return false;

    int[4] values = [3, 5, 7, 11];
    auto sliceStarted = Thread.start!sliceValueWorker(values[]);
    if (!sliceStarted.isOk)
        return false;
    Thread sliceThread = sliceStarted.unwrap();
    if (sliceThread.join() != 26)
        return false;

    auto alignedStarted = Thread.start!overAlignedWorker(OverAlignedCapture(84));
    if (!alignedStarted.isOk)
        return false;
    Thread alignedThread = alignedStarted.unwrap();
    return alignedThread.join() == 84;
}

version (linux) private bool typedMoveLifetimeWorks() nothrow @nogc
{
    Atomic!uint destructions;
    MoveOnlyCapture capture;
    capture.destructions = &destructions;
    capture.value = 91;

    auto started = Thread.start!moveOnlyWorker(move(capture));
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    return thread.join() == 91 && destructions.load() == 1;
}

version (linux) private bool typedConversionRunsOnParent() nothrow @nogc
{
    ThreadId convertedOn;
    ThreadId workerThread;
    ConversionSource source = ConversionSource(&convertedOn, 55);
    const parent = currentThreadId();

    auto started = Thread.start!convertedCaptureWorker(source, &workerThread);
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    return thread.join() == 55 && convertedOn == parent &&
        workerThread != ThreadId.init && workerThread != parent;
}

version (linux) private bool typedStartFailureCleansUp() nothrow @nogc
{
    Atomic!uint destructions;
    MoveOnlyCapture capture;
    capture.destructions = &destructions;
    capture.value = 13;

    auto started = Thread.startWith!moveOnlyWorker(
        ThreadStartOptions(size_t.max),
        move(capture),
    );
    if (!started.isErr)
        return false;
    return started.unwrapError().kind ==
        ThreadStartErrorKind.invalidConfiguration && destructions.load() == 1;
}

version (linux) private bool typedStackOptionsWork() nothrow @nogc
{
    enum requested = 256 * 1024 + 123;
    StackSizeContext context;
    auto started = Thread.startWith!stackSizeWorker(
        ThreadStartOptions(requested),
        &context,
    );
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    return thread.join() == 0 && context.observed >= requested;
}

version (linux) private struct TypedStartHandoffContext
{
    Atomic!uint workerEntered;
    Atomic!uint releaseWorker;
    Atomic!uint startState;
    int workerStatus;
}

version (linux) private int blockedTypedHandoffWorker(
    Atomic!uint* workerEntered,
    Atomic!uint* releaseWorker,
) nothrow @nogc
{
    workerEntered.store(1, MemoryOrder.release);
    releaseWorker.wait(0, MemoryOrder.acquire);
    return 74;
}

version (linux) private extern (C) void* typedStartHandoffStarter(void* opaque)
nothrow @nogc
{
    TypedStartHandoffContext* context = cast(TypedStartHandoffContext*) opaque;
    auto started = Thread.start!blockedTypedHandoffWorker(
        &context.workerEntered,
        &context.releaseWorker,
    );
    if (!started.isOk)
    {
        context.startState.store(2, MemoryOrder.release);
        return null;
    }

    Thread thread = started.unwrap();
    context.startState.store(1, MemoryOrder.release);
    context.workerStatus = thread.join();
    return null;
}

version (linux) private bool typedStartReturnsBeforeWorkerCompletion()
nothrow @nogc
{
    TypedStartHandoffContext context;
    pthread_t starter;
    if (pthread_create(&starter, null, &typedStartHandoffStarter, &context) != 0)
        return false;

    bool workerEntered;
    bool startReturned;
    foreach (_; 0 .. 100_000)
    {
        workerEntered = context.workerEntered.load(MemoryOrder.acquire) != 0;
        startReturned = context.startState.load(MemoryOrder.acquire) == 1;
        if (workerEntered && startReturned)
            break;
        if (context.startState.load(MemoryOrder.acquire) == 2)
            break;
        yieldThread();
    }

    context.releaseWorker.store(1, MemoryOrder.release);
    context.releaseWorker.notifyOne();

    if (pthread_join(starter, null) != 0)
        return false;
    return workerEntered && startReturned && context.workerStatus == 74;
}

version (linux) private bool typedStartShortStress() nothrow @nogc
{
    enum rounds = 32;
    foreach (_; 0 .. rounds)
    {
        auto started = Thread.start!zeroArgTypedWorker();
        if (!started.isOk)
            return false;
        Thread thread = started.unwrap();
        if (thread.join() != 31)
            return false;
    }
    return true;
}

version (linux) private bool allocatedRawStartWorks() nothrow @nogc
{
    StartTrackingAllocator tracker = StartTrackingAllocator.create();
    AllocReleaseContext context = AllocReleaseContext(&tracker);
    const parent = currentThreadId();

    auto started = Thread.startRawAlloc(
        tracker.allocator,
        &allocatedRawWorker,
        &context,
    );
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    const status = thread.join();

    return status == 37 &&
        context.workerEntered.load(MemoryOrder.acquire) == 1 &&
        tracker.allocationCalls.load() == 1 &&
        tracker.deallocationCalls.load() == 1 &&
        tracker.allocationThread == parent &&
        tracker.deallocationThread != parent;
}

version (linux) private bool allocatedTypedStartWorks() nothrow @nogc
{
    StartTrackingAllocator tracker = StartTrackingAllocator.create();
    const parent = currentThreadId();

    auto started = Thread.startAlloc!allocatedTypedWorker(
        tracker.allocator,
        &tracker,
        20,
        22,
    );
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    if (thread.join() != 42)
        return false;
    if (tracker.allocationCalls.load() != 1 ||
        tracker.deallocationCalls.load() != 1 ||
        tracker.allocationThread != parent ||
        tracker.deallocationThread == parent)
        return false;

    Atomic!uint entered;
    auto voidStarted = Thread.startAlloc!allocatedVoidWorker(
        mallocAllocator(),
        &entered,
    );
    if (!voidStarted.isOk)
        return false;
    Thread voidThread = voidStarted.unwrap();
    if (voidThread.join() != 0 || entered.load(MemoryOrder.acquire) != 1)
        return false;

    auto constStarted = Thread.startAlloc!constValueWorker(
        mallocAllocator(),
        73,
    );
    if (!constStarted.isOk)
        return false;
    Thread constThread = constStarted.unwrap();
    if (constThread.join() != 73)
        return false;

    int[4] values = [3, 5, 7, 11];
    auto sliceStarted = Thread.startAlloc!sliceValueWorker(
        mallocAllocator(),
        values[],
    );
    if (!sliceStarted.isOk)
        return false;
    Thread sliceThread = sliceStarted.unwrap();
    if (sliceThread.join() != 26)
        return false;

    auto alignedStarted = Thread.startAlloc!overAlignedWorker(
        mallocAllocator(),
        OverAlignedCapture(84),
    );
    if (!alignedStarted.isOk)
        return false;
    Thread alignedThread = alignedStarted.unwrap();
    return alignedThread.join() == 84;
}

version (linux) private bool allocatedTypedMoveLifetimeWorks() nothrow @nogc
{
    Atomic!uint destructions;
    MoveOnlyCapture capture;
    capture.destructions = &destructions;
    capture.value = 91;

    auto started = Thread.startAlloc!moveOnlyWorker(
        mallocAllocator(),
        move(capture),
    );
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    return thread.join() == 91 && destructions.load() == 1;
}

version (linux) private bool allocatedTypedConversionRunsOnParent() nothrow @nogc
{
    ThreadId convertedOn;
    ThreadId workerThread;
    ConversionSource source = ConversionSource(&convertedOn, 55);
    const parent = currentThreadId();

    auto started = Thread.startAlloc!convertedCaptureWorker(
        mallocAllocator(),
        source,
        &workerThread,
    );
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    return thread.join() == 55 && convertedOn == parent &&
        workerThread != ThreadId.init && workerThread != parent;
}

version (linux) private bool allocatedStartFailuresCleanUp() nothrow @nogc
{
    StartTrackingAllocator failing = StartTrackingAllocator.create(true);
    auto allocationFailure = Thread.startRawAlloc(
        failing.allocator,
        &nullContextRawWorker,
    );
    if (!allocationFailure.isErr)
        return false;
    const allocationError = allocationFailure.unwrapError();
    if (allocationError.kind != ThreadStartAllocErrorKind.allocationFailed ||
        failing.allocationCalls.load() != 1 ||
        failing.deallocationCalls.load() != 0)
        return false;

    Atomic!uint allocationFailureDestructions;
    MoveOnlyCapture allocationFailureCapture;
    allocationFailureCapture.destructions = &allocationFailureDestructions;
    allocationFailureCapture.value = 12;
    StartTrackingAllocator typedFailing = StartTrackingAllocator.create(true);
    auto typedAllocationFailure = Thread.startAlloc!moveOnlyWorker(
        typedFailing.allocator,
        move(allocationFailureCapture),
    );
    if (!typedAllocationFailure.isErr ||
        typedAllocationFailure.unwrapError()
            .kind !=
            ThreadStartAllocErrorKind.allocationFailed ||
            allocationFailureDestructions.load() != 1 ||
        typedFailing.allocationCalls.load() != 1 ||
        typedFailing.deallocationCalls.load() != 0)
        return false;

    StartTrackingAllocator invalidStack = StartTrackingAllocator.create();
    auto nativeFailure = Thread.startRawAllocWith(
        ThreadStartOptions(size_t.max),
        invalidStack.allocator,
        &nullContextRawWorker,
    );
    if (!nativeFailure.isErr)
        return false;
    const nativeError = nativeFailure.unwrapError();
    if (nativeError.kind != ThreadStartAllocErrorKind.threadStartFailed ||
        nativeError.threadStartError.kind !=
        ThreadStartErrorKind.invalidConfiguration ||
        invalidStack.allocationCalls.load() != 1 ||
        invalidStack.deallocationCalls.load() != 1 ||
        invalidStack.deallocationThread != currentThreadId())
        return false;

    Atomic!uint nativeFailureDestructions;
    MoveOnlyCapture nativeFailureCapture;
    nativeFailureCapture.destructions = &nativeFailureDestructions;
    nativeFailureCapture.value = 13;
    StartTrackingAllocator typedInvalidStack = StartTrackingAllocator.create();
    auto typedNativeFailure = Thread.startAllocWith!moveOnlyWorker(
        ThreadStartOptions(size_t.max),
        typedInvalidStack.allocator,
        move(nativeFailureCapture),
    );
    if (!typedNativeFailure.isErr)
        return false;
    const typedNativeError = typedNativeFailure.unwrapError();
    if (typedNativeError.kind != ThreadStartAllocErrorKind.threadStartFailed ||
        typedNativeError.threadStartError.kind !=
        ThreadStartErrorKind.invalidConfiguration ||
        nativeFailureDestructions.load() != 1 ||
        typedInvalidStack.allocationCalls.load() != 1 ||
        typedInvalidStack.deallocationCalls.load() != 1 ||
        typedInvalidStack.deallocationThread != currentThreadId())
        return false;

    return true;
}

version (linux) private bool allocatedDetachCompletes() nothrow @nogc
{
    DetachedContext rawContext;
    auto rawStarted = Thread.startRawAlloc(
        mallocAllocator(),
        &detachedWorker,
        &rawContext,
    );
    if (!rawStarted.isOk)
        return false;
    Thread rawThread = rawStarted.unwrap();
    rawThread.detach();

    foreach (_; 0 .. 1_000_000)
    {
        if (rawContext.done.load(MemoryOrder.acquire) != 0)
            break;
        yieldThread();
    }
    if (rawContext.done.load(MemoryOrder.acquire) == 0)
        return false;

    Atomic!uint typedDone;
    auto typedStarted = Thread.startAlloc!allocatedVoidWorker(
        mallocAllocator(),
        &typedDone,
    );
    if (!typedStarted.isOk)
        return false;
    Thread typedThread = typedStarted.unwrap();
    typedThread.detach();

    foreach (_; 0 .. 1_000_000)
    {
        if (typedDone.load(MemoryOrder.acquire) != 0)
            return true;
        yieldThread();
    }
    return false;
}

version (linux) private bool allocatedTypedStackOptionsWork() nothrow @nogc
{
    enum requested = 256 * 1024 + 123;
    StackSizeContext context;
    auto started = Thread.startAllocWith!stackSizeWorker(
        ThreadStartOptions(requested),
        mallocAllocator(),
        &context,
    );
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    return thread.join() == 0 && context.observed >= requested;
}

version (linux) private struct SpawnMoveOnlyResult
{
    Atomic!uint* destructions;
    int value;

    @disable this(this);

    ~this() nothrow @nogc
    {
        if (destructions !is null)
            destructions.fetchAdd(1, MemoryOrder.relaxed);
    }
}

version (linux) private SpawnMoveOnlyResult makeSpawnMoveOnlyResult(
    Atomic!uint* destructions,
    int value,
) nothrow @nogc
{
    SpawnMoveOnlyResult result;
    result.destructions = destructions;
    result.value = value;
    return move(result);
}

version (linux) private int consumeSpawnCapture(MoveOnlyCapture capture)
nothrow @nogc
{
    return capture.value;
}

version (linux) private Result!(int, ubyte) nestedSpawnResult(int value)
nothrow @nogc
{
    mixin ResultReturns;
    if (value < 0)
        return err(7);
    return ok(value);
}

version (linux) private int oneCaptureSpawnWorker(int value) nothrow @nogc
{
    return value + 1;
}

version (linux) private int twoCaptureSpawnWorker(long left, short right)
nothrow @nogc
{
    return cast(int)(left + right);
}

version (linux) align(64) private struct SpawnAlignedResult
{
    int value;
}

version (linux) private SpawnAlignedResult makeAlignedSpawnResult(
    OverAlignedCapture capture,
) nothrow @nogc
{
    return SpawnAlignedResult(capture.value);
}

version (linux) private int joinSpawnHandle(
    JoinHandle!int handle,
    int* result,
) nothrow @nogc
{
    *result = handle.join();
    return 0;
}

version (linux) private bool spawnResultsAndOwnershipWork() nothrow @nogc
{
    auto scalarStarted = spawn!oneCaptureSpawnWorker(mallocAllocator(), 41);
    if (!scalarStarted.isOk)
        return false;
    JoinHandle!int handleSource = scalarStarted.unwrap();
    JoinHandle!int constructed = move(handleSource);
    if (handleSource.joinable() || !constructed.joinable())
        return false;
    JoinHandle!int assigned;
    assigned = move(constructed);
    if (constructed.joinable() || !assigned.joinable() || assigned.join() != 42 ||
        assigned.joinable())
        return false;

    auto firstLayout = spawn!oneCaptureSpawnWorker(mallocAllocator(), 8);
    auto secondLayout = spawn!twoCaptureSpawnWorker(
        mallocAllocator(),
        20L,
        cast(short) 13,
    );
    if (!firstLayout.isOk || !secondLayout.isOk)
        return false;
    JoinHandle!int first = firstLayout.unwrap();
    JoinHandle!int second = secondLayout.unwrap();
    if (first.join() != 9 || second.join() != 33)
        return false;

    auto nestedStarted = spawn!nestedSpawnResult(mallocAllocator(), -1);
    if (!nestedStarted.isOk)
        return false;
    JoinHandle!(Result!(int, ubyte)) nestedHandle = nestedStarted.unwrap();
    auto nested = nestedHandle.join();
    if (!nested.isErr || nested.unwrapError() != 7)
        return false;

    auto alignedStarted = spawn!makeAlignedSpawnResult(
        mallocAllocator(),
        OverAlignedCapture(71),
    );
    if (!alignedStarted.isOk)
        return false;
    JoinHandle!SpawnAlignedResult aligned = alignedStarted.unwrap();
    if (aligned.join().value != 71)
        return false;

    Atomic!uint captureDestructions;
    MoveOnlyCapture capture;
    capture.destructions = &captureDestructions;
    capture.value = 64;
    auto captureStarted = spawn!consumeSpawnCapture(
        mallocAllocator(),
        move(capture),
    );
    if (!captureStarted.isOk)
        return false;
    JoinHandle!int captureHandle = captureStarted.unwrap();
    if (captureHandle.join() != 64 || captureDestructions.load() != 1)
        return false;

    ThreadId convertedOn;
    ThreadId workerThread;
    ConversionSource source = ConversionSource(&convertedOn, 55);
    const parent = currentThreadId();
    auto convertedStarted = spawn!convertedCaptureWorker(
        mallocAllocator(),
        source,
        &workerThread,
    );
    if (!convertedStarted.isOk)
        return false;
    JoinHandle!int convertedHandle = convertedStarted.unwrap();
    if (convertedHandle.join() != 55 || convertedOn != parent ||
        workerThread == ThreadId.init || workerThread == parent)
        return false;

    Atomic!uint resultDestructions;
    {
        auto resultStarted = spawn!makeSpawnMoveOnlyResult(
            mallocAllocator(),
            &resultDestructions,
            91,
        );
        if (!resultStarted.isOk)
            return false;
        JoinHandle!SpawnMoveOnlyResult resultHandle = resultStarted.unwrap();
        SpawnMoveOnlyResult result = resultHandle.join();
        if (result.value != 91 || resultDestructions.load() != 0)
            return false;
    }
    return resultDestructions.load() == 1;
}

version (linux) private bool spawnFailuresCleanUp() nothrow @nogc
{
    Atomic!uint allocationDestructions;
    MoveOnlyCapture allocationCapture;
    allocationCapture.destructions = &allocationDestructions;
    allocationCapture.value = 12;
    StartTrackingAllocator failing = StartTrackingAllocator.create(true);
    auto allocationFailed = spawn!consumeSpawnCapture(
        failing.allocator,
        move(allocationCapture),
    );
    if (!allocationFailed.isErr)
        return false;
    const allocationError = allocationFailed.unwrapError();
    if (allocationError.kind != SpawnErrorKind.allocationFailed ||
        allocationError.threadStartError != ThreadStartError.init ||
        allocationDestructions.load() != 1 ||
        failing.allocationCalls.load() != 1 ||
        failing.deallocationCalls.load() != 0)
        return false;

    Atomic!uint startDestructions;
    MoveOnlyCapture startCapture;
    startCapture.destructions = &startDestructions;
    startCapture.value = 13;
    StartTrackingAllocator invalidStack = StartTrackingAllocator.create();
    auto startFailed = spawnWith!consumeSpawnCapture(
        ThreadStartOptions(size_t.max),
        invalidStack.allocator,
        move(startCapture),
    );
    if (!startFailed.isErr)
        return false;
    const startError = startFailed.unwrapError();
    return startError.kind == SpawnErrorKind.threadStartFailed &&
        startError.threadStartError.kind ==
        ThreadStartErrorKind.invalidConfiguration &&
        startDestructions.load() == 1 &&
        invalidStack.allocationCalls.load() == 1 &&
        invalidStack.deallocationCalls.load() == 1 &&
        invalidStack.deallocationThread == currentThreadId();
}

version (linux) private bool spawnUsesOneStableAllocation() nothrow @nogc
{
    StartTrackingAllocator tracker = StartTrackingAllocator.create();
    auto started = spawn!twoCaptureSpawnWorker(
        tracker.allocator,
        17L,
        cast(short) 25,
    );
    if (!started.isOk || tracker.allocationCalls.load() != 1 ||
        tracker.deallocationCalls.load() != 0)
        return false;

    JoinHandle!int handle = started.unwrap();
    if (handle.join() != 42 || tracker.allocationCalls.load() != 1 ||
        tracker.deallocationCalls.load() != 1 ||
        tracker.deallocationThread != currentThreadId())
        return false;

    Atomic!uint entered;
    StartTrackingAllocator voidTracker = StartTrackingAllocator.create();
    auto voidStarted = spawn!allocatedVoidWorker(
        voidTracker.allocator,
        &entered,
    );
    if (!voidStarted.isOk || voidTracker.allocationCalls.load() != 1 ||
        voidTracker.deallocationCalls.load() != 0)
        return false;
    JoinHandle!void voidHandle = voidStarted.unwrap();
    voidHandle.join();
    return entered.load(MemoryOrder.acquire) == 1 &&
        voidTracker.allocationCalls.load() == 1 &&
        voidTracker.deallocationCalls.load() == 1 &&
        voidTracker.deallocationThread == currentThreadId() &&
        tracker.allocationCalls.load() == 1 &&
        tracker.deallocationCalls.load() == 1 &&
        tracker.deallocationThread == currentThreadId();
}

version (linux) private bool spawnOptionsWork() nothrow @nogc
{
    enum requested = 256 * 1024 + 123;
    StackSizeContext context;
    auto started = spawnWith!stackSizeWorker(
        ThreadStartOptions(requested),
        mallocAllocator(),
        &context,
    );
    if (!started.isOk)
        return false;
    JoinHandle!int handle = started.unwrap();
    return handle.join() == 0 && context.observed >= requested;
}

version (linux) private bool spawnHandleMovesAcrossThreads() nothrow @nogc
{
    StartTrackingAllocator tracker = StartTrackingAllocator.create();
    auto spawned = spawn!oneCaptureSpawnWorker(tracker.allocator, 41);
    if (!spawned.isOk)
        return false;
    JoinHandle!int handle = spawned.unwrap();

    int result;
    auto joinerStarted = Thread.start!joinSpawnHandle(move(handle), &result);
    if (!joinerStarted.isOk || handle.joinable())
        return false;
    Thread joiner = joinerStarted.unwrap();
    return joiner.join() == 0 && result == 42 &&
        tracker.deallocationCalls.load() == 1 &&
        tracker.deallocationThread != tracker.allocationThread;
}

version (linux) private int blockedSpawnWorker(
    Atomic!uint* entered,
    Atomic!uint* releaseWorker,
) nothrow @nogc
{
    entered.store(1, MemoryOrder.release);
    releaseWorker.wait(0, MemoryOrder.acquire);
    return 74;
}

version (linux) private struct SpawnHandoffContext
{
    Atomic!uint workerEntered;
    Atomic!uint releaseWorker;
    Atomic!uint startState;
    JoinHandle!int handle;
}

version (linux) private extern (C) void* spawnHandoffStarter(void* opaque)
nothrow @nogc
{
    SpawnHandoffContext* context = cast(SpawnHandoffContext*) opaque;
    auto started = spawn!blockedSpawnWorker(
        mallocAllocator(),
        &context.workerEntered,
        &context.releaseWorker,
    );
    if (!started.isOk)
    {
        context.startState.store(2, MemoryOrder.release);
        return null;
    }

    context.handle = started.unwrap();
    context.startState.store(1, MemoryOrder.release);
    return null;
}

version (linux) private bool spawnReturnsBeforeWorkerCompletion()
nothrow @nogc
{
    SpawnHandoffContext context;
    pthread_t starter;
    if (pthread_create(&starter, null, &spawnHandoffStarter, &context) != 0)
        return false;

    bool workerEntered;
    bool startReturned;
    foreach (_; 0 .. 1_000_000)
    {
        workerEntered = context.workerEntered.load(MemoryOrder.acquire) != 0;
        const state = context.startState.load(MemoryOrder.acquire);
        startReturned = state == 1;
        if ((workerEntered && startReturned) || state == 2)
            break;
        yieldThread();
    }

    context.releaseWorker.store(1, MemoryOrder.release);
    context.releaseWorker.notifyOne();
    if (pthread_join(starter, null) != 0 || !workerEntered || !startReturned ||
        !context.handle.joinable())
        return false;
    return context.handle.join() == 74;
}

version (linux) private bool spawnShortStress() nothrow @nogc
{
    enum batchSize = 16;
    enum batchCount = 8;

    foreach (batch; 0 .. batchCount)
    {
        JoinHandle!int[batchSize] handles;
        foreach (index, ref handle; handles)
        {
            auto started = spawn!twoCaptureSpawnWorker(
                mallocAllocator(),
                cast(long) batch,
                cast(short) index,
            );
            if (!started.isOk)
                return false;
            handle = started.unwrap();
        }
        foreach (index, ref handle; handles)
            if (handle.join() != cast(int)(batch + index))
                return false;
    }
    return true;
}

version (linux) private struct SpawnSelfJoinContext
{
    Atomic!uint ready;
    JoinHandle!int* handle;
}

version (linux) private int spawnSelfJoinWorker(SpawnSelfJoinContext* context)
nothrow @nogc
{
    context.ready.wait(0, MemoryOrder.acquire);
    return context.handle.join();
}

version (linux) private struct ThreadScopeManyContext
{
    enum childCount = 48;

    int[childCount] values;
    bool failed;
}

version (linux) private void writeScopedIndex(
    size_t index,
    int* values,
) nothrow @nogc
{
    values[index] = cast(int) index + 1;
}

version (linux) private void manyThreadScopeBody(
    scope ref ThreadScope scope_,
    scope ThreadScopeManyContext* context,
) nothrow @nogc
{
    foreach (index; 0 .. ThreadScopeManyContext.childCount)
    {
        auto started = scope_.spawn!writeScopedIndex(index, context.values.ptr);
        if (started.isErr)
        {
            context.failed = true;
            return;
        }
        started.unwrap();
    }
}

version (linux) private void mutateScopedReference(
    ref int value,
    int increment,
) nothrow @nogc
{
    value += increment;
}

version (linux) private void readScopedConstReference(
    ref const int value,
    int* observed,
) nothrow @nogc
{
    *observed = value;
}

version (linux) private void consumeScopedMoveOnly(
    MoveOnlyCapture capture,
    int* observed,
) nothrow @nogc
{
    *observed = capture.value;
}

version (linux) private struct ThreadScopeBorrowContext
{
    int value;
    int constant;
    int observedConstant;
    int observedMove;
    Atomic!uint* destructions;
    MoveOnlyCapture capture;
}

version (linux) private void borrowedThreadScopeBody(
    scope ref ThreadScope scope_,
    scope ThreadScopeBorrowContext* context,
) nothrow @nogc
{
    scope_.spawn!mutateScopedReference(context.value, 5).unwrap();
    scope_.spawn!readScopedConstReference(
        context.constant,
        &context.observedConstant,
    ).unwrap();
    scope_.spawn!consumeScopedMoveOnly(
        move(context.capture),
        &context.observedMove,
    ).unwrap();
}

version (linux) private bool threadScopeBorrowingAndManyChildren()
nothrow @nogc
{
    ThreadScopeManyContext many;
    threadScope!manyThreadScopeBody(mallocAllocator(), &many);
    if (many.failed)
        return false;
    foreach (index, value; many.values)
        if (value != cast(int) index + 1)
            return false;

    Atomic!uint destructions;
    ThreadScopeBorrowContext borrowed;
    borrowed.value = 37;
    borrowed.constant = 73;
    borrowed.destructions = &destructions;
    borrowed.capture.destructions = &destructions;
    borrowed.capture.value = 91;
    threadScope!borrowedThreadScopeBody(mallocAllocator(), &borrowed);
    return borrowed.value == 42 && borrowed.observedConstant == 73 &&
        borrowed.observedMove == 91 && destructions.load() == 1;
}

version (linux) private void markScopedCompletion(Atomic!uint* completed)
nothrow @nogc
{
    completed.store(1, MemoryOrder.release);
}

version (linux) private struct ThreadScopeFailureContext
{
    StartTrackingAllocator* tracker;
    Atomic!uint firstCompleted;
    Atomic!uint captureDestructions;
    MoveOnlyCapture capture;
    int observedCapture;
    bool sawExpectedFailure;
}

version (linux) private void allocationFailureScopeBody(
    scope ref ThreadScope scope_,
    scope ThreadScopeFailureContext* context,
) nothrow @nogc
{
    auto first = scope_.spawn!markScopedCompletion(&context.firstCompleted);
    if (first.isErr)
        return;
    first.unwrap();

    context.tracker.failAllocation = true;
    auto second = scope_.spawn!consumeScopedMoveOnly(
        move(context.capture),
        &context.observedCapture,
    );
    if (second.isErr)
    {
        const error = second.unwrapError();
        context.sawExpectedFailure =
            error.kind == SpawnErrorKind.allocationFailed &&
            error.threadStartError == ThreadStartError.init;
    }
    return;
}

version (linux) private void nativeFailureScopeBody(
    scope ref ThreadScope scope_,
    scope ThreadScopeFailureContext* context,
) nothrow @nogc
{
    auto first = scope_.spawn!markScopedCompletion(&context.firstCompleted);
    if (first.isErr)
        return;
    first.unwrap();

    auto second = scope_.spawnWith!consumeScopedMoveOnly(
        ThreadStartOptions(size_t.max),
        move(context.capture),
        &context.observedCapture,
    );
    if (second.isErr)
    {
        const error = second.unwrapError();
        context.sawExpectedFailure =
            error.kind == SpawnErrorKind.threadStartFailed &&
            error.threadStartError.kind ==
            ThreadStartErrorKind.invalidConfiguration;
    }
    return;
}

version (linux) private void emptyTrackedScopeBody(
    scope ref ThreadScope,
    scope ThreadScopeFailureContext*,
) nothrow @nogc
{
}

version (linux) private void successfulTrackedScopeBody(
    scope ref ThreadScope scope_,
    scope ThreadScopeFailureContext* context,
) nothrow @nogc
{
    foreach (_; 0 .. 3)
        scope_.spawn!markScopedCompletion(&context.firstCompleted).unwrap();
}

version (linux) private bool threadScopeFailuresStillJoinEarlierChildren()
nothrow @nogc
{
    const owner = currentThreadId();

    StartTrackingAllocator allocationTracker = StartTrackingAllocator.create();
    ThreadScopeFailureContext allocationContext;
    allocationContext.tracker = &allocationTracker;
    allocationContext.capture.destructions =
        &allocationContext.captureDestructions;
    allocationContext.capture.value = 11;
    threadScope!allocationFailureScopeBody(
        allocationTracker.allocator,
        &allocationContext,
    );
    if (!allocationContext.sawExpectedFailure ||
        allocationContext.firstCompleted.load(MemoryOrder.acquire) != 1 ||
        allocationTracker.allocationCalls.load() != 2 ||
        allocationTracker.deallocationCalls.load() != 1 ||
        allocationContext.captureDestructions.load() != 1 ||
        allocationContext.observedCapture != 0 ||
        allocationTracker.allocationThread != owner ||
        allocationTracker.deallocationThread != owner)
        return false;

    StartTrackingAllocator nativeTracker = StartTrackingAllocator.create();
    ThreadScopeFailureContext nativeContext;
    nativeContext.tracker = &nativeTracker;
    nativeContext.capture.destructions = &nativeContext.captureDestructions;
    nativeContext.capture.value = 12;
    threadScope!nativeFailureScopeBody(
        nativeTracker.allocator,
        &nativeContext,
    );
    if (!nativeContext.sawExpectedFailure ||
        nativeContext.firstCompleted.load(MemoryOrder.acquire) != 1 ||
        nativeTracker.allocationCalls.load() != 2 ||
        nativeTracker.deallocationCalls.load() != 2 ||
        nativeContext.captureDestructions.load() != 1 ||
        nativeContext.observedCapture != 0 ||
        nativeTracker.allocationThread != owner ||
        nativeTracker.deallocationThread != owner)
        return false;

    StartTrackingAllocator emptyTracker = StartTrackingAllocator.create();
    ThreadScopeFailureContext emptyContext;
    threadScope!emptyTrackedScopeBody(emptyTracker.allocator, &emptyContext);
    if (emptyTracker.allocationCalls.load() != 0 ||
        emptyTracker.deallocationCalls.load() != 0)
        return false;

    StartTrackingAllocator successTracker = StartTrackingAllocator.create();
    ThreadScopeFailureContext successContext;
    successContext.tracker = &successTracker;
    threadScope!successfulTrackedScopeBody(
        successTracker.allocator,
        &successContext,
    );
    return successContext.firstCompleted.load(MemoryOrder.acquire) == 1 &&
        successTracker.allocationCalls.load() == 3 &&
        successTracker.deallocationCalls.load() == 3 &&
        successTracker.allocationThread == owner &&
        successTracker.deallocationThread == owner;
}

version (linux) private struct ThreadScopeOptionsContext
{
    StackSizeContext stack;
}

version (linux) private void scopedStackSizeWorker(StackSizeContext* context)
nothrow @nogc
{
    if (stackSizeWorker(context) != 0)
        context.observed = 0;
}

version (linux) private void optionsThreadScopeBody(
    scope ref ThreadScope scope_,
    scope ThreadScopeOptionsContext* context,
) nothrow @nogc
{
    enum requested = 256 * 1024 + 123;
    scope_.spawnWith!scopedStackSizeWorker(
        ThreadStartOptions(requested),
        &context.stack,
    ).unwrap();
}

version (linux) private bool threadScopeOptionsWork() nothrow @nogc
{
    enum requested = 256 * 1024 + 123;
    ThreadScopeOptionsContext context;
    threadScope!optionsThreadScopeBody(mallocAllocator(), &context);
    return context.stack.observed >= requested;
}

version (linux) private bool inlineThreadScopeUsesSharedOwnershipCore()
nothrow @nogc
{
    StartTrackingAllocator tracker = StartTrackingAllocator.create();
    int[3] values;
    threadScope(
        tracker.allocator,
        (scope ref ThreadScope scope_) nothrow @nogc {
        foreach (index; 0 .. values.length)
            scope_.spawn!writeScopedIndex(index, values.ptr).unwrap();
        return;
    },
    );

    foreach (index, value; values)
        if (value != cast(int) index + 1)
            return false;
    return tracker.allocationCalls.load() == values.length &&
        tracker.deallocationCalls.load() == values.length &&
        tracker.allocationThread == currentThreadId() &&
        tracker.deallocationThread == currentThreadId();
}

version (linux) private void scopedNoOpWorker() nothrow @nogc
{
}

version (linux) private void scopedPanicWorker() nothrow @nogc
{
    panic("scoped worker panic death test");
}

version (linux) private struct WrongThreadScopeContext
{
    ThreadScope* scope_;
}

version (linux) private void useThreadScopeFromWrongThread(
    WrongThreadScopeContext* context,
) nothrow @nogc
{
    context.scope_.spawn!scopedNoOpWorker().unwrap();
}

version (linux) private void wrongThreadScopeBody(
    scope ref ThreadScope scope_,
    scope WrongThreadScopeContext* context,
) nothrow @nogc
{
    context.scope_ = &scope_;
    auto started = Thread.start!useThreadScopeFromWrongThread(context);
    Thread thread = started.unwrap();
    cast(void) thread.join();
}

version (linux) private struct RawStartHandoffContext
{
    Atomic!uint workerEntered;
    Atomic!uint releaseWorker;
    Atomic!uint startState;
    int workerStatus;
}

version (linux) private int blockedRawHandoffWorker(void* opaque) nothrow @nogc
{
    RawStartHandoffContext* context = cast(RawStartHandoffContext*) opaque;
    context.workerEntered.store(1, MemoryOrder.release);
    context.releaseWorker.wait(0, MemoryOrder.acquire);
    return 73;
}

version (linux) private extern (C) void* rawStartHandoffStarter(void* opaque)
nothrow @nogc
{
    RawStartHandoffContext* context = cast(RawStartHandoffContext*) opaque;
    auto started = Thread.startRaw(&blockedRawHandoffWorker, context);
    if (!started.isOk)
    {
        context.startState.store(2, MemoryOrder.release);
        return null;
    }

    Thread thread = started.unwrap();
    context.startState.store(1, MemoryOrder.release);
    context.workerStatus = thread.join();
    return null;
}

version (linux) private bool rawStartReturnsBeforeWorkerCompletion()
nothrow @nogc
{
    RawStartHandoffContext context;
    pthread_t starter;
    if (pthread_create(&starter, null, &rawStartHandoffStarter, &context) != 0)
        return false;

    bool workerEntered;
    foreach (_; 0 .. 1_000_000)
    {
        if (context.workerEntered.load(MemoryOrder.acquire) != 0)
        {
            workerEntered = true;
            break;
        }
        if (context.startState.load(MemoryOrder.acquire) == 2)
            break;
        yieldThread();
    }

    bool startReturned;
    if (workerEntered)
    {
        foreach (_; 0 .. 1_000_000)
        {
            if (context.startState.load(MemoryOrder.acquire) == 1)
            {
                startReturned = true;
                break;
            }
            yieldThread();
        }
    }

    // Always release the user worker before joining the starter. If startRaw
    // accidentally waited for user completion, this makes the test fail rather
    // than deadlock the suite.
    context.releaseWorker.store(1, MemoryOrder.release);
    context.releaseWorker.notifyOne();

    if (pthread_join(starter, null) != 0)
        return false;
    return workerEntered && startReturned && context.workerStatus == 73;
}

version (linux) private struct RawStressContext
{
    Atomic!uint* completed;
}

version (linux) private int rawStressWorker(void* opaque) nothrow @nogc
{
    RawStressContext* context = cast(RawStressContext*) opaque;
    context.completed.fetchAdd(1, MemoryOrder.relaxed);
    return 0;
}

version (linux) private bool rawStartJoinStress() nothrow @nogc
{
    enum batchSize = 32;
    enum batchCount = 32;

    Atomic!uint completed;
    RawStressContext context = RawStressContext(&completed);

    foreach (_; 0 .. batchCount)
    {
        Thread[batchSize] threads;
        foreach (ref thread; threads)
        {
            auto started = Thread.startRaw(&rawStressWorker, &context);
            if (!started.isOk)
                return false;
            thread = started.unwrap();
        }
        foreach (ref thread; threads)
            if (thread.join() != 0)
                return false;
    }

    return completed.load() == batchSize * batchCount;
}

version (linux) private struct DetachedContext
{
    Atomic!uint done;
}

version (linux) private int detachedWorker(void* opaque) nothrow @nogc
{
    DetachedContext* context = cast(DetachedContext*) opaque;
    context.done.store(1, MemoryOrder.release);
    return 0;
}

version (linux) private bool detachCompletes() nothrow @nogc
{
    DetachedContext context;
    auto started = Thread.startRaw(&detachedWorker, &context);
    if (!started.isOk)
        return false;

    Thread thread = started.unwrap();
    thread.detach();
    if (thread.joinable())
        return false;

    foreach (_; 0 .. 1_000_000)
    {
        if (context.done.load(MemoryOrder.acquire) != 0)
            return true;
        yieldThread();
    }
    return false;
}

version (linux) private struct IdentityContext
{
    Atomic!uint ready;
    ThreadId observed;
}

version (linux) private int identityWorker(void* opaque) nothrow @nogc
{
    IdentityContext* context = cast(IdentityContext*) opaque;
    context.observed = currentThreadId();
    context.ready.store(1, MemoryOrder.release);
    return 0;
}

version (linux) private bool threadIdentityMatches() nothrow @nogc
{
    IdentityContext context;
    const parentId = currentThreadId();
    if (parentId == ThreadId.init)
        return false;

    auto started = Thread.startRaw(&identityWorker, &context);
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    const childId = thread.id();

    while (context.ready.load(MemoryOrder.acquire) == 0)
        yieldThread();

    const idAfterPublication = thread.id();
    const matches = childId == context.observed &&
        childId == idAfterPublication && childId != ThreadId.init &&
        childId != parentId;
    return thread.join() == 0 && matches;
}

version (linux) private int tlsProbeValue;

version (linux) private int tlsProbeWorker(void* context) nothrow @nogc
{
    int* observedInitial = cast(int*) context;
    *observedInitial = tlsProbeValue;
    tlsProbeValue = 1234;
    return tlsProbeValue;
}

version (linux) private bool ldcTlsWorksInRawThread() nothrow @nogc
{
    tlsProbeValue = 77;
    int observedInitial = -1;
    auto started = Thread.startRaw(&tlsProbeWorker, &observedInitial);
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    return thread.join() == 1234 && observedInitial == 0 && tlsProbeValue == 77;
}

version (linux) private struct StackSizeContext
{
    size_t observed;
}

version (linux) private int stackSizeWorker(void* opaque) nothrow @nogc
{
    StackSizeContext* context = cast(StackSizeContext*) opaque;
    pthread_attr_t attributes;
    if (nativePthreadGetAttr(pthread_self(), &attributes) != 0)
        return 1;

    size_t stackSize;
    const getCode = pthread_attr_getstacksize(&attributes, &stackSize);
    const destroyCode = pthread_attr_destroy(&attributes);
    if (getCode != 0 || destroyCode != 0)
        return 2;

    context.observed = stackSize;
    return 0;
}

version (linux) private bool stackSizeIsMinimum() nothrow @nogc
{
    enum requested = 256 * 1024 + 123;
    StackSizeContext context;
    auto started = Thread.startRawWith(
        ThreadStartOptions(requested),
        &stackSizeWorker,
        &context,
    );
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    return thread.join() == 0 && context.observed >= requested;
}

version (linux) private bool tinyStackRequestNormalizes() nothrow @nogc
{
    auto started = Thread.startRawWith(
        ThreadStartOptions(1),
        &nullContextRawWorker,
    );
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();
    return thread.join() == 17;
}

version (linux) private bool overflowingStackRequestFails() nothrow @nogc
{
    auto started = Thread.startRawWith(
        ThreadStartOptions(size_t.max),
        &nullContextRawWorker,
    );
    if (!started.isErr)
        return false;
    const error = started.unwrapError();
    return error.kind == ThreadStartErrorKind.invalidConfiguration;
}

version (linux) private bool nativeNameEquals(const(char)[] expected)
nothrow @nogc
{
    char[16] current;
    if (nativePthreadGetName(pthread_self(), current.ptr, current.length) != 0)
        return false;
    if (expected.length >= current.length)
        return false;
    foreach (index; 0 .. expected.length)
        if (current[index] != expected[index])
            return false;
    return current[expected.length] == '\0';
}

version (linux) private bool currentThreadNaming() nothrow @nogc
{
    auto named = setCurrentThreadName("xtb-main");
    if (!named.isOk)
        return false;
    named.unwrap();
    if (!nativeNameEquals("xtb-main"))
        return false;

    auto maximum = setCurrentThreadName("123456789012345");
    if (!maximum.isOk)
        return false;
    maximum.unwrap();
    if (!nativeNameEquals("123456789012345"))
        return false;

    auto tooLong = setCurrentThreadName("1234567890123456");
    if (!tooLong.isErr ||
        tooLong.unwrapError().kind != ThreadNameErrorKind.tooLong)
        return false;

    auto embeddedNul = setCurrentThreadName("bad\0name");
    return embeddedNul.isErr &&
        embeddedNul.unwrapError().kind == ThreadNameErrorKind.invalidName;
}

version (linux) private struct NamedWorkerContext
{
    Atomic!uint check;
    Atomic!uint matched;
}

version (linux) private int namedWorker(void* opaque) nothrow @nogc
{
    NamedWorkerContext* context = cast(NamedWorkerContext*) opaque;
    while (context.check.load(MemoryOrder.acquire) == 0)
        yieldThread();
    context.matched.store(
        nativeNameEquals("xtb-worker") ? 1 : 0,
        MemoryOrder.release,
    );
    return 0;
}

version (linux) private bool handleThreadNaming() nothrow @nogc
{
    NamedWorkerContext context;
    auto started = Thread.startRaw(&namedWorker, &context);
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();

    auto named = thread.setName("xtb-worker");
    if (!named.isOk)
    {
        context.check.store(1, MemoryOrder.release);
        thread.join();
        return false;
    }
    named.unwrap();
    context.check.store(1, MemoryOrder.release);
    const status = thread.join();
    return status == 0 && context.matched.load(MemoryOrder.acquire) == 1;
}

version (linux) private struct ExitNameContext
{
    Atomic!uint finishing;
}

version (linux) private int exitingNamedWorker(void* opaque) nothrow @nogc
{
    ExitNameContext* context = cast(ExitNameContext*) opaque;
    context.finishing.store(1, MemoryOrder.release);
    return 0;
}

version (linux) private bool exitedThreadNameIsUnavailable() nothrow @nogc
{
    ExitNameContext context;
    auto started = Thread.startRaw(&exitingNamedWorker, &context);
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();

    while (context.finishing.load(MemoryOrder.acquire) == 0)
        yieldThread();

    bool unavailable;
    foreach (_; 0 .. 100_000)
    {
        auto named = thread.setName("late");
        if (named.isErr)
        {
            const error = named.unwrapError();
            if (error.kind == ThreadNameErrorKind.threadUnavailable)
            {
                unavailable = true;
                break;
            }
            thread.join();
            return false;
        }
        named.unwrap();
        yieldThread();
    }

    return thread.join() == 0 && unavailable;
}

version (linux) private struct SelfJoinContext
{
    Atomic!uint ready;
    Thread* thread;
}

version (linux) private int selfJoinWorker(void* opaque) nothrow @nogc
{
    SelfJoinContext* context = cast(SelfJoinContext*) opaque;
    while (context.ready.load(MemoryOrder.acquire) == 0)
        yieldThread();
    context.thread.join();
    return 0;
}

version (linux) private int noOpRawWorker(void* context) nothrow @nogc
{
    return 0;
}

version (linux) private int panicRawWorker(void* context) nothrow @nogc
{
    panic("worker panic death test");
}

version (linux) private struct MutexIncrementContext
{
    Mutex* mutex;
    uint* value;
    uint iterations;
}

version (linux) private int mutexIncrementWorker(
    MutexIncrementContext* context,
) nothrow @nogc
{
    foreach (_; 0 .. context.iterations)
    {
        context.mutex.lock();
        ++*context.value;
        context.mutex.unlock();
    }
    return 0;
}

version (linux) private bool mutexMutualExclusion() nothrow @nogc
{
    enum workerCount = 4;
    enum iterations = 2_000;

    Mutex mutex;
    uint value;
    MutexIncrementContext context = MutexIncrementContext(
        &mutex,
        &value,
        iterations,
    );
    Thread[workerCount] threads;
    size_t startedCount;

    foreach (ref thread; threads)
    {
        auto started = Thread.start!mutexIncrementWorker(&context);
        if (!started.isOk)
        {
            foreach (index; 0 .. startedCount)
                cast(void) threads[index].join();
            return false;
        }
        thread = started.unwrap();
        ++startedCount;
    }

    foreach (ref thread; threads)
        if (thread.join() != 0)
            return false;

    return value == workerCount * iterations;
}

version (linux) private struct MutexHandoffContext
{
    Mutex* mutex;
    Atomic!uint entered;
    Atomic!uint acquired;
    int* payload;
    int observed;
}

version (linux) private int mutexHandoffWorker(
    MutexHandoffContext* context,
) nothrow @nogc
{
    context.entered.store(1, MemoryOrder.release);
    context.mutex.lock();
    context.observed = *context.payload;
    context.acquired.store(1, MemoryOrder.release);
    context.mutex.unlock();
    return 0;
}

version (linux) private bool mutexHandoffAndPublication() nothrow @nogc
{
    Mutex mutex;
    int payload;
    MutexHandoffContext context = MutexHandoffContext(
        &mutex,
        Atomic!uint.init,
        Atomic!uint.init,
        &payload,
        0,
    );

    mutex.lock();
    auto started = Thread.start!mutexHandoffWorker(&context);
    if (!started.isOk)
    {
        mutex.unlock();
        return false;
    }
    Thread thread = started.unwrap();

    if (!waitForAtomicAtLeast(&context.entered, 1))
    {
        mutex.unlock();
        cast(void) thread.join();
        return false;
    }

    // Give the child a few scheduling opportunities while the mutex remains
    // locked. It must not enter the protected region until unlock publishes
    // the payload with release semantics.
    foreach (_; 0 .. 16)
        yieldThread();
    if (context.acquired.load(MemoryOrder.acquire) != 0)
    {
        mutex.unlock();
        cast(void) thread.join();
        return false;
    }

    payload = 0x1234_5678;
    mutex.unlock();
    if (thread.join() != 0)
        return false;

    return context.acquired.load(MemoryOrder.acquire) == 1 &&
        context.observed == payload;
}

version (XTB_Checked) version (linux) private int mutexNonOwnerUnlockWorker(
    Mutex* mutex,
) nothrow @nogc
{
    mutex.unlock();
    return 0;
}

version (XTB_Checked) version (linux) private int rwLockNonOwnerWriteUnlockWorker(
    RwLock* lock,
) nothrow @nogc
{
    lock.unlockWrite();
    return 0;
}

version (XTB_Checked) version (linux) private int destroyMutexGuardOnWrongThread(
    LockGuard!Mutex,
) nothrow @nogc
{
    return 0;
}

version (XTB_Checked) version (linux) private int destroyWriteGuardOnWrongThread(
    WriteLockGuard!RwLock,
) nothrow @nogc
{
    return 0;
}

version (linux) private struct CondVarContext
{
    Mutex mutex;
    CondVar condition;
    Atomic!uint ready;
    Atomic!uint completed;
    uint permits;
    int payload;
    int observed;
}

version (linux) private int condVarWaiter(CondVarContext* context) nothrow @nogc
{
    context.mutex.lock();
    context.ready.fetchAdd(1, MemoryOrder.release);
    while (context.permits == 0)
        context.condition.wait(context.mutex);
    --context.permits;
    context.observed = context.payload;
    context.completed.fetchAdd(1, MemoryOrder.release);
    context.mutex.unlock();
    return 0;
}

version (linux) private bool condVarNotifyOneAndPublication() nothrow @nogc
{
    CondVarContext context;
    auto started = Thread.start!condVarWaiter(&context);
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();

    if (!waitForAtomicAtLeast(&context.ready, 1))
    {
        context.mutex.lock();
        context.permits = 1;
        context.mutex.unlock();
        context.condition.notifyAll();
        cast(void) thread.join();
        return false;
    }

    // Acquiring the predicate mutex proves the waiter has completed CondVar
    // registration and released the mutex as part of entering wait().
    context.mutex.lock();
    context.payload = 0x2468_1357;
    context.permits = 1;
    context.mutex.unlock();
    context.condition.notifyOne();

    if (thread.join() != 0)
        return false;
    return context.completed.load(MemoryOrder.acquire) == 1 &&
        context.observed == context.payload;
}

version (linux) private bool condVarNotifyOneReleasesOneLogicalWaiter() nothrow @nogc
{
    enum workerCount = 3;
    CondVarContext context;
    Thread[workerCount] threads;
    size_t startedCount;

    foreach (ref thread; threads)
    {
        auto started = Thread.start!condVarWaiter(&context);
        if (!started.isOk)
            break;
        thread = started.unwrap();
        ++startedCount;
    }

    if (startedCount != workerCount ||
        !waitForAtomicAtLeast(&context.ready, workerCount))
    {
        context.mutex.lock();
        context.permits = workerCount;
        context.mutex.unlock();
        context.condition.notifyAll();
        foreach (index; 0 .. startedCount)
            cast(void) threads[index].join();
        return false;
    }

    context.mutex.lock();
    context.permits = 1;
    context.mutex.unlock();
    context.condition.notifyOne();

    if (!waitForAtomicAtLeast(&context.completed, 1))
    {
        context.mutex.lock();
        context.permits = workerCount;
        context.mutex.unlock();
        context.condition.notifyAll();
        foreach (ref thread; threads)
            cast(void) thread.join();
        return false;
    }

    // No second waiter has a predicate permit, regardless of which kernel
    // sleeper consumed the CondVar signal.
    foreach (_; 0 .. 32)
        yieldThread();
    if (context.completed.load(MemoryOrder.acquire) != 1)
        return false;

    context.mutex.lock();
    context.permits = workerCount - 1;
    context.mutex.unlock();
    context.condition.notifyAll();

    foreach (ref thread; threads)
        if (thread.join() != 0)
            return false;
    return context.completed.load(MemoryOrder.acquire) == workerCount;
}

version (linux) private bool condVarNotifyAllReleasesWaiters() nothrow @nogc
{
    enum workerCount = 4;
    CondVarContext context;
    Thread[workerCount] threads;
    size_t startedCount;

    foreach (ref thread; threads)
    {
        auto started = Thread.start!condVarWaiter(&context);
        if (!started.isOk)
            break;
        thread = started.unwrap();
        ++startedCount;
    }

    if (startedCount != workerCount ||
        !waitForAtomicAtLeast(&context.ready, workerCount))
    {
        context.mutex.lock();
        context.permits = workerCount;
        context.mutex.unlock();
        context.condition.notifyAll();
        foreach (index; 0 .. startedCount)
            cast(void) threads[index].join();
        return false;
    }

    context.mutex.lock();
    context.payload = 0x1020_3040;
    context.permits = workerCount;
    context.mutex.unlock();
    context.condition.notifyAll();

    foreach (ref thread; threads)
        if (thread.join() != 0)
            return false;
    return context.completed.load(MemoryOrder.acquire) == workerCount;
}

version (linux) private bool condVarNotificationIsNotStored() nothrow @nogc
{
    CondVarContext context;
    context.condition.notifyAll();

    auto started = Thread.start!condVarWaiter(&context);
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();

    if (!waitForAtomicAtLeast(&context.ready, 1))
        return false;

    // Acquiring the predicate mutex after ready becomes visible proves this
    // waiter has actually registered and entered CondVar.wait(). The earlier
    // broadcast must not act like a stored permit for this later wait.
    context.mutex.lock();
    context.mutex.unlock();
    foreach (_; 0 .. 32)
        yieldThread();
    if (context.completed.load(MemoryOrder.acquire) != 0)
        return false;

    context.mutex.lock();
    context.permits = 1;
    context.mutex.unlock();
    context.condition.notifyOne();

    return thread.join() == 0 &&
        context.completed.load(MemoryOrder.acquire) == 1;
}

version (linux) private struct CondVarGenerationContext
{
    Mutex mutex;
    CondVar condition;
    Atomic!uint ready;
    Atomic!uint completed;
    uint generation;
    uint rounds;
}

version (linux) private int condVarGenerationWaiter(
    CondVarGenerationContext* context,
) nothrow @nogc
{
    context.mutex.lock();
    foreach (target; 1 .. context.rounds + 1)
    {
        context.ready.store(target, MemoryOrder.release);
        while (context.generation < target)
            context.condition.wait(context.mutex);
        context.completed.store(target, MemoryOrder.release);
    }
    context.mutex.unlock();
    return 0;
}

version (linux) private bool condVarRepeatedWaits() nothrow @nogc
{
    enum rounds = 32;
    CondVarGenerationContext context;
    context.rounds = rounds;

    auto started = Thread.start!condVarGenerationWaiter(&context);
    if (!started.isOk)
        return false;
    Thread thread = started.unwrap();

    foreach (round; 1 .. rounds + 1)
    {
        if (!waitForAtomicAtLeast(&context.ready, round))
            return false;

        // Hold the predicate mutex while notifying. A correct CondVar must never
        // require the awakened waiter to reacquire this mutex before notifyOne returns.
        context.mutex.lock();
        context.generation = round;
        context.condition.notifyOne();
        context.mutex.unlock();

        if (!waitForAtomicAtLeast(&context.completed, round))
            return false;
    }

    return thread.join() == 0 &&
        context.completed.load(MemoryOrder.acquire) == rounds;
}

version (linux) private struct SemaphorePublicationContext
{
    Semaphore semaphore;
    Atomic!uint entered;
    int payload;
    int observed;
}

version (linux) private int semaphorePublicationWaiter(
    SemaphorePublicationContext* context,
) nothrow @nogc
{
    context.entered.store(1, MemoryOrder.release);
    context.semaphore.acquire();
    context.observed = context.payload;
    return 0;
}

version (linux) private bool semaphoreHandoffPublishes() nothrow @nogc
{
    SemaphorePublicationContext context;
    auto started = Thread.start!semaphorePublicationWaiter(&context);
    if (!started.isOk)
        return false;
    Thread waiter = started.unwrap();

    if (!waitForAtomicAtLeast(&context.entered, 1))
    {
        context.semaphore.release();
        cast(void) waiter.join();
        return false;
    }

    context.payload = 0x43ac_7712;
    context.semaphore.release();
    if (waiter.join() != 0)
        return false;
    return context.observed == context.payload &&
        !context.semaphore.tryAcquire();
}

version (linux) private struct SemaphoreBatchContext
{
    Semaphore* semaphore;
    Atomic!uint entered;
    Atomic!uint completed;
}

version (linux) private int semaphoreBatchWaiter(
    SemaphoreBatchContext* context,
) nothrow @nogc
{
    context.entered.fetchAdd(1, MemoryOrder.release);
    context.semaphore.acquire();
    context.completed.fetchAdd(1, MemoryOrder.release);
    return 0;
}

version (linux) private bool semaphoreReleaseCountIsExact() nothrow @nogc
{
    enum waiterCount = 4;
    Semaphore semaphore;
    SemaphoreBatchContext context;
    context.semaphore = &semaphore;
    Thread[waiterCount] waiters;

    foreach (ref waiter; waiters)
    {
        auto started = Thread.start!semaphoreBatchWaiter(&context);
        if (!started.isOk)
            return false;
        waiter = started.unwrap();
    }

    if (!waitForAtomicAtLeast(&context.entered, waiterCount))
    {
        semaphore.release(waiterCount);
        foreach (ref waiter; waiters)
            if (waiter.joinable())
                cast(void) waiter.join();
        return false;
    }

    semaphore.release(2);
    if (!waitForAtomicAtLeast(&context.completed, 2))
    {
        semaphore.release(2);
        foreach (ref waiter; waiters)
            cast(void) waiter.join();
        return false;
    }

    foreach (_; 0 .. 64)
        yieldThread();
    if (context.completed.load(MemoryOrder.acquire) != 2)
    {
        semaphore.release(2);
        foreach (ref waiter; waiters)
            cast(void) waiter.join();
        return false;
    }

    semaphore.release(2);
    foreach (ref waiter; waiters)
        if (waiter.join() != 0)
            return false;

    return context.completed.load(MemoryOrder.acquire) == waiterCount &&
        !semaphore.tryAcquire();
}

version (linux) private struct SemaphoreBoundContext
{
    Semaphore* semaphore;
    Atomic!uint inside;
    Atomic!uint failed;
    uint iterations;
}

version (linux) private int semaphoreBoundWorker(
    SemaphoreBoundContext* context,
) nothrow @nogc
{
    foreach (_; 0 .. context.iterations)
    {
        context.semaphore.acquire();
        const previous = context.inside.fetchAdd(1, MemoryOrder.acquireRelease);
        if (previous >= 2)
            context.failed.store(1, MemoryOrder.release);
        yieldThread();
        context.inside.fetchSub(1, MemoryOrder.release);
        context.semaphore.release();
    }
    return 0;
}

version (linux) private bool semaphoreRepeatedContention() nothrow @nogc
{
    enum workerCount = 4;
    enum iterations = 96;
    Semaphore semaphore = Semaphore(2);
    SemaphoreBoundContext context;
    context.semaphore = &semaphore;
    context.iterations = iterations;
    Thread[workerCount] workers;

    foreach (ref worker; workers)
    {
        auto started = Thread.start!semaphoreBoundWorker(&context);
        if (!started.isOk)
            return false;
        worker = started.unwrap();
    }

    foreach (ref worker; workers)
        if (worker.join() != 0)
            return false;

    if (context.failed.load(MemoryOrder.acquire) != 0 ||
        context.inside.load(MemoryOrder.acquire) != 0)
        return false;

    if (!semaphore.tryAcquire())
        return false;
    if (!semaphore.tryAcquire())
        return false;
    return !semaphore.tryAcquire();
}

version (XTB_Checked) version (linux) private struct CondVarMutexMixContext
{
    Mutex first;
    Mutex second;
    CondVar condition;
    Atomic!uint ready;
}

version (XTB_Checked) version (linux) private int condVarFirstMutexWaiter(
    CondVarMutexMixContext* context,
) nothrow @nogc
{
    context.first.lock();
    context.ready.store(1, MemoryOrder.release);
    context.condition.wait(context.first);
    context.first.unlock();
    return 0;
}

version (XTB_Checked) version (linux) private void triggerCondVarMutexMix()
nothrow @nogc
{
    CondVarMutexMixContext context;
    auto started = Thread.start!condVarFirstMutexWaiter(&context);
    if (!started.isOk)
        _exit(88);
    Thread thread = started.unwrap();
    if (!waitForAtomicAtLeast(&context.ready, 1))
        _exit(89);

    // This lock can succeed only after the first waiter registered and released
    // its predicate mutex inside CondVar.wait().
    context.first.lock();
    context.first.unlock();

    context.second.lock();
    context.condition.wait(context.second);
    _exit(90);
}

version (Posix) private void recursiveOnceInitializer(Once* once)
nothrow @nogc
{
    callOnce!recursiveOnceInitializer(*once, once);
}

version (Posix) private int recursiveOnceCellInitializer(OnceCell!int* cell)
nothrow @nogc
{
    return cell.getOrInit!recursiveOnceCellInitializer(cell);
}

version (XTB_Checked) version (linux) private struct OnceCellDestroyContext
{
    OnceCell!int cell;
    Atomic!uint entered;
    Atomic!uint releaseInitializer;
}

version (XTB_Checked) version (linux) private int initializeDestroyedOnceCell(
    OnceCellDestroyContext* context,
) nothrow @nogc
{
    context.entered.store(1, MemoryOrder.release);
    context.entered.notifyAll();
    context.releaseInitializer.wait(0, MemoryOrder.acquire);
    return 1;
}

version (XTB_Checked) version (linux) private int initializeDestroyedOnceCellWorker(
    OnceCellDestroyContext* context,
) nothrow @nogc
{
    return context.cell.getOrInit!initializeDestroyedOnceCell(context);
}

version (XTB_Checked) version (linux) private void triggerActiveOnceCellDestroy()
nothrow @nogc
{
    OnceCellDestroyContext context;
    auto started = Thread.start!initializeDestroyedOnceCellWorker(&context);
    if (!started.isOk)
        _exit(93);
    Thread thread = started.unwrap();
    if (!waitForAtomicAtLeast(&context.entered, 1))
        _exit(94);
    destroy(context.cell);
    _exit(95);
}

version (Posix) private enum DeathCase : ubyte
{
    loadRelease,
    storeAcquire,
    casReleaseFailure,
    casStrongerFailure,
    flagClearAcquire,
    invalidOrderValue,
    invalidFenceOrder,
    waitRelease,
    waitAcquireRelease,
    invalidWaitOrderValue,
    nullRawFunction,
    nullRawAllocFunction,
    nullRawAllocAllocator,
    joinEmpty,
    detachEmpty,
    idEmpty,
    nameEmpty,
    joinTwice,
    detachTwice,
    destroyJoinable,
    moveAssignOverJoinable,
    selfJoin,
    workerPanic,
    spawnNullAllocator,
    spawnJoinEmpty,
    spawnJoinTwice,
    spawnDestroyJoinable,
    spawnMoveAssignOverJoinable,
    spawnSelfJoin,
    spawnWorkerPanic,
    threadScopeNullAllocator,
    threadScopeNullBody,
    threadScopeNullContext,
    threadScopeInertSpawn,
    threadScopeWrongThread,
    threadScopeWorkerPanic,
    mutexUnlockUnlocked,
    mutexDoubleUnlock,
    mutexRecursiveLock,
    mutexDestroyLocked,
    mutexUnlockNonOwner,
    rwLockUnlockRead,
    rwLockDoubleUnlockRead,
    rwLockUnlockWrite,
    rwLockDoubleUnlockWrite,
    rwLockRecursiveWrite,
    rwLockWriterToRead,
    rwLockDestroyReadOwned,
    rwLockDestroyWriteOwned,
    rwLockUnlockWriteNonOwner,
    lockGuardNullMutex,
    readLockGuardNullLock,
    writeLockGuardNullLock,
    lockGuardMoveAssignOwned,
    readLockGuardMoveAssignOwned,
    writeLockGuardMoveAssignOwned,
    lockGuardWrongThread,
    writeLockGuardWrongThread,
    condVarWaitWithoutOwnership,
    condVarMixedMutexes,
    semaphoreOverflow,
    latchUnderflow,
    waitGroupOverflow,
    waitGroupUnderflow,
    waitGroupDestroyActive,
    barrierZeroParticipants,
    barrierInitWait,
    barrierInitDrop,
    barrierCompletedWait,
    barrierCompletedDrop,
    onceRecursive,
    onceCellRecursive,
    onceCellDestroyActive,
}

version (Posix) private void runDeathCase(DeathCase deathCase) nothrow @nogc
{
    Atomic!uint value;
    uint expected;

    final switch (deathCase)
    {
        case DeathCase.loadRelease:
            cast(void) value.load(MemoryOrder.release);
            return;
        case DeathCase.storeAcquire:
            value.store(1, MemoryOrder.acquire);
            return;
        case DeathCase.casReleaseFailure:
            cast(void) value.compareExchangeStrong(
                expected,
                1,
                MemoryOrder.acquireRelease,
                MemoryOrder.release,
            );
            return;
        case DeathCase.casStrongerFailure:
            cast(void) value.compareExchangeStrong(
                expected,
                1,
                MemoryOrder.release,
                MemoryOrder.acquire,
            );
            return;
        case DeathCase.flagClearAcquire:
            AtomicFlag flag;
            flag.clear(MemoryOrder.acquire);
            return;
        case DeathCase.invalidOrderValue:
            cast(void) value.exchange(1, cast(MemoryOrder) 0xff);
            return;
        case DeathCase.invalidFenceOrder:
            atomicThreadFence(cast(MemoryOrder) 0xff);
            return;
        case DeathCase.waitRelease:
            static if (Atomic!uint.waitSupported)
                value.wait(0, MemoryOrder.release);
            return;
        case DeathCase.waitAcquireRelease:
            static if (Atomic!uint.waitSupported)
                value.wait(0, MemoryOrder.acquireRelease);
            return;
        case DeathCase.invalidWaitOrderValue:
            static if (Atomic!uint.waitSupported)
                value.wait(0, cast(MemoryOrder) 0xff);
            return;
        case DeathCase.nullRawFunction:
            cast(void) Thread.startRaw(null);
            _exit(80);
            return;
        case DeathCase.nullRawAllocFunction:
            cast(void) Thread.startRawAlloc(mallocAllocator(), null);
            _exit(84);
            return;
        case DeathCase.nullRawAllocAllocator:
            cast(void) Thread.startRawAlloc(null, &noOpRawWorker);
            _exit(85);
            return;
        case DeathCase.joinEmpty:
            Thread thread;
            cast(void) thread.join();
            return;
        case DeathCase.detachEmpty:
            Thread thread;
            thread.detach();
            return;
        case DeathCase.idEmpty:
            Thread thread;
            cast(void) thread.id();
            return;
        case DeathCase.nameEmpty:
            Thread thread;
            cast(void) thread.setName("empty");
            return;
        case DeathCase.joinTwice:
            auto started = Thread.startRaw(&noOpRawWorker);
            Thread thread = started.unwrap();
            cast(void) thread.join();
            cast(void) thread.join();
            return;
        case DeathCase.detachTwice:
            auto started = Thread.startRaw(&noOpRawWorker);
            Thread thread = started.unwrap();
            thread.detach();
            thread.detach();
            return;
        case DeathCase.destroyJoinable:
            auto started = Thread.startRaw(&noOpRawWorker);
            Thread thread = started.unwrap();
            return;
        case DeathCase.moveAssignOverJoinable:
            auto firstStarted = Thread.startRaw(&noOpRawWorker);
            auto secondStarted = Thread.startRaw(&noOpRawWorker);
            Thread first = firstStarted.unwrap();
            Thread second = secondStarted.unwrap();
            first = move(second);
            _exit(81);
            return;
        case DeathCase.selfJoin:
            SelfJoinContext context;
            auto started = Thread.startRaw(&selfJoinWorker, &context);
            Thread thread = started.unwrap();
            context.thread = &thread;
            context.ready.store(1, MemoryOrder.release);
            foreach (_; 0 .. 1_000_000)
                yieldThread();
            _exit(82);
            return;
        case DeathCase.workerPanic:
            auto started = Thread.startRaw(&panicRawWorker);
            Thread thread = started.unwrap();
            cast(void) thread.join();
            _exit(83);
            return;
        case DeathCase.spawnNullAllocator:
            cast(void) spawn!oneCaptureSpawnWorker(null, 1);
            return;
        case DeathCase.spawnJoinEmpty:
            JoinHandle!int handle;
            cast(void) handle.join();
            return;
        case DeathCase.spawnJoinTwice:
            auto started = spawn!oneCaptureSpawnWorker(mallocAllocator(), 1);
            JoinHandle!int handle = started.unwrap();
            cast(void) handle.join();
            cast(void) handle.join();
            return;
        case DeathCase.spawnDestroyJoinable:
            auto started = spawn!oneCaptureSpawnWorker(mallocAllocator(), 1);
            JoinHandle!int handle = started.unwrap();
            return;
        case DeathCase.spawnMoveAssignOverJoinable:
            auto firstStarted = spawn!oneCaptureSpawnWorker(
                mallocAllocator(),
                1,
            );
            auto secondStarted = spawn!oneCaptureSpawnWorker(
                mallocAllocator(),
                2,
            );
            JoinHandle!int first = firstStarted.unwrap();
            JoinHandle!int second = secondStarted.unwrap();
            first = move(second);
            return;
        case DeathCase.spawnSelfJoin:
            SpawnSelfJoinContext context;
            auto started = spawn!spawnSelfJoinWorker(
                mallocAllocator(),
                &context,
            );
            JoinHandle!int handle = started.unwrap();
            context.handle = &handle;
            context.ready.store(1, MemoryOrder.release);
            context.ready.notifyOne();
            foreach (_; 0 .. 1_000_000)
                yieldThread();
            _exit(103);
            return;
        case DeathCase.spawnWorkerPanic:
            auto started = spawn!panicRawWorker(mallocAllocator(), null);
            JoinHandle!int handle = started.unwrap();
            cast(void) handle.join();
            return;
        case DeathCase.threadScopeNullAllocator:
            threadScope(
                null,
                (scope ref ThreadScope) nothrow @nogc {},
            );
            return;
        case DeathCase.threadScopeNullBody:
            ThreadScopeBody body;
            threadScope(mallocAllocator(), body);
            return;
        case DeathCase.threadScopeNullContext:
            threadScope!validThreadScopeCompileBody(
                mallocAllocator(),
                cast(int*) null,
            );
            return;
        case DeathCase.threadScopeInertSpawn:
            ThreadScope scope_;
            cast(void) scope_.spawn!scopedNoOpWorker();
            return;
        case DeathCase.threadScopeWrongThread:
            WrongThreadScopeContext context;
            threadScope!wrongThreadScopeBody(mallocAllocator(), &context);
            return;
        case DeathCase.threadScopeWorkerPanic:
            threadScope(
                mallocAllocator(),
                (scope ref ThreadScope scope_) nothrow @nogc {
                scope_.spawn!scopedPanicWorker().unwrap();
            },
            );
            return;
        case DeathCase.mutexUnlockUnlocked:
            Mutex mutex;
            mutex.unlock();
            return;
        case DeathCase.mutexDoubleUnlock:
            Mutex mutex;
            mutex.lock();
            mutex.unlock();
            mutex.unlock();
            return;
        case DeathCase.mutexRecursiveLock:
            version (XTB_Checked)
            {
                Mutex mutex;
                mutex.lock();
                mutex.lock();
            }
            return;
        case DeathCase.mutexDestroyLocked:
            version (XTB_Checked)
            {
                Mutex mutex;
                mutex.lock();
            }
            return;
        case DeathCase.mutexUnlockNonOwner:
            version (XTB_Checked)
            {
                version (linux)
                {
                    Mutex mutex;
                    mutex.lock();
                    auto started = Thread.start!mutexNonOwnerUnlockWorker(
                        &mutex,
                    );
                    if (!started.isOk)
                        _exit(86);
                    Thread thread = started.unwrap();
                    cast(void) thread.join();
                    _exit(87);
                }
            }
            return;
        case DeathCase.rwLockUnlockRead:
            RwLock lock;
            lock.unlockRead();
            return;
        case DeathCase.rwLockDoubleUnlockRead:
            RwLock lock;
            lock.lockRead();
            lock.unlockRead();
            lock.unlockRead();
            return;
        case DeathCase.rwLockUnlockWrite:
            RwLock lock;
            lock.unlockWrite();
            return;
        case DeathCase.rwLockDoubleUnlockWrite:
            RwLock lock;
            lock.lockWrite();
            lock.unlockWrite();
            lock.unlockWrite();
            return;
        case DeathCase.rwLockRecursiveWrite:
            version (XTB_Checked)
            {
                RwLock lock;
                lock.lockWrite();
                lock.lockWrite();
            }
            return;
        case DeathCase.rwLockWriterToRead:
            version (XTB_Checked)
            {
                RwLock lock;
                lock.lockWrite();
                lock.lockRead();
            }
            return;
        case DeathCase.rwLockDestroyReadOwned:
            version (XTB_Checked)
            {
                RwLock lock;
                lock.lockRead();
            }
            return;
        case DeathCase.rwLockDestroyWriteOwned:
            version (XTB_Checked)
            {
                RwLock lock;
                lock.lockWrite();
            }
            return;
        case DeathCase.rwLockUnlockWriteNonOwner:
            version (XTB_Checked)
            {
                version (linux)
                {
                    RwLock lock;
                    lock.lockWrite();
                    auto started = Thread.start!rwLockNonOwnerWriteUnlockWorker(
                        &lock,
                    );
                    if (!started.isOk)
                        _exit(96);
                    Thread thread = started.unwrap();
                    cast(void) thread.join();
                    _exit(97);
                }
            }
            return;
        case DeathCase.lockGuardNullMutex:
            LockGuard!Mutex guard = LockGuard!Mutex(null);
            return;
        case DeathCase.readLockGuardNullLock:
            ReadLockGuard!RwLock guard = ReadLockGuard!RwLock(null);
            return;
        case DeathCase.writeLockGuardNullLock:
            WriteLockGuard!RwLock guard = WriteLockGuard!RwLock(null);
            return;
        case DeathCase.lockGuardMoveAssignOwned:
            Mutex firstLock;
            Mutex secondLock;
            LockGuard!Mutex first = LockGuard!Mutex(&firstLock);
            LockGuard!Mutex second = LockGuard!Mutex(&secondLock);
            first = move(second);
            return;
        case DeathCase.readLockGuardMoveAssignOwned:
            RwLock firstLock;
            RwLock secondLock;
            ReadLockGuard!RwLock first = ReadLockGuard!RwLock(&firstLock);
            ReadLockGuard!RwLock second = ReadLockGuard!RwLock(&secondLock);
            first = move(second);
            return;
        case DeathCase.writeLockGuardMoveAssignOwned:
            RwLock firstLock;
            RwLock secondLock;
            WriteLockGuard!RwLock first = WriteLockGuard!RwLock(&firstLock);
            WriteLockGuard!RwLock second = WriteLockGuard!RwLock(&secondLock);
            first = move(second);
            return;
        case DeathCase.lockGuardWrongThread:
            version (XTB_Checked)
            {
                version (linux)
                {
                    Mutex mutex;
                    LockGuard!Mutex guard = LockGuard!Mutex(&mutex);
                    auto started = Thread.start!destroyMutexGuardOnWrongThread(
                        move(guard),
                    );
                    if (!started.isOk)
                        _exit(98);
                    Thread thread = started.unwrap();
                    cast(void) thread.join();
                    _exit(99);
                }
            }
            return;
        case DeathCase.writeLockGuardWrongThread:
            version (XTB_Checked)
            {
                version (linux)
                {
                    RwLock lock;
                    WriteLockGuard!RwLock guard = WriteLockGuard!RwLock(&lock);
                    auto started = Thread.start!destroyWriteGuardOnWrongThread(
                        move(guard),
                    );
                    if (!started.isOk)
                        _exit(100);
                    Thread thread = started.unwrap();
                    cast(void) thread.join();
                    _exit(101);
                }
            }
            return;
        case DeathCase.condVarWaitWithoutOwnership:
            version (XTB_Checked)
            {
                version (linux)
                {
                    Mutex mutex;
                    CondVar condition;
                    condition.wait(mutex);
                    _exit(91);
                }
            }
            return;
        case DeathCase.condVarMixedMutexes:
            version (XTB_Checked)
            {
                version (linux)
                {
                    triggerCondVarMutexMix();
                    _exit(92);
                }
            }
            return;
        case DeathCase.semaphoreOverflow:
            Semaphore full = Semaphore(size_t.max);
            full.release();
            return;
        case DeathCase.latchUnderflow:
            Latch latch = Latch(1);
            latch.countDown(2);
            return;
        case DeathCase.waitGroupOverflow:
            WaitGroup group;
            group.add(size_t.max);
            group.add();
            return;
        case DeathCase.waitGroupUnderflow:
            WaitGroup group;
            group.add();
            group.done(2);
            return;
        case DeathCase.waitGroupDestroyActive:
            version (XTB_Checked)
            {
                WaitGroup group;
                group.add();
            }
            return;
        case DeathCase.barrierZeroParticipants:
            Barrier barrier = Barrier(0);
            return;
        case DeathCase.barrierInitWait:
            Barrier barrier;
            barrier.arriveAndWait();
            return;
        case DeathCase.barrierInitDrop:
            Barrier barrier;
            barrier.arriveAndDrop();
            return;
        case DeathCase.barrierCompletedWait:
            Barrier barrier = Barrier(1);
            barrier.arriveAndDrop();
            barrier.arriveAndWait();
            return;
        case DeathCase.barrierCompletedDrop:
            Barrier barrier = Barrier(1);
            barrier.arriveAndDrop();
            barrier.arriveAndDrop();
            return;
        case DeathCase.onceRecursive:
            version (XTB_Checked)
            {
                Once once;
                callOnce!recursiveOnceInitializer(once, &once);
            }
            return;
        case DeathCase.onceCellRecursive:
            version (XTB_Checked)
            {
                OnceCell!int cell;
                cell.getOrInit!recursiveOnceCellInitializer(&cell);
            }
            return;
        case DeathCase.onceCellDestroyActive:
            version (XTB_Checked)
            {
                version (linux)
                    triggerActiveOnceCellDestroy();
            }
            return;
    }
}

version (Posix) private bool expectAbort(DeathCase deathCase) nothrow @nogc
{
    const process = fork();
    if (process < 0)
        return false;
    if (process == 0)
    {
        runDeathCase(deathCase);
        _exit(0);
    }

    int status;
    return waitpid(process, &status, 0) == process &&
        (status & 0x7f) == SIGABRT;
}

version (linux) private bool hardwareConcurrencyMatchesAffinity() nothrow @nogc
{
    cpu_set_t available;
    if (sched_getaffinity(0, cpu_set_t.sizeof, &available) != 0)
        return hardwareConcurrency() != 0;
    const bytes = (cast(const(ubyte)*)&available)[0 .. cpu_set_t.sizeof];
    uint expected;
    foreach (value; bytes)
    {
        ubyte remaining = value;
        while (remaining != 0)
        {
            remaining &= cast(ubyte)(remaining - 1);
            ++expected;
        }
    }
    return expected > 0 && hardwareConcurrency() == cast(uint) expected;
}

version (linux) private bool rawThreadBasics() nothrow @nogc
{
    auto nullStarted = Thread.startRaw(&nullContextRawWorker);
    if (!nullStarted.isOk)
        return false;
    Thread nullThread = nullStarted.unwrap();
    if (!nullThread.joinable() || nullThread.join() != 17 ||
        nullThread.joinable())
        return false;

    int mutated = 7;
    auto mutationStarted = Thread.startRaw(&mutateRawContext, &mutated);
    if (!mutationStarted.isOk)
        return false;
    Thread mutationThread = mutationStarted.unwrap();
    if (mutationThread.join() != -13 || mutated != 12)
        return false;

    int[7] statuses = [0, 1, -1, 1_234_567, -1_234_567, int.min, int.max];
    foreach (status; statuses)
    {
        int expectedStatus = status;
        auto statusStarted = Thread.startRaw(&statusRawWorker, &expectedStatus);
        if (!statusStarted.isOk)
            return false;
        Thread statusThread = statusStarted.unwrap();
        if (statusThread.join() != expectedStatus)
            return false;
    }

    return true;
}

version (linux) private bool moveOwnershipWorks() nothrow @nogc
{
    auto started = Thread.startRaw(&noOpRawWorker);
    if (!started.isOk)
        return false;
    Thread source = started.unwrap();
    const id = source.id();

    Thread constructed = move(source);
    if (source.joinable() || !constructed.joinable() || constructed.id() != id)
        return false;

    Thread assigned;
    assigned = move(constructed);
    if (constructed.joinable() || !assigned.joinable() || assigned.id() != id)
        return false;
    return assigned.join() == 0;
}

extern (C) int main() nothrow @nogc
{
    static foreach (testFunction; __traits(getUnitTests, atomicModule))
        testFunction();
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
    static foreach (testFunction; __traits(getUnitTests, spinWaitModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, threadScopeModule))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, waitGroupModule))
        testFunction();
    version (linux)
        static foreach (testFunction; __traits(getUnitTests, linuxBackendModule))
            testFunction();

    version (Posix)
    {
        if (!stressFetchAdd())
            return 1;
        if (!releaseAcquirePublishes())
            return 2;
    }

    version (linux)
    {
        if (!atomicWaitImmediateOrders())
            return 40;
        if (!atomicWaitPublishesAndRechecks())
            return 41;
        if (!atomicWaitWakeBeforeParkStress())
            return 42;
        if (!atomicNotifyAllReleasesWaiters())
            return 43;
        if (!signedAtomicWaitUsesValueBits())
            return 45;
        if (!rawThreadBasics())
            return 10;
        if (!typedStartWorks())
            return 46;
        if (!typedMoveLifetimeWorks())
            return 47;
        if (!typedConversionRunsOnParent())
            return 48;
        if (!typedStartFailureCleansUp())
            return 49;
        if (!typedStackOptionsWork())
            return 50;
        if (!typedStartReturnsBeforeWorkerCompletion())
            return 51;
        if (!typedStartShortStress())
            return 52;
        if (!allocatedRawStartWorks())
            return 23;
        if (!allocatedTypedStartWorks())
            return 24;
        if (!allocatedTypedMoveLifetimeWorks())
            return 25;
        if (!allocatedTypedConversionRunsOnParent())
            return 26;
        if (!allocatedStartFailuresCleanUp())
            return 27;
        if (!allocatedTypedStackOptionsWork())
            return 28;
        if (!allocatedDetachCompletes())
            return 29;
        if (!spawnResultsAndOwnershipWork())
            return 98;
        if (!spawnFailuresCleanUp())
            return 99;
        if (!spawnUsesOneStableAllocation())
            return 100;
        if (!spawnOptionsWork())
            return 101;
        if (!spawnHandleMovesAcrossThreads())
            return 102;
        if (!spawnReturnsBeforeWorkerCompletion())
            return 103;
        if (!spawnShortStress())
            return 104;
        if (!threadScopeBorrowingAndManyChildren())
            return 105;
        if (!threadScopeFailuresStillJoinEarlierChildren())
            return 106;
        if (!threadScopeOptionsWork())
            return 107;
        if (!inlineThreadScopeUsesSharedOwnershipCore())
            return 108;
        if (!moveOwnershipWorks())
            return 11;
        if (!rawStartJoinStress())
            return 12;
        if (!rawStartReturnsBeforeWorkerCompletion())
            return 30;
        if (!detachCompletes())
            return 13;
        if (!threadIdentityMatches())
            return 14;
        if (!ldcTlsWorksInRawThread())
            return 15;
        if (!stackSizeIsMinimum())
            return 16;
        if (!tinyStackRequestNormalizes())
            return 17;
        if (!overflowingStackRequestFails())
            return 18;
        if (!currentThreadNaming())
            return 19;
        if (!handleThreadNaming())
            return 20;
        if (!exitedThreadNameIsUnavailable())
            return 21;

        if (!hardwareConcurrencyMatchesAffinity())
            return 22;
        cpuRelax();

        SpinWait spinWait;
        foreach (_; 0 .. 10)
            spinWait.spin();
        spinWait.reset();
        spinWait.spin();

        if (!mutexMutualExclusion())
            return 23;
        if (!mutexHandoffAndPublication())
            return 24;
        if (!condVarNotifyOneAndPublication())
            return 53;
        if (!condVarNotifyOneReleasesOneLogicalWaiter())
            return 54;
        if (!condVarNotifyAllReleasesWaiters())
            return 55;
        if (!condVarNotificationIsNotStored())
            return 56;
        if (!condVarRepeatedWaits())
            return 57;
        if (!semaphoreHandoffPublishes())
            return 58;
        if (!semaphoreReleaseCountIsExact())
            return 59;
        if (!semaphoreRepeatedContention())
            return 60;

        yieldThread();
    }

    version (Posix)
    {
        static foreach (deathCase; [
            DeathCase.loadRelease,
            DeathCase.storeAcquire,
            DeathCase.casReleaseFailure,
            DeathCase.casStrongerFailure,
            DeathCase.flagClearAcquire,
            DeathCase.invalidOrderValue,
            DeathCase.invalidFenceOrder,
            DeathCase.nullRawFunction,
            DeathCase.nullRawAllocFunction,
            DeathCase.nullRawAllocAllocator,
            DeathCase.joinEmpty,
            DeathCase.detachEmpty,
            DeathCase.idEmpty,
            DeathCase.nameEmpty,
            DeathCase.joinTwice,
            DeathCase.detachTwice,
            DeathCase.destroyJoinable,
            DeathCase.moveAssignOverJoinable,
            DeathCase.selfJoin,
            DeathCase.workerPanic,
            DeathCase.spawnNullAllocator,
            DeathCase.spawnJoinEmpty,
            DeathCase.spawnJoinTwice,
            DeathCase.spawnDestroyJoinable,
            DeathCase.spawnMoveAssignOverJoinable,
            DeathCase.spawnSelfJoin,
            DeathCase.spawnWorkerPanic,
            DeathCase.threadScopeNullAllocator,
            DeathCase.threadScopeNullBody,
            DeathCase.threadScopeNullContext,
            DeathCase.threadScopeInertSpawn,
            DeathCase.threadScopeWrongThread,
            DeathCase.threadScopeWorkerPanic,
            DeathCase.mutexUnlockUnlocked,
            DeathCase.mutexDoubleUnlock,
            DeathCase.rwLockUnlockRead,
            DeathCase.rwLockDoubleUnlockRead,
            DeathCase.rwLockUnlockWrite,
            DeathCase.rwLockDoubleUnlockWrite,
            DeathCase.lockGuardNullMutex,
            DeathCase.readLockGuardNullLock,
            DeathCase.writeLockGuardNullLock,
            DeathCase.lockGuardMoveAssignOwned,
            DeathCase.readLockGuardMoveAssignOwned,
            DeathCase.writeLockGuardMoveAssignOwned,
            DeathCase.semaphoreOverflow,
            DeathCase.latchUnderflow,
            DeathCase.waitGroupOverflow,
            DeathCase.waitGroupUnderflow,
            DeathCase.barrierZeroParticipants,
            DeathCase.barrierInitWait,
            DeathCase.barrierInitDrop,
            DeathCase.barrierCompletedWait,
            DeathCase.barrierCompletedDrop,
        ])
            if (!expectAbort(deathCase))
                return 30;
    }

    version (linux)
    {
        static foreach (deathCase; [
            DeathCase.waitRelease,
            DeathCase.waitAcquireRelease,
            DeathCase.invalidWaitOrderValue,
        ])
            if (!expectAbort(deathCase))
                return 44;
    }

    version (XTB_Checked)
        version (linux)
        {
            static foreach (deathCase; [
                DeathCase.mutexRecursiveLock,
                DeathCase.mutexDestroyLocked,
                DeathCase.mutexUnlockNonOwner,
                DeathCase.rwLockRecursiveWrite,
                DeathCase.rwLockWriterToRead,
                DeathCase.rwLockDestroyReadOwned,
                DeathCase.rwLockDestroyWriteOwned,
                DeathCase.rwLockUnlockWriteNonOwner,
                DeathCase.lockGuardWrongThread,
                DeathCase.writeLockGuardWrongThread,
                DeathCase.condVarWaitWithoutOwnership,
                DeathCase.condVarMixedMutexes,
                DeathCase.onceRecursive,
                DeathCase.onceCellRecursive,
                DeathCase.onceCellDestroyActive,
                DeathCase.waitGroupDestroyActive,
            ])
                if (!expectAbort(deathCase))
                    return 45;
        }

    return 0;
}
