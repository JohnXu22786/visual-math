import 'dart:math' as dart_math;
import 'dart:typed_data';

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

  /// Creates a Flutter-rendered 2D graph canvas.
  const MathCanvas({
    super.key,
    this.initialExpression,
    this.onReady,
    this.onCoordinateUpdate,
    this.onViewportChange,
    this.onError,
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

class _GraphPoint {
  final double x, y;
  final Color color;
  final String kind;
  const _GraphPoint(this.x, this.y, this.color, this.kind);
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
  final Set<String> _enabledFormulas = {};
  final Set<String> _initializedFormulaKeys = {};
  List<_GraphPoint> _characteristicPoints = [];

  // Gesture state
  Offset? _lastFocalPoint;
  double? _lastScale;
  bool _isReady = false;

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
            identity: 'initial:${widget.initialExpression}',
          );
          _initializeNewFormulaSettings([formula]);
          _formulaCurves.add(
            _FormulaCurve(formula: formula, polylines: _sampleCurve(formula)),
          );
        }
      }
      if (!_isReady) {
        setState(() {
          _characteristicPoints = _findCharacteristicPoints();
          _isReady = true;
        });
        widget.onReady?.call();
      }
    });
  }

  // ==================================================================
  // Public API
  // ==================================================================

  /// Set all formulas to plot (replaces any existing formulas).
  Future<void> setFormulas(List<FormulaEntry> newFormulas) async {
    final formulas = _withStableFormulaIdentities(newFormulas);
    setState(() {
      _initializeNewFormulaSettings(formulas);
      _formulaCurves
        ..clear()
        ..addAll(
          formulas.map(
            (f) => _FormulaCurve(formula: f, polylines: _sampleCurve(f)),
          ),
        );
      _characteristicPoints = _findCharacteristicPoints();
    });
    final allPoints = _formulaCurves
        .expand((fc) => fc.polylines.expand((pl) => pl))
        .toList();
    widget.onCoordinateUpdate?.call(allPoints);
  }

  List<FormulaEntry> _withStableFormulaIdentities(
    List<FormulaEntry> formulas,
  ) {
    final occurrences = <String, int>{};
    final identified = <FormulaEntry>[];
    for (final formula in formulas) {
      if (formula.identity != null) {
        identified.add(formula);
        continue;
      }
      final signature = '${formula.rawExpression}:${formula.color.toARGB32()}';
      final occurrence = occurrences.update(
        signature,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      identified.add(
        formula.copyWith(
          identity: 'anonymous-formula:$signature:$occurrence',
        ),
      );
    }
    return identified;
  }

  void _initializeNewFormulaSettings(Iterable<FormulaEntry> formulas) {
    const categories = ['极值点', 'X轴交点', 'Y轴交点', '图像交点'];
    for (final formula in formulas) {
      final key = _formulaSettingsKey(formula);
      if (_initializedFormulaKeys.add(key)) {
        for (final category in categories) {
          _enabledFormulas.add('$key:$category');
        }
      }
    }
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
      _characteristicPoints = _findCharacteristicPoints();
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
      _characteristicPoints = _findCharacteristicPoints();
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

  /// Numeric markers currently displayed, exposed for focused widget tests.
  List<(double x, double y, String kind, Color color)>
  get characteristicPointsForTesting => [
    for (final point in _characteristicPoints)
      (point.x, point.y, point.kind, point.color),
  ];

  List<String> get formulaIdentitiesForTesting => [
    for (final curve in _formulaCurves)
      _formulaSettingsKey(curve.formula),
  ];

  bool _valuesMatchForIntersection(
    double firstY,
    double secondY, {
    double absoluteTolerance = 0,
  }
  ) {
    final magnitude = dart_math.max(firstY.abs(), secondY.abs());
    final tolerance = dart_math.max(
      magnitude * 64 * 2.220446049250313e-16,
      absoluteTolerance,
    );
    return (firstY - secondY).abs() <= tolerance;
  }

  double? _tangentXAxisRoot(
    FormulaEntry formula,
    double low,
    double high, {
    required bool minimum,
  }) {
    double valueAt(double x) {
      try {
        return formula.parsed!.evaluator(x);
      } catch (_) {
        return double.nan;
      }
    }

    final midpoint = low / 2 + high / 2;
    final firstValue = valueAt(low);
    final middleValue = valueAt(midpoint);
    final lastValue = valueAt(high);
    final halfWidth = (high - low) / 2;
    if (!firstValue.isFinite ||
        !middleValue.isFinite ||
        !lastValue.isFinite ||
        halfWidth == 0) {
      return null;
    }
    final curvature =
        ((firstValue - 2 * middleValue + lastValue).abs() / halfWidth) /
        halfWidth;
    if (!curvature.isFinite) return null;
    var left = low;
    var right = high;
    for (var iteration = 0; iteration < 80; iteration++) {
      final firstThird = (2 * left + right) / 3;
      final secondThird = (left + 2 * right) / 3;
      final firstValue = valueAt(firstThird);
      final secondValue = valueAt(secondThird);
      if (!firstValue.isFinite || !secondValue.isFinite) return null;
      if ((minimum && firstValue < secondValue) ||
          (!minimum && firstValue > secondValue)) {
        right = secondThird;
      } else {
        left = firstThird;
      }
    }
    final rootX = (left + right) / 2;
    final rootY = valueAt(rootX);
    final xPrecision = _floatSpacing(rootX);
    final zeroTolerance =
        curvature * xPrecision * xPrecision * 256 +
        rootY.abs() * 64 * 2.220446049250313e-16;
    return rootY.isFinite &&
            zeroTolerance.isFinite &&
            rootY.abs() <= zeroTolerance
        ? rootX
        : null;
  }

  List<_GraphPoint> _findCharacteristicPoints() {
    final found = <_GraphPoint>[];
    const kinds = ['极值点', 'X轴交点', 'Y轴交点', '图像交点'];
    for (final curve in _formulaCurves) {
      final formula = curve.formula;
      final enabled = <String>{
        for (final kind in kinds)
          if (_enabledFormulas.contains(
            '${_formulaSettingsKey(formula)}:$kind',
          ))
            kind,
      };
      for (final line in curve.polylines) {
        for (var i = 1; i < line.length; i++) {
          final a = line[i - 1], b = line[i];
          final ax = a['x']!, ay = a['y']!, bx = b['x']!, by = b['y']!;
          if (enabled.contains('X轴交点') &&
              ((ay <= 0 && by >= 0) || (by <= 0 && ay >= 0)) &&
              ay != by) {
            final rootX = ax + (bx - ax) * (-ay) / (by - ay);
            if (_includesDomainX(formula, rootX)) {
              found.add(_GraphPoint(rootX, 0, formula.color, 'X轴交点'));
            }
          }
          if (enabled.contains('X轴交点') &&
              i < line.length - 1 &&
              formula.parsed?.type == MathExpressionType.explicit) {
            final cy = line[i + 1]['y']!;
            final isMinimum = (by <= ay && by < cy) || (by < ay && by <= cy);
            final isMaximum = (by >= ay && by > cy) || (by > ay && by >= cy);
            if (isMinimum || isMaximum) {
              final tangentX = _tangentXAxisRoot(
                formula,
                ax,
                line[i + 1]['x']!,
                minimum: isMinimum,
              );
              if (tangentX != null && _includesDomainX(formula, tangentX)) {
                found.add(
                  _GraphPoint(tangentX, 0, formula.color, 'X轴交点'),
                );
              }
            }
          }
          if (enabled.contains('Y轴交点') &&
              ((ax <= 0 && bx >= 0) || (bx <= 0 && ax >= 0)) &&
              ax != bx) {
            final rootY = ay + (by - ay) * (-ax) / (bx - ax);
            if (_includesDomainX(formula, 0)) {
              found.add(_GraphPoint(0, rootY, formula.color, 'Y轴交点'));
            }
          }
          if (formula.parsed?.type == MathExpressionType.explicit &&
              enabled.contains('极值点') &&
              i < line.length - 1) {
            final cy = line[i + 1]['y']!;
            if (((by > ay && cy < by) || (by < ay && cy > by)) &&
                _includesDomainX(formula, bx))
              found.add(_GraphPoint(bx, by, formula.color, '极值点'));
          }
        }
      }
    }
    final pairwiseFormulas = _formulaCurves
        .where(
          (curve) => _enabledFormulas.contains(
            '${_formulaSettingsKey(curve.formula)}:图像交点',
          ),
        )
        .map((curve) => _formulaSettingsKey(curve.formula))
        .toSet();
    bool hasUnresolvedDomain(FormulaEntry formula) =>
        (formula.domainMinExpression.isNotEmpty && formula.domainMin == null) ||
        (formula.domainMaxExpression.isNotEmpty && formula.domainMax == null);
    bool hasInvalidDomain(FormulaEntry formula) =>
        formula.domainMin != null &&
        formula.domainMax != null &&
        formula.domainMax! <= formula.domainMin!;
    if (pairwiseFormulas.isNotEmpty) {
      final explicit = _formulaCurves;
      for (var a = 0; a < explicit.length; a++) {
        for (var b = a + 1; b < explicit.length; b++) {
          final firstEnabled = pairwiseFormulas.contains(
            _formulaSettingsKey(explicit[a].formula),
          );
          final secondEnabled = pairwiseFormulas.contains(
            _formulaSettingsKey(explicit[b].formula),
          );
          if (!firstEnabled && !secondEnabled) continue;
          final intersectionColor = firstEnabled
              ? explicit[a].formula.color
              : explicit[b].formula.color;
          if (hasUnresolvedDomain(explicit[a].formula) ||
              hasUnresolvedDomain(explicit[b].formula) ||
              hasInvalidDomain(explicit[a].formula) ||
              hasInvalidDomain(explicit[b].formula)) {
            continue;
          }
          if (explicit[a].formula.parsed?.type == MathExpressionType.explicit &&
              explicit[b].formula.parsed?.type == MathExpressionType.explicit) {
            final first = explicit[a].formula;
            final second = explicit[b].formula;
            final low = dart_math
                .max(
                  _xMin,
                  dart_math.max(
                    first.domainMin ?? _xMin,
                    second.domainMin ?? _xMin,
                  ),
                )
                .toDouble();
            final high = dart_math
                .min(
                  _xMax,
                  dart_math.min(
                    first.domainMax ?? _xMax,
                    second.domainMax ?? _xMax,
                  ),
                )
                .toDouble();
            if (high < low) continue;
            if (high == low) {
              if (_includesDomainX(first, low) &&
                  _includesDomainX(second, low)) {
                try {
                  final firstY = first.parsed!.evaluator(low);
                  final secondY = second.parsed!.evaluator(low);
                  if (firstY.isFinite &&
                      secondY.isFinite &&
                      _valuesMatchForIntersection(firstY, secondY)) {
                    found.add(
                      _GraphPoint(
                        low,
                        (firstY + secondY) / 2,
                        intersectionColor,
                        '图像交点',
                      ),
                    );
                  }
                } catch (_) {}
              }
              continue;
            }
            double differenceAt(double x) {
              try {
                return first.parsed!.evaluator(x) - second.parsed!.evaluator(x);
              } catch (_) {
                return double.nan;
              }
            }

            const samples = 500;
            var previousX = low;
            var previousDifference = differenceAt(low);
            final sampledDifferences = <(double, double)>[
              (low, previousDifference),
            ];
            for (var sample = 1; sample <= samples; sample++) {
              final x = low + (high - low) * sample / samples;
              final difference = differenceAt(x);
              if (difference.isFinite &&
                  previousDifference.isFinite &&
                  ((previousDifference <= 0 && difference >= 0) ||
                      (previousDifference >= 0 && difference <= 0)) &&
                  difference != previousDifference) {
                var left = previousX;
                var right = x;
                var leftDifference = previousDifference;
                var rootValid = true;
                if (previousDifference == 0) {
                  right = left;
                } else if (difference == 0) {
                  left = right;
                  leftDifference = difference;
                }
                for (var iteration = 0; iteration < 1024; iteration++) {
                  if (left == right) break;
                  final middle = left / 2 + right / 2;
                  if (middle == left || middle == right) break;
                  final middleDifference = differenceAt(middle);
                  if (!middleDifference.isFinite) {
                    rootValid = false;
                    break;
                  }
                  if (middleDifference == 0) {
                    left = middle;
                    right = middle;
                    break;
                  }
                  if ((leftDifference < 0 && middleDifference > 0) ||
                      (leftDifference > 0 && middleDifference < 0)) {
                    right = middle;
                  } else {
                    left = middle;
                    leftDifference = middleDifference;
                  }
                }
                final rootX = (left + right) / 2;
                final rootSlope =
                    (difference - previousDifference).abs() /
                    (x - previousX).abs();
                final rootSpacing = _floatSpacing(rootX);
                final rootTolerance = rootSlope * rootSpacing * 4;
                try {
                  final firstY = first.parsed!.evaluator(rootX);
                  final secondY = second.parsed!.evaluator(rootX);
                  if (rootValid &&
                      firstY.isFinite &&
                      secondY.isFinite &&
                      _valuesMatchForIntersection(
                        firstY,
                        secondY,
                        absoluteTolerance: rootTolerance,
                      ) &&
                      _includesDomainX(first, rootX) &&
                      _includesDomainX(second, rootX)) {
                    found.add(
                      _GraphPoint(
                        rootX,
                        (firstY + secondY) / 2,
                        intersectionColor,
                        '图像交点',
                      ),
                    );
                  }
                } catch (_) {}
              }
              previousDifference = difference;
              sampledDifferences.add((x, difference));
              previousX = x;
            }
            if (sampledDifferences.every(
              (sample) => sample.$2.isFinite && sample.$2 == 0,
            )) {
              continue;
            }
            for (var i = 1; i < sampledDifferences.length - 1; i++) {
              final before = sampledDifferences[i - 1];
              final middle = sampledDifferences[i];
              final after = sampledDifferences[i + 1];
              if (!before.$2.isFinite ||
                  !middle.$2.isFinite ||
                  !after.$2.isFinite ||
                  ((before.$2 <= 0 && middle.$2 >= 0) ||
                      (before.$2 >= 0 && middle.$2 <= 0)) ||
                  ((middle.$2 <= 0 && after.$2 >= 0) ||
                      (middle.$2 >= 0 && after.$2 <= 0)) ||
                  middle.$2.abs() > before.$2.abs() ||
                  middle.$2.abs() > after.$2.abs())
                continue;
              var left = before.$1;
              var right = after.$1;
              for (var iteration = 0; iteration < 96; iteration++) {
                final firstThird = left + (right - left) / 3;
                final secondThird = right - (right - left) / 3;
                if (firstThird == left || secondThird == right) break;
                final firstValue = differenceAt(firstThird).abs();
                final secondValue = differenceAt(secondThird).abs();
                if (!firstValue.isFinite || !secondValue.isFinite) break;
                if (firstValue < secondValue) {
                  right = secondThird;
                } else {
                  left = firstThird;
                }
              }
              final tangentX = (left + right) / 2;
              final difference = differenceAt(tangentX);
              try {
                final firstY = first.parsed!.evaluator(tangentX);
                final secondY = second.parsed!.evaluator(tangentX);
                final tangentHalfWidth = (after.$1 - before.$1) / 2;
                final differenceCurvature = tangentHalfWidth > 0
                    ? ((before.$2 - 2 * middle.$2 + after.$2).abs() /
                              tangentHalfWidth) /
                          tangentHalfWidth
                    : double.nan;
                final xPrecision = _floatSpacing(tangentX);
                final tangentTolerance = differenceCurvature.isFinite
                    ? differenceCurvature *
                          xPrecision *
                          xPrecision *
                          256 +
                          dart_math.max(firstY.abs(), secondY.abs()) *
                              64 *
                              2.220446049250313e-16
                    : 0.0;
                if (difference.isFinite &&
                    firstY.isFinite &&
                    secondY.isFinite &&
                    tangentTolerance.isFinite &&
                    difference.abs() <= tangentTolerance &&
                    _includesDomainX(first, tangentX) &&
                    _includesDomainX(second, tangentX)) {
                  found.add(
                    _GraphPoint(
                      tangentX,
                      (firstY + secondY) / 2,
                      intersectionColor,
                      '图像交点',
                    ),
                  );
                }
              } catch (_) {}
            }
            continue;
          }
          for (final lineA in explicit[a].polylines) {
            for (final lineB in explicit[b].polylines) {
              for (var i = 1; i < lineA.length; i++) {
                final p = lineA[i - 1], q = lineA[i];
                for (var j = 1; j < lineB.length; j++) {
                  final r = lineB[j - 1], s = lineB[j];
                  final x1 = p['x']!, y1 = p['y']!, x2 = q['x']!, y2 = q['y']!;
                  final x3 = r['x']!, y3 = r['y']!, x4 = s['x']!, y4 = s['y']!;
                  final firstCrossTerm = (x1 - x2) * (y3 - y4);
                  final secondCrossTerm = (y1 - y2) * (x3 - x4);
                  final denominator =
                      firstCrossTerm - secondCrossTerm;
                  final determinantScale = dart_math.max(
                    firstCrossTerm.abs(),
                    secondCrossTerm.abs(),
                  );
                  if (determinantScale == 0 ||
                      denominator.abs() <=
                          determinantScale * 64 * 2.220446049250313e-16) {
                    continue;
                  }
                  final t =
                      ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) /
                      denominator;
                  final u =
                      -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) /
                      denominator;
                  if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
                    final x = x1 + t * (x2 - x1);
                    if (_includesDomainX(explicit[a].formula, x) &&
                        _includesDomainX(explicit[b].formula, x)) {
                      found.add(
                        _GraphPoint(
                          x,
                          y1 + t * (y2 - y1),
                          intersectionColor,
                          '图像交点',
                        ),
                      );
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    final bounds = _effectiveYBounds();
    final unique = <_GraphPoint>[];
    double coordinateTolerance(double value) => _floatSpacing(value);
    for (final point in found) {
      if (point.x < _xMin ||
          point.x > _xMax ||
          point.y < bounds.$1 ||
          point.y > bounds.$2)
        continue;
      if (unique.any(
        (other) {
          if (other.kind != point.kind) return false;
          final xTolerance = coordinateTolerance(
            dart_math.max(other.x.abs(), point.x.abs()),
          );
          final yTolerance = coordinateTolerance(
            dart_math.max(other.y.abs(), point.y.abs()),
          );
          return (other.x - point.x).abs() <= xTolerance &&
              (other.y - point.y).abs() <= yTolerance;
        },
      ))
        continue;
      unique.add(point);
    }
    return unique;
  }

  String _formulaSettingsKey(FormulaEntry formula) =>
      formula.identity ?? '${formula.rawExpression}:${formula.color.toARGB32()}';

  bool _includesDomainX(FormulaEntry formula, double x) {
    if (!formula.includeDomainMin &&
        formula.domainMin != null &&
        x <= formula.domainMin!)
      return false;
    if (!formula.includeDomainMax &&
        formula.domainMax != null &&
        x >= formula.domainMax!)
      return false;
    return true;
  }

  Future<void> _openCharacteristicSettings() async {
    const categories = ['极值点', 'X轴交点', 'Y轴交点', '图像交点'];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('特征点显示'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('全部显示'),
                ),
                for (final category in categories)
                  CheckboxListTile(
                    dense: true,
                    tristate: true,
                    title: Text(category),
                    value: _categoryAggregate(category),
                    onChanged: (_) => refresh(() {
                      _setCategoryForAll(
                        category,
                        _categoryAggregate(category) != true,
                      );
                      setState(() => _characteristicPoints = _findCharacteristicPoints());
                    }),
                  ),
                const Divider(),
                for (final curve in _formulaCurves)
                  ExpansionTile(
                    key: PageStorageKey(_formulaSettingsKey(curve.formula)),
                    initiallyExpanded: true,
                    leading: CircleAvatar(
                      radius: 8,
                      backgroundColor: curve.formula.color,
                    ),
                    title: Text(curve.formula.rawExpression),
                    children: [
                      for (final category in categories)
                        CheckboxListTile(
                          dense: true,
                          title: Text(category),
                          value: _isCategoryEnabled(curve.formula, category),
                          onChanged: (value) => refresh(() {
                            _setFormulaCategory(
                              curve.formula,
                              category,
                              value ?? false,
                            );
                            setState(() => _characteristicPoints = _findCharacteristicPoints());
                          }),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isCategoryEnabled(FormulaEntry formula, String category) =>
      _enabledFormulas.contains('${_formulaSettingsKey(formula)}:$category');

  /// Toggle one plotted formula category in focused state-level widget tests.
  void setFormulaCharacteristicForTesting(
    String formulaIdentity,
    String category,
    bool enabled,
  ) {
    final curve = _formulaCurves.firstWhere(
      (item) => _formulaSettingsKey(item.formula) == formulaIdentity,
    );
    setState(() {
      _setFormulaCategory(curve.formula, category, enabled);
      _characteristicPoints = _findCharacteristicPoints();
    });
  }

  bool? _categoryAggregate(String category) {
    if (_formulaCurves.isEmpty) return false;
    final enabledCount = _formulaCurves
        .where((curve) => _isCategoryEnabled(curve.formula, category))
        .length;
    if (enabledCount == 0) return false;
    if (enabledCount == _formulaCurves.length) return true;
    return null;
  }

  void _setFormulaCategory(FormulaEntry formula, String category, bool enabled) {
    final key = '${_formulaSettingsKey(formula)}:$category';
    if (enabled) {
      _enabledFormulas.add(key);
    } else {
      _enabledFormulas.remove(key);
    }
  }

  void _setCategoryForAll(String category, bool enabled) {
    for (final curve in _formulaCurves) {
      _setFormulaCategory(curve.formula, category, enabled);
    }
  }

  void _inspectCharacteristicPoint(Offset position) {
    final bounds = _effectiveYBounds();
    for (final point in _characteristicPoints) {
      final sx = (point.x - _xMin) / (_xMax - _xMin) * _canvasWidth;
      final sy = (bounds.$2 - point.y) / (bounds.$2 - bounds.$1) * _canvasHeight;
      if ((Offset(sx, sy) - position).distance < 16) {
        showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: Text(point.kind),
          content: Text('x = ${point.x.toStringAsFixed(8)}\ny = ${point.y.toStringAsFixed(8)}'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
        ));
        break;
      }
    }
  }

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

  double _adjacentFloat(double value, {required bool upward}) {
    if (!value.isFinite) return value;
    if (value == 0) return upward ? double.minPositive : -double.minPositive;
    final data = ByteData(8)..setFloat64(0, value, Endian.big);
    var bits = data.getUint64(0, Endian.big);
    if ((value > 0) == upward) {
      bits++;
    } else {
      bits--;
    }
    data.setUint64(0, bits, Endian.big);
    return data.getFloat64(0, Endian.big);
  }

  double _floatSpacing(double value) {
    final absolute = value.abs();
    final next = _adjacentFloat(absolute, upward: true);
    return next.isFinite
        ? next - absolute
        : absolute - _adjacentFloat(absolute, upward: false);
  }

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
    if ((formula.domainMinExpression.isNotEmpty && formula.domainMin == null) ||
        (formula.domainMaxExpression.isNotEmpty && formula.domainMax == null)) {
      return [];
    }
    final parsed = formula.parsed!;
    final marginScale = includePanMargin ? _renderMarginScale : 0.0;
    final marginX = (_xMax - _xMin) * marginScale;
    final domainMin = formula.domainMin ?? double.negativeInfinity;
    final domainMax = formula.domainMax ?? double.infinity;
    if (domainMax <= domainMin) return [];
    var sampleMin = dart_math.max(_xMin - marginX, domainMin).toDouble();
    var sampleMax = dart_math.min(_xMax + marginX, domainMax).toDouble();
    if (!formula.includeDomainMin && sampleMin == domainMin) {
      sampleMin = _adjacentFloat(domainMin, upward: true);
    }
    if (!formula.includeDomainMax && sampleMax == domainMax) {
      sampleMax = _adjacentFloat(domainMax, upward: false);
    }
    if (sampleMax <= sampleMin) return [];
    if (parsed.type == MathExpressionType.implicit) {
      final (effectiveYMin, effectiveYMax) = _effectiveYBounds();
      final marginY = (effectiveYMax - effectiveYMin) * marginScale;
      // Contour segments — each is a short line across one grid cell.
      // Extend bounds and proportionally increase grid cells so that
      // contour detail remains consistent across the visible area.
      final scale = 1.0 + 2.0 * marginScale;
      return parsed.sampleContourSegments(
        xMin: sampleMin,
        xMax: sampleMax,
        yMin: effectiveYMin - marginY,
        yMax: effectiveYMax + marginY,
        gridX: (80 * scale).round().clamp(80, 200),
        gridY: (80 * scale).round().clamp(80, 200),
      );
    }
    // Sample well beyond viewport bounds to ensure curves reach the
    // canvas edges during pan/zoom without visible holes in the graph.
    // With _renderMarginScale=1.0, this yields scalePoints=3.0 (3× points).
    final scalePoints = 1.0 + 2.0 * marginScale;
    return parsed.samplePointSegments(
      xMin: sampleMin,
      xMax: sampleMax,
      numPoints: (300 * scalePoints).round().clamp(300, 1200),
    );
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
    _characteristicPoints = _findCharacteristicPoints();
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

        return Stack(
          children: [
            GestureDetector(
              onTapUp: (details) =>
                  _inspectCharacteristicPoint(details.localPosition),
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    MathUiTokens.cornerRadius,
                  ),
                  child: CustomPaint(
                    painter: GraphPainter(
                      xMin: _xMin,
                      yMin: _yMin,
                      xMax: _xMax,
                      yMax: _yMax,
                      curves: _buildCurvesList(),
                      curveColors: _buildColorsList(),
                      characteristicPoints: _characteristicPoints,
                      backgroundColor: cs.surface,
                      gridColor: cs.outlineVariant.withValues(alpha: 0.5),
                      axisColor: cs.onSurface,
                      labelColor: cs.onSurfaceVariant,
                    ),
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: cs.surface,
                elevation: 2,
                shape: const CircleBorder(),
                child: PopupMenuButton<String>(
                  tooltip: '视图设置',
                  icon: const Icon(Icons.settings, size: 21),
                  onSelected: (_) => _openCharacteristicSettings(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'characteristicPoints',
                      child: Text('特征点显示'),
                    ),
                  ],
                  style: IconButton.styleFrom(
                    fixedSize: const Size(40, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
          ],
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
  final List<_GraphPoint> characteristicPoints;

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
    _drawGrid(canvas, size, eYMin, eYMax);
    _drawAxes(canvas, size, eYMin, eYMax);
    _drawCurves(canvas, size, eYMin, eYMax);
    for (final point in characteristicPoints) {
      final center = _mathToScreen(point.x, point.y, size, eYMin, eYMax);
      canvas.drawCircle(center, 7, Paint()..color = backgroundColor);
      canvas.drawCircle(center, 5, Paint()..color = point.color);
      canvas.drawCircle(center, 5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
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
