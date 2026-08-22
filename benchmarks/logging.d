module benchmarks.logging;

nothrow @nogc:

import core.stdc.stdio : FILE, fclose, fopen, printf;
import core.stdc.stdlib : strtoull;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import xtb.core.logging;
import xtb.core.string : String;
import xtb.core.types : u64;

private enum smallMessage = "small message 0123456789";
private enum fragment = "0123456789abcdefghijklmnopqrstuvwxyz";
private enum largeBytes = 64 * 1024;

private struct SinkProbe
{
    u64 events;
    u64 chunks;
    u64 bytes;
}

private bool nullSink(void* context, scope const LogSinkEvent* event)
{
    SinkProbe* probe = cast(SinkProbe*) context;
    if (probe is null || event is null)
        return false;

    ++probe.events;
    if (event.kind == LogSinkEventKind.messageChunk)
    {
        ++probe.chunks;
        probe.bytes += event.bytes.length;
    }
    return true;
}

private bool benchmarkPrefix(void*, LogPrefixWriter* output)
{
    return output !is null && output.write("prefix ");
}

private u64 monotonicNanoseconds()
{
    timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return 0;
    return cast(u64) now.tv_sec * 1_000_000_000UL + cast(u64) now.tv_nsec;
}

private void fillPayload(char[] payload)
{
    foreach (index, ref ch; payload)
        ch = cast(char)('a' + index % 26);
}

private void printResult(
    scope const(char)* name,
    u64 elapsed,
    size_t iterations,
    scope const ref SinkProbe probe,
)
{
    const nsPerOperation = iterations == 0
        ? 0.0 : cast(double) elapsed / cast(double) iterations;
    printf(
        "%-38s %10.2f ns/op  events=%llu chunks=%llu bytes=%llu\n",
        name,
        nsPerOperation,
        cast(ulong) probe.events,
        cast(ulong) probe.chunks,
        cast(ulong) probe.bytes,
    );
}

private void printTiming(
    scope const(char)* name,
    u64 elapsed,
    size_t iterations,
)
{
    const nsPerOperation = iterations == 0
        ? 0.0 : cast(double) elapsed / cast(double) iterations;
    printf("%-38s %10.2f ns/op\n", name, nsPerOperation);
}

private LogRecordInfo benchmarkRecordInfo()
{
    const style = LogPalette.defaults().info;
    return LogRecordInfo(
        LogLevel.info,
        "[info]",
        style.label,
        style.message,
    );
}

private u64 benchmarkResolvedProtocol(LogSinkRef sink, size_t iterations)
{
    const info = benchmarkRecordInfo();
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
    {
        LogRecordRef record = sink.beginRecord(info);
        if (!record.valid)
            return 0;
        if (!record.beginMessage())
            return 0;
        if (!record.messageChunk(smallMessage))
            return 0;
        if (!record.endMessage())
            return 0;
        if (!record.writeText("\n"))
            return 0;
        if (!record.endRecord())
            return 0;
    }
    return monotonicNanoseconds() - started;
}

private u64 benchmarkNormalSmall(
    ref Logger logger,
    size_t iterations,
)
{
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
        if (!logger.info(smallMessage).delivered)
            return 0;
    return monotonicNanoseconds() - started;
}

private u64 benchmarkStreamSmall(
    ref Logger logger,
    size_t iterations,
)
{
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
    {
        const result = logger.stream(LogLevel.info,
            (scope ref LogMessageWriter output) { output.write(smallMessage); });
        if (!result.delivered)
            return 0;
    }
    return monotonicNanoseconds() - started;
}

private u64 benchmarkNormalLarge(
    ref Logger logger,
    scope String payload,
    size_t iterations,
)
{
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
        if (!logger.info(payload).delivered)
            return 0;
    return monotonicNanoseconds() - started;
}

private u64 benchmarkStreamLargeBorrowed(
    ref Logger logger,
    scope String payload,
    size_t iterations,
)
{
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
    {
        const result = logger.stream(LogLevel.info,
            (scope ref LogMessageWriter output) { output.write(payload); });
        if (!result.delivered)
            return 0;
    }
    return monotonicNanoseconds() - started;
}

private u64 benchmarkStreamFragmented(
    ref Logger logger,
    size_t fragmentsPerMessage,
    size_t iterations,
)
{
    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
    {
        const result = logger.stream(LogLevel.info,
            (scope ref LogMessageWriter output) {
            foreach (__; 0 .. fragmentsPerMessage)
                output.write(fragment);
        });
        if (!result.delivered)
            return 0;
    }
    return monotonicNanoseconds() - started;
}

private void warmUp(ref Logger logger, size_t iterations)
{
    foreach (_; 0 .. iterations)
        logger.info(smallMessage);
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

    const largeIterations = iterations / 100 + 1;
    const fragmentedIterations = iterations / 20 + 1;
    const fragmentsPerMessage = largeBytes / fragment.length;

    char[largeBytes] payloadStorage;
    fillPayload(payloadStorage[]);
    const payload = cast(String) payloadStorage[];

    printf("XTB logging microbenchmark\n");
    printf("iterations=%llu large=%llu fragmented=%llu\n\n",
        cast(ulong) iterations,
        cast(ulong) largeIterations,
        cast(ulong) fragmentedIterations,
    );

    // Isolate the resolved record protocol from formatting and I/O. A direct
    // null sink still receives the same eight semantic events, but setup now
    // resolves the reusable sink graph once before message delivery begins.
    SinkProbe protocolProbe;
    LogSinkRef protocolSink = LogSinkRef.create(&nullSink, &protocolProbe);
    benchmarkResolvedProtocol(protocolSink, iterations / 20 + 1);
    protocolProbe = SinkProbe.init;
    auto elapsed = benchmarkResolvedProtocol(protocolSink, iterations);
    printResult("protocol: resolved direct record", elapsed, iterations, protocolProbe);

    printf("\nNull sink\n");
    SinkProbe nullProbe;
    LogSinkRef nullRef = LogSinkRef.create(&nullSink, &nullProbe);
    char[1024] nullBuffer;
    Logger nullLogger = Logger.create(nullRef, nullBuffer[]);
    warmUp(nullLogger, iterations / 20 + 1);
    nullProbe = SinkProbe.init;

    elapsed = benchmarkNormalSmall(nullLogger, iterations);
    printResult("normal small", elapsed, iterations, nullProbe);

    nullLogger.setCallsitesEnabled(true);
    warmUp(nullLogger, iterations / 20 + 1);
    nullProbe = SinkProbe.init;
    elapsed = benchmarkNormalSmall(nullLogger, iterations);
    printResult("normal small + callsite", elapsed, iterations, nullProbe);
    nullLogger.setCallsitesEnabled(false);

    nullProbe = SinkProbe.init;
    elapsed = benchmarkStreamSmall(nullLogger, iterations);
    printResult("stream small", elapsed, iterations, nullProbe);

    char[largeBytes + 64] largeNormalBuffer;
    Logger largeNullLogger = Logger.create(nullRef, largeNormalBuffer[]);
    nullProbe = SinkProbe.init;
    elapsed = benchmarkNormalLarge(largeNullLogger, payload, largeIterations);
    printResult("normal 64 KiB borrowed", elapsed, largeIterations, nullProbe);

    nullProbe = SinkProbe.init;
    elapsed = benchmarkStreamLargeBorrowed(nullLogger, payload, largeIterations);
    printResult("stream 64 KiB borrowed", elapsed, largeIterations, nullProbe);

    nullProbe = SinkProbe.init;
    elapsed = benchmarkStreamFragmented(
        nullLogger,
        fragmentsPerMessage,
        fragmentedIterations,
    );
    printResult("stream ~64 KiB fragmented", elapsed, fragmentedIterations, nullProbe);

    FILE* devNull = fopen("/dev/null", "wb");
    if (devNull is null)
        return 1;
    scope (exit)
        fclose(devNull);

    printf("\nPlain FILE sink -> /dev/null\n");
    char[1024] plainBuffer;
    Logger plain = Logger.create(plainFileLogSink(devNull), plainBuffer[]);
    warmUp(plain, iterations / 100 + 1);
    plain.flush();
    elapsed = benchmarkNormalSmall(plain, iterations / 4 + 1);
    plain.flush();
    printTiming("normal small", elapsed, iterations / 4 + 1);
    elapsed = benchmarkStreamLargeBorrowed(plain, payload, largeIterations);
    plain.flush();
    printTiming("stream 64 KiB borrowed", elapsed, largeIterations);

    printf("\nANSI FILE sink -> /dev/null\n");
    char[1024] ansiBuffer;
    Logger ansi = Logger.create(ansiFileLogSink(devNull), ansiBuffer[]);
    warmUp(ansi, iterations / 100 + 1);
    ansi.flush();
    elapsed = benchmarkNormalSmall(ansi, iterations / 4 + 1);
    ansi.flush();
    printTiming("normal small", elapsed, iterations / 4 + 1);
    elapsed = benchmarkStreamLargeBorrowed(ansi, payload, largeIterations);
    ansi.flush();
    printTiming("stream 64 KiB borrowed", elapsed, largeIterations);

    printf("\nTee null -> null + null\n");
    SinkProbe firstProbe;
    SinkProbe secondProbe;
    LogSinkRef first = LogSinkRef.create(&nullSink, &firstProbe);
    LogSinkRef second = LogSinkRef.create(&nullSink, &secondProbe);
    TeeLogSink tee = TeeLogSink.create(first, second);
    char[1024] teeBuffer;
    Logger teeLogger = Logger.create(tee.sinkRef(), teeBuffer[]);
    warmUp(teeLogger, iterations / 20 + 1);
    firstProbe = SinkProbe.init;
    secondProbe = SinkProbe.init;
    elapsed = benchmarkNormalSmall(teeLogger, iterations);
    printResult("normal small", elapsed, iterations, firstProbe);
    firstProbe = SinkProbe.init;
    secondProbe = SinkProbe.init;
    elapsed = benchmarkStreamLargeBorrowed(teeLogger, payload, largeIterations);
    printResult("stream 64 KiB borrowed", elapsed, largeIterations, firstProbe);

    printf("\nCallsite -> tee without-callsite + null\n");
    WithoutCallsiteLogSink firstWithoutCallsite = WithoutCallsiteLogSink.create(first);
    TeeLogSink callsiteTee = TeeLogSink.create(firstWithoutCallsite.sinkRef(), second);
    char[1024] callsiteTeeBuffer;
    Logger callsiteTeeLogger = Logger.create(callsiteTee.sinkRef(), callsiteTeeBuffer[]);
    callsiteTeeLogger.setCallsitesEnabled(true);
    warmUp(callsiteTeeLogger, iterations / 20 + 1);
    firstProbe = SinkProbe.init;
    secondProbe = SinkProbe.init;
    elapsed = benchmarkNormalSmall(callsiteTeeLogger, iterations);
    printResult("normal small, suppressed branch", elapsed, iterations, firstProbe);
    if (firstProbe.events != cast(u64) iterations * 8 ||
        secondProbe.events != cast(u64) iterations * 11)
        return 1;

    printf("\nPrefix -> tee null + null\n");
    PrefixLogSink prefixedTee = PrefixLogSink.create(
        tee.sinkRef(),
        LogPrefixRef.create(&benchmarkPrefix, null),
    );
    char[1024] prefixBuffer;
    Logger prefixLogger = Logger.create(prefixedTee.sinkRef(), prefixBuffer[]);
    warmUp(prefixLogger, iterations / 20 + 1);
    firstProbe = SinkProbe.init;
    secondProbe = SinkProbe.init;
    elapsed = benchmarkNormalSmall(prefixLogger, iterations);
    printResult("normal small", elapsed, iterations, firstProbe);
    firstProbe = SinkProbe.init;
    secondProbe = SinkProbe.init;
    elapsed = benchmarkStreamLargeBorrowed(prefixLogger, payload, largeIterations);
    printResult("stream 64 KiB borrowed", elapsed, largeIterations, firstProbe);

    return 0;
}
