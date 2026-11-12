import 'dart:math' as dart_math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../models/math_expression.dart' show MathExpression, MathExpressionType;
import '../models/formula_entry.dart';
import 'math_ui_tokens.dart';

/// Callback types for canvas → parent communication.
typedef OnCoordinateUpdate = void Function(List<Map<String, double>> points);
typedef OnViewportChange = void Function(
  double xMin,
  double yMin,
  double xMax,
  double yMax,
);
typedef OnReady = void Function();
typedef OnError = void Function(String message);

/// A pure-Flutter canvas for plotting mathematical functions.
///
/// Uses [CustomPainter] for rendering and [GestureDetector] for
/// pan/zoom interactions — no WebView or external JS dependencies.
///
/// Features:
/// - Adaptive grid lines based on viewport range
/// - Axes with arrows and tick labels
/// - Smooth function curve rendering
/// - Touch/mouse pan and zoom
/// - Coordinate data export
class MathCanvas extends StatefulWidget {
  /// Optional initial expression to plot, such as `x^2` or `sin(x)`.
  final String? initialExpression;

  /// Called after the canvas has initialized and can accept updates.
  final OnReady? onReady;

  /// Called with sampled plot coordinates after a plot is updated.
  final OnCoordinateUpdate? onCoordinateUpdate;

  /// Called with the visible x and y bounds after pan or zoom.
  final OnViewportChange? onViewportChange;

  /// Called when an expression cannot be parsed or plotted.
  final OnError? onError;

  /// Whether touch and stylus gestures can pan or zoom the canvas.
  final bool allowTouchGestures;

  /// Whether mouse and trackpad gestures and wheel signals can navigate.
  final bool allowMouseGestures;

  /// Creates a Flutter-rendered 2D graph canvas.
  const MathCanvas({
    super.key,
    this.initialExpression,
    this.onReady,
    this.onCoordinateUpdate,
    this.onViewportChange,
    this.onError,
    this.allowTouchGestures = true,
    this.allowMouseGestures = true,
  });

  @override
  State<MathCanvas> createState() => MathCanvasState();
}

/// Internal pairing of a formula entry with its sampled curve points.
///
/// For explicit functions, [polylines] has one entry (the y=f(x) curve).
/// For implicit equations, [polylines] has many short segments (the
/// zero-contour line segments from marching squares).
class _FormulaCurve {
  final FormulaEntry formula;
  final List<List<Map<String, double>>> polylines;
  const _FormulaCurve({required this.formula, this.polylines = const []});
}

/// The state class for [MathCanvas], exposing methods that can be
/// called from the parent widget to control the canvas.
class MathCanvasState extends State<MathCanvas> {
  // Viewport state (math coordinates)
  double _xMin = -10;
  double _yMin = -10;
  double _xMax = 10;
  double _yMax = 10;

  // Formula state (multi-formula support)
  final List<_FormulaCurve> _formulaCurves = [];

  // Gesture state
  Offset? _lastFocalPoint;
  double? _lastScale;
  bool _isReady = false;
  bool _showAxes = true;
  bool _showGrid = true;
  bool _showZeros = false;
  bool _showExtrema = false;

  bool get showAxes => _showAxes;
  bool get showGrid => _showGrid;
  bool get showZeros => _showZeros;
  bool get showExtrema => _showExtrema;

  void setDisplaySettings({
    required bool showAxes,
    required bool showGrid,
    required bool showZeros,
    required bool showExtrema,
  }) {
    setState(() {
      _showAxes = showAxes;
      _showGrid = showGrid;
      _showZeros = showZeros;
      _showExtrema = showExtrema;
    });
  }

  // Widget size
  double _canvasWidth = 1;
  double _canvasHeight = 1;

  @override
  void initState() {
    super.initState();
    // Defer initial setup to next frame to avoid setState during parent build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialExpression != null &&
          widget.initialExpression!.isNotEmpty) {
        final expr = MathExpression.fromInput(widget.initialExpression!);
        if (expr.isValid) {
          final formula = FormulaEntry(
            rawExpression: widget.initialExpression!,
            parsed: expr,
            color: formulaPalette[0],
            autoColor: true,
          );
          _formulaCurves.add(
            _FormulaCurve(formula: formula, polylines: _sampleCurve(formula)),
          );
        }
      }
      if (!_isReady) {
        setState(() => _isReady = true);
        widget.onReady?.call();
      }
    });
  }

  // ==================================================================
  // Public API
  // ==================================================================

  /// Set all formulas to plot (replaces any existing formulas).
  Future<void> setFormulas(List<FormulaEntry> newFormulas) async {
    setState(() {
      _formulaCurves
        ..clear()
        ..addAll(
          newFormulas.map(
            (f) => _FormulaCurve(formula: f, polylines: _sampleCurve(f)),
          ),
        );
    });
    final allPoints = _formulaCurves
        .expand((fc) => fc.polylines.expand((pl) => pl))
        .toList();
    widget.onCoordinateUpdate?.call(allPoints);
  }

  /// Backward-compat: set a single expression.
  Future<void> setExpression(
    String expression,
    Map<String, double>? parameters,
  ) async {
    if (expression.isEmpty) {
      await setFormulas([]);
      return;
    }
    final parsed = MathExpression.fromInput(
      expression,
      parameterValues: parameters ?? {},
    );
    if (!parsed.isValid) {
      widget.onError?.call(parsed.parseError ?? '表达式错误');
      return;
    }
    final formula = FormulaEntry(
      rawExpression: expression,
      parsed: parsed,
      color: Colors.blue,
      autoColor: true,
      parameterValues: parameters ?? {},
    );
    await setFormulas([formula]);
  }

  /// Reset the viewport to the default bounds.
  Future<void> resetView() async {
    setState(() {
      _xMin = -10;
      _yMin = -10;
      _xMax = 10;
      _yMax = 10;
      for (int i = 0; i < _formulaCurves.length; i++) {
        _formulaCurves[i] = _FormulaCurve(
          formula: _formulaCurves[i].formula,
          polylines: _sampleCurve(_formulaCurves[i].formula),
        );
      }
    });
    widget.onCoordinateUpdate?.call(curvePoints);
    widget.onViewportChange?.call(_xMin, _yMin, _xMax, _yMax);
  }

  /// Fit the plotted formulas into the current canvas.
  Future<void> fitToView() async {
    if (_canvasWidth <= 0 || _canvasHeight <= 0) return;

    // Keep fitting to this finite domain, since expressions can be unbounded.
    final fittedCurves = _formulaCurves
        .map(
          (curve) => _FormulaCurve(
            formula: curve.formula,
            polylines: _sampleCurve(curve.formula, includePanMargin: false),
          ),
        )
        .toList();
    final points = fittedCurves
        .expand((curve) => curve.polylines)
        .expand((polyline) => polyline)
        .where(
          (point) =>
              (point['x'] ?? double.nan).isFinite &&
              (point['y'] ?? double.nan).isFinite,
        );
    var xMin = double.infinity;
    var xMax = double.negativeInfinity;
    var yMin = double.infinity;
    var yMax = double.negativeInfinity;
    for (final point in points) {
      final x = point['x']!;
      final y = point['y']!;
      if (x < xMin) xMin = x;
      if (x > xMax) xMax = x;
      if (y < yMin) yMin = y;
      if (y > yMax) yMax = y;
    }
    if (!xMin.isFinite || !xMax.isFinite || !yMin.isFinite || !yMax.isFinite) {
      await resetView();
      return;
    }

    final aspectRatio = _canvasWidth / _canvasHeight;
    const padding = 1.1;
    final xRange = dart_math
        .max(
          dart_math.max(xMax - xMin, (yMax - yMin) * aspectRatio) * padding,
          0.1,
        )
        .toDouble();
    final yRange = xRange / aspectRatio;
    final centerX = (xMin + xMax) / 2;
    final centerY = (yMin + yMax) / 2;
    setState(() {
      _xMin = centerX - xRange / 2;
      _yMin = centerY - yRange / 2;
      _xMax = centerX + xRange / 2;
      _yMax = centerY + yRange / 2;
      _formulaCurves
        ..clear()
        ..addAll(fittedCurves);
      _resampleAll();
    });
    widget.onCoordinateUpdate?.call(curvePoints);
    widget.onViewportChange?.call(_xMin, _yMin, _xMax, _yMax);
  }

  /// Zoom toward the canvas center by one toolbar step.
  void zoomIn() => _zoomByRangeFactor(1 / 1.2);

  /// Zoom away from the canvas center by one toolbar step.
  void zoomOut() => _zoomByRangeFactor(1.2);

  void _zoomByRangeFactor(double factor, {Offset? focalPoint}) {
    if (!factor.isFinite ||
        factor <= 0 ||
        _canvasWidth <= 0 ||
        _canvasHeight <= 0) {
      return;
    }
    final point = focalPoint ?? Offset(_canvasWidth / 2, _canvasHeight / 2);
    final fx = _screenToMathX(point.dx);
    final fy = _screenToMathY(point.dy);
    final oldXRange = _xMax - _xMin;
    final (oldYMin, oldYMax) = _effectiveYBounds();
    final newXRange = oldXRange * factor;
    final newYRange = (oldYMax - oldYMin) * factor;

    setState(() {
      _xMin = fx - (fx - _xMin) * factor;
      _xMax = _xMin + newXRange;
      _yMin = fy - (fy - oldYMin) * factor;
      _yMax = _yMin + newYRange;
      _resampleAll();
    });
    widget.onCoordinateUpdate?.call(curvePoints);
    widget.onViewportChange?.call(_xMin, _yMin, _xMax, _yMax);
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
        yMax <= yMin ||
        !(xMax - xMin).isFinite ||
        !(yMax - yMin).isFinite) {
      return;
    }
    setState(() {
      _xMin = xMin;
      _yMin = yMin;
      _xMax = xMax;
      _yMax = yMax;
      for (int i = 0; i < _formulaCurves.length; i++) {
        _formulaCurves[i] = _FormulaCurve(
          formula: _formulaCurves[i].formula,
          polylines: _sampleCurve(_formulaCurves[i].formula),
        );
      }
    });
    widget.onCoordinateUpdate?.call(curvePoints);
    widget.onViewportChange?.call(_xMin, _yMin, _xMax, _yMax);
  }

  /// Get the current viewport bounds.
  (double xMin, double yMin, double xMax, double yMax) get viewport =>
      (_xMin, _yMin, _xMax, _yMax);

  /// Get all current curve points (from all formulas).
  List<Map<String, double>> get curvePoints =>
      _formulaCurves.expand((fc) => fc.polylines.expand((pl) => pl)).toList();

  /// Get the sampled line segments for each formula.
  List<List<Map<String, double>>> get curveSegments => [
    for (final formula in _formulaCurves)
      for (final segment in formula.polylines) segment,
  ];

  // ==================================================================
  // Build helpers for painter
  // ==================================================================

  /// Flatten all formula polylines into a list for the painter.
  List<List<Map<String, double>>> _buildCurvesList() {
    final result = <List<Map<String, double>>>[];
    for (final fc in _formulaCurves) {
      for (final poly in fc.polylines) {
        if (poly.length >= 2) result.add(poly);
      }
    }
    return result;
  }

  /// Build a parallel list of colors matching [_buildCurvesList].
  List<Color> _buildColorsList() {
    final result = <Color>[];
    for (final fc in _formulaCurves) {
      for (final poly in fc.polylines) {
        if (poly.length >= 2) result.add(fc.formula.color);
      }
    }
    return result;
  }

  List<(double, double, Color)> _buildCharacteristicPoints() {
    if (!_showZeros && !_showExtrema) return const [];
    final result = <(double, double, Color)>[];
    for (final curve in _formulaCurves) {
      if (curve.formula.parsed?.type != MathExpressionType.explicit) continue;
      for (final points in curve.polylines) {
        double? lastTouchingZero;
        for (var i = 1; i < points.length; i++) {
          final p0 = points[i - 1];
          final p1 = points[i];
          final x0 = p0['x']!;
          final y0 = p0['y']!;
          final x1 = p1['x']!;
          final y1 = p1['y']!;
          if (_showZeros && (y0 == 0 || y1 == 0 || y0.sign != y1.sign)) {
            final t = y1 == y0 ? 0.0 : (-y0 / (y1 - y0)).clamp(0.0, 1.0);
            result.add((x0 + (x1 - x0) * t, 0, curve.formula.color));
          }
          if (_showZeros && i + 1 < points.length) {
            final p2 = points[i + 1];
            final y2 = p2['y']!;
            // A touching root is a local minimum of |f| with no sign change.
            if (y0 != 0 &&
                y1 != 0 &&
                y2 != 0 &&
                y0.sign == y1.sign &&
                y1.sign == y2.sign &&
                y1.abs() <= y0.abs() &&
                y1.abs() <= y2.abs() &&
                (y1.abs() < y0.abs() || y1.abs() < y2.abs())) {
              try {
                final evaluate = curve.formula.parsed!.evaluator;
                var left = x0;
                var right = p2['x']!;
                for (var step = 0; step < 256; step++) {
                  final a = left + (right - left) / 3;
                  final b = right - (right - left) / 3;
                  final ya = evaluate(a).abs();
                  final yb = evaluate(b).abs();
                  if (!ya.isFinite || !yb.isFinite) break;
                  if (ya < yb) {
                    right = b;
                  } else {
                    left = a;
                  }
                }
                // Only emit an evaluated zero. A small residual could also be
                // a nonzero extremum, so uncertain candidates are omitted.
                final x = x0 <= 0 && p2['x']! >= 0 && evaluate(0) == 0
                    ? 0.0
                    : (left + right) / 2;
                if (evaluate(x) == 0 &&
                    (lastTouchingZero == null ||
                        (x - lastTouchingZero).abs() >
                            (x1 - x0).abs() * 1e-6)) {
                  result.add((x, 0, curve.formula.color));
                  lastTouchingZero = x;
                }
              } catch (_) {
                // An invalid probe leaves this extremum uncertain.
              }
            }
          }
          if (_showExtrema && i + 1 < points.length) {
            final y2 = points[i + 1]['y']!;
            if ((y0 < y1 && y1 > y2) || (y0 > y1 && y1 < y2)) {
              result.add((x1, y1, curve.formula.color));
            }
          }
        }
      }
    }
    return result;
  }

  // ==================================================================
  // Internal: expression handling
  // ==================================================================

  /// How much extra to sample beyond the visible viewport, as a fraction
  /// of the viewport range on each side.
  ///
  /// A value of 1.0 means we sample 100% beyond each edge, so the total
  /// sampled range is 3× the viewport width. This ensures that during
  /// pan gestures the curves remain fully visible without requiring a
  /// costly resample on every frame.
  ///
  /// Tuned to cover one full canvas-width of finger travel before the
  /// edge of the sampled data is reached (pan is 1:1 with the finger),
  /// which comfortably accommodates normal interaction.
  static const double _renderMarginScale = 1.0;

  /// Sample a formula at the current viewport, optionally extending it by
  /// [_renderMarginScale] on each side for smooth drag rendering.
  ///
  /// For explicit functions this returns a single polyline; for implicit
  /// equations it returns many short contour segments (marching squares).
  List<List<Map<String, double>>> _sampleCurve(
    FormulaEntry formula, {
    bool includePanMargin = true,
  }) {
    if (!formula.isValid) return [];
    final parsed = formula.parsed!;
    final marginScale = includePanMargin ? _renderMarginScale : 0.0;
    final marginX = (_xMax - _xMin) * marginScale;
    final domainStart = _resolveDomainValue(
      formula.domainStartExpression,
      formula.parameterValues,
    );
    final domainEnd = _resolveDomainValue(
      formula.domainEndExpression,
      formula.parameterValues,
    );
    if ((formula.domainStartExpression?.trim().isNotEmpty == true &&
            domainStart == null) ||
        (formula.domainEndExpression?.trim().isNotEmpty == true &&
            domainEnd == null)) {
      return [];
    }
    final sampleMin = dart_math.max(
      _xMin - marginX,
      domainStart ?? double.negativeInfinity,
    );
    final sampleMax = dart_math.min(
      _xMax + marginX,
      domainEnd ?? double.infinity,
    );
    if (sampleMin >= sampleMax) return [];
    if (parsed.type == MathExpressionType.implicit) {
      final (effectiveYMin, effectiveYMax) = _effectiveYBounds();
      final marginY = (effectiveYMax - effectiveYMin) * marginScale;
      // Contour segments — each is a short line across one grid cell.
      // Extend bounds and proportionally increase grid cells so that
      // contour detail remains consistent across the visible area.
      final scale = 1.0 + 2.0 * marginScale;
      final contours = parsed.sampleContourSegments(
        xMin: sampleMin,
        xMax: sampleMax,
        yMin: effectiveYMin - marginY,
        yMax: effectiveYMax + marginY,
        gridX: (80 * scale).round().clamp(80, 200),
        gridY: (80 * scale).round().clamp(80, 200),
      );
      return [
        for (final segment in contours)
          if (_clipContourSegment(
                segment,
                domainStart: domainStart,
                domainEnd: domainEnd,
                includeStart: formula.includeDomainStart,
                includeEnd: formula.includeDomainEnd,
              )
              case final clipped?)
            clipped,
      ];
    }
    // Sample well beyond viewport bounds to ensure curves reach the
    // canvas edges during pan/zoom without visible holes in the graph.
    // With _renderMarginScale=1.0, this yields scalePoints=3.0 (3× points).
    final scalePoints = 1.0 + 2.0 * marginScale;
    final segments = parsed.samplePointSegments(
      xMin: sampleMin,
      xMax: sampleMax,
      numPoints: (300 * scalePoints).round().clamp(300, 1200),
    );
    return [
      for (final segment in segments)
        [
          for (final point in segment)
            if ((domainStart == null ||
                    point['x']! > domainStart ||
                    (formula.includeDomainStart &&
                        point['x'] == domainStart)) &&
                (domainEnd == null ||
                    point['x']! < domainEnd ||
                    (formula.includeDomainEnd && point['x'] == domainEnd)))
              point,
        ],
    ];
  }

  List<Map<String, double>>? _clipContourSegment(
    List<Map<String, double>> segment, {
    required double? domainStart,
    required double? domainEnd,
    required bool includeStart,
    required bool includeEnd,
  }) {
    if (segment.length < 2) return null;
    final first = segment.first;
    final last = segment.last;
    final x0 = first['x']!;
    final dx = last['x']! - x0;
    if (dx == 0) {
      if (domainStart != null &&
          (x0 < domainStart || (!includeStart && x0 == domainStart))) {
        return null;
      }
      if (domainEnd != null &&
          (x0 > domainEnd || (!includeEnd && x0 == domainEnd))) {
        return null;
      }
      return [first, last];
    }

    var startT = 0.0;
    var endT = 1.0;
    if (domainStart != null) {
      final t = (domainStart - x0) / dx;
      if (dx > 0) {
        startT = dart_math.max(startT, t);
        if (!includeStart && t >= 0 && t <= 1) {
          startT = dart_math.max(startT, t + 1e-9);
        }
      } else {
        endT = dart_math.min(endT, t);
        if (!includeStart && t >= 0 && t <= 1) {
          endT = dart_math.min(endT, t - 1e-9);
        }
      }
    }
    if (domainEnd != null) {
      final t = (domainEnd - x0) / dx;
      if (dx > 0) {
        endT = dart_math.min(endT, t);
        if (!includeEnd && t >= 0 && t <= 1) {
          endT = dart_math.min(endT, t - 1e-9);
        }
      } else {
        startT = dart_math.max(startT, t);
        if (!includeEnd && t >= 0 && t <= 1) {
          startT = dart_math.max(startT, t + 1e-9);
        }
      }
    }
    if (startT >= endT) return null;

    Map<String, double> interpolate(double t) => {
      'x': x0 + dx * t,
      'y': first['y']! + (last['y']! - first['y']!) * t,
    };
    return [interpolate(startT), interpolate(endT)];
  }

  double? _resolveDomainValue(String? source, Map<String, double> parameters) {
    if (source == null || source.trim().isEmpty) return null;
    final expression = MathExpression.fromInput(
      source,
      parameterValues: parameters,
    );
    if (!expression.isValid) return null;
    final value = expression.evaluator(0);
    return value.isFinite ? value : null;
  }

  // ==================================================================
  // Gesture handling (pan + zoom)
  // ==================================================================

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
    _lastScale = 1.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final focalPoint = details.localFocalPoint;
    final scale = details.scale;

    // Calculate focal point in math coordinates before zoom
    final fx = _screenToMathX(focalPoint.dx);
    final fy = _screenToMathY(focalPoint.dy);

    // Determine if this is a pan or zoom
    if (details.pointerCount == 1 ||
        (scale == 1.0 && focalPoint != _lastFocalPoint)) {
      // Pan 1:1 — the graph tracks the finger exactly.
      //
      // GraphPainter renders both axes with the same pixels-per-unit
      // scale (canvasWidth / xRange; it re-derives the y range from the
      // viewport and canvas aspect ratio to keep units isotropic), so the
      // viewport must shift by that same math-per-pixel amount on both
      // axes. A plain 0.5 damping factor used to halve the movement.
      final dx = _lastFocalPoint == null
          ? 0.0
          : focalPoint.dx - _lastFocalPoint!.dx;
      final dy = _lastFocalPoint == null
          ? 0.0
          : focalPoint.dy - _lastFocalPoint!.dy;
      final perPixel = (_xMax - _xMin) / _canvasWidth;

      setState(() {
        _xMin -= dx * perPixel;
        _xMax -= dx * perPixel;
        _yMin += dy * perPixel;
        _yMax += dy * perPixel;
      });
    } else if (scale != 1.0 && _lastScale != null) {
      // Zoom: scale around focal point
      final scaleChange = scale / _lastScale!;
      final newXRange = (_xMax - _xMin) / scaleChange;
      final (effectiveYMin, effectiveYMax) = _effectiveYBounds();
      final newYRange = (effectiveYMax - effectiveYMin) / scaleChange;

      setState(() {
        _xMin = fx - (fx - _xMin) / scaleChange;
        _xMax = _xMin + newXRange;
        _yMin = fy - (fy - effectiveYMin) / scaleChange;
        _yMax = _yMin + newYRange;
      });
    }

    _lastFocalPoint = focalPoint;
    _lastScale = scale;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _lastFocalPoint = null;
    _lastScale = null;
    // Resample all formulas after gesture ends for smooth result
    setState(() {
      _resampleAll();
    });
    final allPoints = curvePoints;
    widget.onCoordinateUpdate?.call(allPoints);
    widget.onViewportChange?.call(_xMin, _yMin, _xMax, _yMax);
  }

  /// Resample all formulas at the current viewport (updates _formulaCurves).
  void _resampleAll() {
    for (int i = 0; i < _formulaCurves.length; i++) {
      _formulaCurves[i] = _FormulaCurve(
        formula: _formulaCurves[i].formula,
        polylines: _sampleCurve(_formulaCurves[i].formula),
      );
    }
  }

  // Mouse wheel zoom
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    // Scroll up zooms in; scroll down zooms out.
    final zoomFactor = 1.0 + event.scrollDelta.dy * 0.001;
    final clampedFactor = zoomFactor.clamp(0.1, 10.0).toDouble();
    _zoomByRangeFactor(clampedFactor, focalPoint: event.localPosition);
  }

  // ==================================================================
  // Coordinate conversion
  // ==================================================================

  double _screenToMathX(double screenX) {
    return screenX / _canvasWidth * (_xMax - _xMin) + _xMin;
  }

  double _screenToMathY(double screenY) {
    final (effectiveYMin, effectiveYMax) = _effectiveYBounds();
    return (1.0 - screenY / _canvasHeight) * (effectiveYMax - effectiveYMin) +
        effectiveYMin;
  }

  /// Match the aspect-corrected vertical bounds used by [GraphPainter].
  (double, double) _effectiveYBounds() {
    if (_canvasWidth <= 0 || _canvasHeight <= 0) return (_yMin, _yMax);
    final aspectRatio = _canvasWidth / _canvasHeight;
    if (!aspectRatio.isFinite || aspectRatio <= 0) return (_yMin, _yMax);
    final yRange = (_xMax - _xMin) / aspectRatio;
    if (!yRange.isFinite) return (_yMin, _yMax);
    final yCenter = _yMin + (_yMax - _yMin) / 2;
    final effectiveYMin = yCenter - yRange / 2;
    final effectiveYMax = yCenter + yRange / 2;
    if (!effectiveYMin.isFinite || !effectiveYMax.isFinite) {
      return (_yMin, _yMax);
    }
    return (effectiveYMin, effectiveYMax);
  }

  // ==================================================================
  // Build
  // ==================================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final dimensionsChanged =
            width != _canvasWidth || height != _canvasHeight;
        _canvasWidth = width;
        _canvasHeight = height;
        if (dimensionsChanged && _formulaCurves.isNotEmpty) {
          _resampleAll();
        }

        final supportedDevices =
            widget.allowTouchGestures && widget.allowMouseGestures
            ? null
            : <PointerDeviceKind>{
                if (widget.allowTouchGestures) PointerDeviceKind.touch,
                if (widget.allowTouchGestures) PointerDeviceKind.stylus,
                if (widget.allowTouchGestures) PointerDeviceKind.invertedStylus,
                if (widget.allowMouseGestures) PointerDeviceKind.mouse,
                if (widget.allowMouseGestures) PointerDeviceKind.trackpad,
              };
        return GestureDetector(
          supportedDevices: supportedDevices,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Listener(
            onPointerSignal: widget.allowMouseGestures
                ? _onPointerSignal
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MathUiTokens.cornerRadius),
              child: CustomPaint(
                painter: GraphPainter(
                  xMin: _xMin,
                  yMin: _yMin,
                  xMax: _xMax,
                  yMax: _yMax,
                  curves: _buildCurvesList(),
                  curveColors: _buildColorsList(),
                  showAxes: _showAxes,
                  showGrid: _showGrid,
                  characteristicPoints: _buildCharacteristicPoints(),
                  backgroundColor: cs.surface,
                  gridColor: cs.outlineVariant.withValues(alpha: 0.5),
                  axisColor: cs.onSurface,
                  labelColor: cs.onSurfaceVariant,
                ),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Arrow direction for axis tips.
enum ArrowDirection { up, right }

// ======================================================================
// GraphPainter — CustomPainter that renders the math graph
// ======================================================================

/// A [CustomPainter] that renders a mathematical graph with:
/// - Adaptive grid lines
/// - Coordinate axes with arrows
/// - Tick labels
/// - One or more function curves
class GraphPainter extends CustomPainter {
  /// Viewport bounds in math coordinates.
  final double xMin, yMin, xMax, yMax;

  /// Curve data: list of (x, y) coordinate pairs per curve.
  final List<List<Map<String, double>>> curves;

  /// Colors for each curve.
  final List<Color> curveColors;
  final bool showAxes;
  final bool showGrid;
  final List<(double, double, Color)> characteristicPoints;

  final Color backgroundColor;
  final Color gridColor;
  final Color axisColor;
  final Color labelColor;

  const GraphPainter({
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    this.curves = const [],
    this.curveColors = const [],
    this.showAxes = true,
    this.showGrid = true,
    this.characteristicPoints = const [],
    this.backgroundColor = Colors.white,
    this.gridColor = const Color(0x80CCCCCC),
    this.axisColor = Colors.black87,
    this.labelColor = Colors.grey,
  });

  /// The effective yMin that maintains 1:1 pixel aspect ratio.
  /// Computed from the canvas aspect ratio to avoid stretching.
  double _effectiveYMin(double canvasWidth, double canvasHeight) {
    if (canvasWidth <= 0 || canvasHeight <= 0) return yMin;
    final aspectRatio = canvasWidth / canvasHeight;
    final xRange = xMax - xMin;
    if (xRange <= 0) return yMin;
    final targetYRange = xRange / aspectRatio;
    final yCenter = (yMin + yMax) / 2.0;
    return yCenter - targetYRange / 2.0;
  }

  /// The effective yMax that maintains 1:1 pixel aspect ratio.
  double _effectiveYMax(double canvasWidth, double canvasHeight) {
    if (canvasWidth <= 0 || canvasHeight <= 0) return yMax;
    final aspectRatio = canvasWidth / canvasHeight;
    final xRange = xMax - xMin;
    if (xRange <= 0) return yMax;
    final targetYRange = xRange / aspectRatio;
    final yCenter = (yMin + yMax) / 2.0;
    return yCenter + targetYRange / 2.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    final eYMin = _effectiveYMin(size.width, size.height);
    final eYMax = _effectiveYMax(size.width, size.height);
    if (showGrid) _drawGrid(canvas, size, eYMin, eYMax);
    if (showAxes) _drawAxes(canvas, size, eYMin, eYMax);
    _drawCurves(canvas, size, eYMin, eYMax);
    _drawCharacteristicPoints(canvas, size, eYMin, eYMax);
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.xMin != xMin ||
        oldDelegate.yMin != yMin ||
        oldDelegate.xMax != xMax ||
        oldDelegate.yMax != yMax ||
        oldDelegate.curves != curves ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.curveColors != curveColors ||
        oldDelegate.showAxes != showAxes ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.characteristicPoints != characteristicPoints;
  }

  // ==================================================================
  // Coordinate conversion
  // ==================================================================

  double _mathToScreenX(double mathX, double width) {
    return (mathX - xMin) / (xMax - xMin) * width;
  }

  double _mathToScreenY(
    double mathY,
    double height,
    double eYMin,
    double eYMax,
  ) {
    return (1.0 - (mathY - eYMin) / (eYMax - eYMin)) * height;
  }

  Offset _mathToScreen(
    double mathX,
    double mathY,
    Size size,
    double eYMin,
    double eYMax,
  ) {
    return Offset(
      _mathToScreenX(mathX, size.width),
      _mathToScreenY(mathY, size.height, eYMin, eYMax),
    );
  }

  // ==================================================================
  // Background
  // ==================================================================

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  // ==================================================================
  // Adaptive grid
  // ==================================================================

  /// Calculate a "nice" grid spacing based on the viewport range.
  /// Returns values like 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50...
  static double _niceStep(double range, int targetTicks) {
    if (range <= 0) return 1.0;
    final roughStep = range / targetTicks;
    final magnitude = dart_math.pow(
      10,
      (dart_math.log(roughStep) / dart_math.ln10).floor(),
    );
    final residual = roughStep / magnitude;

    double niceStep;
    if (residual <= 1.5) {
      niceStep = 1;
    } else if (residual <= 3.5) {
      niceStep = 2;
    } else if (residual <= 7.5) {
      niceStep = 5;
    } else {
      niceStep = 10;
    }

    return niceStep * magnitude;
  }

  double _firstGridTick(double minimum, double step) {
    final quotient = minimum / step;
    if (!quotient.isFinite) return minimum;
    final tick = quotient.ceil() * step;
    return tick.isFinite ? tick : minimum;
  }

  void _drawGrid(Canvas canvas, Size size, double eYMin, double eYMax) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    // Use the same step for both axes so they have the same number of cells.
    final step = _niceStep((xMax - xMin) / 2 + (eYMax - eYMin) / 2, 8);

    // Vertical grid lines
    double gx = _firstGridTick(xMin, step);
    while (gx <= xMax) {
      if (gx.abs() > 1e-10) {
        // Skip axis line (drawn separately)
        final screenX = _mathToScreenX(gx, size.width);
        canvas.drawLine(
          Offset(screenX, 0),
          Offset(screenX, size.height),
          gridPaint,
        );
      }
      final next = gx + step;
      if (!next.isFinite || next <= gx) break;
      gx = next;
    }

    // Horizontal grid lines (using effective y bounds for 1:1 aspect ratio)
    double gy = _firstGridTick(eYMin, step);
    while (gy <= eYMax) {
      if (gy.abs() > 1e-10) {
        // Skip axis line
        final screenY = _mathToScreenY(gy, size.height, eYMin, eYMax);
        canvas.drawLine(
          Offset(0, screenY),
          Offset(size.width, screenY),
          gridPaint,
        );
      }
      final next = gy + step;
      if (!next.isFinite || next <= gy) break;
      gy = next;
    }
  }

  // ==================================================================
  // Axes
  // ==================================================================

  void _drawAxes(Canvas canvas, Size size, double eYMin, double eYMax) {
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final arrowPaint = Paint()
      ..color = axisColor
      ..style = PaintingStyle.fill;

    final labelTextStyle = TextStyle(
      color: labelColor,
      fontSize: 10,
      fontWeight: FontWeight.w400,
    );

    // X-axis (y = 0)
    if (eYMin <= 0 && eYMax >= 0) {
      final y0 = _mathToScreenY(0, size.height, eYMin, eYMax);
      canvas.drawLine(Offset(0, y0), Offset(size.width, y0), axisPaint);

      // X-axis arrow
      _drawArrow(
        canvas,
        Offset(size.width, y0),
        arrowPaint,
        direction: ArrowDirection.right,
      );

      // X-axis label
      final textPainter = TextPainter(
        text: TextSpan(text: 'x', style: labelTextStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(size.width - textPainter.width - 4, y0 - 16),
      );
    }

    // Y-axis (x = 0)
    if (xMin <= 0 && xMax >= 0) {
      final x0 = _mathToScreenX(0, size.width);
      canvas.drawLine(Offset(x0, 0), Offset(x0, size.height), axisPaint);

      // Y-axis arrow
      _drawArrow(
        canvas,
        Offset(x0, 0),
        arrowPaint,
        direction: ArrowDirection.up,
      );

      // Y-axis label
      final textPainter = TextPainter(
        text: TextSpan(text: 'y', style: labelTextStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x0 + 6, 4));
    }

    // Tick labels
    _drawTickLabels(canvas, size, labelTextStyle, eYMin, eYMax);
  }

  void _drawTickLabels(
    Canvas canvas,
    Size size,
    TextStyle style,
    double eYMin,
    double eYMax,
  ) {
    // Use the same step for both axes so they have the same number of cells.
    final step = _niceStep((xMax - xMin) / 2 + (eYMax - eYMin) / 2, 8);

    // X-axis tick labels
    final y0 = (eYMin <= 0 && eYMax >= 0)
        ? _mathToScreenY(0, size.height, eYMin, eYMax)
        : size.height - 8;

    double tx = _firstGridTick(xMin, step);
    while (tx <= xMax) {
      if (tx.abs() > 1e-10) {
        final screenX = _mathToScreenX(tx, size.width);
        final label = _formatNumber(tx);
        final textPainter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(screenX - textPainter.width / 2, y0 + 4),
        );

        // Small tick mark
        canvas.drawLine(
          Offset(screenX, y0 - 3),
          Offset(screenX, y0 + 3),
          Paint()
            ..color = axisColor
            ..strokeWidth = 1,
        );
      }
      final next = tx + step;
      if (!next.isFinite || next <= tx) break;
      tx = next;
    }

    // Y-axis tick labels
    final x0 = (xMin <= 0 && xMax >= 0) ? _mathToScreenX(0, size.width) : 8;

    double ty = _firstGridTick(eYMin, step);
    while (ty <= eYMax) {
      if (ty.abs() > 1e-10) {
        final screenY = _mathToScreenY(ty, size.height, eYMin, eYMax);
        final label = _formatNumber(ty);
        final textPainter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x0 - textPainter.width - 6, screenY - textPainter.height / 2),
        );

        // Small tick mark
        canvas.drawLine(
          Offset(x0 - 3, screenY),
          Offset(x0 + 3, screenY),
          Paint()
            ..color = axisColor
            ..strokeWidth = 1,
        );
      }
      final next = ty + step;
      if (!next.isFinite || next <= ty) break;
      ty = next;
    }

    // Origin label
    if (xMin <= 0 && xMax >= 0 && eYMin <= 0 && eYMax >= 0) {
      final x0v = _mathToScreenX(0, size.width);
      final y0v = _mathToScreenY(0, size.height, eYMin, eYMax);
      final textPainter = TextPainter(
        text: TextSpan(text: '0', style: style),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x0v + 4, y0v + 4));
    }
  }

  // ==================================================================
  // Arrow helper
  // ==================================================================

  void _drawArrow(
    Canvas canvas,
    Offset tip,
    Paint paint, {
    required ArrowDirection direction,
  }) {
    final arrowSize = 8.0;
    final path = Path();

    if (direction == ArrowDirection.right) {
      path.moveTo(tip.dx, tip.dy);
      path.lineTo(tip.dx - arrowSize, tip.dy - arrowSize / 2);
      path.lineTo(tip.dx - arrowSize, tip.dy + arrowSize / 2);
    } else {
      path.moveTo(tip.dx, tip.dy);
      path.lineTo(tip.dx - arrowSize / 2, tip.dy + arrowSize);
      path.lineTo(tip.dx + arrowSize / 2, tip.dy + arrowSize);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  // ==================================================================
  // Curves
  // ==================================================================

  void _drawCharacteristicPoints(
    Canvas canvas,
    Size size,
    double eYMin,
    double eYMax,
  ) {
    for (final point in characteristicPoints) {
      final screen = _mathToScreen(point.$1, point.$2, size, eYMin, eYMax);
      if (screen.dx < 0 ||
          screen.dx > size.width ||
          screen.dy < 0 ||
          screen.dy > size.height)
        continue;
      canvas.drawCircle(screen, 4, Paint()..color = point.$3);
      canvas.drawCircle(
        screen,
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25,
      );
    }
  }

  void _drawCurves(Canvas canvas, Size size, double eYMin, double eYMax) {
    // Clip to canvas bounds so lines at the very edge are cleanly clipped
    // rather than drawing beyond the visible area.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (int c = 0; c < curves.length; c++) {
      final points = curves[c];
      if (points.length < 2) continue;

      final color = c < curveColors.length ? curveColors[c] : Colors.blue;

      final curvePaint = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      bool inSegment = false;
      bool pathHasContent = false;

      for (int i = 0; i < points.length; i++) {
        final x = points[i]['x']!;
        final y = points[i]['y']!;
        final screenPos = _mathToScreen(x, y, size, eYMin, eYMax);

        // Clamp coordinates to a generous bound to keep the segment
        // continuous for points near the canvas edge. Only break the
        // segment for truly invalid coordinates (NaN or Infinity).
        if (screenPos.dx.isFinite && screenPos.dy.isFinite) {
          final clampedX = screenPos.dx.clamp(-10000.0, size.width + 10000.0);
          final clampedY = screenPos.dy.clamp(-10000.0, size.height + 10000.0);

          if (!inSegment) {
            path.moveTo(clampedX, clampedY);
            inSegment = true;
            pathHasContent = true;
          } else {
            path.lineTo(clampedX, clampedY);
          }
        } else {
          inSegment = false;
        }
      }

      if (pathHasContent) {
        canvas.drawPath(path, curvePaint);
      }
    }

    canvas.restore();
  }

  // ==================================================================
  // Number formatting
  // ==================================================================

  static String _formatNumber(double value) {
    if (value.abs() < 1e-10) return '0';
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    // Show up to 2 significant decimal digits
    final abs = value.abs();
    if (abs >= 1) {
      return value.toStringAsFixed(1);
    } else if (abs >= 0.1) {
      return value.toStringAsFixed(2);
    } else {
      return value.toStringAsExponential(1);
    }
  }
}
