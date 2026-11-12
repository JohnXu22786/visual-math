// Blob URLs inherit the parent origin, allowing the web plugin to access the
// iframe. Data URLs have an opaque origin and cannot be inspected by it.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MathCanvasHtmlLoader {
  String? _url;

  Future<void> load(InAppWebViewController controller, String data) {
    dispose();
    final url = web.URL.createObjectURL(
      web.Blob([data.toJS].toJS, web.BlobPropertyBag(type: 'text/html')),
    );
    _url = url;
    return controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void dispose() {
    if (_url != null) web.URL.revokeObjectURL(_url!);
    _url = null;
  }
}
