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
    expect(tester.takeException(), isNull);
  });
}
