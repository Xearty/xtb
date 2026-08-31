module xtb.opengl;

public import bindbc.opengl;

unittest
{
    static assert(glSupport == GLSupport.gl46);
    static assert(is(typeof(glClear) == pglClear));
    static assert(is(typeof(glCreateBuffers) == pglCreateBuffers));
}
