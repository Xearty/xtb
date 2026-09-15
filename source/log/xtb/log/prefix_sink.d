module xtb.log.prefix_sink;

nothrow @nogc:

import xtb.ansi;
import xtb.lifetime;
import xtb.log.sink;
import xtb.types;

/// Restricted synchronous writer exposed to record-prefix providers.
///
/// Each write goes through the already-resolved child record before the
/// logger's standard level/message framing begins. `try_write` uses semantic
/// `ANSIStyle` with ANSI-free bytes and stays on the direct presentation path;
/// `try_write_ansi` additionally allows supported embedded SGR and lets the
/// destination preserve or strip it. The writer owns no storage and may only be
/// used for the duration of the prefix callback.
struct LogPrefixWriter
{
nothrow @nogc:

    /// Borrowed resolved record. Null makes writes fail; a non-null value must
    /// remain valid for this writer's callback lifetime.
    LogRecordRef* record;
    bool failed;

    /// Writes ANSI-free prefix bytes with an optional semantic style.
    bool try_write(return scope String bytes, ANSIStyle style = ANSIStyle.init) @system
    {
        return this.try_write_impl(bytes, style, false);
    }

    /// Writes one prefix span that may contain supported embedded ANSI SGR.
    /// ANSI presentation terminates the span with a full reset, so embedded
    /// style state does not carry into a later prefix write or logger framing.
    /// One supported SGR sequence must not be split across two calls.
    bool try_write_ansi(return scope String bytes, ANSIStyle style = ANSIStyle.init) @system
    {
        return this.try_write_impl(bytes, style, true);
    }

    private bool try_write_impl(
        return scope String bytes,
        ANSIStyle style,
        bool may_contain_ansi,
    )
    {
        if (this.failed || this.record is null) return false;

        const bool accepted = may_contain_ansi
            ? (*this.record).try_write_ansi_text(bytes, style)
            : (*this.record).try_write_text(bytes, style);
        if (accepted) return true;

        this.failed = true;
        return false;
    }
}

/// Record-prefix provider callback.
///
/// `context` is opaque and may be null when the provider supports it. `output`
/// must not be null and is borrowed only for the duration of the callback.
alias LogPrefix = bool function(
    void* context,
    scope LogPrefixWriter* output,
) nothrow @nogc @system;

/// A copyable, non-owning reference to a record-prefix provider.
struct LogPrefixRef
{
nothrow @nogc:

    /// Provider callback. Null makes this reference invalid.
    LogPrefix prefix;
    /// Opaque borrowed provider context; may be null when the provider supports it.
    void* context;

    /// Creates a provider reference from an opaque callback context.
    ///
    /// `prefix` may be null, producing an invalid reference. `context` may be
    /// null when accepted by `prefix`; otherwise it must point to the context
    /// type expected by `prefix` and remain valid for every use of this reference.
    /// The opaque callback/context pairing is a caller-held safety invariant.
    static LogPrefixRef create(LogPrefix prefix, void* context) @system
    {
        return LogPrefixRef(prefix, context);
    }

    bool valid() const pure @safe
    {
        return this.prefix !is null;
    }

    /// Invokes the provider. `output` may be null, in which case this fails.
    /// The stored callback/context pair must satisfy the contract of `create`.
    bool try_write(scope LogPrefixWriter* output) @system
    {
        return this.valid && output !is null && this.prefix(this.context, output);
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
/// The wrapper owns neither child nor provider. Once `sink_ref()` has been taken,
/// this value must remain at a stable address and outlive every use of that
/// reference.
struct PrefixLogSink
{
nothrow @nogc:

    LogSinkRef child;
    LogPrefixRef prefix;

    static PrefixLogSink create(LogSinkRef child, LogPrefixRef prefix)
    {
        PrefixLogSink result;
        result.child = child;
        result.prefix = prefix;
        return result;
    }

    bool valid() const pure @safe
    {
        return this.child.valid && this.prefix.valid;
    }

    LogSinkRef sink_ref() return @trusted
    {
        // Both @system callbacks receive exactly &this as their opaque context.
        // `return` prevents the resulting sink reference from outliving this decorator.
        return LogSinkRef.create(
            &resolve_prefix_record,
            &this,
            &try_flush_prefix,
        );
    }
}

private LogRecordRef resolve_prefix_record(
    void* context,
    return scope const ref LogRecordInfo info,
    return scope const(LogSourceLocation)* callsite,
) @system
{
    PrefixLogSink* prefix_sink = cast(PrefixLogSink*) context;
    if (prefix_sink is null || !prefix_sink.valid) return LogRecordRef.init;

    LogRecordRef child_record = prefix_sink.child.begin_record(info, callsite);
    if (!child_record.valid) return LogRecordRef.init;

    LogPrefixWriter writer;
    writer.record = &child_record;
    const bool provider_accepted = prefix_sink.prefix.try_write(&writer);
    if (!provider_accepted || writer.failed) child_record.defer_failure();

    return move(child_record);
}

private bool try_flush_prefix(void* context) @system
{
    PrefixLogSink* prefix_sink = cast(PrefixLogSink*) context;
    return prefix_sink !is null && prefix_sink.child.try_flush();
}
