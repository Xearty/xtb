module tests.os_layer_tests;

import core.internal.traits : hasElaborateDestructor;
import core.stdc.stdio : FILE, fclose, fflush, fwrite, tmpfile;
import xtb.lifetime : needsDeinit;
import xtb.os.error : OsErrorKind;
import xtb.os.handle : NativeHandle;
import xtb.os.memory_map : MemoryMapping, mapReadOnly, unmap;
import xtb.os.pipe : Pipe, PipeMode, PipeOptions, PipeReadState, PipeReader,
    PipeWriteState, PipeWriter, close, createPipe, readSome, writeSome;
import xtb.os.terminal : isTerminal;
import xtb.os.time : monotonicNanoseconds, sleepNanoseconds,
    wallClockNanoseconds;
import xtb.types : i64, u64, u8;

static assert(!hasElaborateDestructor!MemoryMapping);
static assert(needsDeinit!MemoryMapping);
static assert(!__traits(isCopyable, MemoryMapping));
static assert(!hasElaborateDestructor!PipeReader);
static assert(!hasElaborateDestructor!PipeWriter);
static assert(!hasElaborateDestructor!Pipe);
static assert(needsDeinit!PipeReader);
static assert(needsDeinit!PipeWriter);
static assert(needsDeinit!Pipe);
static assert(!__traits(isCopyable, PipeReader));
static assert(!__traits(isCopyable, PipeWriter));
static assert(!__traits(isCopyable, Pipe));

extern (C) int main()
{
    version (linux)
    {
        import core.sys.posix.stdio : fileno;

        u64 before;
        u64 after;
        assert(monotonicNanoseconds(&before).succeeded);
        assert(sleepNanoseconds(1_000_000).succeeded);
        assert(monotonicNanoseconds(&after).succeeded && after >= before);

        i64 wallTime;
        assert(wallClockNanoseconds(&wallTime).succeeded && wallTime != 0);

        PipeOptions options;
        options.readerMode = PipeMode.nonBlocking;
        Pipe pipe;
        assert(createPipe(options, &pipe).succeeded);
        assert(pipe.valid);

        u8[3] output;
        assert(readSome(&pipe.reader, output[]).state == PipeReadState.wouldBlock);

        u8[3] input = [1, 2, 3];
        const written = writeSome(&pipe.writer, input[]);
        assert(written.error.succeeded && written.state == PipeWriteState.data &&
                written.transferred == input.length);
        const read = readSome(&pipe.reader, output[]);
        assert(read.error.succeeded && read.state == PipeReadState.data &&
                read.transferred == input.length && output == input);
        assert(close(&pipe.writer).succeeded);
        assert(readSome(&pipe.reader, output[]).state == PipeReadState.endOfFile);
        pipe.deinit();

        PipeOptions invalid;
        invalid.readerMode = cast(PipeMode) 2;
        Pipe rejected;
        assert(createPipe(invalid, &rejected).kind == OsErrorKind.invalidArgument);

        FILE* file = tmpfile();
        assert(file !is null);
        assert(!isTerminal(file));
        u8[4] contents = [4, 3, 2, 1];
        assert(fwrite(contents.ptr, 1, contents.length, file) == contents.length);
        assert(fflush(file) == 0);

        MemoryMapping mapping;
        assert(mapReadOnly(
                NativeHandle.fromFileDescriptor(fileno(file)),
                contents.length,
                &mapping,
        ).succeeded);
        assert(mapping.bytes == contents[]);
        assert(fclose(file) == 0);
        assert(unmap(&mapping).succeeded);
        assert(unmap(&mapping).succeeded);
    }
    return 0;
}
