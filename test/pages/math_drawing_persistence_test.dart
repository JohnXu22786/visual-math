import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

class _MemoryDrawingStorage extends MathDrawingStorage {
  final Map<String, MathDrawingDocument> documents = {};
  Object? listFailure;
  Object? saveFailure;

  @override
  Future<List<String>> listNames() async {
    if (listFailure case final failure?) throw failure;
    return documents.keys.toList()..sort();
  }

  @override
  Future<MathDrawingDocument?> load(String name) async => documents[name];

  @override
  Future<void> save(
    MathDrawingDocument document, {
    bool overwrite = false,
  }) async {
    if (saveFailure case final failure?) throw failure;
    if (documents.containsKey(document.name) && !overwrite) {
      throw StateError('A document with this name already exists.');
    }
    documents[document.name] = document;
  }
}

Future<void> _pumpWorkspace(WidgetTester tester) async {
  // Keep pumping deterministic frames for the canvas' active animation ticker.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('saves a named drawing and reopens it from the Files list', (
    tester,
  ) async {
    final storage = _MemoryDrawingStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          initialExpression: 'x^2',
          initialMathematicalMode: false,
          initialShowWebView: false,
          documentStorage: storage,
          options: const MathWorkspaceOptions(
            show3D: false,
            showFormulaEditor: false,
            showKeyboard: false,
          ),
        ),
      ),
    );
    await _pumpWorkspace(tester);
    await tester.tap(find.byTooltip('保存绘图'));
    await _pumpWorkspace(tester);
    await tester.enterText(find.byType(TextField), 'Quadratic');
    await tester.tap(find.text('继续'));
    await _pumpWorkspace(tester);
    expect(
      storage.documents['Quadratic']!.drawing.formulas.single.rawExpression,
      'x^2',
    );

    await tester.tap(find.byTooltip('打开绘图'));
    await _pumpWorkspace(tester);
    expect(find.text('Quadratic'), findsOneWidget);
    await tester.tap(find.text('Quadratic'));
    await _pumpWorkspace(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('添加公式'));
    await _pumpWorkspace(tester);
    await tester.tap(find.byTooltip('保存绘图'));
    await _pumpWorkspace(tester);
    await tester.enterText(find.byType(TextField), 'Quadratic updated');
    await tester.tap(find.text('继续'));
    await _pumpWorkspace(tester);
    final updated = storage.documents['Quadratic updated'];
    final ids = updated!.drawing.formulas.map((formula) => formula.id).toSet();
    expect(ids.length, updated.drawing.formulas.length);
  });

  testWidgets('shows storage errors when saving and listing fail', (
    tester,
  ) async {
    final storage = _MemoryDrawingStorage()
      ..saveFailure = Exception('disk unavailable')
      ..listFailure = Exception('storage unavailable');
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          initialMathematicalMode: false,
          initialShowWebView: false,
          documentStorage: storage,
          options: const MathWorkspaceOptions(
            show3D: false,
            showFormulaEditor: false,
            showKeyboard: false,
          ),
        ),
      ),
    );
    await _pumpWorkspace(tester);
    await tester.tap(find.byTooltip('保存绘图'));
    await _pumpWorkspace(tester);
    await tester.enterText(find.byType(TextField), 'Unavailable');
    await tester.tap(find.text('继续'));
    await _pumpWorkspace(tester);
    expect(find.textContaining('无法保存绘图'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2100));
    await tester.tap(find.byTooltip('打开绘图'));
    await _pumpWorkspace(tester);
    expect(find.textContaining('无法读取绘图列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
