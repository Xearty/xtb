module xtb.log.callsite_sink;

nothrow @nogc:

import xtb.log.sink;

/// A setup-only decorator that removes callsite metadata from one sink branch.
///
/// The child is resolved with a null source location and its resolved record is
/// returned unchanged. The decorator therefore does not participate in message
/// writes or any later record lifecycle operation. It owns no child sink. Once
/// `sink_ref()` has been taken, this value must remain at a stable address and
/// outlive every use of that reference.
struct WithoutCallsiteLogSink
{
nothrow @nogc:

    LogSinkRef child;

    @disable this(this);

    static WithoutCallsiteLogSink create(LogSinkRef child) @safe
    {
        WithoutCallsiteLogSink result;
        result.child = child;
        return result;
    }

    bool valid() const pure @safe
    {
        return this.child.valid;
    }

    LogSinkRef sink_ref() return @trusted
    {
        // Both @system callbacks receive exactly &this as their opaque context.
        // `return` prevents the resulting sink reference from outliving this decorator.
        return LogSinkRef.create(
            &resolve_without_callsite_record,
            &this,
            &try_flush_without_callsite,
        );
    }
}

private LogRecordRef resolve_without_callsite_record(
    void* context,
    return scope const ref LogRecordInfo info,
    return scope const(LogSourceLocation)*,
) @system
{
    WithoutCallsiteLogSink* sink = cast(WithoutCallsiteLogSink*) context;
    if (sink is null || !sink.valid) return LogRecordRef.init;

    return sink.child.begin_record(info, null);
}

private bool try_flush_without_callsite(void* context) @system
{
    WithoutCallsiteLogSink* sink = cast(WithoutCallsiteLogSink*) context;
    return sink !is null && sink.child.try_flush();
}
