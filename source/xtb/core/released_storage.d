module xtb.core.released_storage;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.lifetime : move;
import xtb.core.memory : Allocator;

version (XTB_Checked) import xtb.core.panic : require;

private template ReleasedFunctionType(alias operation)
{
    static if (is(typeof(&operation) F : F*) && is(F == function))
        alias ReleasedFunctionType = F;
    else static if (is(typeof(operation) F == function))
        alias ReleasedFunctionType = F;
    else
        static assert(false,
            "ReleasedStorage expected a concrete function declaration");
}

private template ReleasedParameters(alias operation)
{
    static if (is(ReleasedFunctionType!operation P == function))
        alias ReleasedParameters = P;
}

private template ReleasedReturnType(alias operation)
{
    static if (is(ReleasedFunctionType!operation R == return))
        alias ReleasedReturnType = R;
}

private size_t publicDeinitCount(Storage)()
{
    size_t result;
    static foreach (alias operation; __traits(getOverloads, Storage, "deinit"))
    {
        static if (__traits(getProtection, operation) == "public")
            ++result;
    }
    return result;
}

/// Move-only RAII owner used while transferring allocator-bound unmanaged
/// storage out of a managed container.
struct ReleasedStorage(Storage)
{
nothrow @nogc:

private:
    Allocator* allocator_;
    Storage storage_;

    static Storage takeStorage(Storage* source) @system
    {
        return move(*source);
    }

public:
    static assert(!__traits(isCopyable, Storage),
        "ReleasedStorage requires non-copyable unmanaged storage");
    static assert(!hasElaborateDestructor!Storage,
        "ReleasedStorage storage must not have an elaborate destructor");
    static if (__traits(hasMember, Storage, "deinit"))
    {
        static assert(publicDeinitCount!Storage() == 1,
            "ReleasedStorage requires Storage.deinit(Allocator*): " ~
                "exactly one public overload is required");
        static foreach (alias operation; __traits(getOverloads, Storage, "deinit"))
        {
            static if (__traits(getProtection, operation) == "public")
            {
                static assert(!__traits(isStaticFunction, operation),
                    "ReleasedStorage requires instance " ~
                        "Storage.deinit(Allocator*)");
                static assert(is(ReleasedReturnType!operation == void),
                    Storage.stringof ~ ".deinit must return void");
                static assert(ReleasedParameters!operation.length == 1,
                    Storage.stringof ~ ".deinit must take exactly one " ~
                        "Allocator* parameter");
                static if (ReleasedParameters!operation.length == 1)
                {
                    static assert(is(ReleasedParameters!operation[0] ==
                            Allocator*),
                        Storage.stringof ~ ".deinit must take exactly one " ~
                            "Allocator* parameter");
                }
            }
        }
    }
    else
        static assert(false,
            "unmanaged storage must provide deinit");

    @disable this(this);

    ~this() @trusted
    {
        if (allocator_ !is null)
            storage_.deinit(allocator_);
        allocator_ = null;
    }

    /// Returns the exact allocator associated with the owned storage.
    Allocator* allocator() return @safe
    {
        return allocator_;
    }

    /// Borrows the unmanaged storage for read-only inspection.
    ref const(Storage) storage() const return @safe
    {
        return storage_;
    }

    /// Borrows the unmanaged storage mutably.
    ///
    /// The caller must preserve the allocator/storage association and must not
    /// move or replace the storage while this token remains its owner.
    ref Storage storage() return @system
    {
        return storage_;
    }

    /// Permanently extracts the allocator/storage pair and empties this token.
    Storage extract(scope Allocator** allocatorOutput) scope @trusted
    {
        version (XTB_Checked)
            require(allocatorOutput !is null,
                "ReleasedStorage allocator output pointer is null");
        *allocatorOutput = allocator_;
        allocator_ = null;
        return takeStorage(&storage_);
    }

package(xtb):
    static ReleasedStorage fromOwnedParts(
        Allocator* allocator,
        scope Storage* storage,
    ) @trusted
    {
        version (XTB_Checked)
            require(storage !is null,
                "ReleasedStorage storage pointer is null");
        ReleasedStorage result;
        result.allocator_ = allocator;
        result.storage_ = takeStorage(storage);
        return move(result);
    }
}
