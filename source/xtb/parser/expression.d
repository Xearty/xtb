module xtb.parser.expression;

nothrow @nogc:

import xtb.core.lifetime : move;
import xtb.core.allocators.arena : Arena;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.parser.parser : FailureKind, Grammar, ParseContext, ParseErrorKind,
    ParseOutcome, ParseState, Parser, Unit, invokeParser, parserFromNode;

/// Associativity for binary operators within one precedence level.
enum OperatorAssociativity : ubyte
{
    none,
    left,
    right,
    nonassoc,
}

private struct BinaryOperatorSpec(BinaryOp)
{
    Parser!Unit parser;
    BinaryOp operation;
    BinaryOperatorSpec* next;
}

private struct UnaryOperatorSpec(UnaryOp)
{
    Parser!Unit parser;
    UnaryOp operation;
    UnaryOperatorSpec* next;
}

private struct ExpressionLevelNode(BinaryOp, UnaryOp)
{
    ExpressionLevelNode* tighter;
    OperatorAssociativity associativity;

    BinaryOperatorSpec!BinaryOp* binaryFirst;
    BinaryOperatorSpec!BinaryOp* binaryLast;

    UnaryOperatorSpec!UnaryOp* prefixFirst;
    UnaryOperatorSpec!UnaryOp* prefixLast;

    UnaryOperatorSpec!UnaryOp* postfixFirst;
    UnaryOperatorSpec!UnaryOp* postfixLast;
}

/// Builder for one precedence level. Levels created earlier bind more tightly.
struct ExpressionLevel(T, BinaryOp, UnaryOp)
{
nothrow @nogc:
private:
    Grammar* grammar_;
    ExpressionLevelNode!(BinaryOp, UnaryOp)* node_;

package(xtb.parser):
    static ExpressionLevel create(
        Grammar* grammar,
        ExpressionLevelNode!(BinaryOp, UnaryOp)* node,
    ) pure @safe
    {
        ExpressionLevel result;
        result.grammar_ = grammar;
        result.node_ = node;
        return result;
    }

public:
    ref ExpressionLevel left(S)(Parser!S parser, BinaryOp operation) return @trusted
    {
        addBinary(parser, operation, OperatorAssociativity.left);
        return this;
    }

    ref ExpressionLevel right(S)(Parser!S parser, BinaryOp operation) return @trusted
    {
        addBinary(parser, operation, OperatorAssociativity.right);
        return this;
    }

    ref ExpressionLevel nonassoc(S)(Parser!S parser, BinaryOp operation) return @trusted
    {
        addBinary(parser, operation, OperatorAssociativity.nonassoc);
        return this;
    }

    ref ExpressionLevel prefix(S)(Parser!S parser, UnaryOp operation) return @trusted
    {
        version (XTB_Checked)
        {
            require(grammar_ !is null && node_ !is null, "invalid expression level");
            require(parser.owningArena is grammar_.arena,
                "expression operator belongs to another grammar");
        }
        auto spec = grammar_.arena.allocateInit!(UnaryOperatorSpec!UnaryOp)();
        spec.parser = parser.skip();
        spec.operation = operation;
        if (node_.prefixLast is null)
            node_.prefixFirst = spec;
        else
            node_.prefixLast.next = spec;
        node_.prefixLast = spec;
        return this;
    }

    ref ExpressionLevel postfix(S)(Parser!S parser, UnaryOp operation) return @trusted
    {
        version (XTB_Checked)
        {
            require(grammar_ !is null && node_ !is null, "invalid expression level");
            require(parser.owningArena is grammar_.arena,
                "expression operator belongs to another grammar");
        }
        auto spec = grammar_.arena.allocateInit!(UnaryOperatorSpec!UnaryOp)();
        spec.parser = parser.skip();
        spec.operation = operation;
        if (node_.postfixLast is null)
            node_.postfixFirst = spec;
        else
            node_.postfixLast.next = spec;
        node_.postfixLast = spec;
        return this;
    }

private:
    void addBinary(S)(
        Parser!S parser,
        BinaryOp operation,
        OperatorAssociativity associativity,
    ) @trusted
    {
        version (XTB_Checked)
        {
            require(grammar_ !is null && node_ !is null, "invalid expression level");
            require(parser.owningArena is grammar_.arena,
                "expression operator belongs to another grammar");
            require(node_.associativity == OperatorAssociativity.none ||
                    node_.associativity == associativity,
                "binary operators in one precedence level must share associativity");
        }
        if (node_.associativity == OperatorAssociativity.none)
            node_.associativity = associativity;
        auto spec = grammar_.arena.allocateInit!(BinaryOperatorSpec!BinaryOp)();
        spec.parser = parser.skip();
        spec.operation = operation;
        if (node_.binaryLast is null)
            node_.binaryFirst = spec;
        else
            node_.binaryLast.next = spec;
        node_.binaryLast = spec;
    }
}

/// Arena-backed operator-precedence table. Earlier levels bind more tightly.
struct ExpressionTable(T, BinaryOp, UnaryOp)
{
nothrow @nogc:
private:
    Grammar* grammar_;
    ExpressionLevelNode!(BinaryOp, UnaryOp)* loosest_;

public:
    static ExpressionTable create(Grammar* grammar) pure @safe
    {
        ExpressionTable result;
        result.grammar_ = grammar;
        return result;
    }

    ExpressionLevel!(T, BinaryOp, UnaryOp) level() @trusted
    {
        version (XTB_Checked)
            require(grammar_ !is null, "expression table requires a grammar");
        auto node = grammar_.arena.allocateInit!(ExpressionLevelNode!(BinaryOp, UnaryOp))();
        node.tighter = loosest_;
        loosest_ = node;
        return ExpressionLevel!(T, BinaryOp, UnaryOp).create(grammar_, node);
    }

    Parser!T build(alias binaryBuilder, alias unaryBuilder)(Parser!T primary) @trusted
    {
        version (XTB_Checked)
        {
            require(grammar_ !is null, "expression table requires a grammar");
            require(primary.owningArena is grammar_.arena,
                "expression primary belongs to another grammar");
        }
        ExpressionNode!(T, BinaryOp, UnaryOp, binaryBuilder, unaryBuilder) node;
        node.primary = primary;
        node.loosest = loosest_;
        return parserFromNode!T(grammar_.arena, node);
    }
}

private struct OperatorMatch(Op)
{
    bool found;
    FailureKind failureKind;
    Op operation;
}

private OperatorMatch!Op matchOperator(Op, Spec)(
    Spec* first,
    ref ParseState state,
)
{
    for (Spec* current = first; current !is null; current = current.next)
    {
        auto result = invokeParser(current.parser, state);
        if (result.success)
        {
            OperatorMatch!Op matched;
            matched.found = true;
            matched.operation = current.operation;
            return matched;
        }
        if (result.failureKind == FailureKind.committed)
        {
            OperatorMatch!Op failed;
            failed.failureKind = FailureKind.committed;
            return failed;
        }
    }
    return OperatorMatch!Op.init;
}

private T applyBinary(T, BinaryOp, alias builder)(
    ref ParseState state,
    T left,
    BinaryOp operation,
    T right,
)
{
    static if (__traits(compiles,
            builder(*cast(ParseContext*) null, left, operation, right)))
    {
        version (XTB_Checked)
            require(state.context !is null,
                "context-aware binary expression builder requires ParseContext");
        return builder(*state.context, move(left), operation, move(right));
    }
    else static if (__traits(compiles, builder(left, operation, right)))
        return builder(move(left), operation, move(right));
    else
        static assert(false,
            "binary expression builder must accept (T, BinaryOp, T) or " ~
                "(ref ParseContext, T, BinaryOp, T)");
}

private T applyUnary(T, UnaryOp, alias builder)(
    ref ParseState state,
    UnaryOp operation,
    T value,
)
{
    static if (__traits(compiles,
            builder(*cast(ParseContext*) null, operation, value)))
    {
        version (XTB_Checked)
            require(state.context !is null,
                "context-aware unary expression builder requires ParseContext");
        return builder(*state.context, operation, move(value));
    }
    else static if (__traits(compiles, builder(operation, value)))
        return builder(operation, move(value));
    else
        static assert(false,
            "unary expression builder must accept (UnaryOp, T) or " ~
                "(ref ParseContext, UnaryOp, T)");
}

private struct ExpressionNode(
    T,
    BinaryOp,
    UnaryOp,
    alias binaryBuilder,
    alias unaryBuilder,
)
{
nothrow @nogc:
    Parser!T primary;
    ExpressionLevelNode!(BinaryOp, UnaryOp)* loosest;

    ParseOutcome!T parse(ref ParseState state)
    {
        return parseLevel(loosest, state);
    }

private:
    ParseOutcome!T parseLevel(
        ExpressionLevelNode!(BinaryOp, UnaryOp)* level,
        ref ParseState state,
    )
    {
        if (level is null)
            return invokeParser(primary, state);

        ParseOutcome!T left = parseUnary(level, state);
        if (!left.success)
            return left;
        if (level.binaryFirst is null)
            return left;

        final switch (level.associativity)
        {
            case OperatorAssociativity.left:
                while (true)
                {
                    OperatorMatch!BinaryOp matched =
                        matchOperator!(BinaryOp, BinaryOperatorSpec!BinaryOp)(
                            level.binaryFirst, state,
                        );
                    if (!matched.found)
                    {
                        if (matched.failureKind == FailureKind.committed)
                            return ParseOutcome!T.failure(FailureKind.committed);
                        return left;
                    }
                    ParseOutcome!T right = parseUnary(level, state);
                    if (!right.success)
                        return ParseOutcome!T.failure(FailureKind.committed);
                    left.value = applyBinary!(T, BinaryOp, binaryBuilder)(
                        state,
                        move(left.value),
                        matched.operation,
                        move(right.value),
                    );
                }

            case OperatorAssociativity.right:
            {
                OperatorMatch!BinaryOp matched =
                    matchOperator!(BinaryOp, BinaryOperatorSpec!BinaryOp)(
                        level.binaryFirst, state,
                    );
                if (!matched.found)
                {
                    if (matched.failureKind == FailureKind.committed)
                        return ParseOutcome!T.failure(FailureKind.committed);
                    return left;
                }
                ParseOutcome!T right = parseLevel(level, state);
                if (!right.success)
                    return ParseOutcome!T.failure(FailureKind.committed);
                left.value = applyBinary!(T, BinaryOp, binaryBuilder)(
                    state,
                    move(left.value),
                    matched.operation,
                    move(right.value),
                );
                return left;
            }

            case OperatorAssociativity.nonassoc:
            {
                OperatorMatch!BinaryOp matched =
                    matchOperator!(BinaryOp, BinaryOperatorSpec!BinaryOp)(
                        level.binaryFirst, state,
                    );
                if (!matched.found)
                {
                    if (matched.failureKind == FailureKind.committed)
                        return ParseOutcome!T.failure(FailureKind.committed);
                    return left;
                }
                ParseOutcome!T right = parseUnary(level, state);
                if (!right.success)
                    return ParseOutcome!T.failure(FailureKind.committed);
                left.value = applyBinary!(T, BinaryOp, binaryBuilder)(
                    state,
                    move(left.value),
                    matched.operation,
                    move(right.value),
                );
                const secondOffset = state.offset;
                OperatorMatch!BinaryOp second =
                    matchOperator!(BinaryOp, BinaryOperatorSpec!BinaryOp)(
                        level.binaryFirst, state,
                    );
                if (second.found)
                {
                    state.fail(
                        ParseErrorKind.invalidSyntax,
                        secondOffset,
                        "non-associative operator cannot be chained",
                    );
                    return ParseOutcome!T.failure(FailureKind.committed);
                }
                if (second.failureKind == FailureKind.committed)
                    return ParseOutcome!T.failure(FailureKind.committed);
                return left;
            }

            case OperatorAssociativity.none:
                return left;
        }
    }

    ParseOutcome!T parseUnary(
        ExpressionLevelNode!(BinaryOp, UnaryOp)* level,
        ref ParseState state,
    )
    {
        OperatorMatch!UnaryOp prefix =
            matchOperator!(UnaryOp, UnaryOperatorSpec!UnaryOp)(
                level.prefixFirst, state,
            );
        if (!prefix.found && prefix.failureKind == FailureKind.committed)
            return ParseOutcome!T.failure(FailureKind.committed);

        ParseOutcome!T value;
        if (prefix.found)
        {
            value = parseUnary(level, state);
            if (!value.success)
                return ParseOutcome!T.failure(FailureKind.committed);
            value.value = applyUnary!(T, UnaryOp, unaryBuilder)(
                state,
                prefix.operation,
                move(value.value),
            );
        }
        else
        {
            value = parseLevel(level.tighter, state);
            if (!value.success)
                return value;
        }

        while (true)
        {
            OperatorMatch!UnaryOp postfix =
                matchOperator!(UnaryOp, UnaryOperatorSpec!UnaryOp)(
                    level.postfixFirst, state,
                );
            if (!postfix.found)
            {
                if (postfix.failureKind == FailureKind.committed)
                    return ParseOutcome!T.failure(FailureKind.committed);
                return value;
            }
            value.value = applyUnary!(T, UnaryOp, unaryBuilder)(
                state,
                postfix.operation,
                move(value.value),
            );
        }
    }
}
