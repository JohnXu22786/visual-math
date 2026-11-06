import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';
import 'package:visual_math/visual_math.dart' as vm;

Widget _app(MathWorkspaceOptions options) => MaterialApp(
  home: MathDrawingPage(
    options: options,
    initialMathematicalMode: false,
    initialShowWebView: false,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('3D-only workspaces omit the selector and start in 3D', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MathWorkspaceOptions(
          show2D: false,
          show3D: true,
          initialView: ViewMode.mode3D,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(MathCanvas), findsNothing);
    expect(find.byType(MathCanvas3D), findsOneWidget);
    expect(find.byType(Math3DToolbar), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);

    await tester.pumpWidget(
      _app(
        const MathWorkspaceOptions(
          show2D: true,
          show3D: false,
          initialView: ViewMode.mode2D,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(MathCanvas), findsOneWidget);
    expect(find.byType(MathCanvas3D), findsNothing);
  });

  testWidgets('restoring an unavailable view keeps the configured view', (
    tester,
  ) async {
    final controller = MathDrawingController();
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          options: const MathWorkspaceOptions(show3D: false),
          initialMathematicalMode: false,
          initialShowWebView: false,
        ),
      ),
    );
    await tester.pump();

    controller.restore(
      MathDrawingSnapshot(
        formulas: const [],
        parameters: const {},
        activeView: ViewMode.mode3D,
        activeTool: ConstructionTool.move,
        viewport2D: vm.Viewport.defaultViewport(),
        camera3D: const Camera3D(),
        projection3D: ProjectionType.parallel,
        scene3D: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.activeView, ViewMode.mode2D);
    expect(find.byType(MathCanvas), findsOneWidget);
    expect(find.byType(MathCanvas3D), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom view selection updates the workspace controller', (
    tester,
  ) async {
    final controller = MathDrawingController();
    final viewChanges = <ViewMode>[];
    controller.onViewChanged = viewChanges.add;
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          options: MathWorkspaceOptions(
            viewSelectorBuilder: (context, _, actions) => TextButton(
              onPressed: () async => actions.setActiveView(ViewMode.mode3D),
              child: const Text('Host select 3D'),
            ),
          ),
          initialMathematicalMode: false,
          initialShowWebView: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Host select 3D'));
    await tester.pumpAndSettle();

    expect(controller.activeView, ViewMode.mode3D);
    expect(viewChanges, [ViewMode.mode3D]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('presentation labels preserve selector semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          options: MathWorkspaceOptions(
            presentation: MathWorkspacePresentation(
              labels: MathWorkspaceLabels(
                addFormula: 'New expression',
                view2D: 'Plane',
                view3D: 'Space',
                plotFormula: 'Plot expression',
                translate: (source) =>
                    source == '数学绘图' ? 'Mathematics' : source,
              ),
            ),
          ),
          initialMathematicalMode: false,
          initialShowWebView: false,
        ),
      ),
    );
    await tester.pump();
    final semantics = tester.ensureSemantics();

    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.byTooltip('New expression'), findsOneWidget);
    expect(find.text('Plane'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Plane')), findsOneWidget);
    expect(find.byTooltip('Plot expression'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('compact density and host theme use configured insets', (
    tester,
  ) async {
    expect(const MathWorkspacePresentation().isCompactForWidth(400), isFalse);
    const inset = EdgeInsets.fromLTRB(17, 19, 17, 21);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        ),
        home: MathDrawingPage(
          options: const MathWorkspaceOptions(
            show3D: false,
            presentation: MathWorkspacePresentation(
              density: MathWorkspaceDensity.compact,
              canvasInset: inset,
              controlInset: const EdgeInsets.fromLTRB(10, 0, 11, 13),
              controlPlacement: MathWorkspaceControlPlacement.bottomStart,
              interactionPolicy: const MathWorkspaceInteractionPolicy(
                allowTouchGestures: false,
              ),
            ),
          ),
          initialMathematicalMode: false,
          initialShowWebView: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.byType(MathCanvas),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is Padding && widget.padding == inset,
                  ),
                )
                .first,
          )
          .padding,
      inset,
    );
    final canvas = tester.widget<MathCanvas>(find.byType(MathCanvas));
    expect(canvas.allowTouchGestures, isFalse);
    expect(canvas.allowMouseGestures, isTrue);
    expect(
      tester
          .widgetList<Positioned>(find.byType(Positioned))
          .any((control) => control.left == 10 && control.right == null),
      isTrue,
    );
    expect(
      Theme.of(tester.element(find.byType(MathCanvas))).colorScheme.primary,
      ColorScheme.fromSeed(seedColor: Colors.purple).primary,
    );
  });

  testWidgets('responsive threshold and error surface are host configurable', (
    tester,
  ) async {
    const presentation = MathWorkspacePresentation(responsiveBreakpoint: 500);
    expect(presentation.isCompactForWidth(400), isTrue);
    expect(presentation.isCompactForWidth(700), isFalse);
    Widget errorSurface(BuildContext context, String message) =>
        Text('Host error: $message');
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          options: MathWorkspaceOptions(
            show3D: false,
            presentation: MathWorkspacePresentation(
              responsiveBreakpoint: 500,
              dialogBuilder: (_, dialog) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [const Text('Host dialog'), dialog],
              ),
              errorBuilder: errorSurface,
            ),
          ),
          initialExpression: 'x+',
          initialMathematicalMode: false,
          initialShowWebView: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加公式'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除公式').last);
    await tester.pumpAndSettle();
    expect(find.text('Host dialog'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('绘制').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Host error:'), findsOneWidget);
    expect(find.byType(MathCanvas), findsOneWidget);

    const threeDInset = EdgeInsets.fromLTRB(11, 12, 13, 14);
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          options: MathWorkspaceOptions(
            show2D: false,
            show3D: true,
            initialView: ViewMode.mode3D,
            presentation: MathWorkspacePresentation(
              canvasInset: threeDInset,
              interactionPolicy: MathWorkspaceInteractionPolicy(
                allowMouseGestures: false,
              ),
              labels: MathWorkspaceLabels(
                translate: (source) => 'Localized $source',
              ),
            ),
          ),
          initialMathematicalMode: false,
          initialShowWebView: false,
        ),
      ),
    );
    await tester.pump();
    final threeDCanvasPadding = find.ancestor(
      of: find.byType(MathCanvas3D),
      matching: find.byWidgetPredicate(
        (widget) => widget is Padding && widget.padding == threeDInset,
      ),
    );
    expect(threeDCanvasPadding, findsOneWidget);
    expect(
      tester.widget<MathCanvas3D>(find.byType(MathCanvas3D)).allowMouseGestures,
      isFalse,
    );
    expect(find.byTooltip('Localized 3D 视图设置'), findsOneWidget);
    expect(find.byTooltip('Localized 放大'), findsOneWidget);
  });

  testWidgets('custom 3D tool selection updates the workspace controller', (
    tester,
  ) async {
    final controller = MathDrawingController();
    final toolChanges = <ConstructionTool>[];
    controller.onToolChanged = toolChanges.add;
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          options: MathWorkspaceOptions(
            threeDToolsBuilder: (context, _, actions) => TextButton(
              onPressed: () => actions.select3DTool(ConstructionTool.point),
              child: const Text('Host select point tool'),
            ),
          ),
          initialMathematicalMode: false,
          initialShowWebView: false,
        ),
      ),
    );
    await tester.pump();
    controller.setActiveView(ViewMode.mode3D);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Host select point tool'));
    await tester.pumpAndSettle();

    expect(controller.activeTool, ConstructionTool.point);
    expect(toolChanges, [ConstructionTool.point]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replacing the formula region retains custom parameter controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MathDrawingPage(
            initialExpression: 'A*x',
            initialMathematicalMode: false,
            initialShowWebView: false,
            options: MathWorkspaceOptions(
              show3D: false,
              formulaEditorBuilder: (context, _, actions) => Column(
                children: [
                  Text('Host formulas: ${actions.formulaCount}'),
                  TextButton(
                    onPressed: actions.plot,
                    child: const Text('Plot host formula'),
                  ),
                ],
              ),
              parameterControlsBuilder: (context, _, actions) => Text(
                'Host parameters: ${actions.parameters.keys.join(', ')}',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Plot host formula'));
      await tester.pumpAndSettle();

      expect(find.text('Host formulas: 1'), findsOneWidget);
      expect(find.text('Host parameters: A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom formula edits update the workspace controller', (
    tester,
  ) async {
    final controller = MathDrawingController();
    final formulaEdits = <String>[];
    controller.onFormulaEdited = (_, expression) =>
        formulaEdits.add(expression);
    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          controller: controller,
          initialExpression: 'x',
          initialMathematicalMode: false,
          initialShowWebView: false,
          options: MathWorkspaceOptions(
            show3D: false,
            formulaEditorBuilder: (context, _, actions) => TextButton(
              onPressed: () => actions.setFormulaExpression(0, 'y'),
              child: const Text('Set host formula draft'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set host formula draft'));
    await tester.pumpAndSettle();

    expect(controller.formulas.single.rawExpression, 'y');
    expect(formulaEdits, ['y']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom regions compose in a host-owned body', (tester) async {
    await tester.pumpWidget(
      _app(
        MathWorkspaceOptions(
          showScaffold: false,
          showAppBar: false,
          show3D: false,
          showFormulaEditor: false,
          showParameterControls: false,
          show3DTools: false,
          show2DCanvasActions: false,
          initialView: ViewMode.mode2D,
          formulaEditorBuilder: (context, _, actions) => SingleChildScrollView(
            child: Column(
              children: [
                const Text('host formula panel'),
                Text('Formula rows: ${actions.formulaCount}'),
                Text('Formula: ${actions.formulaExpression(0)}'),
                TextButton(
                  onPressed: actions.addFormula,
                  child: const Text('Add host formula'),
                ),
              ],
            ),
          ),
          canvas2DOverlayBuilder: (context, defaultOverlay, actions) => Stack(
            children: [
              defaultOverlay,
              Positioned(
                top: 60,
                right: 8,
                child: Column(
                  children: [
                    Text('host canvas tools: ${actions.activeView.name}'),
                    TextButton(
                      onPressed: () => actions.activateFormula(0),
                      child: const Text('Show host keyboard'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          canvas2DActionsBuilder: (context, _, actions) => TextButton(
            onPressed: actions.zoomIn2DCanvas,
            child: const Text('Host zoom'),
          ),
          keyboardBuilder: (context, _, actions) => TextButton(
            onPressed: () => actions.sendEditorCommand('insert', '+'),
            child: const Text('Insert at caret'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('host formula panel'), findsOneWidget);
    expect(find.text('host canvas tools: mode2D'), findsOneWidget);
    expect(find.text('Host zoom'), findsOneWidget);
    expect(find.text('Formula rows: 1'), findsOneWidget);
    expect(find.byType(MathCanvas), findsOneWidget);
    expect(find.byType(MathCanvas3D), findsNothing);
    expect(find.byType(Math3DToolbar), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Add host formula'));
    await tester.pump();
    expect(find.text('Formula rows: 2'), findsOneWidget);
    await tester.tap(find.text('Show host keyboard'));
    await tester.pumpAndSettle();
    expect(find.text('Insert at caret'), findsOneWidget);
    await tester.tap(find.text('Insert at caret'));
    await tester.pumpAndSettle();
    expect(find.text('Formula: +'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          key: const ValueKey('built-in-keyboard-replacement-editor-test'),
          initialExpression: 'y',
          initialMathematicalMode: true,
          initialShowWebView: false,
          options: MathWorkspaceOptions(
            show3D: false,
            showFormulaEditor: false,
            formulaEditorBuilder: (context, _, actions) => Column(
              children: [
                Text(
                  'Built-in keyboard formula: ${actions.formulaExpression(0)}',
                ),
                Text('Built-in keyboard editor ready: ${actions.editorReady}'),
                TextButton(
                  onPressed: () => actions.activateFormula(0),
                  child: const Text('Activate built-in keyboard formula'),
                ),
                TextButton(
                  onPressed: () => actions.sendEditorCommand('insert', '+'),
                  child: const Text('Insert built-in keyboard caret'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activate built-in keyboard formula'));
    await tester.pumpAndSettle();
    expect(find.text('Built-in keyboard editor ready: true'), findsOneWidget);
    await tester.tap(find.text('Insert built-in keyboard caret'));
    await tester.pumpAndSettle();
    expect(find.text('Built-in keyboard formula: y+'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          key: const ValueKey('replacement-editor-command-test'),
          initialExpression: 'x',
          initialMathematicalMode: true,
          initialShowWebView: false,
          options: MathWorkspaceOptions(
            show3D: false,
            formulaEditorBuilder: (context, _, actions) => TextButton(
              onPressed: () => actions.activateFormula(0),
              child: const Text('Activate replacement formula'),
            ),
            keyboardBuilder: (context, _, actions) => Column(
              children: [
                Text('Replacement formula: ${actions.formulaExpression(0)}'),
                TextButton(
                  onPressed: () => actions.sendEditorCommand('insert', '+'),
                  child: const Text('Insert replacement caret'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activate replacement formula'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert replacement caret'));
    await tester.pumpAndSettle();
    expect(find.text('Replacement formula: x+'), findsOneWidget);
    expect(find.byType(MathFormulaField, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: MathDrawingPage(
          key: const ValueKey('keyboard-replacement-test'),
          initialExpression: 'x',
          initialMathematicalMode: true,
          initialShowWebView: false,
          options: MathWorkspaceOptions(
            keyboardBuilder: (context, _, actions) => TextButton(
              onPressed: () => actions.sendEditorCommand('insert', '+'),
              child: const Text('Insert at caret'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MathFormulaField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert at caret'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MathFormulaField>(find.byType(MathFormulaField))
          .controller
          .text,
      'x+',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('parameter validation errors use the host error surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathParameterControls(
            parameters: {'A': MathParameter()},
            onChanged: (_, __) {},
            errorBuilder: (_, message) => Text(
              'Host validation error: $message',
              key: const ValueKey('host-validation-error'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('设置参数 A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'not a number');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('host-validation-error')), findsOneWidget);
    expect(find.textContaining('Host validation error:'), findsOneWidget);
  });
}
