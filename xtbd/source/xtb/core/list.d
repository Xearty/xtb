module xtb.core.list;

import xtb.core.panic : require;

struct List(Node)
{
    static assert(__traits(hasMember, Node, "prev"));
    static assert(__traits(hasMember, Node, "next"));

    Node* first;
    Node* last;

    bool empty() const pure nothrow @safe @nogc
    {
        return first is null;
    }
}

private bool containsNode(Node)(ref List!Node list, Node* node) nothrow @nogc
{
    for (Node* current = list.first; current !is null; current = current.next)
        if (current is node)
            return true;
    return false;
}

void pushBack(Node)(ref List!Node list, Node* node) nothrow @nogc
{
    require(node !is null, "cannot insert a null list node");
    require(node.prev is null && node.next is null, "list node is already linked");
    require(!list.containsNode(node), "list node is already linked");
    node.prev = list.last;
    if (list.last is null)
        list.first = node;
    else
        list.last.next = node;
    list.last = node;
}

void pushFront(Node)(ref List!Node list, Node* node) nothrow @nogc
{
    require(node !is null, "cannot insert a null list node");
    require(node.prev is null && node.next is null, "list node is already linked");
    require(!list.containsNode(node), "list node is already linked");
    node.next = list.first;
    if (list.first is null)
        list.last = node;
    else
        list.first.prev = node;
    list.first = node;
}

void insertAfter(Node)(ref List!Node list, Node* position, Node* node)
    nothrow @nogc
{
    require(position !is null && node !is null, "cannot insert a null list node");
    require(list.containsNode(position), "position is not in this list");
    require(node.prev is null && node.next is null && !list.containsNode(node),
        "list node is already linked");
    if (position is list.last)
    {
        list.pushBack(node);
        return;
    }
    node.prev = position;
    node.next = position.next;
    position.next.prev = node;
    position.next = node;
}

void insertBefore(Node)(ref List!Node list, Node* position, Node* node)
    nothrow @nogc
{
    require(position !is null && node !is null, "cannot insert a null list node");
    require(list.containsNode(position), "position is not in this list");
    require(node.prev is null && node.next is null && !list.containsNode(node),
        "list node is already linked");
    if (position is list.first)
    {
        list.pushFront(node);
        return;
    }
    node.next = position;
    node.prev = position.prev;
    position.prev.next = node;
    position.prev = node;
}

void remove(Node)(ref List!Node list, Node* node) nothrow @nogc
{
    require(node !is null, "cannot remove a null list node");
    require(list.containsNode(node), "node is not in this list");
    if (node.prev is null)
    {
        require(list.first is node, "node is not in this list");
        list.first = node.next;
    }
    else
        node.prev.next = node.next;

    if (node.next is null)
    {
        require(list.last is node, "node is not in this list");
        list.last = node.prev;
    }
    else
        node.next.prev = node.prev;

    node.prev = null;
    node.next = null;
}

Node* popFront(Node)(ref List!Node list) nothrow @nogc
{
    require(list.first !is null, "cannot pop an empty list");
    Node* result = list.first;
    list.remove(result);
    return result;
}

Node* popBack(Node)(ref List!Node list) nothrow @nogc
{
    require(list.last !is null, "cannot pop an empty list");
    Node* result = list.last;
    list.remove(result);
    return result;
}

void concatenate(Node)(ref List!Node destination, ref List!Node source)
    nothrow @nogc
{
    require(&destination !is &source, "cannot concatenate a list with itself");
    if (source.empty)
        return;
    if (destination.empty)
    {
        destination.first = source.first;
        destination.last = source.last;
    }
    else
    {
        destination.last.next = source.first;
        source.first.prev = destination.last;
        destination.last = source.last;
    }
    source.first = null;
    source.last = null;
}

struct ListCursor(Node)
{
    private Node* current_;
    private bool reverse_;

    bool valid() const pure nothrow @safe @nogc
    {
        return current_ !is null;
    }

    Node* get() return nothrow @system @nogc
    {
        require(valid, "invalid list cursor");
        return current_;
    }

    void advance() nothrow @nogc
    {
        require(valid, "invalid list cursor");
        current_ = reverse_ ? current_.prev : current_.next;
    }
}

ListCursor!Node cursor(Node)(ref List!Node list) nothrow @nogc
{
    return ListCursor!Node(list.first, false);
}

ListCursor!Node reverseCursor(Node)(ref List!Node list) nothrow @nogc
{
    return ListCursor!Node(list.last, true);
}

struct Queue(Node)
{
    static assert(__traits(hasMember, Node, "next"));
    Node* first;
    Node* last;

    bool empty() const pure nothrow @safe @nogc { return first is null; }
}

void pushBack(Node)(ref Queue!Node queue, Node* node) nothrow @nogc
{
    require(node !is null && node.next is null, "queue node is already linked");
    if (queue.last is null)
        queue.first = node;
    else
        queue.last.next = node;
    queue.last = node;
}

void pushFront(Node)(ref Queue!Node queue, Node* node) nothrow @nogc
{
    require(node !is null && node.next is null, "queue node is already linked");
    node.next = queue.first;
    queue.first = node;
    if (queue.last is null)
        queue.last = node;
}

Node* popFront(Node)(ref Queue!Node queue) nothrow @nogc
{
    require(queue.first !is null, "cannot pop an empty queue");
    Node* result = queue.first;
    queue.first = result.next;
    result.next = null;
    if (queue.first is null)
        queue.last = null;
    return result;
}

struct Stack(Node)
{
    static assert(__traits(hasMember, Node, "next"));
    Node* top;

    bool empty() const pure nothrow @safe @nogc { return top is null; }
}

void push(Node)(ref Stack!Node stack, Node* node) nothrow @nogc
{
    require(node !is null && node.next is null, "stack node is already linked");
    node.next = stack.top;
    stack.top = node;
}

Node* pop(Node)(ref Stack!Node stack) nothrow @nogc
{
    require(stack.top !is null, "cannot pop an empty stack");
    Node* result = stack.top;
    stack.top = result.next;
    result.next = null;
    return result;
}

nothrow @nogc unittest
{
    struct Node
    {
        Node* prev;
        Node* next;
        int value;
    }

    Node first = Node(null, null, 1);
    Node second = Node(null, null, 2);
    Node middle = Node(null, null, 3);
    List!Node list;
    list.pushBack(&first);
    list.pushBack(&second);
    list.insertBefore(&second, &middle);
    assert(list.first.value == 1);
    assert(list.last.value == 2 && list.first.next is &middle);
    assert(list.popFront() is &first);
    assert(first.prev is null && first.next is null);
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

    struct SingleNode { SingleNode* next; int value; }
    SingleNode one = SingleNode(null, 1);
    SingleNode two = SingleNode(null, 2);
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
