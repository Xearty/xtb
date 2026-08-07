# Intrusive collections

XTB's intrusive `List`, `Queue`, and `Stack` store linkage inside caller-owned
nodes. The containers do not allocate wrapper nodes, do not own node storage,
and never destroy nodes. A node must outlive every intrusive container that
currently references one of its hooks.

## Hooks represent membership

A `ListLink!Node` or `ForwardLink!Node` is one independent membership slot.
The node itself is not globally "linked" or "unlinked". This distinction lets
one object participate in several intrusive structures at the same time:

```d
struct Task
{
    ListLink!Task readyLink;
    ListLink!Task allTasksLink;
    ForwardLink!Task timeoutLink;
}

List!(Task, "readyLink") ready;
List!(Task, "allTasksLink") allTasks;
Queue!(Task, "timeoutLink") timeouts;

Task task;
ready.pushBack(&task);
allTasks.pushBack(&task);
timeouts.pushBack(&task);
```

Those three memberships are independent. Removing `task.readyLink` from
`ready` does not affect `task.allTasksLink` or `task.timeoutLink`.

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
List!(Task, "readyLink") ready;
Queue!(Task, "timeoutLink") timeouts;
```

The named member must have exactly the expected hook type:

- `List` requires `ListLink!Node`;
- `Queue` and `Stack` require `ForwardLink!Node`.

The default member names are `listLink` and `forwardLink` respectively.
Multiple hooks of the same type are intentionally supported; give each role a
separate field and select it through the container's `member` template
argument.

## Checked-build membership bookkeeping

The structural pointers are always present because the containers need them:

- `ListLink!Node` always stores `previous` and `next` pointers;
- `ForwardLink!Node` always stores a `next` pointer.

`XTB_Checked` builds additionally store a private `linked_` flag in each hook.
That flag lets XTB catch accidental double insertion even when the hook is the
sole or final node and all structural pointers are null. The public diagnostic
`hook.linked` accessor is available under the same version condition.

When `XTB_Checked` is not defined, both the `linked_` field and the `linked`
accessor are compiled out completely. Consequently release-fast uses exactly
the structural layouts:

```text
ListLink     = two pointers
ForwardLink  = one pointer
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

`List.concatenate` transfers an entire chain from the source list to the
destination. It does not detach and reattach individual hooks; their membership
remains live throughout the transfer. The source container becomes empty.

## Ownership and copying

Intrusive containers are non-copyable. Nodes remain caller-owned, and the
library does not allocate, clone, move, or destroy them. Moving or bitwise
copying a node while one of its hooks is linked is a programming error because
containers retain the node's address.

The safest pattern is to keep linked nodes at stable addresses and explicitly
remove every active hook before reclaiming or relocating the node storage.
