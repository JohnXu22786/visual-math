import 'dart:async';

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

Future<void> _withTargetPlatformOverride(
  TargetPlatform targetPlatform,
  Future<void> Function() body,
) async {
  final previous = foundation.debugDefaultTargetPlatformOverride;
  foundation.debugDefaultTargetPlatformOverride = targetPlatform;
  try {
    await body();
  } finally {
    foundation.debugDefaultTargetPlatformOverride = previous;
  }
}

void main() {
  testWidgets('long formula previews drag horizontally with a mouse', (
    tester,
  ) async {
    final source = TextEditingController(text: List.filled(24, 'x').join('+'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: MathFormulaField(
                controller: source,
                showWebView: false,
                mathematical: true,
                label: '公式 1',
                onModeChanged: (_) {},
                onActivate: () {},
                onChanged: () {},
                onSubmitted: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      scrollable,
      const Offset(-100, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });

  testWidgets(
    'math input row keeps the regular source height for a tall rendered formula',
    (tester) async {
      final source = TextEditingController(text: r'\frac{x}{2}');
      final key = GlobalKey<MathFormulaFieldState>();
      Widget app(bool mathematical) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: MathFormulaField(
              key: key,
              controller: source,
              showWebView: false,
              mathematical: mathematical,
              onModeChanged: (_) {},
              onActivate: () {},
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        ),
      );

      await tester.pumpWidget(app(false));
      final sourceHeight = tester.getSize(find.byKey(key)).height;
      await tester.pumpWidget(app(true));
      key.currentState!.acceptSnapshot({
        'revision': key.currentState!.revision,
        'height': 132,
        'type': 'selection',
      });
      await tester.pump();

      expect(
        tester.getSize(find.byKey(key)).height,
        closeTo(sourceHeight, 0.01),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    },
  );

  testWidgets(
    'document load without MathLive mount stays pending and falls back on timeout',
    (tester) async {
      final originalPlatform = InAppWebViewPlatform.instance;
      final platform = _EditorPlatform();
      InAppWebViewPlatform.instance = platform;
      addTearDown(
        () => InAppWebViewPlatform.instance =
            originalPlatform ?? _EditorPlatform(),
      );
      final source = TextEditingController(text: 'x');
      final key = GlobalKey<MathFormulaFieldState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MathFormulaField(
              key: key,
              controller: source,
              mathematical: true,
              onModeChanged: (_) {},
              onActivate: () {},
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        ),
      );
      final native = platform.editor!;
      final controller = native.controllerFromPlatform<InAppWebViewController>(
        native.controller,
      );
      native.params.onWebViewCreated!(controller);
      native.params.onLoadStop!(controller, null);
      await tester.pump();
      final editor = key.currentState!;

      expect(editor.ready, isFalse);
      await editor.command('insert', '+y');
      expect(source.text, 'x');
      expect(
        native.controller.scripts.where(
          (script) => script.contains('.command('),
        ),
        isEmpty,
      );

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(editor.failed, isTrue);
      expect(editor.ready, isTrue);
      await editor.command('insert', '+y');
      expect(source.text, 'x+y');

      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    },
  );

  testWidgets(
    'initial MathLive synchronization timeout falls back to usable keyboard',
    (tester) async {
      final originalPlatform = InAppWebViewPlatform.instance;
      final platform = _EditorPlatform();
      InAppWebViewPlatform.instance = platform;
      addTearDown(
        () => InAppWebViewPlatform.instance =
            originalPlatform ?? _EditorPlatform(),
      );
      final source = TextEditingController(text: 'x');
      final key = GlobalKey<MathFormulaFieldState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MathFormulaField(
              key: key,
              controller: source,
              mathematical: true,
              onModeChanged: (_) {},
              onActivate: () {},
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        ),
      );
      final native = platform.editor!;
      final controller = native.controllerFromPlatform<InAppWebViewController>(
        native.controller,
      );
      native.params.onWebViewCreated!(controller);
      native.params.onLoadStop!(controller, null);
      await tester.pump();
      final editor = key.currentState!;
      final stalledEvaluation = Completer<void>();
      native.controller.evaluationBlocker = stalledEvaluation;

      native.controller.sendMessage({'type': 'ready', 'revision': -1});
      await tester.pump();

      expect(editor.ready, isFalse);
      expect(editor.failed, isFalse);
      expect(
        native.controller.scripts.where(
          (script) => script.contains('setSource'),
        ),
        hasLength(1),
      );

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(editor.failed, isTrue);
      expect(editor.ready, isTrue);
      await editor.command('insert', '+y');
      await editor.command('insert', '+z');
      expect(source.text, 'x+y+z');

      stalledEvaluation.complete();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    },
  );

  testWidgets('recreated MathLive editor initializes and accepts commands', (
    tester,
  ) async {
    final originalPlatform = InAppWebViewPlatform.instance;
    final platform = _EditorPlatform();
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () =>
          InAppWebViewPlatform.instance = originalPlatform ?? _EditorPlatform(),
    );
    final source = TextEditingController(text: 'x');
    final key = GlobalKey<MathFormulaFieldState>();
    Widget app(bool showWebView) => MaterialApp(
      home: Scaffold(
        body: MathFormulaField(
          key: key,
          controller: source,
          showWebView: showWebView,
          mathematical: true,
          onModeChanged: (_) {},
          onActivate: () {},
          onChanged: () {},
          onSubmitted: () {},
          label: '公式 1',
        ),
      ),
    );

    await tester.pumpWidget(app(true));
    final first = platform.editor!;
    final firstController = first
        .controllerFromPlatform<InAppWebViewController>(first.controller);
    first.params.onWebViewCreated!(firstController);
    first.params.onLoadStop!(firstController, null);
    await tester.pump();
    first.controller.sendMessage({'type': 'ready', 'revision': -1});
    await tester.pumpAndSettle();
    expect(key.currentState!.ready, isTrue);
    final state = key.currentState;
    final stalledCommand = Completer<void>();
    first.controller.evaluationBlocker = stalledCommand;
    first.controller.evaluationResponse = {
      'revision': key.currentState!.revision,
      'latex': 'stale result',
      'edited': true,
      'sequence': 1,
    };
    final oldCommand = key.currentState!.command('insert', '+old');
    await tester.pump();

    await tester.pumpWidget(app(false));
    expect(key.currentState, same(state));
    expect(key.currentState!.ready, isTrue);
    stalledCommand.complete();
    await oldCommand;
    expect(source.text, 'x');
    await key.currentState!.command('insert', '+fallback');
    expect(source.text, 'x+fallback');

    await tester.pumpWidget(app(true));
    final replacement = platform.editor!;
    expect(replacement, isNot(same(first)));
    final replacementController = replacement
        .controllerFromPlatform<InAppWebViewController>(replacement.controller);
    replacement.params.onWebViewCreated!(replacementController);
    replacement.params.onLoadStop!(replacementController, null);
    await tester.pump();
    expect(key.currentState!.ready, isFalse);

    first.controller.sendMessage({'type': 'ready', 'revision': -1});
    await tester.pump();
    expect(key.currentState!.ready, isFalse);

    replacement.controller.sendMessage({'type': 'ready', 'revision': -1});
    await tester.pumpAndSettle();
    expect(key.currentState!.ready, isTrue);
    expect(
      replacement.controller.scripts.where(
        (script) =>
            script.contains('setSource') && script.contains('x+fallback'),
      ),
      hasLength(1),
    );
    expect(
      replacement.controller.scripts.where(
        (script) => script.contains('.theme('),
      ),
      hasLength(1),
    );
    await key.currentState!.command('insert', '+native');
    expect(
      replacement.controller.scripts.where(
        (script) => script.contains('.command('),
      ),
      hasLength(1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });

  testWidgets('initial synchronization uses the latest source revision', (
    tester,
  ) async {
    final originalPlatform = InAppWebViewPlatform.instance;
    final platform = _EditorPlatform();
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () =>
          InAppWebViewPlatform.instance = originalPlatform ?? _EditorPlatform(),
    );
    final source = TextEditingController(text: 'x');
    final key = GlobalKey<MathFormulaFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathFormulaField(
            key: key,
            controller: source,
            mathematical: true,
            onModeChanged: (_) {},
            onActivate: () {},
            onChanged: () {},
            onSubmitted: () {},
            label: '公式 1',
          ),
        ),
      ),
    );
    final native = platform.editor!;
    final controller = native.controllerFromPlatform<InAppWebViewController>(
      native.controller,
    );
    native.params.onWebViewCreated!(controller);
    native.params.onLoadStop!(controller, null);
    await tester.pump();
    final stalledEvaluation = Completer<void>();
    native.controller.evaluationBlocker = stalledEvaluation;

    native.controller.sendMessage({'type': 'ready', 'revision': -1});
    await tester.pump();
    source.text = 'x+y';
    stalledEvaluation.complete();
    await tester.pumpAndSettle();

    expect(key.currentState!.ready, isTrue);
    expect(
      native.controller.scripts.where(
        (script) => script.contains('setSource') && script.contains('x+y'),
      ),
      hasLength(1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });

  testWidgets('late WebView creation cannot replace the current instance', (
    tester,
  ) async {
    final originalPlatform = InAppWebViewPlatform.instance;
    final platform = _EditorPlatform();
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () =>
          InAppWebViewPlatform.instance = originalPlatform ?? _EditorPlatform(),
    );
    final source = TextEditingController(text: 'x');
    final key = GlobalKey<MathFormulaFieldState>();
    Widget app(bool showWebView) => MaterialApp(
      home: Scaffold(
        body: MathFormulaField(
          key: key,
          controller: source,
          showWebView: showWebView,
          mathematical: true,
          onModeChanged: (_) {},
          onActivate: () {},
          onChanged: () {},
          onSubmitted: () {},
          label: '公式 1',
        ),
      ),
    );

    await tester.pumpWidget(app(true));
    final oldEditor = platform.editor!;
    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    final currentEditor = platform.editor!;
    expect(currentEditor, isNot(same(oldEditor)));

    final oldController = oldEditor
        .controllerFromPlatform<InAppWebViewController>(oldEditor.controller);
    oldEditor.params.onWebViewCreated!(oldController);
    oldEditor.controller.sendMessage({'type': 'ready', 'revision': -1});
    await tester.pump();
    expect(key.currentState!.ready, isFalse);
    expect(oldEditor.controller.scripts, isEmpty);

    final currentController = currentEditor
        .controllerFromPlatform<InAppWebViewController>(
          currentEditor.controller,
        );
    currentEditor.params.onWebViewCreated!(currentController);
    currentEditor.params.onLoadStop!(currentController, null);
    currentEditor.controller.sendMessage({'type': 'ready', 'revision': -1});
    await tester.pumpAndSettle();

    expect(key.currentState!.ready, isTrue);
    expect(
      currentEditor.controller.scripts.where(
        (script) => script.contains('setSource'),
      ),
      hasLength(1),
    );
    expect(
      currentEditor.controller.scripts.where(
        (script) => script.contains('.theme('),
      ),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });

  testWidgets('initial synchronization uses the latest theme', (tester) async {
    final originalPlatform = InAppWebViewPlatform.instance;
    final platform = _EditorPlatform();
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () =>
          InAppWebViewPlatform.instance = originalPlatform ?? _EditorPlatform(),
    );
    final source = TextEditingController(text: 'x');
    final key = GlobalKey<MathFormulaFieldState>();
    final light = ColorScheme.fromSeed(seedColor: Colors.blue);
    final dark = ColorScheme.fromSeed(
      seedColor: Colors.red,
      brightness: Brightness.dark,
    );
    Widget app(ColorScheme colors) => MaterialApp(
      theme: ThemeData(colorScheme: colors),
      home: Scaffold(
        body: MathFormulaField(
          key: key,
          controller: source,
          mathematical: true,
          onModeChanged: (_) {},
          onActivate: () {},
          onChanged: () {},
          onSubmitted: () {},
          label: '公式 1',
        ),
      ),
    );

    await tester.pumpWidget(app(light));
    final native = platform.editor!;
    final controller = native.controllerFromPlatform<InAppWebViewController>(
      native.controller,
    );
    native.params.onWebViewCreated!(controller);
    native.params.onLoadStop!(controller, null);
    await tester.pump();
    final stalledEvaluation = Completer<void>();
    native.controller.blockedEvaluationSource = '.theme(';
    native.controller.evaluationBlocker = stalledEvaluation;

    native.controller.sendMessage({'type': 'ready', 'revision': -1});
    await tester.pump();
    expect(key.currentState!.ready, isFalse);
    expect(
      native.controller.scripts.where((script) => script.contains('.theme(')),
      hasLength(1),
    );
    expect(native.controller.scripts.last, contains(_css(light.onSurface)));
    expect(native.controller.scripts.last, contains(_css(light.primary)));
    await tester.pumpWidget(app(dark));
    await tester.pump(const Duration(seconds: 1));
    stalledEvaluation.complete();
    await tester.pump();

    expect(key.currentState!.ready, isTrue);
    final themeScripts = native.controller.scripts.where(
      (script) => script.contains('.theme('),
    );
    expect(themeScripts, isNotEmpty);
    expect(themeScripts.last, contains(_css(dark.onSurface)));
    expect(themeScripts.last, contains(_css(dark.primary)));

    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });

  testWidgets('MathLive mount message enables native keyboard routing', (
    tester,
  ) async {
    final originalPlatform = InAppWebViewPlatform.instance;
    final platform = _EditorPlatform();
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () =>
          InAppWebViewPlatform.instance = originalPlatform ?? _EditorPlatform(),
    );
    final source = TextEditingController(text: 'x');
    final key = GlobalKey<MathFormulaFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathFormulaField(
            key: key,
            controller: source,
            mathematical: true,
            onModeChanged: (_) {},
            onActivate: () {},
            onChanged: () {},
            onSubmitted: () {},
            label: '公式 1',
          ),
        ),
      ),
    );
    final native = platform.editor!;
    final controller = native.controllerFromPlatform<InAppWebViewController>(
      native.controller,
    );
    native.params.onWebViewCreated!(controller);
    native.params.onLoadStop!(controller, null);
    await tester.pump();
    expect(key.currentState!.ready, isFalse);

    native.controller.sendMessage({'type': 'ready', 'revision': -1});
    await tester.pumpAndSettle();
    expect(key.currentState!.ready, isTrue);
    expect(
      native.controller.scripts.where((script) => script.contains('setSource')),
      hasLength(1),
    );
    expect(
      native.controller.scripts.where((script) => script.contains('.theme(')),
      hasLength(1),
    );
    await key.currentState!.command('insert', '+y');
    expect(
      native.controller.scripts.where((script) => script.contains('.command(')),
      hasLength(1),
    );
    expect(source.text, 'x');

    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });

  testWidgets(
    'theme changes recolor the retained native editor without reimport',
    (tester) async {
      final originalPlatform = InAppWebViewPlatform.instance;
      final platform = _EditorPlatform();
      InAppWebViewPlatform.instance = platform;
      addTearDown(
        () => InAppWebViewPlatform.instance =
            originalPlatform ?? _EditorPlatform(),
      );
      final source = TextEditingController(text: r'\frac{x}{2}');
      final key = GlobalKey<MathFormulaFieldState>();
      final light = ColorScheme.fromSeed(seedColor: Colors.blue);
      final dark = ColorScheme.fromSeed(
        seedColor: Colors.red,
        brightness: Brightness.dark,
      );
      Widget app(ColorScheme colors) => MaterialApp(
        theme: ThemeData(colorScheme: colors),
        home: Scaffold(
          body: MathFormulaField(
            key: key,
            controller: source,
            mathematical: true,
            onModeChanged: (_) {},
            onActivate: () {},
            onChanged: () {},
            onSubmitted: () {},
            label: '公式 1',
          ),
        ),
      );
      await tester.pumpWidget(app(light));
      final native = platform.editor!;
      expect(
        native.params.initialFile,
        'packages/visual_math/assets/vendor/mathlive/editor.html',
      );
      final controller = native.controllerFromPlatform<InAppWebViewController>(
        native.controller,
      );
      native.params.onWebViewCreated!(controller);
      native.params.onLoadStop!(controller, null);
      native.controller.sendMessage({'type': 'ready', 'revision': -1});
      await tester.pumpAndSettle();
      final state = key.currentState;
      final element = tester.element(find.byType(InAppWebView));
      expect(native.controller.scripts.last, contains(_css(light.onSurface)));
      await tester.pumpWidget(app(dark));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(InAppWebView)), same(element));
      expect(key.currentState, same(state));
      expect(native.controller.scripts.last, contains(_css(dark.onSurface)));
      expect(native.controller.scripts.last, contains(_css(dark.primary)));
      expect(
        native.controller.scripts.where((s) => s.contains('setSource')),
        hasLength(1),
      );
      expect(source.text, r'\frac{x}{2}');
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    },
  );

  testWidgets('native clipboard writer errors leave MathLive ready', (
    tester,
  ) async {
    await _withTargetPlatformOverride(TargetPlatform.android, () async {
      final originalPlatform = InAppWebViewPlatform.instance;
      final platform = _EditorPlatform();
      InAppWebViewPlatform.instance = platform;
      addTearDown(
        () => InAppWebViewPlatform.instance =
            originalPlatform ?? _EditorPlatform(),
      );
      final source = TextEditingController(text: 'x');
      final key = GlobalKey<MathFormulaFieldState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MathFormulaField(
              key: key,
              controller: source,
              mathematical: true,
              onModeChanged: (_) {},
              onActivate: () {},
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        ),
      );
      final native = platform.editor!;
      final controller = native.controllerFromPlatform<InAppWebViewController>(
        native.controller,
      );
      native.controller.cutSelectionResponse =
          '{"latex":"x","selection":"selection-1"}';
      native.params.onWebViewCreated!(controller);
      native.params.onLoadStop!(controller, null);
      native.controller.sendMessage({'type': 'ready', 'revision': -1});
      await tester.pumpAndSettle();
      final editor = key.currentState!;

      await expectLater(
        editor.clipboard(
          'copy',
          clipboardWriter: (_) async => throw StateError('host clipboard'),
        ),
        throwsStateError,
      );

      expect(editor.ready, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    });
  });

  testWidgets(
    'unsupported WebView platforms keep the built-in formula editor usable',
    (tester) async {
      await _withTargetPlatformOverride(TargetPlatform.linux, () async {
        final source = TextEditingController(text: 'x');
        final editorKey = GlobalKey<MathFormulaFieldState>();
        var mathematical = false;
        var activated = false;

        Widget app() => MaterialApp(
          home: Scaffold(
            body: MathFormulaField(
              key: editorKey,
              controller: source,
              mathematical: mathematical,
              onModeChanged: (value) => mathematical = value,
              onActivate: () => activated = true,
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        );

        await tester.pumpWidget(app());

        expect(MathFormulaField.supported, isFalse);
        expect(find.byType(InAppWebView), findsNothing);
        expect(find.byTooltip('切换到数学键盘（内置公式预览）'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);

        await tester.tap(find.byTooltip('切换到数学键盘（内置公式预览）'));
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(mathematical, isTrue);
        expect(editorKey.currentState!.ready, isTrue);
        expect(find.byType(Math), findsOneWidget);
        expect(find.byType(InAppWebView), findsNothing);

        final previewGesture = find
            .ancestor(
              of: find.byType(Math),
              matching: find.byType(GestureDetector),
            )
            .last;
        await tester.tap(previewGesture);
        await tester.pump();
        expect(activated, isTrue);
        await editorKey.currentState!.command('insert', '+y');
        expect(source.text, 'x+y');
        await editorKey.currentState!.command('navigate', 'left');
        await editorKey.currentState!.command('insert', 'z');
        expect(source.text, 'x+zy');
        await editorKey.currentState!.command('command', 'deleteBackward');
        expect(source.text, 'x+y');
        await editorKey.currentState!.command('command', 'undo');
        expect(source.text, 'x+zy');
        await editorKey.currentState!.command('command', 'redo');
        expect(source.text, 'x+y');

        source.value = const TextEditingValue(
          text: 'x😀',
          selection: TextSelection.collapsed(offset: 3),
        );
        await editorKey.currentState!.command('navigate', 'left');
        expect(source.selection.extentOffset, 1);
        await editorKey.currentState!.command('navigate', 'right');
        expect(source.selection.extentOffset, 3);
        await editorKey.currentState!.command('command', 'deleteBackward');
        expect(source.text, 'x');

        source.value = const TextEditingValue(
          text: 'word',
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        );
        await editorKey.currentState!.command('insert', 'word');
        expect(source.text, 'word');
        expect(source.selection, const TextSelection.collapsed(offset: 4));
        await editorKey.currentState!.command('insert', '!');
        expect(source.text, 'word!');

        await tester.tap(find.byTooltip('切换到 LaTeX 源码输入'));
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(mathematical, isFalse);
        expect(find.byType(TextField), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        source.dispose();
      });
    },
  );

  testWidgets('switching modes keeps draft and rendered editor identity', (
    tester,
  ) async {
    final source = TextEditingController(text: r'y=\frac{x^{2}+1}{2}');
    final editorKey = GlobalKey<MathFormulaFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathFormulaField(
            key: editorKey,
            controller: source,
            showWebView: false,
            mathematical: true,
            onModeChanged: (_) {},
            onActivate: () {},
            onChanged: () {},
            onSubmitted: () {},
            label: '公式 1',
          ),
        ),
      ),
    );
    final state = editorKey.currentState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathFormulaField(
            key: editorKey,
            controller: source,
            showWebView: false,
            mathematical: false,
            onModeChanged: (_) {},
            onActivate: () {},
            onChanged: () {},
            onSubmitted: () {},
            label: '公式 1',
          ),
        ),
      ),
    );
    expect(source.text, r'y=\frac{x^{2}+1}{2}');
    expect(editorKey.currentState, same(state));
    await tester.enterText(find.byType(TextField), r'\sqrt{x+1}');
    expect(source.text, r'\sqrt{x+1}');
    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });

  testWidgets('formula fallback copies only a nonempty selection', (
    tester,
  ) async {
    await _withTargetPlatformOverride(TargetPlatform.linux, () async {
      final copiedText = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          copiedText.add(arguments['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final source = TextEditingController(text: 'x+y');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MathFormulaField(
              controller: source,
              mathematical: true,
              onModeChanged: (_) {},
              onActivate: () {},
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        ),
      );
      final editor = tester.state<MathFormulaFieldState>(
        find.byType(MathFormulaField),
      );

      source.selection = const TextSelection.collapsed(offset: 3);
      await editor.clipboard('copy');
      source.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
      await editor.clipboard('copy');

      expect(copiedText, ['x']);
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    });
  });

  testWidgets('host clipboard callbacks preserve fallback selection handling', (
    tester,
  ) async {
    await _withTargetPlatformOverride(TargetPlatform.linux, () async {
      final writes = <String>[];
      final source = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'x+y',
          selection: TextSelection(baseOffset: 0, extentOffset: 1),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MathFormulaField(
              controller: source,
              mathematical: true,
              onModeChanged: (_) {},
              onActivate: () {},
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        ),
      );
      final editor = tester.state<MathFormulaFieldState>(
        find.byType(MathFormulaField),
      );

      await editor.clipboard(
        'copy',
        clipboardWriter: (text) async => writes.add(text),
      );
      await editor.clipboard('paste', clipboardReader: () async => 'z');

      expect(writes, ['x']);
      expect(source.text, 'z+y');
      expect(source.selection, const TextSelection.collapsed(offset: 1));
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    });
  });

  testWidgets('formula fallback paste inserts at the current selection', (
    tester,
  ) async {
    await _withTargetPlatformOverride(TargetPlatform.linux, () async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': 'z'};
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final source = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'x+y',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MathFormulaField(
              controller: source,
              mathematical: true,
              onModeChanged: (_) {},
              onActivate: () {},
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        ),
      );
      final editor = tester.state<MathFormulaFieldState>(
        find.byType(MathFormulaField),
      );

      await editor.clipboard('paste');

      expect(source.text, 'xz+y');
      expect(source.selection, const TextSelection.collapsed(offset: 2));
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    });
  });

  testWidgets('formula fallback paste does not edit a replacement controller', (
    tester,
  ) async {
    await _withTargetPlatformOverride(TargetPlatform.linux, () async {
      final clipboardRead = Completer<void>();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          await clipboardRead.future;
          return {'text': ' pasted'};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final original = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'x+y',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      final replacement = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'a+b',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      Widget app(TextEditingController controller) => MaterialApp(
        home: Scaffold(
          body: MathFormulaField(
            controller: controller,
            mathematical: true,
            onModeChanged: (_) {},
            onActivate: () {},
            onChanged: () {},
            onSubmitted: () {},
            label: '公式 1',
          ),
        ),
      );

      await tester.pumpWidget(app(original));
      final editor = tester.state<MathFormulaFieldState>(
        find.byType(MathFormulaField),
      );
      final paste = editor.clipboard('paste');
      await tester.pumpWidget(app(replacement));
      clipboardRead.complete();
      await paste;

      expect(original.text, 'x+y');
      expect(original.selection, const TextSelection.collapsed(offset: 3));
      expect(replacement.text, 'a+b');
      expect(replacement.selection, const TextSelection.collapsed(offset: 1));

      await tester.pumpWidget(const SizedBox.shrink());
      original.dispose();
      replacement.dispose();
    });
  });

  testWidgets('formula fallback vertical navigation preserves the column', (
    tester,
  ) async {
    await _withTargetPlatformOverride(TargetPlatform.linux, () async {
      final source = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'abc\nx\n12345',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MathFormulaField(
              controller: source,
              mathematical: true,
              onModeChanged: (_) {},
              onActivate: () {},
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        ),
      );
      final editor = tester.state<MathFormulaFieldState>(
        find.byType(MathFormulaField),
      );

      await editor.command('navigate', 'down');
      expect(source.selection.extentOffset, 5);
      await editor.command('navigate', 'down');
      expect(source.selection.extentOffset, 8);
      await editor.command('navigate', 'up');
      expect(source.selection.extentOffset, 5);
      await editor.command('navigate', 'up');
      expect(source.selection.extentOffset, 2);

      source.value = const TextEditingValue(
        text: 'a\n😀b\nxy',
        selection: TextSelection.collapsed(offset: 1),
      );
      await editor.command('navigate', 'down');
      expect(source.selection.extentOffset, 4);
      await editor.command('navigate', 'down');
      expect(source.selection.extentOffset, 7);
      await editor.command('navigate', 'up');
      expect(source.selection.extentOffset, 4);

      source.value = const TextEditingValue(
        text: 'a\ne\u0301b\nxy',
        selection: TextSelection.collapsed(offset: 1),
      );
      await editor.command('navigate', 'down');
      expect(source.selection.extentOffset, 4);

      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    });
  });

  testWidgets('formula fallback cut leaves a changed selection untouched', (
    tester,
  ) async {
    await _withTargetPlatformOverride(TargetPlatform.linux, () async {
      final clipboardWrite = Completer<void>();
      final copiedText = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          copiedText.add(arguments['text'] as String);
          await clipboardWrite.future;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final source = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'x+y',
          selection: TextSelection(baseOffset: 0, extentOffset: 1),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MathFormulaField(
              controller: source,
              mathematical: true,
              onModeChanged: (_) {},
              onActivate: () {},
              onChanged: () {},
              onSubmitted: () {},
              label: '公式 1',
            ),
          ),
        ),
      );
      final editor = tester.state<MathFormulaFieldState>(
        find.byType(MathFormulaField),
      );

      final cut = editor.clipboard('cut');
      source.selection = const TextSelection.collapsed(offset: 3);
      clipboardWrite.complete();
      await cut;

      expect(copiedText, ['x']);
      expect(source.text, 'x+y');
      expect(source.selection, const TextSelection.collapsed(offset: 3));

      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    });
  });

  testWidgets('formula fallback cut does not edit a replacement controller', (
    tester,
  ) async {
    await _withTargetPlatformOverride(TargetPlatform.linux, () async {
      final clipboardWrite = Completer<void>();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') await clipboardWrite.future;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final original = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'x+y',
          selection: TextSelection(baseOffset: 0, extentOffset: 1),
        ),
      );
      final replacement = TextEditingController.fromValue(original.value);
      Widget app(TextEditingController controller) => MaterialApp(
        home: Scaffold(
          body: MathFormulaField(
            controller: controller,
            mathematical: true,
            onModeChanged: (_) {},
            onActivate: () {},
            onChanged: () {},
            onSubmitted: () {},
            label: '公式 1',
          ),
        ),
      );

      await tester.pumpWidget(app(original));
      final editor = tester.state<MathFormulaFieldState>(
        find.byType(MathFormulaField),
      );
      final cut = editor.clipboard('cut');
      await tester.pumpWidget(app(replacement));
      clipboardWrite.complete();
      await cut;

      expect(original.text, 'x+y');
      expect(replacement.text, 'x+y');
      expect(
        replacement.selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      original.dispose();
      replacement.dispose();
    });
  });

  testWidgets('late rendered messages cannot overwrite a new source draft', (
    tester,
  ) async {
    final source = TextEditingController(text: 'x');
    final key = GlobalKey<MathFormulaFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathFormulaField(
            key: key,
            controller: source,
            showWebView: false,
            mathematical: true,
            onModeChanged: (_) {},
            onActivate: () {},
            onChanged: () {},
            onSubmitted: () {},
            label: '公式 1',
          ),
        ),
      ),
    );
    final oldRevision = key.currentState!.revision;
    source.text = 'x+1';
    key.currentState!.acceptSnapshot({'revision': oldRevision, 'latex': 'x+2'});
    expect(source.text, 'x+1');
    key.currentState!.acceptSnapshot({
      'revision': key.currentState!.revision,
      'latex': r'\frac{x}{2}',
      'edited': true,
      'sequence': 2,
    });
    expect(source.text, r'\frac{x}{2}');
    key.currentState!.acceptSnapshot({
      'revision': key.currentState!.revision,
      'latex': 'old',
      'edited': true,
      'sequence': 1,
    });
    expect(source.text, r'\frac{x}{2}');
    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });
}

String _css(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2)}';

class _EditorPlatform extends InAppWebViewPlatform {
  _NativeEditor? editor;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => editor = _NativeEditor(params);
}

class _NativeEditor extends PlatformInAppWebViewWidget {
  final controller = _EditorController();
  _NativeEditor(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

class _EditorController extends PlatformInAppWebViewController {
  final scripts = <String>[];
  String? cutSelectionResponse;
  String? blockedEvaluationSource;
  Completer<void>? evaluationBlocker;
  dynamic evaluationResponse;
  JavaScriptHandlerCallback? _javascriptHandler;
  _EditorController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
    if (evaluationBlocker != null &&
        (blockedEvaluationSource == null ||
            source.contains(blockedEvaluationSource!))) {
      await evaluationBlocker!.future;
    }
    if (source.contains('cutSelection')) return cutSelectionResponse;
    return evaluationResponse;
  }

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) => _javascriptHandler = callback;

  void sendMessage(Map<String, dynamic> message) =>
      _javascriptHandler?.call([message]);

  @override
  void dispose({bool isKeepAlive = false}) {}
}
