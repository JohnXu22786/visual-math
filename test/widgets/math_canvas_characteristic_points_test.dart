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
    await tester.tap(find.text('特征点'));
    await tester.pumpAndSettle();
  }

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
  });

  testWidgets('domain interval delimiters and endpoint math keyboard work', (
    tester,
  ) async {
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
    expect(tester.takeException(), isNull);
  });
}
