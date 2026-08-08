module xtb.core.internal.managed_container_adapter;

nothrow @nogc:

import core.lifetime : move;
import xtb.core.memory : Allocator;
import xtb.core.panic : require;
import xtb.core.released_storage : ReleasedStorage;

package(xtb):

template AdapterFunctionType(alias operation)
{
    static if (is(typeof(&operation) F : F*) && is(F == function))
        alias AdapterFunctionType = F;
    else static if (is(typeof(operation) F == function))
        alias AdapterFunctionType = F;
    else
        static assert(false,
            "managed adapter expected a concrete function declaration");
}

template AdapterParameters(alias operation)
{
    static if (is(AdapterFunctionType!operation P == function))
        alias AdapterParameters = P;
}

template AdapterReturnType(alias operation)
{
    static if (is(AdapterFunctionType!operation R == return))
        alias AdapterReturnType = R;
}

template AdapterParameterTuple(alias operation)
{
    static if (is(AdapterFunctionType!operation P == __parameters))
        alias AdapterParameterTuple = P;
}

template decimalString(size_t value)
{
    static if (value < 10)
        enum decimalString = "0123456789"[value .. value + 1];
    else
        enum decimalString = decimalString!(value / 10) ~
            decimalString!(value % 10);
}

private bool attributePresent(alias operation, string sought)()
{
    static foreach (attribute; __traits(getFunctionAttributes, operation))
        static if (attribute == sought)
            return true;
    return false;
}

private string returnPrefix(alias operation)()
{
    return attributePresent!(operation, "ref") ? "ref " : "";
}

private string functionSuffix(alias operation)()
{
    string result;
    static foreach (wanted; [
        "shared", "const", "immutable", "inout",
        "return", "scope", "pure", "nothrow", "@nogc",
        "@safe", "@trusted", "@system", "@property", "@live",
    ])
    {
        static if (attributePresent!(operation, wanted))
            result ~= " " ~ wanted;
    }
    return result;
}

private string conservativeFactorySuffix(alias operation)()
{
    string result;
    static foreach (wanted; ["nothrow", "@nogc", "@safe", "@trusted", "@system"])
    {
        static if (attributePresent!(operation, wanted))
            result ~= " " ~ wanted;
    }
    return result;
}

private string parameterStorageSource(alias operation, size_t index)()
{
    string result;
    static foreach (storageClass;
        __traits(getParameterStorageClasses, operation, index))
    {
        result ~= storageClass ~ " ";
    }
    return result;
}

private bool hasParameterStorageClass(
    alias operation,
    size_t index,
    string sought,
)()
{
    static foreach (storageClass;
        __traits(getParameterStorageClasses, operation, index))
    {
        static if (storageClass == sought)
            return true;
    }
    return false;
}

private bool hasRefLikeStorage(alias operation, size_t index)()
{
    return hasParameterStorageClass!(operation, index, "ref") ||
        hasParameterStorageClass!(operation, index, "out") ||
        hasParameterStorageClass!(operation, index, "lazy") ||
        hasParameterStorageClass!(operation, index, "return");
}

private bool hasDefaultArgument(alias operation, size_t index)()
{
    alias P = AdapterParameterTuple!operation;
    enum callable = mixin("(P[index .. index + 1] argument) => true");
    return __traits(compiles, callable());
}

private bool isMutableStruct(T)()
{
    return is(T == struct);
}

private bool isStorageValueParameter(Storage, T)()
{
    return is(T == Storage) || is(T == const(Storage)) ||
        is(T == immutable(Storage)) || is(T == inout(Storage));
}

private bool isStorageRelatedType(Storage, T)()
{
    return isStorageValueParameter!(Storage, T) ||
        is(T == Storage*) || is(T == const(Storage)*) ||
        is(T == immutable(Storage)*) || is(T == inout(Storage)*);
}

private bool hasStorageRelatedParameter(Storage, alias operation)()
{
    static foreach (P; AdapterParameters!operation)
    {
        static if (isStorageRelatedType!(Storage, P))
            return true;
    }
    return false;
}

private string managedParameterTypeSource(
    Storage,
    alias operation,
    string operationAlias,
    size_t index,
)()
{
    alias P = AdapterParameters!operation[index];
    static if (is(P == Storage))
        return "Self";
    else static if (is(P == const(Storage)))
        return "const(Self)";
    else static if (is(P == immutable(Storage)))
        return "immutable(Self)";
    else static if (is(P == inout(Storage)))
        return "inout(Self)";
    else
        return "AdapterParameters!(" ~ operationAlias ~ ")[" ~
            decimalString!index ~ "]";
}

private string argumentSourceForManaged(
    Storage,
    alias operation,
    size_t index,
)()
{
    alias P = AdapterParameters!operation[index];
    enum name = "argument" ~ decimalString!index;
    static if (isStorageValueParameter!(Storage, P))
        return name ~ ".storage_";
    else
        return argumentSource!(operation, index)();
}

private string argumentSource(alias operation, size_t index)()
{
    alias P = AdapterParameters!operation[index];
    enum name = "argument" ~ decimalString!index;
    static if (hasRefLikeStorage!(operation, index))
        return name;
    else static if (isMutableStruct!P)
        return "move(" ~ name ~ ")";
    else
        return name;
}

private size_t allocatorParameterCount(alias operation)()
{
    size_t result;
    static foreach (P; AdapterParameters!operation)
        static if (is(P == Allocator*))
            ++result;
    return result;
}

private size_t allocatorParameterIndex(alias operation)()
{
    size_t result = size_t.max;
    static foreach (index, P; AdapterParameters!operation)
        static if (is(P == Allocator*))
            result = index;
    return result;
}

private size_t storageOutputParameterCount(Storage, alias operation)()
{
    size_t result;
    static foreach (P; AdapterParameters!operation)
        static if (is(P == Storage*))
            ++result;
    return result;
}

private size_t storageOutputParameterIndex(Storage, alias operation)()
{
    size_t result = size_t.max;
    static foreach (index, P; AdapterParameters!operation)
        static if (is(P == Storage*))
            result = index;
    return result;
}

private void validateCommonOperation(
    Storage,
    alias operation,
    string operationName,
)()
{
    static assert(__traits(getLinkage, operation) == "D",
        Storage.stringof ~ "." ~ operationName ~
            " must use D linkage for managed adaptation");
    static assert(allocatorParameterCount!operation <= 1,
        Storage.stringof ~ "." ~ operationName ~
            " has more than one Allocator* parameter");
    static foreach (index, P; AdapterParameters!operation)
    {
        static assert(!hasDefaultArgument!(operation, index),
            Storage.stringof ~ "." ~ operationName ~
                " uses a default argument, which the managed adapter cannot reproduce");
    }
}

private string ordinaryOperationSource(
    Managed,
    Storage,
    alias operation,
    string operationName,
    string operationAlias,
)()
{
    validateCommonOperation!(Storage, operation, operationName)();
    static assert(!__traits(isStaticFunction, operation));

    enum allocatorIndex = allocatorParameterIndex!operation;
    string source = returnPrefix!operation();
    source ~= "AdapterReturnType!(" ~ operationAlias ~ ") " ~ operationName ~ "(";

    bool first = true;
    static foreach (index, P; AdapterParameters!operation)
    {
        static if (index != allocatorIndex)
        {
            if (!first)
                source ~= ", ";
            first = false;
            source ~= parameterStorageSource!(operation, index)();
            source ~= managedParameterTypeSource!(
                Storage, operation, operationAlias, index)();
            source ~= " argument" ~ decimalString!index;
        }
    }
    source ~= ")" ~ functionSuffix!operation() ~ " { ";

    static if (is(AdapterReturnType!operation == void))
        source ~= "storage_." ~ operationName ~ "(";
    else
        source ~= "return storage_." ~ operationName ~ "(";

    first = true;
    static foreach (index, P; AdapterParameters!operation)
    {
        if (!first)
            source ~= ", ";
        first = false;
        static if (index == allocatorIndex)
            source ~= "allocator_";
        else
            source ~= argumentSourceForManaged!(Storage, operation, index)();
    }
    source ~= "); }";
    return source;
}

private string staticUtilitySource(
    Managed,
    Storage,
    alias operation,
    string operationName,
    string operationAlias,
)()
{
    validateCommonOperation!(Storage, operation, operationName)();
    static assert(__traits(isStaticFunction, operation));
    static assert(!isStorageRelatedType!(
            Storage, AdapterReturnType!operation),
        Storage.stringof ~ "." ~ operationName ~
            " has a storage-related return type");
    static assert(!hasStorageRelatedParameter!(Storage, operation),
        Storage.stringof ~ "." ~ operationName ~
            " has a storage-related parameter");

    string source = "static " ~ returnPrefix!operation();
    source ~= "AdapterReturnType!(" ~ operationAlias ~ ") " ~
        operationName ~ "(";
    bool first = true;
    static foreach (index, P; AdapterParameters!operation)
    {
        if (!first)
            source ~= ", ";
        first = false;
        source ~= parameterStorageSource!(operation, index)();
        source ~= "AdapterParameters!(" ~ operationAlias ~ ")[" ~
            decimalString!index ~ "] argument" ~ decimalString!index;
    }
    source ~= ")" ~ functionSuffix!operation() ~ " { ";
    static if (is(AdapterReturnType!operation == void))
        source ~= "Storage." ~ operationName ~ "(";
    else
        source ~= "return Storage." ~ operationName ~ "(";
    first = true;
    static foreach (index, P; AdapterParameters!operation)
    {
        if (!first)
            source ~= ", ";
        first = false;
        source ~= argumentSource!(operation, index)();
    }
    source ~= "); }";
    return source;
}

private string fallibleFactorySource(
    Managed,
    Storage,
    alias operation,
    string operationName,
    string operationAlias,
)()
{
    validateCommonOperation!(Storage, operation, operationName)();
    enum outputCount = storageOutputParameterCount!(Storage, operation);
    static assert(outputCount == 1,
        Storage.stringof ~ "." ~ operationName ~
            " must have exactly one Storage* output");
    enum outputIndex = storageOutputParameterIndex!(Storage, operation);
    static assert(hasParameterStorageClass!(operation, outputIndex, "scope"),
        Storage.stringof ~ "." ~ operationName ~
            " Storage* output must be scope");
    enum allocatorIndex = allocatorParameterIndex!operation;
    static assert(allocatorIndex != size_t.max);

    string source = "static bool " ~ operationName ~ "(";
    bool first = true;
    static foreach (index, P; AdapterParameters!operation)
    {
        if (!first)
            source ~= ", ";
        first = false;
        source ~= parameterStorageSource!(operation, index)();
        static if (index == outputIndex)
            source ~= "Self* argument" ~ decimalString!index;
        else
            source ~= "AdapterParameters!(" ~ operationAlias ~ ")[" ~
                decimalString!index ~ "] argument" ~ decimalString!index;
    }
    source ~= ")" ~ functionSuffix!operation() ~ " { ";
    source ~= "require(argument" ~ decimalString!outputIndex ~
        " !is null, \"managed container output pointer is null\"); ";
    source ~= "require(argument" ~ decimalString!outputIndex ~
        ".allocator_ is null, \"managed container output is already initialized\"); ";
    source ~= "Storage temporary; ";
    source ~= "const success = (() @trusted nothrow @nogc { return Storage." ~
        operationName ~ "(";

    first = true;
    static foreach (index, P; AdapterParameters!operation)
    {
        if (!first)
            source ~= ", ";
        first = false;
        static if (index == outputIndex)
            source ~= "&temporary";
        else
            source ~= argumentSource!(operation, index)();
    }
    source ~= "); })(); ";
    source ~= "if (!success) return false; ";
    source ~= "argument" ~ decimalString!outputIndex ~
        ".storage_ = move(temporary); ";
    source ~= "argument" ~ decimalString!outputIndex ~
        ".allocator_ = argument" ~ decimalString!allocatorIndex ~ "; ";
    source ~= "return true; }";
    return source;
}

private string returningFactorySource(
    Managed,
    Storage,
    alias operation,
    string operationName,
    string operationAlias,
)()
{
    validateCommonOperation!(Storage, operation, operationName)();
    enum allocatorCount = allocatorParameterCount!operation;
    static assert(allocatorCount <= 1);

    string source = "static Self " ~ operationName ~ "(";
    bool first = true;
    static if (allocatorCount == 0)
    {
        source ~= "Allocator* managedAllocator";
        first = false;
    }
    static foreach (index, P; AdapterParameters!operation)
    {
        if (!first)
            source ~= ", ";
        first = false;
        source ~= parameterStorageSource!(operation, index)();
        source ~= "AdapterParameters!(" ~ operationAlias ~ ")[" ~
            decimalString!index ~ "] argument" ~ decimalString!index;
    }
    source ~= ")" ~ conservativeFactorySuffix!operation() ~ " { ";
    static if (allocatorCount == 0)
        source ~= "require(managedAllocator !is null && *managedAllocator !is null, " ~
            "\"managed container allocator is null\"); ";
    source ~= "Self result; result.storage_ = Storage." ~ operationName ~ "(";

    first = true;
    static foreach (index, P; AdapterParameters!operation)
    {
        if (!first)
            source ~= ", ";
        first = false;
        source ~= argumentSource!(operation, index)();
    }
    source ~= "); ";
    static if (allocatorCount == 0)
        source ~= "result.allocator_ = managedAllocator; ";
    else
    {
        enum allocatorIndex = allocatorParameterIndex!operation;
        source ~= "result.allocator_ = argument" ~ decimalString!allocatorIndex ~ "; ";
    }
    source ~= "return result; }";
    return source;
}

size_t publicConcreteOperationCount(
    Storage,
    string operationName,
)()
{
    size_t result;
    static foreach (alias operation;
        __traits(getOverloads, Storage, operationName))
    {
        static if (__traits(getProtection, operation) == "public")
            ++result;
    }
    return result;
}

bool validateLifecycleOperation(
    Storage,
    alias operation,
    string operationName,
)()
{
    validateCommonOperation!(Storage, operation, operationName)();
    static assert(!__traits(isStaticFunction, operation),
        Storage.stringof ~ "." ~ operationName ~
            " must be an instance operation");
    static assert(is(AdapterReturnType!operation == void),
        Storage.stringof ~ "." ~ operationName ~
            " must return void");
    static assert(AdapterParameters!operation.length == 1,
        Storage.stringof ~ "." ~ operationName ~
            " must take exactly one Allocator* parameter");
    static if (AdapterParameters!operation.length == 1)
    {
        static assert(is(AdapterParameters!operation[0] == Allocator*),
            Storage.stringof ~ "." ~ operationName ~
                " must take exactly one Allocator* parameter");
    }
    return true;
}

string generateManagedOperation(
    Managed,
    Storage,
    alias operation,
    string operationName,
    string operationAlias,
)()
{
    enum isStatic = __traits(isStaticFunction, operation);
    enum allocatorCount = allocatorParameterCount!operation;
    enum outputCount = storageOutputParameterCount!(Storage, operation);

    static if (operationName == "create")
        static assert(false,
            Storage.stringof ~ ".create conflicts with generated managed create");
    else static if (operationName == "deinit" ||
            operationName == "resetAndRelease")
        return "";
    else static if (isStatic && is(AdapterReturnType!operation == bool) &&
            allocatorCount == 1 && outputCount == 1)
        return fallibleFactorySource!(Managed, Storage, operation,
            operationName, operationAlias)();
    else static if (isStatic && is(AdapterReturnType!operation == Storage) &&
            outputCount == 0 && allocatorCount <= 1)
        return returningFactorySource!(Managed, Storage, operation,
            operationName, operationAlias)();
    else static if (!isStatic)
        return ordinaryOperationSource!(Managed, Storage, operation,
            operationName, operationAlias)();
    else static if (!isStorageRelatedType!(
                Storage, AdapterReturnType!operation) &&
            !hasStorageRelatedParameter!(Storage, operation))
        return staticUtilitySource!(Managed, Storage, operation,
            operationName, operationAlias)();
    else
        static assert(false,
            "unsupported public static unmanaged operation: " ~
                Storage.stringof ~ "." ~ operationName);
}

mixin template ManagedContainerAdapter(Managed, Storage)
{
    import core.internal.traits : hasElaborateDestructor;
    import core.lifetime : move;
    import xtb.core.internal.managed_container_adapter :
        AdapterParameters,
        AdapterReturnType,
        decimalString,
        generateManagedOperation,
        publicConcreteOperationCount,
        validateLifecycleOperation;
    import xtb.core.memory : Allocator;
    import xtb.core.panic : require;
    import xtb.core.released_storage : ReleasedStorage;

    static assert(is(Managed == Self),
        "ManagedContainerAdapter requires alias Self");
    static assert(is(Storage == typeof(storage_)),
        "ManagedContainerAdapter requires a Storage storage_ field");
    static assert(is(typeof(allocator_) == Allocator*),
        "ManagedContainerAdapter requires an Allocator* allocator_ field");
    static assert(!__traits(isCopyable, Storage),
        "unmanaged storage must be non-copyable");
    static assert(!hasElaborateDestructor!Storage,
        "unmanaged storage must not have an elaborate destructor");

    static foreach (lifecycleName; ["deinit", "resetAndRelease"])
    {
        static if (__traits(hasMember, Storage, lifecycleName))
        {
            static assert(publicConcreteOperationCount!(
                    Storage, lifecycleName)() == 1,
                Storage.stringof ~ "." ~ lifecycleName ~
                    " must have exactly one public concrete overload");
            static foreach (alias lifecycleOperation;
                __traits(getOverloads, Storage, lifecycleName))
            {
                static if (__traits(getProtection, lifecycleOperation) ==
                        "public")
                {
                    static assert(validateLifecycleOperation!(
                        Storage,
                        lifecycleOperation,
                        lifecycleName,
                    )());
                }
            }
        }
        else
            static assert(false,
                "unmanaged storage must provide " ~ lifecycleName);
    }

    alias Released = ReleasedStorage!Storage;

    @disable this(this);

    static Self create(Allocator* allocator) @safe nothrow @nogc
    {
        require(allocator !is null && *allocator !is null,
            "managed container allocator is null");
        Self result;
        result.allocator_ = allocator;
        return result;
    }

    ~this() @trusted nothrow @nogc
    {
        deinit();
    }

    void deinit() @trusted nothrow @nogc
    {
        if (allocator_ is null)
            return;
        storage_.deinit(allocator_);
        allocator_ = null;
    }

    void resetAndRelease() @trusted nothrow @nogc
    {
        storage_.resetAndRelease(allocator_);
    }

    Allocator* allocator() return @safe nothrow @nogc
    {
        return allocator_;
    }

    Released release() scope @trusted nothrow @nogc
    {
        Released result = Released.fromOwnedParts(allocator_, &storage_);
        allocator_ = null;
        return move(result);
    }

    static Self adopt(scope Released* released) @trusted nothrow @nogc
    {
        require(released !is null,
            "released storage pointer is null");
        Allocator* allocator;
        Storage storage = released.extract(&allocator);
        Self result;
        result.allocator_ = allocator;
        result.storage_ = move(storage);
        return move(result);
    }

    static foreach (memberIndex, memberName; __traits(allMembers, Storage))
    {
        static if ((memberName.length < 2 || memberName[0 .. 2] != "__") &&
                memberName != "opAssign" && memberName != "this" &&
                memberName != "~this" && memberName != "deinit" &&
                memberName != "resetAndRelease")
        {
            static if (__traits(compiles,
                __traits(getMember, Storage, memberName)) &&
                __traits(isTemplate, __traits(getMember, Storage, memberName)))
            {
                static assert(__traits(getProtection,
                        __traits(getMember, Storage, memberName)) != "public",
                    "public unmanaged member templates cannot be managed automatically: " ~
                        Storage.stringof ~ "." ~ memberName);
            }
            else static if (__traits(compiles,
                __traits(getOverloads, Storage, memberName)))
            {
                static foreach (overloadIndex, alias operation;
                    __traits(getOverloads, Storage, memberName))
                {
                    static if (__traits(getProtection, operation) == "public")
                    {
                        mixin("private alias __managedOperation_" ~
                            decimalString!memberIndex ~ "_" ~
                            decimalString!overloadIndex ~ " = operation;");
                        mixin(generateManagedOperation!(
                            Managed,
                            Storage,
                            operation,
                            memberName,
                            "__managedOperation_" ~ decimalString!memberIndex ~
                                "_" ~ decimalString!overloadIndex,
                        ));
                    }
                }
            }
        }
    }
}

version (unittest)
{
    private struct AdapterMoveOnly
    {
        int value;
        @disable this(this);
    }

    private struct AdapterFixtureStorage
    {
    nothrow @nogc:

    private:
        int value_;

    public:
        @disable this(this);

        static bool tryBuild(
            int value,
            Allocator* allocator,
            scope AdapterFixtureStorage* output,
        ) @safe
        {
            require(allocator !is null && *allocator !is null,
                "fixture allocator is null");
            require(output !is null && output.value_ == 0,
                "fixture output is not empty");
            output.value_ = value;
            return true;
        }

        static int staticUtility(int value) pure @safe
        {
            return value + 7;
        }

        static AdapterFixtureStorage configured(int value) @safe
        {
            AdapterFixtureStorage result;
            result.value_ = value;
            return move(result);
        }

        static AdapterFixtureStorage builtWithAllocator(
            Allocator* allocator,
            int value,
        ) @safe
        {
            require(allocator !is null && *allocator !is null,
                "fixture allocator is null");
            AdapterFixtureStorage result;
            result.value_ = value;
            return move(result);
        }

        void deinit(Allocator*) @safe
        {
            this = AdapterFixtureStorage.init;
        }

        void resetAndRelease(Allocator*) @safe
        {
            value_ = 0;
        }

        bool add(int amount, Allocator* allocator) @safe
        {
            require(allocator !is null && *allocator !is null,
                "fixture allocator is null");
            value_ += amount;
            return true;
        }

        bool addFirst(Allocator* allocator, int amount) @safe
        {
            require(allocator !is null && *allocator !is null,
                "fixture allocator is null");
            value_ += amount;
            return true;
        }

        void addMiddle(int left, Allocator* allocator, int right) @safe
        {
            require(allocator !is null && *allocator !is null,
                "fixture allocator is null");
            value_ += left + right;
        }

        void parameterClasses(
            Allocator* allocator,
            scope const(int)* input,
            ref int updated,
            out int written,
        ) @safe
        {
            require(allocator !is null && *allocator !is null,
                "fixture allocator is null");
            require(input !is null, "fixture input is null");
            updated += *input;
            written = value_;
        }

        int transformed(int amount) const pure @safe
        {
            return value_ + amount;
        }

        long transformed(long amount) const pure @safe
        {
            return cast(long) value_ + amount;
        }

        void consume(AdapterMoveOnly value, Allocator* allocator) @safe
        {
            require(allocator !is null && *allocator !is null,
                "fixture allocator is null");
            value_ += value.value;
        }

        ref int current() return @safe
        {
            return value_;
        }

        ref const(int) current() const return @safe
        {
            return value_;
        }

        bool opEquals(scope ref const AdapterFixtureStorage other) const
            pure @safe
        {
            return value_ == other.value_;
        }
    }

    private struct AdapterFixture
    {
    nothrow @nogc:

        alias Self = AdapterFixture;
        alias Storage = AdapterFixtureStorage;

    private:
        Allocator* allocator_;
        Storage storage_;

    public:
        mixin ManagedContainerAdapter!(Self, Storage);
    }
}

unittest
{
    import xtb.core.allocators.malloc : mallocAllocator;

    assert(AdapterFixture.staticUtility(5) == 12);

    AdapterFixture built;
    assert(AdapterFixture.tryBuild(4, mallocAllocator(), &built));
    assert(built.allocator is mallocAllocator());
    assert(built.current == 4);
    assert(built.add(3));
    assert(built.addFirst(2));
    built.addMiddle(1, 2);
    assert(built.current == 12);

    int input = 4;
    int updated = 6;
    int written = -1;
    built.parameterClasses(&input, updated, written);
    assert(updated == 10 && written == 12);
    assert(built.transformed(3) == 15);
    assert(built.transformed(cast(long) 4) == 16L);

    AdapterMoveOnly value;
    value.value = 5;
    built.consume(move(value));
    assert(built.current == 17);

    AdapterFixture configured = AdapterFixture.configured(
        mallocAllocator(),
        17,
    );
    assert(configured == built);

    const(AdapterFixture)* readOnly = &configured;
    static assert(is(typeof((*readOnly).current()) == const(int)));
    assert((*readOnly).current == 17);

    AdapterFixture allocated = AdapterFixture.builtWithAllocator(
        mallocAllocator(),
        9,
    );
    assert(allocated.allocator is mallocAllocator());
    assert(allocated.current == 9);

    built.resetAndRelease();
    assert(built.allocator is mallocAllocator());
    assert(built.current == 0);
    built.deinit();
    assert(built.allocator is null);

    configured.current = 20;
    assert(configured.current == 20);
}

unittest
{
    static foreach (alias operation;
        __traits(getOverloads, AdapterFixture, "addFirst"))
    {
        alias AddFirstParameters = AdapterParameters!operation;
        static assert(AddFirstParameters.length == 1);
        static assert(is(AddFirstParameters[0] == int));
    }

    static foreach (alias operation;
        __traits(getOverloads, AdapterFixture, "parameterClasses"))
    {
        alias ClassParameters = AdapterParameters!operation;
        static assert(ClassParameters.length == 3);
        static assert(is(ClassParameters[0] == const(int)*));
        static assert(is(ClassParameters[1] == int));
        static assert(is(ClassParameters[2] == int));
        static assert(hasParameterStorageClass!(operation, 0, "scope"));
        static assert(hasParameterStorageClass!(operation, 1, "ref"));
        static assert(hasParameterStorageClass!(operation, 2, "out"));
    }

    static foreach (alias operation;
        __traits(getOverloads, AdapterFixture, "tryBuild"))
    {
        alias BuildParameters = AdapterParameters!operation;
        static assert(BuildParameters.length == 3);
        static assert(is(BuildParameters[0] == int));
        static assert(is(BuildParameters[1] == Allocator*));
        static assert(is(BuildParameters[2] == AdapterFixture*));
        static assert(hasParameterStorageClass!(operation, 2, "scope"));
    }

    static foreach (alias operation;
        __traits(getOverloads, AdapterFixture, "release"))
    {
        static assert(is(AdapterReturnType!operation == AdapterFixture.Released));
        static assert(AdapterParameters!operation.length == 0);
    }

    static foreach (alias operation;
        __traits(getOverloads, AdapterFixture, "adopt"))
    {
        alias AdoptParameters = AdapterParameters!operation;
        static assert(AdoptParameters.length == 1);
        static assert(is(AdoptParameters[0] == AdapterFixture.Released*));
        static assert(hasParameterStorageClass!(operation, 0, "scope"));
    }

    static assert(!__traits(compiles,
        (ref AdapterFixture value, Allocator* allocator) {
            value.addFirst(allocator, 1);
        }));
}
