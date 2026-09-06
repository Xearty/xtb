module xtb.containers.intrusive_list;

nothrow @nogc:

import xtb.panic;
import xtb.types;

/// One intrusive doubly linked-list membership hook.
///
/// A node may contain multiple `ListHook!Node` fields and therefore belong to
/// multiple lists at the same time. Each individual hook may belong to at most
/// one list. `XTB_Checked` builds track that per-hook membership and reject
/// double insertion. The `linked` diagnostic field does not exist without
/// `XTB_Checked`, where correct hook ownership is a caller invariant. Direct
/// mutation of `previous`, `next`, or `linked` must preserve list membership.
struct ListHook(Node)
{
    Node* previous;
    Node* next;

    version (XTB_Checked)
    {
        bool linked;
    }
}

/// One intrusive forward-list membership hook used by forward lists, queues, and stacks.
///
/// A node may contain multiple `ForwardListHook!Node` fields and therefore belong
/// to multiple intrusive structures at the same time. Each individual hook may
/// belong to at most one structure. `XTB_Checked` builds track that per-hook
/// membership and reject double insertion. The `linked` diagnostic field does
/// not exist without `XTB_Checked`. Direct mutation of `next` or `linked` must
/// preserve intrusive-structure membership.
struct ForwardListHook(Node)
{
    Node* next;

    version (XTB_Checked)
    {
        bool linked;
    }
}

private ref ListHook!Node list_hook_of(Node, string hook_member)(Node* node)
{
    return __traits(getMember, *node, hook_member);
}

private ref const(ListHook!Node) list_hook_of(Node, string hook_member)(const(Node)* node)
{
    return __traits(getMember, *node, hook_member);
}

private ref ForwardListHook!Node forward_list_hook_of(Node, string hook_member)(Node* node)
{
    return __traits(getMember, *node, hook_member);
}

private ref const(ForwardListHook!Node) forward_list_hook_of(
    Node,
    string hook_member,
)(const(Node)* node)
{
    return __traits(getMember, *node, hook_member);
}

version (XTB_Checked)
{
    private void require_unlinked(Node)(ref ListHook!Node link)
    {
        require(!link.linked, "list hook is already linked");
    }

    private void require_unlinked(Node)(ref ForwardListHook!Node link)
    {
        require(!link.linked, "forward hook is already linked");
    }
}

/// Intrusive doubly linked list using `Node.hook_member` as its membership hook.
///
/// `front` and `back` are null exactly when the list is empty. Direct mutation
/// must preserve the hook chain and membership invariants. Node and position
/// pointer parameters are required to be non-null.
struct IntrusiveList(Node, string hook_member = "list_hook")
{
    static assert(
        __traits(hasMember, Node, hook_member),
        "IntrusiveList node is missing its " ~ hook_member ~ " hook",
    );
    static assert(
        is(typeof(__traits(getMember, Node.init, hook_member)) == ListHook!Node),
        "IntrusiveList hook must be ListHook!Node",
    );

    Node* front;
    Node* back;

    @disable this(this);

    bool empty() const pure @safe
    {
        return this.front is null;
    }

    /// Iterates nodes from front to back without modifying the list.
    ///
    /// The next hook is captured before invoking the callback, so removing the
    /// current node from this list during the loop does not invalidate the
    /// traversal. Other structural mutation during iteration is unspecified.
    i32 opApply(scope i32 delegate(Node*) nothrow @nogc callback) nothrow @nogc
    {
        require(callback !is null, "intrusive-list iteration callback is null");
        for (Node* current = this.front; current !is null;)
        {
            Node* next = list_hook_of!(Node, hook_member)(current).next;
            const control = callback(current);
            if (control != 0) return control;
            current = next;
        }
        return 0;
    }

    /// Const iteration yields pointers to const nodes.
    i32 opApply(scope i32 delegate(const(Node)*) nothrow @nogc callback) const nothrow @nogc
    {
        require(callback !is null, "intrusive-list iteration callback is null");
        for (const(Node)* current = this.front; current !is null;)
        {
            const(Node)* next = list_hook_of!(Node, hook_member)(current).next;
            const control = callback(current);
            if (control != 0) return control;
            current = next;
        }
        return 0;
    }

    private bool contains(Node* node)
    {
        for (Node* current = this.front; current !is null;)
        {
            if (current is node) return true;
            current = list_hook_of!(Node, hook_member)(current).next;
        }
        return false;
    }

    void push_back(Node* node)
    {
        require(node !is null, "cannot insert a null list node");
        ref link = list_hook_of!(Node, hook_member)(node);
        version (XTB_Checked)
        {
            require_unlinked(link);
        }

        link.previous = this.back;
        link.next = null;
        version (XTB_Checked)
        {
            link.linked = true;
        }
        if (this.back is null)
        {
            this.front = node;
        }
        else
        {
            list_hook_of!(Node, hook_member)(this.back).next = node;
        }
        this.back = node;
    }

    void push_front(Node* node)
    {
        require(node !is null, "cannot insert a null list node");
        ref link = list_hook_of!(Node, hook_member)(node);
        version (XTB_Checked)
        {
            require_unlinked(link);
        }

        link.previous = null;
        link.next = this.front;
        version (XTB_Checked)
        {
            link.linked = true;
        }
        if (this.front is null)
        {
            this.back = node;
        }
        else
        {
            list_hook_of!(Node, hook_member)(this.front).previous = node;
        }
        this.front = node;
    }

    void insert_after(Node* position, Node* node)
    {
        require(
            position !is null && node !is null,
            "cannot insert a null list node",
        );
        require(this.contains(position), "position is not in this list");
        if (position is this.back)
        {
            this.push_back(node);
            return;
        }

        ref position_link = list_hook_of!(Node, hook_member)(position);
        ref link = list_hook_of!(Node, hook_member)(node);
        version (XTB_Checked)
        {
            require_unlinked(link);
        }
        link.previous = position;
        link.next = position_link.next;
        version (XTB_Checked)
        {
            link.linked = true;
        }
        list_hook_of!(Node, hook_member)(position_link.next).previous = node;
        position_link.next = node;
    }

    void insert_before(Node* position, Node* node)
    {
        require(
            position !is null && node !is null,
            "cannot insert a null list node",
        );
        require(this.contains(position), "position is not in this list");
        if (position is this.front)
        {
            this.push_front(node);
            return;
        }

        ref position_link = list_hook_of!(Node, hook_member)(position);
        ref link = list_hook_of!(Node, hook_member)(node);
        version (XTB_Checked)
        {
            require_unlinked(link);
        }
        link.next = position;
        link.previous = position_link.previous;
        version (XTB_Checked)
        {
            link.linked = true;
        }
        list_hook_of!(Node, hook_member)(position_link.previous).next = node;
        position_link.previous = node;
    }

    void remove(Node* node)
    {
        require(node !is null, "cannot remove a null list node");
        require(this.contains(node), "node is not in this list");
        ref link = list_hook_of!(Node, hook_member)(node);

        if (link.previous is null)
        {
            this.front = link.next;
        }
        else
        {
            list_hook_of!(Node, hook_member)(link.previous).next = link.next;
        }

        if (link.next is null)
        {
            this.back = link.previous;
        }
        else
        {
            list_hook_of!(Node, hook_member)(link.next).previous = link.previous;
        }

        link = ListHook!Node.init;
    }

    /// Removes and returns the non-null front node. The list must not be empty.
    Node* pop_front()
    {
        require(this.front !is null, "cannot pop an empty list");
        Node* result = this.front;
        this.remove(result);
        return result;
    }

    /// Removes and returns the non-null back node. The list must not be empty.
    Node* pop_back()
    {
        require(this.back !is null, "cannot pop an empty list");
        Node* result = this.back;
        this.remove(result);
        return result;
    }

    /// Appends all nodes from non-null `source`, leaving it empty.
    void splice_back(IntrusiveList* source)
    {
        require(source !is null, "source list is null");
        require(&this !is source, "cannot splice a list with itself");
        if (source.empty) return;
        if (this.empty)
        {
            this.front = source.front;
            this.back = source.back;
        }
        else
        {
            list_hook_of!(Node, hook_member)(this.back).next = source.front;
            list_hook_of!(Node, hook_member)(source.front).previous = this.back;
            this.back = source.back;
        }
        source.front = null;
        source.back = null;
    }

    IntrusiveListCursor!(Node, hook_member) cursor()
    {
        return IntrusiveListCursor!(Node, hook_member)(this.front, false);
    }

    IntrusiveListCursor!(Node, hook_member) reverse_cursor()
    {
        return IntrusiveListCursor!(Node, hook_member)(this.back, true);
    }
}

/// Cursor state over an `IntrusiveList`.
///
/// `node` is null when invalid. Direct mutation of `node` or `reverse` changes
/// the traversal position or direction.
struct IntrusiveListCursor(Node, string hook_member)
{
    Node* node;
    bool reverse;

    bool valid() const pure @safe
    {
        return this.node !is null;
    }

    /// Returns the non-null current node. The cursor must be valid.
    Node* current() return
    {
        require(this.valid, "invalid list cursor");
        return this.node;
    }

    void advance()
    {
        require(this.valid, "invalid list cursor");
        ref link = list_hook_of!(Node, hook_member)(this.node);
        this.node = this.reverse ? link.previous : link.next;
    }
}

/// General intrusive singly linked list using `Node.hook_member` as its membership hook.
///
/// `front` and `back` are null exactly when the list is empty. Direct mutation
/// must preserve the hook chain and membership invariants. Node and position
/// pointer parameters are required to be non-null.
///
/// The list stores both its first and last node so insertion at either end is
/// O(1). `IntrusiveQueue` provides queue operations over this type;
/// `IntrusiveStack` remains separate because it needs only one container pointer.
struct IntrusiveForwardList(Node, string hook_member = "forward_list_hook")
{
    static assert(
        __traits(hasMember, Node, hook_member),
        "IntrusiveForwardList node is missing its " ~ hook_member ~ " hook",
    );
    static assert(
        is(typeof(__traits(getMember, Node.init, hook_member)) == ForwardListHook!Node),
        "IntrusiveForwardList hook must be ForwardListHook!Node",
    );

    Node* front;
    Node* back;

    @disable this(this);

    bool empty() const pure @safe
    {
        return this.front is null;
    }

    /// Iterates nodes from front to back without modifying the list.
    ///
    /// The next hook is captured before invoking the callback, so removing the
    /// current node from this list during the loop does not invalidate the
    /// traversal. Other structural mutation during iteration is unspecified.
    i32 opApply(scope i32 delegate(Node*) nothrow @nogc callback) nothrow @nogc
    {
        require(callback !is null, "intrusive-forward-list iteration callback is null");
        for (Node* current = this.front; current !is null;)
        {
            Node* next = forward_list_hook_of!(Node, hook_member)(current).next;
            const control = callback(current);
            if (control != 0) return control;
            current = next;
        }
        return 0;
    }

    /// Const iteration yields pointers to const nodes.
    i32 opApply(scope i32 delegate(const(Node)*) nothrow @nogc callback) const nothrow @nogc
    {
        require(callback !is null, "intrusive-forward-list iteration callback is null");
        for (const(Node)* current = this.front; current !is null;)
        {
            const(Node)* next = forward_list_hook_of!(Node, hook_member)(current).next;
            const control = callback(current);
            if (control != 0) return control;
            current = next;
        }
        return 0;
    }

    private bool contains(Node* node)
    {
        for (Node* current = this.front; current !is null;)
        {
            if (current is node) return true;
            current = forward_list_hook_of!(Node, hook_member)(current).next;
        }
        return false;
    }

    /// Inserts `node` at the front in O(1).
    void push_front(Node* node)
    {
        require(node !is null, "cannot insert a null forward-list node");
        ref link = forward_list_hook_of!(Node, hook_member)(node);
        version (XTB_Checked)
        {
            require_unlinked(link);
        }

        link.next = this.front;
        version (XTB_Checked)
        {
            link.linked = true;
        }
        this.front = node;
        if (this.back is null) this.back = node;
    }

    /// Inserts `node` at the back in O(1).
    void push_back(Node* node)
    {
        require(node !is null, "cannot insert a null forward-list node");
        ref link = forward_list_hook_of!(Node, hook_member)(node);
        version (XTB_Checked)
        {
            require_unlinked(link);
        }

        link.next = null;
        version (XTB_Checked)
        {
            link.linked = true;
        }
        if (this.back is null)
        {
            this.front = node;
        }
        else
        {
            forward_list_hook_of!(Node, hook_member)(this.back).next = node;
        }
        this.back = node;
    }

    /// Inserts `node` immediately after `position`.
    ///
    /// This is O(1); checked builds verify that `position` belongs to this
    /// list, which requires an O(n) validation walk.
    void insert_after(Node* position, Node* node)
    {
        require(
            position !is null && node !is null,
            "cannot insert relative to a null forward-list node",
        );
        require(this.contains(position), "position is not in this forward list");
        if (position is this.back)
        {
            this.push_back(node);
            return;
        }

        ref position_link = forward_list_hook_of!(Node, hook_member)(position);
        ref link = forward_list_hook_of!(Node, hook_member)(node);
        version (XTB_Checked)
        {
            require_unlinked(link);
        }
        link.next = position_link.next;
        version (XTB_Checked)
        {
            link.linked = true;
        }
        position_link.next = node;
    }

    /// Removes and returns the non-null node immediately after `position`.
    ///
    /// This is O(1); checked builds verify that `position` belongs to this
    /// list, which requires an O(n) validation walk.
    Node* remove_after(Node* position)
    {
        require(position !is null, "cannot remove after a null forward-list node");
        require(this.contains(position), "position is not in this forward list");

        ref position_link = forward_list_hook_of!(Node, hook_member)(position);
        require(position_link.next !is null, "no forward-list node exists after position");

        Node* result = position_link.next;
        ref link = forward_list_hook_of!(Node, hook_member)(result);
        position_link.next = link.next;
        if (result is this.back) this.back = position;
        link = ForwardListHook!Node.init;
        return result;
    }

    /// Removes and returns the non-null first node in O(1). The list must not be empty.
    Node* pop_front()
    {
        require(this.front !is null, "cannot pop an empty forward list");
        Node* result = this.front;
        ref link = forward_list_hook_of!(Node, hook_member)(result);
        this.front = link.next;
        link = ForwardListHook!Node.init;
        if (this.front is null) this.back = null;
        return result;
    }

    /// Appends all nodes from non-null `source` in O(1), leaving it empty.
    void splice_back(IntrusiveForwardList* source)
    {
        require(source !is null, "source forward list is null");
        require(&this !is source, "cannot splice a forward list with itself");
        if (source.empty) return;
        if (this.empty)
        {
            this.front = source.front;
            this.back = source.back;
        }
        else
        {
            forward_list_hook_of!(Node, hook_member)(this.back).next = source.front;
            this.back = source.back;
        }
        source.front = null;
        source.back = null;
    }

    /// Detaches all nodes after `position` and returns them as a new list.
    ///
    /// Existing hook membership remains live because nodes stay linked, only
    /// the owning list header changes. The returned list is empty when
    /// `position` is already the last node.
    IntrusiveForwardList split_after(Node* position)
    {
        require(position !is null, "cannot split after a null forward-list node");
        require(this.contains(position), "position is not in this forward list");

        IntrusiveForwardList result;
        ref position_link = forward_list_hook_of!(Node, hook_member)(position);
        result.front = position_link.next;
        if (result.front !is null)
        {
            result.back = this.back;
            this.back = position;
            position_link.next = null;
        }
        return result;
    }

    IntrusiveForwardListCursor!(Node, hook_member) cursor()
    {
        return IntrusiveForwardListCursor!(Node, hook_member)(this.front);
    }
}

/// Forward-only cursor over an intrusive `IntrusiveForwardList`.
///
/// `node` is null when invalid. Direct mutation changes the traversal position.
struct IntrusiveForwardListCursor(Node, string hook_member)
{
    Node* node;

    bool valid() const pure @safe
    {
        return this.node !is null;
    }

    /// Returns the non-null current node. The cursor must be valid.
    Node* current() return
    {
        require(this.valid, "invalid forward-list cursor");
        return this.node;
    }

    void advance()
    {
        require(this.valid, "invalid forward-list cursor");
        this.node = forward_list_hook_of!(Node, hook_member)(this.node).next;
    }
}

/// Intrusive FIFO queue using `Node.hook_member` as its membership hook.
///
/// IntrusiveQueue provides queue operations over an `IntrusiveForwardList`.
///
/// The public `list` field is representation state. Direct mutation must
/// preserve the queue's membership and ordering invariants. Node pointer
/// parameters are required to be non-null. `front()` and `back()` return null
/// exactly when the queue is empty; `pop_front()` returns a non-null node and
/// requires a non-empty queue.
struct IntrusiveQueue(Node, string hook_member = "forward_list_hook")
{
    static assert(
        __traits(hasMember, Node, hook_member),
        "IntrusiveQueue node is missing its " ~ hook_member ~ " hook",
    );
    static assert(
        is(typeof(__traits(getMember, Node.init, hook_member)) == ForwardListHook!Node),
        "IntrusiveQueue hook must be ForwardListHook!Node",
    );

    IntrusiveForwardList!(Node, hook_member) list;

    @disable this(this);

    bool empty() const pure @safe
    {
        return this.list.empty;
    }

    inout(Node)* front() inout return pure
    {
        return this.list.front;
    }

    inout(Node)* back() inout return pure
    {
        return this.list.back;
    }

    /// Iterates queued nodes from front to back.
    i32 opApply(scope i32 delegate(Node*) nothrow @nogc callback) nothrow @nogc
    {
        return this.list.opApply(callback);
    }

    /// Const iteration yields pointers to const nodes.
    i32 opApply(scope i32 delegate(const(Node)*) nothrow @nogc callback) const nothrow @nogc
    {
        return this.list.opApply(callback);
    }

    void push_back(Node* node)
    {
        this.list.push_back(node);
    }

    void push_front(Node* node)
    {
        this.list.push_front(node);
    }

    Node* pop_front()
    {
        return this.list.pop_front();
    }
}

/// Intrusive LIFO stack using `Node.hook_member` as its membership hook.
///
/// `top` is null exactly when the stack is empty. Direct mutation must preserve
/// the hook chain and membership invariants. `push` requires a non-null node;
/// `pop` returns a non-null node and requires a non-empty stack.
struct IntrusiveStack(Node, string hook_member = "forward_list_hook")
{
    static assert(
        __traits(hasMember, Node, hook_member),
        "IntrusiveStack node is missing its " ~ hook_member ~ " hook",
    );
    static assert(
        is(typeof(__traits(getMember, Node.init, hook_member)) == ForwardListHook!Node),
        "IntrusiveStack hook must be ForwardListHook!Node",
    );

    Node* top;

    @disable this(this);

    bool empty() const pure @safe
    {
        return this.top is null;
    }

    /// Iterates nodes from the current top toward the bottom.
    ///
    /// The next hook is captured before invoking the callback, so popping the
    /// current node during the loop does not invalidate the traversal. Other
    /// structural mutation during iteration is unspecified.
    i32 opApply(scope i32 delegate(Node*) nothrow @nogc callback) nothrow @nogc
    {
        require(callback !is null, "intrusive-stack iteration callback is null");
        for (Node* current = this.top; current !is null;)
        {
            Node* next = forward_list_hook_of!(Node, hook_member)(current).next;
            const control = callback(current);
            if (control != 0) return control;
            current = next;
        }
        return 0;
    }

    /// Const iteration yields pointers to const nodes.
    i32 opApply(scope i32 delegate(const(Node)*) nothrow @nogc callback) const nothrow @nogc
    {
        require(callback !is null, "intrusive-stack iteration callback is null");
        for (const(Node)* current = this.top; current !is null;)
        {
            const(Node)* next = forward_list_hook_of!(Node, hook_member)(current).next;
            const control = callback(current);
            if (control != 0) return control;
            current = next;
        }
        return 0;
    }

    void push(Node* node)
    {
        require(node !is null, "cannot insert a null stack node");
        ref link = forward_list_hook_of!(Node, hook_member)(node);
        version (XTB_Checked)
        {
            require_unlinked(link);
        }

        link.next = this.top;
        version (XTB_Checked)
        {
            link.linked = true;
        }
        this.top = node;
    }

    Node* pop()
    {
        require(this.top !is null, "cannot pop an empty stack");
        Node* result = this.top;
        ref link = forward_list_hook_of!(Node, hook_member)(result);
        this.top = link.next;
        link = ForwardListHook!Node.init;
        return result;
    }
}

version (unittest)
{
    private struct IntrusiveContainerLayoutProbe
    {
        ForwardListHook!IntrusiveContainerLayoutProbe forward_list_hook;
    }

    static assert(IntrusiveForwardList!IntrusiveContainerLayoutProbe.sizeof == usize.sizeof * 2);
    static assert(
        IntrusiveQueue!IntrusiveContainerLayoutProbe.sizeof
            == IntrusiveForwardList!IntrusiveContainerLayoutProbe.sizeof,
    );
    static assert(IntrusiveStack!IntrusiveContainerLayoutProbe.sizeof == usize.sizeof);
    static assert(
        __traits(hasMember, IntrusiveForwardList!IntrusiveContainerLayoutProbe, "insert_after"),
    );
    static assert(
        __traits(hasMember, IntrusiveForwardList!IntrusiveContainerLayoutProbe, "remove_after"),
    );
    static assert(
        __traits(hasMember, IntrusiveForwardList!IntrusiveContainerLayoutProbe, "split_after"),
    );
    static assert(
        !__traits(hasMember, IntrusiveQueue!IntrusiveContainerLayoutProbe, "insert_after"),
    );
    static assert(
        !__traits(hasMember, IntrusiveQueue!IntrusiveContainerLayoutProbe, "remove_after"),
    );
    static assert(
        !__traits(hasMember, IntrusiveQueue!IntrusiveContainerLayoutProbe, "split_after"),
    );

    private struct IntrusiveLinkLayoutProbe
    {
    }

    version (XTB_Checked)
    {
        static assert(__traits(hasMember, ListHook!IntrusiveLinkLayoutProbe, "linked"));
        static assert(__traits(hasMember, ForwardListHook!IntrusiveLinkLayoutProbe, "linked"));
        static assert(ListHook!IntrusiveLinkLayoutProbe.sizeof > usize.sizeof * 2);
        static assert(ForwardListHook!IntrusiveLinkLayoutProbe.sizeof > usize.sizeof);
    }
    else
    {
        // Unchecked hooks contain structural links only. Membership bookkeeping and
        // its public diagnostic field must contribute zero storage/API surface.
        static assert(!__traits(hasMember, ListHook!IntrusiveLinkLayoutProbe, "linked"));
        static assert(!__traits(hasMember, ForwardListHook!IntrusiveLinkLayoutProbe, "linked"));
        static assert(ListHook!IntrusiveLinkLayoutProbe.sizeof == usize.sizeof * 2);
        static assert(ForwardListHook!IntrusiveLinkLayoutProbe.sizeof == usize.sizeof);
    }
}

unittest
{
    struct Node
    {
        ListHook!Node list_hook;
        i32 value;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;
    Node middle;
    middle.value = 3;

    IntrusiveList!Node list;
    list.push_back(&first);
    list.push_back(&second);
    list.insert_before(&second, &middle);
    assert(list.front.value == 1);
    assert(list.back.value == 2 && list.front.list_hook.next is &middle);
    assert(list.pop_front() is &first);
    version (XTB_Checked)
    {
        assert(!first.list_hook.linked);
    }
    assert(list.pop_back() is &second);
    list.remove(&middle);
    assert(list.empty);

    IntrusiveList!Node left;
    IntrusiveList!Node right;
    left.push_back(&first);
    right.push_back(&second);
    left.splice_back(&right);
    assert(right.empty && left.back is &second);
    auto iterator = left.cursor();
    i32 sum;
    while (iterator.valid)
    {
        sum += iterator.current.value;
        iterator.advance();
    }
    assert(sum == 3);
    left.pop_front();
    left.pop_front();
}

unittest
{
    struct MultiListNode
    {
        ListHook!MultiListNode first_hook;
        ListHook!MultiListNode second_hook;
    }

    MultiListNode shared_node;
    IntrusiveList!(MultiListNode, "first_hook") first_list;
    IntrusiveList!(MultiListNode, "second_hook") second_list;
    first_list.push_back(&shared_node);
    second_list.push_back(&shared_node);
    version (XTB_Checked)
    {
        assert(shared_node.first_hook.linked && shared_node.second_hook.linked);
    }
    first_list.pop_front();
    second_list.pop_front();
}

unittest
{
    struct SingleNode
    {
        ForwardListHook!SingleNode forward_list_hook;
        i32 value;
    }

    SingleNode one;
    one.value = 1;
    SingleNode two;
    two.value = 2;
    IntrusiveQueue!SingleNode queue;
    queue.push_back(&one);
    queue.push_front(&two);
    assert(queue.pop_front() is &two);
    assert(queue.pop_front() is &one && queue.empty);

    IntrusiveStack!SingleNode stack;
    stack.push(&one);
    stack.push(&two);
    assert(stack.pop() is &two);
    assert(stack.pop() is &one && stack.empty);
}

unittest
{
    struct Node
    {
        ForwardListHook!Node forward_list_hook;
        i32 value;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;
    Node third;
    third.value = 3;

    IntrusiveForwardList!Node list;
    assert(list.empty && list.front is null && list.back is null);

    list.push_back(&first);
    list.push_back(&third);
    list.insert_after(&first, &second);
    assert(list.front is &first && list.back is &third);
    assert(first.forward_list_hook.next is &second);
    assert(second.forward_list_hook.next is &third);
    assert(third.forward_list_hook.next is null);

    auto cursor = list.cursor();
    i32 expected = 1;
    while (cursor.valid)
    {
        assert(cursor.current.value == expected);
        ++expected;
        cursor.advance();
    }
    assert(expected == 4);

    // Removing after a node preserves the cached tail unless the removed node
    // was the tail, and detaches only the removed hook.
    assert(list.remove_after(&first) is &second);
    assert(first.forward_list_hook.next is &third);
    assert(list.back is &third);
    version (XTB_Checked)
    {
        assert(!second.forward_list_hook.linked);
    }

    list.insert_after(&third, &second);
    assert(list.back is &second);
    assert(third.forward_list_hook.next is &second);
    version (XTB_Checked)
    {
        assert(second.forward_list_hook.linked);
    }

    assert(list.remove_after(&third) is &second);
    assert(list.back is &third && third.forward_list_hook.next is null);
    version (XTB_Checked)
    {
        assert(!second.forward_list_hook.linked);
    }

    // Splitting transfers a suffix without detaching its hooks. Concatenating
    // the result restores the chain in O(1).
    list.insert_after(&first, &second);
    IntrusiveForwardList!Node suffix = list.split_after(&first);
    assert(list.front is &first && list.back is &first);
    assert(first.forward_list_hook.next is null);
    assert(suffix.front is &second && suffix.back is &third);
    assert(second.forward_list_hook.next is &third);
    version (XTB_Checked)
    {
        assert(first.forward_list_hook.linked);
        assert(second.forward_list_hook.linked);
        assert(third.forward_list_hook.linked);
    }

    list.splice_back(&suffix);
    assert(suffix.empty);
    assert(list.front is &first && list.back is &third);
    assert(first.forward_list_hook.next is &second);
    assert(second.forward_list_hook.next is &third);

    IntrusiveForwardList!Node empty_suffix = list.split_after(&third);
    assert(empty_suffix.empty);
    assert(list.back is &third);

    assert(list.pop_front() is &first);
    assert(list.pop_front() is &second);
    assert(list.pop_front() is &third);
    assert(list.empty && list.front is null && list.back is null);
    version (XTB_Checked)
    {
        assert(!first.forward_list_hook.linked);
        assert(!second.forward_list_hook.linked);
        assert(!third.forward_list_hook.linked);
    }

    // Empty/non-empty concatenation must correctly transfer both header
    // pointers and leave the source reusable.
    IntrusiveForwardList!Node source;
    source.push_back(&first);
    source.push_back(&second);
    list.splice_back(&source);
    assert(source.empty);
    assert(list.front is &first && list.back is &second);
    assert(list.pop_front() is &first);
    assert(list.pop_front() is &second);

    source.push_back(&third);
    IntrusiveForwardList!Node empty;
    list.splice_back(&empty);
    assert(list.empty && empty.empty);
    list.splice_back(&source);
    assert(source.empty && list.front is &third && list.back is &third);
    assert(list.pop_front() is &third && list.empty);
}

unittest
{
    // IntrusiveForwardList and IntrusiveQueue can use different hooks on the same object at the
    // same time. IntrusiveQueue is only a facade over IntrusiveForwardList storage; it does not
    // consume an additional node hook.
    struct Node
    {
        ForwardListHook!Node list_hook;
        ForwardListHook!Node queue_hook;
    }

    Node first;
    Node second;
    IntrusiveForwardList!(Node, "list_hook") list;
    IntrusiveQueue!(Node, "queue_hook") queue;

    list.push_back(&first);
    list.push_back(&second);
    queue.push_back(&second);
    queue.push_back(&first);

    assert(list.front is &first && list.back is &second);
    assert(queue.front is &second && queue.back is &first);
    version (XTB_Checked)
    {
        assert(first.list_hook.linked && first.queue_hook.linked);
        assert(second.list_hook.linked && second.queue_hook.linked);
    }

    assert(list.pop_front() is &first);
    assert(queue.pop_front() is &second);
    version (XTB_Checked)
    {
        assert(!first.list_hook.linked && first.queue_hook.linked);
        assert(second.list_hook.linked && !second.queue_hook.linked);
    }

    assert(list.pop_front() is &second);
    assert(queue.pop_front() is &first);
}

unittest
{
    // Separate hooks are separate memberships. The same node can participate
    // in multiple lists simultaneously without wrapper allocations.
    struct Node
    {
        i32 value;
        ListHook!Node ready_hook;
        ListHook!Node all_hook;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;

    IntrusiveList!(Node, "ready_hook") ready;
    IntrusiveList!(Node, "all_hook") all;

    ready.push_back(&first);
    ready.push_back(&second);
    all.push_back(&second);
    all.push_back(&first);

    assert(ready.front is &first && ready.back is &second);
    assert(all.front is &second && all.back is &first);
    assert(first.ready_hook.next is &second);
    assert(first.all_hook.previous is &second);
    version (XTB_Checked)
    {
        assert(first.ready_hook.linked);
        assert(first.all_hook.linked);
        assert(second.ready_hook.linked);
        assert(second.all_hook.linked);
    }

    // Removing one hook must not affect the node's other membership.
    ready.remove(&first);
    assert(ready.front is &second && ready.back is &second);
    assert(all.back is &first);
    version (XTB_Checked)
    {
        assert(!first.ready_hook.linked);
        assert(first.all_hook.linked);
    }

    // A detached hook is immediately reusable.
    ready.push_front(&first);
    assert(ready.front is &first && ready.back is &second);
    version (XTB_Checked)
    {
        assert(first.ready_hook.linked);
    }

    ready.remove(&first);
    ready.remove(&second);
    all.remove(&first);
    all.remove(&second);
    version (XTB_Checked)
    {
        assert(!first.ready_hook.linked && !first.all_hook.linked);
        assert(!second.ready_hook.linked && !second.all_hook.linked);
    }
}

unittest
{
    // Forward hooks have the same independent-membership rule. One node may be
    // queued and stacked at the same time when each structure has its own hook.
    struct Node
    {
        i32 value;
        ForwardListHook!Node queue_hook;
        ForwardListHook!Node stack_hook;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;

    IntrusiveQueue!(Node, "queue_hook") queue;
    IntrusiveStack!(Node, "stack_hook") stack;

    queue.push_back(&first);
    queue.push_back(&second);
    stack.push(&first);
    stack.push(&second);

    assert(queue.front is &first && queue.back is &second);
    assert(stack.top is &second);
    version (XTB_Checked)
    {
        assert(first.queue_hook.linked && first.stack_hook.linked);
        assert(second.queue_hook.linked && second.stack_hook.linked);
    }

    assert(queue.pop_front() is &first);
    assert(stack.pop() is &second);
    version (XTB_Checked)
    {
        assert(!first.queue_hook.linked);
        assert(first.stack_hook.linked);
        assert(second.queue_hook.linked);
        assert(!second.stack_hook.linked);
    }

    // Reuse the detached hooks while the independent memberships remain live.
    queue.push_front(&first);
    stack.push(&second);
    assert(queue.pop_front() is &first);
    assert(queue.pop_front() is &second);
    assert(stack.pop() is &second);
    assert(stack.pop() is &first);
    assert(queue.empty && stack.empty);
}

unittest
{
    // Concatenation transfers list ownership without changing per-hook linked
    // state, and popping from the destination detaches hooks normally.
    struct Node
    {
        i32 value;
        ListHook!Node list_hook;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;
    Node third;
    third.value = 3;

    IntrusiveList!Node left;
    IntrusiveList!Node right;
    left.push_back(&first);
    right.push_back(&second);
    right.push_back(&third);
    left.splice_back(&right);

    assert(right.empty);
    assert(left.front is &first && left.back is &third);
    assert(first.list_hook.next is &second);
    assert(second.list_hook.previous is &first);
    assert(second.list_hook.next is &third);
    assert(third.list_hook.previous is &second);
    version (XTB_Checked)
    {
        assert(first.list_hook.linked);
        assert(second.list_hook.linked);
        assert(third.list_hook.linked);
    }

    assert(left.pop_front() is &first);
    assert(left.pop_front() is &second);
    assert(left.pop_front() is &third);
    assert(left.empty);
    version (XTB_Checked)
    {
        assert(!first.list_hook.linked);
        assert(!second.list_hook.linked);
        assert(!third.list_hook.linked);
    }
}

unittest
{
    struct ListNode
    {
        ListHook!ListNode list_hook;
        i32 value;
    }

    ListNode first;
    first.value = 1;
    ListNode second;
    second.value = 2;
    ListNode third;
    third.value = 3;

    IntrusiveList!ListNode list;
    list.push_back(&first);
    list.push_back(&second);
    list.push_back(&third);

    i32 list_value;
    foreach (node; list)
    {
        static assert(is(typeof(node) == ListNode*));
        list_value = list_value * 10 + node.value;
    }
    assert(list_value == 123);

    const(IntrusiveList!ListNode)* const_list = &list;
    i32 const_list_value;
    foreach (node; *const_list)
    {
        static assert(is(typeof(node) == const(ListNode)*));
        const_list_value += node.value;
    }
    assert(const_list_value == 6);

    // The implementation snapshots the next hook before the body runs, so
    // removing the current node is explicitly supported.
    foreach (node; list)
        list.remove(node);
    assert(list.empty);

    struct ForwardNode
    {
        ForwardListHook!ForwardNode list_hook;
        ForwardListHook!ForwardNode queue_hook;
        ForwardListHook!ForwardNode stack_hook;
        i32 value;
    }

    ForwardNode one;
    one.value = 1;
    ForwardNode two;
    two.value = 2;
    ForwardNode three;
    three.value = 3;

    IntrusiveForwardList!(ForwardNode, "list_hook") forward_list;
    forward_list.push_back(&one);
    forward_list.push_back(&two);
    forward_list.push_back(&three);

    i32 forward_value;
    foreach (node; forward_list)
        forward_value = forward_value * 10 + node.value;
    assert(forward_value == 123);

    IntrusiveQueue!(ForwardNode, "queue_hook") queue;
    queue.push_back(&one);
    queue.push_back(&two);
    queue.push_back(&three);

    i32 queue_value;
    foreach (node; queue)
        queue_value = queue_value * 10 + node.value;
    assert(queue_value == 123);

    IntrusiveStack!(ForwardNode, "stack_hook") stack;
    stack.push(&one);
    stack.push(&two);
    stack.push(&three);

    i32 stack_value;
    foreach (node; stack)
        stack_value = stack_value * 10 + node.value;
    assert(stack_value == 321);

    const(IntrusiveForwardList!(ForwardNode, "list_hook"))* const_forward_list = &forward_list;
    const(IntrusiveQueue!(ForwardNode, "queue_hook"))* const_queue = &queue;
    const(IntrusiveStack!(ForwardNode, "stack_hook"))* const_stack = &stack;

    i32 const_value;
    foreach (node; *const_forward_list)
    {
        static assert(is(typeof(node) == const(ForwardNode)*));
        const_value += node.value;
    }
    foreach (node; *const_queue)
    {
        static assert(is(typeof(node) == const(ForwardNode)*));
        const_value += node.value;
    }
    foreach (node; *const_stack)
    {
        static assert(is(typeof(node) == const(ForwardNode)*));
        const_value += node.value;
    }
    assert(const_value == 18);
}
