import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offscreen axes keep fallback tick labels inside the canvas', () {
    const size = Size(200, 200);
    final narrow = TestRecordingCanvas();
    const GraphPainter(
      xMin: 1000000000,
      xMax: 1000000020,
      yMin: 1000000000,
      yMax: 1000000020,
    ).paint(narrow, const Size(50, 50));
    for (final record in narrow.invocations) {
      final call = record.invocation;
      if (call.memberName != #drawParagraph) continue;
      final paragraph = call.positionalArguments[0] as ui.Paragraph;
      final offset = call.positionalArguments[1] as Offset;
      expect(offset.dx + paragraph.longestLine, lessThanOrEqualTo(50));
      expect(offset.dy + paragraph.height, lessThanOrEqualTo(50));
    }
    final mixed = TestRecordingCanvas();
    const GraphPainter(
      xMin: -10,
      xMax: 10,
      yMin: 1000001,
      yMax: 1000021,
    ).paint(mixed, size);
    final mixedBounds = <Rect>[];
    for (final record in mixed.invocations) {
      final call = record.invocation;
      if (call.memberName != #drawParagraph) continue;
      final paragraph = call.positionalArguments[0] as ui.Paragraph;
      final offset = call.positionalArguments[1] as Offset;
      final bounds = offset & Size(paragraph.longestLine, paragraph.height);
      expect(mixedBounds.any(bounds.overlaps), isFalse);
      mixedBounds.add(bounds);
    }
    for (final xMin in [-30.0, 10.0]) {
      for (final yMin in [-30.0, 10.0]) {
        final painter = GraphPainter(
          xMin: xMin,
          xMax: xMin + 20,
          yMin: yMin,
          yMax: yMin + 20,
          showGrid: false,
        );
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, size);
        expect(
          canvas.invocations.where(
            (record) => record.invocation.memberName == #drawLine,
          ),
          isEmpty,
        );
        final labels = canvas.invocations
            .map((record) => record.invocation)
            .where((call) => call.memberName == #drawParagraph)
            .toList();
        expect(labels, isNotEmpty);
        final bounds = <Rect>[];
        for (final label in labels) {
          final paragraph = label.positionalArguments[0] as ui.Paragraph;
          final offset = label.positionalArguments[1] as Offset;
          expect(offset.dx, greaterThanOrEqualTo(0));
          expect(offset.dy, greaterThanOrEqualTo(0));
          expect(
            offset.dx + paragraph.longestLine,
            lessThanOrEqualTo(size.width),
          );
          expect(offset.dy + paragraph.height, lessThanOrEqualTo(size.height));
          final rect = offset & Size(paragraph.longestLine, paragraph.height);
          expect(bounds.any(rect.overlaps), isFalse);
          bounds.add(rect);
        }
      }
    }
  });

  group('GraphPainter - shouldRepaint', () {
    test('returns false when nothing changes', () {
      final painter1 = const GraphPainter(
        xMin: -10,
        yMin: -10,
        xMax: 10,
        yMax: 10,
      );
      final painter2 = const GraphPainter(
        xMin: -10,
        yMin: -10,
        xMax: 10,
        yMax: 10,
      );
      expect(painter1.shouldRepaint(painter2), isFalse);
    });

    test('returns true when viewport changes', () {
      final painter1 = const GraphPainter(
        xMin: -10,
        yMin: -10,
        xMax: 10,
        yMax: 10,
      );
      final painter2 = const GraphPainter(
        xMin: -20,
        yMin: -10,
        xMax: 20,
        yMax: 10,
      );
      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('returns true when curves change', () {
      final painter1 = const GraphPainter(
        xMin: -10,
        yMin: -10,
        xMax: 10,
        yMax: 10,
        curves: [
          [
            {'x': 0.0, 'y': 0.0},
          ],
        ],
      );
      final painter2 = const GraphPainter(
        xMin: -10,
        yMin: -10,
        xMax: 10,
        yMax: 10,
      );
      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('returns true when colors change', () {
      final painter1 = const GraphPainter(
        xMin: -10,
        yMin: -10,
        xMax: 10,
        yMax: 10,
        gridColor: Colors.grey,
      );
      final painter2 = const GraphPainter(
        xMin: -10,
        yMin: -10,
        xMax: 10,
        yMax: 10,
        gridColor: Colors.blue,
      );
      expect(painter1.shouldRepaint(painter2), isTrue);
    });
  });

  testWidgets(
    'zero markers include touching roots but exclude nearby extrema',
    (tester) async {
      final key = GlobalKey<MathCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MathCanvas(key: key)),
        ),
      );
      await tester.pump();
      key.currentState!.setDisplaySettings(
        showAxes: true,
        showGrid: true,
        showZeros: true,
        showExtrema: false,
      );
      Future<List<(double, double, Color)>> zeros(String expression) async {
        await key.currentState!.setExpression(expression, null);
        await tester.pump();
        return tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<GraphPainter>()
            .single
            .characteristicPoints;
      }

      for (final expression in ['x^2', '-(x-1.23)^2']) {
        final points = await zeros(expression);
        expect(points, hasLength(1), reason: expression);
        expect(points.single.$1, closeTo(expression == 'x^2' ? 0 : 1.23, 1e-5));
      }
      expect(await zeros('(x-1.23)^2+0.0001'), isEmpty);
      expect(await zeros('(x-1.23)^2+0.000000000000001'), isEmpty);
      expect(await zeros('(x-1.23)^2+1e-30'), isEmpty);
      expect(await zeros('(x-1.23)^2+1e-100'), isEmpty);
      expect(await zeros('abs(x-1.23)+1e-16'), isEmpty);
      expect(await zeros('-(x-1.23)^2-1e-100'), isEmpty);
      expect((await zeros('x')).single.$1, closeTo(0, 1e-5));
    },
  );

  group('MathCanvas - initial state', () {
    testWidgets('canvas is ready callback fires', (tester) async {
      bool ready = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(onReady: () => ready = true),
            ),
          ),
        ),
      );
      await tester.pump();
      // The ready callback fires after first frame via addPostFrameCallback
      await tester.pump();
      expect(ready, isTrue);
    });
  });

  group('MathCanvas - expression handling', () {
    testWidgets('setExpression renders a valid function', (tester) async {
      final key = GlobalKey<MathCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      await key.currentState!.setExpression('x^2', null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Should have sampled points
      final points = key.currentState!.curvePoints;
      expect(points.length, greaterThan(0));
    });

    testWidgets('setExpression with parameters works', (tester) async {
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      await key.currentState!.setExpression('a*x^2', {'a': 2});
      await tester.pump();

      final points = key.currentState!.curvePoints;
      expect(points.length, greaterThan(0));
    });

    testWidgets('setFormulas with multiple formulas works', (tester) async {
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      // Set two formulas
      final parsed1 = MathExpression.fromInput('x^2');
      final parsed2 = MathExpression.fromInput('x');
      await key.currentState!.setFormulas([
        FormulaEntry(
          rawExpression: 'x^2',
          parsed: parsed1,
          color: Colors.blue,
          autoColor: true,
        ),
        FormulaEntry(
          rawExpression: 'x',
          parsed: parsed2,
          color: Colors.red,
          autoColor: true,
        ),
      ]);
      await tester.pump();

      // Should have points from both expressions
      expect(key.currentState!.curvePoints.length, greaterThanOrEqualTo(2));
    });

    testWidgets('domain expressions clip curves and exclude open endpoints', (
      tester,
    ) async {
      final key = GlobalKey<MathCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();
      await key.currentState!.setViewport(-2, -2, 2, 2);
      await key.currentState!.setFormulas([
        FormulaEntry(
          rawExpression: 'x',
          parsed: MathExpression.fromInput('x'),
          domainStartExpression: '-1',
          domainEndExpression: '1',
          includeDomainStart: false,
          includeDomainEnd: false,
        ),
      ]);

      final xs = key.currentState!.curvePoints.map((point) => point['x']!);
      expect(xs, isNotEmpty);
      expect(xs.every((x) => x > -1 && x < 1), isTrue);
    });

    testWidgets('implicit open domains keep clipped contour segments intact', (
      tester,
    ) async {
      final key = GlobalKey<MathCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();
      await key.currentState!.setViewport(-2, -2, 2, 2);
      await key.currentState!.setFormulas([
        FormulaEntry(
          rawExpression: 'x^2+y^2=1',
          parsed: MathExpression.fromInput('x^2+y^2=1'),
          domainStartExpression: '0',
          domainEndExpression: '1',
          includeDomainStart: false,
          includeDomainEnd: false,
        ),
      ]);

      final segments = key.currentState!.curveSegments;
      expect(segments, isNotEmpty);
      expect(segments.every((segment) => segment.length >= 2), isTrue);
      expect(
        segments
            .expand((segment) => segment)
            .every((point) => point['x']! > 0 && point['x']! < 1),
        isTrue,
      );
    });
  });

  group('MathCanvas - viewport', () {
    testWidgets('setViewport ignores invalid bounds', (tester) async {
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      await key.currentState!.setViewport(10, -10, -10, 10);
      // Viewport should not change (xMax <= xMin)
      final vp = key.currentState!.viewport;
      expect(vp.$1, closeTo(-10, 1e-10));
    });
  });

  group('MathCanvas - extended sampling margin', () {
    testWidgets(
      'explicit function sampling extends well beyond viewport bounds',
      (tester) async {
        final key = GlobalKey<MathCanvasState>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 300,
                child: MathCanvas(key: key),
              ),
            ),
          ),
        );
        await tester.pump();

        // Set a specific viewport
        await key.currentState!.setViewport(-5, -5, 5, 5);
        await tester.pump();

        // Set a simple linear formula
        await key.currentState!.setExpression('x', null);
        await tester.pump();

        final points = key.currentState!.curvePoints;
        expect(points.length, greaterThanOrEqualTo(2));

        // With 100% margin on each side, sampling range is [-15, 15].
        // The actual margin is 1.0 × (xMax - xMin) = 1.0 × 10 = 10.
        // Verify points extend well beyond the viewport bounds (-5, 5).
        final firstX = points.first['x']!;
        final lastX = points.last['x']!;
        expect(
          firstX,
          lessThanOrEqualTo(-7.0),
          reason:
              'First sampled x ($firstX) should extend ~100% beyond xMin=-5',
        );
        expect(
          lastX,
          greaterThanOrEqualTo(7.0),
          reason: 'Last sampled x ($lastX) should extend ~100% beyond xMax=5',
        );
      },
    );

    testWidgets(
      'sampled point count scales proportionally with extended range',
      (tester) async {
        final key = GlobalKey<MathCanvasState>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 300,
                child: MathCanvas(key: key),
              ),
            ),
          ),
        );
        await tester.pump();

        // Set viewport [-10, 10] (default) — range = 20, margin = 20,
        // so sampling range = 60, scalePoints = 60/20 = 3.0.
        // numPoints = 300 * 3.0 = 900.
        await key.currentState!.setExpression('x', null);
        await tester.pump();

        final points = key.currentState!.curvePoints;
        // For f(x)=x over [-30, 30], all 900 points are finite.
        expect(
          points.length,
          greaterThanOrEqualTo(500),
          reason: 'With 3× range scaling, point count should be ~900, not the base 300',
        );
      },
    );

    testWidgets(
      'implicit equation sampling with extended bounds works correctly',
      (tester) async {
        final key = GlobalKey<MathCanvasState>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 300,
                child: MathCanvas(key: key),
              ),
            ),
          ),
        );
        await tester.pump();

        // Set viewport and an implicit equation whose contour extends
        // beyond the viewport (e.g., x^2 - y = 0 is a broad parabola).
        await key.currentState!.setViewport(-5, -5, 5, 5);
        await key.currentState!.setExpression('x^2-y=0', null);
        await tester.pump();

        final points = key.currentState!.curvePoints;
        // The implicit should produce contour segments
        expect(
          points.length,
          greaterThan(0),
          reason: 'Implicit equation should produce contour segments',
        );

        // Verify all points have finite coordinates (no NaN/infinity)
        for (final p in points) {
          expect(
            p['x']!.isFinite,
            isTrue,
            reason: 'All implicit segment x values should be finite',
          );
          expect(
            p['y']!.isFinite,
            isTrue,
            reason: 'All implicit segment y values should be finite',
          );
        }

        // With 100% margin (y bounds [-15, 15]), the parabola y=x^2 at x=±3
        // has y=9, which should be within the extended y bounds.
        // Verify y-values extend beyond the original viewport yMax=5.
        final ys = points.map((p) => p['y']!).toList();
        final maxY = ys.reduce((a, b) => a > b ? a : b);
        expect(
          maxY,
          greaterThan(5.0),
          reason:
              'Implicit contour y-values should extend beyond yMax=5 with extended bounds, got maxY=$maxY',
        );
      },
    );
  });

  group('MathCanvas - drag coverage', () {
    testWidgets('extended sampling range accommodates half-viewport pan', (
      tester,
    ) async {
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      // Set initial viewport [-10, -10, 10, 10] with a simple function
      await key.currentState!.setViewport(-10, -10, 10, 10);
      await key.currentState!.setExpression('x', null);
      await tester.pump();

      final points = key.currentState!.curvePoints;
      final xs = points.map((p) => p['x']!).toList()..sort();

      // With 100% margin (= 20 units on each side), sampling range is [-30, 30].
      // Verify the data extends well beyond the original viewport [-10, 10].
      expect(
        xs.first,
        lessThanOrEqualTo(-19.0),
        reason:
            'First sampled x (${xs.first}) should extend ~100% beyond viewport xMin=-10',
      );
      expect(
        xs.last,
        greaterThanOrEqualTo(19.0),
        reason:
            'Last sampled x (${xs.last}) should extend ~100% beyond viewport xMax=10',
      );

      // This confirms that if the user pans 50% of viewport width (from [-10,10]
      // to roughly [0,20]), the already-sampled data at [-30,30] still fully
      // covers the visible area — curves stay visible without needing a resample.
    });
  });

  group('MathCanvas - curve continuity', () {
    testWidgets('formula renders without gaps from boundary issues', (
      tester,
    ) async {
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      // Set a simple continuous function
      await key.currentState!.setExpression('x^2', null);
      await tester.pump();

      final points = key.currentState!.curvePoints;
      expect(points.length, greaterThan(0));

      // All points should have finite coordinates
      for (final p in points) {
        expect(p['x']!.isFinite, isTrue);
        expect(p['y']!.isFinite, isTrue);
      }
    });

    testWidgets('extreme zoom levels render without crash', (tester) async {
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      // Set a very tight viewport (deep zoom)
      await key.currentState!.setViewport(-0.1, -0.1, 0.1, 0.1);
      await key.currentState!.setExpression('x^2', null);
      await tester.pump();

      final points = key.currentState!.curvePoints;
      expect(points.length, greaterThan(0));
    });
  });

  group('MathCanvas - callbacks', () {
    testWidgets('onError fires for invalid expression', (tester) async {
      String? errorMsg;
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key, onError: (msg) => errorMsg = msg),
            ),
          ),
        ),
      );
      await tester.pump();

      await key.currentState!.setExpression('x ^^ 2', null);
      await tester.pump();

      // Should have fired error callback
      expect(errorMsg, isNot(isNull));
    });

    testWidgets('onViewportChange fires after resetView', (tester) async {
      bool viewportChanged = false;
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(
                key: key,
                onViewportChange: (_, __, ___, ____) => viewportChanged = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await key.currentState!.resetView();
      await tester.pump();

      expect(viewportChanged, isTrue);
    });
  });

  group('MathCanvas - multiple formulas (Bug 2: formula limit)', () {
    testWidgets('setFormulas with 8 explicit formulas produces data for all', (
      tester,
    ) async {
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      // Create 8 formula entries
      final formulas = <FormulaEntry>[];
      for (int i = 0; i < 8; i++) {
        final parsed = MathExpression.fromInput('${i + 1}x');
        formulas.add(
          FormulaEntry(
            rawExpression: '${i + 1}x',
            parsed: parsed,
            color: Colors.primaries[i % Colors.primaries.length],
          ),
        );
      }

      await key.currentState!.setFormulas(formulas);
      await tester.pump();

      final points = key.currentState!.curvePoints;
      for (var slope = 1; slope <= 8; slope++) {
        expect(
          points.any((point) {
            final x = point['x']!;
            return x.abs() > 1e-6 && ((point['y']! / x) - slope).abs() < 1e-9;
          }),
          isTrue,
          reason: 'y = ${slope}x should produce curve data',
        );
      }
    });

    testWidgets('setFormulas with 10 implicit formulas produces data for all', (
      tester,
    ) async {
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      // Create 10 different implicit formula entries
      final formulas = <FormulaEntry>[
        FormulaEntry(
          rawExpression: 'y^2=4x',
          parsed: MathExpression.fromInput('y^2=4x'),
          color: Colors.red,
        ),
        FormulaEntry(
          rawExpression: 'x^2+y^2=1',
          parsed: MathExpression.fromInput('x^2+y^2=1'),
          color: Colors.blue,
        ),
        FormulaEntry(
          rawExpression: 'x^2=y',
          parsed: MathExpression.fromInput('x^2=y'),
          color: Colors.green,
        ),
        FormulaEntry(
          rawExpression: '4x=y^3',
          parsed: MathExpression.fromInput('4x=y^3'),
          color: Colors.orange,
        ),
        FormulaEntry(
          rawExpression: 'y=x^2+2',
          parsed: MathExpression.fromInput('y=x^2+2'),
          color: Colors.purple,
        ),
        FormulaEntry(
          rawExpression: 'x^2+2y^2=1',
          parsed: MathExpression.fromInput('x^2+2y^2=1'),
          color: Colors.teal,
        ),
        FormulaEntry(
          rawExpression: 'x^3=y',
          parsed: MathExpression.fromInput('x^3=y'),
          color: Colors.pink,
        ),
        FormulaEntry(
          rawExpression: 'x+y=2',
          parsed: MathExpression.fromInput('x+y=2'),
          color: Colors.indigo,
        ),
        FormulaEntry(
          rawExpression: 'x-y=1',
          parsed: MathExpression.fromInput('x-y=1'),
          color: Colors.cyan,
        ),
        FormulaEntry(
          rawExpression: 'y=x^3+2',
          parsed: MathExpression.fromInput('y=x^3+2'),
          color: Colors.amber,
        ),
      ];

      await key.currentState!.setFormulas(formulas);
      await tester.pump();

      final points = key.currentState!.curvePoints;
      const tolerance = 0.1;
      final expectedCurves = <bool Function(double, double)>[
        (x, y) => (y * y - 4 * x).abs() < tolerance,
        (x, y) => (x * x + y * y - 1).abs() < tolerance,
        (x, y) => (y - x * x).abs() < tolerance,
        (x, y) => (4 * x - y * y * y).abs() < tolerance,
        (x, y) => (y - x * x - 2).abs() < tolerance,
        (x, y) => (x * x + 2 * y * y - 1).abs() < tolerance,
        (x, y) => (y - x * x * x).abs() < tolerance,
        (x, y) => (x + y - 2).abs() < tolerance,
        (x, y) => (x - y - 1).abs() < tolerance,
        (x, y) => (y - x * x * x - 2).abs() < tolerance,
      ];
      for (final curve in expectedCurves) {
        expect(
          points.where((point) => curve(point['x']!, point['y']!)).length,
          greaterThan(10),
          reason: 'each submitted formula should contribute its own curve data',
        );
      }
    });

    testWidgets('setFormulas replaces old formulas completely', (tester) async {
      final key = GlobalKey<MathCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      // Set 3 formulas first
      await key.currentState!.setFormulas([
        FormulaEntry(
          rawExpression: 'x',
          parsed: MathExpression.fromInput('x'),
          color: Colors.red,
        ),
        FormulaEntry(
          rawExpression: 'x^2',
          parsed: MathExpression.fromInput('x^2'),
          color: Colors.blue,
        ),
        FormulaEntry(
          rawExpression: 'x^3',
          parsed: MathExpression.fromInput('x^3'),
          color: Colors.green,
        ),
      ]);
      await tester.pump();

      // Now replace with just 1 formula (simulating deletion)
      await key.currentState!.setFormulas([
        FormulaEntry(
          rawExpression: 'x^4',
          parsed: MathExpression.fromInput('x^4'),
          color: Colors.purple,
        ),
      ]);
      await tester.pump();

      final pointsAfter = key.currentState!.curvePoints;
      expect(
        pointsAfter.length,
        greaterThan(0),
        reason: 'Single replacement formula should produce curve data',
      );
      // Every returned point must belong to x^4; stale data from x, x^2, or
      // x^3 would violate this relation even when it contains large y values.
      expect(
        pointsAfter.every((point) {
          final x = point['x']!;
          final expectedY = math.pow(x, 4).toDouble();
          final tolerance = math.max(1, expectedY.abs()) * 1e-10;
          return (point['y']! - expectedY).abs() <= tolerance;
        }),
        isTrue,
        reason: 'replacing formulas should remove every point from old curves',
      );
    });
  });

  group('MathCanvas - pan tracks the finger 1:1', () {
    // The canvas will shift its viewport in math units by
    // fingerDelta * (xRange / canvasWidth) so the drawn graph moves
    // exactly as far on screen as the finger does.
    const canvasWidth = 400.0;
    const canvasHeight = 300.0;

    Future<(GlobalKey<MathCanvasState>, double)> pumpCanvas(
      WidgetTester tester,
    ) async {
      final key = GlobalKey<MathCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // Non-square canvas on purpose: the painter renders both
            // axes with the same pixels-per-unit scale (derived from
            // xRange / width), so the pan math must too.
            body: SizedBox(
              width: canvasWidth,
              height: canvasHeight,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      );
      await tester.pump();
      final vp = key.currentState!.viewport;
      return (key, vp.$3 - vp.$1);
    }

    testWidgets(
      'horizontal drag moves the graph exactly as far as the finger',
      (tester) async {
        final (key, xRange) = await pumpCanvas(tester);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(MathCanvas)),
        );
        await tester.pump();
        // Move well past the pan slop first so the scale recognizer accepts
        // the gesture and starts emitting updates; only the tracked move
        // below is measured.
        await gesture.moveBy(const Offset(150, 0));
        await tester.pump();

        final vp0 = key.currentState!.viewport;

        // Tracked move: exactly 30 logical pixels to the right.
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        final vp1 = key.currentState!.viewport;

        // 1:1 tracking: viewport shifts by 30 * (xRange / width) math units,
        // which renders as exactly 30 pixels of graph movement.
        final expectedShift = 30 * xRange / canvasWidth;
        expect(
          vp1.$1 - vp0.$1,
          closeTo(-expectedShift, 1e-9),
          reason: 'xMin should track the finger at 1x, not half speed',
        );
        expect(
          vp1.$3 - vp0.$3,
          closeTo(-expectedShift, 1e-9),
          reason: 'xMax should track the finger at 1x, not half speed',
        );
        // A pure horizontal drag must leave the y viewport untouched.
        expect(vp1.$2, closeTo(vp0.$2, 1e-9));
        expect(vp1.$4, closeTo(vp0.$4, 1e-9));

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets('vertical drag moves the graph exactly as far as the finger', (
      tester,
    ) async {
      final (key, xRange) = await pumpCanvas(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MathCanvas)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();

      final vp0 = key.currentState!.viewport;

      // Tracked move: exactly 30 logical pixels downward.
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      final vp1 = key.currentState!.viewport;

      // Dragging down moves the graph down, so yMin/yMax must increase.
      // The painter renders the y axis with the same pixels-per-unit
      // scale as the x axis (xRange / width), so the same conversion
      // applies here.
      final expectedShift = 30 * xRange / canvasWidth;
      expect(
        vp1.$2 - vp0.$2,
        closeTo(expectedShift, 1e-9),
        reason: 'yMin should track the finger at 1x on a non-square canvas',
      );
      expect(
        vp1.$4 - vp0.$4,
        closeTo(expectedShift, 1e-9),
        reason: 'yMax should track the finger at 1x on a non-square canvas',
      );
      // A pure vertical drag must leave the x viewport untouched.
      expect(vp1.$1, closeTo(vp0.$1, 1e-9));
      expect(vp1.$3, closeTo(vp0.$3, 1e-9));

      await gesture.up();
      await tester.pump();
    });
  });

  testWidgets('moving pinch keeps the original focal point under the fingers', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: MathCanvas(key: key),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final detector = tester.widget<GestureDetector>(
      find
          .descendant(
            of: find.byType(MathCanvas),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is GestureDetector && widget.onScaleUpdate != null,
            ),
          )
          .first,
    );
    final before = key.currentState!.viewport;
    const oldFocal = Offset(170, 120);
    const newFocal = Offset(210, 140);
    final oldX = before.$1 + oldFocal.dx / 400 * (before.$3 - before.$1);
    final oldY =
        (before.$2 + before.$4) / 2 +
        (150 - oldFocal.dy) / 400 * (before.$3 - before.$1);
    detector.onScaleStart!(ScaleStartDetails(localFocalPoint: oldFocal));
    detector.onScaleUpdate!(
      ScaleUpdateDetails(
        localFocalPoint: newFocal,
        scale: 1.5,
        pointerCount: 2,
      ),
    );
    final after = key.currentState!.viewport;
    final screenX = (oldX - after.$1) / (after.$3 - after.$1) * 400;
    final screenY =
        150 - (oldY - (after.$2 + after.$4) / 2) / (after.$3 - after.$1) * 400;
    expect(screenX, closeTo(newFocal.dx, 1e-9));
    expect(screenY, closeTo(newFocal.dy, 1e-9));
    expect(after.$3 - after.$1, closeTo((before.$3 - before.$1) / 1.5, 1e-9));
  });
}
