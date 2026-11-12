import 'package:flutter/material.dart' hide Viewport;
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
      throw DuplicateDrawingException(document.name);
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

    storage.documents['Quadratic'] = MathDrawingDocument(
      name: 'Quadratic',
      drawing: storage.documents['Quadratic']!.drawing,
      extensions: const {
        'vendor': {'flag': true},
      },
    );
    await tester.tap(find.byTooltip('打开绘图'));
    await _pumpWorkspace(tester);
    expect(find.text('Quadratic'), findsOneWidget);
    await tester.tap(find.text('Quadratic'));
    await _pumpWorkspace(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('保存绘图'));
    await _pumpWorkspace(tester);
    await tester.enterText(find.byType(TextField), 'Quadratic');
    await tester.tap(find.text('继续'));
    await _pumpWorkspace(tester);
    await tester.tap(find.text('覆盖'));
    await _pumpWorkspace(tester);
    expect(storage.documents['Quadratic']!.extensions, {
      'vendor': {'flag': true},
    });

    await tester.tap(find.byTooltip('添加公式'));
    await _pumpWorkspace(tester);
    await tester.tap(find.byTooltip('保存绘图'));
    await _pumpWorkspace(tester);
    await tester.enterText(find.byType(TextField), 'Quadratic updated');
    await tester.tap(find.text('继续'));
    await _pumpWorkspace(tester);
    final updated = storage.documents['Quadratic updated'];
    expect(updated!.extensions, {
      'vendor': {'flag': true},
    });
    final ids = updated.drawing.formulas.map((formula) => formula.id).toSet();
    expect(ids.length, updated.drawing.formulas.length);
  });

  testWidgets('saving preserves the unavailable view of an opened document', (
    tester,
  ) async {
    for (final show2D in [true, false]) {
      final drawing = MathDrawingSnapshot(
        formulas: [],
        parameters: {},
        activeView: ViewMode.mode2D,
        activeTool: ConstructionTool.move,
        viewport2D: const Viewport(xMin: -3, yMin: -4, xMax: 5, yMax: 6),
        camera3D: const Camera3D(target: Point3D(1, 2, 3), distance: 17),
        projection3D: ProjectionType.perspective,
        showAxes2D: false,
        showGrid2D: false,
        showZeros2D: true,
        showExtrema2D: true,
        showAxes3D: false,
        showPlane3D: false,
        showGrid3D: true,
        showLabels3D: false,
        scene3D: [
          Object3D.point(const Point3D(1, 2, 3)).copyWith(documentId: 'p'),
          Object3D.sphere(
            center: const Point3D(0, 0, 0),
            radius: 3,
          ).copyWith(documentId: 's'),
        ],
        pointAttachments3D: const [
          PointAttachment(pointId: 'p', targetId: 's'),
        ],
        constructionDependencies3D: [
          ConstructionDependency(
            objectId: 's',
            tool: ConstructionTool.tetrahedron,
            inputPoints: const [Point3D(1, 2, 3)],
            sourcePointIds: const ['p'],
            workingPlaneNormal: Vector3D.unitZ,
            polygonSides: 5,
          ),
        ],
      );
      final storage = _MemoryDrawingStorage()
        ..documents['Original'] = MathDrawingDocument(
          name: 'Original',
          drawing: drawing,
        );
      await tester.pumpWidget(
        MaterialApp(
          home: MathDrawingPage(
            initialMathematicalMode: false,
            initialShowWebView: false,
            documentStorage: storage,
            options: MathWorkspaceOptions(
              show2D: show2D,
              show3D: !show2D,
              initialView: show2D ? ViewMode.mode2D : ViewMode.mode3D,
              showFormulaEditor: false,
              showKeyboard: false,
            ),
          ),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(find.byTooltip('打开绘图'));
      await _pumpWorkspace(tester);
      await tester.tap(find.text('Original'));
      await _pumpWorkspace(tester);
      await tester.tap(find.byTooltip('保存绘图'));
      await _pumpWorkspace(tester);
      await tester.enterText(find.byType(TextField), 'Saved');
      await tester.tap(find.text('继续'));
      await _pumpWorkspace(tester);
      final saved =
          storage.documents['Saved']!.toJson()['drawing']
              as Map<String, dynamic>;
      final original =
          storage.documents['Original']!.toJson()['drawing']
              as Map<String, dynamic>;
      expect(
        saved[show2D ? 'view3D' : 'view2D'],
        original[show2D ? 'view3D' : 'view2D'],
      );
      await tester.pumpWidget(const SizedBox());
    }
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
