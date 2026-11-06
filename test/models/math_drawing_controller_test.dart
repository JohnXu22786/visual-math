import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  test('snapshot collections cannot be mutated by the host', () {
    final parsed = MathExpression.fromInput('a * x');
    final vertices = <Point3D>[
      const Point3D(0, 0, 0),
      const Point3D(1, 0, 0),
      const Point3D(0, 1, 0),
    ];
    final snapshot = MathDrawingSnapshot(
      formulas: [
        FormulaEntry(rawExpression: 'a * x', parsed: parsed),
      ],
      parameters: const {},
      activeView: ViewMode.mode2D,
      activeTool: ConstructionTool.move,
      viewport2D: Viewport.defaultViewport(),
      camera3D: const Camera3D(),
      projection3D: ProjectionType.parallel,
      scene3D: [
        Object3D.surface(vertices: vertices, indices: [0, 1, 2]),
      ],
    );

    expect(snapshot.version, MathDrawingSnapshot.currentVersion);
    expect(() => snapshot.formulas.add(
      const FormulaEntry(rawExpression: 'x'),
    ), throwsUnsupportedError);
    expect(() => snapshot.parameters['a'] = MathParameter(),
        throwsUnsupportedError);
    expect(() => snapshot.scene3D.clear(), throwsUnsupportedError);
    vertices.add(const Point3D(1, 1, 0));
    expect(snapshot.scene3D.single.vertices, hasLength(3));
    expect(
      () => snapshot.scene3D.single.vertices.clear(),
      throwsUnsupportedError,
    );
    parsed.parameters.add('changed');
    expect(
      snapshot.formulas.single.parsed!.parameters,
      isNot(contains('changed')),
    );
    expect(
      () => snapshot.formulas.single.parsed!.parameters.add('other'),
      throwsUnsupportedError,
    );
  });

  testWidgets('scene changes do not report a viewport change', (tester) async {
    final controller = MathDrawingController();
    final sceneChanges = <List<Object3D>>[];
    final viewportChanges = <MathDrawingSnapshot>[];
    controller.onSceneChanged = sceneChanges.add;
    controller.onViewportChanged = viewportChanges.add;
    await tester.pumpWidget(MaterialApp(
      home: MathDrawingPage(
        controller: controller,
        initialShowWebView: false,
        initialMathematicalMode: false,
      ),
    ));
    await tester.pumpAndSettle();

    controller.setScene3D([const Object3D.point(Point3D(1, 2, 3))]);
    await tester.pumpAndSettle();

    expect(sceneChanges, hasLength(1));
    expect(viewportChanges, isEmpty);
  });

  testWidgets('controller commands update the attached page snapshot', (
    tester,
  ) async {
    final controller = MathDrawingController();
    MathDrawingSnapshot? plotted;
    controller.onPlotted = (snapshot) => plotted = snapshot;
    await tester.pumpWidget(MaterialApp(
      home: MathDrawingPage(
        controller: controller,
        initialShowWebView: false,
        initialMathematicalMode: false,
      ),
    ));
    await tester.pumpAndSettle();

    controller.setFormulas(const [
      FormulaEntry(rawExpression: 'x^2'),
    ]);
    controller.setViewport2D(
      const Viewport(xMin: -4, yMin: -3, xMax: 4, yMax: 3),
    );
    await tester.pumpAndSettle();
    await controller.plot();

    expect(controller.formulas.single.rawExpression, 'x^2');
    expect(controller.viewport2D.xMin, -4);
    expect(controller.viewport2D.yMax, 3);
    expect(plotted?.formulas.single.rawExpression, 'x^2');
    await tester.pumpAndSettle();

    final savedSnapshot = controller.snapshot!;
    await tester.pumpWidget(const SizedBox.shrink());
    final restoredController = MathDrawingController()..restore(savedSnapshot);
    await tester.pumpWidget(MaterialApp(
      home: MathDrawingPage(
        controller: restoredController,
        initialShowWebView: false,
        initialMathematicalMode: false,
      ),
    ));
    await tester.pumpAndSettle();
    expect(restoredController.formulas.single.rawExpression, 'x^2');
    expect(restoredController.viewport2D.xMin, -4);
    expect(restoredController.viewport2D.yMax, 3);
  });

  testWidgets('formula edits and plotting errors reach host callbacks', (
    tester,
  ) async {
    final controller = MathDrawingController();
    final edits = <String>[];
    final errors = <String>[];
    controller.onFormulaEdited = (_, expression) => edits.add(expression);
    controller.onError = errors.add;
    await tester.pumpWidget(MaterialApp(
      home: MathDrawingPage(
        controller: controller,
        initialExpression: 'x',
        initialShowWebView: false,
        initialMathematicalMode: false,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'x +');
    await tester.pumpAndSettle();
    await controller.plot();

    expect(edits, isNotEmpty);
    expect(edits.last, 'x +');
    expect(errors, isNotEmpty);
  });

  testWidgets('adding a formula row updates the controller snapshot', (
    tester,
  ) async {
    final controller = MathDrawingController();
    await tester.pumpWidget(MaterialApp(
      home: MathDrawingPage(
        controller: controller,
        initialShowWebView: false,
        initialMathematicalMode: false,
      ),
    ));
    await tester.pumpAndSettle();
    expect(controller.formulas, hasLength(1));

    await tester.tap(find.byTooltip('添加公式'));
    await tester.pumpAndSettle();

    expect(controller.formulas, hasLength(2));
  });

  testWidgets('snapshot restore preserves formula visibility', (tester) async {
    final controller = MathDrawingController();
    await tester.pumpWidget(MaterialApp(
      home: MathDrawingPage(
        controller: controller,
        initialShowWebView: false,
        initialMathematicalMode: false,
      ),
    ));
    await tester.pumpAndSettle();
    controller.setFormulas(const [
      FormulaEntry(rawExpression: 'x^2', visible: false),
    ]);
    final savedSnapshot = controller.snapshot!;
    await tester.pumpWidget(const SizedBox.shrink());

    final restoredController = MathDrawingController()..restore(savedSnapshot);
    await tester.pumpWidget(MaterialApp(
      home: MathDrawingPage(
        controller: restoredController,
        initialShowWebView: false,
        initialMathematicalMode: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(restoredController.formulas.single.visible, isFalse);
  });
}
