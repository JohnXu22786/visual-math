import 'package:flutter/foundation.dart';

/// Runtime platform capabilities relevant to workspace integration.
///
/// These describe package behavior, not build success or host configuration.
class MathWorkspaceCapabilities {
  const MathWorkspaceCapabilities({
    required this.mathLiveEditor,
    required this.sourceEditorFallback,
    required this.mathCanvasWebViewRequiresNetwork,
    required this.flutterCanvasesRequireNetwork,
  });

  /// Whether this runtime supports the embedded MathLive WebView editor.
  final bool mathLiveEditor;

  /// Whether formula source editing and preview are available as fallback.
  final bool sourceEditorFallback;

  /// The separately exported JSXGraph WebView canvas fetches assets online.
  final bool mathCanvasWebViewRequiresNetwork;

  /// The package's primary Flutter 2D and 3D canvases render offline.
  final bool flutterCanvasesRequireNetwork;

  static const _mathLivePlatforms = <TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  };

  /// Capabilities detected for the current Flutter runtime.
  static MathWorkspaceCapabilities get current => MathWorkspaceCapabilities(
    mathLiveEditor:
        !kIsWeb && _mathLivePlatforms.contains(defaultTargetPlatform),
    sourceEditorFallback: true,
    mathCanvasWebViewRequiresNetwork: true,
    flutterCanvasesRequireNetwork: false,
  );
}
