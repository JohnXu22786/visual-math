import 'math_expression_parser.dart';
import 'math_input_catalog.dart';

/// The type of a math expression.
enum MathExpressionType {
  /// Explicit y = f(x) — a single-valued function of x.
  explicit,

  /// Implicit f(x,y) = 0 — a contour/relation in the plane.
  implicit,
}

/// Represents a single math expression with its various forms.
///
/// Uses a native expression parser for evaluation, enabling Flutter rendering
/// without WebView/JSXGraph dependencies.
///
/// For explicit functions (e.g. "x^2", "sin(x)"), [evaluator] is a
/// [double Function(double)] and [samplePoints] samples y = f(x).
///
/// For implicit equations (e.g. "x^2+y^2=1"), [implicitEvaluator] is a
/// [double Function(double, double)] and [sampleContour] finds the zero set.
class MathExpression {
  /// The raw expression as entered by the user (e.g. "x^2", "x=1").
  final String rawExpression;

  /// The normalized expression ready for numeric parsing.
  final String normalizedExpression;

  /// The type of expression (explicit or implicit).
  final MathExpressionType type;

  /// LaTeX display string for rendering.
  final String latexDisplay;

  /// Set of parameter names extracted from the expression (e.g. {"a", "b"}).
  final Set<String> parameters;

  /// Values bound to parameters when this expression was compiled.
  final Map<String, double> parameterValues;

  /// For explicit functions: evaluates at a given x value.
  /// For implicit equations: evaluates f(x, y) at a given x (y defaults to 0).
  final double Function(double) evaluator;

  /// For implicit equations: evaluates f(x, y). Null for explicit.
  final double Function(double, double)? implicitEvaluator;

  /// Whether this expression is valid (non-empty and parseable).
  bool get isValid => rawExpression.isNotEmpty && _parseError == null;

  /// If parsing failed, contains the error message.
  final String? _parseError;

  /// The error message if the expression is invalid.
  String? get parseError => _parseError;

  const MathExpression._({
    required this.rawExpression,
    required this.normalizedExpression,
    required this.type,
    required this.latexDisplay,
    required this.parameters,
    this.parameterValues = const {},
    required this.evaluator,
    this.implicitEvaluator,
    String? parseError,
  }) : _parseError = parseError;

  /// Create a [MathExpression] from user input.
  ///
  /// Returns an instance with [isValid] = false and [parseError] set
  /// if the input cannot be parsed.
  factory MathExpression.fromInput(
    String input, {
    Map<String, double> parameterValues = const {},
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return MathExpression._(
        rawExpression: '',
        normalizedExpression: '',
        type: MathExpressionType.explicit,
        latexDisplay: '',
        parameters: {},
        evaluator: (_) => 0.0,
        parseError: null,
      );
    }

    // Strip prefix: y = ..., f(x) = ...
    final body = _stripPrefix(trimmed);
    if (body.isEmpty) {
      return MathExpression._(
        rawExpression: trimmed,
        normalizedExpression: '',
        type: MathExpressionType.explicit,
        latexDisplay: _toLatexDisplay(trimmed),
        parameters: {},
        evaluator: (_) => 0.0,
        parseError: '表达式为空',
      );
    }

    // Detect implicit equations: body contains '=' that's not part of y= or f(x)=
    final isEquation = _isEquation(body);

    // Normalize the expression for numeric parsing.
    var normalized = '';

    // Try to parse and create evaluator
    String? error;
    double Function(double)? evalFn;
    double Function(double, double)? implicitFn;

    try {
      normalized = _normalizeExpression(body);
      if (isEquation) {
        // For equations like x=1 or x^2+y^2=1, create f(x,y) = left - right
        final eqParts = normalized.split('=');
        if (eqParts.length == 2) {
          final implicitExpr = '(${eqParts[0]})-(${eqParts[1]})';
          // Normalize the implicit expression
          final normalizedImplicit = _normalizeExpression(implicitExpr);
          // Create multi-variable evaluator with x and y
          implicitFn = _createImplicitEvaluator(
            normalizedImplicit,
            parameterValues,
          );
          // Also create a backward-compat explicit evaluator (y=0 slice)
          evalFn = (double x) => implicitFn!(x, 0.0);
        } else {
          error = '无效的等式';
        }
      } else {
        evalFn = _createEvaluator(normalized, parameterValues);
      }
    } catch (e) {
      error = e.toString();
    }

    // Extract parameters from the normalized formula.
    final params = _extractParameters(normalized, implicit: isEquation);

    return MathExpression._(
      rawExpression: trimmed,
      normalizedExpression: normalized,
      type: isEquation
          ? MathExpressionType.implicit
          : MathExpressionType.explicit,
      latexDisplay: _toLatexDisplay(trimmed),
      parameters: params,
      parameterValues: Map.unmodifiable({
        for (final name in params) name: parameterValues[name] ?? 1.0,
      }),
      evaluator:
          evalFn ??
          ((double x) {
            throw error ?? 'Unknown parse error';
          }),
      implicitEvaluator: implicitFn,
      parseError: error,
    );
  }

  /// Evaluate a scalar domain bound without treating coordinates as constants.
  static double? resolveDomainBound(
    String? source,
    Map<String, double> parameterValues,
  ) {
    if (source == null || source.trim().isEmpty || source.contains('=')) {
      return null;
    }
    final expression = MathExpression.fromInput(
      source,
      parameterValues: parameterValues,
    );
    if (!expression.isValid ||
        RegExp(r'\b[xy]\b').hasMatch(expression.normalizedExpression)) {
      return null;
    }
    try {
      final value = expression.evaluator(0);
      return value.isFinite ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Create an updated evaluator with new parameter values.
  MathExpression withParameters(Map<String, double> parameterValues) {
    if (!isValid) return this;

    double Function(double)? evalFn;
    double Function(double, double)? implicitFn;
    String? error;

    try {
      if (type == MathExpressionType.implicit) {
        final eqParts = normalizedExpression.split('=');
        if (eqParts.length == 2) {
          final implicitExpr = _normalizeExpression(
            '(${eqParts[0]})-(${eqParts[1]})',
          );
          implicitFn = _createImplicitEvaluator(implicitExpr, parameterValues);
          evalFn = (double x) => implicitFn!(x, 0.0);
        }
      } else {
        evalFn = _createEvaluator(normalizedExpression, parameterValues);
      }
    } catch (e) {
      error = e.toString();
    }

    return MathExpression._(
      rawExpression: rawExpression,
      normalizedExpression: normalizedExpression,
      type: type,
      latexDisplay: latexDisplay,
      parameters: parameters,
      parameterValues: Map.unmodifiable({
        for (final name in parameters) name: parameterValues[name] ?? 1.0,
      }),
      evaluator:
          evalFn ??
          ((double x) {
            throw error ?? 'Unknown parse error';
          }),
      implicitEvaluator: implicitFn,
      parseError: error,
    );
  }

  /// Copy this expression with an unmodifiable parameter-name set.
  MathExpression immutableCopy() => MathExpression._(
    rawExpression: rawExpression,
    normalizedExpression: normalizedExpression,
    type: type,
    latexDisplay: latexDisplay,
    parameters: Set.unmodifiable(parameters),
    parameterValues: Map.unmodifiable(parameterValues),
    evaluator: evaluator,
    implicitEvaluator: implicitEvaluator,
    parseError: parseError,
  );

  /// Sample the function at [numPoints] points within [xMin]..[xMax].
  ///
  /// Returns a list of (x, y) coordinate pairs. Points where the function
  /// is undefined (NaN, infinity) are filtered out.
  List<Map<String, double>> samplePoints({
    double xMin = -10,
    double xMax = 10,
    int numPoints = 200,
  }) => samplePointSegments(
    xMin: xMin,
    xMax: xMax,
    numPoints: numPoints,
  ).expand((segment) => segment).toList();

  /// Sample the function into contiguous finite runs within [xMin]..[xMax].
  /// Invalid samples split runs so graph renderers do not join across
  /// discontinuities such as vertical asymptotes.
  List<List<Map<String, double>>> samplePointSegments({
    double xMin = -10,
    double xMax = 10,
    int numPoints = 200,
  }) {
    if (!isValid ||
        !xMin.isFinite ||
        !xMax.isFinite ||
        xMax <= xMin ||
        !(xMax - xMin).isFinite ||
        numPoints < 2) {
      return [];
    }

    final step = (xMax - xMin) / (numPoints - 1);
    final segments = <List<Map<String, double>>>[];
    var currentSegment = <Map<String, double>>[];

    void flushSegment() {
      if (currentSegment.isNotEmpty) segments.add(currentSegment);
      currentSegment = <Map<String, double>>[];
    }

    for (int i = 0; i < numPoints; i++) {
      final x = xMin + i * step;
      try {
        final y = evaluator(x);
        if (y.isFinite) {
          if (currentSegment.isNotEmpty) {
            final previous = currentSegment.last;
            final previousX = previous['x']!;
            final previousY = previous['y']!;
            try {
              final midpointY = evaluator((previousX + x) / 2);
              final expectedMidpointY = (previousY + y) / 2;
              final scale = [
                1.0,
                previousY.abs(),
                y.abs(),
                midpointY.abs(),
              ].reduce((a, b) => a > b ? a : b);
              if (!midpointY.isFinite ||
                  (midpointY - expectedMidpointY).abs() > 0.5 * scale) {
                flushSegment();
              }
            } catch (_) {
              flushSegment();
            }
          }
          currentSegment.add({'x': x, 'y': y});
        } else {
          flushSegment();
        }
      } catch (_) {
        flushSegment();
      }
    }
    flushSegment();
    return segments;
  }

  /// Sample the contour of an implicit equation f(x,y)=0 within the viewport.
  ///
  /// Uses marching squares on a fine grid and returns line segments
  /// (pairs of points). Each inner list has exactly 2 {x, y} maps
  /// forming one segment of the contour. For explicit functions, returns an
  /// empty list; use [samplePoints] to sample those expressions.
  ///
  /// The segment-based output avoids the "scattered points" issue
  /// where unordered contour points get connected incorrectly.
  List<List<Map<String, double>>> sampleContourSegments({
    double xMin = -10,
    double xMax = 10,
    double yMin = -10,
    double yMax = 10,
    int gridX = 80,
    int gridY = 80,
  }) => _sampleContourSegments(
    xMin: xMin,
    xMax: xMax,
    yMin: yMin,
    yMax: yMax,
    gridX: gridX,
    gridY: gridY,
    refinements: 3,
  );

  // Finite sampling cannot prove continuity; limit local refinement near a
  // suspected discontinuity and leave a gap if it cannot resolve the cell.
  List<List<Map<String, double>>> _sampleContourSegments({
    required double xMin,
    required double xMax,
    required double yMin,
    required double yMax,
    required int gridX,
    required int gridY,
    required int refinements,
  }) {
    final result = <List<Map<String, double>>>[];
    if (!isValid ||
        gridX <= 0 ||
        gridY <= 0 ||
        !xMin.isFinite ||
        !xMax.isFinite ||
        !yMin.isFinite ||
        !yMax.isFinite ||
        xMax <= xMin ||
        yMax <= yMin) {
      return result;
    }
    if (type == MathExpressionType.explicit) return result;

    final evaluator2D = implicitEvaluator;
    if (evaluator2D == null) return result;
    final equationParts = normalizedExpression.split('=');
    if (equationParts.length != 2) return result;
    final zeroResidual = '(${equationParts[0]})-(${equationParts[1]})';
    final expressionVariables = ['x', 'y', ...parameters];

    final stepX = (xMax - xMin) / gridX;
    final stepY = (yMax - yMin) / gridY;

    // Evaluate f at each grid point
    final grid = <List<double>>[];
    for (int i = 0; i <= gridX; i++) {
      grid.add(List<double>.filled(gridY + 1, double.nan));
    }
    for (int ix = 0; ix <= gridX; ix++) {
      final x = xMin + ix * stepX;
      for (int iy = 0; iy <= gridY; iy++) {
        final y = yMin + iy * stepY;
        try {
          grid[ix][iy] = evaluator2D(x, y);
        } catch (_) {
          grid[ix][iy] = double.nan;
        }
      }
    }

    // A sign change alone also occurs at poles. Refine the bracket and only
    // accept it when the residual approaches zero relative to its endpoints.
    double? crossing(
      double x1,
      double y1,
      double x2,
      double y2,
      double a,
      double b,
    ) {
      if (a == 0) return 0;
      if (b == 0) return 1;
      final scale = a.abs() > b.abs() ? a.abs() : b.abs();
      final ratioA = a.abs() / scale;
      final ratioB = b.abs() / scale;
      final estimate = ratioA / (ratioA + ratioB);
      try {
        if (evaluator2D(x1 + (x2 - x1) * estimate, y1 + (y2 - y1) * estimate) ==
            0) {
          return estimate;
        }
      } catch (_) {
        // Continue with bracket refinement if interpolation is undefined.
      }
      var lo = 0.0;
      var hi = 1.0;
      var left = a;
      var right = b;
      final smaller = a.abs() < b.abs() ? a.abs() : b.abs();
      final larger = a.abs() > b.abs() ? a.abs() : b.abs();
      // Floating-point evaluation can leave a small residual at a real root.
      final roundingAllowance = larger * 1e-14;
      final threshold = roundingAllowance < smaller
          ? smaller * 0.001 + roundingAllowance
          : smaller;
      for (var i = 0; i < 1100; i++) {
        final t = (lo + hi) / 2;
        if (t == lo || t == hi) break;
        double value;
        try {
          value = evaluator2D(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
        } catch (_) {
          return null;
        }
        if (!value.isFinite) return null;
        if (value == 0) return t;
        if ((value < 0) == (left < 0)) {
          lo = t;
          left = value;
        } else {
          hi = t;
          right = value;
        }
      }
      if (lo > 0 && left.abs() <= threshold) return lo;
      if (hi < 1 && right.abs() <= threshold) return hi;
      return null;
    }

    // Look for an interior minimum of |f| on an edge whose endpoints have
    // the same sign. This detects some tangential roots; finite samples cannot
    // distinguish every root from an arbitrarily small positive minimum.
    double? touching(
      double x1,
      double y1,
      double x2,
      double y2,
      double a,
      double b,
    ) {
      if (a == 0 || b == 0 || (a < 0) != (b < 0)) return null;
      double value(double t) {
        try {
          return evaluator2D(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t).abs();
        } catch (_) {
          return double.nan;
        }
      }

      final middle = value(0.5);
      if (!middle.isFinite) return null;
      final scale = a.abs() > b.abs() ? a.abs() : b.abs();
      // A quadratic estimate identifies a possible interior minimum even when
      // it is closer to an endpoint than to the middle of the edge.
      final curvature = a.abs() - 2 * middle + b.abs();
      final vertex = curvature > scale * 1e-12
          ? 0.5 + (a.abs() - b.abs()) / (4 * curvature)
          : double.nan;
      var lo = 0.0;
      var hi = 1.0;
      if (!vertex.isFinite || vertex <= 0 || vertex >= 1) {
        final samples = [a.abs(), value(0.25), middle, value(0.75), b.abs()];
        var minimum = -1;
        for (var i = 1; i < 4; i++) {
          if (samples[i].isFinite &&
              samples[i] < samples[i - 1] &&
              samples[i] < samples[i + 1]) {
            minimum = i;
            break;
          }
        }
        if (minimum < 0) return null;
        lo = (minimum - 1) / 4;
        hi = (minimum + 1) / 4;
      }
      const fraction = 0.3819660112501051;
      var left = lo + (hi - lo) * fraction;
      var right = hi - (hi - lo) * fraction;
      var leftValue = value(left);
      var rightValue = value(right);
      for (var i = 0; i < 80; i++) {
        if (!leftValue.isFinite || !rightValue.isFinite) return null;
        if (leftValue < rightValue) {
          hi = right;
          right = left;
          rightValue = leftValue;
          left = lo + (hi - lo) * fraction;
          leftValue = value(left);
        } else {
          lo = left;
          left = right;
          leftValue = rightValue;
          right = hi - (hi - lo) * fraction;
          rightValue = value(right);
        }
      }
      final t = leftValue < rightValue ? left : right;
      final residual = leftValue < rightValue ? leftValue : rightValue;
      return residual <= scale * 1e-14 ? t : null;
    }

    bool crossingsHaveSameSign(double a, double b, double c, double d) {
      final values = [a, b, c, d].where((v) => v != 0);
      return values.isNotEmpty &&
          values.every((v) => (v < 0) == (values.first < 0));
    }

    final tangentCache = <(int, int, bool), double?>{};

    // Marching squares: for each cell, find zero-crossing edge pairs.
    for (int ix = 0; ix < gridX; ix++) {
      for (int iy = 0; iy < gridY; iy++) {
        final v00 = grid[ix][iy];
        final v10 = grid[ix + 1][iy];
        final v01 = grid[ix][iy + 1];
        final v11 = grid[ix + 1][iy + 1];

        if (!v00.isFinite || !v10.isFinite || !v01.isFinite || !v11.isFinite) {
          continue;
        }

        final x = xMin + ix * stepX;
        final y = yMin + iy * stepY;

        final zeroEdges = <List<Map<String, double>>>[];
        var hasFalseZeroEdge = false;
        final rejectedZeroEdgeCorners = <(double, double)>{};
        void rejectZeroEdge(double x1, double y1, double x2, double y2) {
          hasFalseZeroEdge = true;
          rejectedZeroEdgeCorners.add((x1, y1));
          rejectedZeroEdgeCorners.add((x2, y2));
        }

        void addZeroEdge(double x1, double y1, double x2, double y2) {
          final horizontal = y1 == y2;
          final fixedCoordinate = horizontal ? {'y': y1} : {'x': x1};
          if (!MathExpressionParser.isIdenticallyZeroAfterSubstitution(
            zeroResidual,
            variables: expressionVariables,
            substitutions: {...parameterValues, ...fixedCoordinate},
            intervals: horizontal
                ? {'x': (x1 < x2 ? x1 : x2, x1 < x2 ? x2 : x1)}
                : {'y': (y1 < y2 ? y1 : y2, y1 < y2 ? y2 : y1)},
          )) {
            rejectZeroEdge(x1, y1, x2, y2);
            return;
          }

          const maxZeroEdgeProbeDepth = 4;
          bool edgeProbesAreZero(double lo, double hi, int depth) {
            final t = (lo + hi) / 2;
            try {
              final value = evaluator2D(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
              if (!value.isFinite || value != 0.0) return false;
            } catch (_) {
              return false;
            }
            return depth == 0 ||
                (edgeProbesAreZero(lo, t, depth - 1) &&
                    edgeProbesAreZero(t, hi, depth - 1));
          }

          // Exact zeros make edge acceptance independent of expression scale.
          // This bounded sampling catches ordinary between-root variation, but
          // finite probes cannot prove an arbitrary expression is zero there.
          if (!edgeProbesAreZero(0, 1, maxZeroEdgeProbeDepth)) {
            rejectZeroEdge(x1, y1, x2, y2);
            return;
          }
          zeroEdges.add([
            {'x': x1, 'y': y1},
            {'x': x2, 'y': y2},
          ]);
        }

        // Preserve grid-aligned zero sets such as x^2 = 0. Assign interior
        // edges to their left/bottom cell so a zero edge is emitted once.
        if (v00 == 0.0 && v10 == 0.0 && (v01 != 0.0 || v11 != 0.0)) {
          addZeroEdge(x, y, x + stepX, y);
        }
        if (iy == gridY - 1 &&
            v01 == 0.0 &&
            v11 == 0.0 &&
            (v00 != 0.0 || v10 != 0.0)) {
          addZeroEdge(x, y + stepY, x + stepX, y + stepY);
        }
        if (v00 == 0.0 && v01 == 0.0 && (v10 != 0.0 || v11 != 0.0)) {
          addZeroEdge(x, y, x, y + stepY);
        }
        if (ix == gridX - 1 &&
            v10 == 0.0 &&
            v11 == 0.0 &&
            (v00 != 0.0 || v01 != 0.0)) {
          addZeroEdge(x + stepX, y, x + stepX, y + stepY);
        }
        // Collect crossing info for each edge.
        // Use a small epsilon to handle exact-zero values at grid points.
        // When f(x,y) == 0 at a grid point (e.g. at the origin for y²=4x,
        // x²=y, etc.), the product v00*v10 == 0 which fails the < 0 check,
        // causing the crossing through that corner to be missed.
        // Treating 0 as a tiny positive (1e-15) ensures the sign comparison
        // correctly detects crossings at zero-valued corners.
        const double zeroEps = 1e-15;
        final s00 = v00 == 0.0 ? zeroEps : v00;
        final s10 = v10 == 0.0 ? zeroEps : v10;
        final s01 = v01 == 0.0 ? zeroEps : v01;
        final s11 = v11 == 0.0 ? zeroEps : v11;

        double? bottomT, topT, leftT, rightT;

        // Bottom edge (v00-v10)
        if ((s00 < 0) != (s10 < 0)) {
          bottomT = crossing(x, y, x + stepX, y, v00, v10);
        }
        // Top edge (v01-v11)
        if ((s01 < 0) != (s11 < 0)) {
          topT = crossing(x, y + stepY, x + stepX, y + stepY, v01, v11);
        }
        // Left edge (v00-v01)
        if ((s00 < 0) != (s01 < 0)) {
          leftT = crossing(x, y, x, y + stepY, v00, v01);
        }
        // Right edge (v10-v11)
        if ((s10 < 0) != (s11 < 0)) {
          rightT = crossing(x + stepX, y, x + stepX, y + stepY, v10, v11);
        }

        double? edgeTouch(
          double x1,
          double y1,
          double x2,
          double y2,
          double a,
          double b,
        ) {
          if (zeroEdges.isNotEmpty && (a == 0) != (b == 0)) {
            const inset = 0.001;
            final lo = a == 0 ? inset : 0.0;
            final hi = b == 0 ? 1 - inset : 1.0;
            try {
              final xa = x1 + (x2 - x1) * lo;
              final ya = y1 + (y2 - y1) * lo;
              final xb = x1 + (x2 - x1) * hi;
              final yb = y1 + (y2 - y1) * hi;
              final t = touching(
                xa,
                ya,
                xb,
                yb,
                evaluator2D(xa, ya),
                evaluator2D(xb, yb),
              );
              return t == null ? null : lo + (hi - lo) * t;
            } catch (_) {
              return null;
            }
          }
          return touching(x1, y1, x2, y2, a, b);
        }

        double? cachedTouch(
          int column,
          int row,
          bool horizontal,
          double x1,
          double y1,
          double x2,
          double y2,
          double a,
          double b,
        ) {
          // Zero endpoint handling depends on the current cell's zero edges.
          if (a == 0 || b == 0) return edgeTouch(x1, y1, x2, y2, a, b);
          final key = (column, row, horizontal);
          if (tangentCache.containsKey(key)) return tangentCache[key];
          return tangentCache[key] = edgeTouch(x1, y1, x2, y2, a, b);
        }

        // Adjacent cells share each grid edge.
        final tangentBottom = cachedTouch(
          ix,
          iy,
          true,
          x,
          y,
          x + stepX,
          y,
          v00,
          v10,
        );
        final tangentTop = cachedTouch(
          ix,
          iy + 1,
          true,
          x,
          y + stepY,
          x + stepX,
          y + stepY,
          v01,
          v11,
        );
        final tangentLeft = cachedTouch(
          ix,
          iy,
          false,
          x,
          y,
          x,
          y + stepY,
          v00,
          v01,
        );
        final tangentRight = cachedTouch(
          ix + 1,
          iy,
          false,
          x + stepX,
          y,
          x + stepX,
          y + stepY,
          v10,
          v11,
        );

        bool zeroEdgeHasUndefinedInterior(List<Map<String, double>> edge) {
          for (final t in [0.25, 0.5, 0.75]) {
            try {
              final a = edge[0];
              final b = edge[1];
              if (!evaluator2D(
                a['x']! + (b['x']! - a['x']!) * t,
                a['y']! + (b['y']! - a['y']!) * t,
              ).isFinite) {
                return true;
              }
            } catch (_) {
              return true;
            }
          }
          return false;
        }

        // Probe just off a touching segment: on the zero set itself a pole can
        // be hidden by a zero numerator. A sharp, unbounded-looking peak in
        // the nearby values makes the segment uncertain, so refine the cell.
        bool tangentHasSuspectedPole(List<Map<String, double>> edge) {
          final dx = edge[1]['x']! - edge[0]['x']!;
          final dy = edge[1]['y']! - edge[0]['y']!;
          var side = 1.0;
          double probe(double t) {
            try {
              return evaluator2D(
                edge[0]['x']! + dx * t - dy * 0.001 * side,
                edge[0]['y']! + dy * t + dx * 0.001 * side,
              ).abs();
            } catch (_) {
              return double.infinity;
            }
          }

          const divisions = 8;
          var values = [
            for (var i = 0; i <= divisions; i++) probe(i / divisions),
          ];
          if (values.any((v) => !v.isFinite)) {
            side = -1;
            values = [
              for (var i = 0; i <= divisions; i++) probe(i / divisions),
            ];
          }
          if (values.any((v) => !v.isFinite)) return true;
          bool sharpPeak(double lo, double hi, double baseline) {
            for (var j = 0; j < 50; j++) {
              final left = lo + (hi - lo) / 3;
              final right = hi - (hi - lo) / 3;
              final a = probe(left);
              final b = probe(right);
              if (!a.isFinite ||
                  !b.isFinite ||
                  a > baseline * 1e6 ||
                  b > baseline * 1e6)
                return true;
              if (a < b) {
                lo = left;
              } else {
                hi = right;
              }
            }
            return false;
          }

          if (values[0] > values[1] && sharpPeak(0, 1 / divisions, values[0]))
            return true;
          if (values[divisions] > values[divisions - 1] &&
              sharpPeak((divisions - 1) / divisions, 1, values[divisions]))
            return true;
          for (var i = 1; i < divisions; i++) {
            if (values[i] <= values[i - 1] || values[i] <= values[i + 1])
              continue;
            if (values[i] > values[i - 1] * 100 &&
                values[i] > values[i + 1] * 100)
              return true;
            if (sharpPeak((i - 1) / divisions, (i + 1) / divisions, values[i]))
              return true;
          }
          return false;
        }

        void refineCell() {
          if (refinements > 0) {
            result.addAll(
              _sampleContourSegments(
                xMin: x,
                xMax: x + stepX,
                yMin: y,
                yMax: y + stepY,
                gridX: 4,
                gridY: 4,
                refinements: refinements - 1,
              ),
            );
          }
        }

        if (hasFalseZeroEdge && refinements > 0) {
          refineCell();
          continue;
        }

        bool hasMultipleMinima(double x1, double y1, double x2, double y2) {
          try {
            final values = [
              for (var i = 0; i <= 8; i++)
                evaluator2D(
                  x1 + (x2 - x1) * i / 8,
                  y1 + (y2 - y1) * i / 8,
                ).abs(),
            ];
            var minima = 0;
            for (var i = 1; i < 8; i++) {
              if (values[i] < values[i - 1] && values[i] < values[i + 1])
                minima++;
            }
            return minima > 1;
          } catch (_) {
            return false;
          }
        }

        if (refinements > 0 &&
            ((tangentBottom != null && hasMultipleMinima(x, y, x + stepX, y)) ||
                (tangentTop != null &&
                    hasMultipleMinima(x, y + stepY, x + stepX, y + stepY)) ||
                (tangentLeft != null &&
                    hasMultipleMinima(x, y, x, y + stepY)) ||
                (tangentRight != null &&
                    hasMultipleMinima(x + stepX, y, x + stepX, y + stepY)))) {
          refineCell();
          continue;
        }

        // A rejected edge may separate two otherwise valid crossings.
        if (((s00 < 0) != (s10 < 0) && bottomT == null) ||
            ((s01 < 0) != (s11 < 0) && topT == null) ||
            ((s00 < 0) != (s01 < 0) && leftT == null) ||
            ((s10 < 0) != (s11 < 0) && rightT == null) ||
            zeroEdges.any(zeroEdgeHasUndefinedInterior)) {
          refineCell();
          continue;
        }

        final cellSegments = <List<Map<String, double>>>[...zeroEdges];
        final tangentPoints = <Map<String, double>>[
          if (tangentBottom != null) {'x': x + tangentBottom * stepX, 'y': y},
          if (tangentTop != null) {'x': x + tangentTop * stepX, 'y': y + stepY},
          if (tangentLeft != null) {'x': x, 'y': y + tangentLeft * stepY},
          if (tangentRight != null)
            {'x': x + stepX, 'y': y + tangentRight * stepY},
        ];
        if (zeroEdges.isEmpty && crossingsHaveSameSign(v00, v10, v01, v11)) {
          if (v00 == 0 && !rejectedZeroEdgeCorners.contains((x, y))) {
            tangentPoints.add({'x': x, 'y': y});
          }
          if (v10 == 0 && !rejectedZeroEdgeCorners.contains((x + stepX, y))) {
            tangentPoints.add({'x': x + stepX, 'y': y});
          }
          if (v01 == 0 && !rejectedZeroEdgeCorners.contains((x, y + stepY))) {
            tangentPoints.add({'x': x, 'y': y + stepY});
          }
          if (v11 == 0 &&
              !rejectedZeroEdgeCorners.contains((x + stepX, y + stepY))) {
            tangentPoints.add({'x': x + stepX, 'y': y + stepY});
          }
        }
        // One bounded subdivision improves separation when nearby touching
        // roots occupy the same sampled valley on a coarse grid edge.
        if (refinements == 3 && tangentPoints.length >= 2) {
          refineCell();
          continue;
        }
        final zeroCorners = [v00, v10, v01, v11].where((v) => v == 0).length;
        if (refinements > 0 &&
            zeroEdges.isEmpty &&
            ((tangentPoints.length == 1 &&
                    (bottomT != null ||
                        topT != null ||
                        leftT != null ||
                        rightT != null)) ||
                (zeroCorners >= 2 &&
                    !crossingsHaveSameSign(v00, v10, v01, v11)))) {
          refineCell();
          continue;
        }
        if (tangentPoints.length > 2 && refinements > 0) {
          refineCell();
          continue;
        }
        if (tangentPoints.length == 1 && zeroEdges.length == 1) {
          // Estimate the branch at the zero edge from two nearby parallel
          // sections; otherwise retain the conservative refinement path.
          final edge = zeroEdges.single;
          final horizontal = edge[0]['y'] == edge[1]['y'];
          final direction = horizontal
              ? (edge[0]['y'] == y ? stepY : -stepY)
              : (edge[0]['x'] == x ? stepX : -stepX);
          double? section(double fraction) {
            try {
              final x1 =
                  edge[0]['x']! + (horizontal ? 0 : direction * fraction);
              final y1 =
                  edge[0]['y']! + (horizontal ? direction * fraction : 0);
              final x2 =
                  edge[1]['x']! + (horizontal ? 0 : direction * fraction);
              final y2 =
                  edge[1]['y']! + (horizontal ? direction * fraction : 0);
              return touching(
                x1,
                y1,
                x2,
                y2,
                evaluator2D(x1, y1),
                evaluator2D(x2, y2),
              );
            } catch (_) {
              return null;
            }
          }

          final a = section(0.001);
          final b = section(0.002);
          if (a != null && b != null) {
            final t = 2 * a - b;
            if (t >= 0 && t <= 1) {
              tangentPoints.add({
                'x': edge[0]['x']! + (edge[1]['x']! - edge[0]['x']!) * t,
                'y': edge[0]['y']! + (edge[1]['y']! - edge[0]['y']!) * t,
              });
            }
          }
          if (tangentPoints.length == 1 && refinements > 0) {
            refineCell();
            continue;
          }
        }
        if (tangentPoints.length == 2) {
          final a = tangentPoints[0];
          final b = tangentPoints[1];
          final scale = [
            v00.abs(),
            v10.abs(),
            v01.abs(),
            v11.abs(),
          ].reduce((a, b) => a > b ? a : b);
          var uncertain = false;
          for (final t in [0.25, 0.5, 0.75]) {
            try {
              final residual = evaluator2D(
                a['x']! + (b['x']! - a['x']!) * t,
                a['y']! + (b['y']! - a['y']!) * t,
              ).abs();
              if (!residual.isFinite ||
                  residual > scale * (zeroCorners >= 2 ? 1e-8 : 0.01)) {
                uncertain = true;
                break;
              }
            } catch (_) {
              uncertain = true;
              break;
            }
          }
          if (uncertain) {
            if (refinements > 0) {
              refineCell();
            } else {
              result.addAll(zeroEdges);
            }
            continue;
          }
        }
        if (tangentPoints.length == 2) {
          if (tangentHasSuspectedPole(tangentPoints)) {
            if (refinements > 0) {
              refineCell();
            } else {
              result.addAll(zeroEdges);
            }
            continue;
          }
          cellSegments.add(tangentPoints);
        }

        // Count crossings and connect pairs
        final crossings = [
          if (bottomT != null) 'bottom',
          if (topT != null) 'top',
          if (leftT != null) 'left',
          if (rightT != null) 'right',
        ];

        // With 2 crossings, connect them as a segment
        // With 4 crossings, use the asymptotic decider to choose adjacent
        // edge pairs, unless the bilinear saddle lies on the contour.
        if (crossings.length == 2) {
          final p1 = _crossingPoint(
            crossings[0],
            bottomT,
            topT,
            leftT,
            rightT,
            x,
            y,
            stepX,
            stepY,
          );
          final p2 = _crossingPoint(
            crossings[1],
            bottomT,
            topT,
            leftT,
            rightT,
            x,
            y,
            stepX,
            stepY,
          );
          if (p1 != null && p2 != null) {
            cellSegments.add([p1, p2]);
          }
        } else if (crossings.length == 4) {
          final pBottom = _crossingPoint(
            'bottom',
            bottomT,
            topT,
            leftT,
            rightT,
            x,
            y,
            stepX,
            stepY,
          );
          final pTop = _crossingPoint(
            'top',
            bottomT,
            topT,
            leftT,
            rightT,
            x,
            y,
            stepX,
            stepY,
          );
          final pLeft = _crossingPoint(
            'left',
            bottomT,
            topT,
            leftT,
            rightT,
            x,
            y,
            stepX,
            stepY,
          );
          final pRight = _crossingPoint(
            'right',
            bottomT,
            topT,
            leftT,
            rightT,
            x,
            y,
            stepX,
            stepY,
          );
          final scale = [
            v00.abs(),
            v10.abs(),
            v01.abs(),
            v11.abs(),
          ].reduce((a, b) => a > b ? a : b);
          final determinant =
              (v00 / scale) * (v11 / scale) - (v10 / scale) * (v01 / scale);
          void addPairedCrossings() {
            if (determinant >= 0) {
              if (pBottom != null && pRight != null)
                cellSegments.add([pBottom, pRight]);
              if (pTop != null && pLeft != null)
                cellSegments.add([pTop, pLeft]);
            } else {
              if (pBottom != null && pLeft != null)
                cellSegments.add([pBottom, pLeft]);
              if (pTop != null && pRight != null)
                cellSegments.add([pTop, pRight]);
            }
          }

          void refineOrPair() {
            if (refinements > 0) {
              refineCell();
            } else {
              addPairedCrossings();
              if (!cellSegments.any(zeroEdgeHasUndefinedInterior)) {
                result.addAll(cellSegments);
              }
            }
          }

          if (pBottom != null &&
              pTop != null &&
              pLeft != null &&
              pRight != null) {
            final ax = pTop['x']! - pBottom['x']!;
            final ay = pTop['y']! - pBottom['y']!;
            final bx = pRight['x']! - pLeft['x']!;
            final by = pRight['y']! - pLeft['y']!;
            final denominator = ax * by - ay * bx;
            if (denominator == 0 || !denominator.isFinite) {
              refineOrPair();
              continue;
            }
            final t =
                ((pLeft['x']! - pBottom['x']!) * by -
                    (pLeft['y']! - pBottom['y']!) * bx) /
                denominator;
            final saddle = {
              'x': pBottom['x']! + t * ax,
              'y': pBottom['y']! + t * ay,
            };
            // The intersection of edge chords is only an approximation for
            // curved branches. Estimate each coordinate from roots on two
            // nearby parallel sections, progressively shrinking their spacing.
            if (determinant.abs() > 1e-14) {
              double? section(bool vertical, double coordinate) {
                final x1 = vertical ? coordinate : x;
                final y1 = vertical ? y : coordinate;
                final x2 = vertical ? coordinate : x + stepX;
                final y2 = vertical ? y + stepY : coordinate;
                try {
                  final a = evaluator2D(x1, y1);
                  final b = evaluator2D(x2, y2);
                  if (!a.isFinite || !b.isFinite || (a < 0) == (b < 0)) {
                    return null;
                  }
                  final root = crossing(x1, y1, x2, y2, a, b);
                  if (root == null) return null;
                  return vertical ? y1 + root * stepY : x1 + root * stepX;
                } catch (_) {
                  return null;
                }
              }

              for (final fraction in [0.01, 0.0001, 0.000001]) {
                final dx = stepX * fraction;
                final dy = stepY * fraction;
                if (saddle['x']! - dx <= x ||
                    saddle['x']! + dx >= x + stepX ||
                    saddle['y']! - dy <= y ||
                    saddle['y']! + dy >= y + stepY) {
                  break;
                }
                final below = section(false, saddle['y']! - dy);
                final above = section(false, saddle['y']! + dy);
                final left = section(true, saddle['x']! - dx);
                final right = section(true, saddle['x']! + dx);
                if (below == null ||
                    above == null ||
                    left == null ||
                    right == null)
                  break;
                saddle['x'] = (below + above) / 2;
                saddle['y'] = (left + right) / 2;
              }
            }
            double saddleValue;
            try {
              saddleValue = evaluator2D(saddle['x']!, saddle['y']!);
            } catch (_) {
              saddleValue = double.nan;
            }
            // Corner values alone cannot establish a crossing for a nonlinear
            // function; subdivide when the candidate is not on the contour.
            if (!saddleValue.isFinite || saddleValue != 0) {
              if (determinant.abs() <= 1e-14) {
                refineOrPair();
                continue;
              }
              addPairedCrossings();
              if (!cellSegments.any(zeroEdgeHasUndefinedInterior)) {
                result.addAll(cellSegments);
              }
              continue;
            }
            // A point on one branch is not necessarily the intersection.
            // Check the alternating signs in a small neighborhood.
            var alternating = false;
            for (final fraction in [1e-8, 1e-6, 1e-4]) {
              final dx = [
                stepX * fraction,
                (saddle['x']! - x) / 2,
                (x + stepX - saddle['x']!) / 2,
              ].reduce((a, b) => a < b ? a : b);
              final dy = [
                stepY * fraction,
                (saddle['y']! - y) / 2,
                (y + stepY - saddle['y']!) / 2,
              ].reduce((a, b) => a < b ? a : b);
              try {
                final a = evaluator2D(saddle['x']! - dx, saddle['y']! - dy);
                final b = evaluator2D(saddle['x']! + dx, saddle['y']! - dy);
                final c = evaluator2D(saddle['x']! - dx, saddle['y']! + dy);
                final d = evaluator2D(saddle['x']! + dx, saddle['y']! + dy);
                if ([a, b, c, d].any((v) => !v.isFinite)) break;
                if ([a, b, c, d].any((v) => v == 0)) continue;
                alternating =
                    (a < 0) == (d < 0) &&
                    (b < 0) == (c < 0) &&
                    (a < 0) != (b < 0);
                break;
              } catch (_) {
                break;
              }
            }
            if (!alternating) {
              if (determinant.abs() <= 1e-14) {
                refineOrPair();
              } else {
                addPairedCrossings();
                if (!cellSegments.any(zeroEdgeHasUndefinedInterior)) {
                  result.addAll(cellSegments);
                }
              }
              continue;
            }
            for (final point in [pBottom, pTop, pLeft, pRight]) {
              cellSegments.add([point, saddle]);
            }
          } else {
            addPairedCrossings();
          }
        }
        if (cellSegments.any(zeroEdgeHasUndefinedInterior)) {
          refineCell();
        } else {
          result.addAll(cellSegments);
        }
      }
    }

    return result;
  }

  /// Compute the (x,y) coordinates of a crossing on the specified edge.
  Map<String, double>? _crossingPoint(
    String edge,
    double? bT,
    double? tT,
    double? lT,
    double? rT,
    double x,
    double y,
    double stepX,
    double stepY,
  ) {
    switch (edge) {
      case 'bottom':
        return bT == null ? null : {'x': x + bT * stepX, 'y': y};
      case 'top':
        return tT == null ? null : {'x': x + tT * stepX, 'y': y + stepY};
      case 'left':
        return lT == null ? null : {'x': x, 'y': y + lT * stepY};
      case 'right':
        return rT == null ? null : {'x': x + stepX, 'y': y + rT * stepY};
    }
    return null;
  }

  /// Check whether [expr] contains `=` as an equation (not y= / f(x)= prefix).
  static bool _isEquation(String expr) {
    if (!expr.contains('=')) return false;
    // If it starts with y= or f(x)=, it's explicit (already stripped prefix).
    // We already stripped those, so any remaining '=' is a true equation.
    // But x=1 is an equation, while things like "==" are malformed.
    return expr.contains('=');
  }

  /// Create a multi-variable evaluator for implicit equations f(x,y).
  static double Function(double, double) _createImplicitEvaluator(
    String normalized,
    Map<String, double> parameterValues,
  ) {
    final params = _extractParameters(normalized, implicit: true);
    final values = {for (final name in params) name: 1.0, ...parameterValues};
    final variableNames = [
      'x',
      'y',
      ...values.keys.where((k) => k != 'x' && k != 'y'),
    ];
    final evaluate = MathExpressionParser.parse(
      normalized,
      variables: variableNames,
    );
    return (double x, double y) {
      final args = Map<String, num>.from(values);
      args['x'] = x;
      args['y'] = y;
      return evaluate(args);
    };
  }

  // ==================================================================
  // Internal helpers
  // ==================================================================

  /// Strip common prefixes like "y = ", "f(x) = " from the expression.
  static String _stripPrefix(String expr) {
    // Try f(x) = (with optional spaces)
    final fxMatch = RegExp(
      r'^f\s*(?:\\left\s*)?\(\s*x\s*(?:\\right\s*)?\)\s*=\s*',
    ).firstMatch(expr);
    if (fxMatch != null) {
      return expr.substring(fxMatch.end);
    }
    // Try y = (with optional spaces)
    final yMatch = RegExp(r'^y\s*=\s*').firstMatch(expr);
    if (yMatch != null) {
      final rhs = expr.substring(yMatch.end);
      try {
        final normalized = _normalizeExpression(rhs);
        if (RegExp(r'\by\b').hasMatch(normalized)) return expr;
      } on FormatException {
        // Parsing below reports invalid input through the normal error path.
      }
      return rhs;
    }
    return expr;
  }

  /// Normalize an expression for numeric parsing.
  ///
  /// Handles:
  /// - LaTeX braces `{}` → `()` so that `2^{x-1}` becomes `2^(x-1)`
  /// - Whitespace removal
  /// - Insertion of explicit `*` for implicit multiplication (e.g., `2x` → `2*x`)
  static String _normalizeExpression(String expr) {
    var result = expr.trim();
    if (result.isEmpty) return '';

    // Step 1: Convert LaTeX commands (including \frac{}{} with braces)
    result = _convertLatex(result);

    // Step 2: Remaining braces → parentheses (for ^{...} superscript, etc.)
    result = result.replaceAll('{', '(').replaceAll('}', ')');

    // Preserve token boundaries: "\\alpha x" is alpha*x, not alphax.
    result = _addImplicitMultiplication(result);
    // Reject unsupported punctuation rather than silently dropping it.
    if (RegExp(r'[^a-zA-Z0-9_+\-*/%^(),.=]').hasMatch(result)) {
      throw const FormatException('此结构可编辑，但绘图引擎暂不支持');
    }

    return result;
  }

  /// Replace `\frac{numerator}{denominator}` with `((num)/(denom))`.
  /// Supports nested braces via brace-level counting.
  static String _replaceFrac(String expr) {
    final fracRegex = RegExp(r'\\frac\b');
    var result = expr;
    int pos;

    while ((pos = result.indexOf(fracRegex, 0)) != -1) {
      // Found \frac at pos
      final start1 = pos + 5; // skip past \frac
      var idx = start1;
      // Skip whitespace before first {
      while (idx < result.length && result[idx] == ' ') {
        idx++;
      }
      if (idx >= result.length || result[idx] != '{') break; // malformed

      // Extract first {…} content with brace counting
      int depth = 1;
      idx++; // move past opening {
      final contentStart1 = idx;
      while (idx < result.length && depth > 0) {
        if (result[idx] == '{') {
          depth++;
        } else if (result[idx] == '}') {
          depth--;
        }
        if (depth > 0) idx++;
      }
      if (depth != 0) break; // unmatched brace
      final content1 = result.substring(contentStart1, idx);
      // Move past first }
      idx++;
      // Skip whitespace before second {
      while (idx < result.length && result[idx] == ' ') {
        idx++;
      }
      if (idx >= result.length || result[idx] != '{') break;

      // Extract second {…}
      depth = 1;
      idx++; // move past opening {
      final contentStart2 = idx;
      while (idx < result.length && depth > 0) {
        if (result[idx] == '{') {
          depth++;
        } else if (result[idx] == '}') {
          depth--;
        }
        if (depth > 0) idx++;
      }
      if (depth != 0) break;
      final content2 = result.substring(contentStart2, idx);
      final braceEnd2 = idx;

      // Keep the whole fraction as one atom for following powers/postfixes.
      final before = result.substring(0, pos);
      final after = result.substring(braceEnd2 + 1);
      result = '$before(($content1)/($content2))$after';
    }

    return result;
  }

  /// Read a balanced LaTeX group, including nested templates.
  static (String, int)? _latexGroup(
    String source,
    int start,
    String open,
    String close,
  ) {
    while (start < source.length && source[start] == ' ') {
      start++;
    }
    if (start >= source.length || source[start] != open) return null;
    final contentStart = ++start;
    var depth = 1;
    while (start < source.length) {
      if (source[start] == open) depth++;
      if (source[start] == close && --depth == 0) {
        return (source.substring(contentStart, start), start + 1);
      }
      start++;
    }
    return null;
  }

  static String _replaceIndexedLatex(String source) {
    var result = source;
    final commands = RegExp(r'\\sqrt\s*\[|\\log\s*_');
    var from = 0;
    while (true) {
      final match = commands.firstMatch(result.substring(from));
      if (match == null) break;
      final start = from + match.start;
      var indexStart = from + match.end;
      final isRoot = match.group(0)!.contains('sqrt');
      (String, int)? index;
      if (isRoot) {
        index = _latexGroup(result, indexStart - 1, '[', ']');
      } else {
        index = _latexGroup(result, indexStart, '{', '}');
        if (index == null && indexStart < result.length) {
          index = (result[indexStart], indexStart + 1);
        }
      }
      if (index == null) throw const FormatException('根式或对数的底未完成');
      var argumentStart = index.$2;
      while (argumentStart < result.length && result[argumentStart] == ' ') {
        argumentStart++;
      }
      if (result.startsWith(r'\left', argumentStart)) argumentStart += 5;
      final group =
          _latexGroup(
            result,
            argumentStart,
            isRoot ? '{' : '(',
            isRoot ? '}' : ')',
          ) ??
          _latexGroup(result, argumentStart, '{', '}');
      if (group == null) throw const FormatException('请为根式或对数填写括号内的内容');
      var argumentSource = group.$1;
      if (!isRoot && argumentSource.endsWith(r'\right')) {
        argumentSource = argumentSource.substring(0, argumentSource.length - 6);
      }
      final argument = _convertLatex(argumentSource);
      final base = _convertLatex(index.$1);
      final replacement = isRoot
          ? 'nrt(($base),($argument))'
          : '(ln($argument)/ln($base))';
      var groupEnd = group.$2;
      if (!isRoot && result.startsWith(r'\right)', groupEnd)) {
        groupEnd += r'\right)'.length;
      }
      result = result.replaceRange(start, groupEnd, replacement);
      from = start + replacement.length;
    }
    return result;
  }

  /// Convert LaTeX command sequences to plain math notation.
  ///
  /// Handles `\frac`, `\times`, `\cdot`, `\div`, `\sin`, `\cos`, `\tan`,
  /// `\ln`, `\log`, `\sqrt`, `\left`/`\right`, `\pi`, Greek letters,
  /// spacing commands. Unknown commands are rejected by the graph evaluator.
  ///
  /// This runs BEFORE `{}` → `()` conversion, so braces are still intact.
  /// Convert editor LaTeX to the numeric parser's notation.
  static String convertLatexForParser(String expr) => _convertLatex(expr);

  static String _convertLatex(String expr) {
    if (RegExp(r'\\(?:pm|mp)\b|!!|!=').hasMatch(expr)) {
      throw const FormatException('此符号未定义单条曲线，请分别输入完整表达式');
    }
    var result = expr.replaceAllMapped(
      RegExp(r'\\mathrm\{([a-zA-Z](?:\w|\\_)*)\}_\{(\w+)\}'),
      (match) => ' ${match[1]!.replaceAll(r'\_', '_')}_${match[2]} ',
    );
    result = result.replaceAllMapped(
      RegExp(r'(\\[a-zA-Z]+|[a-zA-Z])_\{(\w+)\}'),
      (match) {
        final name = match[1]!;
        if (name.startsWith(r'\') &&
            !mathGreekNames.contains(name.substring(1))) {
          return match[0]!;
        }
        return ' ${name.replaceAll(r'\', '')}_${match[2]} ';
      },
    );
    result = _replaceIndexedLatex(result);
    // Named identifier subscripts and logarithm bases have been consumed.
    // Flattening a remaining structural index into ordinary tokens would turn an
    // unsupported indexed expression into multiplication by a fake parameter.
    if (RegExp(r'(?<!\\)_\s*(?:\{|\\)').hasMatch(result)) {
      throw const FormatException('此下标结构可编辑，但绘图仅支持参数名称下标');
    }
    // Rendered imports reserve legacy names in an exact roman namespace. Only
    // an identifier is accepted: arbitrary roman text and calculus stay invalid.
    // Check structural scripts first, before unwrapping names ending with '_'.
    result = result.replaceAllMapped(
      RegExp(r'\\mathrm\{([a-zA-Z](?:\w|\\_)*)\}'),
      (match) => ' ${match[1]!.replaceAll(r'\_', '_')} ',
    );
    result = result.replaceAllMapped(
      RegExp(r'\\operatorname\{([a-zA-Z]+)\}'),
      (m) => _knownFunctions.contains(m[1]) ? m[1]! : m[0]!,
    );
    result = result.replaceAll(RegExp(r'\\(?:dfrac|tfrac)\b'), r'\frac');
    // Paired bars are an absolute-value structure, rather than variable names.
    while (result.contains(r'\left|')) {
      final end = result.indexOf(r'\right|');
      if (end < 0) throw const FormatException('绝对值未完成');
      final start = result.lastIndexOf(r'\left|', end);
      if (start < 0) throw const FormatException('绝对值未完成');
      final content = result.substring(start + 6, end);
      result = result.replaceRange(start, end + 7, 'abs($content)');
    }
    result = result.replaceAll(
      RegExp(r'\\(?:left|right)\s*(?=\\(?:[lr]floor|[lr]ceil)(?![a-zA-Z]))'),
      '',
    );
    for (final fence in {
      r'\lfloor': (r'\rfloor', 'floor'),
      r'\lceil': (r'\rceil', 'ceil'),
    }.entries) {
      while (result.contains(fence.key)) {
        final end = result.indexOf(fence.value.$1);
        if (end < 0) throw const FormatException('取整括号未完成');
        final start = result.lastIndexOf(fence.key, end);
        if (start < 0) throw const FormatException('取整括号未完成');
        final content = result.substring(start + fence.key.length, end);
        result = result.replaceRange(
          start,
          end + fence.value.$1.length,
          '${fence.value.$2}($content)',
        );
      }
    }

    // 1) \frac{numerator}{denominator} → (numerator)/(denominator)
    //    Uses a simple brace-matcher: find first {…} and second {…}
    //    after \frac. Works with nested braces.
    result = _replaceFrac(result);

    // 2) Remove \left and \right (they add no meaning to numeric parsing)
    result = result.replaceAll(RegExp(r'\\left\b'), '');
    result = result.replaceAll(RegExp(r'\\right\b'), '');

    // 3) Operators
    result = result.replaceAll(RegExp(r'\\times(?![a-zA-Z])'), '*');
    result = result.replaceAll(RegExp(r'\\cdot(?![a-zA-Z])'), '*');
    result = result.replaceAll(RegExp(r'\\div(?![a-zA-Z])'), '/');
    result = result.replaceAll(RegExp(r'\\(?:bmod|mod)(?![a-zA-Z])'), '%');

    // 4) Functions supported by the numeric parser
    result = result.replaceAll(RegExp(r'\\sin\b'), 'sin');
    result = result.replaceAll(RegExp(r'\\cos\b'), 'cos');
    result = result.replaceAll(RegExp(r'\\tan\b'), 'tan');
    result = result.replaceAll(RegExp(r'\\cot\b'), 'cot');
    result = result.replaceAll(RegExp(r'\\sec\b'), 'sec');
    result = result.replaceAll(RegExp(r'\\csc\b'), 'csc');
    result = result.replaceAll(RegExp(r'\\sqrt\b'), 'sqrt');
    result = result.replaceAll(RegExp(r'\\ln\b'), 'ln');
    result = result.replaceAll(RegExp(r'\\log\b'), 'log');
    result = result.replaceAll(RegExp(r'\\exp\b'), 'exp');
    result = result.replaceAll(RegExp(r'\\sinh\b'), 'sinh');
    result = result.replaceAll(RegExp(r'\\cosh\b'), 'cosh');
    result = result.replaceAll(RegExp(r'\\tanh\b'), 'tanh');
    result = result.replaceAll(RegExp(r'\\arcsin\b'), 'asin');
    result = result.replaceAll(RegExp(r'\\arccos\b'), 'acos');
    result = result.replaceAll(RegExp(r'\\arctan\b'), 'atan');
    result = result.replaceAll(RegExp(r'\\abs\b'), 'abs');
    result = result.replaceAll(RegExp(r'\\coth\b'), 'coth');
    result = result.replaceAll(RegExp(r'\\sech\b'), 'sech');
    result = result.replaceAll(RegExp(r'\\csch\b'), 'csch');

    // 5) Constants
    result = result.replaceAll(RegExp(r'\\pi(?![a-zA-Z])'), ' pi ');
    result = result.replaceAll(RegExp(r'\\infty\b'), '1e999');

    // 6) Greek commands → named parameters.
    for (final name in mathGreekNames) {
      result = result.replaceAll(RegExp('\\\\$name(?![a-zA-Z])'), ' $name ');
    }

    // 7) Spacing commands → space (will be stripped later, but
    //    keeps token separation for the implicit multiplication pass)
    result = result.replaceAll(RegExp(r'\\;\b'), ' ');
    result = result.replaceAll(RegExp(r'\\:\b'), ' ');
    result = result.replaceAll(RegExp(r'\\,\b'), ' ');
    result = result.replaceAll(RegExp(r'\\!\b'), '');
    result = result.replaceAll(RegExp(r'\\quad\b'), ' ');
    result = result.replaceAll(RegExp(r'\\qquad\b'), '  ');
    result = result.replaceAll(RegExp(r'\\space\b'), ' ');

    // 8) Superscript/subscript notation: x^{n} already handled by
    //    brace conversion above. Handle x_n notation: x_n → x_n
    //    (subscript is kept as-is for parameter naming)

    // Layout-only commands must not silently turn into parameter curves.
    result = result.replaceAll(RegExp(r'\\[,;:! ]'), '');
    // Percent is postfix division by 100; bare % remains binary remainder.
    result = _replacePostfix(result);
    if (result.contains(r'\') || result.contains('|')) {
      throw const FormatException('此 LaTeX 结构可编辑，但绘图引擎暂不支持');
    }

    return result;
  }

  /// Convert postfix operations on a whole atom, including grouped powers.
  static String _replacePostfix(String source) {
    var result = source;
    final postfix = RegExp(r'!|\\%');
    while (true) {
      final match = postfix.firstMatch(result);
      if (match == null) return result;
      final end = match.start;
      final start = _operandStart(result, end);
      if (start == null) throw const FormatException('后缀运算缺少完整的表达式');
      final operand = result.substring(start, end);
      result = result.replaceRange(
        start,
        match.end,
        match[0] == '!' ? 'fact($operand)' : '(($operand)/100)',
      );
    }
  }

  static int? _operandStart(String source, int end) {
    while (end > 0 && source[end - 1] == ' ') end--;
    if (end == 0) return null;
    var start = end;
    final last = source[end - 1];
    if (last == ')' || last == '}') {
      final open = last == ')' ? '(' : '{';
      var depth = 1;
      start = end - 1;
      while (start > 0 && depth > 0) {
        start--;
        if (source[start] == last) depth++;
        if (source[start] == open) depth--;
      }
      if (depth != 0) return null;
      final function = RegExp(r'[a-zA-Z]+$')
          .firstMatch(source.substring(0, start));
      if (function != null && _knownFunctions.contains(function[0]))
        start = function.start;
    } else {
      final atom = RegExp(
        r'(?:[a-zA-Z]\w*|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)$',
      ).firstMatch(source.substring(0, end));
      if (atom == null) return null;
      start = atom.start;
    }
    if (start > 0 && source[start - 1] == '^') {
      return _operandStart(source, start - 1);
    }
    return start;
  }

  /// Insert explicit `*` operators for implicit multiplication.
  ///
  /// Cases:
  /// - `2x` → `2*x` (number followed by letter)
  /// - `2(x+1)` → `2*(x+1)` (number followed by paren)
  /// - `)x` → `)*x` (closing paren followed by letter)
  /// - `)(` → `)*(` (closing paren followed by opening paren)
  /// - `x(y+1)` → `x*(y+1)` (single variable letter followed by paren)
  ///
  /// Known function names (sin, cos, sqrt, etc.) are NOT modified.
  static String _addImplicitMultiplication(String expr) {
    final tokens =
        RegExp(r'(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|[a-zA-Z]\w*|[^\s]')
            .allMatches(expr)
            .expand((match) {
              final token = match[0]!;
              // In 2D expressions, adjacent coordinate names are products:
              // `xy` means x*y, while names such as theta and a_1 stay intact.
              if (RegExp(r'^[xy]{2,}$').hasMatch(token)) {
                return token.split('');
              }
              return [token];
            })
            .toList();
    final result = StringBuffer();
    bool identifier(String token) => RegExp(r'^[a-zA-Z]\w*$').hasMatch(token);
    bool number(String token) => double.tryParse(token) != null;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (i > 0) {
        final previous = tokens[i - 1];
        if (_knownFunctions.contains(previous) && token != '(') {
          throw const FormatException('函数参数请放在括号内');
        }
        final variableBeforeParen =
            identifier(previous) &&
            !_knownFunctions.contains(previous) &&
            (previous.length == 1 ||
                previous.contains('_') ||
                mathGreekNames.contains(previous) ||
                _builtinConstants.contains(previous));
        if ((number(previous) && (identifier(token) || token == '(')) ||
            (previous == ')' &&
                (identifier(token) || number(token) || token == '(')) ||
            (identifier(previous) && identifier(token)) ||
            (identifier(previous) && number(token)) ||
            (variableBeforeParen && token == '('))
          result.write('*');
      }
      result.write(token);
    }
    return result.toString();
  }

  /// Known function names that should not trigger implicit multiplication
  /// insertion when followed by '('.
  static final Set<String> _knownFunctions = {
    ...mathUnaryInputs.map((input) => input.name),
    ...mathBinaryInputs.map((input) => input.name),
  };
  static final Set<String> _builtinConstants = {
    ...mathConstantInputs.map((input) => input.name),
    'E',
    'PI',
    'LN2',
    'LN10',
    'LOG2E',
    'LOG10E',
    'SQRT1_2',
    'SQRT2',
  };

  /// Create an evaluator [double Function(double)] from a normalized expression.
  ///
  /// Parses the expression into a callable function.
  /// [parameterValues] provides values for parameters (e.g., a, b, c).
  /// The variable `x` is the independent variable.
  static double Function(double) _createEvaluator(
    String normalized,
    Map<String, double> parameterValues,
  ) {
    // Detect all variable names in the expression (excluding known functions
    // and built-in constants like e and pi).
    // This ensures we handle parameters like a, b, c even if no values provided.
    final variableNames = <String>['x'];
    // Built-in constants that should not be treated as variables.
    // Use a simple regex to find potential variable names
    final varMatches = RegExp(r'\b([a-zA-Z]\w*)\b').allMatches(normalized);
    for (final m in varMatches) {
      final name = m[1]!;
      if (name != 'x' &&
          !_knownFunctions.contains(name) &&
          !_builtinConstants.contains(name)) {
        if (!variableNames.contains(name)) {
          variableNames.add(name);
        }
      }
    }

    // If there are additional variables (parameters), use multi-variable function.
    // Otherwise use the simpler single-variable function.
    // Merge provided parameter values with defaults for any unset variables.
    final mergedParams = Map<String, double>.from(parameterValues);
    for (final name in variableNames) {
      if (name != 'x' && !mergedParams.containsKey(name)) {
        mergedParams[name] = 1.0;
      }
    }
    final evaluate = MathExpressionParser.parse(
      normalized,
      variables: variableNames,
    );
    return (double x) {
      final args = Map<String, num>.from(mergedParams);
      args['x'] = x;
      return evaluate(args);
    };
  }

  // ==================================================================
  // LaTeX display
  // ==================================================================

  /// Convert a user expression to a LaTeX display string.
  static String _toLatexDisplay(String input) {
    var expr = input.trim();
    if (expr.isEmpty) return '';

    // Check if it already has a prefix like y = or f(x) =
    if (RegExp(r'^[a-zA-Z]+\s*\(\s*[a-zA-Z]*\s*\)\s*=').hasMatch(expr) ||
        RegExp(r'^[a-zA-Z]\s*=').hasMatch(expr)) {
      // Normalize spacing around =
      expr = expr.replaceAllMapped(
        RegExp(r'^([a-zA-Z]+\s*\(\s*[a-zA-Z]*\s*\))\s*=\s*(.*)'),
        (m) => '${m[1]!.trim()} = ${m[2]!.trim()}',
      );
      expr = expr.replaceAllMapped(
        RegExp(r'^([a-zA-Z])\s*=\s*(.*)'),
        (m) => '${m[1]!.trim()} = ${m[2]!.trim()}',
      );
      return expr;
    }

    // Preserve implicit equations such as x^2 + y^2 = 1.
    if (expr.contains('=')) {
      return expr.replaceAllMapped(RegExp(r'\s*=\s*'), (_) => ' = ');
    }

    // No prefix — add y =
    return 'y = $expr';
  }

  // ==================================================================
  // Parameter extraction
  // ==================================================================

  /// Extract parameter names from a user expression body.
  ///
  /// [expr] should already have the `y = ` or `f(x) = ` prefix stripped.
  /// Returns identifiers other than coordinate variables, constants and functions.
  static Set<String> _extractParameters(String expr, {bool implicit = false}) {
    if (expr.isEmpty) return {};

    final params = <String>{};
    final matches = RegExp(r'\b([a-zA-Z]\w*)\b').allMatches(expr);
    for (final m in matches) {
      final name = m[1]!;
      // Exclude x (the variable), e (Euler's number),
      // and known function names
      if (name == 'x' || (implicit && name == 'y')) continue;
      if (_knownFunctions.contains(name) || _builtinConstants.contains(name))
        continue;
      params.add(name);
    }
    return params;
  }

  // ==================================================================
  // Backward compatibility: JS expression conversion
  // (used by the deprecated WebView-based canvas)
  // ==================================================================

  /// Convert a normalized expression to a JavaScript-evaluable form.
  ///
  /// This is kept for backward compatibility with the old WebView-based
  /// [math_canvas_webview] widget. New code should use [evaluator] directly.
  static String toJsExpression(String input) {
    var expr = input.trim();
    if (expr.isEmpty) return '';

    // Strip prefix
    expr = _stripPrefix(expr);
    if (expr.isEmpty) return '';

    expr = _normalizeExpression(expr);
    return MathExpressionParser.toJavaScript(
      expr,
      variables: {'x', ..._extractParameters(expr)},
    );
  }

  /// Generate a JavaScript function body from a JS expression.
  ///
  /// Kept for backward compatibility with the deprecated WebView canvas.
  static String generateFunctionBody(String jsExpression) {
    if (jsExpression.isEmpty) return 'return 0;';
    return 'return $jsExpression;';
  }
}
