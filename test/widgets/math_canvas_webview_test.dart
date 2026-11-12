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

  group('MathCanvasWebView - buildMathHtml', () {
    test('replaces EXPRESSION_PLACEHOLDER with JS expression', () {
      final html = MathCanvasWebView.buildMathHtml('Math.pow(x,2)');
      expect(html, contains('Math.pow(x,2)'));
      expect(html, isNot(contains('EXPRESSION_PLACEHOLDER')));
    });

    test('creates unique board ID', () {
      final html1 = MathCanvasWebView.buildMathHtml('x^2');
      final html2 = MathCanvasWebView.buildMathHtml('x^2');
      expect(html1, isNot(equals(html2)));
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
  _CanvasController(this.initialized)
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => initialized;
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
