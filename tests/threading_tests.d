module tests.threading_tests;

import xtb.threading;
import atomicModule = xtb.threading.atomic;

version (Posix)
{
    import core.stdc.signal : SIGABRT;
    import core.sys.posix.pthread : pthread_create, pthread_join, pthread_t;
    import core.sys.posix.sys.wait : waitpid;
    import core.sys.posix.unistd : _exit, fork;
}

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

version (Posix) private enum DeathCase : ubyte
{
    loadRelease,
    storeAcquire,
    casReleaseFailure,
    casStrongerFailure,
    flagClearAcquire,
    invalidOrderValue,
    invalidFenceOrder,
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

extern (C) int main() nothrow @nogc
{
    static foreach (testFunction; __traits(getUnitTests, atomicModule))
        testFunction();

    version (Posix)
    {
        if (!stressFetchAdd())
            return 1;
        if (!releaseAcquirePublishes())
            return 2;

        static foreach (deathCase; [
            DeathCase.loadRelease,
            DeathCase.storeAcquire,
            DeathCase.casReleaseFailure,
            DeathCase.casStrongerFailure,
            DeathCase.flagClearAcquire,
            DeathCase.invalidOrderValue,
            DeathCase.invalidFenceOrder,
        ])
            if (!expectAbort(deathCase))
                return 3;
    }

    return 0;
}
