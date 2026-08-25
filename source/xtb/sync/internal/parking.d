module xtb.sync.internal.parking;

nothrow @nogc:

import xtb.core.panic : panic;

/// Result of one compare-and-sleep parking attempt.
///
/// Higher-level wait loops must re-check their own atomic state after either
/// result. `valueMismatch` means the wait word no longer matched `expected`
/// when the backend attempted to sleep; `wokenOrSpurious` includes an actual
/// wake, signal interruption, or another backend-permitted spurious return.
package(xtb.sync) enum ParkResult : ubyte
{
    valueMismatch,
    wokenOrSpurious,
}

version (linux)
{
    import core.stdc.config : c_long;
    import core.stdc.errno : EAGAIN, EINTR, errno;

    // Declare libc syscall directly instead of depending on druntime exposing
    // it from core.sys.linux.unistd; that declaration is not present in every
    // supported D toolchain.
    extern (C) c_long syscall(c_long number, ...) nothrow @nogc;

    private enum c_long futexWait = 0;
    private enum c_long futexWake = 1;
    private enum c_long futexPrivateFlag = 128;
    private enum c_long futexWaitPrivate = futexWait | futexPrivateFlag;
    private enum c_long futexWakePrivate = futexWake | futexPrivateFlag;

    // Linux does not expose SYS_futex through this LDC's druntime headers, so
    // keep the architecture mapping local to the Linux parking backend. Unknown
    // Linux architectures still compile and fail explicitly if parking is used.
    version (X86_64)
    {
        version (D_X32)
            private enum c_long futexSyscallNumber = 0x4000_0000 + 202;
        else
            private enum c_long futexSyscallNumber = 202;
        private enum bool futexSyscallAvailable = true;
    }
    else version (X86)
    {
        private enum c_long futexSyscallNumber = 240;
        private enum bool futexSyscallAvailable = true;
    }
    else version (ARM)
    {
        private enum c_long futexSyscallNumber = 240;
        private enum bool futexSyscallAvailable = true;
    }
    else version (AArch64)
    {
        private enum c_long futexSyscallNumber = 98;
        private enum bool futexSyscallAvailable = true;
    }
    else version (RISCV32)
    {
        private enum c_long futexSyscallNumber = 98;
        private enum bool futexSyscallAvailable = true;
    }
    else version (RISCV64)
    {
        private enum c_long futexSyscallNumber = 98;
        private enum bool futexSyscallAvailable = true;
    }
    else version (PPC)
    {
        private enum c_long futexSyscallNumber = 221;
        private enum bool futexSyscallAvailable = true;
    }
    else version (PPC64)
    {
        private enum c_long futexSyscallNumber = 221;
        private enum bool futexSyscallAvailable = true;
    }
    else version (S390)
    {
        private enum c_long futexSyscallNumber = 238;
        private enum bool futexSyscallAvailable = true;
    }
    else version (SystemZ)
    {
        private enum c_long futexSyscallNumber = 238;
        private enum bool futexSyscallAvailable = true;
    }
    else version (LoongArch64)
    {
        private enum c_long futexSyscallNumber = 98;
        private enum bool futexSyscallAvailable = true;
    }
    else
    {
        private enum c_long futexSyscallNumber = 0;
        private enum bool futexSyscallAvailable = false;
    }

    private ParkResult classifyWaitFailure(int errorCode)
    {
        switch (errorCode)
        {
            case EAGAIN:
                return ParkResult.valueMismatch;
            case EINTR:
                return ParkResult.wokenOrSpurious;
            default:
                panic("Linux futex wait failed unexpectedly");
        }
    }

    private c_long futexCall(
        uint* address,
        c_long operation,
        uint value,
    ) @system
    {
        return syscall(
            futexSyscallNumber,
            address,
            operation,
            value,
            cast(void*) null,
            cast(void*) null,
            0,
        );
    }
}

version (XTB_TestUnsupportedThreadBackend)
    package(xtb.sync) enum bool parkingSupported = false;
else version (linux)
    package(xtb.sync) enum bool parkingSupported = futexSyscallAvailable;
else
    package(xtb.sync) enum bool parkingSupported = false;

/// Atomically compares `*address` with `expected` at the backend sleep point
/// and sleeps only while they compare equal.
///
/// This is a single parking attempt rather than a complete wait loop. Callers
/// must re-check their own atomic state after either result. The wait word must
/// remain alive and at a stable address for the full wait/wake protocol.
package(xtb.sync) ParkResult park(uint* address, uint expected) @system
{
    version (XTB_TestUnsupportedThreadBackend)
    {
        panic("thread parking is unsupported on this platform");
    }
    else version (linux)
    {
        static if (!futexSyscallAvailable)
        {
            panic("Linux futex parking is unsupported on this architecture");
        }
        else
        {
            if (address is null)
                panic("park requires a non-null wait-word address");

            const result = futexCall(address, futexWaitPrivate, expected);
            if (result >= 0)
                return ParkResult.wokenOrSpurious;
            return classifyWaitFailure(errno);
        }
    }
    else
    {
        panic("thread parking is unsupported on this platform");
    }
}

/// Wakes at most one thread parked on `address`.
///
/// Wake operations carry no publication ordering of their own; callers publish
/// state with atomics before waking.
package(xtb.sync) void wakeOne(uint* address) @system
{
    version (XTB_TestUnsupportedThreadBackend)
    {
        panic("thread parking is unsupported on this platform");
    }
    else version (linux)
    {
        static if (!futexSyscallAvailable)
        {
            panic("Linux futex parking is unsupported on this architecture");
        }
        else
        {
            if (address is null)
                panic("wakeOne requires a non-null wait-word address");
            if (futexCall(address, futexWakePrivate, 1) < 0)
                panic("Linux futex wake-one failed unexpectedly");
        }
    }
    else
    {
        panic("thread parking is unsupported on this platform");
    }
}

/// Wakes all threads currently parked on `address`.
///
/// Callers must tolerate waiters arriving after this call by changing the
/// protocol state before waking; `park`'s compare-and-sleep check then prevents
/// those late arrivals from sleeping on the stale value.
package(xtb.sync) void wakeAll(uint* address) @system
{
    version (XTB_TestUnsupportedThreadBackend)
    {
        panic("thread parking is unsupported on this platform");
    }
    else version (linux)
    {
        static if (!futexSyscallAvailable)
        {
            panic("Linux futex parking is unsupported on this architecture");
        }
        else
        {
            if (address is null)
                panic("wakeAll requires a non-null wait-word address");
            if (futexCall(address, futexWakePrivate, cast(uint) int.max) < 0)
                panic("Linux futex wake-all failed unexpectedly");
        }
    }
    else
    {
        panic("thread parking is unsupported on this platform");
    }
}

version (unittest)
{
    version (Posix)
    {
        import core.stdc.signal : SIGABRT;
        import core.sys.posix.sys.wait : waitpid;
        import core.sys.posix.unistd : _exit, fork;
    }

    version (linux)
    {
        import core.atomic;
        import core.sys.posix.pthread : pthread_create, pthread_join, pthread_t;
        import core.sys.posix.sched : sched_yield;
        import xtb.sync.atomic : Atomic, MemoryOrder;

        private uint testLoad(uint* address) @trusted
        {
            return core.atomic.atomicLoad!(core.atomic.MemoryOrder.acq)(*address);
        }

        private void testStore(uint* address, uint value) @trusted
        {
            core.atomic.atomicStore!(core.atomic.MemoryOrder.rel)(*address, value);
        }

        private bool waitForAtLeast(Atomic!uint* value, uint target)
        {
            foreach (_; 0 .. 1_000_000)
            {
                if (value.load(MemoryOrder.acquire) >= target)
                    return true;
                sched_yield();
            }
            return false;
        }

        private struct SingleWaitContext
        {
            uint* word;
            Atomic!uint ready;
            Atomic!uint returned;
            Atomic!uint proceed;
            bool gateBeforePark;
            ParkResult result;
        }

        private extern (C) void* singleWaiter(void* opaque) @system
        {
            SingleWaitContext* context = cast(SingleWaitContext*) opaque;
            context.ready.store(1, MemoryOrder.release);
            if (context.gateBeforePark)
            {
                while (context.proceed.load(MemoryOrder.acquire) == 0)
                    sched_yield();
            }
            context.result = park(context.word, 0);
            context.returned.store(1, MemoryOrder.release);
            return null;
        }

        private bool compareAndSleepRejectsChangedValue() @system
        {
            uint word;
            SingleWaitContext context;
            context.word = &word;
            context.gateBeforePark = true;

            pthread_t worker;
            if (pthread_create(&worker, null, &singleWaiter, &context) != 0)
                return false;
            if (!waitForAtLeast(&context.ready, 1))
            {
                testStore(&word, 1);
                context.proceed.store(1, MemoryOrder.release);
                wakeAll(&word);
                cast(void) pthread_join(worker, null);
                return false;
            }

            testStore(&word, 1);
            context.proceed.store(1, MemoryOrder.release);
            const returnedPromptly = waitForAtLeast(&context.returned, 1);
            if (!returnedPromptly)
                wakeAll(&word);

            if (pthread_join(worker, null) != 0)
                return false;
            return returnedPromptly &&
                context.result == ParkResult.valueMismatch;
        }

        private bool wakeOneReleasesWaiter() @system
        {
            uint word;
            SingleWaitContext context;
            context.word = &word;

            pthread_t worker;
            if (pthread_create(&worker, null, &singleWaiter, &context) != 0)
                return false;
            if (!waitForAtLeast(&context.ready, 1))
            {
                testStore(&word, 1);
                wakeAll(&word);
                cast(void) pthread_join(worker, null);
                return false;
            }

            foreach (_; 0 .. 1_000_000)
            {
                if (context.returned.load(MemoryOrder.acquire) != 0)
                    break;
                wakeOne(&word);
                sched_yield();
            }
            const returned = context.returned.load(MemoryOrder.acquire) != 0;
            if (!returned)
            {
                testStore(&word, 1);
                wakeAll(&word);
            }

            if (pthread_join(worker, null) != 0)
                return false;
            return returned &&
                context.result == ParkResult.wokenOrSpurious;
        }

        private struct StressContext
        {
            uint* word;
            Atomic!uint* ready;
            Atomic!uint* completed;
            uint rounds;
        }

        private extern (C) void* stressWaiter(void* opaque) @system
        {
            StressContext* context = cast(StressContext*) opaque;
            foreach (round; 0 .. context.rounds)
            {
                context.ready.fetchAdd(1, MemoryOrder.release);
                while (testLoad(context.word) == round)
                    cast(void) park(context.word, round);
                context.completed.fetchAdd(1, MemoryOrder.release);
            }
            return null;
        }

        private bool repeatedWakeAllStress() @system
        {
            enum workerCount = 8;
            enum rounds = 64;

            uint word;
            Atomic!uint ready;
            Atomic!uint completed;
            StressContext[workerCount] contexts;
            pthread_t[workerCount] workers;
            uint started;

            foreach (index; 0 .. workerCount)
            {
                contexts[index] = StressContext(
                    &word,
                    &ready,
                    &completed,
                    rounds,
                );
                if (pthread_create(
                        &workers[index],
                        null,
                        &stressWaiter,
                        &contexts[index],
                    ) != 0)
                    break;
                ++started;
            }

            if (started != workerCount)
            {
                testStore(&word, uint.max);
                wakeAll(&word);
                foreach (index; 0 .. started)
                    cast(void) pthread_join(workers[index], null);
                return false;
            }

            bool succeeded = true;
            foreach (round; 0 .. rounds)
            {
                const target = cast(uint)((round + 1) * workerCount);
                if (!waitForAtLeast(&ready, target))
                {
                    succeeded = false;
                    break;
                }

                testStore(&word, cast(uint)(round + 1));
                wakeAll(&word);
                if (!waitForAtLeast(&completed, target))
                {
                    succeeded = false;
                    break;
                }
            }

            if (!succeeded)
            {
                testStore(&word, uint.max);
                wakeAll(&word);
            }

            foreach (worker; workers)
                if (pthread_join(worker, null) != 0)
                    succeeded = false;

            return succeeded &&
                completed.load(MemoryOrder.acquire) == workerCount * rounds;
        }
    }

    version (XTB_TestUnsupportedThreadBackend)
    {
        version (Posix)
        {
            private enum UnsupportedParkingCase : ubyte
            {
                park,
                wakeOne,
                wakeAll,
            }

            private void runUnsupportedParkingCase(
                UnsupportedParkingCase parkingCase,
            ) @system
            {
                uint word;
                final switch (parkingCase)
                {
                    case UnsupportedParkingCase.park:
                        cast(void) park(&word, 0);
                        return;
                    case UnsupportedParkingCase.wakeOne:
                        wakeOne(&word);
                        return;
                    case UnsupportedParkingCase.wakeAll:
                        wakeAll(&word);
                        return;
                }
                _exit(91);
            }

            private bool unsupportedParkingAborts(
                UnsupportedParkingCase parkingCase,
            ) @system
            {
                const process = fork();
                if (process < 0)
                    return false;
                if (process == 0)
                {
                    runUnsupportedParkingCase(parkingCase);
                    _exit(0);
                }

                int status;
                return waitpid(process, &status, 0) == process &&
                    (status & 0x7f) == SIGABRT;
            }
        }
    }
}

unittest
{
    version (XTB_TestUnsupportedThreadBackend)
    {
        version (Posix)
        {
            assert(unsupportedParkingAborts(UnsupportedParkingCase.park));
            assert(unsupportedParkingAborts(UnsupportedParkingCase.wakeOne));
            assert(unsupportedParkingAborts(UnsupportedParkingCase.wakeAll));
        }
    }
    else version (linux)
    {
        static if (futexSyscallAvailable)
        {
            assert(classifyWaitFailure(EAGAIN) == ParkResult.valueMismatch);
            assert(classifyWaitFailure(EINTR) == ParkResult.wokenOrSpurious);

            uint word = 1;
            assert(park(&word, 0) == ParkResult.valueMismatch);
            assert(compareAndSleepRejectsChangedValue());
            assert(wakeOneReleasesWaiter());
            assert(repeatedWakeAllStress());
        }
    }
}
