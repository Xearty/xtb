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
    import core.sys.posix.pthread : pthread_create, pthread_join, pthread_t;
    import core.sys.posix.sys.wait : waitpid;
    import core.sys.posix.unistd : _exit, execl, fork;
}

version (Posix)
private extern(C) void* popOnOtherThread(void* context) nothrow @nogc
{
    TempArena* temporary = cast(TempArena*) context;
    (*temporary).pop();
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
    version (Posix)
    if (cStringEqual(name, "crash-signal"))
    {
        import core.stdc.signal : SIGSEGV, raise;

        CrashHandlerOptions options;
        options.signalTraceMode = SignalTraceMode.faultAddressOnly;
        scope CrashHandlerScope handlers = CrashHandlerScope.install(null, options);
        raise(SIGSEGV);
        panic("fatal signal unexpectedly returned");
    }
    version (Posix)
    if (cStringEqual(name, "diagnostic-panic"))
    {
        CrashHandlerOptions options;
        options.signalTraceMode = SignalTraceMode.faultAddressOnly;
        scope CrashHandlerScope handlers = CrashHandlerScope.install(null, options);
        panic("intentional diagnostic panic");
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
private void expectDeath(const(char)* executable, const(char)* name)
    nothrow @nogc
{
    const process = fork();
    assert(process >= 0);
    if (process == 0)
    {
        execl(
            executable,
            executable,
            "--death-case".ptr,
            name,
            cast(const(char)*) null,
        );
        _exit(126);
    }
    int status;
    assert(waitpid(process, &status, 0) == process);
    assert(status != 0);
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
        expectDeath(arguments[0], "panic");
        expectDeath(arguments[0], "scratch-without-context");
        expectDeath(arguments[0], "double-pop");
        expectDeath(arguments[0], "non-lifo-pop");
        expectDeath(arguments[0], "scratch-conflict");
        expectDeath(arguments[0], "cross-thread-pop");
        expectDeath(arguments[0], "crash-signal");
        expectDeath(arguments[0], "diagnostic-panic");
    }
    return 0;
}
