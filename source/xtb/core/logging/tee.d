module xtb.core.logging.tee;

nothrow @nogc:

import xtb.core.logging.sink : LogSinkEvent, LogSinkEventKind, LogSinkRef;

/// A stateful two-way fan-out sink over borrowed child sink references.
///
/// The tee is presentation-agnostic. It forwards the explicit sink lifecycle
/// protocol to both children in deterministic first-then-second order. Branch
/// failures are remembered until `endRecord`: a failed branch stops receiving
/// ordinary payload, while a healthy branch continues the record and every
/// branch that successfully began a message/record still receives the matching
/// finalization event.
///
/// `TeeLogSink` owns no child sink or destination. Once `sinkRef()` has been
/// taken, the tee value must remain at a stable address and outlive every use of
/// that reference.
struct TeeLogSink
{
nothrow @nogc:

    private LogSinkRef first_;
    private LogSinkRef second_;
    private bool inRecord_;
    private bool firstRecordBegan_;
    private bool secondRecordBegan_;
    private bool firstMessageOpen_;
    private bool secondMessageOpen_;
    private bool firstHealthy_;
    private bool secondHealthy_;
    private bool recordFailed_;

    @disable this(this);

    static TeeLogSink create(LogSinkRef first, LogSinkRef second)
    {
        TeeLogSink result;
        result.first_ = first;
        result.second_ = second;
        return result;
    }

    bool valid() const pure @safe
    {
        return first_.valid && second_.valid;
    }

    /// Returns a borrowed sink reference backed by this tee.
    LogSinkRef sinkRef() return @trusted
    {
        return LogSinkRef.create(
            &teeLogSinkCallback,
            cast(void*)&this,
            &teeLogFlushCallback,
        );
    }
}

private bool teeSubmitBranch(
    ref LogSinkRef branch,
    ref bool healthy,
    scope const LogSinkEvent* event,
)
{
    if (!healthy)
        return false;
    if (branch.submit(event))
        return true;
    healthy = false;
    return false;
}

private bool teeLogSinkCallback(void* context, scope const LogSinkEvent* event)
{
    TeeLogSink* tee = cast(TeeLogSink*) context;
    if (tee is null || event is null)
        return false;

    final switch (event.kind)
    {
        case LogSinkEventKind.beginRecord:
        {
            if (tee.inRecord_)
                return false;

            tee.inRecord_ = true;
            tee.firstMessageOpen_ = false;
            tee.secondMessageOpen_ = false;
            tee.recordFailed_ = false;

            tee.firstHealthy_ = tee.first_.submit(event);
            tee.firstRecordBegan_ = tee.firstHealthy_;
            tee.secondHealthy_ = tee.second_.submit(event);
            tee.secondRecordBegan_ = tee.secondHealthy_;
            tee.recordFailed_ = !tee.firstHealthy_ || !tee.secondHealthy_;

            // Branch failures are intentionally deferred until endRecord so a
            // healthy branch can still receive the complete logical record.
            return true;
        }
        case LogSinkEventKind.text:
        case LogSinkEventKind.messageChunk:
        {
            if (!tee.inRecord_)
                return false;
            const firstAccepted = teeSubmitBranch(
                tee.first_,
                tee.firstHealthy_,
                event,
            );
            const secondAccepted = teeSubmitBranch(
                tee.second_,
                tee.secondHealthy_,
                event,
            );
            tee.recordFailed_ = tee.recordFailed_ || !firstAccepted || !secondAccepted;
            return true;
        }
        case LogSinkEventKind.beginMessage:
        {
            if (!tee.inRecord_ || tee.firstMessageOpen_ || tee.secondMessageOpen_)
                return false;

            if (tee.firstHealthy_)
            {
                tee.firstMessageOpen_ = true;
                if (!tee.first_.submit(event))
                {
                    tee.firstHealthy_ = false;
                    tee.recordFailed_ = true;
                }
            }
            if (tee.secondHealthy_)
            {
                tee.secondMessageOpen_ = true;
                if (!tee.second_.submit(event))
                {
                    tee.secondHealthy_ = false;
                    tee.recordFailed_ = true;
                }
            }
            return true;
        }
        case LogSinkEventKind.endMessage:
        {
            if (!tee.inRecord_)
                return false;

            if (tee.firstMessageOpen_)
            {
                if (!tee.first_.submit(event))
                {
                    tee.firstHealthy_ = false;
                    tee.recordFailed_ = true;
                }
                tee.firstMessageOpen_ = false;
            }
            if (tee.secondMessageOpen_)
            {
                if (!tee.second_.submit(event))
                {
                    tee.secondHealthy_ = false;
                    tee.recordFailed_ = true;
                }
                tee.secondMessageOpen_ = false;
            }
            return true;
        }
        case LogSinkEventKind.endRecord:
        {
            if (!tee.inRecord_)
                return false;

            // Be defensive for direct protocol users: if a message was begun
            // but endMessage was omitted, finalize it before ending the record.
            if (tee.firstMessageOpen_)
            {
                LogSinkEvent end = LogSinkEvent.endMessage();
                if (!tee.first_.submit(&end))
                    tee.recordFailed_ = true;
                tee.firstMessageOpen_ = false;
            }
            if (tee.secondMessageOpen_)
            {
                LogSinkEvent end = LogSinkEvent.endMessage();
                if (!tee.second_.submit(&end))
                    tee.recordFailed_ = true;
                tee.secondMessageOpen_ = false;
            }

            if (tee.firstRecordBegan_)
            {
                if (!tee.first_.submit(event))
                    tee.recordFailed_ = true;
                tee.firstRecordBegan_ = false;
            }
            if (tee.secondRecordBegan_)
            {
                if (!tee.second_.submit(event))
                    tee.recordFailed_ = true;
                tee.secondRecordBegan_ = false;
            }

            const accepted = !tee.recordFailed_;
            tee.inRecord_ = false;
            tee.firstHealthy_ = false;
            tee.secondHealthy_ = false;
            tee.recordFailed_ = false;
            return accepted;
        }
    }
}

private bool teeLogFlushCallback(void* context)
{
    TeeLogSink* tee = cast(TeeLogSink*) context;
    if (tee is null)
        return false;
    const firstAccepted = tee.first_.flush();
    const secondAccepted = tee.second_.flush();
    return firstAccepted && secondAccepted;
}
