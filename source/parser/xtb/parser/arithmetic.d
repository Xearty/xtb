module xtb.parser.arithmetic;

nothrow @nogc:

import xtb.lifetime : move;
import core.stdc.errno : ERANGE, errno;
import core.stdc.math : isfinite;
import core.stdc.stdlib : strtod;
import xtb.allocators.arena : Arena;

version (XTB_Checked) import xtb.panic : require;
import xtb.types : String;
import xtb.parser.expression : ExpressionTable;
import xtb.parser.parser : FailureKind, Grammar, ParseContext, ParseErrorKind,
    ParseOutcome, ParseState, Parser, Rule, Tokenizer, Unit;

/// Node category for the example algebraic arithmetic AST.
enum ArithmeticExpressionKind : ubyte
{
    number,
    identifier,
    unary,
    binary,
}

/// Prefix operators supported by the arithmetic grammar.
enum ArithmeticUnaryOperator : ubyte
{
    positive,
    negative,
}

/// Binary operators supported by the arithmetic grammar.
enum ArithmeticBinaryOperator : ubyte
{
    multiply,
    divide,
    add,
    subtract,
}

struct ArithmeticUnary
{
    ArithmeticUnaryOperator operation;
    ArithmeticExpression* operand;
}

struct ArithmeticBinary
{
    ArithmeticBinaryOperator operation;
    ArithmeticExpression* left;
    ArithmeticExpression* right;
}

/// Arena-owned tagged union. Identifier text borrows the parsed input.
struct ArithmeticExpression
{
    ArithmeticExpressionKind kind;

    union
    {
        double number;
        String identifier;
        ArithmeticUnary unary;
        ArithmeticBinary binary;
    }
}

private ArithmeticExpression* allocateExpression(ref ParseContext context) @trusted
{
    version (XTB_Checked)
        require(context.outputArena !is null,
            "arithmetic AST parsing requires an output arena");
    return context.outputArena.create!ArithmeticExpression();
}

private ArithmeticExpression* makeNumber(
    ref ParseContext context,
    double value,
) @trusted
{
    ArithmeticExpression* result = allocateExpression(context);
    result.kind = ArithmeticExpressionKind.number;
    result.number = value;
    return result;
}

private ArithmeticExpression* makeIdentifier(
    ref ParseContext context,
    String value,
) @trusted
{
    ArithmeticExpression* result = allocateExpression(context);
    result.kind = ArithmeticExpressionKind.identifier;
    result.identifier = value;
    return result;
}

private ArithmeticExpression* makeUnary(
    ref ParseContext context,
    ArithmeticUnaryOperator operation,
    ArithmeticExpression* operand,
) @trusted
{
    ArithmeticExpression* result = allocateExpression(context);
    result.kind = ArithmeticExpressionKind.unary;
    result.unary = ArithmeticUnary(operation, operand);
    return result;
}

private ArithmeticExpression* makeBinary(
    ref ParseContext context,
    ArithmeticExpression* left,
    ArithmeticBinaryOperator operation,
    ArithmeticExpression* right,
) @trusted
{
    ArithmeticExpression* result = allocateExpression(context);
    result.kind = ArithmeticExpressionKind.binary;
    result.binary = ArithmeticBinary(operation, left, right);
    return result;
}

private struct ArithmeticNumberNode
{
nothrow @nogc:
    ParseOutcome!double parse(ref ParseState state) @trusted
    {
        const start = state.offset;
        size_t cursor = start;
        const input = state.input;
        if (cursor >= input.length)
        {
            state.fail(ParseErrorKind.expected, cursor, "number");
            return ParseOutcome!double.failure();
        }
        if (input[cursor] == '0')
            ++cursor;
        else
        {
            if (input[cursor] < '1' || input[cursor] > '9')
            {
                state.fail(ParseErrorKind.expected, cursor, "number");
                return ParseOutcome!double.failure();
            }
            do
                ++cursor;
            while (cursor < input.length && input[cursor] >= '0' && input[cursor] <= '9');
        }
        if (cursor < input.length && input[cursor] == '.')
        {
            ++cursor;
            const fractionStart = cursor;
            while (cursor < input.length && input[cursor] >= '0' && input[cursor] <= '9')
                ++cursor;
            if (cursor == fractionStart)
            {
                state.fail(ParseErrorKind.invalidSyntax, cursor, "fraction digit");
                return ParseOutcome!double.failure();
            }
        }
        if (cursor < input.length && (input[cursor] == 'e' || input[cursor] == 'E'))
        {
            ++cursor;
            if (cursor < input.length && (input[cursor] == '+' || input[cursor] == '-'))
                ++cursor;
            const exponentStart = cursor;
            while (cursor < input.length && input[cursor] >= '0' && input[cursor] <= '9')
                ++cursor;
            if (cursor == exponentStart)
            {
                state.fail(ParseErrorKind.invalidSyntax, cursor, "exponent digit");
                return ParseOutcome!double.failure();
            }
        }
        const length = cursor - start;
        if (length >= 128)
        {
            state.fail(ParseErrorKind.numberOutOfRange, cursor, "number in range");
            return ParseOutcome!double.failure();
        }
        char[128] text;
        foreach (index; 0 .. length)
            text[index] = input[start + index];
        text[length] = '\0';
        char* end;
        errno = 0;
        const value = strtod(text.ptr, &end);
        if (end != text.ptr + length)
        {
            state.fail(ParseErrorKind.invalidSyntax, start, "number");
            return ParseOutcome!double.failure();
        }
        if (errno == ERANGE || !isfinite(value))
        {
            state.fail(ParseErrorKind.numberOutOfRange, cursor, "number in range");
            return ParseOutcome!double.failure();
        }
        state.setOffset(cursor);
        return ParseOutcome!double.succeed(value);
    }
}

/// Builds a complete algebraic expression parser in `grammar`.
///
/// Precedence, tightest to loosest:
/// 1. prefix `+` and `-`
/// 2. `*` and `/`, left-associative
/// 3. `+` and `-`, left-associative
///
/// The returned parser accepts leading/trailing ASCII whitespace and requires EOF.
Parser!(ArithmeticExpression*) arithmeticExpression(Grammar* grammar) @trusted
{
    version (XTB_Checked)
        require(grammar !is null, "arithmetic parser requires a grammar");

    Parser!Unit trivia = grammar.asciiWhitespace0().skip();
    Tokenizer token = grammar.tokenizer(trivia);

    Rule!(ArithmeticExpression*) expression =
        grammar.rule!(ArithmeticExpression*)("arithmetic expression");
    Rule!(ArithmeticExpression*) primary =
        grammar.rule!(ArithmeticExpression*)("arithmetic primary");

    Parser!double number = grammar.custom!double(ArithmeticNumberNode.init).before(trivia);
    Parser!(ArithmeticExpression*) numberExpression = number.map!makeNumber();
    Parser!(ArithmeticExpression*) identifierExpression =
        token.identifier().map!makeIdentifier();

    Parser!(ArithmeticExpression*) parenthesized =
        expression.parser.between(token.literal("("), token.literal(")"));

    primary.define(grammar.choice(
            parenthesized,
            numberExpression,
            identifierExpression,
    ));

    auto operators = grammar.expressionTable!(
        ArithmeticExpression*,
        ArithmeticBinaryOperator,
        ArithmeticUnaryOperator,
    )();

    operators.level()
        .prefix(token.literal("+"), ArithmeticUnaryOperator.positive)
        .prefix(token.literal("-"), ArithmeticUnaryOperator.negative);

    operators.level()
        .left(token.literal("*"), ArithmeticBinaryOperator.multiply)
        .left(token.literal("/"), ArithmeticBinaryOperator.divide);

    operators.level()
        .left(token.literal("+"), ArithmeticBinaryOperator.add)
        .left(token.literal("-"), ArithmeticBinaryOperator.subtract);

    expression.define(
        operators.build!(makeBinary, makeUnary)(primary.parser),
    );

    return trivia
        .after(expression.parser)
        .before(grammar.eof())
        .named("arithmetic expression");
}
