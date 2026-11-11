import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';
import 'package:visual_math_example/main.dart';

class MemoryStorage extends MathDrawingStorage {
  MemoryStorage(this.document);
  MathDrawingDocument document;

  @override
  Future<void> save(MathDrawingDocument value, {bool overwrite = false}) async {
    if (!overwrite && value.name == document.name) {
      throw DuplicateDrawingException(value.name);
    }
    document = value;
  }

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
      extensions: const {
        'vendor': {'setting': 42},
      },
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
    final storage = MemoryStorage(document);
    await tester.pumpWidget(
      MaterialApp(home: ExampleMenu(documentStorage: storage)),
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
    await tester.tap(find.byTooltip('保存绘图'));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Saved graph',
    );
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('覆盖'));
    await tester.pump();
    expect(storage.document.extensions, {
      'vendor': {'setting': 42},
    });
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
