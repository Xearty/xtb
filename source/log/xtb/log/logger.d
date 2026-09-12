module xtb.log.logger;

nothrow @nogc:

import xtb.fmt.fixed_buffer;
import xtb.log.internal.sgr;
import xtb.log.labels;
import xtb.log.level;
import xtb.log.message_writer;
import xtb.log.palette;
import xtb.log.result;
import xtb.log.sink;
import xtb.types;

struct Logger
{
nothrow @nogc:

    LogSinkRef sink;
    char[] message_buffer;
    LogLevel minimum_level;
    LogPalette palette;
    /// Complete presentation labels. Use `set_level_labels` to keep the cached width synchronized.
    LogLevelLabels level_labels;
    /// Cached width of `level_labels`; maintained by `create` and `set_level_labels`.
    usize maximum_level_label_width;
    /// Whether new records capture the public caller's function and line.
    bool callsites_enabled;
    /// Whether level labels pad the following message into one column.
    bool message_alignment_enabled;
    /// Reentrancy guard used only while a record is being delivered.
    bool delivering;

    @disable this(this);

    /// Creates a logger borrowing both `sink` and `message_buffer`.
    ///
    /// `message_buffer` bounds the complete message produced by `log` / `logf`
    /// and their level-specific wrappers. `stream` instead reuses it only as
    /// staging storage, so a streamed message is not size-limited by the buffer.
    static Logger create(
        LogSinkRef sink,
        return scope char[] message_buffer,
        LogLevel minimum_level = LogLevel.info,
        LogPalette palette = LogPalette.defaults(),
    ) @safe
    {
        const LogLevelLabels default_labels = LogLevelLabels.defaults();
        Logger result;
        result.sink = sink;
        result.message_buffer = message_buffer;
        result.minimum_level = minimum_level;
        result.palette = palette;
        result.level_labels = default_labels;
        result.maximum_level_label_width = default_labels.maximum_width;
        result.message_alignment_enabled = true;
        return result;
    }

    /// Convenience overload for constructing the borrowed sink descriptor inline.
    ///
    /// `sink` may be null, producing an invalid logger. `flush` may be null.
    /// `context` may be null when accepted by the supplied callbacks; otherwise it
    /// must point to the context type they expect and remain valid for every use of
    /// the returned logger. The callback/context pairing is a caller-held safety
    /// invariant.
    static Logger create(
        LogSink sink,
        void* context,
        return scope char[] message_buffer,
        LogLevel minimum_level = LogLevel.info,
        LogFlush flush = null,
        LogPalette palette = LogPalette.defaults(),
    ) @system
    {
        return Logger.create(
            LogSinkRef.create(sink, context, flush),
            message_buffer,
            minimum_level,
            palette,
        );
    }

    bool valid() const pure @safe
    {
        return this.sink.valid;
    }

    private static usize message_padding(
        String label,
        usize maximum_label_width,
        bool aligned,
    ) pure @safe
    {
        if (!aligned) return 1;

        return maximum_label_width >= label.length
            ? maximum_label_width - label.length + 1
            : 1;
    }

    bool enabled(LogLevel level) const pure @safe
    {
        return this.valid && level >= this.minimum_level;
    }

    /// Selects a built-in palette without constructing it at the call site.
    void set_palette(LogPalettePreset preset) scope @safe
    {
        this.palette = LogPalette.preset(preset);
    }

    /// Selects the complete presentation labels used for subsequent records.
    ///
    /// Custom label bytes are borrowed and must outlive this logger. Alignment width
    /// is recomputed once here rather than for every emitted record.
    void set_level_labels(LogLevelLabels labels) scope @safe
    {
        this.level_labels = labels;
        this.maximum_level_label_width = labels.maximum_width;
    }

    /// Selects a built-in level-label set.
    void set_level_labels(LogLevelLabelPreset preset) scope @safe
    {
        this.set_level_labels(LogLevelLabels.preset(preset));
    }

    /// Replaces this logger's sink using an opaque callback context.
    ///
    /// `sink` may be null, making this logger invalid. `flush` may be null.
    /// `context` may be null when accepted by the supplied callbacks; otherwise it
    /// must point to the context type they expect and remain valid until this sink
    /// is replaced or the logger is no longer used. The callback/context pairing is
    /// a caller-held safety invariant.
    void set_sink(LogSink sink, void* context, LogFlush flush = null) @system
    {
        this.sink = LogSinkRef.create(sink, context, flush);
    }

    private LogRecordInfo record_info(LogLevel level) const pure @safe
    {
        const LogLevelStyle style = this.palette.style_for(level);
        const String label = this.level_labels.label_for(level);
        return LogRecordInfo(
            level,
            label,
            style.label,
            style.message,
            Logger.message_padding(
                label,
                this.maximum_level_label_width,
                this.message_alignment_enabled,
            ),
        );
    }

    private LogResult deliver(
        LogLevel level,
        BufferWriteResult formatted,
        LogSourceLocation callsite,
    ) @system
    {
        if (this.delivering) return LogResult(LogStatus.recursive, 0, formatted.required);

        LogSinkRef sink_ref = this.sink;
        const LogRecordInfo info = this.record_info(level);
        const(LogSourceLocation)* callsite_ptr = this.callsites_enabled ? &callsite : null;
        const String formatted_message = cast(String) this.message_buffer[0 .. formatted.written];
        const usize safe_written = formatted.truncated
            ? safe_sgr_prefix_length(formatted_message)
            : formatted.written;
        this.delivering = true;

        LogRecordRef record = sink_ref.begin_record(info, callsite_ptr);
        if (!record.valid)
        {
            this.delivering = false;
            return LogResult(LogStatus.sink_failed, safe_written, formatted.required);
        }

        bool payload_accepted = record.try_begin_message();
        if (payload_accepted && safe_written != 0)
            payload_accepted = record.try_message_chunk(this.message_buffer[0 .. safe_written]);

        if (record.message_open)
        {
            const bool ended_message = record.try_end_message();
            payload_accepted = ended_message && payload_accepted;
        }
        if (payload_accepted) payload_accepted = record.try_write_text("\n");

        const bool ended_record = record.try_end_record();
        const bool accepted = payload_accepted && ended_record;
        this.delivering = false;

        if (!accepted) return LogResult(LogStatus.sink_failed, safe_written, formatted.required);
        return LogResult(
            formatted.truncated ? LogStatus.truncated : LogStatus.delivered,
            safe_written,
            formatted.required,
        );
    }

    /// Explicitly emits one unbounded synchronous message incrementally.
    ///
    /// Unlike `log` / `logf`, the complete message does not need to fit in
    /// `message_buffer`. Use this path when unbounded diagnostic output is deliberate;
    /// ordinary logging remains bounded by the logger buffer.
    ///
    /// `producer` is invoked exactly once after the sink has accepted the record
    /// framing and message begin event. It receives a borrowed `LogMessageWriter`
    /// that reuses this logger's message buffer as staging storage and is valid only
    /// for the duration of the call. The producer must not retain the writer or any
    /// reference/pointer to it after returning. Filtering, an invalid logger, recursion, or a
    /// sink failure before the message begins prevent the producer from running.
    /// The record lifecycle stays open while `producer` executes, so a sink that
    /// serializes records may hold its record lock for the producer's full duration.
    ///
    /// On success, `written` and `required` both report the message bytes accepted
    /// by the sink. On sink failure they report the successfully accepted streamed
    /// prefix; unlike bounded formatting, a stream has no separately knowable full
    /// required length after output has stopped.
    LogResult stream(Producer)(
        LogLevel level,
        scope auto ref Producer producer,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    ) @system
    {
        if (!this.valid) return LogResult(LogStatus.invalid_logger, 0, 0);
        if (level < this.minimum_level) return LogResult(LogStatus.filtered, 0, 0);
        if (this.delivering) return LogResult(LogStatus.recursive, 0, 0);

        LogSinkRef sink_ref = this.sink;
        const LogRecordInfo info = this.record_info(level);
        const(LogSourceLocation)* callsite_ptr = this.callsites_enabled ? &callsite : null;
        this.delivering = true;

        LogRecordRef record = sink_ref.begin_record(info, callsite_ptr);
        if (!record.valid)
        {
            this.delivering = false;
            return LogResult(LogStatus.sink_failed, 0, 0);
        }

        bool payload_accepted = record.try_begin_message();
        usize written;
        if (payload_accepted)
        {
            auto writer = LogMessageWriter.create(&record, this.message_buffer);
            producer(writer);
            payload_accepted = writer.try_finish();
            written = writer.written;
        }

        if (record.message_open)
        {
            const bool ended_message = record.try_end_message();
            payload_accepted = ended_message && payload_accepted;
        }
        if (payload_accepted) payload_accepted = record.try_write_text("\n");

        const bool ended_record = record.try_end_record();
        const bool accepted = payload_accepted && ended_record;
        this.delivering = false;

        return LogResult(
            accepted ? LogStatus.delivered : LogStatus.sink_failed,
            written,
            written,
        );
    }

    /// Emits one bounded message.
    ///
    /// Formatting completes into `message_buffer` before the sink record begins. If
    /// the representation does not fit, the delivered prefix is reported as
    /// `LogStatus.truncated`. Use `stream` for deliberate unbounded output. The
    /// trailing default source argument captures this public call site and is only
    /// rendered when callsites are enabled on the logger.
    LogResult log(Args...)(
        LogLevel level,
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.log_at!Args(level, callsite, args);
    }

    /// Formats and emits one bounded message.
    ///
    /// Formatting completes into `message_buffer` before the sink record begins. If
    /// the representation does not fit, the delivered prefix is reported as
    /// `LogStatus.truncated`. Use `stream` for deliberate unbounded output. The
    /// trailing default source argument captures this public call site and is only
    /// rendered when callsites are enabled on the logger.
    LogResult logf(string pattern, Args...)(
        LogLevel level,
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.logf_at!(pattern, Args)(level, callsite, args);
    }

    // Forwarding layers use a fixed callsite parameter before the variadic message
    // arguments. This keeps an empty Args tuple unambiguous: a forwarded
    // LogSourceLocation can never be re-deduced as message data.
    package(xtb.log) LogResult log_at(Args...)(
        LogLevel level,
        LogSourceLocation callsite,
        auto ref Args args,
    )
    {
        if (!this.valid) return LogResult(LogStatus.invalid_logger, 0, 0);
        if (level < this.minimum_level) return LogResult(LogStatus.filtered, 0, 0);
        if (this.delivering) return LogResult(LogStatus.recursive, 0, 0);
        const BufferWriteResult formatted = write_buffer(this.message_buffer, args);
        return this.deliver(level, formatted, callsite);
    }

    package(xtb.log) LogResult logf_at(string pattern, Args...)(
        LogLevel level,
        LogSourceLocation callsite,
        auto ref Args args,
    )
    {
        if (!this.valid) return LogResult(LogStatus.invalid_logger, 0, 0);
        if (level < this.minimum_level) return LogResult(LogStatus.filtered, 0, 0);
        if (this.delivering) return LogResult(LogStatus.recursive, 0, 0);
        const BufferWriteResult formatted = format_buffer!pattern(this.message_buffer, args);
        return this.deliver(level, formatted, callsite);
    }

    LogResult trace(Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.log_at!Args(LogLevel.trace, callsite, args);
    }

    LogResult tracef(string pattern, Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.logf_at!(pattern, Args)(LogLevel.trace, callsite, args);
    }

    LogResult debug_(Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.log_at!Args(LogLevel.debug_, callsite, args);
    }

    LogResult debugf(string pattern, Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.logf_at!(pattern, Args)(LogLevel.debug_, callsite, args);
    }

    LogResult info(Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.log_at!Args(LogLevel.info, callsite, args);
    }

    LogResult infof(string pattern, Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.logf_at!(pattern, Args)(LogLevel.info, callsite, args);
    }

    LogResult warning(Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.log_at!Args(LogLevel.warning, callsite, args);
    }

    LogResult warningf(string pattern, Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.logf_at!(pattern, Args)(LogLevel.warning, callsite, args);
    }

    LogResult error(Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.log_at!Args(LogLevel.error, callsite, args);
    }

    LogResult errorf(string pattern, Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.logf_at!(pattern, Args)(LogLevel.error, callsite, args);
    }

    LogResult fatal(Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.log_at!Args(LogLevel.fatal, callsite, args);
    }

    LogResult fatalf(string pattern, Args...)(
        auto ref Args args,
        LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
    )
    {
        return this.logf_at!(pattern, Args)(LogLevel.fatal, callsite, args);
    }

    /// Flushes the configured sink. Its borrowed callback/context pair must remain valid.
    bool try_flush() @system
    {
        return this.sink.try_flush();
    }
}
