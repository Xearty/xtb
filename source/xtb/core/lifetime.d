module xtb.core.lifetime;

nothrow @nogc:

import core.internal.traits : Unqual, hasElaborateDestructor;
import core.lifetime : coreMoveEmplace = moveEmplace, forward;
import xtb.core.types : String;

private alias AliasSeq(T...) = T;

/// Associates a raw union field with its discriminator and inactive tag.
///
/// Apply this to the union field of a containing aggregate:
///
/// ```d
/// @taggedBy("kind", Kind.none)
/// Payload payload;
/// ```
struct TaggedBy(Tag)
{
    String discriminator;
    Tag inactive;
}

/// Overrides the default enum-member-name mapping for one raw union member.
struct TaggedCase(Tag)
{
    Tag tag;
}

/// Creates tagged-union lifetime metadata for a raw union field.
TaggedBy!Tag taggedBy(Tag)(String discriminator, Tag inactive) pure @safe
{
    return TaggedBy!Tag(discriminator, inactive);
}

/// Overrides the discriminator value associated with a raw union member.
TaggedCase!Tag taggedCase(Tag)(Tag tag) pure @safe
{
    return TaggedCase!Tag(tag);
}

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

private bool hasFunctionAttribute(alias operation, String wanted)() pure @safe
{
    static foreach (attribute; __traits(getFunctionAttributes, operation))
        if (attribute == wanted)
            return true;
    return false;
}

private bool parameterRequiresLvalue(alias operation, size_t index)() pure @safe
{
    alias FunctionPointer = typeof(&operation);
    static foreach (storageClass; __traits(getParameterStorageClasses, FunctionPointer, index))
        if (storageClass == "ref" || storageClass == "out")
            return true;
    return false;
}

private template IsCompatibleDeinitOverload(alias operation, arguments...)
{
    alias Parameters = MemberParameters!operation;
    static if (
        __traits(getProtection, operation) != "public" ||
        __traits(isStaticFunction, operation) ||
        !is(MemberReturnType!operation == void) ||
        hasFunctionAttribute!(operation, "immutable")() ||
        hasFunctionAttribute!(operation, "shared")() ||
        Parameters.length != arguments.length)
        enum IsCompatibleDeinitOverload = false;
    else
    {
        enum bool matches = () {
            static foreach (index; 0 .. arguments.length)
            {
                static if (!is(Parameters[index] == typeof(arguments[index])))
                    return false;
                static if (parameterRequiresLvalue!(operation, index)() &&
                    !__traits(isRef, arguments[index]))
                    return false;
            }
            return true;
        }();
        enum IsCompatibleDeinitOverload = matches;
    }
}

private template hasDeinitFamily(T)
{
    alias U = Unqual!T;
    static if ((is(U == struct) || is(U == union)) &&
        __traits(hasMember, U, "deinit"))
        enum hasDeinitFamily = __traits(getOverloads, U, "deinit").length != 0;
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

private template compatibleDeinitOverloadCount(T, arguments...)
{
    alias U = Unqual!T;
    static if (!hasDeinitFamily!U)
        enum compatibleDeinitOverloadCount = 0;
    else
    {
        enum size_t count = () {
            size_t result;
            static foreach (alias operation; __traits(getOverloads, U, "deinit"))
            {
                static if (IsCompatibleDeinitOverload!(operation, arguments))
                    ++result;
            }
            return result;
        }();
        enum compatibleDeinitOverloadCount = count;
    }
}

private template IsTaggedByAttribute(A)
{
    static if (is(A == TaggedBy!Tag, Tag))
        enum IsTaggedByAttribute = true;
    else
        enum IsTaggedByAttribute = false;
}

private template IsTaggedCaseAttribute(A)
{
    static if (is(A == TaggedCase!Tag, Tag))
        enum IsTaggedCaseAttribute = true;
    else
        enum IsTaggedCaseAttribute = false;
}

private template HasNamedField(T, size_t index)
{
    alias U = Unqual!T;
    enum name = __traits(identifier, U.tupleof[index]);
    enum HasNamedField = __traits(compiles, __traits(getMember, U, name));
}

private template FieldSymbol(T, size_t index)
{
    alias U = Unqual!T;
    enum name = __traits(identifier, U.tupleof[index]);
    alias FieldSymbol = __traits(getMember, U, name);
}

private template UnionMemberSymbol(T, size_t index)
{
    alias U = Unqual!T;
    enum name = __traits(identifier, U.tupleof[index]);
    alias UnionMemberSymbol = __traits(getMember, U, name);
}

private size_t taggedByAttributeCount(T, size_t index)() pure @safe
{
    size_t result;
    static if (HasNamedField!(T, index))
        static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
            {
            static if (__traits(compiles, typeof(attribute)))
                static if (IsTaggedByAttribute!(typeof(attribute)))
                    ++result;
        }
    return result;
}

private auto taggedByAttribute(T, size_t index)() pure @safe
{
    static assert(taggedByAttributeCount!(T, index) == 1,
        "tagged lifetime payload field must have exactly one @taggedBy");
    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
    {
        static if (__traits(compiles, typeof(attribute)))
            static if (IsTaggedByAttribute!(typeof(attribute)))
                return attribute;
    }
}

private size_t taggedCaseAttributeCount(T, size_t index)() pure @safe
{
    size_t result;
    static foreach (attribute; __traits(getAttributes,
            UnionMemberSymbol!(T, index)))
    {
        static if (__traits(compiles, typeof(attribute)))
            static if (IsTaggedCaseAttribute!(typeof(attribute)))
                ++result;
    }
    return result;
}

private auto taggedCaseAttribute(T, size_t index)() pure @safe
{
    static assert(taggedCaseAttributeCount!(T, index) == 1,
        "tagged union member must have exactly one @taggedCase override");
    static foreach (attribute; __traits(getAttributes,
            UnionMemberSymbol!(T, index)))
    {
        static if (__traits(compiles, typeof(attribute)))
            static if (IsTaggedCaseAttribute!(typeof(attribute)))
                return attribute;
    }
}

private size_t fieldIndexNamed(T, String name, size_t index = 0)() pure @safe
{
    alias U = Unqual!T;
    static if (index == U.tupleof.length)
        return size_t.max;
    else static if (__traits(identifier, U.tupleof[index]) == name)
        return index;
    else
        return fieldIndexNamed!(U, name, index + 1)();
}

private size_t enumValueCount(Tag)(Tag value) pure @safe
{
    alias U = Unqual!Tag;
    size_t result;
    static foreach (member; __traits(allMembers, U))
    {
        static if (__traits(hasMember, U, member))
            if (__traits(getMember, U, member) == value)
                ++result;
    }
    return result;
}

private bool enumValuesAreUnique(Tag)() pure @safe
{
    alias U = Unqual!Tag;
    alias members = __traits(allMembers, U);
    static foreach (leftIndex, left; members)
    {
        static if (__traits(hasMember, U, left))
            static foreach (rightIndex, right; members)
                {
                static if (rightIndex > leftIndex &&
                    __traits(hasMember, U, right))
                    if (__traits(getMember, U, left) ==
                        __traits(getMember, U, right))
                        return false;
            }
    }
    return true;
}

private Tag unionMemberTag(Payload, size_t index, Tag)() pure @safe
{
    alias P = Unqual!Payload;
    alias U = Unqual!Tag;
    enum caseAttributeCount = taggedCaseAttributeCount!(P, index)();
    static assert(caseAttributeCount <= 1,
        "a tagged union member may have at most one @taggedCase override");

    static if (caseAttributeCount == 1)
    {
        enum attribute = taggedCaseAttribute!(P, index)();
        static assert(is(Unqual!(typeof(attribute.tag)) == U),
            "@taggedCase value must have the discriminator enum type");
        return cast(U) attribute.tag;
    }
    else
    {
        enum memberName = __traits(identifier, P.tupleof[index]);
        static assert(__traits(hasMember, U, memberName),
            "tagged union member has no same-named discriminator value; add @taggedCase");
        enum value = __traits(getMember, U, memberName);
        static assert(is(typeof(value) == U),
            "same-named tagged union discriminator symbol is not an enum member");
        return value;
    }
}

private size_t unionMembersForTag(Payload, Tag)(Tag tag) pure @safe
{
    alias P = Unqual!Payload;
    size_t result;
    static foreach (index; 0 .. P.tupleof.length)
        if (unionMemberTag!(P, index, Tag)() == tag)
            ++result;
    return result;
}

private template ValidateTaggedPayload(T, size_t payloadIndex)
{
    alias U = Unqual!T;
    enum metadata = taggedByAttribute!(U, payloadIndex)();
    alias MetadataTag = Unqual!(typeof(metadata.inactive));
    enum discriminatorIndex = fieldIndexNamed!(U, metadata.discriminator)();

    static assert(discriminatorIndex != size_t.max,
        "@taggedBy discriminator field does not exist in the containing aggregate");
    alias Discriminator = Unqual!(typeof(U.tupleof[discriminatorIndex]));
    alias Payload = Unqual!(typeof(U.tupleof[payloadIndex]));
    static assert(is(Discriminator == enum),
        "@taggedBy discriminator field must have an enum type");
    static assert(is(Discriminator == MetadataTag),
        "@taggedBy inactive value must have the discriminator enum type");
    static assert(is(Payload == union),
        "@taggedBy may only annotate a raw union field");
    static assert(enumValuesAreUnique!Discriminator(),
        "tagged union discriminator enum values must be unique");
    static assert(enumValueCount!Discriminator(metadata.inactive) == 1,
        "@taggedBy inactive value must identify exactly one discriminator enum member");
    static assert(U.init.tupleof[discriminatorIndex] == metadata.inactive,
        "@taggedBy inactive value must match the discriminator field's .init value");

    static foreach (memberIndex; 0 .. Payload.tupleof.length)
    {
        static assert(enumValueCount!Discriminator(
                unionMemberTag!(Payload, memberIndex, Discriminator)()) == 1,
            "tagged union member maps to a value not declared by the discriminator enum");
        static assert(unionMemberTag!(Payload, memberIndex, Discriminator)() !=
                metadata.inactive,
            "the inactive discriminator value cannot identify an active union member");
        static foreach (otherIndex; memberIndex + 1 .. Payload.tupleof.length)
            static assert(unionMemberTag!(Payload, memberIndex, Discriminator)() !=
                    unionMemberTag!(Payload, otherIndex, Discriminator)(),
                "multiple tagged union members map to the same discriminator value");
    }

    static foreach (member; __traits(allMembers, Discriminator))
    {
        static if (__traits(hasMember, Discriminator, member))
            static if (__traits(getMember, Discriminator, member) != metadata.inactive)
                static assert(unionMembersForTag!(Payload, Discriminator)(
                        __traits(getMember, Discriminator, member)) == 1,
                    "every non-inactive discriminator value must map to exactly one union member");
    }

    enum ValidateTaggedPayload = true;
}

private template ValidateTaggedLifetime(T)
{
    alias U = Unqual!T;
    static foreach (index; 0 .. U.tupleof.length)
    {
        static assert(taggedByAttributeCount!(U, index)() <= 1,
            "an aggregate field may have at most one @taggedBy attribute");
        static if (taggedByAttributeCount!(U, index)() == 1)
            static assert(ValidateTaggedPayload!(U, index));
    }
    enum ValidateTaggedLifetime = true;
}

private template IsTaggedPayloadField(T, size_t index)
{
    enum IsTaggedPayloadField = taggedByAttributeCount!(Unqual!T, index)() == 1;
}

// Package-level tagged-union introspection used by other core facilities such
// as structural pretty printing. Keep the reflection and validation rules in
// one place so observers cannot accidentally disagree with lifetime cleanup
// about which raw union member is active.
package template isTaggedPayloadField(T, size_t index)
{
    enum isTaggedPayloadField = IsTaggedPayloadField!(T, index);
}

package auto taggedPayloadMetadata(T, size_t payloadIndex)() pure @safe
{
    alias U = Unqual!T;
    static assert(ValidateTaggedPayload!(U, payloadIndex));
    return taggedByAttribute!(U, payloadIndex)();
}

package size_t taggedPayloadDiscriminatorIndex(T, size_t payloadIndex)()
pure @safe
{
    alias U = Unqual!T;
    enum metadata = taggedPayloadMetadata!(U, payloadIndex)();
    return fieldIndexNamed!(U, metadata.discriminator)();
}

package Tag taggedPayloadMemberTag(Payload, size_t memberIndex, Tag)()
pure @safe
{
    return unionMemberTag!(Payload, memberIndex, Tag)();
}

private void deinitTaggedPayload(T, size_t payloadIndex)(ref T value)
{
    alias U = Unqual!T;
    static assert(ValidateTaggedPayload!(U, payloadIndex));
    enum metadata = taggedByAttribute!(U, payloadIndex)();
    alias Tag = Unqual!(typeof(metadata.inactive));
    alias Payload = Unqual!(typeof(U.tupleof[payloadIndex]));
    enum discriminatorIndex = fieldIndexNamed!(U, metadata.discriminator)();
    const active = value.tupleof[discriminatorIndex];

    if (active == metadata.inactive)
        return;

    static foreach (memberIndex; 0 .. Payload.tupleof.length)
    {
        {
            enum mappedTag = unionMemberTag!(Payload, memberIndex, Tag)();
            if (active == mappedTag)
            {
                static if (needsDeinit!(typeof(Payload.tupleof[memberIndex])))
                    deinit(value.tupleof[payloadIndex].tupleof[memberIndex]);
                return;
            }
        }
    }

    // A discriminator outside the declared enum domain provides no safe active
    // member to inspect. Checked builds retain the assertion; release-fast
    // avoids guessing which union storage is live.
    assert(false, "invalid tagged union discriminator");
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
            static assert(ValidateTaggedLifetime!U);
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
            compatibleDeinitOverloadCount!(U, arguments) != 0,
            U.stringof ~
                ".deinit has no public member overload compatible with the requested signature",
        );
        static assert(
            __traits(compiles,
                __traits(getMember, value, "deinit")(forward!arguments)),
            U.stringof ~ ".deinit overload resolution failed for the requested signature",
        );
        static assert(is(typeof(
                __traits(getMember, value, "deinit")(forward!arguments)) == void),
            U.stringof ~ ".deinit must return void");
        __traits(getMember, value, "deinit")(forward!arguments);
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
                static if (IsTaggedPayloadField!(U,
                        U.tupleof.length - 1 - offset))
                {
                    static if (needsDeinit!(typeof(
                            U.tupleof[U.tupleof.length - 1 - offset])))
                        deinitTaggedPayload!(U,
                            U.tupleof.length - 1 - offset)(value);
                }
                else static if (needsDeinit!(typeof(
                        U.tupleof[U.tupleof.length - 1 - offset])))
                    deinit(value.tupleof[U.tupleof.length - 1 - offset]);
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

    struct NamedDeinitField
    {
        int deinit;
        TrackedOwner owner;
    }

    static assert(!needsDeinit!int);
    static assert(!needsDeinit!(int*));
    static assert(!needsDeinit!(int[]));
    static assert(needsDeinit!TrackedOwner);
    static assert(needsDeinit!Aggregate);
    static assert(needsDeinit!NamedDeinitField);
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

    NamedDeinitField namedField = NamedDeinitField(
        42,
        TrackedOwner(8, &count, order.ptr),
    );
    deinit(namedField);
    assert(order[6] == 8);
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

    struct RefContextOwner
    {
    nothrow @nogc:

        int* calls;

        void deinit(ref int context)
        {
            ++*calls;
            ++context;
        }
    }

    struct QualifiedOwner
    {
    nothrow @nogc:

        int* mutableCalls;

        void deinit()
        {
            ++*mutableCalls;
        }

        void deinit() const
        {
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
    static assert(__traits(compiles,
            (ref RefContextOwner value, ref int context) { deinit(value, context); }));
    static assert(!__traits(compiles,
            (ref RefContextOwner value) { deinit(value, 3); }));
    static assert(__traits(compiles,
            (ref QualifiedOwner value) { deinit(value); }));

    int calls;
    int context;
    ContextOwner owner = ContextOwner(&calls);
    deinit(owner, &context);
    assert(calls == 1);
    assert(context == 1);

    int refCalls;
    int refContext;
    RefContextOwner refOwner = RefContextOwner(&refCalls);
    deinit(refOwner, refContext);
    assert(refCalls == 1);
    assert(refContext == 1);

    int mutableCalls;
    QualifiedOwner qualifiedOwner = QualifiedOwner(&mutableCalls);
    deinit(qualifiedOwner);
    assert(mutableCalls == 1);
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

unittest
{
    struct TaggedOwner
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

    enum FirstKind : ubyte
    {
        none,
        text,
    }

    union FirstPayload
    {
        TaggedOwner text;
    }

    enum SecondKind : ubyte
    {
        none,
        values,
    }

    union SecondPayload
    {
        @taggedCase(SecondKind.values)
        TaggedOwner differentlyNamed;
    }

    struct Message
    {
        TaggedOwner name;

        FirstKind firstKind;
        @taggedBy("firstKind", FirstKind.none)
        FirstPayload firstPayload;

        SecondKind secondKind;
        @taggedBy("secondKind", SecondKind.none)
        SecondPayload secondPayload;
    }

    static assert(needsDeinit!Message);

    size_t count;
    int[8] order;
    Message message;
    message.name = TaggedOwner(1, &count, order.ptr);
    message.firstKind = FirstKind.text;
    message.firstPayload.text = TaggedOwner(2, &count, order.ptr);
    message.secondKind = SecondKind.values;
    message.secondPayload.differentlyNamed = TaggedOwner(3, &count, order.ptr);

    deinit(message);
    assert(count == 3);
    assert(order[0] == 3);
    assert(order[1] == 2);
    assert(order[2] == 1);
    assert(message.firstKind == FirstKind.text);
    assert(message.secondKind == SecondKind.values);
    assert(message.firstPayload.text.id == 2);
    assert(message.secondPayload.differentlyNamed.id == 3);

    struct Inactive
    {
        FirstKind kind;
        @taggedBy("kind", FirstKind.none)
        FirstPayload payload;
    }

    Inactive inactive;
    deinit(inactive);
}

unittest
{
    struct Owner
    {
        void deinit()
        {
        }
    }

    enum Kind : ubyte
    {
        none,
        one,
        two,
    }

    union ValidPayload
    {
        Owner one;
        Owner two;
    }

    struct MissingDiscriminator
    {
        Kind kind;
        @taggedBy("missing", Kind.none)
        ValidPayload payload;
    }

    struct NonEnumDiscriminator
    {
        int kind;
        @taggedBy("kind", Kind.none)
        ValidPayload payload;
    }

    struct NonUnionPayload
    {
        Kind kind;
        @taggedBy("kind", Kind.none)
        Owner payload;
    }

    struct UnknownInactive
    {
        Kind kind;
        @taggedBy("kind", cast(Kind) 99)
        ValidPayload payload;
    }

    enum NonInactiveDefaultKind : ubyte
    {
        one,
        none,
        two,
    }

    union NonInactiveDefaultPayload
    {
        Owner one;
        Owner two;
    }

    struct NonInactiveDefault
    {
        NonInactiveDefaultKind kind;
        @taggedBy("kind", NonInactiveDefaultKind.none)
        NonInactiveDefaultPayload payload;
    }

    union MissingCasePayload
    {
        Owner one;
    }

    struct MissingCase
    {
        Kind kind;
        @taggedBy("kind", Kind.none)
        MissingCasePayload payload;
    }

    union MissingNamePayload
    {
        Owner differentlyNamed;
        Owner two;
    }

    struct MissingName
    {
        Kind kind;
        @taggedBy("kind", Kind.none)
        MissingNamePayload payload;
    }

    union DuplicateCasePayload
    {
        Owner one;
        @taggedCase(Kind.one)
        Owner duplicate;
        Owner two;
    }

    struct DuplicateCase
    {
        Kind kind;
        @taggedBy("kind", Kind.none)
        DuplicateCasePayload payload;
    }

    union InactiveCasePayload
    {
        @taggedCase(Kind.none)
        Owner inactive;
        Owner one;
        Owner two;
    }

    struct InactiveCase
    {
        Kind kind;
        @taggedBy("kind", Kind.none)
        InactiveCasePayload payload;
    }

    enum DuplicateValueKind : ubyte
    {
        none = 0,
        one = 1,
        two = 1,
    }

    union DuplicateValuePayload
    {
        Owner one;
        @taggedCase(DuplicateValueKind.two)
        Owner two;
    }

    struct DuplicateEnumValue
    {
        DuplicateValueKind kind;
        @taggedBy("kind", DuplicateValueKind.none)
        DuplicateValuePayload payload;
    }

    enum OtherKind : ubyte
    {
        value,
    }

    union WrongCaseTypePayload
    {
        @taggedCase(OtherKind.value)
        Owner one;
        Owner two;
    }

    struct WrongCaseType
    {
        Kind kind;
        @taggedBy("kind", Kind.none)
        WrongCaseTypePayload payload;
    }

    static assert(!__traits(compiles, needsDeinit!MissingDiscriminator));
    static assert(!__traits(compiles, needsDeinit!NonEnumDiscriminator));
    static assert(!__traits(compiles, needsDeinit!NonUnionPayload));
    static assert(!__traits(compiles, needsDeinit!UnknownInactive));
    static assert(!__traits(compiles, needsDeinit!NonInactiveDefault));
    static assert(!__traits(compiles, needsDeinit!MissingCase));
    static assert(!__traits(compiles, needsDeinit!MissingName));
    static assert(!__traits(compiles, needsDeinit!DuplicateCase));
    static assert(!__traits(compiles, needsDeinit!InactiveCase));
    static assert(!__traits(compiles, needsDeinit!DuplicateEnumValue));
    static assert(!__traits(compiles, needsDeinit!WrongCaseType));
}
