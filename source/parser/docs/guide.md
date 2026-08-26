# Parser guide

A `Grammar` owns the immutable parser graph. `Parser!T` values are small borrowed
handles into that grammar, so the grammar must outlive every parser built from
it.

```d
Grammar grammar = Grammar.create(mallocAllocator(), 512);
scope(exit) grammar.deinit();

auto assignment = grammar.identifier()
    .before(grammar.value('='))
    .then(grammar.integer!int());

auto result = assignment.parse("answer=42");
assert(result.ok);
assert(result.value.first == "answer");
```

Primitive text parsers return `String` views into the input; they do not copy the
matched text. The input must therefore outlive any returned borrowed strings.
`ParseResult.error` diagnostics likewise borrow input/grammar storage.

## Composition

| Operation | Purpose |
|---|---|
| `then`, `before`, `after`, `between` | sequence parsers |
| `map`, `mapTuple`, `replace`, `skip` | transform results |
| `optional`, `repeat`, `repeat1`, `sepBy` | repetition/optional input |
| `choice` | alternatives |
| `attempt` | allow backtracking after consumed input |
| `cut` | commit to the current branch |
| `where`, `peek`, `named`, `context` | validation and diagnostics |
| `rule` | recursive grammar |
| `tokenizer` | apply shared trivia handling |

Parsers combined with each other must come from the same `Grammar`.

### Backtracking and commitment

Consuming input commits a branch by default. Use `attempt()` around a branch
when another alternative should still be tried if that branch later fails:

```d
auto value = grammar.choice(
    grammar.identifier().before(grammar.value('=')).attempt(),
    grammar.identifier(),
);

assert(value.parse("name").ok);
```

`cut()` does the opposite: once a distinctive prefix has been recognized,
failure after the cut is definitive even if an outer `attempt()` exists. This
is useful for better errors and to avoid pointless alternatives.

## Arena-backed output

Parsing itself does not allocate unless a combinator or semantic action creates
output. Operations such as `collect()` use `ParseContext.outputArena`:

```d
Arena output = Arena.create(mallocAllocator(), 1024);
scope(exit) output.deinit();

ParseContext context = ParseContext.create(&output);
auto numbers = grammar.integer!int()
    .sepBy(grammar.value(','))
    .collect();

auto parsed = numbers.parse("1,2,3", &context);
assert(parsed.ok);
assert(parsed.value == [1, 2, 3]);
```

The collected slice belongs to `output`; it remains valid until that arena is
rewound/cleared/deinitialized. Context-aware `map` callbacks can use the same
`ParseContext` to build application values in that arena. `userData` is
available for additional application state.

Use `ParseState` directly when parsing incrementally or when the caller needs to
inspect the final offset/rest. `ParseResult.failureKind` distinguishes
recoverable failure from a committed branch.

`xtb.parser.json` and `xtb.parser.arithmetic` provide reusable grammars built on
the same API.
