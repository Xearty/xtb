module xtb.log.callsite_sink;

nothrow @nogc:

import xtb.log.sink : LogRecordInfo, LogRecordRef,
    LogSinkRef, LogSourceLocation;

/// A setup-only decorator that removes callsite metadata from one sink branch.
///
/// The child is resolved with a null source location and its resolved record is
/// returned unchanged. The decorator therefore does not participate in message
/// writes or any later record lifecycle operation. It owns no child sink. Once
/// `sinkRef()` has been taken, this value must remain at a stable address and
/// outlive every use of that reference.
struct WithoutCallsiteLogSink
{
nothrow @nogc:

    private LogSinkRef child_;

    @disable this(this);

    static WithoutCallsiteLogSink create(LogSinkRef child)
    {
        WithoutCallsiteLogSink result;
        result.child_ = child;
        return result;
    }

    bool valid() const pure @safe
    {
        return child_.valid;
    }

    LogSinkRef sinkRef() return @trusted
    {
        return LogSinkRef.create(
            &resolveWithoutCallsiteRecord,
            cast(void*)&this,
            &withoutCallsiteFlushCallback,
        );
    }
}

private LogRecordRef resolveWithoutCallsiteRecord(
    void* context,
    scope return const ref LogRecordInfo info,
    scope return const(LogSourceLocation)*,
)
{
    WithoutCallsiteLogSink* sink = cast(WithoutCallsiteLogSink*) context;
    if (sink is null || !sink.valid)
        return LogRecordRef.init;
    return sink.child_.beginRecord(info, null);
}

private bool withoutCallsiteFlushCallback(void* context)
{
    WithoutCallsiteLogSink* sink = cast(WithoutCallsiteLogSink*) context;
    return sink !is null && sink.child_.flush();
}
