module benchmarks.pools;

nothrow @nogc:

import core.stdc.stdio : printf;
import core.stdc.stdlib : strtoull;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import xtb.core.generational_pool : GenerationalPool;
import xtb.core.pool : Pool;
import xtb.core.types : u64;

private enum uint scanCapacity = 4_096;
private enum uint largeCapacity = 10_000_000;
private enum uint largeLiveCount = 16;

private __gshared u64 benchmarkSink;

private u64 monotonicNanoseconds()
{
    timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return 0;
    return cast(u64) now.tv_sec * 1_000_000_000UL + cast(u64) now.tv_nsec;
}

private void printTiming(scope const(char)* name, u64 elapsed, size_t operations)
{
    const nsPerOperation = operations == 0
        ? 0.0 : cast(double) elapsed / cast(double) operations;
    printf("%-42s %10.2f ns/op\n", name, nsPerOperation);
}

private u64 scanPoolItems(ref Pool!uint pool, size_t iterations)
{
    u64 sum;
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
        foreach (ref value; pool.items())
            sum += value;
    benchmarkSink += sum;
    return monotonicNanoseconds() - started;
}

private u64 scanPoolIndices(ref Pool!uint pool, size_t iterations)
{
    u64 sum;
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
        foreach (index; 1 .. pool.capacity + 1)
        {
            const value = pool.get(index);
            if (value !is null)
                sum += *value;
        }
    benchmarkSink += sum;
    return monotonicNanoseconds() - started;
}

private u64 scanGenerationalItems(ref GenerationalPool!uint pool, size_t iterations)
{
    u64 sum;
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
        foreach (ref value; pool.items())
            sum += value;
    benchmarkSink += sum;
    return monotonicNanoseconds() - started;
}

private u64 recyclePool(ref Pool!uint pool, uint* value, size_t iterations)
{
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
    {
        pool.deallocate(value);
        value = pool.allocate();
    }
    benchmarkSink += *value;
    return monotonicNanoseconds() - started;
}

private u64 recycleGenerational(
    ref GenerationalPool!uint pool,
    GenerationalPool!uint.Handle handle,
    size_t iterations,
)
{
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
    {
        pool.deallocate(handle);
        handle = pool.allocate();
    }
    benchmarkSink += handle.generation;
    return monotonicNanoseconds() - started;
}

private u64 lookupGenerational(
    ref GenerationalPool!uint pool,
    scope const(GenerationalPool!uint.Handle)* handles,
    size_t handleCount,
    size_t iterations,
)
{
    u64 sum;
    const started = monotonicNanoseconds();
    foreach (iteration; 0 .. iterations)
    {
        const handle = handles[iteration & (handleCount - 1)];
        sum += *pool.get(handle);
    }
    benchmarkSink += sum;
    return monotonicNanoseconds() - started;
}

private u64 largeReserveSmallLive(size_t iterations)
{
    u64 sum;
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
    {
        auto pool = GenerationalPool!uint.create(largeCapacity);
        foreach (__; 0 .. largeLiveCount)
        {
            const handle = pool.allocateInit();
            *pool.get(handle) = handle.index;
            sum += handle.index;
        }
        pool.deinit();
    }
    benchmarkSink += sum;
    return monotonicNanoseconds() - started;
}

extern (C) int main(int argc, char** argv)
{
    size_t iterations = 200_000;
    if (argc >= 2)
    {
        const parsed = strtoull(argv[1], null, 10);
        if (parsed != 0)
            iterations = cast(size_t) parsed;
    }

    const scanIterations = iterations / 1_000 + 10;
    const largeIterations = iterations / 20_000 + 1;

    Pool!uint densePool = Pool!uint.create(scanCapacity);
    scope (exit)
        densePool.deinit();
    Pool!uint sparsePool = Pool!uint.create(scanCapacity);
    scope (exit)
        sparsePool.deinit();
    GenerationalPool!uint denseGenerational = GenerationalPool!uint.create(scanCapacity);
    scope (exit)
        denseGenerational.deinit();
    GenerationalPool!uint sparseGenerational = GenerationalPool!uint.create(scanCapacity);
    scope (exit)
        sparseGenerational.deinit();

    GenerationalPool!uint.Handle[scanCapacity] denseHandles;
    GenerationalPool!uint.Handle[scanCapacity] sparseHandles;
    foreach (index; 1 .. scanCapacity + 1)
    {
        uint* dense = densePool.allocateInit();
        *dense = index;
        uint* sparse = sparsePool.allocateInit();
        *sparse = index;

        const denseHandle = denseGenerational.allocateInit();
        *denseGenerational.get(denseHandle) = index;
        denseHandles[index - 1] = denseHandle;
        const sparseHandle = sparseGenerational.allocateInit();
        *sparseGenerational.get(sparseHandle) = index;
        sparseHandles[index - 1] = sparseHandle;
    }

    // Keep one slot in eight live in the sparse pools.
    foreach (index; 1 .. scanCapacity + 1)
    {
        if ((index & 7) != 0)
        {
            sparsePool.deallocate(sparsePool.get(index));
            sparseGenerational.deallocate(sparseHandles[index - 1]);
        }
    }

    printf("XTB pool microbenchmark\n");
    printf("iterations=%llu scans=%llu capacity=%u sparse-live=%u\n\n",
        cast(ulong) iterations,
        cast(ulong) scanIterations,
        scanCapacity,
        scanCapacity / 8,
    );

    auto elapsed = scanPoolItems(densePool, scanIterations);
    printTiming("Pool dense items() per visited item", elapsed,
        scanIterations * scanCapacity);
    elapsed = scanPoolIndices(densePool, scanIterations);
    printTiming("Pool dense get(index) per slot", elapsed,
        scanIterations * scanCapacity);
    elapsed = scanPoolItems(sparsePool, scanIterations);
    printTiming("Pool sparse items() per live item", elapsed,
        scanIterations * (scanCapacity / 8));
    elapsed = scanPoolIndices(sparsePool, scanIterations);
    printTiming("Pool sparse get(index) per slot", elapsed,
        scanIterations * scanCapacity);

    elapsed = scanGenerationalItems(denseGenerational, scanIterations);
    printTiming("Generational dense items() per live item", elapsed,
        scanIterations * scanCapacity);
    elapsed = scanGenerationalItems(sparseGenerational, scanIterations);
    printTiming("Generational sparse items() per live item", elapsed,
        scanIterations * (scanCapacity / 8));

    Pool!uint recycledPool = Pool!uint.create(1);
    scope (exit)
        recycledPool.deinit();
    uint* recycledValue = recycledPool.allocateInit();
    *recycledValue = 7;
    elapsed = recyclePool(recycledPool, recycledValue, iterations);
    printTiming("Pool deallocate+recycle", elapsed, iterations);

    GenerationalPool!uint recycledGenerational = GenerationalPool!uint.create(1);
    scope (exit)
        recycledGenerational.deinit();
    auto recycledHandle = recycledGenerational.allocateInit();
    *recycledGenerational.get(recycledHandle) = 9;
    elapsed = recycleGenerational(recycledGenerational, recycledHandle, iterations);
    printTiming("Generational deallocate+recycle", elapsed, iterations);

    elapsed = lookupGenerational(
        denseGenerational,
        denseHandles.ptr,
        denseHandles.length,
        iterations,
    );
    printTiming("Generational get(handle)", elapsed, iterations);

    elapsed = largeReserveSmallLive(largeIterations);
    printTiming("Generational 10M reserve + 16 live", elapsed, largeIterations);

    printf("\nchecksum=%llu\n", cast(ulong) benchmarkSink);
    return 0;
}
