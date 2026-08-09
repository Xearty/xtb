module xtb.threading.once_cell;

nothrow @nogc:

import core.internal.traits : Parameters, ReturnType;
import core.lifetime : emplace, forward, move;
import xtb.core.option : Option, OptionReturns;
import xtb.threading.once : Once, callOnce;

version (unittest) import xtb.threading.atomic : Atomic, MemoryOrder;

/// Raw storage whose `T` lifetime is managed explicitly by `OnceCell`.
private union OnceCellStorage(T)
{
    T value;
}

/// Allocation-free storage for a value initialized at most once.
///
/// `OnceCell.init` is uninitialized. The cell owns the value after successful
/// initialization and destroys it exactly once. Returned pointers and
/// references borrow the cell, which must remain alive and at a stable address.
struct OnceCell(T)
{
nothrow @nogc:
    static assert(!is(T == void), "OnceCell value type cannot be void");

    @disable this(this);

    private Once once_;
    private OnceCellStorage!T storage_;

    ~this() @trusted
    {
        if (once_.completed())
            destroy(storage_.value);
    }

    /// Whether initialization has completed.
    ///
    /// A true result observes publication of the stored value with acquire
    /// ordering. This query never blocks.
    bool isInitialized() const @trusted
    {
        return once_.completed();
    }

    /// Returns a borrowed pointer to the stored value without blocking.
    Option!(T*) tryGet() return @trusted
    {
        mixin OptionReturns;
        if (!once_.completed())
            return none();
        return some(&storage_.value);
    }

    /// Ditto, for a const cell.
    Option!(const(T)*) tryGet() const return @trusted
    {
        mixin OptionReturns;
        if (!once_.completed())
            return none();
        return some(&storage_.value);
    }

    /// Initializes the cell exactly once and returns its stored value.
    ///
    /// The initializer is a module-level or static `nothrow @nogc` function.
    /// Its argument expressions are evaluated by every caller, but only the
    /// caller that wins initialization invokes the function body. The returned
    /// reference borrows this cell. Synchronization covers initialization and
    /// publication only; later mutable access needs caller-supplied protection.
    ref T getOrInit(alias initializer, Args...)(Args arguments) return @trusted
    {
        validateCellInitializer!initializer();
        callOnce!(initializeCell!(T, initializer, Args))(
            once_,
            &this,
            forward!arguments,
        );
        return storage_.value;
    }
}

private void initializeCell(T, alias initializer, Args...)(
    OnceCell!T* cell,
    Args arguments,
) @system
{
    auto value = initializer(forward!arguments);
    emplace(&cell.storage_.value, move(value));
}

private void validateCellInitializer(alias initializer)()
{
    static assert(
        __traits(isStaticFunction, initializer),
        "OnceCell initializer must be a module-level or static function",
    );
    static assert(
        hasFunctionAttribute!(initializer, "nothrow"),
        "OnceCell initializer must be nothrow",
    );
    static assert(
        hasFunctionAttribute!(initializer, "@nogc"),
        "OnceCell initializer must be @nogc",
    );
    static assert(!is(ReturnType!initializer == void),
        "OnceCell initializer must return a value");
    static assert(
        !hasFunctionAttribute!(initializer, "ref"),
        "OnceCell initializer must return an owned value, not ref",
    );
    static foreach (index; 0 .. Parameters!initializer.length)
    {
        static assert(
            !parameterHasStorageClass!(initializer, index, "ref") &&
                !parameterHasStorageClass!(initializer, index, "out") &&
                !parameterHasStorageClass!(initializer, index, "lazy") &&
                !parameterHasStorageClass!(initializer, index, "in"),
            "OnceCell initializer parameters must use by-value transport",
        );
    }
}

private bool hasFunctionAttribute(alias function_, string expected)()
{
    static foreach (attribute; __traits(getFunctionAttributes, function_))
        static if (attribute == expected)
            return true;
    return false;
}

private bool parameterHasStorageClass(
    alias function_,
    size_t index,
    string expected,
)()
{
    static foreach (storageClass; __traits(getParameterStorageClasses, function_, index))
        static if (storageClass == expected)
            return true;
    return false;
}

static assert(!__traits(isCopyable, OnceCell!int));

version (unittest)
{
    private int initializeInt(int* calls, int value) nothrow @nogc
    {
        ++*calls;
        return value;
    }

    private int* evaluateCellArgument(int* evaluations, int* value)
    nothrow @nogc
    {
        ++*evaluations;
        return value;
    }

    private int initializeEvaluatedInt(int* calls, int* value) nothrow @nogc
    {
        ++*calls;
        return *value;
    }

    private void wrongCellReturn() nothrow @nogc
    {
    }

    private int refCellInitializer(ref int value) nothrow @nogc
    {
        return value;
    }

    private ref int borrowedCellInitializer(int* value) nothrow @nogc
    {
        return *value;
    }

    private struct ConstructedCellValue
    {
        int value;

        this(int value) nothrow @nogc
        {
            this.value = value;
        }
    }

    unittest
    {
        OnceCell!int cell;
        assert(!cell.isInitialized());
        assert(cell.tryGet().isNone);

        int calls;
        ref first = cell.getOrInit!initializeInt(&calls, 41);
        assert(cell.isInitialized());
        assert(first == 41);
        assert(calls == 1);

        ref second = cell.getOrInit!initializeInt(&calls, 99);
        assert(&first is &second);
        assert(second == 41);
        assert(calls == 1);

        auto present = cell.tryGet();
        assert(present.isSome);
        assert(present.value() is &first);
        *present.value() = 42;
        assert(first == 42);

        const OnceCell!int* readOnly = &cell;
        auto constPresent = readOnly.tryGet();
        assert(constPresent.isSome);
        assert(constPresent.value() is &first);

        OnceCell!int evaluatedCell;
        int evaluations;
        int evaluatedCalls;
        int value = 73;
        evaluatedCell.getOrInit!initializeEvaluatedInt(
            &evaluatedCalls,
            evaluateCellArgument(&evaluations, &value),
        );
        evaluatedCell.getOrInit!initializeEvaluatedInt(
            &evaluatedCalls,
            evaluateCellArgument(&evaluations, &value),
        );
        assert(evaluations == 2);
        assert(evaluatedCalls == 1);

        OnceCell!ConstructedCellValue constructedCell;
        ref constructed = constructedCell.getOrInit!initializeInt(
            &calls,
            64,
        );
        assert(constructed.value == 64);

        static assert(!__traits(compiles,
                cell.getOrInit!wrongCellReturn()));
        static assert(!__traits(compiles,
                cell.getOrInit!refCellInitializer(calls)));
        static assert(!__traits(compiles,
                cell.getOrInit!borrowedCellInitializer(&calls)));
        int nested() nothrow @nogc
        {
            return 1;
        }

        static assert(!__traits(compiles, cell.getOrInit!nested()));
    }

    private struct TrackedCellValue
    {
    nothrow @nogc:
        int value;
        int* destructions;
        bool armed;

        @disable this(this);

        this(int value, int* destructions)
        {
            this.value = value;
            this.destructions = destructions;
            armed = true;
        }

        ~this()
        {
            if (armed)
                ++*destructions;
        }
    }

    private TrackedCellValue initializeTracked(int* calls, int* destructions)
    nothrow @nogc
    {
        ++*calls;
        return TrackedCellValue(27, destructions);
    }

    unittest
    {
        int calls;
        int destructions;
        {
            OnceCell!TrackedCellValue cell;
            ref value = cell.getOrInit!initializeTracked(
                &calls,
                &destructions,
            );
            assert(value.value == 27);
            assert(calls == 1);
            assert(destructions == 0);
        }
        assert(destructions == 1);

        {
            OnceCell!TrackedCellValue empty;
        }
        assert(destructions == 1);
    }

    static if (Atomic!uint.waitSupported)
    {
        import xtb.threading.thread : Thread;

        private struct OnceCellContentionContext
        {
            OnceCell!int* cell;
            Atomic!uint* argumentEvaluations;
            Atomic!uint* initializerCalls;
            Atomic!uint* entered;
            Atomic!uint* releaseInitializer;
            int payload;
        }

        private OnceCellContentionContext* evaluateContentionArgument(
            OnceCellContentionContext* context,
        ) nothrow @nogc
        {
            context.argumentEvaluations.fetchAdd(1, MemoryOrder.relaxed);
            return context;
        }

        private int initializeContendedCell(OnceCellContentionContext* context)
        nothrow @nogc
        {
            context.initializerCalls.fetchAdd(1, MemoryOrder.relaxed);
            context.entered.store(1, MemoryOrder.release);
            context.entered.notifyAll();
            context.releaseInitializer.wait(0, MemoryOrder.acquire);
            return context.payload;
        }

        private int invokeContendedCell(OnceCellContentionContext* context)
        nothrow @nogc
        {
            ref value = context.cell.getOrInit!initializeContendedCell(
                evaluateContentionArgument(context),
            );
            return value == context.payload ? 0 : 1;
        }

        unittest
        {
            enum callerCount = 8;
            OnceCell!int cell;
            Atomic!uint argumentEvaluations;
            Atomic!uint initializerCalls;
            Atomic!uint entered;
            Atomic!uint releaseInitializer;
            OnceCellContentionContext context = OnceCellContentionContext(
                &cell,
                &argumentEvaluations,
                &initializerCalls,
                &entered,
                &releaseInitializer,
                0x1357_2468,
            );
            Thread[callerCount] callers;

            auto firstStarted = Thread.start!invokeContendedCell(&context);
            assert(firstStarted.isOk);
            callers[0] = firstStarted.unwrap();
            entered.wait(0, MemoryOrder.acquire);

            foreach (ref caller; callers[1 .. $])
            {
                auto started = Thread.start!invokeContendedCell(&context);
                assert(started.isOk);
                caller = started.unwrap();
            }

            releaseInitializer.store(1, MemoryOrder.release);
            releaseInitializer.notifyAll();

            foreach (ref caller; callers)
                assert(caller.join() == 0);
            assert(argumentEvaluations.load(MemoryOrder.relaxed) == callerCount);
            assert(initializerCalls.load(MemoryOrder.relaxed) == 1);
            assert(cell.isInitialized());
        }
    }
}
