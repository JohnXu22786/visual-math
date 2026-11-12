import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/src/models/math_expression_parser.dart';

void main() {
  group('MathExpressionParser', () {
    test('preserves arithmetic precedence, unary signs, and right powers', () {
      final evaluate = MathExpressionParser.parse(
        '-(x^2) + 2 * (3 + 1) + 2^3^2',
        variables: ['x'],
      );

      expect(evaluate({'x': 2}), 516);
    });

    test('evaluates supported constants and unary and binary functions', () {
      final evaluate = MathExpressionParser.parse(
        'sin(pi / 2) + log(2, 8) + pow(2, 3) + sqrt2',
        variables: const [],
      );

      expect(evaluate({}), closeTo(13.414213562373096, 1e-12));
    });

    test('factorial stops after overflow for very large inputs', () {
      final evaluate = MathExpressionParser.parse('fact(x)', variables: ['x']);

      expect(evaluate({'x': 0}), 1);
      expect(evaluate({'x': 170}).isFinite, isTrue);
      expect(evaluate({'x': 171}), double.infinity);
      expect(evaluate({'x': 10000000000}), double.infinity);
      expect(() => evaluate({'x': -1}), throwsArgumentError);
      expect(() => evaluate({'x': 1.5}), throwsArgumentError);
    });

    test('reports unsupported functions, identifiers, and function arity', () {
      expect(
        () => MathExpressionParser.parse('unknown(1)', variables: const []),
        throwsFormatException,
      );
      expect(
        () => MathExpressionParser.parse('mystery', variables: const []),
        throwsFormatException,
      );
      expect(
        () => MathExpressionParser.parse('sin(1, 2)', variables: const []),
        throwsFormatException,
      );
    });

    test('rejects missing values and malformed expressions at evaluation', () {
      final evaluate = MathExpressionParser.parse('x + 1', variables: ['x']);

      expect(() => evaluate({}), throwsArgumentError);
      expect(
        () => MathExpressionParser.parse('1 + )', variables: const []),
        throwsFormatException,
      );
    });
  });
}
