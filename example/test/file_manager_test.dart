import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';
import 'package:visual_math_example/main.dart';

class MemoryDrawings extends MathDrawingStorage {
  final Map<String, MathDrawingDocument> items = {};
  @override
  Future<List<String>> listNames() async => items.keys.toList()..sort();
  @override
  Future<MathDrawingDocument?> load(String name) async => items[name];
  @override
  Future<void> save(
    MathDrawingDocument document, {
    bool overwrite = false,
  }) async {
    if (!overwrite && items.containsKey(document.name))
      throw DuplicateDrawingException(document.name);
    items[document.name] = document;
  }

  @override
  Future<void> delete(String name) async {
    items.remove(name);
  }
}

MathDrawingDocument document(String name) => MathDrawingDocument(
  name: name,
  extensions: const {'example': 42},
  drawing: MathDrawingSnapshot(
    formulas: const [FormulaEntry(rawExpression: 'x^2')],
    parameters: const {},
    activeView: ViewMode.mode2D,
    activeTool: ConstructionTool.move,
    viewport2D: Viewport.defaultViewport(),
    camera3D: const Camera3D(),
    projection3D: ProjectionType.parallel,
    scene3D: const [],
  ),
);

void main() {
  testWidgets('search, grid, copy and multi-delete use saved documents', (
    tester,
  ) async {
    final storage = MemoryDrawings()
      ..items.addAll({'Alpha': document('Alpha'), 'Beta': document('Beta')});
    await tester.pumpWidget(
      MaterialApp(home: ExampleMenu(documentStorage: storage)),
    );
    await tester.tap(find.text('文件').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'Beta');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is Text && w.data == 'Beta'), findsOneWidget);
    await tester.enterText(find.byType(SearchBar), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('网格视图'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.byTooltip('文件操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(storage.items['Alpha 副本']?.extensions, {'example': 42});
    expect(
      storage.items['Alpha 副本']?.drawing.formulas.single.rawExpression,
      'x^2',
    );
    await tester.longPress(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除所选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(storage.items, isEmpty);
    expect(find.text('还没有保存的绘图'), findsWidgets);
  });
}
