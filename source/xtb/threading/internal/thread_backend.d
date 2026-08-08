module xtb.threading.internal.thread_backend;

version (XTB_TestUnsupportedThreadBackend)
{
    public import xtb.threading.internal.thread_unsupported;
}
else version (linux)
{
    public import xtb.threading.internal.thread_linux;
}
else
{
    public import xtb.threading.internal.thread_unsupported;
}
