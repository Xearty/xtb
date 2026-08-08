# Intrusive collections

XTB's `IntrusiveList`, `IntrusiveForwardList`, `IntrusiveQueue`, and `IntrusiveStack` store linkage inside caller-owned
nodes. The containers do not allocate wrapper nodes, do not own node storage,
and never destroy nodes. A node must outlive every intrusive container that
currently references one of its hooks.

## Hooks represent membership

A `ListHook!Node` or `ForwardListHook!Node` is one independent membership slot.
The node itself is not globally "linked" or "unlinked". This distinction lets
one object participate in several intrusive structures at the same time:

```d
struct Task
{
    ListHook!Task readyLink;
    ListHook!Task allTasksLink;
    ForwardListHook!Task timeoutLink;
    ForwardListHook!Task dispatchLink;
}

IntrusiveList!(Task, "readyLink") ready;
IntrusiveList!(Task, "allTasksLink") allTasks;
IntrusiveForwardList!(Task, "timeoutLink") timeouts;
IntrusiveQueue!(Task, "dispatchLink") dispatch;

Task task;
ready.pushBack(&task);
allTasks.pushBack(&task);
timeouts.pushBack(&task);
dispatch.pushBack(&task);
```

Those four memberships are independent. Removing `task.readyLink` from
`ready` does not affect the other three hooks.

The inverse rule is equally important: **one hook may belong to at most one
intrusive structure at a time**. Reusing the same hook simultaneously in two
lists, or in both a queue and stack, corrupts the link chain in builds that do
not diagnose the mistake.

Detach the hook first, then reuse it:

```d
ready.remove(&task);
otherReadyList.pushBack(&task); // valid: readyLink is detached again
```

## Choosing a hook

Containers use a member name at compile time:

```d
IntrusiveList!(Task, "readyLink") ready;
IntrusiveForwardList!(Task, "timeoutLink") timeouts;
IntrusiveQueue!(Task, "dispatchLink") dispatch;
```

The named member must have exactly the expected hook type:

- `IntrusiveList` requires `ListHook!Node`;
- `IntrusiveForwardList`, `IntrusiveQueue`, and `IntrusiveStack` require `ForwardListHook!Node`.

The default member names are `listHook` and `forwardListHook` respectively.
Multiple hooks of the same type are intentionally supported; give each role a
separate field and select it through the container's `hookMember` template
argument.

## IntrusiveForwardList, IntrusiveQueue, and IntrusiveStack

`IntrusiveForwardList` is XTB's general intrusive singly linked list. Each node contributes
one `ForwardListHook!Node`, while the list header caches both ends:

```text
IntrusiveForwardList = front pointer + back pointer
ForwardListHook = next pointer (+ linked_ in XTB_Checked)
```

Caching `back` costs one pointer per list object, not per node, and makes both
`pushFront` and `pushBack` O(1). The general API includes:

```d
IntrusiveForwardList!Node list;
list.pushFront(node);
list.pushBack(node);
list.insertAfter(position, node);
Node* removed = list.removeAfter(position);
Node* first = list.popFront();
list.spliceBack(other);
auto suffix = list.splitAfter(position);
auto cursor = list.cursor();
```

`insertAfter` and `removeAfter` are structurally O(1). In `XTB_Checked` builds,
XTB first validates that `position` belongs to the list; that diagnostic walk is
O(n). Unchecked builds omit the validation.

`spliceBack` transfers an entire source chain in O(1) and empties the source.
`splitAfter` detaches the suffix following a node and returns it as another
`IntrusiveForwardList`. Neither operation detaches individual hooks, so checked-build
membership state remains set while the nodes move between list headers.

`IntrusiveQueue` stores an `IntrusiveForwardList` internally and exposes only the queue-facing end
operations already supported by XTB (`pushBack`, `pushFront`, and `popFront`),
plus `front`/`back`. It therefore shares the same two-pointer header and one
canonical implementation of forward-chain maintenance instead of duplicating
that logic.

`IntrusiveStack` deliberately does **not** use `IntrusiveForwardList`. A stack needs only its top
pointer, so wrapping a two-pointer list would enlarge every stack object for no
benefit:

```text
IntrusiveQueue / IntrusiveForwardList = two container pointers
IntrusiveStack               = one container pointer
```

All three containers use the same `ForwardListHook!Node` hook type and therefore
support the same independent-hook membership model.

## Checked-build membership bookkeeping

The structural pointers are always present because the containers need them:

- `ListHook!Node` always stores `previous` and `next` pointers;
- `ForwardListHook!Node` always stores a `next` pointer.

`XTB_Checked` builds additionally store a private `linked_` flag in each hook.
That flag lets XTB catch accidental double insertion even when the hook is the
sole or final node and all structural pointers are null. The public diagnostic
`hook.linked` accessor is available under the same version condition.

When `XTB_Checked` is not defined, both the `linked_` field and the `linked`
accessor are compiled out completely. Consequently release-fast uses exactly
the structural layouts:

```text
ListHook     = two pointers
ForwardListHook  = one pointer
```

This is intentional. Per-hook membership tracking changes every caller-owned
node's layout, so XTB pays that cost in both checked modes where invariant
diagnostics are requested and removes it in release-fast. Debug and
release-safe therefore diagnose same-hook double insertion consistently.

When `XTB_Checked` is absent, the one-hook/one-container rule is a caller
invariant.

## Why pointers alone cannot represent membership

A detached forward hook naturally has `next == null`, but the final node in a
queue or stack also has `next == null`. Similarly, a detached doubly linked
hook has both pointers null, but so does the only node in a one-element list.
The structural pointers therefore cannot reliably answer whether a hook is
currently attached.

The checked-build membership flag exists specifically to resolve that ambiguity
without carrying an owner pointer or additional bookkeeping in production
layouts.

## Removal and reuse

Removal clears the selected hook back to its default state. In checked builds
this also clears the membership flag. The node's payload and any other hooks
are untouched.

`IntrusiveList.spliceBack` and `IntrusiveForwardList.spliceBack` transfer an entire chain from
the source list to the destination. `IntrusiveForwardList.splitAfter` transfers a suffix
to a new list header. These operations do not detach and reattach individual
hooks; membership remains live throughout the transfer.

## Ownership and copying

Intrusive containers are non-copyable. Nodes remain caller-owned, and the
library does not allocate, clone, move, or destroy them. Moving or bitwise
copying a node while one of its hooks is linked is a programming error because
containers retain the node's address.

The safest pattern is to keep linked nodes at stable addresses and explicitly
remove every active hook before reclaiming or relocating the node storage.
