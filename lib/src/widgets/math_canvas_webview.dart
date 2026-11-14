import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/math_expression.dart';
import 'math_canvas_webview_loader.dart'
    if (dart.library.html) 'math_canvas_webview_loader_web.dart';

/// Callback types for WebView → Flutter communication.
typedef OnCoordinateUpdate = void Function(List<Map<String, dynamic>> points);
typedef OnViewportChange = void Function(
  double xMin,
  double yMin,
  double xMax,
  double yMax,
);
typedef OnReady = void Function();
typedef OnError = void Function(String message);

/// A WebView-based canvas that renders math functions using JSXGraph.
///
/// The generated page downloads JSXGraph JavaScript and CSS from jsDelivr when
/// loaded. Network access to `cdn.jsdelivr.net` is therefore required; this
/// widget has no pure-Flutter graph fallback.
///
/// This widget wraps [InAppWebView] with a full HTML page containing JSXGraph.
/// It provides two-way communication:
/// - Flutter → WebView: update expression, parameters, viewport
/// - WebView → Flutter: coordinate updates, viewport changes, ready signal
class MathCanvasWebView extends StatefulWidget {
  /// Initial JavaScript expression to plot.
  final String initialExpression;

  /// Counter for unique board IDs across multiple instances.
  static int _boardIdCounter = 0;

  /// Whether to show the WebView widget (false in tests to avoid platform issues).
  final bool initialShowWebView;

  /// Called when the WebView has loaded and JSXGraph is ready.
  final OnReady? onReady;

  /// Called when coordinate data is computed and sent from the WebView.
  final OnCoordinateUpdate? onCoordinateUpdate;

  /// Called when the viewport changes (user pans/zooms).
  final OnViewportChange? onViewportChange;

  /// Called when an error occurs in the WebView.
  final OnError? onError;

  const MathCanvasWebView({
    super.key,
    this.initialExpression = '',
    this.initialShowWebView = true,
    this.onReady,
    this.onCoordinateUpdate,
    this.onViewportChange,
    this.onError,
  });

  /// Build a complete HTML document with JSXGraph for 2D function plotting.
  ///
  /// The HTML includes:
  /// - JSXGraph library loaded from CDN
  /// - A board with axes, grid, pan, and zoom
  /// - JavaScript channel communication bridge for Flutter ↔ WebView
  /// - Dynamic expression updating via window.setExpression()
  /// - Coordinate reporting via onCoordinateUpdate callback
  /// - Viewport change reporting via onViewportChange callback
  static String buildMathHtml(
    String jsExpression, {
    Map<String, double> initialParameters = const {},
  }) {
    _boardIdCounter++;
    final boardId = 'jxgbox_$_boardIdCounter';
    final encodedExpression = jsonEncode(jsExpression)
        .replaceAll('<', r'\u003c')
        .replaceAll('\u2028', r'\u2028')
        .replaceAll('\u2029', r'\u2029');
    final safeInitialParameters = <String, double>{
      for (final entry in initialParameters.entries)
        if (RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(entry.key) &&
            entry.value.isFinite)
          entry.key: entry.value,
    };
    final encodedInitialParameters = jsonEncode(safeInitialParameters);

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <script src="https://cdn.jsdelivr.net/npm/jsxgraph/distrib/jsxgraphcore.js">
  </script>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/jsxgraph/distrib/jsxgraph.css" />
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: transparent;
    }
    #board-container {
      width: 100%;
      height: 100%;
      position: relative;
    }
    .JXGtext {
      font-family: 'Times New Roman', serif;
    }
    .error-message {
      position: absolute;
      top: 16px;
      left: 16px;
      right: 16px;
      padding: 12px 16px;
      background: rgba(220, 38, 38, 0.9);
      color: #fff;
      border-radius: 8px;
      font-family: monospace;
      font-size: 13px;
      z-index: 100;
      display: none;
    }
  </style>
</head>
<body>
  <div id="board-container">
    <div id="$boardId" style="width:100%;height:100%;"></div>
    <div class="error-message" id="error-message"></div>
  </div>

  <script>
    // ==================================================================
    // JSXGraph Board Initialization
    // ==================================================================
    var board = JXG.JSXGraph.initBoard('$boardId', {
      boundingbox: [-10, 10, 10, -10],
      axis: true,
      grid: true,
      showNavigation: false,
      showCopyright: false,
      keepaspectratio: true,
      pan: { enabled: true, needTwoFingers: false },
      zoom: { factorX: 1.25, factorY: 1.25 },
    });

    // Current plotted function curve (null if none)
    var currentCurve = null;

    // ==================================================================
    // Flutter Communication Bridge
    // ==================================================================
    // Send messages back to Flutter via the InAppWebView JavaScript channel.
    // The channel name must match the Flutter side: 'MathCanvasChannel'
    // ==================================================================

    function sendToFlutter(message) {
      var payload = JSON.stringify(message);
      try {
        if (window.flutter_inappwebview &&
            typeof window.flutter_inappwebview.callHandler === 'function') {
          window.flutter_inappwebview.callHandler('MathCanvasChannel', payload);
          return;
        }
      } catch(e) {
        console.error('Flutter bridge error:', e);
      }
      // The web implementation forwards same-origin iframe console messages.
      console.log('MATH_CANVAS_MESSAGE:' + payload);
    }

    // ==================================================================
    // Coordinate Tracking
    // ==================================================================
    // When plot is rendered, periodically sample points and send to Flutter
    // ==================================================================

    var coordinateTimer = null;

    function startCoordinateTracking(expression, paramStr) {
      stopCoordinateTracking();
      coordinateTimer = setInterval(function() {
        try {
          if (!board || !expression) return;
          var bbox = board.getBoundingBox();
          var xMin = bbox[0], yMin = bbox[3], xMax = bbox[2], yMax = bbox[1];
          var points = [];
          for (var i = 0; i <= 50; i++) {
            var fraction = i / 50;
            var x = xMin * (1 - fraction) + xMax * fraction;
            var func = new Function('x', paramStr + 'return (' + expression + String.fromCharCode(10) + ');');
            try {
              var y = func(x);
              if (isFinite(y) && y >= yMin - 1 && y <= yMax + 1) {
                points.push({x: x, y: y});
              }
            } catch(e) {
              // Skip invalid points
            }
          }
          sendToFlutter({
            type: 'coordinateUpdate',
            points: points.slice(0, 200) // Limit to 200 points
          });
        } catch(e) {
          // Coordinate tracking error - ignore
        }
      }, 1000);
    }

    function stopCoordinateTracking() {
      if (coordinateTimer) {
        clearInterval(coordinateTimer);
        coordinateTimer = null;
      }
    }

    // ==================================================================
    // Viewport Change Reporting
    // ==================================================================

    var lastViewportReport = 0;
    var viewportReportTimer = null;
    function reportViewport() {
      try {
        var bbox = board.getBoundingBox();
        sendToFlutter({
          type: 'viewportChange',
          xMin: bbox[0],
          yMin: bbox[3],
          xMax: bbox[2],
          yMax: bbox[1]
        });
      } catch(e) {}
    }

    board.on('boundingbox', function() {
      var now = Date.now();
      if (now - lastViewportReport >= 300) {
        lastViewportReport = now;
        if (viewportReportTimer !== null) {
          clearTimeout(viewportReportTimer);
          viewportReportTimer = null;
        }
        reportViewport();
        return;
      }

      if (viewportReportTimer === null) {
        viewportReportTimer = setTimeout(function() {
          viewportReportTimer = null;
          lastViewportReport = Date.now();
          reportViewport();
        }, 300 - (now - lastViewportReport));
      }
    });

    // ==================================================================
    // Plot Function
    // ==================================================================

    var currentExpression = $encodedExpression;
    var initialParameters = $encodedInitialParameters;
    var currentParameters = initialParameters || {};

    function plotFunction(expression, parameters) {
      try {
        // Remove old curve
        if (currentCurve) {
          board.removeObject(currentCurve);
          currentCurve = null;
        }

        if (!expression || expression.trim() === '') {
          currentExpression = expression;
          stopCoordinateTracking();
          hideError();
          return;
        }

        // Build the parameter scope
        var paramStr = 'var __vmParams = ' + JSON.stringify(parameters || {}) + '; ';
        if (parameters) {
          for (var key in parameters) {
            if (Object.prototype.hasOwnProperty.call(parameters, key) &&
                key !== 'Math' && key !== 'Number' && key !== 'NaN' && key !== 'x') {
              try {
                new Function('var ' + key + ';');
                paramStr += 'var ' + key + ' = ' + parameters[key] + '; ';
              } catch (_) {
                // Reserved JavaScript words are accessed through __vmParams.
              }
            }
          }
        }

        // Create a function that evaluates the expression
        var func = null;
        try {
          func = new Function('x', paramStr + 'return (' + expression + String.fromCharCode(10) + ');');
          // Test with a few values
          func(0);
          func(1);
          func(-1);
        } catch(e) {
          stopCoordinateTracking();
          showError('表达式语法错误: ' + e.message);
          return;
        }

        // Create the function plot
        try {
          currentCurve = board.create('functiongraph', [
            func,
            function() { return board.getBoundingBox()[0]; },
            function() { return board.getBoundingBox()[2]; }
          ], {
            strokeColor: '#3b82f6',
            strokeWidth: 2.5,
            highlightStrokeColor: '#2563eb',
            highlightStrokeWidth: 3,
          });
          hideError();
          currentExpression = expression;

          // Start sending coordinate data
          startCoordinateTracking(expression, paramStr);
        } catch(e) {
          showError('绘图错误: ' + e.message);
        }
      } catch(e) {
        showError('未知错误: ' + e.message);
      }
    }

    function showError(msg) {
      var el = document.getElementById('error-message');
      if (el) {
        el.textContent = msg;
        el.style.display = 'block';
      }
    }

    function hideError() {
      var el = document.getElementById('error-message');
      if (el) {
        el.style.display = 'none';
      }
    }

    // ==================================================================
    // Flutter → WebView API
    // ==================================================================
    // These functions are called from Flutter via evaluateJavascript.
    // ==================================================================

    // Set/update the expression to plot
    window.setExpression = function(expression, parameters) {
      try {
        currentParameters = parameters ? JSON.parse(parameters) : {};
        plotFunction(expression, currentParameters);
      } catch(e) {
        currentParameters = {};
        plotFunction(expression, currentParameters);
      }
    };

    // Update parameter values without changing the expression
    window.updateParameters = function(parametersJson) {
      try {
        var params = JSON.parse(parametersJson);
        currentParameters = Object.assign({}, currentParameters, params);
        plotFunction(currentExpression, currentParameters);
      } catch(e) {
        console.error('updateParameters error:', e);
      }
    };

    // Reset the view to default bounds
    window.resetView = function() {
      board.setBoundingBox([-10, 10, 10, -10]);
    };

    // Set viewport bounds
    window.setViewport = function(xMin, yMin, xMax, yMax) {
      if (![xMin, yMin, xMax, yMax].every(Number.isFinite) ||
          xMax <= xMin || yMax <= yMin) return;
      board.setBoundingBox([xMin, yMax, xMax, yMin]);
    };

    // ==================================================================
    // Initial Plot
    // ==================================================================

    // Plot initial expression if non-empty
    if (currentExpression) {
      plotFunction(currentExpression, initialParameters);
    }
    window.mathCanvasInitialized = true;
  </script>
</body>
</html>
''';
  }

  @override
  State<MathCanvasWebView> createState() => MathCanvasWebViewState();
}

/// The state class for [MathCanvasWebView], exposing methods that can be
/// called from the parent widget to control the canvas.
class _CanvasCommand {
  _CanvasCommand(this.source, this.completer, [this.onApplied]);
  final String source;
  final Completer<void>? completer;
  final VoidCallback? onApplied;
}

class MathCanvasWebViewState extends State<MathCanvasWebView> {
  InAppWebViewController? _webViewController;
  final _htmlLoader = MathCanvasHtmlLoader();
  bool _loadFinished = false;
  Set<String> _allowedParameters = {};
  final List<_CanvasCommand> _pendingCommands = [];
  String? _loadedInitialExpression;
  String? _appliedExpression;
  final Map<String, double> _appliedParameters = {};
  bool _pageReady = false;
  bool _startupComplete = false;
  InAppWebViewController? _drainingController;

  @override
  void initState() {
    super.initState();
    final parsed = MathExpression.fromInput(widget.initialExpression);
    _allowedParameters =
        parsed.isValid && parsed.type == MathExpressionType.explicit
        ? parsed.parameters
        : {};
  }

  Future<void> _enqueue(String source, [VoidCallback? onApplied]) async {
    final completer = _pageReady ? Completer<void>() : null;
    _pendingCommands.add(_CanvasCommand(source, completer, onApplied));
    unawaited(_drainCommands());
    if (completer != null) await completer.future;
  }

  Future<void> _drainCommands() async {
    if (!_pageReady ||
        _webViewController == null ||
        _drainingController == _webViewController)
      return;
    final ctrl = _webViewController!;
    _drainingController = ctrl;
    try {
      while (mounted &&
          _pageReady &&
          ctrl == _webViewController &&
          _pendingCommands.isNotEmpty) {
        final command = _pendingCommands.first;
        try {
          await ctrl.evaluateJavascript(source: command.source);
          if (!mounted || !_pageReady || ctrl != _webViewController) break;
          command.onApplied?.call();
          if (command.completer != null && !command.completer!.isCompleted) {
            command.completer!.complete();
          }
        } catch (e, stack) {
          if (!mounted || !_pageReady || ctrl != _webViewController) break;
          if (command.completer != null && !command.completer!.isCompleted) {
            command.completer!.completeError(e, stack);
          } else {
            debugPrint('[MathCanvas] Command failed: $e');
          }
        }
        _pendingCommands.removeAt(0);
      }
    } finally {
      if (_drainingController == ctrl) _drainingController = null;
    }
  }

  void _cancelPendingFutures() {
    for (final command in _pendingCommands) {
      if (command.completer != null && !command.completer!.isCompleted) {
        command.completer!.completeError(
          StateError('WebView was replaced or disposed'),
        );
      }
    }
    _pendingCommands.clear();
  }

  @override
  void didUpdateWidget(covariant MathCanvasWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialShowWebView && !widget.initialShowWebView) {
      _cancelPendingFutures();
      _webViewController = null;
      _loadFinished = false;
      _pageReady = false;
      _startupComplete = false;
    }
    if (!_startupComplete &&
        oldWidget.initialExpression != widget.initialExpression) {
      if (_webViewController != null || _pendingCommands.isNotEmpty) {
        if (_webViewController != null) {
          _loadedInitialExpression = widget.initialExpression;
        }
        unawaited(
          setExpression(widget.initialExpression, null).catchError((Object e) {
            debugPrint('[MathCanvas] Initial expression update failed: $e');
          }),
        );
      } else {
        final parsed = MathExpression.fromInput(widget.initialExpression);
        _allowedParameters =
            parsed.isValid && parsed.type == MathExpressionType.explicit
            ? parsed.parameters
            : {};
      }
    }
  }

  @override
  void dispose() {
    _cancelPendingFutures();
    _webViewController = null;
    _pageReady = false;
    _startupComplete = false;
    _pendingCommands.clear();
    _htmlLoader.dispose();
    super.dispose();
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    if (_webViewController != null) _cancelPendingFutures();
    if (_loadedInitialExpression == widget.initialExpression) {
      final replay = <_CanvasCommand>[];
      final expression = _appliedExpression;
      final parameters = Map<String, double>.of(_appliedParameters);
      if (expression != null) {
        replay.add(
          _CanvasCommand(expression, null, () {
            _appliedExpression = expression;
            _appliedParameters.clear();
          }),
        );
      }
      if (parameters.isNotEmpty) {
        replay.add(
          _CanvasCommand(
            'window.updateParameters(${jsonEncode(jsonEncode(parameters))});',
            null,
            () => _appliedParameters.addAll(parameters),
          ),
        );
      }
      _pendingCommands.insertAll(0, replay);
    }
    _loadedInitialExpression = widget.initialExpression;
    _appliedExpression = null;
    _appliedParameters.clear();
    _webViewController = controller;
    _loadFinished = false;
    _pageReady = false;
    _startupComplete = false;

    // Set up JavaScript channel for WebView → Flutter communication.
    // The web platform of flutter_inappwebview does not implement
    // addJavaScriptHandler (UnimplementedError). Guard the registration so
    // the initial HTML below still loads on web — only the message bridge
    // is unavailable there.
    try {
      controller.addJavaScriptHandler(
        handlerName: 'MathCanvasChannel',
        callback: (args) {
          if (args.isEmpty) return;
          try {
            final message =
                jsonDecode(args[0] as String) as Map<String, dynamic>;
            _handleWebViewMessage(message);
          } catch (e) {
            debugPrint('[MathCanvas] Failed to parse WebView message: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('[MathCanvas] JS handler bridge unavailable: $e');
    }

    // Load initial HTML
    final initialParsed = MathExpression.fromInput(widget.initialExpression);
    final initialAllowedParameters =
        initialParsed.isValid &&
            initialParsed.type == MathExpressionType.explicit
        ? initialParsed.parameters
        : <String>{};
    if (!_pendingCommands.any(
      (command) => command.source.startsWith('window.setExpression('),
    )) {
      _allowedParameters = initialAllowedParameters;
    }
    final initialExpression =
        widget.initialExpression.isNotEmpty &&
            initialParsed.isValid &&
            initialParsed.type == MathExpressionType.explicit
        ? MathExpression.toJsExpression(widget.initialExpression)
        : '';
    final initialParameters = {
      for (final name in initialAllowedParameters) name: 1.0,
    };
    final html = MathCanvasWebView.buildMathHtml(
      initialExpression,
      initialParameters: initialParameters,
    );
    _htmlLoader.load(controller, html);
  }

  void _handleWebViewMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    switch (type) {
      case 'coordinateUpdate':
        final points =
            (message['points'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        widget.onCoordinateUpdate?.call(points);
        break;
      case 'viewportChange':
        final xMin = (message['xMin'] as num?)?.toDouble() ?? -10;
        final yMin = (message['yMin'] as num?)?.toDouble() ?? -10;
        final xMax = (message['xMax'] as num?)?.toDouble() ?? 10;
        final yMax = (message['yMax'] as num?)?.toDouble() ?? 10;
        widget.onViewportChange?.call(xMin, yMin, xMax, yMax);
        break;
      default:
        debugPrint('[MathCanvas] Unknown message type: $type');
    }
  }

  // -----------------------------------------------------------------
  // Public API called by parent widget
  // -----------------------------------------------------------------

  /// Set/update the expression to plot on the canvas.
  Future<void> setExpression(
    String expression,
    Map<String, double>? parameters,
  ) async {
    final parsed = MathExpression.fromInput(expression);
    final isSafeExpression =
        parsed.isValid && parsed.type == MathExpressionType.explicit;
    _allowedParameters = isSafeExpression ? parsed.parameters : {};
    final jsExpression = isSafeExpression
        ? MathExpression.toJsExpression(expression)
        : '';
    final allowedParameters = isSafeExpression ? parsed.parameters : <String>{};
    final safeParameters = <String, double>{
      for (final name in allowedParameters) name: 1.0,
    };
    if (parameters != null) {
      for (final entry in parameters.entries) {
        if (allowedParameters.contains(entry.key) &&
            RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(entry.key) &&
            entry.value.isFinite) {
          safeParameters[entry.key] = entry.value;
        }
      }
    }
    final paramsJson = safeParameters.isNotEmpty
        ? jsonEncode(safeParameters)
        : null;
    await _enqueue(
      'window.setExpression(${jsonEncode(jsExpression)}, ${jsonEncode(paramsJson)});',
      () {
        _appliedExpression =
            'window.setExpression(${jsonEncode(jsExpression)}, ${jsonEncode(paramsJson)});';
        _appliedParameters.clear();
      },
    );
  }

  /// Update parameter values without changing the expression.
  Future<void> updateParameters(Map<String, double> parameters) async {
    final safeParameters = <String, double>{};
    for (final entry in parameters.entries) {
      if (_allowedParameters.contains(entry.key) &&
          RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(entry.key) &&
          entry.value.isFinite) {
        safeParameters[entry.key] = entry.value;
      }
    }
    final paramsJson = jsonEncode(safeParameters);
    await _enqueue('window.updateParameters(${jsonEncode(paramsJson)});', () {
      _appliedParameters.addAll(safeParameters);
    });
  }

  /// Reset the viewport to the default bounds.
  Future<void> resetView() async {
    await _enqueue('window.resetView();');
  }

  /// Set the viewport to specific bounds.
  Future<void> setViewport(
    double xMin,
    double yMin,
    double xMax,
    double yMax,
  ) async {
    if (!xMin.isFinite ||
        !yMin.isFinite ||
        !xMax.isFinite ||
        !yMax.isFinite ||
        xMax <= xMin ||
        yMax <= yMin) {
      return;
    }
    await _enqueue('window.setViewport($xMin, $yMin, $xMax, $yMax);');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.initialShowWebView) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: true,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            disableDefaultErrorPage: true,
            supportZoom: false,
          ),
          onWebViewCreated: _onWebViewCreated,
          onConsoleMessage: (ctrl, consoleMessage) {
            const prefix = 'MATH_CANVAS_MESSAGE:';
            if (!consoleMessage.message.startsWith(prefix)) return;
            try {
              final message = jsonDecode(
                consoleMessage.message.substring(prefix.length),
              ) as Map<String, dynamic>;
              _handleWebViewMessage(message);
            } catch (e) {
              debugPrint('[MathCanvas] Failed to parse WebView message: $e');
            }
          },
          onLoadStop: (ctrl, url) async {
            if (_loadFinished || ctrl.platform != _webViewController?.platform)
              return;
            var initialized = false;
            try {
              initialized =
                  await ctrl.evaluateJavascript(
                    source: 'window.mathCanvasInitialized === true',
                  ) ==
                  true;
            } catch (e) {
              debugPrint('[MathCanvas] Initialization check failed: $e');
            }
            if (!mounted ||
                _loadFinished ||
                ctrl.platform != _webViewController?.platform)
              return;
            setState(() {
              _loadFinished = true;
            });
            if (initialized) {
              _pageReady = true;
              await _drainCommands();
              if (mounted && ctrl.platform == _webViewController?.platform) {
                _startupComplete = true;
                widget.onReady?.call();
              }
            } else {
              widget.onError?.call('绘图引擎初始化失败');
            }
          },
          onReceivedError: (ctrl, request, error) {
            if (request.isForMainFrame == false ||
                _loadFinished ||
                ctrl.platform != _webViewController?.platform)
              return;
            debugPrint('[MathCanvas] Load error: ${error.description}');
            if (mounted) setState(() => _loadFinished = true);
            widget.onError?.call('WebView加载失败: ${error.description}');
          },
        ),
        // Loading overlay
        if (!_loadFinished)
          Positioned.fill(
            child: Container(
              color: cs.surface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '加载绘图引擎...',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
