# Intrusive collections

Intrusive collections store links inside the node instead of allocating a
separate container node. They do not own or destroy their elements.

| Type | Hook | Typical use | Main operations |
|---|---|---|---|
| `IntrusiveList` | `ListHook` | doubly linked list | insert/remove at either end or around a node |
| `IntrusiveForwardList` | `ForwardListHook` | singly linked list | push at either end, insert/remove after a node |
| `IntrusiveQueue` | `ForwardListHook` | FIFO queue | `push_back`, `pop_front` |
| `IntrusiveStack` | `ForwardListHook` | LIFO stack | `push`, `pop` |

All four support `foreach`; lists and queues iterate front-to-back, while a
stack iterates from top to bottom.

## Doubly linked list

The default hook name is `list_hook`.

```d
struct Node
{
    i32 value;
    ListHook!Node list_hook;
}

Node first;
first.value = 1;
Node second;
second.value = 2;

IntrusiveList!Node list;
list.push_back(&first);
list.push_back(&second);

i32 total;
foreach (node; list)
{
    total += node.value;
}

list.remove(&first);
Node* last = list.pop_back();
```

`IntrusiveList` also provides `push_front`, `insert_before`, `insert_after`,
`pop_front`, `splice_back`, and forward/reverse cursors.

## Forward list

The default hook name is `forward_list_hook`.

```d
struct Node
{
    i32 value;
    ForwardListHook!Node forward_list_hook;
}

Node first;
Node second;
Node third;

IntrusiveForwardList!Node list;
list.push_back(&first);
list.insert_after(&first, &second);
list.push_front(&third);

Node* removed = list.remove_after(&first);
```

The forward list keeps both ends, so `push_front` and `push_back` are O(1). It
also provides `pop_front`, `splice_back`, `split_after`, and a forward cursor.

## Queue

`IntrusiveQueue` provides queue operations over a forward list. Its public
`list` field exposes the representation, so direct mutation must preserve the
queue's membership and ordering invariants.

```d
struct Job
{
    i32 id;
    ForwardListHook!Job forward_list_hook;
}

Job first;
Job second;

IntrusiveQueue!Job queue;
queue.push_back(&first);
queue.push_back(&second);

Job* job = queue.pop_front(); // first
```

`front` and `back` inspect the ends without removing them. `push_front` is also
available when a caller needs to prepend work.

## Stack

```d
struct Job
{
    i32 id;
    ForwardListHook!Job forward_list_hook;
}

Job first;
Job second;

IntrusiveStack!Job stack;
stack.push(&first);
stack.push(&second);

Job* job = stack.pop(); // second
```

`top` is the current top node pointer and is null when the stack is empty.

## Multiple memberships

A hook represents one membership. Give a node multiple hooks when it must be in
multiple intrusive collections at once:

```d
struct Job
{
    ListHook!Job active_hook;
    ForwardListHook!Job queue_hook;
    ForwardListHook!Job retry_hook;
}

IntrusiveList!(Job, "active_hook") active;
IntrusiveQueue!(Job, "queue_hook") pending;
IntrusiveStack!(Job, "retry_hook") retries;
```

The same hook must not be linked into two collections at once. Checked builds
diagnose double insertion and invalid membership operations; `release-fast`
omits those checks. Positional membership validation in checked builds can make
some otherwise O(1) operations O(n).

## Lifetime

The collections only store pointers. A node must remain at a stable address
while linked, and must be removed before its storage becomes invalid. Do not
copy or move a linked node: that also copies or moves its hook state.
