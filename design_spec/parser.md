# Parser Combinator Library

## Purpose

`xtb.parser` is an arena-backed parser-combinator library for BetterC programs.
It is intended for reusable grammars, predictable backtracking, explicit output
allocation, structured errors, and good editor discoverability.

The implementation must remain compatible with the project-wide constraints:

- `-betterC`;
- no garbage collector dependency;
- no exceptions;
- no `TypeInfo`, classes, or runtime reflection;
- explicit allocation and ownership;
- parser execution is `@nogc` and `nothrow`;
- checked-only programmer contracts use `version (XTB_Checked)`;
- malformed input is an ordinary parse failure and never a panic/contract;
- primary combinators are real members rather than UFCS-only adapters.

No public parser API is named `init`. Factory operations use `create`, matching
XTB's owning-type conventions and avoiding ambiguity with D's `T.init` value.

## Core model

A parser grammar and its parse output have separate lifetimes:

```text
Grammar
  |
  +-- parser Arena
      +-- literal nodes
      +-- sequence nodes
      +-- choice nodes
      +-- mapping nodes
      +-- recursive rules
      +-- expression-table nodes

Parser invocation
  |
  +-- ParseState on the caller stack
  +-- borrowed source text
  +-- optional ParseContext
          |
          +-- output Arena for ASTs/collections/decoded strings
```

`Grammar` owns all parser nodes. `Parser!T` is a small non-owning handle into
that graph. Constructing a grammar allocates parser nodes from the grammar
arena; executing an already-built parser does not allocate parser machinery.

An operation such as `.collect()` or a semantic action that calls
`context.outputArena.create!T()` explicitly requests output allocation.

This distinction is intentional:

```d
Grammar grammar = Grammar.create(mallocAllocator());
auto parser = grammar.integer!int().before(grammar.eof());

// No parser allocation occurs here.
auto result = parser.parse("42");
```

Compared with:

```d
auto parser = grammar.integer!int()
    .sepBy(grammar.value(','))
    .collect();

Arena output = Arena.create(mallocAllocator());
ParseContext context = ParseContext.create(&output);

// `.collect()` explicitly requests output storage.
auto result = parser.parse("1,2,3", &context);
```

## Package layout

```text
source/xtb/parser/
├── package.d
├── parser.d
├── expression.d
├── json.d
└── arithmetic.d
```

The public import is:

```d
import xtb.parser;
```

`parser.d` contains the fundamental parser handle and common combinators.
`expression.d` contains operator-precedence construction. `json.d` and
`arithmetic.d` are proving grammars and useful parsers built on the public
combinator layer.

## Fundamental types

### `FailureKind`

| Value | Meaning |
|---|---|
| `recoverable` | An enclosing `choice` may try another alternative. |
| `committed` | The current interpretation has consumed/committed enough input that another alternative must not be tried. |

The default rule is:

> Failure before consuming input is recoverable. Failure after consuming input
> is committed.

This behavior prevents hidden unlimited backtracking and generally gives better
error locations.

### `ParseErrorKind`

| Value | Meaning |
|---|---|
| `none` | No error. |
| `expected` | A syntax item was expected. |
| `invalidSyntax` | Input matched the production category but is malformed. |
| `depthLimit` | Reserved for parsers enforcing an explicit depth bound. |
| `numberOutOfRange` | A syntactically valid number cannot be represented by the requested type. |

### `ParseError`

A parse error is structural rather than preformatted:

```d
struct ParseError
{
    ParseErrorKind kind;
    size_t offset;
    ExpectedSet expected;
    String parserName;
    String context;
}
```

The parser tracks the failure furthest into the input. Expectations at the same
furthest offset are merged up to the fixed expectation capacity. Error tracking
must not allocate.

Line/column computation and styled diagnostics belong outside the hot parse
path.

### `ParseContext`

```d
struct ParseContext
{
    Arena* outputArena;
    void* userData;

    static ParseContext create(
        Arena* outputArena = null,
        void* userData = null,
    );
}
```

`outputArena` is used only by operations that explicitly need owned output,
such as `.collect()`, JSON escape decoding, or AST semantic actions.

`userData` lets an application provide additional state without making every
`Parser!T` type depend on an application context type.

### `ParseState`

`ParseState` owns no input. It keeps a borrowed input slice, the current byte
offset, best structural error, parse context, and the internal cut generation.

```d
ParseState state = ParseState.create(input, &context);
auto result = parser.parse(state);
```

Most users should call `parser.parse(input, context)` directly.

### `ParseResult!T`

```d
struct ParseResult(T)
{
    T value;
    ParseError error;
    bool success;
    FailureKind failureKind;
    size_t offset;

    bool ok();
    bool failed();
}
```

Malformed input is represented only through this result/error path.

## Grammar API

`Grammar` is an owning type backed by `Arena`.

```d
Grammar grammar = Grammar.create(
    mallocAllocator(),
    64 * 1024,
);
```

The zero state is safe to destroy. Copying is disabled.

### Primitive parser creation

| API | Result | Description |
|---|---|---|
| `any()` | `Parser!char` | Consume one input byte. |
| `value(c)` | `Parser!char` | Match one exact byte. |
| `literal(text)` | `Parser!String` | Match exact text and return the borrowed matched slice. |
| `satisfy!predicate(name)` | `Parser!char` | Match one byte satisfying a static predicate. |
| `oneOf(chars)` | `Parser!char` | Match one listed byte. |
| `noneOf(chars)` | `Parser!char` | Match one byte not in the set. |
| `take(count)` | `Parser!String` | Consume exactly `count` bytes. |
| `takeWhile!predicate(name)` | `Parser!String` | Consume zero or more matching bytes. |
| `takeWhile1!predicate(name)` | `Parser!String` | Consume one or more matching bytes. |
| `eof()` | `Parser!Unit` | Require end of input. |
| `identifier()` | `Parser!String` | Parse an ASCII identifier. |
| `integer!T()` | `Parser!T` | Parse a signed/unsigned integral value. |
| `floating!T()` | `Parser!T` | Parse a finite decimal floating value. |
| `asciiWhitespace0()` | `Parser!String` | Parse zero or more ASCII whitespace bytes. |
| `asciiWhitespace1()` | `Parser!String` | Parse one or more ASCII whitespace bytes. |
| `digit()` | `Parser!char` | Parse one ASCII decimal digit. |
| `hexDigit()` | `Parser!char` | Parse one ASCII hexadecimal digit. |

Static predicates and mappings should be module/static functions. Function-local
capturing lambdas are intentionally not the common API because they create
closure-context and attribute problems under BetterC.

### Choice

```d
auto value = grammar.choice(
    integer,
    identifier,
    parenthesized,
);
```

Every alternative must produce the same `Parser!T` result type. Alternatives
are tried in declaration order until one succeeds or produces a committed
failure.

### Recursive rules

```d
auto expression = grammar.rule!(Expr*)("expression");

// The handle can be referenced before definition.
auto parenthesized = expression.parser.between(lparen, rparen);

expression.define(...);
```

A `Rule!T` may be defined once. Undefined use and duplicate definition are
programmer errors checked only under `XTB_Checked`.

## Parser member combinators

The parser API intentionally uses real members. This improves code-d/serve-d
completion and go-to-definition compared with a large UFCS free-function
surface.

### Sequencing

| API | Result | Semantics |
|---|---|---|
| `a.then(b)` | `Parser!(Pair!(A, B))` | Parse both and retain both values. |
| `a.before(b)` | `Parser!A` | Parse `a`, then `b`, retain only `a`. |
| `a.after(b)` | `Parser!B` | Parse `a`, then `b`, retain only `b`. |
| `p.between(left, right)` | `Parser!T` | Parse `left`, `p`, `right`, retain only `p`. |

Examples:

```d
expression.before(semicolon);
```

parses `<expression> ;` and returns the expression.

```d
equal.after(expression);
```

parses `= <expression>` and returns the expression.

```d
expression.between(lparen, rparen);
```

parses `( <expression> )` and returns the expression.

### Transformation

| API | Description |
|---|---|
| `map!function()` | Transform a successful result with a static semantic action. |
| `mapTuple!Aggregate()` | Flatten nested `Pair` values into aggregate fields. |
| `where!predicate(expectation)` | Reject a successful value that fails a semantic predicate. |
| `replace(value)` | Replace a successful result with a fixed value. |
| `skip()` | Replace success output with `Unit`. |
| `named(name)` | Replace low-level expectations with a parser-level diagnostic name. |
| `context(name)` | Attach higher-level error context. |
| `peek()` | Parse without retaining input consumption. |

A mapping may have either form:

```d
U mapValue(T value);
```

or:

```d
U mapValue(ref ParseContext context, T value);
```

The second form is appropriate for AST construction:

```d
Expr* makeNumber(ref ParseContext context, double value)
{
    Expr* result = context.outputArena.create!Expr();
    result.kind = ExprKind.number;
    result.number = value;
    return result;
}
```

## Optional and repetition

### Optional

```d
parser.optional(); // Parser!(Option!T)
```

- success -> `some(value)`;
- recoverable failure -> `none`;
- committed failure -> propagated failure.

### Repetition

`repeat()` and `repeat1()` return a repetition builder rather than immediately
allocating a result array.

| API | Meaning |
|---|---|
| `.repeat().skip()` | Recognize zero or more and discard values. |
| `.repeat1().skip()` | Recognize one or more and discard values. |
| `.repeat().fold(initial)` | Aggregate without storing every element. |
| `.repeat().collect()` | Explicitly collect into `ParseContext.outputArena`. |

Separated repetition uses the same model:

```d
item.sepBy(comma).collect();
item.sepBy1(comma).skip();
```

A successful repeated parser must make input progress. Checked builds report a
programmer invariant violation if a repeated parser succeeds without consuming
input. Release-fast still terminates defensively so a zero-width parser cannot
create an infinite loop.

## Backtracking and commitment

### Default behavior

A parser invocation records its starting offset and cut generation. If a parser
fails recoverably but has consumed input or crossed a cut, the failure is
upgraded to committed.

Therefore:

```d
auto statement = grammar.choice(
    assignment,
    expressionStatement,
);
```

with:

```d
assignment = identifier.before(equal).then(expression);
```

will not try `expressionStatement` after `assignment` consumed an identifier
and then failed to find `=`.

### `attempt()`

```d
assignment.attempt()
```

means:

> This interpretation is speculative. If it fails without crossing a `cut`,
> restore the starting offset and expose a recoverable failure.

Typical use:

```d
auto primary = grammar.choice(
    call.attempt(),
    identifierExpression,
);
```

Both calls and identifiers begin with an identifier, so call parsing is
speculative until enough syntax distinguishes it.

### `cut()`

```d
lparen.cut()
```

means:

> After this parser succeeds, failures deeper in this interpretation stay
> committed even through an enclosing `attempt()`.

Example:

```d
auto call = identifier.then(
    arguments.between(
        lparen.cut(),
        rparen,
    ),
);
```

`foo` may fall back to an identifier. `foo(` is definitively a call and a
missing argument/`)` is reported as a call error rather than rewinding to the
identifier alternative.

## Tokenizer

`Tokenizer` wraps common lexical parsers so they consume trailing trivia:

```d
auto trivia = grammar.asciiWhitespace0().skip();
auto token = grammar.tokenizer(trivia);

auto lparen = token.literal("(");
auto identifier = token.identifier();
auto integer = token.integer!int();
```

`keyword(text)` additionally requires an identifier boundary, so
`keyword("let")` does not accept `letter`.

The tokenizer is not a separate lexing pass and does not allocate a token
array.

## Operator precedence

`ExpressionTable!(T, BinaryOp, UnaryOp)` implements precedence parsing over an
existing primary parser.

```d
auto operators = grammar.expressionTable!(
    Expr*,
    BinaryOp,
    UnaryOp,
)();
```

Earlier calls to `level()` bind more tightly.

### Level API

| API | Semantics |
|---|---|
| `.prefix(parser, op)` | Prefix unary operator. |
| `.postfix(parser, op)` | Postfix unary operator. |
| `.left(parser, op)` | Left-associative binary operator. |
| `.right(parser, op)` | Right-associative binary operator. |
| `.nonassoc(parser, op)` | Binary operator that may occur at most once at that level. |

All binary operators in one level must share associativity. That is a grammar
construction invariant enforced under `XTB_Checked`.

Example:

```d
operators.level()
    .prefix(token.literal("+"), UnaryOp.positive)
    .prefix(token.literal("-"), UnaryOp.negative);

operators.level()
    .left(token.literal("*"), BinaryOp.multiply)
    .left(token.literal("/"), BinaryOp.divide);

operators.level()
    .left(token.literal("+"), BinaryOp.add)
    .left(token.literal("-"), BinaryOp.subtract);
```

Then:

```d
expression.define(
    operators.build!(makeBinary, makeUnary)(primary.parser),
);
```

The implementation also supports right-associative and non-associative levels;
tests specifically assert `2 ^ 3 ^ 2` is parsed right-associatively and reject
`1 < 2 < 3` for a non-associative comparison level.

## Real-world arithmetic grammar

`xtb.parser.arithmetic` is a proving grammar for the expression-table API.
It parses:

- decimal numbers;
- identifiers;
- parentheses;
- repeated prefix `+`/`-`;
- left-associative `*`/`/`;
- left-associative `+`/`-`.

It produces arena-owned `ArithmeticExpression` nodes. `ArithmeticExpression` is a tagged union: its `kind` discriminant selects exactly one payload arm (`number`, `identifier`, `unary`, or `binary`). The payloads are trivially destructible and arena-owned, so no active-member destructor bookkeeping is required.

```d
Grammar grammar = Grammar.create(mallocAllocator());
Parser!(ArithmeticExpression*) parser = arithmeticExpression(&grammar);

Arena output = Arena.create(mallocAllocator());
ParseContext context = ParseContext.create(&output);

auto result = parser.parse("2 + 3 * 4", &context);
assert(result.ok);

ArithmeticExpression* root = result.value;
assert(root.kind == ArithmeticExpressionKind.binary);
assert(root.binary.operation == ArithmeticBinaryOperator.add);
assert(root.binary.right.kind == ArithmeticExpressionKind.binary);
assert(root.binary.right.binary.operation == ArithmeticBinaryOperator.multiply);
```

That tree shape proves multiplication binds tighter than addition; it is not
merely an evaluation test that could accidentally hide a precedence bug.

The test suite also asserts:

```text
(2 + 3) * 4     parentheses override precedence
20 / 5 / 2      division associates left
-x * +2         unary operators bind tighter than multiplication
--3             prefix operators nest
```

## Real-world JSON grammar

`xtb.parser.json` builds an RFC 8259-style JSON document parser from the common
combinators. `JsonValue` is a tagged union: its `kind` discriminant selects exactly one payload arm (`boolean`, `number`, `string`, `array`, or `object`), while `null_` carries no payload. Strings and collection slices are borrowed or arena-owned and require no per-variant destruction.

Structural JSON parsing uses:

- recursive `Rule!JsonValue`;
- `choice` for JSON value alternatives;
- `between` for arrays/objects;
- `sepBy(...).collect()` for arrays and object members;
- `cut()` after `[` and `{` so malformed containers remain committed;
- `map` and `mapTuple` for AST construction.

Only JSON string escape/Unicode decoding is implemented as a custom lexical
node because it is specialized byte-level work.

Usage:

```d
Grammar grammar = Grammar.create(mallocAllocator());
Parser!JsonValue parser = jsonDocument(&grammar);

Arena output = Arena.create(mallocAllocator());
ParseContext context = ParseContext.create(&output);

String source = `{
    "name": "xtb",
    "enabled": true,
    "numbers": [1, 2, 3]
}`;

auto result = parser.parse(source, &context);
assert(result.ok);

const JsonValue* name = findMember(&result.value, "name");
assert(name !is null);
assert(name.kind == JsonKind.string);
assert(name.string == "xtb");
```

JSON decoded strings, array storage, and object-member storage use the output
arena. The parser supports JSON escapes, Unicode BMP escapes, surrogate pairs,
UTF-8 input, finite JSON numbers, nested arrays, and nested objects.

Malformed input remains a parse failure. Tests cover at least:

```text
leading-zero numbers       01
missing fraction digit     1.
missing exponent digit     1e
array trailing comma       [1,]
object trailing comma      {"a":1,}
unquoted object key        {a:1}
invalid escape             "bad\xescape"
unpaired high surrogate    "\uD800"
unpaired low surrogate     "\uDC00"
raw control/newline        "line<newline>break"
trailing document data     true false
unterminated containers    [   {
```

## Allocation decisions

### Grammar construction

All combinator nodes are allocated from `Grammar.arena` using the typed Arena
API:

```d
Node* node = grammar.arena.create!Node(...);
```

Parser handles themselves are small copied values and do not own those nodes.

### Parse execution

Normal primitives, sequencing, choice, `attempt`, `cut`, `optional`, `peek`,
and folding operate on stack state and borrowed input only.

### Explicit output allocation

`.collect()` uses `ParseContext.outputArena` and stores a returned slice with its
length. Semantic actions may use:

```d
T* value = context.outputArena.create!T(args);
```

or:

```d
T[] values = context.outputArena.allocateArray!T(length);
```

according to whether they need object construction or raw array storage.

Arena cleanup does not invoke destructors for individually created objects, so
AST/parser output types must follow normal arena-lifetime rules.

## Checked builds

Parser programmer contracts follow the repository build modes:

```text
debug          XTB_Checked enabled
release-safe   XTB_Checked enabled
release-fast   XTB_Checked absent
```

Examples of checked-only programmer invariants:

- combining parsers from different grammars;
- invoking an invalid parser handle;
- defining a rule twice;
- invoking an undefined rule;
- collecting without an output arena;
- expression operators from another grammar;
- mixed binary associativity inside one precedence level;
- zero-width parser success during repetition.

Each contract is guarded at the call site with `version (XTB_Checked)` so its
condition is not evaluated in release-fast.

Input validation is not a checked-only contract. Malformed source must still
produce deterministic parse failure in release-fast.

## Public API summary

### `Grammar`

| Category | API |
|---|---|
| Ownership | `create`, `deinit`, `allocator`, `arena` |
| Bytes/text | `any`, `value`, `literal`, `satisfy`, `oneOf`, `noneOf`, `take`, `takeWhile`, `takeWhile1` |
| Common text | `identifier`, `integer`, `floating`, `asciiWhitespace0`, `asciiWhitespace1`, `digit`, `hexDigit` |
| Structure | `choice`, `rule`, `eof` |
| Lexical helper | `tokenizer` |
| Expressions | `expressionTable` |

### `Parser!T`

| Category | API |
|---|---|
| Execution | `parse`, `valid` |
| Sequencing | `then`, `before`, `after`, `between` |
| Backtracking | `attempt`, `cut`, `peek` |
| Optional/repetition | `optional`, `repeat`, `repeat1`, `sepBy`, `sepBy1` |
| Transformation | `map`, `mapTuple`, `where`, `replace`, `skip` |
| Diagnostics | `named`, `context` |

### Repetition builders

| API | Meaning |
|---|---|
| `skip` | Discard repeated values. |
| `fold` | Aggregate repeated values without collection. |
| `collect` | Explicitly allocate a result slice in `ParseContext.outputArena`. |

### `ExpressionLevel`

| API | Associativity/purpose |
|---|---|
| `prefix` | Prefix unary |
| `postfix` | Postfix unary |
| `left` | Left-associative binary |
| `right` | Right-associative binary |
| `nonassoc` | Single-use binary at a level |

## Testing requirements

The parser test configuration must run in checked debug, optimized,
release-safe, and ASan builds; release-fast must at minimum compile the complete
parser test surface because assertions and checked contracts are intentionally
removed there.

The suite must cover:

- every primitive parser;
- `then`, `before`, `after`, `between`;
- choice error merging;
- natural consumed-input commitment;
- `attempt()` rewind;
- `cut()` preventing rewind;
- optional present/absent behavior;
- repetition, separated repetition, fold, and collection;
- tuple mapping;
- semantic filtering;
- names and diagnostic contexts;
- lookahead;
- recursive rules;
- tokenizer keyword boundaries;
- integer range errors;
- floating syntax/range behavior;
- expression prefix/postfix, left/right/non-associative behavior;
- arithmetic AST precedence and associativity;
- valid and malformed JSON including Unicode/surrogate handling.

## Design decisions

### Arena-backed dynamic parser graph

Chosen over fully type-based parser combinators because it keeps public types
stable (`Parser!T`), makes recursive grammars natural, reduces template/type
explosion, and improves language-server behavior. The runtime tradeoff is an
indirect node dispatch, which should be benchmarked against handwritten parsers
before adding specialization complexity.

### Real member combinators

Chosen because parser operations conceptually belong to `Parser!T` and current D
language tooling resolves members significantly more reliably than large UFCS
free-function overload sets.

### Consumed input commits by default

Chosen to avoid arbitrary hidden backtracking, repeated rescanning, and weak
error locations. Ambiguity is explicit through `attempt()`.

### Explicit cut points

Chosen because syntactic consumption and semantic certainty are related but not
identical. `cut()` documents the exact point after which another grammar branch
is no longer meaningful.

### Structural precedence levels

Chosen over numeric precedence values. Source order directly communicates which
operators bind more tightly and avoids arbitrary numbers such as 70/60/50.

### Explicit collection

Chosen so repetition does not silently allocate. Recognition, folding, and
collection remain separate operations.

### Structural errors

Chosen so parser execution does not perform expensive formatting and so the
same parse errors can feed CLI diagnostics, editors, tests, or other frontends.

### No public `init` factories

Chosen to avoid colliding conceptually and visually with D's built-in `T.init`.
Owning/value factories use `create`; normal zero/default initialization remains
D's native initialization.

## Acceptance criteria

The parser implementation is ready when:

- `xtb:parser` builds under BetterC;
- parser invocation is `@nogc` and `nothrow`;
- grammar/parser node ownership is arena-based;
- output allocations are explicit;
- recursive parsers work without recursive D types;
- `attempt()` and `cut()` behavior is tested;
- expression levels demonstrate real precedence and associativity;
- JSON parses nested real-world documents and rejects malformed syntax;
- arithmetic produces ASTs whose structure proves precedence;
- checked contracts disappear from release-fast;
- the parser test configuration passes checked debug, optimized,
  release-safe, and ASan builds and compiles in release-fast;
- the complete API is accessible through `import xtb.parser;`.
