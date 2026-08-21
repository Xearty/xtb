module xtb.core.logging.prefix;

nothrow @nogc:

import xtb.core.ansi : AnsiStyle;
import xtb.core.logging.sink : LogSinkEvent, LogSinkEventKind, LogSinkRef;
import xtb.core.string : String;

/// Restricted synchronous writer exposed to record-prefix providers.
///
/// Each write becomes one ordinary styled `text` event in an already-begun
/// child record. The writer owns no storage and may only be used for the
/// duration of the prefix callback.
struct LogPrefixWriter
{
nothrow @nogc:

    private LogSinkRef* child_;
    private bool failed_;

    bool write(return scope String bytes, AnsiStyle style = AnsiStyle.init)
    {
        if (failed_ || child_ is null)
            return false;
        LogSinkEvent event = LogSinkEvent.text(bytes, style);
        if ((*child_).submit(&event))
            return true;
        failed_ = true;
        return false;
    }
}

alias LogPrefix = bool function(void* context, LogPrefixWriter* output);

/// A copyable, non-owning reference to a record-prefix provider.
struct LogPrefixRef
{
nothrow @nogc:

    private LogPrefix prefix_;
    private void* context_;

    static LogPrefixRef create(LogPrefix prefix, void* context)
    {
        return LogPrefixRef(prefix, context);
    }

    bool valid() const pure @safe
    {
        return prefix_ !is null;
    }

    bool write(LogPrefixWriter* output)
    {
        return valid && output !is null && prefix_(context_, output);
    }
}

/// A stateful record-prefix decorator over one borrowed child sink.
///
/// The provider runs exactly once after the child accepts `beginRecord` and
/// before the logger's first record event is forwarded. Prefix failure is
/// remembered until `endRecord`, allowing the actual record to continue and
/// its lifecycle to be finalized. The wrapper owns neither child nor provider.
/// Once `sinkRef()` has been taken, this value must remain at a stable address
/// and outlive every use of that reference.
struct PrefixLogSink
{
nothrow @nogc:

    private LogSinkRef child_;
    private LogPrefixRef prefix_;
    private bool inRecord_;
    private bool childRecordBegan_;
    private bool childMessageOpen_;
    private bool prefixFailed_;

    @disable this(this);

    static PrefixLogSink create(LogSinkRef child, LogPrefixRef prefix)
    {
        PrefixLogSink result;
        result.child_ = child;
        result.prefix_ = prefix;
        return result;
    }

    bool valid() const pure @safe
    {
        return child_.valid && prefix_.valid;
    }

    LogSinkRef sinkRef() return @trusted
    {
        return LogSinkRef.create(
            &prefixLogSinkCallback,
            cast(void*)&this,
            &prefixLogFlushCallback,
        );
    }
}

private bool prefixLogSinkCallback(void* context, scope const LogSinkEvent* event)
{
    PrefixLogSink* prefixSink = cast(PrefixLogSink*) context;
    if (prefixSink is null || event is null)
        return false;

    final switch (event.kind)
    {
        case LogSinkEventKind.beginRecord:
        {
            if (prefixSink.inRecord_)
                return false;
            if (!prefixSink.child_.submit(event))
                return false;

            prefixSink.inRecord_ = true;
            prefixSink.childRecordBegan_ = true;
            prefixSink.childMessageOpen_ = false;
            prefixSink.prefixFailed_ = false;

            LogPrefixWriter writer;
            writer.child_ = &prefixSink.child_;
            const providerAccepted = prefixSink.prefix_.write(&writer);
            prefixSink.prefixFailed_ = !providerAccepted || writer.failed_;

            // Prefix failure is deliberately deferred until endRecord so the
            // actual record still reaches an already-begun child.
            return true;
        }
        case LogSinkEventKind.beginMessage:
        {
            if (!prefixSink.inRecord_ || prefixSink.childMessageOpen_)
                return false;
            prefixSink.childMessageOpen_ = true;
            return prefixSink.child_.submit(event);
        }
        case LogSinkEventKind.endMessage:
        {
            if (!prefixSink.inRecord_ || !prefixSink.childMessageOpen_)
                return false;
            const accepted = prefixSink.child_.submit(event);
            prefixSink.childMessageOpen_ = false;
            return accepted;
        }
        case LogSinkEventKind.text:
        case LogSinkEventKind.messageChunk:
            return prefixSink.inRecord_ && prefixSink.child_.submit(event);
        case LogSinkEventKind.endRecord:
        {
            if (!prefixSink.inRecord_)
                return false;

            bool accepted = true;
            if (prefixSink.childMessageOpen_)
            {
                LogSinkEvent end = LogSinkEvent.endMessage();
                accepted = prefixSink.child_.submit(&end) && accepted;
                prefixSink.childMessageOpen_ = false;
            }
            if (prefixSink.childRecordBegan_)
            {
                accepted = prefixSink.child_.submit(event) && accepted;
                prefixSink.childRecordBegan_ = false;
            }

            accepted = accepted && !prefixSink.prefixFailed_;
            prefixSink.inRecord_ = false;
            prefixSink.prefixFailed_ = false;
            return accepted;
        }
    }
}

private bool prefixLogFlushCallback(void* context)
{
    PrefixLogSink* prefixSink = cast(PrefixLogSink*) context;
    return prefixSink !is null && prefixSink.child_.flush();
}
