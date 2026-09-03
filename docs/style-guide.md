# XTB style guide

This guide defines the style for handwritten D code in XTB. Apply it to new
code and to code that is deliberately being migrated. Do not rename public APIs
or reformat unrelated code as an incidental part of another change.

Generated code, vendored code, and declarations that mirror a foreign ABI keep
the spelling and layout required by their source. Keep those exceptions clearly
separated from ordinary XTB code.

## Naming

Use names that describe the role of a declaration without encoding its
visibility or ownership in punctuation.

| Declaration | Convention | Example |
|---|---|---|
| Types | `PascalCase` with uppercase acronyms | `WindowConfig`, `OpenGLConfig` |
| Aliases | Follow what the alias represents | `OpenGLProc`, `create_window` |
| Functions and methods | `snake_case` | `make_context_current` |
| Variables and parameters | `snake_case` | `window_config` |
| Struct fields | `snake_case` | `context_version` |
| Enum members | `snake_case` | `allocation_failed` |
| Compile-time values | `snake_case` | `default_capacity` |
| Modules and filenames | `snake_case` | `thread_context.d` |
| Foreign ABI declarations | Preserve foreign spelling | `glfwCreateWindow` |

Keep acronyms uppercase within type names, such as `OpenGLConfig`,
`UTF8Decoder`, `HTTPServer`, and `XTBAllocator`.

In `snake_case` names, lowercase acronyms like ordinary words, such as
`load_gl_functions`, `decode_utf8`, and `x11_window`.

An alias follows the convention of the declaration it represents. A type or
callable-type alias uses `PascalCase`; a function or value alias uses
`snake_case`.

Use `snake_case` for functions and methods. Preserve spelling required by a D
language hook, such as `opIndex` or `opAssign`.

Use `snake_case` for variables and parameters. A parameter may share a field's
descriptive name because explicit `this.` qualification keeps the two
unambiguous. Short conventional names such as `i` and `j` remain appropriate
when their meaning is clear. Do not add markers such as `p_`, `_arg`, or
`local_` merely to identify a parameter or local variable.

Use `snake_case` for enum members. The enum type already supplies their
category, so do not repeat the type name in each member:

```d
enum WindowErrorKind
{
    none,
    allocation_failed,
    backend_operation_failed,
}
```

Use `snake_case` for compile-time values and value template parameters. Do not
switch to `UPPER_SNAKE_CASE` merely to advertise that a value is constant:

```d
enum default_capacity = 64;

struct StaticArray(T, usize capacity)
{
}
```

Conventional template type parameters such as `T`, `E`, and `R` may remain
short and capitalized. Longer type parameter names use `PascalCase`. Preserve
names imposed by a foreign ABI, build interface, or compiler convention, such
as the `XTB_Checked` version identifier.

Use lowercase `snake_case` for modules, package directory components, and D
source filenames. The filename matches the final component of its module name:

```text
source/window/xtb/window/create_options.d
```

```d
module xtb.window.create_options;
```

Keep conventional filenames required by D or project tooling, including
`package.d`, `dub.sdl`, `README.md`, and `AGENTS.md`. Do not use hyphens in D
module filenames because hyphens cannot appear in module identifiers.

## User-defined attributes

Preserve the spelling of D language attributes such as `@safe`, `@nogc`,
`@property`, and `@mustuse`.

Define XTB user-defined attributes as `PascalCase` types by default. Acronyms in
attribute type names follow the ordinary type rule, such as `CLICommand` and
`HTTPRoute`. Do not add an `Attribute` suffix solely to identify a UDA.

Use the attribute type itself for a marker and construct an attribute value
when it carries configuration:

```d
@CLIFlatten
GlobalOptions global;

@CLIHelp("Maximum number of parallel compiler jobs")
u32 jobs;
```

Template attributes may carry their configuration in the instantiated type:

```d
@CLIValueWith!CacheBudgetCLI
u32 cache_budget;
```

Use a named `snake_case` manifest attribute value only when the same configured
value is deliberately reused. A direct enum-value attribute uses the
parenthesized UDA-expression form and qualifies its member:

```d
@(ExecutionMode.background)
void refresh_cache();
```

Do not create duplicate factory functions or singleton manifest values merely
to give an attribute a separate lowercase spelling. Existing attribute APIs
may be migrated separately rather than changed incidentally.

## Primitive numeric types

Whenever XTB-owned code explicitly names a primitive numeric type, use the
corresponding alias from `xtb.types` instead of D's built-in spelling.
Import `xtb.types` as a whole rather than maintaining selective import lists;
its small set of fundamental aliases is intended to be available together.

- Use `usize` for slice lengths, indexes, capacities, allocation sizes, and
  other values that naturally follow the target address space.
- Use `isize` for signed differences between indexes, lengths, or pointers.
- Use `u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, or `i64` when the value's
  range or representation is intentionally fixed.
- Use `f32` or `f64` whenever floating-point precision is selected explicitly.

```d
import xtb.types;

u16 protocol_version;
u64 file_offset;
usize item_index;
isize item_difference;
f32 coordinate;
```

This rule does not require an explicit type when clear type inference is more
appropriate. Declarations that directly mirror a foreign ABI preserve the
foreign type spelling.

## Variable declarations and type inference

Initialize a variable at its declaration when practical so it begins with an
immediately meaningful value. Delayed initialization remains appropriate when
control flow genuinely determines the value or low-level code intentionally
uses uninitialized storage.

Use `auto` when the initializer makes the concrete type obvious, especially
when it spells the complete type directly:

```d
auto array = Array!u32.create(allocator);
```

Prefer an explicit type when a function name does not reveal the complete
returned type:

```d
Array!u32 array = load_array();
```

This is a readability judgment, not a hard rule. Type inference remains useful
when spelling a template-heavy implementation type would add noise without
useful information.

Prefer `const` for a local value that represents a computed fact and is not
modified. This is not a hard rule: D's `const` is transitive, so do not use it
when it would obstruct ownership transfer, cleanup, or otherwise clear code.
Use `immutable` only when the underlying data is intentionally immutable
through every reference.

Apply the same inference rule to `const` declarations. Infer the type when the
initializer makes it obvious:

```d
const mask = cast(Storage)(one << position);
const state = WindowState.ready;
```

Prefer an explicit type when a function call hides its result type:

```d
const Storage mask = FlagSet.mask_of(flag);
```

Require an explicit type when the exact representation affects correctness,
including foreign ABIs, storage formats, protocols, defined-width arithmetic,
intentional overload selection, and literals for which inference would choose
the wrong type:

```d
const u32 encoded_length = read_length();
const u64 timeout_ns = 1_000_000;
```

Declare one variable per statement. Conventional loop declarations remain one
logical unit. Use `= void` only in tightly scoped low-level code that
initializes every byte before observation, and explain that requirement when
it is not obvious.

## Compile-time and runtime constants

Use `enum` for a compile-time value that needs no storage or identity:

```d
enum default_capacity = 64;
enum u32 protocol_magic = 0x5854_4200;
```

Use local `const` for a value computed for one invocation and not subsequently
modified:

```d
usize encoded_size(String input) pure nothrow @nogc @safe
{
    const usize header_size = calculate_header_size(input);
    return header_size + input.length;
}
```

Use `static immutable` when an actual stored object is required, particularly
when its address or identity matters:

```d
struct Protocol
{
    static immutable u8[4] magic = [0x58, 0x54, 0x42, 0x00];
}
```

A global or static initializer must be statically evaluable. Do not introduce
a module constructor merely to initialize a constant. Do not use `immutable`
as a stronger-looking spelling of `const`; use it only when the underlying data
is intentionally immutable through every reference.

Give a constant an explicit type when its representation affects correctness.
This includes foreign ABIs, storage formats, protocols, and defined-width
arithmetic.

## Enums and flags

Use an enum for one choice from a closed set. Qualify named enum members with
their type; do not import or alias members into the surrounding namespace:

```d
enum WindowState
{
    hidden,
    visible,
    minimized,
}

WindowState state = WindowState.visible;
```

Use `FlagSet!E` for independent XTB-owned options that may be combined:

```d
enum WindowFeature
{
    resizable,
    decorated,
    transparent,
}

FlagSet!WindowFeature features = FlagSet!WindowFeature.of(
    WindowFeature.resizable,
    WindowFeature.decorated,
);
```

Give an enum an explicit base type when its representation is part of a foreign
ABI, storage format, protocol, or defined-width calculation. Assign explicit
numeric values only when those values have external meaning or must remain
stable.

Keep raw integer masks at foreign and storage boundaries rather than spreading
them through XTB-facing code. Foreign ABI enums, constants, spelling, and
representation remain unchanged.

## Function parameters

Do not use the `in` parameter storage class. Spell out borrowing and passing
semantics rather than relying on the compiler's implementation-defined choice
between value and reference passing.

- Prefer slices for borrowed contiguous data.
- Use `scope const` for borrowed reference-bearing input that must not escape
  or mutate.
- Pass scalars, enums, pointers, slices, and ordinary value types by value.
- Use `scope const ref` for a non-null borrowed aggregate that must be passed by
  reference.
- Use `scope const(T)*` for a nullable borrowed aggregate or a native pointer
  boundary.
- Use an explicit pointer for mutable caller-owned values.
- Do not use `ref` for ordinary mutable parameters. Reserve it for
  language-required hooks, tightly scoped internals, or genuine free
  algorithms whose receiver is not an owning type.

Use `return scope` deliberately when borrowed data may escape through the
return value. Document and validate nullability at pointer boundaries.

## The `inout` qualifier

Use `inout` when a member returns a reference, pointer, or slice borrowed from
its receiver and the returned access must preserve the receiver's qualifier. A
mutable receiver produces mutable access, a const receiver produces const
access, and an immutable receiver produces immutable access:

```d
struct Buffer(T)
{
    T[] items;

    inout(T)[] view() inout return pure @safe
    {
        return this.items;
    }
}
```

Pair `inout` with `return` when the result borrows from the receiver:

```d
ref inout(T) front() inout return;
inout(T)* pointer() inout return;
inout(T)[] view() inout return;
```

Do not use `inout` for an ordinary read-only query, a by-value result, or merely
to avoid writing a straightforward `const` method. It preserves qualifiers; it
is not another spelling of `const` and is unrelated to an output parameter.

## Callbacks, function pointers, and delegates

Use a function pointer when no captured context is needed. Use a scoped
delegate when a callback needs caller context but does not escape the call:

```d
alias VisitFn = bool function(scope const ref Item item) nothrow @nogc @safe;

void visit_all(
    scope const(Item)[] items,
    scope bool delegate(scope const ref Item item) nothrow @nogc @safe visitor,
)
{
    foreach (const ref item; items)
    {
        if (!visitor(item)) return;
    }
}
```

Make the ownership and lifetime of an escaping callback context explicit.
Never let an escaping closure introduce hidden garbage-collector allocation.
Foreign callbacks preserve their required ABI and normally carry context
through an explicit `void*` parameter:

```d
alias NativeCallback = extern (C) void function(
    void* context,
    const NativeEvent* event,
) nothrow @nogc;
```

Callable-type aliases use `PascalCase`. Put applicable `nothrow`, `@nogc`, and
safety attributes on the callable type itself, not only on the function that
accepts it.

## Lambdas and nested functions

Use an expression lambda for one short expression. Use an ordinary braced body
when a callback needs statements or control flow. Do not compress mutation or
several operations into an expression lambda:

```d
auto is_even = (i32 value) => value % 2 == 0;

auto selected = values
    .filter!(
        (i32 value)
        {
            const i32 magnitude = absolute(value);
            return magnitude >= minimum && magnitude <= maximum;
        },
    )
    .map!(value => value * value)
    .take(8);
```

Keep a nested function close to its only use. Move noncapturing or reused logic
to a private module-level helper. Base that choice on locality and capture, not
an arbitrary line limit.

Treat every capture as a borrow with a lifetime consequence. A capturing
delegate does not escape unless its context storage and ownership are explicit.
Never let an escaping capture introduce hidden garbage-collector allocation.

## Nullability and optional values

Use `T*` when pointer identity, mutation, borrowing, or native interoperability
is fundamental. A nullable pointer is appropriate when no referenced object is
a natural result:

```d
/// Returns the matching borrowed window, or null when none exists.
Window* find_window(WindowId id);
```

Use `Option!T` for an optional value that is not inherently pointer-shaped. Use
`Result` when absence represents a failure whose reason matters. Do not use a
null pointer or magic value to conceal a fallible operation:

```d
Option!WindowConfig load_saved_config();
WindowResult create_window(WindowConfig config);
```

Document whether every public pointer parameter and return value may be null.
State a non-null pointer requirement as a precondition and validate it at the
actual pointer boundary:

```d
/// `window` must not be null.
void show_window(Window* window)
{
    require(window !is null, "window must not be null");
    window.show();
}
```

Do not add suffixes such as `_nullable` or `_ptr` when the type and API contract
already communicate the distinction.

## Output parameters

Return small ordinary values directly. Use an output pointer when a fallible
operation must report status separately, produces multiple values, or
constructs an ownership-bearing result transactionally. Put output parameters
after ordinary inputs.

A required output pointer is non-null and documented as such. Do not make an
output pointer nullable merely to make the output optional. Define the output's
failure state explicitly:

```d
/**
 * `output` must point to `StringBuf.init`.
 *
 * On success, `output` owns the decoded string.
 * On failure, `output` remains `StringBuf.init`.
 */
bool try_decode(String input, Allocator* allocator, StringBuf* output);
```

A fallible operation must not leave a partially initialized owner in its
output. Build temporary state and commit it to the output only after success:

```d
StringBuf decoded = StringBuf.create(allocator);

if (!decode_into(input, &decoded))
{
    decoded.deinit();
    return false;
}

*output = move(decoded);
return true;
```

For several small non-owning outputs, prefer returning a result struct over
using multiple output pointers when the struct makes their relationship
clearer.

## Ownership at use sites

Let the type communicate ownership. Do not routinely prefix variables with
`owned_` or `borrowed_`. Use role-specific names when owning and borrowed
values coexist and the distinction adds useful meaning:

```d
StringBuf message_buffer = load_message(allocator);
scope (exit) message_buffer.deinit();

String message = message_buffer.view();
process(message);
```

Make ownership transfer visible with an established operation such as `move`,
`take`, `release`, or `adopt`. Passing an owner by value means consumption and
uses an explicit move at the call site:

```d
StringBuf message = load_message(allocator);
consume(move(message));
```

Do not use an ordinary-looking assignment or a mechanical naming prefix as the
only indication that ownership changed.

## Defaults, overloads, and options

Stable, documented defaults are part of an API and callers may rely on them.
Set an option explicitly when correctness, compatibility, ownership, security,
or important performance behavior depends on its exact value. Changing the
meaning of a public default is an API change.

Overloads with the same name represent the same conceptual operation. A
convenience overload delegates to one canonical implementation; do not add
overloads that merely reorder parameters. Keep an overload family adjacent.

Use a default argument when there is one unsurprising, stable ordinary choice.
Use a configuration struct when independent options are likely to grow. Avoid
boolean arguments when literals such as `true` and `false` would be unclear at
the call site:

```d
RenderOptions options = RenderOptions(clear_target: true, preserve_depth: false);

renderer.render(target, options);
```

Do not write an opaque sequence of flags:

```d
renderer.render(target, true, false);
```

Use distinct names for variants with meaningfully different failure behavior,
such as `try_append` for a reported failure and `append` for a panicking
convenience operation.

## Complete data structs

Use `mixin DataStruct;` when ordinary construction of a data-carrying struct
must provide every instance field. Put the mixin after the fields so the
generated memberwise constructor is easy to discover:

```d
struct WindowConfig
{
    i32 width;
    i32 height;
    String title;

    mixin DataStruct;
}

WindowConfig config = WindowConfig(width: 800, height: 600, title: "XTB OpenGL");
```

Declaration-site field defaults remain required constructor arguments. The
constructor consumes its arguments, so move owning lvalues explicitly and give
an owning data struct its appropriate handwritten `deinit` behavior. Do not add
alternate constructors that bypass the complete-field requirement.

`Type.init` remains available because D defines it intrinsically for every
type. Use it deliberately for zero-state storage or output initialization; do
not present it as ordinary complete construction.

## Foreign boundaries

Preserve the canonical spelling of declarations that directly mirror a foreign
ABI or header. This includes foreign functions, variables, types, aliases,
struct fields, enum members, constants, callbacks, and generated bindings.

```d
extern (C)
{
    GLFWwindow* glfwCreateWindow(
        int width,
        int height,
        const(char)* title,
        GLFWmonitor* monitor,
        GLFWwindow* share,
    );
}

enum GLFW_TRUE = 1;
```

XTB-owned wrappers follow XTB naming even when they call a foreign API. Keep
foreign spelling at the boundary rather than allowing it to spread through the
XTB-facing API.

```d
WindowResult!(Window*) create_window(...);
bool make_context_current(Window* window);
```

## Fields and protection

Do not add leading or trailing underscores merely to identify a field. A suffix
such as `_ptr`, `_count`, or `_bytes` is appropriate only when it communicates
real meaning that the unsuffixed name would omit.

All struct fields are public. Do not use access protection to prevent callers
from inspecting or modifying representation state. Document invariants,
ownership rules, lifetime requirements, and the consequences of invalid
mutation as caller responsibilities.

Do not rename a field to make room for a read-only getter, and do not add
trivial getters or setters solely to restrict direct access. Methods should
represent useful operations rather than compulsory access paths.

This rule applies to struct fields, not to every declaration in the module.
Keep implementation-only functions, templates, aliases, and other helpers at
the narrowest useful protection level:

- Use `private` when a declaration is needed only in its own module.
- Use the narrowest `package(...)` boundary that contains every intended user
  when a helper must cross module boundaries.
- Use `public` only when a declaration is intentionally part of the API.

Do not expose a helper merely because hiding it is optional or because current
tests are colocated with its implementation. Conversely, do not hide an
ordinary part of the library's public vocabulary merely because it currently
has few call sites.

Prefer specifying visibility on each declaration. Avoid distant `private:` or
`public:` labels that make readers search upward to determine a declaration's
visibility. A short visibility block remains reasonable when every declaration
in it clearly has the same role.

## Member access

Within an instance method, qualify every access to an instance field with
`this.`. This applies to reads, writes, address-taking, and values passed to
other functions. Parameters and local variables remain unqualified.

A local variable declared inside an instance method must not reuse the name of
an instance field. Give the local a role-specific name such as `combined_bits`
or `previous_capacity`. Parameters may share a field name when the direct
relationship is useful, because `this.` keeps assignments such as
`this.width = width` unambiguous.

Also qualify calls to instance methods and properties with `this.`. Qualify
static members with their type name. Do not use UFCS on `this` to make a free
function look like an instance operation.

```d
struct Window
{
    enum u32 default_width = 1280;

    bool initialized;
    u32 width;

    static Window create()
    {
        return Window.init;
    }

    void resize(u32 width)
    {
        this.width = width;
        this.update_layout();
    }

    bool valid() const
    {
        return this.initialized;
    }

    private void update_layout()
    {
        rebuild_layout(this.width);
    }
}

private void rebuild_layout(u32 width)
{
}

void example()
{
    Window window = Window.create();
    u32 default_width = Window.default_width;
}
```

The distinction should be visible at the use site:

- `this.width` is an instance field;
- `this.update_layout()` is an instance operation;
- `Window.create()` is a static operation;
- `width` is a local variable or parameter;
- `rebuild_layout(...)` is a free function.

D and DScanner do not provide a built-in rule requiring explicit `this.`.
Review this rule by hand.

Do not use D's `with` statement in handwritten XTB code. It hides the origin of
fields, methods, and enum members; qualify them explicitly instead:

```d
window.width = 800;
window.show();
state = WindowState.ready;
```

## API names

Do not declare a member named `init`; preserve D's built-in `Type.init`
property. Use `create`, `with_capacity`, a source-specific name such as
`from_string`, or `acquire` according to whether an operation constructs,
preallocates, converts, or acquires a scoped resource.

Prefer short operation names such as `append`, `reserve`, and `clear` over
type-prefixed names. Put receiver-owned operations on owning structs as real
members. Keep free functions for algorithms over borrowed or native
representations and for operations that genuinely combine unrelated types.

An operation that conceptually belongs to a type must be a real member,
especially when its natural name is short or generic. Do not place names such
as `set`, `get`, `remove`, or `clear` in the module namespace and rely on UFCS
to make them look like members:

```d
map.set(key, value);
map.remove(key);
```

Free functions remain appropriate for genuinely generic facilities such as
`pretty`, algorithms over borrowed or native representations, and operations
without one natural receiver. Give a free function a domain-specific name when
a short generic name would unnecessarily crowd the importing module's
namespace.

## Call and property syntax

A call with no explicit arguments may omit parentheses when the API is
intentionally property-like and the expression describes a non-mutating query,
characteristic, view, or lightweight transformation:

```d
value.pretty
array.empty
style.bold
scratch.allocator
```

Use parentheses when a call performs an action, mutates state, manages a
resource, or takes explicit arguments:

```d
array.clear();
window.show();
buffer.deinit();
const rendered = value.pretty(options);
```

Property syntax may use a member, `@property`, or UFCS; it is a semantic API
choice rather than merely an attribute choice. Do not use it when it would hide
important allocation, failure, ownership transfer, or other surprising work.
Use the chosen form consistently for a given API.

## Operator overloads and language hooks

Preserve the spelling D requires for language hooks, such as `opIndex`,
`opEquals`, and `opApply`. Keep a hook near the ordinary operations or lifecycle
behavior it relates to.

Implement an operator only when its meaning is conventional and immediately
predictable. Do not use an operator to hide allocation, ownership transfer, or
expected failure; use an explicitly named operation whose parameters and
result expose that behavior.

Keep a language hook small and delegate to an ordinarily named method when that
method is independently useful. Do not create a named method solely so a
trivial hook can delegate to it.

Use `alias this` only when the source type is genuinely and consistently
interchangeable with the target type. Prefer an explicit view or conversion
method when implicit conversion could hide ownership, lifetime, allocation, or
overload-selection behavior.

## Comments and API documentation

Use comments to explain intent, invariants, ownership, lifetime, preconditions,
or a non-obvious decision. Do not narrate behavior that is already clear from
the names and structure of the code.

Use `///` for documentation attached to a public declaration and `//` for
implementation notes. Explicitly document ownership transfer and the lifetime
of borrowed return values when the type system does not express the complete
contract.

```d
/// Returns a view valid until this buffer is mutated or deinitialized.
String view() const
{
    return this.storage[];
}
```

An implementation comment should explain why the code is necessary:

```d
// Reset the source so its eventual deinit cannot release transferred storage.
source = Source.init;
```

Do not require documentation for every public declaration. Self-explanatory
constants and operations such as `clear` do not benefit from ceremonial
comments. Do not leave commented-out code; version control preserves it. Keep
comments synchronized with behavior.

Use the searchable uppercase markers `TODO:` for unfinished work and `FIXME:`
for a known problem. An optional owner may follow the marker name:

```d
// TODO: Add support for multiple displays.
// TODO(xearty): Add support for multiple displays.
// FIXME: Preserve the native error code.
// FIXME(xearty): Preserve the native error code.
```

## Imports

Import modules normally rather than listing individual symbols. The module is
the dependency unit, and long selective-import lists add maintenance noise.
Always import `xtb.types` as a whole.

Implementation code imports the defining XTB modules it depends on. Consumer
code and examples may import stable public package modules. Use a selective,
renamed, or static import when it resolves a collision or materially clarifies
the origin of a name:

```d
import x11_backend = xtb.window.internal.x11;
import wayland_backend = xtb.window.internal.wayland;

x11_backend.create_window();
```

Keep production imports at module scope. Put test-only imports in the bottom
test section. Use `public import` only for intentional public re-exports from a
package facade such as `package.d`.

Separate runtime or platform, third-party, and XTB imports into logical groups.
Alphabetize within a group when useful, but do not enforce it mechanically.

## Declaration ordering

Start a module with its declaration, any module-wide default attributes, and
its production imports:

```d
module xtb.example;

nothrow @nogc:

import xtb.string;
import xtb.types;
```

Keep closely related production declarations together and arrange them for a
top-to-bottom reader. A helper may stay immediately before its only consumer;
do not move implementation helpers away from related code merely to put every
public declaration before every internal declaration.

Within a struct, keep instance fields in one uninterrupted block near the
beginning instead of interleaving fields and methods. Put `mixin DataStruct;`
immediately after that field block when it is used. Keep overload families
adjacent, and keep paired lifecycle operations such as `create` and `deinit`
easy to find. Do not impose an exhaustive category order on structs whose
natural organization differs.

## Test placement

Keep all unit-test code at the bottom of its module so it does not interrupt
the production declarations. Once the test-only section begins, no production
declaration may follow it.

The bottom test section includes:

- `version (unittest)` imports;
- test-only structs, enums, templates, mixins, and helper functions;
- every `unittest` block.

Prefer declarations local to a `unittest` block when only that test uses them.
Put helpers shared by several tests in the bottom test section immediately
before the tests that use them.

Each `unittest` block covers one coherent behavior or a closely related set of
cases. Multiple assertions in one block are appropriate when they verify that
behavior; do not create a separate block for every assertion.

Use blank lines to expose substantial setup, operation, and verification
phases. Do not add ceremonial `Arrange`, `Act`, and `Assert` comments when
spacing already makes the structure clear. Prefer testing public behavior over
inspecting private implementation details.

A regression test makes the reproduced boundary or failure condition apparent
from its data or a short explanatory comment.

```d
// Production imports and declarations.
struct Array
{
    // ...
}

// Everything below here is test-only.
version (unittest)
{
    import xtb.allocators : test_allocator;

    private struct TrackedValue
    {
        // ...
    }
}

unittest
{
    // ...
}

unittest
{
    // ...
}
```

## Multiline lists

Keep short parameter, argument, literal, and initializer lists on one line.
Judge the complete statement or signature, including its indentation and
suffix attributes; do not expand a list merely because it contains multiple
items. If the complete construct fits comfortably near the 100-column target,
prefer the single-line form.

When a list must wrap, put one item on each line, put the closing delimiter on
its own line, and include a trailing comma. Do not pack several items onto one
continuation line merely to reduce vertical space. A list is either entirely
on one line or fully expanded: do not leave the first item beside the opening
delimiter when a later item wraps.

```d
static assert(capacity <= maximum_capacity, "capacity exceeds the supported maximum");

static assert(
    requested_capacity <= maximum_supported_capacity_for_current_backend,
    "requested capacity exceeds the maximum supported by the current backend",
);
```

```d
WindowResult create_window(
    WindowSystem* system,
    scope const WindowConfig* config,
    Allocator* allocator,
) nothrow @nogc
{
    Window* window = Window.create(system, config, allocator);
    return WindowResult.ok(window);
}
```

Apply the same layout to named struct initialization:

```d
OpenGLContextConfig config = OpenGLContextConfig(
    requested_major_version: 4,
    requested_minor_version: 6,
    require_forward_compatibility: false,
);
```

## Expression layout

Break a complex expression at meaningful semantic boundaries. Avoid embedding
one multiline expression inside another multiline expression; introduce named
intermediate values instead. Keep nested multiline expressions only when the
nesting itself communicates useful structure, such as aggregate construction.

Do not use increasingly deep indentation to compensate for an expression that
combines several separate operations:

```d
enum member = __traits(getMember, Flag, name);
enum position = declared_position!(FlagSet.FlagBase, member);
const mask = cast(Storage)(cast(Storage) 1 << position);

result = cast(Storage)(result | mask);
```

Indent a continuation by four spaces from the line that introduced its
containing expression or list. Do not align continuation lines with a distant
opening delimiter or an earlier argument:

```d
result = calculate_something_with_a_long_name(
    first_relevant_value,
    second_relevant_value,
    third_relevant_value,
);

total_storage_bytes = persistent_storage_bytes
    + transient_storage_bytes
    + command_buffer_storage_bytes;
```

Put an infix operator at the beginning of a continuation line. Prefer a
slightly longer clear line over a vertically fragmented expression. Treat
three or more visually nested continuation levels as a strong signal to split
the expression, not as a hard syntactic prohibition.

Parenthesize a meaningful subgroup when an expression mixes different operator
families. Always parenthesize a bitwise operation before comparing its result,
and parenthesize mixed `&&` and `||` groups even when precedence would produce
the intended result:

```d
const enabled = (bits & mask) != 0;

if (ready && (visible || forced))
{
    render();
}
```

Ordinary arithmetic may rely on familiar precedence when its meaning remains
obvious. Do not add redundant layers of parentheses. When several nested
groups are needed, introduce named intermediate values instead of using
parentheses to hold together an overly complex expression.

Write a cast with one space before a plain operand. When the operand is a
parenthesized expression, keep it adjacent to the cast. Parenthesize a negative
operand or another operand whose leading operator would be easy to misread:

```d
Storage one = cast(Storage) 1;
Storage mask = cast(Storage)(one << position);
i32 negative = cast(i32)(-1);
T* pointer = cast(T*) source;
```

Keep a short call or property chain on one line. When a chain wraps, put its
receiver on the first line and begin each continuation with `.` at one ordinary
indentation level. Put one operation on each continuation line:

```d
const output = source
    .normalize_unicode()
    .replace_invalid_code_points()
    .escape_control_characters()
    .pretty(options);
```

Do not align dots beneath a distant expression or pack several operations onto
a later line. Introduce a named intermediate when a step may fail, transfers
ownership, requires cleanup, has an important result of its own, or otherwise
makes the chain difficult to understand. Chaining expresses a simple flow of
values; it does not hide error-handling or lifecycle boundaries.

## Function attributes

Write function suffix attributes in this order:

1. receiver qualifier: `const`, `immutable`, `inout`, or `shared`;
2. `pure`;
3. `nothrow`;
4. `@nogc`;
5. safety attribute: `@safe`, `@trusted`, or `@system`.

```d
bool contains(String value) const pure nothrow @nogc @safe
{
    // ...
}
```

Do not repeat attributes already inherited from a module, struct, or
attribute section:

```d
nothrow @nogc:

struct Buffer
{
    bool empty() const pure @safe
    {
        return this.length == 0;
    }
}
```

Keep `@trusted` on the specific declaration whose implementation justifies
the trust boundary. Do not apply `@trusted` to an entire module or broad
section. Keep unavoidable `@system` annotations similarly narrow.

A `@trusted` declaration must provide a genuinely safe interface for every
input permitted by its signature. Use it for a small adapter that performs a
necessary system operation and itself establishes everything required for
memory safety. Explain a non-obvious trusted operation and its safety argument
in a nearby comment:

```d
const(u8)[] bytes(return scope String value) pure nothrow @nogc @trusted
{
    // char and u8 have the same size; const and return scope preserve access
    // and lifetime restrictions while only the element interpretation changes.
    return cast(const(u8)[]) value;
}
```

If callers must uphold a memory-safety obligation that the signature cannot
express, keep the boundary `@system` and document that obligation. Do not use
`@trusted` merely to make such an API callable from `@safe` code.

## Function return style

Give non-template public functions explicit return types. This keeps the API
stable and readable without requiring callers or documentation tools to infer
the type from the function body.

Return-type inference remains appropriate for local helpers, lambdas, and
templates whose result genuinely depends on template arguments. Do not use it
merely to avoid choosing a public API type.

Return a constructed value directly when the expression remains easy to read.
Introduce a named local when it exposes important intermediate state, supports
validation or cleanup, or avoids deeply nested calls. Do not create a local
solely to satisfy a universal single-return or direct-return rule.

Use the established XTB move operations when returning an ownership-bearing
value requires an explicit move. Do not let a preference for direct returns
obscure ownership transfer.

## Must-use types

Mark a type `@mustuse` when discarding one of its values commonly loses an
error, ownership responsibility, or required scoped behavior. Result, status,
ownership-bearing, and scope-guard types should normally be `@mustuse`:

```d
@mustuse struct WindowResult
{
    // ...
}

@mustuse struct Window
{
    // ...
}
```

Do not apply `@mustuse` to ordinary data types merely because discarding a
value would be unusual. A caller may use `cast(void)` to make an intentional
discard explicit.

## Ignored values and parameters

Use `cast(void)` to show that a returned value is deliberately ignored. Do not
discard a failure result unless the operation is explicitly best-effort or no
useful recovery remains:

```d
// Cleanup cannot recover from a native close failure.
cast(void) native_close(descriptor);
```

Omit the name of an unused parameter when D permits it:

```d
extern (C) void error_callback(i32, const(char)* message)
{
    log_error(message);
}
```

When a required signature retains a named but unused parameter, acknowledge it
inside the body:

```d
void visit(Node node, usize depth)
{
    cast(void) depth;

    process(node);
}
```

Do not add `_`, `unused_`, or similar markers to parameter names. `cast(void)`
records the deliberate discard without changing the parameter's descriptive
name.

## Templates and constraints

Apply the normal multiline-list rule to template parameter lists. Longer type
parameter names use `PascalCase`; value and alias parameters follow the naming
rule for what they represent.

Put a template constraint after the function signature. Put the opening brace
on the line after the constraint according to the ordinary Allman rule:

```d
T* allocate_one(T)(Allocator* allocator)
if (!is(T == void))
{
    // ...
}
```

Prefer a small, readable constraint for overload selection and use targeted
`static assert` messages for detailed diagnostics. A large boolean constraint
usually produces worse errors and is harder to maintain.

Keep compile-time reflection and string mixins contained behind a small named
facility. Generated declarations follow the same naming and signature rules as
handwritten XTB code so compiler and LSP diagnostics remain recognizable.
Prefer templates, template mixins, `static foreach`, and aliases over source
generation. When a string mixin is necessary, generate the smallest practical
fragment and report invalid inputs with targeted compile-time diagnostics.

## `version` and `static if`

Prefer selecting whole declarations, imports, or backend modules instead of
scattering conditional fragments through a function. Platform-specific logic
is easiest to understand when the shared interface and differing
implementations are visibly separated.

Use `version` for build and platform selection. Use `static if` for decisions
based on types, template arguments, or compile-time traits.

Provide an explicit unsupported implementation or compile-time diagnostic when
a platform is intentionally unsupported. Do not silently compile an empty
branch unless doing nothing is the documented behavior.

Avoid deeply nested compile-time conditions. Introduce a named compile-time
predicate when it communicates a real concept rather than merely abbreviating
a one-use expression.

## Early returns and nesting

Prefer early returns for failed preconditions, absent values, and error
propagation when they keep the successful path at a lower indentation level.
Do not require early returns universally or impose a fixed nesting or return
count; a small balanced conditional can still be the clearest structure.

Do not add an `else` after a branch that always returns, breaks, continues, or
otherwise transfers control. Continue at the outer indentation level instead.

Express two mutually exclusive outcomes of the same decision as one `if`/`else`
statement. Do not repeat a condition and its negation in separate statements:

```d
if (ready)
{
    start();
}
else
{
    stop();
}
```

Do not write:

```d
if (ready)
{
    start();
}

if (!ready)
{
    stop();
}
```

The repeated form obscures that the branches are exclusive, evaluates the
condition twice, and may behave unexpectedly if the first branch changes the
state used by the condition. If reevaluation after mutation is intentional,
make the new decision and its changed state explicit rather than presenting it
as the other half of the original branch.

## Loops and iteration

Prefer `foreach` when visiting the elements of a range. Include an index only
when the algorithm uses it. Use a counted `for` loop when the index itself
drives the algorithm, and use `while` when evolving state controls iteration.
Prefer `foreach_reverse` over manual reverse-index arithmetic.

Iterate small ordinary values by value. Use `const ref` when an element is
read-only and copying it is invalid or meaningfully wasteful. Use mutable `ref`
only when intentionally modifying the element:

```d
foreach (item; small_items)
{
    process(item);
}

foreach (const ref item; large_items)
{
    inspect(item);
}

foreach (ref item; mutable_items)
{
    item.reset();
}
```

Do not impose a fixed size threshold; decide from the known element type and
operation. Reference iteration requires an array or range that exposes its
elements by reference.

Do not modify a container's structure while iterating it unless its API
explicitly guarantees that behavior. Use `continue` to keep the remaining loop
body from becoming deeply nested when an element can be rejected early.

## Boolean expressions

Use a boolean value or its negation directly. Do not compare an ordinary
`bool` with `true` or `false`:

```d
if (window.visible)
{
    show_contents();
}

if (!window.visible)
{
    hide_contents();
}
```

Prefer a positive condition when both forms are equally natural, but do not
invent awkward names or duplicate work merely to avoid `!`. Avoid double
negation and expressions whose meaning depends on subtle operator precedence.

Do not hide assignment or unrelated mutation inside a condition. A
conventional operation that advances and reports status may remain in a loop
condition when its meaning is established and the result is immediately
consumed.

When a boolean expression wraps, put one condition on each line and put the
operator at the beginning of each continuation line:

```d
bool compatible = requested.major == available.major
    && requested.minor <= available.minor
    && requested.profile == available.profile;
```

## Equality and identity

Use `==` and `!=` for semantic value equality. Use `is` and `!is` for pointer
identity and null checks:

```d
if (left == right)
{
    process_equal_values();
}

if (window is parent)
{
    process_same_window();
}

if (window !is null)
{
    window.show();
}
```

Write `pointer is null` or `pointer !is null`, not `pointer == null` or
`pointer != null`. Invoke overloaded equality through `==` rather than calling
`opEquals` directly.

Slice equality compares contents. When storage identity matters, compare the
pointer and length explicitly:

```d
const same_contents = left == right;
const same_storage = left.ptr is right.ptr && left.length == right.length;
```

Compile-time `is(...)` type expressions are unaffected by these rules.

## Conditional expressions

Use a conditional expression to select between two values. Keep it on one line
when it is comfortably readable:

```d
const state = ready ? State.running : State.waiting;
```

A conditional expression may wrap when both branches remain reasonably simple.
Indent it by one ordinary level and put `?` and `:` at the beginning of their
continuation lines:

```d
return renderer.is_ready
    ? create_running_renderer_state(renderer)
    : create_waiting_renderer_state(renderer);
```

Avoid nested conditional expressions and branches containing mutation,
unrelated side effects, or their own multiline subtrees. Extract a complex
condition or branch first, or use ordinary control flow when the expression
would compress several logical steps.

## Switch statements

Prefer `final switch` as the default when switching on an XTB-owned enum. Let
the compiler identify newly added enum members that do not yet have behavior:

```d
final switch (state)
{
case State.idle:
    wait();
    break;
case State.running:
    update();
    break;
case State.stopped:
    return;
}
```

Use an ordinary `switch` with an explicit `default` when unknown values are a
real part of the input domain or intentionally share fallback behavior. This
commonly applies to integers and enum-like values received through a foreign
ABI.

End every case with an explicit transfer such as `return`, `break`, `continue`,
`goto case`, or `goto default`. Keep small related cases together. Extract a
helper when a large branch obscures the set of cases, but do not impose a case
length limit.

## Errors and diagnostic messages

Represent expected failure with an explicit result or status. Use `bool` for a
fallible operation only when callers need to distinguish success from failure
but do not need a reason. Prefix such a non-panicking attempt with `try_`:

```d
bool try_decode(String input, u8[] output);
DecodeResult decode(String input, u8[] output);
```

A `try_` function does not panic for the failure it promises to report. It may
still use contracts for genuine caller obligations unrelated to that reported
failure.

Name error enum members after the reason rather than the operation that
encountered it:

```d
enum DecodeError
{
    invalid_encoding,
    truncated_input,
    output_too_small,
}
```

Write contract and panic messages as lowercase sentence fragments without a
trailing period. State the violated condition specifically. Do not prefix a
message with `error:`, repeat the function name, or allocate merely to construct
diagnostic text:

```d
require(index < this.length, "index is outside the array");
ensure(this.length <= this.capacity, "array length exceeds capacity");
```

## Assertions and contracts

Use `require` for a caller obligation: a precondition that must be true when an
API is called. Use `ensure` for an implementation obligation: a postcondition
or invariant that must be true if the implementation is correct.

```d
require(index < this.length, "index is outside the array");

this.length += 1;
ensure(this.length <= this.capacity, "array length exceeds capacity");
```

Both functions invoke XTB's panic handler when their condition is false in a
checked build. In `release-fast`, neither the condition nor the message is
evaluated, and their diagnostic text and checking code must not remain in the
executable. The functions own this build-mode behavior, so an unguarded call is
safe. Existing explicit `version (XTB_Checked)` guards may be migrated
separately.

A contract operand may only inspect state that has already been computed. Do
not put required computation, mutation, output initialization, or another
necessary side effect in a contract expression.

Do not use D's runtime `assert` in production code. It does not reliably route
through XTB's panic handler under BetterC. Runtime `assert` remains appropriate
inside unit tests and test programs, and `static assert` remains appropriate
for compile-time constraints.

Do not use a checked-only contract for an expected failure or for a condition
that must remain enforced in every build. Return an explicit result or status
for expected failure. Use an explicit branch with `panic`, or return a failure
value, when the check must remain active in `release-fast`.

## Braces

Use Allman brace style: put an opening brace on the line after the construct it
belongs to, at the same indentation level. Put `else` on its own line after the
preceding closing brace.

A control statement with exactly one controlled statement may omit braces.
For an `if`, prefer putting the complete construct on one physical line when it
fits comfortably:

```d
if (error.failed) return error;
```

When combining the header and controlled statement would make the line too
long, they may occupy one physical line each. Indent the controlled statement
by one level and put a blank line between the completed construct and the
following statement:

```d
if (!this.ready)
    return false;

this.start();
```

```d
foreach (const ref item; items)
    total_size += item.size;

return total_size;
```

For `for`, `foreach`, and `while`, either compact unbraced form is acceptable;
there is no preference for putting a loop body beside its header. A blank line
is not required between an unbraced statement and the closing brace of its
containing scope.

Use braces when the control header or controlled statement wraps, when the body
contains more than one statement, or when an unbraced body would itself contain
control flow. Do not nest an unbraced control statement inside another control
statement.

```d
if (should_retry)
{
    retry_count += calculate_retry_increment(
        current_attempt,
        previous_failure,
    );
}

continue_processing();
```

If an `if` statement has an `else` or `else if` branch, use braces around every
branch regardless of line length.

```d
if (ready)
{
    start();
}
else
{
    stop();
}
```

Neither compact nor mixed `if`/`else` forms are allowed:

```d
if (ready) start(); else stop();

if (ready)
{
    start();
}
else stop();
```

A `static foreach` expansion does not give repeated declarations their own
scope. When its body needs an explicit inner scope for per-iteration
declarations, write the two opening braces together on their own line instead
of adding another level of visual nesting:

```d
static foreach (name; names)
{{
    enum member = __traits(getMember, Flag, name);
    use(member);
}}
```

Use doubled braces only for this necessary per-expansion scope. A
`static foreach` body without per-iteration declarations uses ordinary single
braces.

An intentionally empty function may use `{}` on one line when emptiness is its
complete and obvious behavior:

```d
extern (C) void ignored_callback() {}
```

An empty control-flow branch normally needs a comment explaining why doing
nothing is required. Otherwise, remove the branch or implement the missing
behavior.

```d
struct Renderer
{
    bool is_ready;

    bool render()
    {
        if (!this.ready()) return false;

        this.draw();
        return true;
    }

    private bool ready() const
    {
        return this.is_ready;
    }

    private void draw()
    {
    }
}
```

Apply the same Allman placement to template constraints, `version` conditions,
`extern` blocks, and other D constructs:

```d
T* allocate_one(T)(Allocator* allocator)
if (!is(T == void))
{
    return allocator.allocate!T();
}

version (Windows)
{
    extern (Windows)
    {
        void native_callback();
    }
}
else version (Posix)
{
    extern (C)
    {
        void native_callback();
    }
}
```

## Vertical spacing

Use blank lines to expose logical groups rather than applying a fixed blank-line
count mechanically. Separate setup, validation, mutation, and output when the
separation makes the flow easier to scan.

Keep statements that collectively express one idea adjacent. In this example,
the first three statements derive a flag mask and the conditional performs a
separate action with it:

```d
static foreach (name; __traits(allMembers, Flag))
{{
    enum member = __traits(getMember, Flag, name);
    enum position = declared_position!(FlagSet.FlagBase, member);
    const mask = cast(Storage)(cast(Storage) 1 << position);

    if (result == 0 && (iteration_bits & mask) != 0)
    {
        result = callback(member);
    }
}}
```

Separate distinct phases when doing so makes them easier to recognize:

```d
require(index < this.items.length, "index is out of bounds");

Item* item = &this.items[index];
const new_size = item.size + additional_size;

item.size = new_size;
this.total_size += additional_size;
```

Do not separate every statement mechanically. A short calculation and its
result may be one logical unit:

```d
const Storage mask = FlagSet.mask_of(flag);
const Storage updated_bits = cast(Storage)(this.bits | mask);
return FlagSet.from_valid_bits(updated_bits);
```

Keep an explicit-lifetime acquisition and the `scope (exit)` statement that
protects it adjacent. Put a blank line after the pair before continuing with the
resource:

```d
Window* window = window_result.take();
scope (exit) window.deinit();

window.make_context_current();
```

Keep a one-statement cleanup on one line. Give separate acquired resources
separate visual groups:

```d
WindowSystem system = system_result.take();
scope (exit) system.deinit();

Window* window = window_result.take();
scope (exit) window.deinit();

window.make_context_current();
```

Do not put a blank line between an acquisition and its cleanup guard: the two
statements form one lifetime unit. Do not add a cleanup guard when ownership is
moved or released earlier, or when a genuine RAII object already owns cleanup.

## Literal formatting

Use digit separators when they expose meaningful grouping in a long literal:

```d
u64 allocation_size = 16_777_216;
u32 channel_mask = 0xFF00_FF00;
u8 flags = 0b1010_0011;
```

Do not add separators to short literals or group digits arbitrarily. Use a
lowercase `0x` prefix with uppercase hexadecimal digits.

Use ordinary quoted strings for short text. Use raw or token strings when they
materially reduce escaping in paths, multiline text, generated code, or
embedded syntax. Choose the form that makes the contents easiest to read
rather than enforcing one string-literal syntax universally.

## General formatting

- Indent with four spaces; do not use tabs.
- Use spaces around binary operators and after commas. Do not put spaces just
  inside parentheses, brackets, or template argument delimiters.
- Attach pointer and slice markers to the type in ordinary D spelling:
  `Allocator* allocator` and `const(u8)[] bytes`.
- Aim to keep lines at or below 100 columns. This is a conservative readability
  target, not a hard limit; exceed it when wrapping would make the code less
  clear.
- Remove trailing whitespace and end text files with a newline.
- Preserve intentional blank lines that communicate grouping.
- Prefer the spelling and layout already established by this guide over
  mechanically copying nearby legacy code.

Review formatting manually. Do not treat formatter output as authoritative or
use a formatter to enforce line width. Compiler and lint checks remain useful
for non-formatting rules they support, but passing them does not replace manual
review of naming, member qualification, or logical grouping.
