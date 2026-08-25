module xtb.log.message_writer;

nothrow @nogc:

import xtb.log.internal.sgr : SgrParseKind, maxSupportedSgrLength,
    parseSgrPrefix, safeSgrPrefixLength;
import xtb.log.sink : LogRecordRef;
import xtb.core.fmt.writer : Writer;
import xtb.core.string : String;
import xtb.core.types : u8;

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
/// writer is created by the logging package for the duration of a synchronous message
/// producer and must not escape that producer.
struct LogMessageWriter
{
nothrow @nogc:

    private LogRecordRef* record_;
    private char[] staging_;
    private char[maxSupportedSgrLength] sgrCarry_;
    private size_t staged_;
    private size_t sgrCarryLength_;
    private size_t written_;
    private bool failed_;

    @disable this(this);

    bool failed() const pure @safe
    {
        return failed_ || record_ is null || !(*record_).valid;
    }

    /// Appends borrowed message bytes synchronously.
    ///
    /// The input is never retained after this call. Empty input is ignored.
    /// Once the sink rejects a chunk, this writer becomes failed and later
    /// writes are no-ops.
    void write(scope String text)
    {
        if (failed || text.length == 0)
            return;

        size_t offset;
        while (offset < text.length && !failed_)
        {
            if (sgrCarryLength_ != 0)
            {
                resolveSgrCarry(text, &offset);
                continue;
            }

            writeWithoutCarry(text, &offset);
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
        return Writer.fromSink(
            &logMessageWriterSink,
            cast(void*)&this,
        );
    }

    /// Emits every currently safe staged prefix.
    ///
    /// A trailing incomplete supported SGR sequence is deliberately retained so
    /// a later `write` can complete it without creating an unsafe chunk boundary.
    bool flush()
    {
        if (failed)
            return false;
        flushStaging();
        return !failed_;
    }

    package size_t written() const pure @safe
    {
        return written_;
    }

    /// Finishes the producer side of the message.
    ///
    /// Unlike `flush`, the final incomplete SGR suffix is emitted literally: no
    /// later chunk can complete it, so doing so does not split a sequence across
    /// chunk boundaries.
    package bool finish()
    {
        if (failed)
            return false;

        flushStaging();
        if (failed_)
            return false;

        if (sgrCarryLength_ != 0)
        {
            emitChunk(sgrCarry_[0 .. sgrCarryLength_]);
            sgrCarryLength_ = 0;
        }
        return !failed_;
    }

    private void writeWithoutCarry(scope String text, size_t* offset)
    {
        const remaining = text[*offset .. $];

        if (staging_.length == 0)
        {
            emitDirect(remaining, offset);
            return;
        }

        // Preserve the zero-copy path for a large borrowed slice instead of
        // filling the remainder of a partially occupied staging buffer first.
        if (staged_ != 0 && remaining.length >= staging_.length)
        {
            flushStaging();
            return;
        }

        if (staged_ == 0 && remaining.length >= staging_.length)
        {
            emitDirect(remaining, offset);
            return;
        }

        const available = staging_.length - staged_;
        const amount = available < remaining.length ? available : remaining.length;
        foreach (index; 0 .. amount)
            staging_[staged_ + index] = remaining[index];
        staged_ += amount;
        *offset += amount;

        if (staged_ == staging_.length)
            flushStaging();
    }

    private void emitDirect(scope String text, size_t* offset)
    {
        const safeLength = safeSgrPrefixLength(text);
        if (safeLength != 0)
            emitChunk(text[0 .. safeLength]);
        if (failed_)
            return;

        *offset += safeLength;
        if (safeLength == text.length)
            return;

        const suffix = text[safeLength .. $];
        if (!storeSgrCarry(suffix))
            return;
        *offset += suffix.length;
    }

    private void flushStaging()
    {
        if (failed_ || staged_ == 0)
            return;

        const bytes = cast(String) staging_[0 .. staged_];
        const safeLength = safeSgrPrefixLength(bytes);
        if (safeLength != staged_ && !storeSgrCarry(bytes[safeLength .. $]))
            return;

        if (safeLength != 0)
            emitChunk(bytes[0 .. safeLength]);
        staged_ = 0;
    }

    private bool storeSgrCarry(scope String suffix)
    {
        if (sgrCarryLength_ != 0 || suffix.length > sgrCarry_.length)
        {
            failed_ = true;
            return false;
        }

        foreach (index; 0 .. suffix.length)
            sgrCarry_[index] = suffix[index];
        sgrCarryLength_ = suffix.length;
        return true;
    }

    private void resolveSgrCarry(scope String text, size_t* offset)
    {
        while (*offset < text.length && !failed_ && sgrCarryLength_ != 0)
        {
            if (sgrCarryLength_ == sgrCarry_.length)
            {
                failed_ = true;
                return;
            }

            sgrCarry_[sgrCarryLength_++] = text[(*offset)++];
            const parsed = parseSgrPrefix(sgrCarry_[0 .. sgrCarryLength_]);
            if (parsed.kind == SgrParseKind.incomplete)
                continue;

            emitChunk(sgrCarry_[0 .. sgrCarryLength_]);
            sgrCarryLength_ = 0;
        }
    }

    private void emitChunk(scope String bytes)
    {
        if (failed_ || bytes.length == 0)
            return;
        if (bytes.length > size_t.max - written_)
        {
            failed_ = true;
            return;
        }

        if (!(*record_).messageChunk(bytes))
        {
            failed_ = true;
            return;
        }
        written_ += bytes.length;
    }
}

private size_t logMessageWriterSink(
    void* context,
    scope const(u8)[] bytes,
)
@trusted
{
    LogMessageWriter* writer = cast(LogMessageWriter*) context;
    if (writer is null || writer.failed)
        return 0;

    writer.write(cast(String) bytes);
    return writer.failed ? 0 : bytes.length;
}

package LogMessageWriter createLogMessageWriter(
    LogRecordRef* record,
    return scope char[] staging,
)
{
    LogMessageWriter result;
    result.record_ = record;
    result.staging_ = staging;
    result.failed_ = record is null || !(*record).valid;
    return result;
}
