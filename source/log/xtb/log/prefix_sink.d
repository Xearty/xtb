module xtb.log.prefix_sink;

nothrow @nogc:

import xtb.ansi : AnsiStyle;
import xtb.lifetime : move;
import xtb.log.sink : LogRecordInfo, LogRecordRef, LogSinkRef, LogSourceLocation;
import xtb.string : String;

/// Restricted synchronous writer exposed to record-prefix providers.
///
/// Each write goes through the already-resolved child record before the
/// logger's standard level/message framing begins. `write` uses semantic
/// `AnsiStyle` with ANSI-free bytes and stays on the direct presentation path;
/// `writeAnsi` additionally allows supported embedded SGR and lets the
/// destination preserve or strip it. The writer owns no storage and may only be
/// used for the duration of the prefix callback.
struct LogPrefixWriter
{
nothrow @nogc:

    private LogRecordRef* record_;
    private bool failed_;

    /// Writes ANSI-free prefix bytes with an optional semantic style.
    bool write(return scope String bytes, AnsiStyle style = AnsiStyle.init)
    {
        return writeImpl(bytes, style, false);
    }

    /// Writes one prefix span that may contain supported embedded ANSI SGR.
    /// ANSI presentation terminates the span with a full reset, so embedded
    /// style state does not carry into a later prefix write or logger framing.
    /// One supported SGR sequence must not be split across two calls.
    bool writeAnsi(return scope String bytes, AnsiStyle style = AnsiStyle.init)
    {
        return writeImpl(bytes, style, true);
    }

    private bool writeImpl(
        return scope String bytes,
        AnsiStyle style,
        bool mayContainAnsi,
    )
    {
        if (failed_ || record_ is null)
            return false;
        const accepted = mayContainAnsi
            ? (*record_).writeAnsiText(bytes, style) : (*record_).writeText(bytes, style);
        if (accepted)
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

/// A setup-only record-prefix decorator over one borrowed child sink.
///
/// The child is resolved once, then the provider writes through that resolved
/// record before the logger's level label is emitted. The child record is
/// returned unchanged, so this decorator does not participate in later message
/// writes. Prefix failure is attached to the returned record and reported only
/// when the record ends, allowing an already-begun child to receive the actual
/// message and matching cleanup.
///
/// The wrapper owns neither child nor provider. Once `sinkRef()` has been taken,
/// this value must remain at a stable address and outlive every use of that
/// reference.
struct PrefixLogSink
{
nothrow @nogc:

    private LogSinkRef child_;
    private LogPrefixRef prefix_;

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
            &resolvePrefixRecord,
            cast(void*)&this,
            &prefixLogFlushCallback,
        );
    }
}

private LogRecordRef resolvePrefixRecord(
    void* context,
    scope return const ref LogRecordInfo info,
    scope return const(LogSourceLocation)* callsite,
)
{
    PrefixLogSink* prefixSink = cast(PrefixLogSink*) context;
    if (prefixSink is null || !prefixSink.valid)
        return LogRecordRef.init;

    LogRecordRef childRecord = prefixSink.child_.beginRecord(info, callsite);
    if (!childRecord.valid)
        return LogRecordRef.init;

    LogPrefixWriter writer;
    writer.record_ = &childRecord;
    const providerAccepted = prefixSink.prefix_.write(&writer);
    if (!providerAccepted || writer.failed_)
        childRecord.deferFailure();

    return move(childRecord);
}

private bool prefixLogFlushCallback(void* context)
{
    PrefixLogSink* prefixSink = cast(PrefixLogSink*) context;
    return prefixSink !is null && prefixSink.child_.flush();
}
