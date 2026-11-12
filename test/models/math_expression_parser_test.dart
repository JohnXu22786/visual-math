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

    test(
      'evaluates odd roots of negative values and preserves domain limits',
      () {
        final evaluate = MathExpressionParser.parse(
          'nrt(root, value)',
          variables: ['root', 'value'],
        );

        expect(evaluate({'root': 3, 'value': -8}), closeTo(-2, 1e-12));
        expect(evaluate({'root': -3, 'value': -8}), closeTo(-0.5, 1e-12));
        expect(evaluate({'root': 2, 'value': -8}).isNaN, isTrue);
        expect(evaluate({'root': 2.5, 'value': -8}).isNaN, isTrue);
        expect(evaluate({'root': 3, 'value': 8}), closeTo(2, 1e-12));
      },
    );

    test('hyperbolic ratios stay stable at large and small inputs', () {
      for (final name in ['tanh', 'coth']) {
        final evaluate = MathExpressionParser.parse(
          '$name(x)',
          variables: ['x'],
        );
        for (final x in [-1000.0, -0.5, 0.5, 1000.0]) {
          final expected = switch ((name, x)) {
            ('tanh', -1000.0) || ('coth', -1000.0) => -1.0,
            ('tanh', 1000.0) || ('coth', 1000.0) => 1.0,
            ('tanh', -0.5) => -0.46211715726000974,
            ('tanh', 0.5) => 0.46211715726000974,
            ('coth', -0.5) => -2.163953413738653,
            _ => 2.163953413738653,
          };
          expect(evaluate({'x': x}), closeTo(expected, 1e-12));
        }
        expect(evaluate({'x': 0}), name == 'tanh' ? 0 : double.infinity);
        final negativeZero = evaluate({'x': -0.0});
        expect(
          name == 'tanh'
              ? negativeZero.isNegative
              : negativeZero == double.negativeInfinity,
          isTrue,
        );
        expect(
          evaluate({'x': 1e-20}),
          closeTo(name == 'tanh' ? 1e-20 : 1e20, name == 'tanh' ? 1e-35 : 1e5),
        );
      }
    });

    test('sinh and csch retain precision near zero', () {
      for (final name in ['sinh', 'csch']) {
        final evaluate = MathExpressionParser.parse(
          '$name(x)',
          variables: ['x'],
        );
        for (final x in [-1e-4, -1e-20, 1e-20, 1e-4, 0.00010001, 0.01]) {
          final sinh = x * (1 + x * x / 6 + x * x * x * x / 120);
          final expected = name == 'sinh' ? sinh : 1 / sinh;
          expect((evaluate({'x': x}) / expected - 1).abs(), lessThan(1e-14));
        }
        final negativeZero = evaluate({'x': -0.0});
        expect(
          name == 'sinh'
              ? negativeZero.isNegative
              : negativeZero == double.negativeInfinity,
          isTrue,
        );
        expect(evaluate({'x': 0}), name == 'sinh' ? 0 : double.infinity);
      }
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
