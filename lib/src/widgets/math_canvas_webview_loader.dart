import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MathCanvasHtmlLoader {
  Future<void> load(InAppWebViewController controller, String html) =>
      controller.loadData(data: html, mimeType: 'text/html', encoding: 'utf8');

  void dispose() {}
}
