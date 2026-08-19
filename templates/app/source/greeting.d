module greeting;

nothrow @nogc:

import xtb.core : String, equal;

String greetingSubject() pure @safe
{
    return "codebase";
}

unittest
{
    assert(greetingSubject.equal("codebase"));
}
