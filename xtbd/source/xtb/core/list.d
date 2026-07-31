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

void pushBack(Node)(ref List!Node list, Node* node) nothrow @nogc
{
    require(node !is null, "cannot insert a null list node");
    require(node.prev is null && node.next is null, "list node is already linked");
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
    node.next = list.first;
    if (list.first is null)
        list.last = node;
    else
        list.first.prev = node;
    list.first = node;
}

void remove(Node)(ref List!Node list, Node* node) nothrow @nogc
{
    require(node !is null, "cannot remove a null list node");
    bool found;
    for (Node* current = list.first; current !is null; current = current.next)
    {
        if (current is node)
        {
            found = true;
            break;
        }
    }
    require(found, "node is not in this list");
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
    List!Node list;
    list.pushBack(&first);
    list.pushBack(&second);
    assert(list.first.value == 1);
    assert(list.last.value == 2);
    assert(list.popFront() is &first);
    assert(first.prev is null && first.next is null);
    list.remove(&second);
    assert(list.empty);
}
