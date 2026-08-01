module tests.core_tests;

import xtb.core.types;
import xtb.core.panic : panic, require;
import xtb.core.metadata;
import xtb.core.slice;
import xtb.core.memory;
import xtb.core.arena;
import xtb.core.thread_context;
import xtb.core.array;
import xtb.core.list;
import xtb.core.logger;
import xtb.core.string;
import xtb.core.print;
import xtb.core.demangle;
import xtb.core.stacktrace_style;
import xtb.core.stacktrace;
import xtb.core.crash;

version (Posix)
{
    import core.stdc.signal : SIGABRT, SIGFPE, SIGILL, SIGSEGV, raise;
    import core.sys.posix.signal : SIGBUS;
    import core.sys.posix.pthread : pthread_create, pthread_join, pthread_t;
    import core.sys.posix.sys.wait : waitpid;
    import core.sys.posix.unistd : STDERR_FILENO, _exit, close, dup2, execl,
        fork, pipe, read;
}

version (Posix)
private extern(C) void* popOnOtherThread(void* context) nothrow @nogc
{
    TempArena* temporary = cast(TempArena*) context;
    (*temporary).pop();
    return null;
}

version (Posix)
private extern(C) void* panicOnOtherThread(void*) nothrow @nogc
{
    panic("intentional worker diagnostic panic");
}

version (Posix)
private extern(C) void* captureMallocAllocator(void* context) nothrow @nogc
{
    *cast(Allocator**) context = mallocAllocator();
    return null;
}

private bool cStringEqual(const(char)* left, const(char)* right)
    nothrow @system @nogc
{
    if (left is null || right is null)
        return left is right;
    size_t index;
    while (left[index] != '\0' && right[index] != '\0')
    {
        if (left[index] != right[index])
            return false;
        ++index;
    }
    return left[index] == right[index];
}

private noreturn runDeathCase(const(char)* name) nothrow @nogc
{
    if (cStringEqual(name, "panic"))
        require(false, "intentional death test");
    if (cStringEqual(name, "scratch-without-context"))
        ScratchScope.acquire();
    if (cStringEqual(name, "double-pop"))
    {
        Arena arena = Arena.create(mallocAllocator(), 64);
        TempArena temporary = (&arena).push();
        temporary.pop();
        temporary.pop();
    }
    if (cStringEqual(name, "non-lifo-pop"))
    {
        Arena arena = Arena.create(mallocAllocator(), 64);
        TempArena outer = (&arena).push();
        TempArena inner = (&arena).push();
        outer.pop();
    }
    if (cStringEqual(name, "scratch-conflict"))
    {
        ThreadContextScope context = ThreadContextScope.acquire(1, 64);
        ScratchScope first = ScratchScope.acquire();
        ScratchScope.acquire(first.allocator);
    }
    version (linux)
    if (cStringEqual(name, "crash-segv-address"))
    {
        CrashHandlerOptions options;
        options.signalTraceMode = SignalTraceMode.faultAddressOnly;
        scope CrashHandlerScope handlers = CrashHandlerScope.install(null, options);
        raise(SIGSEGV);
        panic("fatal signal unexpectedly returned");
    }
    version (linux)
    if (cStringEqual(name, "crash-segv-unwind"))
    {
        CrashHandlerOptions options;
        options.signalTraceMode = SignalTraceMode.attemptStackUnwind;
        scope CrashHandlerScope handlers = CrashHandlerScope.install(null, options);
        raise(SIGSEGV);
        panic("fatal signal unexpectedly returned");
    }
    version (linux)
    if (cStringEqual(name, "crash-abrt"))
    {
        scope CrashHandlerScope handlers = CrashHandlerScope.install();
        raise(SIGABRT);
        panic("fatal signal unexpectedly returned");
    }
    version (linux)
    if (cStringEqual(name, "crash-bus"))
    {
        scope CrashHandlerScope handlers = CrashHandlerScope.install();
        raise(SIGBUS);
        panic("fatal signal unexpectedly returned");
    }
    version (linux)
    if (cStringEqual(name, "crash-fpe"))
    {
        scope CrashHandlerScope handlers = CrashHandlerScope.install();
        raise(SIGFPE);
        panic("fatal signal unexpectedly returned");
    }
    version (linux)
    if (cStringEqual(name, "crash-ill"))
    {
        scope CrashHandlerScope handlers = CrashHandlerScope.install();
        raise(SIGILL);
        panic("fatal signal unexpectedly returned");
    }
    version (linux)
    if (cStringEqual(name, "diagnostic-panic"))
    {
        CrashHandlerOptions options;
        options.signalTraceMode = SignalTraceMode.faultAddressOnly;
        scope CrashHandlerScope handlers = CrashHandlerScope.install(null, options);
        panic("intentional diagnostic panic");
    }
    version (linux)
    if (cStringEqual(name, "diagnostic-panic-thread"))
    {
        CrashHandlerOptions options;
        options.signalTraceMode = SignalTraceMode.faultAddressOnly;
        scope CrashHandlerScope handlers = CrashHandlerScope.install(null, options);
        pthread_t thread;
        if (pthread_create(&thread, null, &panicOnOtherThread, null) != 0)
            panic("pthread_create failed");
        pthread_join(thread, null);
        panic("worker panic unexpectedly returned");
    }
    version (Posix)
    if (cStringEqual(name, "cross-thread-pop"))
    {
        Arena arena = Arena.create(mallocAllocator(), 64);
        TempArena temporary = (&arena).push();
        pthread_t thread;
        if (pthread_create(&thread, null, &popOnOtherThread, &temporary) != 0)
            panic("pthread_create failed");
        pthread_join(thread, null);
        panic("cross-thread pop unexpectedly returned");
    }
    panic("unknown death case");
}

version (Posix)
private struct DeathOutput
{
    char[32 * 1024] storage;
    size_t length;
    int signal;
    bool truncated;

    String text() return scope pure nothrow @system @nogc
    {
        return storage[0 .. length];
    }
}

version (Posix)
private DeathOutput captureDeath(const(char)* executable, const(char)* name)
    nothrow @system @nogc
{
    int[2] descriptors;
    assert(pipe(descriptors) == 0);
    const process = fork();
    assert(process >= 0);
    if (process == 0)
    {
        close(descriptors[0]);
        if (dup2(descriptors[1], STDERR_FILENO) != STDERR_FILENO)
            _exit(125);
        close(descriptors[1]);
        execl(
            executable,
            executable,
            "--death-case".ptr,
            name,
            cast(const(char)*) null,
        );
        _exit(126);
    }

    close(descriptors[1]);
    DeathOutput output;
    char[4096] overflowStorage;
    for (;;)
    {
        char[] destination = output.length < output.storage.length
            ? output.storage[output.length .. $]
            : overflowStorage[];
        const amount = read(
            descriptors[0],
            destination.ptr,
            destination.length,
        );
        if (amount <= 0)
            break;
        if (output.length < output.storage.length)
            output.length += cast(size_t) amount;
        else
            output.truncated = true;
    }
    close(descriptors[0]);

    int status;
    assert(waitpid(process, &status, 0) == process);
    // POSIX exposes these operations as C macros, which have no callable
    // symbol in BetterC. Linux and the BSD/Darwin family use this encoding.
    const terminatingSignal = status & 0x7f;
    assert(terminatingSignal != 0 && terminatingSignal != 0x7f);
    output.signal = terminatingSignal;
    return output;
}

version (Posix)
private void expectDeath(
    const(char)* executable,
    const(char)* name,
    int expectedSignal = SIGABRT,
) nothrow @nogc
{
    DeathOutput output = captureDeath(executable, name);
    assert(output.signal == expectedSignal);
}

version (Posix)
private void expectSignalDiagnostic(
    const(char)* executable,
    const(char)* deathCase,
    int expectedSignal,
    String expectedName,
) nothrow @nogc
{
    DeathOutput output = captureDeath(executable, deathCase);
    assert(output.signal == expectedSignal);
    assert(output.text.contains("Fatal crash: "));
    assert(output.text.contains(expectedName));
    assert(output.text.contains("Stack trace (signal context):"));
    assert(output.text.contains("<faulting instruction>"));
}

extern(C) int main(int argumentCount, char** arguments)
{
    if (argumentCount == 3 && cStringEqual(arguments[1], "--death-case"))
        runDeathCase(arguments[2]);

    static foreach (testFunction; __traits(getUnitTests, xtb.core.types))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.metadata))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.slice))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.memory))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.arena))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.thread_context))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.array))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.list))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.logger))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.string))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.print))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.demangle))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.stacktrace_style))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.stacktrace))
        testFunction();

    version (Posix)
    {
        Allocator* workerAllocator;
        pthread_t allocatorThread;
        assert(pthread_create(
            &allocatorThread,
            null,
            &captureMallocAllocator,
            &workerAllocator,
        ) == 0);
        assert(pthread_join(allocatorThread, null) == 0);
        assert(workerAllocator is mallocAllocator());

        expectDeath(arguments[0], "panic");
        expectDeath(arguments[0], "scratch-without-context");
        expectDeath(arguments[0], "double-pop");
        expectDeath(arguments[0], "non-lifo-pop");
        expectDeath(arguments[0], "scratch-conflict");
        expectDeath(arguments[0], "cross-thread-pop");
        version (linux)
        {
            DeathOutput panicOutput = captureDeath(
                arguments[0],
                "diagnostic-panic",
            );
            assert(panicOutput.signal == SIGABRT);
            assert(panicOutput.text.contains("Stack trace"));
            assert(panicOutput.text.contains("intentional diagnostic panic"));
            assert(panicOutput.text.contains("<rich panic trace printed above>"));
            DeathOutput workerPanic = captureDeath(
                arguments[0],
                "diagnostic-panic-thread",
            );
            assert(workerPanic.signal == SIGABRT);
            assert(workerPanic.text.contains("Stack trace"));
            assert(workerPanic.text.contains("intentional worker diagnostic panic"));
            assert(workerPanic.text.contains("<rich panic trace printed above>"));
            DeathOutput addressOnly = captureDeath(
                arguments[0],
                "crash-segv-address",
            );
            assert(addressOnly.signal == SIGSEGV);
            assert(addressOnly.text.contains("Fatal crash: "));
            assert(addressOnly.text.contains("SIGSEGV"));
            assert(addressOnly.text.contains("Stack trace (signal context):"));
            assert(addressOnly.text.contains("<faulting instruction>"));
            assert(addressOnly.text.contains(
                "<fault-address-only mode: stack unwinding disabled>",
            ));

            DeathOutput unwound = captureDeath(
                arguments[0],
                "crash-segv-unwind",
            );
            assert(unwound.signal == SIGSEGV);
            assert(unwound.text.contains("SIGSEGV"));
            assert(unwound.text.contains("+1"));

            expectSignalDiagnostic(
                arguments[0], "crash-abrt", SIGABRT, "SIGABRT",
            );
            expectSignalDiagnostic(
                arguments[0], "crash-bus", SIGBUS, "SIGBUS",
            );
            expectSignalDiagnostic(
                arguments[0], "crash-fpe", SIGFPE, "SIGFPE",
            );
            expectSignalDiagnostic(
                arguments[0], "crash-ill", SIGILL, "SIGILL",
            );
        }
    }
    return 0;
}
