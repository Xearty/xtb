module xtb.sync.lock_guard;

nothrow @nogc:

import core.attribute : mustuse;
import xtb.core.panic : panic;
import xtb.sync.mutex : Mutex;
import xtb.sync.rw_lock : RwLock;

private noreturn nullMutexGuardLock() @trusted
{
    panic("LockGuard requires a non-null Mutex pointer");
}

private noreturn nullReadGuardLock() @trusted
{
    panic("ReadLockGuard requires a non-null RwLock pointer");
}

private noreturn nullWriteGuardLock() @trusted
{
    panic("WriteLockGuard requires a non-null RwLock pointer");
}

private noreturn overwriteMutexGuard() @trusted
{
    panic("cannot move-assign over an owning LockGuard");
}

private noreturn overwriteReadGuard() @trusted
{
    panic("cannot move-assign over an owning ReadLockGuard");
}

private noreturn overwriteWriteGuard() @trusted
{
    panic("cannot move-assign over an owning WriteLockGuard");
}

/// Move-only lexical owner of one `Mutex` acquisition.
///
/// Construction locks the caller-owned mutex and destruction unlocks it. The
/// mutex must remain at a stable address and outlive the guard. An owning guard
/// is thread-affine: move it only between variables on the same thread.
@mustuse struct LockGuard(Lock)
{
nothrow @nogc:
    static assert(is(Lock == Mutex), "LockGuard supports Mutex");
    @disable this(this);

    private Lock* lock_;

    /// Acquires `lock` and owns that acquisition until guard destruction.
    this(return scope Lock* lock) @safe
    {
        if (lock is null)
            nullMutexGuardLock();
        lock.lock();
        lock_ = lock;
    }

    ~this() @safe
    {
        if (lock_ is null)
            return;
        lock_.unlock();
        lock_ = null;
    }

    /// Transfers ownership into an empty destination guard.
    ref LockGuard opAssign(LockGuard source) return @safe
    {
        if (lock_ !is null)
            overwriteMutexGuard();
        lock_ = source.lock_;
        source.lock_ = null;
        return this;
    }
}

/// Move-only lexical owner of one `RwLock` read acquisition.
///
/// Construction acquires shared read ownership and destruction releases one
/// read ownership. The lock must remain at a stable address and outlive the
/// guard.
@mustuse struct ReadLockGuard(Lock)
{
nothrow @nogc:
    static assert(is(Lock == RwLock), "ReadLockGuard supports RwLock");
    @disable this(this);

    private Lock* lock_;

    /// Acquires shared read ownership until guard destruction.
    this(return scope Lock* lock) @safe
    {
        if (lock is null)
            nullReadGuardLock();
        lock.lockRead();
        lock_ = lock;
    }

    ~this() @safe
    {
        if (lock_ is null)
            return;
        lock_.unlockRead();
        lock_ = null;
    }

    /// Transfers ownership into an empty destination guard.
    ref ReadLockGuard opAssign(ReadLockGuard source) return @safe
    {
        if (lock_ !is null)
            overwriteReadGuard();
        lock_ = source.lock_;
        source.lock_ = null;
        return this;
    }
}

/// Move-only lexical owner of one `RwLock` write acquisition.
///
/// Construction acquires exclusive write ownership and destruction releases
/// it. The lock must remain at a stable address and outlive the guard. An owning
/// write guard is thread-affine: move it only between variables on the same
/// thread.
@mustuse struct WriteLockGuard(Lock)
{
nothrow @nogc:
    static assert(is(Lock == RwLock), "WriteLockGuard supports RwLock");
    @disable this(this);

    private Lock* lock_;

    /// Acquires exclusive write ownership until guard destruction.
    this(return scope Lock* lock) @safe
    {
        if (lock is null)
            nullWriteGuardLock();
        lock.lockWrite();
        lock_ = lock;
    }

    ~this() @safe
    {
        if (lock_ is null)
            return;
        lock_.unlockWrite();
        lock_ = null;
    }

    /// Transfers ownership into an empty destination guard.
    ref WriteLockGuard opAssign(WriteLockGuard source) return @safe
    {
        if (lock_ !is null)
            overwriteWriteGuard();
        lock_ = source.lock_;
        source.lock_ = null;
        return this;
    }
}

static assert(!__traits(isCopyable, LockGuard!Mutex));
static assert(!__traits(isCopyable, ReadLockGuard!RwLock));
static assert(!__traits(isCopyable, WriteLockGuard!RwLock));
static assert(LockGuard!Mutex.sizeof == (Mutex*).sizeof);
static assert(ReadLockGuard!RwLock.sizeof == (RwLock*).sizeof);
static assert(WriteLockGuard!RwLock.sizeof == (RwLock*).sizeof);
static assert(!__traits(hasMember, LockGuard!Mutex, "release"));
static assert(!__traits(hasMember, ReadLockGuard!RwLock, "release"));
static assert(!__traits(hasMember, WriteLockGuard!RwLock, "release"));
static assert(!__traits(compiles, () { alias Invalid = LockGuard!RwLock; }));
static assert(!__traits(compiles, () { alias Invalid = ReadLockGuard!Mutex; }));
static assert(!__traits(compiles, () { alias Invalid = WriteLockGuard!Mutex; }));
static assert(__traits(compiles, () @safe {
        Mutex mutex;
        RwLock readLock;
        RwLock writeLock;
        LockGuard!Mutex mutexGuard = LockGuard!Mutex(&mutex);
        ReadLockGuard!RwLock readGuard = ReadLockGuard!RwLock(&readLock);
        WriteLockGuard!RwLock writeGuard = WriteLockGuard!RwLock(&writeLock);
    }));
static assert(!__traits(compiles, () @safe { Mutex lock; return LockGuard!Mutex(&lock); }));
static assert(!__traits(compiles, () @safe { RwLock lock; return ReadLockGuard!RwLock(&lock); }));
static assert(!__traits(compiles, () @safe { RwLock lock; return WriteLockGuard!RwLock(&lock); }));

unittest
{
    import core.lifetime : move;

    Mutex mutex;
    {
        LockGuard!Mutex first = LockGuard!Mutex(&mutex);
        LockGuard!Mutex second = move(first);
    }
    assert(mutex.tryLock());
    mutex.unlock();

    {
        LockGuard!Mutex source = LockGuard!Mutex(&mutex);
        LockGuard!Mutex destination;
        destination = move(source);
    }
    assert(mutex.tryLock());
    mutex.unlock();

    RwLock lock;
    {
        ReadLockGuard!RwLock first = ReadLockGuard!RwLock(&lock);
        ReadLockGuard!RwLock second = move(first);
        assert(lock.tryLockRead());
        lock.unlockRead();
        assert(!lock.tryLockWrite());
    }
    assert(lock.tryLockWrite());
    lock.unlockWrite();

    {
        ReadLockGuard!RwLock source = ReadLockGuard!RwLock(&lock);
        ReadLockGuard!RwLock destination;
        destination = move(source);
    }
    assert(lock.tryLockWrite());
    lock.unlockWrite();

    {
        WriteLockGuard!RwLock first = WriteLockGuard!RwLock(&lock);
        WriteLockGuard!RwLock second = move(first);
        assert(!lock.tryLockRead());
        assert(!lock.tryLockWrite());
    }
    assert(lock.tryLockRead());
    lock.unlockRead();

    {
        WriteLockGuard!RwLock source = WriteLockGuard!RwLock(&lock);
        WriteLockGuard!RwLock destination;
        destination = move(source);
    }
    assert(lock.tryLockRead());
    lock.unlockRead();
}
