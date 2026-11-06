import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

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
