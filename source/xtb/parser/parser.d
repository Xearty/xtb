module xtb.parser.parser;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.stdc.errno : ERANGE, errno;
import core.stdc.math : isfinite;
import core.stdc.stdlib : strtod;
import core.stdc.string : memcpy;
import xtb.core.allocators.arena : Arena;
import xtb.core.memory : Allocator;
import xtb.core.lifetime : hasDDestructor, move, moveEmplace, needsDeinit;
import xtb.core.numeric : addOverflows;
import xtb.core.option : Option;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.types : String;

/// Whether a failed parser permits an enclosing choice to try another branch.
enum FailureKind : ubyte
{
    recoverable,
    committed,
}

/// Unit value used by parsers whose success carries no semantic value.
struct Unit
{
nothrow @nogc:
}

/// High-level category for a parse failure.
enum ParseErrorKind : ubyte
{
    none,
    expected,
    invalidSyntax,
    depthLimit,
    numberOutOfRange,
}

/// Fixed-capacity expectation set. Tracking errors never allocates.
struct ExpectedSet
{
nothrow @nogc:
    enum capacity = 8;

    private String[capacity] values_;
    private ubyte length_;

    size_t length() pure @safe
    {
        return length_;
    }

    bool empty() pure @safe
    {
        return length_ == 0;
    }

    String opIndex(size_t index) const return @trusted
    {
        version (XTB_Checked)
            require(index < length_, "parse expected-item index out of bounds");
        return values_[index];
    }

package(xtb.parser):
    void clear()
    {
        length_ = 0;
    }

    void add(String value)
    {
        if (value.length == 0)
            return;
        foreach (index; 0 .. length_)
            if (values_[index] == value)
                return;
        if (length_ < capacity)
            values_[length_++] = value;
    }
}

/// Structured parse error. All strings borrow grammar or input storage.
struct ParseError
{
nothrow @nogc:
    ParseErrorKind kind;
    size_t offset;
    ExpectedSet expected;
    String parserName;
    String context;

    bool valid() pure @safe
    {
        return kind != ParseErrorKind.none;
    }
}

/// Optional application state supplied to semantic actions and collectors.
struct ParseContext
{
nothrow @nogc:
    Arena* outputArena;
    void* userData;

    static ParseContext create(
        Arena* outputArena = null,
        void* userData = null,
    ) pure @safe
    {
        return ParseContext(outputArena, userData);
    }
}

/// Mutable state for one parse invocation.
struct ParseState
{
nothrow @nogc:
private:
    String input_;
    size_t offset_;
    ParseError bestError_;
    ParseContext* context_;
    size_t cutGeneration_;

public:
    static ParseState create(
        String input,
        ParseContext* context = null,
    ) pure @safe
    {
        ParseState result;
        result.input_ = input;
        result.context_ = context;
        return result;
    }

    String input() const return pure @safe
    {
        return input_;
    }

    size_t offset() pure @safe
    {
        return offset_;
    }

    bool atEnd() pure @safe
    {
        return offset_ >= input_.length;
    }

    size_t remaining() pure @safe
    {
        return offset_ <= input_.length ? input_.length - offset_ : 0;
    }

    String rest() const return @trusted
    {
        return input_[offset_ .. $];
    }

    ParseContext* context() return pure @safe
    {
        return context_;
    }

    const(ParseContext)* context() const return pure @safe
    {
        return context_;
    }

    ParseError error() pure @safe
    {
        return bestError_;
    }

package(xtb.parser):
    char peekByte() @trusted
    {
        version (XTB_Checked)
            require(!atEnd, "cannot peek past parser input");
        return input_[offset_];
    }

    char takeByte() @trusted
    {
        version (XTB_Checked)
            require(!atEnd, "cannot consume past parser input");
        return input_[offset_++];
    }

    bool consumeByte(char value) @trusted
    {
        if (atEnd || input_[offset_] != value)
            return false;
        ++offset_;
        return true;
    }

    void setOffset(size_t offset) @trusted
    {
        version (XTB_Checked)
            require(offset <= input_.length, "parse offset is outside input");
        offset_ = offset;
    }

    size_t cutGeneration() pure @safe
    {
        return cutGeneration_;
    }

    void establishCut()
    {
        ++cutGeneration_;
    }

    void restoreCutGeneration(size_t generation)
    {
        cutGeneration_ = generation;
    }

    void fail(
        ParseErrorKind kind,
        size_t offset,
        String expected = String.init,
        String parserName = String.init,
        String context = String.init,
    )
    {
        if (!bestError_.valid || offset > bestError_.offset)
        {
            bestError_ = ParseError.init;
            bestError_.kind = kind;
            bestError_.offset = offset;
            bestError_.expected.add(expected);
            bestError_.parserName = parserName;
            bestError_.context = context;
            return;
        }
        if (offset < bestError_.offset)
            return;
        if (bestError_.kind == ParseErrorKind.expected && kind != ParseErrorKind.expected)
            bestError_.kind = kind;
        bestError_.expected.add(expected);
        if (bestError_.parserName.length == 0 && parserName.length != 0)
            bestError_.parserName = parserName;
        if (bestError_.context.length == 0 && context.length != 0)
            bestError_.context = context;
    }

    void replaceExpectationAt(
        size_t offset,
        String expected,
        String parserName = String.init,
    )
    {
        if (!bestError_.valid || bestError_.offset != offset)
            return;
        bestError_.kind = ParseErrorKind.expected;
        bestError_.expected.clear();
        bestError_.expected.add(expected);
        if (parserName.length != 0)
            bestError_.parserName = parserName;
    }

    void attachContextAtOrAfter(size_t offset, String context)
    {
        if (bestError_.valid && bestError_.offset >= offset && context.length != 0)
            bestError_.context = context;
    }
}

/// Public result of parsing an input or state.
struct ParseResult(T)
{
nothrow @nogc:
    T value;
    ParseError error;
    bool success;
    FailureKind failureKind;
    size_t offset;

    bool ok() pure @safe
    {
        return success;
    }

    bool failed() pure @safe
    {
        return !success;
    }
}

/// Result of a sequencing combinator.
struct Pair(A, B)
{
nothrow @nogc:
    A first;
    B second;
}

package(xtb.parser) struct ParseOutcome(T)
{
nothrow @nogc:
    T value;
    bool success;
    FailureKind failureKind;

    static ParseOutcome succeed(T value)
    {
        ParseOutcome result;
        result.value = move(value);
        result.success = true;
        return result;
    }

    static ParseOutcome failure(FailureKind kind = FailureKind.recoverable)
    {
        ParseOutcome result;
        result.failureKind = kind;
        return result;
    }
}

package(xtb.parser) alias ParseFunction(T) = ParseOutcome!T function(
    void* node,
    ref ParseState state,
) @system nothrow @nogc;

private ParseOutcome!T dispatchNode(T, Node)(
    void* rawNode,
    ref ParseState state,
) @trusted
{
    return (cast(Node*) rawNode).parse(state);
}

package(xtb.parser) Parser!T parserFromNode(T, Node)(
    Arena* arena,
    Node node,
) @trusted
{
    version (XTB_Checked)
        require(arena !is null, "parser node requires an arena");
    Node* stored = arena.allocateInit!Node();
    *stored = move(node);
    Parser!T result;
    result.arena_ = arena;
    result.node_ = stored;
    result.parse_ = &dispatchNode!(T, Node);
    return result;
}

private void requireCompatibleArenas(A, B)(scope const Parser!A left, scope const Parser!B right)
{
    version (XTB_Checked)
    {
        require(left.valid, "left parser is invalid");
        require(right.valid, "right parser is invalid");
        require(left.arena_ is right.arena_, "cannot combine parsers from different grammars");
    }
}

package(xtb.parser) ParseOutcome!T invokeParser(T)(Parser!T parser, ref ParseState state) @trusted
{
    version (XTB_Checked)
        require(parser.valid, "cannot invoke an invalid parser");
    const startOffset = state.offset_;
    const startCut = state.cutGeneration_;
    ParseOutcome!T result = parser.parse_(parser.node_, state);
    if (!result.success && result.failureKind == FailureKind.recoverable &&
        (state.offset_ != startOffset || state.cutGeneration_ != startCut))
        result.failureKind = FailureKind.committed;
    return result;
}

/// Small non-owning parser handle. The owning `Grammar` must outlive it.
struct Parser(T)
{
nothrow @nogc:
private:
    Arena* arena_;
    void* node_;
    ParseFunction!T parse_;

public:
    bool valid() const pure @safe
    {
        return arena_ !is null && node_ !is null && parse_ !is null;
    }

    ParseResult!T parse(
        String input,
        ParseContext* context = null,
    ) @trusted
    {
        ParseState state = ParseState.create(input, context);
        return parse(state);
    }

    ParseResult!T parse(ref ParseState state) @trusted
    {
        ParseOutcome!T outcome = invokeParser(this, state);
        ParseResult!T result;
        result.success = outcome.success;
        result.failureKind = outcome.failureKind;
        result.error = state.bestError_;
        result.offset = state.offset_;
        if (outcome.success)
            result.value = move(outcome.value);
        return result;
    }

    Parser!(Pair!(T, U)) then(U)(Parser!U next) @trusted
    {
        requireCompatibleArenas(this, next);
        ThenNode!(T, U) node;
        node.first = this;
        node.second = next;
        return parserFromNode!(Pair!(T, U))(arena_, node);
    }

    Parser!T before(U)(Parser!U next) @trusted
    {
        requireCompatibleArenas(this, next);
        BeforeNode!(T, U) node;
        node.first = this;
        node.second = next;
        return parserFromNode!T(arena_, node);
    }

    Parser!U after(U)(Parser!U next) @trusted
    {
        requireCompatibleArenas(this, next);
        AfterNode!(T, U) node;
        node.first = this;
        node.second = next;
        return parserFromNode!U(arena_, node);
    }

    Parser!T between(L, R)(Parser!L left, Parser!R right) @trusted
    {
        return left.after(this).before(right);
    }

    Parser!T attempt() @trusted
    {
        AttemptNode!T node;
        node.parser = this;
        return parserFromNode!T(arena_, node);
    }

    Parser!T cut() @trusted
    {
        CutNode!T node;
        node.parser = this;
        return parserFromNode!T(arena_, node);
    }

    auto optional(Dummy = void)() @trusted
    {
        OptionalNode!T node;
        node.parser = this;
        return parserFromNode!(Option!T)(arena_, node);
    }

    auto repeat(Dummy = void)() pure @safe
    {
        return RepetitionParser!T(this, false);
    }

    auto repeat1(Dummy = void)() pure @safe
    {
        return RepetitionParser!T(this, true);
    }

    SeparatedParser!(T, S) sepBy(S)(Parser!S separator) @trusted
    {
        requireCompatibleArenas(this, separator);
        return SeparatedParser!(T, S)(this, separator, false);
    }

    SeparatedParser!(T, S) sepBy1(S)(Parser!S separator) @trusted
    {
        requireCompatibleArenas(this, separator);
        return SeparatedParser!(T, S)(this, separator, true);
    }

    auto map(alias mapper)() @trusted
    {
        alias U = MapReturn!(mapper, T);
        MapNode!(T, U, mapper) node;
        node.parser = this;
        return parserFromNode!U(arena_, node);
    }

    Parser!U mapTuple(U)() @trusted if (__traits(isCopyable, T) && __traits(isCopyable, U))
    {
        static assert(flattenedCount!T == U.tupleof.length,
            "mapTuple destination field count must match flattened parser result count");
        MapTupleNode!(T, U) node;
        node.parser = this;
        return parserFromNode!U(arena_, node);
    }

    Parser!T where(alias predicate)(String expectation = String.init) @trusted
    {
        WhereNode!(T, predicate) node;
        node.parser = this;
        node.expectation = copyIntoArena(arena_, expectation);
        return parserFromNode!T(arena_, node);
    }

    Parser!U replace(U)(U value) @trusted if (__traits(isCopyable, U))
    {
        ReplaceNode!(T, U) node;
        node.parser = this;
        node.value = value;
        return parserFromNode!U(arena_, node);
    }

    Parser!Unit skip() @trusted
    {
        SkipNode!T node;
        node.parser = this;
        return parserFromNode!Unit(arena_, node);
    }

    Parser!T named(String name) @trusted
    {
        NamedNode!T node;
        node.parser = this;
        node.name = copyIntoArena(arena_, name);
        return parserFromNode!T(arena_, node);
    }

    Parser!T context(String name) @trusted
    {
        ContextNode!T node;
        node.parser = this;
        node.name = copyIntoArena(arena_, name);
        return parserFromNode!T(arena_, node);
    }

    Parser!T peek() @trusted
    {
        PeekNode!T node;
        node.parser = this;
        return parserFromNode!T(arena_, node);
    }

package(xtb.parser):
    Arena* owningArena() return pure @safe
    {
        return arena_;
    }
}

private struct ThenNode(A, B)
{
nothrow @nogc:
    Parser!A first;
    Parser!B second;

    ParseOutcome!(Pair!(A, B)) parse(ref ParseState state)
    {
        ParseOutcome!A left = invokeParser(first, state);
        if (!left.success)
            return ParseOutcome!(Pair!(A, B)).failure(left.failureKind);
        ParseOutcome!B right = invokeParser(second, state);
        if (!right.success)
            return ParseOutcome!(Pair!(A, B)).failure(right.failureKind);
        Pair!(A, B) value;
        value.first = move(left.value);
        value.second = move(right.value);
        return ParseOutcome!(Pair!(A, B)).succeed(move(value));
    }
}

private struct BeforeNode(A, B)
{
nothrow @nogc:
    Parser!A first;
    Parser!B second;

    ParseOutcome!A parse(ref ParseState state)
    {
        ParseOutcome!A left = invokeParser(first, state);
        if (!left.success)
            return ParseOutcome!A.failure(left.failureKind);
        ParseOutcome!B right = invokeParser(second, state);
        if (!right.success)
            return ParseOutcome!A.failure(right.failureKind);
        return ParseOutcome!A.succeed(move(left.value));
    }
}

private struct AfterNode(A, B)
{
nothrow @nogc:
    Parser!A first;
    Parser!B second;

    ParseOutcome!B parse(ref ParseState state)
    {
        ParseOutcome!A left = invokeParser(first, state);
        if (!left.success)
            return ParseOutcome!B.failure(left.failureKind);
        ParseOutcome!B right = invokeParser(second, state);
        if (!right.success)
            return ParseOutcome!B.failure(right.failureKind);
        return ParseOutcome!B.succeed(move(right.value));
    }
}

private struct AttemptNode(T)
{
nothrow @nogc:
    Parser!T parser;

    ParseOutcome!T parse(ref ParseState state)
    {
        const startOffset = state.offset_;
        const startCut = state.cutGeneration_;
        ParseOutcome!T result = invokeParser(parser, state);
        if (result.success)
            return result;
        if (state.cutGeneration_ != startCut)
        {
            result.failureKind = FailureKind.committed;
            return result;
        }
        state.offset_ = startOffset;
        state.cutGeneration_ = startCut;
        result.failureKind = FailureKind.recoverable;
        return result;
    }
}

private struct CutNode(T)
{
nothrow @nogc:
    Parser!T parser;

    ParseOutcome!T parse(ref ParseState state)
    {
        ParseOutcome!T result = invokeParser(parser, state);
        if (result.success)
            state.establishCut();
        return result;
    }
}

private struct OptionalNode(T)
{
nothrow @nogc:
    Parser!T parser;

    ParseOutcome!(Option!T) parse(ref ParseState state)
    {
        ParseOutcome!T result = invokeParser(parser, state);
        if (result.success)
            return ParseOutcome!(Option!T).succeed(Option!T.some(move(result.value)));
        if (result.failureKind == FailureKind.committed)
            return ParseOutcome!(Option!T).failure(FailureKind.committed);
        return ParseOutcome!(Option!T).succeed(Option!T.none());
    }
}

private template MapReturn(alias mapper, T)
{
    static if (__traits(compiles, mapper(T.init)))
        alias MapReturn = typeof(mapper(T.init));
    else static if (__traits(compiles, mapper(*cast(ParseContext*) null, T.init)))
        alias MapReturn = typeof(mapper(*cast(ParseContext*) null, T.init));
    else
        static assert(false, "map function must accept T or (ref ParseContext, T)");
}

private struct MapNode(T, U, alias mapper)
{
nothrow @nogc:
    Parser!T parser;

    ParseOutcome!U parse(ref ParseState state) @trusted
    {
        ParseOutcome!T source = invokeParser(parser, state);
        if (!source.success)
            return ParseOutcome!U.failure(source.failureKind);
        static if (__traits(compiles, mapper(source.value)))
        {
            U mapped = mapper(source.value);
            return ParseOutcome!U.succeed(move(mapped));
        }
        else
        {
            version (XTB_Checked)
                require(state.context_ !is null,
                    "context-aware parser mapping requires ParseContext");
            U mappedWithContext = mapper(*state.context_, source.value);
            return ParseOutcome!U.succeed(move(mappedWithContext));
        }
    }
}

private template flattenedCount(T)
{
    static if (is(T == Pair!(A, B), A, B))
        enum flattenedCount = flattenedCount!A + flattenedCount!B;
    else
        enum flattenedCount = 1;
}

private void assignFlattened(U, V, size_t index)(ref U output, V value)
{
    static if (is(V == Pair!(A, B), A, B))
    {
        assignFlattened!(U, A, index)(output, value.first);
        assignFlattened!(U, B, index + flattenedCount!A)(output, value.second);
    }
    else
        output.tupleof[index] = value;
}

private struct MapTupleNode(T, U)
{
nothrow @nogc:
    Parser!T parser;

    ParseOutcome!U parse(ref ParseState state)
    {
        ParseOutcome!T source = invokeParser(parser, state);
        if (!source.success)
            return ParseOutcome!U.failure(source.failureKind);
        U mapped;
        assignFlattened!(U, T, 0)(mapped, source.value);
        return ParseOutcome!U.succeed(move(mapped));
    }
}

private struct WhereNode(T, alias predicate)
{
nothrow @nogc:
    Parser!T parser;
    String expectation;

    ParseOutcome!T parse(ref ParseState state)
    {
        const start = state.offset_;
        ParseOutcome!T result = invokeParser(parser, state);
        if (!result.success)
            return result;
        if (predicate(result.value))
            return result;
        state.fail(ParseErrorKind.expected, state.offset_, expectation);
        return ParseOutcome!T.failure(
            state.offset_ == start ? FailureKind.recoverable : FailureKind.committed,
        );
    }
}

private struct ReplaceNode(A, B)
{
nothrow @nogc:
    Parser!A parser;
    B value;

    ParseOutcome!B parse(ref ParseState state)
    {
        ParseOutcome!A source = invokeParser(parser, state);
        if (!source.success)
            return ParseOutcome!B.failure(source.failureKind);
        return ParseOutcome!B.succeed(value);
    }
}

private struct SkipNode(T)
{
nothrow @nogc:
    Parser!T parser;

    ParseOutcome!Unit parse(ref ParseState state)
    {
        ParseOutcome!T source = invokeParser(parser, state);
        if (!source.success)
            return ParseOutcome!Unit.failure(source.failureKind);
        return ParseOutcome!Unit.succeed(Unit.init);
    }
}

private struct NamedNode(T)
{
nothrow @nogc:
    Parser!T parser;
    String name;

    ParseOutcome!T parse(ref ParseState state)
    {
        const start = state.offset_;
        ParseOutcome!T result = invokeParser(parser, state);
        if (!result.success && state.bestError_.valid && state.bestError_.offset >= start)
            state.replaceExpectationAt(state.bestError_.offset, name, name);
        return result;
    }
}

private struct ContextNode(T)
{
nothrow @nogc:
    Parser!T parser;
    String name;

    ParseOutcome!T parse(ref ParseState state)
    {
        const start = state.offset_;
        ParseOutcome!T result = invokeParser(parser, state);
        if (!result.success)
            state.attachContextAtOrAfter(start, name);
        return result;
    }
}

private struct PeekNode(T)
{
nothrow @nogc:
    Parser!T parser;

    ParseOutcome!T parse(ref ParseState state)
    {
        const startOffset = state.offset_;
        const startCut = state.cutGeneration_;
        ParseOutcome!T result = invokeParser(parser, state);
        state.offset_ = startOffset;
        state.cutGeneration_ = startCut;
        if (!result.success)
            result.failureKind = FailureKind.recoverable;
        return result;
    }
}

package(xtb.parser) struct ArenaList(T) if (__traits(isCopyable, T) && !hasDDestructor!T)
{
nothrow @nogc:
    Arena* arena;
    T* data;
    size_t length;
    size_t capacity;

    static ArenaList create(Arena* arena)
    {
        version (XTB_Checked)
            require(arena !is null, "arena list requires an arena");
        ArenaList result;
        result.arena = arena;
        return result;
    }

    void append(T value) @trusted
    {
        if (length == capacity)
        {
            size_t nextCapacity = capacity == 0 ? 8 : capacity * 2;
            if (nextCapacity < capacity)
                nextCapacity = size_t.max;
            T[] replacement = arena.allocateArray!T(nextCapacity);
            if (length != 0)
                memcpy(replacement.ptr, data, T.sizeof * length);
            data = replacement.ptr;
            capacity = replacement.length;
        }
        data[length++] = value;
    }

    T[] slice() return @trusted
    {
        return data[0 .. length];
    }
}

struct RepetitionParser(T)
{
nothrow @nogc:
private:
    Parser!T parser_;
    bool requireOne_;

package(xtb.parser):
    this(Parser!T parser, bool requireOne) pure @safe
    {
        parser_ = parser;
        requireOne_ = requireOne;
    }

public:
    Parser!Unit skip() @trusted
    {
        RepeatSkipNode!T node;
        node.parser = parser_;
        node.requireOne = requireOne_;
        return parserFromNode!Unit(parser_.arena_, node);
    }

    static if (__traits(isCopyable, T) && !hasDDestructor!T)
    {
        Parser!(T[]) collect() @trusted
        {
            RepeatCollectNode!T node;
            node.parser = parser_;
            node.requireOne = requireOne_;
            return parserFromNode!(T[])(parser_.arena_, node);
        }
    }

    auto fold(U, alias combine)(U initial) @trusted if (__traits(isCopyable, U))
    {
        FoldNode!(T, U, combine) node;
        node.parser = parser_;
        node.requireOne = requireOne_;
        node.initial = initial;
        return parserFromNode!U(parser_.arena_, node);
    }
}

private bool repeatedProgressed(size_t before, size_t after)
{
    return after > before;
}

private struct RepeatSkipNode(T)
{
nothrow @nogc:
    Parser!T parser;
    bool requireOne;

    ParseOutcome!Unit parse(ref ParseState state)
    {
        size_t count;
        while (true)
        {
            const before = state.offset_;
            ParseOutcome!T item = invokeParser(parser, state);
            if (!item.success)
            {
                if (item.failureKind == FailureKind.committed)
                    return ParseOutcome!Unit.failure(FailureKind.committed);
                break;
            }
            if (!repeatedProgressed(before, state.offset_))
            {
                version (XTB_Checked)
                    require(false, "repeated parser succeeded without consuming input");
                break;
            }
            ++count;
        }
        if (requireOne && count == 0)
            return ParseOutcome!Unit.failure(FailureKind.recoverable);
        return ParseOutcome!Unit.succeed(Unit.init);
    }
}

private struct RepeatCollectNode(T) if (__traits(isCopyable, T) && !hasDDestructor!T)
{
nothrow @nogc:
    Parser!T parser;
    bool requireOne;

    ParseOutcome!(T[]) parse(ref ParseState state) @trusted
    {
        version (XTB_Checked)
            require(state.context_ !is null && state.context_.outputArena !is null,
                "collect requires a parse output arena");
        ArenaList!T values = ArenaList!T.create(state.context_.outputArena);
        while (true)
        {
            const before = state.offset_;
            ParseOutcome!T item = invokeParser(parser, state);
            if (!item.success)
            {
                if (item.failureKind == FailureKind.committed)
                    return ParseOutcome!(T[]).failure(FailureKind.committed);
                break;
            }
            if (!repeatedProgressed(before, state.offset_))
            {
                version (XTB_Checked)
                    require(false, "repeated parser succeeded without consuming input");
                break;
            }
            values.append(item.value);
        }
        if (requireOne && values.length == 0)
            return ParseOutcome!(T[]).failure(FailureKind.recoverable);
        return ParseOutcome!(T[]).succeed(values.slice);
    }
}

private struct FoldNode(T, U, alias combine)
{
nothrow @nogc:
    Parser!T parser;
    bool requireOne;
    U initial;

    ParseOutcome!U parse(ref ParseState state)
    {
        U accumulator = initial;
        size_t count;
        while (true)
        {
            const before = state.offset_;
            ParseOutcome!T item = invokeParser(parser, state);
            if (!item.success)
            {
                if (item.failureKind == FailureKind.committed)
                    return ParseOutcome!U.failure(FailureKind.committed);
                break;
            }
            if (!repeatedProgressed(before, state.offset_))
            {
                version (XTB_Checked)
                    require(false, "repeated parser succeeded without consuming input");
                break;
            }
            accumulator = combine(accumulator, item.value);
            ++count;
        }
        if (requireOne && count == 0)
            return ParseOutcome!U.failure(FailureKind.recoverable);
        return ParseOutcome!U.succeed(move(accumulator));
    }
}

struct SeparatedParser(T, S)
{
nothrow @nogc:
private:
    Parser!T parser_;
    Parser!S separator_;
    bool requireOne_;

package(xtb.parser):
    this(Parser!T parser, Parser!S separator, bool requireOne) pure @safe
    {
        parser_ = parser;
        separator_ = separator;
        requireOne_ = requireOne;
    }

public:
    Parser!Unit skip() @trusted
    {
        SepSkipNode!(T, S) node;
        node.parser = parser_;
        node.separator = separator_;
        node.requireOne = requireOne_;
        return parserFromNode!Unit(parser_.arena_, node);
    }

    static if (__traits(isCopyable, T) && !hasDDestructor!T)
    {
        Parser!(T[]) collect() @trusted
        {
            SepCollectNode!(T, S) node;
            node.parser = parser_;
            node.separator = separator_;
            node.requireOne = requireOne_;
            return parserFromNode!(T[])(parser_.arena_, node);
        }
    }
}

private struct SepSkipNode(T, S)
{
nothrow @nogc:
    Parser!T parser;
    Parser!S separator;
    bool requireOne;

    ParseOutcome!Unit parse(ref ParseState state)
    {
        ParseOutcome!T first = invokeParser(parser, state);
        if (!first.success)
        {
            if (first.failureKind == FailureKind.committed)
                return ParseOutcome!Unit.failure(FailureKind.committed);
            return requireOne
                ? ParseOutcome!Unit.failure(FailureKind.recoverable) : ParseOutcome!Unit.succeed(Unit
                        .init);
        }
        while (true)
        {
            ParseOutcome!S sep = invokeParser(separator, state);
            if (!sep.success)
            {
                if (sep.failureKind == FailureKind.committed)
                    return ParseOutcome!Unit.failure(FailureKind.committed);
                break;
            }
            ParseOutcome!T item = invokeParser(parser, state);
            if (!item.success)
                return ParseOutcome!Unit.failure(FailureKind.committed);
        }
        return ParseOutcome!Unit.succeed(Unit.init);
    }
}

private struct SepCollectNode(T, S) if (__traits(isCopyable, T) && !hasDDestructor!T)
{
nothrow @nogc:
    Parser!T parser;
    Parser!S separator;
    bool requireOne;

    ParseOutcome!(T[]) parse(ref ParseState state) @trusted
    {
        version (XTB_Checked)
            require(state.context_ !is null && state.context_.outputArena !is null,
                "collect requires a parse output arena");
        ArenaList!T values = ArenaList!T.create(state.context_.outputArena);
        ParseOutcome!T first = invokeParser(parser, state);
        if (!first.success)
        {
            if (first.failureKind == FailureKind.committed)
                return ParseOutcome!(T[]).failure(FailureKind.committed);
            if (requireOne)
                return ParseOutcome!(T[]).failure(FailureKind.recoverable);
            return ParseOutcome!(T[]).succeed(values.slice);
        }
        values.append(first.value);
        while (true)
        {
            ParseOutcome!S sep = invokeParser(separator, state);
            if (!sep.success)
            {
                if (sep.failureKind == FailureKind.committed)
                    return ParseOutcome!(T[]).failure(FailureKind.committed);
                break;
            }
            ParseOutcome!T item = invokeParser(parser, state);
            if (!item.success)
                return ParseOutcome!(T[]).failure(FailureKind.committed);
            values.append(item.value);
        }
        return ParseOutcome!(T[]).succeed(values.slice);
    }
}

/// Forward-declared recursive parser rule.
struct Rule(T)
{
nothrow @nogc:
private:
    Parser!T parser_;
    RuleNode!T* node_;

public:
    Parser!T parser() return pure @safe
    {
        return parser_;
    }

    bool defined() pure @safe
    {
        return node_ !is null && node_.implementation.valid;
    }

    void define(Parser!T implementation) @trusted
    {
        version (XTB_Checked)
        {
            require(node_ !is null, "invalid parser rule");
            require(!node_.implementation.valid, "parser rule is already defined");
            require(parser_.arena_ is implementation.arena_,
                "parser rule implementation belongs to another grammar");
        }
        node_.implementation = implementation;
    }

    alias parser this;
}

private struct RuleNode(T)
{
nothrow @nogc:
    Parser!T implementation;
    String name;

    ParseOutcome!T parse(ref ParseState state)
    {
        version (XTB_Checked)
            require(implementation.valid, "parser rule is undefined");
        return invokeParser(implementation, state);
    }
}

private String copyIntoArena(Arena* arena, String value) @trusted
{
    if (value.length == 0)
        return String.init;
    char[] storage = arena.allocateArray!char(value.length);
    memcpy(storage.ptr, value.ptr, value.length);
    return cast(String) storage;
}

private struct AnyNode
{
nothrow @nogc:
    ParseOutcome!char parse(ref ParseState state)
    {
        if (state.atEnd)
        {
            state.fail(ParseErrorKind.expected, state.offset_, "any character");
            return ParseOutcome!char.failure();
        }
        return ParseOutcome!char.succeed(state.takeByte());
    }
}

private struct ValueNode
{
nothrow @nogc:
    char expected;
    String expectation;

    ParseOutcome!char parse(ref ParseState state)
    {
        if (state.atEnd || state.peekByte() != expected)
        {
            state.fail(ParseErrorKind.expected, state.offset_, expectation);
            return ParseOutcome!char.failure();
        }
        return ParseOutcome!char.succeed(state.takeByte());
    }
}

private struct LiteralNode
{
nothrow @nogc:
    String expected;

    ParseOutcome!String parse(ref ParseState state) @trusted
    {
        const start = state.offset_;
        size_t matched;
        while (matched < expected.length && start + matched < state.input_.length &&
            state.input_[start + matched] == expected[matched])
            ++matched;
        if (matched != expected.length)
        {
            state.fail(ParseErrorKind.expected, start + matched, expected);
            return ParseOutcome!String.failure();
        }
        state.offset_ = start + expected.length;
        return ParseOutcome!String.succeed(state.input_[start .. state.offset_]);
    }
}

private struct TakeNode
{
nothrow @nogc:
    size_t count;

    ParseOutcome!String parse(ref ParseState state) @trusted
    {
        const start = state.offset_;
        if (count > state.remaining)
        {
            state.fail(ParseErrorKind.expected, state.input_.length, "input bytes");
            return ParseOutcome!String.failure();
        }
        state.offset_ += count;
        return ParseOutcome!String.succeed(state.input_[start .. state.offset_]);
    }
}

private struct PredicateNode(alias predicate)
{
nothrow @nogc:
    String expectation;

    ParseOutcome!char parse(ref ParseState state)
    {
        if (state.atEnd || !predicate(state.peekByte()))
        {
            state.fail(ParseErrorKind.expected, state.offset_, expectation);
            return ParseOutcome!char.failure();
        }
        return ParseOutcome!char.succeed(state.takeByte());
    }
}

private struct TakeWhileNode(alias predicate)
{
nothrow @nogc:
    String expectation;
    bool requireOne;

    ParseOutcome!String parse(ref ParseState state) @trusted
    {
        const start = state.offset_;
        while (!state.atEnd && predicate(state.peekByte()))
            state.takeByte();
        if (requireOne && state.offset_ == start)
        {
            state.fail(ParseErrorKind.expected, start, expectation);
            return ParseOutcome!String.failure();
        }
        return ParseOutcome!String.succeed(state.input_[start .. state.offset_]);
    }
}

private struct CharacterSetNode
{
nothrow @nogc:
    String characters;
    bool inverted;
    String expectation;

    ParseOutcome!char parse(ref ParseState state)
    {
        if (state.atEnd)
        {
            state.fail(ParseErrorKind.expected, state.offset_, expectation);
            return ParseOutcome!char.failure();
        }
        const value = state.peekByte();
        bool found;
        foreach (candidate; characters)
            if (candidate == value)
            {
                found = true;
                break;
            }
        if (found == inverted)
        {
            state.fail(ParseErrorKind.expected, state.offset_, expectation);
            return ParseOutcome!char.failure();
        }
        return ParseOutcome!char.succeed(state.takeByte());
    }
}

private struct EofNode
{
nothrow @nogc:
    ParseOutcome!Unit parse(ref ParseState state)
    {
        if (!state.atEnd)
        {
            state.fail(ParseErrorKind.expected, state.offset_, "end of input");
            return ParseOutcome!Unit.failure();
        }
        return ParseOutcome!Unit.succeed(Unit.init);
    }
}

private struct IdentifierNode
{
nothrow @nogc:
    ParseOutcome!String parse(ref ParseState state) @trusted
    {
        const start = state.offset_;
        if (state.atEnd || !isIdentifierStart(state.peekByte()))
        {
            state.fail(ParseErrorKind.expected, start, "identifier");
            return ParseOutcome!String.failure();
        }
        state.takeByte();
        while (!state.atEnd && isIdentifierContinue(state.peekByte()))
            state.takeByte();
        return ParseOutcome!String.succeed(state.input_[start .. state.offset_]);
    }
}

private struct IdentifierBoundaryNode
{
nothrow @nogc:
    ParseOutcome!Unit parse(ref ParseState state)
    {
        if (!state.atEnd && isIdentifierContinue(state.peekByte()))
        {
            state.fail(ParseErrorKind.expected, state.offset_, "identifier boundary");
            return ParseOutcome!Unit.failure();
        }
        return ParseOutcome!Unit.succeed(Unit.init);
    }
}

private struct IntegerNode(T)
{
nothrow @nogc:
    ParseOutcome!T parse(ref ParseState state) @trusted
    {
        static assert(__traits(isIntegral, T), "integer parser requires an integral type");
        const start = state.offset_;
        size_t cursor = start;
        bool negative;
        static if (T.min < 0)
        {
            if (cursor < state.input_.length && state.input_[cursor] == '-')
            {
                negative = true;
                ++cursor;
            }
        }
        if (cursor >= state.input_.length || state.input_[cursor] < '0' ||
            state.input_[cursor] > '9')
        {
            state.fail(ParseErrorKind.expected, cursor, "integer");
            return ParseOutcome!T.failure();
        }
        ulong magnitude;
        while (cursor < state.input_.length && state.input_[cursor] >= '0' &&
            state.input_[cursor] <= '9')
        {
            const digit = cast(ulong)(state.input_[cursor] - '0');
            if (magnitude > (ulong.max - digit) / 10)
            {
                state.fail(ParseErrorKind.numberOutOfRange, cursor, "integer in range");
                return ParseOutcome!T.failure();
            }
            magnitude = magnitude * 10 + digit;
            ++cursor;
        }
        static if (T.min == 0)
        {
            if (magnitude > cast(ulong) T.max)
            {
                state.fail(ParseErrorKind.numberOutOfRange, cursor, "integer in range");
                return ParseOutcome!T.failure();
            }
            T value = cast(T) magnitude;
        }
        else
        {
            enum ulong negativeLimit = cast(ulong)(0UL - cast(ulong) T.min);
            if ((!negative && magnitude > cast(ulong) T.max) ||
                (negative && magnitude > negativeLimit))
            {
                state.fail(ParseErrorKind.numberOutOfRange, cursor, "integer in range");
                return ParseOutcome!T.failure();
            }
            T value;
            if (negative)
                value = magnitude == negativeLimit ? T.min : cast(T)-cast(long) magnitude;
            else
                value = cast(T) magnitude;
        }
        state.offset_ = cursor;
        return ParseOutcome!T.succeed(value);
    }
}

private struct FloatingNode(T)
{
nothrow @nogc:
    ParseOutcome!T parse(ref ParseState state) @trusted
    {
        static assert(is(T == float) || is(T == double) || is(T == real),
            "floating parser requires float, double, or real");
        const start = state.offset_;
        size_t cursor = start;
        if (cursor < state.input_.length &&
            (state.input_[cursor] == '+' || state.input_[cursor] == '-'))
            ++cursor;
        const integerStart = cursor;
        while (cursor < state.input_.length && isAsciiDigitByte(state.input_[cursor]))
            ++cursor;
        if (cursor == integerStart)
        {
            state.fail(ParseErrorKind.expected, cursor, "number");
            return ParseOutcome!T.failure();
        }
        if (cursor < state.input_.length && state.input_[cursor] == '.')
        {
            ++cursor;
            const fractionStart = cursor;
            while (cursor < state.input_.length && isAsciiDigitByte(state.input_[cursor]))
                ++cursor;
            if (cursor == fractionStart)
            {
                state.fail(ParseErrorKind.invalidSyntax, cursor, "digit after decimal point");
                return ParseOutcome!T.failure();
            }
        }
        if (cursor < state.input_.length &&
            (state.input_[cursor] == 'e' || state.input_[cursor] == 'E'))
        {
            ++cursor;
            if (cursor < state.input_.length &&
                (state.input_[cursor] == '+' || state.input_[cursor] == '-'))
                ++cursor;
            const exponentStart = cursor;
            while (cursor < state.input_.length && isAsciiDigitByte(state.input_[cursor]))
                ++cursor;
            if (cursor == exponentStart)
            {
                state.fail(ParseErrorKind.invalidSyntax, cursor, "exponent digits");
                return ParseOutcome!T.failure();
            }
        }
        const length = cursor - start;
        if (length >= 128)
        {
            state.fail(ParseErrorKind.numberOutOfRange, cursor, "number in range");
            return ParseOutcome!T.failure();
        }
        char[128] text;
        foreach (index; 0 .. length)
            text[index] = state.input_[start + index];
        text[length] = '\0';
        char* end;
        errno = 0;
        const parsed = strtod(text.ptr, &end);
        if (end != text.ptr + length)
        {
            state.fail(ParseErrorKind.invalidSyntax, start, "number");
            return ParseOutcome!T.failure();
        }
        if (errno == ERANGE || !isfinite(parsed) ||
            (T.sizeof <= float.sizeof && !isfinite(cast(float) parsed)))
        {
            state.fail(ParseErrorKind.numberOutOfRange, cursor, "number in range");
            return ParseOutcome!T.failure();
        }
        state.offset_ = cursor;
        return ParseOutcome!T.succeed(cast(T) parsed);
    }
}

private struct ChoiceNode(T)
{
nothrow @nogc:
    Parser!T[] alternatives;

    ParseOutcome!T parse(ref ParseState state)
    {
        foreach (parser; alternatives)
        {
            ParseOutcome!T result = invokeParser(parser, state);
            if (result.success || result.failureKind == FailureKind.committed)
                return result;
        }
        return ParseOutcome!T.failure(FailureKind.recoverable);
    }
}

private bool isAsciiWhitespaceByte(char value) pure @safe
{
    return value == ' ' || value == '\t' || value == '\n' || value == '\r';
}

private bool isAsciiDigitByte(char value) pure @safe
{
    return value >= '0' && value <= '9';
}

private bool isAsciiHexDigitByte(char value) pure @safe
{
    return (value >= '0' && value <= '9') ||
        (value >= 'a' && value <= 'f') ||
        (value >= 'A' && value <= 'F');
}

private bool isIdentifierStart(char value) pure @safe
{
    return (value >= 'a' && value <= 'z') ||
        (value >= 'A' && value <= 'Z') || value == '_';
}

private bool isIdentifierContinue(char value) pure @safe
{
    return isIdentifierStart(value) || isAsciiDigitByte(value);
}

/// Owns the arena containing an immutable parser graph.
struct Grammar
{
nothrow @nogc:
private:
    Arena arena_;

public:
    @disable this(this);
    @disable ref Grammar opAssign(Grammar source) return;

    static Grammar create(
        Allocator* allocator,
        size_t chunkSize = 64 * 1024,
    )
    {
        Grammar result;
        Arena arena = Arena.create(allocator, chunkSize);
        moveEmplace(arena, result.arena_);
        return move(result);
    }

    void deinit()
    {
        arena_.deinit();
    }

    Allocator* allocator() return
    {
        return arena_.allocator;
    }

    Arena* arena() return
    {
        return &arena_;
    }

    Parser!char any() @trusted
    {
        return parserFromNode!char(&arena_, AnyNode.init);
    }

    Parser!char value(char expected) @trusted
    {
        ValueNode node;
        node.expected = expected;
        char[1] text = [expected];
        node.expectation = copyIntoArena(&arena_, text[]);
        return parserFromNode!char(&arena_, node);
    }

    Parser!String literal(String expected) @trusted
    {
        LiteralNode node;
        node.expected = copyIntoArena(&arena_, expected);
        return parserFromNode!String(&arena_, node);
    }

    Parser!char satisfy(alias predicate)(String name = "matching character") @trusted
    {
        PredicateNode!predicate node;
        node.expectation = copyIntoArena(&arena_, name);
        return parserFromNode!char(&arena_, node);
    }

    Parser!char oneOf(String characters) @trusted
    {
        CharacterSetNode node;
        node.characters = copyIntoArena(&arena_, characters);
        node.expectation = copyIntoArena(&arena_, "one of the expected characters");
        return parserFromNode!char(&arena_, node);
    }

    Parser!char noneOf(String characters) @trusted
    {
        CharacterSetNode node;
        node.characters = copyIntoArena(&arena_, characters);
        node.inverted = true;
        node.expectation = copyIntoArena(&arena_, "character outside excluded set");
        return parserFromNode!char(&arena_, node);
    }

    Parser!String take(size_t count) @trusted
    {
        TakeNode node;
        node.count = count;
        return parserFromNode!String(&arena_, node);
    }

    Parser!String takeWhile(alias predicate)(String name = "matching text") @trusted
    {
        TakeWhileNode!predicate node;
        node.expectation = copyIntoArena(&arena_, name);
        return parserFromNode!String(&arena_, node);
    }

    Parser!String takeWhile1(alias predicate)(String name = "matching text") @trusted
    {
        TakeWhileNode!predicate node;
        node.expectation = copyIntoArena(&arena_, name);
        node.requireOne = true;
        return parserFromNode!String(&arena_, node);
    }

    Parser!Unit eof() @trusted
    {
        return parserFromNode!Unit(&arena_, EofNode.init);
    }

    Parser!String identifier() @trusted
    {
        return parserFromNode!String(&arena_, IdentifierNode.init);
    }

    Parser!T integer(T)() @trusted
    {
        static assert(__traits(isIntegral, T), "integer parser requires an integral type");
        return parserFromNode!T(&arena_, IntegerNode!T.init);
    }

    Parser!T floating(T)() @trusted
    {
        static assert(is(T == float) || is(T == double) || is(T == real),
            "floating parser requires float, double, or real");
        return parserFromNode!T(&arena_, FloatingNode!T.init);
    }

    Parser!String asciiWhitespace0() @trusted
    {
        return takeWhile!isAsciiWhitespaceByte("ASCII whitespace");
    }

    Parser!String asciiWhitespace1() @trusted
    {
        return takeWhile1!isAsciiWhitespaceByte("ASCII whitespace");
    }

    Parser!char digit() @trusted
    {
        return satisfy!isAsciiDigitByte("digit");
    }

    Parser!char hexDigit() @trusted
    {
        return satisfy!isAsciiHexDigitByte("hex digit");
    }

    Parser!T choice(T, Rest...)(Parser!T first, Rest rest) @trusted if (allParserTypes!(T, Rest))
    {
        enum count = 1 + Rest.length;
        Parser!T[] alternatives = arena_.allocateArray!(Parser!T)(count);
        alternatives[0] = first;
        static foreach (index; 0 .. Rest.length)
            alternatives[index + 1] = rest[index];
        version (XTB_Checked)
            foreach (alternative; alternatives)
                require(alternative.arena_ is &arena_,
                    "choice parser belongs to another grammar");
        ChoiceNode!T node;
        node.alternatives = alternatives;
        return parserFromNode!T(&arena_, node);
    }

    Rule!T rule(T)(String name = String.init) @trusted
    {
        RuleNode!T node;
        node.name = copyIntoArena(&arena_, name);
        Parser!T parser = parserFromNode!T(&arena_, node);
        Rule!T result;
        result.parser_ = parser;
        result.node_ = cast(RuleNode!T*) parser.node_;
        return result;
    }

    Tokenizer tokenizer(Parser!Unit trivia) @trusted
    {
        version (XTB_Checked)
            require(trivia.arena_ is &arena_, "token trivia belongs to another grammar");
        Tokenizer result;
        result.grammar_ = &this;
        result.trivia_ = trivia;
        return result;
    }

    auto expressionTable(T, BinaryOp, UnaryOp)() @trusted
    {
        import xtb.parser.expression : ExpressionTable;

        return ExpressionTable!(T, BinaryOp, UnaryOp).create(&this);
    }

package(xtb.parser):
    Parser!Unit identifierBoundary() @trusted
    {
        return parserFromNode!Unit(&arena_, IdentifierBoundaryNode.init);
    }

    Parser!T custom(T, Node)(Node node) @trusted
    {
        return parserFromNode!T(&arena_, move(node));
    }
}

private template allParserTypes(T, Rest...)
{
    static if (Rest.length == 0)
        enum allParserTypes = true;
    else
    {
        enum firstMatches = is(Rest[0] == Parser!T);
        static if (Rest.length == 1)
            enum allParserTypes = firstMatches;
        else
            enum allParserTypes = firstMatches && allParserTypes!(T, Rest[1 .. $]);
    }
}

/// Adds trailing trivia consumption to common textual primitives.
static assert(!hasElaborateDestructor!Grammar);
static assert(needsDeinit!Grammar);
static assert(!__traits(isCopyable, Grammar));

struct Tokenizer
{
nothrow @nogc:
private:
    Grammar* grammar_;
    Parser!Unit trivia_;

public:
    Parser!String literal(String text) @trusted
    {
        return grammar_.literal(text).before(trivia_);
    }

    Parser!String keyword(String text) @trusted
    {
        return grammar_.literal(text)
            .before(grammar_.identifierBoundary())
            .before(trivia_);
    }

    Parser!String identifier() @trusted
    {
        return grammar_.identifier().before(trivia_);
    }

    Parser!T integer(T)() @trusted
    {
        return grammar_.integer!T().before(trivia_);
    }

    Parser!T floating(T)() @trusted
    {
        return grammar_.floating!T().before(trivia_);
    }
}

version (unittest)
{
    private int testAddDigits(int left, char digit)
    {
        return left + digit - '0';
    }

    private int testParseInt(String value)
    {
        int result;
        foreach (c; value)
            result = result * 10 + c - '0';
        return result;
    }

    private bool testPositive(int value)
    {
        return value > 0;
    }
}

unittest
{
    import xtb.core.allocators.arena : Arena;
    import xtb.core.allocators.malloc : mallocAllocator;

    Grammar grammar = Grammar.create(mallocAllocator(), 256);
    scope (exit)
        grammar.deinit();

    auto abc = grammar.literal("abc");
    auto exact = abc.parse("abc");
    assert(exact.ok);
    assert(exact.value == "abc");
    assert(exact.offset == 3);

    auto mismatch = abc.parse("abx");
    assert(mismatch.failed);
    assert(mismatch.failureKind == FailureKind.recoverable);
    assert(mismatch.error.offset == 2);
    assert(mismatch.error.expected.length == 1);
    assert(mismatch.error.expected[0] == "abc");

    auto pair = grammar.literal("a").then(grammar.literal("b"));
    auto pairResult = pair.parse("ab");
    assert(pairResult.ok);
    assert(pairResult.value.first == "a");
    assert(pairResult.value.second == "b");

    auto before = grammar.literal("name").before(grammar.value(':'));
    auto beforeResult = before.parse("name:");
    assert(beforeResult.ok && beforeResult.value == "name");

    auto after = grammar.value('=').after(grammar.integer!int());
    auto afterResult = after.parse("=42");
    assert(afterResult.ok && afterResult.value == 42);

    auto between = grammar.identifier().between(grammar.value('('), grammar.value(')'));
    auto betweenResult = between.parse("(hello)");
    assert(betweenResult.ok && betweenResult.value == "hello");

    auto choice = grammar.choice(
        grammar.literal("cat"),
        grammar.literal("car"),
        grammar.literal("dog"),
    );
    auto choiceResult = choice.parse("car");
    assert(choiceResult.ok && choiceResult.value == "car");
    auto choiceFailure = choice.parse("cab");
    assert(choiceFailure.failed);
    assert(choiceFailure.error.offset == 2);
    assert(choiceFailure.error.expected.length >= 2);

    auto committed = grammar.choice(
        grammar.identifier().before(grammar.value('=')),
        grammar.identifier(),
    );
    auto committedResult = committed.parse("hello");
    assert(committedResult.failed);
    assert(committedResult.failureKind == FailureKind.committed);

    auto backtracking = grammar.choice(
        grammar.identifier().before(grammar.value('=')).attempt(),
        grammar.identifier(),
    );
    auto backtrackingResult = backtracking.parse("hello");
    assert(backtrackingResult.ok && backtrackingResult.value == "hello");

    auto cutBranch = grammar.choice(
        grammar.identifier()
            .then(grammar.value('(').cut())
            .before(grammar.value(')'))
            .attempt()
            .replace(1),
        grammar.identifier().replace(2),
    );
    auto noCall = cutBranch.parse("foo");
    assert(noCall.ok && noCall.value == 2);
    auto malformedCall = cutBranch.parse("foo(");
    assert(malformedCall.failed);
    assert(malformedCall.failureKind == FailureKind.committed);

    auto optional = grammar.value('-').optional().then(grammar.integer!int());
    auto optionalPresent = optional.parse("-4");
    assert(optionalPresent.ok);
    assert(optionalPresent.value.first.isSome);
    auto optionalAbsent = optional.parse("4");
    assert(optionalAbsent.ok);
    assert(optionalAbsent.value.first.isNone);

    auto digits = grammar.digit().repeat1().skip();
    assert(digits.parse("12345").ok);
    assert(digits.parse("").failed);

    Arena output = Arena.create(mallocAllocator(), 128);
    ParseContext context = ParseContext.create(&output);
    auto collected = grammar.integer!int().sepBy(grammar.value(',')).collect();
    auto collectedResult = collected.parse("1,2,3,4", &context);
    assert(collectedResult.ok);
    assert(collectedResult.value == [1, 2, 3, 4]);

    auto trailingSeparator = collected.parse("1,", &context);
    assert(trailingSeparator.failed);
    assert(trailingSeparator.failureKind == FailureKind.committed);

    auto folded = grammar.digit().repeat1().fold!(int, testAddDigits)(0);
    auto foldedResult = folded.parse("123");
    assert(foldedResult.ok && foldedResult.value == 6);

    auto mapped = grammar.takeWhile1!isAsciiDigitByte("digits").map!testParseInt();
    assert(mapped.parse("2048").value == 2048);

    struct Assignment
    {
    nothrow @nogc:
        String name;
        int value;
    }

    auto assignment = grammar.identifier()
        .then(grammar.value('=').after(grammar.integer!int()))
        .mapTuple!Assignment();
    auto assignmentResult = assignment.parse("answer=42");
    assert(assignmentResult.ok);
    assert(assignmentResult.value.name == "answer");
    assert(assignmentResult.value.value == 42);

    auto named = grammar.integer!int().named("number").context("test expression");
    auto namedFailure = named.parse("x");
    assert(namedFailure.failed);
    assert(namedFailure.error.expected.length == 1);
    assert(namedFailure.error.expected[0] == "number");
    assert(namedFailure.error.context == "test expression");

    auto positive = grammar.integer!int().where!testPositive("positive integer");
    assert(positive.parse("5").ok);
    assert(positive.parse("0").failed);

    auto peeked = grammar.literal("abc").peek().then(grammar.literal("abc"));
    auto peekedResult = peeked.parse("abc");
    assert(peekedResult.ok && peekedResult.offset == 3);

    auto recursive = grammar.rule!int("recursive integer");
    auto atom = grammar.integer!int();
    auto parenthesized = recursive.parser.between(
        grammar.value('('),
        grammar.value(')'),
    );
    recursive.define(grammar.choice(parenthesized, atom));
    assert(recursive.parser.parse("(((7)))").value == 7);

    auto trivia = grammar.asciiWhitespace0().skip();
    Tokenizer token = grammar.tokenizer(trivia);
    auto tokenized = token.keyword("let")
        .after(token.identifier())
        .before(token.literal(";"))
        .before(grammar.eof());
    auto tokenizedResult = tokenized.parse("let   value ;");
    assert(tokenizedResult.ok && tokenizedResult.value == "value");
    assert(token.keyword("let").parse("letter").failed);

    auto intMin = grammar.integer!int().parse("-2147483648");
    assert(intMin.ok && intMin.value == int.min);
    assert(grammar.integer!ubyte().parse("255").value == 255);
    assert(grammar.integer!ubyte().parse("256").error.kind == ParseErrorKind.numberOutOfRange);

    output.deinit();
}
