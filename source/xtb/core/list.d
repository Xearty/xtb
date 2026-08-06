module xtb.core.list;

version (XTB_Checked)
    import xtb.core.panic : require;

nothrow @nogc:

/// Membership state for one intrusive doubly linked list.
struct ListLink(Node)
{
    private Node* previous_;
    private Node* next_;
    private bool linked_;

    bool linked() const pure @safe
    {
        return linked_;
    }

    Node* previous() return pure
    {
        return previous_;
    }

    const(Node)* previous() const return pure
    {
        return previous_;
    }

    Node* next() return pure
    {
        return next_;
    }

    const(Node)* next() const return pure
    {
        return next_;
    }
}

/// Membership state for one intrusive queue or stack.
struct ForwardLink(Node)
{
    private Node* next_;
    private bool linked_;

    bool linked() const pure @safe
    {
        return linked_;
    }

    Node* next() return pure
    {
        return next_;
    }

    const(Node)* next() const return pure
    {
        return next_;
    }
}

private ref ListLink!Node listLinkOf(Node, string member)(Node* node)
{
    return __traits(getMember, *node, member);
}

private ref ForwardLink!Node forwardLinkOf(Node, string member)(Node* node)
{
    return __traits(getMember, *node, member);
}

/// Intrusive doubly linked list using `Node.member` as its membership hook.
struct List(Node, string member = "listLink")
{
    static assert(__traits(hasMember, Node, member),
        "List node is missing its " ~ member ~ " hook");
    static assert(is(typeof(__traits(getMember, Node.init, member)) == ListLink!Node),
        "List hook must be ListLink!Node");

    private Node* first_;
    private Node* last_;

    @disable this(this);

    bool empty() const pure @safe
    {
        return first_ is null;
    }

    Node* first() return pure
    {
        return first_;
    }

    const(Node)* first() const return pure
    {
        return first_;
    }

    Node* last() return pure
    {
        return last_;
    }

    const(Node)* last() const return pure
    {
        return last_;
    }

    private bool contains(Node* node)
    {
        for (Node* current = first_; current !is null; current = listLinkOf!(Node, member)(current)
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
        ref link = listLinkOf!(Node, member)(node);
        version (XTB_Checked)
            require(!link.linked_, "list node is already linked");

        link.previous_ = last_;
        link.next_ = null;
        link.linked_ = true;
        if (last_ is null)
            first_ = node;
        else
            listLinkOf!(Node, member)(last_).next_ = node;
        last_ = node;
    }

    void pushFront(Node* node)
    {
        version (XTB_Checked)
            require(node !is null, "cannot insert a null list node");
        ref link = listLinkOf!(Node, member)(node);
        version (XTB_Checked)
            require(!link.linked_, "list node is already linked");

        link.previous_ = null;
        link.next_ = first_;
        link.linked_ = true;
        if (first_ is null)
            last_ = node;
        else
            listLinkOf!(Node, member)(first_).previous_ = node;
        first_ = node;
    }

    void insertAfter(Node* position, Node* node)
    {
        version (XTB_Checked)
        {
            require(position !is null && node !is null,
                "cannot insert a null list node");
            require(contains(position), "position is not in this list");
            require(!listLinkOf!(Node, member)(node).linked_,
                "list node is already linked");
        }
        if (position is last_)
        {
            pushBack(node);
            return;
        }

        ref positionLink = listLinkOf!(Node, member)(position);
        ref link = listLinkOf!(Node, member)(node);
        link.previous_ = position;
        link.next_ = positionLink.next_;
        link.linked_ = true;
        listLinkOf!(Node, member)(positionLink.next_).previous_ = node;
        positionLink.next_ = node;
    }

    void insertBefore(Node* position, Node* node)
    {
        version (XTB_Checked)
        {
            require(position !is null && node !is null,
                "cannot insert a null list node");
            require(contains(position), "position is not in this list");
            require(!listLinkOf!(Node, member)(node).linked_,
                "list node is already linked");
        }
        if (position is first_)
        {
            pushFront(node);
            return;
        }

        ref positionLink = listLinkOf!(Node, member)(position);
        ref link = listLinkOf!(Node, member)(node);
        link.next_ = position;
        link.previous_ = positionLink.previous_;
        link.linked_ = true;
        listLinkOf!(Node, member)(positionLink.previous_).next_ = node;
        positionLink.previous_ = node;
    }

    void remove(Node* node)
    {
        version (XTB_Checked)
        {
            require(node !is null, "cannot remove a null list node");
            require(contains(node), "node is not in this list");
        }
        ref link = listLinkOf!(Node, member)(node);

        if (link.previous_ is null)
            first_ = link.next_;
        else
            listLinkOf!(Node, member)(link.previous_).next_ = link.next_;

        if (link.next_ is null)
            last_ = link.previous_;
        else
            listLinkOf!(Node, member)(link.next_).previous_ = link.previous_;

        link = ListLink!Node.init;
    }

    Node* popFront()
    {
        version (XTB_Checked)
            require(first_ !is null, "cannot pop an empty list");
        Node* result = first_;
        remove(result);
        return result;
    }

    Node* popBack()
    {
        version (XTB_Checked)
            require(last_ !is null, "cannot pop an empty list");
        Node* result = last_;
        remove(result);
        return result;
    }

    void concatenate(ref List source)
    {
        version (XTB_Checked)
            require(&this !is &source, "cannot concatenate a list with itself");
        if (source.empty)
            return;
        if (empty)
        {
            first_ = source.first_;
            last_ = source.last_;
        }
        else
        {
            listLinkOf!(Node, member)(last_).next_ = source.first_;
            listLinkOf!(Node, member)(source.first_).previous_ = last_;
            last_ = source.last_;
        }
        source.first_ = null;
        source.last_ = null;
    }

    ListCursor!(Node, member) cursor()
    {
        return ListCursor!(Node, member)(first_, false);
    }

    ListCursor!(Node, member) reverseCursor()
    {
        return ListCursor!(Node, member)(last_, true);
    }
}

struct ListCursor(Node, string member)
{
    private Node* current_;
    private bool reverse_;

    bool valid() const pure @safe
    {
        return current_ !is null;
    }

    Node* get() return
    {
        version (XTB_Checked)
            require(valid, "invalid list cursor");
        return current_;
    }

    void advance()
    {
        version (XTB_Checked)
            require(valid, "invalid list cursor");
        ref link = listLinkOf!(Node, member)(current_);
        current_ = reverse_ ? link.previous_ : link.next_;
    }
}

/// Intrusive FIFO queue using `Node.member` as its membership hook.
struct Queue(Node, string member = "forwardLink")
{
    static assert(__traits(hasMember, Node, member),
        "Queue node is missing its " ~ member ~ " hook");
    static assert(is(typeof(__traits(getMember, Node.init, member)) == ForwardLink!Node),
        "Queue hook must be ForwardLink!Node");

    private Node* first_;
    private Node* last_;

    @disable this(this);

    bool empty() const pure @safe
    {
        return first_ is null;
    }

    Node* first() return pure
    {
        return first_;
    }

    Node* last() return pure
    {
        return last_;
    }

    void pushBack(Node* node)
    {
        version (XTB_Checked)
            require(node !is null, "cannot insert a null queue node");
        ref link = forwardLinkOf!(Node, member)(node);
        version (XTB_Checked)
            require(!link.linked_, "queue node is already linked");

        link.next_ = null;
        link.linked_ = true;
        if (last_ is null)
            first_ = node;
        else
            forwardLinkOf!(Node, member)(last_).next_ = node;
        last_ = node;
    }

    void pushFront(Node* node)
    {
        version (XTB_Checked)
            require(node !is null, "cannot insert a null queue node");
        ref link = forwardLinkOf!(Node, member)(node);
        version (XTB_Checked)
            require(!link.linked_, "queue node is already linked");

        link.next_ = first_;
        link.linked_ = true;
        first_ = node;
        if (last_ is null)
            last_ = node;
    }

    Node* popFront()
    {
        version (XTB_Checked)
            require(first_ !is null, "cannot pop an empty queue");
        Node* result = first_;
        ref link = forwardLinkOf!(Node, member)(result);
        first_ = link.next_;
        link = ForwardLink!Node.init;
        if (first_ is null)
            last_ = null;
        return result;
    }
}

/// Intrusive LIFO stack using `Node.member` as its membership hook.
struct Stack(Node, string member = "forwardLink")
{
    static assert(__traits(hasMember, Node, member),
        "Stack node is missing its " ~ member ~ " hook");
    static assert(is(typeof(__traits(getMember, Node.init, member)) == ForwardLink!Node),
        "Stack hook must be ForwardLink!Node");

    private Node* top_;

    @disable this(this);

    bool empty() const pure @safe
    {
        return top_ is null;
    }

    Node* top() return pure
    {
        return top_;
    }

    void push(Node* node)
    {
        version (XTB_Checked)
            require(node !is null, "cannot insert a null stack node");
        ref link = forwardLinkOf!(Node, member)(node);
        version (XTB_Checked)
            require(!link.linked_, "stack node is already linked");

        link.next_ = top_;
        link.linked_ = true;
        top_ = node;
    }

    Node* pop()
    {
        version (XTB_Checked)
            require(top_ !is null, "cannot pop an empty stack");
        Node* result = top_;
        ref link = forwardLinkOf!(Node, member)(result);
        top_ = link.next_;
        link = ForwardLink!Node.init;
        return result;
    }
}

unittest
{
    struct Node
    {
        ListLink!Node listLink;
        int value;
    }

    Node first;
    first.value = 1;
    Node second;
    second.value = 2;
    Node middle;
    middle.value = 3;

    List!Node list;
    list.pushBack(&first);
    list.pushBack(&second);
    list.insertBefore(&second, &middle);
    assert(list.first.value == 1);
    assert(list.last.value == 2 && list.first.listLink.next is &middle);
    assert(list.popFront() is &first);
    assert(!first.listLink.linked);
    assert(list.popBack() is &second);
    list.remove(&middle);
    assert(list.empty);

    List!Node left;
    List!Node right;
    left.pushBack(&first);
    right.pushBack(&second);
    left.concatenate(right);
    assert(right.empty && left.last is &second);
    auto iterator = left.cursor();
    int sum;
    while (iterator.valid)
    {
        sum += iterator.get.value;
        iterator.advance();
    }
    assert(sum == 3);
    left.popFront();
    left.popFront();

    struct MultiListNode
    {
        ListLink!MultiListNode firstLink;
        ListLink!MultiListNode secondLink;
    }

    MultiListNode sharedNode;
    List!(MultiListNode, "firstLink") firstList;
    List!(MultiListNode, "secondLink") secondList;
    firstList.pushBack(&sharedNode);
    secondList.pushBack(&sharedNode);
    assert(sharedNode.firstLink.linked && sharedNode.secondLink.linked);
    firstList.popFront();
    secondList.popFront();

    struct SingleNode
    {
        ForwardLink!SingleNode forwardLink;
        int value;
    }

    SingleNode one;
    one.value = 1;
    SingleNode two;
    two.value = 2;
    Queue!SingleNode queue;
    queue.pushBack(&one);
    queue.pushFront(&two);
    assert(queue.popFront() is &two);
    assert(queue.popFront() is &one && queue.empty);

    Stack!SingleNode stack;
    stack.push(&one);
    stack.push(&two);
    assert(stack.pop() is &two);
    assert(stack.pop() is &one && stack.empty);
}
