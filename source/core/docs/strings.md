# Strings

XTB separates string views from string ownership.

| Type | Meaning |
|---|---|
| `String` | borrowed immutable UTF-8 bytes |
| `OwnedString` | independently owned exact-sized string |
| `StringBuf` | mutable growable string bound to an allocator |

`String` does not own its bytes and has no cleanup. The backing storage must
outlive the view.

```d
String name = "xtb";
OwnedString copy = name.copy(heap);
scope(exit) copy.deinit();
```

`OwnedString.view` borrows its bytes. `StringBuf.view` does the same for a
mutable buffer; do not retain such a view across mutations that may reallocate
the buffer.

## Transformation ownership

The destination argument determines the ownership of allocating string
transformations:

| Destination | Result |
|---|---|
| `Allocator*` | independently owned `OwnedString` |
| `Arena*` | borrowed `String` backed by the arena |

This convention applies to `copy`, `concat`, `replace`, `join`, and `escape`.

```d
Arena arena = Arena.create(heap);
scope(exit) arena.deinit();

String temporary = "//api//users".replace("//", "/", &arena);
OwnedString persistent = temporary.copy(heap);
scope(exit) persistent.deinit();
```

Use the arena form for temporary results and the allocator form when the result
must have an independent lifetime.

Each allocating operation also has a fallible `try*` form. It returns `false`
on allocation failure and writes into caller-provided empty output storage:

```d
OwnedString escaped;
if (!input.tryEscape(heap, &escaped))
    return false;
scope(exit) escaped.deinit();
```

The non-`try` counterparts panic on allocation failure.

## OwnedString and StringBuf

`OwnedString` is immutable and exact-sized. Use `clone(allocator)` when an
existing `OwnedString` needs another independent owner; transformations such as
`concat`, `replace`, and `escape` accept either `Allocator*` or `Arena*`.

`StringBuf` is the mutable builder. It supports reserving capacity, appending,
inserting, in-place replacement/escaping, and formatting. `copy(Allocator*)`
freezes its current contents into an `OwnedString`; `copy(Arena*)` copies them
into arena-owned storage.

Neither `String` nor `OwnedString` promises a trailing NUL. Use `StringBuf`'s C
string helpers when interoperating with APIs that require one.
