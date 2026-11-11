import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('saves a named drawing and reopens it from the Files list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: MathDrawingPage(
          initialExpression: 'x^2',
          initialMathematicalMode: false,
          initialShowWebView: false,
          options: MathWorkspaceOptions(
            show3D: false,
            showFormulaEditor: false,
            showKeyboard: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('保存绘图'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Quadratic');
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(
      (await const MathDrawingStorage().load('Quadratic'))!
          .drawing
          .formulas
          .single
          .rawExpression,
      'x^2',
    );

    await tester.tap(find.byTooltip('打开绘图'));
    await tester.pumpAndSettle();
    expect(find.text('Quadratic'), findsOneWidget);
    await tester.tap(find.text('Quadratic'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('添加公式'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('保存绘图'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Quadratic updated');
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    final updated = await const MathDrawingStorage().load('Quadratic updated');
    final ids = updated!.drawing.formulas.map((formula) => formula.id).toSet();
    expect(ids.length, updated.drawing.formulas.length);
  });
}
