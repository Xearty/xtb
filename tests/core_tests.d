module tests.core_tests;

import xtb.core.types;
import xtb.core.numeric;
import xtb.core.duration;
import xtb.core.panic : panic;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.metadata;
import xtb.core.slice;
import xtb.core.memory;
import xtb.core.lifetime;
import xtb.core.allocators;
import xtb.core.allocators.arena;
import xtb.core.thread_context;
import xtb.core.array;
import xtb.core.option;
import xtb.core.result;
import xtb.core.flag_set;
import xtb.core.intrusive_list;
import xtb.core.hash;
import xtb.core.hash_map;
import xtb.core.logger;
import xtb.core.thread_logger;
import xtb.core.utf8;
import xtb.core.string;
import xtb.core.owned_string;
import xtb.core.string_hash_map;
import xtb.core.string_hash_set;
import xtb.core.print;
import xtb.core.ansi;
import xtb.diagnostics.demangle;
import xtb.diagnostics.stacktrace_style;
import xtb.diagnostics.stacktrace;
import xtb.diagnostics.crash;

static assert(__traits(hasMember, StringBuf, "append"));
static assert(__traits(hasMember, Array!int, "append"));
static assert(__traits(hasMember, Option!int, "take"));
static assert(__traits(hasMember, Option!int, "unwrap"));
static assert(__traits(hasMember, Option!int, "expect"));
static assert(__traits(hasMember, Result!(int, int), "take"));
static assert(__traits(hasMember, Result!(int, int), "unwrap"));
static assert(__traits(hasMember, Result!(int, int), "unwrapError"));
static assert(__traits(hasMember, OwnedString, "view"));
static assert(__traits(hasMember, HashMap!(int, int), "set"));
static assert(__traits(hasMember, HashSet!int, "contains"));
static assert(__traits(hasMember, StringHashMapUnmanaged!int, "set"));
static assert(__traits(hasMember, StringHashMap!int, "set"));
static assert(__traits(hasMember, StringHashSetUnmanaged, "contains"));
static assert(__traits(hasMember, StringHashSet, "contains"));
static assert(__traits(compiles,
        (cast(StringBuf*) null).append("member lookup")));
static assert(__traits(compiles,
        (cast(const(StringBuf)*) null).view));

version (Posix)
{
    import core.stdc.signal : SIGABRT, SIGFPE, SIGILL, SIGSEGV, raise;
    import core.sys.posix.signal : SIGBUS;
    import core.sys.posix.pthread : pthread_create, pthread_join, pthread_t;
    import core.sys.posix.sys.wait : waitpid;
    import core.sys.posix.unistd : STDERR_FILENO, _exit, close, dup2, execl,
        fork, pipe, read;
}

version (Posix) private extern (C) void* popOnOtherThread(void* context) nothrow @nogc
{
    TempArena* temporary = cast(TempArena*) context;
    (*temporary).pop();
    return null;
}

version (Posix) private extern (C) void* panicOnOtherThread(void*) nothrow @nogc
{
    panic("intentional worker diagnostic panic");
}

version (Posix) private extern (C) void* captureMallocAllocator(void* context) nothrow @nogc
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

private enum DeathFlag
{
    first,
    third = 2,
}

private noreturn runDeathCase(const(char)* name) nothrow @nogc
{
    if (cStringEqual(name, "panic"))
        version (XTB_Checked)
            require(false, "intentional death test");
    if (cStringEqual(name, "numeric-clamp"))
        clamp(0, 1, 0);
    if (cStringEqual(name, "numeric-overflow"))
        tebibytes(size_t.max);
    if (cStringEqual(name, "duration-negative"))
        milliseconds(-1);
    if (cStringEqual(name, "duration-conversion-overflow"))
        days(u64.max);
    if (cStringEqual(name, "duration-addition-overflow"))
        Duration.max + nanoseconds(1);
    if (cStringEqual(name, "duration-subtraction-underflow"))
        Duration.init - nanoseconds(1);
    if (cStringEqual(name, "duration-multiplication-overflow"))
        Duration.max * 2;
    if (cStringEqual(name, "duration-negative-scale"))
        seconds(1) * -1;
    if (cStringEqual(name, "duration-division-by-zero"))
        seconds(1) / 0;
    if (cStringEqual(name, "string-bytes-null-output"))
        StringBuf.tryFromBytesUnchecked(mallocAllocator(), null, null);
    if (cStringEqual(name, "unmanaged-null-fallible-factory"))
    {
        ArrayUnmanaged!int output;
        ArrayUnmanaged!int.tryWithCapacity(null, 0, &output);
    }
    if (cStringEqual(name, "unmanaged-null-returning-factory"))
        ArrayUnmanaged!int.withCapacity(null, 0);
    if (cStringEqual(name, "managed-null-fallible-factory"))
    {
        Array!int output;
        Array!int.tryWithCapacity(null, 0, &output);
    }
    if (cStringEqual(name, "managed-null-returning-factory"))
        Array!int.withCapacity(null, 0);
    if (cStringEqual(name, "owned-string-null-pointer"))
        (cast(OwnedString*) null).deinit();
    if (cStringEqual(name, "string-split-slice"))
        "é".sliceBytes(1, 2);
    if (cStringEqual(name, "string-split-insert"))
    {
        StringBuf text = StringBuf.fromString(mallocAllocator(), "é");
        text.insert(1, "x");
    }
    if (cStringEqual(name, "string-split-truncate"))
    {
        StringBuf text = StringBuf.fromString(mallocAllocator(), "é");
        text.truncateBytes(1);
    }
    if (cStringEqual(name, "string-non-ascii-char"))
    {
        StringBuf text = StringBuf.create(mallocAllocator());
        text.append(cast(char) 0xc3);
    }
    if (cStringEqual(name, "print-invalid-code-point"))
        write(cast(dchar) 0xd800);
    if (cStringEqual(name, "bit-flags-invalid-value"))
    {
        FlagSet!DeathFlag flags;
        flags.enable(cast(DeathFlag) 1);
    }
    if (cStringEqual(name, "bit-flags-invalid-mask"))
        FlagSet!DeathFlag.fromBits(0b010);
    if (cStringEqual(name, "bit-flags-null-output"))
        FlagSet!DeathFlag.tryFromBits(0, null);
    if (cStringEqual(name, "option-unwrap-none"))
    {
        Option!int option = none();
        option.unwrap();
    }
    if (cStringEqual(name, "option-expect-none"))
    {
        Option!int option = none();
        option.expect("expected option value");
    }
    if (cStringEqual(name, "result-unwrap-err"))
    {
        auto result = Result!(int, int).err(1);
        result.unwrap();
    }
    if (cStringEqual(name, "result-unwrap-empty"))
    {
        Result!(int, int) result;
        result.unwrap();
    }
    if (cStringEqual(name, "result-expect-err"))
    {
        auto result = Result!(int, int).err(1);
        result.expect("expected result value");
    }
    if (cStringEqual(name, "result-unwrap-error-ok"))
    {
        auto result = Result!(int, int).ok(1);
        result.unwrapError();
    }
    if (cStringEqual(name, "result-expect-error-ok"))
    {
        auto result = Result!(int, int).ok(1);
        result.expectError("expected result error");
    }
    if (cStringEqual(name, "scratch-without-context"))
        ScratchScope.acquire();
    if (cStringEqual(name, "thread-logger-null"))
        ThreadLoggerScope.install(null);
    if (cStringEqual(name, "thread-logger-without-context"))
    {
        char[16] storage;
        Logger logger = stderrLogger(storage[]);
        ThreadLoggerScope.install(&logger);
    }
    if (cStringEqual(name, "thread-logger-invalid"))
    {
        ThreadContextScope context = ThreadContextScope.acquire();
        Logger logger;
        ThreadLoggerScope.install(&logger);
    }
    if (cStringEqual(name, "thread-context-before-logger"))
    {
        ThreadContextScope context = ThreadContextScope.acquire();
        char[16] storage;
        Logger logger = stderrLogger(storage[]);
        ThreadLoggerScope logging = ThreadLoggerScope.install(&logger);
        context.__dtor();
    }
    if (cStringEqual(name, "thread-loggers-non-lifo"))
    {
        ThreadContextScope context = ThreadContextScope.acquire();
        char[16] firstStorage;
        char[16] secondStorage;
        Logger first = stderrLogger(firstStorage[]);
        Logger second = stderrLogger(secondStorage[]);
        ThreadLoggerScope outer = ThreadLoggerScope.install(&first);
        ThreadLoggerScope inner = ThreadLoggerScope.install(&second);
        outer.__dtor();
    }
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
    version (XTB_Checked)
        if (cStringEqual(name, "intrusive-list-double-link"))
        {
            struct Node
            {
                ListHook!Node listHook;
            }

            Node node;
            IntrusiveList!Node first;
            IntrusiveList!Node second;
            first.pushBack(&node);
            second.pushBack(&node);
        }
    version (XTB_Checked)
        if (cStringEqual(name, "intrusive-forward-list-double-link"))
        {
            struct Node
            {
                ForwardListHook!Node forwardListHook;
            }

            Node node;
            IntrusiveForwardList!Node first;
            IntrusiveForwardList!Node second;
            first.pushBack(&node);
            second.pushBack(&node);
        }
    version (XTB_Checked)
        if (cStringEqual(name, "intrusive-forward-double-link"))
        {
            struct Node
            {
                ForwardListHook!Node forwardListHook;
            }

            Node node;
            IntrusiveQueue!Node queue;
            IntrusiveStack!Node stack;
            queue.pushBack(&node);
            stack.push(&node);
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

version (Posix) private struct DeathOutput
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

version (Posix) private DeathOutput captureDeath(const(char)* executable, const(char)* name)
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
            ? output.storage[output.length .. $] : overflowStorage[];
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

version (Posix) private void expectDeath(
    const(char)* executable,
    const(char)* name,
    int expectedSignal = SIGABRT,
) nothrow @nogc
{
    DeathOutput output = captureDeath(executable, name);
    assert(output.signal == expectedSignal);
}

version (Posix) private void expectSignalDiagnostic(
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

extern (C) int main(int argumentCount, char** arguments)
{
    if (argumentCount == 3 && cStringEqual(arguments[1], "--death-case"))
        runDeathCase(arguments[2]);

    static foreach (testFunction; __traits(getUnitTests, xtb.core.types))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.numeric))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.duration))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.metadata))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.slice))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.memory))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.lifetime))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.allocators.arena))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.thread_context))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.array))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.option))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.result))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.flag_set))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.intrusive_list))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.hash))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.hash_map))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.logger))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.thread_logger))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.string))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.owned_string))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.string_hash_map))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.string_hash_set))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.print))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.core.ansi))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.diagnostics.demangle))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.diagnostics.stacktrace_style))
        testFunction();
    static foreach (testFunction; __traits(getUnitTests, xtb.diagnostics.stacktrace))
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
        expectDeath(arguments[0], "numeric-clamp");
        expectDeath(arguments[0], "numeric-overflow");
        expectDeath(arguments[0], "duration-negative");
        expectDeath(arguments[0], "duration-conversion-overflow");
        expectDeath(arguments[0], "duration-addition-overflow");
        expectDeath(arguments[0], "duration-subtraction-underflow");
        expectDeath(arguments[0], "duration-multiplication-overflow");
        expectDeath(arguments[0], "duration-negative-scale");
        expectDeath(arguments[0], "duration-division-by-zero");
        expectDeath(arguments[0], "string-bytes-null-output");
        expectDeath(arguments[0], "unmanaged-null-fallible-factory");
        expectDeath(arguments[0], "unmanaged-null-returning-factory");
        expectDeath(arguments[0], "managed-null-fallible-factory");
        expectDeath(arguments[0], "managed-null-returning-factory");
        expectDeath(arguments[0], "owned-string-null-pointer");
        expectDeath(arguments[0], "string-split-slice");
        expectDeath(arguments[0], "string-split-insert");
        expectDeath(arguments[0], "string-split-truncate");
        expectDeath(arguments[0], "string-non-ascii-char");
        expectDeath(arguments[0], "print-invalid-code-point");
        expectDeath(arguments[0], "bit-flags-invalid-value");
        expectDeath(arguments[0], "bit-flags-invalid-mask");
        expectDeath(arguments[0], "bit-flags-null-output");
        expectDeath(arguments[0], "option-unwrap-none");
        expectDeath(arguments[0], "option-expect-none");
        expectDeath(arguments[0], "result-unwrap-err");
        expectDeath(arguments[0], "result-unwrap-empty");
        expectDeath(arguments[0], "result-expect-err");
        expectDeath(arguments[0], "result-unwrap-error-ok");
        expectDeath(arguments[0], "result-expect-error-ok");
        expectDeath(arguments[0], "scratch-without-context");
        expectDeath(arguments[0], "thread-logger-null");
        expectDeath(arguments[0], "thread-logger-without-context");
        expectDeath(arguments[0], "thread-logger-invalid");
        expectDeath(arguments[0], "thread-context-before-logger");
        expectDeath(arguments[0], "thread-loggers-non-lifo");
        expectDeath(arguments[0], "double-pop");
        expectDeath(arguments[0], "non-lifo-pop");
        expectDeath(arguments[0], "scratch-conflict");
        version (XTB_Checked)
        {
            expectDeath(arguments[0], "intrusive-list-double-link");
            expectDeath(arguments[0], "intrusive-forward-list-double-link");
            expectDeath(arguments[0], "intrusive-forward-double-link");
        }
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
