module xtb.log.result;

nothrow @nogc:

import xtb.data_struct;
import xtb.types;

enum LogStatus
{
    filtered,
    delivered,
    truncated,
    sink_failed,
    recursive,
    invalid_logger,
}

struct LogResult
{
nothrow @nogc:

    LogStatus status;
    usize written;
    usize required;

    mixin DataStruct;

    bool delivered() const pure @safe
    {
        return this.status == LogStatus.delivered || this.status == LogStatus.truncated;
    }
}
