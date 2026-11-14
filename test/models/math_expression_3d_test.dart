import 'dart:math' as dart_math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  group('Expression3D - surface parsing', () {
    test('parses z = f(x, y) surface from simple expression', () {
      final expr = Expression3D.surface('x^2 + y^2');
      expect(expr.isValid, isTrue);
      expect(expr.type, Expression3DType.surface);
    });

    test('surface evaluator returns correct z values', () {
      final expr = Expression3D.surface('x^2 + y^2');
      expect(expr.isValid, isTrue);
      expect(expr.evaluateSurface(0, 0), closeTo(0, 1e-10));
      expect(expr.evaluateSurface(1, 1), closeTo(2, 1e-10));
      expect(expr.evaluateSurface(-1, 2), closeTo(5, 1e-10));
    });

    test('treats mixed-case function names as parameters', () {
      final surface = Expression3D.surface(
        'Sin + x + sin(x) + PI',
        parameterValues: {'Sin': 2},
      );
      expect(surface.isValid, isTrue, reason: surface.parseError);
      expect(surface.parameters, {'Sin'});
      expect(
        surface.evaluateSurface(1, 0),
        closeTo(2 + 1 + dart_math.sin(1) + dart_math.pi, 1e-10),
      );
    });

    test('uppercase constants evaluate in every 3D expression type', () {
      final surface = Expression3D.surface('PI + E + LN2 + SQRT2');
      expect(surface.parameters, isEmpty);
      expect(
        surface.evaluateSurface(0, 0),
        closeTo(
          dart_math.pi + dart_math.e + dart_math.ln2 + dart_math.sqrt2,
          1e-10,
        ),
      );

      final curve = Expression3D.parametricCurve('(PI, E, t)');
      final curvePoint = curve.evaluateCurve(2);
      expect(curvePoint.x, closeTo(dart_math.pi, 1e-10));
      expect(curvePoint.y, closeTo(dart_math.e, 1e-10));
      expect(curvePoint.z, closeTo(2, 1e-10));

      final parametric = Expression3D.parametricSurface('(PI, E, u+v)');
      final surfacePoint = parametric.evaluateParametricSurface(2, 3);
      expect(surfacePoint.x, closeTo(dart_math.pi, 1e-10));
      expect(surfacePoint.y, closeTo(dart_math.e, 1e-10));
      expect(surfacePoint.z, closeTo(5, 1e-10));
    });

    test('mixed-case constant names remain adjustable parameters', () {
      for (final input in ['Pi+x', r'\Pi+x']) {
        final surface = Expression3D.surface(input);
        expect(surface.isValid, isTrue, reason: surface.parseError);
        expect(surface.parameters, {'Pi'}, reason: input);
        expect(surface.evaluateSurface(2, 0), 3, reason: input);

        final updated = Expression3D.surface(input, parameterValues: {'Pi': 4});
        expect(updated.parameters, {'Pi'}, reason: input);
        expect(updated.evaluateSurface(2, 0), 6, reason: input);
      }

      for (final name in ['pi', 'PI']) {
        final constant = Expression3D.surface('$name+x');
        expect(constant.parameters, isEmpty, reason: name);
        expect(
          constant.evaluateSurface(2, 0),
          closeTo(dart_math.pi + 2, 1e-10),
          reason: name,
        );
      }
    });

    test('constant products before parentheses accept uppercase names', () {
      for (final name in ['pi', 'PI']) {
        final surface = Expression3D.surface('$name(x+1) + sin(x)');
        expect(surface.isValid, isTrue, reason: surface.parseError);
        expect(surface.parameters, isEmpty);
        expect(
          surface.evaluateSurface(1, 0),
          closeTo(2 * dart_math.pi + dart_math.sin(1), 1e-10),
        );
      }
      final curve = Expression3D.parametricCurve('(LN2(t+1), SQRT2(t), t)');
      expect(curve.isValid, isTrue, reason: curve.parseError);
      final point = curve.evaluateCurve(2);
      expect(point.x, closeTo(3 * dart_math.ln2, 1e-10));
      expect(point.y, closeTo(2 * dart_math.sqrt2, 1e-10));
    });

    test('scientific literals retain exponents and implicit products', () {
      final surface = Expression3D.surface('1e-3x + 2E+2y + .5e1');
      expect(surface.isValid, isTrue);
      expect(surface.evaluateSurface(2, 3), closeTo(605.002, 1e-10));
      expect(surface.parameters, isEmpty);

      final parameter = Expression3D.surface(
        'a1*e-3',
        parameterValues: {'a1': 2},
      );
      expect(
        parameter.evaluateSurface(0, 0),
        closeTo(2 * dart_math.e - 3, 1e-10),
      );

      final curve = Expression3D.parametricCurve('(1e-3t, 2E+1, 1e2)');
      expect(curve.isValid, isTrue);
      final point = curve.evaluateCurve(2);
      expect(point.x, closeTo(0.002, 1e-10));
      expect(point.y, closeTo(20, 1e-10));
      expect(point.z, closeTo(100, 1e-10));
    });

    test(
      'preserves complete parameter identifiers during implicit products',
      () {
        final surface = Expression3D.surface(
          'xy_1 + a1b + 2xy + 3a1b',
          parameterValues: {'xy_1': 4, 'a1b': 5},
        );
        expect(surface.isValid, isTrue, reason: surface.parseError);
        expect(surface.parameters, {'xy_1', 'a1b'});
        expect(surface.evaluateSurface(2, 3), 36);

        final curve = Expression3D.parametricCurve(
          '(xy_1, a1b, 2t)',
          parameterValues: {'xy_1': 4, 'a1b': 5},
        );
        expect(curve.isValid, isTrue, reason: curve.parseError);
        expect(curve.parameters, {'xy_1', 'a1b'});
        final point = curve.evaluateCurve(3);
        expect([point.x, point.y, point.z], [4, 5, 6]);
      },
    );

    test('surface with z= prefix works', () {
      final expr = Expression3D.surface('z = x^2 + y^2');
      expect(expr.isValid, isTrue);
      expect(expr.evaluateSurface(2, 3), closeTo(13, 1e-10));
    });

    test('surface with f(x,y)= prefix works', () {
      final expr = Expression3D.surface('f(x,y) = x^2 + y^2');
      expect(expr.isValid, isTrue);
      expect(expr.evaluateSurface(0, 0), closeTo(0, 1e-10));
    });
  });

  group('Expression3D - parametric curve', () {
    test('parses 3D parametric curve', () {
      final expr = Expression3D.parametricCurve('(cos(t), sin(t), t)');
      expect(expr.isValid, isTrue);
      expect(expr.parseError, isNull);
      expect(expr.type, Expression3DType.parametricCurve);
    });

    test('parametric curve evaluates at t values', () {
      final expr = Expression3D.parametricCurve(
        '(cos(t), sin(t), t)',
        tMin: 0,
        tMax: 2 * dart_math.pi,
      );
      expect(expr.isValid, isTrue);
      final pt0 = expr.evaluateCurve(0);
      expect(pt0.x, closeTo(1, 1e-4)); // cos(0) = 1
      expect(pt0.y, closeTo(0, 1e-4)); // sin(0) = 0
      expect(pt0.z, closeTo(0, 1e-10));

      final ptHalfPi = expr.evaluateCurve(dart_math.pi / 2);
      expect(ptHalfPi.x, closeTo(0, 1e-4));
      expect(ptHalfPi.y, closeTo(1, 1e-4));
    });

    test('sampleCurve generates correct number of points', () {
      final expr = Expression3D.parametricCurve(
        '(cos(t), sin(t), t)',
        tMin: 0,
        tMax: 2 * dart_math.pi,
      );
      final pts = expr.sampleCurve(numSamples: 50);
      expect(pts.length, 50);
    });

    test('returns empty points for invalid curve', () {
      final expr = Expression3D.parametricCurve('invalid');
      expect(expr.isValid, isFalse);
      expect(expr.sampleCurve(), isEmpty);
    });
  });

  group('Expression3D - parametric surface', () {
    test('parses 3D parametric surface', () {
      final expr = Expression3D.parametricSurface(
        '((R + r*cos(u))*cos(v), (R + r*cos(u))*sin(v), r*sin(u))',
        uMin: 0,
        uMax: 2,
        vMin: 0,
        vMax: 2,
      );
      expect(expr.isValid, isTrue);
      expect(expr.type, Expression3DType.parametricSurface);
    });

    test('parametric surface evaluates at u,v values', () {
      final expr = Expression3D.parametricSurface(
        '(cos(u)*cos(v), cos(u)*sin(v), sin(u))', // unit sphere
        uMin: -dart_math.pi / 2,
        uMax: dart_math.pi / 2,
        vMin: 0,
        vMax: 2 * dart_math.pi,
      );
      expect(expr.isValid, isTrue);
      final pt = expr.evaluateParametricSurface(0, 0);
      expect(pt.x, closeTo(1, 1e-4));
      expect(pt.y, closeTo(0, 1e-4));
      expect(pt.z, closeTo(0, 1e-4));
    });
  });

  group('Expression3D - error handling', () {
    test('returns invalid for empty input', () {
      final expr = Expression3D.surface('');
      expect(expr.isValid, isFalse);
      expect(expr.parseError, isNotNull);
    });

    test('returns error for invalid surface expression', () {
      final expr = Expression3D.surface('x ^^ y');
      expect(expr.isValid, isFalse);
    });

    test('returns error for malformed parametric curve', () {
      final expr = Expression3D.parametricCurve('(x, y)'); // no t parameter
      expect(expr.isValid, isFalse);
    });
  });

  group('Expression3D - surface sampling', () {
    test('sampleSurfaceGrid returns proper mesh data', () {
      final expr = Expression3D.surface('x^2 + y^2');
      final mesh = expr.sampleSurfaceGrid(
        xMin: -2,
        xMax: 2,
        yMin: -2,
        yMax: 2,
        gridX: 4,
        gridY: 4,
      );
      // 5x5 grid = 25 vertices
      // 4x4 cells × 2 triangles = 32 triangles = 96 indices
      expect(mesh.vertices.length, 25);
      expect(mesh.indices.length, 96);
      // Center should be at z=0
      expect(mesh.vertices[12].z, closeTo(0, 1e-10));
      // Corners should be at z=8 (2^2+2^2=8)
      expect(mesh.vertices[0].z, closeTo(8, 1e-10));
      expect(mesh.vertices[4].z, closeTo(8, 1e-10));
      expect(mesh.vertices[20].z, closeTo(8, 1e-10));
      expect(mesh.vertices[24].z, closeTo(8, 1e-10));
    });

    test('sampleSurfaceGrid handles sine waves correctly', () {
      final expr = Expression3D.surface('sin(x)*cos(y)');
      final mesh = expr.sampleSurfaceGrid(
        xMin: -dart_math.pi,
        xMax: dart_math.pi,
        yMin: -dart_math.pi,
        yMax: dart_math.pi,
        gridX: 6,
        gridY: 6,
      );
      expect(mesh.vertices.length, 49); // 7x7
      // sin(0)*cos(0) = 0
      expect(mesh.vertices[24].z, closeTo(0, 1e-10)); // center
    });

    test('returns empty mesh for invalid expression', () {
      final expr = Expression3D.surface('');
      final mesh = expr.sampleSurfaceGrid();
      expect(mesh.vertices, isEmpty);
      expect(mesh.indices, isEmpty);
    });

    test('handles limited domain correctly', () {
      final expr = Expression3D.surface('sqrt(4 - x^2 - y^2)');
      final mesh = expr.sampleSurfaceGrid(
        xMin: -1,
        xMax: 1,
        yMin: -1,
        yMax: 1,
        gridX: 4,
        gridY: 4,
      );
      expect(mesh.vertices.length, 25);
      // sqrt(4 - 0 - 0) = 2 at center
      expect(mesh.vertices[12].z, closeTo(2, 1e-5));
    });
  });

  group('Expression3D - LaTeX support', () {
    test('keyboard templates evaluate in every 3D expression type', () {
      final surface = Expression3D.surface(
        r'\sqrt[3]{\left|x\right|}+\left(y\right)!+\log_{2}\left(8\right)+\left\lfloor1.8\right\rfloor',
      );
      expect(surface.isValid, isTrue, reason: surface.parseError);
      expect(surface.evaluateSurface(-27, 3), closeTo(13, 1e-10));
      expect(surface.parameters, isEmpty);
      final negativeRoot = Expression3D.surface(r'\sqrt[3]{x}');
      expect(negativeRoot.evaluateSurface(-8, 0), closeTo(-2, 1e-10));
      final adjacentNumber = Expression3D.surface(
        r'\sqrt[3]{x}2+\left(y\right)!3',
      );
      expect(adjacentNumber.isValid, isTrue, reason: adjacentNumber.parseError);
      expect(adjacentNumber.evaluateSurface(8, 3), closeTo(22, 1e-10));
      final adjacent = Expression3D.surface(
        r'\pi x + \alpha y',
        parameterValues: {'alpha': 2},
      );
      expect(
        adjacent.evaluateSurface(2, 3),
        closeTo(2 * dart_math.pi + 6, 1e-10),
      );
      expect(adjacent.parameters, {'alpha'});
      final grouped = Expression3D.surface(
        r'\pi\left(x+1\right)+\alpha\left(y+1\right)',
        parameterValues: {'alpha': 2},
      );
      expect(grouped.isValid, isTrue, reason: grouped.parseError);
      expect(
        grouped.evaluateSurface(1, 2),
        closeTo(2 * dart_math.pi + 6, 1e-10),
      );
      final products = Expression3D.surface(
        r'\pi 2 + \alpha \beta \gamma',
        parameterValues: {'alpha': 2, 'beta': 3, 'gamma': 4},
      );
      expect(
        products.evaluateSurface(0, 0),
        closeTo(2 * dart_math.pi + 24, 1e-10),
      );
      final spacedCurve = Expression3D.parametricCurve(r'(t\,2,0,0)');
      expect(spacedCurve.isValid, isTrue, reason: spacedCurve.parseError);
      expect(spacedCurve.evaluateCurve(3).x, 6);

      final curve = Expression3D.parametricCurve(
        r'(\left|t\right|,\sqrt[3]{\left|t\right|},\left(3\right)!)',
      );
      expect(curve.isValid, isTrue, reason: curve.parseError);
      final point = curve.evaluateCurve(-27);
      expect(point.x, 27);
      expect(point.y, closeTo(3, 1e-10));
      expect(point.z, 6);
      expect(curve.parameters, isEmpty);

      final parametric = Expression3D.parametricSurface(
        r'(\left|u\right|,\sqrt[3]{v},\left(3\right)!)',
      );
      expect(parametric.isValid, isTrue, reason: parametric.parseError);
      final p = parametric.evaluateParametricSurface(-2, 27);
      expect(p.x, 2);
      expect(p.y, closeTo(3, 1e-10));
      expect(p.z, 6);
      expect(parametric.parameters, isEmpty);

      expect(Expression3D.surface(r'\sqrt[3]{').isValid, isFalse);
      expect(Expression3D.parametricCurve(r'(\left|t,0,0)').isValid, isFalse);
    });

    test('LaTeX commands work in surface expressions', () {
      final expr = Expression3D.surface(r'\sin(x) \times \cos(y)');
      expect(expr.isValid, isTrue);
      expect(expr.evaluateSurface(0, 0), closeTo(0, 1e-10));
    });

    test('frac works in surface expressions', () {
      final expr = Expression3D.surface(r'\frac{x}{y}');
      expect(expr.isValid, isTrue);
      expect(expr.evaluateSurface(4, 2), closeTo(2, 1e-10));
    });
  });

  group('Expression3D - parameters', () {
    test(
      'uppercase independent variable names remain adjustable parameters',
      () {
        final surface = Expression3D.surface('X+x+Y+y');
        expect(surface.parameters, {'X', 'Y'});
        expect(surface.evaluateSurface(2, 3), 7);
        expect(
          surface.withParameters({'X': 4, 'Y': 5}).evaluateSurface(2, 3),
          14,
        );

        final curve = Expression3D.parametricCurve('(T+t, t, 0)');
        expect(curve.parameters, {'T'});
        expect(curve.evaluateCurve(2).x, 3);
        expect(curve.withParameters({'T': 4}).evaluateCurve(2).x, 6);

        final parametric = Expression3D.parametricSurface('(U+u, V+v, 0)');
        expect(parametric.parameters, {'U', 'V'});
        expect(parametric.evaluateParametricSurface(2, 3).x, 3);
        final point = parametric
            .withParameters({'U': 4, 'V': 5})
            .evaluateParametricSurface(2, 3);
        expect(point.x, 6);
        expect(point.y, 8);
      },
    );

    test('extracts parameters from surface expression', () {
      final expr = Expression3D.surface('a*x^2 + b*y^2');
      expect(expr.parameters, contains('a'));
      expect(expr.parameters, contains('b'));
      expect(expr.parameters, isNot(contains('x')));
      expect(expr.parameters, isNot(contains('y')));
    });

    test('evaluates surface with parameters', () {
      final expr = Expression3D.surface(
        'a*x^2 + b*y^2',
        parameterValues: {'a': 2, 'b': 3},
      );
      expect(expr.isValid, isTrue);
      // 2*1^2 + 3*2^2 = 2 + 12 = 14
      expect(expr.evaluateSurface(1, 2), closeTo(14, 1e-10));
    });

    test('withParameters creates updated evaluator', () {
      final expr = Expression3D.surface('a*x^2', parameterValues: {'a': 1});
      final updated = expr.withParameters({'a': 5});
      expect(updated.evaluateSurface(2, 0), closeTo(20, 1e-10));
    });
  });
}
