module xtb.core.lifetime;

nothrow @nogc:

import core.internal.traits : Unqual, hasElaborateDestructor;
import core.lifetime : coreMoveEmplace = moveEmplace;

private alias AliasSeq(T...) = T;

private template MemberFunctionType(alias operation)
{
    static if (is(typeof(&operation) Function : Function*) &&
        is(Function == function))
        alias MemberFunctionType = Function;
    else static if (is(typeof(operation) Function == function))
        alias MemberFunctionType = Function;
    else
        alias MemberFunctionType = void;
}

private template MemberParameters(alias operation)
{
    static if (is(MemberFunctionType!operation Parameters == function))
        alias MemberParameters = Parameters;
    else
        alias MemberParameters = AliasSeq!();
}

private template MemberReturnType(alias operation)
{
    static if (is(MemberFunctionType!operation Return == return))
        alias MemberReturnType = Return;
    else
        alias MemberReturnType = void;
}

private template HasExactParameterTypes(alias operation, Args...)
{
    alias Parameters = MemberParameters!operation;
    static if (Parameters.length != Args.length)
        enum HasExactParameterTypes = false;
    else
    {
        enum bool matches = () {
            static foreach (index; 0 .. Args.length)
            {
                static if (!is(Parameters[index] == Args[index]))
                    return false;
            }
            return true;
        }();
        enum HasExactParameterTypes = matches;
    }
}

private template hasDeinitFamily(T)
{
    alias U = Unqual!T;
    static if (is(U == struct) || is(U == union))
        enum hasDeinitFamily = __traits(hasMember, U, "deinit");
    else
        enum hasDeinitFamily = false;
}

private template validDeinitOverloadCount(T)
{
    alias U = Unqual!T;
    static if (!hasDeinitFamily!U)
        enum validDeinitOverloadCount = 0;
    else
    {
        enum size_t count = () {
            size_t result;
            static foreach (alias operation; __traits(getOverloads, U, "deinit"))
            {
                static if (
                    __traits(getProtection, operation) == "public" &&
                    !__traits(isStaticFunction, operation) &&
                    is(MemberReturnType!operation == void))
                {
                    ++result;
                }
            }
            return result;
        }();
        enum validDeinitOverloadCount = count;
    }
}

private template exactDeinitOverloadCount(T, Args...)
{
    alias U = Unqual!T;
    static if (!hasDeinitFamily!U)
        enum exactDeinitOverloadCount = 0;
    else
    {
        enum size_t count = () {
            size_t result;
            static foreach (alias operation; __traits(getOverloads, U, "deinit"))
            {
                static if (
                    __traits(getProtection, operation) == "public" &&
                    !__traits(isStaticFunction, operation) &&
                    is(MemberReturnType!operation == void) &&
                    HasExactParameterTypes!(operation, Args))
                {
                    ++result;
                }
            }
            return result;
        }();
        enum exactDeinitOverloadCount = count;
    }
}

private template NeedsDeinitImpl(T)
{
    alias U = Unqual!T;

    static if (hasDeinitFamily!U)
    {
        static assert(
            validDeinitOverloadCount!U != 0,
            U.stringof ~
                ".deinit must contain a public, non-static void overload",
        );
        enum NeedsDeinitImpl = true;
    }
    else static if (is(U == struct))
    {
        // During the migration away from destructor-owned resources, do not
        // structurally reinterpret an aggregate whose D destruction semantics
        // are still elaborate. Once ordinary owner destructors are removed,
        // their containing aggregates naturally become structurally eligible.
        static if (hasElaborateDestructor!U)
            enum NeedsDeinitImpl = false;
        else
        {
            enum bool result = () {
                static foreach (index; 0 .. U.tupleof.length)
                {
                    static if (NeedsDeinitImpl!(typeof(U.tupleof[index])))
                        return true;
                }
                return false;
            }();
            enum NeedsDeinitImpl = result;
        }
    }
    else static if (is(U == union))
    {
        enum bool result = () {
            static foreach (index; 0 .. U.tupleof.length)
            {
                static if (NeedsDeinitImpl!(typeof(U.tupleof[index])))
                    return true;
            }
            return false;
        }();
        enum NeedsDeinitImpl = result;
    }
    else static if (is(U == Element[Length], Element, size_t Length))
        enum NeedsDeinitImpl = NeedsDeinitImpl!Element;
    else
        enum NeedsDeinitImpl = false;
}

/// True when explicit deinitialization of a live `T` performs meaningful work.
///
/// This is deliberately not an ownership classifier. In particular, borrowed
/// pointers and slices are false, as are lexical RAII values that rely only on
/// a D destructor.
template needsDeinit(T)
{
    enum needsDeinit = NeedsDeinitImpl!T;
}

/// Explicitly deinitializes a mutable live value.
///
/// A real member `deinit` customization is authoritative. Structural cleanup
/// is used only for destructor-free aggregates without such a member and walks
/// fields in reverse declaration order. Raw pointers are never accepted as
/// direct cleanup targets.
void deinit(T, Args...)(ref T value, auto ref Args arguments)
{
    alias U = Unqual!T;

    static assert(is(T == U), "deinit requires a mutable lvalue");
    static assert(!is(U == P*, P), "deinit does not accept raw pointers");
    static assert(
        needsDeinit!U,
        U.stringof ~ " does not participate in explicit deinitialization",
    );

    static if (hasDeinitFamily!U)
    {
        static assert(
            exactDeinitOverloadCount!(U, Args) == 1,
            U.stringof ~
                ".deinit has no unique public overload with the requested signature",
        );
        __traits(getMember, value, "deinit")(arguments);
    }
    else
    {
        static assert(
            Args.length == 0,
            "structural deinit does not accept cleanup context arguments",
        );
        static assert(
            !hasElaborateDestructor!U,
            U.stringof ~
                " still has D destructor semantics and cannot use structural deinit",
        );

        static if (is(U == struct))
        {
            static foreach (offset; 0 .. U.tupleof.length)
            {
                static if (needsDeinit!(typeof(
                        U.tupleof[U.tupleof.length - 1 - offset])))
                {
                    deinit(value.tupleof[U.tupleof.length - 1 - offset]);
                }
            }
        }
        else static if (is(U == union))
        {
            static assert(false,
                "a raw union with cleanup-bearing members requires tagged lifetime metadata");
        }
        else static if (is(U == Element[Length], Element, size_t Length))
        {
            foreach_reverse (ref element; value)
                deinit(element);
        }
        else
        {
            static assert(false, U.stringof ~ " has no structural deinit rule");
        }
    }
}

/// Move-constructs `target` from `source` without cleaning `target` first.
/// `target` must denote dead or uninitialized storage.
void moveEmplace(T)(ref T source, ref T target) @system
{
    coreMoveEmplace(source, target);
}

/// Replaces a live explicit-deinit owner with `source`.
///
/// This intentionally applies only to destructor-free values that participate
/// in the explicit deinit protocol. Semantic resources outside that protocol,
/// such as a live Thread, cannot accidentally acquire generic replacement
/// semantics merely because their representation is structurally simple.
void moveAssign(T)(ref T source, ref T target) @system
        if (is(T == Unqual!T) && needsDeinit!T && !hasElaborateDestructor!T)
{
    if (&source == &target)
        return;

    deinit(target);
    coreMoveEmplace(source, target);
}

unittest
{
    struct TrackedOwner
    {
    nothrow @nogc:

        int id;
        size_t* count;
        int* order;

        @disable this(this);

        void deinit()
        {
            order[(*count)++] = id;
        }
    }

    struct Aggregate
    {
        TrackedOwner first;
        int* borrowed;
        TrackedOwner second;
    }

    struct Authoritative
    {
    nothrow @nogc:

        TrackedOwner nested;
        size_t* memberCalls;

        void deinit()
        {
            ++*memberCalls;
        }
    }

    static assert(!needsDeinit!int);
    static assert(!needsDeinit!(int*));
    static assert(!needsDeinit!(int[]));
    static assert(needsDeinit!TrackedOwner);
    static assert(needsDeinit!Aggregate);
    static assert(needsDeinit!(TrackedOwner[2]));

    size_t count;
    int[8] order;
    Aggregate aggregate = Aggregate(
        TrackedOwner(1, &count, order.ptr),
        null,
        TrackedOwner(2, &count, order.ptr),
    );
    deinit(aggregate);
    assert(count == 2);
    assert(order[0] == 2);
    assert(order[1] == 1);

    size_t memberCalls;
    Authoritative authoritative = Authoritative(
        TrackedOwner(3, &count, order.ptr),
        &memberCalls,
    );
    deinit(authoritative);
    assert(memberCalls == 1);
    assert(count == 2);

    TrackedOwner[2] fixed = [
        TrackedOwner(4, &count, order.ptr),
        TrackedOwner(5, &count, order.ptr),
    ];
    deinit(fixed);
    assert(order[2] == 5);
    assert(order[3] == 4);

    TrackedOwner source = TrackedOwner(6, &count, order.ptr);
    TrackedOwner target = TrackedOwner(7, &count, order.ptr);
    moveAssign(source, target);
    assert(order[4] == 7);
    assert(source.id == TrackedOwner.init.id);
    assert(target.id == 6);
    deinit(target);
    assert(order[5] == 6);
}

unittest
{
    struct ContextOwner
    {
    nothrow @nogc:

        int* calls;

        void deinit(int* context)
        {
            ++*calls;
            ++*context;
        }
    }

    union Untagged
    {
        ContextOwner owner;
        int value;
    }

    static assert(needsDeinit!ContextOwner);
    static assert(needsDeinit!Untagged);
    static assert(__traits(compiles,
            (ref ContextOwner value, int* context) { deinit(value, context); }));
    static assert(!__traits(compiles,
            (ref ContextOwner value) { deinit(value); }));
    static assert(!__traits(compiles,
            (ref const(ContextOwner) value, int* context) { deinit(value, context); }));
    static assert(!__traits(compiles,
            (ref ContextOwner* pointer) { deinit(pointer); }));
    static assert(!__traits(compiles,
            (ref int value) { deinit(value); }));
    static assert(!__traits(compiles,
            (ref Untagged value) { deinit(value); }));

    int calls;
    int context;
    ContextOwner owner = ContextOwner(&calls);
    deinit(owner, &context);
    assert(calls == 1);
    assert(context == 1);
}

unittest
{
    struct DestructorOnly
    {
    nothrow @nogc:

        int* destructions;

        ~this()
        {
            ++*destructions;
        }
    }

    struct ContainsDestructorOnly
    {
        DestructorOnly value;
    }

    static assert(!needsDeinit!DestructorOnly);
    static assert(!needsDeinit!ContainsDestructorOnly);
}
