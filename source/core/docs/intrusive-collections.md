# Intrusive collections

Intrusive collections store links inside the node instead of allocating a
separate container node. They do not own or destroy their elements.

| Type | Hook | Typical use | Main operations |
|---|---|---|---|
| `IntrusiveList` | `ListHook` | doubly linked list | insert/remove at either end or around a node |
| `IntrusiveForwardList` | `ForwardListHook` | singly linked list | push at either end, insert/remove after a node |
| `IntrusiveQueue` | `ForwardListHook` | FIFO queue | `pushBack`, `popFront` |
| `IntrusiveStack` | `ForwardListHook` | LIFO stack | `push`, `pop` |

All four support `foreach`; lists and queues iterate front-to-back, while a
stack iterates from top to bottom.

## Doubly linked list

The default hook name is `listHook`.

```d
struct Node
{
    int value;
    ListHook!Node listHook;
}

Node first;
first.value = 1;
Node second;
second.value = 2;

IntrusiveList!Node list;
list.pushBack(&first);
list.pushBack(&second);

int total;
foreach (node; list)
    total += node.value;

list.remove(&first);
Node* last = list.popBack();
```

`IntrusiveList` also provides `pushFront`, `insertBefore`, `insertAfter`,
`popFront`, `spliceBack`, and forward/reverse cursors.

## Forward list

The default hook name is `forwardListHook`.

```d
struct Node
{
    int value;
    ForwardListHook!Node forwardListHook;
}

Node first;
Node second;
Node third;

IntrusiveForwardList!Node list;
list.pushBack(&first);
list.insertAfter(&first, &second);
list.pushFront(&third);

Node* removed = list.removeAfter(&first);
```

The forward list keeps both ends, so `pushFront` and `pushBack` are O(1). It
also provides `popFront`, `spliceBack`, `splitAfter`, and a forward cursor.

## Queue

`IntrusiveQueue` is the restricted queue interface over a forward list.

```d
struct Job
{
    int id;
    ForwardListHook!Job forwardListHook;
}

Job first;
Job second;

IntrusiveQueue!Job queue;
queue.pushBack(&first);
queue.pushBack(&second);

Job* job = queue.popFront(); // first
```

`front` and `back` inspect the ends without removing them. `pushFront` is also
available when a caller needs to prepend work.

## Stack

```d
struct Job
{
    int id;
    ForwardListHook!Job forwardListHook;
}

Job first;
Job second;

IntrusiveStack!Job stack;
stack.push(&first);
stack.push(&second);

Job* job = stack.pop(); // second
```

`top` inspects the current top without removing it.

## Multiple memberships

A hook represents one membership. Give a node multiple hooks when it must be in
multiple intrusive collections at once:

```d
struct Job
{
    ListHook!Job activeHook;
    ForwardListHook!Job queueHook;
    ForwardListHook!Job retryHook;
}

IntrusiveList!(Job, "activeHook") active;
IntrusiveQueue!(Job, "queueHook") pending;
IntrusiveStack!(Job, "retryHook") retries;
```

The same hook must not be linked into two collections at once. Checked builds
diagnose double insertion and invalid membership operations; `release-fast`
omits those checks. Positional membership validation in checked builds can make
some otherwise O(1) operations O(n).

## Lifetime

The collections only store pointers. A node must remain at a stable address
while linked, and must be removed before its storage becomes invalid. Do not
copy or move a linked node: that also copies or moves its hook state.
