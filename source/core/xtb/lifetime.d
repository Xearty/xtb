module xtb.lifetime;

nothrow @nogc:

import core.internal.lifetime : emplace_initializer = emplaceInitializer;
import core.internal.traits : Unqual, has_elaborate_copy_constructor = hasElaborateCopyConstructor,
    has_elaborate_destructor = hasElaborateDestructor;
import core.lifetime : core_move_emplace = moveEmplace, forward;
import xtb.panic;
import xtb.types;

private alias AliasSeq(T...) = T;

/// Associates a raw union field with its discriminator and inactive tag.
///
/// Apply this to the union field of a containing aggregate:
///
/// ```d
/// @tagged_by("kind", Kind.none)
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

/// Creates tagged-union lifetime metadata while inferring the tag type.
TaggedBy!Tag tagged_by(Tag)(String discriminator, Tag inactive) pure @safe
{
    return TaggedBy!Tag(discriminator, inactive);
}

/// Overrides a raw union member's discriminator value while inferring its type.
TaggedCase!Tag tagged_case(Tag)(Tag tag) pure @safe
{
    return TaggedCase!Tag(tag);
}

private template MemberFunctionType(alias operation)
{
    static if (
        is(typeof(&operation) Function : Function*)
        && is(Function == function)
    )
    {
        alias MemberFunctionType = Function;
    }
    else static if (is(typeof(operation) Function == function))
    {
        alias MemberFunctionType = Function;
    }
    else
    {
        alias MemberFunctionType = void;
    }
}

private template MemberParameters(alias operation)
{
    static if (is(MemberFunctionType!operation Parameters == function))
    {
        alias MemberParameters = Parameters;
    }
    else
    {
        alias MemberParameters = AliasSeq!();
    }
}

private template MemberReturnType(alias operation)
{
    static if (is(MemberFunctionType!operation Return == return))
    {
        alias MemberReturnType = Return;
    }
    else
    {
        alias MemberReturnType = void;
    }
}

private bool has_function_attribute(alias operation, String wanted)() pure @safe
{
    static foreach (attribute; __traits(getFunctionAttributes, operation))
    {
        if (attribute == wanted)
            return true;
    }

    return false;
}

private bool parameter_requires_lvalue(alias operation, usize index)() pure @safe
{
    alias FunctionPointer = typeof(&operation);

    static foreach (storage_class; __traits(
        getParameterStorageClasses,
        FunctionPointer,
        index,
    ))
    {
        if (storage_class == "ref" || storage_class == "out")
            return true;
    }

    return false;
}

private template is_compatible_deinit_overload(alias operation, arguments...)
{
    alias Parameters = MemberParameters!operation;

    static if (
        __traits(getProtection, operation) != "public"
        || __traits(isStaticFunction, operation)
        || !is(MemberReturnType!operation == void)
        || has_function_attribute!(operation, "immutable")()
        || has_function_attribute!(operation, "shared")()
        || Parameters.length != arguments.length
    )
    {
        enum is_compatible_deinit_overload = false;
    }
    else
    {
        enum bool matches = ()
        {
            static foreach (index; 0 .. arguments.length)
            {
                static if (!is(Parameters[index] == typeof(arguments[index])))
                {
                    return false;
                }

                static if (
                    parameter_requires_lvalue!(operation, index)()
                    && !__traits(isRef, arguments[index])
                )
                {
                    return false;
                }
            }

            return true;
        }();

        enum is_compatible_deinit_overload = matches;
    }
}

private template instance_deinit_overload_count(T)
{
    alias U = Unqual!T;

    static if (
        !(
            (is(U == struct) || is(U == union))
            && __traits(hasMember, U, "deinit")
        )
    )
    {
        enum instance_deinit_overload_count = 0;
    }
    else
    {
        enum usize count = ()
        {
            usize result;

            static foreach (alias operation; __traits(getOverloads, U, "deinit"))
            {
                static if (!__traits(isStaticFunction, operation))
                {
                    ++result;
                }
            }

            return result;
        }();

        enum instance_deinit_overload_count = count;
    }
}

private template has_deinit_family(T)
{
    enum has_deinit_family = instance_deinit_overload_count!(Unqual!T) != 0;
}

private template valid_deinit_overload_count(T)
{
    alias U = Unqual!T;

    static if (!has_deinit_family!U)
    {
        enum valid_deinit_overload_count = 0;
    }
    else
    {
        enum usize count = ()
        {
            usize result;

            static foreach (alias operation; __traits(getOverloads, U, "deinit"))
            {
                static if (
                    __traits(getProtection, operation) == "public"
                    && !__traits(isStaticFunction, operation)
                    && is(MemberReturnType!operation == void)
                    && !has_function_attribute!(operation, "immutable")()
                    && !has_function_attribute!(operation, "shared")()
                )
                {
                    ++result;
                }
            }

            return result;
        }();

        enum valid_deinit_overload_count = count;
    }
}

private template compatible_deinit_overload_count(T, arguments...)
{
    alias U = Unqual!T;

    static if (!has_deinit_family!U)
    {
        enum compatible_deinit_overload_count = 0;
    }
    else
    {
        enum usize count = ()
        {
            usize result;

            static foreach (alias operation; __traits(getOverloads, U, "deinit"))
            {
                static if (is_compatible_deinit_overload!(operation, arguments))
                {
                    ++result;
                }
            }

            return result;
        }();

        enum compatible_deinit_overload_count = count;
    }
}

private template is_tagged_by_attribute(A)
{
    static if (is(A == TaggedBy!Tag, Tag))
    {
        enum is_tagged_by_attribute = true;
    }
    else
    {
        enum is_tagged_by_attribute = false;
    }
}

private template is_tagged_case_attribute(A)
{
    static if (is(A == TaggedCase!Tag, Tag))
    {
        enum is_tagged_case_attribute = true;
    }
    else
    {
        enum is_tagged_case_attribute = false;
    }
}

private template has_named_field(T, usize index)
{
    alias U = Unqual!T;
    enum name = __traits(identifier, U.tupleof[index]);
    enum has_named_field = __traits(compiles, __traits(getMember, U, name));
}

private template FieldSymbol(T, usize index)
{
    alias U = Unqual!T;
    enum name = __traits(identifier, U.tupleof[index]);
    alias FieldSymbol = __traits(getMember, U, name);
}

private template UnionMemberSymbol(T, usize index)
{
    alias U = Unqual!T;
    enum name = __traits(identifier, U.tupleof[index]);
    alias UnionMemberSymbol = __traits(getMember, U, name);
}

private usize tagged_by_attribute_count(T, usize index)() pure @safe
{
    usize result;

    static if (has_named_field!(T, index))
    {
        static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
        {
            static if (__traits(compiles, typeof(attribute)))
            {
                static if (is_tagged_by_attribute!(typeof(attribute)))
                {
                    ++result;
                }
            }
        }
    }

    return result;
}

private auto tagged_by_attribute(T, usize index)() pure @safe
{
    static assert(
        tagged_by_attribute_count!(T, index) == 1,
        "tagged lifetime payload field must have exactly one @tagged_by",
    );

    static foreach (attribute; __traits(getAttributes, FieldSymbol!(T, index)))
    {
        static if (__traits(compiles, typeof(attribute)))
        {
            static if (is_tagged_by_attribute!(typeof(attribute)))
            {
                return attribute;
            }
        }
    }
}

private usize tagged_case_attribute_count(T, usize index)() pure @safe
{
    usize result;

    static foreach (attribute; __traits(
        getAttributes,
        UnionMemberSymbol!(T, index),
    ))
    {
        static if (__traits(compiles, typeof(attribute)))
        {
            static if (is_tagged_case_attribute!(typeof(attribute)))
            {
                ++result;
            }
        }
    }

    return result;
}

private auto tagged_case_attribute(T, usize index)() pure @safe
{
    static assert(
        tagged_case_attribute_count!(T, index) == 1,
        "tagged union member must have exactly one @tagged_case override",
    );

    static foreach (attribute; __traits(
        getAttributes,
        UnionMemberSymbol!(T, index),
    ))
    {
        static if (__traits(compiles, typeof(attribute)))
        {
            static if (is_tagged_case_attribute!(typeof(attribute)))
            {
                return attribute;
            }
        }
    }
}

private usize field_index_named(T, String name, usize index = 0)() pure @safe
{
    alias U = Unqual!T;

    static if (index == U.tupleof.length)
    {
        return usize.max;
    }
    else static if (__traits(identifier, U.tupleof[index]) == name)
    {
        return index;
    }
    else
    {
        return field_index_named!(U, name, index + 1)();
    }
}

private usize enum_value_count(Tag)(Tag value) pure @safe
{
    alias U = Unqual!Tag;
    usize result;

    static foreach (member; __traits(allMembers, U))
    {
        static if (__traits(hasMember, U, member))
        {
            if (__traits(getMember, U, member) == value)
                ++result;
        }
    }

    return result;
}

private bool enum_values_are_unique(Tag)() pure @safe
{
    alias U = Unqual!Tag;
    alias members = __traits(allMembers, U);

    static foreach (left_index, left; members)
    {
        static if (__traits(hasMember, U, left))
        {
            static foreach (right_index, right; members)
            {
                static if (
                    right_index > left_index
                    && __traits(hasMember, U, right)
                )
                {
                    if (
                        __traits(getMember, U, left)
                        == __traits(getMember, U, right)
                    )
                    {
                        return false;
                    }
                }
            }
        }
    }

    return true;
}

private Tag union_member_tag(Payload, usize index, Tag)() pure @safe
{
    alias P = Unqual!Payload;
    alias U = Unqual!Tag;
    enum case_attribute_count = tagged_case_attribute_count!(P, index)();

    static assert(
        case_attribute_count <= 1,
        "a tagged union member may have at most one @tagged_case override",
    );

    static if (case_attribute_count == 1)
    {
        enum attribute = tagged_case_attribute!(P, index)();

        static assert(
            is(Unqual!(typeof(attribute.tag)) == U),
            "@tagged_case value must have the discriminator enum type",
        );

        return cast(U) attribute.tag;
    }
    else
    {
        enum member_name = __traits(identifier, P.tupleof[index]);

        static assert(
            __traits(hasMember, U, member_name),
            "tagged union member has no same-named discriminator value; add @tagged_case",
        );

        enum value = __traits(getMember, U, member_name);

        static assert(
            is(typeof(value) == U),
            "same-named tagged union discriminator symbol is not an enum member",
        );

        return value;
    }
}

private usize union_members_for_tag(Payload, Tag)(Tag tag) pure @safe
{
    alias P = Unqual!Payload;
    usize result;

    static foreach (index; 0 .. P.tupleof.length)
    {
        if (union_member_tag!(P, index, Tag)() == tag)
            ++result;
    }

    return result;
}

private bool tag_mapping_is_valid(Payload, Tag, string member)(Tag inactive) pure @safe
{
    enum tag = __traits(getMember, Tag, member);

    if (tag == inactive) return true;

    enum matching_member_count = union_members_for_tag!(Payload, Tag)(tag);
    return matching_member_count == 1;
}

private template validate_tagged_payload(T, usize payload_index)
{
    alias U = Unqual!T;
    enum metadata = tagged_by_attribute!(U, payload_index)();
    alias MetadataTag = Unqual!(typeof(metadata.inactive));
    enum discriminator_index = field_index_named!(U, metadata.discriminator)();

    static assert(
        discriminator_index != usize.max,
        "@tagged_by discriminator field does not exist in the containing aggregate",
    );

    alias Discriminator = Unqual!(typeof(U.tupleof[discriminator_index]));
    alias Payload = Unqual!(typeof(U.tupleof[payload_index]));

    static assert(
        is(Discriminator == enum),
        "@tagged_by discriminator field must have an enum type",
    );
    static assert(
        is(Discriminator == MetadataTag),
        "@tagged_by inactive value must have the discriminator enum type",
    );
    static assert(
        is(Payload == union),
        "@tagged_by may only annotate a raw union field",
    );
    static assert(
        enum_values_are_unique!Discriminator(),
        "tagged union discriminator enum values must be unique",
    );
    static assert(
        enum_value_count!Discriminator(metadata.inactive) == 1,
        "@tagged_by inactive value must identify exactly one discriminator enum member",
    );
    static assert(
        U.init.tupleof[discriminator_index] == metadata.inactive,
        "@tagged_by inactive value must match the discriminator field's .init value",
    );

    static foreach (member_index; 0 .. Payload.tupleof.length)
    {
        static assert(
            enum_value_count!Discriminator(
                union_member_tag!(Payload, member_index, Discriminator)(),
            ) == 1,
            "tagged union member maps to a value not declared by the discriminator enum",
        );
        static assert(
            union_member_tag!(Payload, member_index, Discriminator)() != metadata.inactive,
            "the inactive discriminator value cannot identify an active union member",
        );

        static foreach (other_index; member_index + 1 .. Payload.tupleof.length)
        {
            static assert(
                union_member_tag!(Payload, member_index, Discriminator)()
                    != union_member_tag!(Payload, other_index, Discriminator)(),
                "multiple tagged union members map to the same discriminator value",
            );
        }
    }

    static foreach (member; __traits(allMembers, Discriminator))
    {
        static assert(
            tag_mapping_is_valid!(Payload, Discriminator, member)(metadata.inactive),
            "every non-inactive discriminator value must map to exactly one union member",
        );
    }

    enum validate_tagged_payload = true;
}

private template validate_tagged_lifetime(T)
{
    alias U = Unqual!T;

    static foreach (index; 0 .. U.tupleof.length)
    {
        static assert(
            tagged_by_attribute_count!(U, index)() <= 1,
            "an aggregate field may have at most one @tagged_by attribute",
        );

        static if (tagged_by_attribute_count!(U, index)() == 1)
        {
            static assert(validate_tagged_payload!(U, index));
        }
    }

    enum validate_tagged_lifetime = true;
}

private template is_tagged_payload_field_impl(T, usize index)
{
    enum is_tagged_payload_field_impl = tagged_by_attribute_count!(Unqual!T, index)() == 1;
}

// Package-level tagged-union introspection used by other core facilities such
// as structural pretty printing. Keep the reflection and validation rules in
// one place so observers cannot accidentally disagree with lifetime cleanup
// about which raw union member is active.
package(xtb) template is_tagged_payload_field(T, usize index)
{
    enum is_tagged_payload_field = is_tagged_payload_field_impl!(T, index);
}

package(xtb) auto tagged_payload_metadata(T, usize payload_index)() pure @safe
{
    alias U = Unqual!T;
    static assert(validate_tagged_payload!(U, payload_index));
    return tagged_by_attribute!(U, payload_index)();
}

package(xtb) usize tagged_payload_discriminator_index(T, usize payload_index)() pure @safe
{
    alias U = Unqual!T;
    enum metadata = tagged_payload_metadata!(U, payload_index)();
    return field_index_named!(U, metadata.discriminator)();
}

package(xtb) Tag tagged_payload_member_tag(Payload, usize member_index, Tag)() pure @safe
{
    return union_member_tag!(Payload, member_index, Tag)();
}

private void deinit_tagged_payload(T, usize payload_index)(ref T value)
{
    alias U = Unqual!T;
    static assert(validate_tagged_payload!(U, payload_index));
    enum metadata = tagged_by_attribute!(U, payload_index)();
    alias Tag = Unqual!(typeof(metadata.inactive));
    alias Payload = Unqual!(typeof(U.tupleof[payload_index]));
    enum discriminator_index = field_index_named!(U, metadata.discriminator)();
    const active = value.tupleof[discriminator_index];

    if (active == metadata.inactive)
        return;

    static foreach (member_index; 0 .. Payload.tupleof.length)
    {{
        enum mapped_tag = union_member_tag!(Payload, member_index, Tag)();

        if (active == mapped_tag)
        {
            static if (needs_deinit!(typeof(Payload.tupleof[member_index])))
            {
                deinit(value.tupleof[payload_index].tupleof[member_index]);
            }

            return;
        }
    }}

    // No union member is safe to inspect for an invalid discriminator.
    ensure(false, "invalid tagged union discriminator");
}

/// True when `T` has D destructor semantics.
///
/// `core.internal.traits.hasElaborateDestructor` can miss destructor hooks for
/// some structs (notably semantic obligation types such as `Thread`). Include
/// the compiler-visible destructor hooks directly and recurse through static
/// arrays so lifetime-sensitive generic code never treats such a value as
/// plain POD.
template has_d_destructor(T)
{
    alias U = Unqual!T;

    static if (is(U == struct))
    {
        enum has_d_destructor = has_elaborate_destructor!U
            || __traits(hasMember, U, "__dtor")
            || __traits(hasMember, U, "__xdtor");
    }
    else static if (is(U == Element[length], Element, usize length))
    {
        enum has_d_destructor = length != 0 && has_d_destructor!Element;
    }
    else
    {
        enum has_d_destructor = false;
    }
}

private template needs_deinit_impl(T)
{
    alias U = Unqual!T;

    static if (has_deinit_family!U)
    {
        static assert(
            valid_deinit_overload_count!U != 0,
            U.stringof
                ~ ".deinit must contain a public, non-static void overload"
                ~ " callable on a mutable value",
        );
        enum needs_deinit_impl = true;
    }
    else static if (is(U == struct))
    {
        // During the migration away from destructor-owned resources, do not
        // structurally reinterpret an aggregate whose D destruction semantics
        // are still elaborate. Once ordinary owner destructors are removed,
        // their containing aggregates naturally become structurally eligible.
        static if (has_d_destructor!U)
        {
            enum needs_deinit_impl = false;
        }
        else
        {
            static assert(validate_tagged_lifetime!U);

            enum bool result = ()
            {
                static foreach (index; 0 .. U.tupleof.length)
                {
                    static if (needs_deinit_impl!(typeof(U.tupleof[index])))
                    {
                        return true;
                    }
                }

                return false;
            }();

            enum needs_deinit_impl = result;
        }
    }
    else static if (is(U == union))
    {
        enum bool result = ()
        {
            static foreach (index; 0 .. U.tupleof.length)
            {
                static if (needs_deinit_impl!(typeof(U.tupleof[index])))
                {
                    return true;
                }
            }

            return false;
        }();

        enum needs_deinit_impl = result;
    }
    else static if (is(U == Element[length], Element, usize length))
    {
        enum needs_deinit_impl = needs_deinit_impl!Element;
    }
    else
    {
        enum needs_deinit_impl = false;
    }
}

/// True when explicit deinitialization of a live `T` performs meaningful work.
///
/// This is deliberately not an ownership classifier. In particular, borrowed
/// pointers and slices are false, as are lexical RAII values that rely only on
/// a D destructor.
template needs_deinit(T)
{
    enum needs_deinit = needs_deinit_impl!T;
}

/// True when a live `T` has either explicit or D destructor cleanup work.
template needs_finalization(T)
{
    enum needs_finalization = needs_deinit!T || has_d_destructor!T;
}

private template supports_context_free_deinit(T)
{
    alias U = Unqual!T;
    enum supports_context_free_deinit = __traits(
        compiles,
        (ref U value) nothrow @nogc
        {
            deinit(value);
        },
    );
}

private template supports_context_free_destroy(T)
{
    alias U = Unqual!T;
    enum supports_context_free_destroy = __traits(
        compiles,
        (ref U value) nothrow @nogc
        {
            destroy(value);
        },
    );
}

/// True when a container can discard a live `T` without extra cleanup context.
///
/// Cleanup-free values always qualify. Explicit-deinit values qualify only
/// when free `deinit(value)` is valid without additional arguments under
/// `nothrow @nogc`. Values using only D destructor semantics qualify when
/// `destroy(value)` satisfies the same attributes.
template can_finalize_without_context(T)
{
    static if (needs_deinit!T)
    {
        enum can_finalize_without_context = supports_context_free_deinit!T;
    }
    else static if (has_d_destructor!T)
    {
        enum can_finalize_without_context = supports_context_free_destroy!T;
    }
    else
    {
        enum can_finalize_without_context = true;
    }
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
        needs_deinit!U,
        U.stringof ~ " does not participate in explicit deinitialization",
    );

    static if (has_deinit_family!U)
    {
        static assert(
            compatible_deinit_overload_count!(U, arguments) != 0,
            U.stringof
                ~ ".deinit has no public member overload compatible with the requested signature",
        );
        static assert(
            __traits(compiles, value.deinit(forward!arguments)),
            U.stringof ~ ".deinit overload resolution failed for the requested signature",
        );
        static assert(
            is(typeof(value.deinit(forward!arguments)) == void),
            U.stringof ~ ".deinit must return void",
        );

        value.deinit(forward!arguments);
    }
    else
    {
        static assert(
            Args.length == 0,
            "structural deinit does not accept cleanup context arguments",
        );
        static assert(
            !has_d_destructor!U,
            U.stringof
                ~ " still has D destructor semantics and cannot use structural deinit",
        );

        static if (is(U == struct))
        {
            static foreach (offset; 0 .. U.tupleof.length)
            {{
                enum index = U.tupleof.length - 1 - offset;

                static if (is_tagged_payload_field_impl!(U, index))
                {
                    static if (needs_deinit!(typeof(U.tupleof[index])))
                    {
                        deinit_tagged_payload!(U, index)(value);
                    }
                }
                else static if (needs_deinit!(typeof(U.tupleof[index])))
                {
                    deinit(value.tupleof[index]);
                }
            }}
        }
        else static if (is(U == union))
        {
            static assert(
                false,
                "a raw union with cleanup-bearing members requires tagged lifetime metadata",
            );
        }
        else static if (is(U == Element[length], Element, usize length))
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

/// Finalizes a mutable live value without external cleanup context.
///
/// Explicit `deinit` is authoritative when present. Destructor-only values use
/// D's `destroy`. Cleanup-free values intentionally have no `finalize`
/// overload, so generic code cannot pretend that finalization work exists.
void finalize(T)(ref T value) if (needs_finalization!T && can_finalize_without_context!T)
{
    static if (needs_deinit!T)
    {
        deinit(value);
    }
    else
    {
        destroy(value);
    }
}

/// Moves `source` into a returned value.
///
/// Unlike druntime's move for plain POD structs, an XTB explicit owner is
/// reconstructed to `.init` so the source remains safely deinitializable.
/// `source` must be live, and every move hook of `T` must be safe to invoke for
/// its current state.
T move(T)(ref T source) @system
{
    T result = void;
    move_emplace(source, result);
    return result;
}

/// Move-constructs `target` from `source` without cleaning `target` first.
/// `source` must be live, `target` must denote dead or uninitialized storage,
/// and every move hook of `T` must be safe to invoke for its current state.
void move_emplace(T)(ref T source, ref T target) @system
{
    core_move_emplace(source, target);

    // druntime only wipes a moved source when D destructor/copy machinery is
    // elaborate. XTB explicit owners may deliberately have neither, while a
    // duplicated representation would still carry the same cleanup obligation.
    // Reconstruct those sources to `.init` so every successful XTB move leaves
    // a live, safely deinitializable moved-from value.
    static if (
        (needs_deinit!T || has_d_destructor!T)
        && !has_elaborate_destructor!T
        && !has_elaborate_copy_constructor!T
    )
    {
        emplace_initializer(source);
    }
}

/// Replaces a live explicit-deinit owner with `source`.
///
/// This intentionally applies only to destructor-free values that participate
/// in the explicit deinit protocol. Semantic resources outside that protocol,
/// such as a live Thread, cannot accidentally acquire generic replacement
/// semantics merely because their representation is structurally simple.
/// Both values must be live, and `T`'s deinitialization and move hooks must be
/// safe to invoke for their current states.
void move_assign(T)(ref T source, ref T target) @system
if (is(T == Unqual!T) && needs_deinit!T && !has_d_destructor!T)
{
    if (&source == &target)
        return;

    deinit(target);
    move_emplace(source, target);
}

unittest
{
    static struct DisabledDefaultOwner
    {
    nothrow @nogc:

        i32* deinits;
        bool active;

        @disable this();
        @disable this(this);

        this(i32* deinits)
        {
            this.deinits = deinits;
            this.active = true;
        }

        void deinit()
        {
            if (this.active)
            {
                ++*this.deinits;
                this.active = false;
            }
        }
    }

    i32 deinits;
    DisabledDefaultOwner source = DisabledDefaultOwner(&deinits);
    DisabledDefaultOwner target = move(source);
    assert(source == DisabledDefaultOwner.init);
    deinit(source);
    assert(deinits == 0);
    deinit(target);
    assert(deinits == 1);
}

unittest
{
    static struct ExplicitPODOwner
    {
    nothrow @nogc:

        i32* deinits;
        bool active;

        void deinit()
        {
            if (this.active)
            {
                ++*this.deinits;
                this.active = false;
            }
        }
    }

    static assert(__traits(isPOD, ExplicitPODOwner));
    static assert(__traits(isCopyable, ExplicitPODOwner));

    i32 deinits;
    ExplicitPODOwner source = ExplicitPODOwner(&deinits, true);
    ExplicitPODOwner target = void;
    move_emplace(source, target);
    assert(source == ExplicitPODOwner.init);
    deinit(source);
    assert(deinits == 0);
    deinit(target);
    assert(deinits == 1);

    ExplicitPODOwner returned_source = ExplicitPODOwner(&deinits, true);
    ExplicitPODOwner returned = move(returned_source);
    assert(returned_source == ExplicitPODOwner.init);
    deinit(returned_source);
    assert(deinits == 1);
    deinit(returned);
    assert(deinits == 2);

    ExplicitPODOwner replacement_source = ExplicitPODOwner(&deinits, true);
    ExplicitPODOwner replacement_target = ExplicitPODOwner(&deinits, true);
    move_assign(replacement_source, replacement_target);
    assert(replacement_source == ExplicitPODOwner.init);
    assert(deinits == 3);
    deinit(replacement_source);
    assert(deinits == 3);
    deinit(replacement_target);
    assert(deinits == 4);
}

unittest
{
    struct TrackedOwner
    {
    nothrow @nogc:

        i32 id;
        usize* count;
        i32* order;

        @disable this(this);

        void deinit()
        {
            this.order[(*this.count)++] = this.id;
        }
    }

    struct Aggregate
    {
        TrackedOwner first;
        i32* borrowed;
        TrackedOwner second;
    }

    struct Authoritative
    {
    nothrow @nogc:

        TrackedOwner nested;
        usize* member_calls;

        void deinit()
        {
            ++*this.member_calls;
        }
    }

    struct NamedDeinitField
    {
        i32 deinit;
        TrackedOwner owner;
    }

    struct StaticDeinitMember
    {
        TrackedOwner owner;

        static void deinit()
        {
        }
    }

    static assert(!needs_deinit!i32);
    static assert(!needs_deinit!(i32*));
    static assert(!needs_deinit!(i32[]));
    static assert(needs_deinit!TrackedOwner);
    static assert(needs_deinit!Aggregate);
    static assert(needs_deinit!NamedDeinitField);
    static assert(needs_deinit!StaticDeinitMember);
    static assert(needs_deinit!(TrackedOwner[2]));

    usize count;
    i32[8] order;
    Aggregate aggregate = Aggregate(
        TrackedOwner(1, &count, order.ptr),
        null,
        TrackedOwner(2, &count, order.ptr),
    );
    deinit(aggregate);
    assert(count == 2);
    assert(order[0] == 2);
    assert(order[1] == 1);

    usize member_calls;
    Authoritative authoritative = Authoritative(
        TrackedOwner(3, &count, order.ptr),
        &member_calls,
    );
    deinit(authoritative);
    assert(member_calls == 1);
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
    move_assign(source, target);
    assert(order[4] == 7);
    assert(source.id == TrackedOwner.init.id);
    assert(target.id == 6);
    deinit(target);
    assert(order[5] == 6);

    NamedDeinitField named_field = NamedDeinitField(
        42,
        TrackedOwner(8, &count, order.ptr),
    );
    deinit(named_field);
    assert(order[6] == 8);

    StaticDeinitMember static_member;
    static_member.owner = TrackedOwner(9, &count, order.ptr);
    deinit(static_member);
    assert(order[7] == 9);
}

unittest
{
    struct ContextOwner
    {
    nothrow @nogc:

        i32* calls;

        void deinit(i32* context)
        {
            ++*this.calls;
            ++*context;
        }
    }

    struct RefContextOwner
    {
    nothrow @nogc:

        i32* calls;

        void deinit(ref i32 context)
        {
            ++*this.calls;
            ++context;
        }
    }

    struct QualifiedOwner
    {
    nothrow @nogc:

        i32* mutable_calls;

        void deinit()
        {
            ++*this.mutable_calls;
        }

        void deinit() const
        {
        }
    }

    struct ConstOnlyOwner
    {
    nothrow @nogc:

        void deinit() const
        {
        }
    }

    union Untagged
    {
        ContextOwner owner;
        i32 value;
    }

    static assert(needs_deinit!ContextOwner);
    static assert(needs_finalization!ContextOwner);
    static assert(!can_finalize_without_context!ContextOwner);
    static assert(needs_deinit!Untagged);
    static assert(__traits(compiles, (ref ContextOwner value, i32* context)
    {
        deinit(value, context);
    }));
    static assert(!__traits(compiles, (ref ContextOwner value)
    {
        deinit(value);
    }));
    static assert(!__traits(compiles, (ref ContextOwner value)
    {
        finalize(value);
    }));
    static assert(!__traits(compiles, (ref const(ContextOwner) value, i32* context)
    {
        deinit(value, context);
    }));
    static assert(!__traits(compiles, (ref ContextOwner* pointer)
    {
        deinit(pointer);
    }));
    static assert(!__traits(compiles, (ref i32 value)
    {
        deinit(value);
    }));
    static assert(!__traits(compiles, (ref Untagged value)
    {
        deinit(value);
    }));
    static assert(__traits(compiles, (ref RefContextOwner value, ref i32 context)
    {
        deinit(value, context);
    }));
    static assert(!__traits(compiles, (ref RefContextOwner value)
    {
        deinit(value, 3);
    }));
    static assert(__traits(compiles, (ref QualifiedOwner value)
    {
        deinit(value);
    }));
    static assert(needs_deinit!ConstOnlyOwner);
    static assert(__traits(compiles, (ref ConstOnlyOwner value)
    {
        deinit(value);
    }));

    i32 calls;
    i32 context;
    ContextOwner owner = ContextOwner(&calls);
    deinit(owner, &context);
    assert(calls == 1);
    assert(context == 1);

    i32 ref_calls;
    i32 ref_context;
    RefContextOwner ref_owner = RefContextOwner(&ref_calls);
    deinit(ref_owner, ref_context);
    assert(ref_calls == 1);
    assert(ref_context == 1);

    i32 mutable_calls;
    QualifiedOwner qualified_owner = QualifiedOwner(&mutable_calls);
    deinit(qualified_owner);
    assert(mutable_calls == 1);

    ConstOnlyOwner const_only;
    deinit(const_only);
}

unittest
{
    struct DestructorOnly
    {
    nothrow @nogc:

        i32* destructions;
        bool armed;

        ~this()
        {
            if (this.armed)
            {
                ++*this.destructions;
                this.armed = false;
            }
        }
    }

    struct ContainsDestructorOnly
    {
        DestructorOnly value;
    }

    static assert(has_d_destructor!DestructorOnly);
    static assert(has_d_destructor!ContainsDestructorOnly);
    static assert(has_d_destructor!(DestructorOnly[2]));
    static assert(!needs_deinit!DestructorOnly);
    static assert(!needs_deinit!ContainsDestructorOnly);
    static assert(needs_finalization!DestructorOnly);
    static assert(can_finalize_without_context!DestructorOnly);
    static assert(!needs_finalization!i32);
    static assert(can_finalize_without_context!i32);
    static assert(__traits(compiles, (ref DestructorOnly value)
    {
        finalize(value);
    }));
    static assert(!__traits(compiles, (ref i32 value)
    {
        finalize(value);
    }));

    i32 destructions;
    DestructorOnly value = DestructorOnly(&destructions, true);
    finalize(value);
    assert(destructions == 1);
}

unittest
{
    struct TaggedOwner
    {
    nothrow @nogc:

        i32 id;
        usize* count;
        i32* order;

        @disable this(this);

        void deinit()
        {
            this.order[(*this.count)++] = this.id;
        }
    }

    enum FirstKind : u8
    {
        none,
        text,
    }

    union FirstPayload
    {
        TaggedOwner text;
    }

    enum SecondKind : u8
    {
        none,
        values,
    }

    union SecondPayload
    {
        @tagged_case(SecondKind.values)
        TaggedOwner differently_named;
    }

    struct Message
    {
        TaggedOwner name;

        FirstKind first_kind;
        @tagged_by("first_kind", FirstKind.none)
        FirstPayload first_payload;

        SecondKind second_kind;
        @tagged_by("second_kind", SecondKind.none)
        SecondPayload second_payload;
    }

    static assert(needs_deinit!Message);

    usize count;
    i32[8] order;
    Message message;
    message.name = TaggedOwner(1, &count, order.ptr);
    message.first_kind = FirstKind.text;
    message.first_payload.text = TaggedOwner(2, &count, order.ptr);
    message.second_kind = SecondKind.values;
    message.second_payload.differently_named = TaggedOwner(3, &count, order.ptr);

    deinit(message);
    assert(count == 3);
    assert(order[0] == 3);
    assert(order[1] == 2);
    assert(order[2] == 1);
    assert(message.first_kind == FirstKind.text);
    assert(message.second_kind == SecondKind.values);
    assert(message.first_payload.text.id == 2);
    assert(message.second_payload.differently_named.id == 3);

    struct Inactive
    {
        FirstKind kind;
        @tagged_by("kind", FirstKind.none)
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

    enum Kind : u8
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
        @tagged_by("missing", Kind.none)
        ValidPayload payload;
    }

    struct NonEnumDiscriminator
    {
        i32 kind;
        @tagged_by("kind", Kind.none)
        ValidPayload payload;
    }

    struct NonUnionPayload
    {
        Kind kind;
        @tagged_by("kind", Kind.none)
        Owner payload;
    }

    struct UnknownInactive
    {
        Kind kind;
        @tagged_by("kind", cast(Kind) 99)
        ValidPayload payload;
    }

    enum NonInactiveDefaultKind : u8
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
        @tagged_by("kind", NonInactiveDefaultKind.none)
        NonInactiveDefaultPayload payload;
    }

    union MissingCasePayload
    {
        Owner one;
    }

    struct MissingCase
    {
        Kind kind;
        @tagged_by("kind", Kind.none)
        MissingCasePayload payload;
    }

    union MissingNamePayload
    {
        Owner differently_named;
        Owner two;
    }

    struct MissingName
    {
        Kind kind;
        @tagged_by("kind", Kind.none)
        MissingNamePayload payload;
    }

    union DuplicateCasePayload
    {
        Owner one;
        @tagged_case(Kind.one)
        Owner duplicate;
        Owner two;
    }

    struct DuplicateCase
    {
        Kind kind;
        @tagged_by("kind", Kind.none)
        DuplicateCasePayload payload;
    }

    union InactiveCasePayload
    {
        @tagged_case(Kind.none)
        Owner inactive;
        Owner one;
        Owner two;
    }

    struct InactiveCase
    {
        Kind kind;
        @tagged_by("kind", Kind.none)
        InactiveCasePayload payload;
    }

    enum DuplicateValueKind : u8
    {
        none = 0,
        one = 1,
        two = 1,
    }

    union DuplicateValuePayload
    {
        Owner one;
        @tagged_case(DuplicateValueKind.two)
        Owner two;
    }

    struct DuplicateEnumValue
    {
        DuplicateValueKind kind;
        @tagged_by("kind", DuplicateValueKind.none)
        DuplicateValuePayload payload;
    }

    enum OtherKind : u8
    {
        value,
    }

    union WrongCaseTypePayload
    {
        @tagged_case(OtherKind.value)
        Owner one;
        Owner two;
    }

    struct WrongCaseType
    {
        Kind kind;
        @tagged_by("kind", Kind.none)
        WrongCaseTypePayload payload;
    }

    static assert(!__traits(compiles, needs_deinit!MissingDiscriminator));
    static assert(!__traits(compiles, needs_deinit!NonEnumDiscriminator));
    static assert(!__traits(compiles, needs_deinit!NonUnionPayload));
    static assert(!__traits(compiles, needs_deinit!UnknownInactive));
    static assert(!__traits(compiles, needs_deinit!NonInactiveDefault));
    static assert(!__traits(compiles, needs_deinit!MissingCase));
    static assert(!__traits(compiles, needs_deinit!MissingName));
    static assert(!__traits(compiles, needs_deinit!DuplicateCase));
    static assert(!__traits(compiles, needs_deinit!InactiveCase));
    static assert(!__traits(compiles, needs_deinit!DuplicateEnumValue));
    static assert(!__traits(compiles, needs_deinit!WrongCaseType));
}
