import 'dart:async';

import 'package:flutter/foundation.dart' as foundation;
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

  testWidgets('queued native cut does not delete from an inactive formula', (
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
      await tester.pumpAndSettle();

      final block = Completer<void>();
      var active = true;
      late Future<void> flush;
      final cut = key.currentState!.clipboard(
        'cut',
        isTargetActive: () => active,
        clipboardWriter: (_) async {
          native.controller.snapshotBlock = block.future;
          flush = key.currentState!.flush();
        },
      );
      await tester.pump();
      expect(native.controller.scripts.last, contains('snapshot()'));
      active = false;
      block.complete();
      await flush;
      await cut;
      expect(
        native.controller.scripts.where((s) => s.contains('deleteSelection')),
        isEmpty,
      );
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
  Future<void>? snapshotBlock;
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
    if (source.contains('cutSelection')) return cutSelectionResponse;
    if (source.contains('snapshot()')) await snapshotBlock;
    return null;
  }

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {}

  @override
  void dispose({bool isKeepAlive = false}) {}
}
