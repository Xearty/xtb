module xtb.data_struct;

/// Generates a consuming memberwise constructor that requires every field.
///
/// Fields with declaration-site defaults remain required. The constructor
/// moves each by-value parameter into its corresponding field, allowing the
/// struct to contain move-only owners.
///
/// `Type.init` remains available because it is an intrinsic property of every
/// D type. Do not add constructors that bypass the complete-field requirement.
mixin template DataStruct()
{
    static assert(
        typeof(this).tupleof.length != 0,
        "DataStruct requires at least one instance field",
    );

    mixin(
        (()
        {
            alias T = typeof(this);
            auto move_name = "data_struct_move";
            bool move_name_in_use = true;

            while (move_name_in_use)
            {
                move_name_in_use = false;

                static foreach (index; 0 .. T.tupleof.length)
                {
                    if (move_name == __traits(identifier, T.tupleof[index]))
                    {
                        move_name_in_use = true;
                    }
                }

                if (move_name_in_use)
                {
                    move_name ~= "_field";
                }
            }

            auto declaration = "@disable this();\n\nthis(\n";

            static foreach (index; 0 .. T.tupleof.length)
            {{
                enum field_name = __traits(identifier, T.tupleof[index]);
                declaration ~= "    typeof(this." ~ field_name ~ ") " ~ field_name ~ ",\n";
            }}

            declaration ~= ") nothrow @nogc @trusted\n{\n";
            declaration ~= "    import xtb.lifetime : " ~ move_name ~ " = move;\n\n";

            static foreach (index; 0 .. T.tupleof.length)
            {{
                enum field_name = __traits(identifier, T.tupleof[index]);
                declaration ~= "    this." ~ field_name ~ " = " ~ move_name
                    ~ "(" ~ field_name ~ ");\n";
            }}

            declaration ~= "}\n";
            return declaration;
        })(),
    );
}

version (unittest)
{
    import xtb.lifetime;
    import xtb.types;
}

unittest
{
    struct Config
    {
        i32 width;
        i32 height;

        mixin DataStruct;
    }

    Config config = Config(width: 800, height: 600);

    assert(config.width == 800);
    assert(config.height == 600);
    static assert(!__traits(compiles, Config(width: 800)));
    static assert(!__traits(compiles, ()
    {
        Config value;
    }));
    static assert(__traits(compiles, Config.init));
}

unittest
{
    struct Defaults
    {
        i32 value = 10;

        mixin DataStruct;
    }

    Defaults defaults = Defaults(value: 20);

    assert(defaults.value == 20);
    static assert(!__traits(compiles, Defaults()));
}

unittest
{
    struct Owner
    {
        i32 value;

        @disable this(this);
        @disable ref Owner opAssign(Owner source) return;
    }

    struct OwnerConfig
    {
        Owner owner;

        mixin DataStruct;
    }

    Owner owner = Owner(42);
    OwnerConfig config = OwnerConfig(owner: move(owner));

    assert(config.owner.value == 42);
    assert(owner == Owner.init);
}

unittest
{
    struct MoveName
    {
        i32 data_struct_move;

        mixin DataStruct;
    }

    MoveName value = MoveName(data_struct_move: 42);

    assert(value.data_struct_move == 42);
}
