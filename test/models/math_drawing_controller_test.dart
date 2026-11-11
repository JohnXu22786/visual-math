import 'package:flutter/material.dart' hide Viewport;
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
      formulas: [FormulaEntry(rawExpression: 'a * x', parsed: parsed)],
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
    expect(
      () => snapshot.formulas.add(const FormulaEntry(rawExpression: 'x')),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.parameters['a'] = MathParameter(),
      throwsUnsupportedError,
    );
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
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialShowWebView: false,
          initialMathematicalMode: false,
        ),
      ),
    );
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
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialShowWebView: false,
          initialMathematicalMode: false,
          options: const MathWorkspaceOptions(show3D: true, show3DTools: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.setFormulas(const [FormulaEntry(rawExpression: 'x^2')]);
    controller.setViewport2D(
      const Viewport(xMin: -4, yMin: -3, xMax: 4, yMax: 3),
    );
    controller.setActiveView(ViewMode.mode3D);
    controller.setActiveTool(ConstructionTool.regularPolygon);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9').last);
    await tester.pumpAndSettle();
    expect(controller.snapshot?.polygonSides3D, 9);
    await controller.plot();

    expect(controller.formulas.single.rawExpression, 'x^2');
    expect(controller.viewport2D.xMin, -4);
    expect(controller.viewport2D.yMax, 3);
    expect(plotted?.formulas.single.rawExpression, 'x^2');
    await tester.pumpAndSettle();

    final savedSnapshot = controller.snapshot!;
    await tester.pumpWidget(const SizedBox.shrink());
    final restoredController = MathDrawingController()..restore(savedSnapshot);
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: restoredController,
          initialShowWebView: false,
          initialMathematicalMode: false,
          options: const MathWorkspaceOptions(show3D: true, show3DTools: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(restoredController.formulas.single.rawExpression, 'x^2');
    expect(restoredController.viewport2D.xMin, -4);
    expect(restoredController.viewport2D.yMax, 3);
    expect(restoredController.snapshot?.polygonSides3D, 9);
    expect(
      tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).value,
      9,
    );
  });

  testWidgets('formula edits and plotting errors reach host callbacks', (
    tester,
  ) async {
    final controller = MathDrawingController();
    final edits = <String>[];
    final errors = <String>[];
    controller.onFormulaEdited = (_, expression) => edits.add(expression);
    controller.onError = errors.add;
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialExpression: 'x',
          initialShowWebView: false,
          initialMathematicalMode: false,
        ),
      ),
    );
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
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialShowWebView: false,
          initialMathematicalMode: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.formulas, hasLength(1));

    await tester.tap(find.byTooltip('添加公式'));
    await tester.pumpAndSettle();

    expect(controller.formulas, hasLength(2));
  });

  testWidgets('snapshot restore preserves formula visibility', (tester) async {
    final controller = MathDrawingController();
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialShowWebView: false,
          initialMathematicalMode: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.setFormulas(const [
      FormulaEntry(rawExpression: 'x^2', visible: false),
    ]);
    final savedSnapshot = controller.snapshot!;
    await tester.pumpWidget(const SizedBox.shrink());

    final restoredController = MathDrawingController()..restore(savedSnapshot);
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: restoredController,
          initialShowWebView: false,
          initialMathematicalMode: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(restoredController.formulas.single.visible, isFalse);
  });

  testWidgets('restoring a 3D drawing replaces the offstage 2D plot', (
    tester,
  ) async {
    final controller = MathDrawingController();
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialShowWebView: false,
          initialMathematicalMode: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.setFormulas([
      FormulaEntry(
        rawExpression: 'x^2',
        parsed: MathExpression.fromInput('x^2'),
      ),
    ]);
    await controller.plot();
    await tester.pump();

    controller.restore(
      MathDrawingSnapshot(
        formulas: [
          FormulaEntry(id: 'restored-formula', rawExpression: 'x + 5'),
        ],
        parameters: const {},
        activeView: ViewMode.mode3D,
        activeTool: ConstructionTool.move,
        viewport2D: Viewport.defaultViewport(),
        camera3D: const Camera3D(),
        projection3D: ProjectionType.parallel,
        scene3D: const [],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.activeView, ViewMode.mode3D);
    final canvas = tester.state<MathCanvasState>(
      find.byType(MathCanvas, skipOffstage: false),
    );
    expect(canvas.curvePoints, isNotEmpty);
    expect(
      canvas.curvePoints.every(
        (point) => (point['y']! - point['x']! - 5).abs() < 1e-8,
      ),
      isTrue,
    );
  });

  testWidgets('domain-only expressions use and follow shared parameters', (
    tester,
  ) async {
    final controller = MathDrawingController();
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialShowWebView: false,
          initialMathematicalMode: false,
          options: const MathWorkspaceOptions(
            show3D: false,
            showFormulaEditor: false,
            showKeyboard: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.setParameters({
      'a': MathParameter(value: 2, min: 0, max: 6, step: 1),
    });
    controller.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        domainStartExpression: 'a',
        domainEndExpression: 'a + 1',
      ),
    ]);
    await controller.plot();
    await tester.pump();

    final canvas = tester.state<MathCanvasState>(find.byType(MathCanvas));
    void expectDomain(double start, double end) {
      final xs = canvas.curvePoints.map((point) => point['x']!);
      expect(xs, isNotEmpty);
      expect(xs.every((x) => x >= start && x <= end), isTrue);
    }

    expectDomain(2, 3);
    controller.setParameters({
      'a': MathParameter(value: 4, min: 0, max: 6, step: 1),
    });
    await tester.pump();
    expectDomain(4, 5);
  });
  testWidgets('invalid parameterized bounds hide curves until valid again', (
    tester,
  ) async {
    final controller = MathDrawingController();
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialShowWebView: false,
          initialMathematicalMode: false,
          options: const MathWorkspaceOptions(
            show3D: false,
            showFormulaEditor: false,
            showKeyboard: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    void setA(double value) => controller.setParameters({
      'a': MathParameter(value: value, min: -2, max: 2, step: 1),
    });
    setA(1);
    controller.setFormulas([
      FormulaEntry(
        rawExpression: 'x',
        parsed: MathExpression.fromInput('x'),
        domainStartExpression: 'sqrt(a)',
      ),
    ]);
    await controller.plot();
    await tester.pump();
    final canvas = tester.state<MathCanvasState>(find.byType(MathCanvas));
    expect(canvas.curvePoints, isNotEmpty);
    expect(canvas.curvePoints.every((point) => point['x']! >= 1), isTrue);

    setA(-1);
    await tester.pump();
    expect(canvas.curvePoints, isEmpty);

    setA(1);
    await tester.pump();
    expect(canvas.curvePoints, isNotEmpty);
    expect(canvas.curvePoints.every((point) => point['x']! >= 1), isTrue);
  });
}
