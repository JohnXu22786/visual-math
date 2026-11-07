import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  Widget app(GlobalKey<MathCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 640, height: 480, child: MathCanvas(key: key)),
    ),
  );

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('视图设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('特征点显示'));
    await tester.pumpAndSettle();
  }

  testWidgets('initial expressions receive enabled characteristic markers', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 480,
            child: MathCanvas(key: key, initialExpression: 'x^2'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final kinds = key.currentState!.characteristicPointsForTesting
        .map((point) => point.$3)
        .toSet();
    expect(kinds, isNotEmpty);
  });

  testWidgets('explicit extrema are refined between curve samples', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvasState>();
    await tester.pumpWidget(app(key));
    await tester.pumpAndSettle();
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '(x-2)^2-3',
        parsed: MathExpression.fromInput('(x-2)^2-3'),
        color: Colors.blue,
        identity: 'precision-minimum',
      ),
    ]);
    await tester.pumpAndSettle();
    final minimum = key.currentState!.characteristicPointsForTesting
        .where((point) => point.$3 == '极值点')
        .single;
    expect(minimum.$1, closeTo(2, 1e-5));
    expect(minimum.$2, closeTo(-3, 1e-5));
  });

  testWidgets('small curve values do not underflow marker sign checks', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvasState>();
    await tester.pumpWidget(app(key));
    await tester.pumpAndSettle();
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '1e-200*((x-0.03337041156840925)^2+1)',
        parsed: MathExpression.fromInput(
          '1e-200*((x-0.03337041156840925)^2+1)',
        ),
        color: Colors.blue,
        identity: 'small-positive-curve',
        domainMin: -30,
        domainMax: 30,
      ),
    ]);
    await tester.pumpAndSettle();

    final markers = key.currentState!.characteristicPointsForTesting;
    expect(markers.where((point) => point.$3 == 'X轴交点'), isEmpty);
    expect(
      markers.where((point) => point.$3 == '极值点').any(
        (point) => (point.$1 - 0.03337041156840925).abs() < 1e-6 &&
            point.$2 > 0,
      ),
      isTrue,
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '1e-200*(x-0.1234567)',
        parsed: MathExpression.fromInput('1e-200*(x-0.1234567)'),
        color: Colors.blue,
        identity: 'small-crossing',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'small-crossing-zero',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting
          .where((point) => point.$3 == '图像交点')
          .any((point) => (point.$1 - 0.1234567).abs() < 1e-5),
      isTrue,
    );
  });

  testWidgets('tiny coordinate tangency checks keep finite error bounds', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvasState>();
    await tester.pumpWidget(app(key));
    await tester.pumpAndSettle();
    await key.currentState!.setViewport(-1e-200, -1, 1e-200, 1);
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '1e300*x*x+1e-100',
        parsed: MathExpression.fromInput('1e300*x*x+1e-100'),
        color: Colors.blue,
        identity: 'tiny-coordinate-near-miss',
        domainMin: -1e-200,
        domainMax: 1e-200,
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'tiny-coordinate-zero',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == 'X轴交点' || point.$3 == '图像交点',
      ),
      isEmpty,
    );
  });

  testWidgets('tangent x-axis roots are found and near misses are rejected', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvasState>();
    await tester.pumpWidget(app(key));
    await tester.pumpAndSettle();
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '(x-0.023)^2',
        parsed: MathExpression.fromInput('(x-0.023)^2'),
        color: Colors.blue,
        identity: 'tangent-x-axis',
        domainMin: -3,
        domainMax: 3,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting
          .where((point) => point.$3 == 'X轴交点')
          .any((point) => (point.$1 - 0.023).abs() < 1e-6),
      isTrue,
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '(x-0.023)^2+0.000000000001',
        parsed: MathExpression.fromInput('(x-0.023)^2+0.000000000001'),
        color: Colors.red,
        identity: 'tangent-x-axis-near-miss',
        domainMin: -3,
        domainMax: 3,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == 'X轴交点',
      ),
      isEmpty,
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '1e20*(x-0.023)^2+1',
        parsed: MathExpression.fromInput('1e20*(x-0.023)^2+1'),
        color: Colors.green,
        identity: 'large-scale-tangent-near-miss',
        domainMin: -3,
        domainMax: 3,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == 'X轴交点',
      ),
      isEmpty,
    );
  });

  testWidgets('implicit contour intersections scale with the viewport', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvasState>();
    await tester.pumpWidget(app(key));
    await tester.pumpAndSettle();
    await key.currentState!.setViewport(-1e-9, -1e-9, 1e-9, 1e-9);
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x+y=0',
        parsed: MathExpression.fromInput('x+y=0'),
        color: Colors.blue,
        identity: 'small-scale-contour-one',
      ),
      FormulaEntry(
        rawExpression: 'x-y=0',
        parsed: MathExpression.fromInput('x-y=0'),
        color: Colors.red,
        identity: 'small-scale-contour-two',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting
          .where((point) => point.$3 == '图像交点')
          .any((point) => point.$1.abs() < 1e-10 && point.$2.abs() < 1e-10),
      isTrue,
    );
  });

  testWidgets('per-formula category filters and global tri-state work', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvasState>();
    await tester.pumpWidget(app(key));
    await tester.pumpAndSettle();
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x^2-4*x+3',
        parsed: MathExpression.fromInput('x^2-4*x+3'),
        color: Colors.blue,
        identity: 'first',
      ),
      FormulaEntry(
        rawExpression: '-(x-2)^2+3',
        parsed: MathExpression.fromInput('-(x-2)^2+3'),
        color: Colors.red,
        identity: 'second',
      ),
    ]);
    await tester.pumpAndSettle();

    for (final category in ['极值点', 'X轴交点', 'Y轴交点']) {
      key.currentState!.setFormulaCharacteristicForTesting(
        'second',
        category,
        false,
      );
    }
    await tester.pumpAndSettle();

    final markers = key.currentState!.characteristicPointsForTesting;
    final extrema = markers.where((point) => point.$3 == '极值点').toList();
    final xCrossings = markers.where((point) => point.$3 == 'X轴交点').toList();
    final yCrossings = markers.where((point) => point.$3 == 'Y轴交点').toList();
    expect(extrema, hasLength(1));
    expect(extrema.single.$4, Colors.blue);
    expect(xCrossings, hasLength(2));
    expect(xCrossings.every((point) => point.$4 == Colors.blue), isTrue);
    expect(yCrossings, hasLength(1));
    expect(yCrossings.single.$4, Colors.blue);

    await openSettings(tester);
    final globalTiles = find
        .byType(CheckboxListTile)
        .evaluate()
        .map((element) => element.widget as CheckboxListTile)
        .take(4)
        .toList();
    expect(globalTiles.map((tile) => tile.value), [null, null, null, true]);

    // Tapping a partially-selected global category enables it for every row.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == '极值点',
      ),
      hasLength(2),
    );
    expect(
      (find.byType(CheckboxListTile).evaluate().first.widget
              as CheckboxListTile)
          .value,
      isTrue,
    );

    // Tapping a fully-selected global category turns it off for every row.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == '极值点',
      ),
      isEmpty,
    );
    expect(
      (find.byType(CheckboxListTile).evaluate().first.widget
              as CheckboxListTile)
          .value,
      isFalse,
    );

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x^2',
        parsed: MathExpression.fromInput('x^2'),
        color: Colors.blue,
      ),
      FormulaEntry(
        rawExpression: 'x^2',
        parsed: MathExpression.fromInput('x^2'),
        color: Colors.blue,
      ),
    ]);
    await tester.pumpAndSettle();
    final formulaIds = key.currentState!.formulaIdentitiesForTesting;
    expect(formulaIds, hasLength(2));
    expect(formulaIds[0], isNot(formulaIds[1]));
    key.currentState!.setFormulaCharacteristicForTesting(
      formulaIds.first,
      '极值点',
      false,
    );
    await tester.pumpAndSettle();
    await openSettings(tester);
    final categoryTiles = find
        .byType(CheckboxListTile)
        .evaluate()
        .map((element) => element.widget as CheckboxListTile)
        .toList();
    expect(categoryTiles.first.value, isNull);
  });

  testWidgets('pair intersections use either formula switch and deduplicate', (
    tester,
  ) async {
    final key = GlobalKey<MathCanvasState>();
    await tester.pumpWidget(app(key));
    await tester.pumpAndSettle();
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'a',
      ),
      FormulaEntry(
        rawExpression: '2*x+1',
        parsed: MathExpression.fromInput('2*x+1'),
        color: Colors.red,
        identity: 'b',
      ),
      FormulaEntry(
        rawExpression: '-x-2',
        parsed: MathExpression.fromInput('-x-2'),
        color: Colors.green,
        identity: 'c',
      ),
    ]);
    await tester.pumpAndSettle();
    key.currentState!.setFormulaCharacteristicForTesting('b', '图像交点', false);
    key.currentState!.setFormulaCharacteristicForTesting('c', '图像交点', false);
    await tester.pumpAndSettle();

    final pairMarkers = key.currentState!.characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .where(
          (point) => (point.$1 + 1).abs() < 1e-3 && (point.$2 + 1).abs() < 1e-3,
        )
        .toList();
    expect(pairMarkers, hasLength(1));
    expect(pairMarkers.single.$4, Colors.blue);

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'first-nearby-root',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'shared-zero-line',
      ),
      FormulaEntry(
        rawExpression: 'x-0.00000000000005',
        parsed: MathExpression.fromInput('x-0.00000000000005'),
        color: Colors.green,
        identity: 'second-nearby-root',
      ),
    ]);
    await tester.pumpAndSettle();
    final nearbyPairRoots = key.currentState!.characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .where((point) => point.$1.abs() < 1e-12)
        .toList();
    expect(nearbyPairRoots, hasLength(2));

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'first-subfemto-root',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'subfemto-zero-line',
      ),
      FormulaEntry(
        rawExpression: 'x-0.0000000000000005',
        parsed: MathExpression.fromInput('x-0.0000000000000005'),
        color: Colors.green,
        identity: 'second-subfemto-root',
      ),
    ]);
    await tester.pumpAndSettle();
    final subfemtoPairRoots = key.currentState!.characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .where((point) => point.$1.abs() < 1e-12)
        .toList();
    expect(subfemtoPairRoots, hasLength(2));

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x^2-2',
        parsed: MathExpression.fromInput('x^2-2'),
        color: Colors.blue,
        identity: 'irrational-roots',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'irrational-roots-zero',
      ),
    ]);
    await tester.pumpAndSettle();
    final irrationalRoots = key.currentState!.characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .toList();
    expect(irrationalRoots, hasLength(2));
    expect(
      irrationalRoots.any(
        (point) => (point.$1 - 1.4142135623730951).abs() < 1e-12,
      ),
      isTrue,
    );
    expect(
      irrationalRoots.any(
        (point) => (point.$1 + 1.4142135623730951).abs() < 1e-12,
      ),
      isTrue,
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'axis-first',
      ),
      FormulaEntry(
        rawExpression: '2*x',
        parsed: MathExpression.fromInput('2*x'),
        color: Colors.green,
        identity: 'axis-second',
      ),
    ]);
    await tester.pumpAndSettle();
    key.currentState!.setFormulaCharacteristicForTesting(
      'axis-first',
      '图像交点',
      false,
    );
    await tester.pumpAndSettle();

    final axisIntersection = key.currentState!.characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .where((point) => point.$1.abs() < 1e-3 && point.$2.abs() < 1e-3)
        .toList();
    expect(axisIntersection, hasLength(1));
    expect(axisIntersection.single.$4, Colors.green);

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'left-domain',
        domainMax: 1,
      ),
      FormulaEntry(
        rawExpression: '2*x-1',
        parsed: MathExpression.fromInput('2*x-1'),
        color: Colors.red,
        identity: 'right-domain',
        domainMin: 1,
      ),
    ]);
    await tester.pumpAndSettle();
    final sharedEndpoint = key.currentState!.characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .where((point) => (point.$1 - 1).abs() < 1e-3)
        .toList();
    expect(sharedEndpoint, hasLength(1));
    expect(sharedEndpoint.single.$2, closeTo(1, 1e-3));

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '(x-0.1234567)^2',
        parsed: MathExpression.fromInput('(x-0.1234567)^2'),
        color: Colors.blue,
        identity: 'tangent-one',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'tangent-zero',
      ),
      FormulaEntry(
        rawExpression: '2*(x-0.1234567)^2',
        parsed: MathExpression.fromInput('2*(x-0.1234567)^2'),
        color: Colors.green,
        identity: 'tangent-two',
      ),
    ]);
    await tester.pumpAndSettle();
    final sharedTangency = key.currentState!.characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .where((point) => (point.$1 - 0.1234567).abs() < 1e-4)
        .toList();
    expect(sharedTangency, hasLength(1));

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '1e20*(x-0.1234567)^2+1',
        parsed: MathExpression.fromInput('1e20*(x-0.1234567)^2+1'),
        color: Colors.blue,
        identity: 'large-scale-pair-near-miss',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'large-scale-pair-zero',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == '图像交点',
      ),
      isEmpty,
    );

    await key.currentState!.setViewport(
      1e12 - 10,
      -60,
      1e12 + 110,
      60,
    );
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.blue,
        identity: 'large-open-domain',
        domainMin: 1e12,
        domainMax: 1e12 + 100,
        includeDomainMin: false,
      ),
      FormulaEntry(
        rawExpression: 'x-1000000000050',
        parsed: MathExpression.fromInput('x-1000000000050'),
        color: Colors.red,
        identity: 'large-domain-crossing',
        domainMin: 1e12,
        domainMax: 1e12 + 100,
      ),
    ]);
    await tester.pumpAndSettle();
    final interiorLargeIntersection = key.currentState!
        .characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .where((point) => (point.$1 - (1e12 + 50)).abs() < 1e-3)
        .toList();
    expect(interiorLargeIntersection, hasLength(1));

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.blue,
        identity: 'large-near-open-domain',
        domainMin: 1e12,
        domainMax: 1e12 + 100,
        includeDomainMin: false,
      ),
      FormulaEntry(
        rawExpression: 'x-1000000000000.0005',
        parsed: MathExpression.fromInput('x-1000000000000.0005'),
        color: Colors.red,
        identity: 'near-open-crossing',
        domainMin: 1e12,
        domainMax: 1e12 + 100,
      ),
    ]);
    await tester.pumpAndSettle();
    final nearOpenIntersection = key.currentState!.characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .where((point) => (point.$1 - (1e12 + 0.0005)).abs() < 1e-3)
        .toList();
    expect(nearOpenIntersection, hasLength(1));

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x-1000000000000',
        parsed: MathExpression.fromInput('x-1000000000000'),
        color: Colors.blue,
        identity: 'large-open-root',
        domainMin: 1e12,
        domainMax: 1e12 + 100,
        includeDomainMin: false,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == 'X轴交点',
      ),
      isEmpty,
    );
    expect(key.currentState!.curvePoints, isNotEmpty);
    expect(
      key.currentState!.curvePoints.every((point) => point['x']! > 1e12),
      isTrue,
    );

    const narrowOpenMax = 1e12 + 0.00048828125;
    await key.currentState!.setViewport(
      1e12 - 0.001,
      -1,
      narrowOpenMax + 0.001,
      1,
    );
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'narrow-open-domain',
        domainMin: 1e12,
        domainMax: narrowOpenMax,
        includeDomainMin: false,
        includeDomainMax: false,
      ),
    ]);
    await tester.pumpAndSettle();
    final narrowOpenPoints = key.currentState!.curvePoints;
    expect(narrowOpenPoints, isNotEmpty);
    expect(
      narrowOpenPoints.every(
        (point) => point['x']! > 1e12 && point['x']! < narrowOpenMax,
      ),
      isTrue,
    );
    expect(
      narrowOpenPoints.map((point) => point['x']).toSet().length,
      greaterThanOrEqualTo(2),
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'invalid-domain',
        domainMinExpression: '1/p',
      ),
      FormulaEntry(
        rawExpression: '2*x',
        parsed: MathExpression.fromInput('2*x'),
        color: Colors.red,
        identity: 'valid-domain',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == '图像交点',
      ),
      isEmpty,
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'empty-domain',
        domainMin: 1,
        domainMax: 1,
      ),
      FormulaEntry(
        rawExpression: '1',
        parsed: MathExpression.fromInput('1'),
        color: Colors.red,
        identity: 'empty-domain-crossing',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == '图像交点',
      ),
      isEmpty,
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'coincident-a',
      ),
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.red,
        identity: 'coincident-b',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == '图像交点',
      ),
      isEmpty,
    );

    await key.currentState!.setViewport(
      -500,
      1e12 - 500,
      500,
      1e12 + 500,
    );
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '1000000000000',
        parsed: MathExpression.fromInput('1000000000000'),
        color: Colors.blue,
        identity: 'high-constant-a',
      ),
      FormulaEntry(
        rawExpression: '1000000000100',
        parsed: MathExpression.fromInput('1000000000100'),
        color: Colors.red,
        identity: 'high-constant-b',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == '图像交点',
      ),
      isEmpty,
    );

    await key.currentState!.setViewport(-1e13, -1e13, 1e13, 1e13);
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '1/(x-0.1234567)',
        parsed: MathExpression.fromInput('1/(x-0.1234567)'),
        color: Colors.blue,
        identity: 'vertical-asymptote',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'asymptote-zero',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == '图像交点',
      ),
      isEmpty,
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        color: Colors.blue,
        identity: 'wide-root-line',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'wide-root-zero',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting
          .where((point) => point.$3 == '图像交点')
          .any((point) => point.$1.abs() < 1e-6 && point.$2.abs() < 1e-6),
      isTrue,
    );

    await key.currentState!.setViewport(-2, -1, 2, 1);
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x^2+0.00000000001',
        parsed: MathExpression.fromInput('x^2+0.00000000001'),
        color: Colors.blue,
        identity: 'near-miss',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'near-miss-zero',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting.where(
        (point) => point.$3 == '图像交点',
      ),
      isEmpty,
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: 'x^2',
        parsed: MathExpression.fromInput('x^2'),
        color: Colors.blue,
        identity: 'tangent',
      ),
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.red,
        identity: 'tangent-zero',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting
          .where((point) => point.$3 == '图像交点')
          .any((point) => point.$1.abs() < 1e-6 && point.$2.abs() < 1e-6),
      isTrue,
    );

    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.blue,
        identity: 'small-tangent-zero',
      ),
      FormulaEntry(
        rawExpression: '1e-14*(x-1.234567)^2',
        parsed: MathExpression.fromInput('1e-14*(x-1.234567)^2'),
        color: Colors.red,
        identity: 'small-tangent',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.characteristicPointsForTesting
          .where((point) => point.$3 == '图像交点')
          .any((point) => (point.$1 - 1.234567).abs() < 1e-4),
      isTrue,
    );

    await key.currentState!.setViewport(-0.001, -0.001, 0.002, 0.001);
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.blue,
        identity: 'close-roots-zero',
        domainMin: 0,
        domainMax: 0.001,
      ),
      FormulaEntry(
        rawExpression: 'x*(x-0.0005)',
        parsed: MathExpression.fromInput('x*(x-0.0005)'),
        color: Colors.red,
        identity: 'close-roots-quadratic',
        domainMin: 0,
        domainMax: 0.001,
      ),
    ]);
    await tester.pumpAndSettle();
    final closeIntersections = key.currentState!
        .characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .toList();
    expect(closeIntersections, hasLength(2));
    expect((closeIntersections[0].$1 - closeIntersections[1].$1).abs(),
        greaterThan(0.0004));

    await key.currentState!.setViewport(-1e-9, -1e-9, 2e-9, 1e-9);
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.blue,
        identity: 'subnano-zero',
        domainMin: 0,
        domainMax: 1e-9,
      ),
      FormulaEntry(
        rawExpression: 'x*(x-0.0000000005)',
        parsed: MathExpression.fromInput('x*(x-0.0000000005)'),
        color: Colors.red,
        identity: 'subnano-quadratic',
        domainMin: 0,
        domainMax: 1e-9,
      ),
    ]);
    await tester.pumpAndSettle();
    final subnanoIntersections = key.currentState!
        .characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .toList();
    expect(subnanoIntersections, hasLength(2));
    expect(
      (subnanoIntersections[0].$1 - subnanoIntersections[1].$1).abs(),
      greaterThan(4e-10),
    );

    await key.currentState!.setViewport(-1e-13, -1e-10, 1e-12, 1e-10);
    await key.currentState!.setFormulas([
      FormulaEntry(
        rawExpression: '0',
        parsed: MathExpression.fromInput('0'),
        color: Colors.blue,
        identity: 'ulps-close-zero',
        domainMin: 0,
        domainMax: 1e-12,
      ),
      FormulaEntry(
        rawExpression: '1e15*x*(x-5e-14)',
        parsed: MathExpression.fromInput('1e15*x*(x-5e-14)'),
        color: Colors.red,
        identity: 'ulps-close-roots',
        domainMin: 0,
        domainMax: 1e-12,
      ),
    ]);
    await tester.pumpAndSettle();
    final ulpsCloseIntersections = key.currentState!
        .characteristicPointsForTesting
        .where((point) => point.$3 == '图像交点')
        .toList();
    expect(ulpsCloseIntersections, hasLength(2));
    expect(
      (ulpsCloseIntersections[0].$1 - ulpsCloseIntersections[1].$1).abs(),
      greaterThan(4e-14),
    );
  });

  testWidgets('domain interval delimiters and endpoint math keyboard work', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(
        home: MathDrawingPage(
          initialExpression: 'x',
          initialMathematicalMode: false,
          initialShowWebView: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置定义域'));
    await tester.pumpAndSettle();

    expect(find.text('数学键盘输入'), findsOneWidget);
    expect(find.text('点击括号切换开闭区间。'), findsOneWidget);
    expect(find.text('['), findsOneWidget);
    expect(find.text(']'), findsOneWidget);
    expect(find.text('−∞'), findsOneWidget);
    expect(find.text('+∞'), findsOneWidget);
    await tester.tap(find.text('['));
    await tester.pumpAndSettle();
    expect(find.text('('), findsOneWidget);
    await tester.tap(find.text(']'));
    await tester.pumpAndSettle();
    expect(find.text(')'), findsOneWidget);

    await tester.tap(find.text('数学键盘输入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开端点数学键盘'));
    await tester.pumpAndSettle();
    expect(find.byType(MathKeyboard), findsOneWidget);
    expect(find.text('常用'), findsOneWidget);
    expect(find.byTooltip('收起数学键盘'), findsOneWidget);
    expect(find.byTooltip('光标左移'), findsOneWidget);
    expect(find.byTooltip('光标上移 / 切换上层'), findsOneWidget);
    expect(find.text('绘图'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(480, 640);
    await tester.pumpAndSettle();
    expect(find.byType(MathKeyboard), findsOneWidget);
    expect(find.text('常用'), findsOneWidget);
    expect(find.byTooltip('收起数学键盘'), findsOneWidget);
    expect(find.byTooltip('光标左移'), findsOneWidget);
    expect(find.text('绘图'), findsOneWidget);
    final lastRowKey = find.byTooltip('⌫');
    await tester.ensureVisible(lastRowKey);
    await tester.pumpAndSettle();
    final keyboardRect = tester.getRect(find.byType(MathKeyboard));
    final keyRect = tester.getRect(lastRowKey);
    expect(keyRect.top, greaterThanOrEqualTo(keyboardRect.top));
    expect(keyRect.bottom, lessThanOrEqualTo(keyboardRect.bottom));
    await tester.tap(lastRowKey);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('应用'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('应用')).bottom, lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
  });
}
