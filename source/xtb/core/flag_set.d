/**
 * Strongly typed, allocation-free sets of enum flags.
 *
 * Enum values are bit positions, not pre-shifted masks. Consequently an
 * ordinary sequential enum gives each member its own bit:
 *
 * ---
 * enum Permission
 * {
 *     read,
 *     write,
 *     execute,
 *     administer = 7,
 * }
 *
 * alias Permissions = FlagSet!Permission;
 * auto permissions = Permissions.of(Permission.read, Permission.write);
 * permissions.enable(Permission.execute);
 * ---
 *
 * Every declared position must be non-negative and unique. The default
 * storage is the smallest of `ubyte`, `ushort`, `uint`, and `ulong` that fits
 * the highest declared position. Specify `Storage` explicitly when its size
 * is part of an ABI or serialized representation.
 */
module xtb.core.flag_set;

nothrow @nogc:

version (XTB_Checked) import xtb.core.panic : require;

private template EnumBaseType(E)
{
    static if (is(E Base == enum))
        alias EnumBaseType = Base;
    else
        static assert(false, "FlagSet requires an enum, not " ~ E.stringof);
}

private enum bool isStorageType(T) =
    is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong);

private template declaredPosition(Base, alias member)
{
    static if (__traits(isUnsigned, Base))
    {
        enum ulong declaredPosition = cast(ulong) member;
    }
    else
    {
        static assert(cast(long) member >= 0,
            "FlagSet positions must not be negative");
        enum ulong declaredPosition = cast(ulong) cast(long) member;
    }
}

private ulong highestDeclaredPosition(E)() pure @safe
{
    alias Base = EnumBaseType!E;
    ulong highest;
    static foreach (name; __traits(allMembers, E))
    {
        if (declaredPosition!(Base, __traits(getMember, E, name)) > highest)
            highest = declaredPosition!(Base, __traits(getMember, E, name));
    }
    return highest;
}

private template DefaultFlagStorage(E)
{
    enum highest = highestDeclaredPosition!E;
    static if (highest < 8)
        alias DefaultFlagStorage = ubyte;
    else static if (highest < 16)
        alias DefaultFlagStorage = ushort;
    else static if (highest < 32)
        alias DefaultFlagStorage = uint;
    else static if (highest < 64)
        alias DefaultFlagStorage = ulong;
    else
        static assert(false,
            "FlagSet!(" ~ E.stringof ~ ") has a position beyond bit 63");
}

/**
 * A set of the flags declared by `Flag`.
 *
 * `FlagSet.init` is an empty set. This is a plain copyable value containing
 * only its integer mask; it allocates nothing and owns no resources.
 */
struct FlagSet(Flag, Storage = DefaultFlagStorage!Flag)
{
    static assert(is(Flag == enum),
        "FlagSet requires an enum, not " ~ Flag.stringof);
    static assert(isStorageType!Storage,
        "FlagSet storage must be ubyte, ushort, uint, or ulong");

    alias FlagType = Flag;
    alias StorageType = Storage;
    private alias FlagBase = EnumBaseType!Flag;

    /// Number of bits in the selected storage type.
    enum size_t bitCapacity = Storage.sizeof * 8;

    /// Number of atomic flags declared by the enum.
    enum size_t declaredCount = __traits(allMembers, Flag).length;

    static foreach (name; __traits(allMembers, Flag))
    {
        static assert(declaredPosition!(FlagBase,
                __traits(getMember, Flag, name)) < bitCapacity,
            "FlagSet!(" ~ Flag.stringof ~ ", " ~ Storage.stringof ~
                "): flag '" ~ name ~ "' does not fit in storage");
    }

    static foreach (leftIndex, leftName; __traits(allMembers, Flag))
    {
        static foreach (rightIndex, rightName; __traits(allMembers, Flag))
        {
            static if (rightIndex > leftIndex)
            {
                static assert(__traits(getMember, Flag, leftName) !=
                        __traits(getMember, Flag, rightName),
                    "FlagSet!(" ~ Flag.stringof ~ "): flags '" ~
                        leftName ~ "' and '" ~ rightName ~
                        "' use the same bit position");
            }
        }
    }

    private static Storage buildValidMask() pure @safe
    {
        Storage result;
        static foreach (name; __traits(allMembers, Flag))
        {
            result = cast(Storage)(result | (cast(Storage) 1 <<
                    declaredPosition!(FlagBase,
                    __traits(getMember, Flag, name))));
        }
        return result;
    }

    /// Mask containing every declared flag and no unused storage bits.
    enum Storage validMask = buildValidMask();

    private Storage bits_;

    private static FlagSet fromValidBits(Storage raw) pure @safe
    {
        FlagSet result;
        result.bits_ = raw;
        return result;
    }

    private static bool tryMaskOf(Flag flag, scope Storage* output) pure @safe
    {
        ulong position;
        static if (__traits(isUnsigned, FlagBase))
        {
            position = cast(ulong) cast(FlagBase) flag;
        }
        else
        {
            const raw = cast(long) cast(FlagBase) flag;
            if (raw < 0)
                return false;
            position = cast(ulong) raw;
        }

        if (position >= bitCapacity)
            return false;
        const mask = cast(Storage)(cast(Storage) 1 << position);
        if ((validMask & mask) == 0)
            return false;
        *output = mask;
        return true;
    }

    private static Storage maskOf(Flag flag) @safe
    {
        Storage mask;
        const valid = tryMaskOf(flag, &mask);
        version (XTB_Checked)
            require(valid, "invalid FlagSet enum value");
        return mask;
    }

    /// Returns a set containing every declared flag.
    static FlagSet all() pure @safe
    {
        return fromValidBits(validMask);
    }

    /// Returns a set containing all supplied flags.
    static FlagSet of(Flags...)(Flags flags) @safe
    {
        FlagSet result;
        static foreach (index, Argument; Flags)
        {
            static assert(is(Argument == Flag),
                "FlagSet.of accepts only " ~ Flag.stringof ~ " values");
            result.bits_ = cast(Storage)(
                result.bits_ | maskOf(flags[index])
            );
        }
        return result;
    }

    /// Returns whether `raw` contains no undeclared bits.
    static bool acceptsBits(Storage raw) pure @safe
    {
        return (raw & cast(Storage)(~validMask)) == 0;
    }

    /**
     * Decodes a raw mask if it contains only declared flags.
     *
     * Returns `false` and leaves `output` unchanged for an invalid mask.
     * `output` is required and a null pointer is a programmer error.
     */
    static bool tryFromBits(Storage raw, scope FlagSet* output) @safe
    {
        version (XTB_Checked)
            require(output !is null, "FlagSet output must not be null");
        if (!acceptsBits(raw))
            return false;
        output.bits_ = raw;
        return true;
    }

    /// Decodes a raw mask and panics if it contains an undeclared bit.
    static FlagSet fromBits(Storage raw) @safe
    {
        version (XTB_Checked)
            require(acceptsBits(raw), "FlagSet mask contains undeclared bits");
        return fromValidBits(raw);
    }

    /// Decodes a raw mask after discarding all undeclared bits.
    static FlagSet fromBitsTruncated(Storage raw) pure @safe
    {
        return fromValidBits(cast(Storage)(raw & validMask));
    }

    /// Returns the underlying integer mask.
    Storage bits() const pure @safe
    {
        return bits_;
    }

    /// Returns whether no flag is enabled.
    bool isEmpty() const pure @safe
    {
        return bits_ == 0;
    }

    /// Returns whether every declared flag is enabled.
    bool isFull() const pure @safe
    {
        return bits_ == validMask;
    }

    /// Returns whether `flag` is one of the enum's declared values.
    static bool isDeclared(Flag flag) pure @safe
    {
        Storage mask;
        return tryMaskOf(flag, &mask);
    }

    /// Returns whether `flag` is enabled. Invalid enum values panic.
    bool contains(Flag flag) const @safe
    {
        return (bits_ & maskOf(flag)) != 0;
    }

    /// Returns whether every flag in `subset` is enabled.
    bool containsAll(FlagSet subset) const pure @safe
    {
        return (bits_ & subset.bits_) == subset.bits_;
    }

    /// Returns whether at least one flag in `other` is enabled here.
    bool intersects(FlagSet other) const pure @safe
    {
        return (bits_ & other.bits_) != 0;
    }

    /// Returns the number of flags enabled in this value.
    size_t enabledCount() const pure @safe
    {
        Storage remaining = bits_;
        size_t result;
        while (remaining != 0)
        {
            remaining = cast(Storage)(remaining & (remaining - 1));
            ++result;
        }
        return result;
    }

    /// Set union (`|`), intersection (`&`), difference (`-`), or symmetric difference (`^`).
    FlagSet opBinary(string operation)(FlagSet other) const pure @safe
    {
        static if (operation == "|")
            return fromValidBits(cast(Storage)(bits_ | other.bits_));
        else static if (operation == "&")
            return fromValidBits(cast(Storage)(bits_ & other.bits_));
        else static if (operation == "-")
            return fromValidBits(cast(Storage)(bits_ & cast(Storage)(~other.bits_)));
        else static if (operation == "^")
            return fromValidBits(cast(Storage)(bits_ ^ other.bits_));
        else
            static assert(false,
                "unsupported FlagSet binary operator: " ~ operation);
    }

    /// Applies set union, intersection, difference, or symmetric difference in place.
    ref FlagSet opOpAssign(string operation)(FlagSet other) return pure @safe
    {
        static if (operation == "|")
            bits_ = cast(Storage)(bits_ | other.bits_);
        else static if (operation == "&")
            bits_ = cast(Storage)(bits_ & other.bits_);
        else static if (operation == "-")
            bits_ = cast(Storage)(bits_ & cast(Storage)(~other.bits_));
        else static if (operation == "^")
            bits_ = cast(Storage)(bits_ ^ other.bits_);
        else
            static assert(false,
                "unsupported FlagSet assignment operator: " ~ operation);
        return this;
    }

    /// Complements declared flags while leaving unused storage bits clear.
    FlagSet opUnary(string operation)() const pure @safe
    {
        static if (operation == "~")
            return fromValidBits(cast(Storage)(cast(Storage)(~bits_) & validMask));
        else
            static assert(false,
                "unsupported FlagSet unary operator: " ~ operation);
    }

    /**
     * Iterates enabled flags by value in enum declaration order.
     *
     * The enabled mask is captured when iteration starts, so changing the
     * original set inside the loop does not change which values are visited.
     */
    int opApply(scope int delegate(Flag) nothrow @nogc callback) const
    {
        const iterationBits = bits_;
        int result;
        static foreach (name; __traits(allMembers, Flag))
        {
            if (result == 0 && (iterationBits & cast(Storage)(cast(Storage) 1 <<
                    declaredPosition!(FlagBase,
                    __traits(getMember, Flag, name)))) != 0)
                result = callback(__traits(getMember, Flag, name));
        }
        return result;
    }
}

/// Enables `flag`. An invalid enum value is a programmer error and panics.
void enable(Flag, Storage)(ref FlagSet!(Flag, Storage) flags, Flag flag) @safe
{
    flags.bits_ = cast(Storage)(flags.bits_ | flags.maskOf(flag));
}

/// Disables `flag`. An invalid enum value is a programmer error and panics.
void disable(Flag, Storage)(ref FlagSet!(Flag, Storage) flags, Flag flag) @safe
{
    flags.bits_ = cast(Storage)(flags.bits_ & cast(Storage)(~flags.maskOf(flag)));
}

/// Toggles `flag`. An invalid enum value is a programmer error and panics.
void toggle(Flag, Storage)(ref FlagSet!(Flag, Storage) flags, Flag flag) @safe
{
    flags.bits_ = cast(Storage)(flags.bits_ ^ flags.maskOf(flag));
}

/// Returns a copy of `flags` with `flag` enabled.
FlagSet!(Flag, Storage) enabled(Flag, Storage)(
    FlagSet!(Flag, Storage) flags,
    Flag flag,
) @safe
{
    flags.enable(flag);
    return flags;
}

/// Returns a copy of `flags` with `flag` disabled.
FlagSet!(Flag, Storage) disabled(Flag, Storage)(
    FlagSet!(Flag, Storage) flags,
    Flag flag,
) @safe
{
    flags.disable(flag);
    return flags;
}

/// Returns a copy of `flags` with `flag` toggled.
FlagSet!(Flag, Storage) toggled(Flag, Storage)(
    FlagSet!(Flag, Storage) flags,
    Flag flag,
) @safe
{
    flags.toggle(flag);
    return flags;
}

/// Disables every flag.
void clear(Flag, Storage)(ref FlagSet!(Flag, Storage) flags) pure @safe
{
    flags.bits_ = 0;
}

/// Enables every declared flag.
void fill(Flag, Storage)(ref FlagSet!(Flag, Storage) flags) pure @safe
{
    flags.bits_ = flags.validMask;
}

version (unittest)
{
    private enum Permission
    {
        read,
        write,
        execute,
        administer = 7,
    }

    private alias Permissions = FlagSet!Permission;
    private enum readWrite = Permissions.of(
            Permission.read,
            Permission.write,
        );

    unittest
    {
        static assert(Permissions.bitCapacity == 8);
        static assert(Permissions.declaredCount == 4);
        static assert(Permissions.validMask == 0b1000_0111);
        static assert(Permissions.sizeof == ubyte.sizeof);
        static assert(is(typeof(readWrite) == Permissions));
        static assert(readWrite.bits == 0b0000_0011);

        auto permissions = Permissions.of(Permission.read, Permission.write);
        assert(permissions.bits == 0b0000_0011);
        assert(permissions.contains(Permission.read));
        assert(permissions.contains(Permission.write));
        assert(!permissions.contains(Permission.execute));
        assert(permissions.enabledCount == 2);

        permissions.enable(Permission.execute);
        assert(permissions.bits == 0b0000_0111);
        permissions.disable(Permission.write);
        assert(permissions.bits == 0b0000_0101);
        permissions.toggle(Permission.read);
        assert(permissions.bits == 0b0000_0100);
        permissions.clear();
        assert(permissions.isEmpty);
        permissions.fill();
        assert(permissions.isFull);
    }

    unittest
    {
        const read = Permissions.of(Permission.read);
        const write = Permissions.of(Permission.write);
        const execute = Permissions.of(Permission.execute);

        assert((read | write).bits == 0b0000_0011);
        assert(((read | write) & write) == write);
        assert(((read | write) - write) == read);
        assert(((read | write) ^ write) == read);
        assert((~Permissions.init).isFull);
        assert((~Permissions.all).isEmpty);

        auto combined = Permissions.of(Permission.read);
        combined |= write;
        combined |= execute;
        combined &= read | execute;
        combined -= execute;
        assert(combined == read);
    }

    unittest
    {
        Permissions decoded = Permissions.of(Permission.write);
        assert(Permissions.acceptsBits(0b1000_0101));
        assert(Permissions.tryFromBits(0b1000_0101, &decoded));
        assert(decoded.bits == 0b1000_0101);

        const before = decoded;
        assert(!Permissions.acceptsBits(0b0000_1000));
        assert(!Permissions.tryFromBits(0b0000_1000, &decoded));
        assert(decoded == before);
        assert(Permissions.fromBits(0b1000_0001).bits == 0b1000_0001);
        assert(Permissions.fromBitsTruncated(0xff).bits == Permissions.validMask);

        assert(Permissions.isDeclared(Permission.administer));
        assert(!Permissions.isDeclared(cast(Permission) 3));
        assert(!Permissions.isDeclared(cast(Permission)-1));
    }

    unittest
    {
        const original = Permissions.of(Permission.read);
        const changed = original
            .enabled(Permission.write)
            .toggled(Permission.read)
            .disabled(Permission.write);

        assert(original == Permissions.of(Permission.read));
        assert(changed.isEmpty);
    }

    unittest
    {
        const selected = Permissions.of(
            Permission.administer,
            Permission.execute,
            Permission.read,
        );
        Permission[4] visited;
        size_t visitCount;
        foreach (permission; selected)
            visited[visitCount++] = permission;

        assert(visitCount == 3);
        assert(visited[0] == Permission.read);
        assert(visited[1] == Permission.execute);
        assert(visited[2] == Permission.administer);

        visitCount = 0;
        foreach (permission; Permissions.init)
            ++visitCount;
        assert(visitCount == 0);

        foreach (permission; Permissions.all)
        {
            ++visitCount;
            if (visitCount == 2)
                break;
        }
        assert(visitCount == 2);
    }

    unittest
    {
        auto changing = Permissions.of(Permission.read, Permission.write);
        auto changingPointer = &changing;
        Permission[2] visited;
        size_t visitCount;
        foreach (permission; changing)
        {
            visited[visitCount++] = permission;
            (*changingPointer).disable(Permission.write);
            (*changingPointer).enable(Permission.administer);
        }

        assert(visitCount == 2);
        assert(visited[0] == Permission.read);
        assert(visited[1] == Permission.write);
        assert(changing == Permissions.of(
                Permission.read,
                Permission.administer,
        ));
    }

    private enum WideFlag : ulong
    {
        low,
        high = 40,
    }

    private enum MediumFlag
    {
        low,
        high = 8,
    }

    private enum LargeFlag
    {
        low,
        high = 16,
    }

    static assert(FlagSet!WideFlag.sizeof == ulong.sizeof);
    static assert(FlagSet!MediumFlag.sizeof == ushort.sizeof);
    static assert(FlagSet!LargeFlag.sizeof == uint.sizeof);
    static assert(FlagSet!(Permission, ushort).sizeof == ushort.sizeof);

    private enum NineFlags
    {
        f0,
        f1,
        f2,
        f3,
        f4,
        f5,
        f6,
        f7,
        f8,
    }

    private enum OutOfRangeFlag
    {
        first,
        tooFar = 8,
    }

    private enum DuplicatePosition
    {
        first,
        duplicate = 0,
    }

    private enum NegativePosition
    {
        invalid = -1,
    }

    private enum BeyondMaximum : ulong
    {
        invalid = 64,
    }

    static assert(!__traits(compiles, FlagSet!(NineFlags, ubyte).init));
    static assert(!__traits(compiles, FlagSet!(OutOfRangeFlag, ubyte).init));
    static assert(!__traits(compiles, FlagSet!(DuplicatePosition, ubyte).init));
    static assert(!__traits(compiles, FlagSet!NegativePosition.init));
    static assert(!__traits(compiles, FlagSet!BeyondMaximum.init));
    static assert(!__traits(compiles, FlagSet!(Permission, byte).init));
}
