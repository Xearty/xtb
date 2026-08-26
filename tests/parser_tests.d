module tests.parser_tests;

nothrow @nogc:

import xtb.allocators.arena : Arena;
import xtb.allocators.malloc : mallocAllocator;
import xtb.types : String;
import xtb.parser;

private int digitSum(int left, char digit) pure @safe
{
    return left + digit - '0';
}

private bool decimalDigit(char value) pure @safe
{
    return value >= '0' && value <= '9';
}

private int parseDecimal(String value) pure @safe
{
    int result;
    foreach (digit; value)
        result = result * 10 + digit - '0';
    return result;
}

private bool positive(int value) pure @safe
{
    return value > 0;
}

private void testCoreCombinators()
{
    Grammar grammar = Grammar.create(mallocAllocator(), 512);
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
    assert(choice.parse("car").value == "car");
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
    assert(cutBranch.parse("foo").value == 2);
    auto malformedCall = cutBranch.parse("foo(");
    assert(malformedCall.failed);
    assert(malformedCall.failureKind == FailureKind.committed);

    auto optional = grammar.value('-').optional().then(grammar.integer!int());
    auto optionalPresent = optional.parse("-4");
    assert(optionalPresent.ok && optionalPresent.value.first.isSome);
    auto optionalAbsent = optional.parse("4");
    assert(optionalAbsent.ok && optionalAbsent.value.first.isNone);

    assert(grammar.digit().repeat1().skip().parse("12345").ok);
    assert(grammar.digit().repeat1().skip().parse("").failed);

    Arena output = Arena.create(mallocAllocator(), 256);
    ParseContext context = ParseContext.create(&output);
    auto collected = grammar.integer!int().sepBy(grammar.value(',')).collect();
    auto collectedResult = collected.parse("1,2,3,4", &context);
    assert(collectedResult.ok);
    assert(collectedResult.value == [1, 2, 3, 4]);
    assert(collected.parse("", &context).ok);
    assert(collected.parse("1,", &context).failed);

    auto folded = grammar.digit().repeat1().fold!(int, digitSum)(0);
    assert(folded.parse("123").value == 6);

    auto mapped = grammar.takeWhile1!decimalDigit("digits")
        .map!parseDecimal();
    assert(mapped.parse("2048").value == 2048);

    struct Assignment
    {
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

    auto positiveInteger = grammar.integer!int().where!positive("positive integer");
    assert(positiveInteger.parse("5").ok);
    assert(positiveInteger.parse("0").failed);

    auto peeked = grammar.literal("abc").peek().then(grammar.literal("abc"));
    auto peekedResult = peeked.parse("abc");
    assert(peekedResult.ok && peekedResult.offset == 3);

    auto recursive = grammar.rule!int("recursive integer");
    auto parenthesized = recursive.parser.between(
        grammar.value('('),
        grammar.value(')'),
    );
    recursive.define(grammar.choice(parenthesized, grammar.integer!int()));
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

    assert(grammar.integer!int().parse("-2147483648").value == int.min);
    assert(grammar.integer!ubyte().parse("255").value == 255);
    assert(grammar.integer!ubyte().parse("256").error.kind == ParseErrorKind.numberOutOfRange);

    assert(grammar.floating!double().parse("0").value == 0.0);
    assert(grammar.floating!double().parse("-12.5e2").value == -1250.0);
    assert(grammar.floating!double().parse("01").value == 1.0);
    assert(grammar.floating!double().parse("+1.5").value == 1.5);
    assert(grammar.floating!double().parse("1.").failed);
    assert(grammar.floating!double().parse("1e").failed);

    output.deinit();
}

private enum TestBinaryOperator : ubyte
{
    power,
    less,
}

private enum TestUnaryOperator : ubyte
{
    negate,
    factorial,
}

private int integerPower(int base, int exponent) pure @safe
{
    int result = 1;
    foreach (_; 0 .. exponent)
        result *= base;
    return result;
}

private int expressionBinary(
    int left,
    TestBinaryOperator operation,
    int right,
) pure @safe
{
    final switch (operation)
    {
        case TestBinaryOperator.power:
            return integerPower(left, right);
        case TestBinaryOperator.less:
            return left < right ? 1 : 0;
    }
}

private int expressionUnary(
    TestUnaryOperator operation,
    int value,
) pure @safe
{
    final switch (operation)
    {
        case TestUnaryOperator.negate:
            return -value;
        case TestUnaryOperator.factorial:
            int result = 1;
            foreach (current; 2 .. value + 1)
                result *= current;
            return result;
    }
}

private void testExpressionTable()
{
    Grammar grammar = Grammar.create(mallocAllocator(), 1024);
    scope (exit)
        grammar.deinit();
    auto trivia = grammar.asciiWhitespace0().skip();
    Tokenizer token = grammar.tokenizer(trivia);
    auto atom = grammar.takeWhile1!decimalDigit("integer")
        .map!parseDecimal()
        .before(trivia);

    auto table = grammar.expressionTable!(
        int,
        TestBinaryOperator,
        TestUnaryOperator,
    )();

    table.level()
        .prefix(token.literal("-"), TestUnaryOperator.negate)
        .postfix(token.literal("!"), TestUnaryOperator.factorial);

    table.level()
        .right(token.literal("^"), TestBinaryOperator.power);

    table.level()
        .nonassoc(token.literal("<"), TestBinaryOperator.less);

    auto expression = trivia
        .after(table.build!(expressionBinary, expressionUnary)(atom))
        .before(grammar.eof());

    assert(expression.parse("2 ^ 3 ^ 2").value == 512);
    assert(expression.parse("-3!").value == -6);
    assert(expression.parse("--2").value == 2);
    assert(expression.parse("1 < 2").value == 1);
    assert(expression.parse("2 < 1").value == 0);
    assert(expression.parse("1 < 2 < 3").failed);
}

static assert(JsonValue.sizeof <= JsonKind.sizeof + (JsonValue[]).sizeof + (void*).alignof);
static assert(ArithmeticExpression.sizeof <=
        ArithmeticExpressionKind.sizeof + ArithmeticBinary.sizeof + (void*).alignof);

private void assertNumber(const ArithmeticExpression* node, double expected)
{
    assert(node !is null);
    assert(node.kind == ArithmeticExpressionKind.number);
    assert(node.number == expected);
}

private void testArithmeticParser()
{
    Grammar grammar = Grammar.create(mallocAllocator(), 1024);
    scope (exit)
        grammar.deinit();
    Parser!(ArithmeticExpression*) parser = arithmeticExpression(&grammar);
    Arena output = Arena.create(mallocAllocator(), 1024);
    ParseContext context = ParseContext.create(&output);

    auto precedence = parser.parse("2 + 3 * 4", &context);
    assert(precedence.ok);
    auto root = precedence.value;
    assert(root.kind == ArithmeticExpressionKind.binary);
    assert(root.binary.operation == ArithmeticBinaryOperator.add);
    assertNumber(root.binary.left, 2);
    assert(root.binary.right.kind == ArithmeticExpressionKind.binary);
    assert(root.binary.right.binary.operation == ArithmeticBinaryOperator.multiply);
    assertNumber(root.binary.right.binary.left, 3);
    assertNumber(root.binary.right.binary.right, 4);

    output.clear();
    auto grouping = parser.parse("(2 + 3) * 4", &context);
    assert(grouping.ok);
    root = grouping.value;
    assert(root.kind == ArithmeticExpressionKind.binary);
    assert(root.binary.operation == ArithmeticBinaryOperator.multiply);
    assert(root.binary.left.kind == ArithmeticExpressionKind.binary);
    assert(root.binary.left.binary.operation == ArithmeticBinaryOperator.add);
    assertNumber(root.binary.right, 4);

    output.clear();
    auto associativity = parser.parse("20 / 5 / 2", &context);
    assert(associativity.ok);
    root = associativity.value;
    assert(root.binary.operation == ArithmeticBinaryOperator.divide);
    assert(root.binary.left.kind == ArithmeticExpressionKind.binary);
    assert(root.binary.left.binary.operation == ArithmeticBinaryOperator.divide);
    assertNumber(root.binary.left.binary.left, 20);
    assertNumber(root.binary.left.binary.right, 5);
    assertNumber(root.binary.right, 2);

    output.clear();
    auto unary = parser.parse(" -x * +2 ", &context);
    assert(unary.ok);
    root = unary.value;
    assert(root.binary.operation == ArithmeticBinaryOperator.multiply);
    assert(root.binary.left.kind == ArithmeticExpressionKind.unary);
    assert(root.binary.left.unary.operation == ArithmeticUnaryOperator.negative);
    assert(root.binary.left.unary.operand.kind == ArithmeticExpressionKind.identifier);
    assert(root.binary.left.unary.operand.identifier == "x");
    assert(root.binary.right.kind == ArithmeticExpressionKind.unary);
    assert(root.binary.right.unary.operation == ArithmeticUnaryOperator.positive);
    assertNumber(root.binary.right.unary.operand, 2);

    output.clear();
    auto nestedUnary = parser.parse("--3", &context);
    assert(nestedUnary.ok);
    assert(nestedUnary.value.kind == ArithmeticExpressionKind.unary);
    assert(nestedUnary.value.unary.operand.kind == ArithmeticExpressionKind.unary);

    assert(parser.parse("1 + * 2", &context).failed);
    assert(parser.parse("(1 + 2", &context).failed);
    assert(parser.parse("1 2", &context).failed);

    output.deinit();
}

private void testJsonParser()
{
    Grammar grammar = Grammar.create(mallocAllocator(), 2048);
    scope (exit)
        grammar.deinit();
    Parser!JsonValue parser = jsonDocument(&grammar);
    Arena output = Arena.create(mallocAllocator(), 2048);
    ParseContext context = ParseContext.create(&output);

    auto nullResult = parser.parse("null", &context);
    assert(nullResult.ok && nullResult.value.kind == JsonKind.null_);

    output.clear();
    auto trueResult = parser.parse(" true \n", &context);
    assert(trueResult.ok);
    assert(trueResult.value.kind == JsonKind.boolean && trueResult.value.boolean);

    output.clear();
    auto numberResult = parser.parse("-12.5e2", &context);
    assert(numberResult.ok);
    assert(numberResult.value.kind == JsonKind.number);
    assert(numberResult.value.number == -1250.0);

    output.clear();
    auto stringResult = parser.parse("\"hello\\nworld\"", &context);
    assert(stringResult.ok);
    assert(stringResult.value.kind == JsonKind.string);
    assert(stringResult.value.string == "hello\nworld");

    output.clear();
    auto unicodeResult = parser.parse("\"\\u0041\\u03A9\\uD83D\\uDE00\"", &context);
    assert(unicodeResult.ok);
    assert(unicodeResult.value.string == "AΩ😀");

    output.clear();
    auto arrayResult = parser.parse("[null,true,false,1,2.5,\"x\",[3]]", &context);
    assert(arrayResult.ok);
    assert(arrayResult.value.kind == JsonKind.array);
    assert(arrayResult.value.array.length == 7);
    assert(arrayResult.value.array[1].boolean);
    assert(!arrayResult.value.array[2].boolean);
    assert(arrayResult.value.array[3].number == 1.0);
    assert(arrayResult.value.array[5].string == "x");
    assert(arrayResult.value.array[6].array[0].number == 3.0);

    output.clear();
    String document = `{
        "name": "xtb",
        "enabled": true,
        "count": 42,
        "nested": {"items": [1, 2, 3], "none": null}
    }`;
    auto objectResult = parser.parse(document, &context);
    assert(objectResult.ok);
    assert(objectResult.value.kind == JsonKind.object);
    const JsonValue* name = findMember(&objectResult.value, "name");
    assert(name !is null && name.kind == JsonKind.string && name.string == "xtb");
    const JsonValue* count = findMember(&objectResult.value, "count");
    assert(count !is null && count.number == 42.0);
    const JsonValue* nested = findMember(&objectResult.value, "nested");
    assert(nested !is null && nested.kind == JsonKind.object);
    const JsonValue* items = findMember(nested, "items");
    assert(items !is null && items.kind == JsonKind.array && items.array.length == 3);

    // JSON grammar rejection cases.
    assert(parser.parse("", &context).failed);
    assert(parser.parse("01", &context).failed);
    assert(parser.parse("1.", &context).failed);
    assert(parser.parse("1e", &context).failed);
    assert(parser.parse("[1,]", &context).failed);
    assert(parser.parse("{\"a\":1,}", &context).failed);
    assert(parser.parse("{a:1}", &context).failed);
    assert(parser.parse("\"bad\\xescape\"", &context).failed);
    assert(parser.parse("\"\\uD800\"", &context).failed);
    assert(parser.parse("\"\\uDC00\"", &context).failed);
    assert(parser.parse("\"line\nbreak\"", &context).failed);
    assert(parser.parse("true false", &context).failed);
    assert(parser.parse("[", &context).failed);
    assert(parser.parse("{", &context).failed);

    output.deinit();
}

extern (C) int main()
{
    testCoreCombinators();
    testExpressionTable();
    testArithmeticParser();
    testJsonParser();
    return 0;
}
