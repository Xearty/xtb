module benchmarks.pools;

nothrow @nogc:

import core.stdc.stdio : fileno, printf, stdout;
import core.stdc.stdlib : getenv, strtoull;
import core.stdc.string : strcmp;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import xtb.core.generational_pool : GenerationalPool;
import xtb.core.pool : Pool;
import xtb.core.types : u64;

private enum uint scanCapacity = 4_096;
private enum uint largeCapacity = 10_000_000;
private enum uint largeLiveCount = 16;
private enum size_t scanSampleCount = 5;
private enum size_t scanWarmupCount = 32;
private enum size_t occupancyWordBits = size_t.sizeof * 8;
private enum size_t occupancyBitCount = cast(size_t) scanCapacity + 1;
private enum size_t occupancyWordCount =
    (occupancyBitCount + occupancyWordBits - 1) / occupancyWordBits;
private enum size_t expectedClusteredNonzeroWords =
    (occupancyWordCount + 7) / 8;
private enum size_t noBitmapWordCount = size_t.max;

private enum ansiReset = "\x1b[0m";
private enum ansiDim = "\x1b[2m";
private enum ansiPool = "\x1b[1;96m";
private enum ansiGenerational = "\x1b[1;95m";
private enum ansiOperations = "\x1b[1;93m";
private enum ansiHeader = "\x1b[1;97m";

private __gshared u64 benchmarkSink;

private u64 monotonicNanoseconds()
{
    timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return 0;
    return cast(u64) now.tv_sec * 1_000_000_000UL + cast(u64) now.tv_nsec;
}

private bool terminalSupportsAnsi() @system
{
    version (Posix)
    {
        import core.sys.posix.unistd : isatty;

        if (isatty(fileno(stdout)) != 1)
            return false;

        const noColor = getenv("NO_COLOR".ptr);
        if (noColor !is null && noColor[0] != '\0')
            return false;

        const term = getenv("TERM".ptr);
        return term is null || strcmp(term, "dumb".ptr) != 0;
    }
    else
        return false;
}

private const(char)* color(bool enabled, const(char)* sequence)
{
    return enabled ? sequence : "".ptr;
}

private struct PoolBitmapStats
{
    size_t liveItems;
    size_t nonzeroWords;
}

private PoolBitmapStats poolBitmapStats(ref Pool!uint pool)
{
    ubyte[occupancyWordCount] seen;
    PoolBitmapStats result;

    foreach (slot; pool.occupiedSlots())
    {
        ++result.liveItems;
        const wordIndex = cast(size_t) slot.index / occupancyWordBits;
        if (seen[wordIndex] == 0)
        {
            seen[wordIndex] = 1;
            ++result.nonzeroWords;
        }
    }

    return result;
}

private void printSection(bool ansi, scope const(char)* sequence, scope const(char)* title)
{
    printf("\n%s%s%s\n", color(ansi, sequence), title, color(ansi, ansiReset.ptr));
}

private void printScanHeader(bool ansi, bool bitmapColumns)
{
    printf("%s%-30s %11s %7s ",
        color(ansi, ansiHeader.ptr),
        "case".ptr,
        "live/slots".ptr,
        "occ.".ptr,
    );
    if (bitmapColumns)
        printf("%10s %10s ", "bm nonzero".ptr, "bm zero".ptr);
    printf("%9s %9s %9s%s\n",
        "ns/live".ptr,
        "ns/slot".ptr,
        "us/scan".ptr,
        color(ansi, ansiReset.ptr),
    );
}

private void printScanTiming(
    scope const(char)* name,
    u64 elapsed,
    size_t scans,
    size_t provisionedSlots,
    size_t liveItems,
    bool bitmapColumns = false,
    size_t nonzeroBitmapWords = noBitmapWordCount,
)
{
    const nsPerScan = scans == 0
        ? 0.0 : cast(double) elapsed / cast(double) scans;
    const nsPerLiveItem = liveItems == 0
        ? 0.0 : nsPerScan / cast(double) liveItems;
    const nsPerProvisionedSlot = provisionedSlots == 0
        ? 0.0 : nsPerScan / cast(double) provisionedSlots;
    const usPerScan = nsPerScan / 1_000.0;
    const occupancyPercent = provisionedSlots == 0
        ? 0.0 : cast(double) liveItems / cast(double) provisionedSlots * 100.0;

    printf("%-30s %4llu/%-6llu %6.2f%% ",
        name,
        cast(ulong) liveItems,
        cast(ulong) provisionedSlots,
        occupancyPercent,
    );
    if (bitmapColumns)
    {
        if (nonzeroBitmapWords == noBitmapWordCount)
            printf("%10s %10s ", "-".ptr, "-".ptr);
        else
            printf("%4llu/%-5llu %10llu ",
                cast(ulong) nonzeroBitmapWords,
                cast(ulong) occupancyWordCount,
                cast(ulong)(occupancyWordCount - nonzeroBitmapWords),
            );
    }
    printf("%9.2f %9.2f %9.2f\n",
        nsPerLiveItem,
        nsPerProvisionedSlot,
        usPerScan,
    );
}

private void printTiming(scope const(char)* name, u64 elapsed, size_t operations)
{
    const nsPerOperation = operations == 0
        ? 0.0 : cast(double) elapsed / cast(double) operations;
    printf("%-40s %10.2f ns/op\n", name, nsPerOperation);
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

private u64 medianScan(alias scan, PoolType)(ref PoolType pool, size_t iterations)
{
    scan(pool, scanWarmupCount);

    u64[scanSampleCount] samples;
    foreach (ref sample; samples)
        sample = scan(pool, iterations);

    foreach (index; 1 .. samples.length)
    {
        const value = samples[index];
        size_t position = index;
        while (position != 0 && samples[position - 1] > value)
        {
            samples[position] = samples[position - 1];
            --position;
        }
        samples[position] = value;
    }

    return samples[samples.length / 2];
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

    const scanIterations = iterations / 10 + 1_000;
    const largeIterations = iterations / 20_000 + 1;

    Pool!uint densePool = Pool!uint.create(scanCapacity);
    scope (exit)
        densePool.deinit();
    Pool!uint sparsePool = Pool!uint.create(scanCapacity);
    scope (exit)
        sparsePool.deinit();
    Pool!uint clusteredPool = Pool!uint.create(scanCapacity);
    scope (exit)
        clusteredPool.deinit();
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
        uint* clustered = clusteredPool.allocateInit();
        *clustered = index;

        const denseHandle = denseGenerational.allocateInit();
        *denseGenerational.get(denseHandle) = index;
        denseHandles[index - 1] = denseHandle;
        const sparseHandle = sparseGenerational.allocateInit();
        *sparseGenerational.get(sparseHandle) = index;
        sparseHandles[index - 1] = sparseHandle;
    }

    // Interleaved sparse layout: keep one slot in eight live. Every 64-bit
    // occupancy word therefore remains nonzero and items() cannot skip a
    // complete bitmap word. GenerationalPool uses the same live pattern.
    foreach (index; 1 .. scanCapacity + 1)
    {
        if ((index & 7) != 0)
        {
            sparsePool.deallocate(sparsePool.get(index));
            sparseGenerational.deallocate(sparseHandles[index - 1]);
        }
    }

    // Clustered sparse layout: keep every eighth *actual Pool bitmap word*
    // live and clear the seven words between them. Pool reserves index zero,
    // so bitmap word boundaries are based on `index / occupancyWordBits`.
    // At capacity 4096 this keeps words 0, 8, ..., 64 and still yields exactly
    // 512 live slots while leaving 56 complete zero words.
    foreach (index; 1 .. scanCapacity + 1)
    {
        const wordIndex = cast(size_t) index / occupancyWordBits;
        if ((wordIndex & 7) != 0)
            clusteredPool.deallocate(clusteredPool.get(index));
    }

    const denseBitmap = poolBitmapStats(densePool);
    const sparseBitmap = poolBitmapStats(sparsePool);
    const clusteredBitmap = poolBitmapStats(clusteredPool);
    const sparseLiveCount = sparseBitmap.liveItems;

    if (denseBitmap.liveItems != scanCapacity ||
        denseBitmap.nonzeroWords != occupancyWordCount ||
        sparseBitmap.liveItems != scanCapacity / 8 ||
        sparseBitmap.nonzeroWords != occupancyWordCount ||
        clusteredBitmap.liveItems != sparseBitmap.liveItems ||
        clusteredBitmap.nonzeroWords != expectedClusteredNonzeroWords)
    {
        printf("benchmark fixture validation failed\n");
        return 1;
    }

    const ansi = terminalSupportsAnsi();

    printf("%sXTB pool microbenchmark%s\n",
        color(ansi, ansiHeader.ptr),
        color(ansi, ansiReset.ptr),
    );
    printf("%soperations=%llu  scan sample=%llu full scans  samples=%llu median  warmup=%llu scans/case%s\n",
        color(ansi, ansiDim.ptr),
        cast(ulong) iterations,
        cast(ulong) scanIterations,
        cast(ulong) scanSampleCount,
        cast(ulong) scanWarmupCount,
        color(ansi, ansiReset.ptr),
    );
    printf("%scapacity=%u  sparse=%u/%u (12.50%%)%s\n",
        color(ansi, ansiDim.ptr),
        scanCapacity,
        cast(uint) sparseLiveCount,
        scanCapacity,
        color(ansi, ansiReset.ptr),
    );
    printf("%sPool bitmap: index 0 reserved; usable indices 1..%u; " ~
            "bitmap covers 0..%u => %llu x %llu-bit words; word = index/%llu%s\n",
        color(ansi, ansiDim.ptr),
        scanCapacity,
        scanCapacity,
        cast(ulong) occupancyWordCount,
        cast(ulong) occupancyWordBits,
        cast(ulong) occupancyWordBits,
        color(ansi, ansiReset.ptr),
    );

    printSection(ansi, ansiPool.ptr, "Pool scans".ptr);
    printScanHeader(ansi, true);

    auto elapsed = medianScan!scanPoolItems(densePool, scanIterations);
    printScanTiming(
        "dense items()".ptr,
        elapsed,
        scanIterations,
        scanCapacity,
        denseBitmap.liveItems,
        true,
        denseBitmap.nonzeroWords,
    );
    elapsed = medianScan!scanPoolIndices(densePool, scanIterations);
    printScanTiming(
        "dense get(index)".ptr,
        elapsed,
        scanIterations,
        scanCapacity,
        scanCapacity,
        true,
        noBitmapWordCount,
    );
    elapsed = medianScan!scanPoolItems(sparsePool, scanIterations);
    printScanTiming(
        "sparse interleaved items()".ptr,
        elapsed,
        scanIterations,
        scanCapacity,
        sparseBitmap.liveItems,
        true,
        sparseBitmap.nonzeroWords,
    );
    elapsed = medianScan!scanPoolItems(clusteredPool, scanIterations);
    printScanTiming(
        "sparse clustered items()".ptr,
        elapsed,
        scanIterations,
        scanCapacity,
        clusteredBitmap.liveItems,
        true,
        clusteredBitmap.nonzeroWords,
    );
    elapsed = medianScan!scanPoolIndices(sparsePool, scanIterations);
    printScanTiming(
        "sparse interleaved get(index)".ptr,
        elapsed,
        scanIterations,
        scanCapacity,
        sparseLiveCount,
        true,
        noBitmapWordCount,
    );

    printf("%s  interleaved: keep every 8th slot; %llu/%llu bitmap words " ~
            "are nonzero, so no whole word can be skipped.%s\n",
        color(ansi, ansiDim.ptr),
        cast(ulong) sparseBitmap.nonzeroWords,
        cast(ulong) occupancyWordCount,
        color(ansi, ansiReset.ptr),
    );
    printf("%s  clustered: keep actual bitmap words 0,8,...,64; " ~
            "%llu/%llu nonzero, %llu zero; live = 63 + 7*64 + 1 = 512.%s\n",
        color(ansi, ansiDim.ptr),
        cast(ulong) clusteredBitmap.nonzeroWords,
        cast(ulong) occupancyWordCount,
        cast(ulong)(
            occupancyWordCount - clusteredBitmap.nonzeroWords),
        color(ansi, ansiReset.ptr),
    );

    printSection(ansi, ansiGenerational.ptr, "GenerationalPool scans".ptr);
    printScanHeader(ansi, false);

    elapsed = medianScan!scanGenerationalItems(denseGenerational, scanIterations);
    printScanTiming(
        "dense items()".ptr,
        elapsed,
        scanIterations,
        scanCapacity,
        scanCapacity,
    );
    elapsed = medianScan!scanGenerationalItems(sparseGenerational, scanIterations);
    printScanTiming(
        "sparse interleaved items()".ptr,
        elapsed,
        scanIterations,
        scanCapacity,
        sparseLiveCount,
    );

    printSection(ansi, ansiOperations.ptr, "Other operations".ptr);
    printf("%s%-40s %10s%s\n",
        color(ansi, ansiHeader.ptr),
        "operation".ptr,
        "ns/op".ptr,
        color(ansi, ansiReset.ptr),
    );

    Pool!uint recycledPool = Pool!uint.create(1);
    scope (exit)
        recycledPool.deinit();
    uint* recycledValue = recycledPool.allocateInit();
    *recycledValue = 7;
    elapsed = recyclePool(recycledPool, recycledValue, iterations);
    printTiming("Pool deallocate+recycle".ptr, elapsed, iterations);

    GenerationalPool!uint recycledGenerational = GenerationalPool!uint.create(1);
    scope (exit)
        recycledGenerational.deinit();
    auto recycledHandle = recycledGenerational.allocateInit();
    *recycledGenerational.get(recycledHandle) = 9;
    elapsed = recycleGenerational(recycledGenerational, recycledHandle, iterations);
    printTiming("Generational deallocate+recycle".ptr, elapsed, iterations);

    elapsed = lookupGenerational(
        denseGenerational,
        denseHandles.ptr,
        denseHandles.length,
        iterations,
    );
    printTiming("Generational get(handle)".ptr, elapsed, iterations);

    elapsed = largeReserveSmallLive(largeIterations);
    printTiming("Generational 10M reserve + 16 live".ptr, elapsed, largeIterations);

    printf("\nchecksum=%llu\n", cast(ulong) benchmarkSink);
    return 0;
}
