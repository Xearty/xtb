module tests.os_layer_tests;

import core.stdc.stdio : FILE, fclose, fflush, fwrite, tmpfile;
import xtb.os.error : OsErrorKind;
import xtb.os.handle : NativeHandle;
import xtb.os.pipe : Pipe, PipeMode, PipeOptions, PipeReadState, PipeReader,
    PipeWriteState, PipeWriter, close, createPipe, readSome, writeSome;
import xtb.types : i64, u64, u8;

version (Posix)
{
    import posix = xtb.os.posix;
}

version (linux) import linux = xtb.os.linux;

extern (C) int main()
{
    version (linux)
    {
        u64 before;
        u64 after;
        assert(posix.monotonicNanoseconds(&before).succeeded);
        assert(posix.sleepNanoseconds(1_000_000).succeeded);
        assert(posix.monotonicNanoseconds(&after).succeeded && after >= before);

        i64 wallTime;
        assert(posix.wallClockNanoseconds(&wallTime).succeeded && wallTime != 0);

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

        NativeHandle nativeReader;
        NativeHandle nativeWriter;
        assert(linux.createPipe(false, false, &nativeReader, &nativeWriter).succeeded);
        assert(nativeReader.valid && nativeWriter.valid);
        assert(linux.closeHandle(nativeReader).succeeded);
        assert(linux.closeHandle(nativeWriter).succeeded);

        PipeOptions invalid;
        invalid.readerMode = cast(PipeMode) 2;
        Pipe rejected;
        assert(createPipe(invalid, &rejected).kind == OsErrorKind.invalidArgument);

        FILE* file = tmpfile();
        assert(file !is null);
        assert(!posix.isTerminal(posix.fileHandle(file)));
        u8[4] contents = [4, 3, 2, 1];
        assert(fwrite(contents.ptr, 1, contents.length, file) == contents.length);
        assert(fflush(file) == 0);

        void* address;
        assert(posix.mapReadOnly(
                posix.fileHandle(file),
                contents.length,
                &address,
        ).succeeded);
        assert((cast(const(u8)*) address)[0 .. contents.length] == contents[]);
        assert(fclose(file) == 0);
        assert(posix.unmap(address, contents.length).succeeded);
    }
    return 0;
}
