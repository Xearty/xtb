module xtb.threading.internal.thread_linux;

// dfmt off
version (linux):
// dfmt on
nothrow @nogc:

import core.stdc.errno : EAGAIN, EINVAL, ENOENT, ENOMEM, ENOSYS, EPERM, ERANGE, ESRCH;
import core.stdc.stdint : intptr_t;
import core.sys.linux.sched : cpu_set_t, sched_getaffinity;
import core.sys.posix.pthread : pthread_attr_destroy,
    pthread_attr_init,
    pthread_attr_setstacksize,
    pthread_attr_t,
    pthread_create,
    pthread_detach,
    pthread_equal,
    pthread_join,
    pthread_self,
    pthread_t;
import core.sys.posix.sched : sched_yield;
import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN,
    _SC_PAGESIZE,
    _SC_THREAD_STACK_MIN,
    sysconf;
import xtb.core.panic : panic;
import xtb.core.types : String;
import xtb.threading.internal.start_latch : StartLatch, startLatchSupported;

static if (!startLatchSupported)
{
    import xtb.threading.atomic : Atomic, MemoryOrder;
    import xtb.threading.spin_wait : cpuRelax;
}

alias NativeRawThreadFn = int function(void* context) nothrow @nogc;
private alias NativeThreadEntryFn = extern (C) void* function(void* context) nothrow @nogc;

/// Stable caller-owned start state for a native thread.
///
/// The pointed object must remain valid until the native trampoline has
/// copied both fields and entered `function_`.
struct NativeStableStartPacket
{
    NativeRawThreadFn function_;
    void* context;
}

enum NativeThreadStartErrorKind : ubyte
{
    unsupported,
    resourceExhausted,
    permissionDenied,
    invalidConfiguration,
    system,
}

struct NativeThreadHandle
{
    pthread_t value;
}

struct NativeThreadStartResult
{
    bool succeeded;
    NativeThreadHandle handle;
    NativeThreadStartErrorKind kind;
    int nativeCode;
}

struct NativeJoinResult
{
    bool succeeded;
    int status;
    int nativeCode;
}

enum NativeThreadNameErrorKind : ubyte
{
    unsupported,
    invalidName,
    tooLong,
    threadUnavailable,
    system,
}

struct NativeThreadNameResult
{
    bool succeeded;
    NativeThreadNameErrorKind kind;
    int nativeCode;
}

private struct RawStartPacket
{
    NativeRawThreadFn function_;
    void* context;
    static if (startLatchSupported)
        StartLatch captured;
    else
        Atomic!uint captured;
}

private void* encodeThreadStatus(int status) pure @trusted
{
    return cast(void*) cast(intptr_t) status;
}

private extern (C) void* rawThreadTrampoline(void* opaque) @system
{
    RawStartPacket* packet = cast(RawStartPacket*) opaque;
    const function_ = packet.function_;
    void* context = packet.context;

    // Signaling marks the final access to parent-stack packet storage.
    static if (startLatchSupported)
        packet.captured.signal();
    else
        packet.captured.store(1, MemoryOrder.release);

    return encodeThreadStatus(function_(context));
}

private extern (C) void* stableThreadTrampoline(void* opaque) @system
{
    NativeStableStartPacket* packet = cast(NativeStableStartPacket*) opaque;
    const function_ = packet.function_;
    void* context = packet.context;

    // The packet is caller-owned stable storage. Once these two values have
    // been copied, the portable callback owns the remaining lifetime
    // protocol and may release the packet before invoking user work.
    return encodeThreadStatus(function_(context));
}

private NativeThreadStartResult startFailure(
    NativeThreadStartErrorKind kind,
    int nativeCode,
) pure @safe
{
    return NativeThreadStartResult(
        false,
        NativeThreadHandle.init,
        kind,
        nativeCode,
    );
}

private NativeThreadStartErrorKind mapStartError(int code) pure @safe
{
    switch (code)
    {
        case EAGAIN:
        case ENOMEM:
            return NativeThreadStartErrorKind.resourceExhausted;
        case EPERM:
            return NativeThreadStartErrorKind.permissionDenied;
        case EINVAL:
            return NativeThreadStartErrorKind.invalidConfiguration;
        default:
            return NativeThreadStartErrorKind.system;
    }
}

unittest
{
    assert(mapStartError(EAGAIN) ==
            NativeThreadStartErrorKind.resourceExhausted);
    assert(mapStartError(ENOMEM) ==
            NativeThreadStartErrorKind.resourceExhausted);
    assert(mapStartError(EPERM) ==
            NativeThreadStartErrorKind.permissionDenied);
    assert(mapStartError(EINVAL) ==
            NativeThreadStartErrorKind.invalidConfiguration);
    assert(mapStartError(12_345) == NativeThreadStartErrorKind.system);
}

private bool roundUpStackSize(
    size_t requested,
    size_t* normalized,
) @system
{
    // Linux/glibc's traditional minimum is 16 KiB. sysconf can report a
    // larger target-specific minimum, and page rounding prevents an underlying
    // implementation from rounding a caller's requested minimum downward.
    size_t minimum = 16 * 1024;
    const reportedMinimum = sysconf(_SC_THREAD_STACK_MIN);
    if (reportedMinimum > 0 && cast(size_t) reportedMinimum > minimum)
        minimum = cast(size_t) reportedMinimum;

    size_t alignment = 16;
    const reportedPageSize = sysconf(_SC_PAGESIZE);
    if (reportedPageSize > 0 && cast(size_t) reportedPageSize > alignment)
        alignment = cast(size_t) reportedPageSize;

    size_t value = requested > minimum ? requested : minimum;
    const remainder = value % alignment;
    if (remainder != 0)
    {
        const increment = alignment - remainder;
        if (value > size_t.max - increment)
            return false;
        value += increment;
    }

    *normalized = value;
    return true;
}

private NativeThreadStartResult startNative(
    size_t stackSize,
    NativeThreadEntryFn function_,
    void* context,
) @system
{
    pthread_attr_t attributes;
    pthread_attr_t* attributesPointer = null;

    if (stackSize != 0)
    {
        const initCode = pthread_attr_init(&attributes);
        if (initCode != 0)
            return startFailure(mapStartError(initCode), initCode);
        attributesPointer = &attributes;

        size_t normalizedStackSize;
        if (!roundUpStackSize(stackSize, &normalizedStackSize))
        {
            const destroyCode = pthread_attr_destroy(&attributes);
            if (destroyCode != 0)
                panic("pthread_attr_destroy failed after stack-size overflow");
            return startFailure(
                NativeThreadStartErrorKind.invalidConfiguration,
                EINVAL,
            );
        }

        const stackCode = pthread_attr_setstacksize(
            &attributes,
            normalizedStackSize,
        );
        if (stackCode != 0)
        {
            const destroyCode = pthread_attr_destroy(&attributes);
            if (destroyCode != 0)
                panic("pthread_attr_destroy failed after stack-size rejection");
            return startFailure(mapStartError(stackCode), stackCode);
        }
    }

    pthread_t nativeThread;
    const createCode = pthread_create(
        &nativeThread,
        attributesPointer,
        function_,
        context,
    );

    if (attributesPointer !is null)
    {
        const destroyCode = pthread_attr_destroy(&attributes);
        if (destroyCode != 0)
            panic("pthread_attr_destroy failed after pthread_create");
    }

    if (createCode != 0)
        return startFailure(mapStartError(createCode), createCode);

    return NativeThreadStartResult(
        true,
        NativeThreadHandle(nativeThread),
        NativeThreadStartErrorKind.system,
        0,
    );
}

NativeThreadStartResult startRaw(
    size_t stackSize,
    NativeRawThreadFn function_,
    void* context,
) @system
{
    RawStartPacket packet;
    packet.function_ = function_;
    packet.context = context;

    const started = startNative(
        stackSize,
        &rawThreadTrampoline,
        &packet,
    );
    if (!started.succeeded)
        return started;

    // The allocation-free path borrows this parent-stack packet. Wait only
    // until the child has copied the portable callback and context; user
    // work still runs asynchronously after that handoff. Use the parking-backed
    // latch where available, while preserving the bootstrap spin/yield fallback
    // on Linux architectures whose parking backend is not yet implemented.
    static if (startLatchSupported)
    {
        packet.captured.wait();
    }
    else
    {
        uint relaxCount;
        while (packet.captured.load(MemoryOrder.acquire) == 0)
        {
            if (relaxCount < 64)
            {
                cpuRelax();
                ++relaxCount;
            }
            else
            {
                cast(void) sched_yield();
            }
        }
    }

    return started;
}

/// Starts from already-stable packet storage and therefore performs no
/// child-start handoff before returning.
NativeThreadStartResult startStable(
    size_t stackSize,
    NativeStableStartPacket* packet,
) @system
{
    return startNative(
        stackSize,
        &stableThreadTrampoline,
        packet,
    );
}

NativeJoinResult joinThread(NativeThreadHandle handle) @system
{
    void* rawStatus;
    const code = pthread_join(handle.value, &rawStatus);
    if (code != 0)
        return NativeJoinResult(false, 0, code);

    return NativeJoinResult(
        true,
        cast(int) cast(intptr_t) rawStatus,
        0,
    );
}

int detachThread(NativeThreadHandle handle) @system
{
    return pthread_detach(handle.value);
}

bool isCurrentThread(NativeThreadHandle handle) @system
{
    return pthread_equal(handle.value, pthread_self()) != 0;
}

private ulong encodeThreadId(pthread_t value) @trusted
{
    static assert(
        pthread_t.sizeof <= ulong.sizeof,
        "Linux pthread_t must fit in XTB's opaque diagnostic ThreadId storage",
    );
    return cast(ulong) value;
}

ulong threadIdValue(NativeThreadHandle handle) @trusted
{
    const value = encodeThreadId(handle.value);
    if (value == 0)
        panic("Linux pthread produced the invalid ThreadId sentinel");
    return value;
}

ulong currentThreadIdValue() @trusted
{
    const value = encodeThreadId(pthread_self());
    if (value == 0)
        panic("Linux pthread_self produced the invalid ThreadId sentinel");
    return value;
}

void yieldThreadBackend() @system
{
    cast(void) sched_yield();
}

uint hardwareConcurrencyBackend() @system
{
    cpu_set_t available;
    if (sched_getaffinity(0, cpu_set_t.sizeof, &available) == 0)
    {
        const count = countAffinityCpus(&available);
        if (count > 0)
            return count;
    }

    const online = sysconf(_SC_NPROCESSORS_ONLN);
    if (online <= 0 || cast(ulong) online > uint.max)
        return 0;
    return cast(uint) online;
}

private uint countAffinityCpus(const(cpu_set_t)* available) pure @trusted
{
    const bytes = (cast(const(ubyte)*) available)[0 .. cpu_set_t.sizeof];
    uint count;
    foreach (value; bytes)
    {
        ubyte remaining = value;
        while (remaining != 0)
        {
            remaining &= cast(ubyte)(remaining - 1);
            ++count;
        }
    }
    return count;
}

private enum size_t linuxThreadNameCapacity = 16;
private enum size_t linuxThreadNameMaximum = linuxThreadNameCapacity - 1;

private extern (C) pragma(mangle, "pthread_setname_np")
int nativePthreadSetName(pthread_t thread, const(char)* name);

private bool containsNul(String name) pure @safe
{
    foreach (character; name)
        if (character == '\0')
            return true;
    return false;
}

private NativeThreadNameResult nameFailure(
    NativeThreadNameErrorKind kind,
    int nativeCode,
) pure @safe
{
    return NativeThreadNameResult(false, kind, nativeCode);
}

private NativeThreadNameResult setNativeThreadName(
    pthread_t thread,
    String name,
) @system
{
    if (containsNul(name))
        return nameFailure(NativeThreadNameErrorKind.invalidName, EINVAL);
    if (name.length > linuxThreadNameMaximum)
        return nameFailure(NativeThreadNameErrorKind.tooLong, ERANGE);

    char[linuxThreadNameCapacity] terminated;
    foreach (index; 0 .. name.length)
        terminated[index] = name[index];
    terminated[name.length] = '\0';

    const code = nativePthreadSetName(thread, terminated.ptr);
    if (code == 0)
        return NativeThreadNameResult(true);

    switch (code)
    {
        case ERANGE:
            return nameFailure(NativeThreadNameErrorKind.tooLong, code);
        case ESRCH:
        case ENOENT:
            return nameFailure(
                NativeThreadNameErrorKind.threadUnavailable,
                code,
            );
        case ENOSYS:
            return nameFailure(NativeThreadNameErrorKind.unsupported, code);
        default:
            return nameFailure(NativeThreadNameErrorKind.system, code);
    }
}

NativeThreadNameResult setCurrentThreadNameBackend(String name) @system
{
    return setNativeThreadName(pthread_self(), name);
}

NativeThreadNameResult setThreadNameBackend(
    NativeThreadHandle handle,
    String name,
) @system
{
    return setNativeThreadName(handle.value, name);
}
