# XTB CLI Requiredness, Defaults, and Custom Value Representation

## Status

**Approved design — implemented by the accompanying CLI redesign.**

This document records the agreed direction for XTB CLI argument requiredness, defaults, and custom value parsing/formatting. It covers the finalized redesign beginning with removal of `cliRequired` and continuing through required-by-default scalar fields, `Option!T`, semantic defaults, `cliHideDefault`, parser-input defaults, negatable booleans, and grouped custom CLI value representations.

This document is the source of truth for the implemented redesign. Further changes should be discussed and reflected here before changing the API.

---

## 1. Motivation

The pre-redesign CLI design treated requiredness as an independent attribute:

```d
@cliRequired
uint port;
```

while ordinary scalar fields are otherwise optional and retain their initialized D value when omitted.

This works, but it creates awkward combinations. For example:

```d
@cliRequired
Option!uint port;
```

is technically expressible, but contradictory in spirit:

- `Option!T` says that absence is a meaningful state.
- `cliRequired` says that absence is invalid.

After a successful parse, the field can therefore never be `none`.

The API also requires the user to explicitly mark the most ordinary scalar case—"this value must be provided"—while a plain field silently behaves as optional.

The implemented design reverses this.

The declaration itself should communicate the schema:

```d
String output;              // required
Option!String output;       // optional; absence is preserved

@cliDefault
uint jobs = 8;              // optional; defaults to 8
```

This makes the common cases obvious from the field declaration and removes the need for `cliRequired`. The `cliRequired` attribute is removed by this redesign rather than retained as a second requiredness mechanism.

---

## 2. Core semantic model

For ordinary value-taking scalar arguments, the implemented model is:

| Declaration | Meaning |
|---|---|
| `T value;` | Required |
| `Option!T value;` | Optional; absence is preserved as `none` |
| `@cliDefault T value;` | Optional; initialized D value is the default |
| `@cliDefaultInput("text") T value;` | Optional; the declared text is parsed at runtime when omitted |

The central rule is:

> A value-taking scalar field is required unless its declaration provides a valid representation of absence.

There are two ways to make absence valid:

1. Preserve absence explicitly with `Option!T`.
2. Provide a default value.

---

## 3. Plain scalar fields are required

A plain scalar field means that the application requires a value.

```d
struct ConnectArgs
{
    ushort port;
}
```

Conceptually:

```text
tool connect
    -> parse error: --port is required

tool connect --port 8080
    -> port == 8080
```

The implicit D initializer is not treated as a CLI default.

For example:

```d
uint jobs;
```

does **not** mean:

```text
absent -> 0
```

It means:

```text
absent -> parse error
```

This is important because D does not reliably expose whether a field initializer equal to `.init` was written explicitly. These two declarations cannot be distinguished reliably through normal reflection:

```d
uint jobs;
uint jobs = 0;
```

The design therefore does not attempt to infer CLI defaults from field initializer syntax.

A default must be declared explicitly using `cliDefault` or `cliDefaultInput`.

---

## 4. `Option!T` means observable absence

`Option!T` is the direct representation of an optional argument.

```d
Option!uint jobs;
```

Semantics:

```text
tool
    -> jobs == none

tool --jobs 0
    -> jobs == some(0)

tool --jobs 8
    -> jobs == some(8)
```

The important invariant is:

> If a field is declared as `Option!T`, successful parsing must still be capable of producing `none`.

This gives `Option!T` a precise purpose: the application cares whether the user supplied the value at all.

For example:

```d
Option!uint jobs;
```

may mean:

```text
none     -> choose automatically
some(0)  -> the user explicitly requested zero
some(8)  -> the user explicitly requested eight
```

---

## 5. `cliRequired` is removed

Under this model, requiredness is derived from the schema rather than declared by a generic UDA.

```d
String registry;
```

already means that the value is required. Therefore `cliRequired` adds no useful information for ordinary scalars. On `Option!T` it is contradictory, and on defaulted fields it conflicts with the meaning of a default.

The redesign therefore **removes `cliRequired` completely** from the public CLI API, traits, validation, examples, tests, and documentation. It is not kept as a deprecated alias.

Argument categories that need cardinality constraints should use category-specific concepts if those features are added later. For example, a repeated argument that must occur at least once would be better expressed as something like:

```d
@cliMinValues(1)
Array!String input;
```

rather than reviving a generic `cliRequired`.

---

## 6. Important exceptions: argument categories with natural absence semantics

"Plain fields are required" is specifically a rule for **value-taking scalar arguments**.

Some CLI argument categories naturally have a zero-occurrence state and should remain optional without needing `Option`.

### 6.1 Presence flags

```d
bool verbose;
```

retains ordinary presence-flag behavior:

```text
absent       -> false
--verbose    -> true
```

Requiring a presence-only flag would not be useful.

### 6.2 Count flags

```d
@cliCount
uint verbose;
```

naturally means:

```text
absent       -> 0
-v           -> 1
-vv          -> 2
-vvv         -> 3
```

Zero occurrences are intrinsic to the argument kind.

### 6.3 Repeated values

A repeated field such as:

```d
Array!String include;
```

should normally continue to mean zero-or-more.

If one-or-more is needed, that should eventually be expressed using a repeated-value-specific constraint rather than scalar requiredness.

### 6.4 Terminal arguments

`cliTerminal` is an optional trigger, including when the terminal field takes a value:

```d
@(cliTerminal, cliValueName("SHELL"))
CompletionShell completions;
```

Omitting `--completions` must not make the surrounding command invalid. Supplying it parses the value and produces the terminal outcome. Terminal arguments therefore have intrinsic zero-occurrence semantics and are excluded from derived requiredness.

---

## 7. Negatable booleans

Negatable booleans are a special and useful case because they represent an explicit two-way choice.

### 7.1 Required explicit choice

```d
@cliNegatable
bool color;
```

means:

```text
absent       -> parse error
--color      -> true
--no-color   -> false
```

This is useful when the application requires the user to choose explicitly.

Unlike an ordinary presence flag, a negatable boolean has two explicit spellings and therefore behaves like a two-valued scalar option.

### 7.2 Optional with a default

```d
@(cliNegatable, cliDefault)
bool color = true;
```

means:

```text
absent       -> true
--color      -> true
--no-color   -> false
```

Generated help can show:

```text
default: true
```

### 7.3 Optional while preserving user intent

```d
@cliNegatable
Option!bool color;
```

means:

```text
absent       -> none
--color      -> some(true)
--no-color   -> some(false)
```

This is a true three-state choice:

```text
no preference
explicitly enabled
explicitly disabled
```

| Declaration | absent | `--color` | `--no-color` |
|---|---|---|---|
| `@cliNegatable bool` | error | `true` | `false` |
| `@(cliNegatable, cliDefault) bool = true` | `true` | `true` | `false` |
| `@cliNegatable Option!bool` | `none` | `some(true)` | `some(false)` |

---

## 8. `cliDefault`: initialized D value as the default

`cliDefault` explicitly declares that the field's initialized D value is the CLI default.

```d
@cliDefault
uint jobs = 8;
```

Semantics:

```text
absent       -> jobs == 8
--jobs 16    -> jobs == 16
```

The attribute is important even though the field already has an initializer. It is the schema marker that tells XTB:

1. omission is valid;
2. the initialized field value is the semantic default;
3. generated help should render that default.

This avoids relying on unreliable reflection about whether the initializer was syntactically explicit.

It also handles defaults equal to `.init` correctly:

```d
@cliDefault
uint retries;
```

This intentionally means:

```text
absent -> retries == 0
```

The same principle applies to any compatible type whose `.init` value is intentionally the default.

---

## 9. Formatting `cliDefault` in generated help

A `cliDefault` value must be representable as CLI-facing text so generated help can show it.

```d
@(cliDefault, cliHelp("Number of parallel jobs"))
uint jobs = 8;
```

Help:

```text
--jobs <N>  Number of parallel jobs
            default: 8
```

For built-in CLI value types, XTB should use the canonical CLI representation.

Examples:

```text
uint        -> 8
bool        -> true
enum        -> release-safe
String      -> text
```

For a custom type, XTB should use its CLI-specific formatter if one exists. A `cliValueWith` formatter has priority over built-in/general formatting so the help spelling can match the custom parser's CLI domain.

The formatter shape is:

```d
static void format(
    ref Writer writer,
    scope const T* value,
) nothrow @nogc;
```

If there is no CLI-specific formatter, XTB falls back to the normal XTB `Writer` formatting machinery.

If the default cannot be formatted through either route, the schema should be rejected.

The important rule is:

> `cliDefault` stores a semantic D value, so help must format that value into a canonical CLI representation.

---

## 10. `cliHideDefault`: explicit help-display opt-out

`cliDefault` normally carries a help-generation contract: XTB should be able to render the semantic default as canonical CLI-facing text.

Sometimes the default is useful operationally but not worth exposing in generated help yet, or the type does not yet have a suitable formatter. In that case the schema can explicitly opt out:

```d
@(cliDefault, cliHideDefault)
MyType policy = ...;
```

This means:

- omission is valid;
- the initialized D value is still the semantic default;
- generated help does not show `default: ...`;
- no formatter is required solely for default visualization.

The attribute is help-only. It does not change parsing or runtime values.

`cliHideDefault` may also be used with `cliDefaultInput`:

```d
@(cliDefaultInput("automatic"), cliHideDefault)
Mode mode;
```

The fallback still parses `"automatic"` at runtime, but help omits the default line.

Using `cliHideDefault` without either default mechanism is a schema error because there is no default to hide.

The default behavior remains strict: `@cliDefault` without `cliHideDefault` requires a renderable default **when the argument itself is visible in help**. XTB should not silently omit an unformattable visible default because that would make help output depend on accidental formatting availability.

`cliHidden` is different: it hides the entire argument, so there is no default visualization to perform. A hidden `cliDefault` therefore does not require a formatter merely for help generation and does not also need `cliHideDefault`.

---

## 11. Parser-derived defaults: `cliDefaultInput`

Some CLI defaults are best expressed as CLI text rather than as a raw D value.

Example:

```d
@(
    cliValueWith!ByteSizeCli,
    cliDefaultInput("auto"),
)
ByteSize cacheBudget;
```

This means:

> If the user does not provide the option, parse `"auto"` through the same CLI parser that handles user input.

Conceptually:

```d
if (!seenCacheBudget)
{
    CliValueError error =
        ByteSizeCli.parse("auto", &cacheBudget);

    ...
}
```

If the custom parser understands:

```text
auto
64MiB
256MiB
1GiB
```

then `"auto"` remains the canonical default spelling without requiring XTB to invert the parsed representation.

---

## 12. `cliDefaultInput` is validated at runtime

The parser input declared by `cliDefaultInput` must **not** be parsed at compile time.

For example:

```d
@(
    cliValueWith!DurationCli,
    cliDefaultInput("30s"),
)
Duration timeout;
```

XTB does not require `DurationCli.parse` to be CTFE-capable.

The default is validated by actually running the parser at runtime when the fallback is needed.

This keeps custom parsers unrestricted by CTFE constraints and ensures the default uses exactly the same behavior as ordinary CLI input.

This is an explicit design decision:

> Parser-derived defaults are runtime-validated, not compile-time parsed.

The schema can still validate structural facts at compile time, such as:

- compatible field category;
- valid `parse` signature;
- conflicting default mechanisms;
- allocator requirements;
- whole-field versus element target.

But whether the literal default input is semantically accepted by a custom parser is determined at runtime.

---

## 13. Runtime failure of a default parser

Because `cliDefaultInput` is parsed at runtime, its parser can fail.

Example:

```d
@(
    cliValueWith!DurationCli,
    cliDefaultInput("nonsense"),
)
Duration timeout;
```

If `DurationCli.parse("nonsense", ...)` returns `invalid`, this is not a user-input error. The user did not provide `"nonsense"`; the application declared it.

The implemented policy distinguishes this from user input explicitly:

- `invalid` / `outOfRange` from a declared default produce `CliErrorKind.invalidDefault`;
- the diagnostic identifies the value as an **application default**, not as user input;
- the original `CliValueError` kind/message is retained for detail;
- `allocationFailed` remains `CliErrorKind.allocationFailed`, because it is a genuine runtime resource failure rather than a bad declared value.

The library therefore runtime-validates parser-derived defaults without misleadingly blaming the user for a broken application default.

---

## 14. Help rendering for `cliDefaultInput`

For a parser-derived default, generated help should display the declared CLI input, not the parsed D value.

```d
@(
    cliValueWith!ByteSizeCli,
    cliDefaultInput("auto"),
)
ByteSize budget;
```

Help:

```text
--budget <SIZE>
    default: auto
```

XTB must **not** do:

```text
"auto"
  -> parse
  -> ByteSize(0)
  -> format
  -> "0B"
```

and then show:

```text
default: 0B
```

That would lose the intended CLI semantics.

The rule is:

> `cliDefaultInput` displays the declared input spelling directly.

The parser and help therefore share one source of truth.

Whether leading/trailing whitespace should be rejected, preserved, or normalized for display is still open. The safest initial rule is to preserve the exact text and avoid hidden normalization.

---

## 15. The two default mechanisms are mutually exclusive

A field may have either:

```d
@cliDefault
```

or:

```d
@cliDefaultInput("...")
```

but never both.

Invalid:

```d
@(
    cliDefault,
    cliDefaultInput("16"),
)
uint jobs = 8;
```

There is no useful precedence rule.

The two attributes represent different sources of truth:

```text
cliDefault
    -> initialized D value is authoritative

cliDefaultInput
    -> CLI input text is authoritative
```

Allowing both would create ambiguity and should be a compile-time schema error.

---

## 16. Defaults and `Option!T` are mutually exclusive

The invariant for `Option!T` is that absence remains observable after a successful parse.

Therefore these should be invalid:

```d
@cliDefault
Option!uint jobs;
```

```d
@cliDefaultInput("8")
Option!uint jobs;
```

If omission always turns into a value, then `Option` no longer communicates anything useful.

Use:

```d
@cliDefault
uint jobs = 8;
```

or:

```d
@cliDefaultInput("8")
uint jobs;
```

instead.

This preserves the strong rule:

> `Option!T` means successful parsing can genuinely produce `none`.

---

## 17. Grouped custom CLI value representation

Parsing and formatting a custom CLI value are two sides of the same representation.

Instead of separate attributes such as:

```d
@(cliParseWith!parseDuration, cliFormatWith!formatDuration)
Duration timeout;
```

the preferred design is to group the behavior into one statically typed definition.

Example:

```d
struct DurationCli
{
    static CliValueError parse(
        scope String input,
        Duration* output,
    ) nothrow @nogc
    {
        ...
    }

    static void format(
        ref Writer writer,
        scope const Duration* value,
    ) nothrow @nogc
    {
        ...
    }
}
```

Applied as:

```d
@cliValueWith!DurationCli
Duration timeout;
```

This says:

> `DurationCli` defines the CLI representation of `Duration`.

That is more coherent than maintaining unrelated parser and formatter callbacks.

---

## 18. Proposed `cliValueWith`

The preferred field-level customization is:

```d
@cliValueWith!DurationCli
Duration timeout;
```

A value representation definition is a normal D type with static functions.

At minimum:

```d
struct DurationCli
{
    static CliValueError parse(
        scope String input,
        Duration* output,
    ) nothrow @nogc;
}
```

Formatting is optional:

```d
struct DurationCli
{
    static CliValueError parse(...);

    static void format(
        ref Writer writer,
        scope const Duration* value,
    ) nothrow @nogc;
}
```

No interface, base class, TypeInfo, runtime reflection, or dynamic dispatch is needed. The contract is structural and verified at compile time.

This is appropriate for XTB's `-betterC` design.

---

## 19. Allocator-backed custom parsing

The existing allocator inference model should be preserved.

A custom representation may define:

```d
struct BigValueCli
{
    static CliValueError parse(
        scope String input,
        Allocator* allocator,
        BigValue* output,
    ) nothrow @nogc;
}
```

XTB inspects the parser signature and infers that an allocator is required.

No generic parse context object is introduced.

This keeps custom parsing explicit and low-cost.

---

## 20. Whole-field versus element parsing remains signature-driven

The existing custom-parser design infers whether a parser applies to a whole field or to individual repeated elements from the parser target type.

That should remain unchanged under `cliValueWith`.

Example:

```d
struct PortCli
{
    static CliValueError parse(
        scope String input,
        Port* output,
    ) nothrow @nogc;
}

@cliValueWith!PortCli
Array!Port ports;
```

Because the parser targets `Port*`, each repeated argument parses one `Port`.

By contrast:

```d
struct PortListCli
{
    static CliValueError parse(
        scope String input,
        Allocator* allocator,
        Array!Port* output,
    ) nothrow @nogc;
}

@cliValueWith!PortListCli
Array!Port ports;
```

targets the entire field.

The existing inference is expressive and should not be replaced by an extra scalar/element policy attribute.

---

## 21. Formatting custom values

When XTB needs a canonical CLI representation of a value, resolution should be:

1. If `cliValueWith!Representation` provides `format`, use it.
2. Otherwise use the normal XTB formatting machinery.
3. If neither works, reject the schema when formatting is required.

Example:

```d
struct ByteSizeCli
{
    static CliValueError parse(...);

    static void format(
        ref Writer writer,
        scope const ByteSize* value,
    ) nothrow @nogc
    {
        ...
    }
}

@(
    cliValueWith!ByteSizeCli,
    cliDefault,
)
ByteSize cache = mib(256);
```

Generated help may show:

```text
default: 256MiB
```

even if the generic D representation would otherwise be something like:

```text
ByteSize(268435456)
```

The CLI formatter defines the canonical CLI-facing spelling.

---

## 22. Parser and formatter relationship

For a representation that provides both directions:

```text
CLI text --parse--> T
CLI text <--format-- T
```

The formatter should ideally produce a canonical spelling accepted by the parser.

It does **not** need to reproduce the user's exact original input.

For example:

```text
256mb
256MiB
268435456
```

could all parse to the same value, while formatting always emits:

```text
256MiB
```

That canonicalization is desirable.

The contract should encourage:

```text
parse(format(value))
```

to reproduce an equivalent value whenever formatting is defined.

This does not need to be mechanically enforced by the library.

---

## 23. `cliDefault` with a custom representation

Example:

```d
@(
    cliValueWith!DurationCli,
    cliDefault,
)
Duration timeout = Duration.seconds(30);
```

Behavior:

```text
absent
    -> use initialized Duration value

help
    -> DurationCli.format(defaultValue)
    -> "30s"
```

The default is semantic. The formatter converts it into the canonical CLI spelling for help.

---

## 24. `cliDefaultInput` with a custom representation

Example:

```d
@(
    cliValueWith!DurationCli,
    cliDefaultInput("infinite"),
)
Duration timeout;
```

Behavior:

```text
absent
    -> DurationCli.parse("infinite", &timeout)

help
    -> default: infinite
```

Importantly, help does not call `DurationCli.format` for this default. The attribute text is the authoritative representation.

---

## 25. Why a grouped representation is preferred over separate hooks

The grouped definition:

```d
struct DurationCli
{
    static CliValueError parse(...);
    static void format(...);
}
```

has several advantages.

### 24.1 Cohesion

Parsing and formatting describe the same CLI value domain. Keeping them together makes that relationship explicit.

### 24.2 Reuse

One representation can be reused across fields:

```d
@cliValueWith!ByteSizeCli
ByteSize cacheLimit;

@cliValueWith!ByteSizeCli
ByteSize uploadLimit;

@(cliValueWith!ByteSizeCli, cliDefault)
ByteSize memoryLimit = mib(256);
```

### 24.3 Extensibility

A parser-only definition can later gain formatting without changing every use site.

### 24.4 Fewer customization mechanisms

`cliValueWith` replaces the former `cliParseWith` customization and avoids introducing a separate `cliFormatWith` hook.

This avoids having several overlapping ways to customize the same concept.

---

## 26. Default/requiredness matrix

For value-taking scalar fields:

| Schema | Required? | Omission result | Help default |
|---|---:|---|---|
| `T` | yes | error | none |
| `Option!T` | no | `none` | none |
| `@cliDefault T` | no | initialized D value | formatted D value |
| `@(cliDefault, cliHideDefault) T` | no | initialized D value | hidden |
| `@cliDefaultInput("x") T` | no | parse `"x"` at runtime | literal `"x"` |
| `@(cliDefaultInput("x"), cliHideDefault) T` | no | parse `"x"` at runtime | hidden |

For negatable booleans:

| Schema | Omission |
|---|---|
| `@cliNegatable bool` | error |
| `@cliNegatable Option!bool` | `none` |
| `@(cliNegatable, cliDefault) bool = true` | `true` |
| `@(cliNegatable, cliDefault) bool = false` | `false` |

For intrinsic zero-occurrence categories:

```d
bool verbose;
@cliCount uint verbose;
Array!T repeated;
@cliTerminal T terminalValue;
```

absence retains the category's natural zero-occurrence semantics.

---

## 27. Invalid combinations

The following should be compile-time schema errors.

### Two defaults

```d
@(cliDefault, cliDefaultInput("8"))
uint jobs;
```

### Default plus `Option`

```d
@cliDefault
Option!uint jobs;
```

```d
@cliDefaultInput("8")
Option!uint jobs;
```

### Defaults on intrinsic zero-occurrence/terminal categories

Defaults are rejected on repeated arrays, `@cliCount`, ordinary named bool presence flags, and `@cliTerminal`. Those categories already have intrinsic occurrence semantics or terminal-presence semantics, so a fallback default would be misleading.

### `cliHideDefault` without a default

```d
@cliHideDefault
uint jobs;
```

This is invalid because there is no default to hide.

### Required hidden argument

```d
@cliHidden
String secret;
```

This is invalid because the scalar is required but generated help intentionally provides no way to discover it. `cliHidden` is only valid for fields that are omittable through their intrinsic category, `Option!T`, or a declared default. Hidden positionals must also be omitted from usage rendering.

A hidden semantic default does not require a formatter solely for help visualization because the entire argument is absent from help.

### Invalid custom representation

```d
@cliValueWith!BrokenCli
Duration timeout;
```

where `BrokenCli` does not expose a supported `parse` signature.

### `cliDefault` with no available formatter

If a custom value cannot be converted to a CLI-facing representation, `cliDefault` cannot truthfully advertise its default. The schema should fail rather than silently omit or display a misleading internal representation.

---

## 28. When defaults are applied

D-value defaults and parser-input defaults differ operationally.

### `cliDefault`

The D initializer already exists as part of aggregate initialization. No parser work is needed when the argument is absent.

### `cliDefaultInput`

The fallback parser should be invoked only when the parser reaches the stage where a complete normal invocation is being finalized.

It should not be eagerly invoked before parsing argv.

In particular, built-in help/version and terminal early-exit paths should not unnecessarily run fallback parsers or allocate fallback values.

Conceptually:

```text
construct parsed tree
    |
parse argv
    |
terminal/help/version?
    | yes
    +----> return partial/builtin outcome
    |
apply unseen cliDefaultInput fallbacks
    |
validate required scalar fields
    |
validate relationships/groups
    |
return successful invocation
```

The exact ordering relative to future argument relationships should be reviewed when those features are implemented.

---

## 29. Partial parse trees and defaults

XTB already exposes partial typed state for some non-normal outcomes such as terminal arguments.

Parser-derived defaults should not necessarily be present in those partial trees.

For example:

```text
tool --print-schema
```

should be allowed to terminate parsing without invoking unrelated `cliDefaultInput` parsers.

This is consistent with the existing idea that `result.parsed` may represent a partial parse tree while `result.invocation` represents a successfully completed invocation.

---

## 30. Diagnostics

Required-by-default changes some diagnostics.

A missing ordinary scalar should produce a direct missing-value diagnostic without requiring `cliRequired`.

Example:

```d
String registry;
```

and:

```text
tool publish
```

should report something equivalent to:

```text
error: required option '--registry' was not provided
```

Generated help communicates requiredness structurally. The required named
option appears explicitly in usage and in a dedicated section:

```text
Usage: tool publish --registry <REGISTRY> [OPTIONS]

Required options:
  --registry <REGISTRY>  Package registry
```

`[OPTIONS]` therefore means the remaining omittable options; it does not hide
required named options.

For parser-input default failure, diagnostics identify that the application declared an invalid default rather than blaming user input. `invalid` and `outOfRange` become `CliErrorKind.invalidDefault`; `allocationFailed` remains an allocation failure.

---

## 31. Help generation consequences

The richer help renderer naturally fits the new model.

### Required scalar

```d
String output;
```

```text
Usage: tool build --output <PATH> [OPTIONS]

Required options:
  --output <PATH>  Output path
```

### Semantic default

```d
@cliDefault
uint jobs = 8;
```

```text
--jobs <N>  Number of parallel jobs
            default: 8
```

### Parser-input default

```d
@cliDefaultInput("auto")
ByteSize budget;
```

```text
--budget <SIZE>  Cache budget
                 default: auto
```

### Optional absence

```d
Option!String compiler;
```

No `required` or `default` metadata is needed. The field is simply optional.

---

## 32. Possible values and defaults

Existing possible-value help should compose naturally with the new defaults.

Example:

```d
@(cliDefault, cliHelp("Build mode"))
BuildMode mode = BuildMode.debug_;
```

Help:

```text
--mode <MODE>  Build mode
               values: debug, release-safe, release-fast
               default: debug
```

For a custom parser:

```d
@(
    cliValueWith!CacheBudgetCli,
    cliPossibleValues!("auto", "64MiB", "256MiB", "1GiB"),
    cliDefaultInput("auto"),
)
CacheBudget budget;
```

Help:

```text
--cache-budget <SIZE>  Cache budget
                       values: auto, 64MiB, 256MiB, 1GiB
                       default: auto
```

No attempt is made to infer possible values from arbitrary custom parsers.

---

## 33. Interaction with aliases and negatable help

Requiredness/default metadata remains secondary to canonical spellings.

Example:

```d
@(
    cliAliasName("colour"),
    cliNegatable,
    cliDefault,
)
bool color = true;
```

Help:

```text
-c, --color  Use colored output
             aliases: --colour
             negatable: --no-color
             default: true
```

If no default exists:

```d
@(cliAliasName("colour"), cliNegatable)
bool color;
```

help makes the two-way requirement structural:

```text
Usage: tool (--color|--no-color) [OPTIONS]

Required options:
  --color  Use colored output
           aliases: --colour
           negatable: --no-color
```

The user must explicitly provide either the positive or negative spelling.

---

## 34. Implemented API transition

The redesign has been implemented. The current model is:

```d
plain T                 // required scalar
Option!T                // optional
cliDefault
cliDefaultInput("...")
cliHideDefault
cliValueWith!Representation
```

`cliRequired` and `cliParseWith` have been removed. Requiredness is derived from
the schema, and `cliValueWith` is the single custom CLI-value representation
hook.

---

## 35. Implementation strategy

The implementation should keep the current compile-time-schema philosophy.

### Compile-time responsibilities

Traits should determine:

- argument category;
- whether the field is `Option!T`;
- whether the field has `cliDefault`;
- whether it has `cliDefaultInput`;
- whether it has `cliHideDefault`;
- whether it has `cliValueWith`;
- whether the custom representation's parser signature is valid;
- whether an allocator is required;
- whether the parser targets the field or repeated element type;
- whether formatting is available when `cliDefault` needs it;
- whether incompatible attributes are combined.

### Runtime responsibilities

Runtime parsing should determine:

- whether the user supplied the field;
- parsed user values;
- parser-input fallback values;
- allocation failure;
- custom-parser semantic failure;
- final required-value validation;
- future relationship/group validation.

No custom parser is invoked at compile time merely to validate default input.

---

## 36. Parser bookkeeping

Requiredness must not be inferred from the current field value.

For example:

```d
uint port;
```

may hold `0` both before parsing and after the user explicitly enters:

```text
--port 0
```

The parser therefore needs independent "seen" bookkeeping.

Conceptually:

```text
field storage
    port = 0

parser metadata
    portWasProvided = false/true
```

This is already conceptually necessary for duplicate detection and should remain separate from application values.

For `cliDefault`, omission is valid because the field already contains its initialized value.

For `cliDefaultInput`, omission triggers the fallback parser.

For plain scalar `T`, omission is an error.

When a child command is selected successfully, the parent frame must still be finalized afterward. Parent required fields and parser-derived defaults therefore remain authoritative even when argv descends into a child command. Built-in/terminal/error outcomes still stop before that normal finalization path.

---

## 37. Design principles

### The declaration should communicate semantics

Prefer:

```d
String output;
Option!String compiler;

@cliDefault
uint jobs = 8;
```

over a design where requiredness and default semantics are mostly external annotations.

### Absence should have one clear representation

`Option!T` means absence survives successful parsing.

Defaults mean absence does not survive because a value replaces it.

Do not combine them.

### Defaults should have one source of truth

Use either:

```d
@cliDefault
```

or:

```d
@cliDefaultInput(...)
```

never both.

### Parsing and formatting belong to one CLI representation

Use:

```d
cliValueWith!Representation
```

rather than independent parser/formatter hooks where possible.

### Runtime parsers stay runtime parsers

Do not impose CTFE requirements merely to validate defaults.

### Help should reflect actual CLI semantics

Display semantic defaults using canonical CLI formatting.

Display parser-input defaults using the declared CLI spelling.

Do not attempt lossy inversion of custom parser values.

When a visible semantic default should intentionally not appear in help, require the explicit `cliHideDefault` opt-out rather than silently omitting it. If `cliHidden` hides the entire field, no separate default-visualization opt-out is necessary.

---

## 38. Remaining presentation details

The core semantics in this document are settled. Generated help currently makes
requiredness structural: required named options are explicit in `Usage:` and
split into `Required options:` / `Required global options:` sections. Named
required options do not also receive a redundant `required` metadata line.
Required positionals continue to use `<NAME>` in usage and may retain positional
required metadata in their detailed argument block.

The following small presentation details can still be revisited independently
without changing requiredness/default semantics.

### Empty/default input strings

Should this be valid?

```d
@cliDefaultInput("")
String value;
```

Probably yes if the parser accepts it.

The attribute should not impose arbitrary normalization that changes parser semantics.

### Whitespace

Should:

```d
@cliDefaultInput(" auto ")
```

display exactly that text, normalize it for help, or be rejected?

The cleanest invariant is probably to preserve the exact input text and avoid hidden normalization.


---

## 39. Recommended direction

The preferred final model is:

```d
struct DurationCli
{
    static CliValueError parse(
        scope String input,
        Duration* output,
    ) nothrow @nogc
    {
        ...
    }

    static void format(
        ref Writer writer,
        scope const Duration* value,
    ) nothrow @nogc
    {
        ...
    }
}

struct Args
{
    // Required scalar.
    String output;

    // Optional and preserves absence.
    Option!String compiler;

    // Optional semantic default.
    @cliDefault
    uint jobs = 8;

    // Required explicit two-way choice.
    @cliNegatable
    bool color;

    // Optional semantic two-way default.
    @(cliNegatable, cliDefault)
    bool diagnostics = true;

    // Optional custom semantic default.
    @(
        cliValueWith!DurationCli,
        cliDefault,
    )
    Duration timeout = Duration.seconds(30);

    // Optional parser-derived default.
    @(
        cliValueWith!DurationCli,
        cliDefaultInput("infinite"),
    )
    Duration idleTimeout;

    // Optional semantic default intentionally omitted from help.
    @(cliDefault, cliHideDefault)
    InternalPolicy policy = defaultInternalPolicy();
}
```

This schema communicates most of its behavior without additional requiredness annotations.

That is the main goal of the redesign.

---

## 40. Summary

The design moves XTB CLI from:

```text
everything is optional unless cliRequired says otherwise
```

to:

```text
plain scalar T
    -> required

Option!T
    -> optional, absence preserved

cliDefault + T
    -> optional, initialized D value is the default

cliDefaultInput("...") + T
    -> optional, fallback text is parsed at runtime
```

with sensible exceptions for intrinsic zero-occurrence argument categories such as presence flags, count flags, repeated arguments, and terminal triggers.

Custom CLI parsing and formatting are grouped through a reusable representation:

```d
@cliValueWith!Representation
T value;
```

where the representation provides:

```d
static CliValueError parse(...);
static void format(...); // optional
```

`cliDefault` formats the semantic default through the CLI representation or normal XTB formatting.

`cliDefaultInput` displays its literal parser input and validates it only when parsed at runtime.

The implemented model removes `cliRequired` entirely, adds `cliHideDefault` as an explicit help-only escape hatch, and makes ordinary CLI schemas much more self-describing.
