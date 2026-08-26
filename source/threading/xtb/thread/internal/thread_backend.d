module xtb.thread.internal.thread_backend;

version (XTB_TestUnsupportedThreadBackend)
{
    public import xtb.thread.internal.thread_unsupported;
}
else version (linux)
{
    public import xtb.thread.internal.thread_linux;
}
else
{
    public import xtb.thread.internal.thread_unsupported;
}
