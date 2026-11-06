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
}
