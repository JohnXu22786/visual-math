import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

Widget _buildTestApp({
  String? initialExpression,
  MathDrawingController? controller,
}) {
  return MaterialApp(
    home: MathDrawingPage(
      initialExpression: initialExpression,
      controller: controller,
      initialMathematicalMode: false,
      initialShowWebView: false,
    ),
    localizationsDelegates: const [
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  editorInteractionTests();

  group('MathDrawingPage - toolbar controls', () {
    testWidgets('add action moves to app bar and keeps graph fit control', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      final addButton = find.byTooltip('添加公式');
      expect(addButton, findsOneWidget);
      expect(
        find.ancestor(of: addButton, matching: find.byType(AppBar)),
        findsOneWidget,
      );
      expect(find.byTooltip('重置视图'), findsNothing);
      expect(find.byTooltip('缩放至适合'), findsOneWidget);

      await tester.tap(addButton);
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });

  group('MathDrawingPage - adjustable parameters', () {
    MathCanvasState canvas(WidgetTester tester) =>
        tester.state<MathCanvasState>(find.byType(MathCanvas));
    MathParameterControls controls(WidgetTester tester) => tester
        .widget<MathParameterControls>(find.byType(MathParameterControls));

    testWidgets(
      'shared sliders update committed curves without submitting drafts',
      (tester) async {
        await tester.pumpWidget(_buildTestApp(initialExpression: 'A*x'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('添加公式'));
        await tester.pump();
        await tester.enterText(find.byType(TextField).at(1), '2*A*x');
        await tester.tap(find.byTooltip('绘制').first);
        await tester.pumpAndSettle();
        expect(controls(tester).parameters.keys, ['A']);
        final original = canvas(tester).curvePoints;
        expect(original, isNotEmpty);

        await tester.enterText(find.byType(TextField).first, 'A*x+100');
        controls(tester)
            .onChanged('A', controls(tester).parameters['A']!.withValue(3));
        await tester.pump();
        final updated = canvas(tester).curvePoints;
        expect(updated.length, original.length);
        for (var i = 0; i < updated.length; i += 37) {
          expect(updated[i]['y'], closeTo(original[i]['y']! * 3, 1e-9));
        }
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'A*x+100',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '3D plots use and follow shared parameters without plotting drafts',
      (tester) async {
        final controller = MathDrawingController();
        await tester.pumpWidget(
          _buildTestApp(initialExpression: 'A*x', controller: controller),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('绘制'));
        await tester.pumpAndSettle();
        controls(tester)
            .onChanged('A', controls(tester).parameters['A']!.withValue(2));
        await tester.pump();
        await tester.tap(find.text('3D'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('绘制'));
        await tester.pumpAndSettle();
        final canvas3d = tester.state<MathCanvas3DState>(
          find.byType(MathCanvas3D),
        );
        Object3D plot() =>
            canvas3d.objects.singleWhere((o) => o.formulaRowId != null);
        final id = plot().documentId;
        expect(
          plot().vertices.first.z,
          closeTo(2 * plot().vertices.first.x, 1e-8),
        );
        await tester.enterText(find.byType(TextField), 'A*x+100');
        controls(tester)
            .onChanged('A', controls(tester).parameters['A']!.withValue(3));
        await tester.pump();
        expect(plot().documentId, id);
        expect(plot().label, 'A*x');
        expect(
          plot().vertices.first.z,
          closeTo(3 * plot().vertices.first.x, 1e-8),
        );
        final reopened = MathDrawingDocument.decode(
          MathDrawingDocument(
            name: 'plot',
            drawing: controller.snapshot!,
          ).encode(),
        );
        expect(
          reopened.drawing.scene3D
              .singleWhere((o) => o.documentId == id)
              .vertices
              .first
              .z,
          closeTo(plot().vertices.first.z, 1e-8),
        );
      },
    );

    testWidgets('3D-only parametric curves follow their parameter', (
      tester,
    ) async {
      final controller = MathDrawingController();
      await tester.pumpWidget(_buildTestApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '(1/(A-1), t, 0)');
      await tester.pump();
      await tester.tap(find.byTooltip('绘制'));
      await tester.pumpAndSettle();
      final canvas3d = tester.state<MathCanvas3DState>(
        find.byType(MathCanvas3D),
      );
      Object3D plot() =>
          canvas3d.objects.singleWhere((o) => o.formulaRowId != null);
      expect(controls(tester).parameters.keys, contains('A'));
      controls(tester)
          .onChanged('A', controls(tester).parameters['A']!.withValue(2));
      await tester.pump();
      expect(plot().vertices.last.x, closeTo(1, 1e-8));
      await tester.enterText(find.byType(TextField), '(1/A, t, 0)');
      await tester.pump();
      await tester.tap(find.byTooltip('绘制'));
      await tester.pumpAndSettle();
      final id = plot().documentId;
      controls(tester)
          .onChanged('A', controls(tester).parameters['A']!.withValue(0));
      await tester.pump();
      expect(plot().documentId, id);
      expect(plot().vertices, isEmpty);
      controls(tester)
          .onChanged('A', controls(tester).parameters['A']!.withValue(1));
      await tester.pump();
      expect(plot().vertices, isNotEmpty);
      expect(plot().vertices.first.x, closeTo(1, 1e-8));
    });

    testWidgets(
      'parameter settings survive replot and visibility reconciliation',
      (tester) async {
        await tester.pumpWidget(_buildTestApp(initialExpression: 'A*x'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('绘制'));
        await tester.pumpAndSettle();
        controls(tester).onChanged(
          'A',
          controls(tester).parameters['A']!
              .reconfigure(min: 0, max: 3, step: 0.25, value: 2.5),
        );
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'A*x+2');
        await tester.pump();
        await tester.tap(find.byTooltip('绘制'));
        await tester.pumpAndSettle();
        final parameter = controls(tester).parameters['A']!;
        expect(
          [parameter.value, parameter.min, parameter.max, parameter.step],
          [2.5, 0, 3, 0.25],
        );
        final point = canvas(tester).curvePoints.first;
        expect(point['y'], closeTo(2.5 * point['x']! + 2, 1e-9));

        await tester.tap(find.byTooltip('隐藏公式'));
        await tester.pumpAndSettle();
        expect(find.byType(MathParameterControls), findsNothing);
        expect(canvas(tester).curvePoints, isEmpty);
        await tester.tap(find.byTooltip('显示公式'));
        await tester.pumpAndSettle();
        expect(controls(tester).parameters['A']!.value, 2.5);
        expect(controls(tester).parameters['A']!.step, 0.25);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'implicit curves use shared parameters excluding coordinates and constants',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(initialExpression: r'x^2+y^2=A+0*e+0*\pi'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('绘制'));
        await tester.pumpAndSettle();
        expect(controls(tester).parameters.keys, ['A']);
        final before = canvas(tester).curvePoints
            .map((point) => point['x']!.abs())
            .reduce((a, b) => a > b ? a : b);
        controls(tester)
            .onChanged('A', controls(tester).parameters['A']!.withValue(4));
        await tester.pump();
        final after = canvas(tester).curvePoints
            .map((point) => point['x']!.abs())
            .reduce((a, b) => a > b ? a : b);
        expect(before, closeTo(1, 0.08));
        expect(after, closeTo(2, 0.08));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('MathDrawingPage - formula input', () {
    testWidgets('checkmark button plots formulas', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'x^2');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('MathDrawingPage - multi formula', () {
    testWidgets('add button adds another row', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('remove button with confirmation removes formula', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      // Add a second formula
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));

      // Tap remove on first formula
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Confirmation dialog should appear
      expect(find.text('删除'), findsWidgets);

      // Confirm deletion
      await tester.tap(find.text('删除').last);
      await tester.pump();

      // Now 1 formula should remain
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('add button only on first row', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      // There should be exactly 1 add button (only on first row)
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('eye toggle hides formula', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'x^2');
      await tester.pump();

      // Tap eye to toggle
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();

      // Should now show eye-off icon
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets(
      'hide and delete remove committed plots with an invalid draft',
      (tester) async {
        for (final is3D in [false, true]) {
          for (final delete in [false, true]) {
            await tester.pumpWidget(_buildTestApp(initialExpression: 'x'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('添加公式'));
            await tester.pump();
            await tester.enterText(find.byType(TextField).at(1), 'x+2');
            if (is3D) {
              await tester.tap(find.text('3D'));
              await tester.pumpAndSettle();
            }
            await tester.tap(find.byTooltip('绘制').first);
            await tester.pumpAndSettle();
            final canvas2D = tester.state<MathCanvasState>(
              find.byType(MathCanvas, skipOffstage: false),
            );
            final canvas3D = tester.state<MathCanvas3DState>(
              find.byType(MathCanvas3D, skipOffstage: false),
            );
            if (is3D) {
              expect(
                canvas3D.objects.where((o) => o.formulaRowId != null),
                hasLength(2),
              );
            } else {
              expect(
                canvas2D.curvePoints.any(
                  (p) => (p['y']! - p['x']! - 2).abs() < 0.01,
                ),
                isTrue,
              );
            }
            await tester.enterText(find.byType(TextField).first, 'x+');
            if (delete) {
              await tester.tap(find.byIcon(Icons.remove_circle_outline).last);
              await tester.pumpAndSettle();
              await tester.tap(find.text('删除').last);
            } else {
              await tester.tap(find.byIcon(Icons.visibility).last);
            }
            await tester.pumpAndSettle();
            if (is3D) {
              expect(
                canvas3D.objects
                    .where((o) => o.formulaRowId != null)
                    .map((o) => o.label),
                ['x'],
              );
            } else {
              expect(canvas2D.curvePoints, isNotEmpty);
              expect(
                canvas2D.curvePoints.every(
                  (p) => (p['y']! - p['x']!).abs() < 0.01,
                ),
                isTrue,
              );
            }
            expect(
              tester
                  .widget<TextField>(find.byType(TextField).first)
                  .controller!
                  .text,
              'x+',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        }
      },
    );

    testWidgets('each view tracks its own plotted expression', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();
      bool canPlot() =>
          tester
              .widget<IconButton>(
                find
                    .ancestor(
                      of: find.byIcon(Icons.check_circle_outline),
                      matching: find.byType(IconButton),
                    )
                    .first,
              )
              .onPressed !=
          null;

      await tester.enterText(find.byType(TextField), 'x^2');
      await tester.pump();
      await tester.tap(find.byTooltip('绘制').first);
      await tester.pumpAndSettle();
      expect(canPlot(), isFalse);

      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      expect(canPlot(), isTrue);
      await tester.tap(find.byTooltip('绘制').first);
      await tester.pumpAndSettle();
      expect(canPlot(), isFalse);

      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2D'));
      await tester.pumpAndSettle();
      expect(canPlot(), isTrue);
      await tester.tap(find.byTooltip('绘制').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      expect(canPlot(), isTrue);
      await tester.tap(find.byTooltip('绘制').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'x+y');
      await tester.pump();
      await tester.tap(find.byTooltip('绘制').first);
      await tester.pumpAndSettle();
      expect(canPlot(), isFalse);
      await tester.tap(find.text('2D'));
      await tester.pumpAndSettle();
      expect(canPlot(), isTrue);
      await tester.tap(find.byTooltip('绘制').first);
      await tester.pumpAndSettle();
      expect(canPlot(), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('plotting across tabs keeps formulas alive', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      // Enter formula
      await tester.enterText(find.byType(TextField), 'x^2');
      await tester.pump();

      // Plot it
      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();

      // Switch to 3D tab
      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();

      // Switch back to 2D tab
      await tester.tap(find.text('2D'));
      await tester.pumpAndSettle();

      // Text field should still have the formula
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller?.text, equals('x^2'));

      // Canvas should still be present
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('3D display toggles immediately publish their snapshot', (
    tester,
  ) async {
    final controller = MathDrawingController();
    await tester.pumpWidget(_buildTestApp(controller: controller));
    await tester.pump();
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    final canvas = tester.state<MathCanvas3DState>(find.byType(MathCanvas3D));

    for (var i = 0; i < 2; i++) {
      canvas.toggleAxes();
      expect(controller.snapshot!.showAxes3D, canvas.showAxes);
      canvas.toggleGrid();
      expect(controller.snapshot!.showGrid3D, canvas.showGrid);
      canvas.togglePlane();
      expect(controller.snapshot!.showPlane3D, canvas.showPlane);
    }
  });

  testWidgets('3D replots preserve constructed objects and relationships', (
    tester,
  ) async {
    final controller = MathDrawingController();
    await tester.pumpWidget(_buildTestApp(controller: controller));
    await tester.pump();
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    final canvas = tester.state<MathCanvas3DState>(find.byType(MathCanvas3D));
    canvas.setObjects([
      Object3D.point(const Point3D(1, 2, 3)).copyWith(documentId: 'p'),
      Object3D.sphere().copyWith(documentId: 's'),
    ]);
    canvas.restoreDocumentRelationships(
      pointAttachments: const [PointAttachment(pointId: 'p', targetId: 's')],
      constructionDependencies: const [],
    );
    await tester.enterText(find.byType(TextField), 'x+y');
    await tester.pump();
    await tester.tap(find.byTooltip('绘制').first);
    await tester.pumpAndSettle();
    expect(canvas.objects.map((o) => o.documentId), containsAll(['p', 's']));
    expect(
      canvas.objects.where((o) => o.type == Object3DType.surface),
      hasLength(1),
    );
    expect(canvas.documentPointAttachments.single.targetId, 's');
    final reopened = MathDrawingDocument.decode(
      MathDrawingDocument(name: 'plot', drawing: controller.snapshot!).encode(),
    );
    expect(
      reopened.drawing.scene3D
          .singleWhere((o) => o.type == Object3DType.surface)
          .formulaRowId,
      controller.formulas.first.id,
    );
    final plotId = canvas.objects
        .singleWhere((o) => o.type == Object3DType.surface)
        .documentId;
    canvas.restoreDocumentRelationships(
      pointAttachments: [PointAttachment(pointId: 'p', targetId: plotId)],
      constructionDependencies: const [],
    );
    final observed = <MathDrawingSnapshot>[];
    controller.onSceneChanged = (_) => observed.add(controller.snapshot!);
    await tester.enterText(find.byType(TextField), 'x-y');
    await tester.pump();
    await tester.tap(find.byTooltip('绘制').first);
    await tester.pumpAndSettle();
    expect(
      canvas.objects.where((o) => o.type == Object3DType.surface),
      hasLength(1),
    );
    expect(canvas.documentPointAttachments.single.targetId, plotId);
    final moved = canvas.objects.first.point;
    expect(moved.z, closeTo(moved.x - moved.y, 1e-8));
    expect(observed, hasLength(1));
    expect(observed.single.pointAttachments3D.single.targetId, plotId);
    expect(
      observed.single.scene3D.where((o) => o.type == Object3DType.surface),
      hasLength(1),
    );
    canvas.restoreDocumentRelationships(
      pointAttachments: const [PointAttachment(pointId: 'p', targetId: 's')],
      constructionDependencies: const [],
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.byTooltip('绘制').first);
    await tester.pumpAndSettle();
    expect(canvas.objects.map((o) => o.documentId), ['p', 's']);
    expect(canvas.documentPointAttachments.single.targetId, 's');
  });

  testWidgets('legacy unmarked objects and attachments survive plotting', (
    tester,
  ) async {
    final mesh = Expression3D.surface('x+y').sampleSurfaceGrid(
      xMin: -5,
      xMax: 5,
      yMin: -5,
      yMax: 5,
      gridX: 30,
      gridY: 30,
    );
    final controller = MathDrawingController();
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialMathematicalMode: false,
          initialShowWebView: false,
        ),
      ),
    );
    await tester.pump();
    final snapshot = controller.snapshot!;
    final color = snapshot.formulas.first.color;
    controller.restore(
      MathDrawingSnapshot(
        formulas: [snapshot.formulas.first.copyWith(rawExpression: 'x+y')],
        parameters: {},
        activeView: ViewMode.mode3D,
        activeTool: ConstructionTool.move,
        viewport2D: snapshot.viewport2D,
        camera3D: snapshot.camera3D,
        projection3D: snapshot.projection3D,
        scene3D: [
          Object3D.point(const Point3D(1, 2, 3)).copyWith(
            documentId: 'formula-plot-3d:${snapshot.formulas.first.id}',
          ),
          Object3D.surface(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: mesh.normals,
            color: color.toARGB32(),
            opacity: 0.85,
            label: 'x+y',
          ).copyWith(documentId: 'object-1'),
        ],
        pointAttachments3D: [
          PointAttachment(
            pointId: 'formula-plot-3d:${snapshot.formulas.first.id}',
            targetId: 'object-1',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final canvas = tester.state<MathCanvas3DState>(find.byType(MathCanvas3D));
    final targetId = canvas.documentPointAttachments.single.targetId;
    await tester.enterText(find.byType(TextField), 'x-y');
    await tester.pump();
    await tester.tap(find.byTooltip('绘制').first);
    await tester.pumpAndSettle();
    expect(
      canvas.objects.where((o) => o.type == Object3DType.surface),
      hasLength(2),
    );
    expect(
      canvas.objects.singleWhere((o) => o.documentId == 'object-1').label,
      'x+y',
    );
    expect(canvas.documentPointAttachments.single.targetId, targetId);
    await tester.enterText(find.byType(TextField), 'x+2*y');
    await tester.pump();
    await tester.tap(find.byTooltip('绘制').first);
    await tester.pumpAndSettle();
    expect(
      canvas.objects.where((o) => o.type == Object3DType.point),
      hasLength(1),
    );
    expect(canvas.documentPointAttachments.single.targetId, targetId);
  });

  group('MathDrawingPage - error handling', () {
    testWidgets('shows error for invalid expression', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'x ^^ 2');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('此公式暂不能绘图'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('MathDrawingPage - UI spacing', () {
    // Helpers to measure the formula row's action buttons (the IconButtons
    // inside the row that contains the formula TextField, excluding the
    // TextField's own undo suffix icon.
    List<Rect> rowButtonRects(WidgetTester tester, {int rowIndex = 0}) {
      final row = find
          .ancestor(
            of: find.byType(TextField).at(rowIndex),
            matching: find.byType(Row),
          )
          .first;
      final buttons = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              ![
                Icons.undo,
                Icons.calculate_outlined,
                Icons.keyboard,
              ].contains((w.icon as Icon?)?.icon),
        ),
      );
      return [
        for (var i = 0; i < buttons.evaluate().length; i++)
          tester.getRect(buttons.at(i)),
      ];
    }

    Rect textFieldRect(WidgetTester tester, {int rowIndex = 0}) {
      return tester.getRect(find.byType(TextField).at(rowIndex));
    }

    void expectUniformSpacing(
      WidgetTester tester, {
      required int rowIndex,
      required double gap,
    }) {
      final tfRect = textFieldRect(tester, rowIndex: rowIndex);
      final rects = rowButtonRects(tester, rowIndex: rowIndex);
      expect(rects, isNotEmpty);

      // Input -> first action button
      expect(
        rects.first.left - tfRect.right,
        closeTo(gap, 0.01),
        reason: 'Gap between text field and first action button',
      );

      // Every action button is a compact 24x24 block
      for (final r in rects) {
        expect(
          r.width,
          closeTo(24, 0.01),
          reason: 'Action button should be 24 wide (compact block)',
        );
        expect(
          r.height,
          closeTo(24, 0.01),
          reason: 'Action button should be 24 tall (compact block)',
        );
      }

      // Uniform gaps between consecutive buttons
      for (var i = 0; i < rects.length - 1; i++) {
        expect(
          rects[i + 1].left - rects[i].right,
          closeTo(gap, 0.01),
          reason: 'Gap between consecutive action buttons should be uniform',
        );
      }
    }

    testWidgets(
      'action buttons are compact 24x24 blocks with uniform 12px gaps',
      (tester) async {
        await tester.pumpWidget(_buildTestApp());
        await tester.pump();

        expectUniformSpacing(tester, rowIndex: 0, gap: 12);
      },
    );
  });

  group('MathDrawingPage - initial expression', () {
    testWidgets('pre-populates expression when provided', (tester) async {
      await tester.pumpWidget(_buildTestApp(initialExpression: 'sin(x)'));
      await tester.pump();

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller?.text, equals('sin(x)'));
    });
  });
}

// Editing snapshots are asynchronous on native WebViews. Exercise the page
// with the bridge boundary rather than constructing a platform view in tests.
void editorInteractionTests() {
  testWidgets(
    'a tap bridge event reopens the keyboard after dismissal without a new focus event',
    (tester) async {
      final platform = await _delayedEditors(tester, rows: 1);
      final editor = platform.activeEditors.single.controller;
      editor.emit({'type': 'focus', 'revision': 0});
      await tester.pumpAndSettle();
      expect(find.text('下一项'), findsOneWidget);

      await tester.tap(find.byTooltip('收起数学键盘'));
      await tester.pumpAndSettle();
      expect(find.text('下一项'), findsNothing);

      editor.emit({'type': 'tap', 'revision': 0});
      await tester.pumpAndSettle();
      expect(find.text('下一项'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching a lower source row to math mode keeps it visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    for (var i = 1; i < 6; i++) {
      await tester.tap(find.byTooltip('添加公式'));
      await tester.pumpAndSettle();
    }

    final lastField = find.byType(MathFormulaField).last;
    await tester.ensureVisible(lastField);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换到数学键盘（内置公式预览）').last);
    await tester.pumpAndSettle();

    final formulaViewport = tester.getRect(find.byType(ListView).first);
    final lastRow = tester.getRect(lastField);
    expect(lastRow.top, greaterThanOrEqualTo(formulaViewport.top));
    expect(lastRow.bottom, lessThanOrEqualTo(formulaViewport.bottom));
    expect(find.text('下一项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unsupported syntax warning stays visible in the fixed math row',
    (tester) async {
      final platform = await _delayedEditors(tester, rows: 1);
      final editor = platform.activeEditors.single.controller;
      final row = find.byType(MathFormulaField).first;
      final rowHeight = tester.getSize(row).height;

      editor.emit({
        'type': 'selection',
        'revision': 0,
        'sequence': 1,
        'errors': ['unexpected-command'],
      });
      await tester.pumpAndSettle();

      expect(find.text('暂不支持此语法，请切换源码'), findsOneWidget);
      expect(tester.getSize(row).height, closeTo(rowHeight, 0.01));
      expect(rowHeight, closeTo(48, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending deletion keeps a later confirmation tied to its formula',
    (tester) async {
      final platform = await _delayedEditors(tester, rows: 3);
      final fields = tester
          .stateList<MathFormulaFieldState>(find.byType(MathFormulaField))
          .toList();
      final gate = Completer<void>();
      platform.activeEditors.first.controller.snapshotGate = gate.future;
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_circle_outline).last);
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MathFormulaField), findsNWidgets(2));
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.state<MathFormulaFieldState>(find.byType(MathFormulaField)),
        same(fields[1]),
      );
    },
  );

  testWidgets('concurrent pending deletions retain the final formula', (
    tester,
  ) async {
    final platform = await _delayedEditors(tester, rows: 2);
    final gate = Completer<void>();
    platform.activeEditors.first.controller.snapshotGate = gate.future;
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_circle_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MathFormulaField), findsOneWidget);
  });

  testWidgets('short narrow screens keep the canvas and keyboard scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MathDrawingPage(
          initialShowWebView: false,
          initialMathematicalMode: true,
        ),
      ),
    );
    await tester.tap(find.byType(MathFormulaField));
    await tester.pump();
    await tester.tap(find.byTooltip('全部符号分类'));
    await tester.pumpAndSettle();
    final matrices = find.text('矩阵').last;
    await tester.ensureVisible(matrices);
    await tester.tap(matrices);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('收起数学键盘'));
    await tester.pump();
    expect(find.text('下一项'), findsNothing);
  });
  testWidgets('math keyboard follows row identity across deletion and tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MathDrawingPage(
          initialShowWebView: false,
          initialMathematicalMode: true,
        ),
      ),
    );
    await tester.tap(find.byType(MathFormulaField).first);
    await tester.pump();
    expect(find.text('下一项'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    final fields = tester
        .stateList<MathFormulaFieldState>(find.byType(MathFormulaField))
        .toList();
    fields[1].acceptSnapshot({
      'revision': fields[1].revision,
      'latex': r'\frac{x}{2}',
      'edited': true,
    });
    await tester.pump();
    await tester.tap(find.byType(MathFormulaField).last);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(
      tester.state<MathFormulaFieldState>(find.byType(MathFormulaField)),
      same(fields[1]),
    );
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(find.text('下一项'), findsNothing);
    await tester.tap(find.text('2D'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换到 LaTeX 源码输入'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      r'\frac{x}{2}',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('fallback math keyboard disables structural navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MathDrawingPage(
          initialShowWebView: false,
          initialMathematicalMode: true,
        ),
      ),
    );
    await tester.tap(find.byType(MathFormulaField).first);
    await tester.pump();

    final previous = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '上一项'),
    );
    final next = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '下一项'),
    );
    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNull);

    await tester.tap(find.byTooltip('7'));
    await tester.pump();
    expect(
      tester
          .widget<MathFormulaField>(find.byType(MathFormulaField).first)
          .controller
          .text,
      '7',
    );
    expect(tester.takeException(), isNull);
  });
}

Future<_DelayedEditorPlatform> _delayedEditors(
  WidgetTester tester, {
  required int rows,
}) async {
  final original = InAppWebViewPlatform.instance;
  final platform = _DelayedEditorPlatform();
  InAppWebViewPlatform.instance = platform;
  addTearDown(
    () => InAppWebViewPlatform.instance = original ?? _DelayedEditorPlatform(),
  );
  await tester.pumpWidget(
    const MaterialApp(home: MathDrawingPage(initialMathematicalMode: true)),
  );
  for (var i = 1; i < rows; i++) {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
  }
  platform.activeEditors = platform.editors.sublist(
    platform.editors.length - rows,
  );
  for (final native in platform.activeEditors) {
    final controller = native.controllerFromPlatform<InAppWebViewController>(
      native.controller,
    );
    native.params.onWebViewCreated!(controller);
    native.params.onLoadStop!(controller, null);
  }
  await tester.pumpAndSettle();
  return platform;
}

class _DelayedEditorPlatform extends InAppWebViewPlatform {
  final editors = <_DelayedEditor>[];
  late final List<_DelayedEditor> activeEditors;
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    final editor = _DelayedEditor(params);
    editors.add(editor);
    return editor;
  }
}

class _DelayedEditor extends PlatformInAppWebViewWidget {
  final controller = _DelayedEditorController();
  _DelayedEditor(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {}
}

class _DelayedEditorController extends PlatformInAppWebViewController {
  Future<void>? snapshotGate;
  JavaScriptHandlerCallback? _handler;
  _DelayedEditorController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  void emit(Map<String, dynamic> message) {
    _handler?.call([message]);
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains('stroomMath.snapshot()')) await snapshotGate;
    return null;
  }

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {
    _handler = callback;
  }

  @override
  void dispose({bool isKeepAlive = false}) {}
}
