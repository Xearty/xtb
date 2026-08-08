module xtb.core.intrusive_list;

version (XTB_Checked)
    import xtb.core.panic : require;

nothrow @nogc:

/// One intrusive doubly linked-list membership hook.
///
/// A node may contain multiple `ListHook!Node` fields and therefore belong to
/// multiple lists at the same time. Each individual hook may belong to at most
/// one list. `XTB_Checked` builds track that per-hook membership and reject
/// double insertion. The membership flag and `linked` diagnostic accessor do
/// not exist without `XTB_Checked`, where correct hook ownership is a caller
/// invariant.
struct ListHook(Node)
{
    private Node* previous_;
    private Node* next_;

    version (XTB_Checked)
    {
        private bool linked_;

        /// Whether this hook currently belongs to an intrusive list.
        /// Available only in checked builds.
        bool linked() const pure @safe
        {
            return linked_;
        }
    }

    inout(Node)* previous() inout return pure
    {
        return previous_;
    }

    inout(Node)* next() inout return pure
    {
        return next_;
    }
}

/// One intrusive forward-list membership hook used by forward lists, queues, and stacks.
///
/// A node may contain multiple `ForwardListHook!Node` fields and therefore belong
/// to multiple intrusive structures at the same time. Each individual hook may
/// belong to at most one structure. `XTB_Checked` builds track that per-hook
/// membership and reject double insertion. The membership flag and `linked`
/// diagnostic accessor do not exist without `XTB_Checked`.
struct ForwardListHook(Node)
{
    private Node* next_;

    version (XTB_Checked)
    {
        private bool linked_;

        /// Whether this hook currently belongs to an intrusive structure.
        /// Available only in checked builds.
        bool linked() const pure @safe
        {
            return linked_;
        }
    }

    inout(Node)* next() inout return pure
    {
        return next_;
    }
}

private ref ListHook!Node listHookOf(Node, string hookMember)(Node* node)
{
    return __traits(getMember, *node, hookMember);
}

private ref const(ListHook!Node) listHookOf(Node, string hookMember)(const(Node)* node)
{
    return __traits(getMember, *node, hookMember);
}

private ref ForwardListHook!Node forwardListHookOf(Node, string hookMember)(Node* node)
{
    return __traits(getMember, *node, hookMember);
}

private ref const(ForwardListHook!Node) forwardListHookOf(Node, string hookMember)(const(Node)* node)
{
    return __traits(getMember, *node, hookMember);
}

version (XTB_Checked)
{
    private void requireUnlinked(Node)(ref ListHook!Node link)
    {
        require(!link.linked_, "list hook is already linked");
    }

    private void requireUnlinked(Node)(ref ForwardListHook!Node link)
    {
        require(!link.linked_, "forward hook is already linked");
    }
}

/// Intrusive doubly linked list using `Node.hookMember` as its membership hook.
struct IntrusiveList(Node, string hookMember = "listHook")
{
    static assert(__traits(hasMember, Node, hookMember),
        "IntrusiveList node is missing its " ~ hookMember ~ " hook");
    static assert(is(typeof(__traits(getMember, Node.init, hookMember)) == ListHook!Node),
        "IntrusiveList hook must be ListHook!Node");

    private Node* front_;
    private Node* back_;

    @disable this(this);

    bool empty() const pure @safe
    {
        return front_ is null;
    }

    inout(Node)* front() inout return pure
    {
        return front_;
    }

    inout(Node)* back() inout return pure
    {
        return back_;
    }

    /// Iterates nodes from front to back without modifying the list.
    ///
    /// The next hook is captured before invoking the callback, so removing the
    /// current node from this list during the loop does not invalidate the
    /// traversal. Other structural mutation during iteration is unspecified.
    int opApply(
        scope int delegate(Node*) nothrow @nogc callback,
    ) nothrow @nogc
    {
        version (XTB_Checked)
            require(callback !is null, "intrusive-list iteration callback is null");
        for (Node* current = front_; current !is null;)
        {
            Node* next = listHookOf!(Node, hookMember)(current).next_;
            const control = callback(current);
            if (control != 0)
                return control;
            current = next;
        }
        return 0;
    }

    /// Const iteration yields pointers to const nodes.
    int opApply(
        scope int delegate(const(Node)*) nothrow @nogc callback,
    ) const nothrow @nogc
    {
        version (XTB_Checked)
            require(callback !is null, "intrusive-list iteration callback is null");
        for (const(Node)* current = front_; current !is null;)
        {
            const(Node)* next = listHookOf!(Node, hookMember)(current).next_;
            const control = callback(current);
            if (control != 0)
                return control;
            current = next;
        }
        return 0;
    }

    private bool contains(Node* node)
    {
        for (Node* current = front_; current !is null; current = listHookOf!(Node, hookMember)(current)
            .next_)
        {
            if (current is node)
                return true;
        }
        return false;
    }

    void pushBack(Node* node)
    {
        version (XTB_Checked)
            require(node !is null, "cannot insert a null list node");
        ref link = listHookOf!(Node, hookMember)(node);
        version (XTB_Checked) requireUnlinked(link);

        link.previous_ = back_;
        link.next_ = null;
        version (XTB_Checked) link.linked_ = true;
        if (back_ is null)
            front_ = node;
        else
            listHookOf!(Node, hookMember)(back_).next_ = node;
        back_ = node;
    }

    void pushFront(Node* node)
    {
        version (XTB_Checked)
            require(node !is null, "cannot insert a null list node");
        ref link = listHookOf!(Node, hookMember)(node);
        version (XTB_Checked) requireUnlinked(link);

        link.previous_ = null;
        link.next_ = front_;
        version (XTB_Checked) link.linked_ = true;
        if (front_ is null)
            back_ = node;
        else
            listHookOf!(Node, hookMember)(front_).previous_ = node;
        front_ = node;
    }

    void insertAfter(Node* position, Node* node)
    {
        version (XTB_Checked)
        {
            require(position !is null && node !is null,
                "cannot insert a null list node");
            require(contains(position), "position is not in this list");
        }
        if (position is back_)
        {
            pushBack(node);
            return;
        }

        ref positionLink = listHookOf!(Node, hookMember)(position);
        ref link = listHookOf!(Node, hookMember)(node);
        version (XTB_Checked) requireUnlinked(link);
        link.previous_ = position;
        link.next_ = positionLink.next_;
        version (XTB_Checked) link.linked_ = true;
        listHookOf!(Node, hookMember)(positionLink.next_).previous_ = node;
        positionLink.next_ = node;
    }

    void insertBefore(Node* position, Node* node)
    {
        version (XTB_Checked)
        {
            require(position !is null && node !is null,
                "cannot insert a null list node");
            require(contains(position), "position is not in this list");
        }
        if (position is front_)
        {
            pushFront(node);
            return;
        }

        ref positionLink = listHookOf!(Node, hookMember)(position);
        ref link = listHookOf!(Node, hookMember)(node);
        version (XTB_Checked) requireUnlinked(link);
        link.next_ = position;
        link.previous_ = positionLink.previous_;
        version (XTB_Checked) link.linked_ = true;
        listHookOf!(Node, hookMember)(positionLink.previous_).next_ = node;
        positionLink.previous_ = node;
    }

    void remove(Node* node)
    {
        version (XTB_Checked)
        {
            require(node !is null, "cannot remove a null list node");
            require(contains(node), "node is not in this list");
        }
        ref link = listHookOf!(Node, hookMember)(node);

        if (link.previous_ is null)
            front_ = link.next_;
        else
            listHookOf!(Node, hookMember)(link.previous_).next_ = link.next_;

        if (link.next_ is null)
            back_ = link.previous_;
        else
            listHookOf!(Node, hookMember)(link.next_).previous_ = link.previous_;

        link = ListHook!Node.init;
    }

    Node* popFront()
    {
        version (XTB_Checked)
            require(front_ !is null, "cannot pop an empty list");
        Node* result = front_;
        remove(result);
        return result;
    }

    Node* popBack()
    {
        version (XTB_Checked)
            require(back_ !is null, "cannot pop an empty list");
        Node* result = back_;
        remove(result);
        return result;
    }

    void spliceBack(ref IntrusiveList source)
    {
        version (XTB_Checked)
            require(&this !is &source, "cannot spliceBack a list with itself");
        if (source.empty)
            return;
        if (empty)
        {
            front_ = source.front_;
            back_ = source.back_;
        }
        else
        {
            listHookOf!(Node, hookMember)(back_).next_ = source.front_;
            listHookOf!(Node, hookMember)(source.front_).previous_ = back_;
            back_ = source.back_;
        }
        source.front_ = null;
        source.back_ = null;
    }

    IntrusiveListCursor!(Node, hookMember) cursor()
    {
        return IntrusiveListCursor!(Node, hookMember)(front_, false);
    }

    IntrusiveListCursor!(Node, hookMember) reverseCursor()
    {
        return IntrusiveListCursor!(Node, hookMember)(back_, true);
    }
}

struct IntrusiveListCursor(Node, string hookMember)
{
    private Node* current_;
    private bool reverse_;

    bool valid() const pure @safe
    {
        return current_ !is null;
    }

    Node* current() return
    {
        version (XTB_Checked)
            require(valid, "invalid list cursor");
        return current_;
    }

    void advance()
    {
        version (XTB_Checked)
            require(valid, "invalid list cursor");
        ref link = listHookOf!(Node, hookMember)(current_);
        current_ = reverse_ ? link.previous_ : link.next_;
    }
}

/// General intrusive singly linked list using `Node.hookMember` as its membership hook.
///
/// The list stores both its first and last node so insertion at either end is
/// O(1). `IntrusiveQueue` is implemented as a restricted queue facade over this type;
/// `IntrusiveStack` remains separate because it needs only one container pointer.
struct IntrusiveForwardList(Node, string hookMember = "forwardListHook")
{
    static assert(__traits(hasMember, Node, hookMember),
        "IntrusiveForwardList node is missing its " ~ hookMember ~ " hook");
    static assert(is(typeof(__traits(getMember, Node.init, hookMember)) == ForwardListHook!Node),
        "IntrusiveForwardList hook must be ForwardListHook!Node");

    private Node* front_;
    private Node* back_;

    @disable this(this);

    bool empty() const pure @safe
    {
        return front_ is null;
    }

    inout(Node)* front() inout return pure
    {
        return front_;
    }

    inout(Node)* back() inout return pure
    {
        return back_;
    }

    /// Iterates nodes from front to back without modifying the list.
    ///
    /// The next hook is captured before invoking the callback, so removing the
    /// current node from this list during the loop does not invalidate the
    /// traversal. Other structural mutation during iteration is unspecified.
    int opApply(
        scope int delegate(Node*) nothrow @nogc callback,
    ) nothrow @nogc
    {
        version (XTB_Checked)
            require(callback !is null, "intrusive-forward-list iteration callback is null");
        for (Node* current = front_; current !is null;)
        {
            Node* next = forwardListHookOf!(Node, hookMember)(current).next_;
            const control = callback(current);
            if (control != 0)
                return control;
            current = next;
        }
        return 0;
    }

    /// Const iteration yields pointers to const nodes.
    int opApply(
        scope int delegate(const(Node)*) nothrow @nogc callback,
    ) const nothrow @nogc
    {
        version (XTB_Checked)
            require(callback !is null, "intrusive-forward-list iteration callback is null");
        for (const(Node)* current = front_; current !is null;)
        {
            const(Node)* next = forwardListHookOf!(Node, hookMember)(current).next_;
            const control = callback(current);
            if (control != 0)
                return control;
            current = next;
        }
        return 0;
    }

    private bool contains(Node* node)
    {
        for (Node* current = front_; current !is null;
             current = forwardListHookOf!(Node, hookMember)(current).next_)
        {
            if (current is node)
                return true;
        }
        return false;
    }

    /// Inserts `node` at the front in O(1).
    void pushFront(Node* node)
    {
        version (XTB_Checked)
            require(node !is null, "cannot insert a null forward-list node");
        ref link = forwardListHookOf!(Node, hookMember)(node);
        version (XTB_Checked) requireUnlinked(link);

        link.next_ = front_;
        version (XTB_Checked) link.linked_ = true;
        front_ = node;
        if (back_ is null)
            back_ = node;
    }

    /// Inserts `node` at the back in O(1).
    void pushBack(Node* node)
    {
        version (XTB_Checked)
            require(node !is null, "cannot insert a null forward-list node");
        ref link = forwardListHookOf!(Node, hookMember)(node);
        version (XTB_Checked) requireUnlinked(link);

        link.next_ = null;
        version (XTB_Checked) link.linked_ = true;
        if (back_ is null)
            front_ = node;
        else
            forwardListHookOf!(Node, hookMember)(back_).next_ = node;
        back_ = node;
    }

    /// Inserts `node` immediately after `position`.
    ///
    /// This is O(1); checked builds verify that `position` belongs to this
    /// list, which requires an O(n) validation walk.
    void insertAfter(Node* position, Node* node)
    {
        version (XTB_Checked)
        {
            require(position !is null && node !is null,
                "cannot insert relative to a null forward-list node");
            require(contains(position), "position is not in this forward list");
        }
        if (position is back_)
        {
            pushBack(node);
            return;
        }

        ref positionLink = forwardListHookOf!(Node, hookMember)(position);
        ref link = forwardListHookOf!(Node, hookMember)(node);
        version (XTB_Checked) requireUnlinked(link);
        link.next_ = positionLink.next_;
        version (XTB_Checked) link.linked_ = true;
        positionLink.next_ = node;
    }

    /// Removes and returns the node immediately after `position`.
    ///
    /// This is O(1); checked builds verify that `position` belongs to this
    /// list, which requires an O(n) validation walk.
    Node* removeAfter(Node* position)
    {
        version (XTB_Checked)
        {
            require(position !is null, "cannot remove after a null forward-list node");
            require(contains(position), "position is not in this forward list");
        }

        ref positionLink = forwardListHookOf!(Node, hookMember)(position);
        version (XTB_Checked)
            require(positionLink.next_ !is null, "no forward-list node exists after position");

        Node* result = positionLink.next_;
        ref link = forwardListHookOf!(Node, hookMember)(result);
        positionLink.next_ = link.next_;
        if (result is back_)
            back_ = position;
        link = ForwardListHook!Node.init;
        return result;
    }

    /// Removes and returns the first node in O(1).
    Node* popFront()
    {
        version (XTB_Checked)
            require(front_ !is null, "cannot pop an empty forward list");
        Node* result = front_;
        ref link = forwardListHookOf!(Node, hookMember)(result);
        front_ = link.next_;
        link = ForwardListHook!Node.init;
        if (front_ is null)
            back_ = null;
        return result;
    }

    /// Appends all nodes from `source` in O(1), leaving `source` empty.
    void spliceBack(ref IntrusiveForwardList source)
    {
        version (XTB_Checked)
            require(&this !is &source, "cannot spliceBack a forward list with itself");
        if (source.empty)
            return;
        if (empty)
        {
            front_ = source.front_;
            back_ = source.back_;
        }
        else
        {
            forwardListHookOf!(Node, hookMember)(back_).next_ = source.front_;
            back_ = source.back_;
        }
        source.front_ = null;
        source.back_ = null;
    }

    /// Detaches all nodes after `position` and returns them as a new list.
    ///
    /// Existing hook membership remains live because nodes stay linked, only
    /// the owning list header changes. The returned list is empty when
    /// `position` is already the last node.
    IntrusiveForwardList splitAfter(Node* position)
    {
        version (XTB_Checked)
        {
            require(position !is null, "cannot split after a null forward-list node");
            require(contains(position), "position is not in this forward list");
        }

        IntrusiveForwardList result;
        ref positionLink = forwardListHookOf!(Node, hookMember)(position);
        result.front_ = positionLink.next_;
        if (result.front_ !is null)
        {
            result.back_ = back_;
            back_ = position;
            positionLink.next_ = null;
        }
        return result;
    }

    IntrusiveForwardListCursor!(Node, hookMember) cursor()
    {
        return IntrusiveForwardListCursor!(Node, hookMember)(front_);
    }
}

/// Forward-only cursor over an intrusive `IntrusiveForwardList`.
struct IntrusiveForwardListCursor(Node, string hookMember)
{
    private Node* current_;

    bool valid() const pure @safe
    {
        return current_ !is null;
    }

    Node* current() return
    {
        version (XTB_Checked)
            require(valid, "invalid forward-list cursor");
        return current_;
    }

    void advance()
    {
        version (XTB_Checked)
            require(valid, "invalid forward-list cursor");
        current_ = forwardListHookOf!(Node, hookMember)(current_).next_;
    }
}

/// Intrusive FIFO queue using `Node.hookMember` as its membership hook.
///
/// IntrusiveQueue is intentionally a narrow facade over `IntrusiveForwardList`: it preserves
/// XTB's existing front/back queue operations while hiding arbitrary
/// insert-after, split, spliceBack, and cursor mutation.
struct IntrusiveQueue(Node, string hookMember = "forwardListHook")
{
    static assert(__traits(hasMember, Node, hookMember),
        "IntrusiveQueue node is missing its " ~ hookMember ~ " hook");
    static assert(is(typeof(__traits(getMember, Node.init, hookMember)) == ForwardListHook!Node),
        "IntrusiveQueue hook must be ForwardListHook!Node");

    private IntrusiveForwardList!(Node, hookMember) list_;

    @disable this(this);

    bool empty() const pure @safe
    {
        return list_.empty;
    }

    inout(Node)* front() inout return pure
    {
        return list_.front;
    }

    inout(Node)* back() inout return pure
    {
        return list_.back;
    }

    /// Iterates queued nodes from front to back.
    int opApply(
        scope int delegate(Node*) nothrow @nogc callback,
    ) nothrow @nogc
    {
        return list_.opApply(callback);
    }

    /// Const iteration yields pointers to const nodes.
    int opApply(
        scope int delegate(const(Node)*) nothrow @nogc callback,
    ) const nothrow @nogc
    {
        return list_.opApply(callback);
    }

    void pushBack(Node* node)
    {
        list_.pushBack(node);
    }

    void pushFront(Node* node)
    {
        list_.pushFront(node);
    }

    Node* popFront()
    {
        return list_.popFront();
    }
}

/// Intrusive LIFO stack using `Node.hookMember` as its membership hook.
struct IntrusiveStack(Node, string hookMember = "forwardListHook")
{
    static assert(__traits(hasMember, Node, hookMember),
        "IntrusiveStack node is missing its " ~ hookMember ~ " hook");
    static assert(is(typeof(__traits(getMember, Node.init, hookMember)) == ForwardListHook!Node),
        "IntrusiveStack hook must be ForwardListHook!Node");

    private Node* top_;

    @disable this(this);

    bool empty() const pure @safe
    {
        return top_ is null;
    }

    inout(Node)* top() inout return pure
    {
        return top_;
    }

    /// Iterates nodes from the current top toward the bottom.
    ///
    /// The next hook is captured before invoking the callback, so popping the
    /// current node during the loop does not invalidate the traversal. Other
    /// structural mutation during iteration is unspecified.
    int opApply(
        scope int delegate(Node*) nothrow @nogc callback,
    ) nothrow @nogc
    {
        version (XTB_Checked)
            require(callback !is null, "intrusive-stack iteration callback is null");
        for (Node* current = top_; current !is null;)
        {
            Node* next = forwardListHookOf!(Node, hookMember)(current).next_;
            const control = callback(current);
            if (control != 0)
                return control;
            current = next;
        }
        return 0;
    }

    /// Const iteration yields pointers to const nodes.
    int opApply(
        scope int delegate(const(Node)*) nothrow @nogc callback,
    ) const nothrow @nogc
    {
        version (XTB_Checked)
            require(callback !is null, "intrusive-stack iteration callback is null");
        for (const(Node)* current = top_; current !is null;)
        {
            const(Node)* next = forwardListHookOf!(Node, hookMember)(current).next_;
            const control = callback(current);
            if (control != 0)
                return control;
            current = next;
        }
        return 0;
    }

    void push(Node* node)
    {
        version (XTB_Checked)
            require(node !is null, "cannot insert a null stack node");
        ref link = forwardListHookOf!(Node, hookMember)(node);
        version (XTB_Checked) requireUnlinked(link);

        link.next_ = top_;
        version (XTB_Checked) link.linked_ = true;
        top_ = node;
    }

    Node* pop()
    {
        version (XTB_Checked)
            require(top_ !is null, "cannot pop an empty stack");
        Node* result = top_;
        ref link = forwardListHookOf!(Node, hookMember)(result);
        top_ = link.next_;
        link = ForwardListHook!Node.init;
        return result;
    }
}

unittest
{
    struct Node
    {
        ListHook!Node listHook;
        int value;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;
    Node middle;
    middle.value = 3;

    IntrusiveList!Node list;
    list.pushBack(&first);
    list.pushBack(&second);
    list.insertBefore(&second, &middle);
    assert(list.front.value == 1);
    assert(list.back.value == 2 && list.front.listHook.next is &middle);
    assert(list.popFront() is &first);
    version (XTB_Checked) assert(!first.listHook.linked);
    assert(list.popBack() is &second);
    list.remove(&middle);
    assert(list.empty);

    IntrusiveList!Node left;
    IntrusiveList!Node right;
    left.pushBack(&first);
    right.pushBack(&second);
    left.spliceBack(right);
    assert(right.empty && left.back is &second);
    auto iterator = left.cursor();
    int sum;
    while (iterator.valid)
    {
        sum += iterator.current.value;
        iterator.advance();
    }
    assert(sum == 3);
    left.popFront();
    left.popFront();

    struct MultiListNode
    {
        ListHook!MultiListNode firstHook;
        ListHook!MultiListNode secondHook;
    }

    MultiListNode sharedNode;
    IntrusiveList!(MultiListNode, "firstHook") firstList;
    IntrusiveList!(MultiListNode, "secondHook") secondList;
    firstList.pushBack(&sharedNode);
    secondList.pushBack(&sharedNode);
    version (XTB_Checked) assert(sharedNode.firstHook.linked && sharedNode.secondHook.linked);
    firstList.popFront();
    secondList.popFront();

    struct SingleNode
    {
        ForwardListHook!SingleNode forwardListHook;
        int value;
    }

    SingleNode one;
    one.value = 1;
    SingleNode two;
    two.value = 2;
    IntrusiveQueue!SingleNode queue;
    queue.pushBack(&one);
    queue.pushFront(&two);
    assert(queue.popFront() is &two);
    assert(queue.popFront() is &one && queue.empty);

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
        ForwardListHook!Node forwardListHook;
        int value;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;
    Node third;
    third.value = 3;

    IntrusiveForwardList!Node list;
    assert(list.empty && list.front is null && list.back is null);

    list.pushBack(&first);
    list.pushBack(&third);
    list.insertAfter(&first, &second);
    assert(list.front is &first && list.back is &third);
    assert(first.forwardListHook.next is &second);
    assert(second.forwardListHook.next is &third);
    assert(third.forwardListHook.next is null);

    auto cursor = list.cursor();
    int expected = 1;
    while (cursor.valid)
    {
        assert(cursor.current.value == expected);
        ++expected;
        cursor.advance();
    }
    assert(expected == 4);

    // Removing after a node preserves the cached tail unless the removed node
    // was the tail, and detaches only the removed hook.
    assert(list.removeAfter(&first) is &second);
    assert(first.forwardListHook.next is &third);
    assert(list.back is &third);
    version (XTB_Checked) assert(!second.forwardListHook.linked);

    list.insertAfter(&third, &second);
    assert(list.back is &second);
    assert(third.forwardListHook.next is &second);
    version (XTB_Checked) assert(second.forwardListHook.linked);

    assert(list.removeAfter(&third) is &second);
    assert(list.back is &third && third.forwardListHook.next is null);
    version (XTB_Checked) assert(!second.forwardListHook.linked);

    // Splitting transfers a suffix without detaching its hooks. Concatenating
    // the result restores the chain in O(1).
    list.insertAfter(&first, &second);
    IntrusiveForwardList!Node suffix = list.splitAfter(&first);
    assert(list.front is &first && list.back is &first);
    assert(first.forwardListHook.next is null);
    assert(suffix.front is &second && suffix.back is &third);
    assert(second.forwardListHook.next is &third);
    version (XTB_Checked)
    {
        assert(first.forwardListHook.linked);
        assert(second.forwardListHook.linked);
        assert(third.forwardListHook.linked);
    }

    list.spliceBack(suffix);
    assert(suffix.empty);
    assert(list.front is &first && list.back is &third);
    assert(first.forwardListHook.next is &second);
    assert(second.forwardListHook.next is &third);

    IntrusiveForwardList!Node emptySuffix = list.splitAfter(&third);
    assert(emptySuffix.empty);
    assert(list.back is &third);

    assert(list.popFront() is &first);
    assert(list.popFront() is &second);
    assert(list.popFront() is &third);
    assert(list.empty && list.front is null && list.back is null);
    version (XTB_Checked)
    {
        assert(!first.forwardListHook.linked);
        assert(!second.forwardListHook.linked);
        assert(!third.forwardListHook.linked);
    }

    // Empty/non-empty concatenation must correctly transfer both header
    // pointers and leave the source reusable.
    IntrusiveForwardList!Node source;
    source.pushBack(&first);
    source.pushBack(&second);
    list.spliceBack(source);
    assert(source.empty);
    assert(list.front is &first && list.back is &second);
    assert(list.popFront() is &first);
    assert(list.popFront() is &second);

    source.pushBack(&third);
    IntrusiveForwardList!Node empty;
    list.spliceBack(empty);
    assert(list.empty && empty.empty);
    list.spliceBack(source);
    assert(source.empty && list.front is &third && list.back is &third);
    assert(list.popFront() is &third && list.empty);
}

unittest
{
    // IntrusiveForwardList and IntrusiveQueue can use different hooks on the same object at the
    // same time. IntrusiveQueue is only a facade over IntrusiveForwardList storage; it does not
    // consume an additional node hook.
    struct Node
    {
        ForwardListHook!Node listHook;
        ForwardListHook!Node queueHook;
    }

    Node first;
    Node second;
    IntrusiveForwardList!(Node, "listHook") list;
    IntrusiveQueue!(Node, "queueHook") queue;

    list.pushBack(&first);
    list.pushBack(&second);
    queue.pushBack(&second);
    queue.pushBack(&first);

    assert(list.front is &first && list.back is &second);
    assert(queue.front is &second && queue.back is &first);
    version (XTB_Checked)
    {
        assert(first.listHook.linked && first.queueHook.linked);
        assert(second.listHook.linked && second.queueHook.linked);
    }

    assert(list.popFront() is &first);
    assert(queue.popFront() is &second);
    version (XTB_Checked)
    {
        assert(!first.listHook.linked && first.queueHook.linked);
        assert(second.listHook.linked && !second.queueHook.linked);
    }

    assert(list.popFront() is &second);
    assert(queue.popFront() is &first);
}

private struct IntrusiveContainerLayoutProbe
{
    ForwardListHook!IntrusiveContainerLayoutProbe forwardListHook;
}

static assert(IntrusiveForwardList!IntrusiveContainerLayoutProbe.sizeof == size_t.sizeof * 2);
static assert(IntrusiveQueue!IntrusiveContainerLayoutProbe.sizeof == IntrusiveForwardList!IntrusiveContainerLayoutProbe.sizeof);
static assert(IntrusiveStack!IntrusiveContainerLayoutProbe.sizeof == size_t.sizeof);
static assert(__traits(hasMember, IntrusiveForwardList!IntrusiveContainerLayoutProbe, "insertAfter"));
static assert(__traits(hasMember, IntrusiveForwardList!IntrusiveContainerLayoutProbe, "removeAfter"));
static assert(__traits(hasMember, IntrusiveForwardList!IntrusiveContainerLayoutProbe, "splitAfter"));
static assert(!__traits(hasMember, IntrusiveQueue!IntrusiveContainerLayoutProbe, "insertAfter"));
static assert(!__traits(hasMember, IntrusiveQueue!IntrusiveContainerLayoutProbe, "removeAfter"));
static assert(!__traits(hasMember, IntrusiveQueue!IntrusiveContainerLayoutProbe, "splitAfter"));

private struct IntrusiveLinkLayoutProbe
{
}

version (XTB_Checked)
{
    static assert(__traits(hasMember, ListHook!IntrusiveLinkLayoutProbe, "linked"));
    static assert(__traits(hasMember, ForwardListHook!IntrusiveLinkLayoutProbe, "linked"));
    static assert(ListHook!IntrusiveLinkLayoutProbe.sizeof > size_t.sizeof * 2);
    static assert(ForwardListHook!IntrusiveLinkLayoutProbe.sizeof > size_t.sizeof);
}
else
{
    // Unchecked hooks contain structural links only. Membership bookkeeping and
    // its public diagnostic accessor must contribute zero storage/API surface.
    static assert(!__traits(hasMember, ListHook!IntrusiveLinkLayoutProbe, "linked"));
    static assert(!__traits(hasMember, ForwardListHook!IntrusiveLinkLayoutProbe, "linked"));
    static assert(ListHook!IntrusiveLinkLayoutProbe.sizeof == size_t.sizeof * 2);
    static assert(ForwardListHook!IntrusiveLinkLayoutProbe.sizeof == size_t.sizeof);
}

unittest
{
    // Separate hooks are separate memberships. The same node can participate
    // in multiple lists simultaneously without wrapper allocations.
    struct Node
    {
        int value;
        ListHook!Node readyHook;
        ListHook!Node allHook;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;

    IntrusiveList!(Node, "readyHook") ready;
    IntrusiveList!(Node, "allHook") all;

    ready.pushBack(&first);
    ready.pushBack(&second);
    all.pushBack(&second);
    all.pushBack(&first);

    assert(ready.front is &first && ready.back is &second);
    assert(all.front is &second && all.back is &first);
    assert(first.readyHook.next is &second);
    assert(first.allHook.previous is &second);
    version (XTB_Checked)
    {
        assert(first.readyHook.linked);
        assert(first.allHook.linked);
        assert(second.readyHook.linked);
        assert(second.allHook.linked);
    }

    // Removing one hook must not affect the node's other membership.
    ready.remove(&first);
    assert(ready.front is &second && ready.back is &second);
    assert(all.back is &first);
    version (XTB_Checked)
    {
        assert(!first.readyHook.linked);
        assert(first.allHook.linked);
    }

    // A detached hook is immediately reusable.
    ready.pushFront(&first);
    assert(ready.front is &first && ready.back is &second);
    version (XTB_Checked) assert(first.readyHook.linked);

    ready.remove(&first);
    ready.remove(&second);
    all.remove(&first);
    all.remove(&second);
    version (XTB_Checked)
    {
        assert(!first.readyHook.linked && !first.allHook.linked);
        assert(!second.readyHook.linked && !second.allHook.linked);
    }
}

unittest
{
    // Forward hooks have the same independent-membership rule. One node may be
    // queued and stacked at the same time when each structure has its own hook.
    struct Node
    {
        int value;
        ForwardListHook!Node queueHook;
        ForwardListHook!Node stackHook;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;

    IntrusiveQueue!(Node, "queueHook") queue;
    IntrusiveStack!(Node, "stackHook") stack;

    queue.pushBack(&first);
    queue.pushBack(&second);
    stack.push(&first);
    stack.push(&second);

    assert(queue.front is &first && queue.back is &second);
    assert(stack.top is &second);
    version (XTB_Checked)
    {
        assert(first.queueHook.linked && first.stackHook.linked);
        assert(second.queueHook.linked && second.stackHook.linked);
    }

    assert(queue.popFront() is &first);
    assert(stack.pop() is &second);
    version (XTB_Checked)
    {
        assert(!first.queueHook.linked);
        assert(first.stackHook.linked);
        assert(second.queueHook.linked);
        assert(!second.stackHook.linked);
    }

    // Reuse the detached hooks while the independent memberships remain live.
    queue.pushFront(&first);
    stack.push(&second);
    assert(queue.popFront() is &first);
    assert(queue.popFront() is &second);
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
        int value;
        ListHook!Node listHook;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;
    Node third;
    third.value = 3;

    IntrusiveList!Node left;
    IntrusiveList!Node right;
    left.pushBack(&first);
    right.pushBack(&second);
    right.pushBack(&third);
    left.spliceBack(right);

    assert(right.empty);
    assert(left.front is &first && left.back is &third);
    assert(first.listHook.next is &second);
    assert(second.listHook.previous is &first);
    assert(second.listHook.next is &third);
    assert(third.listHook.previous is &second);
    version (XTB_Checked)
    {
        assert(first.listHook.linked);
        assert(second.listHook.linked);
        assert(third.listHook.linked);
    }

    assert(left.popFront() is &first);
    assert(left.popFront() is &second);
    assert(left.popFront() is &third);
    assert(left.empty);
    version (XTB_Checked)
    {
        assert(!first.listHook.linked);
        assert(!second.listHook.linked);
        assert(!third.listHook.linked);
    }
}

unittest
{
    struct ListNode
    {
        ListHook!ListNode listHook;
        int value;
    }

    ListNode first;
    first.value = 1;
    ListNode second;
    second.value = 2;
    ListNode third;
    third.value = 3;

    IntrusiveList!ListNode list;
    list.pushBack(&first);
    list.pushBack(&second);
    list.pushBack(&third);

    int listValue;
    foreach (node; list)
    {
        static assert(is(typeof(node) == ListNode*));
        listValue = listValue * 10 + node.value;
    }
    assert(listValue == 123);

    const(IntrusiveList!ListNode)* constList = &list;
    int constListValue;
    foreach (node; *constList)
    {
        static assert(is(typeof(node) == const(ListNode)*));
        constListValue += node.value;
    }
    assert(constListValue == 6);

    // The implementation snapshots the next hook before the body runs, so
    // removing the current node is explicitly supported.
    foreach (node; list)
        list.remove(node);
    assert(list.empty);

    struct ForwardNode
    {
        ForwardListHook!ForwardNode listHook;
        ForwardListHook!ForwardNode queueHook;
        ForwardListHook!ForwardNode stackHook;
        int value;
    }

    ForwardNode one;
    one.value = 1;
    ForwardNode two;
    two.value = 2;
    ForwardNode three;
    three.value = 3;

    IntrusiveForwardList!(ForwardNode, "listHook") forwardList;
    forwardList.pushBack(&one);
    forwardList.pushBack(&two);
    forwardList.pushBack(&three);

    int forwardValue;
    foreach (node; forwardList)
        forwardValue = forwardValue * 10 + node.value;
    assert(forwardValue == 123);

    IntrusiveQueue!(ForwardNode, "queueHook") queue;
    queue.pushBack(&one);
    queue.pushBack(&two);
    queue.pushBack(&three);

    int queueValue;
    foreach (node; queue)
        queueValue = queueValue * 10 + node.value;
    assert(queueValue == 123);

    IntrusiveStack!(ForwardNode, "stackHook") stack;
    stack.push(&one);
    stack.push(&two);
    stack.push(&three);

    int stackValue;
    foreach (node; stack)
        stackValue = stackValue * 10 + node.value;
    assert(stackValue == 321);

    const(IntrusiveForwardList!(ForwardNode, "listHook"))* constForwardList = &forwardList;
    const(IntrusiveQueue!(ForwardNode, "queueHook"))* constQueue = &queue;
    const(IntrusiveStack!(ForwardNode, "stackHook"))* constStack = &stack;

    int constValue;
    foreach (node; *constForwardList)
    {
        static assert(is(typeof(node) == const(ForwardNode)*));
        constValue += node.value;
    }
    foreach (node; *constQueue)
    {
        static assert(is(typeof(node) == const(ForwardNode)*));
        constValue += node.value;
    }
    foreach (node; *constStack)
    {
        static assert(is(typeof(node) == const(ForwardNode)*));
        constValue += node.value;
    }
    assert(constValue == 18);
}
