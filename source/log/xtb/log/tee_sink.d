module xtb.log.tee_sink;

nothrow @nogc:

import xtb.log.sink;

/// A stateful two-way fan-out sink over borrowed child sink references.
///
/// Each child graph is resolved exactly once when a record begins. The tee then
/// remains in the record path only because fan-out itself is genuine per-write
/// work. Branch failures are remembered until `try_end_record`: a failed branch
/// stops receiving ordinary payload, while a healthy branch continues the
/// record and every branch that successfully began a message/record still
/// receives the matching finalization operation.
///
/// `TeeLogSink` owns no child sink or destination. Once `sink_ref()` has been
/// taken, the tee value must remain at a stable address and outlive every use of
/// that reference.
struct TeeLogSink
{
nothrow @nogc:

    // Child references are borrowed; active record state is valid only while
    // `in_record` is true and is reset when that record is finalized.
    LogSinkRef first;
    LogSinkRef second;
    LogRecordRef first_record;
    LogRecordRef second_record;
    bool in_record;
    bool first_record_began;
    bool second_record_began;
    bool first_healthy;
    bool second_healthy;
    bool record_failed;

    @disable this(this);

    static TeeLogSink create(LogSinkRef first, LogSinkRef second) @safe
    {
        TeeLogSink result;
        result.first = first;
        result.second = second;
        return result;
    }

    bool valid() const pure @safe
    {
        return this.first.valid && this.second.valid;
    }

    /// Returns a borrowed sink reference backed by this tee.
    LogSinkRef sink_ref() return @trusted
    {
        // All @system callbacks receive exactly &this as their opaque context.
        // `return` prevents the resulting sink reference from outliving this tee.
        return LogSinkRef.create(
            &resolve_tee_record,
            &this,
            &try_flush_tee,
        );
    }
}

private LogRecordRef resolve_tee_record(
    void* context,
    return scope const ref LogRecordInfo info,
    return scope const(LogSourceLocation)* callsite,
) @system
{
    TeeLogSink* tee = cast(TeeLogSink*) context;
    if (tee is null || !tee.valid || tee.in_record) return LogRecordRef.init;

    tee.in_record = true;
    tee.record_failed = false;

    tee.first_record = tee.first.begin_record(info, callsite);
    tee.first_record_began = tee.first_record.valid;
    tee.first_healthy = tee.first_record_began;
    tee.second_record = tee.second.begin_record(info, callsite);
    tee.second_record_began = tee.second_record.valid;
    tee.second_healthy = tee.second_record_began;
    tee.record_failed = !tee.first_healthy || !tee.second_healthy;

    // Child setup failures are deliberately deferred until try_end_record so a
    // healthy branch still receives the complete logical record.
    return LogRecordRef.create(
        &try_tee_record_event,
        tee,
        info,
        callsite,
    );
}

private bool try_tee_record_event(void* context, scope const LogSinkEvent* event) @system
{
    TeeLogSink* tee = cast(TeeLogSink*) context;
    if (tee is null || event is null || !tee.in_record) return false;

    final switch (event.kind)
    {
    case LogSinkEventKind.begin_record:
        return false;
    case LogSinkEventKind.text:
    case LogSinkEventKind.message_chunk:
    {
        bool first_accepted = true;
        if (tee.first_healthy)
        {
            first_accepted = event.kind == LogSinkEventKind.message_chunk
                ? tee.first_record.try_message_chunk(event.bytes)
                : tee.first_record.try_submit(event);
            if (!first_accepted) tee.first_healthy = false;
        }

        bool second_accepted = true;
        if (tee.second_healthy)
        {
            second_accepted = event.kind == LogSinkEventKind.message_chunk
                ? tee.second_record.try_message_chunk(event.bytes)
                : tee.second_record.try_submit(event);
            if (!second_accepted) tee.second_healthy = false;
        }

        tee.record_failed = tee.record_failed || !first_accepted || !second_accepted;
        return true;
    }
    case LogSinkEventKind.begin_message:
    {
        if (tee.first_healthy && !tee.first_record.try_begin_message())
        {
            tee.first_healthy = false;
            tee.record_failed = true;
        }
        if (tee.second_healthy && !tee.second_record.try_begin_message())
        {
            tee.second_healthy = false;
            tee.record_failed = true;
        }
        return true;
    }
    case LogSinkEventKind.end_message:
    {
        if (tee.first_record_began && tee.first_record.message_open)
        {
            if (!tee.first_record.try_end_message())
            {
                tee.first_healthy = false;
                tee.record_failed = true;
            }
        }
        if (tee.second_record_began && tee.second_record.message_open)
        {
            if (!tee.second_record.try_end_message())
            {
                tee.second_healthy = false;
                tee.record_failed = true;
            }
        }
        return true;
    }
    case LogSinkEventKind.end_record:
    {
        if (tee.first_record_began)
        {
            if (!tee.first_record.try_end_record()) tee.record_failed = true;
            tee.first_record_began = false;
        }
        if (tee.second_record_began)
        {
            if (!tee.second_record.try_end_record()) tee.record_failed = true;
            tee.second_record_began = false;
        }

        const bool accepted = !tee.record_failed;
        tee.in_record = false;
        tee.first_healthy = false;
        tee.second_healthy = false;
        tee.record_failed = false;
        tee.first_record = LogRecordRef.init;
        tee.second_record = LogRecordRef.init;
        return accepted;
    }
    }
}

private bool try_flush_tee(void* context) @system
{
    TeeLogSink* tee = cast(TeeLogSink*) context;
    if (tee is null) return false;

    const bool first_accepted = tee.first.try_flush();
    const bool second_accepted = tee.second.try_flush();
    return first_accepted && second_accepted;
}
