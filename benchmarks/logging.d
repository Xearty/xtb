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

private u64 benchmarkCurrentProtocol(LogSinkRef sink, size_t iterations)
{
    LogSinkEvent[8] events = [
        LogSinkEvent.beginRecord(),
        LogSinkEvent.text("[info]"),
        LogSinkEvent.text(" "),
        LogSinkEvent.beginMessage(),
        LogSinkEvent.messageChunk(smallMessage),
        LogSinkEvent.endMessage(),
        LogSinkEvent.text("\n"),
        LogSinkEvent.endRecord(),
    ];

    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
    {
        foreach (ref event; events)
            if (!sink.submit(&event))
                return 0;
    }
    return monotonicNanoseconds() - started;
}

private u64 benchmarkProtocolWithoutMessageBoundaries(
    LogSinkRef sink,
    size_t iterations,
)
{
    LogSinkEvent[6] events = [
        LogSinkEvent.beginRecord(),
        LogSinkEvent.text("[info]"),
        LogSinkEvent.text(" "),
        LogSinkEvent.messageChunk(smallMessage),
        LogSinkEvent.text("\n"),
        LogSinkEvent.endRecord(),
    ];

    const started = monotonicNanoseconds();
    foreach (_; 0 .. iterations)
    {
        foreach (ref event; events)
            if (!sink.submit(&event))
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

    // Isolate the dormant cost of the two message-lifecycle callbacks from
    // formatting and I/O. The second case is deliberately hypothetical: it is
    // not a valid sink record, only the same event sequence with begin/end
    // message removed for comparison.
    SinkProbe protocolProbe;
    LogSinkRef protocolSink = LogSinkRef.create(&nullSink, &protocolProbe);
    benchmarkCurrentProtocol(protocolSink, iterations / 20 + 1);
    protocolProbe = SinkProbe.init;
    auto elapsed = benchmarkCurrentProtocol(protocolSink, iterations);
    printResult("protocol: current 8 events", elapsed, iterations, protocolProbe);

    protocolProbe = SinkProbe.init;
    elapsed = benchmarkProtocolWithoutMessageBoundaries(protocolSink, iterations);
    printResult("protocol: hypothetical 6 events", elapsed, iterations, protocolProbe);

    printf("\nNull sink\n");
    SinkProbe nullProbe;
    LogSinkRef nullRef = LogSinkRef.create(&nullSink, &nullProbe);
    char[1024] nullBuffer;
    Logger nullLogger = Logger.create(nullRef, nullBuffer[]);
    warmUp(nullLogger, iterations / 20 + 1);
    nullProbe = SinkProbe.init;

    elapsed = benchmarkNormalSmall(nullLogger, iterations);
    printResult("normal small", elapsed, iterations, nullProbe);

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

    return 0;
}
