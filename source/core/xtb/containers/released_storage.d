module xtb.containers.released_storage;

nothrow @nogc:

import core.attribute;

import xtb.lifetime;
import xtb.memory;
import xtb.panic;
import xtb.types;

private template ReleasedFunctionType(alias operation)
{
    static if (is(typeof(&operation) F : F*) && is(F == function))
    {
        alias ReleasedFunctionType = F;
    }
    else static if (is(typeof(operation) F == function))
    {
        alias ReleasedFunctionType = F;
    }
    else
    {
        static assert(false, "ReleasedStorage expected a concrete function declaration");
    }
}

private template ReleasedParameters(alias operation)
{
    static if (is(ReleasedFunctionType!operation P == function))
    {
        alias ReleasedParameters = P;
    }
}

private template ReleasedReturnType(alias operation)
{
    static if (is(ReleasedFunctionType!operation R == return))
    {
        alias ReleasedReturnType = R;
    }
}

private usize public_deinit_count(Storage)()
{
    usize result;
    static foreach (alias operation; __traits(getOverloads, Storage, "deinit"))
    {
        static if (__traits(getProtection, operation) == "public")
        {
            ++result;
        }
    }
    return result;
}

/// Move-only explicit owner used while transferring allocator-bound unmanaged
/// storage out of a managed container. Call free `deinit` if ownership is not
/// transferred onward with `extract`/adopt.
@mustuse struct ReleasedStorage(Storage)
{
nothrow @nogc:

    /// Allocator associated with `storage`, or null when ownership was extracted.
    Allocator* allocator;

    /// Unmanaged storage owned by this token until extracted or deinitialized.
    Storage storage;

    static assert(
        !__traits(isCopyable, Storage),
        "ReleasedStorage requires non-copyable unmanaged storage",
    );
    static assert(
        !has_d_destructor!Storage,
        "ReleasedStorage storage must not have an elaborate destructor",
    );
    static if (__traits(hasMember, Storage, "deinit"))
    {
        static assert(
            public_deinit_count!Storage() == 1,
            "ReleasedStorage requires Storage.deinit(Allocator*): "
                ~ "exactly one public overload is required",
        );
        static foreach (alias operation; __traits(getOverloads, Storage, "deinit"))
        {
            static if (__traits(getProtection, operation) == "public")
            {
                static assert(
                    !__traits(isStaticFunction, operation),
                    "ReleasedStorage requires instance Storage.deinit(Allocator*)",
                );
                static assert(
                    is(ReleasedReturnType!operation == void),
                    Storage.stringof ~ ".deinit must return void",
                );
                static assert(
                    ReleasedParameters!operation.length == 1,
                    Storage.stringof ~ ".deinit must take exactly one Allocator* parameter",
                );
                static if (ReleasedParameters!operation.length == 1)
                {
                    static assert(
                        is(ReleasedParameters!operation[0] == Allocator*),
                        Storage.stringof ~ ".deinit must take exactly one Allocator* parameter",
                    );
                }
            }
        }
    }
    else
    {
        static assert(false, "unmanaged storage must provide deinit");
    }

    @disable this(this);
    @disable ref ReleasedStorage opAssign(ReleasedStorage source) return;

    /// Explicitly releases the owned allocator/storage pair.
    void deinit() @trusted
    {
        if (this.allocator !is null)
        {
            this.storage.deinit(this.allocator);
        }
    }

    /// Permanently extracts the allocator/storage pair and empties this token.
    /// `allocator_output` must not be null.
    Storage extract(scope Allocator** allocator_output) scope @trusted
    {
        require(
            allocator_output !is null,
            "ReleasedStorage allocator output pointer is null",
        );
        *allocator_output = this.allocator;
        this.allocator = null;
        return take_storage(&this.storage);
    }

    package(xtb) static ReleasedStorage from_owned_parts(
        Allocator* allocator,
        scope Storage* storage,
    ) @trusted
    {
        require(storage !is null, "ReleasedStorage storage pointer is null");

        ReleasedStorage result;
        result.allocator = allocator;
        move_emplace(*storage, result.storage);
        return move(result);
    }

    private static Storage take_storage(Storage* source) @system
    {
        return move(*source);
    }
}
