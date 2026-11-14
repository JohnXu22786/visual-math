import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('failed graph initialization reports an error instead of ready', (
    tester,
  ) async {
    final previous = InAppWebViewPlatform.instance;
    final platform = _CanvasPlatform();
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () => InAppWebViewPlatform.instance = previous ?? _CanvasPlatform(),
    );
    var ready = 0;
    final errors = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MathCanvasWebView(onReady: () => ready++, onError: errors.add),
      ),
    );
    final view = platform.view!;
    final controller = view.controllerFromPlatform<InAppWebViewController>(
      view.controller,
    );
    view.params.onWebViewCreated!(controller);
    view.params.onLoadStop!(
      view.controllerFromPlatform<InAppWebViewController>(view.controller),
      null,
    );
    await tester.pump();
    expect(ready, 0);
    expect(errors, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    platform.initialized = true;
    ready = 0;
    errors.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: MathCanvasWebView(onReady: () => ready++, onError: errors.add),
      ),
    );
    final successView = platform.view!;
    final successController = successView
        .controllerFromPlatform<InAppWebViewController>(successView.controller);
    successView.params.onWebViewCreated!(successController);
    successView.params.onLoadStop!(
      successView.controllerFromPlatform<InAppWebViewController>(
        successView.controller,
      ),
      null,
    );
    await tester.pump();
    expect(ready, 1);
    expect(errors, isEmpty);
  });

  testWidgets('web console bridge dispatches canvas callbacks', (tester) async {
    final previous = InAppWebViewPlatform.instance;
    final platform = _CanvasPlatform()..initialized = true;
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () => InAppWebViewPlatform.instance = previous ?? _CanvasPlatform(),
    );
    List<Map<String, dynamic>>? points;
    List<double>? viewport;
    await tester.pumpWidget(
      MaterialApp(
        home: MathCanvasWebView(
          onCoordinateUpdate: (value) => points = value,
          onViewportChange: (xMin, yMin, xMax, yMax) =>
              viewport = [xMin, yMin, xMax, yMax],
        ),
      ),
    );
    final view = platform.view!;
    final controller = view.controllerFromPlatform<InAppWebViewController>(
      view.controller,
    );
    view.params.onWebViewCreated!(controller);

    final html = MathCanvasWebView.buildMathHtml('x');
    expect(html, contains("console.log('MATH_CANVAS_MESSAGE:' + payload)"));
    final onConsoleMessage = view.params.onConsoleMessage;
    expect(onConsoleMessage, isNotNull);
    onConsoleMessage!(
      controller,
      ConsoleMessage(
        message: 'MATH_CANVAS_MESSAGE:{"type":"coordinateUpdate","points":[{"x":1,"y":2}]}',
      ),
    );
    onConsoleMessage(
      controller,
      ConsoleMessage(
        message: 'MATH_CANVAS_MESSAGE:{"type":"viewportChange","xMin":-2,"yMin":-3,"xMax":4,"yMax":5}',
      ),
    );

    expect(points, [
      {'x': 1, 'y': 2},
    ]);
    expect(viewport, [-2, -3, 4, 5]);
  });

  testWidgets('startup commands are replayed in order after initialization', (
    tester,
  ) async {
    final previous = InAppWebViewPlatform.instance;
    final platform = _CanvasPlatform()..initialized = true;
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () => InAppWebViewPlatform.instance = previous ?? _CanvasPlatform(),
    );
    final key = GlobalKey<MathCanvasWebViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: MathCanvasWebView(key: key, initialExpression: 'a*x'),
      ),
    );
    await key.currentState!.updateParameters({'a': 2});
    await key.currentState!.setExpression('', null);
    await key.currentState!.setExpression('b*x', {'b': 3});
    final view = platform.view!;
    final controller = view.controllerFromPlatform<InAppWebViewController>(
      view.controller,
    );
    view.params.onWebViewCreated!(controller);
    await key.currentState!.updateParameters({'b': 4});
    await key.currentState!.setViewport(-2, -3, 4, 5);
    await key.currentState!.resetView();
    expect(view.controller.sources, isEmpty);
    view.params.onLoadStop!(controller, null);
    await tester.pump();
    expect(
      view.controller.sources.first,
      'window.mathCanvasInitialized === true',
    );
    final commands = view.controller.sources.skip(1).toList();
    expect(commands, hasLength(6));
    expect(commands[0], contains(r'\"a\":2'));
    expect(commands[1], contains('window.setExpression("",'));
    expect(commands[2], contains(r'\"b\":3'));
    expect(commands[3], contains(r'\"b\":4'));
    expect(commands[4], 'window.setViewport(-2.0, -3.0, 4.0, 5.0);');
    expect(commands[5], 'window.resetView();');
  });

  testWidgets(
    'replacement settles interrupted commands and replays their expression',
    (tester) async {
      final previous = InAppWebViewPlatform.instance;
      final platform = _CanvasPlatform()..initialized = true;
      InAppWebViewPlatform.instance = platform;
      addTearDown(
        () => InAppWebViewPlatform.instance = previous ?? _CanvasPlatform(),
      );
      final key = GlobalKey<MathCanvasWebViewState>();
      Widget canvas(bool visible) => MaterialApp(
        home: MathCanvasWebView(key: key, initialShowWebView: visible),
      );
      await tester.pumpWidget(canvas(true));
      final first = platform.view!;
      final controller = first.controllerFromPlatform<InAppWebViewController>(
        first.controller,
      );
      first.params.onWebViewCreated!(controller);
      first.params.onLoadStop!(controller, null);
      await tester.pump();
      await key.currentState!.setExpression('a*x', {'a': 2});
      first.controller.gate = Completer<void>();
      final pending = key.currentState!.updateParameters({'a': 4});
      final result = pending.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      await tester.pumpWidget(canvas(false));
      expect(await result, isA<StateError>());
      await tester.pumpWidget(canvas(true));
      final second = platform.view!;
      final secondController = second
          .controllerFromPlatform<InAppWebViewController>(second.controller);
      second.params.onWebViewCreated!(secondController);
      second.params.onLoadStop!(secondController, null);
      await tester.pump();
      expect(second.controller.sources[1], contains('window.setExpression'));
      expect(second.controller.sources, hasLength(2));
      first.controller.gate!.complete();
      await tester.pump();
    },
  );

  testWidgets('completed commands do not override a new initial expression', (
    tester,
  ) async {
    final previous = InAppWebViewPlatform.instance;
    final platform = _CanvasPlatform()..initialized = true;
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () => InAppWebViewPlatform.instance = previous ?? _CanvasPlatform(),
    );
    final key = GlobalKey<MathCanvasWebViewState>();
    Widget canvas(bool visible, String expression) => MaterialApp(
      home: MathCanvasWebView(
        key: key,
        initialShowWebView: visible,
        initialExpression: expression,
      ),
    );
    await tester.pumpWidget(canvas(true, 'a*x'));
    final first = platform.view!;
    final controller = first.controllerFromPlatform<InAppWebViewController>(
      first.controller,
    );
    first.params.onWebViewCreated!(controller);
    first.params.onLoadStop!(controller, null);
    await tester.pump();
    await key.currentState!.setExpression('a*x', {'a': 3});
    await tester.pumpWidget(canvas(false, 'b*x'));
    await key.currentState!.updateParameters({'b': 5});
    await tester.pumpWidget(canvas(true, 'b*x'));
    final second = platform.view!;
    final secondController = second
        .controllerFromPlatform<InAppWebViewController>(second.controller);
    second.params.onWebViewCreated!(secondController);
    second.params.onLoadStop!(secondController, null);
    await tester.pump();
    expect(second.controller.sources, hasLength(2));
    expect(second.controller.sources.last, contains(r'\"b\":5'));
  });

  testWidgets(
    'initial expression changes during loading follow earlier commands',
    (tester) async {
      final previous = InAppWebViewPlatform.instance;
      final platform = _CanvasPlatform()..initialized = true;
      InAppWebViewPlatform.instance = platform;
      addTearDown(
        () => InAppWebViewPlatform.instance = previous ?? _CanvasPlatform(),
      );
      final key = GlobalKey<MathCanvasWebViewState>();
      Widget canvas(String expression, [bool visible = true]) => MaterialApp(
        home: MathCanvasWebView(
          key: key,
          initialExpression: expression,
          initialShowWebView: visible,
        ),
      );
      await tester.pumpWidget(canvas('a*x'));
      final view = platform.view!;
      final controller = view.controllerFromPlatform<InAppWebViewController>(
        view.controller,
      );
      view.params.onWebViewCreated!(controller);
      await key.currentState!.setExpression('c*x', {'c': 3});
      await tester.pumpWidget(canvas('b*x'));
      await key.currentState!.updateParameters({'b': 4});
      view.params.onLoadStop!(controller, null);
      await tester.pump();
      expect(view.controller.sources, hasLength(4));
      expect(view.controller.sources[1], contains(r'\"c\":3'));
      expect(view.controller.sources[2], contains(r'\"b\":1.0'));
      expect(view.controller.sources[3], contains(r'\"b\":4'));
      await tester.pumpWidget(canvas('b*x', false));
      await tester.pumpWidget(canvas('b*x'));
      final next = platform.view!;
      final nextController = next
          .controllerFromPlatform<InAppWebViewController>(next.controller);
      next.params.onWebViewCreated!(nextController);
      next.params.onLoadStop!(nextController, null);
      await tester.pump();
      expect(next.controller.sources.last, contains(r'\"b\":4'));
    },
  );

  testWidgets(
    'replacement restores applied expression before new parameter updates',
    (tester) async {
      final previous = InAppWebViewPlatform.instance;
      final platform = _CanvasPlatform()..initialized = true;
      InAppWebViewPlatform.instance = platform;
      addTearDown(
        () => InAppWebViewPlatform.instance = previous ?? _CanvasPlatform(),
      );
      final key = GlobalKey<MathCanvasWebViewState>();
      Widget canvas(bool visible) => MaterialApp(
        home: MathCanvasWebView(key: key, initialShowWebView: visible),
      );
      await tester.pumpWidget(canvas(true));
      final first = platform.view!;
      final controller = first.controllerFromPlatform<InAppWebViewController>(
        first.controller,
      );
      first.params.onWebViewCreated!(controller);
      first.params.onLoadStop!(controller, null);
      await tester.pump();
      await key.currentState!.setExpression('a*x', {'a': 3});
      await tester.pumpWidget(canvas(false));
      await tester.pumpWidget(canvas(true));
      final second = platform.view!;
      final nextController = second
          .controllerFromPlatform<InAppWebViewController>(second.controller);
      second.params.onWebViewCreated!(nextController);
      await key.currentState!.updateParameters({'a': 4});
      second.params.onLoadStop!(nextController, null);
      await tester.pump();
      expect(second.controller.sources[1], contains(r'\"a\":3'));
      expect(second.controller.sources[2], contains(r'\"a\":4'));
    },
  );

  testWidgets('initial expression changes while startup commands drain', (
    tester,
  ) async {
    final previous = InAppWebViewPlatform.instance;
    final platform = _CanvasPlatform()..initialized = true;
    InAppWebViewPlatform.instance = platform;
    addTearDown(
      () => InAppWebViewPlatform.instance = previous ?? _CanvasPlatform(),
    );
    final key = GlobalKey<MathCanvasWebViewState>();
    Widget canvas(String expression) => MaterialApp(
      home: MathCanvasWebView(key: key, initialExpression: expression),
    );
    await tester.pumpWidget(canvas('a*x'));
    final view = platform.view!;
    final controller = view.controllerFromPlatform<InAppWebViewController>(
      view.controller,
    );
    view.params.onWebViewCreated!(controller);
    await key.currentState!.setExpression('c*x', {'c': 3});
    view.params.onLoadStop!(controller, null);
    view.controller.gate = Completer<void>();
    await tester.pump();
    await tester.pumpWidget(canvas('b*x'));
    view.controller.gate!.complete();
    view.controller.gate = null;
    await tester.pump();
    expect(view.controller.sources.last, contains(r'\"b\":1.0'));
  });

  group('MathCanvasWebView - buildMathHtml', () {
    test('replaces EXPRESSION_PLACEHOLDER with JS expression', () {
      final html = MathCanvasWebView.buildMathHtml('Math.pow(x,2)');
      expect(html, contains('Math.pow(x,2)'));
      expect(html, isNot(contains('EXPRESSION_PLACEHOLDER')));
    });

    test('preserves multiline expressions without ending the script', () {
      const expression = "x +\n1 + '\\' + \"</ScRiPt>\"";
      final html = MathCanvasWebView.buildMathHtml(expression);
      final match = RegExp(r'var currentExpression = (.*);').firstMatch(html);

      expect(match, isNotNull);
      expect(jsonDecode(match!.group(1)!), expression);
      expect(html.toLowerCase().split('</script>'), hasLength(3));
    });

    test('creates unique board ID', () {
      final html1 = MathCanvasWebView.buildMathHtml('x^2');
      final html2 = MathCanvasWebView.buildMathHtml('x^2');
      expect(html1, isNot(equals(html2)));
    });

    test('reports the latest viewport after throttled changes', () {
      final html = MathCanvasWebView.buildMathHtml('x');
      final reporter = RegExp(
        r'function reportViewport\(\) \{([\s\S]*?)\n    \}',
      ).firstMatch(html);
      final trailingReport = RegExp(
        r'viewportReportTimer = setTimeout\(function\(\) \{([\s\S]*?)\n        \}, 300 - \(now - lastViewportReport\)\);',
      ).firstMatch(html);

      expect(html, contains('var viewportReportTimer = null;'));
      expect(reporter, isNotNull);
      expect(
        reporter!.group(1),
        contains('var bbox = board.getBoundingBox();'),
      );
      expect(reporter.group(1), contains("type: 'viewportChange'"));
      expect(reporter.group(1), contains('xMin: bbox[0]'));
      expect(reporter.group(1), contains('yMin: bbox[3]'));
      expect(reporter.group(1), contains('xMax: bbox[2]'));
      expect(reporter.group(1), contains('yMax: bbox[1]'));
      expect(trailingReport, isNotNull);
      expect(
        trailingReport!.group(1),
        contains('lastViewportReport = Date.now();'),
      );
      expect(trailingReport.group(1), contains('reportViewport();'));
      expect(html, contains('}, 300 - (now - lastViewportReport));'));
    });
  });
}

class _CanvasPlatform extends InAppWebViewPlatform {
  _CanvasView? view;
  bool initialized = false;
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => view = _CanvasView(params, initialized);
}

class _CanvasView extends PlatformInAppWebViewWidget {
  final _CanvasController controller;
  _CanvasView(super.params, bool initialized)
    : controller = _CanvasController(initialized),
      super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {}
}

class _CanvasController extends PlatformInAppWebViewController {
  final bool initialized;
  final sources = <String>[];
  Completer<void>? gate;
  _CanvasController(this.initialized)
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    sources.add(source);
    if (gate != null) await gate!.future;
    return initialized;
  }

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {}
  @override
  Future<void> loadData({
    required String data,
    String mimeType = 'text/html',
    String encoding = 'utf8',
    WebUri? baseUrl,
    Uri? androidHistoryUrl,
    WebUri? historyUrl,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {}
  @override
  void dispose({bool isKeepAlive = false}) {}
}
