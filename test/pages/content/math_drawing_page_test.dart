import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

Widget _buildTestApp({String? initialExpression}) {
  return MaterialApp(
    home: MathDrawingPage(
      initialExpression: initialExpression,
      initialMathematicalMode: false,
      initialShowWebView: false,
    ),
    localizationsDelegates: const [
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
  );
}

Future<void> _chooseFormulaAction(
  WidgetTester tester,
  int rowIndex,
  String action,
) async {
  await tester.ensureVisible(find.byTooltip('公式操作').at(rowIndex));
  await tester.tap(find.byTooltip('公式操作').at(rowIndex));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action).last);
  await tester.pumpAndSettle();
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
        await _chooseFormulaAction(tester, 1, '绘制');
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
      'parameter settings survive replot and visibility reconciliation',
      (tester) async {
        await tester.pumpWidget(_buildTestApp(initialExpression: 'A*x'));
        await tester.pumpAndSettle();
        await _chooseFormulaAction(tester, 0, '绘制');
        await tester.pumpAndSettle();
        controls(tester).onChanged(
          'A',
          controls(tester).parameters['A']!
              .reconfigure(min: 0, max: 3, step: 0.25, value: 2.5),
        );
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'A*x+2');
        await tester.pump();
        await _chooseFormulaAction(tester, 0, '绘制');
        await tester.pumpAndSettle();
        final parameter = controls(tester).parameters['A']!;
        expect(
          [parameter.value, parameter.min, parameter.max, parameter.step],
          [2.5, 0, 3, 0.25],
        );
        final point = canvas(tester).curvePoints.first;
        expect(point['y'], closeTo(2.5 * point['x']! + 2, 1e-9));

        await _chooseFormulaAction(tester, 0, '隐藏公式');
        await tester.pumpAndSettle();
        expect(find.byType(MathParameterControls), findsNothing);
        expect(canvas(tester).curvePoints, isEmpty);
        await _chooseFormulaAction(tester, 0, '显示公式');
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
        await _chooseFormulaAction(tester, 0, '绘制');
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
    testWidgets('math mode switch is present only while its keyboard is open', (
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
      expect(find.byTooltip('切换到 LaTeX 源码输入'), findsNothing);

      await tester.tap(find.byType(MathFormulaField).first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('切换到 LaTeX 源码输入'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('收起数学键盘'));
      await tester.tap(find.byTooltip('收起数学键盘'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('切换到 LaTeX 源码输入'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('source mode can reopen the math keyboard from row actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MathDrawingPage(
            initialShowWebView: false,
            initialMathematicalMode: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip('切换到数学键盘'), findsNothing);
      await tester.tap(find.byTooltip('公式操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开数学键盘'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('切换到 LaTeX 源码输入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('math mode without a keyboard can switch back to source', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MathDrawingPage(
            initialShowWebView: false,
            initialMathematicalMode: true,
            options: MathWorkspaceOptions(showKeyboard: false),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('切换到 LaTeX 源码输入'), findsNothing);
      await tester.tap(find.byTooltip('公式操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('切换到源码输入'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('checkmark button plots formulas', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'x^2');
      await tester.pump();

      await _chooseFormulaAction(tester, 0, '绘制');
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
      await _chooseFormulaAction(tester, 0, '删除公式');
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
      await _chooseFormulaAction(tester, 0, '隐藏公式');
      await tester.tap(find.byTooltip('公式操作').first);
      await tester.pumpAndSettle();
      expect(find.text('显示公式'), findsOneWidget);
    });

    testWidgets('plotting across tabs keeps formulas alive', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      // Enter formula
      await tester.enterText(find.byType(TextField), 'x^2');
      await tester.pump();

      // Plot it
      await _chooseFormulaAction(tester, 0, '绘制');
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

  group('MathDrawingPage - error handling', () {
    testWidgets('shows error for invalid expression', (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'x ^^ 2');
      await tester.pump();
      await _chooseFormulaAction(tester, 0, '绘制');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('此公式暂不能绘图'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('MathDrawingPage - UI spacing', () {
    testWidgets(
      'formula row keeps one overflow action and gives the field room',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_buildTestApp());
        await tester.pump();

        final action = find.byTooltip('公式操作');
        expect(action, findsOneWidget);
        expect(tester.getSize(find.byType(TextField)).width, greaterThan(180));
        expect(
          find.descendant(
            of: find
                .ancestor(
                  of: find.byType(TextField),
                  matching: find.byType(Row),
                )
                .first,
            matching: find.byTooltip('公式操作'),
          ),
          findsOneWidget,
        );
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
      await tester.ensureVisible(find.byTooltip('收起数学键盘'));
      await tester.tap(find.byTooltip('收起数学键盘'));
      await tester.pumpAndSettle();

      editor.emit({'type': 'tap', 'revision': 0});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('activating a lower math row keeps it visible', (tester) async {
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
    await tester.pumpAndSettle();

    for (var i = 1; i < 6; i++) {
      await tester.tap(find.byTooltip('添加公式'));
      await tester.pumpAndSettle();
    }

    final lastField = find.byType(MathFormulaField).last;
    await tester.ensureVisible(lastField);
    await tester.pumpAndSettle();
    await tester.tap(lastField);
    await tester.pumpAndSettle();

    final formulaViewport = tester.getRect(find.byType(ListView).first);
    final lastRow = tester.getRect(lastField);
    expect(lastRow.top, greaterThanOrEqualTo(formulaViewport.top));
    expect(lastRow.bottom, lessThanOrEqualTo(formulaViewport.bottom));
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
      await _chooseFormulaAction(tester, 0, '删除公式');
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      await _chooseFormulaAction(tester, 2, '删除公式');
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
    await _chooseFormulaAction(tester, 0, '删除公式');
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await _chooseFormulaAction(tester, 1, '删除公式');
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
    await tester.ensureVisible(find.byTooltip('收起数学键盘'));
    await tester.tap(find.byTooltip('收起数学键盘'));
    await tester.pump();
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
    await _chooseFormulaAction(tester, 0, '删除公式');
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(
      tester.state<MathFormulaFieldState>(find.byType(MathFormulaField)),
      same(fields[1]),
    );
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2D'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MathFormulaField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换到 LaTeX 源码输入'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      r'\frac{x}{2}',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('fallback math keyboard supports insertion', (tester) async {
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
