module tests.opengl_tests;

import xtb.opengl;

private GLSupport loadForAttributeCheck() nothrow @nogc
{
    return loadOpenGL();
}

extern (C) int main() nothrow @nogc
{
    static assert(glSupport == GLSupport.gl46);
    static assert(is(typeof(&loadForAttributeCheck) == GLSupport function() nothrow @nogc));

    if (isOpenGLLoaded() || glClear !is null || glCreateBuffers !is null)
        return 1;

    const loaded = loadOpenGL();
    if (loaded != GLSupport.noLibrary &&
        loaded != GLSupport.badLibrary &&
        loaded != GLSupport.noContext)
        return 1;

    unloadOpenGL();
    if (isOpenGLLoaded())
        return 1;
    return 0;
}
