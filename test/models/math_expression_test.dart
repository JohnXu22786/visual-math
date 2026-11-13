import 'dart:math' as dart_math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('domain bounds reject evaluation errors and retain validation', () {
    expect(MathExpression.resolveDomainBound('0.5!', {}), isNull);
    expect(MathExpression.resolveDomainBound('a!', {'a': 0.5}), isNull);
    expect(MathExpression.resolveDomainBound('a!', {'a': 3}), 6);
    expect(MathExpression.resolveDomainBound('1/0', {}), isNull);
    expect(MathExpression.resolveDomainBound('x+1', {}), isNull);
    expect(MathExpression.resolveDomainBound('y=1', {}), isNull);
  });

  group('MathExpression - fromInput (evaluator)', () {
    test('evaluates simple power expression', () {
      final expr = MathExpression.fromInput('x^2');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(0, 1e-10));
      expect(expr.evaluator(2), closeTo(4, 1e-10));
      expect(expr.evaluator(-2), closeTo(4, 1e-10));
    });

    test('evaluates expression with y= prefix', () {
      final expr = MathExpression.fromInput('y = x^2');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(2), closeTo(4, 1e-10));
    });

    test('y prefix retains equations that depend on y', () {
      for (final input in ['y=x+y', 'y=2y+x', r'y=\frac{y}{2}+x', 'y=xy']) {
        final expr = MathExpression.fromInput(input);
        expect(expr.isValid, isTrue, reason: input);
        expect(expr.type, MathExpressionType.implicit, reason: input);
        expect(expr.parameters, isEmpty, reason: input);
        expect(
          expr.implicitEvaluator!(0, 2),
          closeTo(
            input == r'y=\frac{y}{2}+x'
                ? 1
                : input == 'y=2y+x'
                ? -2
                : input == 'y=xy'
                ? 2
                : 0,
            1e-10,
          ),
          reason: input,
        );
      }
      final explicit = MathExpression.fromInput('y=yellow+x');
      expect(explicit.type, MathExpressionType.explicit);
      expect(explicit.parameters, {'yellow'});
    });

    test('evaluates expression with f(x)= prefix', () {
      final expr = MathExpression.fromInput('f(x) = x^2');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(2), closeTo(4, 1e-10));
    });

    test('evaluates sin function', () {
      final expr = MathExpression.fromInput('sin(x)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(0, 1e-10));
      expect(expr.evaluator(3.14159 / 2), closeTo(1, 1e-4));
    });

    test('evaluates cos function', () {
      final expr = MathExpression.fromInput('cos(x)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(1, 1e-10));
    });

    test('evaluates tan function', () {
      final expr = MathExpression.fromInput('tan(x)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(0, 1e-10));
    });

    test('evaluates sqrt function', () {
      final expr = MathExpression.fromInput('sqrt(x)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(4), closeTo(2, 1e-10));
    });

    test('evaluates ln/log function', () {
      final expr = MathExpression.fromInput('ln(x)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(1), closeTo(0, 1e-10));
      expect(expr.evaluator(dart_math.e), closeTo(1, 1e-4));
    });

    test('evaluates abs function', () {
      final expr = MathExpression.fromInput('abs(x)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(-5), closeTo(5, 1e-10));
      expect(expr.evaluator(3), closeTo(3, 1e-10));
    });

    test('evaluates complex polynomial expression', () {
      final expr = MathExpression.fromInput('x^3 + 2*x^2 - 5*x + 1');
      expect(expr.isValid, isTrue);
      // x=0: 1
      // x=1: 1 + 2 - 5 + 1 = -1
      // x=2: 8 + 8 - 10 + 1 = 7
      expect(expr.evaluator(0), closeTo(1, 1e-10));
      expect(expr.evaluator(1), closeTo(-1, 1e-10));
      expect(expr.evaluator(2), closeTo(7, 1e-10));
    });

    test('evaluates expression with multiple trig functions', () {
      final expr = MathExpression.fromInput('sin(x) + cos(x)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(1, 1e-10)); // sin(0)+cos(0)=0+1=1
    });

    test('evaluates implicit multiplication: 2x equals 2*x', () {
      final expr = MathExpression.fromInput('2x');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(3), closeTo(6, 1e-10));
    });

    test('evaluates implicit multiplication: 2(x+1) equals 2*(x+1)', () {
      final expr = MathExpression.fromInput('2(x+1)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(4), closeTo(10, 1e-10));
    });

    test('evaluates implicit multiplication: x(2) equals x*(2)', () {
      final expr = MathExpression.fromInput('x(2)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(3), closeTo(6, 1e-10));
      expect(expr.evaluator(5), closeTo(10, 1e-10));
    });

    test('evaluates implicit multiplication: a(x+1) equals a*(x+1)', () {
      final expr = MathExpression.fromInput('a(x+1)');
      expect(expr.isValid, isTrue);
      expect(expr.parameters, equals({'a'}));
      expect(expr.evaluator(4), closeTo(5, 1e-10)); // a=1 (default): 1*(4+1)=5
    });

    test('implicit multiplication does not break function names', () {
      final expr = MathExpression.fromInput('sin(x) + cos(x)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(1, 1e-10));
    });

    test('implicit multiplication does not break sqrt', () {
      final expr = MathExpression.fromInput('sqrt(4)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(2, 1e-10)); // sqrt(4)=2 (x not used)
    });

    test('implicit multiplication: )( pattern', () {
      final expr = MathExpression.fromInput('(x+1)(x+2)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(2, 1e-10)); // (0+1)*(0+2)=2
    });

    test('preserves parser precedence and maps supported functions', () {
      expect(MathExpression.toJsExpression('ln(x)'), 'Math.log(x)');
      expect(MathExpression.toJsExpression('010'), 'Number("010")');
      expect(
        MathExpression.toJsExpression('class+Math'),
        '__vmParams["class"]+__vmParams["Math"]',
      );
      expect(MathExpression.toJsExpression('-(-x)'), '-(-x)');
      expect(MathExpression.toJsExpression('x- -x'), 'x-(-x)');
      expect(
        MathExpression.toJsExpression('x^2^3'),
        'Math.pow(x,Math.pow(2,3))',
      );
      expect(
        MathExpression.toJsExpression('sin(x)^(1+x)'),
        'Math.pow(Math.sin(x),1+x)',
      );
      expect(
        MathExpression.toJsExpression('log(2,x)'),
        '(Math.log(x)/Math.log(2))',
      );
    });

    test('handles empty string', () {
      final expr = MathExpression.fromInput('');
      expect(expr.isValid, isFalse);
    });

    test('handles whitespace-only string', () {
      final expr = MathExpression.fromInput('   ');
      expect(expr.isValid, isFalse);
    });

    test('evaluates e^x (Euler number exponent)', () {
      final expr = MathExpression.fromInput('e^x');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(1, 1e-10));
      expect(expr.evaluator(1), closeTo(dart_math.e, 1e-4));
    });

    test('evaluates pi constant', () {
      final expr = MathExpression.fromInput('sin(x + pi)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(0), closeTo(0, 1e-10));
    });

    test('strips whitespace in conversion', () {
      final expr = MathExpression.fromInput('  x ^ 2  ');
      expect(expr.isValid, isTrue);
      expect(expr.evaluator(3), closeTo(9, 1e-10));
    });

    test('returns error for invalid expression', () {
      final expr = MathExpression.fromInput('x ^^ 2');
      expect(expr.isValid, isFalse);
      expect(expr.parseError, isNot(isNull));
    });

    test('returns error for malformed expression', () {
      final expr = MathExpression.fromInput('sin( + cos(x)');
      expect(expr.isValid, isFalse);
      expect(expr.parseError, isNot(isNull));
    });
  });

  group('MathExpression - withParameters', () {
    test('creates evaluator with parameter values', () {
      final expr = MathExpression.fromInput(
        'a*x^2 + b',
        parameterValues: {'a': 2, 'b': 1},
      );
      expect(expr.isValid, isTrue);
      // a=2, b=1: 2*x^2 + 1
      // x=0: 1
      // x=1: 3
      // x=2: 9
      expect(expr.evaluator(0), closeTo(1, 1e-10));
      expect(expr.evaluator(1), closeTo(3, 1e-10));
      expect(expr.evaluator(2), closeTo(9, 1e-10));
    });

    test('updates evaluator with new parameter values', () {
      final expr = MathExpression.fromInput(
        'a*x + b',
        parameterValues: {'a': 2, 'b': 3},
      );
      expect(expr.evaluator(5), closeTo(13, 1e-10)); // 2*5+3=13

      final updated = expr.withParameters({'a': 3, 'b': 1});
      expect(updated.evaluator(5), closeTo(16, 1e-10)); // 3*5+1=16
    });

    test('withParameters on invalid expression returns self', () {
      final expr = MathExpression.fromInput('');
      final updated = expr.withParameters({'a': 1});
      expect(identical(expr, updated), isTrue);
    });
  });

  group('MathExpression - latexDisplay', () {
    test('adds y= prefix when not present', () {
      expect(MathExpression.fromInput('x^2').latexDisplay, equals('y = x^2'));
    });

    test('preserves existing y= prefix', () {
      expect(
        MathExpression.fromInput('y = x^2').latexDisplay,
        equals('y = x^2'),
      );
    });

    test('preserves existing y= with spaces', () {
      expect(
        MathExpression.fromInput('y =   x^2').latexDisplay,
        equals('y = x^2'),
      );
    });

    test('preserves existing f(x)= prefix', () {
      expect(
        MathExpression.fromInput('f(x) = sin(x)').latexDisplay,
        equals('f(x) = sin(x)'),
      );
    });

    test('handles empty input', () {
      expect(MathExpression.fromInput('').latexDisplay, equals(''));
    });
  });

  group('MathExpression - parameters', () {
    test('extracts no parameters from simple x expression', () {
      expect(MathExpression.fromInput('x^2').parameters, isEmpty);
    });

    test('extracts single parameter a', () {
      expect(MathExpression.fromInput('a*x^2').parameters, equals({'a'}));
    });

    test('extracts multiple parameters', () {
      final expr = MathExpression.fromInput('a*x^2 + b*x + c');
      expect(expr.parameters, equals({'a', 'b', 'c'}));
    });

    test('excludes x and e from parameters', () {
      expect(MathExpression.fromInput('e^x').parameters, isEmpty);
    });

    test('excludes trig function names from parameters', () {
      final expr = MathExpression.fromInput('a*sin(b*x)');
      expect(expr.parameters, equals({'a', 'b'}));
      expect(expr.parameters, isNot(contains('sin')));
    });

    test('returns empty set for empty input', () {
      expect(MathExpression.fromInput('').parameters, isEmpty);
    });
  });

  group('MathExpression - samplePoints', () {
    test('samples correct number of points', () {
      final expr = MathExpression.fromInput('x^2');
      final points = expr.samplePoints(xMin: -10, xMax: 10, numPoints: 100);
      expect(points.length, 100);
    });

    test('first and last points are correct', () {
      final expr = MathExpression.fromInput('x^2');
      final points = expr.samplePoints(xMin: -2, xMax: 2, numPoints: 5);
      expect(points.length, 5);
      expect(points.first['x'], closeTo(-2, 1e-10));
      expect(points.first['y'], closeTo(4, 1e-10));
      expect(points.last['x'], closeTo(2, 1e-10));
      expect(points.last['y'], closeTo(4, 1e-10));
    });

    test('returns empty list for invalid expression', () {
      final expr = MathExpression.fromInput('');
      expect(expr.samplePoints(), isEmpty);
    });

    test('filters out NaN/Infinity points', () {
      final expr = MathExpression.fromInput('1/(x-0.5)');
      final points = expr.samplePoints(xMin: 0, xMax: 1, numPoints: 101);
      // x-0.5 = 0 at x=0.5, which should be one of the sample points
      // since 101 points from 0 to 1 includes 0.5 exactly.
      // At x=0.5, 1/0 = Infinity (non-finite), so it should be filtered.
      expect(points.length, lessThan(101));
    });

    test('returns empty list for invalid parameters', () {
      final expr = MathExpression.fromInput('x^2');
      expect(expr.samplePoints(xMin: 10, xMax: -10, numPoints: 5), isEmpty);
      expect(expr.samplePoints(xMin: -10, xMax: 10, numPoints: 1), isEmpty);
    });
  });

  group('MathExpression - isValid', () {
    test('is false for empty expression', () {
      expect(MathExpression.fromInput('').isValid, isFalse);
    });

    test('is true for valid expression', () {
      expect(MathExpression.fromInput('x^2').isValid, isTrue);
    });

    test('is false for invalid syntax', () {
      expect(MathExpression.fromInput('x + )').isValid, isFalse);
    });
  });

  group('MathExpression - toJsExpression (backward compat)', () {
    test('converts simple power expression', () {
      expect(MathExpression.toJsExpression('x^2'), equals('Math.pow(x,2)'));
    });

    test('converts expression with y= prefix', () {
      expect(MathExpression.toJsExpression('y = x^2'), equals('Math.pow(x,2)'));
    });

    test('converts sin function to Math.sin', () {
      expect(MathExpression.toJsExpression('sin(x)'), equals('Math.sin(x)'));
    });

    test('converts complex expression', () {
      expect(
        MathExpression.toJsExpression('x^3 + 2*x^2 - 5*x + 1'),
        equals('Math.pow(x,3)+2*Math.pow(x,2)-5*x+1'),
      );
    });

    test('handles empty string', () {
      expect(MathExpression.toJsExpression(''), equals(''));
    });
  });

  group('MathExpression - generateFunctionBody (backward compat)', () {
    test('generates return statement from JS expression', () {
      expect(
        MathExpression.generateFunctionBody('Math.pow(x,2)'),
        equals('return Math.pow(x,2);'),
      );
    });

    test('defaults to return 0 for empty', () {
      expect(MathExpression.generateFunctionBody(''), equals('return 0;'));
    });
  });

  group('MathExpression - LaTeX conversion', () {
    test('\\times is converted to *', () {
      final e = MathExpression.fromInput(r'x \times e^x');
      expect(e.isValid, isTrue, reason: '\times should be converted to *');
      expect(e.evaluator(0), closeTo(0, 1e-10)); // 0 * e^0 = 0
      expect(e.evaluator(1), closeTo(dart_math.e, 1e-4)); // 1 * e^1 = e
    });

    test('\\frac{x}{y} works', () {
      final e = MathExpression.fromInput(r'\frac{x}{2}');
      expect(e.isValid, isTrue);
      expect(e.evaluator(4), closeTo(2, 1e-10)); // 4/2 = 2
    });

    test('\\frac with nested braces works: \\frac{x^{2}}{y}', () {
      final e = MathExpression.fromInput(r'\frac{x^{2}}{2}');
      expect(e.isValid, isTrue);
      // x^2 / 2
      expect(e.evaluator(4), closeTo(8, 1e-10)); // 4^2/2 = 8
    });

    test('\\sin, \\cos work', () {
      final e = MathExpression.fromInput(r'\sin(x) + \cos(x)');
      expect(e.isValid, isTrue);
      expect(e.evaluator(0), closeTo(1, 1e-10)); // sin(0)+cos(0)=1
    });

    test('\\sqrt works', () {
      final e = MathExpression.fromInput(r'\sqrt{x}');
      expect(e.isValid, isTrue);
      expect(e.evaluator(16), closeTo(4, 1e-10));
    });

    test('\\pi constant works', () {
      final e = MathExpression.fromInput(r'\pi');
      expect(e.isValid, isTrue);
      expect(e.evaluator(0), closeTo(dart_math.pi, 1e-10));
    });

    test('\\ln works', () {
      final e = MathExpression.fromInput(r'\ln(x)');
      expect(e.isValid, isTrue);
      expect(e.evaluator(1), closeTo(0, 1e-10));
    });

    test('x \\times \\sin(x) works', () {
      final e = MathExpression.fromInput(r'x \times \sin(x)');
      expect(e.isValid, isTrue);
      expect(e.evaluator(dart_math.pi / 2), closeTo(dart_math.pi / 2, 1e-4));
      // (pi/2) * sin(pi/2) = (pi/2) * 1 = pi/2
    });

    test('\\left and \\right are stripped', () {
      final e = MathExpression.fromInput(r'\left(x^2\right)');
      expect(e.isValid, isTrue);
      expect(e.evaluator(3), closeTo(9, 1e-10));
    });
  });

  group('MathExpression - sampleContourSegments (marching squares)', () {
    // The marching squares algorithm must detect contour crossings even when
    // f(x,y) == 0 exactly at a grid point (e.g. at the origin). The condition
    // v00 * v10 < 0 misses crossings when the product is zero. We fix this by
    // treating exact-zero corner values as a tiny positive (1e-15) so that the
    // sign comparison correctly detects zero-value crossings.

    test('detects contour crossing when f=0 at a corner (origin-crossing curve)', () {
      // y^2 = 4x  =>  f(x,y) = y^2 - 4x
      // At origin (0,0): f = 0 - 0 = 0
      final expr = MathExpression.fromInput('y^2=4x');
      expect(expr.isValid, isTrue);
      expect(expr.type, MathExpressionType.implicit);

      final segments = expr.sampleContourSegments(
        xMin: -2,
        xMax: 2,
        yMin: -2,
        yMax: 2,
        gridX: 20,
        gridY: 20,
      );

      // The contour y^2=4x passes through (0,0). With a 20×20 grid over
      // [-2,2]×[-2,2], the origin is at a grid point. The algorithm must
      // produce at least some segments to represent this curve.
      expect(
        segments.isNotEmpty,
        isTrue,
        reason:
            'y^2=4x must produce contour segments even though f=0 at origin',
      );

      // The crucial test: the origin (0,0) MUST be part of the contour.
      // With the zero-value bug (v00*v10 < 0), the cells adjacent to the
      // origin each have only 1 crossing and produce NO segment, creating a
      // gap. After the fix, these cells produce segments through (0,0) via
      // the epsilon-based sign comparison.
      final atOrigin = segments.expand((s) => s).where((p) {
        return p['x']!.abs() < 1e-10 && p['y']!.abs() < 1e-10;
      }).toList();
      expect(
        atOrigin.isNotEmpty,
        isTrue,
        reason:
            'y^2=4x must have contour points at the origin (|x|<1e-10, |y|<1e-10). '
            'The zero-value bug (v00*v10<0) at f=0 grid points creates a gap; '
            'the epsilon fix ensures crossings through zero-valued corners',
      );
    });

    test(
      'finds off-grid touching zero contours without inventing nearby ones',
      () {
        for (final axis in ['x', 'y']) {
          List<List<Map<String, double>>> sample(String equation) =>
              MathExpression.fromInput(equation).sampleContourSegments(
                xMin: -1,
                xMax: 1,
                yMin: -1,
                yMax: 1,
                gridX: 4,
                gridY: 4,
              );
          final segments = sample('($axis-0.1)^2=0');
          expect(segments, isNotEmpty, reason: axis);
          expect(
            segments
                .expand((s) => s)
                .every((p) => (p[axis]! - 0.1).abs() < 1e-6),
            isTrue,
            reason: axis,
          );
          expect(sample('($axis-0.1)^2+0.001=0'), isEmpty, reason: axis);
          final intersecting = sample('($axis-0.1)^2*(y-0.1)=0');
          if (axis == 'x') {
            expect(
              intersecting.any(
                (s) =>
                    s.every((p) => (p['x']! - 0.1).abs() < 1e-6) &&
                    s.first['y']! < 0.1 &&
                    s.last['y']! > 0.1,
              ),
              isTrue,
            );
          }
        }
      },
    );

    test('touching contours connect adjacent edges and avoid poles', () {
      List<List<Map<String, double>>> sample(String equation) =>
          MathExpression.fromInput(equation).sampleContourSegments(
            xMin: 0,
            xMax: 0.5,
            yMin: 0,
            yMax: 0.5,
            gridX: 1,
            gridY: 1,
          );
      final diagonal = sample('(x+y-0.1)^2=0');
      expect(diagonal, isNotEmpty);
      expect(
        diagonal
            .expand((s) => s)
            .every((p) => (p['x']! + p['y']! - 0.1).abs() < 1e-6),
        isTrue,
      );
      expect(sample('((x^2+y^2)*((x-0.5)^2+(y-0.5)^2))=0'), isEmpty);
      expect(sample('((x-0.1)^2+y^2)*((x-0.4)^2+(y-0.5)^2)=0'), isEmpty);
      expect(
        sample(
          '((x-0.1)^2+y^2)*((x-0.25)^2+(y-0.25)^2)*((x-0.4)^2+(y-0.5)^2)=0',
        ),
        isEmpty,
      );
      final boundary = sample('(x+y-0.1)^2*sqrt(x)=0');
      expect(
        boundary.any(
          (s) => s.any(
            (p) => p['x']!.abs() < 1e-12 && (p['y']! - 0.1).abs() < 1e-6,
          ),
        ),
        isTrue,
      );
      final mixed = sample('(x-2*y-0.05)^2*(y-0.2)=0');
      expect(
        mixed.any(
          (s) => s.every((p) => (p['x']! - 2 * p['y']! - 0.05).abs() < 1e-6),
        ),
        isTrue,
      );
      final cornersMixed = sample('(x-y)^2*(x-0.4)=0');
      expect(
        cornersMixed.any(
          (s) => s.every((p) => (p['x']! - p['y']!).abs() < 1e-6),
        ),
        isTrue,
      );
      final crossingTangents = sample('(x-0.1)^2*(y-0.2)^2=0');
      expect(
        crossingTangents.any(
          (s) => s.every((p) => (p['x']! - 0.1).abs() < 1e-6),
        ),
        isTrue,
      );
      expect(
        crossingTangents.any(
          (s) => s.every((p) => (p['y']! - 0.2).abs() < 1e-6),
        ),
        isTrue,
      );
      final closeRoots = sample('(x-0.1)^2*(x-0.15)^2=0');
      for (final root in [0.1, 0.15]) {
        expect(
          closeRoots.any((s) => s.every((p) => (p['x']! - root).abs() < 1e-6)),
          isTrue,
        );
      }
      final multiple = sample('(x-0.1)^2*(x-0.4)^2=0');
      for (final root in [0.1, 0.4]) {
        expect(
          multiple.any((s) => s.every((p) => (p['x']! - root).abs() < 1e-6)),
          isTrue,
        );
      }
      final boundedPole = sample('(x-0.1)^2/((x-0.1)^2+(y-0.25)^2)=0');
      expect(boundedPole, isNotEmpty);
      expect(
        boundedPole.every(
          (s) => (s.first['y']! - 0.25) * (s.last['y']! - 0.25) > 0,
        ),
        isTrue,
      );
      for (final equation in [
        '(x-0.25)^2*(1+16*x*(1-x))=0',
        '(x-0.25)^2*(x-0.75)^2*(1+32*x*(1-x))=0',
      ]) {
        final segments = MathExpression.fromInput(equation)
            .sampleContourSegments(
              xMin: 0,
              xMax: 1,
              yMin: 0,
              yMax: 1,
              gridX: 1,
              gridY: 1,
            );
        for (final root in equation.contains('0.75') ? [0.25, 0.75] : [0.25]) {
          expect(
            segments.any((s) => s.every((p) => (p['x']! - root).abs() < 1e-6)),
            isTrue,
            reason: equation,
          );
        }
      }
      final rounded = MathExpression.fromInput('abs(x^2-2)=0')
          .sampleContourSegments(
            xMin: 1,
            xMax: 2,
            yMin: 0,
            yMax: 1,
            gridX: 1,
            gridY: 1,
          );
      expect(rounded, isNotEmpty);
      expect(
        rounded
            .expand((s) => s)
            .every((p) => (p['x']! * p['x']! - 2).abs() < 1e-10),
        isTrue,
      );
      final flat = sample('(x-0.01)^4=0');
      expect(flat, isNotEmpty);
      expect(
        flat.expand((s) => s).every((p) => (p['x']! - 0.01).abs() < 1e-6),
        isTrue,
      );
      final branch = sample('(x-0.1)^2*y=0');
      expect(
        branch.any((s) => s.every((p) => (p['x']! - 0.1).abs() < 1e-6)),
        isTrue,
      );
      final curvedBranch = sample('y*(x-y^2-0.1)^2=0');
      final zeroLength = curvedBranch
          .where((s) => s.every((p) => p['y'] == 0))
          .fold<double>(
            0,
            (sum, s) => sum + (s.last['x']! - s.first['x']!).abs(),
          );
      expect(zeroLength, closeTo(0.5, 1e-9));
      final angledBranch = sample('(x-y-0.1)^2*y=0');
      expect(
        angledBranch.any(
          (s) => s.every((p) => (p['x']! - p['y']! - 0.1).abs() < 1e-6),
        ),
        isTrue,
      );
      expect(
        angledBranch.every(
          (s) =>
              s.every((p) => p['y'] == 0) ||
              s.every((p) => (p['x']! - p['y']! - 0.1).abs() < 1e-6),
        ),
        isTrue,
      );
      final corners = sample('(x+y-0.5)^2=0');
      expect(corners, isNotEmpty);
      expect(
        corners
            .expand((s) => s)
            .every((p) => (p['x']! + p['y']! - 0.5).abs() < 1e-6),
        isTrue,
      );
      final nearEndPole = sample('(x-0.1)^2/(y-0.01)^2=0');
      expect(nearEndPole, isNotEmpty);
      expect(
        nearEndPole.every(
          (s) => (s.first['y']! - 0.01) * (s.last['y']! - 0.01) > 0,
        ),
        isTrue,
      );
      final offGridPole = sample('(x-0.1)^2/(y-0.2)^2=0');
      expect(offGridPole, isNotEmpty);
      expect(
        offGridPole.every(
          (s) => (s.first['y']! - 0.2) * (s.last['y']! - 0.2) > 0,
        ),
        isTrue,
      );
      final pole = sample('(x-0.1)^2/(y-0.25)^2=0');
      expect(pole, isNotEmpty);
      expect(
        pole.every((s) => (s.first['y']! - 0.25) * (s.last['y']! - 0.25) > 0),
        isTrue,
      );
    });

    test('rejects pole crossings while retaining nearby real roots', () {
      List<List<Map<String, double>>> sample(String equation) =>
          MathExpression.fromInput(equation).sampleContourSegments(
            xMin: -1,
            xMax: 2,
            yMin: -1,
            yMax: 2,
            gridX: 4,
            gridY: 1,
          );
      expect(sample('1/x=0'), isEmpty);
      expect(sample('1/y=0'), isEmpty);
      expect(sample('1/x+1000000000*x=0'), isEmpty);
      expect(sample('x-0.000000000001=0'), isNotEmpty);
      final roots = sample('(x-1)/x=0');
      expect(roots, isNotEmpty);
      expect(
        roots.expand((s) => s).every((p) => (p['x']! - 1).abs() < 1e-4),
        isTrue,
      );
      final branches = MathExpression.fromInput('(y-0.5)/x=0')
          .sampleContourSegments(
            xMin: -1,
            xMax: 1,
            yMin: 0,
            yMax: 1,
            gridX: 1,
            gridY: 1,
          );
      expect(branches, isNotEmpty);
      expect(branches.expand((s) => s).any((p) => p['x']! < 0), isTrue);
      expect(branches.expand((s) => s).any((p) => p['x']! > 0), isTrue);
      expect(branches.every((s) => s.first['x']! * s.last['x']! > 0), isTrue);
      final alignedBranches = MathExpression.fromInput('(y-0.5)/x=0')
          .sampleContourSegments(
            xMin: -1,
            xMax: 1,
            yMin: 0,
            yMax: 1,
            gridX: 1,
            gridY: 2,
          );
      expect(alignedBranches, isNotEmpty);
      expect(
        alignedBranches.every((s) => s.first['x']! * s.last['x']! > 0),
        isTrue,
      );
      final zeroEdge = MathExpression.fromInput('y^2/x^2=0')
          .sampleContourSegments(
            xMin: -1,
            xMax: 1,
            yMin: 0,
            yMax: 1,
            gridX: 1,
            gridY: 1,
          );
      expect(zeroEdge, isNotEmpty);
      expect(zeroEdge.every((s) => s.first['x']! * s.last['x']! > 0), isTrue);
      final evenPole = MathExpression.fromInput('(y-0.5)/x^2=0')
          .sampleContourSegments(
            xMin: -1,
            xMax: 1,
            yMin: 0,
            yMax: 1,
            gridX: 1,
            gridY: 1,
          );
      expect(evenPole, isNotEmpty);
      expect(evenPole.every((s) => s.first['x']! * s.last['x']! > 0), isTrue);
      final curve =
          MathExpression.fromInput(
            '(x*x+y*y-1)/((x-0.5)*(x-0.5)+(y-0.5)*(y-0.5))=0',
          ).sampleContourSegments(
            xMin: 0,
            xMax: 1,
            yMin: 0,
            yMax: 1,
            gridX: 1,
            gridY: 1,
          );
      expect(curve, isNotEmpty);
      final wide = MathExpression.fromInput('x*x=2').sampleContourSegments(
        xMin: 0,
        xMax: 1e40,
        yMin: -1,
        yMax: 1,
        gridX: 1,
        gridY: 1,
      );
      expect(wide, isNotEmpty);
      expect(
        wide
            .expand((s) => s)
            .every((p) => (p['x']! - 1.41421356237).abs() < 1e-6),
        isTrue,
      );
    });

    test('detects contour crossing for unit circle', () {
      // x^2 + y^2 = 1
      // The circle does not pass through the origin (f(0,0) = -1), but it
      // still exercises the marching squares across the grid to verify
      // the full contour is produced without gaps or errors.
      final expr = MathExpression.fromInput('x^2+y^2=1');
      expect(expr.isValid, isTrue);
      expect(expr.type, MathExpressionType.implicit);

      final segments = expr.sampleContourSegments(
        xMin: -2,
        xMax: 2,
        yMin: -2,
        yMax: 2,
        gridX: 20,
        gridY: 20,
      );

      // Circle x^2+y^2=1 should produce contour segments
      expect(
        segments.isNotEmpty,
        isTrue,
        reason: 'Circle equation must produce contour segments',
      );
    });

    test('detects contour crossing for x^2=y (implicit, origin-crossing)', () {
      // x^2 = y  =>  f(x,y) = x^2 - y
      // At origin (0,0): f = 0 - 0 = 0
      final expr = MathExpression.fromInput('x^2=y');
      expect(expr.isValid, isTrue);
      expect(expr.type, MathExpressionType.implicit);

      final segments = expr.sampleContourSegments(
        xMin: -2,
        xMax: 2,
        yMin: -2,
        yMax: 2,
        gridX: 20,
        gridY: 20,
      );

      expect(
        segments.isNotEmpty,
        isTrue,
        reason: 'x^2=y must produce contour segments even though f=0 at origin',
      );

      // The origin (0,0) MUST be part of the contour.
      final atOrigin = segments.expand((s) => s).where((p) {
        return p['x']!.abs() < 1e-10 && p['y']!.abs() < 1e-10;
      }).toList();
      expect(
        atOrigin.isNotEmpty,
        isTrue,
        reason: 'x^2=y must have contour points at the origin, no gap',
      );
    });

    test('detects contour crossing for 4x=y^3 (origin-crossing)', () {
      // 4x = y^3  =>  f(x,y) = 4x - y^3
      // At origin (0,0): f = 0 - 0 = 0
      final expr = MathExpression.fromInput('4x=y^3');
      expect(expr.isValid, isTrue);
      expect(expr.type, MathExpressionType.implicit);

      final segments = expr.sampleContourSegments(
        xMin: -2,
        xMax: 2,
        yMin: -2,
        yMax: 2,
        gridX: 20,
        gridY: 20,
      );

      expect(
        segments.isNotEmpty,
        isTrue,
        reason:
            '4x=y^3 must produce contour segments even though f=0 at origin',
      );

      // The origin (0,0) MUST be part of the contour.
      final atOrigin = segments.expand((s) => s).where((p) {
        return p['x']!.abs() < 1e-10 && p['y']!.abs() < 1e-10;
      }).toList();
      expect(
        atOrigin.isNotEmpty,
        isTrue,
        reason: '4x=y^3 must have contour points at the origin, no gap',
      );
    });

    test('connects a curved crossing without joining a nearby hyperbola', () {
      List<List<Map<String, double>>> sample(String input) =>
          MathExpression.fromInput(input).sampleContourSegments(
            xMin: 0,
            xMax: 0.25,
            yMin: 0,
            yMax: 0.25,
            gridX: 1,
            gridY: 1,
          );
      final crossing = sample('(x-0.1)*(y-0.1+0.001*x*(0.25-x))=0');
      final incident = crossing.where(
        (segment) => segment.any(
          (point) =>
              (point['x']! - 0.1).abs() < 1e-10 &&
              (point['y']! - 0.099985).abs() < 1e-10,
        ),
      );
      expect(incident.length, 4);

      final curvedBoth = sample('(x*x-0.02)*(y-0.1+0.001*x*(0.25-x))=0');
      final crossX = 0.1414213562373095;
      final crossY = 0.1 - 0.001 * crossX * (0.25 - crossX);
      expect(
        curvedBoth
            .where(
              (segment) => segment.any(
                (point) =>
                    (point['x']! - crossX).abs() < 1e-10 &&
                    (point['y']! - crossY).abs() < 1e-10,
              ),
            )
            .length,
        4,
      );

      final separated = sample('(x-0.1)*(y-0.1+0.001*x*(0.25-x))+1e-10=0');
      expect(
        separated.where(
          (segment) => segment.any(
            (point) =>
                (point['x']! - 0.1).abs() < 1e-10 &&
                (point['y']! - 0.099985).abs() < 1e-10,
          ),
        ),
        isEmpty,
      );
    });

    test(
      'zero determinant connects all four contour branches at the saddle',
      () {
        final expr = MathExpression.fromInput('(x-0.125)*(y-0.125)=0');
        final segments = expr.sampleContourSegments();
        final saddle = {'x': 0.125, 'y': 0.125};
        final incident = segments.where(
          (segment) => segment.any(
            (point) => point['x'] == saddle['x'] && point['y'] == saddle['y'],
          ),
        );
        expect(incident.length, 4);
        final ends = incident.map(
          (segment) => segment.firstWhere(
            (point) => point['x'] != saddle['x'] || point['y'] != saddle['y'],
          ),
        );
        expect(ends.map((p) => '${p['x']},${p['y']}').toSet(), {
          '0.125,0.0',
          '0.125,0.25',
          '0.0,0.125',
          '0.25,0.125',
        });

        final offCenter = MathExpression.fromInput('(x-0.1)*(y-0.1)=0')
            .sampleContourSegments(
              xMin: 0,
              xMax: 0.25,
              yMin: 0,
              yMax: 0.25,
              gridX: 1,
              gridY: 1,
            );
        expect(
          offCenter
              .where(
                (segment) => segment.any(
                  (p) =>
                      (p['x']! - 0.1).abs() < 1e-12 &&
                      (p['y']! - 0.1).abs() < 1e-12,
                ),
              )
              .length,
          4,
        );

        final curved =
            MathExpression.fromInput(
              '(x-0.125)*(y-0.125)+x*(0.25-x)*y*(0.25-y)=0',
            ).sampleContourSegments(
              xMin: 0,
              xMax: 0.25,
              yMin: 0,
              yMax: 0.25,
              gridX: 1,
              gridY: 1,
            );
        expect(
          curved
              .expand((s) => s)
              .where((p) => p['x'] == 0.125 && p['y'] == 0.125),
          isEmpty,
        );
        final cancelled = MathExpression.fromInput('(x-0.1)*(y-0.1)+1-1=0')
            .sampleContourSegments(
              xMin: 0,
              xMax: 0.25,
              yMin: 0,
              yMax: 0.25,
              gridX: 1,
              gridY: 1,
            );
        expect(
          cancelled
              .where(
                (segment) => segment.any(
                  (p) =>
                      (p['x']! - 0.1).abs() < 1e-7 &&
                      (p['y']! - 0.1).abs() < 1e-7,
                ),
              )
              .length,
          4,
        );

        final rotated =
            MathExpression.fromInput(
              '(x-0.4+2*(y-7/15))*(2*(x-0.4)-(y-7/15))=0',
            ).sampleContourSegments(
              xMin: 0,
              xMax: 1,
              yMin: 0,
              yMax: 1,
              gridX: 1,
              gridY: 1,
            );
        expect(
          rotated
              .where(
                (segment) => segment.any(
                  (p) =>
                      (p['x']! - 0.4).abs() < 1e-12 &&
                      (p['y']! - 7 / 15).abs() < 1e-12,
                ),
              )
              .length,
          4,
        );

        final closeBranches =
            MathExpression.fromInput('(x-0.1)*(y-0.1)+1e-25=0')
                .sampleContourSegments(
                  xMin: 0,
                  xMax: 0.25,
                  yMin: 0,
                  yMax: 0.25,
                  gridX: 1,
                  gridY: 1,
                );
        expect(
          closeBranches.where(
            (segment) => segment.every(
              (p) =>
                  (p['x']! - 0.1).abs() < 0.003 &&
                  (p['y']! - 0.1).abs() < 0.003,
            ),
          ),
          isNotEmpty,
        );

        final subtlyShifted =
            MathExpression.fromInput('(x-0.125)*(y-0.125+0.001*x*(0.25-x))=0')
                .sampleContourSegments(
                  xMin: 0,
                  xMax: 0.25,
                  yMin: 0,
                  yMax: 0.25,
                  gridX: 1,
                  gridY: 1,
                );
        expect(
          subtlyShifted.where(
            (segment) =>
                segment.any((p) => p['x'] == 0.125 && p['y'] == 0.125) &&
                segment.any((p) => p['x'] == 0 || p['x'] == 0.25),
          ),
          isEmpty,
        );

        final separated =
            MathExpression.fromInput('(x-0.125)*(y-0.125)+1e-32=0')
                .sampleContourSegments(
                  xMin: 0,
                  xMax: 0.25,
                  yMin: 0,
                  yMax: 0.25,
                  gridX: 1,
                  gridY: 1,
                );
        expect(
          separated
              .expand((s) => s)
              .where(
                (p) =>
                    (p['x']! - 0.125).abs() < 1e-12 &&
                    (p['y']! - 0.125).abs() < 1e-12,
              ),
          isEmpty,
        );

        final nearEdge =
            MathExpression.fromInput(
              'ln(x-0.999999999)*(x-1.00000001)*(y-0.1)=0',
            ).sampleContourSegments(
              xMin: 1,
              xMax: 1.25,
              yMin: 0,
              yMax: 0.25,
              gridX: 1,
              gridY: 1,
            );
        expect(
          nearEdge
              .where(
                (segment) => segment.any(
                  (p) =>
                      (p['x']! - 1.00000001).abs() < 1e-10 &&
                      (p['y']! - 0.1).abs() < 1e-10,
                ),
              )
              .length,
          4,
        );

        final shifted =
            MathExpression.fromInput('(x-0.5)*((y-0.5)+x*(1-x)*y*(1-y))=0')
                .sampleContourSegments(
                  xMin: 0,
                  xMax: 1,
                  yMin: 0,
                  yMax: 1,
                  gridX: 1,
                  gridY: 1,
                );
        expect(
          shifted.where(
            (segment) =>
                segment.any((p) => p['x'] == 0.5 && p['y'] == 0.5) &&
                segment.any((p) => p['x'] == 0 || p['x'] == 1),
          ),
          isEmpty,
        );
      },
    );

    test('marching squares segments are all finite and properly paired', () {
      final expr = MathExpression.fromInput('y^2=4x');
      final segments = expr.sampleContourSegments(
        xMin: -10,
        xMax: 10,
        yMin: -10,
        yMax: 10,
        gridX: 80,
        gridY: 80,
      );

      // Each segment must have exactly 2 points
      for (final seg in segments) {
        expect(
          seg.length,
          2,
          reason: 'Each contour segment must have 2 points',
        );
        expect(seg[0]['x']!.isFinite, isTrue);
        expect(seg[0]['y']!.isFinite, isTrue);
        expect(seg[1]['x']!.isFinite, isTrue);
        expect(seg[1]['y']!.isFinite, isTrue);
      }
    });

    test('same implicit formula produces same segments (deterministic)', () {
      final expr1 = MathExpression.fromInput('y^2=4x');
      final expr2 = MathExpression.fromInput('y^2=4x');

      final segs1 = expr1.sampleContourSegments(
        xMin: -5,
        xMax: 5,
        yMin: -5,
        yMax: 5,
        gridX: 40,
        gridY: 40,
      );
      final segs2 = expr2.sampleContourSegments(
        xMin: -5,
        xMax: 5,
        yMin: -5,
        yMax: 5,
        gridX: 40,
        gridY: 40,
      );

      // Same formula at same grid should produce same number of segments
      expect(
        segs1.length,
        segs2.length,
        reason: 'Same formula at same grid should produce same segments',
      );
    });

    test(
      'explicit function (y=x^2) uses samplePoints, not marching squares',
      () {
        // y=x^2 is explicit (y= prefix stripped), should use explicit path.
        final expr = MathExpression.fromInput('y=x^2');
        expect(expr.isValid, isTrue);
        expect(expr.type, MathExpressionType.explicit);

        // sampleContourSegments should return empty for explicit
        final segments = expr.sampleContourSegments(
          xMin: -10,
          xMax: 10,
          yMin: -10,
          yMax: 10,
          gridX: 80,
          gridY: 80,
        );
        expect(
          segments,
          isEmpty,
          reason: 'Explicit functions should not produce contour segments',
        );
      },
    );
  });
}
