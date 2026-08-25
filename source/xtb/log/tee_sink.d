module xtb.log.tee_sink;

nothrow @nogc:

import xtb.log.sink : LogRecordInfo, LogRecordRef,
    LogSinkEvent, LogSinkEventKind, LogSinkRef, LogSourceLocation;

/// A stateful two-way fan-out sink over borrowed child sink references.
///
/// Each child graph is resolved exactly once when a record begins. The tee then
/// remains in the record path only because fan-out itself is genuine per-write
/// work. Branch failures are remembered until `endRecord`: a failed branch
/// stops receiving ordinary payload, while a healthy branch continues the
/// record and every branch that successfully began a message/record still
/// receives the matching finalization operation.
///
/// `TeeLogSink` owns no child sink or destination. Once `sinkRef()` has been
/// taken, the tee value must remain at a stable address and outlive every use of
/// that reference.
struct TeeLogSink
{
nothrow @nogc:

    private LogSinkRef first_;
    private LogSinkRef second_;
    private LogRecordRef firstRecord_;
    private LogRecordRef secondRecord_;
    private bool inRecord_;
    private bool firstRecordBegan_;
    private bool secondRecordBegan_;
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
            &resolveTeeRecord,
            cast(void*)&this,
            &teeLogFlushCallback,
        );
    }
}

private LogRecordRef resolveTeeRecord(
    void* context,
    scope return const ref LogRecordInfo info,
    scope return const(LogSourceLocation)* callsite,
)
{
    TeeLogSink* tee = cast(TeeLogSink*) context;
    if (tee is null || !tee.valid || tee.inRecord_)
        return LogRecordRef.init;

    tee.inRecord_ = true;
    tee.recordFailed_ = false;

    tee.firstRecord_ = tee.first_.beginRecord(info, callsite);
    tee.firstRecordBegan_ = tee.firstRecord_.valid;
    tee.firstHealthy_ = tee.firstRecordBegan_;
    tee.secondRecord_ = tee.second_.beginRecord(info, callsite);
    tee.secondRecordBegan_ = tee.secondRecord_.valid;
    tee.secondHealthy_ = tee.secondRecordBegan_;
    tee.recordFailed_ = !tee.firstHealthy_ || !tee.secondHealthy_;

    // Child setup failures are deliberately deferred until endRecord so a
    // healthy branch still receives the complete logical record.
    return LogRecordRef.create(
        &teeRecordCallback,
        cast(void*) tee,
        info,
        callsite,
    );
}

private bool teeRecordCallback(void* context, scope const LogSinkEvent* event)
{
    TeeLogSink* tee = cast(TeeLogSink*) context;
    if (tee is null || event is null || !tee.inRecord_)
        return false;

    final switch (event.kind)
    {
        case LogSinkEventKind.beginRecord:
            return false;
        case LogSinkEventKind.text:
        case LogSinkEventKind.messageChunk:
        {
            bool firstAccepted = true;
            if (tee.firstHealthy_)
            {
                firstAccepted = event.kind == LogSinkEventKind.messageChunk
                    ? tee.firstRecord_.messageChunk(event.bytes) : tee.firstRecord_.submit(event);
                if (!firstAccepted)
                    tee.firstHealthy_ = false;
            }

            bool secondAccepted = true;
            if (tee.secondHealthy_)
            {
                secondAccepted = event.kind == LogSinkEventKind.messageChunk
                    ? tee.secondRecord_.messageChunk(event.bytes) : tee.secondRecord_.submit(event);
                if (!secondAccepted)
                    tee.secondHealthy_ = false;
            }

            tee.recordFailed_ = tee.recordFailed_ || !firstAccepted || !secondAccepted;
            return true;
        }
        case LogSinkEventKind.beginMessage:
        {
            if (tee.firstHealthy_ && !tee.firstRecord_.beginMessage())
            {
                tee.firstHealthy_ = false;
                tee.recordFailed_ = true;
            }
            if (tee.secondHealthy_ && !tee.secondRecord_.beginMessage())
            {
                tee.secondHealthy_ = false;
                tee.recordFailed_ = true;
            }
            return true;
        }
        case LogSinkEventKind.endMessage:
        {
            if (tee.firstRecordBegan_ && tee.firstRecord_.messageOpen)
            {
                if (!tee.firstRecord_.endMessage())
                {
                    tee.firstHealthy_ = false;
                    tee.recordFailed_ = true;
                }
            }
            if (tee.secondRecordBegan_ && tee.secondRecord_.messageOpen)
            {
                if (!tee.secondRecord_.endMessage())
                {
                    tee.secondHealthy_ = false;
                    tee.recordFailed_ = true;
                }
            }
            return true;
        }
        case LogSinkEventKind.endRecord:
        {
            if (tee.firstRecordBegan_)
            {
                if (!tee.firstRecord_.endRecord())
                    tee.recordFailed_ = true;
                tee.firstRecordBegan_ = false;
            }
            if (tee.secondRecordBegan_)
            {
                if (!tee.secondRecord_.endRecord())
                    tee.recordFailed_ = true;
                tee.secondRecordBegan_ = false;
            }

            const accepted = !tee.recordFailed_;
            tee.inRecord_ = false;
            tee.firstHealthy_ = false;
            tee.secondHealthy_ = false;
            tee.recordFailed_ = false;
            tee.firstRecord_ = LogRecordRef.init;
            tee.secondRecord_ = LogRecordRef.init;
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
