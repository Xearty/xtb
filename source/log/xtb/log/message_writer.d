module xtb.log.message_writer;

nothrow @nogc:

import core.attribute;

import xtb.fmt.writer;
import xtb.log.internal.sgr;
import xtb.log.sink;
import xtb.types;

/// A synchronous, allocation-free writer for one already-begun log message.
///
/// Small writes are coalesced in caller-owned staging storage. Large borrowed
/// slices bypass staging when possible. Artificial chunk boundaries never split
/// a supported SGR sequence, so stateless presentation sinks can process every
/// emitted chunk independently. A trailing incomplete SGR prefix is retained
/// across writes and ordinary flushes until it is completed or the message is
/// explicitly finished.
///
/// The writer owns neither its resolved record nor its staging storage. A valid
/// writer is created by the logging package for the duration of a synchronous
/// message producer and must not escape that producer.
@mustuse struct LogMessageWriter
{
nothrow @nogc:

    LogRecordRef* record;
    char[] staging;
    char[max_supported_sgr_length] sgr_carry;
    usize staged;
    usize sgr_carry_length;
    usize written;
    bool write_failed;

    @disable this(this);

    package static LogMessageWriter create(LogRecordRef* record, return scope char[] staging)
    {
        LogMessageWriter result;
        result.record = record;
        result.staging = staging;
        result.write_failed = record is null || !(*record).valid;
        return result;
    }

    bool failed() const pure @safe
    {
        return this.write_failed || this.record is null || !(*this.record).valid;
    }

    /// Appends borrowed message bytes synchronously.
    ///
    /// The input is never retained after this call. Empty input is ignored.
    /// Once the sink rejects a chunk, this writer becomes failed and later
    /// writes are no-ops.
    void write(scope String text)
    {
        if (this.failed || text.length == 0) return;

        usize offset;
        while (offset < text.length && !this.write_failed)
        {
            if (this.sgr_carry_length != 0)
            {
                this.resolve_sgr_carry(text, &offset);
                continue;
            }

            this.write_without_carry(text, &offset);
        }
    }

    /// Returns an immediate generic `Writer` view over this message.
    ///
    /// The returned writer borrows this `LogMessageWriter` and is valid only
    /// during the surrounding synchronous logger producer. Generic formatting
    /// reaches this writer immediately; this type remains responsible for
    /// staging and SGR-safe message chunk boundaries.
    Writer writer() return @trusted
    {
        return Writer.from_sink(&log_message_writer_sink, cast(void*)&this);
    }

    /// Emits every currently safe staged prefix.
    ///
    /// A trailing incomplete supported SGR sequence is deliberately retained so
    /// a later `write` can complete it without creating an unsafe chunk boundary.
    bool try_flush()
    {
        if (this.failed) return false;

        this.flush_staging();
        return !this.write_failed;
    }

    /// Finishes the producer side of the message.
    ///
    /// Unlike `try_flush`, the final incomplete SGR suffix is emitted literally:
    /// no later chunk can complete it, so doing so does not split a sequence
    /// across chunk boundaries.
    package bool try_finish()
    {
        if (this.failed) return false;

        this.flush_staging();
        if (this.write_failed) return false;

        if (this.sgr_carry_length != 0)
        {
            this.emit_chunk(this.sgr_carry[0 .. this.sgr_carry_length]);
            this.sgr_carry_length = 0;
        }

        return !this.write_failed;
    }

    private void write_without_carry(scope String text, usize* offset)
    {
        const remaining = text[*offset .. $];

        if (this.staging.length == 0)
        {
            this.emit_direct(remaining, offset);
            return;
        }

        // Preserve the zero-copy path for a large borrowed slice instead of
        // filling the remainder of a partially occupied staging buffer first.
        if (this.staged != 0 && remaining.length >= this.staging.length)
        {
            this.flush_staging();
            return;
        }

        if (this.staged == 0 && remaining.length >= this.staging.length)
        {
            this.emit_direct(remaining, offset);
            return;
        }

        const available = this.staging.length - this.staged;
        const amount = available < remaining.length ? available : remaining.length;
        foreach (index; 0 .. amount)
            this.staging[this.staged + index] = remaining[index];

        this.staged += amount;
        *offset += amount;

        if (this.staged == this.staging.length) this.flush_staging();
    }

    private void emit_direct(scope String text, usize* offset)
    {
        const usize safe_length = safe_sgr_prefix_length(text);
        if (safe_length != 0) this.emit_chunk(text[0 .. safe_length]);
        if (this.write_failed) return;

        *offset += safe_length;
        if (safe_length == text.length) return;

        const suffix = text[safe_length .. $];
        if (!this.try_store_sgr_carry(suffix)) return;

        *offset += suffix.length;
    }

    private void flush_staging()
    {
        if (this.write_failed || this.staged == 0) return;

        const bytes = cast(String) this.staging[0 .. this.staged];
        const usize safe_length = safe_sgr_prefix_length(bytes);
        if (safe_length != this.staged && !this.try_store_sgr_carry(bytes[safe_length .. $]))
            return;

        if (safe_length != 0) this.emit_chunk(bytes[0 .. safe_length]);
        this.staged = 0;
    }

    private bool try_store_sgr_carry(scope String suffix)
    {
        if (this.sgr_carry_length != 0 || suffix.length > this.sgr_carry.length)
        {
            this.write_failed = true;
            return false;
        }

        foreach (index; 0 .. suffix.length)
            this.sgr_carry[index] = suffix[index];

        this.sgr_carry_length = suffix.length;
        return true;
    }

    private void resolve_sgr_carry(scope String text, usize* offset)
    {
        while (*offset < text.length && !this.write_failed && this.sgr_carry_length != 0)
        {
            if (this.sgr_carry_length == this.sgr_carry.length)
            {
                this.write_failed = true;
                return;
            }

            this.sgr_carry[this.sgr_carry_length++] = text[(*offset)++];
            const SGRParseResult parsed = parse_sgr_prefix(
                this.sgr_carry[0 .. this.sgr_carry_length],
            );
            if (parsed.kind == SGRParseKind.incomplete) continue;

            this.emit_chunk(this.sgr_carry[0 .. this.sgr_carry_length]);
            this.sgr_carry_length = 0;
        }
    }

    private void emit_chunk(scope String bytes)
    {
        if (this.write_failed || bytes.length == 0) return;

        if (bytes.length > usize.max - this.written)
        {
            this.write_failed = true;
            return;
        }

        if (!(*this.record).try_message_chunk(bytes))
        {
            this.write_failed = true;
            return;
        }

        this.written += bytes.length;
    }
}

private usize log_message_writer_sink(void* context, scope const(u8)[] bytes) @trusted
{
    LogMessageWriter* writer = cast(LogMessageWriter*) context;
    if (writer is null || writer.failed) return 0;

    writer.write(cast(String) bytes);
    return writer.failed ? 0 : bytes.length;
}
