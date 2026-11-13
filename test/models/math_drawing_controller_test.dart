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
      formulas: [
        FormulaEntry(
          rawExpression: 'a * x',
          parsed: parsed,
          hiddenPlot3D: Object3D.surface(
            vertices: vertices,
            indices: [0, 1, 2],
          ),
        ),
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
    expect(snapshot.formulas.single.hiddenPlot3D!.vertices, hasLength(3));
    expect(
      () => snapshot.formulas.single.hiddenPlot3D!.vertices.clear(),
      throwsUnsupportedError,
    );
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

    // Initial canvas layout can publish its aspect-corrected viewport.
    viewportChanges.clear();
    controller.setScene3D([const Object3D.point(Point3D(1, 2, 3))]);
    await tester.pumpAndSettle();

    expect(sceneChanges, hasLength(1));
    expect(viewportChanges, isEmpty);
  });

  testWidgets('attached controller publishes construction relationships', (
    tester,
  ) async {
    final controller = MathDrawingController();
    final published = <MathDrawingSnapshot>[];
    controller.onSceneChanged = (_) => published.add(controller.snapshot!);
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
    controller.setActiveView(ViewMode.mode3D);
    const first = Point3D(-2, 0, 0);
    const second = Point3D(-1, 0, 0);
    controller.setScene3D([
      const Object3D.point(first),
      const Object3D.point(second),
    ]);
    controller.setActiveTool(ConstructionTool.tetrahedron);
    await tester.pumpAndSettle();
    final finder = find.byType(MathCanvas3D);
    final state = tester.state<MathCanvas3DState>(finder);
    final box = tester.renderObject<RenderBox>(finder);
    final projection = Projection3D.parallel(
      width: box.size.width,
      height: box.size.height,
      scale: state.camera.distance * 0.6,
    );
    Offset screen(Point3D point) {
      final p = worldToScreen(point, state.camera, projection);
      return box.localToGlobal(Offset(p.x, p.y));
    }

    await tester.tapAt(screen(first));
    await tester.pump();
    await tester.tapAt(screen(second));
    await tester.pump();
    expect(controller.snapshot!.constructionDependencies3D, hasLength(1));
    expect(published.last.constructionDependencies3D, hasLength(1));
    final decoded = MathDrawingDocument.decode(
      MathDrawingDocument(name: '3D', drawing: controller.snapshot!).encode(),
    );
    expect(decoded.drawing.constructionDependencies3D, hasLength(1));
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

    final canvasSize = tester.getSize(find.byType(MathCanvas));
    final expectedYMax = 4 * canvasSize.height / canvasSize.width;
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
    expect(controller.viewport2D.yMax, closeTo(expectedYMax, 1e-9));
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
    expect(restoredController.viewport2D.yMax, closeTo(expectedYMax, 1e-9));
    expect(restoredController.snapshot?.polygonSides3D, 9);
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .value,
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

  testWidgets('auto colors continue cycling after the palette is exhausted', (
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
      for (final color in formulaPalette)
        FormulaEntry(rawExpression: '', color: color),
    ]);
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('添加公式'));
      await tester.pumpAndSettle();
      expect(controller.formulas.last.color, formulaPalette[i]);
    }
    final formulas = controller.formulas.toList()..removeAt(10);
    controller.setFormulas(formulas);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加公式'));
    await tester.pumpAndSettle();
    expect(controller.formulas.last.color, formulaPalette[3]);
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
  testWidgets('shared 3D updates retain parameterized LaTeX bounds', (
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
    controller.setParameters({
      'a': MathParameter(value: 2, min: 0, max: 6, step: 1),
    });
    controller.setFormulas([
      FormulaEntry(
        rawExpression: 'a*x',
        domainStartExpression: r'\frac{a}{2}',
        domainEndExpression: 'a+1',
      ),
    ]);
    await controller.plot();
    await tester.pumpAndSettle();
    final canvas2d = tester.state<MathCanvasState>(find.byType(MathCanvas));
    void checkBounds(double low, double high) {
      final xs = canvas2d.curvePoints.map((p) => p['x']!);
      expect(xs, isNotEmpty);
      expect(xs.every((x) => x >= low && x <= high), isTrue);
    }

    checkBounds(1, 3);
    controller.setActiveView(ViewMode.mode3D);
    await tester.pumpAndSettle();
    await controller.plot();
    await tester.pumpAndSettle();
    final canvas3d = tester.state<MathCanvas3DState>(find.byType(MathCanvas3D));
    Object3D plot() =>
        canvas3d.objects.singleWhere((o) => o.formulaRowId != null);
    controller.setParameters({
      'a': MathParameter(value: 4, min: 0, max: 6, step: 1),
    });
    await tester.pumpAndSettle();
    checkBounds(2, 5);
    final p = plot().vertices.first;
    expect(p.z, closeTo(4 * p.x, 1e-8));
    final restored = MathDrawingDocument.decode(
      MathDrawingDocument(
        name: 'bounds',
        drawing: controller.snapshot!,
      ).encode(),
    ).drawing;
    expect(restored.formulas.single.domainStartExpression, r'\frac{a}{2}');
    expect(restored.formulas.single.domainEndExpression, 'a+1');
    expect(restored.parameters['a']!.value, 4);
    expect(
      restored.scene3D
          .singleWhere((o) => o.formulaRowId != null)
          .vertices
          .first
          .z,
      closeTo(p.z, 1e-8),
    );
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
  testWidgets('coordinate-dependent domain bounds report an error', (
    tester,
  ) async {
    final controller = MathDrawingController();
    String? error;
    controller.onError = (message) => error = message;
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
    for (final bound in ['x+1', r'\frac{y}{2}']) {
      error = null;
      controller.setFormulas([
        FormulaEntry(rawExpression: 'x', domainStartExpression: bound),
      ]);
      await controller.plot();
      await tester.pump();
      expect(error, contains('定义域表达式无效'));
      expect(controller.snapshot!.formulas.first.domainStartExpression, bound);
    }
  });
}
