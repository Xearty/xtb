module xtb.core.logging.result;

nothrow @nogc:

enum LogStatus : ubyte
{
    filtered,
    delivered,
    truncated,
    sinkFailed,
    recursive,
    invalidLogger,
}

struct LogResult
{
nothrow @nogc:

    LogStatus status;
    size_t written;
    size_t required;

    bool delivered() const pure @safe
    {
        return status == LogStatus.delivered || status == LogStatus.truncated;
    }
}
