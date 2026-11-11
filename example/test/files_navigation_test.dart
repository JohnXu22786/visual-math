import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';
import 'package:visual_math_example/main.dart';

class MemoryStorage extends MathDrawingStorage {
  MemoryStorage(this.document);
  final MathDrawingDocument document;

  @override
  Future<List<String>> listNames() async => [document.name];

  @override
  Future<MathDrawingDocument?> load(String name) async => document;
}

void main() {
  testWidgets('Files navigation opens the saved drawing with its state', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final document = MathDrawingDocument(
      name: 'Saved graph',
      drawing: MathDrawingSnapshot(
        formulas: const [FormulaEntry(rawExpression: 'x^2')],
        parameters: const {},
        activeView: ViewMode.mode2D,
        activeTool: ConstructionTool.move,
        viewport2D: const Viewport(xMin: -4, yMin: -3, xMax: 4, yMax: 3),
        camera3D: const Camera3D(),
        projection3D: ProjectionType.parallel,
        scene3D: const [],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: ExampleMenu(documentStorage: MemoryStorage(document))),
    );
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Saved graph'), findsOneWidget);
    await tester.tap(find.text('Saved graph'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final page = tester.widget<MathDrawingPage>(find.byType(MathDrawingPage));
    expect(page.controller!.snapshot!.formulas.single.rawExpression, 'x^2');
    expect(page.controller!.snapshot!.viewport2D.xMin, -4);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
