module xtb.diagnostics.demangle;

nothrow @nogc:

import xtb.types;

private enum max_recursion = 64;

private enum NumberSign
{
    positive,
    negative,
}

/// Controls how much function-signature information demangling includes.
enum SignatureDetail
{
    overload_identity,
    overload_identity_and_return,
    full,
}

private struct DemangleWriter
{
pure nothrow @nogc:

    char[] storage;
    usize written;
    bool failed;
    bool discard;

    void put(char value)
    {
        if (this.discard) return;

        if (this.written == this.storage.length)
        {
            this.failed = true;
            return;
        }

        this.storage[this.written++] = value;
    }

    void put(String value)
    {
        if (this.discard) return;

        if (value.length > this.storage.length - this.written)
        {
            this.failed = true;
            return;
        }

        foreach (character; value)
            this.storage[this.written++] = character;
    }
}

private struct FunctionAttributes
{
    bool is_pure;
    bool is_nothrow;
    bool is_ref;
    bool is_property;
    bool is_nogc;
    bool is_return;
    bool is_scope;
    bool is_trusted;
    bool is_safe;
    bool is_live;
}

private struct Demangler
{
pure nothrow @nogc:

    String input;
    usize offset;
    usize recursion;
    usize last_template_name;
    bool has_last_template_name;
    SignatureDetail detail;
    DemangleWriter output;

    bool consume(char value)
    {
        if (this.offset == this.input.length || this.input[this.offset] != value) return false;

        ++this.offset;
        return true;
    }

    bool starts_with(String value)
    {
        return value.length <= this.input.length - this.offset
            && this.input[this.offset .. this.offset + value.length] == value;
    }

    bool qualified_name()
    {
        bool found;
        while (this.symbol_name_start())
        {
            if (found && this.repeated_template_function_name())
            {
                usize ignored;
                if (!this.back_reference_target(&ignored)) return false;

                continue;
            }

            if (found) this.output.put('.');
            if (!this.symbol_name()) return false;

            found = true;
        }

        return found && !this.output.failed;
    }

    bool symbol_name_start()
    {
        if (this.offset >= this.input.length) return false;
        if (digit(this.input[this.offset]) || this.input[this.offset] == '0') return true;
        if (this.starts_with("__T") || this.starts_with("__U")) return true;

        return this.input[this.offset] == 'Q' && this.back_reference_targets_identifier();
    }

    bool symbol_name()
    {
        if (this.starts_with("__T") || this.starts_with("__U")) return this.template_name();
        if (this.offset < this.input.length && this.input[this.offset] == 'Q')
            return this.identifier_back_reference();
        if (this.consume('0'))
        {
            this.output.put("<anonymous>");
            return true;
        }

        return this.length_name();
    }

    bool length_name()
    {
        usize length;
        if (!this.number(&length) || length == 0 || length > this.input.length - this.offset)
            return false;

        this.output.put(this.input[this.offset .. this.offset + length]);
        this.offset += length;
        return !this.output.failed;
    }

    bool template_name()
    {
        this.offset += 3;
        this.last_template_name = this.offset;
        this.has_last_template_name = true;
        if (!this.length_name()) return false;

        this.output.put("!(");
        bool first = true;
        while (this.offset < this.input.length && this.input[this.offset] != 'Z')
        {
            if (!first) this.output.put(", ");
            if (!this.template_argument()) return false;

            first = false;
        }

        if (!this.consume('Z')) return false;

        this.output.put(')');
        return !this.output.failed;
    }

    bool repeated_template_function_name()
    {
        if (
            !this.has_last_template_name
            || this.offset >= this.input.length
            || this.input[this.offset] != 'Q'
        )
        {
            return false;
        }

        const saved_offset = this.offset;
        usize target;
        if (!this.back_reference_target(&target))
        {
            this.offset = saved_offset;
            return false;
        }

        const follows_with_function = this.offset < this.input.length
            && (call_convention(this.input[this.offset]) || this.input[this.offset] == 'M');
        this.offset = saved_offset;
        return target == this.last_template_name && follows_with_function;
    }

    bool template_argument()
    {
        if (this.consume('H')) this.output.put("specialized ");
        if (this.consume('T')) return this.type();
        if (this.consume('V'))
        {
            DemangleWriter saved_output = this.output;
            DemangleWriter discarded_output;
            discarded_output.discard = true;
            this.output = discarded_output;
            const valid_type = this.type();
            this.output = saved_output;
            if (!valid_type) return false;

            return this.value();
        }
        if (this.consume('S'))
            return this.starts_with("_D") ? this.mangled_name() : this.qualified_name();

        if (this.consume('X'))
        {
            usize length;
            if (!this.number(&length) || length > this.input.length - this.offset) return false;

            this.output.put(this.input[this.offset .. this.offset + length]);
            this.offset += length;
            return true;
        }

        return false;
    }

    bool value()
    {
        if (this.consume('n'))
        {
            this.output.put("null");
            return true;
        }
        if (this.consume('i')) return this.copy_number(NumberSign.positive);
        if (this.consume('N')) return this.copy_number(NumberSign.negative);
        if (
            this.offset < this.input.length
            && (
                this.input[this.offset] == 'a'
                || this.input[this.offset] == 'w'
                || this.input[this.offset] == 'd'
            )
        )
        {
            return this.string_value();
        }
        if (this.consume('A') || this.consume('S'))
        {
            usize count;
            if (!this.number(&count)) return false;
            this.output.put('[');
            foreach (index; 0 .. count)
            {
                if (index != 0) this.output.put(", ");
                if (!this.value()) return false;
            }
            this.output.put(']');
            return true;
        }
        if (this.consume('f'))
        {
            this.output.put('&');
            return this.mangled_name();
        }
        if (this.consume('e')) return this.floating_value();
        if (this.consume('c'))
        {
            if (!this.floating_value()) return false;

            this.output.put(" + ");
            if (!this.consume('c')) return false;

            return this.floating_value();
        }

        return false;
    }

    bool string_value()
    {
        const width_code = this.input[this.offset++];
        usize characters;
        if (!this.number(&characters) || !this.consume('_')) return false;

        usize code_units;
        switch (width_code)
        {
        case 'a':
            code_units = 1;
            break;
        case 'w':
            code_units = 2;
            break;
        case 'd':
            code_units = 4;
            break;
        default:
            return false;
        }

        if (characters > usize.max / code_units / 2) return false;

        const hex_length = characters * code_units * 2;
        if (hex_length > this.input.length - this.offset) return false;

        this.output.put('"');
        this.output.put(this.input[this.offset .. this.offset + hex_length]);
        this.output.put('"');
        this.offset += hex_length;
        return !this.output.failed;
    }

    bool floating_value()
    {
        const start = this.offset;
        while (
            this.offset < this.input.length
            && (
                hex_digit(this.input[this.offset])
                || this.input[this.offset] == 'N'
                || this.input[this.offset] == 'I'
                || this.input[this.offset] == 'P'
            )
        )
        {
            ++this.offset;
        }

        if (this.offset == start) return false;

        this.output.put(this.input[start .. this.offset]);
        return !this.output.failed;
    }

    bool copy_number(NumberSign sign)
    {
        const start = this.offset;
        usize ignored;
        if (!this.number(&ignored)) return false;

        if (sign == NumberSign.negative) this.output.put('-');

        this.output.put(this.input[start .. this.offset]);
        return !this.output.failed;
    }

    bool number(usize* result)
    {
        if (result is null || this.offset == this.input.length || !digit(this.input[this.offset]))
            return false;

        usize number_value;
        while (this.offset < this.input.length && digit(this.input[this.offset]))
        {
            const next = cast(usize)(this.input[this.offset] - '0');
            if (number_value > (usize.max - next) / 10) return false;

            number_value = number_value * 10 + next;
            ++this.offset;
        }

        *result = number_value;
        return true;
    }

    bool back_reference_target(usize* target)
    {
        if (target is null || this.offset >= this.input.length || this.input[this.offset] != 'Q')
            return false;

        const reference_position = this.offset++;
        usize distance;
        bool finished;
        while (this.offset < this.input.length)
        {
            const character = this.input[this.offset++];
            usize digit_value;
            if (character >= 'A' && character <= 'Z')
            {
                digit_value = cast(usize)(character - 'A');
            }
            else if (character >= 'a' && character <= 'z')
            {
                digit_value = cast(usize)(character - 'a');
                finished = true;
            }
            else
            {
                return false;
            }

            if (distance > (usize.max - digit_value) / 26) return false;

            distance = distance * 26 + digit_value;
            if (finished) break;
        }

        if (!finished || distance == 0 || distance > reference_position) return false;

        *target = reference_position - distance;
        return *target < this.input.length;
    }

    bool back_reference_targets_identifier()
    {
        const saved_offset = this.offset;
        usize target;
        const valid = this.back_reference_target(&target);
        this.offset = saved_offset;
        return valid && digit(this.input[target]);
    }

    bool identifier_back_reference()
    {
        const reference_offset = this.offset;
        usize target;
        if (!this.back_reference_target(&target) || !digit(this.input[target])) return false;

        const after_reference = this.offset;
        if (++this.recursion > max_recursion) return false;

        this.offset = target;
        const result = this.length_name();
        --this.recursion;
        this.offset = after_reference;
        return result && reference_offset != target;
    }

    bool type_back_reference()
    {
        usize target;
        if (!this.back_reference_target(&target) || digit(this.input[target])) return false;

        const after_reference = this.offset;
        if (++this.recursion > max_recursion) return false;

        this.offset = target;
        const result = this.type();
        --this.recursion;
        this.offset = after_reference;
        return result;
    }

    bool function_type(
        String callable = null,
        SignatureDetail function_detail = SignatureDetail.full,
    )
    {
        String member_qualifier;
        if (this.offset < this.input.length && this.input[this.offset] == 'M')
        {
            ++this.offset;
            if (this.consume('x'))
            {
                member_qualifier = " const";
            }
            else if (this.consume('y'))
            {
                member_qualifier = " immutable";
            }
            else if (this.consume('O'))
            {
                if (this.consume('x'))
                {
                    member_qualifier = " shared const";
                }
                else if (this.starts_with("Ng"))
                {
                    this.offset += 2;
                    member_qualifier = " shared inout";
                }
                else
                {
                    member_qualifier = " shared";
                }
            }
            else if (this.starts_with("Ng"))
            {
                this.offset += 2;
                member_qualifier = " inout";
            }
        }

        if (this.offset >= this.input.length || !call_convention(this.input[this.offset]))
            return false;

        const convention = this.input[this.offset++];
        FunctionAttributes attributes;
        if (!this.function_attributes(&attributes)) return false;

        if (callable.length != 0) this.output.put(callable);
        this.output.put('(');
        bool first = true;
        char close;
        while (this.offset < this.input.length)
        {
            if (
                this.input[this.offset] == 'X'
                || this.input[this.offset] == 'Y'
                || this.input[this.offset] == 'Z'
            )
            {
                close = this.input[this.offset++];
                break;
            }

            if (!first) this.output.put(", ");
            if (!this.parameter()) return false;

            first = false;
        }

        if (close == '\0') return false;

        if (close != 'Z')
        {
            if (!first) this.output.put(", ");
            this.output.put(close == 'X' ? "..." : "TypeInfo[]...");
        }

        this.output.put(')');
        this.output.put(member_qualifier);
        DemangleWriter saved_output = this.output;
        if (function_detail == SignatureDetail.overload_identity)
        {
            DemangleWriter discarded_output;
            discarded_output.discard = true;
            this.output = discarded_output;
        }
        else
        {
            this.output.put(" -> ");
        }

        const valid_return = this.type();
        if (function_detail == SignatureDetail.overload_identity) this.output = saved_output;
        if (!valid_return) return false;

        if (function_detail == SignatureDetail.full)
            this.write_function_suffix(attributes, convention);

        return !this.output.failed;
    }

    bool function_attributes(FunctionAttributes* attributes)
    {
        while (this.offset + 1 < this.input.length && this.input[this.offset] == 'N')
        {
            const code = this.input[this.offset + 1];
            switch (code)
            {
            case 'a':
                attributes.is_pure = true;
                break;
            case 'b':
                attributes.is_nothrow = true;
                break;
            case 'c':
                attributes.is_ref = true;
                break;
            case 'd':
                attributes.is_property = true;
                break;
            case 'e':
                attributes.is_trusted = true;
                break;
            case 'f':
                attributes.is_safe = true;
                break;
            case 'i':
                attributes.is_nogc = true;
                break;
            case 'j':
                attributes.is_return = true;
                break;
            case 'l':
                attributes.is_scope = true;
                break;
            case 'm':
                attributes.is_live = true;
                break;
            default:
                return true;
            }

            this.offset += 2;
        }

        return true;
    }

    void write_function_suffix(FunctionAttributes attributes, char convention)
    {
        if (attributes.is_pure) this.output.put(" pure");
        if (attributes.is_nothrow) this.output.put(" nothrow");
        if (attributes.is_ref) this.output.put(" ref");
        if (attributes.is_property) this.output.put(" @property");
        if (attributes.is_nogc) this.output.put(" @nogc");
        if (attributes.is_return) this.output.put(" return");
        if (attributes.is_scope) this.output.put(" scope");
        if (attributes.is_trusted) this.output.put(" @trusted");
        if (attributes.is_safe) this.output.put(" @safe");
        if (attributes.is_live) this.output.put(" @live");

        switch (convention)
        {
        case 'U':
            this.output.put(" extern(C)");
            break;
        case 'W':
            this.output.put(" extern(Windows)");
            break;
        case 'R':
            this.output.put(" extern(C++)");
            break;
        case 'Y':
            this.output.put(" extern(Objective-C)");
            break;
        default:
            break;
        }
    }

    bool parameter()
    {
        if (this.consume('M'))
        {
            this.output.put("scope ");
        }
        else if (this.starts_with("Nk"))
        {
            this.offset += 2;
            this.output.put("return ");
        }

        if (this.consume('I'))
        {
            this.output.put("in ");
        }
        else if (this.consume('J'))
        {
            this.output.put("out ");
        }
        else if (this.consume('K'))
        {
            this.output.put("ref ");
        }
        else if (this.consume('L'))
        {
            this.output.put("lazy ");
        }

        return this.type();
    }

    bool type()
    {
        if (this.offset >= this.input.length) return false;
        if (this.input[this.offset] == 'Q') return this.type_back_reference();
        if (this.starts_with("Ng"))
        {
            this.offset += 2;
            return this.wrapped("inout(", ")");
        }
        if (this.consume('O'))
        {
            if (this.consume('x')) return this.wrapped("shared const(", ")");
            if (this.starts_with("Ng"))
            {
                this.offset += 2;
                return this.wrapped("shared inout(", ")");
            }
            return this.wrapped("shared(", ")");
        }
        if (this.consume('x')) return this.wrapped("const(", ")");
        if (this.consume('y')) return this.wrapped("immutable(", ")");
        if (this.starts_with("Nn"))
        {
            this.offset += 2;
            this.output.put("noreturn");
            return true;
        }
        if (this.starts_with("Nh"))
        {
            this.offset += 2;
            return this.wrapped("__vector(", ")");
        }
        if (this.starts_with("zi"))
        {
            this.offset += 2;
            this.output.put("cent");
            return true;
        }
        if (this.starts_with("zk"))
        {
            this.offset += 2;
            this.output.put("ucent");
            return true;
        }

        const code = this.input[this.offset++];
        switch (code)
        {
        case 'v':
            this.output.put("void");
            return true;
        case 'b':
            this.output.put("bool");
            return true;
        case 'g':
            this.output.put("byte");
            return true;
        case 'h':
            this.output.put("ubyte");
            return true;
        case 's':
            this.output.put("short");
            return true;
        case 't':
            this.output.put("ushort");
            return true;
        case 'i':
            this.output.put("int");
            return true;
        case 'k':
            this.output.put("uint");
            return true;
        case 'l':
            this.output.put("long");
            return true;
        case 'm':
            this.output.put("ulong");
            return true;
        case 'a':
            this.output.put("char");
            return true;
        case 'u':
            this.output.put("wchar");
            return true;
        case 'w':
            this.output.put("dchar");
            return true;
        case 'f':
            this.output.put("float");
            return true;
        case 'd':
            this.output.put("double");
            return true;
        case 'e':
            this.output.put("real");
            return true;
        case 'o':
            this.output.put("ifloat");
            return true;
        case 'p':
            this.output.put("idouble");
            return true;
        case 'j':
            this.output.put("ireal");
            return true;
        case 'q':
            this.output.put("cfloat");
            return true;
        case 'r':
            this.output.put("cdouble");
            return true;
        case 'c':
            this.output.put("creal");
            return true;
        case 'n':
            this.output.put("typeof(null)");
            return true;
        case 'P':
            if (
                this.offset < this.input.length
                && (call_convention(this.input[this.offset]) || this.input[this.offset] == 'M')
            )
            {
                return this.type();
            }

            return this.postfix("*");
        case 'A':
            return this.postfix("[]");
        case 'G':
            return this.static_array();
        case 'H':
            return this.associative_array();
        case 'I':
        case 'S':
        case 'C':
        case 'E':
        case 'T':
            return this.qualified_name();
        case 'D':
            this.skip_type_modifiers();
            return this.function_type("delegate");
        case 'B':
            return this.tuple_type();
        case 'F':
        case 'U':
        case 'W':
        case 'R':
        case 'Y':
            --this.offset;
            return this.function_type("function");
        default:
            return false;
        }
    }

    bool postfix(String suffix)
    {
        if (!this.type()) return false;

        this.output.put(suffix);
        return !this.output.failed;
    }

    bool static_array()
    {
        const number_start = this.offset;
        usize length;
        if (!this.number(&length)) return false;

        const number_end = this.offset;
        if (!this.type()) return false;

        this.output.put('[');
        this.output.put(this.input[number_start .. number_end]);
        this.output.put(']');
        return !this.output.failed;
    }

    bool associative_array()
    {
        Demangler key_start = this;
        DemangleWriter discarded_output;
        discarded_output.discard = true;
        key_start.output = discarded_output;

        Demangler parsed_key = key_start;
        if (!parsed_key.type()) return false;

        this.offset = parsed_key.offset;
        this.last_template_name = parsed_key.last_template_name;
        this.has_last_template_name = parsed_key.has_last_template_name;
        if (!this.type()) return false;

        this.output.put('[');
        Demangler rendered_key = key_start;
        rendered_key.output = this.output;
        if (!rendered_key.type()) return false;

        this.output = rendered_key.output;
        this.output.put(']');
        return !this.output.failed;
    }

    bool tuple_type()
    {
        this.output.put("Tuple!(");
        bool first = true;
        while (this.offset < this.input.length && this.input[this.offset] != 'Z')
        {
            if (!first) this.output.put(", ");
            if (!this.parameter()) return false;

            first = false;
        }

        if (!this.consume('Z')) return false;

        this.output.put(')');
        return !this.output.failed;
    }

    bool wrapped(String prefix, String suffix)
    {
        this.output.put(prefix);
        if (!this.type()) return false;

        this.output.put(suffix);
        return !this.output.failed;
    }

    void skip_type_modifiers()
    {
        bool progress = true;
        while (progress)
        {
            progress = false;
            if (
                this.offset < this.input.length
                && (
                    this.input[this.offset] == 'x'
                    || this.input[this.offset] == 'y'
                    || this.input[this.offset] == 'O'
                )
            )
            {
                ++this.offset;
                progress = true;
            }
            else if (
                this.offset + 1 < this.input.length
                && this.input[this.offset] == 'N'
                && this.input[this.offset + 1] == 'g'
            )
            {
                this.offset += 2;
                progress = true;
            }
        }
    }

    bool mangled_name()
    {
        if (!this.starts_with("_D")) return false;

        this.offset += 2;
        if (!this.qualified_name()) return false;
        if (this.consume('Z')) return true;

        if (
            this.offset < this.input.length
            && (call_convention(this.input[this.offset]) || this.input[this.offset] == 'M')
        )
        {
            return this.function_type(null, this.detail);
        }

        return this.type();
    }
}

private bool digit(char value) pure @safe
{
    return value >= '0' && value <= '9';
}

private bool hex_digit(char value) pure @safe
{
    return digit(value) || (value >= 'A' && value <= 'F');
}

private bool call_convention(char value) pure @safe
{
    return value == 'F'
        || value == 'U'
        || value == 'W'
        || value == 'R'
        || value == 'Y';
}

/// Attempts to demangle a D symbol into caller-provided storage.
///
/// `result` may be null. Otherwise it must point to writable `String` storage.
/// On success, `*result` is a view into `storage`; the caller must keep that
/// storage alive while using the view. On failure, `*result` remains `mangled`.
bool try_demangle_d(
    String mangled,
    return scope char[] storage,
    return scope String* result,
) pure @system
{
    return try_demangle_d(mangled, SignatureDetail.overload_identity, storage, result);
}

/// Same operation with explicit signature-detail control.
bool try_demangle_d(
    String mangled,
    SignatureDetail detail,
    return scope char[] storage,
    return scope String* result,
) pure @system
{
    if (result is null) return false;

    *result = mangled;
    if (mangled == "_Dmain")
    {
        if (storage.length < 4) return false;

        storage[0 .. 4] = "main";
        *result = storage[0 .. 4];
        return true;
    }

    if (mangled.length < 3 || mangled[0 .. 2] != "_D") return false;

    Demangler demangler;
    demangler.input = mangled;
    demangler.offset = 2;
    demangler.detail = detail;
    demangler.output.storage = storage;
    if (!demangler.qualified_name()) return false;

    if (demangler.offset < mangled.length)
    {
        const code = mangled[demangler.offset];
        if (code == 'Z')
        {
            ++demangler.offset;
        }
        else if (call_convention(code) || code == 'M')
        {
            if (!demangler.function_type(null, detail)) return false;
        }
        else
        {
            if (!demangler.type()) return false;
        }
    }

    if (demangler.offset != mangled.length || demangler.output.failed) return false;

    *result = storage[0 .. demangler.output.written];
    return true;
}

version (unittest)
{
    private i32 generated_signature(
        ref const(i32)[],
        i32[String],
        i32 delegate(f32),
        i32 function(i64),
        i32[4],
        shared const(i32)*,
    ) pure
    {
        return 0;
    }

    private i32 generated_template(i32 value, T)(T input) pure
    {
        return value + cast(i32) input;
    }

    private bool generated_alias_target(scope const(f32)[]) pure
    {
        return true;
    }

    private i32 generated_alias_template(alias target)() pure
    {
        return target(null) ? 1 : 0;
    }

    private template repeated_identifier(usize chunks)
    {
        static if (chunks == 0)
        {
            enum repeated_identifier = "";
        }
        else
        {
            enum repeated_identifier =
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                ~ repeated_identifier!(chunks - 1);
        }
    }

    private enum generated_long_declarations = "private struct X"
        ~ repeated_identifier!20
        ~ " {} private alias GeneratedLongType = X"
        ~ repeated_identifier!20
        ~ ";";
    mixin(generated_long_declarations);

    private GeneratedLongType generated_long_return()
    {
        return GeneratedLongType.init;
    }

    private bool contains_ellipsis(String value) pure @safe
    {
        if (value.length < 3) return false;

        foreach (index; 0 .. value.length - 2)
        {
            if (value[index .. index + 3] == "...") return true;
        }

        return false;
    }

    private bool contains_text(String value, String needle) pure @safe
    {
        if (needle.length > value.length) return false;

        foreach (offset; 0 .. value.length - needle.length + 1)
        {
            if (value[offset .. offset + needle.length] == needle) return true;
        }

        return false;
    }
}

unittest
{
    char[2048] storage;
    String result;

    enum load_scene_mangled =
        "_D8examples15stacktrace_demo9loadSceneFNbNiKS3xtb4core"
        ~ "10stacktrace17StackTraceContextAxaZi";
    enum load_scene_identity =
        "examples.stacktrace_demo.loadScene(ref xtb.core.stacktrace."
        ~ "StackTraceContext, const(char)[])";
    enum load_scene_with_return = load_scene_identity ~ " -> int";
    enum load_scene_full = load_scene_with_return ~ " nothrow @nogc";

    assert(try_demangle_d(load_scene_mangled, storage[], &result));
    assert(result == load_scene_identity);
    const bool return_signature_demangled = try_demangle_d(
        load_scene_mangled,
        SignatureDetail.overload_identity_and_return,
        storage[],
        &result,
    );
    assert(return_signature_demangled);
    assert(result == load_scene_with_return);
    assert(try_demangle_d(load_scene_mangled, SignatureDetail.full, storage[], &result));
    assert(result == load_scene_full);

    enum render_graph_mangled =
        "_D8examples15stacktrace_demo16buildRenderGraphFNbNiKS3xtb4core"
        ~ "10stacktrace17StackTraceContextKSQDpQDj12AssetRequestPiZi";
    enum render_graph_expected =
        "examples.stacktrace_demo.buildRenderGraph(ref xtb.core.stacktrace."
        ~ "StackTraceContext, ref examples.stacktrace_demo.AssetRequest, int*)";

    assert(try_demangle_d(render_graph_mangled, storage[], &result));
    assert(result == render_graph_expected);

    enum dispatch_mangled =
        "_D8examples15stacktrace_demo__T13dispatchTypedTiZQsFNbNiK"
        ~ "S3xtb4core10stacktrace17StackTraceContextKSQDuQDo12AssetRequestMAxiZi";
    enum dispatch_expected =
        "examples.stacktrace_demo.dispatchTyped!(int)(ref "
        ~ "xtb.core.stacktrace.StackTraceContext, ref examples.stacktrace_demo."
        ~ "AssetRequest, scope const(int)[])";

    assert(try_demangle_d(dispatch_mangled, storage[], &result));
    assert(result == dispatch_expected);
}

unittest
{
    char[2048] storage;
    String result;

    assert(!try_demangle_d("_D999broken", storage[], &result));
    assert(result == "_D999broken");
    assert(!try_demangle_d("not_a_d_symbol", storage[], &result));
    assert(result == "not_a_d_symbol");

    char[0] empty;
    assert(!try_demangle_d("_D4mainFZi", empty[], &result));
}

unittest
{
    char[2048] storage;
    String result;

    assert(try_demangle_d(generated_signature.mangleof, storage[], &result));
    assert(!result.contains_ellipsis);
    assert(result.length > "generated_signature".length);
    assert(result.contains_text("function(long) -> int"));
    assert(!result.contains_text("function(long) -> int*"));

    alias generated_instantiation = generated_template!(7, i64);
    assert(try_demangle_d(generated_instantiation.mangleof, storage[], &result));
    assert(!result.contains_ellipsis);
    assert(result.contains_text("generated_template!(7, long)"));

    alias generated_alias_instantiation = generated_alias_template!generated_alias_target;
    assert(try_demangle_d(generated_alias_instantiation.mangleof, storage[], &result));
    assert(result.contains_text("generated_alias_target("));
    assert(!result.contains_text("generated_alias_target(scope const(float)[]) ->"));

    const bool full_alias_demangled = try_demangle_d(
        generated_alias_instantiation.mangleof,
        SignatureDetail.full,
        storage[],
        &result,
    );
    assert(full_alias_demangled);
    assert(result.contains_text("generated_alias_target(scope const(float)[]) -> bool"));
}

unittest
{
    String result;

    char[256] identity_storage;
    const bool identity_demangled = try_demangle_d(
        generated_long_return.mangleof,
        SignatureDetail.overload_identity,
        identity_storage[],
        &result,
    );
    assert(identity_demangled);
    assert(result.contains_text("generated_long_return()"));

    char[4096] long_storage;
    const bool long_demangled = try_demangle_d(
        generated_long_return.mangleof,
        SignatureDetail.overload_identity_and_return,
        long_storage[],
        &result,
    );
    assert(long_demangled);
    assert(result.length > 1024);
}
